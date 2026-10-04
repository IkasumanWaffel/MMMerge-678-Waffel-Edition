Game.MapEvtLines:RemoveEvent(454)
evt.map[454] = function()
	evt.Subtract("Gold", 10)
	--evt.Add{"Inventory", 1022}	-- "_potion/reagent"
	evt.Add("Inventory", 220)	-- "Potion Bottle"
end

Game.MapEvtLines:RemoveEvent(501)
evt.map[501] = function()
	if vars.TempleInABottleEnteredFrom then -- set in General/UsableItems.lua
		evt.MoveToMap(vars.TempleInABottleEnteredFrom)
		vars.TempleInABottleEnteredFrom = nil
	else
		evt.MoveToMap{X = -177331, Y = 12547, Z = 465, Direction = 0, LookAngle = 0, SpeedZ = 0, HouseId = 0, Icon = 8, Name = "out02.odm"}
	end
end
