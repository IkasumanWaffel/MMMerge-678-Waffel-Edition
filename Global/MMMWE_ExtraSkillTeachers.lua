-- MMMWE: teachers of the new skills (General\MMMWE_ExtraSkills.lua)
--
-- The teachers of Sword teach Dual-Wield and the teachers of Leather teach Robe, each up to
-- the rank they teach their own skill at (an Expert Sword teacher: Novice and Expert
-- Dual-Wield; a Grand Master: all ranks). The topic ("Dual-Wield", "Robe") takes a free slot
-- of the teacher and shows while the selected character has something to learn there.
-- Price and the skill level needed: the teacher's own topic's (Teacher topics.txt); Novice
-- costs EXTRA_TEACH.NoviceGold. The class must allow the rank (MF.ClassSkillCap).

local MF = Merge.Functions
local EXTRA = MF.ExtraSkills
if not EXTRA then
	return
end

local TEACH = {
	-- new skill <- the skill whose teachers teach it
	[EXTRA.Skills.DualWield] = const.Skills.Sword,
	[EXTRA.Skills.Robe]      = const.Skills.Leather,
}
local NOVICE_GOLD = 500
local DEF_LEVEL = {[2] = 4, [3] = 7, [4] = 10}          -- skill level needed for E, M, GM
local DEF_GOLD  = {[2] = 2000, [3] = 5000, [4] = 10000}
local MASTERY_NAME = {"Novice", "Expert", "Master", "Grand Master"}

local function currentPlayer()
	local i = Party.CurrentPlayer
	if i and i >= 0 and i < Party.Count then return Party[i] end
end

-- what pl can learn of skill at a teacher of rank (Teacher topics.txt Mas: 1 E, 2 M, 3 GM)
local function nextRank(pl, skill, rank)
	local lvl, mas = SplitSkill(MF.GetExtraSkill(pl, skill))
	mas = mas or 0
	local target = mas + 1
	if mas == 0 then target = 1 end
	if target > rank + 1 then return end
	return target, lvl or 0
end

local function teach(skill, rank, topic)
	local pl = currentPlayer()
	if not pl then return end
	local name = EXTRA.Names[skill]
	local target, lvl = nextRank(pl, skill, rank)
	if not target then
		Message(string.format("I have taught you all I know of %s, %s.", name, pl.Name))
		return
	end
	local cap = MF.ClassSkillCap(pl.Class, skill)
	if cap < target then
		if cap == 0 then
			Message(string.format("%s is not for one of your calling, %s.", name, pl.Name))
		else
			Message(string.format("Your calling takes %s no further than %s, %s.", name, MASTERY_NAME[cap], pl.Name))
		end
		return
	end
	local gold, need
	if target == 1 then
		gold, need = NOVICE_GOLD, 0
	else
		-- the teacher's own topic's price and level when it is of this rank
		local own = topic and topic.Mas + 1 == target
		gold = own and topic.Gold or DEF_GOLD[target]
		need = own and topic.Skill or DEF_LEVEL[target]
	end
	if lvl < need then
		Message(string.format("You need %s at %d to become %s %s, %s.", name, need,
			target == 4 and "a Grand Master of" or (target == 3 and "a Master of" or "an Expert in"), name, pl.Name))
		return
	end
	if Party.Gold < gold then
		Message(string.format("%s %s costs %d gold.", MASTERY_NAME[target], name, gold))
		return
	end
	Party.Gold = Party.Gold - gold
	MF.SetExtraSkill(pl, skill, JoinSkill(math.max(lvl, 1), target))
	if target == 1 then
		Message(string.format("%s has learned %s.", pl.Name, name))
	else
		Message(string.format("%s is now %s %s.", pl.Name,
			target == 4 and "a Grand Master of" or (target == 3 and "a Master of" or "an Expert in"), name))
	end
end

local function register()
	local topics = Game.TeacherTopics
	if not topics then return false end
	-- teacher topic id -> {skill, Mas}
	local byTopic = {}
	for id, t in pairs(topics) do
		for newSkill, base in pairs(TEACH) do
			if t.SId == base then byTopic[id] = {Skill = newSkill, Mas = t.Mas, Topic = t} end
		end
	end
	for npc = 0, Game.NPCDataTxt.high do
		local ev = Game.NPCDataTxt[npc].Events
		local ranks = {}
		for slot = 0, 5 do
			local b = byTopic[ev[slot]]
			if b and (not ranks[b.Skill] or b.Mas > ranks[b.Skill].Mas) then ranks[b.Skill] = b end
		end
		local taken = {}
		for newSkill, b in pairs(ranks) do
			local free
			for slot = 5, 0, -1 do
				if ev[slot] == 0 and not taken[slot] then free = slot break end
			end
			if free then
				taken[free] = true
				NPCTopic{
					Name = string.format("MMMWE_ExtraSkill_%d_%d", npc, newSkill),
					NPC = npc,
					Slot = free,
					Topic = EXTRA.Names[newSkill],
					NeverGiven = true,
					NeverDone = true,
					CanShow = function()
						local pl = currentPlayer()
						return pl ~= nil and nextRank(pl, newSkill, b.Mas) ~= nil
					end,
					Done = function() teach(newSkill, b.Mas, b.Topic) end,
				}
			end
		end
	end
	return true
end

if not register() then
	function events.GameInitialized2()
		register()
	end
end
