local LogId = "UsableItems"
local MF = Merge.Functions
MF.LogInit1(LogId)
local MM = Merge.ModSettings

local max, min, floor, ceil, sqrt = math.max, math.min, math.floor, math.ceil, math.sqrt
local StatNames = {[32] = 144, [33] = 116, [34] = 163, [35] = 75, [36] = 211, [37] = 1, [38] = 136}
	
	-- Blaster Toolbox to mount/dismount Blaster upgrades and convert MM6 to MM7 blasters
local function CSModExchange(Target, Item)
	local It = Target.ItemMainHand
	if Target.Items[It].Number == 1666 then
		evt.PlaySound{12070}
		Target.Items[It].Number = 866
		return 0
	end
	if Target.Items[It].Number == 1667 then
		evt.PlaySound{12070}
		Target.Items[It].Number = 867
		return 0
	end
	if Target.Items[It].Number == 866
	or Target.Items[It].Number == 867 then
		if Target.Items[It].Charges > 0 then
			evt.PlaySound{17020}
			Item.Charges = Target.Items[It].Charges
			Target.Items[It].Charges = 0
			return 0
		elseif Target.Items[It].Charges == 0 then
			if Item.Charges > 0 then
				evt.PlaySound{12070}
				Target.Items[It].Charges = Item.Charges
				Item.Charges = 0
				return 0
			end
		end
	end
end

evt.UseItemEffects[962] = CSModExchange
	
-- Blaster Upgrades

local BLASTER_ITEMS = {[866] = true, [867] = true, [1666] = true, [1667] = true}

-- Ore item -> tier (1..6)
local OreLookup = {
  [686] = 1, [1488] = 1, [687] = 2, [1489] = 2,
  [688] = 3, [1490] = 3, [689] = 4, [1491] = 4,
  [690] = 5, [1492] = 5, [691] = 6, [1493] = 6,
}

-- Gem item -> tier (1..4)
local GemLookup = {
  [178] = 1, [988] = 1, [2057] = 1, [3000] = 1,
  [182] = 2, [989] = 2, [996] = 2, [2058] = 2,
  [184] = 3, [991] = 3, [2065] = 3,
  [186] = 4, [994] = 4, [997] = 4, [2056] = 4,
}

-- Ore: repair mastery req, repair skill req per tier
local OreRMreq = {1, 1, 2, 2, 3, 4}
local OreRSreq = {1, 3, 5, 7, 10, 15}

-- Gem: repair mastery req, target tier per gem type
local GemRMreq   = {1, 2, 3, 4}
local GemTierreq = {0, 1, 2, 3}

local function fail(msg)
  Game.ShowStatusText(msg)
  evt.PlaySound{358}
  return 0
end

local function getBlaster(Target)
  local slot = Target.ItemMainHand
  if not BLASTER_ITEMS[Target.Items[slot].Number] then return end
  local ch = Target.Items[slot].Charges
  return slot, math.floor(ch / 1000), math.fmod(ch, 1000)
end

local function Ore(Target, Item)
  local ind = OreLookup[Item.Number]
  if not ind then return end

  local slot, tier, level = getBlaster(Target)
  if not slot then return fail("Wrong target for modification.") end

  local RS, RM = SplitSkill(Target:GetSkill(const.Skills.Repair))
  local _,  BM = SplitSkill(Target:GetSkill(const.Skills.Blaster))

  if tier == 4 then
    return fail("Maximum upgrade Tier reached.")
  elseif tier >= BM then
    return fail("Upgrade is not available due to Blaster skill issue.")
  elseif RM < OreRMreq[ind] or RS < OreRSreq[ind] then
    return fail(string.format(
      "Upgrade failed. Repair skill reqs: S%d/%d, M%d/%d",
      RS, OreRSreq[ind], RM, OreRMreq[ind]))
  elseif level >= 100 then
    return fail("Mod is full. Use a gem to advance to the next tier.")
  end

  local gain = math.min(ind * (4 - tier), 100 - level)
  Target.Items[slot].Charges = Target.Items[slot].Charges + gain
  evt.PlaySound{12050}
  Game.ShowStatusText(string.format(
    "Upgrade successful. Mod status: Tier %d (%d/100)",
    tier, math.fmod(Target.Items[slot].Charges, 1000)))
  return 2
end

local function Gemz(Target, Item)
  local ind = GemLookup[Item.Number]
  if not ind then return end

  local slot, tier, level = getBlaster(Target)
  if not slot then return fail("Wrong target for modification.") end

  local _, RM = SplitSkill(Target:GetSkill(const.Skills.Repair))

  if RM < GemRMreq[ind] then
    return fail(string.format(
      "Upgrade failed. Repair skill reqs: M%d/%d",
      RM, GemRMreq[ind]))
  elseif tier >= GemTierreq[ind] + 1 then
    return fail(string.format("This item is already Tier %d.", tier))
  elseif tier ~= GemTierreq[ind] or level < 100 then
    return fail(string.format(
      "Upgrade failed. Mod status: Tier %d (%d/100)", tier, level))
  end

  Target.Items[slot].Charges = Target.Items[slot].Charges + 900
  evt.PlaySound{12050}
  Game.ShowStatusText(string.format(
    "Upgrade successful. Item has advanced to Tier %d", tier + 1))
  return 2
end

-- Register handlers
for id in pairs(GemLookup) do
  evt.UseItemEffects[id] = Gemz
end
for id in pairs(OreLookup) do
  evt.UseItemEffects[id] = Ore
end

--[[
	Reusable "bulk container" items: apothecary satchels and ore bags.

	Both items pack up to three ingredient/ore tallies into a single
	Item.Charges value, one decimal digit-pair per tier:
		tier 1 (x1)     -> ones/tens digits          (0-99)
		tier 2 (x100)   -> hundreds/thousands digits (0-99)
		tier 3 (x10000) -> ten-thousands+ digits

	Using the item either:
	  - deposits matching items from the party's inventory into the
	    container (up to CAPACITY total items), or
	  - if the party is carrying none of the container's ingredients,
	    withdraws a random handful (1..RANDOM_MAX per tier) back out.
]]

local CAPACITY = 99
local RANDOM_MAX = 3
local TIER_MULTIPLIERS = {1, 100, 10000}

-- Splits a packed Charges value into its three tier counts.
local function DecodeCharges(charges)
	local tier1 = math.fmod(charges, 100)
	local tier2 = math.fmod(math.modf(charges / 100), 100)
	local tier3 = math.modf(charges / 10000)
	return tier1, tier2, tier3
end

-- Total number of items currently packed into Charges.
local function TotalCount(charges)
	local tier1, tier2, tier3 = DecodeCharges(charges)
	return tier1 + tier2 + tier3
end

-- Moves `available` units of `ingredientNumber` from the party's inventory
-- into `item`, crediting Charges one unit at a time and stopping at `capacity`.
local function FillTierPerUnit(item, playerId, ingredientNumber, multiplier, available, itemCount, capacity)
	if available > 0 and itemCount < capacity then
		for j = 1, available do
			evt.Sub("Inventory", ingredientNumber)
			item.Charges = item.Charges + multiplier
			itemCount = itemCount + 1
			if itemCount == capacity then
				evt.FaceAnimation{Party(playerId), 15}
				break
			end
		end
	end
	return itemCount
end

-- Same idea as FillTierPerUnit, but credits Charges with the full
-- available*multiplier amount up front before removing inventory one unit
-- at a time. This matches the original ore-bag script's behavior (including
-- its quirk of over-crediting Charges if the loop breaks early on capacity).
local function FillTierBulk(item, playerId, ingredientNumber, multiplier, available, itemCount, capacity)
	if available > 0 and itemCount < capacity then
		item.Charges = item.Charges + available * multiplier
		for j = 1, available do
			evt.Sub("Inventory", ingredientNumber)
			itemCount = itemCount + 1
			if itemCount == capacity then
				evt.FaceAnimation{Party(playerId), 15}
				break
			end
		end
	end
	return itemCount
end

-- Withdraws a random 1..randomMax units per tier (capped by what's stored)
-- from `item` back into the player's inventory, handing back tierNItem
-- for that tier.
local function EmptyContainer(item, playerId, tier1Item, tier2Item, tier3Item, randomMax)
	local tier1, tier2, tier3 = DecodeCharges(item.Charges)
	local ext1 = math.min(math.random(1, randomMax), tier1)
	local ext2 = math.min(math.random(1, randomMax), tier2)
	local ext3 = math.min(math.random(1, randomMax), tier3)

	item.Charges = item.Charges - ext3 * 10000 - ext2 * 100 - ext1

	if tier1 > 0 then
		for j = 1, ext1 do
			evt.ForPlayer(playerId).Add("Inventory", tier1Item)
		end
	end
	if tier2 > 0 then
		for j = 1, ext2 do
			evt.ForPlayer(playerId).Add("Inventory", tier2Item)
		end
	end
	if tier3 > 0 then
		for j = 1, ext3 do
			evt.ForPlayer(playerId).Add("Inventory", tier3Item)
		end
	end
end

-- Single-slot variant (no tier packing, Charges is just a plain count) used
-- by the bottle box. Uses the item's own Target:ShowFaceAnimation call,
-- matching the original script rather than evt.FaceAnimation{Party(...)}.
local function FillSingleSlot(target, item, ingredientNumber, available, capacity)
	if available > 0 and item.Charges < capacity then
		for i = 1, math.min(capacity, available) do
			evt.Sub("Inventory", ingredientNumber)
			item.Charges = item.Charges + 1
			if item.Charges == capacity then
				target:ShowFaceAnimation(15)
				break
			end
		end
	end
end

-- Withdraws a fixed `extractCount` units (capped by what's stored) back to
-- the player's inventory. Unlike EmptyContainer this is not randomized,
-- matching the original bottle box script.
local function EmptySingleSlot(item, playerId, ingredientNumber, extractCount)
	local stored = item.Charges
	item.Charges = math.max(0, stored - extractCount)
	if stored > 0 then
		for i = 1, math.min(extractCount, stored) do
			evt.ForPlayer(playerId).Add("Inventory", ingredientNumber)
		end
	end
end

--------------------------------------------------------------------------
-- Apothecary satchels
--------------------------------------------------------------------------

-- Item number -> {ingredient1, ingredient2, ingredient3}
local ApothecaryItems = {
	[969] = {200, 1002, 1764},
	[970] = {201, 1003, 3000},
	[971] = {202, 1004, 3000},
	[972] = {203, 1005, 3000},
	[973] = {204, 1006, 3000},
	[974] = {205, 1007, 1763},
	[975] = {206, 1008, 3000},
	[976] = {207, 1009, 3000},
	[977] = {208, 1010, 3000},
	[978] = {209, 1011, 3000},
	[979] = {210, 1012, 1762},
	[980] = {211, 1013, 3000},
	[981] = {212, 1014, 3000},
	[982] = {213, 1015, 3000},
	[983] = {214, 1016, 3000},
	[984] = {215, 1017, 3000},
	[985] = {216, 1018, 3000},
	[986] = {217, 1019, 3000},
	[987] = {218, 1020, 3000},
}

local function Satchel(Target, Item, PlayerId)
	local recipe = ApothecaryItems[Item.Number]
	if not recipe then return 0 end
	local ing1, ing2, ing3 = recipe[1], recipe[2], recipe[3]

	local available1 = Party.CountItems{ing1}
	local available2 = Party.CountItems{ing2}
	local available3 = Party.CountItems{ing3}

	local itemCount = TotalCount(Item.Charges)
	itemCount = FillTierPerUnit(Item, PlayerId, ing1, TIER_MULTIPLIERS[1], available1, itemCount, CAPACITY)
	itemCount = FillTierPerUnit(Item, PlayerId, ing2, TIER_MULTIPLIERS[2], available2, itemCount, CAPACITY)
	itemCount = FillTierPerUnit(Item, PlayerId, ing3, TIER_MULTIPLIERS[3], available3, itemCount, CAPACITY)

	if available1 == 0 and available2 == 0 and available3 == 0 then
		EmptyContainer(Item, PlayerId, ing1, ing2, ing3, RANDOM_MAX)
	end

	Game.PlaySound(2513, -1, 0)
	return 0
end

for itemNumber in pairs(ApothecaryItems) do
	evt.UseItemEffects[itemNumber] = Satchel
end

--------------------------------------------------------------------------
-- Ore bags (from Scripts\General\UsableItems.lua)
--------------------------------------------------------------------------

-- Item number -> { {tier1 variants}, {tier2 variants}, {tier3 variants} }
-- Each tier has two ore item numbers (e.g. raw ore + ingot) that both feed
-- the same Charges digit-pair; withdrawing always hands back the first
-- variant of the tier, matching the original script.
local OreBags = {
	[191] = {
		{686, 1488},
		{687, 1489},
		{688, 1490},
	},
	[192] = {
		{689, 1491},
		{690, 1492},
		{691, 1493},
	},
}

local function OreBag(Target, Item, PlayerId)
	local tiers = OreBags[Item.Number]
	if not tiers then return end

	local itemCount = TotalCount(Item.Charges)
	local anyAvailable = false

	for tierIndex, variants in ipairs(tiers) do
		local multiplier = TIER_MULTIPLIERS[tierIndex]
		for _, oreNumber in ipairs(variants) do
			local available = Party.CountItems{oreNumber}
			if available > 0 then
				anyAvailable = true
			end
			itemCount = FillTierBulk(Item, PlayerId, oreNumber, multiplier, available, itemCount, CAPACITY)
		end
	end

	if not anyAvailable then
		EmptyContainer(Item, PlayerId, tiers[1][1], tiers[2][1], tiers[3][1], RANDOM_MAX)
	end

	Game.PlaySound(2513, -1, 0)
	return 0
end

for itemNumber in pairs(OreBags) do
	evt.UseItemEffects[itemNumber] = OreBag
end

--------------------------------------------------------------------------
-- Bottle Box
--------------------------------------------------------------------------

-- Item number -> {bottleNumber, capacity, extractCount}
local BottleBoxes = {
	[193] = {bottleNumber = 220, capacity = 12, extractCount = 3},
}

local function Bottlebox(Target, Item, PlayerId)
	local box = BottleBoxes[Item.Number]
	if not box then return 0 end

	local available = Party.CountItems{box.bottleNumber}

	FillSingleSlot(Target, Item, box.bottleNumber, available, box.capacity)

	if available == 0 then
		EmptySingleSlot(Item, PlayerId, box.bottleNumber, box.extractCount)
	end

	Game.PlaySound(42259, -1, 0)
	return 0
end

for itemNumber in pairs(BottleBoxes) do
	evt.UseItemEffects[itemNumber] = Bottlebox
end
	
-- Horseshoe

local function Horseshoe(Target, Item)
	Target.SkillPoints = Target.SkillPoints + 2
	Target:ShowFaceAnimation(36)
	Game.ShowStatusText(Game.GlobalTxt[125])
	return 2
end

evt.UseItemEffects[1448] = Horseshoe
evt.UseItemEffects[2083] = Horseshoe

-- Genie lamp

local function GenieLamp(Target, Item, PlayerId)

	local Reward, RewName
	local RewardString = "+%s %s !"
	local Mul = floor(sqrt(Target.LuckBase/10))
	local result = Mul + math.random(1, 7)

	if result == 1 then
		-- worst results
		evt.ForPlayer(PlayerId).Add{math.random(119, 123), 1}
	elseif result == 2 then
		-- random poison
		evt.ForPlayer(PlayerId).Add{math.random(113, 118), 1}
	elseif result == 3 then
		-- random harmless condition
		evt.ForPlayer(PlayerId).Add{math.random(107, 112), 1}
	elseif result == 4 then
		-- Gold
		evt.Add{21, math.random(1, 3) * 1000 * max(Mul, 1)}
	elseif result == 5 then
		-- Experience
		Reward = math.random(2, 5) * 1000 * max(Mul, 1)
		RewName = Game.GlobalTxt[83]
		evt.ForPlayer(PlayerId).Add{13, Reward}
	elseif result == 6 then
		-- SkillPoints
		Reward = math.random(2, 4) + Mul
		RewName = Game.GlobalTxt[207]
		evt.ForPlayer(PlayerId).Add{245, Reward}
	elseif result >= 7 then
		-- random base stat
		local Stat = math.random(32, 38)
		Reward = math.random(1, 3) + Mul
		RewName = Game.GlobalTxt[StatNames[Stat]]
		evt.ForPlayer(PlayerId).Add{Stat, Reward}
		if result > 7 then
			-- random item and Day of Gods buff
			Mouse.Item.Number = 0
			evt.GiveItem{5,0,0}
			CastSpellDirect(83, 10, 4)
			return 0
		end
	end

	if result > 4 then
		Game.ShowStatusText(RewardString:format(Reward, RewName))
	end

	if result > 7 then
		Target:ShowFaceAnimation(36)
		return 2
	else
		Mouse.Item.Number = 0
		return 0
	end

end

if not MF.GtSettingNum(MM.ItemsGenieLampType, 0) then
	evt.UseItemEffects[1418] = GenieLamp
end
evt.UseItemEffects[2103] = GenieLamp

-- Eatable items
local function EatItem()
	Party.Food = Party.Food + 1
	Game.ShowStatusText(string.replace(Game.GlobalTxt[502], "%lu", "1"))
	Game.PlaySound(144)
	return 1
end

evt.UseItemEffects[1002] = EatItem
evt.UseItemEffects[1764] = EatItem
evt.UseItemEffects[1432] = EatItem
evt.UseItemEffects[2104] = EatItem

-- Deck of fate
local StatByMonth = {[0] = 32,33,34,35,36,37,38,46,47,48,49,52}
local StatNames = {[0] = 144,116,163,75,211,1,136,24,202,194,208,204}

evt.UseItemEffects[2067] = function(Target, Item, PlayerId)
	local stat, result = StatByMonth[Game.Month], Game.WeekOfMonth + 1
	evt.ForPlayer(PlayerId).Add{stat, result}
	Game.ShowStatusText("+" .. tostring(result) .. " " .. Game.GlobalTxt[StatNames[Game.Month]] .. "!")
	return 2
end

-- Temple in a bottle
evt.UseItemEffects[1452] = function(Target, Item, PlayerId)
	if Map.Name ~= "7nwc.blv" then
		vars.TempleInABottleEnteredFrom = {Party.X, Party.Y, Party.Z, 0,0,0,0,0, Map.Name}
	end
	ExitCurrentScreen(false, true)
	evt.MoveToMap{0,0,0,0,0,0,0,0,"7nwc.blv"}
	return 0
end

-- Dimension door spell scroll
local function DimensionDoor()
	TownPortalControls.GenDimDoor()
	TownPortalControls.SwitchTo(4)
	Game.GlobalTxt[10] = " "
	ExitCurrentScreen(false, true)
	CastSpellDirect(31, 10, 4) -- avoid any condition checks. -- CastSpellScroll(31)
	Mouse.Item.Number = 0
	Timer(TownPortalControls.RevertTPSwitch, const.Minute, Game.Time+const.Minute, false, false)
	return 0
end

evt.UseItemEffects[190] = DimensionDoor

-- Elven mushrom
evt.UseItemEffects[1011] = function(Target, Item, PlayerId)
	local PL = Party[PlayerId]
	PL.SP = min(PL.SP + 50, PL:GetFullSP())
	evt.ForPlayer(PlayerId).Set{112,1}
	return 1
end

-- Beacon Pathfinder
evt.UseItemEffects[964] = function(Target, Item, PlayerId)
	local BS, BM = SplitSkill(Target:GetSkill(7))
	if BM == 4 then
		if Item.Charges >= 25 then
			Item.Charges = Item.Charges - 25
			Game.ShowStatusText(string.format("Remaining charge: %d%%.", Item.Charges))
			ExitCurrentScreen(false,true)
			Mouse:ReleaseItem()
			CastSpellDirect(33, 15, 4)
		else  
			Game.ShowStatusText(string.format("Low charge: %d%%. Please recharge the device!", Item.Charges))
			evt.PlaySound{358}
		end
	elseif BM < 4 then
		Game.ShowStatusText(string.format("Tech mastery (%d/4) is insufficient to use this function.",BM))
		evt.PlaySound{358}
	end
	return 0
end

-- Dimensional Scanner
evt.UseItemEffects[965] = function(Target, Item, PlayerId)
	local BS, BM = SplitSkill(Target:GetSkill(7))
	if BM >= 3 then
		if Item.Charges >= 25 then
		Item.Charges = Item.Charges - 25
		Game.ShowStatusText(string.format("Remaining charge: %d%%.", Item.Charges))
		ExitCurrentScreen(false,true)
		Mouse:ReleaseItem()
		CastSpellDirect(31, 15, 4)
		else 
			Game.ShowStatusText(string.format("Low charge: %d%%. Please recharge the device!", Item.Charges))
			evt.PlaySound{358}
		end
	elseif BM < 3 then
		Game.ShowStatusText(string.format("Tech mastery (%d/3) is insufficient to use this function.",BM))
		evt.PlaySound{358}
	end
	return 0
end

-- Item sounds

local ItemSounds = {
	[1434] = 130, -- Lute
	[1436] = 132, -- Trumpet
	[2081] = 151, -- Tanir's bell
	[2082] = 148, -- Gong
	[2095] = 152, -- Chime
	[2098] = 149, -- Flute
	[2099] = 150, -- Harp
}
Game.ItemSounds = ItemSounds

local function ItemSound(Target, Item, PlayerId)
	Target:ShowFaceAnimation(14)
	Game.PlaySound(ItemSounds[Item.Number])
	return 0
end

for k, v in pairs(ItemSounds) do
	evt.UseItemEffects[k] = ItemSound
end

MF.LogInit2(LogId)
