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

for _, t in ipairs(TEACHERS) do
	Quest{
		Name = "MMMWE_DodgeUnarmedTeacher_" .. t.NPC,
		NPC = t.NPC,
		Slot = t.Slot,
		StdTopic = t.Topic,
	}
end
