-- The Barrow Downs

function events.AfterLoadMap()
	Party.QBits[826] = true	-- DDMapBuff
end

Game.MapEvtLines:RemoveEvent(501)
evt.hint[501] = evt.str[30]
evt.map[501] = function()
	evt.MoveToMap {179, -5386, 33, 240, 0, 0, 408, 2, "7d24.blv"}
	--evt.MoveToMap {245, -5362, 34, 512, 0, 0, 408, 2, "7d24.blv"}
end

function events.AfterLoadMap()
	if evt.CheckSeason{Season = 3} then
		Map.Tilesets[0].Group = 1
		Map.Tilesets[2].Group = 1
		for i,v in Map.Tilesets do
			Map.LoadTileset(1)
		end
	else
		Map.Tilesets[0].Group = 0
		Map.Tilesets[2].Group = 0
		for i,v in Map.Tilesets do
			Map.LoadTileset(0)
		end
	end
end

evt.HouseDoor(5, 469)  -- "Led Zeppelin"
evt.house[6] = 469  -- "Led Zeppelin"