--[[
	MMMWE_ExtraSkillsEffects.lua — what the new skills Dual-Wield and Robe do (07.11.26)
	(the skills themselves: MMMWE_ExtraSkills.lua)

	Dual-Wield (41)
	  A weapon in the off hand needs the skill (any mastery), whatever its kind: the Sword and
	  Dagger Master rule of ItemsExtra.txt (Equip2Req) is replaced for weapons. Blaster pistols
	  keep their own rule (MMMWE_Blasters.lua). A two-handed weapon next to another weapon
	  needs Grand Master; next to a shield or alone, the table's rule stays (Spear Master).
	  Holding a weapon in each hand (not a pair of blaster pistols):
	    Novice (or none, for weapons put on before the rule): -10 attack, the off hand's
	      damage halved, recovery +20%
	    Expert: -5 attack, off hand 75%, recovery +10%
	    Master, Grand Master: no penalties
	Robe (42), while no body armor is worn (robe items will count too):
	    Novice: +1 AC per 2 skill points
	    Expert: spell recovery 1% faster per skill point
	    Master: spells cost 10% less SP
	    Grand Master: +1 to every magic resistance per skill point
--]]

local MF = Merge.Functions
local EXTRA = MF.ExtraSkills
if not EXTRA then
	return
end

local DW, ROBE = EXTRA.Skills.DualWield, EXTRA.Skills.Robe
local floor, max, min = math.floor, math.max, math.min

local S = {
	Attack     = {[0] = -10, -10, -5, 0, 0},
	OffHandMul = {[0] = 0.5, 0.5, 0.75, 1, 1},
	DelayMul   = {[0] = 1.2, 1.2, 1.1, 1, 1},
	RobeACPer  = 0.5,         -- AC per skill point (Novice+)
	RobeRecoveryPer = 0.01,   -- spell recovery per point (Expert+)
	RobeSPMul  = 0.9,         -- Master+
	RobeResPer = 1,           -- resistances per point (Grand Master)
}
MF.DualWieldRobeSettings = S

local WEAPON, WEAPON2H, SHIELD = const.ItemType.Weapon - 1, const.ItemType.Weapon2H - 1, const.ItemType.Shield - 1

local function skill(pl, id)
	local lvl, mas = SplitSkill(MF.GetExtraSkill(pl, id))
	return lvl or 0, mas or 0
end

local function itemNum(pl, slot)
	if slot <= 0 then return end
	local it = pl.Items[slot]
	if it.Number <= 0 or it.Broken then return end
	return it.Number
end

local function isWeapon(num)
	if not num or num <= 0 then return false end
	local es = Game.ItemsTxt[num].EquipStat
	return es == WEAPON or es == WEAPON2H
end
local function isShield(num)
	return num and num > 0 and Game.ItemsTxt[num].EquipStat == SHIELD
end
local function isBlaster(num)
	return num and num > 0 and Game.ItemsTxt[num].Skill == const.Skills.Blaster
end
local function isTwoHanded(num)
	local ok, r = pcall(mem.call, Merge.Offsets.IsItemTwoHand, 1, num)
	if ok then return r ~= 0 end
	return Game.ItemsTxt[num].EquipStat == WEAPON2H
end

---------------------------------------------------------------------------
-- equipping (ItemsModifiers.lua: Req 2 = the left hand, or a two-handed one in one hand)
---------------------------------------------------------------------------

function events.ItemEquipRequirement(t)
	if t.Req ~= 2 or not t.Player then return end
	local num = t.ItemId
	if not isWeapon(num) or isBlaster(num) then return end
	local pl = t.Player
	local _, mas = skill(pl, DW)
	if isTwoHanded(num) then
		-- the other things in play: the hands and the mouse
		local other = {}
		local mouse = mem.i4[0xB7CA64]
		if mouse > 0 and mouse ~= num then other[#other + 1] = mouse end
		local m, e = itemNum(pl, pl.ItemMainHand), itemNum(pl, pl.ItemExtraHand)
		if m and m ~= num then other[#other + 1] = m end
		if e and e ~= num then other[#other + 1] = e end
		local weapon = false
		for _, o in ipairs(other) do
			if isWeapon(o) then weapon = true end
		end
		if weapon then t.Result = mas >= 4 end
	else
		t.Result = mas >= 1
	end
end

---------------------------------------------------------------------------
-- fighting with two weapons
---------------------------------------------------------------------------

-- the weapons of both hands when the character holds one in each (not two blaster pistols)
local function dualWeapons(pl)
	local m, e = itemNum(pl, pl.ItemMainHand), itemNum(pl, pl.ItemExtraHand)
	if not (isWeapon(m) and isWeapon(e)) then return end
	if isBlaster(m) and isBlaster(e) then return end
	return m, e
end
MF.DualWieldWeapons = dualWeapons

local function dwMastery(pl)
	local _, mas = skill(pl, DW)
	return mas
end

local function avgDamage(num)
	local t = Game.ItemsTxt[num]
	return (t.Mod1DiceCount or 0) * ((t.Mod1DiceSides or 0) + 1) / 2 + (t.Mod2 or 0)
end

function events.CalcStatBonusBySkills(t)
	local pl = t.Player
	if not pl then return end
	if t.Stat == const.Stats.MeleeAttack then
		if dualWeapons(pl) then t.Result = t.Result + (S.Attack[dwMastery(pl)] or 0) end
	elseif t.Stat == const.Stats.ArmorClass then
		local lvl, mas = skill(pl, ROBE)
		if mas >= 1 and not itemNum(pl, pl.ItemArmor) then
			t.Result = t.Result + floor(lvl * S.RobeACPer)
		end
	else
		local res = {[const.Stats.FireResistance] = 1, [const.Stats.AirResistance] = 1,
			[const.Stats.WaterResistance] = 1, [const.Stats.EarthResistance] = 1,
			[const.Stats.MindResistance] = 1, [const.Stats.BodyResistance] = 1,
			[const.Stats.SpiritResistance or -1] = 1}
		if res[t.Stat] then
			local lvl, mas = skill(pl, ROBE)
			if mas >= 4 and not itemNum(pl, pl.ItemArmor) then
				t.Result = t.Result + floor(lvl * S.RobeResPer)
			end
		end
	end
end

function events.GetAttackDelay(t)
	if t.Ranged or not t.Player then return end
	if dualWeapons(t.Player) then
		t.Result = floor(t.Result * (S.DelayMul[dwMastery(t.Player)] or 1) + 0.5)
	end
end

-- the off hand's share of a melee blow, by the two weapons' average damage
function events.CalcDamageToMonster(t)
	if not t.ByPlayer or not t.Player or not t.Melee or t.IsSecondary then return end
	if mem.u2[0x51D820] ~= 0 then return end   -- a spell being cast, not a blow
	local m, e = dualWeapons(t.Player)
	if not m then return end
	local mul = S.OffHandMul[dwMastery(t.Player)] or 1
	if mul >= 1 then return end
	local am, ae = avgDamage(m), avgDamage(e)
	if am + ae <= 0 then return end
	t.Result = floor(t.Result * (am + mul * ae) / (am + ae) + 0.5)
end

---------------------------------------------------------------------------
-- Robe: the spells' recovery and cost
---------------------------------------------------------------------------

function events.SpellCostRecovery(t)
	if t.Spell >= 133 then return end
	local pl = Party[max(0, t.Caster - 35)]   -- as SpellsExtra.lua finds the caster
	if not pl or itemNum(pl, pl.ItemArmor) then return end
	local lvl, mas = skill(pl, ROBE)
	if mas >= 2 then
		t.Recovery = floor(t.Recovery * max(0.5, 1 - lvl * S.RobeRecoveryPer) + 0.5)
	end
	if mas >= 3 then
		t.Cost = floor(t.Cost * S.RobeSPMul + 0.5)
	end
end
