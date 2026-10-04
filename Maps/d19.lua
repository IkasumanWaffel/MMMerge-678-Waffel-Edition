--[[

-- Allow to open inner chambers without Dyson Leland in group, if invisibility is on

Game.MapEvtLines:RemoveEvent(15)
evt.hint[15] = evt.str[2]
evt.map[15] = function()
	if Party.QBits[20] or Party.QBits[19] or evt.IsPlayerInParty(34) then
		evt.SetDoorState{5,0}
	elseif evt.Cmp{evt.VarNum.Invisible} then
		evt.FaceAnimation{Game.CurrentPlayer, 18}
	else
		evt.SetNPCGreeting{45, 107}
		evt.SpeakNPC{45}
	end
end

-- Allow ro destroy Skeleton transformer without Dyson Leland in group

Game.MapEvtLines:RemoveEvent(131)
evt.map[131] = function()
	if Party.QBits[27] -- Skeleton Transformer Destroyed.
		or not Party.QBits[26] -- Quest to destroy Transformer given
		or Map.Vars[19] ~= 15 then
		return
	end

	evt.Add{"QBits", 27}
	evt.ShowMovie{1,0,"skeltrans"}
	evt.SetFacetBit{30, const.FacetBits.Untouchable, true}
	evt.SetFacetBit{30, const.FacetBits.Invisible, true}
end
]]

