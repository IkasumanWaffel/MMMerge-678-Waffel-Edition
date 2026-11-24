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

-- (MMMWE 25.11.26) the two Thunderfist Mountain entrances nearest the town: a warlock envoy
-- meets the party there for the peace talks (Global/MMMWE_WarlockPeace.lua)
local Thunderfist = {
	[501] = {X = -1024, Y = 768, Z = 4097, Direction = 1792, LookAngle = 0, SpeedZ = 0, HouseId = 406, Icon = 9, Name = "7d07.blv"},
	[505] = {X = 11471, Y = -3498, Z = 2814, Direction = 414, LookAngle = 0, SpeedZ = 0, HouseId = 406, Icon = 9, Name = "7d07.blv"},
}
for n, dest in pairs(Thunderfist) do
	Game.MapEvtLines:RemoveEvent(n)
	evt.hint[n] = evt.str[30]  -- "Enter Thunderfist Mountain"
	evt.map[n] = function()
		if MF.WarlockEnvoy and MF.WarlockEnvoy() then
			return
		end
		evt.MoveToMap(dest)
	end
end
