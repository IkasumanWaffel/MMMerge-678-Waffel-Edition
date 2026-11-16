-- Celeste

function events.AfterLoadMap()
	Party.QBits[722] = true	-- TP Buff Celeste
	if Party.QBits[612] then
		evt.SetMonGroupBit{57, const.MonsterBits.Hostile, true}
		evt.SetMonGroupBit{56, const.MonsterBits.Hostile, true}
		evt.SetMonGroupBit{55, const.MonsterBits.Hostile, true}
	end
end

-- Webstation Supply: one of the hostels opens it once Resurectra has the Command Cube (MMMWE_GateStory.lua)
Merge.Functions.AncientShopDoor(Merge.Functions.GateStory, Merge.Functions.GateStory.CUBE_DONE)
