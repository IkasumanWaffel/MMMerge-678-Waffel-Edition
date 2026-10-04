-- Ironsand Desert

local TileSounds = {
[0] = {[0] = 91, 	[1] = 52},
[5] = {[0] = 101, 	[1] = 62},
[6] = {[0] = 90, 	[1] = 51}
}

function events.TileSound(t)
	local Grp = TileSounds[Game.CurrentTileBin[Map.TileMap[t.X][t.Y]].TileSet]
	if Grp then
		t.Sound = Grp[t.Run]
	end
end

function events.AfterLoadMap()
	Party.QBits[804] = true	-- DDMapBuff
end

Game.MapEvtLines:RemoveEvent(495)
evt.hint[495] = evt.str[41]
evt.map[495] = function()
	local i
	if evt.Cmp{"QBits", Value = 277} then	-- Reagant spout area 4
		return
	end
	if not evt.Cmp{"PerceptionSkill", Value = 5} then
		return
	end
	i = Game.Rand() % 4
	if i == 1 then
		evt.SummonObject{Item = 200138, X = 1728, Y = -3776, Z = 1008, Speed = 1000, Count = 1, RandomAngle = true}	-- "Gold Ring"
	elseif i == 2 then
		evt.SummonObject{Item = 200139, X = 1728, Y = -3776, Z = 1008, Speed = 1000, Count = 1, RandomAngle = true}	-- "Pearl Ring"
	elseif i == 3 then
		evt.SummonObject{Item = 200140, X = 1728, Y = -3776, Z = 1008, Speed = 1000, Count = 1, RandomAngle = true}	-- "Gemstone Ring"
	else
		evt.SummonObject{Item = 200141, X = 1728, Y = -3776, Z = 1008, Speed = 1000, Count = 1, RandomAngle = true}	-- "Amethyst Ring"
	end
	evt.Add{"QBits", Value = 277}	-- Reagant spout area 4
end


