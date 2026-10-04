-- New Sorpigal
local MF = Merge.Functions
local MM = Merge.ModSettings

local TileSounds = {
[6] = {[0] = 90, 	[1] = 51}
}

function events.TileSound(t)
	local Grp = TileSounds[Game.CurrentTileBin[Map.TileMap[t.X][t.Y]].TileSet]
	if Grp then
		t.Sound = Grp[t.Run]
	end
end

----------------------------------------

function events.AfterLoadMap()
	LocalHostileTxt()
	Game.HostileTxt[185][0] = 0
	Party.QBits[183] = true -- Town portal
	Party.QBits[313] = true	-- TP Buff New Sorpigal
	Party.QBits[845] = true	-- DDMapBuff
end

----------------------------------------
-- Loretta Fleise's fix prices quest

Game.MapEvtLines:RemoveEvent(15)
evt.house[15] = 470
evt.map[15] = function() StdQuestsFunctions.CheckPrices(470, 1523) end

Game.MapEvtLines:RemoveEvent(16)
evt.house[16] = 470
evt.map[16] = function() StdQuestsFunctions.CheckPrices(470, 1523) end

-- Town Portal fountain
evt.map[131] = function()
	MF.SetLastFountain()
end
----------------------------------------
-- Dragon tower

--[[
Game.MapEvtLines:RemoveEvent(230)
if not Party.QBits[1180] then

	local function DragonTower()
		StdQuestsFunctions.DragonTower(-6152, -9208, 2700, 1180)
	end
	Timer(DragonTower, 5*const.Minute)

	function events.LeaveMap()
		RemoveTimer(DragonTower)
	end

end
]]

Game.MapEvtLines:RemoveEvent(231)
evt.map[231] = function()
	if not Party.QBits[1180] and evt.ForPlayer("All").Cmp{"Inventory", 2106} then
		evt.Set{"QBits", 1180}
		StdQuestsFunctions.SetTextureOutdoors(84, 42, "t1swbu")
	end
end

evt.map[232] = function()
	if Party.QBits[1180] then
		StdQuestsFunctions.SetTextureOutdoors(84, 42, "t1swbu")
	end
end

----------------------------------------
-- Give Master 5 Fly spell scroll
if MM.SpellScrollRanks == 1 then
	Game.MapEvtLines:RemoveEvent(225)
        evt.map[225] = function()
		if Map.Vars[59] == 0 then
			evt.Add("Inventory", 320)	-- "Fly"
			Map.Vars[59] = 1
		end
	end
end

----------------------------------------
-- Dimension door

evt.map[140] = function()
	if not evt.Cmp{"MapVar50", 1} then
		TownPortalControls.DimDoorEvent()
	end
end

----------------------------------------
-- Volcano

Game.MapEvtLines:RemoveEvent(220)
evt.map[220] = function()
	Game.PlaySound(18090)

	local rand = math.random
	for i = 1, 6 do
		evt.CastSpell{6, 4, 10, -14074, 16106, 1250, rand(-14024, -14124), rand(16056, 16156), 1500}
	end

	evt.CastSpell{43, 4, 10, -14320, 16272, 1400, rand(-14220, -14420), rand(16172, 16372), 2400}
	evt.CastSpell{43, 4, 10, -14096, 15648, 1400, rand(-14000, -14200), rand(15548, 15748), 2400}
	evt.CastSpell{43, 4, 10, -13856, 16448, 1400, rand(-13756, -13956), rand(16348, 16548), 2400}

	Timer(function()
		for i = 1, 6 do
			local x, y = rand(-20549, -7225), rand(11879, 18122)
			evt.CastSpell{9, 4, 10, x, y, 5084, x, y, 3000}
		end
		RemoveTimer()
		end, 256)
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
