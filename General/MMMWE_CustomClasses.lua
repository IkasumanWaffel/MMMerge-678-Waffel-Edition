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

local BUDGET   = {100, 115, 130, 130, 130}
local MAX_TIER = {5, 6, 7, 7, 7}
local PARENT   = {nil, 1, 2, 2, 2}
local STEP_OF  = {0, 1, 2, 2, 2}                 -- Class Extra Step
local ALIGN_OF = {5, 5, 5, 0, 10}                -- Class Extra Alignment (const.Alignment)
local STEP_NAMES = {"base", "first promotion", "neutral", "light", "dark"}

-- {base, per level}
local HP_TIERS = {[0] = {20, 3}, {25, 4}, {30, 5}, {35, 6}, {35, 7}, {40, 8}, {40, 9}, {40, 10}}
local SP_TIERS = {[0] = {0, 0}, {5, 1}, {5, 2}, {10, 3}, {15, 3}, {20, 4}, {20, 5}, {25, 5}}

local CAP_COST  = {[0] = 0, 2, 4, 7, 10}         -- total cost of a mastery cap
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

local function store()
	vars.CustomClasses = vars.CustomClasses or {}
	return vars.CustomClasses
end

local function family(f)
	local fam = vars and vars.CustomClasses and vars.CustomClasses[f]
	if not fam then error(string.format("no custom class %s", tostring(f)), 3) end
	return fam
end

local function copySpec(s)
	local t = {Name = s.Name, HP = s.HP, SP = s.SP, Stats = s.Stats, Skills = {}}
	for k, v in pairs(s.Skills) do t.Skills[k] = v end
	return t
end

-- point cost of one step's build, and the lines that explain it
local function cost(spec)
	local total, lines = 0, {}
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
	return total, lines
end

-- problems of a step: over budget, tiers too high, less than its parent
local function problems(fam, step)
	local spec, out = fam.Steps[step], {}
	local total = cost(spec)
	if total > BUDGET[step] then
		out[#out + 1] = string.format("%g points of %d", total, BUDGET[step])
	end
	if spec.HP > MAX_TIER[step] then out[#out + 1] = "HP tier above " .. MAX_TIER[step] end
	if spec.SP > MAX_TIER[step] then out[#out + 1] = "SP tier above " .. MAX_TIER[step] end
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
	for m = 4, 1, -1 do
		if bySkillCap[m] then
			table.sort(bySkillCap[m])
			parts[#parts + 1] = CAP_NAMES[m] .. ": " .. table.concat(bySkillCap[m], ", ") .. "."
		end
	end
	return table.concat(parts, " ")
end

local AllSpellsB1
local function spellsLearning()
	if not AllSpellsB1 then
		AllSpellsB1 = {}
		for spell = 1, 99 do
			AllSpellsB1[spell] = {{PlayerLevel = 1, SkillMastery = 1, SkillLevel = 1}}
		end
	end
	return AllSpellsB1
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
		MT.SpellsLearning[id] = spec and spellsLearning() or nil
	end
end

local function applyAll()
	if not (Game.Classes and Game.Classes.Skills.count > LAST_ID and Game.ClassNames.count > LAST_ID) then
		MF.LogError("CustomClasses: the class tables have no room for the custom classes (%d / %d)",
			Game.Classes.Skills.count, Game.ClassNames.count)
		return false
	end
	local all = vars and vars.CustomClasses or {}
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
	end
	return true
end
MF.ApplyCustomClasses = applyAll

function events.BeforeLoadMap()
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

function CustomClass.New(name)
	local all = store()
	local f
	for i = 1, FAMILIES do
		if not all[i] then f = i break end
	end
	if not f then error("all " .. FAMILIES .. " custom classes are in use", 2) end
	name = name or ("Custom class " .. f)
	local base = {Name = name, HP = 0, SP = 0, Stats = 1, Skills = {}}
	local fam = {Steps = {base}}
	local names = {name, name .. " Adept", name .. " Master", "Light " .. name, "Dark " .. name}
	for step = 2, STEPS do
		fam.Steps[step] = copySpec(base)
		fam.Steps[step].Name = names[step]
	end
	all[f] = fam
	changed()
	return f
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
	vars.CustomClasses[f] = nil
	changed()
end

function CustomClass.Name(f, step, name)
	local fam = family(f)
	fam.Steps[checkStep(step)].Name = tostring(name)
	changed()
end

local function setTier(f, step, field, tier)
	local fam = family(f)
	step = checkStep(step)
	tier = math.floor(tonumber(tier) or -1)
	if tier < 0 or tier > MAX_TIER[step] then
		error(string.format("tier must be 0..%d for the %s", MAX_TIER[step], STEP_NAMES[step]), 3)
	end
	local old = fam.Steps[step][field]
	fam.Steps[step][field] = tier
	for _, c in ipairs(children(step)) do
		local v = fam.Steps[c][field]
		if v < tier or v == old then fam.Steps[c][field] = tier end
	end
end

function CustomClass.HP(f, step, tier)
	setTier(f, step, "HP", tier)
	changed()
end

function CustomClass.SP(f, step, tier, stats)
	setTier(f, step, "SP", tier)
	if stats then
		local code = STATS_CODE[tostring(stats):upper()]
		if not code then error('stats must be "I", "P" or "IP"', 2) end
		local fam = family(f)
		local old = fam.Steps[step].Stats
		fam.Steps[step].Stats = code
		for _, c in ipairs(children(step)) do
			if code == 3 or fam.Steps[c].Stats == old then fam.Steps[c].Stats = code end
		end
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
	local old = fam.Steps[step].Skills[id] or 0
	fam.Steps[step].Skills[id] = m > 0 and m or nil
	for _, c in ipairs(children(step)) do
		local v = fam.Steps[c].Skills[id] or 0
		if v < m or v == old then fam.Steps[c].Skills[id] = m > 0 and m or nil end
	end
	changed()
end

function CustomClass.Show(f)
	local fam = family(f)
	local out = {}
	for step = 1, STEPS do
		local spec = fam.Steps[step]
		local total, lines = cost(spec)
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
	local all = vars and vars.CustomClasses or {}
	for f = 1, FAMILIES do
		local fam = all[f]
		if fam then
			local users = {}
			for i = 0, Party.PlayersArray.count - 1 do
				local pl = Party.PlayersArray[i]
				if familyOf(pl.Class) == f and pl.Name ~= "" then users[#users + 1] = pl.Name end
			end
			out[#out + 1] = string.format("%d: %s (%g points)%s", f, fam.Steps[1].Name, (cost(fam.Steps[1])),
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

-- for the creation screen (stage 2)
MF.CustomClassCost = function(spec) return cost(spec) end
MF.CustomClassSettings = {FirstId = FIRST_ID, Families = FAMILIES, Steps = STEPS, FirstKind = FIRST_KIND,
	Budget = BUDGET, MaxTier = MAX_TIER, HPTiers = HP_TIERS, SPTiers = SP_TIERS, CapCost = CAP_COST,
	SkillMul = SKILL_MUL, Groups = GROUPS, GroupRest = GROUP_REST}
