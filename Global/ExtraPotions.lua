local MV, MF = Merge.Vars, Merge.Functions
vars.PotionBuffs = vars.PotionBuffs or {}
local PSet	= vars.PotionBuffs
PSet.UsedPotions = PSet.UsedPotions or {}

-- regeneration potions: the amount of each 5-minute step is paid out a fifth per game
-- minute with fractions (MMMWE_Main.lua, MF.RegenGive); without it, at once as before
local function potionGive(pl, hp, sp)
	if MF.RegenGive then
		MF.RegenGive(pl, hp, sp)
	else
		if hp and hp > 0 then pl.HP = math.min(pl:GetFullHP(), pl.HP + math.floor(hp)) end
		if sp and sp > 0 then pl.SP = math.min(pl:GetFullSP(), pl.SP + math.floor(sp)) end
	end
end

---------------------------------------------------------------------------
-- MMMWE (11.11.26): the common limits of the potions
--   POTION_MAX_MINUTES  no potion's effect lasts longer (12 hours)
--   MASTER_CAP          the most a potion adds to a statistic or a resistance for a time
--                       (the boosts, the resistances, the Divine potions: 3 per point of
--                       potion strength, reached at strength 50)
--   MINOR_POWER         what the Expert ("minor") potions add: a fixed amount for
--                       MINOR_BASE minutes + MINOR_PER per point of strength
--   PURE_DIV, PURE_STAT_MAX, PURE_RES_MAX   the black "Pure" potions: + strength /
--                       PURE_DIV for good, as many times as one likes, until the
--                       statistic's (resistance's) own value reaches the maximum
---------------------------------------------------------------------------
local POTION_MAX_MINUTES = 12 * 60
local MASTER_CAP    = 150
local MINOR_POWER   = 25
local MINOR_BASE    = 60
local MINOR_PER     = 5
local PURE_DIV      = 4
local PURE_STAT_MAX = 150
local PURE_RES_MAX  = 100
local Tx = Merge.Functions.Text or function(s) return s end
local PotionMessage      -- a status line shown after the game's own

local function potionMinutes(minutes)
	return const.Minute * math.min(minutes, POTION_MAX_MINUTES)
end
MF.PotionMaxMinutes = POTION_MAX_MINUTES
MF.PotionMasterCap = MASTER_CAP

-- The potions the game itself handles (Shield, Water Breathing, the Master boosts and
-- resistances): the drinker's buffs are noted before the game applies the potion, and on
-- the next tick the buffs it changed are brought within the limits.
local Limited            -- {Player = index, Before = {[buff] = {ExpireTime, Power}}}
local CAPPED_POWER = {}
for _, n in ipairs{"TempMight", "TempIntellect", "TempPersonality", "TempEndurance", "TempSpeed",
		"TempAccuracy", "TempLuck", "FireResistance", "AirResistance", "WaterResistance",
		"EarthResistance", "MindResistance", "BodyResistance"} do
	CAPPED_POWER[const.PlayerBuff[n]] = true
end

local function limitGamePotion(IsDrunk, Target)
	if not IsDrunk then return end
	local before = {}
	for i, b in Target.SpellBuffs do
		before[i] = {b.ExpireTime, b.Power}
	end
	Limited = {Player = Target:GetIndex(), Before = before}
end
for _, id in ipairs{12, 15, 20, 21, 22, 23, 24, 25, 35, 36, 37, 38, 39, 40, 41} do
	evt.PotionEffects[id] = limitGamePotion
end

function events.Tick()
	if PotionMessage then
		Game.ShowStatusText(PotionMessage)
		PotionMessage = nil
	end
	if Limited then
		local l = Limited
		Limited = nil
		local pl = Party.PlayersArray[l.Player]
		local latest = Game.Time + potionMinutes(POTION_MAX_MINUTES)
		for i, b in pl.SpellBuffs do
			local was = l.Before[i]
			if was and (b.ExpireTime ~= was[1] or b.Power ~= was[2]) then
				if b.ExpireTime > latest then b.ExpireTime = latest end
				if CAPPED_POWER[i] and b.Power > MASTER_CAP then b.Power = MASTER_CAP end
			end
		end
	end
end

local HPPotionTimers = {}
local SPPotionTimers = {}
local DCPotionTimers = {}
local DPPotionTimers = {}

local function GetPlayerId(Player)
	return Player:GetIndex()
end

local function GetPartyId(Player)
	for i, v in Party do
		if v['?ptr'] == Player['?ptr'] then
			return i
		end
	end
end

-- Rejuvenation potion
evt.PotionEffects[51] = function(IsDrunk, Target, Power)
	if IsDrunk then
		if Target.AgeBonus <= 0 then
			Target.AgeBonus = Target.AgeBonus - math.ceil(Power/10)
			return true
		end
	end
end

-- Divine boost
evt.PotionEffects[60] = function(IsDrunk, Target, Power)
	if IsDrunk then
		local Buffs = Target.SpellBuffs
		local ExpireTime = Game.Time + potionMinutes(Power*30)
		local Effect = math.min(Power*3, MASTER_CAP)

		for k,v in pairs({"TempLuck", "TempIntellect", "TempPersonality", "TempAccuracy", "TempEndurance", "TempSpeed", "TempMight"}) do
			Buff = Buffs[const.PlayerBuff[v]]
			Buff.ExpireTime = ExpireTime
			Buff.Power = Effect
		end
	end
end

-- Divine protection
evt.PotionEffects[61] = function(IsDrunk, Target, Power)
	if IsDrunk then
		local Buffs = Target.SpellBuffs
		local ExpireTime = Game.Time + potionMinutes(Power*30)
		local Effect = math.min(Power*3, MASTER_CAP)

		for k,v in pairs({"AirResistance", "BodyResistance", "EarthResistance", "FireResistance", "MindResistance", "WaterResistance"}) do
			Buff = Buffs[const.PlayerBuff[v]]
			Buff.ExpireTime = ExpireTime
			Buff.Power = Effect
		end
	end
end

-- Divine Transcendence
evt.PotionEffects[62] = function(IsDrunk, Target, Power)
	if IsDrunk then
		local PlayerId = GetPartyId(Target)
		evt[PlayerId].Add{"LevelBonus", 20}
	end
end

-- Essences
local function EssenseOf(Target, Stat, cStat, ItemId)
	local PlayerId = GetPlayerId(Target)
	PSet.UsedPotions[PlayerId] = PSet.UsedPotions[PlayerId] or {}

	local t = PSet.UsedPotions[PlayerId]
	if t[ItemId] then
		return -1
	else
		t[ItemId] = true
		Target[Stat]  = Target[Stat] + 15
		Target[cStat] = Target[cStat] - 5
		return true
	end
end

-- Essence of Might
evt.PotionEffects[52] = function(IsDrunk, Target, Power, ItemId)
	if IsDrunk then
		return EssenseOf(Target, "MightBase", "IntellectBase", ItemId)
	end
end

-- Essence of Intellect
evt.PotionEffects[53] = function(IsDrunk, Target, Power, ItemId)
	if IsDrunk then
		return EssenseOf(Target, "IntellectBase", "MightBase", ItemId)
	end
end

-- Essence of Personality
evt.PotionEffects[54] = function(IsDrunk, Target, Power, ItemId)
	if IsDrunk then
		return EssenseOf(Target, "PersonalityBase", "SpeedBase", ItemId)
	end
end

-- Essence of Endurance
evt.PotionEffects[55] = function(IsDrunk, Target, Power, ItemId)
	if IsDrunk then
		local PlayerId = GetPlayerId(Target)
		PSet.UsedPotions[PlayerId] = PSet.UsedPotions[PlayerId] or {}
		local t = PSet.UsedPotions[PlayerId]

		if t[ItemId] then
			return -1
		else
			t[ItemId] = true
			Target.MightBase		= Target.MightBase - 1
			Target.IntellectBase	= Target.IntellectBase - 1
			Target.PersonalityBase	= Target.PersonalityBase - 1
			Target.AccuracyBase		= Target.AccuracyBase - 1
			Target.SpeedBase		= Target.SpeedBase - 1
			Target.LuckBase			= Target.LuckBase - 1
			Target.EnduranceBase	= Target.EnduranceBase + 15
		end
	end
end

-- Essence of Accuracy
evt.PotionEffects[56] = function(IsDrunk, Target, Power, ItemId)
	if IsDrunk then
		return EssenseOf(Target, "AccuracyBase", "LuckBase", ItemId)
	end
end

-- Essence of Speed
evt.PotionEffects[57] = function(IsDrunk, Target, Power, ItemId)
	if IsDrunk then
		return EssenseOf(Target, "SpeedBase", "PersonalityBase", ItemId)
	end
end

-- Essence of Luck
evt.PotionEffects[58] = function(IsDrunk, Target, Power, ItemId)
	if IsDrunk then
		return EssenseOf(Target, "LuckBase", "AccuracyBase", ItemId)
	end
end

-- Potion of the Gods
evt.PotionEffects[63] = function(IsDrunk, Target, Power, ItemId)
	if IsDrunk then
		local PlayerId = GetPlayerId(Target)
		PSet.UsedPotions[PlayerId] = PSet.UsedPotions[PlayerId] or {}
		if PSet.UsedPotions[PlayerId][ItemId] then
			return -1
		else
			PSet.UsedPotions[PlayerId][ItemId] = true

			local Stats = Target.Stats
			for i = 0, 6 do
				Stats[i].Base = Stats[i].Base + 20
			end
			Target.AgeBonus = Target.AgeBonus + 10
		end
	end
end

-- Potion of Doom
evt.PotionEffects[59] = function(IsDrunk, Target, Power)
	if IsDrunk then
		Target.MightBase		= Target.MightBase + 1
		Target.IntellectBase	= Target.IntellectBase + 1
		Target.PersonalityBase	= Target.PersonalityBase + 1
		Target.EnduranceBase	= Target.EnduranceBase + 1
		Target.AccuracyBase		= Target.AccuracyBase + 1
		Target.SpeedBase		= Target.SpeedBase + 1
		Target.LuckBase			= Target.LuckBase + 1

		for i,v in Target.Resistances do
			v.Base = v.Base + 1
		end
		Target.AgeBonus = Target.AgeBonus + 5
	end
end

-- Minor potions and Spirit Resistance (MMMWE 11.11.26)
--   73 (item 293)       Spirit Resistance, Master, as the other six: +3 per point of potion
--                       strength (MASTER_CAP at most) for 30 minutes per point
--   74..79 (294..299)   Minor Fire / Air / Water / Earth / Mind / Body Resistance, Expert
--   80..86 (1022..1028) Minor Might / Intellect / Personality / Endurance / Speed /
--                       Accuracy / Luck Boost, Expert
-- The minor potions add MINOR_POWER for MINOR_BASE minutes + MINOR_PER per point of
-- strength. A minor potion isn't drunk while a stronger effect of its kind is active (it
-- would replace it). The Spirit bonus is kept in vars.MMMWE_SpiritPotion[player] =
-- {Expire, Power} and added by SpellsExtra.lua (the larger of it and Preservation's).
local function MinorPotion(Target, BuffName, Power)
	local Buff = Target.SpellBuffs[const.PlayerBuff[BuffName]]
	if Buff.ExpireTime > Game.Time and Buff.Power > MINOR_POWER then
		PotionMessage = Tx"A stronger effect of this kind is already active"
		return -1
	end
	Buff.ExpireTime = Game.Time + potionMinutes(MINOR_BASE + MINOR_PER*math.max(Power or 1, 1))
	Buff.Power = MINOR_POWER
	Buff.Skill = 1
	Buff.OverlayId = 0
end

for id, name in pairs{[74] = "FireResistance", [75] = "AirResistance", [76] = "WaterResistance",
		[77] = "EarthResistance", [78] = "MindResistance", [79] = "BodyResistance",
		[80] = "TempMight", [81] = "TempIntellect", [82] = "TempPersonality", [83] = "TempEndurance",
		[84] = "TempSpeed", [85] = "TempAccuracy", [86] = "TempLuck"} do
	evt.PotionEffects[id] = function(IsDrunk, Target, Power)
		if IsDrunk then return MinorPotion(Target, name, Power) end
	end
end

-- Spirit Resistance
evt.PotionEffects[73] = function(IsDrunk, Target, Power)
	if IsDrunk then
		Power = math.max(Power or 1, 1)
		vars.MMMWE_SpiritPotion = vars.MMMWE_SpiritPotion or {}
		vars.MMMWE_SpiritPotion[Target:GetIndex()] = {Expire = Game.Time + potionMinutes(30*Power),
			Power = math.min(3*Power, MASTER_CAP)}
	end
end

-- The Pure potions (black): for good, + strength / PURE_DIV, as many times as one likes
-- until the value itself reaches the maximum (before: +50 / +40, once for a character)
local function PureGain(now, Power, most)
	if now >= most then
		PotionMessage = Tx"Potions can't raise this any higher"
		return
	end
	return math.min(math.max(1, math.floor(math.max(Power or 1, 1) / PURE_DIV)), most - now)
end

for id, stat in pairs{[44] = "LuckBase", [45] = "SpeedBase", [46] = "IntellectBase", [47] = "EnduranceBase",
		[48] = "PersonalityBase", [49] = "AccuracyBase", [50] = "MightBase"} do
	evt.PotionEffects[id] = function(IsDrunk, Target, Power)
		if not IsDrunk then return end
		local gain = PureGain(Target[stat], Power, PURE_STAT_MAX)
		if not gain then return -1 end
		Target[stat] = Target[stat] + gain
		return true
	end
end

local function PureResistance(Target, Stat, Power)
	local res = Target.Resistances[Stat]
	local gain = PureGain(res.Base, Power, PURE_RES_MAX)
	if not gain then return -1 end
	res.Base = res.Base + gain
end

evt.PotionEffects[64] = function(IsDrunk, Target, Power) if IsDrunk then return PureResistance(Target, 0, Power) end end
evt.PotionEffects[65] = function(IsDrunk, Target, Power) if IsDrunk then return PureResistance(Target, 1, Power) end end
evt.PotionEffects[66] = function(IsDrunk, Target, Power) if IsDrunk then return PureResistance(Target, 2, Power) end end
evt.PotionEffects[67] = function(IsDrunk, Target, Power) if IsDrunk then return PureResistance(Target, 3, Power) end end
evt.PotionEffects[68] = function(IsDrunk, Target, Power) if IsDrunk then return PureResistance(Target, 7, Power) end end
evt.PotionEffects[69] = function(IsDrunk, Target, Power) if IsDrunk then return PureResistance(Target, 8, Power) end end

-- Protection from Magic
evt.PotionEffects[70] = function(IsDrunk, Target, Power)
	if IsDrunk then
		local AS, AM = SplitSkill(Target:GetSkill(const.Skills.Alchemy))
		local Buff = Party.SpellBuffs[const.PartyBuff.ProtectionFromMagic]
		Buff.ExpireTime = Game.Time + const.Minute*120*math.max(1,AM)
		Buff.Power = math.max(1,AM)+1
		Buff.Skill = JoinSkill(10,4)
		Buff.OverlayId = 0
	end
end

local potionSpellSkill

-- Heroism (as Bless and Stoneskin below: +15 damage, +1 per point of the spell's skill)
evt.PotionEffects[9] = function(IsDrunk, Target, Power)
	if IsDrunk then
		local ind = Target:GetSlot()
		local rid = Target:GetIndex()
		CastSpellDirect(51, potionSpellSkill(Power), 1, rid, ind) -- Heroism
		return true
	end
end

-- Bless and Stoneskin (MMMWE 10.11.26): by their spells at the Expert rank, the rank of
-- Alchemy the potions take to brew, for the drinker alone. The spell's skill is
-- potion strength / POTION_SPELL_DIV (rounded up, POTION_SPELL_MAX at most):
--   Heroism    +15 damage, +1 per point of that skill          (the spell at Expert)
--   Bless      +10 attack, +1 per point of that skill          (the spell at Expert)
--   Stoneskin  15% physical resistance, +1% per point of skill (the spell at Expert)
--   duration   1 hour 25 minutes + 5 minutes per point of skill
-- The spell is cast at the Novice rank (one target) with 5 more points of skill, which
-- gives the Expert rank's numbers: Novice Bless is 5 + skill, Novice Stone Skin 10% + skill,
-- Novice Heroism 10 + skill.
-- Before, the skill was 5 * sqrt(strength) with nothing taken off: stronger than a Grand
-- Master's spell from strength 50 on, and Stone Skin's formula broke past strength 300.
local POTION_SPELL_DIV = 5
local POTION_SPELL_MAX = 50
local POTION_SPELL_RANK = 5   -- skill points that make up for the rank: Expert over Novice

function potionSpellSkill(Power)
	local k = math.ceil(math.max(Power or 1, 1) / POTION_SPELL_DIV)
	return math.min(k, POTION_SPELL_MAX) + POTION_SPELL_RANK
end

-- Bless
evt.PotionEffects[10] = function(IsDrunk, Target, Power)
	if IsDrunk then
		local ind = Target:GetSlot()
		local rid = Target:GetIndex()
		CastSpellDirect(46, potionSpellSkill(Power), 1, rid, ind) -- Bless
		return true
	end
end

-- Stoneskin
evt.PotionEffects[14] = function(IsDrunk, Target, Power)
	if IsDrunk then
		local ind = Target:GetSlot()
		local rid = Target:GetIndex()
		CastSpellDirect(38, potionSpellSkill(Power), 1, rid, ind) -- Stoneskin
		return true
	end
end

-- Haste
evt.PotionEffects[8] = function(IsDrunk, Target, Power)
	if IsDrunk then
		local ind = Target:GetSlot()
		local BP = 5 * math.ceil(math.sqrt(Power))
		local rid = Target:GetIndex()
		CastSpellDirect(5, BP, 1, rid, ind) -- Haste
		return true
	end
end


MV.PotionHPReg = {0,0,0,0,0}
MV.PotionSPReg = {0,0,0,0,0}

-- Cure Wounds
function events.AfterLoadMap()
	for _,pl in Party do
		local slot = pl:GetSlot() + 1
		local SpellBuff = Game.PlayersExtra[pl:GetIndex()].SpellBuffs2

		-- HP regen
		if SpellBuff[31].ExpireTime <= Game.Time then
			MV.PotionHPReg[slot] = 0
		else
			local Time = SpellBuff[31].ExpireTime
			local Power = SpellBuff[31].Power
			local Cond = pl:GetMainCondition()
			local key = "HP_" .. slot
			if HPPotionTimers[key] then
				RemoveTimer(HPPotionTimers[key])
			end
			HPPotionTimers[key] = function()
				local Cond = pl:GetMainCondition()
				if Game.Time > Time then
					RemoveTimer(HPPotionTimers[key])
					HPPotionTimers[key] = nil
					MV.PotionHPReg[slot] = 0
				elseif Cond >= 17 or Cond < 14 then
					MV.PotionHPReg[slot] = Power
					local FHP = pl:GetFullHP()
					potionGive(pl, Power, 0)
					if pl.HP > 0 and pl.Conditions[13] > 0 then pl.Conditions[13] = 0 end
				else
					MV.PotionHPReg[slot] = 0
				end
			end
			Timer(HPPotionTimers[key], const.Minute*5, true)
		end

		-- SP regen
		if SpellBuff[32].ExpireTime <= Game.Time then
			MV.PotionSPReg[slot] = 0
		else
			local Time = SpellBuff[32].ExpireTime
			local Power = SpellBuff[32].Power
			local Cond = pl:GetMainCondition()
			local key = "SP_" .. slot
			if SPPotionTimers[key] then
				RemoveTimer(SPPotionTimers[key])
			end
			SPPotionTimers[key] = function()
				local Cond = pl:GetMainCondition()
				if Game.Time > Time then
					RemoveTimer(SPPotionTimers[key])
					SPPotionTimers[key] = nil
					MV.PotionSPReg[slot] = 0
				elseif Cond >= 17 or Cond < 14 then
					MV.PotionSPReg[slot] = Power
					local FSP = pl:GetFullSP()
					potionGive(pl, 0, Power)
				else
					MV.PotionSPReg[slot] = 0
				end
			end
			Timer(SPPotionTimers[key], const.Minute*5, true)
		end
	end
end

evt.PotionEffects[2] = function(IsDrunk, Target, Power)
	if not IsDrunk then return end
	local slot = Target:GetSlot() + 1
	local key = "HP_" .. slot
	local Time = Game.Time + const.Hour
	local Pl = Target

	-- Не заменяем, если текущий баф длится дольше
	local existingBuff = Game.PlayersExtra[Target:GetIndex()].SpellBuffs2[31]
	if existingBuff and existingBuff.ExpireTime > Time then return end

	local RegenHP = Power
	local RegenCap = Target.LevelBase + 4

	if HPPotionTimers[key] then
		RemoveTimer(HPPotionTimers[key])
		HPPotionTimers[key] = nil
	end

	HPPotionTimers[key] = function()
		local Cond = Pl:GetMainCondition()
		if Game.Time > Time then
			RemoveTimer(HPPotionTimers[key])
			HPPotionTimers[key] = nil
			MV.PotionHPReg[slot] = 0
		elseif Cond >= 17 or Cond < 14 then
			MV.PotionHPReg[slot] = math.min(RegenHP, RegenCap)
			local FHP = Pl:GetFullHP()
			potionGive(Pl, math.min(RegenHP, RegenCap), 0)
			if Pl.HP > 0 and Pl.Conditions[13] > 0 then Pl.Conditions[13] = 0 end
			local Buff = Game.PlayersExtra[Target:GetIndex()].SpellBuffs2[31]
			Buff.ExpireTime = Time
			Buff.Power = math.floor(MV.PotionHPReg[slot])
		else
			MV.PotionHPReg[slot] = 0
		end
	end
	Timer(HPPotionTimers[key], const.Minute * 5, true)
end


evt.PotionEffects[3] = function(IsDrunk, Target, Power)
	if not IsDrunk then return end
	local slot = Target:GetSlot() + 1
	local key = "SP_" .. slot
	local Time = Game.Time + const.Hour
	local Pl = Target

	-- Не заменяем, если текущий баф длится дольше
	local existingBuff = Game.PlayersExtra[Target:GetIndex()].SpellBuffs2[32]
	if existingBuff and existingBuff.ExpireTime > Time then return end

	local RegenSP = Power
	local RegenCap = Target.LevelBase / 4 + 1

	if SPPotionTimers[key] then
		RemoveTimer(SPPotionTimers[key])
		SPPotionTimers[key] = nil
	end

	SPPotionTimers[key] = function()
		local Cond = Pl:GetMainCondition()
		if Game.Time > Time then
			RemoveTimer(SPPotionTimers[key])
			SPPotionTimers[key] = nil
			MV.PotionSPReg[slot] = 0
		elseif Cond >= 17 or Cond < 14 then
			MV.PotionSPReg[slot] = math.min(RegenSP, RegenCap)
			local FSP = Pl:GetFullSP()
			potionGive(Pl, 0, math.min(RegenSP, RegenCap))
			local Buff = Game.PlayersExtra[Target:GetIndex()].SpellBuffs2[32]
			Buff.ExpireTime = Time
			Buff.Power = math.floor(MV.PotionSPReg[slot])
		else
			MV.PotionSPReg[slot] = 0
		end
	end
	Timer(SPPotionTimers[key], const.Minute * 5, true)
end



-- Cure Weakness
evt.PotionEffects[4] = function(IsDrunk, Target, Power)
	if IsDrunk then
		local Pl = Target
		local Cond = Pl:GetMainCondition()
		if Cond == 4 then
			Pl.Conditions[4] = 0
		end
	end
end

-- Cure Disease
evt.PotionEffects[5] = function(IsDrunk, Target, Power)
	if IsDrunk then
		Game.PlayersExtra[Target:GetIndex()].Debuffs[7].ExpireTime = 0
		Game.PlayersExtra[Target:GetIndex()].Debuffs[9].ExpireTime = 0
		Game.PlayersExtra[Target:GetIndex()].Debuffs[11].ExpireTime = 0
		Game.PlayersExtra[Target:GetIndex()].Debuffs[17].ExpireTime = 0
	end
end

-- Cure Poison
evt.PotionEffects[6] = function(IsDrunk, Target, Power)
	if IsDrunk then
		Game.PlayersExtra[Target:GetIndex()].Debuffs[6].ExpireTime = 0
		Game.PlayersExtra[Target:GetIndex()].Debuffs[8].ExpireTime = 0
		Game.PlayersExtra[Target:GetIndex()].Debuffs[10].ExpireTime = 0
	end
end

-- Cure Insanity
evt.PotionEffects[19] = function(IsDrunk, Target, Power)
	if IsDrunk then
		Game.PlayersExtra[Target:GetIndex()].Debuffs[5].ExpireTime = 0
		Game.PlayersExtra[Target:GetIndex()].Debuffs[18].ExpireTime = 0
	end
end

-- Divine Restoration
evt.PotionEffects[32] = function(IsDrunk, Target, Power)
	if IsDrunk then
		for i = 1,13 do
			Game.PlayersExtra[Target:GetIndex()].Debuffs[i-1].ExpireTime = 0
		end
		Game.PlayersExtra[Target:GetIndex()].Debuffs[17].ExpireTime = 0
		Game.PlayersExtra[Target:GetIndex()].Debuffs[18].ExpireTime = 0
	end
end

evt.PotionEffects[33] = function(IsDrunk, Target, Power)
	if not IsDrunk then return end
	local slot = Target:GetSlot() + 1
	local key = "HP_" .. slot
	local Time = Game.Time + const.Hour * 2
	local Pl = Target

	-- Не заменяем, если текущий баф длится дольше
	local existingBuff = Game.PlayersExtra[Target:GetIndex()].SpellBuffs2[31]
	if existingBuff and existingBuff.ExpireTime > Time then return end

	local RegenHP = Power * 1.5
	local RegenCap = Target.LevelBase + 7

	if HPPotionTimers[key] then
		RemoveTimer(HPPotionTimers[key])
		HPPotionTimers[key] = nil
	end

	HPPotionTimers[key] = function()
		local Cond = Pl:GetMainCondition()
		if Game.Time > Time then
			RemoveTimer(HPPotionTimers[key])
			HPPotionTimers[key] = nil
			MV.PotionHPReg[slot] = 0
		elseif Cond >= 17 or Cond < 14 then
			MV.PotionHPReg[slot] = math.min(RegenHP, RegenCap * 1.5)
			local FHP = Pl:GetFullHP()
			potionGive(Pl, MV.PotionHPReg[slot], 0)
			if Pl.HP > 0 and Pl.Conditions[13] > 0 then Pl.Conditions[13] = 0 end
			local Buff = Game.PlayersExtra[Target:GetIndex()].SpellBuffs2[31]
			Buff.ExpireTime = Time
			Buff.Power = math.floor(MV.PotionHPReg[slot])
		else
			MV.PotionHPReg[slot] = 0
		end
	end
	Timer(HPPotionTimers[key], const.Minute * 5, true)
end



evt.PotionEffects[34] = function(IsDrunk, Target, Power)
	if not IsDrunk then return end
	local slot = Target:GetSlot() + 1
	local key = "SP_" .. slot
	local Time = Game.Time + const.Hour * 2
	local Pl = Target

	-- Не заменяем, если текущий баф длится дольше
	local existingBuff = Game.PlayersExtra[Target:GetIndex()].SpellBuffs2[32]
	if existingBuff and existingBuff.ExpireTime > Time then return end

	local RegenSP = Power
	local RegenCap = Target.LevelBase / 2 + 4

	if SPPotionTimers[key] then
		RemoveTimer(SPPotionTimers[key])
		SPPotionTimers[key] = nil
	end

	SPPotionTimers[key] = function()
		local Cond = Pl:GetMainCondition()
		if Game.Time > Time then
			RemoveTimer(SPPotionTimers[key])
			SPPotionTimers[key] = nil
			MV.PotionSPReg[slot] = 0
		elseif Cond >= 17 or Cond < 14 then
			MV.PotionSPReg[slot] = math.min(RegenSP, RegenCap)
			local FSP = Pl:GetFullSP()
			potionGive(Pl, 0, math.min(RegenSP, RegenCap))
			local Buff = Game.PlayersExtra[Target:GetIndex()].SpellBuffs2[32]
			Buff.ExpireTime = Time
			Buff.Power = math.floor(MV.PotionSPReg[slot])
		else
			MV.PotionSPReg[slot] = 0
		end
	end
	Timer(SPPotionTimers[key], const.Minute * 5, true)
end



-- Recharge Item use to recharge Ancients' devices
evt.PotionEffects[13] = function(IsDrunk, Target, Power)
	local Pl = Party:GetCurrentPlayer()
	local RS, RM = SplitSkill(Pl:GetSkill(const.Skills.RepairItem))
	if not IsDrunk then
		local Itnum = Target.Number
		if Itnum == 963 or Itnum == 964 or Itnum == 965 or Itnum == 967 then
			Target.Charges = math.min(Target.Charges + Power, 50 + 25*RM + RS)
		elseif Itnum == 966 then
			Target.Charges = math.min(Target.Charges + Power*2, 250*RM)
		elseif Merge.Functions.BlasterRecharge and Merge.Functions.BlasterRecharge(Target, Power) then
			-- a blaster's power cell: Power % (MMMWE_Blasters.lua), no loss of capacity
			Game.ShowStatusText(string.format("%s: %d%%", Itnum == 968 and "Shield charge" or "Power cell",
				math.floor(Target.MaxCharges / 2)))
		end
		return 3
	end
end

-- Pain Reflection
evt.PotionEffects[72] = function(IsDrunk, Target, Power)
	if IsDrunk then
		local Buff = Target.SpellBuffs[const.PlayerBuff.PainReflection]
		Buff.ExpireTime = Game.Time + potionMinutes(10*math.max(Power, 1))
		Buff.Power = 25
		Buff.Skill = JoinSkill(25,1)
	end
end

-- Aqua Vitae
evt.PotionEffects[71] = function(IsDrunk, Target, Power)
	if IsDrunk then
		local Cond = Target:GetMainCondition()
		local FHP = Target:GetFullHP()
		local FSP = Target:GetFullSP()
		if Cond == 14 then
			Target.HP = FHP
			Target.SP = FSP
			Target.Conditions[17] = 0
			Target.Conditions[14] = 0
			Target.Conditions[13] = 0
		elseif Cond == 16 then
			Target.HP = math.max(FHP/2)
			Target.SP = math.max(FSP/2)
			Target.Conditions[17] = 0
			Target.Conditions[16] = 0
			Target.Conditions[13] = 0
		elseif Cond == 17 then
			Target.Conditions[17] = 0
		end
		Target:ShowFaceAnimation(const.FaceAnimation.Smile)
	end
end

-- Powerful Recharge Item used as Ink
--evt.PotionEffects[13] = function(IsDrunk, Target, Power)
--	if not IsDrunk then
--		local pl = Party[math.max(Game.CurrentPlayer,0)]
--		local IVal1 = 0
--		local IVal2 = 0
--		local IVal3 = 0
--		local Itnum = Target.Number
--		for i = 1, 99 do
--			IVal1 = 399+i
--			IVal2 = 1201+i
--			IVal3 = 1901+i
--			if Itnum == IVal1 or Itnum == IVal2 or Itnum == IVal3 then
--				Target.Number = Target.Number - 100
--				evt[pl].Add("Inventory", Target.Number, 2)
--				Mouse:ReleaseItem()
--				return 3
--			end
--		end
--	end
--end