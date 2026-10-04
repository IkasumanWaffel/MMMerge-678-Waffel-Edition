-- Ravenshore
local MF = Merge.Functions

function events.AfterLoadMap()
	Party.QBits[802] = true	-- DDMapBuff
end

-- Town Portal fountain
evt.map[104] = function()
	Party.QBits[302] = true	-- TP Buff Ravenshore
	MF.SetLastFountain()
end

-- Final part of Cross continents quest

local function InBreachRange()
	local QSet = vars.Quest_CrossContinents
	return QSet and QSet.GotFinalQuest and 600 > math.sqrt((15103-Party.X)^2 + (-9759-Party.Y)^2)
end

function events.TileSound(t)
	if InBreachRange() then
		TownPortalControls.DimDoorEvent()
	end
end

function events.CanCastTownPortal(t)
	if InBreachRange() then
		local QSet = vars.Quest_CrossContinents
		t.CanCast = false
		evt.MoveToMap{0,0,0,0,0,0,0,0, QSet.QuestFinished and "Breach.odm" or "BrAlvar.odm"}
	end
end

function events.LoadMap()
	if vars.Quest_CrossContinents and Party.QBits[56] then
		vars.Quest_CrossContinents.ContinentFinished[1] = true
	end
end

-- Allow entering crystal without conflux key, if it was opened at least once before
Game.MapEvtLines:RemoveEvent(504)
evt.map[504] = function()
	evt.ForPlayer("All")
	if mapvars.CrystalOpened or evt.Cmp("Inventory", 610) then -- "Conflux Key"
		mapvars.CrystalOpened = true
		evt.MoveToMap{X = -1024, Y = -1626, Z = 0, Direction = 520, LookAngle = 0, SpeedZ = 0, HouseId = 355, Icon = 1, Name = "D10.blv"} -- "Inside the Crystal"
	else
		evt.FaceAnimation{Player = "Current", Animation = 18}
	end
end

