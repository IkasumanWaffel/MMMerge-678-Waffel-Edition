-- Merge Settings
local LogId = "MergeSettings"

-- Load user-defined values
-- Use file MMMergeSettings.lua in Game root directory
function LoadUserMergeSettings ()
	local f1 = io.open("MMMergeSettings.lua", "r")
	if not f1 then
		local f2 = io.open("Extra/MMMergeSettings.lua", "r")
		if f2 then
			f1 = io.open("MMMergeSettings.lua", "w")
			local t = f2:read("*a")
			io.close(f2)
			f1:write(t)
			io.close(f1)
		end
	else
		io.close(f1)
	end
	print("Loading user settings from MMMergeSettings.lua")
	local f, errstr = loadfile("MMMergeSettings.lua")
	if f then f() else
		print("Cannot load user settings: " .. errstr)
	end
end

-- Initialize default Merge Settings
local function InitializeMergeSettings()

	-- Initialize tables
	Merge = Merge or {}
	Merge.Consts = {}
	Merge.Functions = {}
	Merge.ModSettings = {}
	Merge.Offsets = {}
	Merge.Settings = {}
	Merge.Tables = {}
	Merge.Vars = {}
	Merge.Settings.Logging = {}
	Merge.Settings.Base = {}
	Merge.Settings.Abuse = {}
	Merge.Settings.Animations = {}
	Merge.Settings.Attack = {}
	Merge.Settings.Character = {}
	Merge.Settings.Conversions = {}
	Merge.Settings.DimensionDoor = {}
	Merge.Settings.Promotions = {}
	Merge.Settings.Races = {}
	Merge.Settings.Skills = {}
	Merge.Settings.Stealing = {}

	-- Set version
	-- Version of the last Rodril's full pack
	Merge.PackVersion = "20231105"
	-- Version of the last Rodril's patch
	Merge.PatchVersion = "20240930"
	-- Version of Merge variant patch. Comment out for Base Merge
	Merge.VariantVersion = "20240129-revamp"
	-- Set version to latest change
	Merge.Version = Merge.VariantVersion or Merge.PatchVersion or Merge.PackVersion
	-- Full version string
	Merge.VersionFull = (Merge.VariantVersion and Merge.VariantVersion .. " based on " or "")
		.. (Merge.PatchVersion and Merge.PatchVersion .. " Patch of " or "")
		.. Merge.PackVersion .. " Pack"
	-- SaveGame compatibility. Raise when SaveGame format is changed.
	-- Version format: YYMMDDxx
	Merge.SaveGameFormatVersion = 23091700

	------------ Logging settings ------------

	-- Log File Name
	-- Note: if you add subdirectory into File Name, you have to create it first
	--Merge.Settings.Logging.LogFile = "Logs/MMMergeLog.txt"
	Merge.Settings.Logging.LogFile = "MMMergeLog.txt"

	-- Number of old Log Files to preserve [default: 2]
	Merge.Settings.Logging.OldLogsCount = 2

	-- Force immediate flush into log file
	--   0 - [default] don't force
	--   1 - force
	Merge.Settings.Logging.ForceFlush = 0

	-- Print times before log messages
	--   0 - [default] disabled
	--   1 - enabled
	Merge.Settings.Logging.PrintTimes = 1

	-- Print CPU times before log messages also, requires Logging.PrintTimes to be enabled
	--   0 - [default] disabled
	--   1 - enabled
	Merge.Settings.Logging.PrintOsClock = 0

	-- Print message source file before log messages
	--   0 - [default] disabled
	--   1 - enabled
	Merge.Settings.Logging.PrintSources = 0

	-- Print traceback of invalid log message formatting
	--   0 - [default] disable
	--   1 - enable
	Merge.Settings.Logging.PrintFormatTraceback = 0

	-- Log Level
	--    0 - disabled
	--    1 - fatal errors
	--    2 - [default] errors
	--    3 - warnings
	--    4 - informational
	--    5 - verbose
	--    6 - debug
	Merge.Settings.Logging.LogLevel = 5

	-- Debug settings (yet to be implemented)
	Merge.Settings.Logging.DebugScope = 0
	Merge.Settings.Logging.DebugFiles = {}

	-------------------------------------------------------
	------------ Default Merge Settings values ------------
	-------------------------------------------------------

	-- 24-hour time format
	--    0 - [default] use 12-hour time format
	--    1 - use 24-hour time format
	Merge.Settings.Time24hFormat = 1

	------------ Animation settings ------------

	-- Skip logo animations at the start of mm8.exe
	--    0 - [default] do not skip
	--    1 - skip all animations
	Merge.Settings.Animations.SkipLogos = 1

	-- Skip new game animations (after continent selection)
	--    0 - [revamp] do not skip animations
	--    1 - [base][comm] skip animations called from already started game
	--    2 - always skip animations
	Merge.Settings.Animations.SkipNewGameIntro = 0

	------------ Attack settings ------------

	-- Minimal delay of Melee Attack
	--    Hardcoded at 30
	Merge.Settings.Attack.MinimalMeleeAttackDelay = 30

	-- Minimal delay of Ranged Attack
	--    [base] value: 30
	--    [community default] value: 5
	--    [mm8] value: 0
	Merge.Settings.Attack.MinimalRangedAttackDelay = 15

	-- Minimal delay of Blaster Attack
	--    [base] value: 5
	--    [community default] value: 5
	--    [mm8] value: 0
	Merge.Settings.Attack.MinimalBlasterAttackDelay = 15

	------------ Character settings ------------

	-- Use enhanced autobiographies
	--    0 - [base] use 'Name - Class' style
	--    1 - [community default] use 'Name, the RaceAdj Class' style
	--    2 - use 'Name - Class (Race)' style
	Merge.Settings.Character.EnhancedAutobiographies = 1

	-- Force Zombie character to be of Undead race during Character creation
	--    0 - [base] don't force
	--    1 - [community default] force
	Merge.Settings.Character.ForceZombieToUndeadRace = 1

	-- Autolearn racial skills
	--   0 - [base] disable
	--   1 - [community default] enable
	Merge.Settings.Character.AutolearnRacialSkills = 1

	------------ Character conversions settings ------------

	-- Do not change character pic to Undead one on Lich Class Promotion
	--    0 - [default] always convert
	--    1 - keep current face pic
	Merge.Settings.Conversions.PreservePicOnLichPromotion = 0

	-- Do not change character voice when his race has been changed
	--    0 - [default] change voice to race default one
	--    1 - keep current voice
	Merge.Settings.Conversions.KeepVoiceOnRaceConversion = 0

	-- Do not change character voice when he was zombified
	--    0 - [default] change voice to race default one
	--    1 - keep current voice
	Merge.Settings.Conversions.KeepVoiceOnZombification = 0

	-- Chance of Zombie race character random zombification (out of 1000)
	--   Mind and Dark resistances and Luck effect reduce this chance
	--   Check is done ~ every 5 minutes
	--   0 disables random zombificaton
	--   [default]: 0
	--   [revamp]: 10
	Merge.Settings.Conversions.ZombieZombificationChance = 10

	------------ Promotions settings ------------

	-- Require Lich Jar for promotion to Master Necromancer
	--    0 - [default] do not require Lich Jar
	--    1 - require Lich Jar once
	--    2 - require Lich Jar for every promotion
	Merge.Settings.Promotions.LichJarForMasterNecromancer = 0

	------------ Races settings ------------

	-- Maximum race maturity
	--    0 - [default] no mature races
	--    1 - one extra level of maturity
	Merge.Settings.Races.MaxMaturity = 0

	------------ Skills settings ------------

	-- Include skill bonus from items in Bow GM damage bonus
	--    0 - [base][mm8] use base skill value
	--    1 - [community default] include skill bonus from items
	-- NOTE: mm8.exe start only; change doesn't work on MMMergeSetting.lua reload
	Merge.Settings.Skills.BowDamageIncludeItemsBonus = 1

	------------ Stealing settings ------------
	-- Duration of ban from shop player has been caught in days
	--   default: 336
	Merge.Settings.Stealing.ShopBanDuration = 28

	-- Base fine for being caught
	--   default: 50
	Merge.Settings.Stealing.BaseFine = 250

	------------ Dimension Door settings ------------
	-- Restrict Dimension Door to already visited and starting maps
	Merge.Settings.DimensionDoor.RestrictMaps = true
	------------ Artifact Stat Bonus Settings ------------
	Merge.Settings.TKPreventDeathFromNegativeEndurance = 1
end

local function LoadModSettings()
	local filename = "Data/Tables/ModSettings.txt"
	local MMS = Merge.ModSettings
	local mst = io.open(filename)
	if mst then
		local strsplit = string.split
		local iter = mst:lines()
		for line in iter do
			if line:byte(1) ~= 35 then	-- "#"
				local words = strsplit(line, "\9")
				local varname = strsplit(words[1], "%.")
				if #varname == 1 then
					MMS[words[1]] = tonumber(words[2]) or words[2]
				elseif #varname == 2 then
					MMS[varname[1]] = MMS[varname[1]] or {}
					MMS[varname[1]][varname[2]] = tonumber(words[2]) or words[2]
				end
			end
		end
		io.close(mst)
	end
end

if not Merge or not Merge.Settings then
	InitializeMergeSettings()
	LoadModSettings()
	LoadUserMergeSettings()
end

-- Put SaveGameFormatVersion into the savegame
function events.BeforeSaveGame()
	vars.SaveGameFormatVersion = Merge.SaveGameFormatVersion
end

function events.BeforeNewGameAutosave()
	vars.SaveGameFormatVersion = Merge.SaveGameFormatVersion
end

-- Compatibility mode check

local function CheckCompatibilityMode()
	local dll = mem.dll["advapi32"]
	if not dll then
		return
	end

	local RegGetValue = dll.RegGetValueA
	if not RegGetValue then
		return
	end

	-- unlike MF.cstring, uses mem.malloc, so memory can be freed afterwards
	local function cstr(str)
		local ptr = mem.malloc(#str + 1)
		mem.copy(ptr, str, #str + 1)
		return ptr
	end

	local toptr = mem.topointer
	local buffSize = 256
	local buff = mem.malloc(buffSize)
	mem.u4[buff] = buffSize - 4

	local HKEY_LOCAL_MACHINE, HKEY_CURRENT_USER = 0x80000002, 0x80000001
	local ERROR_SUCCESS, ERROR_FILE_NOT_FOUND = 0, 2

	local SUBKEY = cstr("Software\\Microsoft\\Windows NT\\CurrentVersion\\AppCompatFlags\\Layers")
	local MM8, MM8Set = cstr(AppPath .. "mm8.exe"), cstr(AppPath .. "MM8Setup.exe")
	local exclude = {"WIN95", "WIN98", "WIN2000"}

	local warning = StrColor(250, 250, 250, "COMPATIBILITY WARNING\n \nCompatibility mode of '%s' is set to ")
		.. StrColor(250, 10, 10, "%s")
		.. StrColor(250, 250, 250, ", it is STRONGLY recommended to set compatibility mode of 'MM8.exe' and 'MM8Setup.exe' to ")
		.. StrColor(10, 250, 10, "Windows XP SP2")
		.. StrColor(250, 250, 250, " or higher.")

	local function check(HKEY, SUBKEY, KEY) -- returns: 0 - key does not exist; 1 - key has invalid value, 2 - key valid; other value are RegGetValue error codes
		local result = RegGetValue(HKEY, SUBKEY, KEY, 0x2, 0, buff+4, buff)
		if result == ERROR_SUCCESS then
			local compat = mem.string(buff+4)
			for _, v in pairs(exclude) do
				if string.find(compat, v) then
					return 1, SUBKEY, v, compat
				end
			end
			return 2, SUBKEY, nil, compat
		elseif result == ERROR_FILE_NOT_FOUND then
			return 0
		else
			return result
		end
		return 2
	end

	local text = ""
	local results = {}
	local Names = {[MM8] = "mm8.exe", [MM8Set] = "MM8Setup.exe"}
	for _, p in pairs({{HKEY_CURRENT_USER, MM8}, {HKEY_CURRENT_USER, MM8Set}, {HKEY_LOCAL_MACHINE, MM8}, {HKEY_LOCAL_MACHINE, MM8Set}}) do
		local result, key, mode, compat = check(p[1], SUBKEY, p[2])
		if result == 1 then
			text = warning:format(Names[p[2]], mode)
		end
		p[3] = result
		p[4] = compat
		table.insert(results, p)
	end

	mem.free(buff)
	mem.free(MM8)
	mem.free(MM8Set)
	return results, text
end

local function warning_append(warn, str)
	if not str or string.len(str) == 0 then return warn end
	if warn and string.len(warn) > 0 then
		warn = warn .. "\n \n" .. str
	else
		warn = str
	end
	return warn
end

local function colored(str)
	return StrColor(0xFF, 0xFF, 0x9C, str)
end

local function check_mm8ini()
	local MF = Merge.Functions
	local str
	local iniconditions, inihooks
	local f = io.open("mm8.ini")
	if not f then
		return "mm8.ini could not be read"
	end

	local iter = f:lines()
	for line in iter do
		if string.match(line, "^ *FixConditionPriorities=0 *") then
			iniconditions = true
		else
			local res = string.match(line, "^ *DisableHooks=(.+) *$")
			if res then
				MF.LogVerbose("DisableHooks: %s", res)
				res = string.lower(res)
				local hks = string.split(res, ",")
				local hk408ECC, hk424ED0
				for k, v in pairs(hks) do
					if v == "408ecc" then
						hk408ECC = true
					elseif v == "424ed0" then
						hk424ED0 = true
					end
				end
				inihooks = hk408ECC and hk424ED0
			end
		end
	end

	if not iniconditions then
		str = warning_append(str, "Option " .. colored("FixConditionPriorities") .. " is not disabled in mm8.ini."
			.. " Wrong player condition will be shown."
			.. " Add " .. colored("FixConditionPriorities=0") .. " to fix.")
		MF.LogError("Add 'FixConditionPriorities=0' to mm8.ini")
	end
	if not inihooks then
		str = warning_append(str, "Hooks ".. colored("408ECC") .. " and " .. colored("424ED0")
			.. " are not disabled in mm8.ini. Monster items could be lost."
			.. " Add " .. colored("DisableHooks=408ECC,424ED0") .. " to fix.")
		MF.LogError("Add 'DisableHooks=408ECC,424ED0' to mm8.ini")
	end

	io.close(f)
	return str
end

function events.GameInitialized2()
	local MF = Merge.Functions
	MF.LogVerbose("%s: GameInitialized2", LogId)
	local _, text = CheckCompatibilityMode()
	if string.find(AppPath:lower(), "program files") then
		text = text .. (#text > 0 and "\n \n" or "") .. ("Game installation path is '%s', it is STRONGLY recommended to install the game outside of 'Program Files' folder."):format(AppPath)
	end

	text = warning_append(text, check_mm8ini())

	if not Game.PatchOptions.FixChests then
		text = warning_append(text, "Option " .. colored("FixChests") .. " is not enabled in mm8.ini."
			.. " Some chest items could be lost."
			.. " Add " .. colored("FixChests=1") .. " to fix.")
		MF.LogError("Add 'FixChests=1' to mm8.ini")
	end

	if #text > 0  then
		--CustomUI.DisplayTooltip(text, 30, 50, 160, 540, Game.CurrentScreen, Game.Create_fnt)
		CustomUI.DisplayTooltip(text, 30, 50, 160, 540, 0, Game.Create_fnt)
	end
end
