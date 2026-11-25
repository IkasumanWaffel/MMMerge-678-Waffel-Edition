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

-- (MMMWE 25.11.26) the three buildings added to the town: MM7's unused Nighon houses (the town
-- hall and the bank had their rows in 2DEvents.txt, map 69, but no building) and a spare
-- alchemist's shop. The door facets of the new models get their events here.
local NewDoors = {
	{Model = "13rp_temple_N_1", Facets = {28, 53}, Event = 31, House = 207},  -- Hall of Midnight (town hall)
	{Model = "Human", Facets = {39}, Event = 32, House = 290},                -- Frozen Assets (bank)
	{Model = "13rp_alchemistN", Facets = {11}, Event = 33, House = 126},      -- alchemist's shop
}
for _, d in ipairs(NewDoors) do
	evt.HouseDoor(d.Event, d.House)
end

function events.AfterLoadMap()
	for _, d in ipairs(NewDoors) do
		for _, m in Map.Models do
			if m.Name == d.Model then
				for _, k in ipairs(d.Facets) do
					local f = k < m.Facets.count and m.Facets[k]
					if f then
						f.Event = d.Event
						pcall(function() f.TriggerByClick = true end)
					end
				end
				break
			end
		end
	end
end
