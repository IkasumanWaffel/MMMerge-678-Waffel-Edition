--[[
	MMMWE_ExtraSkillsEnchanting.lua — what the skill Enchanting (43) does (11.11.26)
	(the skill itself: MMMWE_ExtraSkills.lua; its teachers: Global\MMMWE_ExtraSkillTeachers.lua)

	Wands as a caster's sidearm.
	  Every wand casts its spell at the Enchanting skill and rank of the one who uses it
	  (at least BASE_SKILL; without the skill: BASE_SKILL at Novice, as the game's wands did).
	  Grand Master: a use costs no charge one time in KEEP_CHANCE.
	  Legendary (Living Wands): the party's wands regain a charge every game hour.

	Wands of the spells cast on characters (SUPPORT below, items 2232..2249): picked up and
	clicked on a portrait, they cast the spell on that character (or the party, for a
	party spell), a charge a use. The last charge used, the wand is gone.

	Making and refilling wands, by right-clicking one item on another in the backpack:
	  a gem on a wand (Expert): the wand's charges back to its most, which goes down by
	      RECHARGE_LOSS of the rank (a fifth at Expert, a tenth at Master, none at Grand
	      Master); the gem is used up
	  a gem on a blank wand (BLANK, Master): the gem is set in (the blank's Charges keep
	      the gem's item number, shown on its card)
	  a spell scroll on a blank wand with a gem (Master): a wand of the scroll's spell
	      (the game's wand of it, or a support wand), with CRAFT_BASE + the Enchanting
	      skill + the gem's value / GEM_VALUE_PER charges; the scroll is used up
	  Spells with no wand of their own can't be bound.

	MF.WandSkill(pl) -> skill, rank the character's wands cast at
--]]

local MF = Merge.Functions
local Tx = Merge.Functions.Text
local EXTRA = MF.ExtraSkills
if not EXTRA or not EXTRA.Skills.Enchanting then
	return
end

local ENCH = EXTRA.Skills.Enchanting
local u1, u4, i4 = mem.u1, mem.u4, mem.i4
local floor, max, min, random = math.floor, math.max, math.min, math.random

local BASE_SKILL     = 8          -- the game's wands: skill 8, Novice
local KEEP_CHANCE    = 4          -- Grand Master: one use in this many costs no charge
local RECHARGE_LOSS  = {[2] = 0.2, [3] = 0.1, [4] = 0}
local CRAFT_BASE     = 5
local GEM_VALUE_PER  = 250
local BLANK          = 2231
local WAND_EQUIP     = 12         -- ItemsTxt EquipStat of the game's wands
local SCROLL_EQUIP   = 15         -- of the spell scrolls
local GemEquip                    -- of the gems (Zircon's)

-- the support wands: item -> spell
local SUPPORT = {
	[2232] = 68, [2233] = 67, [2234] = 72, [2235] = 74, [2236] = 61, [2237] = 57,
	[2238] = 64, [2239] = 49, [2240] = 46, [2241] = 51, [2242] = 38, [2243] = 5,
	[2244] = 17, [2245] = 13, [2246] = 27, [2247] = 21, [2248] = 71, [2249] = 77,
}
MF.SupportWands = SUPPORT

local function log(fmt, ...) if MF.LogInfo then MF.LogInfo("[Enchanting] " .. fmt, ...) end end

local function playerAt(ptr)
	local arr = Party.PlayersArray
	local i = (ptr - arr[0]["?ptr"]) / arr[0]["?size"]
	if i >= 0 and i == floor(i) and i < arr.count then return arr[i], i end
end

local function enchanting(pl)
	local ok, s, m = pcall(function() return SplitSkill(pl:GetSkill(ENCH)) end)
	if not ok or not s then s, m = SplitSkill(MF.GetExtraSkill(pl, ENCH)) end
	return s or 0, m or 0
end

-- the skill and rank a character's wands cast at
local function wandSkill(pl)
	local s, m = enchanting(pl)
	if m <= 0 then return BASE_SKILL, 1 end
	return max(s, BASE_SKILL), min(m, 4)
end
MF.WandSkill = wandSkill

local function spellOf(num)
	local t = Game.ItemsTxt[num]
	return t and u1[t["?ptr"] + 0x23] or 0     -- the spell of S<n> (RemoveItemsLimits.lua)
end

local function isWand(num)
	local t = Game.ItemsTxt[num]
	return t and t.EquipStat == WAND_EQUIP or SUPPORT[num] ~= nil
end

local function mostCharges(it)
	if it.MaxCharges > 0 then return it.MaxCharges end
	local t = Game.ItemsTxt[it.Number]
	return max(t and t.Mod2 or 0, it.Charges, 1)
end

-- the mouse's item put away (the game's own "remove the item on the mouse")
local function removeMouseItem()
	mem.call(0x467C0A, 1, u4[0x75D770])
end

local function say(text)
	Game.ShowStatusText(text)
end

---------------------------------------------------------------------------
-- the game's wands: the spell cast at the Enchanting skill and rank
---------------------------------------------------------------------------

-- 0x42DAE4: a wand attack, about to call the spell (ecx - spell, esi - player, the skill
-- pushed was 8); the item in the main hand is [esi+1C08h]
local WandSkillVar = mem.StaticAlloc(4)
local KeepCharge = false
local code = mem.asmpatch(0x42DAE4, [[
	nop
	nop
	nop
	nop
	nop
	push ebx
	push dword []] .. WandSkillVar .. [[]
	mov dword ptr [ebp-0x20], 1
]], 10)
mem.hook(code or 0x42DAE4, function(d)
	u4[WandSkillVar] = BASE_SKILL
	KeepCharge = false
	local ok, err = pcall(function()
		local pl = playerAt(d.esi)
		if not pl then return end
		local s, m = wandSkill(pl)
		u4[WandSkillVar] = JoinSkill(s, m)
		KeepCharge = m >= 4 and random(KEEP_CHANCE) == 1
	end)
	if not ok then log("wand skill: %s", tostring(err)) end
end)

-- 0x42DB05: the charge has been taken (dec [item+10h]); a Grand Master's lucky use gets it back
mem.autohook(0x42DB05, function(d)
	if not KeepCharge then return end
	KeepCharge = false
	local idx = i4[d.esi + 0x1C08]
	if idx > 0 then
		i4[d.esi + 0x484 + idx * 0x24 + 0x10] = i4[d.esi + 0x484 + idx * 0x24 + 0x10] + 1
	end
end)

---------------------------------------------------------------------------
-- the support wands: clicked on a portrait
---------------------------------------------------------------------------

local function useSupportWand(target, item, slot)
	local spell = SUPPORT[item.Number]
	if not spell then return end
	if item.Charges <= 0 then
		say(Tx"The wand has no charges left")
		return 0
	end
	local userSlot = Game.CurrentPlayer
	if not userSlot or userSlot < 0 or userSlot >= Party.count then userSlot = slot end
	local user = Party[userSlot]
	local s, m = wandSkill(user)
	CastSpellDirect(spell, s, m, Party.PlayersIndexes[userSlot], slot)
	local keep = m >= 4 and random(KEEP_CHANCE) == 1
	if not keep then item.Charges = item.Charges - 1 end
	if item.Charges <= 0 then
		removeMouseItem()
		say(Tx"The wand crumbles to dust")
	end
	return 0
end

for num in pairs(SUPPORT) do
	evt.UseItemEffects[num] = useSupportWand
end

-- a support wand found or bought: the game gives charges to its own wands only
function events.ItemGenerated(t)
	local it = t.Item
	if not it or not SUPPORT[it.Number] then return end
	local most = max(Game.ItemsTxt[it.Number].Mod2, 1)
	it.MaxCharges = most
	it.Charges = random(floor(most / 2), most)
end

---------------------------------------------------------------------------
-- making and refilling wands (an item right-clicked on an item in the backpack)
---------------------------------------------------------------------------

-- the game's wand of a spell (the one of the continent the party is on first), or a support wand
local WandOfSpell
local function wandFor(spell)
	if not WandOfSpell then
		WandOfSpell = {}
		for n = 1, Game.ItemsTxt.count - 1 do
			local t = Game.ItemsTxt[n]
			if t.EquipStat == WAND_EQUIP then
				local sp = spellOf(n)
				if sp > 0 then
					WandOfSpell[sp] = WandOfSpell[sp] or {}
					table.insert(WandOfSpell[sp], n)
				end
			end
		end
		for n, sp in pairs(SUPPORT) do WandOfSpell[sp] = {n} end
	end
	local list = WandOfSpell[spell]
	if not list then return end
	local c = Merge.Vars and Merge.Vars.Continent or 1
	-- the item ranges of the wands: Jadame (MM8) below 900, Antagarich 900..1699, Enroth above
	for _, n in ipairs(list) do
		local cn = n < 900 and 1 or (n < 1700 and 2 or 3)
		if cn == c then return n end
	end
	return list[1]
end

local function gemEquip()
	GemEquip = GemEquip or Game.ItemsTxt[177].EquipStat
	return GemEquip
end

-- what happens when the mouse's item meets the target item; true if handled
local function combine(pl, target)
	local num = Mouse.Item.Number
	local t = Game.ItemsTxt[num]
	if not t or num == 0 or target.Number == 0 then return end
	local _, m = enchanting(pl)
	local isGem = t.EquipStat == gemEquip()

	if isGem and target.Number == BLANK then
		if m < 3 then say(Tx"Making wands takes a Master of Enchanting") return true end
		if target.Charges > 0 then say(Tx"The blank wand has a gem already") return true end
		target.Charges = num
		target.Identified = true
		removeMouseItem()
		say(string.format(Tx"%s sets the %s in the blank wand", pl.Name, t.Name))
		evt.PlaySound{12050}
		return true
	end

	if isGem and isWand(target.Number) then
		if m < 2 then say(Tx"Refilling wands takes an Expert in Enchanting") return true end
		local most = mostCharges(target)
		local after = max(1, floor(most * (1 - (RECHARGE_LOSS[m] or 0)) + 0.5))
		if target.Charges >= after then say(Tx"The wand is full") return true end
		target.MaxCharges = min(after, 255)
		target.Charges = after
		target.Identified = true
		removeMouseItem()
		say(string.format(Tx"%s refills the %s: %d charges", pl.Name, Game.ItemsTxt[target.Number].Name, after))
		evt.PlaySound{12050}
		return true
	end

	if t.EquipStat == SCROLL_EQUIP and target.Number == BLANK then
		if m < 3 then say(Tx"Making wands takes a Master of Enchanting") return true end
		local gem = target.Charges
		local gt = gem > 0 and Game.ItemsTxt[gem]
		if not gt then say(Tx"Set a gem in the blank wand first") return true end
		local spell = spellOf(num)
		local wand = spell > 0 and wandFor(spell)
		if not wand then say(Tx"This spell can't be bound into a wand") return true end
		local s = enchanting(pl)
		local charges = min(CRAFT_BASE + s + floor(gt.Value / GEM_VALUE_PER), 255)
		target:Clear()
		target.Number = wand
		target.Charges = charges
		target.MaxCharges = charges
		target.Identified = true
		removeMouseItem()
		say(string.format(Tx"%s makes a %s with %d charges", pl.Name, Game.ItemsTxt[wand].Name, charges))
		evt.PlaySound{12050}
		log("%s made item %d (spell %d) from scroll %d and gem %d: %d charges", pl.Name, wand, spell, num, gem, charges)
		return true
	end
end

-- 0x4157C3: an item on the mouse right-clicked on the item at slot [ebp-0Ch] + 1 of the
-- character esi (the potions' and reagents' mixing follows); handled: the routine's end
mem.autohook(0x4157C3, function(d)
	local ok, res = pcall(function()
		local pl = playerAt(d.esi)
		if not pl then return end
		local slot = i4[d.ebp - 0xC] + 1
		if slot < 1 or slot > 138 then return end
		return combine(pl, pl.Items[slot])
	end)
	if not ok then log("combine: %s", tostring(res)) return end
	if res then
		Game.NeedRedraw = true
		d:push(0x416323)
		return true
	end
end)

---------------------------------------------------------------------------
-- Legendary: the party's wands regain a charge every game hour
---------------------------------------------------------------------------

local function legendary()
	if not MF.IsLegendary then return false end
	for _, pl in Party do
		if MF.IsLegendary(pl, ENCH) then return true end
	end
	return false
end

local tick = 0
function events.Tick()
	tick = tick + 1
	if tick < 60 then return end
	tick = 0
	if not vars then return end
	local now = Game.Time
	local last = vars.MMMWE_WandRegen
	if not last or now < last then vars.MMMWE_WandRegen = now return end
	local hours = floor((now - last) / const.Hour)
	if hours < 1 then return end
	vars.MMMWE_WandRegen = last + hours * const.Hour
	if not legendary() then return end
	for _, pl in Party do
		for _, it in pl.Items do
			if it.Number ~= 0 and isWand(it.Number) and not it.Broken then
				local most = mostCharges(it)
				if it.Charges < most then it.Charges = min(most, it.Charges + hours) end
			end
		end
	end
end
