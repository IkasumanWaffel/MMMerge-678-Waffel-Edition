-- MMMWE: Dodging and Unarmed teachers in Enroth (MM6) and Jadame (MM8)
--
-- Antagarich has its own (NPCData.txt, topics 396-401). In the other two continents some house
-- NPCs who had nothing to teach before (no topics, or only a hint) take the topics, chosen by
-- their portraits and professions. The teacher topics are the game's (Teacher topics.txt):
--   396 Expert Dodging   397 Master Dodging   398 Grand Master Dodging
--   399 Expert Unarmed   400 Master Unarmed   401 Grand Master Unarmed

local TEACHERS = {
	-- Jadame: Expert in Ravenshore, Master in Garrote Gorge, Grand Master in Shadowspire
	{NPC = 229,  Topic = 396, Slot = 1},   -- Poundlin Deerhunter, Deerhunter's House, Ravenshore
	{NPC = 247,  Topic = 399, Slot = 1},   -- Ethan Hillsman, Hillsman Cottage, Ravenshore
	{NPC = 232,  Topic = 397, Slot = 1},   -- Weldrik Falconeye, Weldrick's Home, Garrote Gorge
	{NPC = 230,  Topic = 400, Slot = 1},   -- Isram Delver, Morningstar Residence, Garrote Gorge
	{NPC = 236,  Topic = 398, Slot = 1},   -- Ashen Fiddlebone, House Fiddlebone, Shadowspire
	{NPC = 237,  Topic = 401, Slot = 1},   -- Sethrik Fist, Fist Residence, Shadowspire

	-- Enroth: Expert in Free Haven and Silver Cove, Master and Grand Master Dodging in
	-- Kriegspire, Grand Master Unarmed in Dragonsand
	{NPC = 1060, Topic = 396, Slot = 0},   -- Nikobi (scout), Free Haven
	{NPC = 1041, Topic = 399, Slot = 0},   -- Nigan (arms master), Silver Cove
	{NPC = 1007, Topic = 397, Slot = 0},   -- Eunbo Kim (counselor), Kriegspire
	{NPC = 1105, Topic = 400, Slot = 0},   -- Vance Cornelius (teacher), Kriegspire
	{NPC = 1009, Topic = 398, Slot = 0},   -- Sila Daewon (instructor), Kriegspire
	{NPC = 1161, Topic = 401, Slot = 0},   -- Ian Trom (locksmith), Dragonsand
}

-- their autonotes (Teacher autonotes.txt links topic, NPC and note): ids that are empty in
-- Autonote.txt, given texts here, in the "teacher" category of the game's teacher notes
local NOTES = {
	[110] = "You may receive Expert Dodging instruction from Poundlin Deerhunter in the city of Ravenshore.",
	[303] = "You may receive Expert Unarmed instruction from Ethan Hillsman in the city of Ravenshore.",
	[112] = "Master Dodging is taught by Weldrik Falconeye, who lives in Garrote Gorge.",
	[305] = "Master Unarmed is taught by Isram Delver, who lives in Garrote Gorge.",
	[301] = "The Grandmaster of the Dodging Skill, Ashen Fiddlebone, can be found in Shadowspire.",
	[308] = "The Grandmaster of Unarmed Combat, Sethrik Fist, can be found in Shadowspire.",
	[111] = "You may receive Expert Dodging instruction from Nikobi in the town of Free Haven.",
	[304] = "You may receive Expert Unarmed instruction from Nigan in the town of Silver Cove.",
	[300] = "Master Dodging is taught by Eunbo Kim in the town of Kriegspire.",
	[306] = "Master Unarmed is taught by Vance Cornelius in the town of Kriegspire.",
	[302] = "The Grandmaster of the Dodging Skill, Sila Daewon, can be found in the town of Kriegspire.",
	[726] = "The Grandmaster of Unarmed Combat, Ian Trom, can be found in Dragonsand.",
}
local TEACHER_NOTE = 373   -- an existing teacher note, for its category
for id, text in pairs(NOTES) do
	if id <= Game.AutonoteTxt.high then
		Game.AutonoteTxt[id] = text
		Game.AutonoteCategory[id] = Game.AutonoteCategory[TEACHER_NOTE]
	end
end

for _, t in ipairs(TEACHERS) do
	Quest{
		Name = "MMMWE_DodgeUnarmedTeacher_" .. t.NPC,
		NPC = t.NPC,
		Slot = t.Slot,
		StdTopic = t.Topic,
	}
end
