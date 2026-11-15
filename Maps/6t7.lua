-- Superior Temple of Baa

local MF, MM = Merge.Functions, Merge.ModSettings

Game.MapEvtLines:RemoveEvent(1)
evt.hint[1] = evt.str[1]  -- "Door"
evt.map[1] = function()
	evt.ForPlayer("Current")
	if evt.CheckSkill{const.Skills.Perception, Mastery = const.Novice, Level = 8} then
		evt.SetDoorState{Id = 1, State = 1}
	else
		evt.DamagePlayer{Player = "Current", DamageType = const.Damage.Fire, Damage = 50}
	end
end

Game.MapEvtLines:RemoveEvent(75)
evt.hint[75] = evt.str[16]	-- "Almighty Head of Baa."
evt.map[75] = function()
	if not evt.Cmp("MapVar14", 1) then
		evt.StatusText(17)	-- "You're not worthy of Baa!"
		evt.DamagePlayer{Player = "Current", DamageType = const.Damage.Water, Damage = 100}
	else
		if evt.Cmp("PlayerBits", 69) then
			evt.StatusText(19)	-- "Go forth and spread the word of Baa!"
		else
			evt.StatusText(18)	-- "Follow Baa!  +50,000 Experience."
			evt.Add("Experience", 50000)
			evt.Subtract("ReputationIs", 10)	-- (15.11.26) the Antagarich scale (was 500, MM6's)
			evt.Set("PlayerBits", 69)
		end
	end
end

