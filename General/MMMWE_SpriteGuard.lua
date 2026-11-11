--[[
	MMMWE_SpriteGuard.lua — a diagnostic for the crash on loading a game again in a session (11.11.26)

	The game crashes on the first frame after such a load, drawing a billboard with the
	loaded sprite number CRASH_SPRITE, which is an empty place in the sprite list then.
	This script only writes to MMMergeLog.txt ("[SpriteGuard]"), on leaving a map and after
	a map is loaded: the number of loaded sprites, what is in the place CRASH_SPRITE, and
	the SFT frames that point to it. It changes nothing.
--]]

local MF = Merge.Functions
local u4, i4 = mem.u4, mem.i4

local CRASH_SPRITE = 2227

local function log(fmt, ...) if MF.LogInfo then MF.LogInfo("[SpriteGuard] " .. fmt, ...) end end

local function report(when)
	local lod = Game.SpritesLod
	local count = lod.SpritesSW.count
	local name = "?"
	pcall(function()
		if CRASH_SPRITE < count then name = lod.SpritesSW[CRASH_SPRITE].Name end
	end)
	local d3d = "?"
	pcall(function()
		local p = u4[lod["?ptr"] + 0xECB0]
		d3d = string.format("%X", u4[p + CRASH_SPRITE * 0x28])
	end)
	log("%s %s: %d sprites loaded; sprite %d is '%s' (D3D name pointer %s)", when, tostring(Map.Name), count,
		CRASH_SPRITE, tostring(name), d3d)
	local frames = Game.SFTBin.Frames
	local found = 0
	for k = 0, frames.count - 1 do
		local f = frames[k]
		for a = 0, 7 do
			if f.SpriteIndex[a] == CRASH_SPRITE then
				found = found + 1
				if found <= 12 then
					log("  SFT frame %d group '%s' sprite '%s' [%d] loaded %s", k, f.GroupName, f.SpriteName, a, tostring(f.Loaded))
				end
				break
			end
		end
	end
	log("  %d SFT frames point to it", found)
	-- who uses those frames: objects and monsters of the map
	for i = 0, Map.Objects.count - 1 do
		local o = Map.Objects[i]
		local ok, g = pcall(function() return Game.ObjListBin[o.TypeIndex].SFTIndex end)
		if ok and g and g > 0 and not o.Removed then
			local f = frames[g]
			if f and f.SpriteIndex[0] == CRASH_SPRITE then
				log("  object %d type %d item %d uses group %d '%s'", i, o.Type, o.Item.Number, g, f.GroupName)
			end
		end
	end
	-- any object or monster whose first frame points to an empty place
	local p = u4[lod["?ptr"] + 0xECB0]
	local function empty(idx)
		return idx < 0 or idx >= count or (p ~= 0 and u4[p + idx * 0x28] == 0)
	end
	local bad = 0
	for i = 0, Map.Objects.count - 1 do
		local o = Map.Objects[i]
		local ok, g, invisible = pcall(function()
			local d = Game.ObjListBin[o.TypeIndex]
			return d.SFTIndex, d.Invisible
		end)
		if ok and g and g > 0 and not invisible and not o.Removed and o.Type ~= 0 then
			local f = frames[g]
			if f and empty(f.SpriteIndex[0]) then
				bad = bad + 1
				if bad <= 15 then
					log("  EMPTY: object %d type %d item %d group %d '%s' sprite %d loaded %s", i, o.Type, o.Item.Number, g,
						f.GroupName, f.SpriteIndex[0], tostring(f.Loaded))
				end
			end
		end
	end
	for i = 0, Map.Monsters.count - 1 do
		local m = Map.Monsters[i]
		if m.AIState ~= const.AIState.Removed then
			for k, g in m.Frames do
				local f = g > 0 and frames[g]
				if f and empty(f.SpriteIndex[0]) then
					bad = bad + 1
					if bad <= 15 then
						log("  EMPTY: monster %d id %d frames %d group %d '%s' sprite %d loaded %s", i, m.Id, k, g,
							f.GroupName, f.SpriteIndex[0], tostring(f.Loaded))
					end
				end
			end
		end
	end
	local seen = {}
	for i = 0, Map.Sprites.count - 1 do
		local ok, g, id = pcall(function()
			local id = Map.Sprites[i].DecListId
			return Game.DecListBin[id].SFTIndex, id
		end)
		if ok and g and g > 0 and not seen[g] then
			seen[g] = true
			local f = frames[g]
			if f and empty(f.SpriteIndex[0]) then
				bad = bad + 1
				if bad <= 25 then
					log("  EMPTY: decoration %d (declist %d) group %d '%s' sprite %d loaded %s", i, id, g, f.GroupName,
						f.SpriteIndex[0], tostring(f.Loaded))
				end
			end
		end
	end
	log("  %d objects / monster frame groups / decoration kinds point to an empty place", bad)
end

function events.AfterLoadMap()
	local ok, err = pcall(report, "after load")
	if not ok then log("error: %s", tostring(err)) end
end

function events.LeaveMap()
	local ok, err = pcall(report, "leaving")
	if not ok then log("error: %s", tostring(err)) end
end
