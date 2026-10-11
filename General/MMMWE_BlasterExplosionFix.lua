--[[
	MMMWE_BlasterExplosionFix.lua — blaster impact explosion visible indoors

	The engine draws the blaster impact object (ObjList id 556, sprite spell135c) only as a
	red light flash on indoor maps, whatever sprite or flags it is given, so object 556 itself
	is treated specially there. Every new 556 object is turned into a copy of it with an
	unused id (ObjList.txt: "blaster explosion" 12050, same flags, lifetime and sprite), which
	the engine draws like any other explosion. Damage was already dealt at impact, so nothing
	else changes.
--]]

local FROM_ID = 556       -- blaster impact, as the engine creates it
local TO_ID   = 12050     -- copy in ObjList.txt

local MF = Merge.Functions
local toIndex

local function findIndex(id)
	for i, o in Game.ObjListBin do
		if o.Id == id then return i end
	end
end

function events.GameInitialized2()
	toIndex = findIndex(TO_ID)
	if not toIndex then
		MF.LogWarning("BlasterExplosionFix: ObjList.txt has no object %d, fix disabled", TO_ID)
	end
end

function events.Tick()
	if not toIndex then return end
	if Map.IsOutdoor() then return end
	for i = 0, Map.Objects.count - 1 do
		local o = Map.Objects[i]
		if o.Type == FROM_ID then
			o.Type = TO_ID
			o.TypeIndex = toIndex
			o.Missile = false   -- an explosion, not a flying weapon missile
		end
	end
end
