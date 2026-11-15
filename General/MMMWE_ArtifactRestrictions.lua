--[[
	MMMWE_ArtifactRestrictions.lua — who can wear artifacts and relics (15.11.26)

	The rules (agreed on Celestial Heavens): an item is restricted only where its description
	gives a reason; the restrictions are kept in Tables/Artifact restrictions.txt, one
	row per item, and the same row writes the item's label into its description, so the
	check and the label can't drift apart.

	Columns (tab separated; "-" for none, lists with commas):
	  Item         item number
	  Alignment    NotGood (neutral and evil classes), NotEvil (good and neutral), Good, Evil
	               (that alignment only)
	  Classes      class families (const.ClassKind names: Knight, Paladin, Cleric, Sorcerer...)
	  Except       class families the alignment rule doesn't bar (Twilight: Thief)
	  Races        Human, Elf, DarkElf, Dwarf, Goblin, Minotaur, Troll, Vampire, Undead
	  NotRaces     the same names: who can't wear it (the undead and the undead-slaying weapons)
	  Gender       Male or Female
	  OldTag       the label the description had (replaced by the new one); "-" adds the label
	               to the description's first bracket, or a bracket of its own
	  Name         for reading only

	The class alignment is the class's own (Data/Tables/Class Extra.txt: 0 good, 5 neutral,
	10 evil; custom classes: their editor setting). A class family counts the preset class a
	custom class resembles (MF.PresetClassOf, as for the promoters). Undead are the undead and
	ghost race families (liches, ghosts); vampires and zombies are not.

	MF.ArtifactRestrictions[item] -> the row; MF.ArtifactRestrictionLabel(item) -> its label.
	The Crown of Final Dominion (Lich) and the Wetsuit keep their own conditions in
	Global/ExtraArtifacts.lua.

	Last Stage Cuirass (533): made by a lich for liches, so an undead wearer doesn't suffer
	its -30 Mind and Spirit resistance (+30 back here, CUIRASS_UNDEAD); its description says so.
--]]

local MF = Merge.Functions
local Tx = Merge.Functions.Text

local FILE = "Data/Tables/Artifact restrictions.txt"

local AL = const.Alignment or {Good = 0, Neutral = 5, Evil = 10}

local CLASS_NAMES = {
	Archer = {Tx"Archer", Tx"Archers"}, Cleric = {Tx"Cleric", Tx"Clerics"},
	Deerslayer = {Tx"Deerslayer", Tx"Deerslayers"}, Dragon = {Tx"Dragon", Tx"Dragons"},
	Druid = {Tx"Druid", Tx"Druids"}, Knight = {Tx"Knight", Tx"Knights"},
	Minotaur = {Tx"Minotaur", Tx"Minotaurs"}, Monk = {Tx"Monk", Tx"Monks"},
	Paladin = {Tx"Paladin", Tx"Paladins"}, Ranger = {Tx"Ranger", Tx"Rangers"},
	Thief = {Tx"Thief", Tx"Thieves"}, Barbarian = {Tx"Barbarian", Tx"Barbarians"},
	Vampire = {Tx"Vampire", Tx"Vampires"}, Sorcerer = {Tx"Sorcerer", Tx"Sorcerers"},
	Technician = {Tx"Technician", Tx"Technicians"}, Peasant = {Tx"Peasant", Tx"Peasants"},
}
local RACE_NAMES = {
	Human = Tx"Human", Elf = Tx"Elven", DarkElf = Tx"Dark Elf", Dwarf = Tx"Dwarven",
	Goblin = Tx"Goblin", Minotaur = Tx"Minotaur", Troll = Tx"Troll", Vampire = Tx"Vampire",
	Undead = Tx"Undead",
}
local NOT_RACE_NAMES = {
	Undead = Tx"Not for the undead", Human = Tx"Not for humans", Elf = Tx"Not for elves",
	DarkElf = Tx"Not for dark elves", Dwarf = Tx"Not for dwarves", Goblin = Tx"Not for goblins",
	Minotaur = Tx"Not for minotaurs", Troll = Tx"Not for trolls", Vampire = Tx"Not for vampires",
}
local ALIGN_LABEL = {
	NotGood = Tx"Not for the good", NotEvil = Tx"Not for the evil", Good = Tx"Good",
	Evil = Tx"Evil",
}
local GENDER = {Male = 0, Female = 1}
local GENDER_LABEL = {Male = Tx"Male", Female = Tx"Female"}

local Rows = {}
MF.ArtifactRestrictions = Rows

---------------------------------------------------------------------------
-- the table
---------------------------------------------------------------------------

local function list(s)
	local t = {}
	if s and s ~= "" and s ~= "-" then
		for w in s:gmatch("[^,]+") do
			w = w:match("^%s*(.-)%s*$")
			if w ~= "" then t[#t + 1] = w end
		end
	end
	return t
end

local function load()
	local f = io.open(FILE, "r")
	if not f then
		MF.LogWarning("[ArtifactRestrictions] %s not found", FILE)
		return
	end
	local first = true
	for line in f:lines() do
		line = line:gsub("\r$", "")
		if first then
			first = false
		elseif line ~= "" and not line:match("^%s*#") then
			local w = string.split(line, "\9")
			local id = tonumber(w[1])
			if id then
				local r = {Item = id, Alignment = (w[2] ~= "-" and w[2] ~= "") and w[2] or nil,
					Classes = list(w[3]), Except = list(w[4]), Races = list(w[5]),
					NotRaces = list(w[6]), Gender = (w[7] ~= "-" and w[7] ~= "") and w[7] or nil,
					OldTag = (w[8] and w[8] ~= "-" and w[8] ~= "") and w[8] or nil, Name = w[9]}
				for _, k in ipairs(r.Classes) do
					if not const.ClassKind[k] then MF.LogWarning("[ArtifactRestrictions] item %d: unknown class %s", id, k) end
				end
				for _, k in ipairs(r.Except) do
					if not const.ClassKind[k] then MF.LogWarning("[ArtifactRestrictions] item %d: unknown class %s", id, k) end
				end
				for _, k in ipairs(r.Races) do
					if not RACE_NAMES[k] then MF.LogWarning("[ArtifactRestrictions] item %d: unknown race %s", id, k) end
				end
				for _, k in ipairs(r.NotRaces) do
					if not RACE_NAMES[k] then MF.LogWarning("[ArtifactRestrictions] item %d: unknown race %s", id, k) end
				end
				if r.Alignment and not ALIGN_LABEL[r.Alignment] then
					MF.LogWarning("[ArtifactRestrictions] item %d: unknown alignment %s", id, r.Alignment)
				end
				Rows[id] = r
			end
		end
	end
	f:close()
end

---------------------------------------------------------------------------
-- the check
---------------------------------------------------------------------------

local function classKind(pl)
	local cls = MF.PresetClassOf and MF.PresetClassOf(pl) or pl.Class
	local ce = Game.ClassesExtra[cls]
	return ce and ce.Kind
end

local function alignment(pl)
	local ce = Game.ClassesExtra[pl.Class]
	return ce and ce.Alignment or AL.Neutral
end

local function raceIs(pl, name)
	local r = Game.Races[GetCharRace(pl)]
	if not r then return false end
	if name == "Undead" then
		return r.Family == const.RaceFamily.Undead or r.Family == const.RaceFamily.Ghost
	elseif name == "Vampire" then
		return r.Family == const.RaceFamily.Vampire
	elseif name == "DarkElf" then
		return r.BaseRace == const.Race.DarkElf and r.Family == const.RaceFamily.None
	elseif name == "Elf" then
		return r.Kind == const.RaceKind.Elf
	end
	return r.Kind == const.RaceKind[name]
end

local function inKinds(kind, names)
	for _, n in ipairs(names) do
		if const.ClassKind[n] == kind then return true end
	end
	return false
end

-- true if the character can wear the item by its row
local function allowed(pl, r)
	local kind = classKind(pl)
	if #r.Classes > 0 and not inKinds(kind, r.Classes) then return false end
	local a = r.Alignment
	if a and not (#r.Except > 0 and inKinds(kind, r.Except)) then
		local al = alignment(pl)
		if a == "NotGood" and al == AL.Good then return false end
		if a == "NotEvil" and al == AL.Evil then return false end
		if a == "Good" and al ~= AL.Good then return false end
		if a == "Evil" and al ~= AL.Evil then return false end
	end
	if #r.Races > 0 then
		local ok = false
		for _, n in ipairs(r.Races) do if raceIs(pl, n) then ok = true end end
		if not ok then return false end
	end
	for _, n in ipairs(r.NotRaces) do
		if raceIs(pl, n) then return false end
	end
	if r.Gender then
		local p = Game.CharacterPortraits[pl.Face]
		if not p or p.DefSex ~= GENDER[r.Gender] then return false end
	end
	return true
end
MF.ArtifactAllowed = function(pl, item)
	local r = Rows[item]
	return not r or allowed(pl, r)
end

function events.CanWearItem(t)
	local r = Rows[t.ItemId]
	if r and t.Available then
		t.Available = allowed(t.Player, r)
	end
end

---------------------------------------------------------------------------
-- the label
---------------------------------------------------------------------------

local function joinOr(names)
	if #names <= 1 then return names[1] or "" end
	return table.concat(names, ", ", 1, #names - 1) .. Tx" or " .. names[#names]
end

local function label(r)
	local parts = {}
	local classes = {}
	for _, k in ipairs(r.Classes) do classes[#classes + 1] = CLASS_NAMES[k] and CLASS_NAMES[k][1] or k end
	local a = r.Alignment
	if #classes > 0 then parts[#parts + 1] = joinOr(classes) end
	if a then
		local s = ALIGN_LABEL[a]
		if #r.Except > 0 then
			local ex = {}
			for _, k in ipairs(r.Except) do ex[#ex + 1] = CLASS_NAMES[k] and CLASS_NAMES[k][2] or k end
			s = s .. string.format(Tx" (%s excepted)", joinOr(ex))
		end
		parts[#parts + 1] = s
	end
	local races = {}
	for _, k in ipairs(r.Races) do races[#races + 1] = RACE_NAMES[k] or k end
	if #races > 0 then parts[#parts + 1] = joinOr(races) end
	for _, k in ipairs(r.NotRaces) do parts[#parts + 1] = NOT_RACE_NAMES[k] or k end
	if r.Gender then parts[#parts + 1] = GENDER_LABEL[r.Gender] end
	return table.concat(parts, ", ")
end
MF.ArtifactRestrictionLabel = function(item)
	local r = Rows[item]
	return r and label(r)
end

local function plainFind(s, pat, init)
	return s:find(pat, init or 1, true)
end

-- the label in the description: in place of the old one, else at the end of the first
-- bracket (before a closing full stop), else in a bracket of its own at the end
local function relabel(id, r)
	local txt = Game.ItemsTxt[id]
	local s = txt and txt.Notes
	if not s or s == "" then return end
	local lab = label(r)
	if lab == "" then return end
	if plainFind(s, lab) then return end
	if r.OldTag then
		local i1, i2 = plainFind(s, ", " .. r.OldTag .. ")")
		if i1 then
			txt.Notes = s:sub(1, i1 - 1) .. ", " .. lab .. ")" .. s:sub(i2 + 1)
			return
		end
		i1, i2 = plainFind(s, "(" .. r.OldTag .. ")")
		if i1 then
			txt.Notes = s:sub(1, i1 - 1) .. "(" .. lab .. ")" .. s:sub(i2 + 1)
			return
		end
	end
	local open = plainFind(s, "(")
	local close = open and plainFind(s, ")", open)
	if close then
		local before = close - 1
		while before > open and s:sub(before, before):match("[%s%.;]") do before = before - 1 end
		txt.Notes = s:sub(1, before) .. ", " .. lab .. s:sub(before + 1)
	else
		txt.Notes = s .. " (" .. lab .. ")"
	end
end

---------------------------------------------------------------------------
-- Last Stage Cuirass: no resistance penalty for the undead
---------------------------------------------------------------------------

local CUIRASS = 533
local CUIRASS_UNDEAD = 30

local function wearsCuirass(pl)
	local i = pl.ItemArmor
	if not i or i <= 0 then return false end
	local it = pl.Items[i]
	return it.Number == CUIRASS and not it.Broken
end

function events.CalcStatBonusByItems(t)
	local st = const.Stats
	if t.Stat ~= st.MindResistance and t.Stat ~= st.SpiritResistance then return end
	local pl = t.Player
	if pl and wearsCuirass(pl) and raceIs(pl, "Undead") then
		t.Result = t.Result + CUIRASS_UNDEAD
	end
end

local function cuirassNote()
	local txt = Game.ItemsTxt[CUIRASS]
	local s = txt and txt.Notes
	local note = Tx" The undead suffer no loss of resistance."
	if s and s ~= "" and not s:find(note, 1, true) then
		txt.Notes = s:gsub("%s+$", "") .. note
	end
end

function events.GameInitialized2()
	load()
	local n = 0
	for id, r in pairs(Rows) do
		if Game.ItemsTxt[id] then
			relabel(id, r)
			n = n + 1
		end
	end
	cuirassNote()
	if MF.LogInfo then MF.LogInfo("[ArtifactRestrictions] %d items restricted", n) end
end
