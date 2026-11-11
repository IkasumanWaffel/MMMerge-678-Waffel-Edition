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
	  CustomClass.Alignment(f, a)               alignment of the base class, the first promotion and
	                                            the neutral second one: 0 good, 5 neutral, 10 evil
	                                            (the light and dark promotions stay 0 and 10)
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
local Tx, Tn = Merge.Functions.Text, Merge.Functions.TextKey

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
-- the base class, the first promotion and the neutral one take the family's own alignment
-- (fam.Alignment: 0 good, 5 neutral, 10 evil; for the alignment-tied artifacts and relics)
local OWN_ALIGNMENT_STEPS = 3
local AL = const.Alignment                       -- Good 0, Neutral 5, Evil 10 (20_MergeConsts.lua)
local ALIGNMENTS = {AL.Good, AL.Neutral, AL.Evil}
local STEP_NAMES = {Tx"base", Tx"first promotion", Tx"neutral", Tx"light", Tx"dark"}

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
	{Key = "Barbarian",  Name = "Barbarian",  Kind = 12, Price = 30, Page = "Fire",  Resource = Tn"Rage"},
	{Key = "Knight",     Name = "Knight",     Kind = 6,  Price = 25, Page = "Air",   Resource = Tn"Resolve",
		Branches = {[3] = "Champion", [4] = "Templar", [5] = "BlackKnight"}},
	{Key = "Thief",      Name = "Thief",      Kind = 11, Price = 20, Page = "Mind",  Resource = Tn"Energy",
		Branches = {[4] = "Spy", [5] = "Assassin"}},
	{Key = "Archer",     Name = "Archer",     Kind = 1,  Price = 15, Page = "Body",
		Branches = {[4] = "MasterArcher", [5] = "Sniper"}},
	{Key = "Ranger",     Name = "Ranger",     Kind = 10, Price = 15, Page = "Light"},
	{Key = "Paladin",    Name = "Paladin",    Kind = 9,  Price = 15, Page = "Air"},
	{Key = "DarkElf",    Name = Tn"Dark Elf",   Kind = 3,  Price = 15, Page = "Body"},
	{Key = "Minotaur",   Name = "Minotaur",   Kind = 7,  Price = 15, Page = "Fire",  Race = 10},   -- BaseRace Minotaur
	{Key = "Technician", Name = "Technician", Kind = 15, Price = 15, Page = "Earth", Resource = Tn"Construction",
		Needs = {"Blaster", "Repair"}, Branches = {[4] = "AncientResearcher", [5] = "Scientist"}},
}
-- spells (picked one by one; a spell needs its school's skill): cost by the spell's rank in
-- its school (spots 1-4 Novice, 5-7 Expert, 8-10 Master, 11 Grand Master) times its impact
-- (SPELL_IMPACT below). Picked spells are learned from Novice 1, as with most preset classes.
-- A step without a Spells list (builds made before spells could be picked) has every spell
-- of its schools, free of charge.
local SPELL_COST = {0.5, 1, 1.5, 2}

-- (07.11.26) a spell's price is its rank's price x its impact: minor utility and things a
-- potion or a temple does as well x0.5, standard x1, strong (area damage, party buffs,
-- crowd control, the top single-target damage) x1.5, game-changing (travel, skipping
-- fights, taking control, undoing death) x2.5. Spells not listed: x1.
local IMPACT_NAMES = {[0.5] = "minor", [1] = "standard", [1.5] = "strong", [2.5] = "game-changing"}
local SPELL_IMPACT = {}
for _, n in ipairs{1, 12, 13, 45, 56, 42, 27, 23,        -- Torch Light, Wizard Eye, Feather Fall,
		-- Detect Life, Telepathy, Telekinesis, Water Walk, Awaken
		3, 14, 25, 36, 58, 69,                           -- the six single resistances
		40, 49, 57, 61, 64, 67, 72, 74,                  -- the cures
		48} do                                           -- Turn Undead
	SPELL_IMPACT[n] = 0.5
end
for _, n in ipairs{6, 9, 10, 15, 22, 32, 43, 90, 93, 84, 99,   -- area damage
		11, 44, 87,                                      -- Incinerate, Mass Distortion, Sunray
		5, 17, 38, 46, 51, 50, 71, 75, 95, 83, 85,       -- party buffs
		60, 62, 63, 81, 96, 92,                          -- crowd control
		54, 77, 53,                                      -- Shared Life, Power Cure, Raise Dead
		30} do                                           -- Enchant Item
	SPELL_IMPACT[n] = 1.5
end
for _, n in ipairs{31, 33, 21,                           -- Town Portal, Lloyd's Beacon, Fly
		19,                                              -- Invisibility
		66, 94, 89,                                      -- Enslave, Control Undead, Reanimate
		55, 88, 86, 98} do                               -- Resurrection, Divine Intervention,
		                                                 -- Hour of Power, Armageddon
	SPELL_IMPACT[n] = 2.5
end

-- (07.11.26) fighter-mages: with Armsmaster at Master or above, a magic school at Master costs
-- x1.5 and at Grand Master x2 (all nine schools; on top of Light's and Dark's own x1.5, before
-- the school discount). A master of Armsmaster is a fighter, no longer a hybrid.
local FIGHTER_MAGE_MUL = {[3] = 1.5, [4] = 2}
local FIGHTER_MAGE_FROM = 3                      -- Armsmaster cap that starts it
local SPELL_RANK_NAMES = {Tx"Novice", Tx"Expert", Tx"Master", Tx"Grand Master"}
local MAGIC_SCHOOLS = {"Fire", "Air", "Water", "Earth", "Spirit", "Mind", "Body", "Light", "Dark"}
local function spellRank(spell)
	local i = (spell - 1) % 11
	return i == 10 and 4 or i >= 7 and 3 or i >= 4 and 2 or 1
end
local function spellSchool(spell)       -- skill id of the spell's school
	return const.Skills[MAGIC_SCHOOLS[math.floor((spell - 1) / 11) + 1]]
end
local function spellPrice(spell)
	return SPELL_COST[spellRank(spell)] * (SPELL_IMPACT[spell] or 1)
end
local function spellName(spell)
	local t = Game.SpellsTxt and Game.SpellsTxt[spell]
	return t and t.Name or ("spell " .. spell)
end

local KIT_BY_KEY = {}
for _, k in ipairs(KITS) do KIT_BY_KEY[k.Key] = k end
local SKILL_MUL = {Armsmaster = 1.5, Merchant = 1.5, Light = 1.5, Dark = 1.5,
	Learning = 1.25, Alchemy = 1.25, Blaster = 1.25, Enchanting = 1.25}
local GROUPS    = {{"Fire", "Air", "Water", "Earth"}, {"Spirit", "Mind", "Body"}}
local GROUP_REST = 0.75                          -- share paid for the other caps of a group
local FORBIDDEN = {DarkElfAbility = true, VampireAbility = true, DragonAbility = true}
local BOTH_STATS_COST = 3

local function tierCost(t)
	return 4 * math.min(t, 5) + 5 * math.max(t - 5, 0)
end

-- (09.11.26) starting items: bought with a budget of their own (not the build's points) and
-- given to the characters who take the class on the party creation screen (at the start of
-- the game) or in a training hall. An item costs its value / ITEM_VALUE_PER_POINT (at least
-- 1); a spellbook ITEM_BOOK_MUL x the spell's price in the build (rank x impact). Weapons,
-- bows, armor and shields need their skill on the base class; books a spell the base class
-- has. Potions can be taken up to ITEM_MAX_STACK times.
local ITEM_BUDGET = 20
local ITEM_VALUE_PER_POINT = 50
local ITEM_BOOK_MUL = 2
local ITEM_MAX_STACK = 5
local ITEM_POOL = {
	1, 6, 21, 26, 31, 36, 42, 66, 857, 863, 79, 56, 61, 2201,    -- weapons, bows, a cestus
	84, 85, 89, 90, 94, 104, 99,                                -- armor and shields
	109, 114, 117, 122, 127, 132, 137,                          -- helm, hat, belt, cloak, gloves, boots, ring
	222, 223, 224,                                              -- Cure Wounds, Magic, Cure Weakness potions
}
local STACKABLE = {[222] = true, [223] = true, [224] = true}
local SKILL_ITEM = {[0] = true, [1] = true, [2] = true, [3] = true, [4] = true}   -- EquipStat that needs the skill

local BookOf = {}
local function bookOf(spell)   -- the spellbook item of a spell (Mod1DiceSides = the spell)
	if BookOf[spell] ~= nil then return BookOf[spell] or nil end
	BookOf[spell] = false
	local t = Game.ItemsTxt
	local i = 399 + spell
	if not (t[i] and t[i].EquipStat == 16 and t[i].Mod1DiceSides == spell) then
		i = nil
		for j = 1, t.count - 1 do
			if t[j].EquipStat == 16 and t[j].Mod1DiceSides == spell then i = j break end
		end
	end
	BookOf[spell] = i or false
	return i
end

local function itemCost(num)
	local it = Game.ItemsTxt[num]
	if it.EquipStat == 16 then
		return math.max(1, math.ceil(ITEM_BOOK_MUL * spellPrice(it.Mod1DiceSides)))
	end
	return math.max(1, math.floor(it.Value / ITEM_VALUE_PER_POINT + 0.5))
end

-- the items a family's base class may take: the pool and the Novice spellbooks of its spells
local function itemPool(fam)
	local spec, list = fam.Steps[1], {}
	for _, n in ipairs(ITEM_POOL) do list[#list + 1] = n end
	for spell = 1, 99 do
		if spellRank(spell) == 1 and (spec.Skills[spellSchool(spell)] or 0) > 0
				and (not spec.Spells or spec.Spells[spell]) then
			local b = bookOf(spell)
			if b then list[#list + 1] = b end
		end
	end
	return list
end

-- nil and the reason when the base class can't take the item
local function itemAllowed(fam, num)
	local it = Game.ItemsTxt[num]
	if SKILL_ITEM[it.EquipStat] and (fam.Steps[1].Skills[it.Skill] or 0) == 0 then
		return nil, string.format(Tx"%s needs %s", it.Name, Game.SkillNames[it.Skill])
	end
	if it.EquipStat == 16 then
		local spell = it.Mod1DiceSides
		local spec = fam.Steps[1]
		if (spec.Skills[spellSchool(spell)] or 0) == 0 or (spec.Spells and not spec.Spells[spell]) then
			return nil, string.format(Tx"%s isn't a spell of the class", spellName(spell))
		end
	end
	return true
end

local function itemsTotal(fam)
	local total = 0
	for num, n in pairs(fam.Items or {}) do total = total + itemCost(num) * n end
	return total
end

-- adds (d = 1) or removes (d = -1) one of an item
local function famSetItem(fam, num, d)
	fam.Items = fam.Items or {}
	local n = fam.Items[num] or 0
	if d > 0 then
		local ok, err = itemAllowed(fam, num)
		if not ok then return nil, err end
		if n >= (STACKABLE[num] and ITEM_MAX_STACK or 1) then
			return nil, string.format(Tx"No more of %s", Game.ItemsTxt[num].Name)
		end
		if itemsTotal(fam) + itemCost(num) > ITEM_BUDGET then
			return nil, string.format(Tx"Starting items: %d points at most", ITEM_BUDGET)
		end
	end
	n = math.max(0, n + d)
	fam.Items[num] = n > 0 and n or nil
	return true
end

-- items the base class can no longer take (after a skill or spell change) are dropped
local function dropBadItems(fam)
	for num in pairs(fam.Items or {}) do
		if not itemAllowed(fam, num) then fam.Items[num] = nil end
	end
end

-- (09.11.26) the items the game hands out by the starting skills (weapons, armor, books,
-- potions...: EquipStat 0..16) are taken from a custom class character at the start of the
-- game, before its own starting items; gold, gems, quest items and letters stay
local function clearStartItems(pl)
	for k = 1, 138 do
		local it = pl.Items[k]
		local txt = it.Number > 0 and Game.ItemsTxt[it.Number]
		if txt and txt.EquipStat <= 16 then
			for c = 0, 125 do
				if pl.Inventory[c] == k then
					for c2 = 0, 125 do
						if pl.Inventory[c2] == -(1 + c) then pl.Inventory[c2] = 0 end
					end
					pl.Inventory[c] = 0
				end
			end
			for e = 0, 15 do
				if pl.EquippedItems[e] == k then pl.EquippedItems[e] = 0 end
			end
			it.Number = 0
		end
	end
end

-- gives a family's starting items to a party member (party slot)
local function giveItems(fam, slot)
	for num, n in pairs(fam.Items or {}) do
		for _ = 1, n do evt.ForPlayer(slot).Add("Inventory", num) end
	end
end

-- (09.11.26) the preset class a build resembles: the base class with the most alike skill
-- caps (the sum of the smaller caps over the sum of the larger, over all skills); its
-- promoters promote the custom class to its own steps (MMMWE_CustomClassPromotions.lua)
local PRESET_MATCH = 0.7
local function presetMatch(fam)
	local spec = fam.Steps[1]
	local best, bestScore
	local CE = Game.ClassesExtra
	if not CE then return end
	for c = 0, FIRST_ID - 1 do
		local ce = CE[c]
		if ce and ce.Step == 0 and ce.Kind and ce.Kind > 0 and ce.Kind < 16 then
			local lo, hi = 0, 0
			for id = 0, 38 do
				local a, b = spec.Skills[id] or 0, Game.Classes.Skills[c][id]
				lo, hi = lo + math.min(a, b), hi + math.max(a, b)
			end
			local score = hi > 0 and lo / hi or 0
			if not bestScore or score > bestScore then best, bestScore = c, score end
		end
	end
	return best, bestScore or 0
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

local PLACEHOLDER_NAME = Tx"Custom class"
local PLACEHOLDER_DESC = Tx"An unused custom class."

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
-- (08.11.26) the new skills of MMMWE_ExtraSkills.lua (not in const.Skills): their caps go to
-- MF.ExtraSkills.Caps[class] (MF.ClassSkillCap), not to the game's class table. They can't be
-- starting skills: they are learned in houses.
local EXTRA_SKILL_IDS = {[41] = "DualWield", [42] = "Robe", [43] = "Enchanting"}
for id, name in pairs(EXTRA_SKILL_IDS) do SKILL_IDS[id] = name end
local SKILL_LABEL = {DualWield = Tx"Dual-Wield"}
local function skillLabel(id)
	local name = SKILL_IDS[id]
	return SKILL_LABEL[name] or name
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
local CAP_NAMES = {[0] = "-", Tx"Novice", Tx"Expert", Tx"Master", Tx"Grand Master"}

local function capValue(cap)
	if type(cap) == "number" then return math.max(0, math.min(4, math.floor(cap))) end
	return CAP_LETTERS[tostring(cap):upper()]
end

local STATS_CODE = {I = 1, P = 2, IP = 3, PI = 3}
local STATS_NAME = {[1] = Tx"Intellect", [2] = Tx"Personality", [3] = Tx"Intellect and Personality"}

-- the builds in use: the save's, or the ones made on the party creation screen (Pending,
-- moved into the new game's vars when it starts)
local Pending, Creating, NewGameStarted = {}, false, false
local GiveStartItems = false

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
local IS_MAGIC = {}
for _, n in ipairs(MAGIC_SCHOOLS) do IS_MAGIC[n] = true end

local function cost(spec, kitKey)
	local total, lines = 0, {}
	local kit = kitKey and KIT_BY_KEY[kitKey]
	if kit then
		total = total + kit.Price
		lines[#lines + 1] = string.format(Tx"%s kit: %g", Tx(kit.Name), kit.Price)
	end
	local hp, sp = tierCost(spec.HP), tierCost(spec.SP)
	total = total + hp + sp
	lines[#lines + 1] = string.format(Tx"HP tier %d (%d/%d per level): %g", spec.HP, HP_TIERS[spec.HP][1], HP_TIERS[spec.HP][2], hp)
	local stats = spec.Stats == 3 and BOTH_STATS_COST or 0
	lines[#lines + 1] = string.format(Tx"SP tier %d (%d/%d per level, %s): %g", spec.SP, SP_TIERS[spec.SP][1], SP_TIERS[spec.SP][2],
		STATS_NAME[spec.Stats] or "?", sp + stats)
	total = total + stats
	-- fighter-mage surcharge on the magic schools (FIGHTER_MAGE_MUL)
	local fighter = (spec.Skills[const.Skills.Armsmaster] or 0) >= FIGHTER_MAGE_FROM
	local function capMul(name, m)
		local mul = SKILL_MUL[name] or 1
		local fm = fighter and IS_MAGIC[name] and FIGHTER_MAGE_MUL[m]
		if fm then mul = mul * fm end
		return mul, fm
	end
	local function note(fm, discount)
		local t = {}
		if fm then t[1] = string.format(Tx"fighter-mage x%g", fm) end
		if discount then t[#t + 1] = Tx"school discount" end
		return #t > 0 and " (" .. table.concat(t, ", ") .. ")" or ""
	end
	local grouped = {}
	for _, g in ipairs(GROUPS) do
		local costs = {}
		for _, name in ipairs(g) do
			local id = const.Skills[name]
			grouped[id] = true
			local m = spec.Skills[id] or 0
			if m > 0 then
				local mul, fm = capMul(name, m)
				costs[#costs + 1] = {CAP_COST[m] * mul, name, m, fm}
			end
		end
		table.sort(costs, function(a, b) return a[1] > b[1] end)
		for i, c in ipairs(costs) do
			local v = i == 1 and c[1] or c[1] * GROUP_REST
			total = total + v
			lines[#lines + 1] = string.format("%s %s: %g%s", c[2], CAP_NAMES[c[3]], v, note(c[4], i > 1))
		end
	end
	local others = {}
	for id, m in pairs(spec.Skills) do
		if m > 0 and not grouped[id] then others[#others + 1] = id end
	end
	table.sort(others)
	for _, id in ipairs(others) do
		local name, m = SKILL_IDS[id], spec.Skills[id]
		local mul, fm = capMul(name, m)
		local v = CAP_COST[m] * mul
		total = total + v
		lines[#lines + 1] = string.format("%s %s: %g%s", skillLabel(id), CAP_NAMES[m], v, note(fm))
	end
	if spec.Spells then
		local n, v = 0, 0
		for spell in pairs(spec.Spells) do
			n, v = n + 1, v + spellPrice(spell)
		end
		if n > 0 then
			total = total + v
			lines[#lines + 1] = string.format(Tx"%d spells: %g (by rank and impact)", n, v)
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
			out[#out + 1] = string.format(Tx"%s needs %s Magic", spellName(spell), MAGIC_SCHOOLS[math.floor((spell - 1) / 11) + 1])
		end
	end
	for i, name in ipairs(MAGIC_SCHOOLS) do
		local school = const.Skills[name]
		if (spec.Skills[school] or 0) > 0 and not has[school] then
			out[#out + 1] = name .. Tx" Magic: no spell picked"
		end
	end
	local p = PARENT[step] and fam.Steps[PARENT[step]]
	if p and p.Spells then
		for spell in pairs(p.Spells) do
			if not spec.Spells[spell] then
				out[#out + 1] = spellName(spell) .. Tx" is lost from the previous step"
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
		out[#out + 1] = string.format(Tx"%g points of %d", total, BUDGET[step])
	end
	if spec.HP > MAX_TIER[step] then out[#out + 1] = Tx"HP tier above " .. MAX_TIER[step] end
	if spec.SP > MAX_TIER[step] then out[#out + 1] = Tx"SP tier above " .. MAX_TIER[step] end
	local kit = fam.Kit and KIT_BY_KEY[fam.Kit]
	if kit then
		if (spec.Skills[const.Skills[kit.Page]] or 0) > 0 then
			out[#out + 1] = string.format(Tx"the %s kit uses the %s page: no %s Magic", Tx(kit.Name), kit.Page, kit.Page)
		end
		if kit.Resource and spec.SP > 0 then
			out[#out + 1] = string.format(Tx"%s replaces spell points: SP tier 0", Tx(kit.Resource))
		end
		for _, need in ipairs(kit.Needs or {}) do
			if (spec.Skills[const.Skills[need]] or 0) == 0 then
				out[#out + 1] = string.format(Tx"the %s kit needs %s", Tx(kit.Name), need == "Repair" and Tx"Repair Item" or need)
			end
		end
	end
	local p = PARENT[step] and fam.Steps[PARENT[step]]
	if p then
		if spec.HP < p.HP or spec.SP < p.SP then out[#out + 1] = Tx"lower HP/SP tier than the previous step" end
		if p.Stats == 3 and spec.Stats ~= 3 then out[#out + 1] = Tx"loses the second SP stat" end
		for id, m in pairs(p.Skills) do
			if (spec.Skills[id] or 0) < m then
				out[#out + 1] = SKILL_IDS[id] .. Tx" cap lower than the previous step"
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
			table.insert(bySkillCap[m], skillLabel(id))
		end
	end
	local parts = {string.format(Tx"A custom class. Hit points: tier %d. Spell points: tier %d%s.",
		spec.HP, spec.SP, spec.SP > 0 and (Tx", from " .. (STATS_NAME[spec.Stats] or "?")) or "")}
	local kit = fam.Kit and KIT_BY_KEY[fam.Kit]
	if kit then
		parts[#parts + 1] = string.format(Tx"%s kit: %s and the %s abilities (%s page of the spellbook).",
			Tx(kit.Name), kit.Resource and Tx(kit.Resource) or Tx"spell points", Tx(kit.Name), kit.Page)
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
		parts[#parts + 1] = string.format(Tx"Spells: %d.", n)
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
	local ex = MF.ExtraSkills
	if ex and ex.Caps then
		if spec then
			local caps = {}
			for sk in pairs(EXTRA_SKILL_IDS) do caps[sk] = spec.Skills[sk] or 0 end
			ex.Caps[id] = caps
		else
			ex.Caps[id] = nil
		end
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
	ce.Alignment = (spec and step <= OWN_ALIGNMENT_STEPS and fam.Alignment) or ALIGN_OF[step]
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
		-- a resource kit replaces the spell points (30.10.26: the Technician kit got
		-- Construction): builds made before keep no SP tier
		local kit = fam and fam.Kit and KIT_BY_KEY[fam.Kit]
		if kit and kit.Resource then
			for step = 1, STEPS do
				local spec = fam.Steps and fam.Steps[step]
				if spec and spec.SP > 0 then spec.SP = 0 end
			end
		end
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

-- the starting items of the classes taken on the creation screen, once the game has begun
function events.AfterLoadMap()
	if not GiveStartItems then return end
	GiveStartItems = false
	for i = 0, Party.count - 1 do
		local f, step = familyOf(Party[i].Class)
		local fam = f and builds()[f]
		if fam and step == 1 then
			clearStartItems(Party[i])
			giveItems(fam, i)
		end
	end
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
			GiveStartItems = true
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
	if not f then return nil, Tx"all " .. FAMILIES .. Tx" custom classes are in use" end
	name = name or (Tx"Custom Class " .. f)
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
		return nil, string.format(Tx"%s tier must be 0..%d for the %s", field, MAX_TIER[step], STEP_NAMES[step])
	end
	local p = PARENT[step] and fam.Steps[PARENT[step]]
	if p and tier < p[field] then
		return nil, string.format(Tx"%s tier can't be lower than the previous step's (%d)", field, p[field])
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
		return nil, Tx"the previous step already uses both stats"
	end
	local old = fam.Steps[step].Stats
	fam.Steps[step].Stats = code
	for _, c in ipairs(children(step)) do
		if code == 3 or fam.Steps[c].Stats == old then fam.Steps[c].Stats = code end
	end
	return true
end

local function famSetSkill(fam, step, id, m)
	if not SKILL_IDS[id] then return nil, Tx"this skill can't be bought" end
	m = math.max(0, math.min(4, m))
	local p = PARENT[step] and fam.Steps[PARENT[step]]
	if p and m < (p.Skills[id] or 0) then
		return nil, string.format(Tx"%s can't be lower than the previous step's %s", SKILL_IDS[id], CAP_NAMES[p.Skills[id]])
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
	if not spell or spell < 1 or spell > 99 then return nil, Tx"no such spell" end
	local spec = fam.Steps[step]
	local school = spellSchool(spell)
	if on and (spec.Skills[school] or 0) == 0 then
		return nil, string.format(Tx"%s needs %s Magic", spellName(spell), MAGIC_SCHOOLS[math.floor((spell - 1) / 11) + 1])
	end
	local p = PARENT[step] and fam.Steps[PARENT[step]]
	if not on and p and (not p.Spells or p.Spells[spell]) and (p.Skills[school] or 0) > 0 then
		return nil, spellName(spell) .. Tx" is a spell of the previous step"
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
		out[#out + 1] = string.format(Tx"%d. %s (%s, class %d): %g / %d points%s", step, spec.Name, STEP_NAMES[step],
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
			out[#out + 1] = string.format(Tx"%d: %s (%g points)%s", f, fam.Steps[1].Name, (cost(fam.Steps[1], fam.Kit)),
				#users > 0 and (" - " .. table.concat(users, ", ")) or "")
		end
	end
	local s = #out > 0 and table.concat(out, "\n") or Tx"no custom classes"
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
		return string.format(Tx"%s already is a %s", pl.Name, fam.Steps[step].Name)
	end
	-- the Merge's class conversion: skills the new class can't learn are removed and
	-- skills above its caps are lowered; the skill points spent raising them come back
	local before = pl.SkillPoints
	if MF.ConvertCharacter and pl.Attrs then
		MF.ConvertCharacter({Player = pl, ToClass = id})
	end
	pl.Class = id
	local refund = pl.SkillPoints - before
	return string.format(Tx"%s is now a %s%s", pl.Name, fam.Steps[step].Name,
		refund > 0 and string.format(Tx" (%d skill points refunded)", refund) or "")
end

-- promotes a party member of a custom class to 'step' of the same family (stage 3, ruler NPCs).
-- Returns the refunded skill points, or nil and the reason.
local function promote(pl, step)
	local f = familyOf(pl.Class)
	if not f then return nil, Tx"not a custom class" end
	local fam = builds()[f]
	if not fam or not fam.Steps[step] then return nil, Tx"the class has no build" end
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
	return false, string.format(Tx"the %s kit is for %ss only", Tx(kit.Name), Tx(kit.Name))
end
MF.CustomClassKitAllowed = kitAllowed

local function famSetAlignment(fam, a)
	a = tonumber(a)
	if a ~= AL.Good and a ~= AL.Neutral and a ~= AL.Evil then return nil, Tx"alignment: 0 good, 5 neutral, 10 evil" end
	fam.Alignment = a ~= AL.Neutral and a or nil
	return true
end

function CustomClass.Alignment(f, a)
	local fam = family(f)
	try(famSetAlignment(fam, a))
	changed()
end

local function famSetKit(fam, key)
	if key ~= nil and not KIT_BY_KEY[key] then return nil, Tx"unknown kit: " .. tostring(key) end
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
	if fam.Alignment then out[#out + 1] = string.format("\tAlignment = %d,", fam.Alignment) end
	local ss = {}
	for _, id in ipairs(fam.StartSkills or {}) do ss[#ss + 1] = string.format("%q", SKILL_IDS[id]) end
	out[#out + 1] = "\tStartSkills = {" .. table.concat(ss, ", ") .. "},"
	local its = {}
	for num, n in pairs(fam.Items or {}) do its[#its + 1] = string.format("[%d] = %d", num, n) end
	table.sort(its)
	if #its > 0 then out[#out + 1] = "\tItems = {" .. table.concat(its, ", ") .. "}," end
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
	local chunk, err = loadstring(text, Tx"custom class")
	if not chunk then return nil, "not a custom class file (" .. tostring(err) .. ")" end
	setfenv(chunk, {})
	local ok, t = pcall(chunk)
	if not ok or type(t) ~= "table" or type(t.Steps) ~= "table" then return nil, "not a custom class file" end
	local fam = {Steps = {}, StartSkills = {}}
	if t.Kit ~= nil then
		if not KIT_BY_KEY[t.Kit] then return nil, Tx"unknown kit: " .. tostring(t.Kit) end
		fam.Kit = t.Kit
	end
	if t.Alignment ~= nil then
		local ok, err = famSetAlignment(fam, t.Alignment)
		if not ok then return nil, err end
	end
	for step = 1, STEPS do
		local src = t.Steps[step]
		if type(src) ~= "table" then return nil, Tx"step " .. step .. Tx" is missing" end
		local name = tostring(src.Name or ""):gsub("[%c]", ""):sub(1, 24)
		if name == "" then return nil, Tx"step " .. step .. Tx" has no name" end
		local spec = {Name = name, Skills = {},
			HP = math.max(0, math.min(MAX_TIER[step], math.floor(tonumber(src.HP) or 0))),
			SP = math.max(0, math.min(MAX_TIER[step], math.floor(tonumber(src.SP) or 0))),
			Stats = STATS_NAME[tonumber(src.Stats)] and tonumber(src.Stats) or 1}
		for k, v in pairs(type(src.Skills) == "table" and src.Skills or {}) do
			local id, m = skillId(k), capValue(v)
			if not id then return nil, Tx"unknown skill: " .. tostring(k) end
			if not m then return nil, Tx"unknown cap: " .. tostring(v) end
			spec.Skills[id] = m > 0 and m or nil
		end
		if type(src.Spells) == "table" then
			spec.Spells = {}
			for _, v in ipairs(src.Spells) do
				local spell = tonumber(v)
				if not spell or spell < 1 or spell > 99 or spell ~= math.floor(spell) then
					return nil, Tx"unknown spell: " .. tostring(v)
				end
				spec.Spells[spell] = true
			end
		end
		fam.Steps[step] = spec
	end
	if type(t.Items) == "table" then
		fam.Items = {}
		for num, n in pairs(t.Items) do
			num, n = tonumber(num), tonumber(n)
			if num and n and n >= 1 and Game.ItemsTxt[num] and itemAllowed(fam, num) then
				fam.Items[num] = math.min(math.floor(n), STACKABLE[num] and ITEM_MAX_STACK or 1)
			end
		end
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
	return EXPORT_DIR .. "/" .. (s ~= "" and s or Tx"Custom class") .. ".txt"
end

-- writes the build into CustomClasses/<base name>.txt; returns the path
local function exportBuild(fam)
	if os.mkdir then pcall(os.mkdir, EXPORT_DIR) end
	local path = fileName(fam.Steps[1].Name)
	local f, err = io.open(path, "wb")
	if not f then return nil, Tx"can't write " .. path .. ": " .. tostring(err) end
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
	if not f then return nil, Tx"can't read " .. tostring(p) .. ": " .. tostring(err) end
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
	SetAlignment = famSetAlignment,
	Alignments = ALIGNMENTS,
	OwnAlignmentSteps = OWN_ALIGNMENT_STEPS,
	SetSpell = famSetSpell,
	SpellRank = spellRank,
	SpellSchool = spellSchool,
	SpellCost = SPELL_COST,
	SpellPrice = spellPrice,
	SpellImpact = SPELL_IMPACT,
	ImpactNames = IMPACT_NAMES,
	FighterMageMul = FIGHTER_MAGE_MUL,
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
	SkillLabel = skillLabel,
	ExtraSkillIds = EXTRA_SKILL_IDS,
	CapNames = CAP_NAMES,
	StatsName = STATS_NAME,
	StepNames = STEP_NAMES,
	Budget = BUDGET,
	ItemBudget = ITEM_BUDGET,
	ItemPool = itemPool,
	ItemCost = itemCost,
	ItemAllowed = itemAllowed,
	ItemsTotal = itemsTotal,
	SetItem = famSetItem,
	DropBadItems = dropBadItems,
	GiveItems = giveItems,
	PresetMatch = presetMatch,
	PresetMatchMin = PRESET_MATCH,
	MaxTier = MAX_TIER,
	HPTiers = HP_TIERS,
	SPTiers = SP_TIERS,
	Families = FAMILIES,
	Steps = STEPS,
}
MF.CustomClassSettings = {FirstId = FIRST_ID, Families = FAMILIES, Steps = STEPS, FirstKind = FIRST_KIND,
	Budget = BUDGET, MaxTier = MAX_TIER, HPTiers = HP_TIERS, SPTiers = SP_TIERS, CapCost = CAP_COST,
	SkillMul = SKILL_MUL, Groups = GROUPS, GroupRest = GROUP_REST}
