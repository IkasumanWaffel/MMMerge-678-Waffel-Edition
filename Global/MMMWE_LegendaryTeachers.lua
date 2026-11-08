-- MMMWE: the Grand Master teachers teach the Legendary mastery (General\MMMWE_LegendaryMastery.lua)
--
-- Every NPC with a Grand Master topic (Teacher topics.txt, mastery 3) gets the topic
-- "Legendary <skill>" in the same slot. It shows in place of the Grand Master topic while the
-- selected character is a Grand Master of the skill (who has nothing more to learn there),
-- and the teacher tells what is still missing or makes the skill Legendary.

local MF = Merge.Functions
local LEGEND = MF.LegendarySettings
if not LEGEND then
	return
end

local GM_TOPIC_MASTERY = 3   -- Teacher topics.txt: 1 Expert, 2 Master, 3 Grand Master

local function currentPlayer()
	local i = Party.CurrentPlayer
	if i and i >= 0 and i < Party.Count then
		return Party[i]
	end
end

local function isGM(pl, skill)
	local _, mas = SplitSkill(MF.SkillValue and MF.SkillValue(pl, skill) or pl.Skills[skill])
	return (mas or 0) >= (const.GM or 4)
end

local function teach(skill)
	local pl = currentPlayer()
	if not pl then return end
	local name = MF.LegendarySkillName and MF.LegendarySkillName(skill) or Game.SkillNames[skill]
	if MF.IsLegendary(pl, skill) then
		Message(string.format("%s, you have gone as far in %s as anyone can. There is nothing left for me to teach you.",
			pl.Name, name))
		return
	end
	local bad = MF.LegendaryProblems(pl, skill)
	if #bad > 0 then
		Message(string.format("Beyond Grand Master lies the %s path in %s, %s, but it is not open to you yet: %s.\n\n"
			.. "It asks for the second promotion of your calling, %s at %d and the experience of level %d. "
			.. "And it can be walked in one skill only.",
			LEGEND.Name, name, pl.Name, table.concat(bad, "; "), name, LEGEND.SkillLevel, LEGEND.CharLevel))
		return
	end
	if LEGEND.Gold > 0 then
		if Party.Gold < LEGEND.Gold then
			Message(string.format("The %s path in %s costs %d gold. Come back when you have it.", LEGEND.Name, name, LEGEND.Gold))
			return
		end
		Party.Gold = Party.Gold - LEGEND.Gold
	end
	MF.MakeLegendary(pl, skill)
	local p = LEGEND.Passives[skill]
	Message(string.format("%s is now %s in %s.%s", pl.Name, LEGEND.Name, name,
		p and string.format("\n\n%s: %s.", p.Name, p.Text) or ""))
end

-- (08.11.26) for the teachers of the new skills (MMMWE_ExtraSkillTeachers.lua)
MF.TeachLegendary = teach
MF.IsGMForLegendary = isGM

local function register()
	local topics = Game.TeacherTopics
	if not topics then return false end
	local gmTopic = {}     -- topic id -> skill
	for id, t in pairs(topics) do
		if t.Mas == GM_TOPIC_MASTERY then gmTopic[id] = t.SId end
	end
	local seen = {}
	local function add(npc, slot, skill)
		local key = npc * 8 + slot
		if seen[key] then return end
		seen[key] = true
		NPCTopic{
			Name = string.format("MMMWE_Legendary_%d_%d", npc, slot),
			NPC = npc,
			Slot = slot,
			Topic = string.format("%s %s", LEGEND.Name, Game.SkillNames[skill]),
			NeverGiven = true,
			NeverDone = true,
			CanShow = function()
				local pl = currentPlayer()
				return pl ~= nil and isGM(pl, skill)
			end,
			Done = function() teach(skill) end,
		}
	end
	for npc = 0, Game.NPCDataTxt.high do
		local ev = Game.NPCDataTxt[npc].Events
		for slot = 0, 5 do
			local skill = gmTopic[ev[slot]]
			if skill then add(npc, slot, skill) end
		end
	end
	for _, t in ipairs(MF.ExtraTeachers or {}) do
		local skill = gmTopic[t.Topic]
		if skill then add(t.NPC, t.Slot, skill) end
	end
	return true
end

if not register() then
	function events.GameInitialized2()
		register()
	end
end
