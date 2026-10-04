local LogId = "ExtraArtifacts"
local MF, MM = Merge.Functions, Merge.ModSettings
MF.LogInit1(LogId)
local MT = Merge.Tables
local Log = Log

local min, max, floor, ceil, random, sqrt = math.min, math.max, math.floor, math.ceil, math.random, math.sqrt
local PlayerEffects		= {}
local ArtifactBonuses	= {}
local SpecialBonuses	= {}
local StoreEffects
local AdvInnScreen = const.Screens.AdventurersInn

local GetRace = GetCharRace
local GetSlotByIndex = MF.GetSlotByIndex

local spell_distance = 50
MT.PlayerEffects = PlayerEffects

------------------------------------------------
----			Base events					----
------------------------------------------------

------------------------------------------------
-- Make artifacts unique

vars.GotArtifact = vars.GotArtifact or {}

vars.PlacedArtifacts = vars.PlacedArtifacts or {
	-- MM8
	[501] = -1, [502] = -1, [503] = -1, [504] = -1, [508] = -1,
	[509] = -1, [516] = -1, [519] = -1, [523] = -1, [539] = -1,
	[540] = -1, [541] = -1,
	-- MM7
	[1333] = -1, [1334] = -1, [1335] = -1, [1336] = -1,
	[1337] = -1, [1338] = -1,
	-- MM6
	[2020] = -1, [2023] = -1, [2032] = -1, [2033] = -1, [2034] = -1
}

local GItems = Game.ItemsTxt
local ArtifactsList = {}
for i,v in GItems do
	if v.Material > 0 and v.Value > 0 and v.ChanceByLevel[6] > 0 then
		table.insert(ArtifactsList, i)
	end
end

function events.GotItem(i)
	local v = GItems[i]
	if v.Material > 0 and v.Value > 0 and v.ChanceByLevel[6] > 0 then
		vars.GotArtifact[i] = true
		if vars.PlacedArtifacts[i] and vars.PlacedArtifacts[i] > 0 then
			vars.PlacedArtifacts[i] = nil
		end
	end
end

local function GetNotFoundArts()
	local t = {}
	for k,v in pairs(ArtifactsList) do
		if not vars.GotArtifact[v] and not vars.PlacedArtifacts[v] then
			table.insert(t, v)
		end
	end
	return t
end

local function RosterHaveItem(ItemId)
	for i = 0, Party.PlayersArray.count - 1 do
		local Player = Party.PlayersArray[i]
		for _, Item in Player.Items do
			if Item.Number == ItemId then
				return true
			end
		end
	end
end

local function RecountFoundArtifacts()
	for ItemId,v in pairs(vars.GotArtifact) do
		vars.GotArtifact[ItemId] = RosterHaveItem(ItemId)
	end
end
Game.RecountFoundArtifacts = RecountFoundArtifacts

function events.ItemGenerated(t)
	local Num = t.Item.Number
	local ItemTxt = GItems[Num]
	if ItemTxt.Material > 0 and ItemTxt.Value > 0 and ItemTxt.ChanceByLevel[6] > 0
			and (vars.GotArtifact[Num] or vars.PlacedArtifacts[Num]) then
		local cArts = GetNotFoundArts()
		if #cArts == 0 then
			t.Item:Randomize(5, ItemTxt.EquipStat+1)
		else
			t.Item.Number = cArts[random(#cArts)]
			vars.PlacedArtifacts[t.Item.Number] = Map.LastRefillDay
				+ Game.MapStats[Map.MapStatsIndex].RefillDays
		end
		Log(Merge.Log.Info, "ItemGenerated: replace item %d with %d", Num, t.Item.Number)
	else
		Log(Merge.Log.Info, "ItemGenerated: item %d", Num)
	end
end

function events.ArtifactGenerated(t)
	-- FIXME?
	local cArts = GetNotFoundArts()
	local orig_id = t.ItemId
	if #cArts == 0 then
		t.ItemId = random(177, 186)
	else
		t.ItemId = cArts[random(#cArts)]
		vars.PlacedArtifacts[t.ItemId] = Map.LastRefillDay
			+ Game.MapStats[Map.MapStatsIndex].RefillDays
	--if vars.GotArtifact[t.ItemId] then
	--	t.ItemId = random(177, 186)
	--else
	--	vars.GotArtifact[t.ItemId] = true
	end
	Log(Merge.Log.Info, "ArtifactGenerated: replace item %d with %d", orig_id, t.ItemId)
end

vars.NextArtifactsRefill = vars.NextArtifactsRefill or Game.Time + const.Year*2
function events.AfterLoadMap()
	-- Reset flags
	if Game.Time > vars.NextArtifactsRefill then
		RecountFoundArtifacts()
		vars.NextArtifactsRefill = Game.Time + const.Year*2
	end
end

function events.NewDay(t)
	local DayOfGame = t.DayOfMonth + 28 * t.Month + 336 * t.GameYear
	for k, v in pairs(vars.PlacedArtifacts) do
		if v > 0 and v <= DayOfGame then
			vars.PlacedArtifacts[k] = nil
			Log(Merge.Log.Info, "NewDay: artifact recalled: %d", k)
		end
	end
end

------------------------------------------------
-- Can wear conditions

local WearItemConditions = {}

function events.CanWearItem(t)
	local Cond = WearItemConditions[t.ItemId]
	if Cond then
		t.Available = Cond(t.Player, t.RosterId, t.Available)
	end
end

-- Stat bonuses

function events.CalcStatBonusByItems(t)
	--local PLT = PlayerEffects[t.Player]
	local PLT = PlayerEffects[t.PlayerIndex]
	if PLT then
		t.Result = t.Result + (PLT.Stats[t.Stat] or 0)
	elseif Game.CurrentScreen == AdvInnScreen or GetSlotByIndex(t.PlayerIndex) then
		Log(Merge.Log.Info, "%s: CalcStatBonusByItems (%d) StoreEffects", LogId, t.Stat)
		StoreEffects(t.PlayerIndex)
	end
end

-- Skill bonuses

function events.GetSkill(t)
	--local PLT = PlayerEffects[t.Player]
	local PLT = PlayerEffects[t.PlayerIndex]
	if PLT then
		local Skill, Mas = SplitSkill(t.Result)
		Skill = Skill + (PLT.Skills[t.Skill] or 0)
		if Mas > 0 then
			if PLT.SpcBonuses[t.Skill + 100] then
				Mas = min(Mas + 1, 4)
			end
		end
		t.Result = JoinSkill(Skill, Mas)
	elseif Game.CurrentScreen == AdvInnScreen or GetSlotByIndex(t.PlayerIndex) then
		Log(Merge.Log.Info, "%s: GetSkill (%d) StoreEffects", LogId, t.Skill)
		StoreEffects(t.PlayerIndex)
	end
end

function events.GetPlayerSkillMastery(t)
	--local PLT = PlayerEffects[t.Player]
	local PLT = PlayerEffects[t.PlayerIndex]
	if PLT then
		local Skill, Mas = SplitSkill(t.Result)
		if Mas > 0 then
			if PLT.SpcBonuses[t.Skill + 100] then
				Mas = min(Mas + 1, 4)
			end
		end
		t.Result = JoinSkill(Skill, Mas)
	elseif Game.CurrentScreen == AdvInnScreen or GetSlotByIndex(t.PlayerIndex) then
		Log(Merge.Log.Info, "%s: GetPlayerSkillMastery (%d) StoreEffects", LogId, t.Skill)
		StoreEffects(t.PlayerIndex)
	end
end

-- Buffs and extra effects

local TimerPeriod = 2*const.Minute
local MiscItemsEffects = {}

-- Checks if player has an item in Inventory
local function PlayerHasItem(player, item_num)
	-- FIXME: check for item status?
	if mem.call(0x43C0DA, 2, item_num, player["?ptr"], 0) % 256 == 1 then
		return true
	else
		return false
	end
end

local function PartyHasItem(item_num)
	for _, pl in Party do
		if PlayerHasItem(pl, item_num) then
			return true
		end
	end
	return false
end

local function SetBuffs()

	for iR, Player in Party do
		--local PLT = PlayerEffects[Player]
		local PLT = PlayerEffects[Party.PlayersIndexes[iR]]
		if PLT then
			for k,b in pairs(PLT.Buffs) do
				local Buff = Player.SpellBuffs[k]
				Buff.ExpireTime = Game.Time + TimerPeriod + const.Minute
				Buff.Power = b
				Buff.Skill = b
				Buff.OverlayId = 0
			end
			for k, b in pairs(PLT.PartyBuffs) do
				local Buff = Party.SpellBuffs[k]
				local skill, mas = SplitSkill(b)
				Buff.ExpireTime = Game.Time + TimerPeriod + const.Minute
				Buff.Bits = 0
				Buff.Caster = 50
				-- FIXME: true for Resistances only
				Buff.Power = skill * mas
				Buff.Skill = mas
				Buff.OverlayId = 0
			end
		else
			Log(Merge.Log.Info, "%s: SetBuff StoreEffects", LogId)
			StoreEffects(Party.PlayersIndexes[iR])
		end
	end

	for k,v in pairs(MiscItemsEffects) do
		if PartyHasItem(k) then
			v()
		end
	end

end

function events.AfterLoadMap()
	Timer(SetBuffs, TimerPeriod, true)
end

-- Base effects

local function HPSPoverTime(Player, HPSP, Amount, PlayerId)
	local Cond = Player:GetMainCondition()
	if Cond >= 17 or Cond < 14 then
		Player[HPSP] = min(Player[HPSP] + Amount, Player["GetFull" .. HPSP](Player))
	end
end

local function SharedLife(Char, PlayerId)

	local Mid = Char:GetMainCondition()
	if Party.count == 1 or Mid == 14 or Mid == 16 or Char.HP >= Char:GetFullHP() then
		return
	end

	local Players = {}
	local Pool = Char.HP
	local Need = 1
	for i,v in Party do
		local res = v.HP - Char.HP
		if res > 0 then
			Pool = Pool + v.HP
			Need = Need + 1
			Players[i] = res
		end
	end

	Mid = floor(Pool/Need)
	Need = Mid - Char.HP
	Pool = Need
	for k, v in pairs(Players) do
		local p = Party[k]
		local res = min(max(p.HP - Mid, 0), Need)

		Players[k] = v - res
		p.HP = p.HP - floor(res/2)
		Pool = Pool - floor(res/2)
	end
	Char.HP = Char.HP + ceil(Need - Pool)

	if Char.HP > 0 and Char.Conditions[13] > 0 then
		Char.Conditions[13] = 0
	end

	Char:ShowFaceAnimation(const.FaceAnimation.Smile)

end

-- Over time effects

function events.RegenTick(Player, player_index)

	--local PLT = PlayerEffects[Player]
	local PLT = PlayerEffects[player_index]
	if PLT then
		for k,v in pairs(PLT.OverTimeEffects) do
			v(Player)
		end
		PLT = PLT.HPSPRegen
		if PLT.SP ~= 0 then
			HPSPoverTime(Player, "SP", PLT.SP)
		end
		if PLT.HP ~= 0 then
			HPSPoverTime(Player, "HP", PLT.HP)
		end
	else
		Log(Merge.Log.Info, "%s: RegenTick StoreEffects", LogId)
		StoreEffects(player_index)
	end

end

-- Attack delay mods

local MinimalMeleeAttackDelay = Merge and Merge.Settings and Merge.Settings.Attack
		and Merge.Settings.Attack.MinimalMeleeAttackDelay or 30
local MinimalRangedAttackDelay = Merge and Merge.Settings and Merge.Settings.Attack
		and Merge.Settings.Attack.MinimalRangedAttackDelay or 15
local MinimalBlasterAttackDelay = Merge and Merge.Settings and Merge.Settings.Attack
		and Merge.Settings.Attack.MinimalBlasterAttackDelay or 15

function events.GetAttackDelay(t)
	local Player = t.Player
	--local PLT = PlayerEffects[Pl]
	local PLT = PlayerEffects[t.PlayerIndex]
	if PLT then
		t.Result = t.Result + (PLT.AttackDelay[t.Ranged and 1 or 2] or 0)
		local MHItem = Player.ItemMainHand > 0 and Player.Items[Player.ItemMainHand] or false
		--local AD = 0
		if MHItem and not MHItem.Broken and Game.ItemsTxt[MHItem.Number].Skill == 7 then
			--local BS, BM = SplitSkill(Pl:GetSkill(const.Skills.Blaster))
			--local ADadd = {2, 1, 0.6, 0.4}
			--local ADcap = {0, 10, 15, 18}
			--local SkillCap = {0, 5, 10, 15}
			--local SkillCapHi = {5, 10, 15, 100}
			--AD = math.min(math.floor(ADadd[BM]*BS-ADadd[BM]*SkillCap[BM]+ADcap[BM]),math.floor(ADadd[BM]*SkillCapHi[BM]-ADadd[BM]*SkillCap[BM]+ADcap[BM]))
			t.Result = max(t.Result, MinimalBlasterAttackDelay)
		elseif t.Ranged then
			t.Result = max(t.Result, MinimalRangedAttackDelay)
		else
			t.Result = max(t.Result, MinimalMeleeAttackDelay)
		end
	elseif Game.CurrentScreen == AdvInnScreen or GetSlotByIndex(t.PlayerIndex) then
		Log(Merge.Log.Info, "%s: GetAttackDelay StoreEffects", LogId)
		StoreEffects(t.PlayerIndex)
	end
end

-- On-hit effects

local OnHitEffects = {}

function events.ItemAdditionalDamage(t)

	if t.Item.Broken then return end

	local Effect = OnHitEffects[t.Item.Number]

	if not Effect then return end

	t.DamageKind = Effect.DamageKind or t.DamageKind
	if Effect.Add then
		t.Result = t.Result + Effect.Add
	end
	if Effect.Special then
		Effect.Special(t)
	end
end

-- Effect immunities
function events.DoBadThingToPlayer(t)
	--local PLT = PlayerEffects[t.Player]
	local PLT = PlayerEffects[t.PlayerIndex]
	if PLT then
		if PLT.EffectImmunities[t.Thing] then
			t.Allow = false
		end
	elseif Game.CurrentScreen == AdvInnScreen or GetSlotByIndex(t.PlayerIndex) then
		Log(Merge.Log.Info, "%s: DoBadThingToPlayer StoreEffects", LogId)
		StoreEffects(t.PlayerIndex)
	end
end

-- Additional item Special Bonuses
-- Scope: item
local ItemSpcBonuses = {}

function events.ItemHasBonus2(t)
	local Bonuses = ItemSpcBonuses[t.ItemId]
	if Bonuses and table.find(Bonuses, t.Bonus2) then
		t.Result = 1
	end
end

-- Scope: player
function events.OnHasItemBonus(t)
	--local PLT = PlayerEffects[t.Player]
	local PLT = PlayerEffects[t.PlayerIndex]
	if PLT then
		if PLT.SpcBonuses[t.Bonus2] then
			t.Result = 1
		end
	else
		MF.LogVerbose("%s: OnHasItemBonus (%d) StoreEffects %d", LogId, t.Bonus2, t.PlayerIndex)
		StoreEffects(t.PlayerIndex)
	end
end

-- Groups of mutually exclusive bonuses
local Bonus2Group = {
	-- Additional damage
	[1] = {4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 46, 67, 68,
		80, 81, 82, 83, 84, 85, 86, 87, 88,
		90, 91, 92, 93, 94, 95, 96, 97, 98, 99},
	-- Vampiric
	[2] = {16, 41}
}

-- Check if item has one of the bonuses from the specific group
function events.ItemHasBonus2OfGroup(t)
	-- Check enchanted Bonus2 first
	if t.Bonus2 and t.Bonus2 > 0 then
		if table.find(Bonus2Group[t.Group], t.Bonus2) then
			t.Result = t.Bonus2
			return
		end
	end
	local Bonuses = ItemSpcBonuses[t.ItemId]
	if not Bonuses then
		return
	end
	for _, bonus in pairs(Bonuses) do
		if table.find(Bonus2Group[t.Group], bonus) then
			t.Result = bonus
			return
		end
	end
end

-- Arrow projectiles

local ArrowProjectiles = {}
function events.ArrowProjectile(t)
	if t.ObjId == 0x221 then
		local Player = Party.PlayersArray[t.PlayerIndex]
		local Bow = Player.Items[Player.ItemBow].Number

		t.ObjId = ArrowProjectiles[Bow] or 0x221
	end
end

------------------------------------------------
----			Bake effects				----
------------------------------------------------

local function SpellPowerByItemSkill(Player, Item)
	local Skill, Mas = 7, 3
	local SkillNum = Game.ItemsTxt[Item.Number].Skill
	if SkillNum < 39 then
		Skill, Mas = SplitSkill(Player:GetSkill(SkillNum))
	end
	return Skill, Mas
end

StoreEffects = function(player_index, postpone_gc)
	Log(Merge.Log.Info, "%s: StoreEffects", LogId)
	local Mod, T
	local Player = Party.PlayersArray[player_index]
	local PLT = PlayerEffects[player_index] or {}
	local TKPreventDeathFromNegativeEndurance = MM.TKPreventDeathFromNegativeEndurance or 0
	PlayerEffects[player_index] = PLT

	PLT.EffectImmunities = {}
	PLT.OverTimeEffects = {}
	PLT.AttackDelay = {}
	PLT.HPSPRegen = {}
	PLT.Buffs  = {}
	PLT.PartyBuffs = {}
	PLT.Stats  = {}
	PLT.Skills = {}
	PLT.SpcBonuses = {}

	PLT.HPSPRegen.HP = 0
	PLT.HPSPRegen.SP = 0

	for i,v in Player.EquippedItems do
		if v > Player.Items.limit then
			Log(Merge.Log.Error, "%s: StoreEffects: incorrect item id (%d - %d) in inventory of player #0x%X", LogId, i, v, Player["?ptr"])
			Player.EquippedItems[i] = 0
		elseif v > 0 then
			local Item = Player.Items[v]
			if not Item.Broken then

				Mod = ArtifactBonuses[Item.Number]
				if Mod then
					-- Stats
					if Mod.Stats then
						T = PLT.Stats
						for k,v in pairs(Mod.Stats) do
							if k == 3 and (TKPreventDeathFromNegativeEndurance == 1) then
								T[k] = math.max((T[k] or 0) + v, (T[k] or 0) - Player:GetBaseEndurance())
							else
								T[k] = (T[k] or 0) + v
							end
						end
					end
					-- Skills
					if Mod.Skills then
						T = PLT.Skills
						for k,v in pairs(Mod.Skills) do
							T[k] = (T[k] or 0) + v
						end
					end
					-- Spell muls
					if Mod.SpellBonus then
						T = PLT.Skills
						for k,v in pairs(Mod.SpellBonus) do
							local base = SplitSkill(Player.Skills[k])
							T[k] = (T[k] or 0) + base*0.5
						end
					end
					-- Buffs
					if Mod.Buffs then
						T = PLT.Buffs
						local Skill, Mas = SpellPowerByItemSkill(Player, Item)
						for k,v in pairs(Mod.Buffs) do
							T[k] = math.max((T[k] or 0), v, Skill*Mas/2)
						end
					end
					-- Party Buffs
					if Mod.PartyBuffs then
						T = PLT.PartyBuffs
						local skill, mas = SpellPowerByItemSkill(Player, Item)
						if Mod.PartyBuffs.ReqMastery <= mas then
							for k, v in pairs(Mod.PartyBuffs.Buff) do
								v = (v == -1) and JoinSkill(skill, mas) or v
								T[k] = max((T[k] or 0), v)
							end
						end
					end
					-- Effect immunities
					if Mod.EffectImmunities then
						T = PLT.EffectImmunities
						for k,v in pairs(Mod.EffectImmunities) do
							T[k] = true
						end
					end
					-- Attack recovery
					if Mod.ModAttackDelay then
						local IsRangedItem = Game.ItemsTxt[Item.Number].EquipStat == const.ItemType.Missile - 1
						T = PLT.AttackDelay
						T[IsRangedItem and 1 or 2] = (T[IsRangedItem and 1 or 2] or 0) + Mod.ModAttackDelay
					end
					-- HP/SP regen
					if Mod.HPSPRegen then
						T = PLT.HPSPRegen
						for k, v in pairs(Mod.HPSPRegen) do
							T[k] = (T[k] or 0) + v
						end
					end
					-- Over time effects
					if Mod.OverTimeEffect then
						table.insert(PLT.OverTimeEffects, Mod.OverTimeEffect)
					end
				end

				-- Bonus2
				if ItemSpcBonuses[Item.Number] then
					T = PLT.SpcBonuses
					for _, bonus in pairs(ItemSpcBonuses[Item.Number]) do
						T[bonus] = true
					end
				end
				if Item.Bonus2 > 99 and Item.Bonus2 < 139 then
					PLT.SpcBonuses[Item.Bonus2] = true
				end

				Mod = SpecialBonuses[Item.Bonus2]
				if Mod then
					-- HP/SP regen
					if Mod.HPSPRegen then
						T = PLT.HPSPRegen
						for k, v in pairs(Mod.HPSPRegen) do
							T[k] = (T[k] or 0) + v
						end
					end
					-- Effect immunities
					if Mod.EffectImmunities then
						T = PLT.EffectImmunities
						for k,v in pairs(Mod.EffectImmunities) do
							T[k] = true
						end
					end
					-- Resistances (Stats in general)
					if Mod.Stats then
						T = PLT.Stats
						for k,v in pairs(Mod.Stats) do
							T[k] = (T[k] or 0) + v
						end
					end
				end
			end
		end
	end

	if not postpone_gc then
		--Log(Merge.Log.Info, "%s: StoreEffects gc", LogId)
		--collectgarbage("collect")
	end
	Log(Merge.Log.Info, "%s: StoreEffects finished", LogId)
end
Game.CountItemBonuses = StoreEffects

function events.LoadMapScripts(WasInGame)
	if not WasInGame then
		for i,v in Party do
			Log(Merge.Log.Info, "%s: LoadMapScripts StoreEffects %d", LogId, Party.PlayersIndexes[i])
			StoreEffects(Party.PlayersIndexes[i], true)
		end
	end
end

local NeedRecount = false

function events.Action(t)
	if t.Action == 121 or t.Action == 133 and Game.CurrentScreen == 7 then
		NeedRecount = true
	end
end

function events.Tick()
	if NeedRecount then
		local Player = max(Game.CurrentPlayer, 0)
		Log(Merge.Log.Info, "%s: Tick StoreEffects", LogId)
		StoreEffects(Party.PlayersIndexes[Player])
		NeedRecount = false
	end
end

------------------------------------------------
----			Item settings				----
------------------------------------------------

local function GetBonusList(ItemId)
	local t = ArtifactBonuses[ItemId]
	if not t then
		t = {}
		ArtifactBonuses[ItemId] = t
	end
	return t
end

local function GetSpcBonusList(BonusId)
	local t = SpecialBonuses[BonusId]
	if not t then
		t = {}
		SpecialBonuses[BonusId] = t
	end
	return t
end

--------------------------------
-- Special effects of unequipable items

-- Horn of Ros
MiscItemsEffects[2055] = function()
	local Buff = Party.SpellBuffs[const.PartyBuff.DetectLife]
	Buff.ExpireTime = Game.Time + TimerPeriod + const.Minute
	Buff.Power = 3
	Buff.Skill = 7
	Buff.OverlayId = 0
end

-- Electric Lantern
MiscItemsEffects[963] = function()
	local SkillSum = 0
	local MasterySum = 0
	local Player_count = 0
	for i,pl in Party do
		if PlayerHasItem(pl, 962) then
		local PS, PM = SplitSkill(pl:GetSkill(const.Skills.Perception))
			MasterySum = MasterySum + PM
		end
		--Player_count=Player_count+1
	end
	--SkillSum = SkillSum/Player_count
	--MasterySum = MasterySum/Player_count
	local Buff = Party.SpellBuffs[const.PartyBuff.WizardEye]
	Buff.ExpireTime = Game.Time + TimerPeriod + const.Minute
	Buff.Power = math.max(1, MasterySum)
	Buff.Skill = math.max(1, MasterySum)
	Buff.OverlayId = 0
	
	local Buff2 = Party.SpellBuffs[const.PartyBuff.TorchLight]
	Buff2.ExpireTime = Game.Time + TimerPeriod + const.Minute
	Buff2.Power = math.max(1, MasterySum)--+1)
	Buff2.Skill = math.max(1, MasterySum)
	Buff2.OverlayId = 0
end
--
-- Jetpack
ItemSpcBonuses[966] = {72}
-- Reflector Shield
Keys[const.Keys.G] = function()
	local Player = Party:GetCurrentPlayer()
	local It = Player.ItemExtraHand
	local BS, BM = SplitSkill(Player:GetSkill(7))
	if It and It > 0 then
		local Itnum = Player.Items[It].Number
		if Itnum == 967 and BM == 4 then
			local ItemCharge = Player.Items[It].Charges	
			if ItemCharge >= 30 then
				ExitCurrentScreen(false,true)
				CastSpellDirect(75, 10, 4)
				Player.Items[It].Charges = Player.Items[It].Charges - 30
				Game.ShowStatusText(string.format("Remaining charge: %d percent.", Player.Items[It].Charges))
			else
				Game.ShowStatusText(string.format("Low charge: %d/30 percent! Please recharge the device.", Player.Items[It].Charges))
				evt.PlaySound{358}
			end
		elseif Itnum == 967 and BM <4 then
			Game.ShowStatusText(string.format("Tech mastery (%d/4) is insufficient to use this function.",BM))
			evt.PlaySound{358}
		end
	end
end

GetBonusList(967).Buffs = {[const.PlayerBuff.Shield] = 3, [const.PlayerBuff.PainReflection] = 20}

GetBonusList(967).Stats = {
	[const.Stats.FireResistance] = 20,
	[const.Stats.AirResistance] = 20,
	[const.Stats.WaterResistance] = 20,
	[const.Stats.EarthResistance] = 20,
	[const.Stats.MindResistance] = 20,
	[const.Stats.BodyResistance] = 20,
	[const.Stats.SpiritResistance] = 20,
	[const.Stats.LightResistance] = 20,
	[const.Stats.DarkResistance] = 20,
	[const.Stats.EnergyResistance] = 50
}

--------------------------------
---- Can wear conditions

-- Jetpack
WearItemConditions[966] = function(Player, RosterId, Available)
	return Available and
		Game.ClassesExtra[Player.Class].Kind == const.ClassKind.Technician
end

-- Power Shield
WearItemConditions[967] = function(Player, RosterId, Available)
	BS,BM = SplitSkill(Player:GetSkill(7))
	return Available and
		Game.ClassesExtra[Player.Class].Kind == const.ClassKind.Technician
end

WearItemConditions[968] = function(Player, RosterId, Available)
	return Available and
		Game.ClassesExtra[Player.Class].Kind == const.ClassKind.Technician
end

-- Elderaxe
WearItemConditions[504] = function(Player, RosterId, Available)
	return Available and
		Game.Races[GetRace(Player)].Kind == const.RaceKind.Minotaur
end

-- Foulfang
WearItemConditions[508] = function(Player, RosterId, Available)
	return Available and
		Game.Races[GetRace(Player)].Family == const.RaceFamily.Vampire
end

-- Glomenmail
WearItemConditions[514] = function(Player, RosterId, Available)
	local Race = GetRace(Player)
	return Available and Game.Races[Race].BaseRace == const.Race.DarkElf
			and Game.Races[Race].Family == const.RaceFamily.None
end

-- Supreme plate
WearItemConditions[515] = function(Player, RosterId, Available)
	return Available and
		Game.ClassesExtra[Player.Class].Kind == const.ClassKind.Knight
end

-- Eclipse
WearItemConditions[516] = function(Player, RosterId, Available)
	return Available
		and Game.ClassesExtra[Player.Class].Kind == const.ClassKind.Cleric
end

-- Crown of final Dominion
WearItemConditions[521] = function(Player, RosterId, Available)
	return Available and Player.Class == const.Class.MasterNecromancer
			and Game.Races[GetRace(Player)].Family == const.RaceFamily.Undead
end

-- Blade of Mercy
WearItemConditions[529] = function(Player, RosterId, Available)
	return Available and (Player.Class == const.Class.Necromancer
			or Player.Class == const.Class.MasterNecromancer)
	-- return Game.ClassesExtra[Player.Class].Kind == const.ClassKind.Sorcerer
	--		and Game.ClassesExtra[Player.Class].Alignment == const.Alignment.Evil
end

-- Lightning crossbow
WearItemConditions[532] = function(Player, RosterId, Available)
	return Available and
		Game.Races[GetRace(Player)].Kind == const.RaceKind.Elf
end
-- Ethric's Staff
WearItemConditions[1317] = function(Player, RosterId, Available)
	return Available and
		Game.ClassesExtra[Player.Class].Alignment == const.Alignment.Evil
end
-- Old Nick
WearItemConditions[1319] = function(Player, RosterId, Available)
	return Available and
		Game.ClassesExtra[Player.Class].Alignment == const.Alignment.Evil
end
-- Taledon's Helm
WearItemConditions[1323] = function(Player, RosterId, Available)
	return Available and
		Game.ClassesExtra[Player.Class].Alignment == const.Alignment.Good
end
-- Twilight
WearItemConditions[1327] = function(Player, RosterId, Available)
	return Available and
		Game.ClassesExtra[Player.Class].Alignment == const.Alignment.Evil
end
-- Justice
WearItemConditions[1329] = function(Player, RosterId, Available)
	return Available and
		Game.ClassesExtra[Player.Class].Alignment == const.Alignment.Good
end
-- Elfbane
WearItemConditions[1333] = function(Player, RosterId, Available)
	return Available and
		Game.Races[GetRace(Player)].Kind == const.RaceKind.Goblin
end

-- Mind's Eye
WearItemConditions[1334] = function(Player, RosterId, Available)
	return Available and
		Game.Races[GetRace(Player)].Kind == const.RaceKind.Human
end

-- Elven chainmail
WearItemConditions[1335] = function(Player, RosterId, Available)
	return Available and
		Game.Races[GetRace(Player)].Kind == const.RaceKind.Elf
end

-- Forge Gauntlets
WearItemConditions[1336] = function(Player, RosterId, Available)
	return Available and
		Game.Races[GetRace(Player)].Kind == const.RaceKind.Dwarf
end

-- Hero's belt
WearItemConditions[1337] = function(Player, RosterId, Available)
	local Gender = Game.CharacterPortraits[Player.Face].DefSex
	return Available and Gender == 0 -- only male can wear it.
end

-- Lady's Escort ring
WearItemConditions[1338] = function(Player, RosterId, Available)
	local Gender = Game.CharacterPortraits[Player.Face].DefSex
	return Available and Gender == 1 -- only female can wear it.
end

-- Wetsuit
local WetsuitSlots = {0,2,4,5,6,8}
WearItemConditions[1406] = function(Player, RosterId, Available)

	if not Game.CharacterDollTypes[Game.CharacterPortraits[Player.Face].DollType].Armor then
		return false
	end

	local EqItems = Player.EquippedItems

	-- Armors, except body (this one will be replaced).
	for _,v in pairs(WetsuitSlots) do
		if EqItems[v] > 0 then
			return false
		end
	end

	-- Main hand allow only blasters and one-handed weapons
	local MIt = EqItems[1]
	if MIt > 0 then
		local Item = Game.ItemsTxt[Player.Items[MIt].Number]
		if Item.EquipStat == 1 then
			return false
		end
	end

	return true
end

function events.CanWearItem(t)
	if t.Player.ItemArmor > 0 and t.Player.Items[t.Player.ItemArmor].Number == 1406 then
		local EqSt = Game.ItemsTxt[t.ItemId].EquipStat
		t.Available = EqSt == 0 or EqSt == 3 or EqSt == 8 or EqSt == 10 or EqSt == 11
	end
end

--------------------------------
---- Stat bonuses

-- Crown of final Dominion
GetBonusList(521).Stats = {	[const.Stats.Intellect] = 50}

-- Last Stage Cuirass
GetBonusList(533).Stats = {[const.Stats.SpiritResistance] = -30}

-- Cycle of life
GetBonusList(543).Stats = {	[const.Stats.Endurance] = 20}

-- Puck
GetBonusList(1302).Stats = {[const.Stats.Speed]	= 40}
-- Iron Feather
GetBonusList(1303).Stats = {[const.Stats.Might]	= 40}
-- Wallace
GetBonusList(1304).Stats = {[const.Stats.Personality] = 40}
-- Corsair
GetBonusList(1305).Stats = {[const.Stats.Luck] = 40}
-- Governor's Armor
GetBonusList(1306).Stats = {[const.Stats.Might] 		= 10,
							[const.Stats.Intellect] 	= 10,
							[const.Stats.Personality] 	= 10,
							[const.Stats.Speed] 		= 10,
							[const.Stats.Accuracy]		= 10,
							[const.Stats.Endurance] 	= 10,
							[const.Stats.Luck]			= 10}
-- Yoruba
GetBonusList(1307).Stats = {[const.Stats.Endurance] 	= 25}
-- Splitter
GetBonusList(1308).Stats = {[const.Stats.FireResistance] = 65000}
-- Ullyses
GetBonusList(1312).Stats = {[const.Stats.Accuracy] = 50}
-- Seven League Boots
GetBonusList(1314).Stats = {[const.Stats.Speed] = 40}
-- Mash
GetBonusList(1316).Stats = {[const.Stats.Might] 		= 150,
							[const.Stats.Intellect] 	= -40,
							[const.Stats.Personality] 	= -40,
							[const.Stats.Speed] 		= -40}
-- Hareck's Leather
GetBonusList(1318).Stats = {[const.Stats.Luck]				= 50,
							[const.Stats.FireResistance] 	= -10,
							[const.Stats.AirResistance] 	= -10,
							[const.Stats.WaterResistance] 	= -10,
							[const.Stats.EarthResistance] 	= -10,
							[const.Stats.MindResistance] 	= -10,
							[const.Stats.BodyResistance] 	= -10,
							[const.Stats.SpiritResistance] 	= -10}
-- Amuck
GetBonusList(1320).Stats = {[const.Stats.Might] 		= 100,
							[const.Stats.Endurance] 	= 100,
							[const.Stats.ArmorClass] 	= -15}
-- Glory shield
GetBonusList(1321).Stats = {[const.Stats.BodyResistance] = -10,
							[const.Stats.MindResistance] = -10}
-- Kelebrim
GetBonusList(1322).Stats = {[const.Stats.Endurance] = 50,
							[const.Stats.EarthResistance] = -30}
-- Taledon's Helm
GetBonusList(1323).Stats = {
	[const.Stats.Might] = 15,
	[const.Stats.Personality] = 15,
	[const.Stats.Luck] = -40
}
-- Scholar's Cap
GetBonusList(1324).Stats = {[const.Stats.Endurance] = -50}
-- Phynaxian Crown
GetBonusList(1325).Stats = {
	[const.Stats.Personality] = 30,
	[const.Stats.ArmorClass] = -20,
	[const.Stats.WaterResistance] = 50
}
-- Titan's Belt
GetBonusList(1326).Stats = {
	[const.Stats.Might] = 75,
	[const.Stats.Speed] = -40
}
-- Twilight
GetBonusList(1327).Stats = {
	[const.Stats.Speed] = 50,
	[const.Stats.Luck] = 50,
	[const.Stats.FireResistance] = -15,
	[const.Stats.AirResistance] = -15,
	[const.Stats.WaterResistance] = -15,
	[const.Stats.EarthResistance] = -15,
	[const.Stats.MindResistance] = -15,
	[const.Stats.BodyResistance] = -15,
	[const.Stats.SpiritResistance] = -15
}
-- Ania Selving
GetBonusList(1328).Stats = {[const.Stats.ArmorClass] = -25,
							[const.Stats.Accuracy] = 150}
-- Justice
GetBonusList(1329).Stats = {[const.Stats.Speed] = -40}
-- Mekorig's hammer
GetBonusList(1330).Stats = {[const.Stats.Might] = 75,
							[const.Stats.AirResistance] = -50}
-- Hermes's Sandals
GetBonusList(1331).Stats = { [const.Stats.Speed] = 100,
							[const.Stats.Accuracy] = 50,
							[const.Stats.AirResistance] = 50}
-- Cloak of the sheep
GetBonusList(1332).Stats = { [const.Stats.Intellect] 	= -20,
							[const.Stats.Personality] 	= -20}
-- Mind's Eye
GetBonusList(1334).Stats = {
	[const.Stats.Intellect] = 15,
	[const.Stats.Personality] = 15
}
-- Elven Chainmail
GetBonusList(1335).Stats = {[const.Stats.Speed] = 15,
							[const.Stats.Accuracy] = 15}
-- Forge Gauntlets
GetBonusList(1336).Stats = {
	[const.Stats.Might] = 15,
	[const.Stats.Endurance] = 15,
	[const.Stats.FireResistance] = 30
}
-- Hero's belt
GetBonusList(1337).Stats = {[const.Stats.Might] = 15}
-- Lady's Escort ring
GetBonusList(1338).Stats = {[const.Stats.FireResistance]	= 10,
							[const.Stats.AirResistance]		= 10,
							[const.Stats.WaterResistance]	= 10,
							[const.Stats.EarthResistance]	= 10,
							[const.Stats.MindResistance]	= 10,
							[const.Stats.BodyResistance]	= 10,
							[const.Stats.SpiritResistance]	= 10}
-- Heavenly Warhammer
GetBonusList(1355).Stats = {[const.Stats.EarthResistance] = 65000}
-- Thor
GetBonusList(2021).Stats = {[const.Stats.Might] = 75}
-- Conan
GetBonusList(2022).Stats = {[const.Stats.Might] = 75}
-- Excalibur
GetBonusList(2023).Stats = {[const.Stats.Might] = 30}
-- Merlin
GetBonusList(2024).Stats = {[const.Stats.SP] = 40}
-- Percival
GetBonusList(2025).Stats = {[const.Stats.Speed] = 40}
-- Galahad
GetBonusList(2026).Stats = {[const.Stats.HP] = 25}
-- Pellinore
GetBonusList(2027).Stats = {[const.Stats.Endurance] = 30}
-- Valeria
GetBonusList(2028).Stats = {[const.Stats.Accuracy] = 30}
-- Arthur
GetBonusList(2029).Stats = {
	[const.Stats.Might] = 10,
	[const.Stats.Intellect] = 10,
	[const.Stats.Personality] = 10,
	[const.Stats.Endurance] = 10,
	[const.Stats.Accuracy] = 10,
	[const.Stats.Speed] = 10,
	[const.Stats.Luck] = 10,
	[const.Stats.SP] = 25
}
-- Pendragon
GetBonusList(2030).Stats = {[const.Stats.Luck] = 30}
-- Lucius
GetBonusList(2031).Stats = {[const.Stats.Speed] = 30}
-- Guinevere
GetBonusList(2032).Stats = {[const.Stats.SP] = 30}
-- Igraine
GetBonusList(2033).Stats = {[const.Stats.SP] = 25}
-- Morgan
GetBonusList(2034).Stats = {[const.Stats.SP] = 20}
-- Hades
GetBonusList(2035).Stats = {[const.Stats.Luck] = 20}
-- Ares
GetBonusList(2036).Stats = {[const.Stats.FireResistance] = 25}
-- Poseidon
GetBonusList(2037).Stats = {[const.Stats.Might] 	 = 20,
							[const.Stats.Endurance]  = 20,
							[const.Stats.Accuracy] 	 = 20,
							[const.Stats.Speed] 	 = -10,
							[const.Stats.ArmorClass] = -10}
-- Cronos
GetBonusList(2038).Stats = {[const.Stats.Luck] 	 	= -50,
							[const.Stats.HP] = 100}
-- Hercules
GetBonusList(2039).Stats = {[const.Stats.Might] 	= 50,
							[const.Stats.Endurance] = 20,
							[const.Stats.Intellect]	= -30}
-- Artemis
GetBonusList(2040).Stats = {[const.Stats.FireResistance] 	= -10,
							[const.Stats.AirResistance] 	= -10,
							[const.Stats.WaterResistance] 	= -10,
							[const.Stats.EarthResistance] 	= -10}
-- Apollo
GetBonusList(2041).Stats = {[const.Stats.Endurance]			= -30,
							[const.Stats.FireResistance] 	= 20,
							[const.Stats.AirResistance] 	= 20,
							[const.Stats.WaterResistance] 	= 20,
							[const.Stats.EarthResistance] 	= 20,
							[const.Stats.MindResistance] 	= 20,
							[const.Stats.BodyResistance] 	= 20,
							[const.Stats.SpiritResistance] 	= 20,
							[const.Stats.Luck]				= 20}
-- Zeus
GetBonusList(2042).Stats = {[const.Stats.HP] 		= 50,
							[const.Stats.SP] 		= 50,
							[const.Stats.Luck] 		= 50,
							[const.Stats.Intellect] = -50}
-- Aegis
GetBonusList(2043).Stats = {[const.Stats.Speed] = -20,
							[const.Stats.Luck] 	= 20}
-- Odin
GetBonusList(2044).Stats = {
	[const.Stats.Speed] = -40,
	[const.Stats.FireResistance] = 50,
	[const.Stats.AirResistance] = 50,
	[const.Stats.WaterResistance] = 50,
	[const.Stats.EarthResistance] = 50
}
-- Atlas
GetBonusList(2045).Stats = {
	[const.Stats.Might] = 100,
	[const.Stats.Speed] = -40
}
-- Hermes
GetBonusList(2046).Stats = {
	[const.Stats.Speed] = 100,
	[const.Stats.Accuracy] = -40
}
-- Aphrodite
GetBonusList(2047).Stats = {[const.Stats.Personality] = 100,
							[const.Stats.Luck] 	= -40}
-- Athena
GetBonusList(2048).Stats = {[const.Stats.Intellect] = 100,
							[const.Stats.Might] 	= -40}
-- Hera
GetBonusList(2049).Stats = {[const.Stats.HP] = 50,
							[const.Stats.SP] = 50,
							[const.Stats.Luck] = 50,
							[const.Stats.Personality] = -50}
							
-- Spirit, Light and Dark resistances stdbonuses
function events.CalcStatBonusByItems(t)
	local SLDBonuses = {30, 31, 32}
	local SLDRes = {const.Stats.SpiritResistance, const.Stats.LightResistance, const.Stats.DarkResistance}
	local Player = t.Player
	for item, slot in Player:EnumActiveItems() do
		if table.find(SLDBonuses, item.Bonus) then
			if item.Bonus == 30 then
				if t.Stat == SLDRes[1] then
					t.Result = t.Result + item.BonusStrength
				end
			elseif item.Bonus == 31 then
				if t.Stat == SLDRes[2] then
					t.Result = t.Result + item.BonusStrength
				end
			elseif item.Bonus == 32 then
				if t.Stat == SLDRes[3] then
					t.Result = t.Result + item.BonusStrength
				end
			end
		end
	end
end

--------------------------------
---- Skill bonuses

-- Hero's belt
GetBonusList(1337).Skills =	{	[const.Skills.Armsmaster] = 5}
--Clanker's Amulet
GetBonusList(1339).Skills =	{	[const.Skills.Alchemy] = 10}
Game.ItemsTxt[1339].Bonus = 0

-- Wallace
GetBonusList(1304).Skills =	{	[const.Skills.Armsmaster] = 10}
-- Corsair
GetBonusList(1305).Skills =	{	[const.Skills.DisarmTraps] = 10}
-- Hands of the Master
GetBonusList(1313).Skills =	{	[const.Skills.Unarmed] = 10,
								[const.Skills.Dodging] = 10}
-- Ethric's Staff
GetBonusList(1317).Skills =	{	[const.Skills.Meditation] = 15}
-- Hareck's Leather
GetBonusList(1318).Skills =	{	[const.Skills.DisarmTraps] = 5,
								[const.Skills.Unarmed] = 5,}
-- Old Nick
GetBonusList(1319).Skills =	{	[const.Skills.DisarmTraps] = 5}
-- Glory shield
GetBonusList(1321).Skills =	{	[const.Skills.Shield] = 5}
-- Scholar's Cap
GetBonusList(1324).Skills = {[const.Skills.Learning] = 15}
-- Ania Selving
GetBonusList(1328).Skills =	{	[const.Skills.Bow] = 5}
-- Faerie ring
--[[GetBonusList(1348).Skills =	{	[const.Skills.Fire] = 5,
								[const.Skills.Air] = 5,
								[const.Skills.Water] = 5,
								[const.Skills.Earth] = 5}
]]
-- Hades
GetBonusList(2035).Skills =	{	[const.Skills.DisarmTraps] = 10}

-- Energy Shield Meditation bonus
function events.CalcStatBonusByItems(t)
	local Player = t.Player
	local MedS, MedM = SplitSkill(Player.Skills[const.Skills.Meditation])
	
	if MedS == 0 then return end
	if t.Stat ~= const.Stats.Meditation then return end
	
	local BS, BM = SplitSkill(Player:GetSkill(7))
	local BeltItem = Player.ItemBelt
	if BeltItem > 0 then
		local BeltNum = Player.Items[BeltItem].Number
		if BeltNum == 968 and not Player.Items[BeltItem].Broken then
			t:SetArtifactBonus(BS)
		end
	end
end

--------------------------------
---- Spell bonuses

-- Staffs boost magic skills
function events.CalcStatBonusByItems(t)
	if t.Stat < 34 or t.Stat > 42 then
		return
	end
	local Player = t.Player
	local StaffSlot = Player.ItemMainHand
	if StaffSlot > 0 then
		local StaffNum = Player.Items[StaffSlot].Number
		local IsStaff = Game.ItemsTxt[StaffNum].Skill
		if IsStaff == const.Skills.Staff and not Player.Items[StaffSlot].Broken then
			local SS, SM = SplitSkill(Player:GetSkill(0))
			SMDiv = 5 - SM
			StaffFocusPower = math.min(Game.ItemsTxt[StaffNum].Mod2,math.min(SS,select(SM, 3, 6, 9, 20))) + Game.ItemsTxt[StaffNum].Mod1DiceCount*Game.ItemsTxt[StaffNum].Mod1DiceSides/SMDiv
			t:SetArtifactBonus(StaffFocusPower)
		end
	end
end

-- Eclipse
GetBonusList(516).SpellBonus =	{[const.Skills.Spirit] = true, [const.Skills.Body] = true, [const.Skills.Mind] = true}
-- Crown of final Dominion
GetBonusList(521).SpellBonus =	{[const.Skills.Dark] = true}
-- Staff of Elements
GetBonusList(530).SpellBonus =	{[const.Skills.Fire] = true, [const.Skills.Air] = true, [const.Skills.Water] = true, [const.Skills.Earth] = true}
-- Ring of Fusion
GetBonusList(535).SpellBonus =	{[const.Skills.Water] = true}
-- Seven League Boots
GetBonusList(1314).SpellBonus =	{[const.Skills.Water] = true}
-- Ruler's Ring
GetBonusList(1315).SpellBonus =	{[const.Skills.Mind] = true, [const.Skills.Dark] = true}
-- Ethric's Staff
GetBonusList(1317).SpellBonus =	{[const.Skills.Dark] = true}
-- Glory Shield
GetBonusList(1321).SpellBonus =	{[const.Skills.Spirit] = true}
-- Taledon's Helm
GetBonusList(1323).SpellBonus = {[const.Skills.Light] = true}
-- Phynaxian Crown
GetBonusList(1325).SpellBonus = {[const.Skills.Fire] = true}
-- Justice
GetBonusList(1329).SpellBonus =	{[const.Skills.Mind] = true,
								[const.Skills.Body] = true}
-- Mekorig's hammer
GetBonusList(1330).SpellBonus =	{[const.Skills.Spirit] = true}
-- Ghost ring
GetBonusList(1347).SpellBonus =	{[const.Skills.Spirit] = true}
-- Faerie ring
GetBonusList(1348).SpellBonus =	{[const.Skills.Air] = true}
-- Guinevere
GetBonusList(2032).SpellBonus =	{[const.Skills.Light] = true, [const.Skills.Dark] = true}
-- Igraine
GetBonusList(2033).SpellBonus =	{[const.Skills.Spirit] = true, [const.Skills.Body] = true, [const.Skills.Mind] = true}
-- Morgan
GetBonusList(2034).SpellBonus =	{[const.Skills.Fire] = true, [const.Skills.Air] = true, [const.Skills.Water] = true, [const.Skills.Earth] = true}

--------------------------------
---- Buffs and extra effects
-- Runeblade
GetBonusList(550).Buffs = {[const.PlayerBuff.Bless] = 20}
-- Lady's Escort ring
--GetBonusList(1338).Buffs = {[const.PlayerBuff.WaterBreathing] = 0} -- Buff = Skill
-- Governor's Armor
GetBonusList(1306).Buffs = {[const.PlayerBuff.Shield] = 3}
-- Hareck's Leather
--GetBonusList(1318).Buffs = {[const.PlayerBuff.WaterBreathing] = 0}
-- Kelebrim
GetBonusList(1322).Buffs = {[const.PlayerBuff.Shield] = 3}
-- Elfbane
GetBonusList(1333).Buffs = {[const.PlayerBuff.Shield] = 3}
-- Ghost ring
GetBonusList(1347).Buffs = {[const.PlayerBuff.Preservation] = 3}
GetBonusList(1347).Stats = {[const.Stats.SpiritResistance] = 10}
-- Wetsuit
--GetBonusList(1406).Buffs = {[const.PlayerBuff.WaterBreathing] = 0}
-- Excalibur
GetBonusList(2023).Buffs = {[const.PlayerBuff.Bless] = 3}
-- Galahad
GetBonusList(2026).Buffs = {[const.PlayerBuff.Shield] = 3,
							[const.PlayerBuff.Stoneskin] = 20}
--Pellinore
GetBonusList(2027).Buffs = {[const.PlayerBuff.Stoneskin] = 20}
-- Valeria
GetBonusList(2028).Buffs = {[const.PlayerBuff.Shield] = 3}
-- Aegis
GetBonusList(2043).Buffs = {[const.PlayerBuff.Shield] = 3}

--------------------------------
---- Party Buffs

-- Aegis
GetBonusList(2043).PartyBuffs = {
	ReqMastery = 4,
	Buff = {[const.PartyBuff.Shield] = JoinSkill(7, 3)}
}

--------------------------------
---- Effect Immunities

-- Yoruba
GetBonusList(1307).EffectImmunities = {	[const.MonsterBonus.Insane] 	= true,
							[const.MonsterBonus.Disease1] 	= true,
							[const.MonsterBonus.Disease2] 	= true,
							[const.MonsterBonus.Disease3] 	= true,
							[const.MonsterBonus.Paralyze] 	= true,
							[const.MonsterBonus.Stone] 		= true,
							[const.MonsterBonus.Poison1] 	= true,
							[const.MonsterBonus.Poison2] 	= true,
							[const.MonsterBonus.Poison3] 	= true,
							[const.MonsterBonus.Asleep] 	= true}
-- Ghoulsbane
GetBonusList(1309).EffectImmunities = {[const.MonsterBonus.Paralyze] = true}
-- Kelebrim
GetBonusList(1322).EffectImmunities = {[const.MonsterBonus.Stone] = true}
-- Cloak of the sheep
GetBonusList(1332).EffectImmunities = {	[const.MonsterBonus.Insane] 	= true,
							[const.MonsterBonus.Disease1] 	= true,
							[const.MonsterBonus.Disease2] 	= true,
							[const.MonsterBonus.Disease3] 	= true,
							[const.MonsterBonus.Paralyze] 	= true,
							[const.MonsterBonus.Stone] 		= true,
							[const.MonsterBonus.Poison1] 	= true,
							[const.MonsterBonus.Poison2] 	= true,
							[const.MonsterBonus.Poison3] 	= true,
							[const.MonsterBonus.Asleep] 	= true}
-- Medusa's mirror
GetBonusList(1341).EffectImmunities = {[const.MonsterBonus.Stone] = true}
-- Pendragon
GetBonusList(2030).EffectImmunities = {
	[const.MonsterBonus.Poison1] = true,
	[const.MonsterBonus.Poison2] = true,
	[const.MonsterBonus.Poison3] = true
}
-- Aegis
GetBonusList(2043).EffectImmunities = {[const.MonsterBonus.Stone] = true}

--------------------------------
---- Attack delay mods

-- Mournbringer
GetBonusList(545).ModAttackDelay = -20
-- Runeblade
GetBonusList(550).ModAttackDelay = -20
-- Supreme plate
GetBonusList(515).ModAttackDelay = -20
-- Percival
GetBonusList(2025).ModAttackDelay = -20
-- Puck
GetBonusList(1302).ModAttackDelay = -20
-- Merlin
GetBonusList(2024).ModAttackDelay = -20

--------------------------------
---- HP/SP regen

-- Scepter of Kings
GetBonusList(509).HPSPRegen = {HP = 2}
-- Serendine's Preservation
GetBonusList(513).HPSPRegen = {SP = 3}
-- Drogg's Helm
GetBonusList(520).HPSPRegen = {HP = 2}
-- Runeblade
GetBonusList(550).HPSPRegen = {HP = 5, SP = 5}
-- Hermes's Sandals
GetBonusList(1331).HPSPRegen = {HP = 3, SP = 3}
-- Mind's Eye
GetBonusList(1334).HPSPRegen = {SP = 3}
-- Elven Chainmail
GetBonusList(1335).HPSPRegen = {HP = 3}
-- Hero's belt
GetBonusList(1337).HPSPRegen = {HP = 3}
-- Merlin
GetBonusList(2024).HPSPRegen = {SP = 3}
-- Pellinore
GetBonusList(2027).HPSPRegen = {HP = 3}
-- Guinevere
GetBonusList(2032).HPSPRegen = {SP = 3}
-- Igraine
GetBonusList(2033).HPSPRegen = {SP = 3}
-- Morgan
GetBonusList(2034).HPSPRegen = {SP = 3}
-- Hades
GetBonusList(2035).HPSPRegen = {HP = -3}

-- Energy Shield
GetBonusList(968).HPSPRegen = {SP = 5}

function events.CalcStatBonusByItems(t)
	local Player = t.Player
	local ResStatInd = {10, 11, 12, 13, 14, 15, 9, 33, 50, 51}
	--local ResBonusInd = {0, 1, 2, 3, 7, 8}
	--local HiddenStats = {}
	if Player.ItemBelt > 0 and Player.Items[Player.ItemBelt].Number == 968 and not Player.Items[Player.ItemBelt].Broken then
		for i = 1, 10 do
			if t.Stat == ResStatInd[i] then
				t.Result = t.Result + Player.SP/10
			end
		end
	end
end

GetSpcBonusList(1).Stats = {
	[const.Stats.SpiritResistance] = 10,
	[const.Stats.LightResistance] = 10,
	[const.Stats.DarkResistance] = 10
	}
GetSpcBonusList(37).HPSPRegen = {HP = 2}
GetSpcBonusList(38).HPSPRegen = {SP = 1}
GetSpcBonusList(42).Stats = {
	[const.Stats.SpiritResistance] = 1,
	[const.Stats.LightResistance] = 1,
	[const.Stats.DarkResistance] = 1
	}
GetSpcBonusList(44).HPSPRegen = {HP = 2}
GetSpcBonusList(47).HPSPRegen = {SP = 1}
GetSpcBonusList(50).HPSPRegen = {HP = 3}
GetSpcBonusList(54).HPSPRegen = {HP = 2}
GetSpcBonusList(55).HPSPRegen = {SP = 1}
GetSpcBonusList(66).HPSPRegen = {HP = 2, SP = 1}

GetSpcBonusList(73).EffectImmunities = {
	[const.MonsterBonus.Dead] 	= true,
	[const.MonsterBonus.Errad] 	= true}
	
GetSpcBonusList(139).Stats = {
	[const.Stats.FireResistance] = 5,
	[const.Stats.AirResistance] = 5,
	[const.Stats.WaterResistance] = 5,
	[const.Stats.EarthResistance] = 5
}
GetSpcBonusList(140).Stats = {
	[const.Stats.MindResistance] = 5,
	[const.Stats.BodyResistance] = 5,
	[const.Stats.SpiritResistance] = 5
}
GetSpcBonusList(141).Stats = {
	[const.Stats.LightResistance] = 5,
	[const.Stats.DarkResistance] = 5
}
GetSpcBonusList(142).Stats = {
	[const.Stats.FireResistance] = 15,
	[const.Stats.AirResistance] = 15,
	[const.Stats.WaterResistance] = 15,
	[const.Stats.EarthResistance] = 15
}
GetSpcBonusList(143).Stats = {
	[const.Stats.MindResistance] = 15,
	[const.Stats.BodyResistance] = 15,
	[const.Stats.SpiritResistance] = 15
}
GetSpcBonusList(144).Stats = {
	[const.Stats.LightResistance] = 15,
	[const.Stats.DarkResistance] = 15
}

--------------------------------
---- Over time item effects

-- Cycle of life
GetBonusList(543).OverTimeEffect = function(Player, PlayerId)
	SharedLife(Player, PlayerId)
end

-- Ethric's Staff
GetBonusList(1317).OverTimeEffect =	function(Player, PlayerId)
	local race_family = Game.Races[GetCharRace(Player)].Family
	--if Player.Class ~= const.Class.MasterNecromancer then
	if race_family ~= const.RaceFamily.Undead and race_family ~= const.RaceFamily.Ghost then
		HPSPoverTime(Player, "HP", -3, PlayerId)
	end
end

------------------------------------
---- Additional item Special Bonuses
-- See SPCITEMS.TXT
-- Supported bonuses:
--   Additional damage (excl): 4-15,46,67,68,80-88
--   Vampiric (excl): 16,41
--   Double damage: 39,40,63-65,74-79
--   Carnage: 3
--   Water walking: 71
--   Feather Falling: 72
-- Mournbringer
ItemSpcBonuses[545] = {16}

-- Elsenrail
ItemSpcBonuses[500] = {87}
-- Glomenthal
ItemSpcBonuses[501] = {88}
-- Judicious Measure
ItemSpcBonuses[503] = {39}
-- Elderaxe (buffed to 9-12 Water damage)
ItemSpcBonuses[504] = {6} --{6, 59}
-- Volcano
ItemSpcBonuses[505] = {80}
-- Wyrm Spitter
ItemSpcBonuses[506] = {40} --{40, 59}
-- Guardian
ItemSpcBonuses[507] = {86}
-- Foulfang (buffed to 12 Body damage)
ItemSpcBonuses[508] = {15, 16}
-- Breaker
ItemSpcBonuses[510] = {86}
-- Staff of the Swamp
--ItemSpcBonuses[511] = {36}
-- Longseeker
--ItemSpcBonuses[512] = {59}
-- Supreme Plate
--ItemSpcBonuses[515] = {59}
-- Herald's Boots
--ItemSpcBonuses[518] = {59}
-- Archangel Wings
--ItemSpcBonuses[522] = {72}
-- Finality
ItemSpcBonuses[525] = {80}
-- Spiritslayer
ItemSpcBonuses[527] = {16}
-- Trident of Rulership
--ItemSpcBonuses[528] = {71}
-- Blade of Mercy
ItemSpcBonuses[529] = {8}
-- Lightning Crossbow
--ItemSpcBonuses[532] = {59}
-- Mace of the Sun (Special)
--ItemSpcBonuses[538] = {63}
-- Ebonest (Special)
--ItemSpcBonuses[539] = {40}
-- Sword of Whistlebone (Special)
--ItemSpcBonuses[540] = {40}
-- Axe of Balthazar (Special)
--ItemSpcBonuses[541] = {6}
-- Noblebone Bow (Special)
--ItemSpcBonuses[542] = {3}
-- Puck
--ItemSpcBonuses[1302] = {59}
-- Iron Feather
ItemSpcBonuses[1303] = {9}
-- Governor's Armor
--ItemSpcBonuses[1306] = {36}
-- Splitter
--ItemSpcBonuses[1308] = {24}
-- Ghoulsbane
ItemSpcBonuses[1309] = {12, 64}
-- Gibbet
ItemSpcBonuses[1310] = {40, 64, 74}
-- Ullyses
ItemSpcBonuses[1312] = {6}
-- Hareck's Leather
ItemSpcBonuses[1318] = {71}
-- Old Nick
ItemSpcBonuses[1319] = {14, 75}
-- Kelebrim
--ItemSpcBonuses[1322] = {36}
-- Justice
ItemSpcBonuses[1329] = {64}
-- Hermes' Sandals
ItemSpcBonuses[1331] = {72}
-- Elfbane
ItemSpcBonuses[1333] = {75} --{36, 75}
-- Lady's Escort ring
ItemSpcBonuses[1338] = {71, 72}
-- Lieutenant's Cutlass (Special)
--ItemSpcBonuses[1340] = {46}
-- Villain's Blade (Special)
--ItemSpcBonuses[1343] = {16}
-- Grognard's Cutlass (Special)
ItemSpcBonuses[1354] = {75}
-- Wetsuit
ItemSpcBonuses[1406] = {71}
-- Winged Sandals
ItemSpcBonuses[1439] = {72}
-- Mordred
ItemSpcBonuses[2020] = {16}
-- Thor
--ItemSpcBonuses[2021] = {24}
-- Conan
ItemSpcBonuses[2022] = {40, 74}
-- Merlin
--ItemSpcBonuses[2024] = {59}
-- Percival
ItemSpcBonuses[2025] = {3, 59}
-- Valeria
--ItemSpcBonuses[2028] = {36}
-- Pendragon
ItemSpcBonuses[2030] = {35}
-- Artemis
--ItemSpcBonuses[2040] = {24}
-- Aegis
--ItemSpcBonuses[2043] = {36}

--------------------------------
---- Arrow projectiles

-- Ullyses
ArrowProjectiles[1312] = 3030

--------------------------------
---- On-hit item effects (only weapons)

-- FIXME: Monster positions seems to be a corner of the sprite.
--     Should be increased by half of the sprite size.
local function CastSpellTowardsMonster(Spell, Skill, Mastery, Monster)
	local dist_c = spell_distance / sqrt((Monster.X - Party.X) ^ 2 +
		(Monster.Y - Party.Y) ^ 2 + (Monster.Z - Party.Z) ^ 2)
	 evt.CastSpell(Spell, Mastery, Skill,
		Monster.X - floor((Monster.X - Party.X) * dist_c),
		Monster.Y - floor((Monster.Y - Party.Y) * dist_c),
		Monster.Z - floor((Monster.Z - Party.Z) * dist_c),
		Monster.X, Monster.Y, Monster.Z)
end
-- Mournbringer
OnHitEffects[545] = {
	DamageKind	= const.Damage.Dark,
	Add			= 20}--,
--	Special = function(t)
--		local SoundNum = {44590, 44591, 44592, 44593, 44594, 44595, 44596}
--			evt.PlaySound{SoundNum[math.random(1,7)]}
--	end}
	
-- Runeblade
OnHitEffects[550] = {
	DamageKind	= const.Damage.Light,
	Add			= 30}
-- Splitter
OnHitEffects[1308] = {
	DamageKind 	= const.Damage.Fire,
	Add			= 10,
	Special = function(t)
		local Skill, Mas = SpellPowerByItemSkill(t.Player, t.Item)
		CastSpellDirect(125,Skill,Mas)
		--evt.CastSpell(6, Mas, Skill, t.Monster.X,t.Monster.Y,t.Monster.Z+50, t.Monster.X,t.Monster.Y,t.Monster.Z)
		CastSpellTowardsMonster(6, Skill, Mas, t.Monster)
	end}
-- Heavenly Warhammer
OnHitEffects[1355] = {
	DamageKind	= const.Damage.Energy,
	Add			= 20,
	Special = function(t)
		local Skill, Mas = SpellPowerByItemSkill(t.Player, t.Item)
		CastSpellDirect(125,Skill,Mas)
		evt.CastSpell(41, Mas, Skill, t.Monster.X,t.Monster.Y,t.Monster.Z+50, t.Monster.X,t.Monster.Y,t.Monster.Z)	
		--evt.PlaySound{44597}
	end}
-- Okkam's Razor
OnHitEffects[1356] = {
	DamageKind = const.Damage.Energy,
	Add = 15}
-- Thor
OnHitEffects[2021] = {
	Add			= 10,
	Special = function(t)
		CastSpellDirect(125, 7, 3)
		if t.Monster.HP - t.Result > 0 then
			local Skill, Mas = SpellPowerByItemSkill(t.Player, t.Item)
			evt.CastSpell(18, Mas, Skill, t.Monster.X,t.Monster.Y,t.Monster.Z+50, t.Monster.X,t.Monster.Y,t.Monster.Z)
		end
	end}
-- Excalibur
OnHitEffects[2023] = {
	Add			= 10,
	Special = function(t)
		local montype = Game.Bolster.Monsters[t.Monster.Id].Type
		if	montype == const.MonsterKind.Dragon then
			t.Result = t.Result*2
		end
	end}
-- Hades
OnHitEffects[2035] = {
	DamageKind 	= const.Damage.Water,
	Add = 20,
	Special = function(t)
		local Skill, Mas = SpellPowerByItemSkill(t.Player, t.Item)
		CastSpellDirect(29, Skill, Mas)
	end}
-- Ares
OnHitEffects[2036] = {
	DamageKind 	= const.Damage.Fire,
	Add = 30}
-- Artemis
OnHitEffects[2040] = {
	DamageKind 	= const.Damage.Air,
	Add			= 20,
	Special = function(t)
		local Skill, Mas = SpellPowerByItemSkill(t.Player, t.Item)
		CastSpellDirect(125,Skill,Mas)
		evt.CastSpell(18, Mas, Skill, t.Monster.X,t.Monster.Y,t.Monster.Z+50, t.Monster.X,t.Monster.Y,t.Monster.Z)
	end}
	
MF.LogInit2(LogId)
