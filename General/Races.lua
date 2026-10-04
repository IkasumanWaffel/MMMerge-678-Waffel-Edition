-- Race-related stuff except for const.Race
local LogId = "Races"
local MF = Merge.Functions
MF.LogInit1(LogId)
local MT = Merge.Tables

-- Get Character's Race by his Race Attr or by his Face
function GetCharRace(Char)
	if Char == nil then
		MF.LogError("GetCharRace: nil Character")
		return false
	end
	return Char.Attrs and Char.Attrs.Race or Game.CharacterPortraits[Char.Face].Race
end

local function ProcessRacesTxt()
	Game.RaceMaturityMax = 1
	local mature_variants = Game.RaceMaturityMax + 1

	--[[local TXTMatureNames = {
		[0] = nil,
		[1] = "Mature"
	}]]

	local BaseRaceKinds = {
		[const.Race.Human] = const.RaceKind.Human,
		[const.Race.DarkElf] = const.RaceKind.Elf,
		[const.Race.Minotaur] = const.RaceKind.Minotaur,
		[const.Race.Troll] = const.RaceKind.Troll,
		[const.Race.Dragon] = const.RaceKind.Dragon,
		[const.Race.Elf] = const.RaceKind.Elf,
		[const.Race.Goblin] = const.RaceKind.Goblin,
		[const.Race.Dwarf] = const.RaceKind.Dwarf
	}

	-- Default Race Names*, can be overridden/localized in Data/Tables/Races.txt
	local TXTRaceNames = {
		[const.Race.Human]	= "Human",
		[const.Race.DarkElf]	= "Dark Elf",
		[const.Race.Minotaur]	= "Minotaur",
		[const.Race.Troll]	= "Troll",
		[const.Race.Dragon]	= "Dragon",
		[const.Race.Elf]	= "Elf",
		[const.Race.Goblin]	= "Goblin",
		[const.Race.Dwarf]	= "Dwarf"
	}

	local TXTFamilyNames = {
		[const.RaceFamily.None]		= nil,
		[const.RaceFamily.Undead]	= "Undead",
		[const.RaceFamily.Vampire]	= "Vampire",
		[const.RaceFamily.Zombie]	= "Zombie",
		[const.RaceFamily.Ghost]	= "Ghost"
	}

	local TXTRaceNamesPlural = {
		[const.Race.Human]	= "Humans",
		[const.Race.DarkElf]	= "Dark Elves",
		[const.Race.Minotaur]	= "Minotaurs",
		[const.Race.Troll]	= "Trolls",
		[const.Race.Dragon]	= "Dragons",
		[const.Race.Elf]	= "Elves",
		[const.Race.Goblin]	= "Goblins",
		[const.Race.Dwarf]	= "Dwarves"
	}

	local TXTFamilyNamesPlural = {
		[const.RaceFamily.None]		= nil,
		[const.RaceFamily.Undead]	= "Undead",
		[const.RaceFamily.Vampire]	= "Vampires",
		[const.RaceFamily.Zombie]	= "Zombies",
		[const.RaceFamily.Ghost]	= "Ghosts"
	}

	local TXTRaceNamesAdj = {
		[const.Race.Human]	= "Human",
		[const.Race.DarkElf]	= "Dark Elven",
		[const.Race.Minotaur]	= "Minotaur",
		[const.Race.Troll]	= "Troll",
		[const.Race.Dragon]	= "Dragon",
		[const.Race.Elf]	= "Elven",
		[const.Race.Goblin]	= "Goblin",
		[const.Race.Dwarf]	= "Dwarven"
	}

	local TXTFamilyNameAdj = {
		[const.RaceFamily.None]		= nil,
		[const.RaceFamily.Undead]	= "Undead",
		[const.RaceFamily.Vampire]	= "Vampire",
		[const.RaceFamily.Zombie]	= "Zombie",
		[const.RaceFamily.Ghost]	= "Ghost"
	}

	local race_kinds_count = 0

	for k, v in pairs(const.RaceKind) do
		race_kinds_count = race_kinds_count + 1
	end

	Game.RaceKindsCount = race_kinds_count

	local race_families_count = 0

	for k, v in pairs(const.RaceFamily) do
		race_families_count = race_families_count + 1
	end

	Game.RaceFamiliesCount = race_families_count

	-- Amount of variants per base race
	--   Should be equal to number of families
	local race_variants = Game.RaceFamiliesCount

	local Races = {}
	local races_count = 0

	-- Set Race Names to const.Race key by default
	for k, v in pairs(const.Race) do
		Races[v] = {}
		Races[v].Id = v
		Races[v].StringId = k
		Races[v].BaseRace = v - (v % race_variants)
		Races[v].Family = v % race_variants
		if v % race_variants == 0 then
			Races[v].Kind = BaseRaceKinds[Races[v].BaseRace]
		else
			-- We have only Undead race variants yet
			--   Extend when new variants will be added
			Races[v].Kind = const.RaceKind.Undead
		end
		Races[v].Name =
			TXTRaceNames[Races[v].BaseRace] and
			((TXTFamilyNames[Races[v].Family] and TXTFamilyNames[Races[v].Family] .. " " or "")
			.. TXTRaceNames[Races[v].BaseRace]) or k
		Races[v].Plural =
			TXTRaceNamesPlural[Races[v].BaseRace] and
			((TXTFamilyNames[Races[v].Family] and TXTFamilyNames[Races[v].Family] .. " " or "")
			.. TXTRaceNamesPlural[Races[v].BaseRace]) or k
		Races[v].Adj =
			TXTRaceNamesAdj[Races[v].BaseRace] and
			((TXTFamilyNames[Races[v].Family] and TXTFamilyNames[Races[v].Family] .. " " or "")
			.. TXTRaceNamesAdj[Races[v].BaseRace]) or k
		races_count = races_count + 1
	end

	Game.RacesCount = races_count
	MT.RacesCount = races_count

	local TxtTable = io.open("Data/Tables/Races.txt", "r")
	local header = "#\9StringId\9BaseRace\9Family\9Kind\9Name\9Plural\9Adjective"
		.. "\9SpellsB\9SpellsE\9SpellsM\9SpellsG\9SpcMSpell\9SpcMSkill\9SpcMDmg"
		.. "\9SpcMSP\9SpcMRecv\9SpcMBits\9SpcMCD\9SpcMProj\9SpcMSnd\9SpcRSpell"
		.. "\9SpcRSkill\9SpcRDmg\9SpcRSP\9SpcRRecv\9SpcRBits\9SpcRCD\9SpcRProj"
		.. "\9SpcRSnd"

	if not TxtTable then
		Log(Merge.Log.Warning, "No Races.txt found, creating one.")
		TxtTable = io.open("Data/Tables/Races.txt", "w")
		TxtTable:write(header .. "\n")
		for k, v in pairs(Races) do
			TxtTable:write(string.format("%d\9%s\9%d\9%d\9%d\9%s\9%s\9%s\n", k, v.StringId, v.BaseRace, v.Family, v.Kind, v.Name, v.Plural, v.Adj))
		end
	else
		local LineIt = TxtTable:lines()
		if LineIt() ~= header then
			Log(Merge.Log.Error, "Races.txt header differs from expected one, table is ignored. Regenerate or fix it.")
			return false
		end

		for line in LineIt do
			local Words = string.split(line, "\9")
			if string.len(Words[1]) == 0 then
				break
			end
			if Words[1] and tonumber(Words[1]) then
				local race = tonumber(Words[1])
				-- We won't take StringId from TxtTable so skip Words[2]
				local baserace = tonumber(Words[3])
				if baserace and baserace >= 0 and baserace <= Game.RacesCount then
					Races[race].BaseRace = baserace
				end
				local racefamily = tonumber(Words[4])
				if racefamily and racefamily >= 0 and racefamily <= Game.RaceFamiliesCount then
					Races[race].Family = racefamily
				end
				local racekind = tonumber(Words[5])
				if racekind and racekind >= 0 and racekind <= Game.RaceKindsCount then
					Races[race].Kind = racekind
				end
				Races[race].Name = Words[6] or Races[race].Name
				Races[race].Plural = Words[7] or Races[race].Name
				Races[race].Adj = Words[8] or Races[race].Adj
				Races[race].Spells = {}
				if Words[9] and Words[9] ~= "" then
					Races[race].SpellsB = string.split(Words[9], ',')
					for k, v in pairs(Races[race].SpellsB) do
						Races[race].SpellsB[k] = tonumber(v)
					end
				end
				Races[race].Spells[1] = Races[race].SpellsB
				if Words[10] and Words[10] ~= "" then
					Races[race].SpellsE = string.split(Words[10], ',')
					for k, v in pairs(Races[race].SpellsE) do
						Races[race].SpellsE[k] = tonumber(v)
					end
				end
				Races[race].Spells[2] = Races[race].SpellsE
				if Words[11] and Words[11] ~= "" then
					Races[race].SpellsM = string.split(Words[11], ',')
					for k, v in pairs(Races[race].SpellsM) do
						Races[race].SpellsM[k] = tonumber(v)
					end
				end
				Races[race].Spells[3] = Races[race].SpellsM
				if Words[12] and Words[12] ~= "" then
					Races[race].SpellsG = string.split(Words[12], ',')
					for k, v in pairs(Races[race].SpellsG) do
						Races[race].SpellsG[k] = tonumber(v)
					end
				end
				Races[race].Spells[4] = Races[race].SpellsG
				Races[race].SpcAttack = {}
				Races[race].SpcAttack[0] = {}
				Races[race].SpcAttack[1] = {}
				Races[race].SpcAttack[0].Spell = tonumber(Words[13])
				Races[race].SpcAttack[0].Skill = tonumber(Words[14])
				Races[race].SpcAttack[0].DamageType = tonumber(Words[15])
				Races[race].SpcAttack[0].SpellPoints = tonumber(Words[16])
				Races[race].SpcAttack[0].Recovery = tonumber(Words[17])
				Races[race].SpcAttack[0].Bits = tonumber(Words[18])
				Races[race].SpcAttack[0].Cooldown = tonumber(Words[19])
				Races[race].SpcAttack[0].Projectile = tonumber(Words[20])
				Races[race].SpcAttack[0].Sound = tonumber(Words[21])
				Races[race].SpcAttack[1].Spell = tonumber(Words[22])
				Races[race].SpcAttack[1].Skill = tonumber(Words[23])
				Races[race].SpcAttack[1].DamageType = tonumber(Words[24])
				Races[race].SpcAttack[1].SpellPoints = tonumber(Words[25])
				Races[race].SpcAttack[1].Recovery = tonumber(Words[26])
				Races[race].SpcAttack[1].Bits = tonumber(Words[27])
				Races[race].SpcAttack[1].Cooldown = tonumber(Words[28])
				Races[race].SpcAttack[1].Projectile = tonumber(Words[29])
				Races[race].SpcAttack[1].Sound = tonumber(Words[30])
				Races[race].SpcAttackMelee = Races[race].SpcAttack[0]
				Races[race].SpcAttackRanged = Races[race].SpcAttack[1]
			end
		end
	end

	io.close(TxtTable)

	-- MM7 MMExtension has Game.Races which isn't present in
	--   MM8/Merge MMExtension, so using this name should be safe
	Game.Races = Races
	MT.Races = Races
end

function events.GameInitialized1()
	ProcessRacesTxt()
end

local function get_ability_spells(Skill, Mastery)
	local spells
	if Skill == 21 then
		if Mastery == 1 then
			spells = {100}
		elseif Mastery == 2 then
			spells = {101}
		elseif Mastery == 3 then
			spells = {102}
		elseif Mastery == 4 then
			spells = {103}
		end
	elseif Skill == 22 then
		if Mastery == 1 then
			spells = {111}
		elseif Mastery == 2 then
			spells = {112}
		elseif Mastery == 3 then
			spells = {113}
		elseif Mastery == 4 then
			spells = {114}
		end
	elseif Skill == 23 then
		if Mastery == 1 then
			spells = {122}
		elseif Mastery == 2 then
			spells = {123}
		elseif Mastery == 3 then
			spells = {124}
		elseif Mastery == 4 then
			spells = {125}
		end
	end
	return spells
end
MF.GetAbilitySpells = get_ability_spells

local function get_race_ability_spells(Race, Skill, Mastery, full)
	local spells
	if Game.Races[Race] then
		local start, stop = full and 1 or Mastery, Mastery
		for i = start, stop do
			if Game.Races[Race].Spells[i] then
				for k, v in pairs(Game.Races[Race].Spells[i]) do
					-- FIXME: Use GetSpellSkill or smth
					if v >= (Skill - 12) * 11 and v < (Skill - 11) * 11 then
						spells = spells or {}
						table.insert(spells, v)
					end
				end
			end
		end
	end
	return spells
end
MF.GetRaceAbilitySpells = get_race_ability_spells

MF.LogInit2(LogId)
