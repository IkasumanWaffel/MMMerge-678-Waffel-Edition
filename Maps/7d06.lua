
function events.LoadMap()
	for i = 5, 8 do
		evt.SetDoorState(i, 1)
	end
	for i = 9, 10 do
		evt.SetDoorState(i, 0)
	end
end

Game.MapEvtLines:RemoveEvent(51)

evt.map[51] = function()  -- Timer(<function>, 2.5*const.Minute)
	evt.CastSpell{Spell = 39, Mastery = const.Expert, Skill = 10, FromX = -2619, FromY = 7850, FromZ = -95, ToX = -2619, ToY = 4008, ToZ = -95}         -- "Fire Bolt"
	evt.CastSpell{Spell = 39, Mastery = const.Expert, Skill = 10, FromX = -2619, FromY = 4050, FromZ = -95, ToX = -2619, ToY = 7896, ToZ = -95}         -- "Fire Bolt"
end

Timer(evt.map[51].last, 2.5*const.Minute)
