--[[
	MMMWE_LegendaryMastery.lua — the fifth mastery, Legendary (07.11.26)

	One skill per character can be raised above Grand Master. The requirements:
	  - the character's class is a second promotion (Game.ClassesExtra[class].Step == 2: the
	    light, dark and neutral second promotions, and the custom classes' last stage),
	  - Grand Master of the skill and its base level at least LEGEND.SkillLevel (20),
	  - character level at least LEGEND.CharLevel (100),
	  - no other Legendary skill.
	The Grand Master teachers of the skill teach it (Global\MMMWE_LegendaryTeachers.lua): the
	topic "Legendary <skill>" shows in place of their Grand Master topic while the selected
	character is a Grand Master of that skill.

	For the game a Legendary skill stays a Grand Master skill: the skill value is not changed
	(no new mastery bit), so nothing of the game's own code or of the Merge's skill tables
	(indexed 1..4) can see a mastery 5. The Legendary skill is kept in the save game,
	vars.MMMWE_Legendary[roster index] = skill id, and holds while the skill is at Grand
	Master. Its passive ability is the scripts' (LEGEND.Passives, the effects in the scripts of
	each skill).

	Shown: the Skills screen writes "<skill> Legend" instead of "<skill> Grand" (the four lists:
	weapons, magic, armor, misc); the skill's popup tells the passive ability after the Grand
	Master line.

	Functions:
	  MF.LegendarySkill(pl)           the skill id or nil
	  MF.IsLegendary(pl, skill)       true when that skill of pl is Legendary
	  MF.LegendaryProblems(pl, skill) a list of the unmet requirements (empty: can learn)
	  MF.MakeLegendary(pl, skill, force)  learn it (force: skip the requirements); returns ok, problems
	  MF.ClearLegendary(pl)           forget it (console, tests)
	  MF.LegendarySettings            the settings below
	Event: events.LegendaryLearned(t) {Player, Skill}
--]]

local MF = Merge.Functions

local LEGEND = {
	Word        = "Legend",    -- in place of "Grand" on the Skills screen
	Name        = "Legendary", -- the mastery's name in texts
	SkillLevel  = 20,          -- the skill's base level needed
	CharLevel   = 100,         -- the character's base level needed
	PromoStep   = 2,           -- Game.ClassesExtra[class].Step: the second promotion
	Gold        = 0,           -- the teachers' price
	-- the passive ability of each Legendary skill: [skill id] = {Name = ..., Text = ...}
	Passives    = {},
}
MF.LegendarySettings = LEGEND

local GM = const.GM or 4

local function store()
	vars.MMMWE_Legendary = vars.MMMWE_Legendary or {}
	return vars.MMMWE_Legendary
end

-- the roster index (Party.PlayersArray) of a character, from its pointer (called often)
local function rosterIndex(pl)
	local arr = Party.PlayersArray
	local p = pl and pl["?ptr"]
	if not p then return end
	local i = (p - arr["?ptr"]) / arr[0]["?size"]
	if i >= 0 and i == math.floor(i) then return i end
end

local function baseSkill(pl, skill)
	local lvl, mas = SplitSkill(pl.Skills[skill])
	return lvl or 0, mas or 0
end

function MF.LegendarySkill(pl)
	local s = vars and vars.MMMWE_Legendary
	if not pl or not s or next(s) == nil then return end
	local i = rosterIndex(pl)
	local skill = i and s[i]
	if skill and select(2, baseSkill(pl, skill)) >= GM then
		return skill
	end
end

function MF.IsLegendary(pl, skill)
	return skill ~= nil and MF.LegendarySkill(pl) == skill
end

local function skillName(skill)
	return Game.SkillNames[skill] or ("skill " .. tostring(skill))
end

function MF.LegendaryProblems(pl, skill)
	local out = {}
	local cur = MF.LegendarySkill(pl)
	if cur and cur ~= skill then
		out[#out + 1] = string.format("already %s in %s, and only one skill can be", LEGEND.Name, skillName(cur))
	end
	local ce = Game.ClassesExtra and Game.ClassesExtra[pl.Class]
	if not ce or (ce.Step or 0) < LEGEND.PromoStep then
		out[#out + 1] = "not of a second promotion class"
	end
	local lvl, mas = baseSkill(pl, skill)
	if mas < GM then
		out[#out + 1] = "not a Grand Master of " .. skillName(skill)
	elseif lvl < LEGEND.SkillLevel then
		out[#out + 1] = string.format("%s at %d of %d", skillName(skill), lvl, LEGEND.SkillLevel)
	end
	if (pl.LevelBase or 0) < LEGEND.CharLevel then
		out[#out + 1] = string.format("level %d of %d", pl.LevelBase or 0, LEGEND.CharLevel)
	end
	return out
end

function MF.MakeLegendary(pl, skill, force)
	local bad = MF.LegendaryProblems(pl, skill)
	if #bad > 0 and not force then return false, bad end
	local i = rosterIndex(pl)
	if not i then return false, {"no roster index"} end
	store()[i] = skill
	events.call("LegendaryLearned", {Player = pl, Skill = skill})
	return true, bad
end

function MF.ClearLegendary(pl)
	local i = rosterIndex(pl)
	if i then store()[i] = nil end
end

-- the Skills screen: the four lists write "<name> <mastery>" into 0x5DF0E0 before drawing the
-- line; the player is [ebp-0x48], the skill [ebp-0x20] (as the Merge's patches there use them)
local LINE_BUF = 0x5DF0E0
local function skillLine(d)
	local p, skill = mem.u4[d.ebp - 0x48], mem.i4[d.ebp - 0x20]
	if p == 0 or skill < 0 or skill > Game.SkillNames.high then return end
	local ok, pl = pcall(function()
		local idx = (p - Party.PlayersArray["?ptr"]) / Party.PlayersArray[0]["?size"]
		return Party.PlayersArray[idx]
	end)
	if not ok or not pl or not MF.IsLegendary(pl, skill) then return end
	local s = skillName(skill) .. " " .. LEGEND.Word
	mem.copy(LINE_BUF, s .. "\0", #s + 1)
end
for _, p in ipairs{0x418E5F, 0x41920C, 0x4195AC, 0x41994F} do
	mem.autohook(p, skillLine)
end

-- the skill popup: the passive ability after the Grand Master line
local baseGM = {}
local function describe()
	for skill = 0, Game.SkillNames.high do
		local p = LEGEND.Passives[skill]
		if p then
			baseGM[skill] = baseGM[skill] or Game.SkillDesGM[skill] or ""
			Game.SkillDesGM[skill] = string.format("%s\n%s (one skill; second promotion, skill %d, level %d): %s. %s",
				baseGM[skill], LEGEND.Name, LEGEND.SkillLevel, LEGEND.CharLevel, p.Name, p.Text)
		end
	end
end
MF.LegendaryDescribe = describe

function events.GameInitialized2()
	describe()
end

-- console: who is Legendary in what
function MF.LegendaryInfo()
	local lines = {}
	for i = 0, Party.Count - 1 do
		local pl = Party[i]
		local skill = MF.LegendarySkill(pl)
		lines[#lines + 1] = string.format("%s: %s", pl.Name, skill and (LEGEND.Name .. " " .. skillName(skill)) or "none")
	end
	local s = table.concat(lines, "\n")
	print(s)
	return s
end
