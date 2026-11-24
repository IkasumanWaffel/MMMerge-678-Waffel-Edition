--[[
	MMMWE_HerbShrubs.lua - herb shrubs to pick reagents from (25.11.26)

	MM6 drew three herb shrubs that no map ever placed (herbspr01..03 in the MM6 sprites):
	a red-berried Widowsweep bush, the leaves of a Phirna root and a yellow Poppysnaps plant.
	Here they grow on the outdoor maps of all three games.

	Placement (random, new every refill): the map's tile map (128 x 128 tiles of 512 x 512)
	and height map pick the spots:
	  a tile of grass, swamp or tropical ground (Enroth) whose eight neighbours are of the same
	    kinds (no roads, water, sand, rock or borders around it),
	  flat enough (the height map within HERB.MaxSlope steps around it),
	  no building, other decoration or herb nearby, nothing above the ground there;
	HERB.Min..HERB.Max shrubs per map (fewer where the map has little ground for them).
	The spots and what has been picked are kept in mapvars, so they last until the map refills.
	The shrubs are new sprites added after the map's own: before every save (and when leaving
	the map) the sprite count is set back to the map's own, so the saved map stays as the
	game expects it, and the shrubs come back after the save.

	Click a shrub to pick it:
	  1 reagent; +1 if someone in the party is an Expert in Alchemy, +1 more at Master or
	    above (the best alchemist counts);
	  the reagent of the continent: Jadame gives MM8's Widowsweep Berries, Phima Root and
	    Poppy Pod, Antagarich and Enroth MM7's Widowsweep Berries, Phirna Root and Poppysnaps;
	  nothing in winter.

	The shrubs use the sprite event numbers 20000 + sprite index (MMExt's convention).
--]]

local MF = Merge.Functions
local Tx = Merge.Functions.Text
local random, floor, abs, max, min = math.random, math.floor, math.abs, math.max, math.min

local HERB = {
	Min = 12, Max = 20,
	TilesPerShrub = 40,     -- at most one shrub per this many good tiles
	MaxSlope = 6,           -- height map steps (32 units each) within the 3 x 3 tiles
	GrassWeight = 3,        -- a grass tile is that many times likelier than a dirt one
	SpriteGap = 320,        -- from other decorations
	HerbGap = 1536,         -- between the shrubs
	ModelGap = 384,         -- from the bounding box of a building
	-- no herbs there: the planes, the Breach, the tutorial, all-snow maps, Shoals
	Skip = {elema = true, elemf = true, elemw = true, pbp = true, breach = true, bralvar = true,
		out15 = true, ["7out15"] = true, outb1 = true, outc1 = true},
}
MF.HerbShrubsSettings = HERB

local EVBASE = 20000
local KINDS = {"Widowsweep", "Phirna", "Poppysnaps"}
local HERBS = {
	Widowsweep = {Pic = "herbspr01", Items = {[1] = 200, [2] = 1002, [3] = 1002}, Hint = Tx"Widowsweep bush"},
	Phirna     = {Pic = "herbspr02", Items = {[1] = 205, [2] = 1007, [3] = 1007}, Hint = Tx"Phirna plant"},
	Poppysnaps = {Pic = "herbspr03", Items = {[1] = 210, [2] = 1012, [3] = 1012}, Hint = Tx"Poppysnaps"},
}

local function mapName() return ((Map.Name or ""):lower():gsub("%.odm$", "")) end
local function winter() return evt.CheckSeason{Season = 3} end

local function continent()
	local c = Merge.Vars and Merge.Vars.Continent
	return (c == 2 or c == 3) and c or 1
end

---------------------------------------------------------------------------
-- the spots
---------------------------------------------------------------------------

-- the tile behind a tile map value (the four tilesets of the map from 90 on)
local function tileAt(tx, ty)
	local v = Map.TileMap[ty][tx]
	if v >= 90 then
		local set = min(floor((v - 90) / 36), 3)
		v = Map.Tilesets[set].Offset + (v - 90 - 36*set)
	end
	return Game.CurrentTileBin[v]
end

-- 1: grass, swamp or tropical ground (or its border with dirt), 2: dirt; nil: no herbs
local function tileKind(t, snowOk)
	if not t or t.Water or t.Block or t.WaterTransition then return end
	local name = (t.Name or ""):lower()
	if name == "" or name == "pending" then return end
	local s = t.TileSet
	if s == 0 or s == 7 then return 1 end
	if s == 8 then return name:find("^trop") and 1 or nil end
	if s == 4 then return 2 end
	if snowOk and s == 1 then return 1 end
end

local function candidates()
	local snowOk = winter()   -- the MM6 maps turn their grass to snow in winter
	local ok = {}
	for ty = 0, 127 do
		ok[ty] = {}
		for tx = 0, 127 do ok[ty][tx] = tileKind(tileAt(tx, ty), snowOk) end
	end
	local h = Map.HeightMap
	local list = {}
	for ty = 2, 125 do
		for tx = 2, 125 do
			local good = ok[ty][tx]
			local lo, hi = 255, 0
			for dy = -1, 1 do
				if not good then break end
				for dx = -1, 1 do
					if not ok[ty + dy][tx + dx] then good = false; break end
					local v = h[ty + dy][tx + dx]
					lo, hi = min(lo, v), max(hi, v)
				end
			end
			if good and hi - lo <= HERB.MaxSlope then
				list[#list + 1] = {tx, ty}
				-- grass is likelier than bare dirt
				for _ = 2, ok[ty][tx] == 1 and HERB.GrassWeight or 1 do list[#list + 1] = {tx, ty} end
			end
		end
	end
	return list
end

local function nearSprite(x, y, spots)
	local g2 = HERB.SpriteGap*HERB.SpriteGap
	for i = 0, Map.Sprites.Count - 1 do
		local s = Map.Sprites[i]
		local dx, dy = s.X - x, s.Y - y
		if dx*dx + dy*dy < g2 then return true end
	end
	g2 = HERB.HerbGap*HERB.HerbGap
	for _, p in ipairs(spots) do
		local dx, dy = p.X - x, p.Y - y
		if dx*dx + dy*dy < g2 then return true end
	end
end

local function nearModel(x, y)
	local g = HERB.ModelGap
	for _, m in Map.Models do
		if x > m.MinX - g and x < m.MaxX + g and y > m.MinY - g and y < m.MaxY + g then return true end
	end
end

local function makeSpots()
	local list = candidates()
	local n = min(random(HERB.Min, HERB.Max), floor(#list / HERB.TilesPerShrub))
	local spots = {}
	local tries = 0
	while #spots < n and #list > 0 and tries < n*40 do
		tries = tries + 1
		local k = random(#list)
		local c = list[k]
		list[k] = list[#list]; list[#list] = nil
		local x = (c[1] - 64)*512 + random(64, 448)
		local y = (63 - c[2])*512 + random(64, 448)
		if not nearModel(x, y) and not nearSprite(x, y, spots) then
			local z = Map.GetGroundLevel(x, y)
			local fz = Map.GetFloorLevel(x, y, z + 2000)
			if abs((fz or z) - z) <= 16 then
				spots[#spots + 1] = {X = x, Y = y, Z = z, Herb = KINDS[random(3)],
					Dir = random(0, 2047)}
			end
		end
	end
	return spots
end

---------------------------------------------------------------------------
-- picking
---------------------------------------------------------------------------

local function bonus()
	local best = 0
	for _, pl in Party do
		local _, m = SplitSkill(pl.Skills[const.Skills.Alchemy] or 0)
		if (m or 0) > best then best = m end
	end
	return (best >= 2 and 1 or 0) + (best >= 3 and 1 or 0)
end

local function pick(s)
	if winter() then
		Game.ShowStatusText(Tx"The shrub is bare: nothing grows in winter.")
		return
	end
	if s.Picked then
		Game.ShowStatusText(Tx"This shrub has been picked already.")
		return
	end
	s.Picked = true
	local item = HERBS[s.Herb].Items[continent()]
	local n = 1 + bonus()
	for _ = 1, n do
		evt.Add("Inventory", item)
	end
	local name = Game.ItemsTxt[item].Name
	Game.ShowStatusText(n > 1 and string.format(Tx"You pick %s (%d).", name, n)
		or string.format(Tx"You pick %s.", name))
end

---------------------------------------------------------------------------
-- the sprites, and the saves
---------------------------------------------------------------------------

local Own, Added    -- the map's own sprite count, the count with the shrubs

local function placeShrubs(spots)
	Own = Map.Sprites.Count
	for _, s in ipairs(spots) do
		local sp, i = CreateSprite{HERBS[s.Herb].Pic, s.X, s.Y, s.Z, Direction = s.Dir}
		if not sp then break end
		local ev = EVBASE + i
		sp.Event = ev
		evt.hint[ev] = HERBS[s.Herb].Hint
		evt.map[ev] = function() pick(s) end
	end
	Added = Map.Sprites.Count
	if Added > Own then RebildIDList() else Own, Added = nil, nil end
end

-- (25.11.26) the first version turned bushes listed in Data/Tables/Herb shrubs.txt into
-- herb shrubs, and the picture is saved with the map: they get their own picture back
local OldSpots
local function revertOld()
	if OldSpots == nil then
		OldSpots = {}
		local f = io.open("Data/Tables/Herb shrubs.txt", "r")
		if f then
			for line in f:lines() do
				local map, spr, was = line:match("^([^\t]+)\t(%d+)\t[^\t]*\t[^\t]*\t[^\t]*\t([^\t\r]+)")
				if map then
					map = map:lower()
					OldSpots[map] = OldSpots[map] or {}
					table.insert(OldSpots[map], {tonumber(spr), was})
				end
			end
			f:close()
		end
	end
	for _, o in ipairs(OldSpots[(Map.Name or ""):lower()] or {}) do
		local sp = o[1] < Map.Sprites.Count and Map.Sprites[o[1]]
		if sp and (sp.DecName or ""):lower():find("^herbspr") then
			sp.DecName = o[2]
			sp.Event = 0
		end
	end
end

local function setup()
	Own, Added = nil, nil
	pcall(revertOld)
	if not Map.IsOutdoor() or HERB.Skip[mapName()] then return end
	if not mapvars.MMMWE_Herbs then
		mapvars.MMMWE_Herbs = makeSpots()
	end
	placeShrubs(mapvars.MMMWE_Herbs)
end

function events.AfterLoadMap()
	local ok, err = pcall(setup)
	if not ok and MF.LogWarning then MF.LogWarning("MMMWE herb shrubs: " .. tostring(err)) end
end

local function restoreOwn()
	if Own then Map.Sprites.Count = Own end
end

function events.BeforeSaveGame() restoreOwn() end
function events.AfterSaveGame()
	if Own and Added then Map.Sprites.Count = Added end
end
function events.LeaveMap()
	restoreOwn()
	Own, Added = nil, nil
end
