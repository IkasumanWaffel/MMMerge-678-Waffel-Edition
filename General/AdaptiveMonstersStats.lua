local LogId = "AdaptiveMonstersStats"
local MF = Merge.Functions
MF.LogInit1(LogId)
local max, min, ceil, floor, random, sqrt = math.max, math.min, math.ceil, math.floor, math.random, math.sqrt
local ReadyMons, ReadySpcMons = {}, {}
local MonBolStep = {}
local MT, MV = Merge.Tables, Merge.Vars
local TxtLocalized = false

Game.Bolster = {}

-----------------------------------------------
--	Constants

const.Bolster = {}

const.Bolster.Types = {
	NoBolster 		= 0,
	OriginalStats	= 1,
	LowerToEqual	= 2,
	AllToEqual		= 3
}

const.MonsterKind = {
	Undead = 1,
	Dragon = 2,
	Swimmer = 3,
	Immobile = 4,
	Peasant = 5,
	NoArena = 6,
	Ogre = 7,
	Elemental = 8,
	Demon = 9,
	Titan = 10,
	Elf = 11,
	Goblin = 12,
	Dwarf = 13,
	Human = 14
}

const.Bolster.MonsterType = {
	Unknown		= 0,
	Undead 		= 1,
	Dragon 		= 2,
	Swimmer		= 3,
	Immobile	= 4,
	Peasant		= 5,
	NoArena		= 6,
	Ogre		= 7,
	Elemental	= 8,
	Demon 		= 9,
	Titan 		= 10,
	Elf 		= 11,
	Goblin		= 12,
	Dwarf		= 13,
	Human		= 14,
	DarkElf		= 15,
	Lizardman	= 16,
	Minotaur	= 17,
	Troll		= 18,
	Creature	= 19,
	Construct	= 20
	}

const.Bolster.Creed = {
	Neutral	= 0,
	Light 	= 1,
	Dark 	= 2,
	Peasant = 3	-- for hireable creatures
	}

const.Bolster.Magic = {
	Any		= 0,
	Fire	= 1,
	Air		= 2,
	Water	= 3,
	Earth	= 4,
	Spirit	= 5,
	Mind	= 6,
	Body	= 7,
	Light	= 8,
	Dark	= 9,
	Self	= 10,
	Elemental = 11
	}

const.Bolster.Style = {
	Strength	= 0,
	Endurance 	= 1,
	Speed 		= 2,
	Magic		= 3,
	Wimpy		= 4
	}

-----------------------------------------------
-- Text tables processing

local function ProcessBolsterTxt()

	local Warning = ""

	local function GetProp(Val, Type, i)
		local result = tonumber(Val) or const.Bolster[Type][Val] or 0
		if not result then
			result = 0
			Warning = Warning .. "Undefined property, line: " .. i .. ", type: " .. Type .. "\n"
		end
		return result
	end

	---- Monsters:

	Game.Bolster.Monsters = {}

	local Bolster = Game.Bolster.Monsters
	local BolsterTxt = io.open("Data/Tables/Bolster - monsters.txt", "r")

	if not BolsterTxt then
		BolsterTxt = io.open("Data/Tables/Bolster - monsters.txt", "w")
		BolsterTxt:write("#	Note	Type	ExtraType	Creed	Style	Pref magic	NoArena	Allow ranged attacks	Allow spells	HP by size	Allow replicate	Allow summons	Summon Id	Extra points	Max HP Boost (%)\n")
		for i,v in Game.MonstersTxt do
			BolsterTxt:write(i .. "\9" .. v.Name .. "\9\9\9\9\9\9-\9-\9-\9-\9-\9-\9\9\n")
			Bolster[i] = {Type = 0, Creed = 0, Style = 0, PrefMagic = 0, Ranged = false, Spells = false, HPBySize = false, Summons = false, SummonId = 0, LevelShift = 0}
		end
	else
		local LineIt = BolsterTxt:lines()
		LineIt() -- skip header

		for line in LineIt do
			local Words = string.split(line, "\9")
			local CurId = tonumber(Words[1]) or 0
			Bolster[CurId] = {
				Type 		= GetProp(Words[3], "MonsterType", CurId),
				ExtraType 	= {},
				Creed 		= GetProp(Words[5], "Creed", CurId),
				Gender 		= Words[6] == "F" and 2 or (Words[6] == "M" and 1 or 0),
				Style	 	= GetProp(Words[7], "Style", CurId),
				Magic 		= GetProp(Words[8], "Magic", CurId),
				NoArena 	= Words[9]  == "x",
				Ranged 		= Words[10] == "x",
				Spells 		= Words[11] == "x",
				HPBySize	= Words[12] == "x",
				Replicate	= Words[13] == "x",
				Summons 	= Words[14] == "x",
				SummonId 	= tonumber(Words[15]) or 0,
				LevelShift 	= tonumber(Words[16]) or 0,
				MaxHPBoost	= (tonumber(Words[17]) or 300)/100}
			local types = string.split(Words[4], ",")
			for _, v in pairs(types) do
				local mon_type = GetProp(v, "MonsterType", CurId)
				if mon_type and mon_type > 0 then
					table.insert(Bolster[CurId].ExtraType, mon_type)
				end
			end
		end

		if string.len(Warning) > 0 then
			Warning = 'Errors in "Bolster - monsters.txt":\n'
			debug.Message(Warning)
		end
	end

	BolsterTxt:close()

	---- Per-map restrictions:

	Game.Bolster.Maps = {}
	Game.Bolster.MapsSource = {}

	Bolster = Game.Bolster.Maps
	BolsterTxt = io.open("Data/Tables/Bolster - maps.txt", "r")

	if not BolsterTxt then
		BolsterTxt = io.open("Data/Tables/Bolster - maps.txt", "w")
		BolsterTxt:write("#	Note	Continent	Bolster kind	Spells	Summons	Level shift\n")
		for i,v in Game.MapStats do
			BolsterTxt:write(i .. "\9" .. v.Name .. "\9\9NoBolster\9-\9-\9-\9\9\n")
			Bolster[i] = {Continent = 1, Type = 0, Spells = false, Summons = false, Weather = false, LevelShift = 0, CustomSky = false}
		end
	else
		local LineIt = BolsterTxt:lines()
		LineIt() -- skip header

		for line in LineIt do
			local Words = string.split(line, "\9")
			local CurId = tonumber(Words[1]) or 0
			Bolster[CurId] = {
				Continent	= tonumber(Words[3]) or 1,
				Type 		= GetProp(Words[4], "Types", CurId),
				Spells 		= Words[5] == "x",
				Summons	 	= Words[6] == "x",
				Weather	 	= Words[7] == "x",
				LevelShift	= tonumber(Words[8]) or 0,
				CustomSky 	= string.len(Words[10]) > 0 and Words[10] or false,
				ProfsMaxRarity = tonumber(Words[9]) or 0}

			Game.Bolster.MapsSource[CurId] = table.copy(Bolster[CurId])
		end

		if string.len(Warning) > 0 then
			Warning = 'Errors in "Bolster - monsters.txt":\n'
			debug.Message(Warning)
		end
	end

	BolsterTxt:close()

	----

	Game.Bolster.MonstersSource = Game.Bolster.Monsters

	---- Formulas:

	Game.Bolster.Formulas = {}
	Bolster = Game.Bolster.Formulas
	BolsterTxt = io.open("Data/Tables/Bolster - formulas.txt", "r")

	if BolsterTxt then
		local LineIt = BolsterTxt:lines()
		LineIt() -- skip header

		for line in LineIt do
			local Words = string.split(line, "\9")
			if Words[1] and Words[2] and Words[3] and string.len(Words[1]) > 0 and string.len(Words[2]) > 0 then
				local CurId = tonumber(Words[1]) or Words[1]
				local str
				Bolster[CurId] = Bolster[CurId] or {}

				if string.len(Words[3]) == 0 then
					str = "return false"
				elseif string.find(Words[3], "return") then
					str = Words[3]
				else
					str = "return " .. Words[3]
				end

				Bolster[CurId][Words[2]] = assert(loadstring(str))
			end
		end
		BolsterTxt:close()
	end

	---- Special Monsters
	MT.SpcMonstersTxt = {}
	Game.Bolster.SpcMonsters = {}
	BolsterTxt = io.open("Data/Tables/Bolster-SpcMonsters.txt", "r")

	if BolsterTxt then
		local LineIt = BolsterTxt:lines()
		LineIt() -- skip header

		for line in LineIt do
			local Words = string.split(line, "\9")
			if Words[1] and tonumber(Words[1]) then
				local idx = tonumber(Words[1])
				MT.SpcMonstersTxt[idx] = {}
				local t = MT.SpcMonstersTxt[idx]
				t.Level = tonumber(Words[3]) or 1
				t.FullHP = tonumber(Words[4]) or 3
				t.ArmorClass = tonumber(Words[5]) or 0
				t.Experience = tonumber(Words[6]) or 11
				t.MoveSpeed = tonumber(Words[7]) or 140
				t.Attack1 = {}
				t.Attack1.Type = tonumber(Words[8]) or 4	-- Phys
				t.Attack1.DamageDiceCount = tonumber(Words[9]) or 2
				t.Attack1.DamageDiceSides = tonumber(Words[10]) or 2
				t.Attack1.DamageAdd = tonumber(Words[11]) or 2
				t.Attack1.Missile = tonumber(Words[12]) or 0
				t.Attack2Chance = tonumber(Words[13]) or 0
				t.Attack2 = {}
				t.Attack2.Type = tonumber(Words[14]) or 4
				t.Attack2.DamageDiceCount = tonumber(Words[15]) or 2
				t.Attack2.DamageDiceSides = tonumber(Words[16]) or 2
				t.Attack2.DamageAdd = tonumber(Words[17]) or 2
				t.Attack2.Missile = tonumber(Words[18]) or 0
				t.Spell = tonumber(Words[19]) or 0
				t.SpellChance = tonumber(Words[20]) or 0
				t.SpellSkill = tonumber(Words[21]) or 1
				t.Spell2 = tonumber(Words[22]) or 0
				t.Spell2Chance = tonumber(Words[23]) or 0
				t.Spell2Skill = tonumber(Words[24]) or 1
				t.Bonus = tonumber(Words[25]) or 0
				t.BonusMul = tonumber(Words[26]) or 1
				t.Special = tonumber(Words[27]) or 0
				t.SpecialA = tonumber(Words[28]) or 0
				t.SpecialB = tonumber(Words[29]) or 0
				t.SpecialC = tonumber(Words[30]) or 0
				t.SpecialD = tonumber(Words[31]) or 0
				t.FireResistance = tonumber(Words[32]) or 0
				t.AirResistance = tonumber(Words[33]) or 0
				t.WaterResistance = tonumber(Words[34]) or 0
				t.EarthResistance = tonumber(Words[35]) or 0
				t.SpiritResistance = tonumber(Words[36]) or 0
				t.MindResistance = tonumber(Words[37]) or 0
				t.BodyResistance = tonumber(Words[38]) or 0
				t.LightResistance = tonumber(Words[39]) or 0
				t.DarkResistance = tonumber(Words[40]) or 0
				t.PhysResistance = tonumber(Words[41]) or 0
				t.TreasureItemPercent = tonumber(Words[42]) or 100
				t.TreasureItemType = tonumber(Words[43]) or 0
				t.TreasureItemLevel = tonumber(Words[44]) or 0
				if Words[45] and Words[45] ~= "" then
					t.TreasureDiceCount, t.TreasureDiceSides = Words[45]:match("(%d+)[dD](%d+)")
					t.TreasureDiceCount = tonumber(t.TreasureDiceCount) or 0
					t.TreasureDiceSides = tonumber(t.TreasureDiceSides) or 0
				end
			end
		end
		BolsterTxt:close()
	end
	
	---- Map Monsters
	MT.MapMonstersTxt = {}
	BolsterTxt = io.open("Data/Tables/Bolster-MapMonsters.txt", "r")

	if BolsterTxt then
		local LineIt = BolsterTxt:lines()
		LineIt() -- skip header

		for line in LineIt do
			local Words = string.split(line, "\t")
			if Words[1] and tonumber(Words[1]) then
				-- FIXME: check NameId
				local map_id = tonumber(Words[2])
				local idx = tonumber(Words[4])
				MT.MapMonstersTxt[map_id] = MT.MapMonstersTxt[map_id] or {}
				MT.MapMonstersTxt[map_id][idx] = tonumber(Words[6])
			end
		end
	end
end

MF.GetMonsterKindSex = function(mon_kind, expanded)
	local res = Game.Bolster.Monsters and Game.Bolster.Monsters[mon_kind]
		and Game.Bolster.Monsters[mon_kind].Gender or 0
	if not expanded then
		res = max(0, res - 1)
	end
	return res
end

local SpellReplace = {[81] = 87}

local OffensiveSpells = {
{2,6,11},		-- fire
{15,18},		-- air
{24,26,29,32},	-- water
{39,41},		-- earth
{46,47,51,59},	-- spirit
{59,65},		-- mind
{68,70,76},		-- body
{78,87},		-- light
{90,93,95}		-- dark
}

local DefensiveSpells = {
{5},			-- fire
{17},			-- air
{26},			-- water
{38},			-- earth
{46,47,51,52},	-- spirit
{59,65},		-- mind
{68,71,77},		-- body
{86},			-- light
{95}			-- dark
}

local HPMulByStyle 		= {[0] = 1, 1.3, 0.9, 0.7, 0.5}
local DamageMulByStyle 	= {[0] = 1.5, 1, 1.2, 1, 1}
local BolsterTypes = const.Bolster.Types

-----------------------------------------------
-- Service

local function GetOverallPartyLevel()
	--local Ov, Cnt = 0, 1
	--for i,v in Party do
	--	Ov = Ov + v.LevelBase
	--	Cnt = i + 1
	--end
	--
	--local t = {Result = ceil(Ov/Cnt)}
	local Fame = Party:GetFame()
	local Cnt = sqrt(Party.Count)
	local t = {Result = ceil((50+sqrt(2500+20*Fame*250*Cnt))/100)}
	events.Call("CalcBolsterLevel", t)

	return t.Result
end

local function GetOverallItemBonus() -- approximate equipped items costs as their power
	local result = 0
	for ip,player in Party do
		for i,v in player.EquippedItems do
			if v > 0 then
				result = result + player.Items[v]:GetValue()
			end
		end
	end
	return result
end

local function SetAttackMaxDamage(Attack, MaxDamage)
	MaxDamage = ceil(MaxDamage)

	local Dices, Sides
	local FixDamage = MaxDamage * random(1,3)/10

	MaxDamage = MaxDamage - FixDamage
	Dices = sqrt(MaxDamage)
	Sides = Dices + random(ceil(sqrt(Dices)))

	Attack.DamageAdd 		= FixDamage
	Attack.DamageDiceSides 	= Sides
	Attack.DamageDiceCount 	= Dices
end

local function GenMonSpell(MonSettings, BolStep, SpellNum, OtherSpell)

	local Magic, Creed, Style, Ranged = MonSettings.Magic, MonSettings.Creed, MonSettings.Style, MonSettings.Ranged
	local NoSpell = SpellNum == 2 and (Style == 0 or Style == 2) or Style == 4

	if NoSpell then
		return 0
	end

	local School, Spell
	if Magic == 0 then
		School = random(1,9)
	elseif Magic < 10 then
		School = Magic
	elseif Magic == 10 then
		School = random(5,7)
	elseif Magic == 11 then
		School = random(1,4)
	end

	-- Light mages always have one offensive spell and one defensive spell.
	-- Dark mages always have two offensive spells.
	-- Strength monsters have one offensive or defensive spell according to ability to use ranged attacks.
	-- Endurance monsters have two defensive spells.
	-- Speed monsters have one defensive spell.

	local IsOffensive =
					(Creed == 2 and Style == 3)
				or 	(Creed ~= 2 and Style == 3 and SpellNum == 0)
				or 	(Style == 0 and SpellNum == 0)

	local SpellSet
	if IsOffensive then
		SpellSet = OffensiveSpells[School]
	else
		SpellSet = DefensiveSpells[School]
	end

	Spell = min(#SpellSet, BolStep + SpellNum)
	Spell = SpellSet[random(1,Spell)]

	if OtherSpell and OtherSpell == Spell then
		Spell = DefensiveSpells[School][1]
		if OtherSpell == Spell then
			Spell = 0
		end
	end

	return Spell

end

local function GetMaxDamage(Attack)
	return Attack.DamageDiceCount*Attack.DamageDiceSides+Attack.DamageAdd
end
local function clamp(v, low, high)
	return min(max(v, low), high)
end

local function GetAvgMonLevel(MonsterIndex)
	local MonsterKind = ceil(MonsterIndex/3)
	local result = 0
	for p = 0, 2 do
		result = result + Game.MonstersTxt[MonsterKind*3-p].Level + Game.Bolster.Monsters[MonsterKind*3-p].LevelShift
	end
	result = max(ceil(result/3), 3)

	local shift = ceil(result * (1 - Game.BolsterAmount / 100))
	result = clamp(result + shift, 3, result + 25)
	return result
end

-----------------------------------------------
--	Multipliers

local Multipliers = {
	HP = 1.1,
	AC = 1.1,
	MaxDamage = 1.1,
	PlayerAC = 1,
	MoveSpeed = 1.1,
}

local function ApplyMultiplier(Field, Old, New)
	local mul = Multipliers[Field]
	if not mul then
		return New
	end
	local Diff = New - Old
	return Old + Diff * mul
end

function events.NeedRebolster(t)
	local old = vars.BolsterMultipliers
	if not old then
		vars.BolsterMultipliers = table.copy(Multipliers)
		t.Need = true
	else
		for k, v in pairs(Multipliers) do
			if v ~= old[k] then
				t.Need = true
				old[k] = v
			end
		end
	end
end

function events.BeforeSaveGame()
	vars.BolsterMultipliers = table.copy(Multipliers)
end

function events.LoadMapScripts(WasInGame)
	if not WasInGame and vars.BolsterMultipliers then
		for k,v in pairs(vars.BolsterMultipliers) do
			Multipliers[k] = v
		end
	end
end

local function SimpleText(Screen, Text, X, Y, Font, Condition, Action, AlignLeft, Layer)
	if AlignLeft == nil then
		AlignLeft = true
	end

	return CustomUI.CreateText{
		Text = Text,
		Font = Font or Game.Arrus_fnt,
		X = X, Y = Y,
		ColorStd = 0xFFFF,
		ColorMouseOver = Action and 0xe664 or 0xFFFF,
		Layer = Layer or 1,
		Screen = Screen,
		AlignLeft = AlignLeft,
		Condition = Condition,
		Action = Action
	}
end

local function CustomNumeric(Screen, X, Y, Condition, Header, Parent, Field, Step, Low, High)
	local Option = {ValueSource = {Parent = Parent, Field = Field}, Step = Step, Low = Low, High = High}

	local function Handler(self, side)
		local src = self.ValueSource
		local val = src.Parent[src.Field] + self.Step * side

		val = math.max(val, self.Low)
		val = math.min(val, self.High)
		val = math.round(val * 100) / 100

		src.Parent[src.Field] = val
		self.Value.Text = " " .. tostring(val)
		self.Value:UpdateSize()
	end

	local function Update(self)
		local src = self.ValueSource
		local val = src.Parent[src.Field]
		val = math.round(val * 100) / 100
		self.Value.Text = " " .. tostring(val)
	end

	Option.Header = SimpleText(Screen, Header, X, Y, nil, Condition)

	Option.Left = SimpleText(Screen, "<",
		X + Option.Header.Wt, Y, nil, Condition, function() Handler(Option, -1) end, false)

	Option.Value = SimpleText(Screen, " " .. tostring(Parent[Field]),
		Option.Left.X + Option.Left.Wt + 16, Y, nil, Condition, nil, false)

	Option.Right = SimpleText(Screen, ">",
		Option.Value.X + Option.Value.Wt + 16, Y, nil, Condition, function() Handler(Option, 1) end, false)

	Option.Update = Update

	return Option
end

function events.GameInitialized2()
	local ScreenId = CustomUI.NewSettingsPage("BolsterFineTuning", "Bolster multipliers", "ExSetScr2")
	local Elements = {}
	local function regulator(Y, Header, Field)
		Elements[#Elements + 1] = CustomNumeric(ScreenId, 120, Y, nil,
			StrColor(255,255,150) .. Header .. StrColor(255,255,255),
			Multipliers, Field, 0.05, 0.05, 5)
	end
	regulator(190, "Health points ", "HP")
	regulator(220, "Armor class   ", "AC")
	regulator(250, "Damage        ", "MaxDamage")
	regulator(280, "Hit chance    ", "PlayerAC")
	regulator(310, "Movement speed", "MoveSpeed")

	function events.OpenExtraSettingsMenu()
		for _, v in pairs(Elements) do
			if v.Update then
				v:Update()
			end
		end
	end
end

-----------------------------------------------
--	Rebolster without map reload

local MonTxtDumpFields = "FullHP,ArmorClass,MoveSpeed,Attack2Chance,Spell,Spell2,SpellChance,SpellSkill,Spell2Chance,Spell2Skill,SpecialA,SpecialB,SpecialC,SpecialD,Experience,TreasureItemPercent,TreasureItemLevel,Level"
MonTxtDumpFields = MonTxtDumpFields:split(",")

local monsters_txt_dump

local function dump_monsters_txt()
	local fields = MonTxtDumpFields

	local result = {}
	for i,txtmon in Game.MonstersTxt do
		local t = {}
		result[i] = t
		for fi, field in ipairs(fields) do
			t[fi] = txtmon[field]
		end

		t.Attack1 = mem.string(txtmon.Attack1["?ptr"], txtmon.Attack1["?size"], true)
		t.Attack2 = mem.string(txtmon.Attack2["?ptr"], txtmon.Attack2["?size"], true)
	end
	return result
end
Game.Bolster.DumpMonstersTxt = dump_monsters_txt

local function load_monsters_txt(data)
	local fields = MonTxtDumpFields

	for monid, t in pairs(data) do
		local txtmon = Game.MonstersTxt[monid]
		for fi, field in ipairs(fields) do
			txtmon[field] = t[fi]
		end
		mem.copy(txtmon.Attack1["?ptr"], t.Attack1)
		mem.copy(txtmon.Attack2["?ptr"], t.Attack2)
	end
end
Game.Bolster.LoadMonstersTxt = load_monsters_txt

function events.LoadMapScripts()
	monsters_txt_dump = dump_monsters_txt()
end

local function ReBolsterMonsters()
	table.clear(ReadyMons)
	table.clear(ReadySpcMons)
	load_monsters_txt(monsters_txt_dump)
	Game.BolsterMonsters()
end
Game.ReBolsterMonsters = ReBolsterMonsters

function events.ExitExtraSettingsMenu()
	vars.ExtraSettings = vars.ExtraSettings or {}
	local ExSet = vars.ExtraSettings

	local t = {Need = vars.ExtraSettings.BolsterAmount ~= Game.BolsterAmount or Game.UseMonsterBolster ~= ExSet.UseMonsterBolster}
	events.Call("NeedRebolster", t)
	if t.Need then
		Game.ReBolsterMonsters()
		ExSet.BolsterAmount = Game.BolsterAmount
		ExSet.UseMonsterBolster = Game.UseMonsterBolster
	end
end

-----------------------------------------------
-- Helpers
local spc_add_fields = {"Bonus","BonusMul","Special","FireResistance","AirResistance",
	"WaterResistance","EarthResistance","SpiritResistance","MindResistance",
	"BodyResistance","LightResistance","DarkResistance","PhysResistance",
	"TreasureItemType","TreasureDiceCount","TreasureDiceSides"}

local attack_fields = {"Type", "Missile", "DamageDiceCount", "DamageDiceSides", "DamageAdd"}

local function copy_spc_monsters_txt(id)
	Game.Bolster.SpcMonsters[id] = Game.Bolster.SpcMonsters[id] or {}
	local src = MT.SpcMonstersTxt[id]
	local dst = Game.Bolster.SpcMonsters[id]
	dst.Attack1 = dst.Attack1 or {}
	dst.Attack2 = dst.Attack2 or {}
	for _, v in pairs(MonTxtDumpFields) do
		dst[v] = src[v]
	end
	for k, v in pairs(src.Attack1) do
		dst.Attack1[k] = v
	end
	for k, v in pairs(src.Attack2) do
		dst.Attack2[k] = v
	end
	for _, v in pairs(spc_add_fields) do
		dst[v] = src[v]
	end
end

local function copy_monsters_txt(idx)
	MT.MonstersTxt[idx] = {}
	local src = Game.MonstersTxt[idx]
	local dst = MT.MonstersTxt[idx]
	dst.Attack1 = dst.Attack1 or {}
	dst.Attack2 = dst.Attack2 or {}
	for _, v in pairs(MonTxtDumpFields) do
		dst[v] = src[v]
	end
	for _, v in pairs(attack_fields) do
		dst.Attack1[v] = src.Attack1[v]
		dst.Attack2[v] = src.Attack2[v]
	end
	for _, v in pairs(spc_add_fields) do
		dst[v] = src[v]
	end
end

local function restore_monsters_txt(idx)
	local src = MT.MonstersTxt[idx]
	local dst = Game.MonstersTxt[idx]
	if not src then
		return
	end
	for _, v in pairs(MonTxtDumpFields) do
		dst[v] = src[v]
	end
	for _, v in pairs(attack_fields) do
		dst.Attack1[v] = src.Attack1[v]
		dst.Attack2[v] = src.Attack2[v]
	end
	for _, v in pairs(spc_add_fields) do
		dst[v] = src[v]
	end
end

local function is_special_monster(map_id, mon_idx)
	return MT.MapMonstersTxt and MT.MapMonstersTxt[map_id]
		and MT.MapMonstersTxt[map_id][mon_idx]
end

-----------------------------------------------
-- Bolstering

local LastFormulaEnv = {
	max	= max,
	min	= min,
	ceil = ceil,
	floor = floor,
	sqrt = sqrt,
	random = random,
	abs = math.abs,
	clamp = clamp
}

local function PrepareMapMon(mon, MapSettings, SpcMonId)

	local t = {TxtId = mon.Id, Id = mon:GetIndex(), Monster = mon, Handled = false}
	events.Call("BeforeMonsterBolster", t)

	if t.Handled then
		return
	end

	MF.LogVerbose("PrepareMapMon: %s, %s, %s", t.Id, mon.Id, SpcMonId)

	local TxtMon		= SpcMonId
		and (Game.Bolster.SpcMonsters[SpcMonId]
			or MT.SpcMonstersTxt[SpcMonId])
		or Game.MonstersTxt[mon.Id]
	local MonSettings	= Game.Bolster.Monsters[mon.Id]
	local BolStep		= MonBolStep[mon.Id]

	-- Base stats

	if mon.HP > 0 then
		mon.HP = max(floor(TxtMon.FullHP * mon.HP/mon.FullHP), 1)
	end
	mon.FullHP = TxtMon.FullHP

	mon.ArmorClass = TxtMon.ArmorClass
	mon.MoveSpeed = TxtMon.MoveSpeed
	mon.Velocity = mon.MoveSpeed

	-- Attacks

	mon.Attack1.DamageAdd 		= TxtMon.Attack1.DamageAdd
	mon.Attack1.DamageDiceSides = TxtMon.Attack1.DamageDiceSides
	mon.Attack1.DamageDiceCount = TxtMon.Attack1.DamageDiceCount

	mon.Attack2.DamageAdd 		= TxtMon.Attack2.DamageAdd
	mon.Attack2.DamageDiceSides = TxtMon.Attack2.DamageDiceSides
	mon.Attack2.DamageDiceCount = TxtMon.Attack2.DamageDiceCount

	mon.Attack2Chance 			= TxtMon.Attack2Chance
	mon.Attack2.Missile 		= TxtMon.Attack2.Missile
	mon.Attack2.Type 			= TxtMon.Attack2.Type

	-- Spells
	-- Monsters can not cast paralyze, replace it:
	mon.Spell = SpellReplace[mon.Spell] or mon.Spell
	mon.Spell2 = SpellReplace[mon.Spell2] or mon.Spell2

	local NeedSpells = BolStep and MapSettings.Spells and MonSettings.Spells
	if mon.SpellChance > 0 and mon.Spell == 0 and NeedSpells then
		mon.Spell = GenMonSpell(MonSettings, BolStep, 0)
	end
	mon.SpellChance		= TxtMon.SpellChance
	mon.SpellSkill 		= TxtMon.SpellSkill

	if mon.Spell2Chance > 0 and mon.Spell2 == 0 and NeedSpells then
		mon.Spell2 = GenMonSpell(MonSettings, BolStep, 1, mon.Spell)
	end
	mon.Spell2Chance	= TxtMon.Spell2Chance
	mon.Spell2Skill 	= TxtMon.Spell2Skill

	-- Summons

	mon.Special 	= TxtMon.Special
	mon.SpecialA 	= TxtMon.SpecialA
	mon.SpecialB 	= TxtMon.SpecialB
	if mon.Special == 3 then
		mon.SpecialC = TxtMon.SpecialC
	end
	mon.SpecialD 	= TxtMon.SpecialD

	-- Rewards

	mon.Experience = TxtMon.Experience
	mon.TreasureItemPercent = TxtMon.TreasureItemPercent
	mon.TreasureItemLevel	= TxtMon.TreasureItemLevel

	mon.Level = TxtMon.Level

end

-- FIXME: change "i"
local function PrepareTxtMon(i, PartyLevel, MapSettings, OnlyThis, SpcMonId)
	if not Game.UseMonsterBolster or not TxtLocalized or PartyLevel < 0 or MapSettings.Type == 0 then
		return
	end

	local ftype
	if SpcMonId then
		ftype = "spc"
		copy_spc_monsters_txt(SpcMonId)
	end
	MF.LogVerbose("PrepareTxtMon: %s, %s, %s, %s", i, PartyLevel, OnlyThis, SpcMonId)
	if type(i) == "table" then
		MF.LogVerbose(" i: " .. table.concat(i, ","))
	end

	local t = {TxtId = i, Id = nil, Handled = false}
	events.Call("BeforeMonsterBolster", t)

	if t.Handled then
		return
	end

	-- formulas variables
	local MonsterLevel,TotalEquipCost,HP,BoostedHP,AC,MonsterHeight,MaxDamage,SpellSkill,SpellMastery,BolsterMul,MonsterPower,MonSettings,MoveSpeed
	--

	local BolStep, MonTable, MonKind
	local TotalEquipCost = GetOverallItemBonus()
	local MonsSettings = Game.Bolster.Monsters
	local BolsterMul = Game.BolsterAmount/100
	local Formulas = Game.Bolster.Formulas

	local env = LastFormulaEnv

	local function ProcessFormula(MonKind, Field, Default, FType)
		local Formula
		local set
		local fdomain
		local res = Default
		if FType == "spc" then
			fdomain = "spc"
			set = Formulas["spc"..MonKind]
		elseif FType == "sum" then
			fdomain = "sum"
			set = Formulas["sum"..MonKind]
		else
			fdomain = "def"
			set = Formulas[MonKind]
		end
		if set and set[Field] then
			Formula = set[Field]
		else
			Formula = Formulas[fdomain] and Formulas[fdomain][Field]
		end
		if not Formula then
			Formula = Formulas["def"][Field]
		end

		if type(Formula) == "function" then
			env.PartyLevel 		= PartyLevel
			env.MonsterLevel 	= MonsterLevel
			env.TotalEquipCost 	= TotalEquipCost
			env.HP				= HP
			env.BoostedHP 		= BoostedHP
			env.AC 				= AC
			env.MonsterHeight 	= MonsterHeight
			env.MaxDamage 		= MaxDamage
			env.SpellSkill		= SpellSkill
			env.SpellMastery 	= SpellMastery
			env.BolsterMul 		= BolsterMul
			env.MonsterPower 	= MonsterPower
			env.MonSettings 	= MonSettings
			env.MapSettings 	= MapSettings
			env.MoveSpeed		= MoveSpeed

			setfenv(Formula, env)
			res = ApplyMultiplier(Field, Default, Formula())
		end
		MF.LogVerbose("ProcessFormula: %s, %s, %s, %s, %s", MonKind, Field, Default, FType, res)
		return res
	end

	MonTable = {}

	if SpcMonId then
		--copy_map_monsters_txt(MV.Map, MapMonIdx)
		MonTable[i] = MT.SpcMonstersTxt[SpcMonId]
	elseif type(i) == "number" then
		MonKind = ceil(i/3)
		MonTable = OnlyThis and {[i] = Game.MonstersTxt[i]}
			or 	{	[MonKind*3-2] = Game.MonstersTxt[MonKind*3-2],
					[MonKind*3-1] = Game.MonstersTxt[MonKind*3-1],
					[MonKind*3  ] = Game.MonstersTxt[MonKind*3  ]}

	elseif type(i) == "table" then
		for k,v in pairs(i) do
			MonKind = ceil(v/3)
			MonTable[MonKind*3-2] = Game.MonstersTxt[MonKind*3-2]
			MonTable[MonKind*3-1] = Game.MonstersTxt[MonKind*3-1]
			MonTable[MonKind*3  ] = Game.MonstersTxt[MonKind*3  ]
		end
	else
		return
	end

	for k,v in pairs(MonTable) do
		if not SpcMonId and
		(ReadyMons[k] or GetAvgMonLevel(k) >= PartyLevel and MapSettings.Type ~= BolsterTypes.AllToEqual) then
			MonTable[k] = nil
		end
	end

	for monId, mon in pairs(MonTable) do

		MonKind 		= ceil(monId/3)
		HP 				= mon.FullHP
		BoostedHP		= mon.FullHP
		AC 				= mon.ArmorClass
		MonSettings		= MonsSettings[monId]
		MonsterHeight 	= Game.MonListBin[monId].Height
		MonsterPower	= monId - MonKind*3 + 3
		MonsterLevel	= SpcMonId and mon.Level or GetAvgMonLevel(monId)
		BolStep 		= min(floor(PartyLevel/MonsterLevel), 4)

		local Formula = Formulas[MonKind] or Formulas["def"]
		local src, dst = mon, mon
		if SpcMonId then
			dst = Game.Bolster.SpcMonsters[SpcMonId]
		end

		MonBolStep[monId] = BolStep

		if MapSettings.Type ~= BolsterTypes.OriginalStats then
			MF.LogVerbose("PrepareTxtMon: mon id %d", monId)
			
			-- Base hitpoints
			dst.FullHP = min(ProcessFormula(MonKind, "HP", src.FullHP, ftype), 32000)
			BoostedHP  = dst.FullHP

			-- Armor class
			dst.ArmorClass = ProcessFormula(MonKind, "AC", src.ArmorClass, ftype)

			-- Attacks
			MaxDamage = GetMaxDamage(src.Attack1)
			MaxDamage = ProcessFormula(MonKind, "MaxDamage", MaxDamage, ftype)
			SetAttackMaxDamage(dst.Attack1, MaxDamage)

			if src.Attack2Chance > 0 then
				MaxDamage = GetMaxDamage(src.Attack2)
				MaxDamage = ProcessFormula(MonKind, "MaxDamage", MaxDamage, ftype)
				SetAttackMaxDamage(dst.Attack2, MaxDamage)
			end

			-- Base spells

			local Skill, Mas
			if src.Spell > 0 then
				SpellSkill, SpellMastery = SplitSkill(src.SpellSkill)
				Skill = ProcessFormula(MonKind, "SpellSkill", SpellSkill, ftype)
				Mas   = ProcessFormula(MonKind, "SpellMastery", SpellMastery, ftype)
				dst.SpellSkill = JoinSkill(Skill, Mas)
			end

			if src.Spell2 > 0 then
				SpellSkill, SpellMastery = SplitSkill(src.Spell2Skill)
				Skill = ProcessFormula(MonKind, "SpellSkill", SpellSkill, ftype)
				Mas   = ProcessFormula(MonKind, "SpellMastery", SpellMastery, ftype)
				dst.Spell2Skill = JoinSkill(Skill, Mas)
			end

		end

		-- Move speed

		-- FIXME?
		MoveSpeed = src.MoveSpeed
		dst.MoveSpeed = ProcessFormula(MonKind, "MoveSpeed", src.MoveSpeed, ftype)

		-- Additional attacks

		if src.Attack2Chance == 0 and MonSettings.Ranged and BolStep > 0 then
			dst.Attack2Chance 			= min(BolStep*10, 35)
			dst.Attack2.Missile 		= BolStep > 2 and (MonSettings.Magic == 0 and 1 or 6) or 0
			dst.Attack2.Type 			= dst.Attack1.Type

			-- FIXME
			MaxDamage = GetMaxDamage(dst.Attack1)
			SetAttackMaxDamage(dst.Attack2, MaxDamage)
		end

		-- Additional spells

		if ProcessFormula(MonKind, "AllowNewSpell", false, ftype) then

			local SkillByMas = {1,4,7,10}
			local Mas = MonSettings.Style == 3 and 2 or 1
			local Skill = SkillByMas[Mas]

			SpellSkill, SpellMastery = Skill, Mas
			Skill = ProcessFormula(MonKind, "SpellSkill", SpellSkill, ftype)
			Mas   = ProcessFormula(MonKind, "SpellMastery", SpellMastery, ftype)

			if src.Spell == 0 and (BolStep >= 1 or MonSettings.Style == 3) then
				dst.SpellSkill = JoinSkill(Skill, Mas)
				dst.SpellChance = MonSettings.Style == 3 and 60 or 35
			end

			if src.Spell2 == 0 and (BolStep >= 2 or (MonSettings.Style == 3 and BolStep >= 1)) then
				dst.Spell2Skill = JoinSkill(Skill, Mas)
				dst.Spell2Chance = MonSettings.Style == 3 and 35 or 20
			end

		end

		-- Summons

		if ProcessFormula(MonKind, "AllowReplicate", false, ftype) then

			dst.Special = 4
			dst.SpecialA = 0
			dst.SpecialB = 0
			dst.SpecialC = 2
			dst.SpecialD = MonSettings.SummonId

		end

		if ProcessFormula(MonKind, "AllowSummons", false, ftype) then

			dst.Special = 2
			dst.SpecialA = dst.MoveType == 5 and 0 or max((1 + BolStep),3) -- If monster always stands still, like Trees in The Tularean forest, he will behave like spawn point.
			dst.SpecialB = Game.MonstersTxt[MonSettings.SummonId].Fly == 1 and 0 or 1 -- if summon can fly he will be summoned in air.
			dst.SpecialC = 0
			dst.SpecialD = MonSettings.SummonId == 0 and monId or MonSettings.SummonId

		end

		if SpcMonId then
			ReadySpcMons[SpcMonId] = true
		else
			ReadyMons[monId] = true
		end
	end

end

local function BolsterMonsters()

	local map_id = Map.MapStatsIndex
	local MapSettings = Game.Bolster.Maps[map_id]
	if not MapSettings then
		return
	end

	local t = {Handled = false}
	events.Call("BeforeMapBolster", t)

	if not t.Handled then
		local PartyLevel = GetOverallPartyLevel() + MapSettings.LevelShift
		local MapInTxt = Game.MapStats[map_id]
		local t = {}

		for i,v in Game.MonListBin do
			if 		string.find(v.Name, MapInTxt.Monster1Pic)
				or	string.find(v.Name, MapInTxt.Monster2Pic)
				or	string.find(v.Name, MapInTxt.Monster3Pic) then

				if not ReadyMons[i] then
					table.insert(t, i)
				end
			end
		end

		-- summons
		for i = 97, 99 do
			if not ReadyMons[i] then
				table.insert(t, i)
			end
		end

		for i,v in Map.Monsters do
			local spc_id = is_special_monster(map_id, i)
			if spc_id and spc_id > 0 then
				if not ReadySpcMons[spc_id] then
					PrepareTxtMon(v.Id, PartyLevel, MapSettings, true, spc_id)
				end
			elseif not ReadyMons[v.Id] then
				if v.Id > 0 and v.Id < Game.MonstersTxt.Limit then
					if not table.find(t, v.Id) then
						table.insert(t, v.Id)
					end
				else
					MF.LogError("%s: Monster with incorrect Id (%s) at %s %s %s", Map.Name, v.Id, v.X, v.Y, v.Z)
					v.AIState = const.AIState.Removed
				end
			end
		end

		PrepareTxtMon(t, PartyLevel, MapSettings, false)

		for i,v in Map.Monsters do
			if v.Id > 0 and v.Id < Game.MonstersTxt.Limit then
				local spc_id = is_special_monster(map_id, i)
				if spc_id and spc_id > 0 then
					PrepareMapMon(v, MapSettings, spc_id)
				else
					PrepareMapMon(v, MapSettings)
				end
			end
		end
	end

	events.Call("AfterMapBolster")

end

-----------------------------------------------
-- Init

local function Init()

	ProcessBolsterTxt()
	Game.Bolster.ReloadTxt = ProcessBolsterTxt
	local StdSummonMonster = SummonMonster

	function SummonMonster(Id, ...)

		local mon, i = StdSummonMonster(Id, ...)
		if not mon then
			return
		end

		if not (Editor and Editor.WorkMode) then

			local MapSettings = Game.Bolster.Maps[Map.MapStatsIndex]
			if MapSettings then
				local PartyLevel = GetOverallPartyLevel() + MapSettings.LevelShift
				if not ReadyMons[Id] then
					PrepareTxtMon(Id, PartyLevel, MapSettings)
				end
				PrepareMapMon(mon, MapSettings)
			end

		end

		return mon, i
	end

	-- Set monster kind check

	function events.IsMonsterOfKind(t)
		local MonExtra = Game.Bolster.MonstersSource[t.Id]
		if MonExtra and (t.Kind == MonExtra.Type or table.find(MonExtra.ExtraType, t.Kind)) then
			t.Result = 1
		end
	end

	-- Boost summons

	mem.autohook2(0x44d4b1, function(d)
		if Game.UseMonsterBolster and not ReadyMons[d.esi] then
			local MapSettings = Game.Bolster.Maps[Map.MapStatsIndex]
			if MapSettings then
				local PartyLevel = GetOverallPartyLevel() + MapSettings.LevelShift

				for i = d.esi, d.esi+2 do
					if not ReadyMons[i] then
						PrepareTxtMon(i, PartyLevel, MapSettings)
					end
				end
			end
		end
	end)

	-- Arena monsters generation
	local ArenaMonstersList, ArenaPartyLevel, ArenaMapSettings
	function events.BeforeArenaStart(ArenaLevel)

		local PartyLevel = GetOverallPartyLevel()

		local MinLevel, MaxLevel
		if ArenaLevel == 0 then
			MinLevel = 0
			MaxLevel = max(PartyLevel, 10)
		elseif ArenaLevel == 1 then
			MinLevel = min(ceil(PartyLevel/5), 70)
			MaxLevel = max(PartyLevel, 10) + 5
		elseif ArenaLevel == 2 then
			MinLevel = min(ceil(PartyLevel/3), 70)
			MaxLevel = max(PartyLevel, 10) + 7
		elseif ArenaLevel == 3 then
			MinLevel = min(ceil(PartyLevel/2), 70)
			MaxLevel = max(PartyLevel, 10) + 10
		end

		local MinKind, MaxKind
		if ArenaLevel == 0 then
			MinKind, MaxKind = 1,1
		elseif ArenaLevel == 1 then
			MinKind, MaxKind = 1,2
		elseif ArenaLevel == 2 then
			MinKind, MaxKind = 2,3
		elseif ArenaLevel == 3 then
			MinKind, MaxKind = 3,3
		end

		local MonstersTxt = Game.MonstersTxt
		local List, Kind, MonLevel = {}, nil, nil
		for i = 1, Game.MonstersTxt.count-1 do
			Kind = 3 - i % 3
			if not (Kind < MinKind or Kind > MaxKind) then
				MonLevel = MonstersTxt[i].Level
				if not (MonLevel < MinLevel or MonLevel > MaxLevel)
						and Game.IsMonsterOfKind(i, const.MonsterKind.NoArena) == 0
						and Game.IsMonsterOfKind(i, const.MonsterKind.Peasant) == 0 then
					table.insert(List, i)
				end
			end
		end

		ArenaPartyLevel = PartyLevel
		ArenaMonstersList = List
		ArenaMapSettings = Game.Bolster.Maps[Map.MapStatsIndex]
	end

	function events.GenerateArenaMonster(t)
		local MonId = ArenaMonstersList[random(#ArenaMonstersList)]

		t.Handled = true
		t.MonId = MonId

		if Game.UseMonsterBolster and ArenaMapSettings and not ReadyMons[MonId] then
			PrepareTxtMon(MonId, ArenaPartyLevel, ArenaMapSettings, true)
		end
	end

	-- Add player's armor class penalty depending on enemy's bolster
	local NewCode = mem.asmpatch(0x48db2f, [[
	add esi, eax
	nop; mem hook
	nop
	nop
	nop
	nop

	xor edx, edx
	@std:
	cmp esi, 0x1]])

	local pptr, psize = Party.PlayersArray["?ptr"], Party.PlayersArray[0]["?size"]
	local function GetPlayer(ptr)
		local PlayerId = (ptr - pptr)/psize
		return Party.PlayersArray[PlayerId], PlayerId
	end

	mem.hook(NewCode + 2, function(d)
		local source, player_slot = WhoHitPlayer()
		if not source or not source.Monster then
			return
		end

		local t = {
			Monster = source.Monster,
			MonsterIndex = source.MonsterIndex,
			AC = d.esi,
			Player = Party[player_slot]}

		local monId = t.Monster.Id
		if Game.UseMonsterBolster and ReadyMons[monId] then
			local Formulas = Game.Bolster.Formulas
			local f = Formulas[monId] and Formulas[monId]["PlayerAC"] or Formulas["def"]["PlayerAC"]
			LastFormulaEnv.PlayerAC = t.AC
			LastFormulaEnv.Player = t.Player
			LastFormulaEnv.Monster = t.Monster
			LastFormulaEnv.BolsterMul = Game.BolsterAmount / 100
			setfenv(f, LastFormulaEnv)

			local result = f() or d.esi
			t.AC = math.max(ApplyMultiplier("PlayerAC", t.AC, result), 0)
		end

		events.call("GetArmorClass", t)
		d.esi = t.AC
	end)

	Game.Bolster.Multipliers = Multipliers
	Game.Bolster.BolsterLevel = GetOverallPartyLevel
	Game.Bolster.PreparedTxtMons = function()
		return ReadyMons
	end

	Game.Bolster.OnLoadMap = function()
		if Editor and Editor.WorkMode then
			return
		end

		LocalMonstersTxt()
		TxtLocalized = true
		ReadyMons	= {}
		table.clear(ReadySpcMons)
		MonBolStep	= {}

		BolsterMonsters()
	end
	
	MT.MonstersTxt = {}
	for idx = 1, Game.MonstersTxt.high do
		copy_monsters_txt(idx)
	end

end

function events.AfterLoadMap()
	local t = {Handled = false}
	events.Call("BolsterOnLoadMap", t)

	if not t.Handled then
		Game.Bolster.OnLoadMap()
	end
end

function events.LeaveMap()
	TxtLocalized = false
end

function events.LeaveGame()
	TxtLocalized = false
end

function events.GameInitialized2()
	Init()
end

Game.BolsterMonsters = BolsterMonsters

MF.LogInit2(LogId)
