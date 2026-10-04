-- Bootleg Bay

function events.AfterLoadMap()
	Party.QBits[841] = true	-- DDMapBuff
end

function events.AfterLoadMap()
	if evt.CheckSeason{Season = 3} then
		Map.Tilesets[0].Group = 1
		Map.LoadTileset(1)
	else
		Map.Tilesets[0].Group = 0
		Map.LoadTileset(0)
	end
end
