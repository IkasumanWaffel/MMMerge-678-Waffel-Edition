--[[
	MMMWE_SeasonalTrees.lua - the trees of the MM6 maps follow the seasons (24.11.26)

	MM7's outdoor maps change their trees on load: every tree given an id by the map editor
	gets its autumn picture in autumn and its bare (or snowy) picture in winter (the load
	events of 7out02, 7out03, 7out04, out11, out14). The MM6 maps whose ground turns to snow
	in winter (their Scripts\Maps\<map>.lua) have no such trees: MM6 has no seasonal pictures.
	Here their broadleaf trees take MM7's autumn and winter pictures, the flowering trees
	lose their blossom in winter and the conifers get snow; spring and summer show the map's
	own trees. Food trees (6tree06, tree06a: their events change their pictures), palms,
	swamp trees and the snowy trees of the Frozen Highlands are left as they are.

	The map's own tree of each sprite is kept in mapvars (the sprite's picture is saved with
	the map), so the trees come back in spring.
--]]

local MAPS = {outa1 = true, outc2 = true, outd1 = true, outd2 = true, outd3 = true,
	oute1 = true, oute2 = true, oute3 = true}

-- the map's tree -> {autumn, winter}; nil keeps the tree in that season.
-- (24.11.26) The pictures are MM7's, in copies sized to the MM6 tree they stand for
-- (DecList.txt / SFT.txt s6tNNa / s6tNNw, the MM7 picture with a smaller SFT scale): MM7's
-- trees drawn at their own scale came out two to five times taller.
local TREES = {
	["6tree01"] = {"s6t01a", "s6t01w"},   -- 7tree14 yellow / 7tree15 bare
	["6tree02"] = {"s6t02a", "s6t02w"},   -- 7tree05 / 7tree06
	["6tree05"] = {"s6t05a", "s6t05w"},   -- 7tree17 / 7tree18
	["6tree10"] = {"s6t10a", "s6t10w"},   -- 7tree08 / 7tree09
	["6tree15"] = {"s6t15a", "s6t15w"},   -- 7tree20 red / 7tree21
	["6tree19"] = {"s6t19a", "s6t19w"},   -- tree26 red / tree27
	["6tree03"] = {nil, "s6t03w"},        -- flowering trees: bare in winter (7tree24)
	["6tree04"] = {nil, "s6t04w"},
	["6tree18"] = {nil, "s6t18w"},        -- conifers: snow in winter (tree33)
	["6tree25"] = {nil, "s6t25w"},        -- (tree36)
}

local function season()
	for s = 3, 1, -1 do
		if evt.CheckSeason{Season = s} then return s end
	end
	return 0
end

local function apply()
	local name = (Map.Name or ""):lower():gsub("%.odm$", "")
	if not MAPS[name] then return end
	local s = season()
	mapvars.MMMWE_SeasonTrees = mapvars.MMMWE_SeasonTrees or {}
	local orig = mapvars.MMMWE_SeasonTrees
	local changed = 0
	for i = 0, Map.Sprites.count - 1 do
		local sp = Map.Sprites[i]
		local own = orig[i]
		if not own then
			local cur = sp.DecName
			if cur and TREES[cur:lower()] then
				own = cur:lower()
				orig[i] = own
			end
		end
		if own then
			local t = TREES[own]
			local want = (s == 3 and t[2]) or (s == 2 and t[1]) or own
			if (sp.DecName or ""):lower() ~= want then
				sp.DecName = want
				changed = changed + 1
			end
		end
	end
	if changed > 0 and Merge.Functions.LogInfo then
		Merge.Functions.LogInfo("[SeasonalTrees] %s, season %d: %d trees changed", name, s, changed)
	end
end

function events.AfterLoadMap()
	local ok, err = pcall(apply)
	if not ok and Merge.Functions.LogWarning then
		Merge.Functions.LogWarning("[SeasonalTrees] %s", tostring(err))
	end
end
