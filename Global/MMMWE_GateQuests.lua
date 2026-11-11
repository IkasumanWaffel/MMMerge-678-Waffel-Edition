--[[
	MMMWE_GateQuests.lua — Resurectra's topics after the Light ending of MM7 (11.11.26)
	The story, its texts, the Cube's guardian and the station's stock:
	General/MMMWE_GateStory.lua (and the engine in General/MMMWE_ForgeStory.lua).
--]]

local G = Merge.Functions.GateStory
local RESURECTRA = 419

local function lightEnd() return Party.QBits[G.GATE_DONE] and Party.QBits[G.LIGHT_PATH] end

Quest{
	Name = "MMMWE_Gate_Talk",
	NPC = RESURECTRA,
	Slot = 2,
	CanShow = lightEnd,
	Texts = {
		Topic = G.GateTopic,
		Ungive = G.GateText,
	},
}

Quest{
	Name = "MMMWE_Gate_Cube",
	NPC = RESURECTRA,
	Slot = 3,
	Quest = G.CUBE_QUEST,
	QuestItem = G.CUBE,
	KeepQuestItem = true,
	Exp = 50000,
	CanShow = lightEnd,
	Done = function()
		Party.QBits[G.CUBE_DONE] = true
		Merge.Functions.AncientShopDoorHint(G, G.CUBE_DONE)
	end,
	Texts = {
		Topic = G.CubeTopic,
		Give = G.CubeGive,
		Undone = G.CubeUndone,
		Done = G.CubeDone,
		After = G.CubeAfter,
	},
}
