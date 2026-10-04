-- Use QBit check instead of Award #3 check upon entering Throne room
-- Award can be erased, depending on party changes (initial player can be dismissed in the merge)
Game.MapEvtLines:RemoveEvent(416)
evt.hint[416] = evt.str[20]
evt.map[416] = function()
	if Party.QBits[647] then
		evt.EnterHouse{216}
	else
		Game.ShowStatusText(evt.Str[19])
		evt.FaceAnimation{math.max(Game.CurrentPlayer, 0), const.FaceAnimation.DoorLocked}
	end
end

function events.ExitNPC(i)
	if i == 398 then -- Dwarf king
		-- Prevent QBit stuck, in case party went to Dwarf king after killing goblins, but before talking to Butler.
		Party.QBits[658] = false -- "Talk to the Dwarves in Stone City in the Barrow Downs to find a way to repair Castle Harmondale."
	end
end
