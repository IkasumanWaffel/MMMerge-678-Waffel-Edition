-- Allow some classes to swap their alligment at Enroth:
-- Priest of Light to Priest of Dark; Archmage to Master Necromancer; Hero to Villain, Master Archer to Sniper.
local LogId = "EnrothDarkArts"
local Log = Log
Log(Merge.Log.Info, "Init started: %s", LogId)
local MF, MM = Merge.Functions, Merge.ModSettings

----------------------
---- LOCALIZATION ----

local TXT = {

path_light = Game.NPCText[2102], --"Path of Light",
path_dark = Game.NPCText[2103], --"Path of Dark",

warning_light = Game.NPCText[2104], --"Are you sure, you want to change your path? Dark spells will be vanished from your spellbook and dark magic will be erased from your mind. (Yes/No)",
warning_dark = Game.NPCText[2105], --"Are you sure, you want to change your path? Light spells will be vanished from your spellbook and light magic will be erased from your mind. (Yes/No)",

advert_light = Game.NPCText[2106], --"It is never late to turn back to light, child. Choose light side.",
advert_dark = Game.NPCText[2107], --"Darkness wait and it's patience is eternal. Choose dark side.",

--Yes = Game.NPCText[2108], --"yes",

Std = Game.NPCText[2109], --"Either you've already choosen your path, or you are not ready to do it."

path_neutral = Game.NPCText[2780],	-- "Path of Neutrality"
warning_neutral = Game.NPCText[2781]	-- "Are you sure you want to follow the Path of Neutrality? All Dark and Light spells unavailable for Neutral Path will disappear from your spellbook."
}
---- LOCALIZATION ----
----------------------

local LastClick = 0

local CC = const.Class

local DarkPromTable = {
	[CC.BattleMage] = CC.Sniper,
	[CC.MasterArcher] = CC.Sniper,
	[CC.HighPriest] = CC.PriestDark,
	[CC.PriestLight] = CC.PriestDark,
	[CC.MasterDruid] = CC.Warlock,
	[CC.ArchDruid] = CC.Warlock,
	[CC.Champion] = CC.BlackKnight,
	[CC.Templar] = CC.BlackKnight,
	[CC.Justiciar] = CC.Villain,
	[CC.Hero] = CC.Villain,
	[CC.MasterWizard] = CC.MasterNecromancer,
	[CC.ArchMage] = CC.MasterNecromancer
}

local LightPromTable = {
	[CC.BattleMage] = CC.MasterArcher,
	[CC.Sniper] = CC.MasterArcher,
	[CC.HighPriest] = CC.PriestLight,
	[CC.PriestDark] = CC.PriestLight,
	[CC.MasterDruid] = CC.ArchDruid,
	[CC.Warlock] = CC.ArchDruid,
	[CC.Champion] = CC.Templar,
	[CC.BlackKnight] = CC.Templar,
	[CC.Justiciar] = CC.Hero,
	[CC.Villain] = CC.Hero,
	[CC.MasterWizard] = CC.ArchMage,
	[CC.MasterNecromancer] = CC.ArchMage
}

local neutral_promo_table = {
	[CC.MasterArcher] = CC.BattleMage,
	[CC.Sniper] = CC.BattleMage,
	[CC.PriestLight] = CC.HighPriest,
	[CC.PriestDark] = CC.HighPriest,
	[CC.ArchDruid] = CC.MasterDruid,
	[CC.Warlock] = CC.MasterDruid,
	[CC.Templar] = CC.Champion,
	[CC.BlackKnight] = CC.Champion,
	[CC.Hero] = CC.Justiciar,
	[CC.Villain] = CC.Justiciar,
	[CC.ArchMage] = CC.MasterWizard,
	[CC.MasterNecromancer] = CC.MasterWizard
}
if MM.MM6ConvertCleric and MM.MM6ConvertCleric == 1 then
	neutral_promo_table[CC.AcolyteLight] = CC.Cleric
	neutral_promo_table[CC.AcolyteDark] = CC.Cleric
	LightPromTable[CC.Cleric] = CC.AcolyteLight
	LightPromTable[CC.AcolyteDark] = CC.AcolyteLight
	DarkPromTable[CC.Cleric] = CC.AcolyteDark
	DarkPromTable[CC.AcolyteLight] = CC.AcolyteDark
end
if MM.MM6ConvertPriest and MM.MM6ConvertPriest == 1 then
	neutral_promo_table[CC.ClericLight] = CC.Priest
	neutral_promo_table[CC.ClericDark] = CC.Priest
	LightPromTable[CC.Priest] = CC.ClericLight
	LightPromTable[CC.ClericDark] = CC.ClericLight
	DarkPromTable[CC.Priest] = CC.ClericDark
	DarkPromTable[CC.ClericLight] = CC.ClericDark
end
if MM.MM6ConvertSorcerer and MM.MM6ConvertSorcerer == 1 then
	neutral_promo_table[CC.ApprenticeMage] = CC.Sorcerer
	neutral_promo_table[CC.DarkAdept] = CC.Sorcerer
	LightPromTable[CC.Sorcerer] = CC.ApprenticeMage
	LightPromTable[CC.DarkAdept] = CC.ApprenticeMage
	DarkPromTable[CC.Sorcerer] = CC.DarkAdept
	DarkPromTable[CC.ApprenticeMage] = CC.DarkAdept
end
if MM.MM6ConvertWizard and MM.MM6ConvertWizard == 1 then
	neutral_promo_table[CC.Mage] = CC.Wizard
	neutral_promo_table[CC.Necromancer] = CC.Wizard
	LightPromTable[CC.Wizard] = CC.Mage
	LightPromTable[CC.Necromancer] = CC.Mage
	DarkPromTable[CC.Wizard] = CC.Necromancer
	DarkPromTable[CC.Mage] = CC.Necromancer
end

local path_conv_table = {
	light = LightPromTable,
	dark = DarkPromTable,
	neutral = neutral_promo_table
}

-- MMMWE: custom classes switch between their own second promotions
-- (steps: 3 neutral, 4 light, 5 dark), from the other second promotions only, as the preset ones do
local custom_path_step = {light = 4, dark = 5, neutral = 3}

local function change_custom_alignment(dest, player)
	local CCL = MF.CustomClasses
	local f, step = CCL.FamilyOf(player.Class)
	local to_step = custom_path_step[dest]
	if f and step >= 3 and step ~= to_step and to_step and CCL.Promote(player, to_step) then
		MF.ShowAwardAnimation(71)
	else
		Message(TXT.Std)
		player:ShowFaceAnimation(67)
	end
end

local function change_alignment(dest)
	local slot = MF.GetCurrentPlayer() or 0
	local player = Party[slot]
	if MF.IsCustomClass and MF.IsCustomClass(player.Class) and MF.CustomClasses then
		return change_custom_alignment(dest, player)
	end
	local to_class = path_conv_table[dest] and path_conv_table[dest][player.Class]
	if to_class then
		MF.ConvertCharacter({Player = player, ToClass = to_class})
		MF.ShowAwardAnimation(71)
	else
		Message(TXT.Std)
		player:ShowFaceAnimation(67)
	end
end

local function generate_path_quests(t)
	QuestNPC = t.QuestNPC
	Quest{
		Name = t.Name .. "Path",
		Branch = "",
		Slot = t.Slot,
		CanShow = t.QBit and function() return Party.QBits[t.QBit] end,
		Ungive = function() QuestBranch("path") end,
		Texts = {
			Topic = TXT["path_" .. t.Dest],
			Ungive = TXT["warning_" .. t.Dest]
		}
	}
	Quest{
		Name = t.Name .. "PathY",
		Branch = "path",
		Slot = 0,
		Ungive = function()
			change_alignment(t.Dest)
			QuestBranch("")
		end,
		Texts = {
			Topic = Game.GlobalTxt[704]	-- "Yes"
		}
	}
	Quest{
		Name = t.Name .. "PathN",
		Branch = "path",
		Slot = 1,
		Ungive = function() QuestBranch("") end,
		Texts = {
			Topic = Game.GlobalTxt[705],	-- "No"
			Ungive = TXT["advert_" .. t.Dest]
		}
	}
	Quest{
		Name = t.Name .. "Path2",
		Branch = "path",
		Slot = 2
	}
	Quest{
		Name = t.Name .. "Path3",
		Branch = "path",
		Slot = 3
	}
end

-- Dark
-- Su Lang Manchu
generate_path_quests({QuestNPC = 1040, Name = "SuLangManchu", Slot = 4, Dest = "dark"})
-- Rebecca Calaway
generate_path_quests({QuestNPC = 1030, Name = "RebeccaCalaway", Slot = 4, Dest = "dark"})
-- Rachel Herzl
--generate_path_quests({QuestNPC = 1048, Name = "RachelHerzl", Slot = 4, Dest = "dark"})

-- Light
-- Ki Lo Nee
generate_path_quests({QuestNPC = 1057, Name = "KiLoNee", Slot = 4, Dest = "light"})
-- Virginia Standridge
generate_path_quests({QuestNPC = 1031, Name = "VirginiaStandridge", Slot = 4, Dest = "light"})
-- Marton Ferris
generate_path_quests({QuestNPC = 795, Name = "MartonFerris", Slot = 4, Dest = "light"})

-- Neutral
-- Sharry Carnegie
generate_path_quests({QuestNPC = 978, Name = "SharryCarnegie", Slot = 2, QBit = 1284, Dest = "neutral"})

Log(Merge.Log.Info, "Init finished: %s", LogId)

