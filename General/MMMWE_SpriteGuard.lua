--[[
	MMMWE_SpriteGuard.lua — pictures of the map's objects and monsters checked after a load (11.11.26)

	A crash on loading a game again in the same session came from the game drawing a
	billboard whose picture wasn't loaded (an empty place in the list of loaded sprites).
	After every map load, before the first frame, this script looks at the sprite of every
	object and monster on the map: one whose frames are marked as loaded but point to an
	empty or missing sprite is logged ("[SpriteGuard]" in MMMergeLog.txt) and its frames
	are loaded again.
--]]

local MF = Merge.Functions
local u4 = mem.u4

local function log(fmt, ...) if MF.LogInfo then MF.LogInfo("[SpriteGuard] " .. fmt, ...) end end

-- is the loaded sprite number idx a real one
local function spriteOk(idx)
	local lod = Game.SpritesLod
	if idx < 0 then return false end
	if lod.IsHardware then
		local arr = lod.SpritesD3D
		if idx >= arr.count then return false end
		return u4[arr[idx]["?ptr"]] ~= 0          -- its name
	end
	return idx < lod.SpritesSW.count
end

-- the frames of the SFT group that starts at g
local function groupFrames(g)
	local frames = Game.SFTBin.Frames
	local list = {}
	local k = g
	while k >= 0 and k < frames.count and #list < 64 do
		local f = frames[k]
		list[#list + 1] = f
		if not f.NotGroupEnd then break end
		k = k + 1
	end
	return list
end

local checked = {}

-- true if the group was fine; otherwise it is loaded again
local function checkGroup(g, what)
	if not g or g <= 0 or checked[g] ~= nil then return checked[g] ~= false end
	local bad
	local list = groupFrames(g)
	for _, f in ipairs(list) do
		if f.SpriteName ~= "" and (not f.Loaded or not spriteOk(f.SpriteIndex[0])) then
			bad = bad or f
		end
	end
	checked[g] = not bad
	if not bad then return true end
	log("%s: group %d '%s' frame '%s' sprite %d loaded %s of %d sprites: loading it again", what, g,
		bad.GroupName, bad.SpriteName, bad.SpriteIndex[0], tostring(bad.Loaded),
		Game.SpritesLod.IsHardware and Game.SpritesLod.SpritesD3D.count or Game.SpritesLod.SpritesSW.count)
	for _, f in ipairs(list) do f.Loaded = false end
	Game.SFTBin:LoadGroup(g)
	return false
end

local function check()
	checked = {}
	local objects, monsters, fixed = 0, 0, 0
	for i = 0, Map.Objects.count - 1 do
		local o = Map.Objects[i]
		if not o.Removed and o.Type ~= 0 then
			objects = objects + 1
			local d = Game.ObjListBin[o.TypeIndex]
			if d and not d.Invisible then
				if not checkGroup(d.SFTIndex, string.format("object %d (type %d, item %d)", i, o.Type, o.Item.Number)) then
					fixed = fixed + 1
				end
			end
		end
	end
	for i = 0, Map.Monsters.count - 1 do
		local m = Map.Monsters[i]
		if m.AIState ~= const.AIState.Removed then
			monsters = monsters + 1
			for k, g in m.Frames do
				if not checkGroup(g, string.format("monster %d (id %d, frames %d)", i, m.Id, k)) then
					fixed = fixed + 1
				end
			end
		end
	end
	log("%s: %d objects, %d monsters checked, %d loaded again", Map.Name, objects, monsters, fixed)
end

function events.AfterLoadMap()
	local ok, err = pcall(check)
	if not ok then log("check error: %s", tostring(err)) end
end
