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
		Map.Tilesets[0].Group = 4
		Map.LoadTileset(4)
	end
end

evt.HouseDoor(17, 495)  -- "Ship"
evt.house[18] = 495  -- "Ship"

