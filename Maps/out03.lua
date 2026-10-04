-- Alvar
local MF = Merge.Functions

function events.AfterLoadMap()
	Party.QBits[803] = true	-- DDMapBuff
end

-- Town Portal fountain
evt.map[104] = function()
	Party.QBits[301] = true	-- TP Buff Alvar
	MF.SetLastFountain()
end

Game.MapEvtLines:RemoveEvent(495)
evt.hint[495] = evt.str[40]
evt.map[495] = function()
	local i
	if evt.Cmp{"QBits", Value = 276} then	-- Reagant spout area 3
		return
	end
	if not evt.Cmp{"PerceptionSkill", Value = 5} then
		return
	end
	i = Game.Rand() % 4
	if i == 1 then
		evt.SummonObject{Item = 200138, X = 14624, Y = -160, Z = 3296, Speed = 1000, Count = 1, RandomAngle = true}	-- "Gold Ring"
	elseif i == 2 then
		evt.SummonObject{Item = 200139, X = 14624, Y = -160, Z = 3296, Speed = 1000, Count = 1, RandomAngle = true}	-- "Pearl Ring"
	elseif i == 3 then
		evt.SummonObject{Item = 200140, X = 14624, Y = -160, Z = 3296, Speed = 1000, Count = 1, RandomAngle = true}	-- "Gemstone Ring"
	else
		evt.SummonObject{Item = 200141, X = 14624, Y = -160, Z = 3296, Speed = 1000, Count = 1, RandomAngle = true}	-- "Amethyst Ring"
	end
	evt.Add{"QBits", Value = 276}	-- Reagant spout area 3
end


