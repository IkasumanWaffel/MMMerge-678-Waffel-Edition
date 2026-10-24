--[[
	MMMWE_Blasters.lua — blaster specs, power cells and upgrades (25.10.26)

	The gun is the source of firepower; the gunslinger's Blaster skill brings accuracy
	(the attack bonus of the mastery) and critical hits (MMMWE_Main.lua, CalcBlasterDamage).

	Specs (raised one tier at a time, at most 4 tiers each):
	  Emitter    (warm gems)   +60% damage per tier
	  Capacitor  (blue gems)   -5 recovery per tier
	  Disruptor  (purple gems) eradication strength per tier
	  Power cell (green gems)  +50% cell capacity per tier
	  Diamond: any spec (no key Emitter, Shift Capacitor, Ctrl Disruptor, Ctrl+Shift Power cell)
	Tier 4 specials: Overcharge (Emitter), Rapid cycling (Capacitor), Chain disruption
	(Disruptor), Self-recharge (Power cell).
	A Fine install (chance by Repair skill and Luck) counts half a tier more.
	Blaster mastery limits the upgrades of a gun: 2 / 4 / 6 / 8.

	Work: before each gem the work bar is filled to 100 with ore; the ore needed rises with
	the number of upgrades on the gun. Two pieces of the same ore smelt into one of the next
	grade (use ore on a character who isn't holding a blaster).
	Blaster Toolkit (962): moves the whole board between guns; with Ctrl it removes the
	last upgrade (the gem is lost).

	Item fields of a blaster:
	  Charges    = OFFSET + stack + STACK_SIZE * (work / 5)
	               stack: the installed upgrades in order, base 9, oldest first; each entry
	               1 + (spec - 1) + 4 * fine
	  MaxCharges = power cell, 0..200 (0.5% steps)
	Old blasters (Charges = tier * 1000 + progress) become Emitter T + Disruptor T.
	The toolkit keeps a board in its Charges in the same format.
--]]

local MF = Merge.Functions
local u1, u2, u4, i4 = mem.u1, mem.u2, mem.u4, mem.i4
local floor, min, max, random = math.floor, math.min, math.max, math.random

local B = {
	EmitterPerTier   = 0.6,     -- x base damage per Emitter tier
	CapacitorPerTier = 5,       -- recovery per Capacitor tier
	DisruptorPerTier = 0.12,    -- eradication strength per Disruptor tier (MMMWE_Main.lua)
	CellPerTier      = 0.5,     -- x cell capacity per Power cell tier
	FineShare        = 0.5,     -- a Fine install counts this much of a tier more
	FineBase         = 5,       -- % chance of a Fine install
	FinePerRepair    = 1,       -- % per point of Repair skill
	FinePerLuck      = 2,       -- % per point of Luck bonus
	CritChancePerSkill = 1,     -- % crit chance per point of Blaster skill
	CritDamagePerSkill = 4,     -- % crit damage per point of Blaster skill
	Shots            = {1000, 600},   -- shots of a full cell: pistol, rifle
	CellFull         = 200,     -- MaxCharges of a full cell (0.5% steps)
	LowWarn          = 20,      -- warn below 10%
	OverchargeBody   = 0.5,     -- Emitter 4: share of Body resistance counted on a crit
	RapidChance      = 0.15,    -- Capacitor 4: share of shots without recovery
	ChainRadius      = 300,     -- Disruptor 4
	ChainShare       = 0.5,
	SelfRechargePerHour = 2,    -- Power cell 4: +1% (2 steps) per game hour
	Limit            = {2, 4, 6, 8},          -- upgrades by Blaster mastery
	GemValue         = {250, 750, 1250, 2000},-- gem value needed per tier
	WorkPerPiece     = {10, 15, 20},          -- ore of the lowest grade / one higher / more
	BashMin = 1, BashMax = 3,   -- an empty blaster bashes for 1d3
	BashRange        = 400,
	EmptyRecovery    = 100,
	FoundUpgrade1    = 0.20,    -- a newly found blaster: chance of a random upgrade
	FoundUpgrade2    = 0.05,    -- ... and of a second one
}
MF.BlasterSpecs = B

local SPECS = {"Emitter", "Capacitor", "Disruptor", "Power cell"}
local SPEC_SHORT = {"Emitter", "Capacitor", "Disruptor", "Cell"}
B.SpecNames = SPECS

local BLASTERS = {[866] = 1, [867] = 2, [1666] = 1, [1667] = 2}   -- 1 pistol, 2 rifle
local TOOLKIT = 962
MF.IsBlasterItem = function(n) return BLASTERS[n] ~= nil end

-- ore item -> grade (1 Iron .. 6 Stalt); same grade in both item sets
local ORE = {
	[686] = 1, [687] = 2, [688] = 3, [689] = 4, [690] = 5, [691] = 6,
	[1488] = 1, [1489] = 2, [1490] = 3, [1491] = 4, [1492] = 5, [1493] = 6,
}
local ORE_NAMES = {"Iron", "Siertal", "Phylt", "Kergar", "Erudine", "Stalt"}
local ORE_RM = {1, 1, 2, 2, 3, 4}       -- Repair mastery and skill to work an ore
local ORE_RS = {1, 3, 5, 7, 10, 15}
-- lowest ore grade by the number of upgrades already installed (0..7)
local ORE_MIN = {[0] = 1, 1, 3, 3, 4, 4, 5, 5}

-- gem item -> spec (1 Emitter, 2 Capacitor, 3 Disruptor, 4 Power cell, 0 Diamond)
local GEM = {
	-- MM8
	[177] = 2, [178] = 2, [179] = 1, [180] = 1, [181] = 3, [182] = 1, [183] = 4, [184] = 2, [185] = 1, [186] = 0,
	-- MM7
	[988] = 2, [989] = 1, [990] = 4, [991] = 2, [992] = 4, [993] = 1, [994] = 0, [995] = 3, [996] = 1, [997] = 0, [998] = 1,
	-- MM6
	[2056] = 0, [2057] = 2, [2058] = 1, [2059] = 1, [2060] = 3, [2061] = 4, [2062] = 3, [2063] = 1, [2064] = 4, [2065] = 2,
}
B.Gems, B.Ores = GEM, ORE

---------------------------------------------------------------------------
-- state
---------------------------------------------------------------------------

local OFFSET = 10000000
local STACK_SIZE = 9 ^ 8          -- 43046721

-- decode a board from Charges. Old format (tier * 1000 + progress) is converted.
-- Returns {Stack = {{Spec, Fine}, ...}, Work, Old}
local function decodeBoard(ch)
	local st = {Stack = {}, Work = 0}
	if ch < OFFSET then
		-- old blaster: Emitter T + Disruptor T, work progress kept
		local tier = min(4, max(0, floor(ch / 1000)))
		for t = 1, tier do
			st.Stack[#st.Stack + 1] = {Spec = 1, Fine = false}
			st.Stack[#st.Stack + 1] = {Spec = 3, Fine = false}
		end
		st.Work = tier < 4 and min(100, ch % 1000) or 0
		st.Old = true
		return st
	end
	local rest = ch - OFFSET
	local v = rest % STACK_SIZE
	st.Work = min(100, floor(rest / STACK_SIZE) * 5)
	for i = 1, 8 do
		local code = v % 9
		v = floor(v / 9)
		if code == 0 then break end
		code = code - 1
		st.Stack[#st.Stack + 1] = {Spec = code % 4 + 1, Fine = code >= 4}
	end
	return st
end

local function encodeBoard(st)
	local v, mul = 0, 1
	for i, e in ipairs(st.Stack) do
		if i > 8 then break end
		v = v + (1 + (e.Spec - 1) + (e.Fine and 4 or 0)) * mul
		mul = mul * 9
	end
	return OFFSET + v + STACK_SIZE * floor(min(100, max(0, st.Work)) / 5)
end

-- tiers and effective levels (a Fine install counts FineShare more)
local function levels(st)
	local tiers, lv = {0, 0, 0, 0}, {0, 0, 0, 0}
	for _, e in ipairs(st.Stack) do
		tiers[e.Spec] = tiers[e.Spec] + 1
		lv[e.Spec] = lv[e.Spec] + 1 + (e.Fine and B.FineShare or 0)
	end
	st.Tiers, st.Levels, st.Count = tiers, lv, #st.Stack
	return st
end

-- random upgrades for a newly found blaster
local function randomUpgrades(st)
	local n = 0
	if random() < B.FoundUpgrade1 then n = 1 end
	if n == 1 and random() < B.FoundUpgrade2 / B.FoundUpgrade1 then n = 2 end
	for i = 1, n do
		st.Stack[#st.Stack + 1] = {Spec = random(1, 4), Fine = false}
	end
end

-- state of a blaster item (struct); converts old and new-found blasters in place
local function state(item)
	local ch = item.Charges
	local st
	if ch < OFFSET then
		st = decodeBoard(ch)
		if ch == 0 then
			-- never touched: a found blaster with a random charge and maybe an upgrade
			randomUpgrades(st)
			item.MaxCharges = random(40, B.CellFull)
		else
			item.MaxCharges = B.CellFull
		end
		item.Charges = encodeBoard(st)
	else
		st = decodeBoard(ch)
	end
	st.Cell = item.MaxCharges
	return levels(st)
end
MF.BlasterState = state

local function save(item, st)
	item.Charges = encodeBoard(st)
	if st.Cell then item.MaxCharges = max(0, min(B.CellFull, st.Cell)) end
end
MF.BlasterSave = save

-- read-only view from raw fields (item card)
local function view(ch, cell)
	local st = decodeBoard(ch)
	if st.Old then cell = B.CellFull end
	st.Cell = cell
	return levels(st)
end

local function blasterOf(pl)
	local slot = pl.ItemMainHand
	if slot <= 0 then return end
	local it = pl.Items[slot]
	if not BLASTERS[it.Number] then return end
	return it, slot
end
MF.BlasterOf = blasterOf

---------------------------------------------------------------------------
-- effects (used by MMMWE_Main.lua)
---------------------------------------------------------------------------

function MF.BlasterDamageMult(item)
	local st = state(item)
	return 1 + B.EmitterPerTier * st.Levels[1], st
end

function MF.BlasterBaseRange(item)
	local t = BLASTERS[item.Number]
	return select(t, 10, 15), select(t, 20, 30)
end

function MF.BlasterRecovery(item)
	local st = state(item)
	local base = select(BLASTERS[item.Number], 50, 35)
	return max(5, floor(base - B.CapacitorPerTier * st.Levels[2] + 0.5))
end

-- eradication: Disruptor level (Emitter 4 without Disruptor: crits at tier 1 strength),
-- and the share of Body resistance counted
function MF.BlasterEradication(item, crit)
	local st = state(item)
	local lv = st.Levels[3]
	local bodyMul = 1
	if st.Tiers[1] >= 4 and crit then
		bodyMul = B.OverchargeBody
		if lv <= 0 then lv = 1 end
	end
	return lv * B.DisruptorPerTier, bodyMul, st
end

local function capacity(item, st)
	return B.Shots[BLASTERS[item.Number]] * (1 + B.CellPerTier * st.Levels[4])
end

---------------------------------------------------------------------------
-- item card
---------------------------------------------------------------------------

local function pips(st, spec)
	local s, done, fine = "", st.Tiers[spec], 0
	for _, e in ipairs(st.Stack) do
		if e.Spec == spec and e.Fine then fine = fine + 1 end
	end
	for i = 1, 4 do
		if i <= done then
			s = s .. (i <= fine and "+" or "#")
		else
			s = s .. "-"
		end
	end
	return "[" .. s .. "]"
end

-- the "Charges" line of a blaster's card (a format string: % doubled)
function MF.BlasterCardText(ch, cell)
	local st = view(ch, cell)
	local pl = Party:GetCurrentPlayer()
	local lim = 0
	if pl then
		local _, BM = SplitSkill(pl:GetSkill(const.Skills.Blaster))
		lim = BM > 0 and B.Limit[min(4, BM)] or 0
	end
	return string.format("%s %s  %s %s\n%s %s  %s %s\nUpgrades: %d/%d   Work: %d%%%%\nCharge: %d%%%%",
		SPEC_SHORT[1], pips(st, 1), SPEC_SHORT[2], pips(st, 2),
		SPEC_SHORT[3], pips(st, 3), SPEC_SHORT[4], pips(st, 4),
		st.Count, lim, st.Work, floor(st.Cell / 2))
end

function MF.BlasterCardDamageMult(ch)
	return 1 + B.EmitterPerTier * view(ch, 0).Levels[1]
end

function MF.ToolkitCardText(ch)
	if ch <= 0 then return "Board: empty" end
	local st = view(ch, 0)
	return string.format("Board: %s %d, %s %d, %s %d, %s %d   Work: %d%%%%",
		SPEC_SHORT[1], st.Tiers[1], SPEC_SHORT[2], st.Tiers[2],
		SPEC_SHORT[3], st.Tiers[3], SPEC_SHORT[4], st.Tiers[4], st.Work)
end

---------------------------------------------------------------------------
-- upgrades
---------------------------------------------------------------------------

local function fail(msg)
	Game.ShowStatusText(msg)
	evt.PlaySound{358}
	return 0
end

local function repairSkill(pl)
	local v = MF.TechRepairSkill and MF.TechRepairSkill(pl) or pl:GetSkill(const.Skills.Repair)
	return SplitSkill(v)
end

local function masteryLimit(pl)
	local _, BM = SplitSkill(pl:GetSkill(const.Skills.Blaster))
	return BM > 0 and B.Limit[min(4, BM)] or 0, BM
end

-- remove one item of the given numbers from a character's backpack (not equipped)
local function takeFromBackpack(pl, numbers)
	local found
	for cell, idx in pl.Inventory do
		if idx > 0 and numbers[pl.Items[idx].Number] then found = cell break end
	end
	if not found then return false end
	local idx = pl.Inventory[found]
	pl.Inventory[found] = 0
	for cell2, v2 in pl.Inventory do
		if v2 == -(found + 1) then pl.Inventory[cell2] = 0 end
	end
	pl.Items[idx].Number = 0
	return true
end

-- smelt: the ore on the cursor and another piece of the same grade -> next grade
local function smelt(pl, item)
	local grade = ORE[item.Number]
	if grade >= 6 then return fail("Stalt can't be refined any further.") end
	local RS, RM = repairSkill(pl)
	local g = grade + 1
	if RM < ORE_RM[g] or RS < ORE_RS[g] then
		return fail(string.format("Smelting %s needs Repair %d (%s), %s has %d (%s).",
			ORE_NAMES[g], ORE_RS[g], select(ORE_RM[g], "Novice", "Expert", "Master", "Grand Master"),
			pl.Name, RS, RM > 0 and select(RM, "Novice", "Expert", "Master", "Grand Master") or "none"))
	end
	local same = {}
	for n, gr in pairs(ORE) do if gr == grade then same[n] = true end end
	if not takeFromBackpack(pl, same) then
		return fail(string.format("Smelting needs a second piece of %s ore in %s's backpack.", ORE_NAMES[grade], pl.Name))
	end
	item.Number = item.Number + 1          -- the next ore of the same item set
	evt.PlaySound{12050}
	Game.ShowStatusText(string.format("%s smelts two pieces into %s ore.", pl.Name, ORE_NAMES[g]))
	return 0
end

local function useOre(pl, item)
	local grade = ORE[item.Number]
	if not grade then return end
	local gun = blasterOf(pl)
	if not gun then return smelt(pl, item) end
	if gun.Broken then return fail("The blaster is broken.") end
	local st = state(gun)
	local lim, BM = masteryLimit(pl)
	if st.Count >= 8 then return fail("This blaster is fully upgraded.") end
	if st.Count >= lim then
		return fail(string.format("%s's Blaster mastery allows %d upgrades on a gun.", pl.Name, lim))
	end
	if st.Work >= 100 then return fail("The work is done. Install a gem to finish the upgrade.") end
	local need = ORE_MIN[st.Count]
	if grade < need then
		return fail(string.format("This upgrade needs %s ore or better.", ORE_NAMES[need]))
	end
	local RS, RM = repairSkill(pl)
	if RM < ORE_RM[grade] or RS < ORE_RS[grade] then
		return fail(string.format("Working %s ore needs Repair %d (%s).", ORE_NAMES[grade], ORE_RS[grade],
			select(ORE_RM[grade], "Novice", "Expert", "Master", "Grand Master")))
	end
	local gain = B.WorkPerPiece[min(3, grade - need + 1)]
	st.Work = min(100, st.Work + gain)
	save(gun, st)
	evt.PlaySound{12050}
	Game.ShowStatusText(string.format("Work on the blaster: %d%%", st.Work))
	return 2
end

local function specFromKeys()
	local shift, ctrl = Keys.IsPressed(const.Keys.SHIFT), Keys.IsPressed(const.Keys.CTRL)
	if shift and ctrl then return 4 elseif ctrl then return 3 elseif shift then return 2 end
	return 1
end

local function useGem(pl, item)
	local spec = GEM[item.Number]
	if not spec then return end
	local gun = blasterOf(pl)
	if not gun then return fail("Hold a blaster in the main hand to install a gem.") end
	if gun.Broken then return fail("The blaster is broken.") end
	if spec == 0 then spec = specFromKeys() end
	local st = state(gun)
	local lim = masteryLimit(pl)
	if st.Count >= 8 then return fail("This blaster is fully upgraded.") end
	if st.Count >= lim then
		return fail(string.format("%s's Blaster mastery allows %d upgrades on a gun.", pl.Name, lim))
	end
	local tier = st.Tiers[spec] + 1
	if tier > 4 then return fail(string.format("%s is already at tier 4.", SPECS[spec])) end
	if st.Work < 100 then
		return fail(string.format("Work on the blaster first: %d/100 (use ore).", st.Work))
	end
	local value = Game.ItemsTxt[item.Number].Value
	if value < B.GemValue[tier] then
		return fail(string.format("%s tier %d needs a gem worth %d or more.", SPECS[spec], tier, B.GemValue[tier]))
	end
	local RS, RM = repairSkill(pl)
	if RM < tier then
		return fail(string.format("%s tier %d needs Repair at %s.", SPECS[spec], tier,
			select(tier, "Novice", "Expert", "Master", "Grand Master")))
	end
	local luck = Game.GetStatisticEffect(pl:GetLuck())
	local fineChance = B.FineBase + B.FinePerRepair * RS + B.FinePerLuck * luck
	local fine = random() * 100 < fineChance
	st.Stack[#st.Stack + 1] = {Spec = spec, Fine = fine}
	st.Work = 0
	save(gun, st)
	evt.PlaySound{12050}
	Game.ShowStatusText(string.format("%s tier %d installed%s", SPECS[spec], tier, fine and " - Fine work!" or "."))
	return 2
end

-- Blaster Toolkit: move the board between guns; Ctrl removes the last upgrade
local function useToolkit(pl, kit)
	local slot = pl.ItemMainHand
	if slot > 0 and (pl.Items[slot].Number == 1666 or pl.Items[slot].Number == 1667) then
		-- MM6 blasters to MM7 ones (as before)
		evt.PlaySound{12070}
		pl.Items[slot].Number = pl.Items[slot].Number - 800
		return 0
	end
	local gun = blasterOf(pl)
	if not gun then return fail("Hold a blaster in the main hand to use the toolkit.") end
	local st = state(gun)
	if Keys.IsPressed(const.Keys.CTRL) then
		local last = st.Stack[#st.Stack]
		if not last then return fail("There is no upgrade to remove.") end
		local tier = st.Tiers[last.Spec]
		local _, RM = repairSkill(pl)
		if RM < tier then
			return fail(string.format("Removing %s tier %d needs Repair at %s.", SPECS[last.Spec], tier,
				select(tier, "Novice", "Expert", "Master", "Grand Master")))
		end
		st.Stack[#st.Stack] = nil
		st.Work = 0
		save(gun, st)
		evt.PlaySound{17020}
		Game.ShowStatusText(string.format("%s tier %d removed. The gem is lost.", SPECS[last.Spec], tier))
		return 0
	end
	if #st.Stack > 0 or st.Work > 0 then
		if kit.Charges > 0 then return fail("The toolkit already holds a board.") end
		kit.Charges = encodeBoard(st)
		st.Stack, st.Work = {}, 0
		save(gun, st)
		evt.PlaySound{17020}
		Game.ShowStatusText("The upgrades are dismounted into the toolkit.")
		return 0
	end
	if kit.Charges > 0 then
		local board = decodeBoard(kit.Charges)
		st.Stack, st.Work = board.Stack, board.Work
		save(gun, st)
		kit.Charges = 0
		evt.PlaySound{12070}
		Game.ShowStatusText("The upgrades are mounted onto the blaster.")
		return 0
	end
	return fail("Neither the blaster nor the toolkit holds any upgrades.")
end

for id in pairs(ORE) do evt.UseItemEffects[id] = useOre end
for id in pairs(GEM) do evt.UseItemEffects[id] = useGem end
evt.UseItemEffects[TOOLKIT] = useToolkit

---------------------------------------------------------------------------
-- item descriptions: what an ore or gem does for blasters, while the selected
-- character has the Blaster skill
---------------------------------------------------------------------------

local function gemNote(id)
	local spec = GEM[id]
	local value = Game.ItemsTxt[id].Value
	local top = 0
	for t = 1, 4 do if value >= B.GemValue[t] then top = t end end
	if spec == 0 then
		return string.format("\n\nBlaster upgrade: any spec up to tier %d (no key Emitter, Shift Capacitor, Ctrl Disruptor, Ctrl+Shift Power cell).", top)
	end
	if top == 0 then return "" end
	return string.format("\n\nBlaster upgrade: %s up to tier %d.", SPECS[spec], top)
end

local function oreNote(id)
	local g = ORE[id]
	local s = string.format("\n\nBlaster upgrade work (needs Repair %d, %s).", ORE_RS[g],
		select(ORE_RM[g], "Novice", "Expert", "Master", "Grand Master"))
	if g < 6 then s = s .. string.format(" Two pieces can be smelted into %s ore.", ORE_NAMES[g + 1]) end
	return s
end

local BaseNotes, NoteShown
local function setNotes(show)
	if show == NoteShown then return end
	if not BaseNotes then
		BaseNotes = {}
		for id in pairs(ORE) do
			local ok, txt = pcall(function() return Game.ItemsTxt[id].Notes end)
			if ok and txt then BaseNotes[id] = {txt, oreNote(id)} end
		end
		for id in pairs(GEM) do
			local ok, txt = pcall(function() return Game.ItemsTxt[id].Notes end)
			if ok and txt then BaseNotes[id] = {txt, gemNote(id)} end
		end
	end
	for id, t in pairs(BaseNotes) do
		Game.ItemsTxt[id].Notes = show and (t[1] .. t[2]) or t[1]
	end
	NoteShown = show
end

---------------------------------------------------------------------------
-- shots: power cell, empty blaster, rapid cycling
---------------------------------------------------------------------------

local Pending = {}
local CellFrac = {}   -- while no game is loaded
B.Forced = nil       -- damage forced on the next hit (bash, chain); read by MMMWE_Main.lua

local function monsterDistance(m, x, y, z)
	local dx, dy, dz = m.X - x, m.Y - y, m.Z - z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function bashTarget(targetRef)
	local mi
	if targetRef and targetRef % 8 == 3 then mi = floor(targetRef / 8) end
	local function valid(i)
		local m = i and Map.Monsters[i]
		return m and m.HP > 0 and m.AIState ~= const.AIState.Removed
			and monsterDistance(m, Party.X, Party.Y, Party.Z) <= B.BashRange + (m.BodyRadius or 0)
	end
	if valid(mi) then return mi end
	local best, bd
	for i = 0, Map.Monsters.count - 1 do
		local m = Map.Monsters[i]
		if m.HP > 0 and m.Hostile then
			local d = monsterDistance(m, Party.X, Party.Y, Party.Z)
			if d <= B.BashRange + (m.BodyRadius or 0) and (not bd or d < bd) then best, bd = i, d end
		end
	end
	return best
end

local BLASTER_SPELL = 135

mem.autohook(0x42609E, function(d)
	local slot = 0x51D820 + u4[d.ebp - 0xC8] * 0x14
	if u2[slot] ~= BLASTER_SPELL then return end
	local pl = Party.PlayersArray[u2[slot + 2]]
	if not pl then return end
	local gun = blasterOf(pl)
	if not gun then return end
	local st = state(gun)
	if st.Cell <= 0 then
		-- out of power: no shot; a bash at a monster in reach
		pl:SetRecoveryDelay(B.EmptyRecovery)
		local mi = bashTarget(u2[slot + 0xC])
		if mi then
			Pending[#Pending + 1] = {Kind = "Bash", pi = pl:GetIndex(), mi = mi}
			Game.ShowStatusText(string.format("%s's blaster is out of power - %s bashes with it", pl.Name, pl.Name), 2)
		else
			Game.ShowStatusText(string.format("%s's blaster is out of power", pl.Name), 2)
			evt.PlaySound{358}
		end
		u2[slot] = 0
		d:push(0x42D45D)
		return true
	end
	-- one shot's share of the cell, in 0.5% steps; the fraction is kept per gun (by the
	-- character and the item slot) and adds up, so every shot drains exactly its share
	local use = B.CellFull / capacity(gun, st)
	local key = pl:GetIndex() * 1000 + pl.ItemMainHand
	local fracs = vars and vars.BlasterCellFrac
	if vars and not fracs then fracs = {} vars.BlasterCellFrac = fracs end
	fracs = fracs or CellFrac
	local acc = (fracs[key] or 0) + use
	local steps = floor(acc)
	fracs[key] = acc - steps
	local before = st.Cell
	st.Cell = max(0, st.Cell - steps)
	gun.MaxCharges = st.Cell
	if before >= B.LowWarn and st.Cell < B.LowWarn then
		Game.ShowStatusText(string.format("%s's blaster: power cell low (%d%%)", pl.Name, floor(st.Cell / 2)), 3)
	elseif st.Cell <= 0 then
		Game.ShowStatusText(string.format("%s's blaster: power cell empty", pl.Name), 3)
	end
	if st.Tiers[2] >= 4 and random() < B.RapidChance then
		Pending[#Pending + 1] = {Kind = "Rapid", pi = pl:GetIndex()}
	end
end)

local HitVec = mem.StaticAlloc(12)
local function forcedHit(pi, mi, dmg)
	B.Forced = dmg
	local ok, err = pcall(mem.call, 0x436E26, 2, pi * 8 + 4, mi, HitVec)
	B.Forced = nil
	return ok
end

-- Disruptor 4: an eradicated target's neighbours take half the hit (MMMWE_Main.lua)
function MF.BlasterChain(pl, mon, damage)
	local st = blasterOf(pl) and state(blasterOf(pl))
	if not st or st.Tiers[3] < 4 then return end
	local dmg = floor(damage * B.ChainShare)
	if dmg <= 0 then return end
	for i = 0, Map.Monsters.count - 1 do
		local m = Map.Monsters[i]
		if m ~= mon and m.HP > 0 and m.Hostile and m.AIState ~= const.AIState.Removed
				and monsterDistance(m, mon.X, mon.Y, mon.Z) <= B.ChainRadius + (m.BodyRadius or 0) then
			Pending[#Pending + 1] = {Kind = "Chain", pi = pl:GetIndex(), mi = i, dmg = dmg}
		end
	end
end

---------------------------------------------------------------------------
-- Recharge Item: the spell (on a blaster in the backpack) and the potion
---------------------------------------------------------------------------

-- restore pct % of a blaster's cell; returns true if it was a blaster
function MF.BlasterRecharge(item, pct)
	if not BLASTERS[item.Number] then return false end
	local st = state(item)
	st.Cell = min(B.CellFull, st.Cell + floor(pct * 2 + 0.5))
	item.MaxCharges = st.Cell
	return true
end

-- the spell: at 0x428B9C ecx is the target item; a wand check follows. A blaster is
-- recharged here and the spell succeeds (0x42C1F6).
mem.autohook(0x428B9C, function(d)
	local ptr = d.ecx
	local num = i4[ptr]
	if not BLASTERS[num] then return end
	local mastery = i4[d.ebp - 0xC]
	local skill = i4[d.ebp - 0x3C]
	local se = Merge.Tables and Merge.Tables.SpellsExtra and Merge.Tables.SpellsExtra[28]
	local base = {30, 50, 70, 80}
	if se then
		base = {se.Var1Normal or 30, se.Var1Expert or 50, se.Var1Master or 70, se.Var1GM or 80}
	end
	local pct = min(100, (base[min(4, max(1, mastery))] or 30) + skill)
	-- the item struct at ptr
	for _, pl in Party do
		for idx, it in pl.Items do
			if it["?ptr"] == ptr then
				MF.BlasterRecharge(it, pct)
				Game.ShowStatusText(string.format("Power cell: %d%%", floor(it.MaxCharges / 2)), 2)
			end
		end
	end
	d:push(0x42C1F6)
	return true
end)

---------------------------------------------------------------------------
-- tick: pending hits, rapid cycling, self-recharge, notes
---------------------------------------------------------------------------

function events.Tick()
	if #Pending > 0 then
		local q = Pending
		Pending = {}
		for _, r in ipairs(q) do
			local pl = Party.PlayersArray[r.pi]
			if r.Kind == "Rapid" then
				if pl then pl:SetRecoveryDelay(0) end
			elseif r.Kind == "Bash" then
				local m = Map.Monsters[r.mi]
				if m and m.HP > 0 then forcedHit(r.pi, r.mi, random(B.BashMin, B.BashMax)) end
			elseif r.Kind == "Chain" then
				local m = Map.Monsters[r.mi]
				if m and m.HP > 0 then forcedHit(r.pi, r.mi, r.dmg) end
			end
		end
	end

	local pl = Party:GetCurrentPlayer()
	setNotes(pl ~= nil and SplitSkill(pl.Skills[const.Skills.Blaster]) > 0)

	-- Power cell 4: +1% per game hour for every such blaster the party carries
	if vars then
		local last = vars.BlasterCellTime
		if not last or last > Game.Time then
			vars.BlasterCellTime = Game.Time
		elseif Game.Time - last >= const.Hour then
			local hours = floor((Game.Time - last) / const.Hour)
			vars.BlasterCellTime = last + hours * const.Hour
			for _, p in Party do
				for _, it in p.Items do
					if BLASTERS[it.Number] and it.Charges >= OFFSET then
						local st = view(it.Charges, it.MaxCharges)
						if st.Tiers[4] >= 4 and st.Cell < B.CellFull then
							it.MaxCharges = min(B.CellFull, st.Cell + hours * B.SelfRechargePerHour)
						end
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- ore in the world: prices of the MM7 ores, ore at blacksmiths
-- (random loot: ItemsExtra.txt continent factors of the ores)
---------------------------------------------------------------------------

B.ShopOreChance = 0.15        -- a weapon shop's refill: chance of ore in stock
B.ShopOreMax    = 2           -- pieces at most

function events.GameInitialized2()
	-- the MM7 ores have value 0 in Items.txt (sold for "n/a" or 1 gold): same as the MM8 ones
	for k = 0, 5 do
		local mm7, mm8 = Game.ItemsTxt[1488 + k], Game.ItemsTxt[686 + k]
		if mm7.Value <= 0 then mm7.Value = mm8.Value end
	end
end

-- grade range by the shop's best item (shop tier)
local function shopOreGrade(best)
	if best < 300 then return random(1, 2)
	elseif best < 1000 then return random(2, 3)
	elseif best < 3000 then return random(3, 4)
	elseif best < 8000 then return random(4, 5)
	end
	return random(5, 6)
end

function events.ShopRefilled(items)
	if random() >= B.ShopOreChance then return end
	local weapons, total, best, empty = 0, 0, 0, {}
	for i, it in items do
		if it.Number > 0 then
			total = total + 1
			local txt = Game.ItemsTxt[it.Number]
			if txt.EquipStat <= 2 and txt.Skill ~= const.Skills.Blaster then weapons = weapons + 1 end
			best = max(best, txt.Value)
		else
			empty[#empty + 1] = i
		end
	end
	if total == 0 or weapons * 2 < total then return end   -- blacksmiths only
	local base = (Merge.Vars and Merge.Vars.Continent == 2) and 1488 or 686
	for n = 1, random(1, B.ShopOreMax) do
		local slot = table.remove(empty, random(1, max(1, #empty)))
		if not slot then
			-- no free place: replace a random item
			local all = {}
			for i, it in items do all[#all + 1] = i end
			slot = all[random(1, #all)]
		end
		local it = items[slot]
		it.Number = base + shopOreGrade(best) - 1
		it.Bonus, it.Bonus2, it.BonusStrength, it.Charges, it.MaxCharges = 0, 0, 0, 0, 0
		it.Identified = true
		it.Broken = false
	end
end

-- console: Merge.Functions.BlasterInfo()
function MF.BlasterInfo(pl)
	pl = pl or Party:GetCurrentPlayer()
	local gun = blasterOf(pl)
	if not gun then return "no blaster in the main hand" end
	local st = state(gun)
	local s = {}
	for i, e in ipairs(st.Stack) do s[#s + 1] = SPEC_SHORT[e.Spec] .. (e.Fine and "+" or "") end
	return string.format("%s: E%d C%d D%d P%d (levels %.1f/%.1f/%.1f/%.1f), order %s, work %d, cell %.1f%%, recovery %d, shots per cell %d",
		pl.Name, st.Tiers[1], st.Tiers[2], st.Tiers[3], st.Tiers[4],
		st.Levels[1], st.Levels[2], st.Levels[3], st.Levels[4], table.concat(s, " "),
		st.Work, st.Cell / 2, MF.BlasterRecovery(gun), floor(capacity(gun, st)))
end
