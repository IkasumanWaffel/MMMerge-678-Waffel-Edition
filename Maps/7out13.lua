-- Tatalia

-- Fix snow tile step sounds
local TileSounds = {
[1] = {[0] = 97, 	[1] = 58},
[5] = {[0] = 97, 	[1] = 58}
}

function events.TileSound(t)
	local Grp = TileSounds[Game.CurrentTileBin[Map.TileMap[t.X][t.Y]].TileSet]
	if Grp then
		t.Sound = Grp[t.Run]
	end
end

function events.AfterLoadMap()
	Party.QBits[828] = true	-- DDMapBuff
end

----------------------------------------
-- Adventurer's Inn

evt.house[82] = 1607
evt.map[82] = function() evt.EnterHouse{1607} end

function events.AfterLoadMap()
	if Map.Vars[1] < 1 and Party.QBits[535] == true then
		Party.Reputation = Party.Reputation - 10
		Map.Vars[1] = 1 
	end
end
