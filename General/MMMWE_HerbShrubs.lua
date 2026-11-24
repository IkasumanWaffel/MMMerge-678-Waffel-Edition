--[[
	MMMWE_HerbShrubs.lua - herb shrubs to pick reagents from (25.11.26)

	MM6 drew three herb shrubs that no map ever placed (herbspr01..03 in the MM6 sprites):
	a red-berried Widowsweep bush, the leaves of a Phirna root and a yellow Poppysnaps plant.
	Here they grow on the outdoor maps of all three games, on hand-picked spots listed in
	Data/Tables/Herb shrubs.txt: an ordinary bush, plant or flower of the map (its sprite
	index and old picture in the table) becomes the herb shrub. Rows can be added, moved or
	removed there; a row whose sprite no longer shows the picture in the Was column is skipped
	(another version of the map), so a wrong row does no harm.

	Click a shrub to pick it:
	  1 reagent; +1 if someone in the party is an Expert in Alchemy, +1 more at Master or
	    above (the best alchemist counts);
	  the reagent of the continent: Jadame gives MM8's Widowsweep Berries, Phima Root and
	    Poppy Pod, Antagarich and Enroth MM7's Widowsweep Berries, Phirna Root and Poppysnaps;
	  a picked shrub grows back when the map refills (mapvars);
	  nothing in winter.

	The shrubs use the sprite event numbers 20000 + sprite index (MMExt's convention).
--]]

local MF = Merge.Functions
local Tx = Merge.Functions.Text

local FILE = "Data/Tables/Herb shrubs.txt"
local EVBASE = 20000

local HERBS = {
	Widowsweep = {Pic = "herbspr01", Items = {[1] = 200, [2] = 1002, [3] = 1002}},
	Phirna     = {Pic = "herbspr02", Items = {[1] = 205, [2] = 1007, [3] = 1007}},
	Poppysnaps = {Pic = "herbspr03", Items = {[1] = 210, [2] = 1012, [3] = 1012}},
}
local HINTS = {
	Widowsweep = Tx"Widowsweep bush",
	Phirna = Tx"Phirna plant",
	Poppysnaps = Tx"Poppysnaps",
}

-- [map] = {{Sprite, Herb, Was}, ...}
local Shrubs
MF.HerbShrubs = HERBS

local function loadTable()
	Shrubs = {}
	local f = io.open(FILE, "r")
	if not f then
		if MF.LogWarning then MF.LogWarning("MMMWE herb shrubs: no " .. FILE) end
		return
	end
	local first = true
	for line in f:lines() do
		line = line:gsub("\r$", "")
		if first then
			first = false
		elseif line ~= "" and line:sub(1, 1) ~= "#" then
			local c = {}
			for w in (line .. "\t"):gmatch("([^\t]*)\t") do c[#c + 1] = w end
			local map, spr, herb = (c[1] or ""):lower(), tonumber(c[2]), c[3]
			if map ~= "" and spr and HERBS[herb] then
				Shrubs[map] = Shrubs[map] or {}
				table.insert(Shrubs[map], {Sprite = spr, Herb = herb, Was = (c[6] or ""):lower()})
			end
		end
	end
	f:close()
end

local function winter() return evt.CheckSeason{Season = 3} end

local function continent()
	local c = Merge.Vars and Merge.Vars.Continent
	return (c == 2 or c == 3) and c or 1
end

-- extra reagents for the party's best alchemist
local function bonus()
	local best = 0
	for _, pl in Party do
		local _, m = SplitSkill(pl.Skills[const.Skills.Alchemy] or 0)
		if (m or 0) > best then best = m end
	end
	return (best >= 2 and 1 or 0) + (best >= 3 and 1 or 0)
end

local function pick(s, i)
	local picked = mapvars.MMMWE_HerbsPicked or {}
	mapvars.MMMWE_HerbsPicked = picked
	if winter() then
		Game.ShowStatusText(Tx"The shrub is bare: nothing grows in winter.")
		return
	end
	if picked[i] then
		Game.ShowStatusText(Tx"This shrub has been picked already.")
		return
	end
	picked[i] = true
	local item = HERBS[s.Herb].Items[continent()]
	local n = 1 + bonus()
	for _ = 1, n do
		evt.Add("Inventory", item)
	end
	local name = Game.ItemsTxt[item].Name
	Game.ShowStatusText(n > 1 and string.format(Tx"You pick %s (%d).", name, n)
		or string.format(Tx"You pick %s.", name))
end

local function setup()
	if not Shrubs then loadTable() end
	if Map.IsIndoors() then return end
	local list = Shrubs[(Map.Name or ""):lower()]
	if not list then return end
	for _, s in ipairs(list) do
		local i = s.Sprite
		local sp = i < Map.Sprites.count and Map.Sprites[i]
		local herb = HERBS[s.Herb]
		local cur = sp and (sp.DecName or ""):lower()
		if cur and (cur == s.Was or cur == herb.Pic) then
			if cur ~= herb.Pic then sp.DecName = herb.Pic end
			local ev = EVBASE + i
			sp.Event = ev
			evt.hint[ev] = HINTS[s.Herb]
			evt.map[ev] = function() pick(s, i) end
		end
	end
end

function events.AfterLoadMap()
	local ok, err = pcall(setup)
	if not ok and MF.LogWarning then MF.LogWarning("MMMWE herb shrubs: " .. tostring(err)) end
end
