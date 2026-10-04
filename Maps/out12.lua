-- The Land of the Giants
local LogId = "out12"
local MF = Merge.Functions
MF.LogInit1(LogId)
local MM = Merge.ModSettings

-- Correct load map event.
Game.MapEvtLines:RemoveEvent(1)
local function event1()
	Sleep(1000, 1000)

	local QB = Party.QBits
	local need_speak = not QB[775] and (QB[616] or QB[635])

	if need_speak then
		QB[775] = true

		if QB[616] then
			evt.SetNPCGreeting{462, 316}
		elseif QB[635] then
			evt.SetNPCGreeting{462, 317}
		end

		if Mouse.Item.Number ~= 0 then
			Mouse:ReleaseItem()
		end

		Mouse.Item.Number = 866
		Mouse.Item.Identified = true

		evt.SpeakNPC{462}
	end
end

function events.AfterLoadMap()
	coroutine.resume(coroutine.create(event1))
	Party.QBits[827] = true	-- DDMapBuff
end

local pct = MM and tonumber(MM.EofolWellGoldPreservePct) or 0

Game.MapEvtLines:RemoveEvent(205)
evt.hint[205] = evt.str[3]
evt.map[205] = function()
	local i, j
	if Party.Gold >= 5000 then
		if math.random(100) > pct then
			mem.call(0x4914BF, 1, 4999)
		end
		j = Game.Rand() % 3
		if j == 1 then
			i = Game.Rand() % 4
			if i == 1 then
				evt.Set{"Eradicated", Value = 0}
			elseif i == 2 then
				--evt.Set{"AgeBonus", Value = 0}	-- MM7 behavior
				evt.Add{"AgeBonus", Value = 1}	-- Revamp behavior
				evt.Add{"Experience", Value = 5000}
			elseif i == 3 then
			else
				evt.Set{"Dead", Value = 0}
			end
		elseif j == 2 then
			i = Game.Rand() % 3
			if i == 1 then
				evt.Add{"AirResBonus", Value = 50}
			elseif i == 2 then
				evt.Add{"FireResBonus", Value = 50}
			else
				evt.Set{"Stoned", Value = 0}
			end
		else
			i = Game.Rand() % 3
			if i == 1 then
				Party.AddGold(10000, 1)
			elseif i == 2 then
				evt.Add{"SkillPoints", Value = 10}
			else
				evt.Subtract{"ArmorClassBonus", Value = 50}
			end
		end
		evt.StatusText(65)	-- You make a wish
	end
end

function events.AfterLoadMap()
	if evt.CheckSeason{Season = 3} then
		Map.Tilesets[0].Group = 1
		Map.LoadTileset(1)
	else
		Map.Tilesets[0].Group = 8
		Map.LoadTileset(8)
	end
end

MF.LogInit2(LogId)