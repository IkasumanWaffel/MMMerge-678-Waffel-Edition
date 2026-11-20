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

	3. Traps by treasure level (20.11.26)
	   Map Lock 0 meant no check at all (every trapped chest opened safely without the
	   skill), and many early maps have small or no Trap dice. Now every map has at least
	   the Lock and Trap dice of its treasure level (TRAPS.MinLock, TRAPS.MinDice), and the
	   dice of the deeper levels are multiplied (TRAPS.DiceMul): the map's own values if
	   higher. Applied to the map's MapStats when it is entered.
	   A trap that goes off also deals TRAPS.Percent % of each character's full Hit Points
	   of its element (Fire, Air, Water or Body, as the trap's own explosion), resisted as
	   any hit: high level chests can't be emptied by simply taking the blast.

	4. More trapped chests (20.11.26)
	   When a chest is first filled, an untrapped one becomes trapped with TRAPS.ExtraChance %
	   by treasure level (once per refill).
--]]

local MF = Merge.Functions
local Tx, Tn, TxN = Merge.Functions.Text, Merge.Functions.TextKey, Merge.Functions.TextN
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

-- by treasure level 1..6
local TRAPS = {
	Enabled     = true,
	MinLock     = {1, 2, 3, 5, 7, 9},       -- disarmed at total skill 2 x Lock (MMMWE: a chance around it)
	MinDice     = {2, 3, 4, 6, 9, 12},      -- d20 of the trap's explosion
	DiceMul     = {1, 1.1, 1.25, 1.5, 1.75, 2},
	Percent     = {3, 5, 8, 12, 18, 25},    -- % of full Hit Points, each character
	ExtraChance = {10, 15, 20, 25, 30, 35}, -- % for an untrapped chest to be trapped
	FlagBit     = 0x8000,                   -- chest Bits flag: the extra trap already rolled
}
MF.ChestTraps = TRAPS

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
	local chance = math.min(LOOT.MaxChance, LOOT.BaseChance + LOOT.ChancePerPoint * s
		+ (MF.LuckFindBonus and MF.LuckFindBonus(pl) or 0))                -- MMMWE_Luck.lua
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
		Game.ShowStatusText(string.format(TxN(found, "%s spots %d hidden item!", "%s spots %d hidden items!"),
			pl.Name, found))
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
			+ (MF.LuckDisarmBonus and MF.LuckDisarmBonus(t.Player) or 0)   -- MMMWE_Luck.lua
		chance = math.max(DISARM.Min, math.min(DISARM.Max, chance))
		success = math.random(100) <= chance
		lastRoll[key] = {Game.Time, success}
	end
	t.Result = success and math.max(t.Result, need) or math.min(t.Result, need - 1)
end

---------------------------------------------------------------------------
-- Traps by treasure level (20.11.26)
---------------------------------------------------------------------------

local function tresOf(ms)
	return math.max(1, math.min(6, ms.Tres or 1))
end

-- the map's own values are kept (Orig) and the raised ones written for the map being
-- entered, so a reload of MapStats.txt or a second entry doesn't raise them twice
local Orig = {}
function events.LoadMap()
	if not TRAPS.Enabled then return end
	local i = Map.MapStatsIndex
	local ms = i and i > 0 and Game.MapStats[i]
	if not ms then return end
	local o = Orig[i]
	if not o or (ms.Lock ~= o.NewLock or ms.Trap ~= o.NewTrap) then
		o = {Lock = ms.Lock, Trap = ms.Trap}
		Orig[i] = o
	end
	local t = tresOf(ms)
	o.NewLock = math.min(255, math.max(o.Lock, TRAPS.MinLock[t]))
	o.NewTrap = math.min(255, math.max(math.ceil(o.Trap * TRAPS.DiceMul[t]), TRAPS.MinDice[t]))
	ms.Lock, ms.Trap = o.NewLock, o.NewTrap
	log("traps: map %d Lock %d -> %d, Trap %dd20 -> %dd20", i, o.Lock, o.NewLock, o.Trap, o.NewTrap)
end

-- an untrapped chest may be trapped when it is first filled
local TRAPPED = const.ChestBits.Trapped
local function maybeTrap(id)
	if not TRAPS.Enabled then return end
	local chest = Map.Chests[id]
	if not chest or bit.band(chest.Bits, ITEMS_PLACED) ~= 0 or bit.band(chest.Bits, TRAPS.FlagBit) ~= 0 then
		return
	end
	chest.Bits = bit.bor(chest.Bits, TRAPS.FlagBit)
	if bit.band(chest.Bits, TRAPPED) ~= 0 then return end
	if math.random(100) <= TRAPS.ExtraChance[treasureLevel()] then
		chest.Bits = bit.bor(chest.Bits, TRAPPED)
		log("chest %d: trapped", id)
	end
end
function events.OpenChest(id)
	local ok, err = pcall(maybeTrap, id)
	if not ok then log("trap roll error: %s", tostring(err)) end
end

-- the trap goes off (0x41F9E6: edx = which of the four trap explosions, 811..814 in
-- ObjList.txt; the trap's object reference at 0x5CC030 is of kind 5 or 6 when it fires)
local TRAP_KIND = {[0] = const.Damage.Fire, const.Damage.Air, const.Damage.Water, const.Damage.Body}
local function percentDamage(which)
	local ref = mem.u4[0x5CC030] % 8
	if ref ~= 5 and ref ~= 6 then return end
	local pct = TRAPS.Percent[treasureLevel()]
	local kind = TRAP_KIND[which] or const.Damage.Fire
	for slot = 0, Party.count - 1 do
		local pl = Party[slot]
		local c = pl.Conditions
		if c[const.Condition.Dead] == 0 and c[const.Condition.Eradicated] == 0
				and c[const.Condition.Stoned] == 0 and pl.HP > 0 then
			local dmg = math.floor(pl:GetFullHP() * pct / 100)
			if dmg > 0 then evt.DamagePlayer{Player = slot, DamageType = kind, Damage = dmg} end
		end
	end
end
if mem.u1[0x41F9E6] == 0x8B and mem.u4[0x41F9E8] == 0x5CC030 then
	mem.autohook(0x41F9E6, function(d)
		if not TRAPS.Enabled then return end
		local ok, err = pcall(percentDamage, d.edx)
		if not ok then log("trap damage error: %s", tostring(err)) end
	end)
else
	MF.LogWarning("[Chests] the trap at 0x41F9E6 wasn't found: no percent damage")
end
