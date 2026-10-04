-- Sweet Water

function events.AfterLoadMap()
	Party.QBits[831] = true	-- DDMapBuff
end

function events.AfterLoadMap()
	if evt.CheckSeason{Season = 3} then
		Map.Tilesets[0].Group = 1
		Map.LoadTileset(1)
	else
		Map.Tilesets[0].Group = 6
		Map.LoadTileset(6)
	end
end
