--[[
	MMMWE_DroppedItems.lua — items the party drops stay on the floor

	The game keeps the items placed on a map by its makers, but items the party drops
	(map objects with the DroppedByPlayer bit) are gone when the map is loaded again.
	This script remembers them and puts back the ones that are missing:
	  - on leaving a map and before saving, every item the party dropped on it is recorded
	    (the whole item: enchantments, charges, identified / broken state) with its place;
	  - after a map is loaded, each recorded item that is not lying there is put back.
	Items picked up are simply not recorded the next time. The records are kept in the
	saved game (vars.MMMWE_DroppedItems, per map).

	Settings: KEEP_ON_REFILL (keep the items when the map refills), MAX_PER_MAP.
	Console: Merge.Functions.DroppedItemsList() prints the records of the current map.
--]]

local MF = Merge.Functions

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local ENABLED        = true
local KEEP_ON_REFILL = true    -- false: dropped items are gone when the map refills
local MAX_PER_MAP    = 200     -- at most this many items are kept per map
local SAME_PLACE     = 48      -- an item this close (each axis) counts as still lying there

---------------------------------------------------------------------------

if not ENABLED then return end

local function log(fmt, ...) if MF.LogInfo then MF.LogInfo("[DroppedItems] " .. fmt, ...) end end

local function mapKey()
	return (Map.Name or ""):lower()
end

local function store()
	vars.MMMWE_DroppedItems = vars.MMMWE_DroppedItems or {}
	return vars.MMMWE_DroppedItems
end

local function isDropped(o)
	return o.TypeIndex ~= 0 and o.Item.Number > 0 and o.DroppedByPlayer
		and not o.Removed and not o.Missile
end

-- record the items the party dropped on the current map
local function record()
	local key = mapKey()
	if key == "" then return end
	local list = {}
	for i = 0, Map.Objects.count - 1 do
		local o = Map.Objects[i]
		if isDropped(o) and #list < MAX_PER_MAP then
			local it = o.Item
			list[#list + 1] = {
				Number = it.Number,
				Item = mem.string(it["?ptr"], it["?size"], true),
				X = o.X, Y = o.Y, Z = o.Z, Room = o.Room,
			}
		end
	end
	store()[key] = #list > 0 and list or nil
end

-- put back the recorded items that are not on the map
local function restore()
	local key = mapKey()
	local list = store()[key]
	if not list then return end
	if Map.Refilled and not KEEP_ON_REFILL then
		store()[key] = nil
		return
	end
	if not SummonItem then return end

	local used, back = {}, 0
	for _, e in ipairs(list) do
		local found = false
		for i = 0, Map.Objects.count - 1 do
			local o = Map.Objects[i]
			if not used[i] and o.TypeIndex ~= 0 and not o.Removed and o.Item.Number == e.Number
					and math.abs(o.X - e.X) <= SAME_PLACE and math.abs(o.Y - e.Y) <= SAME_PLACE
					and math.abs(o.Z - e.Z) <= SAME_PLACE then
				used[i], found = true, true
				break
			end
		end
		if not found then
			local ok, obj = pcall(SummonItem, e.Number, e.X, e.Y, e.Z, 0)
			if ok and obj then
				local it = obj.Item
				mem.copy(it["?ptr"], e.Item, math.min(#e.Item, it["?size"]))
				obj.X, obj.Y, obj.Z = e.X, e.Y, e.Z
				obj.VelocityX, obj.VelocityY, obj.VelocityZ = 0, 0, 0
				if e.Room then obj.Room = e.Room end
				obj.DroppedByPlayer = true
				back = back + 1
			end
		end
	end
	if back > 0 then log("%s: %d item(s) put back", key, back) end
end

function events.LeaveMap()
	local ok, err = pcall(record)
	if not ok then log("record error: %s", tostring(err)) end
end

function events.BeforeSaveGame()
	local ok, err = pcall(record)
	if not ok then log("record error: %s", tostring(err)) end
end

function events.AfterLoadMap()
	local ok, err = pcall(restore)
	if not ok then log("restore error: %s", tostring(err)) end
end

function MF.DroppedItemsList()
	local list = store()[mapKey()] or {}
	for i, e in ipairs(list) do
		print(i, e.Number, Game.ItemsTxt[e.Number] and Game.ItemsTxt[e.Number].Name or "?", e.X, e.Y, e.Z)
	end
	return #list
end
