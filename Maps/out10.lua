-- Mount Nighon
local MF = Merge.Functions

function events.AfterLoadMap()
	Party.QBits[721] = true	-- TP Buff Nighon
	Party.QBits[825] = true	-- DDMapBuff
end

-- Town Portal fountain
evt.map[206] = function()
	MF.SetLastFountain()
end

function events.AfterLoadMap()
	if evt.CheckSeason{Season = 3} then
		Map.Tilesets[0].Group = 1
		Map.LoadTileset(1)
	else
		-- (MMMWE 22.11.26) the wasteland set (8), as in out12: the dirt set (4) has only the base
		-- tiles, no borders, so the borders of the map's own snow set showed as broken tiles
		Map.Tilesets[0].Group = 8
		Map.LoadTileset(8)
	end
end

evt.HouseDoor(17, 495)  -- "Ship"
evt.house[18] = 495  -- "Ship"

