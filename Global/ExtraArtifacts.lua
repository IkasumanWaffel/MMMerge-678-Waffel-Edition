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
-- Make unique items one-time spawns
-- (22.11.26) Xfing's rules (Celestial Heavens, "script revision 9"), ported to the Waffel
-- Edition with its own items:
--   * every artifact, relic and equippable special item is recorded once it appears in the
--     world (generated loot, a map's chests, ground or monsters) and the record is never
--     undone: selling, losing or stashing an item doesn't make it come back
--   * a random artifact or relic that is already recorded becomes an unrecorded one; once all
--     are recorded, an ordinary item of treasure class 6 of the same kind
--   * on a map refill, the fixed placements already recorded are taken away: chests of
--     Judicious Measure, Snake and Noblebone Bow get another unrecorded artifact (or TC6
--     loot), the special items ordinary TC5 loot, named monster drops (Villain's Blade, the
--     Cutlasses, Minotaur's Axe, the cloaks...) the monster's ordinary treasure
--   * quest items stay until their quest is done (Mordred, Ebonest, Whistlebone, Balthazar's
--     Axe); the Perfect Bow and the Waffel Edition's scripted items (Padish's Signet, the
--     Command Cube, the Leathers of the Road Warrior, the Ancients' gear) are left to their
--     own scripts
--   * specials that aren't equipment (MM6's Horseshoes, Lodestones, Harpy Feathers...) are
--     left to the game, as their quests and buyers expect
-- Material in Items.txt: 0 normal, 1 artifact, 2 relic, 3 special.

-- fixed map placements: never in the random pool, registered by the map scan
local FixedPlacementItems = {
	-- MM8 artifacts and relics placed by the maps
	501, 502, 503, 504, 508, 509, 516, 519, 523, 538, 539, 540, 541, 542,
	-- MM7 placed artifacts and named special items
	1333, 1334, 1335, 1336, 1337, 1338,
	1339, 1340, 1341, 1342, 1343, 1347, 1348, 1351, 1352, 1353, 1354,
	-- MM6
	2020, 2023, 2032, 2033, 2034,
}

-- fixed chest items that become another unrecorded artifact when their chest refills
local GuaranteedUniqueRespawnChestItems = {
	[503] = true,   -- Judicious Measure: Ravage Roaming
	[523] = true,   -- Snake: Dragon Hunter's Camp
	[542] = true,   -- Noblebone Bow: Yaardrake's Cave
}

-- special items placed by the maps: what they become once recorded (default: TC5 loot of
-- the same kind)
local FixedSpecialRespawnFallbacks = {
	[538]  = {AnyWeapon = true},                                     -- Mace of the Sun
	[1347] = {Strength = 5, ItemType = const.ItemType.Ring},         -- Ghost Ring
	[1348] = {Strength = 5, ItemType = const.ItemType.Ring},         -- Faerie Ring
}

-- named monster drops: back to the monster's ordinary treasure once looted
local MonsterSpecialDropItems = {
	[1339] = true,   -- Clanker's Amulet
	[1340] = true,   -- Lieutenant's Cutlass
	[1341] = true,   -- Medusa's Mirror
	[1342] = true,   -- Lady Carmine's Dagger
	[1343] = true,   -- Villain's Blade
	[1349] = true,   -- Sun Cloak
	[1350] = true,   -- Moon Cloak
	[1352] = true,   -- Vampire's Cape
	[1353] = true,   -- Minotaur's Axe
	[1354] = true,   -- Grognard's Cutlass
}

-- left entirely to their own scripts
local NativeQuestControlledItems = {
	[1344] = true, [1345] = true,   -- The Perfect Bow (quest and fixed): its MM7 map script
	[2213] = true,                  -- Padish's Signet: the Forge story's guardian (MMMWE_ForgeStory.lua)
	[2220] = true,                  -- Command Cube: the Gate story's guardian (MMMWE_GateStory.lua)
	[2259] = true,                  -- Leathers of the Road Warrior: once per game (MMMWE_RoadWarrior.lua)
	-- the Ancients' gear (MMMWE_AncientArtifacts.lua), not in the loot yet
	[2214] = true, [2215] = true, [2216] = true, [2217] = true, [2218] = true, [2219] = true,
	[2221] = true, [2222] = true, [2223] = true, [2224] = true,
}

-- quest items: available until the quest is done (award numbers of the Waffel Edition's
-- Awards.txt; Xfing's 24/26/27/47 are Arcomage and Arena awards here)
local QuestCompletionAwards = {
	[2020] = 205,  -- Mordred: "Found Zoltan's Artifact" (MM6)
	[539]  = 74,   -- Ebonest: "Returned Ebonest to Charles Quixote" (MM8)
	[541]  = 79,   -- "Recovered Axe of Balthazar" (MM8)
	[540]  = 77,   -- "Gave the Sword of Whistlebone the Slayer to the Deftclaw Redreaver" (MM8)
}
local QuestCompletionItems = {}
for id in pairs(QuestCompletionAwards) do QuestCompletionItems[id] = true end

vars.UniqueQuestItemCompletion = vars.UniqueQuestItemCompletion or {}

local function IsQuestItemCompleted(ItemId)
	if vars.UniqueQuestItemCompletion[ItemId] == true then
		return true
	end
	local AwardIndex = QuestCompletionAwards[ItemId]
	if AwardIndex then
		for _, Player in Party.PlayersArray do
			local Award = Player.Awards and Player.Awards[AwardIndex]
			if Award == true or Award == 1 then
				return true
			end
		end
	end
	return false
end

local FixedPlacementSet = {}
for _, id in ipairs(FixedPlacementItems) do
	FixedPlacementSet[id] = true
end

-- the record: vars.GotArtifact[item] = true, append-only (tracking version 4, as Xfing's).
-- Saves of the old Merge tracking keep what they had recorded, and the artifacts the old
-- code had placed in the world (vars.PlacedArtifacts > 0) count as recorded.
vars.GotArtifact = vars.GotArtifact or {}
if vars.UniqueArtifactTrackingVersion ~= 4 then
	for id, v in pairs(vars.GotArtifact) do
		if not v then vars.GotArtifact[id] = nil end
	end
	for id, v in pairs(vars.PlacedArtifacts or {}) do
		if type(v) == "number" and v > 0 then vars.GotArtifact[id] = true end
	end
	vars.PlacedArtifacts = nil
	vars.NextArtifactsRefill = nil
	vars.UniqueArtifactTrackingVersion = 4
	vars.UniqueArtifactHistoryInitialized = false
end

local function isEquipment(txt)
	return txt.EquipStat >= 0 and txt.EquipStat <= 11
end

local UniqueItemSet = {}
local RandomUniquePool = {}
for id, txt in Game.ItemsTxt do
	local mat = txt.Material or 0
	if mat > 0 and not NativeQuestControlledItems[id]
			and (mat ~= 3 or isEquipment(txt) or FixedPlacementSet[id]) then
		UniqueItemSet[id] = true
		-- only artifacts and relics that can be found at random make the replacement pool
		if (mat == 1 or mat == 2) and txt.Value > 0 and txt.ChanceByLevel[6] > 0
				and not FixedPlacementSet[id] then
			table.insert(RandomUniquePool, id)
		end
	end
end
for id in pairs(GuaranteedUniqueRespawnChestItems) do UniqueItemSet[id] = true end
for id in pairs(FixedSpecialRespawnFallbacks) do UniqueItemSet[id] = true end
for id in pairs(MonsterSpecialDropItems) do UniqueItemSet[id] = true end

local function GetNotFoundArts()
	local t = {}
	for _, id in ipairs(RandomUniquePool) do
		if not vars.GotArtifact[id] then
			table.insert(t, id)
		end
	end
	return t
end
Game.UniqueItemsNotFound = GetNotFoundArts

local function noRefund(Item)
	if Item.Refundable ~= nil then
		Item.Refundable = false
	end
end

local function SetItemToId(Item, ItemId)
	Item:Clear()
	Item.Number = ItemId
	local Txt = Game.ItemsTxt[ItemId]
	if Txt then
		Item.Bonus = Txt.Bonus or 0
		Item.Bonus2 = Txt.Bonus2 or 0
		Item.BonusStrength = Txt.BonusStrength or 0
		if Txt.Material == 3 then
			Item:InitSpecial()
		end
	end
	Item.Identified = false
	noRefund(Item)
end

-- ordinary items of a treasure class (1..6) and kind; never another unique
local function RandomizeOrdinaryItem(Item, Strength, ItemType)
	Strength = Strength or 5
	ItemType = ItemType or const.ItemType.Any
	for _ = 1, 64 do
		Item:Randomize(Strength, ItemType)
		local Txt = Game.ItemsTxt[Item.Number]
		if Item.Number > 0 and Txt and (Txt.Material or 0) == 0
				and Txt.ChanceByLevel[Strength] > 0 then
			noRefund(Item)
			return true
		end
	end
	Item:Clear()
	return false
end

-- an ordinary TC5 weapon: one-handed, two-handed or missile
local TC5WeaponKinds = {const.ItemType.Weapon, const.ItemType.Weapon2H, const.ItemType.Missile}
local TC5WeaponKindSet = {
	[const.ItemType.Weapon] = true, [const.ItemType.Weapon2H] = true, [const.ItemType.Missile] = true,
}
local TC5WeaponPool = {}
for id, txt in Game.ItemsTxt do
	if (txt.Material or 0) == 0 and txt.ChanceByLevel[5] > 0 and TC5WeaponKindSet[txt.EquipStat + 1] then
		table.insert(TC5WeaponPool, id)
	end
end

local function RandomizeOrdinaryWeaponTC5(Item)
	for _ = 1, 96 do
		Item:Randomize(5, TC5WeaponKinds[random(#TC5WeaponKinds)])
		local Txt = Game.ItemsTxt[Item.Number]
		if Item.Number > 0 and Txt and (Txt.Material or 0) == 0 and Txt.ChanceByLevel[5] > 0
				and TC5WeaponKindSet[Txt.EquipStat + 1] then
			noRefund(Item)
			return true
		end
	end
	if #TC5WeaponPool > 0 then
		SetItemToId(Item, TC5WeaponPool[random(#TC5WeaponPool)])
		return true
	end
	Item:Clear()
	return false
end

-- an ordinary TC6 item of the kind of the item it replaces
local OrdinaryTreasure6Pool, OrdinaryTreasure6PoolByType = {}, {}
for id, txt in Game.ItemsTxt do
	if (txt.Material or 0) == 0 and txt.Value > 0 and txt.ChanceByLevel[6] > 0 then
		table.insert(OrdinaryTreasure6Pool, id)
		local ItemType = txt.EquipStat + 1
		OrdinaryTreasure6PoolByType[ItemType] = OrdinaryTreasure6PoolByType[ItemType] or {}
		table.insert(OrdinaryTreasure6PoolByType[ItemType], id)
	end
end

local function RandomizeOrdinaryTreasure6(Item, OriginalItemId)
	local ItemType = Game.ItemsTxt[OriginalItemId].EquipStat + 1
	if RandomizeOrdinaryItem(Item, 6, ItemType) then
		return
	end
	local Pool = OrdinaryTreasure6PoolByType[ItemType]
	if not Pool or #Pool == 0 then
		Pool = OrdinaryTreasure6Pool
	end
	if #Pool > 0 then
		SetItemToId(Item, Pool[random(#Pool)])
	else
		Item:Clear()
	end
end

-- generated loot (chests, corpses, shops, events): recorded when it is generated
function events.ItemGenerated(t)
	local Item = t.Item
	local ItemId = Item.Number
	local ItemTxt = Game.ItemsTxt[ItemId]
	if not ItemTxt or NativeQuestControlledItems[ItemId] then
		return
	end

	if QuestCompletionItems[ItemId] then
		if not IsQuestItemCompleted(ItemId) then
			return
		end
		vars.GotArtifact[ItemId] = true
		if ItemId == 540 then
			-- Jeric Whistlebone's drop becomes his ordinary treasure after the quest
			RandomizeOrdinaryItem(Item, t.Strength, t.Kind)
		else
			Item:Clear()
		end
		return
	end

	if MonsterSpecialDropItems[ItemId] then
		-- recorded when it reaches the party (RecordLootedMonsterSpecials), not when the
		-- corpse gets it
		if vars.GotArtifact[ItemId] then
			RandomizeOrdinaryItem(Item, t.Strength, t.Kind)
		else
			noRefund(Item)
		end
		return
	end

	if not UniqueItemSet[ItemId] then
		return
	end

	if (ItemTxt.Material or 0) == 3 then
		if vars.GotArtifact[ItemId] then
			RandomizeOrdinaryItem(Item, t.Strength, t.Kind)
		else
			vars.GotArtifact[ItemId] = true
			noRefund(Item)
		end
		return
	end

	if FixedPlacementSet[ItemId] then
		-- fixed placements don't come as random loot: a gem instead
		SetItemToId(Item, random(177, 186))
		return
	end

	if vars.GotArtifact[ItemId] then
		local Available = GetNotFoundArts()
		if #Available > 0 then
			ItemId = Available[random(#Available)]
			SetItemToId(Item, ItemId)
		else
			RandomizeOrdinaryTreasure6(Item, ItemId)
			Log(Merge.Log.Info, "ItemGenerated: no artifacts left, %d -> %d", ItemId, Item.Number)
			return
		end
	end
	-- record the final item, not the one it replaced
	vars.GotArtifact[ItemId] = true
	noRefund(Item)
	Log(Merge.Log.Info, "ItemGenerated: unique %d", ItemId)
end

-- the artifact the game picks: only the fixed placements are filtered out here
-- (ItemGenerated records and replaces once the item is made)
function events.ArtifactGenerated(t)
	if FixedPlacementSet[t.ItemId] and not MonsterSpecialDropItems[t.ItemId] then
		t.ItemId = random(177, 186)
	end
end

-- a unique placed by the map (chest, ground): recorded; on a refill, removed or replaced
local function ProcessMapSpawnItem(Item, IsMapRefill)
	if not Item then
		return false
	end
	local ItemId = Item.Number
	if NativeQuestControlledItems[ItemId] then
		return false
	end

	if QuestCompletionItems[ItemId] then
		if IsQuestItemCompleted(ItemId) then
			vars.GotArtifact[ItemId] = true
			Item:Clear()
			return true
		end
		return false
	end

	if MonsterSpecialDropItems[ItemId] then
		if vars.GotArtifact[ItemId] and IsMapRefill then
			Item:Clear()
			return true
		end
		noRefund(Item)
		return false
	end

	if not UniqueItemSet[ItemId] then
		return false
	end

	local ItemTxt = Game.ItemsTxt[ItemId]
	local Material = ItemTxt and (ItemTxt.Material or 0) or 0
	local WasRefundable = Item.Refundable == true

	if not vars.GotArtifact[ItemId] then
		vars.GotArtifact[ItemId] = true
		noRefund(Item)
		return false
	end

	if IsMapRefill and Material == 3 then
		local Rule = FixedSpecialRespawnFallbacks[ItemId]
		if Rule and Rule.AnyWeapon then
			RandomizeOrdinaryWeaponTC5(Item)
		else
			RandomizeOrdinaryItem(Item, Rule and Rule.Strength or 5,
				Rule and Rule.ItemType or (ItemTxt.EquipStat + 1))
		end
		return "replaced"
	end

	if IsMapRefill and (FixedPlacementSet[ItemId] or WasRefundable) then
		Item:Clear()
		return true
	end

	noRefund(Item)
	return false
end

local function ProcessChestItem(Item, IsMapRefill)
	if not Item or Item.Number <= 0 then
		return
	end
	local ItemId = Item.Number
	if IsMapRefill and GuaranteedUniqueRespawnChestItems[ItemId] and vars.GotArtifact[ItemId] then
		local Available = GetNotFoundArts()
		if #Available > 0 then
			local NewItemId = Available[random(#Available)]
			SetItemToId(Item, NewItemId)
			vars.GotArtifact[NewItemId] = true
		else
			RandomizeOrdinaryTreasure6(Item, ItemId)
		end
		return
	end
	ProcessMapSpawnItem(Item, IsMapRefill)
end

-- monster treasure: Items[2] the item, Items[3] its gold (with the TreasureGenerated bit).
-- A recorded unique is cleared on a refill and the bit reset, so the monster rolls its
-- ordinary treasure again.
local function resetTreasure(Monster)
	local Gold = Monster.Items[3]
	if Gold then
		Gold:Clear()
	end
	Monster.TreasureGenerated = false
end

local function ProcessMonsterTreasureItem(Monster, IsMapRefill)
	local Item = Monster.Items[2]
	if not Item or Item.Number <= 0 then
		return
	end
	local ItemId = Item.Number
	if NativeQuestControlledItems[ItemId] then
		return
	end

	if QuestCompletionItems[ItemId] then
		if IsQuestItemCompleted(ItemId) then
			vars.GotArtifact[ItemId] = true
			Item:Clear()
			if IsMapRefill then resetTreasure(Monster) end
		end
		return
	end

	if MonsterSpecialDropItems[ItemId] then
		if vars.GotArtifact[ItemId] then
			Item:Clear()
			if IsMapRefill then resetTreasure(Monster) end
		else
			noRefund(Item)
		end
		return
	end

	if not UniqueItemSet[ItemId] then
		return
	end

	if not vars.GotArtifact[ItemId] then
		vars.GotArtifact[ItemId] = true
		noRefund(Item)
		return
	end

	if IsMapRefill then
		Item:Clear()
		resetTreasure(Monster)
	end
end

-- a named drop already looted isn't handed out by the corpse again
function events.PickCorpse(t)
	local Monster = t.Monster
	if not Monster or not Monster.Item or Monster.Item <= 0 then
		return
	end
	local ItemId = Monster.Item
	if MonsterSpecialDropItems[ItemId] and vars.GotArtifact[ItemId] then
		evt.SetMonsterItem{Monster = t.MonsterIndex, Item = ItemId, Has = 0}
	end
end

local function ScanMapUniqueSpawns()
	local IsMapRefill = Map.Refilled ~= nil

	-- an old save: the party's own uniques start the record (once)
	local InitialHistoryScan = not vars.UniqueArtifactHistoryInitialized
	if InitialHistoryScan then
		for _, Player in Party.PlayersArray do
			for _, Item in Player.Items do
				if UniqueItemSet[Item.Number] then
					vars.GotArtifact[Item.Number] = true
				end
			end
		end
		vars.UniqueArtifactHistoryInitialized = true
	end

	-- the first scan of an old save leaves the map as it is
	local SuppressRespawns = IsMapRefill and not InitialHistoryScan

	for _, Chest in Map.Chests do
		for _, Item in Chest.Items do
			ProcessChestItem(Item, SuppressRespawns)
		end
	end

	-- items on the ground: those the party dropped are its own (recorded, left alone)
	for _, Obj in Map.Objects do
		if Obj.Item and Obj.Item.Number > 0 and not Obj.Removed then
			if Obj.DroppedByPlayer then
				if UniqueItemSet[Obj.Item.Number] then
					vars.GotArtifact[Obj.Item.Number] = true
				end
			else
				local Result = ProcessMapSpawnItem(Obj.Item, SuppressRespawns)
				if Result == true then
					Obj.Removed = true
				elseif Result == "replaced" then
					local Sprite = Game.ItemsTxt[Obj.Item.Number].SpriteIndex
					if Sprite ~= nil then
						Obj.Type = Sprite
						Obj.TypeIndex = Sprite
					end
				end
			end
		end
	end

	for _, Monster in Map.Monsters do
		ProcessMonsterTreasureItem(Monster, SuppressRespawns)
	end
end
Game.ScanUniqueItemsOnCurrentMap = ScanMapUniqueSpawns

-- anything unique that reaches a backpack (quest rewards, events) is recorded as well
function events.GotItem(i)
	if UniqueItemSet[i] or MonsterSpecialDropItems[i] then
		vars.GotArtifact[i] = true
	end
end

-- after MMMWE_DroppedItems.lua (a General script, its handler comes first) has put the
-- party's dropped items back
function events.AfterLoadMap()
	local ok, err = pcall(ScanMapUniqueSpawns)
	if not ok then Log(Merge.Log.Error, "%s: unique items scan: %s", LogId, tostring(err)) end
end

-- named monster drops are recorded only when they reach a backpack (a monster dying
-- doesn't use up its drop); checked every second
local function RecordLootedMonsterSpecials()
	for _, Player in Party do
		for _, Item in Player.Items do
			local ItemId = Item.Number
			if MonsterSpecialDropItems[ItemId] and not vars.GotArtifact[ItemId] then
				vars.GotArtifact[ItemId] = true
			end
		end
	end
	local m = Mouse.Item.Number
	if MonsterSpecialDropItems[m] and not vars.GotArtifact[m] then
		vars.GotArtifact[m] = true
	end
end
local LootTick = 0
function events.Tick()
	LootTick = LootTick + 1
	if LootTick % 30 == 0 then
		RecordLootedMonsterSpecials()
	end
end

-- console fallback for builds whose award numbering differs, after the quest is done:
--   Game.MarkUniqueQuestItemCompleted(2020)  -- Mordred (539 Ebonest, 540 Whistlebone, 541 Balthazar)
function Game.MarkUniqueQuestItemCompleted(ItemId)
	if not QuestCompletionItems[ItemId] then
		return false
	end
	vars.UniqueQuestItemCompletion[ItemId] = true
	vars.GotArtifact[ItemId] = true
	ScanMapUniqueSpawns()
	return true
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
	-- (any copy in the backpack or worn, broken ones too)
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

local PB = const.PartyBuff
local ResistPartyBuffs = {[PB.AirResistance] = true, [PB.BodyResistance] = true,
	[PB.EarthResistance] = true, [PB.FireResistance] = true, [PB.MindResistance] = true,
	[PB.WaterResistance] = true}

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
				-- the resistance buffs keep their amount in Power (skill x mastery); the other
				-- party buffs (Shield, Wizard Eye, Water Walk, Feather Fall...) the skill (MMMWE 15.11.26)
				Buff.Power = ResistPartyBuffs[k] and skill * mas or skill
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

-- Artifact attack delay mods of a player (ranged or melee). MMMWE_Main.lua applies them as a
-- percentage of the attack delay (and the minimal delays) in its own GetAttackDelay handler.
Merge.Functions.ArtifactAttackDelay = function(PlayerIndex, Ranged)
	local PLT = PlayerEffects[PlayerIndex]
	return PLT and PLT.AttackDelay[Ranged and 1 or 2] or 0
end

function events.GetAttackDelay(t)
	local Player = t.Player
	--local PLT = PlayerEffects[Pl]
	local PLT = PlayerEffects[t.PlayerIndex]
	if PLT and Merge.Functions.RecoverySettings then
		-- handled by MMMWE_Main.lua (percentages)
	elseif PLT then
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
		-- MMMWE (11.11.26): the artifact's own damage scales like a weapon enchantment
		-- (MMMWE_EnchantScaling.lua: weapon and / or magic skill, two-handed). If that
		-- script's handler has run already (t.EnchantScaled), the damage is scaled here;
		-- if it runs after this one, it scales the whole result itself.
		local add = Effect.Add
		if t.EnchantScaled and Merge.Functions.ScaleEnchantDamage and t.Player then
			add = Merge.Functions.ScaleEnchantDamage(t.Player, t.Item, add, t.DamageKind)
		end
		t.Result = t.Result + add
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
-- MMMWE (15.11.26): the lists are open to other scripts
Merge.Functions.ArtifactSpcBonuses = ItemSpcBonuses

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
								T[k] = (T[k] or 0) + v   -- (23.11.26) the total is kept above -base Endurance in Core/events.lua
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

-- Jetpack (966), Power Shield (967) and item 968 used to be Technician-only;
-- the restriction has been removed, anyone can wear them now.

-- MMMWE (15.11.26): the race, class, alignment and gender restrictions of the artifacts
-- and relics are in Data/Tables/Artifact restrictions.txt (General/MMMWE_ArtifactRestrictions.lua);
-- only the Crown of Final Dominion and the Wetsuit keep their conditions here.

-- Crown of final Dominion
WearItemConditions[521] = function(Player, RosterId, Available)
	return Available and Player.Class == const.Class.MasterNecromancer
			and Game.Races[GetRace(Player)].Family == const.RaceFamily.Undead
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
local SLDStat = {[const.Stats.SpiritResistance] = true, [const.Stats.LightResistance] = true, [const.Stats.DarkResistance] = true}
function events.CalcStatBonusByItems(t)
	if not SLDStat[t.Stat] then return end      -- (03.11.26) was run for every stat
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
GetBonusList(1305).Skills =	{	[const.Skills.DisarmTraps] = 5, 
								[const.Skills.Perception] = 5}
-- Hands of the Master
GetBonusList(1313).Skills =	{	[const.Skills.Unarmed] = 10,
								[const.Skills.Dodging] = 10}
-- Cestuses (MMMWE_Cestus.lua; the elemental damage is there)
-- Fists of the Four Winds
GetBonusList(2209).Skills =	{	[const.Skills.Unarmed] = 5}
GetBonusList(2209).Stats = {	[const.Stats.FireResistance] = 20, [const.Stats.AirResistance] = 20,
								[const.Stats.WaterResistance] = 20, [const.Stats.EarthResistance] = 20}
-- Palms of Serenity
GetBonusList(2210).Skills =	{	[const.Skills.Meditation] = 8}
GetBonusList(2210).Stats = {	[const.Stats.Personality] = 15, [const.Stats.Intellect] = 15}
-- Shadowgrip
GetBonusList(2211).Skills =	{	[const.Skills.Dodging] = 8}
GetBonusList(2211).Stats = {	[const.Stats.Speed] = 20}
-- Mountain's Heart (relic)
GetBonusList(2212).Stats = {	[const.Stats.Might] = 40, [const.Stats.Endurance] = 40, [const.Stats.EarthResistance] = 30,
								[const.Stats.Speed] = -20, [const.Stats.Accuracy] = -20}
-- Robes (15.11.26; the Robe skill and the wearing rule: MMMWE_ExtraSkillsEffects.lua)
do
	local S = const.Stats
	local function res(v)
		return {[S.FireResistance] = v, [S.AirResistance] = v, [S.WaterResistance] = v,
			[S.EarthResistance] = v, [S.MindResistance] = v, [S.BodyResistance] = v,
			[S.SpiritResistance] = v}
	end
	GetBonusList(2250).Stats = {[S.SP] = 5}                                                    -- Apprentice's Robe
	GetBonusList(2251).Stats = {[S.SP] = 10}                                                   -- Acolyte's Robe
	GetBonusList(2252).Stats = {[S.SP] = 15, [S.Intellect] = 5, [S.Personality] = 5}           -- Scholar's Robe
	GetBonusList(2253).Stats = {[S.SP] = 20, [S.Intellect] = 10, [S.Personality] = 10}         -- Magister's Robe
	local t = res(10); t[S.SP], t[S.Intellect], t[S.Personality] = 30, 15, 15
	GetBonusList(2254).Stats = t                                                               -- Archmage's Robe
	t = res(20); t[S.SP], t[S.Intellect], t[S.Personality] = 50, 25, 25
	GetBonusList(2255).Stats = t                                                               -- Vestments of the Archmagus (artifact)
	GetBonusList(2256).Stats = {[S.SP] = 80, [S.Intellect] = 40, [S.Personality] = 40,        -- Lichweave Shroud (relic)
		[S.DarkResistance] = 40, [S.Endurance] = -40, [S.LightResistance] = -30}
end
-- Nightwyrm Staff (relic of 15.11.26, the Lichweave Shroud's companion; the set bonus: MMMWE_Nightwyrm.lua)
GetBonusList(2257).Stats = {	[const.Stats.Intellect] = 40, [const.Stats.DarkResistance] = 30,
								[const.Stats.Personality] = -30, [const.Stats.BodyResistance] = -30}
GetBonusList(2257).SpellBonus =	{[const.Skills.Dark] = true}
-- Hat of the Archmagus (artifact of 16.11.26, the Vestments' companion; the set bonus: MMMWE_ArchmagusSet.lua)
GetBonusList(2258).Stats = {	[const.Stats.Intellect] = 20, [const.Stats.Personality] = 20,
								[const.Stats.MindResistance] = 20}
-- Leathers of the Road Warrior (artifact of 17.11.26; the damage cut and the Tomb of VARN: MMMWE_RoadWarrior.lua)
GetBonusList(2259).Stats = {	[const.Stats.ArmorClass] = 15, [const.Stats.Endurance] = 20, [const.Stats.Speed] = 15}
-- Warhammers and the Warscythe of 07.11.26 (their on-hit effects are at the end)
-- Rimefall
GetBonusList(2225).Stats = {	[const.Stats.Endurance] = 25, [const.Stats.WaterResistance] = 30}
-- Mjolnir
GetBonusList(2226).Stats = {	[const.Stats.Might] = 30, [const.Stats.AirResistance] = 30}
-- Dawnbringer
GetBonusList(2227).Stats = {	[const.Stats.Personality] = 25, [const.Stats.LightResistance] = 30}
GetBonusList(2227).Skills =	{	[const.Skills.Spirit] = 5}
-- Warscythe (relic)
GetBonusList(2228).Stats = {	[const.Stats.Might] = 40, [const.Stats.Accuracy] = 25,
								[const.Stats.Personality] = -30, [const.Stats.MindResistance] = -30}
-- Ancient artifacts and relics (MMMWE_AncientArtifacts.lua; not found in game until their pictures are drawn)
-- Padish's Signet
GetBonusList(2213).Stats = {	[const.Stats.Personality] = 15}
GetBonusList(2213).Skills =	{	[const.Skills.Merchant] = 5}
-- VARN Officer's Visor
GetBonusList(2214).Skills =	{	[const.Skills.IdentifyMonster] = 10, [const.Skills.Perception] = 10}
GetBonusList(2214).Stats = {	[const.Stats.LightResistance] = 20}
GetBonusList(2214).PartyBuffs = {ReqMastery = 0, Buff = {[const.PartyBuff.WizardEye] = JoinSkill(10, 4)}}
-- Servo Gauntlets
GetBonusList(2215).Stats = {	[const.Stats.Might] = 25}
-- Gravity Treads
GetBonusList(2217).Stats = {	[const.Stats.Speed] = 20}
GetBonusList(2217).PartyBuffs = {ReqMastery = 0, Buff = {[const.PartyBuff.WaterWalk] = JoinSkill(10, 4),
	[const.PartyBuff.FeatherFall] = JoinSkill(10, 4)}}
-- Command Cube
GetBonusList(2220).Stats = {	[const.Stats.Intellect] = 20}
-- Ancient Power Core (relic)
GetBonusList(2222).Stats = {	[const.Stats.Intellect] = 50, [const.Stats.BodyResistance] = -30}
-- Sentinel Frame (relic)
GetBonusList(2223).Stats = {	[const.Stats.Might] = 50, [const.Stats.Endurance] = 30, [const.Stats.Speed] = -30,
								[const.Stats.Accuracy] = -20}
-- Neural Crown (relic)
GetBonusList(2224).Stats = {	[const.Stats.Intellect] = 40, [const.Stats.Personality] = -30, [const.Stats.MindResistance] = -40}
GetBonusList(2224).Skills =	{	[const.Skills.Learning] = 10}
-- Ethric's Staff
GetBonusList(1317).Skills =	{	[const.Skills.Meditation] = 15}
-- Hareck's Leather
GetBonusList(1318).Skills =	{	[const.Skills.DisarmTraps] = 5,
								[const.Skills.Perception] = 5,}
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
-- Hades: Disarm Traps +10 now comes with its "of Thievery" bonus (MMMWE_Thievery.lua)

-- Energy Shield: 30.10.26 no Meditation bonus, regeneration or resistances any more; the
-- shield has its own capacity (MMMWE_EnergyShield.lua)

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
-- Hades (MMMWE 15.11.26: "Thievery" as on Pendragon)
ItemSpcBonuses[2035] = {35}
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

-- A monster's Z is at its feet: aim at the middle of its body (MMMWE 15.11.26)
local function CastSpellTowardsMonster(Spell, Skill, Mastery, Monster)
	local mz = Monster.Z + floor((Monster.BodyHeight or 100) / 2)
	local dist_c = spell_distance / sqrt((Monster.X - Party.X) ^ 2 +
		(Monster.Y - Party.Y) ^ 2 + (mz - Party.Z) ^ 2)
	 evt.CastSpell(Spell, Mastery, Skill,
		Monster.X - floor((Monster.X - Party.X) * dist_c),
		Monster.Y - floor((Monster.Y - Party.Y) * dist_c),
		mz - floor((mz - Party.Z) * dist_c),
		Monster.X, Monster.Y, mz)
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
-- (07.11.26) The Rock Blast it cast had no caster: its rocks bounced around and hurt the party
-- as well. Now the blast is the bearer's own: Earth damage of a Rock Blast of the bearer's
-- Mace skill to the target and every foe within HW_BLAST_RADIUS of it (through their Earth
-- resistance), dealt on the next tick as the bearer's hits (MF.QueueForcedHit).
local HW_BLAST_RADIUS = 300
OnHitEffects[1355] = {
	DamageKind	= const.Damage.Energy,
	Add			= 20,
	Special = function(t)
		local Skill, Mas = SpellPowerByItemSkill(t.Player, t.Item)
		CastSpellDirect(125,Skill,Mas)
		local mon = t.Monster
		if not mon or not MF.QueueForcedHit then return end
		-- Rock Blast: 10 + 1d8 per skill point
		local dmg = 10
		for _ = 1, Skill do dmg = dmg + math.random(1, 8) end
		local pi = t.Player:GetIndex()
		for i = 0, Map.Monsters.count - 1 do
			local m = Map.Monsters[i]
			if m.HP > 0 and (m == mon or m.Hostile) then
				local dx, dy, dz = m.X - mon.X, m.Y - mon.Y, m.Z - mon.Z
				if dx * dx + dy * dy + dz * dz <= HW_BLAST_RADIUS * HW_BLAST_RADIUS then
					local d = m:CalcTakenDamage(const.Damage.Earth, dmg)
					if d > 0 then MF.QueueForcedHit(pi, i, d, const.Damage.Earth) end
				end
			end
		end
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
		-- MMMWE (15.11.26): the monster's every kind, as the slaying enchantments see it
		if Game.IsMonsterOfKind(t.Monster.Id, const.MonsterKind.Dragon) ~= 0 then
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
	
-- (07.11.26) Rimefall, Mjolnir, Dawnbringer and the Warscythe
-- a monster debuff unless the monster resists it by its resistance to kind (as the shield bash)
local function DebuffMonster(t, kind, buff, time, power)
	local mon = t.Monster
	if not mon or mon.HP <= 0 then return end
	local res = mon.Resistances[kind]
	if res == const.MonsterImmune then return end
	local S, M = SplitSkill(t.Player:GetSkill(const.Skills.Mace))
	if math.random(5, 100) + S + M * 2.5 <= res then return end
	local b = mon.SpellBuffs[buff]
	b.ExpireTime = max(Game.Time + time, b.ExpireTime)
	if power then
		b.Power = max(b.Power, power)
		b.Skill = max(b.Skill, 3)
	end
	-- (20.11.26) the sparkles the game shows on a monster its spell or the Snake's slow took hold of
	pcall(mon.ShowSpellEffect, mon, 0)
	return true
end
-- extra hits of kind to hostile monsters near the target (nearest first, at most count)
local function NearbyHits(t, kind, dmg, radius, count)
	local mon = t.Monster
	if not mon or not MF.QueueForcedHit then return end
	local near = {}
	for i = 0, Map.Monsters.count - 1 do
		local m = Map.Monsters[i]
		if m ~= mon and m.HP > 0 and m.Hostile then
			local dx, dy, dz = m.X - mon.X, m.Y - mon.Y, m.Z - mon.Z
			local d2 = dx * dx + dy * dy + dz * dz
			if d2 <= radius * radius then near[#near + 1] = {i, d2} end
		end
	end
	table.sort(near, function(a, b) return a[2] < b[2] end)
	local pi = t.Player:GetIndex()
	for n = 1, min(count, #near) do
		local i = near[n][1]
		local d = Map.Monsters[i]:CalcTakenDamage(kind, dmg)
		if d > 0 then MF.QueueForcedHit(pi, i, d, kind) end
	end
end
-- Rimefall: Water damage, the target is slowed
OnHitEffects[2225] = {
	DamageKind	= const.Damage.Water,
	Add			= 15,
	Special = function(t)
		DebuffMonster(t, const.Damage.Water, const.MonsterBuff.Slow, 2 * const.Minute, 2)
	end}
-- Mjolnir: Air damage, a chance to stun the target and to strike two foes near it with lightning
OnHitEffects[2226] = {
	DamageKind	= const.Damage.Air,
	Add			= 15,
	Special = function(t)
		if random(100) <= 20 then
			if DebuffMonster(t, const.Damage.Air, const.MonsterBuff.Paralyze, const.Minute) then
				Game.ShowStatusText("Mjolnir's thunder stuns the foe!", 2)
			end
			NearbyHits(t, const.Damage.Air, 10 + random(1, 10) + random(1, 10), 400, 2)
		end
	end}
-- Dawnbringer: Light damage, double against the undead, whose blows also heal the bearer
OnHitEffects[2227] = {
	DamageKind	= const.Damage.Light,
	Add			= 15,
	Special = function(t)
		local mon = t.Monster
		if mon and Game.IsMonsterOfKind(mon.Id, const.MonsterKind.Undead) ~= 0 then
			t.Result = t.Result * 2
			local pl = t.Player
			if pl.HP > 0 then pl.HP = min(pl:GetFullHP(), pl.HP + 3 + floor(t.Result / 5)) end
		end
	end}
-- Warscythe: Energy damage, and the blow may arc to the nearest foe
-- Nightwyrm Staff
OnHitEffects[2257] = {
	DamageKind	= const.Damage.Dark,
	Add			= 15}

OnHitEffects[2228] = {
	DamageKind	= const.Damage.Energy,
	Add			= 20,
	Special = function(t)
		if random(100) <= 30 then
			NearbyHits(t, const.Damage.Energy, 15 + random(1, 10) + random(1, 10), 500, 1)
		end
	end}

-- MMMWE (11.11.26): the artifacts and relics whose own damage scales like a weapon
-- enchantment (MMMWE_EnchantScaling.lua adds its note to their descriptions): the on-hit
-- damage above and the damaging special bonuses (group 1)
do
	local list = {}
	for id, e in pairs(OnHitEffects) do
		if e.Add then list[id] = true end
	end
	for id, bonuses in pairs(ItemSpcBonuses) do
		for _, b in pairs(bonuses) do
			if table.find(Bonus2Group[1], b) then list[id] = true end
		end
	end
	MF.ScalingArtifacts = list
	if EnchantScaling and EnchantScaling.UpdateTexts then pcall(EnchantScaling.UpdateTexts) end
end

MF.LogInit2(LogId)
