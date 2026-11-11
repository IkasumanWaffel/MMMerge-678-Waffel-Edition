-- The Pit

function events.AfterLoadMap()
	Party.QBits[723] = true	-- TP Buff The Pit
	
	-- after the Dark ending: the music in MMMWE_Music.lua (Music.QuestMusic), the Forge garrison
	-- (Blaster Guys and Droids on the party's side) in MMMWE_ForgeGarrison.lua
end

-- the Forge Outfitter: one of the hostels opens it once Kastore has the Signet (MMMWE_ForgeStory.lua)
Merge.Functions.AncientShopDoor(Merge.Functions.ForgeStory, Merge.Functions.ForgeStory.SIGNET_DONE)
