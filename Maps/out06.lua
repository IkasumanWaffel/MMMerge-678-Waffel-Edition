-- Shadowspire
local MF = Merge.Functions

function events.AfterLoadMap()
	Party.QBits[806] = true	-- DDMapBuff
	if Party.QBits[294] then
		evt.SetSprite(12, 1, "OrMatt1")
	end
end

GroundTex = "gdtyl"
GroundTex = Game.BitmapsLod:LoadBitmap(GroundTex)
Game.BitmapsLod.Bitmaps[GroundTex]:LoadBitmapPalette()

LocalFile(Game.TileBin)
for i = 1, 12 do
	if string.sub(Game.TileBin[i].Name, 1, 4) == "dirt" then
		Game.TileBin[i].Bitmap = GroundTex
	end
end

local TileSounds = {
[5] = {[0] = 101, 	[1] = 62}
}

function events.TileSound(t)
	local Grp = TileSounds[Game.CurrentTileBin[Map.TileMap[t.X][t.Y]].TileSet]
	if Grp then
		t.Sound = Grp[t.Run]
	end
end

-- Town Portal fountain
evt.map[104] = function()
	Party.QBits[305] = true	-- TP Buff Shadowspire
	MF.SetLastFountain()
end

evt.map[410] = function()
	if Party.QBits[293] and not Party.QBits[294] and evt.All.Cmp("Inventory", 668) then
		Party.QBits[294] = true
		evt.SetSprite(12, 1, "OrMatt1")
	end
end

Game.MapEvtLines:RemoveEvent(495)
evt.hint[495] = evt.str[40]
evt.map[495] = function()
	local i
	if evt.Cmp{"QBits", Value = 279} then	-- Reagant spout area 6
		return
	end
	if not evt.Cmp{"PerceptionSkill", Value = 5} then
		return
	end
	i = Game.Rand() % 4
	if i == 1 then
		evt.SummonObject{Item = 200138, X = -3136, Y = -4032, Z = 348, Speed = 1000, Count = 1, RandomAngle = true}	-- "Gold Ring"
	elseif i == 2 then
		evt.SummonObject{Item = 200139, X = -3136, Y = -4032, Z = 348, Speed = 1000, Count = 1, RandomAngle = true}	-- "Pearl Ring"
	elseif i == 3 then
		evt.SummonObject{Item = 200140, X = -3136, Y = -4032, Z = 348, Speed = 1000, Count = 1, RandomAngle = true}	-- "Gemstone Ring"
	else
		evt.SummonObject{Item = 200141, X = -3136, Y = -4032, Z = 348, Speed = 1000, Count = 1, RandomAngle = true}	-- "Amethyst Ring"
	end
	evt.Add{"QBits", Value = 279}	-- Reagant spout area 6
end


