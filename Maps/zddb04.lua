-- Warehouse
local LogId = "zddb04"
local MF = Merge.Functions
MF.LogInit1(LogId)

Game.MapEvtLines.Count = 0  -- Deactivate all standard events

--[[
evt.hint[1] = evt.str[1]  -- "Bench"
evt.map[1] = function()
	if not evt.Cmp{"MapVar0", Value = 1} then
		evt.Add{"MapVar0", Value = 1}
		evt.StatusText{Str = 2}         -- "You find a small wooden dowl."
	end
end

evt.hint[2] = evt.str[3]  -- "Crate"
evt.map[2] = function()
	evt.OpenChest{Id = 1}
end

evt.hint[3] = evt.str[3]  -- "Crate"
evt.map[3] = function()
	evt.OpenChest{Id = 0}
end
]]

function events.LoadMapScripts()
	MF.LogVerbose("%s: LoadMapScripts", LogId)
	vars.WarehouseChests = math.min(vars.WarehouseChests or 0, 18)
	for i = 1, 2 + vars.WarehouseChests do
		evt.SetFacetBit{Id = i, Bit = const.FacetBits.Untouchable, On = false}
		evt.SetFacetBit{Id = i, Bit = const.FacetBits.Invisible, On = false}
	end
	for i = 3 + vars.WarehouseChests, 20 do
		evt.SetFacetBit{Id = i, Bit = const.FacetBits.Untouchable, On = true}
		evt.SetFacetBit{Id = i, Bit = const.FacetBits.Invisible, On = true}
	end
end

function events.CanCastLloyd(t)
	t.Result = false
end

evt.hint[176] = evt.str[8]  -- "Chest"
evt.map[176] = function()
	evt.OpenChest(0)
end

evt.hint[177] = evt.str[8]  -- "Chest"
evt.map[177] = function()
	evt.OpenChest(1)
end

evt.hint[178] = evt.str[8]  -- "Chest"
evt.map[178] = function()
	evt.OpenChest(2)
end

evt.hint[179] = evt.str[8]  -- "Chest"
evt.map[179] = function()
	evt.OpenChest(3)
end

evt.hint[180] = evt.str[8]  -- "Chest"
evt.map[180] = function()
	evt.OpenChest(4)
end

evt.hint[181] = evt.str[3]  -- "Crate"
evt.map[181] = function()
	evt.OpenChest(5)
end

evt.hint[182] = evt.str[8]  -- "Chest"
evt.map[182] = function()
	evt.OpenChest(6)
end

evt.hint[183] = evt.str[8]  -- "Chest"
evt.map[183] = function()
	evt.OpenChest(7)
end

evt.hint[184] = evt.str[8]  -- "Chest"
evt.map[184] = function()
	evt.OpenChest(8)
end

evt.hint[185] = evt.str[8]  -- "Chest"
evt.map[185] = function()
	evt.OpenChest(9)
end

evt.hint[186] = evt.str[8]  -- "Chest"
evt.map[186] = function()
	evt.OpenChest(10)
end

evt.hint[187] = evt.str[3]  -- "Crate"
evt.map[187] = function()
	evt.OpenChest(11)
end

evt.hint[188] = evt.str[8]  -- "Chest"
evt.map[188] = function()
	evt.OpenChest(12)
end

evt.hint[189] = evt.str[3]  -- "Crate"
evt.map[189] = function()
	evt.OpenChest(13)
end

evt.hint[190] = evt.str[3]  -- "Crate"
evt.map[190] = function()
	evt.OpenChest(14)
end

evt.hint[191] = evt.str[8]  -- "Chest"
evt.map[191] = function()
	evt.OpenChest(15)
end

evt.hint[192] = evt.str[8]  -- "Chest"
evt.map[192] = function()
	evt.OpenChest(16)
end

evt.hint[193] = evt.str[3]  -- "Crate"
evt.map[193] = function()
	evt.OpenChest(17)
end

evt.hint[194] = evt.str[8]  -- "Chest"
evt.map[194] = function()
	evt.OpenChest(18)
end

evt.hint[195] = evt.str[3]  -- "Crate"
evt.map[195] = function()
	evt.OpenChest(19)
end

evt.hint[501] = evt.str[9]  -- "Exit"
evt.map[501] = function()
	evt.MoveToMap{X = 10960, Y = 13450, Z = 161, Direction = 512, LookAngle = 0, SpeedZ = 0, HouseId = 0, Icon = 0, Name = "outc2.odm"}
end

MF.LogInit2(LogId)

