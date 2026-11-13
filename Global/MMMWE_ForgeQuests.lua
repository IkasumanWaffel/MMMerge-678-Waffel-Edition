--[[
	MMMWE_ForgeQuests.lua — Kastore's topics after the Dark ending of MM7 (11.11.26)
	The story, its texts, the Signet's guardian and the Outfitter's stock:
	General/MMMWE_ForgeStory.lua.
--]]

local F = Merge.Functions.ForgeStory
local KASTORE = 423

Quest{
	Name = "MMMWE_Forge_Talk",
	NPC = KASTORE,
	Slot = 2,
	CanShow = function() return Party.QBits[F.FORGE_DONE] and Party.QBits[F.DARK_PATH] end,
	Texts = {
		Topic = F.ForgeTopic,
		Ungive = F.ForgeText,
	},
}

Quest{
	Name = "MMMWE_Forge_Signet",
	NPC = KASTORE,
	Slot = 3,
	Quest = F.SIGNET_QUEST,
	QuestItem = F.SIGNET,
	KeepQuestItem = true,
	Exp = 50000,
	CanShow = function() return Party.QBits[F.FORGE_DONE] and Party.QBits[F.DARK_PATH] end,
	Done = function()
		Party.QBits[F.SIGNET_DONE] = true
		Merge.Functions.AncientShopDoorHint(F, F.SIGNET_DONE)
	end,
	Texts = {
		Topic = F.SignetTopic,
		Give = F.SignetGive,
		Undone = F.SignetUndone,
		Done = F.SignetDone,
		After = F.SignetAfter,
	},
}

-- the war for Harmondale (General/MMMWE_SiegeOfHarmondale.lua)
Quest{
	Name = "MMMWE_Forge_War",
	NPC = KASTORE,
	Slot = 5,
	CanShow = function() return vars.MMMWE_Siege and vars.MMMWE_Siege.Announced end,
	Ungive = function()
		local text = Merge.Functions.SiegeTopicText and Merge.Functions.SiegeTopicText()
		if text then Message(text) end
	end,
	Texts = {
		Topic = Merge.Functions.SiegeTexts.Topic,
	},
}
