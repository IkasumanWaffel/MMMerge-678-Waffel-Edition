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
	CanShow = function() return Party.QBits[F.FORGE_DONE] end,
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
	CanShow = function() return Party.QBits[F.FORGE_DONE] end,
	Done = function()
		Party.QBits[F.SIGNET_DONE] = true
	end,
	Texts = {
		Topic = F.SignetTopic,
		Give = F.SignetGive,
		Undone = F.SignetUndone,
		Done = F.SignetDone,
		After = F.SignetAfter,
	},
}

Quest{
	Name = "MMMWE_Forge_Outfitter",
	NPC = KASTORE,
	Slot = 5,
	CanShow = function() return Party.QBits[F.SIGNET_DONE] end,
	Ungive = function()
		ReloadHouse(F.OUTFITTER)
	end,
	Texts = {
		Topic = F.OutfitterTopic,
	},
}
