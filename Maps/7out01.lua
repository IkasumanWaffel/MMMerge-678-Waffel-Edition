-- Emerald Island

function events.AfterLoadMap()
	Party.QBits[816] = true	-- DDMapBuff
	if Party.QBits[825] == true then
		Game.MapEvtLines:RemoveEvent(24)
		evt.HouseDoor(24, 485)  -- "Ship"
		evt.house[25] = 485  -- "Ship"
	end
end


-- Remove arcomage from Emerald Island's taverns
function events.DrawShopTopics(t)
	if t.HouseType == const.HouseType.Tavern then
		t.Handled = true
		t.NewTopics[1] = const.ShopTopics.RentRoom
		t.NewTopics[2] = const.ShopTopics.BuyFood
		t.NewTopics[3] = const.ShopTopics.Learn
	end
end


