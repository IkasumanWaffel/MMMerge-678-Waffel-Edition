-- MMMWE: teachers of the new skills Dual-Wield, Robe and Enchanting (General\MMMWE_ExtraSkills.lua)
--
-- As the Dodging and Unarmed teachers of MMMWE_DodgingUnarmedTeachers.lua: house NPCs who
-- had nothing to teach before (no topics, or only hints) take the topics, chosen by their
-- professions and homes. On each continent an Expert, a Master and a Grand Master teacher
-- of each skill. The skill itself is learned in houses only (Dual-Wield: training halls and
-- mercenary guilds; Robe: temples and magic guilds).
--
--   Jadame      Dual-Wield: Ravenshore (Expert), Alvar (Master), Regna (Grand Master)
--               Robe:       Ravenshore, Alvar, Shadowspire
--   Antagarich  Dual-Wield: Harmondale, Erathia, Deyja
--               Robe:       Harmondale, the Tularean Forest, the Bracada Desert
--   Enroth      Dual-Wield: Free Haven, Misty Islands, Dragonsand
--               Robe:       New Sorpigal, Bootleg Bay, Dragonsand
--   Enchanting (11.11.26, learned in the guilds of magic):
--               Jadame: Ravenshore, Alvar, Shadowspire; Antagarich: Harmondale, the
--               Tularean Forest, the Bracada Desert; Enroth: New Sorpigal, Free Haven,
--               Castle Ironfist
--
-- Prices and the skill levels needed are those of Sword (Dual-Wield) and Leather (Robe):
-- Expert at 5, Master at 10, Grand Master at 15. The class must allow the rank
-- (MF.ClassSkillCap). Each teacher's autonote is added when the party talks to them.

local MF = Merge.Functions
local Tx, Tn = Merge.Functions.Text, Merge.Functions.TextKey
local EXTRA = MF.ExtraSkills
if not EXTRA then
	return
end

local DW, ROBE = EXTRA.Skills.DualWield, EXTRA.Skills.Robe
local ENCH = EXTRA.Skills.Enchanting

local PRICES = {
	[DW]   = {[2] = 5000, [3] = 10000, [4] = 15000},
	[ROBE] = {[2] = 4000, [3] = 8000,  [4] = 12000},
	[ENCH] = {[2] = 4000, [3] = 8000,  [4] = 12000},
}
local LEARN_WHERE = {
	[DW]   = Tx"Training halls and the mercenary guilds teach it.",
	[ROBE] = Tx"Temples and the guilds of magic teach it.",
	[ENCH] = Tx"The guilds of magic teach it.",
}
local LEVEL = {[2] = 5, [3] = 10, [4] = 15}
local MASTERY_NAME = {Tx"Novice", Tx"Expert", Tx"Master", Tx"Grand Master"}
local RANK_TITLE = {[2] = Tx"Expert", [3] = Tx"Master", [4] = Tx"Grand Master"}

-- Rank: the mastery taught (2 Expert, 3 Master, 4 Grand Master); Slot: a free topic slot
local TEACHERS = {
	-- Jadame
	{NPC = 221,  Skill = DW,   Rank = 2, Slot = 1, Where = Tx"Aznog Black in the city of Ravenshore"},
	{NPC = 234,  Skill = DW,   Rank = 3, Slot = 1, Where = Tx"Brand Featherwind in Alvar"},
	{NPC = 318,  Skill = DW,   Rank = 4, Slot = 1, Where = Tx"Pirate Paul in Regna"},
	{NPC = 218,  Skill = ROBE, Rank = 2, Slot = 1, Where = Tx"Jillian Applebee in the city of Ravenshore"},
	{NPC = 245,  Skill = ROBE, Rank = 3, Slot = 1, Where = Tx"Myles Greydawn in Alvar"},
	{NPC = 319,  Skill = ROBE, Rank = 4, Slot = 1, Where = Tx"Yoel Wargreen in Shadowspire"},
	-- Antagarich
	{NPC = 730,  Skill = DW,   Rank = 2, Slot = 2, Where = Tx"Brahein Kadarr in Harmondale"},
	{NPC = 728,  Skill = DW,   Rank = 3, Slot = 2, Where = Tx"Matthias Bearheart in Steadwick, Erathia"},
	{NPC = 737,  Skill = DW,   Rank = 4, Slot = 2, Where = Tx"Claes Mogren in Deyja"},
	{NPC = 729,  Skill = ROBE, Rank = 2, Slot = 2, Where = Tx"Tanya Kirklynn in Harmondale"},
	{NPC = 764,  Skill = ROBE, Rank = 3, Slot = 2, Where = Tx"Mireille Warlin in the Tularean Forest"},
	{NPC = 760,  Skill = ROBE, Rank = 4, Slot = 2, Where = Tx"Alashandra Reese in the Bracada Desert"},
	-- Enroth
	{NPC = 1050, Skill = DW,   Rank = 2, Slot = 0, Where = Tx"Miriam Boyer in the town of Free Haven"},
	{NPC = 960,  Skill = DW,   Rank = 3, Slot = 0, Where = Tx"Selena Stipe on the Misty Islands"},
	{NPC = 1162, Skill = DW,   Rank = 4, Slot = 0, Where = Tx"Darth Cartwright in Dragonsand"},
	{NPC = 843,  Skill = ROBE, Rank = 2, Slot = 0, Where = Tx"Orville Corvair in New Sorpigal"},
	{NPC = 1047, Skill = ROBE, Rank = 3, Slot = 0, Where = Tx"Svetlanta Irktusk in Bootleg Bay"},
	{NPC = 979,  Skill = ROBE, Rank = 4, Slot = 0, Where = Tx"Jo Handlebaum in Dragonsand"},
	-- (11.11.26) Enchanting
	{NPC = 73,   Skill = ENCH, Rank = 2, Slot = 1, Where = Tx"Lathius in the city of Ravenshore"},
	{NPC = 246,  Skill = ENCH, Rank = 3, Slot = 1, Where = Tx"Xavier Havest in Alvar"},
	{NPC = 101,  Skill = ENCH, Rank = 4, Slot = 2, Where = Tx"Whisper in Shadowspire"},
	{NPC = 484,  Skill = ENCH, Rank = 2, Slot = 2, Where = Tx"Torrent in Harmondale"},
	{NPC = 479,  Skill = ENCH, Rank = 3, Slot = 2, Where = Tx"Sethrik Windsong in the Tularean Forest"},
	{NPC = 497,  Skill = ENCH, Rank = 4, Slot = 2, Where = Tx"Ethan Lightsworn in the Bracada Desert"},
	{NPC = 866,  Skill = ENCH, Rank = 2, Slot = 2, Where = Tx"Isao Magistrus in New Sorpigal"},
	{NPC = 861,  Skill = ENCH, Rank = 3, Slot = 1, Where = Tx"Zoltan Phelps in the town of Free Haven"},
	{NPC = 841,  Skill = ENCH, Rank = 4, Slot = 2, Where = Tx"Leon Lazaru in Castle Ironfist"},
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
	-- the skill itself is learned in houses only (MMMWE_ExtraSkills.lua: training halls and
	-- mercenary guilds for Dual-Wield, temples and magic guilds for Robe)
	if mas == 0 then
		Message(string.format(Tx"You must first learn %s, %s. %s", name, pl.Name, LEARN_WHERE[skill]))
		return
	end
	if mas >= rank then
		Message(string.format(Tx"You already know all I can teach you of %s, %s.", name, pl.Name))
		return
	end
	if mas < rank - 1 then
		Message(string.format(Tx"You must be %s in %s before I can teach you more, %s.",
			rank - 1 == 2 and Tx"an Expert" or Tx"a Master", name, pl.Name))
		return
	end
	if cap < rank then
		if cap <= 0 then
			Message(string.format(Tx"%s is not for one of your calling, %s.", name, pl.Name))
		else
			Message(string.format(Tx"Your calling takes %s no further than %s, %s.", name, MASTERY_NAME[cap], pl.Name))
		end
		return
	end
	if lvl < LEVEL[rank] then
		Message(string.format(Tx"You need %s at %d to become %s %s, %s.", name, LEVEL[rank],
			rank == 4 and Tx"a Grand Master of" or (rank == 3 and Tx"a Master of" or Tx"an Expert in"), name, pl.Name))
		return
	end
	local gold = PRICES[skill][rank]
	if Party.Gold < gold then
		Message(string.format(Tx"%s %s costs %d gold, %s.", RANK_TITLE[rank], name, gold, pl.Name))
		return
	end
	Party.Gold = Party.Gold - gold
	MF.SetExtraSkill(pl, skill, JoinSkill(lvl, rank))
	Message(string.format(Tx"%s is now %s %s.", pl.Name,
		rank == 4 and Tx"a Grand Master of" or (rank == 3 and Tx"a Master of" or Tx"an Expert in"), name))
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
		Game.AutonoteTxt[id] = string.format(Tx"%s %s is taught by %s.", RANK_TITLE[t.Rank], EXTRA.Names[t.Skill], t.Where)
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

-- (08.11.26) the Grand Master teachers of a skill with a Legendary ability (Dual-Wield) teach the
-- Legendary mastery as the other Grand Master teachers do (Global\MMMWE_LegendaryTeachers.lua):
-- "Legendary <skill>" in the same slot, shown while the character is a Grand Master of it
local LEGEND = MF.LegendarySettings
if LEGEND then
	for _, t in ipairs(TEACHERS) do
		if t.Rank == 4 and LEGEND.Passives[t.Skill] then
			NPCTopic{
				Name = string.format("MMMWE_ExtraSkillLegendary_%d_%d", t.NPC, t.Skill),
				NPC = t.NPC,
				Slot = t.Slot,
				Topic = string.format("%s %s", LEGEND.Name, EXTRA.Names[t.Skill]),
				NeverGiven = true,
				NeverDone = true,
				CanShow = function()
					local pl = currentPlayer()
					if not pl then return false end
					local _, mas = SplitSkill(MF.GetExtraSkill(pl, t.Skill))
					return (mas or 0) >= 4
				end,
				Done = function()
					if MF.TeachLegendary then MF.TeachLegendary(t.Skill) end
				end,
			}
		end
	end
end
