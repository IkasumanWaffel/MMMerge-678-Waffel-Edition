-- MMMWE: teachers of the new skills Dual-Wield and Robe (General\MMMWE_ExtraSkills.lua)
--
-- As the Dodging and Unarmed teachers of MMMWE_DodgingUnarmedTeachers.lua: house NPCs who
-- had nothing to teach before (no topics, or only hints) take the topics, chosen by their
-- professions and homes. On each continent an Expert, a Master and a Grand Master teacher
-- of each skill; the Expert teacher also teaches the skill itself (Novice).
--
--   Jadame      Dual-Wield: Ravenshore (Expert), Alvar (Master), Regna (Grand Master)
--               Robe:       Ravenshore, Alvar, Shadowspire
--   Antagarich  Dual-Wield: Harmondale, Erathia, Deyja
--               Robe:       Harmondale, the Tularean Forest, the Bracada Desert
--   Enroth      Dual-Wield: Free Haven, Misty Islands, Dragonsand
--               Robe:       New Sorpigal, Bootleg Bay, Dragonsand
--
-- Prices and the skill levels needed are those of Sword (Dual-Wield) and Leather (Robe):
-- Expert at 5, Master at 10, Grand Master at 15. The class must allow the rank
-- (MF.ClassSkillCap). Each teacher's autonote is added when the party talks to them.

local MF = Merge.Functions
local EXTRA = MF.ExtraSkills
if not EXTRA then
	return
end

local DW, ROBE = EXTRA.Skills.DualWield, EXTRA.Skills.Robe

local PRICES = {
	[DW]   = {Novice = 1000, [2] = 5000, [3] = 10000, [4] = 15000},
	[ROBE] = {Novice = 1000, [2] = 4000, [3] = 8000,  [4] = 12000},
}
local LEVEL = {[2] = 5, [3] = 10, [4] = 15}
local MASTERY_NAME = {"Novice", "Expert", "Master", "Grand Master"}
local RANK_TITLE = {[2] = "Expert", [3] = "Master", [4] = "Grand Master"}

-- Rank: the mastery taught (2 Expert, 3 Master, 4 Grand Master); Slot: a free topic slot
local TEACHERS = {
	-- Jadame
	{NPC = 221,  Skill = DW,   Rank = 2, Slot = 1, Where = "Aznog Black in the city of Ravenshore"},
	{NPC = 234,  Skill = DW,   Rank = 3, Slot = 1, Where = "Brand Featherwind in Alvar"},
	{NPC = 318,  Skill = DW,   Rank = 4, Slot = 1, Where = "Pirate Paul in Regna"},
	{NPC = 218,  Skill = ROBE, Rank = 2, Slot = 1, Where = "Jillian Applebee in the city of Ravenshore"},
	{NPC = 245,  Skill = ROBE, Rank = 3, Slot = 1, Where = "Myles Greydawn in Alvar"},
	{NPC = 319,  Skill = ROBE, Rank = 4, Slot = 1, Where = "Yoel Wargreen in Shadowspire"},
	-- Antagarich
	{NPC = 730,  Skill = DW,   Rank = 2, Slot = 2, Where = "Brahein Kadarr in Harmondale"},
	{NPC = 728,  Skill = DW,   Rank = 3, Slot = 2, Where = "Matthias Bearheart in Steadwick, Erathia"},
	{NPC = 737,  Skill = DW,   Rank = 4, Slot = 2, Where = "Claes Mogren in Deyja"},
	{NPC = 729,  Skill = ROBE, Rank = 2, Slot = 2, Where = "Tanya Kirklynn in Harmondale"},
	{NPC = 764,  Skill = ROBE, Rank = 3, Slot = 2, Where = "Mireille Warlin in the Tularean Forest"},
	{NPC = 760,  Skill = ROBE, Rank = 4, Slot = 2, Where = "Alashandra Reese in the Bracada Desert"},
	-- Enroth
	{NPC = 1050, Skill = DW,   Rank = 2, Slot = 0, Where = "Miriam Boyer in the town of Free Haven"},
	{NPC = 960,  Skill = DW,   Rank = 3, Slot = 0, Where = "Selena Stipe on the Misty Islands"},
	{NPC = 1162, Skill = DW,   Rank = 4, Slot = 0, Where = "Darth Cartwright in Dragonsand"},
	{NPC = 843,  Skill = ROBE, Rank = 2, Slot = 0, Where = "Orville Corvair in New Sorpigal"},
	{NPC = 1047, Skill = ROBE, Rank = 3, Slot = 0, Where = "Svetlanta Irktusk in Bootleg Bay"},
	{NPC = 979,  Skill = ROBE, Rank = 4, Slot = 0, Where = "Jo Handlebaum in Dragonsand"},
}
MF.ExtraSkillTeachers = TEACHERS

local function currentPlayer()
	local i = Party.CurrentPlayer
	if i and i >= 0 and i < Party.Count then return Party[i] end
end

local function teach(t)
	local pl = currentPlayer()
	if not pl then return end
	local skill, rank = t.Skill, t.Rank
	local name = EXTRA.Names[skill]
	local lvl, mas = SplitSkill(MF.GetExtraSkill(pl, skill))
	lvl, mas = lvl or 0, mas or 0
	local cap = MF.ClassSkillCap(pl.Class, skill)
	-- the Expert teachers teach the skill itself first
	if mas == 0 then
		if rank ~= 2 then
			Message(string.format("You must first learn %s, %s. An Expert teacher can show you the basics.", name, pl.Name))
			return
		end
		if cap < 1 then
			Message(string.format("%s is not for one of your calling, %s.", name, pl.Name))
			return
		end
		local gold = PRICES[skill].Novice
		if Party.Gold < gold then
			Message(string.format("I can teach you %s for %d gold, %s.", name, gold, pl.Name))
			return
		end
		Party.Gold = Party.Gold - gold
		MF.SetExtraSkill(pl, skill, JoinSkill(1, 1))
		Message(string.format("%s has learned %s.", pl.Name, name))
		return
	end
	if mas >= rank then
		Message(string.format("You already know all I can teach you of %s, %s.", name, pl.Name))
		return
	end
	if mas < rank - 1 then
		Message(string.format("You must be %s in %s before I can teach you more, %s.",
			rank - 1 == 2 and "an Expert" or "a Master", name, pl.Name))
		return
	end
	if cap < rank then
		if cap <= 0 then
			Message(string.format("%s is not for one of your calling, %s.", name, pl.Name))
		else
			Message(string.format("Your calling takes %s no further than %s, %s.", name, MASTERY_NAME[cap], pl.Name))
		end
		return
	end
	if lvl < LEVEL[rank] then
		Message(string.format("You need %s at %d to become %s %s, %s.", name, LEVEL[rank],
			rank == 4 and "a Grand Master of" or (rank == 3 and "a Master of" or "an Expert in"), name, pl.Name))
		return
	end
	local gold = PRICES[skill][rank]
	if Party.Gold < gold then
		Message(string.format("%s %s costs %d gold, %s.", RANK_TITLE[rank], name, gold, pl.Name))
		return
	end
	Party.Gold = Party.Gold - gold
	MF.SetExtraSkill(pl, skill, JoinSkill(lvl, rank))
	Message(string.format("%s is now %s %s.", pl.Name,
		rank == 4 and "a Grand Master of" or (rank == 3 and "a Master of" or "an Expert in"), name))
end

-- the autonotes: the first empty entries of Autonote.txt from the end, one per teacher
-- (the same ones every time, as long as Autonote.txt doesn't change)
local TEACHER_NOTE = 373   -- an existing teacher note, for its category
local function assignNotes()
	local id = Game.AutonoteTxt.high
	for _, t in ipairs(TEACHERS) do
		while id > 0 and (Game.AutonoteTxt[id] or "") ~= "" do id = id - 1 end
		if id <= 0 then return end
		t.Note = id
		Game.AutonoteTxt[id] = string.format("%s %s is taught by %s.", RANK_TITLE[t.Rank], EXTRA.Names[t.Skill], t.Where)
		Game.AutonoteCategory[id] = Game.AutonoteCategory[TEACHER_NOTE]
		id = id - 1
	end
end
assignNotes()

for _, t in ipairs(TEACHERS) do
	NPCTopic{
		Name = string.format("MMMWE_ExtraSkillTeacher_%d_%d", t.NPC, t.Skill),
		NPC = t.NPC,
		Slot = t.Slot,
		Topic = string.format("%s %s", RANK_TITLE[t.Rank], EXTRA.Names[t.Skill]),
		NeverGiven = true,
		NeverDone = true,
		CanShow = function()
			if t.Note and not Party.AutonotesBits[t.Note] then
				Party.AutonotesBits[t.Note] = true
			end
			return true
		end,
		Done = function() teach(t) end,
	}
end
