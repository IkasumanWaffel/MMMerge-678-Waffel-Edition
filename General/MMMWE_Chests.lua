--[[
	MMMWE_Chests.lua — Perception finds extra chest loot, Disarm Traps works by chance

	1. Extra loot (Perception)
	   The first time a chest is opened after the map is (re)filled, the party member with
	   the best Perception may find extra items hidden in it:
	     tries      = Perception mastery (Novice 1 ... Grand Master 4)
	     chance     = LOOT.BaseChance + LOOT.ChancePerPoint x skill per try (capped)
	     item level = map treasure level (MapStats "Tres") - 1, +1 per LOOT.PointsPerLevel
	                  points of skill, +1 at Grand Master (1..6)
	     enchanted  = at Master and Grand Master an item is always enchanted with a chance
	                  of LOOT.EnchantPerPoint x skill
	   Extra items are added before the game lays the chest out, so they take the free
	   space like the chest's own items (none are added if the chest is full).
	   The status line says "<name> spots N hidden item(s)!".

	2. Disarm Traps by chance
	   The game disarms a chest trap when Disarm Traps total skill >= 2 x map "Lock"
	   (MapStats). Now the margin gives a chance instead:
	     chance = 50% + DISARM.PerPoint x (total skill - 2 x Lock), DISARM.Min..DISARM.Max
	   Grand Masters still always succeed; maps with Lock 0 have no check.
	   One roll per attempt (the same result is reused if the game asks again in the
	   same moment).
--]]

local MF = Merge.Functions
local SK = const.Skills

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local LOOT = {
	Enabled         = true,
	BaseChance      = 5,     -- % per try
	ChancePerPoint  = 3,     -- % per point of Perception skill
	MaxChance       = 80,    -- % per try
	PointsPerLevel  = 10,    -- +1 item level per this many points of skill
	EnchantPerPoint = 3,     -- % per point, Master and Grand Master only
	FlagBit         = 0x4000 -- chest Bits flag: extra loot already rolled
}

local DISARM = {
	Enabled  = true,
	PerPoint = 5,    -- % per point of total skill above / below 2 x Lock
	Min      = 5,
	Max      = 95,
}

local function log(fmt, ...) if MF.LogInfo then MF.LogInfo("[Chests] " .. fmt, ...) end end

---------------------------------------------------------------------------
-- Extra loot
---------------------------------------------------------------------------

local ITEMS_PLACED = const.ChestBits.ItemsPlaced

local function bestPerception()
	local best, bestS, bestM = nil, 0, 0
	for i = 0, Party.Count - 1 do
		local pl = Party[i]
		local s, m = SplitSkill(pl:GetSkill(SK.Perception))
		if m > 0 and s * m > bestS * bestM then
			best, bestS, bestM = pl, s, m
		end
	end
	return best, bestS, bestM
end

local function treasureLevel()
	local ok, ms = pcall(function() return Game.MapStats[Map.MapStatsIndex] end)
	local tres = ok and ms and ms.Tres or 1
	return math.max(1, math.min(6, tres))
end

local function freeSlots(chest)
	local list = {}
	for i = 1, 140 do
		if chest.Items[i].Number == 0 then list[#list + 1] = i end
	end
	return list
end

local function addExtraLoot(id)
	if not LOOT.Enabled then return end
	local chest = Map.Chests[id]
	if not chest then return end
	-- only before the game lays the items out the first time, and once per refill
	if bit.band(chest.Bits, ITEMS_PLACED) ~= 0 or bit.band(chest.Bits, LOOT.FlagBit) ~= 0 then
		return
	end
	chest.Bits = bit.bor(chest.Bits, LOOT.FlagBit)

	local pl, s, m = bestPerception()
	if not pl then return end
	local chance = math.min(LOOT.MaxChance, LOOT.BaseChance + LOOT.ChancePerPoint * s)
	local level = treasureLevel() - 1 + math.floor(s / LOOT.PointsPerLevel) + (m >= 4 and 1 or 0)
	level = math.max(1, math.min(6, level))

	local slots = freeSlots(chest)
	local found = 0
	for _ = 1, m do
		if #slots == 0 then break end
		if math.random(100) <= chance then
			local it = chest.Items[table.remove(slots, 1)]
			local enchant = m >= 3 and math.random(100) <= LOOT.EnchantPerPoint * s
			it:Randomize(level, 0, enchant)
			if it.Number ~= 0 then found = found + 1 end
		end
	end
	if found > 0 then
		Game.ShowStatusText(string.format("%s spots %d hidden item%s!", pl.Name, found,
			found == 1 and "" or "s"))
		log("chest %d: %d extra item(s), level %d", id, found, level)
	end
end

function events.OpenChest(id)
	local ok, err = pcall(addExtraLoot, id)
	if not ok then log("extra loot error: %s", tostring(err)) end
end

---------------------------------------------------------------------------
-- Disarm Traps by chance
---------------------------------------------------------------------------

local lastRoll = {}   -- [player ptr] = {time, result}

function events.GetDisarmTrapTotalSkill(t)
	if not DISARM.Enabled or not t.Player then return end
	local _, m = SplitSkill(t.Player:GetSkill(SK.DisarmTraps))
	if m >= 4 then return end                          -- Grand Master: always
	local ok, lock = pcall(function() return Game.MapStats[Map.MapStatsIndex].Lock end)
	if not ok or not lock or lock <= 0 then return end -- no check on this map
	local need = lock * 2

	local key = t.Player["?ptr"]
	local prev = lastRoll[key]
	local success
	if prev and prev[1] == Game.Time then
		success = prev[2]
	else
		local chance = 50 + DISARM.PerPoint * (t.Result - need)
		chance = math.max(DISARM.Min, math.min(DISARM.Max, chance))
		success = math.random(100) <= chance
		lastRoll[key] = {Game.Time, success}
	end
	t.Result = success and math.max(t.Result, need) or math.min(t.Result, need - 1)
end
