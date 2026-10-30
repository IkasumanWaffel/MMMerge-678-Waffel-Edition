--[[
	MMMWE_CustomClasses.lua — custom classes, stage 1: the data layer

	Design: "Waffel Edition design: custom classes" (Google Doc).

	The player builds a class with a budget of points: HP and SP tiers and the mastery cap
	of every skill. A custom class "family" has five steps:
	  1 base class, 2 first promotion, 3 second promotion (neutral), 4 light, 5 dark
	Up to 8 families per game. They use the class ids 130..169 (family f: 125 + 5f + step)
	and the class family Kind 17..24 in Game.ClassesExtra.

	The ids are made in memory, so no LOD or table file has to change:
	  class.txt (names, descriptions)   extended when the game loads it (RemoveClassLimits.lua
	                                    calls MF.ExtendClassTxt)
	  Class Skills / Class HP SP /      placeholder columns or rows added to the text before
	  Class Starting Skills             it is read, so the game arrays grow
	The builds are kept in vars.CustomClasses (saved with the game) and applied before every
	map load and after every change: names, skill caps, HP/SP, Class Extra, promotions and
	SpellsLearning. An unused family is a placeholder (Kind 0, no skills).

	Console (stage 1, until the creation screen exists):
	  CustomClass.New(name)                     new family, returns its number
	  CustomClass.Name(f, step, name)
	  CustomClass.HP(f, step, tier)             tier 0..5 (6 first promotion, 7 second)
	  CustomClass.SP(f, step, tier, stats)      stats "I", "P" or "IP"
	  CustomClass.Skill(f, step, skill, cap)    cap 0..4 or "-", "N"/"B", "E", "M", "G"
	  CustomClass.Export(f)                     writes the build to CustomClasses/<name>.txt
	  CustomClass.Import(file [, f])            reads a build from CustomClasses (new class, or into f)
	  CustomClass.Spell(f, step, spell [, false]) picks (or drops) a spell, 1..99
	  CustomClass.Kit(f, kit)                   resource kit: "Monk", "Barbarian", "Knight", "Thief",
	                                            "Archer", "Ranger", "Paladin", "DarkElf", "Minotaur",
	                                            "Technician", or nil / "none"
	  CustomClass.Show(f), CustomClass.List()
	  CustomClass.Give(player, f, step)         player: party slot 0..4 (default: selected);
	                                            skills the class can't learn are removed and
	                                            skills above its caps lowered, with the skill
	                                            points spent on them refunded (MF.ConvertCharacter)
	  CustomClass.Delete(f)
	A change on a step is passed on to the later steps that had the same value (and raises
	the ones that had less), so promotions never lose anything.
--]]

local MF, MT = Merge.Functions, Merge.Tables

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local FIRST_ID   = 130     -- first custom class id
local FAMILIES   = 8
local STEPS      = 5       -- base, first promotion, neutral, light, dark
local FIRST_KIND = 17      -- Class Extra Kind of family 1 (Peasant is 16)
local LAST_ID    = FIRST_ID + FAMILIES * STEPS - 1

-- 30.10.26: the preset classes priced with this file's costs (Class Skills caps, HP/SP
-- tiers by the HP/SP at level 25, the spells SpellsLearning gives them, their kit) average
-- 150 / 187 / 222 / 238 / 238 points by step; the budgets follow those averages
local BUDGET   = {150, 185, 220, 240, 240}
local MAX_TIER = {5, 6, 7, 7, 7}
local PARENT   = {nil, 1, 2, 2, 2}
local STEP_OF  = {0, 1, 2, 2, 2}                 -- Class Extra Step
local ALIGN_OF = {5, 5, 5, 0, 10}                -- Class Extra Alignment (const.Alignment)
local STEP_NAMES = {"base", "first promotion", "neutral", "light", "dark"}

-- {base, per level}
local HP_TIERS = {[0] = {20, 3}, {25, 4}, {30, 5}, {35, 6}, {35, 7}, {40, 8}, {40, 9}, {40, 10}}
local SP_TIERS = {[0] = {0, 0}, {5, 1}, {5, 2}, {10, 3}, {15, 3}, {20, 4}, {20, 5}, {25, 5}}

local CAP_COST  = {[0] = 0, 2, 4, 7, 10}         -- total cost of a mastery cap

-- resource kits (stage 4): bought with the base class and kept by its promotions; the price
-- counts on every step. A kit gives the resource (if any) and the abilities of one preset
-- family (MMMWE_Resources.lua). Kind: that family's Class Extra kind. Page: the magic school
-- whose spellbook page holds the abilities (the class can't buy it). Resource kits replace
-- the spell points, so their builds keep the SP tier at 0. Branches: the promotion branch
-- each second-promotion step stands for (light / dark abilities of the family).
-- Breath (Dragons) is never sold.
local KITS = {
	{Key = "Monk",       Name = "Monk",       Kind = 8,  Price = 35, Page = "Water", Resource = "Ki",
		Branches = {[4] = "MasterMonk", [5] = "Ninja"}},
	{Key = "Barbarian",  Name = "Barbarian",  Kind = 12, Price = 30, Page = "Fire",  Resource = "Rage"},
	{Key = "Knight",     Name = "Knight",     Kind = 6,  Price = 25, Page = "Air",   Resource = "Resolve",
		Branches = {[3] = "Champion", [4] = "Templar", [5] = "BlackKnight"}},
	{Key = "Thief",      Name = "Thief",      Kind = 11, Price = 20, Page = "Mind",  Resource = "Energy",
		Branches = {[4] = "Spy", [5] = "Assassin"}},
	{Key = "Archer",     Name = "Archer",     Kind = 1,  Price = 15, Page = "Body",
		Branches = {[4] = "MasterArcher", [5] = "Sniper"}},
	{Key = "Ranger",     Name = "Ranger",     Kind = 10, Price = 15, Page = "Light"},
	{Key = "Paladin",    Name = "Paladin",    Kind = 9,  Price = 15, Page = "Air"},
	{Key = "DarkElf",    Name = "Dark Elf",   Kind = 3,  Price = 15, Page = "Body"},
	{Key = "Minotaur",   Name = "Minotaur",   Kind = 7,  Price = 15, Page = "Fire",  Race = 10},   -- BaseRace Minotaur
	{Key = "Technician", Name = "Technician", Kind = 15, Price = 15, Page = "Earth", Needs = {"Blaster", "Repair"}},
}
-- spells (picked one by one; a spell needs its school's skill): cost by the spell's rank in
-- its school (spots 1-4 Novice, 5-7 Expert, 8-10 Master, 11 Grand Master), a whole school
-- 11.5 points. Picked spells are learned from Novice 1, as with most preset classes.
-- A step without a Spells list (builds made before spells could be picked) has every spell
-- of its schools, free of charge.
local SPELL_COST = {0.5, 1, 1.5, 2}
local SPELL_RANK_NAMES = {"Novice", "Expert", "Master", "Grand Master"}
local MAGIC_SCHOOLS = {"Fire", "Air", "Water", "Earth", "Spirit", "Mind", "Body", "Light", "Dark"}
local function spellRank(spell)
	local i = (spell - 1) % 11
	return i == 10 and 4 or i >= 7 and 3 or i >= 4 and 2 or 1
end
local function spellSchool(spell)       -- skill id of the spell's school
	return const.Skills[MAGIC_SCHOOLS[math.floor((spell - 1) / 11) + 1]]
end
local function spellName(spell)
	local t = Game.SpellsTxt and Game.SpellsTxt[spell]
	return t and t.Name or ("spell " .. spell)
end

local KIT_BY_KEY = {}
for _, k in ipairs(KITS) do KIT_BY_KEY[k.Key] = k end
local SKILL_MUL = {Armsmaster = 1.5, Merchant = 1.5, Light = 1.5, Dark = 1.5,
	Learning = 1.25, Alchemy = 1.25, Blaster = 1.25}
local GROUPS    = {{"Fire", "Air", "Water", "Earth"}, {"Spirit", "Mind", "Body"}}
local GROUP_REST = 0.75                          -- share paid for the other caps of a group
local FORBIDDEN = {DarkElfAbility = true, VampireAbility = true, DragonAbility = true}
local BOTH_STATS_COST = 3

local function tierCost(t)
	return 4 * math.min(t, 5) + 5 * math.max(t - 5, 0)
end

---------------------------------------------------------------------------
-- ids
---------------------------------------------------------------------------

local function classId(f, step)
	return FIRST_ID + (f - 1) * STEPS + (step - 1)
end

local function isCustomClass(id)
	return id ~= nil and id >= FIRST_ID and id <= LAST_ID
end

local function familyOf(id)
	if not isCustomClass(id) then return nil end
	local i = id - FIRST_ID
	return math.floor(i / STEPS) + 1, i % STEPS + 1
end

MF.IsCustomClass = isCustomClass
MF.CustomClassId = classId
MF.CustomClassOf = familyOf

-- table header names (DataTables writers use const.Class to name columns)
local ID_SUFFIX = {"", "Promo", "Neutral", "Light", "Dark"}
for f = 1, FAMILIES do
	for step = 1, STEPS do
		const.Class["Custom" .. f .. ID_SUFFIX[step]] = classId(f, step)
	end
end

local PLACEHOLDER_NAME = "Custom class"
local PLACEHOLDER_DESC = "An unused custom class."

---------------------------------------------------------------------------
-- making room: class.txt and the class tables
---------------------------------------------------------------------------

local CLASS_COUNT = LAST_ID + 1

-- class.txt as the game loaded it: a header line, then "name<TAB>description" lines
-- separated by \r\n. Returns a new buffer with lines for the custom ids.
function MF.ExtendClassTxt(p)
	local ok, res = pcall(function()
		-- rows are read up to the first line without a tab (DataTables.ComputeRowCountInPChar)
		local lines = {}
		for line in (mem.string(p) .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
		local valid = 0
		while lines[valid + 1] and lines[valid + 1]:find("\t") do valid = valid + 1 end
		local rows = valid - 1         -- the header is the first line
		if rows < 1 or rows >= CLASS_COUNT then return p end
		local out = {}
		for i = 1, valid do out[i] = (lines[i]:gsub("\r$", "")) end
		for i = rows, CLASS_COUNT - 1 do
			out[#out + 1] = PLACEHOLDER_NAME .. "\t" .. PLACEHOLDER_DESC
		end
		for i = valid + 1, #lines do
			local l = lines[i]:gsub("\r$", "")
			if l ~= "" then out[#out + 1] = l end
		end
		local s = table.concat(out, "\r\n") .. "\r\n"
		local np = mem.malloc(#s + 1)
		mem.copy(np, s, #s)
		mem.u1[np + #s] = 0
		MF.LogInfo("CustomClasses: class.txt extended from %d to %d classes", rows, CLASS_COUNT)
		return np
	end)
	if ok then return res end
	MF.LogError("CustomClasses: could not extend class.txt: %s", tostring(res))
	return p
end

local function splitLines(str)
	local t = {}
	for line in (str .. "\n"):gmatch("([^\n]*)\n") do t[#t + 1] = line end
	if t[#t] == "" then t[#t] = nil end
	return t
end

local function chomp(line)
	if line:sub(-1) == "\r" then return line:sub(1, -2), "\r" end
	return line, ""
end

-- a table with one column per class (or per class kind): add columns up to `need`
local function addColumns(str, need, header, cell)
	local lines = splitLines(str)
	if not lines[1] then return str end
	local h = chomp(lines[1])
	local have = #h:split("\t") - 1
	if have >= need then return str end
	for i, line in ipairs(lines) do
		local body, cr = chomp(line)
		if body ~= "" then
			local add = {}
			for c = have, need - 1 do
				add[#add + 1] = "\t" .. (i == 1 and header(c) or cell)
			end
			lines[i] = body .. table.concat(add) .. cr
		end
	end
	return table.concat(lines, "\n") .. "\n"
end

-- Class HP SP: one row per class after the header
local function addHPSPRows(str)
	local lines = splitLines(str)
	local rows, last = 0, 1
	for i = 2, #lines do
		local body = chomp(lines[i])
		if #body:split("\t") >= 6 then rows, last = rows + 1, i else break end
	end
	if rows >= CLASS_COUNT then return str end
	local add = {}
	for c = rows, CLASS_COUNT - 1 do
		add[#add + 1] = string.format("Custom%d\t%d\t%d\t%d\t%d\t-\r", c, HP_TIERS[0][1], HP_TIERS[0][2], 0, 0)
	end
	local out = {}
	for i = 1, last do
		local body = chomp(lines[i])
		out[#out + 1] = body .. "\r"
	end
	for _, l in ipairs(add) do out[#out + 1] = l end
	for i = last + 1, #lines do out[#out + 1] = lines[i] end
	return table.concat(out, "\n") .. "\n"
end

local function headerName(c)
	local f, step = familyOf(c)
	return f and ("Custom" .. f .. ID_SUFFIX[step]) or ("Class" .. c)
end

local SkillsStd, HPSPStd, StartingSkillsStd = DataTables.Skills, DataTables.HPSP, DataTables.StartingSkills

if SkillsStd then
	function DataTables.Skills(str)
		if str then str = addColumns(str, CLASS_COUNT, headerName, "-") end
		return SkillsStd(str)
	end
end

if HPSPStd then
	function DataTables.HPSP(str)
		if str then str = addHPSPRows(str) end
		return HPSPStd(str)
	end
end

if StartingSkillsStd then
	-- one column per class kind (class / 2)
	function DataTables.StartingSkills(str)
		if str then
			str = addColumns(str, math.ceil(CLASS_COUNT / 2), function(c) return "CustomKind" .. c end, "-")
		end
		return StartingSkillsStd(str)
	end
end

---------------------------------------------------------------------------
-- builds
---------------------------------------------------------------------------

local SKILL_IDS = {}       -- skill id -> name, purchasable skills only
for name, id in pairs(const.Skills) do
	if not FORBIDDEN[name] then SKILL_IDS[id] = name end
end

local function skillId(skill)
	if type(skill) == "number" then return SKILL_IDS[skill] and skill end
	local s = tostring(skill):lower():gsub("[%s_]", "")
	for id, name in pairs(SKILL_IDS) do
		if name:lower() == s or name:lower() == s:gsub("magic$", "") then return id end
	end
	if s == "repairitem" then return const.Skills.Repair end
	if s == "disarmtrap" then return const.Skills.DisarmTraps end
end

local CAP_LETTERS = {["-"] = 0, ["0"] = 0, N = 1, B = 1, E = 2, M = 3, G = 4, GM = 4}
local CAP_NAMES = {[0] = "-", "Novice", "Expert", "Master", "Grand Master"}

local function capValue(cap)
	if type(cap) == "number" then return math.max(0, math.min(4, math.floor(cap))) end
	return CAP_LETTERS[tostring(cap):upper()]
end

local STATS_CODE = {I = 1, P = 2, IP = 3, PI = 3}
local STATS_NAME = {[1] = "Intellect", [2] = "Personality", [3] = "Intellect and Personality"}

-- the builds in use: the save's, or the ones made on the party creation screen (Pending,
-- moved into the new game's vars when it starts)
local Pending, Creating, NewGameStarted = {}, false, false

local function builds()
	if Creating then return Pending end
	if not vars then return {} end
	vars.CustomClasses = vars.CustomClasses or {}
	return vars.CustomClasses
end
local store = builds

local function family(f)
	local fam = builds()[f]
	if not fam then error(string.format("no custom class %s", tostring(f)), 3) end
	return fam
end

local function copySpec(s)
	local t = {Name = s.Name, HP = s.HP, SP = s.SP, Stats = s.Stats, Skills = {}}
	for k, v in pairs(s.Skills) do t.Skills[k] = v end
	if s.Spells then
		t.Spells = {}
		for k, v in pairs(s.Spells) do t.Spells[k] = v end
	end
	return t
end

-- point cost of one step's build, and the lines that explain it
local function cost(spec, kitKey)
	local total, lines = 0, {}
	local kit = kitKey and KIT_BY_KEY[kitKey]
	if kit then
		total = total + kit.Price
		lines[#lines + 1] = string.format("%s kit: %g", kit.Name, kit.Price)
	end
	local hp, sp = tierCost(spec.HP), tierCost(spec.SP)
	total = total + hp + sp
	lines[#lines + 1] = string.format("HP tier %d (%d/%d per level): %g", spec.HP, HP_TIERS[spec.HP][1], HP_TIERS[spec.HP][2], hp)
	local stats = spec.Stats == 3 and BOTH_STATS_COST or 0
	lines[#lines + 1] = string.format("SP tier %d (%d/%d per level, %s): %g", spec.SP, SP_TIERS[spec.SP][1], SP_TIERS[spec.SP][2],
		STATS_NAME[spec.Stats] or "?", sp + stats)
	total = total + stats
	local grouped = {}
	for _, g in ipairs(GROUPS) do
		local costs = {}
		for _, name in ipairs(g) do
			local id = const.Skills[name]
			grouped[id] = true
			local m = spec.Skills[id] or 0
			if m > 0 then costs[#costs + 1] = {CAP_COST[m] * (SKILL_MUL[name] or 1), name, m} end
		end
		table.sort(costs, function(a, b) return a[1] > b[1] end)
		for i, c in ipairs(costs) do
			local v = i == 1 and c[1] or c[1] * GROUP_REST
			total = total + v
			lines[#lines + 1] = string.format("%s %s: %g%s", c[2], CAP_NAMES[c[3]], v, i > 1 and " (school discount)" or "")
		end
	end
	local others = {}
	for id, m in pairs(spec.Skills) do
		if m > 0 and not grouped[id] then others[#others + 1] = id end
	end
	table.sort(others)
	for _, id in ipairs(others) do
		local name, m = SKILL_IDS[id], spec.Skills[id]
		local v = CAP_COST[m] * (SKILL_MUL[name] or 1)
		total = total + v
		lines[#lines + 1] = string.format("%s %s: %g", name, CAP_NAMES[m], v)
	end
	if spec.Spells then
		local n, v = 0, 0
		for spell in pairs(spec.Spells) do
			n, v = n + 1, v + SPELL_COST[spellRank(spell)]
		end
		if n > 0 then
			total = total + v
			lines[#lines + 1] = string.format("%d spells: %g", n, v)
		end
	end
	return total, lines
end

-- problems of a step's spells: a spell without its school, a school without spells
local function spellProblems(fam, step)
	local spec, out = fam.Steps[step], {}
	if not spec.Spells then return out end
	local has = {}
	for spell in pairs(spec.Spells) do
		local school = spellSchool(spell)
		has[school] = true
		if (spec.Skills[school] or 0) == 0 then
			out[#out + 1] = string.format("%s needs %s Magic", spellName(spell), MAGIC_SCHOOLS[math.floor((spell - 1) / 11) + 1])
		end
	end
	for i, name in ipairs(MAGIC_SCHOOLS) do
		local school = const.Skills[name]
		if (spec.Skills[school] or 0) > 0 and not has[school] then
			out[#out + 1] = name .. " Magic: no spell picked"
		end
	end
	local p = PARENT[step] and fam.Steps[PARENT[step]]
	if p and p.Spells then
		for spell in pairs(p.Spells) do
			if not spec.Spells[spell] then
				out[#out + 1] = spellName(spell) .. " is lost from the previous step"
				break
			end
		end
	end
	return out
end

-- problems of a step: over budget, tiers too high, less than its parent
local function problems(fam, step)
	local spec, out = fam.Steps[step], {}
	local total = cost(spec, fam.Kit)
	if total > BUDGET[step] then
		out[#out + 1] = string.format("%g points of %d", total, BUDGET[step])
	end
	if spec.HP > MAX_TIER[step] then out[#out + 1] = "HP tier above " .. MAX_TIER[step] end
	if spec.SP > MAX_TIER[step] then out[#out + 1] = "SP tier above " .. MAX_TIER[step] end
	local kit = fam.Kit and KIT_BY_KEY[fam.Kit]
	if kit then
		if (spec.Skills[const.Skills[kit.Page]] or 0) > 0 then
			out[#out + 1] = string.format("the %s kit uses the %s page: no %s Magic", kit.Name, kit.Page, kit.Page)
		end
		if kit.Resource and spec.SP > 0 then
			out[#out + 1] = string.format("%s replaces spell points: SP tier 0", kit.Resource)
		end
		for _, need in ipairs(kit.Needs or {}) do
			if (spec.Skills[const.Skills[need]] or 0) == 0 then
				out[#out + 1] = string.format("the %s kit needs %s", kit.Name, need == "Repair" and "Repair Item" or need)
			end
		end
	end
	local p = PARENT[step] and fam.Steps[PARENT[step]]
	if p then
		if spec.HP < p.HP or spec.SP < p.SP then out[#out + 1] = "lower HP/SP tier than the previous step" end
		if p.Stats == 3 and spec.Stats ~= 3 then out[#out + 1] = "loses the second SP stat" end
		for id, m in pairs(p.Skills) do
			if (spec.Skills[id] or 0) < m then
				out[#out + 1] = SKILL_IDS[id] .. " cap lower than the previous step"
			end
		end
	end
	for _, b in ipairs(spellProblems(fam, step)) do out[#out + 1] = b end
	return out
end

local function children(step)
	if step == 1 then return {2, 3, 4, 5} elseif step == 2 then return {3, 4, 5} end
	return {}
end

---------------------------------------------------------------------------
-- applying the builds to the game data
---------------------------------------------------------------------------

local function describe(fam, step)
	local spec = fam.Steps[step]
	local bySkillCap = {}
	for id, m in pairs(spec.Skills) do
		if m > 0 then
			bySkillCap[m] = bySkillCap[m] or {}
			table.insert(bySkillCap[m], SKILL_IDS[id])
		end
	end
	local parts = {string.format("A custom class. Hit points: tier %d. Spell points: tier %d%s.",
		spec.HP, spec.SP, spec.SP > 0 and (", from " .. (STATS_NAME[spec.Stats] or "?")) or "")}
	local kit = fam.Kit and KIT_BY_KEY[fam.Kit]
	if kit then
		parts[#parts + 1] = string.format("%s kit: %s and the %s abilities (%s page of the spellbook).",
			kit.Name, kit.Resource or "spell points", kit.Name, kit.Page)
	end
	for m = 4, 1, -1 do
		if bySkillCap[m] then
			table.sort(bySkillCap[m])
			parts[#parts + 1] = CAP_NAMES[m] .. ": " .. table.concat(bySkillCap[m], ", ") .. "."
		end
	end
	if spec.Spells then
		local n = 0
		for _ in pairs(spec.Spells) do n = n + 1 end
		parts[#parts + 1] = string.format("Spells: %d.", n)
	end
	return table.concat(parts, " ")
end

-- SpellsLearning entries: every spell of the step's schools (no Spells list: older builds) or
-- the picked ones, from Novice 1
local B1 = {{PlayerLevel = 1, SkillMastery = 1, SkillLevel = 1}}
local function spellsLearning(spec)
	local t = {}
	for spell = 1, 99 do
		if spec.Spells then
			if spec.Spells[spell] then t[spell] = B1 end
		else
			t[spell] = B1
		end
	end
	return t
end

local function setPromotion(src, dest)
	if not MT.ClassPromotions then return end
	MT.ClassPromotions[src] = dest
	if dest then
		for _, d in ipairs(dest) do MT.ClassPromotionsInv[d] = {src} end
	end
end

local function applyClass(id, fam, f, step)
	local spec = fam and fam.Steps[step]
	local skills = Game.Classes.Skills[id]
	for sk = 0, skills.count - 1 do
		skills[sk] = spec and spec.Skills[sk] or 0
	end
	local hp = HP_TIERS[spec and spec.HP or 0]
	local sp = SP_TIERS[spec and spec.SP or 0]
	Game.Classes.HPBase[id], Game.Classes.HPFactor[id] = hp[1], hp[2]
	Game.Classes.SPBase[id], Game.Classes.SPFactor[id] = sp[1], sp[2]
	Game.Classes.SPStats[id] = (spec and spec.SP > 0) and spec.Stats or 0
	Game.ClassNames[id] = spec and spec.Name or PLACEHOLDER_NAME
	Game.ClassDescriptions[id] = spec and describe(fam, step) or PLACEHOLDER_DESC
	local ce = Game.ClassesExtra[id] or {}
	Game.ClassesExtra[id] = ce
	ce.Kind = spec and (FIRST_KIND + f - 1) or 0
	ce.Step = STEP_OF[step]
	ce.Alignment = ALIGN_OF[step]
	if MT.SpellsLearning then
		MT.SpellsLearning[id] = spec and spellsLearning(spec) or nil
	end
end

-- the game's creation screen: the class kind (class / 2) of the base class gives the
-- default skills (2, shown at the top: the two starting skills of the build) and the
-- skills to pick two more from (1: the other skills the base class can learn)
local function applyStartingSkills(f, fam)
	local ss = Game.ClassKinds and Game.ClassKinds.StartingSkills
	local kind = math.floor(classId(f, 1) / 2)
	if not ss or kind >= ss.count then return end
	local row = ss[kind]
	local base = fam and fam.Steps[1]
	local start = {}
	for _, sk in ipairs(fam and fam.StartSkills or {}) do start[sk] = true end
	for sk = 0, row.count - 1 do
		row[sk] = not base and 0 or start[sk] and 2 or ((base.Skills[sk] or 0) > 0 and 1 or 0)
	end
end

local function applyAll()
	if not (Game.Classes and Game.Classes.Skills.count > LAST_ID and Game.ClassNames.count > LAST_ID) then
		MF.LogError("CustomClasses: the class tables have no room for the custom classes (%d / %d)",
			Game.Classes.Skills.count, Game.ClassNames.count)
		return false
	end
	local all = builds()
	for f = 1, FAMILIES do
		local fam = all[f]
		for step = 1, STEPS do
			applyClass(classId(f, step), fam, f, step)
		end
		if MT.ClassPromotions then
			for step = 1, STEPS do setPromotion(classId(f, step), nil) end
			for step = 1, STEPS do MT.ClassPromotionsInv[classId(f, step)] = nil end
			if fam then
				setPromotion(classId(f, 1), {classId(f, 2)})
				setPromotion(classId(f, 2), {classId(f, 3), classId(f, 4), classId(f, 5)})
			end
		end
		applyStartingSkills(f, fam)
	end
	return true
end
MF.ApplyCustomClasses = applyAll

function events.NewGameMap()
	NewGameStarted = true
end

function events.BeforeLoadMap()
	if Creating then
		Creating = false
		if NewGameStarted then
			-- the classes made on the creation screen that party members took
			local keep = {}
			for i = 0, Party.PlayersArray.count - 1 do
				local f = familyOf(Party.PlayersArray[i].Class)
				if f and Pending[f] then keep[f] = Pending[f] end
			end
			vars.CustomClasses = keep
		end
		Pending = {}
	end
	NewGameStarted = false
	applyAll()
end

---------------------------------------------------------------------------
-- console
---------------------------------------------------------------------------

CustomClass = {}

local function playerOf(p)
	if type(p) == "table" then return p end
	p = p or math.max(Game.CurrentPlayer, 0)
	return Party[p]
end

local function checkStep(step)
	step = tonumber(step)
	if not step or step < 1 or step > STEPS then error("step must be 1..5 (base, first promotion, neutral, light, dark)", 3) end
	return step
end

local function changed()
	applyAll()
end

local function newFamily(name)
	local all = store()
	local f
	for i = 1, FAMILIES do
		if not all[i] then f = i break end
	end
	if not f then return nil, "all " .. FAMILIES .. " custom classes are in use" end
	name = name or ("Custom Class " .. f)
	local base = {Name = name, HP = 0, SP = 0, Stats = 1, Skills = {}, Spells = {}}
	local fam = {Steps = {base}}
	local names = {name, name .. " Adept", name .. " Master", "Light " .. name, "Dark " .. name}
	for step = 2, STEPS do
		fam.Steps[step] = copySpec(base)
		fam.Steps[step].Name = names[step]
	end
	fam.StartSkills = {}
	all[f] = fam
	changed()
	return f
end

function CustomClass.New(name)
	local f, err = newFamily(name)
	if not f then error(err, 2) end
	return f
end

-- roster characters (Party.PlayersArray) with a class of family f
local function members(f)
	local t = {}
	for i = 0, Party.PlayersArray.count - 1 do
		local pl = Party.PlayersArray[i]
		if familyOf(pl.Class) == f then t[#t + 1] = pl end
	end
	return t
end

function CustomClass.Delete(f)
	family(f)
	for i = 0, Party.PlayersArray.count - 1 do
		local pl = Party.PlayersArray[i]
		local ff = familyOf(pl.Class)
		if ff == f then
			error(string.format("%s has this class", pl.Name), 2)
		end
	end
	builds()[f] = nil
	changed()
end

function CustomClass.Name(f, step, name)
	local fam = family(f)
	fam.Steps[checkStep(step)].Name = tostring(name)
	changed()
end

-- changes of one step of a build; a change is passed on to the later steps that had the
-- same value (and raises the ones that had less). A promotion step can't go below its
-- previous step. Return nil and the reason when refused.
local function famSetTier(fam, step, field, tier)
	tier = math.floor(tonumber(tier) or -1)
	if tier < 0 or tier > MAX_TIER[step] then
		return nil, string.format("%s tier must be 0..%d for the %s", field, MAX_TIER[step], STEP_NAMES[step])
	end
	local p = PARENT[step] and fam.Steps[PARENT[step]]
	if p and tier < p[field] then
		return nil, string.format("%s tier can't be lower than the previous step's (%d)", field, p[field])
	end
	local old = fam.Steps[step][field]
	fam.Steps[step][field] = tier
	for _, c in ipairs(children(step)) do
		local v = fam.Steps[c][field]
		if v < tier or v == old then fam.Steps[c][field] = tier end
	end
	return true
end

local function famSetStats(fam, step, code)
	local p = PARENT[step] and fam.Steps[PARENT[step]]
	if p and p.Stats == 3 and code ~= 3 then
		return nil, "the previous step already uses both stats"
	end
	local old = fam.Steps[step].Stats
	fam.Steps[step].Stats = code
	for _, c in ipairs(children(step)) do
		if code == 3 or fam.Steps[c].Stats == old then fam.Steps[c].Stats = code end
	end
	return true
end

local function famSetSkill(fam, step, id, m)
	if not SKILL_IDS[id] then return nil, "this skill can't be bought" end
	m = math.max(0, math.min(4, m))
	local p = PARENT[step] and fam.Steps[PARENT[step]]
	if p and m < (p.Skills[id] or 0) then
		return nil, string.format("%s can't be lower than the previous step's %s", SKILL_IDS[id], CAP_NAMES[p.Skills[id]])
	end
	local old = fam.Steps[step].Skills[id] or 0
	fam.Steps[step].Skills[id] = m > 0 and m or nil
	for _, c in ipairs(children(step)) do
		local v = fam.Steps[c].Skills[id] or 0
		if v < m or v == old then fam.Steps[c].Skills[id] = m > 0 and m or nil end
	end
	-- a starting skill must stay learnable
	if step == 1 and m == 0 and fam.StartSkills then
		for i = #fam.StartSkills, 1, -1 do
			if fam.StartSkills[i] == id then table.remove(fam.StartSkills, i) end
		end
	end
	-- a school given up takes its spells with it
	if id >= const.Skills.Fire and id <= const.Skills.Dark then
		for _, st in ipairs({step, unpack(children(step))}) do
			local spec = fam.Steps[st]
			if spec.Spells and (spec.Skills[id] or 0) == 0 then
				for spell in pairs(spec.Spells) do
					if spellSchool(spell) == id then spec.Spells[spell] = nil end
				end
			end
		end
	end
	return true
end

-- builds made before spells could be picked have no Spells lists (every spell of their
-- schools); the first spell change turns that into explicit lists
local function materializeSpells(fam)
	for st = 1, STEPS do
		local spec = fam.Steps[st]
		if not spec.Spells then
			spec.Spells = {}
			for spell = 1, 99 do
				if (spec.Skills[spellSchool(spell)] or 0) > 0 then spec.Spells[spell] = true end
			end
		end
	end
end

-- picks (on = true) or drops a spell on a step; passed on to the later steps (a drop only to
-- the ones that had it). A promotion step can't drop a spell of its previous step.
local function famSetSpell(fam, step, spell, on)
	spell = tonumber(spell)
	if not spell or spell < 1 or spell > 99 then return nil, "no such spell" end
	local spec = fam.Steps[step]
	local school = spellSchool(spell)
	if on and (spec.Skills[school] or 0) == 0 then
		return nil, string.format("%s needs %s Magic", spellName(spell), MAGIC_SCHOOLS[math.floor((spell - 1) / 11) + 1])
	end
	local p = PARENT[step] and fam.Steps[PARENT[step]]
	if not on and p and (not p.Spells or p.Spells[spell]) and (p.Skills[school] or 0) > 0 then
		return nil, spellName(spell) .. " is a spell of the previous step"
	end
	materializeSpells(fam)
	spec.Spells[spell] = on or nil
	for _, c in ipairs(children(step)) do
		if on then
			fam.Steps[c].Spells[spell] = true
		else
			fam.Steps[c].Spells[spell] = nil
		end
	end
	return true
end

local function try(ok, err)
	if not ok then error(err, 3) end
end

function CustomClass.HP(f, step, tier)
	try(famSetTier(family(f), checkStep(step), "HP", tier))
	changed()
end

function CustomClass.SP(f, step, tier, stats)
	local fam = family(f)
	step = checkStep(step)
	try(famSetTier(fam, step, "SP", tier))
	if stats then
		local code = STATS_CODE[tostring(stats):upper()]
		if not code then error('stats must be "I", "P" or "IP"', 2) end
		try(famSetStats(fam, step, code))
	end
	changed()
end

function CustomClass.Skill(f, step, skill, cap)
	local fam = family(f)
	step = checkStep(step)
	local id = skillId(skill)
	if not id then error("unknown or unavailable skill: " .. tostring(skill), 2) end
	local m = capValue(cap)
	if not m then error('cap must be 0..4 or "-", "N", "E", "M", "G"', 2) end
	try(famSetSkill(fam, step, id, m))
	changed()
end

-- CustomClass.Spell(f, step, spell, on): picks (on true or nil) or drops (false) a spell
function CustomClass.Spell(f, step, spell, on)
	try(famSetSpell(family(f), checkStep(step), spell, on ~= false))
	changed()
end

function CustomClass.Show(f)
	local fam = family(f)
	local out = {}
	for step = 1, STEPS do
		local spec = fam.Steps[step]
		local total, lines = cost(spec, fam.Kit)
		local bad = problems(fam, step)
		out[#out + 1] = string.format("%d. %s (%s, class %d): %g / %d points%s", step, spec.Name, STEP_NAMES[step],
			classId(f, step), total, BUDGET[step], #bad > 0 and ("  !! " .. table.concat(bad, "; ")) or "")
		for _, l in ipairs(lines) do out[#out + 1] = "     " .. l end
	end
	local s = table.concat(out, "\n")
	print(s)
	return s
end

function CustomClass.List()
	local out = {}
	local all = builds()
	for f = 1, FAMILIES do
		local fam = all[f]
		if fam then
			local users = {}
			for i = 0, Party.PlayersArray.count - 1 do
				local pl = Party.PlayersArray[i]
				if familyOf(pl.Class) == f and pl.Name ~= "" then users[#users + 1] = pl.Name end
			end
			out[#out + 1] = string.format("%d: %s (%g points)%s", f, fam.Steps[1].Name, (cost(fam.Steps[1], fam.Kit)),
				#users > 0 and (" - " .. table.concat(users, ", ")) or "")
		end
	end
	local s = #out > 0 and table.concat(out, "\n") or "no custom classes"
	print(s)
	return s
end

function CustomClass.Give(player, f, step)
	local fam = family(f)
	step = checkStep(step or 1)
	for s = 1, step do
		if s == 1 or s == 2 or s == step then
			local bad = problems(fam, s)
			if #bad > 0 then
				error(string.format("step %d is not valid: %s", s, table.concat(bad, "; ")), 2)
			end
		end
	end
	local pl = playerOf(player)
	if not pl then error("no such party member", 2) end
	local okKit, kitErr = MF.CustomClassKitAllowed(pl, fam.Kit)
	if not okKit then error(kitErr, 2) end
	applyAll()
	local id = classId(f, step)
	if pl.Class == id then
		return string.format("%s already is a %s", pl.Name, fam.Steps[step].Name)
	end
	-- the Merge's class conversion: skills the new class can't learn are removed and
	-- skills above its caps are lowered; the skill points spent raising them come back
	local before = pl.SkillPoints
	if MF.ConvertCharacter and pl.Attrs then
		MF.ConvertCharacter({Player = pl, ToClass = id})
	end
	pl.Class = id
	local refund = pl.SkillPoints - before
	return string.format("%s is now a %s%s", pl.Name, fam.Steps[step].Name,
		refund > 0 and string.format(" (%d skill points refunded)", refund) or "")
end

-- promotes a party member of a custom class to 'step' of the same family (stage 3, ruler NPCs).
-- Returns the refunded skill points, or nil and the reason.
local function promote(pl, step)
	local f = familyOf(pl.Class)
	if not f then return nil, "not a custom class" end
	local fam = builds()[f]
	if not fam or not fam.Steps[step] then return nil, "the class has no build" end
	local bad = problems(fam, step)
	if #bad > 0 then return nil, table.concat(bad, "; ") end
	applyAll()
	local id = classId(f, step)
	local before = pl.SkillPoints
	if MF.ConvertCharacter and pl.Attrs then
		MF.ConvertCharacter({Player = pl, ToClass = id})
	end
	pl.Class = id
	return pl.SkillPoints - before
end

-- the kit of a custom class: nil for other classes, false for a custom class without a kit,
-- else {Kind, Race, Branch, Resource, Key, Name} (MMMWE_Resources.lua)
function MF.CustomClassKit(class)
	local f, step = familyOf(class)
	if not f then return nil end
	local fam = builds()[f]
	local kit = fam and fam.Kit and KIT_BY_KEY[fam.Kit]
	if not kit then return false end
	return {Kind = kit.Kind, Race = kit.Race, Branch = kit.Branches and kit.Branches[step],
		Resource = kit.Resource, Key = kit.Key, Name = kit.Name}
end

-- can this character take a class with this kit (the Minotaur kit is for Minotaurs only)?
local function kitAllowed(pl, key)
	local kit = key and KIT_BY_KEY[key]
	if not (kit and kit.Race) then return true end
	local r = GetCharRace and GetCharRace(pl)
	local race = r and Game.Races and Game.Races[r]
	if race and race.BaseRace == kit.Race then return true end
	return false, string.format("the %s kit is for %ss only", kit.Name, kit.Name)
end
MF.CustomClassKitAllowed = kitAllowed

local function famSetKit(fam, key)
	if key ~= nil and not KIT_BY_KEY[key] then return nil, "unknown kit: " .. tostring(key) end
	fam.Kit = key
	return true
end

function CustomClass.Kit(f, key)
	local fam = family(f)
	if key == "" or key == "none" then key = nil end
	try(famSetKit(fam, key))
	changed()
end

---------------------------------------------------------------------------
-- export and import of builds: text files in the CustomClasses folder of the game
---------------------------------------------------------------------------

local EXPORT_DIR = "CustomClasses"
local CAP_LETTER = {[1] = "N", [2] = "E", [3] = "M", [4] = "G"}

local function exportText(fam)
	local out = {"-- MMMWE custom class build (MMMWE_CustomClasses.lua). Caps: N, E, M, G.",
		"-- Steps: base, first promotion, neutral, light, dark. Stats: 1 Intellect, 2 Personality, 3 both.",
		"-- Spells: spell numbers 1..99 (11 per school from Fire to Dark).",
		"return {"}
	out[#out + 1] = fam.Kit and string.format("\tKit = %q,", fam.Kit) or "\tKit = nil,"
	local ss = {}
	for _, id in ipairs(fam.StartSkills or {}) do ss[#ss + 1] = string.format("%q", SKILL_IDS[id]) end
	out[#out + 1] = "\tStartSkills = {" .. table.concat(ss, ", ") .. "},"
	out[#out + 1] = "\tSteps = {"
	for step = 1, STEPS do
		local spec = fam.Steps[step]
		local sk = {}
		local ids = {}
		for id, m in pairs(spec.Skills) do if m > 0 then ids[#ids + 1] = id end end
		table.sort(ids)
		for _, id in ipairs(ids) do sk[#sk + 1] = string.format("%s = %q", SKILL_IDS[id], CAP_LETTER[spec.Skills[id]]) end
		out[#out + 1] = string.format("\t\t{Name = %q, HP = %d, SP = %d, Stats = %d,", spec.Name, spec.HP, spec.SP, spec.Stats)
		local sp
		if spec.Spells then
			local ids = {}
			for spell in pairs(spec.Spells) do ids[#ids + 1] = spell end
			table.sort(ids)
			sp = "{" .. table.concat(ids, ", ") .. "}"
		end
		out[#out + 1] = "\t\t\tSkills = {" .. table.concat(sk, ", ") .. "}" ..
			(sp and (",\r\n\t\t\tSpells = " .. sp) or "") .. "},"
	end
	out[#out + 1] = "\t},"
	out[#out + 1] = "}"
	return table.concat(out, "\r\n") .. "\r\n"
end

-- a build from an exported text, checked field by field; nil and the reason when it can't be read
local function importText(text)
	local chunk, err = loadstring(text, "custom class")
	if not chunk then return nil, "not a custom class file (" .. tostring(err) .. ")" end
	setfenv(chunk, {})
	local ok, t = pcall(chunk)
	if not ok or type(t) ~= "table" or type(t.Steps) ~= "table" then return nil, "not a custom class file" end
	local fam = {Steps = {}, StartSkills = {}}
	if t.Kit ~= nil then
		if not KIT_BY_KEY[t.Kit] then return nil, "unknown kit: " .. tostring(t.Kit) end
		fam.Kit = t.Kit
	end
	for step = 1, STEPS do
		local src = t.Steps[step]
		if type(src) ~= "table" then return nil, "step " .. step .. " is missing" end
		local name = tostring(src.Name or ""):gsub("[%c]", ""):sub(1, 24)
		if name == "" then return nil, "step " .. step .. " has no name" end
		local spec = {Name = name, Skills = {},
			HP = math.max(0, math.min(MAX_TIER[step], math.floor(tonumber(src.HP) or 0))),
			SP = math.max(0, math.min(MAX_TIER[step], math.floor(tonumber(src.SP) or 0))),
			Stats = STATS_NAME[tonumber(src.Stats)] and tonumber(src.Stats) or 1}
		for k, v in pairs(type(src.Skills) == "table" and src.Skills or {}) do
			local id, m = skillId(k), capValue(v)
			if not id then return nil, "unknown skill: " .. tostring(k) end
			if not m then return nil, "unknown cap: " .. tostring(v) end
			spec.Skills[id] = m > 0 and m or nil
		end
		if type(src.Spells) == "table" then
			spec.Spells = {}
			for _, v in ipairs(src.Spells) do
				local spell = tonumber(v)
				if not spell or spell < 1 or spell > 99 or spell ~= math.floor(spell) then
					return nil, "unknown spell: " .. tostring(v)
				end
				spec.Spells[spell] = true
			end
		end
		fam.Steps[step] = spec
	end
	for _, v in ipairs(type(t.StartSkills) == "table" and t.StartSkills or {}) do
		local id = skillId(v)
		if id and (fam.Steps[1].Skills[id] or 0) > 0 and #fam.StartSkills < 2 then
			table.insert(fam.StartSkills, id)
		end
	end
	return fam
end

local function fileName(name)
	local s = tostring(name):gsub("[^%w%-' ]", "_"):match("^%s*(.-)%s*$")
	return EXPORT_DIR .. "/" .. (s ~= "" and s or "Custom class") .. ".txt"
end

-- writes the build into CustomClasses/<base name>.txt; returns the path
local function exportBuild(fam)
	if os.mkdir then pcall(os.mkdir, EXPORT_DIR) end
	local path = fileName(fam.Steps[1].Name)
	local f, err = io.open(path, "wb")
	if not f then return nil, "can't write " .. path .. ": " .. tostring(err) end
	f:write(exportText(fam))
	f:close()
	return path
end

local function buildFiles()
	local t = {}
	if path and path.find then
		for p in path.find(EXPORT_DIR .. "/*.txt") do t[#t + 1] = p end
	end
	table.sort(t, function(a, b) return a:lower() < b:lower() end)
	return t
end

local function importFile(p)
	local f, err = io.open(p, "rb")
	if not f then return nil, "can't read " .. tostring(p) .. ": " .. tostring(err) end
	local text = f:read("*a")
	f:close()
	return importText(text)
end

-- CustomClass.Export(f): returns the file written
function CustomClass.Export(f)
	local p, err = exportBuild(family(f))
	if not p then error(err, 2) end
	print("saved " .. p)
	return p
end

-- CustomClass.Import(file [, f]): file name in CustomClasses (with or without .txt) or a
-- path; into family f (replacing its build, not while a character has it) or a new one
function CustomClass.Import(file, f)
	local p = tostring(file)
	if not p:find("[/\\]") then p = EXPORT_DIR .. "/" .. p end
	if not p:lower():find("%.txt$") then p = p .. ".txt" end
	local fam, err = importFile(p)
	if not fam then error(err, 2) end
	if f then
		family(f)
		if #members(f) > 0 then error("a character has this class", 2) end
	else
		for i = 1, FAMILIES do
			if not builds()[i] then f = i break end
		end
		if not f then error("all " .. FAMILIES .. " custom classes are in use", 2) end
	end
	builds()[f] = fam
	changed()
	local bad = {}
	for step = 1, STEPS do
		for _, b in ipairs(problems(fam, step)) do bad[#bad + 1] = STEP_NAMES[step] .. ": " .. b end
	end
	print(string.format("custom class %d: %s%s", f, fam.Steps[1].Name,
		#bad > 0 and ("  !! " .. table.concat(bad, "; ")) or ""))
	return f
end

-- for the creation screen (MMMWE_CustomClassEditor.lua)
MF.CustomClassCost = function(spec, kit) return cost(spec, kit) end
MF.CustomClasses = {
	Builds = builds,
	BeginCreation = function() Creating, Pending, NewGameStarted = true, {}, false; applyAll() end,
	IsCreating = function() return Creating end,
	NewFamily = newFamily,
	RemoveFamily = function(f) builds()[f] = nil; applyAll() end,
	Members = members,
	Cost = cost,
	Problems = problems,
	Apply = applyAll,
	Promote = promote,
	ClassId = classId,
	FamilyOf = familyOf,
	SetTier = famSetTier,
	SetStats = famSetStats,
	SetSkill = famSetSkill,
	SetKit = famSetKit,
	SetSpell = famSetSpell,
	SpellRank = spellRank,
	SpellSchool = spellSchool,
	SpellCost = SPELL_COST,
	SpellRankNames = SPELL_RANK_NAMES,
	MagicSchools = MAGIC_SCHOOLS,
	SpellProblems = spellProblems,
	ExportBuild = exportBuild,
	ImportFile = importFile,
	BuildFiles = buildFiles,
	ExportText = exportText,
	ImportText = importText,
	KitAllowed = function(pl, key) return MF.CustomClassKitAllowed(pl, key) end,
	Kits = KITS,
	KitByKey = KIT_BY_KEY,
	SkillNames = SKILL_IDS,
	CapNames = CAP_NAMES,
	StatsName = STATS_NAME,
	StepNames = STEP_NAMES,
	Budget = BUDGET,
	MaxTier = MAX_TIER,
	HPTiers = HP_TIERS,
	SPTiers = SP_TIERS,
	Families = FAMILIES,
	Steps = STEPS,
}
MF.CustomClassSettings = {FirstId = FIRST_ID, Families = FAMILIES, Steps = STEPS, FirstKind = FIRST_KIND,
	Budget = BUDGET, MaxTier = MAX_TIER, HPTiers = HP_TIERS, SPTiers = SP_TIERS, CapCost = CAP_COST,
	SkillMul = SKILL_MUL, Groups = GROUPS, GroupRest = GROUP_REST}
