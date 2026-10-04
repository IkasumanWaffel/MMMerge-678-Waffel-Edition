-- The Bracada Desert

function events.AfterLoadMap()
	Party.QBits[821] = true	-- DDMapBuff
end

evt.hint[318] = evt.str[100]  -- ""
evt.map[318] = function()
	evt.MoveToMap{X = 16170, Y = -3720, Z = 3072, Direction = 512, LookAngle = 0, SpeedZ = 0, HouseId = 0, Icon = 0, Name = "0."}
end
evt.hint[470] = "Airship Docks"

evt.HouseDoor(115, 468)  -- "Led Zeppelin"
evt.house[116] = 468  -- "Led Zeppelin"