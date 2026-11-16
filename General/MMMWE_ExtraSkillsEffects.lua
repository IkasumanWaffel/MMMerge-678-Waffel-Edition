--[[
	MMMWE_ExtraSkillsEffects.lua — what the new skills Dual-Wield and Robe do (07.11.26)
	(the skills themselves: MMMWE_ExtraSkills.lua)

	Dual-Wield (41)
	  A weapon in the off hand needs the skill (any mastery), whatever its kind: the Sword and
	  Dagger Master rule of ItemsExtra.txt (Equip2Req) is replaced for weapons. Blaster pistols
	  keep their own rule (MMMWE_Blasters.lua). A two-handed weapon next to another weapon
	  needs Grand Master; next to a shield or alone, the table's rule stays (Spear Master).
	  Holding a weapon in each hand (not a pair of blaster pistols):
	    Attack -10 + 1 per point of skill, at any mastery (08.11.26)
	    Novice (or none, for weapons put on before the rule): the off hand's damage halved,
	      recovery +20%
	    Expert: off hand 75%, recovery +10%
	    Master, Grand Master: no penalties
	    A two-handed weapon in each hand (Grand Master): off hand 75%, recovery +20%; none
	      for a Legendary Dual-Wield
	Robe (42), while no body armor is worn or a robe is (15.11.26: robes, items 2250-2256,
	  Items.txt Skill Group Misc, ItemSubtypes 42; wearing one needs the Robe skill):
	    Novice: +1 AC per skill point (Master 1.5, Grand Master 2; it was 1 per 2 points)
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
	-- (08.11.26) Attack with a weapon in each hand: AttackBase + AttackPerPoint x skill
	-- (-10 at 0, 0 at 10, +10 at 20), at any mastery
	AttackBase     = -10,
	AttackPerPoint = 1,
	OffHandMul = {[0] = 0.5, 0.5, 0.75, 1, 1},
	DelayMul   = {[0] = 1.2, 1.2, 1.1, 1, 1},
	-- (08.11.26) a two-handed weapon in each hand (Grand Master): these on top; none for a
	-- Legendary Dual-Wield (MMMWE_LegendaryPassives.lua)
	PairedTwoHandedOffHandMul = 0.75,
	PairedTwoHandedDelayMul   = 1.2,
	RobeACPer  = {[0] = 0, 1, 1, 1.5, 2},   -- AC per skill point by rank (15.11.26; was 0.5)
	RobeRecoveryPer = 0.01,   -- spell recovery per point (Expert+)
	RobeSPMul  = 0.9,         -- Master+
	RobeResPer = 1,           -- resistances per point (Grand Master)
	RobeStoneskinMul = 1.5,   -- Stone Skin's physical resistance in a robe and no other armor (15.11.26)
	RobeStoneskinCap = 0.75,  -- ... but never above this
}
MF.DualWieldRobeSettings = S

local WEAPON, WEAPON2H, SHIELD = const.ItemType.Weapon - 1, const.ItemType.Weapon2H - 1, const.ItemType.Shield - 1

local function skill(pl, id)
	local lvl, mas = SplitSkill(MF.GetExtraSkill(pl, id))
	return lvl or 0, mas or 0
end

-- robes (15.11.26): body armor of the Robe skill, worn as clothes
local ROBES = {[2250] = 1, [2251] = 2, [2252] = 3, [2253] = 4, [2254] = 5, [2255] = 6, [2256] = 7}
MF.Robes = ROBES
function MF.IsRobe(num) return ROBES[num] ~= nil end

local function itemNum(pl, slot)
	if slot <= 0 then return end
	local it = pl.Items[slot]
	if it.Number <= 0 or it.Broken then return end
	return it.Number
end

-- no body armor, or a robe: the Robe skill works
function MF.RobeClothed(pl)
	local num = itemNum(pl, pl.ItemArmor)
	return not num or ROBES[num] ~= nil
end

-- a robe and no other armor: no gauntlets, belt or boots, and in the helm slot only a hat or
-- a crown (ItemSubtypes 32, 33); a cloak and a shield do not count. Stone Skin then gives
-- RobeStoneskinMul times its physical resistance (15.11.26). Stone Skin's power is armor class
-- sized so that an unarmored character gets the spell's resistance p:
-- damage x (205 - h) / (210 - h + AC), AC = (210p - 5) / (1 - p)  (SpellsExtra.lua, MMMWE_Main.lua)
local HEADWEAR = {[32] = true, [33] = true}
local function subtype(num)
	local mt = Merge.Tables; local e = mt and mt.ItemsExtra and mt.ItemsExtra[num]
	return e and e.Subtype or 0
end
-- (16.11.26) most hats and crowns leave ItemsExtra's Subtype empty: their unidentified name tells
local function isHeadwear(num)
	if HEADWEAR[subtype(num)] then return true end
	local n = string.lower(Game.ItemsTxt[num].NotIdentifiedName or "")
	return n:find("hat") ~= nil or n:find("cap") ~= nil or n:find("crown") ~= nil
end
function MF.RobeOnlyArmor(pl)
	local num = itemNum(pl, pl.ItemArmor)
	if not num or not ROBES[num] then return false end
	if itemNum(pl, pl.ItemGauntlets) or itemNum(pl, pl.ItemBelt) or itemNum(pl, pl.ItemBoots) then
		return false
	end
	local helm = itemNum(pl, pl.ItemHelm)
	return not helm or isHeadwear(helm)
end
local function acOf(p) return (210 * p - 5) / (1 - p) end
local function resOf(ac) return (ac + 5) / (ac + 210) end
function MF.RobeStoneskinExtra(pl)
	local b = pl.SpellBuffs[const.PlayerBuff.Stoneskin]
	if not b or b.ExpireTime <= Game.Time or b.Power <= 0 or not MF.RobeOnlyArmor(pl) then return 0 end
	local p = math.min(S.RobeStoneskinCap, resOf(b.Power) * S.RobeStoneskinMul)
	return math.max(0, math.ceil(acOf(p) - b.Power))
end
function events.CalcStatBonusByMagic(t)
	if t.Stat ~= const.Stats.ArmorClass or not t.Player then return end
	t.Result = t.Result + MF.RobeStoneskinExtra(t.Player)
end

-- a robe needs the Robe skill (ItemsExtra.txt EquipReq "1" lets everyone else through)
function events.ItemEquipRequirement(t)
	if t.Req ~= 1 or not t.Player or not ROBES[t.ItemId] then return end
	local _, mas = skill(t.Player, ROBE)
	t.Result = mas >= 1
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
		-- the other things in play: the hands and the mouse, without the item itself (one
		-- copy of it: an identical second copy counts as the other weapon, 08.11.26)
		local other = {}
		local mouse = mem.i4[0xB7CA64]
		local inPlay = {mouse > 0 and mouse or nil, itemNum(pl, pl.ItemMainHand), itemNum(pl, pl.ItemExtraHand)}
		local self = false
		for i = 1, 3 do
			local n = inPlay[i]
			if n then
				if n == num and not self then self = true else other[#other + 1] = n end
			end
		end
		local weapon = false
		for _, o in ipairs(other) do
			if isWeapon(o) then weapon = true end
		end
		if weapon then t.Result = mas >= 4 end
	else
		t.Result = mas >= 1
	end
end

-- (08.11.26) the game puts a two-handed weapon (Equip Stat 1) only in the right hand; at Grand
-- Master it goes the one-handed way instead (0x46770E): to the left hand when dropped on
-- the left half of the doll, or in place of the right-hand weapon with the left one kept.
-- At 0x4674F8 the item's Equip Stat ([ebp-8]) picks the way; ebx is the player.
mem.autohook(0x4674F8, function(d)
	if mem.i4[d.ebp - 8] ~= 1 then return end
	local num = mem.i4[0xB7CA64]
	if not isWeapon(num) or isBlaster(num) then return end
	local pl = MF.GetPlayerFromPtr(d.ebx)
	if pl and select(2, skill(pl, DW)) >= 4 then
		mem.i4[d.ebp - 8] = 0
	end
end)

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

-- two two-handed weapons, and Dual-Wield not Legendary
local function pairedTwoHanded(pl)
	local m, e = dualWeapons(pl)
	if not (m and isTwoHanded(m) and isTwoHanded(e)) then return false end
	return not (MF.IsLegendary and MF.IsLegendary(pl, DW))
end
MF.DualWieldPairedTwoHanded = pairedTwoHanded

local function avgDamage(num)
	local t = Game.ItemsTxt[num]
	return (t.Mod1DiceCount or 0) * ((t.Mod1DiceSides or 0) + 1) / 2 + (t.Mod2 or 0)
end

function events.CalcStatBonusBySkills(t)
	local pl = t.Player
	if not pl then return end
	if t.Stat == const.Stats.MeleeAttack then
		if dualWeapons(pl) then
			local lvl = skill(pl, DW)
			t.Result = t.Result + S.AttackBase + S.AttackPerPoint * lvl
		end
	elseif t.Stat == const.Stats.ArmorClass then
		local lvl, mas = skill(pl, ROBE)
		if mas >= 1 and MF.RobeClothed(pl) then
			t.Result = t.Result + floor(lvl * (S.RobeACPer[mas] or 1))
		end
	end
end

-- Grand Master Robe: Fire, Air, Water, Earth, Spirit, Mind and Body resistance (16.11.26: through
-- GetRaceClassResistance, as Diamond Body does; the game never asks CalcStatBonusBySkills for them)
local ROBE_RES = {[0] = true, [1] = true, [2] = true, [3] = true, [6] = true, [7] = true, [8] = true}
function MF.RobeResBonus(pl)
	local lvl, mas = skill(pl, ROBE)
	if mas >= 4 and MF.RobeClothed(pl) then return floor(lvl * S.RobeResPer) end
	return 0
end
function events.GetRaceClassResistance(t)
	if t.Player and ROBE_RES[t.Resistance] then
		t.Result = t.Result + MF.RobeResBonus(t.Player)
	end
end

function events.GetAttackDelay(t)
	if t.Ranged or not t.Player then return end
	if dualWeapons(t.Player) then
		local mul = S.DelayMul[dwMastery(t.Player)] or 1
		if pairedTwoHanded(t.Player) then mul = mul * S.PairedTwoHandedDelayMul end
		t.Result = floor(t.Result * mul + 0.5)
	end
end

-- (13.11.26) the stats screen's melee damage range shows the off hand's share too: the off-hand
-- weapon's own dice and bonus count only by its share (the blow itself: below)
local function offHandMul(pl)
	local mul = S.OffHandMul[dwMastery(pl)] or 1
	if pairedTwoHanded(pl) then mul = mul * S.PairedTwoHandedOffHandMul end
	return mul
end
MF.DualWieldOffHandMul = function(pl) return dualWeapons(pl) and offHandMul(pl) or 1 end

function events.CalcStatBonusByItems(t)
	local st = const.Stats
	if t.Stat ~= st.MeleeDamageMin and t.Stat ~= st.MeleeDamageMax then return end
	local pl = t.Player
	if not pl then return end
	local m, e = dualWeapons(pl)
	if not m then return end
	local mul = offHandMul(pl)
	if mul >= 1 then return end
	local txt = Game.ItemsTxt[e]
	local n, sides, add = txt.Mod1DiceCount or 0, txt.Mod1DiceSides or 0, txt.Mod2 or 0
	local dmg = (t.Stat == st.MeleeDamageMin and n or n * sides) + add
	t.Result = t.Result - floor(dmg * (1 - mul) + 0.5)
end

-- the off hand's share of a melee blow, by the two weapons' average damage
function events.CalcDamageToMonster(t)
	if not t.ByPlayer or not t.Player or not t.Melee or t.IsSecondary then return end
	if mem.u2[0x51D820] ~= 0 then return end   -- a spell being cast, not a blow
	local m, e = dualWeapons(t.Player)
	if not m then return end
	local mul = offHandMul(t.Player)
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
	if not pl or not MF.RobeClothed(pl) then return end
	local lvl, mas = skill(pl, ROBE)
	if mas >= 2 then
		t.Recovery = floor(t.Recovery * max(0.5, 1 - lvl * S.RobeRecoveryPer) + 0.5)
	end
	if mas >= 3 then
		t.Cost = floor(t.Cost * S.RobeSPMul + 0.5)
	end
end
