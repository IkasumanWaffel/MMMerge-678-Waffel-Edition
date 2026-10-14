--[[
	MMMWE_Drains.lua — stat, armor and resistance drains by monsters

	Some monsters drain the character they hit (melee or missile, when the hit does damage):
	  vampires                 Might or Endurance
	  MM6 bloodsuckers         Endurance, Intellect or Personality
	  MM8 nightmares           any of the seven stats
	  oozes                    Armor Class (Armor Corrosion)
	  elementals               the resistance of their element (Fire, Air, Water, Earth, Light)
	The monsters are listed in DRAINERS below.

	One drain:
	  stat        enough points to lower the stat bonus by 1
	  resistance  enough points to lower the damage reduction by 3 percentage points
	  Armor Class enough points to lower the physical resistance by 5% of its value
	              without corrosion
	Drains stack and last until an 8 hour rest, a Divine Restoration potion or Divine
	Intervention.

	Chance per damaging hit:
	  BASE_CHANCE x (monster level + 30) / (monster level + 30 + save)
	  save = the drained stat, the base resistance, or the Armor Class (without corrosion)
	The monster level raises the chance as for the game's own conditions; a higher stat /
	resistance / AC resists better.

	The drains are kept in the extra debuff slots 20..32 (Structs/30_MergeStructs.lua):
	Power = the total amount drained, Skill = the number of drains, ExpireTime = a week
	ahead (renewed with each drain; the cures clear them). They are listed with the other
	debuffs and saved with the game. CalcStatBonusByMagic subtracts them.
--]]

local MF = Merge.Functions
local ST = const.Stats

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local ENABLED       = true
local BASE_CHANCE   = 25      -- % per damaging hit before the save
local STAT_STEP     = 1       -- stat bonus points per drain
local RES_STEP      = 0.03    -- damage reduction per resistance drain
local AC_STEP       = 0.05    -- share of the uncorroded physical resistance per corrosion
local DURATION      = 7 * const.Day   -- "until rest": long, renewed with every drain

local STATS = {"Might", "Intellect", "Personality", "Endurance", "Accuracy", "Speed", "Luck"}

-- debuff slot of each drain
local SLOT = {
	Might = 20, Intellect = 21, Personality = 22, Endurance = 23, Accuracy = 24, Speed = 25,
	Luck = 26, ArmorClass = 27, Fire = 28, Air = 29, Water = 30, Earth = 31, Light = 32,
}
local FIRST_SLOT, LAST_SLOT = 20, 32

local RES_STAT = {Fire = ST.FireResistance, Air = ST.AirResistance, Water = ST.WaterResistance,
	Earth = ST.EarthResistance, Light = ST.LightResistance}

-- monster id -> list of drains (one is picked at random per proc)
local DRAINERS = {}
local function add(ids, what)
	for _, id in ipairs(ids) do DRAINERS[id] = what end
end
add({52, 53, 54, 415, 416, 417},       {"Might", "Endurance"})                  -- vampires
add({487, 488, 489},                   {"Endurance", "Intellect", "Personality"}) -- MM6 bloodsuckers
add({151, 152, 153},                   STATS)                                   -- MM8 nightmares
add({310, 311, 312, 589, 590, 591},    {"ArmorClass"})                          -- oozes
add({73, 74, 75, 240, 531},            {"Fire"})                                -- fire elementals
add({82, 83, 84, 234, 525},            {"Air"})                                 -- air elementals
add({76, 77, 78, 246, 534},            {"Water"})                               -- water elementals
add({79, 80, 81, 235, 236, 237, 528},  {"Earth"})                               -- earth elementals
add({241, 242, 243},                   {"Light"})                               -- light elementals
MF.DrainMonsters = DRAINERS

---------------------------------------------------------------------------

local function debuffs(pl)
	return Game.PlayersExtra[pl:GetIndex()].Debuffs
end

local function active(b)
	return b.ExpireTime > Game.Time and b.Power > 0
end

local function statValue(pl, name)
	return pl["Get" .. name](pl)
end

-- points that lower the stat bonus of value v by STAT_STEP
local function statDrainAmount(v)
	local bonus = Game.GetStatisticEffect(v)
	for d = 1, v do
		if Game.GetStatisticEffect(v - d) <= bonus - STAT_STEP then return d end
	end
	return 0
end

-- damage reduction of a resistance value (the resistance curve)
local function reduction(r)
	if r <= 0 then return 0 end
	local p = 1 - 30 / (r + 30)
	return 0.5 * p + 0.25 * p^2 + 0.125 * p^3 + 0.0625 * p^4
end

-- points of resistance r that lower its damage reduction by RES_STEP (at most r)
local function resDrainAmount(r)
	if r <= 0 then return 0 end
	local target = reduction(r) - RES_STEP
	for d = 1, r do
		if reduction(r - d) <= target then return d end
	end
	return r
end

-- physical resistance (0..1) of pl at armor class ac (MMMWE_Main.lua formula)
local function physRes(pl, ac)
	local dur = MF.CalcTotalArmorDurability and MF.CalcTotalArmorDurability(pl) or 0
	local hr = dur / (MF.HR_DIVISOR or 5)
	local strengthDR = 1 - Game.GetStatisticEffect(pl:GetMight()) * 0.01
	return 1 - strengthDR * (205 - hr) / (210 - hr + ac), strengthDR, hr
end

-- total corrosion for n corrosions: the AC at which phys res is (1 - AC_STEP*n) of the
-- uncorroded value
local function corrosionFor(pl, acClean, n)
	local base, strengthDR, hr = physRes(pl, acClean)
	local target = base * (1 - AC_STEP * n)
	if target <= 0 then return acClean end
	-- 1 - s * (205 - hr) / (210 - hr + ac) = target  ->  ac = s * (205 - hr) / (1 - target) - 210 + hr
	local ac = strengthDR * (205 - hr) / (1 - target) - 210 + hr
	return math.max(0, math.min(acClean, math.floor(acClean - ac + 0.5)))
end

---------------------------------------------------------------------------
-- applying a drain
---------------------------------------------------------------------------

local function saveValue(pl, what, b)
	if RES_STAT[what] then return math.max(pl:GetBaseResistance(RES_STAT[what]), 0) end
	if what == "ArmorClass" then
		return pl:GetArmorClass() + (active(b) and b.Power or 0)
	end
	return math.max(statValue(pl, what), 0)
end

local function applyDrain(pl, what)
	local b = debuffs(pl)[SLOT[what]]
	local cur = active(b) and b.Power or 0
	local count = active(b) and b.Skill or 0
	local amount
	if RES_STAT[what] then
		amount = cur + resDrainAmount(pl:GetResistance(RES_STAT[what]))
	elseif what == "ArmorClass" then
		local acClean = pl:GetArmorClass() + cur
		amount = corrosionFor(pl, acClean, count + 1)
	else
		amount = cur + statDrainAmount(statValue(pl, what))
	end
	if amount <= cur then return false end
	b.Power = math.min(amount, 32767)
	b.Skill = count + 1
	b.ExpireTime = Game.Time + DURATION
	return true, amount - cur
end

local LABEL = {ArmorClass = "armor is corroded", Fire = "Fire resistance is drained",
	Air = "Air resistance is drained", Water = "Water resistance is drained",
	Earth = "Earth resistance is drained", Light = "Light resistance is drained"}

-- the monster behind the hit the party is taking right now
local function attackingMonster()
	if not WhoHitPlayer then return nil end
	local who = WhoHitPlayer()
	if type(who) ~= "table" then return nil end
	if who.Monster then return who.Monster end
	local o = who.Object
	if o and o.Owner and o.Owner % 8 == 3 then
		local i = math.floor(o.Owner / 8)
		if i < Map.Monsters.count then return Map.Monsters[i] end
	end
end

local function onHit(t)
	if not ENABLED or not t.Player or (t.Result or 0) <= 0 then return end
	local mon = attackingMonster()
	local list = mon and DRAINERS[mon.Id]
	if not list then return end
	local pl = t.Player
	local what = list[math.random(#list)]
	local b = debuffs(pl)[SLOT[what]]
	local level = math.max(mon.Level or 1, 1)
	local save = saveValue(pl, what, b)
	local chance = BASE_CHANCE * (level + 30) / (level + 30 + save)
	if math.random() * 100 >= chance then return end
	local ok, amount = applyDrain(pl, what)
	if ok then
		Game.ShowStatusText(string.format("%s's %s!", pl.Name,
			LABEL[what] or (what .. " is drained")))
		MF.LogInfo("[Drain] %s: %s -%d (monster %d, chance %.1f%%)", pl.Name, what, amount, mon.Id, chance)
	end
end

-- registered after every other handler, so t.Result is the damage actually taken
function events.GameInitialized2()
	events.CalcDamageToPlayer = onHit
end

---------------------------------------------------------------------------
-- effect on the stats
---------------------------------------------------------------------------

local SLOT_OF_STAT = {
	[ST.Might] = SLOT.Might, [ST.Intellect] = SLOT.Intellect, [ST.Personality] = SLOT.Personality,
	[ST.Endurance] = SLOT.Endurance, [ST.Accuracy] = SLOT.Accuracy, [ST.Speed] = SLOT.Speed,
	[ST.Luck] = SLOT.Luck, [ST.ArmorClass] = SLOT.ArmorClass,
	[ST.FireResistance] = SLOT.Fire, [ST.AirResistance] = SLOT.Air,
	[ST.WaterResistance] = SLOT.Water, [ST.EarthResistance] = SLOT.Earth,
	[ST.LightResistance] = SLOT.Light,
}

function events.CalcStatBonusByMagic(t)
	local slot = SLOT_OF_STAT[t.Stat]
	if not slot or not t.Player then return end
	local b = debuffs(t.Player)[slot]
	if active(b) then
		t.Result = t.Result - b.Power
	end
end

---------------------------------------------------------------------------
-- cures
---------------------------------------------------------------------------

local function clearDrains(pl)
	local d = debuffs(pl)
	for i = FIRST_SLOT, LAST_SLOT do
		local b = d[i]
		b.ExpireTime, b.Power, b.Skill = 0, 0, 0
	end
end
MF.ClearDrains = clearDrains

local function clearParty()
	for i = 0, Party.count - 1 do clearDrains(Party[i]) end
end

-- 8 hour rest: the party's rest-and-heal routine (0x48FE9C, also used by Party.RestAndHeal)
mem.hookfunction(0x48FE9C, 1, 0, function(d, def, this)
	local r = def(this)
	pcall(clearParty)
	return r
end)

-- Divine Restoration (potion 252): its effect is defined by the potion scripts (Global),
-- which load later, so it is wrapped (again whenever it was replaced) from the tick below
local DR = 252 - 220
local wrapper
local function wrapDivineRestoration()
	if evt.PotionEffects[DR] == wrapper and wrapper then return end
	local orig = evt.PotionEffects[DR]
	wrapper = function(IsDrunk, Target, Power, ...)
		local r
		if orig then r = orig(IsDrunk, Target, Power, ...) end
		if IsDrunk and Target then clearDrains(Target) end
		return r
	end
	evt.PotionEffects[DR] = wrapper
end

-- Divine Intervention: a cast raises the caster's DevineInterventionCasts
local lastDI = {}
function events.Tick()
	wrapDivineRestoration()
	for i = 0, Party.count - 1 do
		local pl = Party[i]
		local id = pl:GetIndex()
		local n = pl.DevineInterventionCasts
		if lastDI[id] and n > lastDI[id] then
			clearParty()
		end
		lastDI[id] = n
	end
end
