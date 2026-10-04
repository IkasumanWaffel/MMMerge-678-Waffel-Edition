local MV, MF = Merge.Vars, Merge.Functions
vars.PotionBuffs = vars.PotionBuffs or {}
local PSet	= vars.PotionBuffs
PSet.UsedPotions = PSet.UsedPotions or {}

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
		local ExpireTime = Game.Time + Power*const.Minute*30
		local Effect = Power*3

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
		local ExpireTime = Game.Time + Power*const.Minute*30
		local Effect = Power*3

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

-- Pure resistances
local function PureResistance(Target, Stat, ItemId)
	local PlayerId = GetPlayerId(Target)
	PSet.UsedPotions[PlayerId] = PSet.UsedPotions[PlayerId] or {}

	local t = PSet.UsedPotions[PlayerId]
	if t[ItemId] then
		return -1
	else
		t[ItemId] = true
		Target.Resistances[Stat].Base = Target.Resistances[Stat].Base + 40
	end
end

evt.PotionEffects[64] = function(IsDrunk, Target, Power, ItemId) return PureResistance(Target, 0, ItemId) end
evt.PotionEffects[65] = function(IsDrunk, Target, Power, ItemId) return PureResistance(Target, 1, ItemId) end
evt.PotionEffects[66] = function(IsDrunk, Target, Power, ItemId) return PureResistance(Target, 2, ItemId) end
evt.PotionEffects[67] = function(IsDrunk, Target, Power, ItemId) return PureResistance(Target, 3, ItemId) end
evt.PotionEffects[68] = function(IsDrunk, Target, Power, ItemId) return PureResistance(Target, 7, ItemId) end
evt.PotionEffects[69] = function(IsDrunk, Target, Power, ItemId) return PureResistance(Target, 8, ItemId) end

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

-- Heroism
evt.PotionEffects[9] = function(IsDrunk, Target, Power)
	if IsDrunk then
		local ind = Target:GetSlot()
		local BP = 5 * math.ceil(math.sqrt(Power))
		local rid = Target:GetIndex()
		CastSpellDirect(51, BP, 1, rid, ind) -- Heroism
		return true
	end
end

-- Bless
evt.PotionEffects[10] = function(IsDrunk, Target, Power)
	if IsDrunk then
		local ind = Target:GetSlot()
		local BP = 5 * math.ceil(math.sqrt(Power))
		local rid = Target:GetIndex()
		CastSpellDirect(46, BP, 1, rid, ind) -- Bless
		return true
	end
end

-- Stoneskin
evt.PotionEffects[14] = function(IsDrunk, Target, Power)
	if IsDrunk then
		local ind = Target:GetSlot()
		local BP = 5 * math.ceil(math.sqrt(Power))
		local rid = Target:GetIndex()
		CastSpellDirect(38, BP, 1, rid, ind) -- Stoneskin
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
					pl.HP = math.min(FHP, pl.HP + Power)
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
					pl.SP = math.min(FSP, pl.SP + Power)
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
			Pl.HP = math.min(FHP, Pl.HP + math.min(RegenHP, RegenCap))
			if Pl.HP > 0 and Pl.Conditions[13] > 0 then Pl.Conditions[13] = 0 end
			local Buff = Game.PlayersExtra[Target:GetIndex()].SpellBuffs2[31]
			Buff.ExpireTime = Time
			Buff.Power = MV.PotionHPReg[slot]
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
	local RegenCap = math.ceil(Target.LevelBase / 4 + 1)

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
			Pl.SP = math.min(FSP, Pl.SP + math.min(RegenSP, RegenCap))
			local Buff = Game.PlayersExtra[Target:GetIndex()].SpellBuffs2[32]
			Buff.ExpireTime = Time
			Buff.Power = MV.PotionSPReg[slot]
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
			MV.PotionHPReg[slot] = math.min(math.floor(RegenHP), math.floor(RegenCap * 1.5))
			local FHP = Pl:GetFullHP()
			Pl.HP = math.min(FHP, Pl.HP + math.min(math.floor(RegenHP), math.floor(RegenCap * 1.5)))
			if Pl.HP > 0 and Pl.Conditions[13] > 0 then Pl.Conditions[13] = 0 end
			local Buff = Game.PlayersExtra[Target:GetIndex()].SpellBuffs2[31]
			Buff.ExpireTime = Time
			Buff.Power = MV.PotionHPReg[slot]
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
	local RegenCap = math.ceil(Target.LevelBase / 2 + 4)

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
			Pl.SP = math.min(FSP, Pl.SP + math.min(RegenSP, RegenCap))
			local Buff = Game.PlayersExtra[Target:GetIndex()].SpellBuffs2[32]
			Buff.ExpireTime = Time
			Buff.Power = MV.PotionSPReg[slot]
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
		end
		return 3
	end
end

-- Pain Reflection
evt.PotionEffects[72] = function(IsDrunk, Target, Power)
	if IsDrunk then
		local Buff = Target.SpellBuffs[const.PlayerBuff.PainReflection]
		Buff.ExpireTime = Game.Time + const.Minute*10*math.max(Power, 1)
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