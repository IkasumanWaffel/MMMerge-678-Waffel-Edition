local LogId = "RemoveHouseRulesLimits"
local MF = Merge.Functions
MF.LogInit1(LogId)
local MO = Merge.Offsets

local asmpatch, asmproc, StaticAlloc = MF.Asmpatch, MF.Asmproc, MF.StaticAlloc
local autohook, autohook2, hook = MF.Autohook, MF.Autohook2, MF.Hook

if offsets.MMVersion ~= 8 then
	return 0
end

--Shop counts:
local OldWepCount, WepCount = 14, nil
local OldArmCount, ArmCount = 14, nil
local OldMagCount, MagCount = 13, nil
local OldAlcCount, AlcCount = 12, nil
local OldSpBCount, SpBCount = 10, nil
local OldTrHCount, TrHCount = 13, nil
local OldTavCount, TavCount = 12, nil
local OldStablesCount, StablesCount = 9, nil
local OldBoatsCount, BoatsCount = 11, nil
local OldHousesCount, HousesCount = 525, nil

local OldGuildCount, GuildCount = 34, nil -- 8 entries (in a block of 10 houses) were used in MM8
local OldGuildAssortCount, GuildAssortCount = 34, nil

--Rules pointers (original starts of blocks):
local StRWepPtr = 0x5007f0
local StRArmPtr = 0x500880
local StRMagPtr = 0x500998
local StRAlcPtr = 0x5009b4

local SpRWepPtr = 0x500a30
local SpRArmPtr = 0x500ac0
local SpRMagPtr = 0x500bd8
local SpRAlcPtr = 0x500bf4

local RSBPtr = 0x501238 -- Game.GuildSpellLevels
local RTavernsPtr = 0x4f2d60
local RTrHallPtr = 0x500d5c

local TranIndexPtr = 0x501118

--Assortment pointers:
local StandartAssortPtr   = 0xb7ca8c -- Game.ShopItems
local SpecialAssortPtr    = 0xb823fc -- Game.ShopSpecialItems
local SpellbooksAssortPtr = 0xb87d6c -- Game.GuildItems

local FillStatePtr1 = 0xb20f1c -- Game.ShopNextRefill
local FillStatePtr2 = 0xbb2e20

-- Game.GuildNextRefill
-- Note: relative address, actual space starts at 0xB210C4 for house 139
local SBFillStatePtr = 0xb20c6c

--local RepPtr = 0xb20bc4 -- mistake, evt Counter block
local RepPtr2 = 0xb211d4 -- Game.ShopTheftExpireTime, 53 entries (0..52) in MM8

local HousesPtr = mem.u4[0x4b7305 + 3] --0x5a5728 - original
local AMRulesTopicsPtr

local CurHouseID = 0x518678

function GetCurrentHouse()
	return mem.u4[CurHouseID]
end
MF.GetCurrentHouse = GetCurrentHouse

--Structures:

local OldGame = structs.f.GameStructure
function structs.f.GameStructure(define)
   OldGame(define)
   define
	[0].struct(structs.HouseRules)  'HouseRules'
	[0].array(1, OldHousesCount).struct(structs.HousesExtra)  'HousesExtra'
	[SBFillStatePtr].array(0, OldSpBCount).i8  'GuildNextRefill2'
	--[RepPtr2].array(OldHousesCount).i8 'ShopBanExpiration' -- Game.ShopTheftExpireTime, 53 entries
	[0].array(1, OldSpBCount).u2 'GuildAssortIds'
end

function structs.f.HouseRules(define)
	define
	[0x5007f0].array(1, OldWepCount).struct(structs.WeaponShopRule)  'WeaponShopsStandart'
	[0x500a30].array(1, OldWepCount).struct(structs.WeaponShopRule)  'WeaponShopsSpecial'
	[0x500880].array(1, OldArmCount).struct(structs.ArmorShopRule)  'ArmorShopsStandart'
	[0x500ac0].array(1, OldArmCount).struct(structs.ArmorShopRule)  'ArmorShopsSpecial'
	[0x500998].array(1, OldMagCount).struct(structs.ShopRule)  'MagicShopsStandart'
	[0x500bd8].array(1, OldMagCount).struct(structs.ShopRule)  'MagicShopsSpecial'
	[0x5009b4].array(1, OldAlcCount).struct(structs.ShopRule)  'AlchemistsStandart'
	[0x500bf4].array(1, OldAlcCount).struct(structs.ShopRule)  'AlchemistsSpecial'
	[0x501238].array(1, OldSpBCount).struct(structs.ShopRule)  'SpellbookShops'
	[0x500d5c].array(1, OldTrHCount).struct(structs.ShopRule)  'Training'
	[0x4f2d60].array(1, OldTavCount).struct(structs.ArcomageRule)  'Arcomage'
	[0X4f2d60].array(0).i2  'ArcomageTexts'
end

function structs.f.ShopRep(define)
	define
	.i4 'unk1'
	.i4 'unk2'
end

function structs.f.WeaponShopRule(define)
   define
   .i2  'Quality'
   .array(1, 4).i2  'ItemTypes'
end

function structs.f.ArmorShopRule(define)
   define
   .i2  'QualityShelf'
   .array(1, 4).i2  'ItemTypesShelf'
   .i2  'QualityCase'
   .array(1, 4).i2  'ItemTypesCase'
end

function structs.f.ShopRule(define)
   define
   .i2  'Quality'
end

function structs.f.ArcomageRule(define)
   define
   .i2  'TowerToWin'
   .i2  'ResToWin'
   .i2  'TowerAtStart'
   .i2  'WallAtStart'
   .i2  'Quarry'
   .i2  'Magic'
   .i2  'Dungeon'
   .i2  'Bricks'
   .i2  'Gems'
   .i2  'Recruits'
   .i4  'Ai'
end

function structs.f.HousesExtra(define)
   define
   .i2  'IndexByType'
   .i2	'Map'
end

-- Topics const
const.ShopTopics =	{
	Empty = 0x0, Standart = 0x2,
	Heal = 0xa, Donate = 0xb,
	RentRoom = 0xf, BuyFood = 0x10,
	Special = 0x5f, Inventory = 0x5e,
	Learn = 0x60,
	PlayArcomage = 0x65,
	StableTravel = 0x69, BoatTravel = 0x6a,
	MagicFire = 0x6e,
	MagicAir = 0x6f, MagicWater = 0x70,
	MagicEarth = 0x71, MagicSpirit = 0x72,
	MagicMind = 0x73, MagicBody = 0x74,
	MagicLight = 0x75, MagicDark = 0x76,
	MagicElem = 0x79, MagicSelf = 0x7A,
	MagicMirrored = 0x7B
}

-- 0x24 (36 dec) + const.Skills
const.LearnTopics = {
	Staff = 0x24, Sword = 0x25,
	Dagger = 0x26, Axe = 0x27,
	Spear = 0x28, Bow = 0x29,
	Mace = 0x2a, Blaster = 0x2b,
	Shield = 0x2c, Leather = 0x2d,
	Chain = 0x2e, Plate = 0x2f,
	Fire = 0x30, Air = 0x31,
	Water = 0x32, Earth = 0x33,
	Spirit = 0x34, Mind = 0x35,
	Body = 0x36, Light = 0x37,
	Dark = 0x38, DarkElfAbility = 0x39,
	VampireAbility = 0x3a, DragonAbility = 0x3b,
	IdentifyItem = 0x3c, Merchant = 0x3d,
	Repair = 0x3e, Bodybuilding = 0x3f,
	Meditation = 0x40, Perception = 0x41,
	Regeneration = 0x42, DisarmTraps = 0x43,
	Dodging = 0x44, Unarmed = 0x45,
	IdentifyMonster = 0x46, Armsmaster = 0x47,
	Stealing = 0x48, Alchemy = 0x49,
	Learning = 0x4a
}

-- Extra fields for Houses table ("Map" and "IndexByType")

local HousesExtraPtr

autohook(0x4406db, function(d)
	if not HousesExtraPtr then
		HousesExtraPtr = StaticAlloc(4*Game.Houses.count)
	end

	local Counter = (d.edi - mem.u4[0x440692 + 1])/0x34
	-- "IndexByType" column
	if d.edx == -1 then
		mem.i2[HousesExtraPtr + Counter*4] = tonumber(string.split(mem.string(d.esi, 5), "\9")[1]) or 0
	-- "Map" column
	elseif d.edx == 1 then
		mem.i2[HousesExtraPtr + Counter*4 + 2] = tonumber(string.split(mem.string(d.esi, 5), "\9")[1]) or 0
	-- "C" column
	elseif d.edx == 13 then
		d.eax = 1 -- force to process it always, not just for shops.
	end
end)

--

local function GenerateTable()

	local function SimpleParse(File, StartAddress, Count, LineSize, ItemSize, Header)

		local UX = mem["u" .. ItemSize]

		if Header ~= nil then
			File:write(Header .. "\n")
		end
		for iQ = 0, Count-1 do
			local Str = tostring(iQ + 1)
			for iI = 0, LineSize-1 do
				Str = Str .. "	" .. UX[StartAddress + (iQ*LineSize + iI)*ItemSize]
			end
			File:write(Str .. "\n")
		end
	end

	local ShopsTable = io.open("Data/Tables/House rules.txt", "w")
	ShopsTable:write("Index by type	Quality	Items1	Items2	Items3	Items4	Quality	Items1	Items2	Items3	Items4\n")

	SimpleParse(ShopsTable, StRWepPtr, OldWepCount, 5, 2, "Weapon shops Standart")
	SimpleParse(ShopsTable, SpRWepPtr, OldWepCount, 5, 2, "Weapon shops Special")

	SimpleParse(ShopsTable, StRArmPtr, OldArmCount, 10, 2, "Armor shops Standart")
	SimpleParse(ShopsTable, SpRArmPtr, OldArmCount, 10, 2, "Armor shops Special")

	SimpleParse(ShopsTable, StRMagPtr, OldMagCount, 1, 2, "Magic shops Standart")
	SimpleParse(ShopsTable, SpRMagPtr, OldMagCount, 1, 2, "Magic shops Special")

	SimpleParse(ShopsTable, StRAlcPtr, OldAlcCount, 1, 2, "Alchem shops Standart")
	SimpleParse(ShopsTable, SpRAlcPtr, OldAlcCount, 1, 2, "Alchem shops Special")

	SimpleParse(ShopsTable, RSBPtr, OldSpBCount, 1, 2, "Spellbook shops")

	SimpleParse(ShopsTable, TranIndexPtr, OldStablesCount, 4, 1, "Stables	Loc1	Loc2	Loc3	Loc4")
	SimpleParse(ShopsTable, TranIndexPtr + OldStablesCount*4, OldBoatsCount, 4, 1, "Boats	Loc1	Loc2	Loc3	Loc4")

	SimpleParse(ShopsTable, RTrHallPtr, OldTrHCount, 1, 2, "Training halls	Max level")

	ShopsTable:write("Arcomage in taverns	Tower to win	Res to win	Tower at start	Wall at start	Res1 per turn	Res2	Res3	Res1 at start	Res2	Res3	Ai	'Rules' text index\n")
	for iQ = 0, OldTavCount - 1 do
		local Str = tostring(iQ + 1)
		for iI = 0, 10 do
			Str = Str .. "	" .. mem.u2[RTavernsPtr + iQ*2*12 + iI*2]
		end
		Str = Str .. "	" .. tostring(137 + iQ)
		ShopsTable:write(Str .. "\n")
	end

	ShopsTable:close()
end

local function LoadTable()

	local CurWepCount, CurArmCount, CurMagCount, CurAlcCount, CurStablesCount, CurBoatsCount, CurTrHCount, CurSpbCount, CurTavCount, SHSets, CurrentPtr, CurrentSize, CurItemSize
	local CurrentCount = 0
	local ShopsTable = io.open("Data/Tables/House rules.txt", "r")

	local function LoadInMemory(Ptr, t, size, ItemSize)

		if ItemSize == 1 then
			UX = mem.u1
		elseif ItemSize == 2 then
			UX = mem.u2
		elseif ItemSize == 4 then
			UX = mem.u4
		else
			return 0
		end

		Ptr = Ptr + (tonumber(t[1])-1)*size*ItemSize
		for i = 2, size+1 do
			UX[Ptr + (i-2)*ItemSize] = tonumber(t[i])
		end
	end

	local function LoadTavRules(t)
		local Ptr = RTavernsPtr
		Ptr = Ptr + (tonumber(t[1])-1)*12*2
		if AMRulesTopicsPtr ~= nil then
			local Topics = AMRulesTopicsPtr
			Topics = Topics + (tonumber(t[1])-1)*2
			mem.u2[Topics] = tonumber(t[13])
		end
		for i = 2, 12 do
			mem.u2[Ptr + (i-2)*2] = tonumber(t[i])
		end
	end

	local function LoadGuildRules(t)
		-- Base MMMerge has 1 i2 field
		local ptr1 = RSBPtr + (tonumber(t[1]) - 1) * 2
		mem.i2[ptr1] = tonumber(t[2])
		ptr1 = MO.GuildAssortIds + (tonumber(t[1]) - 1) * 2
		mem.i2[ptr1] = tonumber(t[3]) or 1
	end

	for line in ShopsTable:lines() do

		SHSets = string.split(line, "\9")

		if SHSets[1] == "Weapon shops Standart" then
			CurrentPtr = StRWepPtr
			CurrentSize = 5
			CurItemSize = 2
		elseif SHSets[1] == "Weapon shops Special" then
			CurrentPtr = SpRWepPtr
			CurrentSize = 5
			CurWepCount = CurrentCount
		elseif SHSets[1] == "Armor shops Standart" then
			CurrentPtr = StRArmPtr
			CurrentSize = 10
		elseif SHSets[1] == "Armor shops Special" then
			CurrentPtr = SpRArmPtr
			CurrentSize = 10
			CurArmCount = CurrentCount
		elseif SHSets[1] == "Magic shops Standart" then
			CurrentPtr = StRMagPtr
			CurrentSize = 1
		elseif SHSets[1] == "Magic shops Special" then
			CurrentPtr = SpRMagPtr
			CurrentSize = 1
			CurMagCount = CurrentCount
		elseif SHSets[1] == "Alchem shops Standart" then
			CurrentPtr = StRAlcPtr
			CurrentSize = 1
		elseif SHSets[1] == "Alchem shops Special" then
			CurrentPtr = SpRAlcPtr
			CurrentSize = 1
			CurAlcCount = CurrentCount
		elseif SHSets[1] == "Spellbook shops" then
			CurrentPtr = RSBPtr
			CurrentSize = 1
		elseif SHSets[1] == "Stables" then
			CurrentPtr = TranIndexPtr
			CurrentSize = 4
			CurItemSize = 1
			CurSpbCount = CurrentCount
		elseif SHSets[1] == "Boats" then
			CurrentPtr = TranIndexPtr+StablesCount*4
			CurrentSize = 4
			CurStablesCount = CurrentCount
		elseif SHSets[1] == "Training halls" then
			CurrentPtr = RTrHallPtr
			CurrentSize = 1
			CurItemSize = 2
			CurBoatsCount = CurrentCount
		elseif SHSets[1] == "Arcomage in taverns" then
			CurrentPtr = RTavernsPtr
			CurrentSize = 12
			CurTrHCount = CurrentCount
		elseif SHSets[1] == "Index by type" or string.len(SHSets[1]) == 0 then
			--nothing
		else
			CurrentCount = tonumber(SHSets[1])
			if CurrentPtr == RTavernsPtr then
				LoadTavRules(SHSets)
			elseif CurrentPtr == RSBPtr then
				LoadGuildRules(SHSets)
			else
				LoadInMemory(CurrentPtr, SHSets, CurrentSize, CurItemSize)
			end
		end

	end
	CurTavCount = CurrentCount

	local ErrStr = ""
	if WepCount > CurWepCount then
		ErrStr = ErrStr .. "Count of weapon shops in '2DEvents.txt' (" .. WepCount .. ") and 'House rules.txt' (" .. CurWepCount .. ") do not match!\n"
	end
	if ArmCount > CurArmCount then
		ErrStr = ErrStr .. "Count of armor shops in '2DEvents.txt' (" .. ArmCount .. ") and 'House rules.txt' (" .. CurArmCount .. ") do not match!\n"
	end
	if MagCount > CurMagCount then
		ErrStr = ErrStr .. "Count of magic shops in '2DEvents.txt' (" .. MagCount .. ") and 'House rules.txt' (" .. CurMagCount .. ") do not match!\n"
	end
	if AlcCount > CurAlcCount then
		ErrStr = ErrStr .. "Count of alchemical shops in '2DEvents.txt' (" .. AlcCount .. ") and 'House rules.txt' (" .. CurAlcCount .. ") do not match!\n"
	end
	if StablesCount > CurStablesCount then
		ErrStr = ErrStr .. "Count of stables in '2DEvents.txt' (" .. StablesCount .. ") and 'House rules.txt' (" .. CurStablesCount .. ") do not match!\n"
	end
	if BoatsCount > CurBoatsCount then
		ErrStr = ErrStr .. "Count of boats in '2DEvents.txt' (" .. BoatsCount .. ") and 'House rules.txt' (" .. CurBoatsCount .. ") do not match!\n"
	end
	if TrHCount > CurTrHCount then
		ErrStr = ErrStr .. "Count of training halls in '2DEvents.txt' (" .. TrHCount .. ") and 'House rules.txt' (" .. CurTrHCount .. ") do not match!\n"
	end
	if SpBCount > CurSpbCount then
		ErrStr = ErrStr .. "Count of spellbook shops in '2DEvents.txt' (" .. SpBCount .. ") and 'House rules.txt' (" .. CurSpbCount .. ") do not match!\n"
	end
	if TavCount > CurTavCount then
		ErrStr = ErrStr .. "Count of taverns in '2DEvents.txt' (" .. TavCount .. ") and 'House rules.txt' (" .. CurTavCount .. ") do not match!\n"
	end

	if string.len(ErrStr) > 0 then
		ErrStr = ErrStr .. "\nErrors are possible."
		debug.Message(ErrStr)
	end

	ShopsTable:close()

end

local function GetGuildAssortCount()
	assort_count = OldGuildAssortCount
	local f = io.open("Data/Tables/House rules.txt", "r")
	if f then
		local started = false
		local iter = f:lines()
		for line in iter do
			local words = string.split(line, "\t")
			if words[1] == "Spellbook shops" then
				started = true
			elseif started then
				if tonumber(words[1]) then
					local assort_id = tonumber(words[3])
					if assort_id and assort_id > assort_count then
						assort_count = assort_id
					end
				else
					started = false
				end
			end
		end
		io.close(f)
	end
	return assort_count
end
MF.GetGuildAssortCount = GetGuildAssortCount

local function RemoveLimits()

	--Misc:
	local StIdentCheckPtr = 0xb7ca8c - 0x24
	local SpIdentCheckPtr = 0xb823fc - 0x24

	local NewSpace, NewSize, NewCode
	----

	mem.IgnoreProtection(true)

	local WepRSize, ArmRSize, MagRSize, AlcRSize, WepAsrtSize, ArmAsrtSize, MagAsrtSize, AlcAsrtSize, TranIndexSize, RepSize
	local SbRSize, SbAsrtSize, TrHRSize, TavRSize, TavTopicsPtrsSize, FillState1Size, FillState2Size, FillStateSBSize

	--Setting new space and pointers:
	WepRSize = WepCount*2*5*2
	ArmRSize = ArmCount*2*5*2*2
	MagRSize = MagCount*2*2
	AlcRSize = AlcCount*2*2
	SbRSize = SpBCount*2

	TrHRSize = TrHCount*2
	TavRSize = TavCount*12*2
	TavTopicsPtrsSize = TavCount*2

	WepAsrtSize = WepCount*12*9*4*2
	ArmAsrtSize = ArmCount*12*9*4*2
	MagAsrtSize = MagCount*12*9*4*2
	AlcAsrtSize = AlcCount*12*9*4*2 + 12*9*4*2
	--SbAsrtSize = SpBCount*12*12*9*8
	SbAsrtSize = GuildAssortCount * 12 * 12 * 36

	FillState1Size = (WepCount+ArmCount+MagCount+AlcCount+SpBCount+1)*8
	FillState2Size = (WepCount+ArmCount+MagCount+AlcCount+SpBCount+1)*4
	FillStateSBSize = SpBCount*8

	RepSize = (WepCount+ArmCount+MagCount+AlcCount+SpBCount)*8

	TranIndexSize = StablesCount*4 + BoatsCount*4

	-- FIXME: Previously additional 36288 bytes were allocated via double SbAsrtSize.
	--   Shrinking it somehow affects items from 'Complex Item Pictures' (like armor offsets became garbage or item pic not loaded).
	--   0x200 bytes seem to be enough for them to work. Need to investigate further.
	NewSize = WepRSize + ArmRSize + MagRSize + AlcRSize + SbRSize + TrHRSize + TavRSize
				-- + TavTopicsPtrsSize + WepAsrtSize + ArmAsrtSize + MagAsrtSize + AlcAsrtSize + SbAsrtSize + TranIndexSize + FillStateSBSize + RepSize*2 + 0x10
				+ TavTopicsPtrsSize + WepAsrtSize + ArmAsrtSize + MagAsrtSize + AlcAsrtSize + TranIndexSize + FillStateSBSize + RepSize*2 + 0x200
	NewSpace = StaticAlloc(NewSize)

	if GuildAssortCount > OldGuildAssortCount then
		SpellbooksAssortPtr = StaticAlloc(SbAsrtSize)
	end

	StRWepPtr = NewSpace
	SpRWepPtr = NewSpace + WepRSize/2

	StRArmPtr = NewSpace + WepRSize
	SpRArmPtr = StRArmPtr + ArmRSize/2

	StRMagPtr = StRArmPtr + ArmRSize
	SpRMagPtr = StRMagPtr + MagRSize/2

	StRAlcPtr = StRMagPtr + MagRSize
	SpRAlcPtr = StRAlcPtr + AlcRSize/2

	TranIndexPtr = StRAlcPtr + AlcRSize

	RSBPtr = TranIndexPtr + TranIndexSize
	RTrHallPtr = RSBPtr + SbRSize
	RTavernsPtr = RTrHallPtr + TrHRSize
	AMRulesTopicsPtr = RTavernsPtr + TavRSize

	FillStatePtr1 = AMRulesTopicsPtr + TavTopicsPtrsSize
	FillStatePtr2 = FillStatePtr1 + FillState1Size

	SBFillStatePtr = FillStatePtr2 + FillState2Size

	--RepPtr = SBFillStatePtr + FillStateSBSize
	--RepPtr2 = RepPtr + RepSize
	RepPtr2 = SBFillStatePtr + FillStateSBSize

	StandartAssortPtr = RepPtr2 + RepSize
	StIdentCheckPtr = StandartAssortPtr - 0x24

	SpecialAssortPtr = StandartAssortPtr + WepAsrtSize/2 + ArmAsrtSize/2 + MagAsrtSize/2 + AlcAsrtSize/2
	SpIdentCheckPtr = SpecialAssortPtr - 0x24

	--SpellbooksAssortPtr = SpecialAssortPtr + WepAsrtSize/2 + ArmAsrtSize/2 + MagAsrtSize/2 + AlcAsrtSize/2

	--Correcting structures structures:

	local function ChangeHouseRulesArray(name, p, count)
		structs.o.HouseRules[name] = p
		internal.SetArrayUpval(Game.HouseRules[name], "o", p)
		internal.SetArrayUpval(Game.HouseRules[name], "count", count)
	end

	local function ChangeGameArray(name, p, count, low)
		structs.o.GameStructure[name] = p
		internal.SetArrayUpval(Game[name], "o", p)
		internal.SetArrayUpval(Game[name], "low", low or 0)
		internal.SetArrayUpval(Game[name], "count", count)
	end

	ChangeHouseRulesArray("WeaponShopsStandart", StRWepPtr, WepCount)
	ChangeHouseRulesArray("WeaponShopsSpecial", SpRWepPtr, WepCount)

	ChangeHouseRulesArray("ArmorShopsStandart", StRArmPtr, ArmCount)
	ChangeHouseRulesArray("ArmorShopsSpecial", SpRArmPtr, ArmCount)

	ChangeHouseRulesArray("MagicShopsStandart", StRMagPtr, MagCount)
	ChangeHouseRulesArray("MagicShopsSpecial", SpRMagPtr, MagCount)

	ChangeHouseRulesArray("AlchemistsStandart", StRAlcPtr, AlcCount)
	ChangeHouseRulesArray("AlchemistsSpecial", SpRAlcPtr, AlcCount)

	ChangeHouseRulesArray("SpellbookShops", RSBPtr, SpBCount)
	ChangeHouseRulesArray("Training", RTrHallPtr, TrHCount)
	ChangeHouseRulesArray("Arcomage", RTavernsPtr, TavCount)
	ChangeHouseRulesArray("ArcomageTexts", AMRulesTopicsPtr, TavCount)

	ChangeGameArray("TransportIndex", 	TranIndexPtr, StablesCount + BoatsCount)
	ChangeGameArray("ShopItems", 		StandartAssortPtr, WepCount + ArmCount + MagCount + AlcCount + 1)
	ChangeGameArray("ShopSpecialItems", SpecialAssortPtr, WepCount + ArmCount + MagCount + AlcCount + 1)
	--ChangeGameArray("GuildItems", 		SpellbooksAssortPtr, SpBCount)
	ChangeGameArray("GuildItems", SpellbooksAssortPtr, GuildAssortCount, 1)
	ChangeGameArray("ShopNextRefill", 	FillStatePtr1, WepCount + ArmCount + MagCount + AlcCount + 1)
	ChangeGameArray("GuildNextRefill2",	SBFillStatePtr, SpBCount, 1)

	ChangeGameArray("ShopTheftExpireTime", RepPtr2, WepCount+ArmCount+MagCount+AlcCount+SpBCount)

	internal.SetArrayUpval(Game.HouseRules["ArcomageTexts"], "low", 1)

	ChangeGameArray("GuildAssortIds", MO.GuildAssortIds, SpBCount, 1)
	
	-- FIXME: allocated but not used
	--Setting new code:
	mem.hookalloc(0x1000)

	-- Base functions:

	local GetCurHouseType = asmproc([[
	mov eax, dword [ds:]] .. CurHouseID .. [[]; Current house index
	dec eax
	imul eax, eax, 0xD
	lea eax, dword [ds:eax*4+]] .. HousesPtr + 0x34 .. [[];
	movzx eax, word [ds:eax]; Current house type
	retn]])

	local GetCurHouseIndexByType = asmproc([[
	pushfd
	mov eax, dword [ds:]] .. CurHouseID .. [[]; Current house index
	test eax, eax
	je @end

	dec eax
	movzx eax, word [ds:eax*4 + ]] .. HousesExtraPtr .. [[]

	@end:
	popfd
	retn]])

	local GetCurHouseWritePos = asmproc([[
	pushfd
	call absolute ]] .. GetCurHouseType .. [[;
	xor ecx, ecx
	cmp ax, 0x24
	je @end1
	cmp ax, 0x22
	je @end1
	cmp ax, 0x21
	je @end1
	cmp ax, 0x1e
	je @end1
	cmp ax, 0x1c
	je @Boat
	cmp ax, 0x1b
	je @end1
	cmp ax, 0x15
	je @end1
	cmp ax, 0x10
	jg @end2
	cmp ax, 0x4
	jg @end1
	je @Alch
	cmp ax, 0x3
	je @Mag
	cmp ax, 0x2
	je @Arm
	cmp ax, 0x1
	je @end1
	jmp @end2
	@Boat:
	add ecx, ]] .. StablesCount .. [[;
	jmp @end1
	nop; add ecx, ]] .. AlcCount .. [[; Maybe will be needed in future.
	@Alch:
	add ecx, ]] .. MagCount .. [[;
	@Mag:
	add ecx, ]] .. ArmCount .. [[;
	@Arm:
	add ecx, ]] .. WepCount .. [[;
	@end1:
	call absolute ]] .. GetCurHouseIndexByType .. [[;
	add eax, ecx
	popfd
	retn
	@end2:
	mov eax, dword [ds:]] .. CurHouseID .. [[];
	popfd
	retn]])

	function GetHouseWritePos(i)
		local res, std = i, mem.u4[CurHouseID]
		mem.u4[CurHouseID] = i
		res = mem.call(GetCurHouseWritePos)
		mem.u4[CurHouseID] = std
		return res
	end

	MO.GetGuildAssortId = asmproc([[
	mov eax, ecx
	test eax, eax
	jle @end
	dec eax
	movsx eax, word [eax * 4 + ]] .. HousesExtraPtr .. [[]
	test eax, eax
	jle @end
	dec eax
	movzx eax, word [eax * 2 + ]] .. MO.GuildAssortIds.. [[]
	@end:
	retn
	]])

	------ Shops filling. New conditions and rules pointers.

	--Getting write index at entrance:
	NewCode = asmproc([[nop
	push ecx
	call absolute ]] .. GetCurHouseWritePos .. [[;
	mov edx, dword [ds:eax*8+]] .. FillStatePtr1 + 0x4 .. [[];
	pop ecx
	cmp edx, dword [ds:0xb20ec0]
	jg absolute 0x4bb053
	jl absolute 0x4baffb
	mov eax, dword [ds:eax*8+]] .. FillStatePtr1 .. [[];
	cmp eax, dword [ds:0xb20ebc]
	jmp absolute 0x4baff9]])
	asmpatch(0x4bafdb, "jmp absolute " .. NewCode+1)

	mem.u4[0x4bafec + 3] = FillStatePtr1 --to avoid confuses.
	----

	--Weapon shop standart:
	NewCode = asmproc([[nop
	push eax
	push ecx
	call absolute ]] .. GetCurHouseType .. [[;
	cmp ax, 0x1; Index of house type "weapon shop".
	jnz @neq
	call absolute ]] .. GetCurHouseIndexByType .. [[;
	mov esi, eax
	pop ecx
	dec esi
	lea ecx, dword [esi+esi*4]
	movsx ebp, word [ds:ecx*2+]] .. StRWepPtr .. [[];
	pop eax
	call absolute 0x4d99f2
	cdq
	push 4
	pop ecx
	idiv ecx
	lea eax, dword [ds:esi+esi*4]
	add edx, eax
	movsx ecx, word [ds:edx*2+]] .. StRWepPtr + 2 .. [[];
	jmp absolute 0x4b7402
	@neq:
	pop ecx
	pop eax
	jmp absolute 0x4b7353]])
	asmpatch(0x4b731e, "jmp absolute " .. NewCode+1)

	--Armor shop standart:
	NewCode = asmproc([[
	push eax
	push ecx
	call absolute ]] .. GetCurHouseType .. [[;
	cmp ax, 0x2
	jnz @neq
	xor ebx, ebx
	cmp edi, 0x3
	setg bl
	call absolute ]] .. GetCurHouseIndexByType .. [[;
	mov esi, eax
	pop ecx
	pop eax
	dec esi
	lea ecx, dword [ds:ebx+esi*2]
	lea ecx, dword [ds:ecx+ecx*4]
	movsx ebp, word [ds:ecx*2+]] .. StRArmPtr .. [[];
	call absolute 0x4d99f2
	cdq
	push 4
	pop ecx
	idiv ecx
	mov eax, esi
	lea eax, dword [ds:eax+eax]
	add eax, ebx
	lea eax, dword [ds:eax+eax*4]
	add edx, eax
	movsx ecx, word [ds:edx*2+]] .. StRArmPtr + 2 .. [[];
	jmp absolute 0x4b7402
	@neq:
	pop ecx
	pop eax
	jmp absolute 0x4b7394]])
	asmpatch(0x4b7353, "jmp absolute " .. NewCode)

	--Magic shop standart:
	NewCode = asmproc([[
	push eax
	push ecx
	call absolute ]] .. GetCurHouseType .. [[;
	cmp ax, 0x3
	jnz @neq
	call absolute ]] .. GetCurHouseIndexByType .. [[;
	mov esi, eax
	pop ecx
	pop eax
	dec esi
	movsx ebp, word [ds:esi*2+]] .. StRMagPtr .. [[];
	push 0x16
	jmp absolute 0x4b7401
	@neq:
	pop ecx
	pop eax
	jmp absolute 0x4b73aa]])
	asmpatch(0x4b7394, "jmp absolute " .. NewCode)

	--Weapon, armor and magic shops store table:
	NewCode = asmproc([[
	push ecx
	call absolute ]] .. GetCurHouseWritePos .. [[;
	mov esi, eax
	pop ecx
	lea eax, dword [ds:esi+esi*2]
	lea eax, dword [ds:edi+eax*4]
	push 0x0
	lea eax, dword [ds:eax+eax*8]
	lea eax, dword [ds:eax*4+]] .. StandartAssortPtr .. [[];
	jmp absolute 0x4b7414]])
	asmpatch(0x4b7402, "jmp absolute " .. NewCode)

	--Magic shop additional:
	NewCode = asmproc([[
	call absolute ]] .. GetCurHouseWritePos .. [[;
	mov ecx, eax
	call absolute ]] .. GetCurHouseType .. [[;
	cmp ax, 0x3
	jnz @neq
	lea ecx, dword [ds:ecx+ecx*2]
	lea ecx, dword [ds:edi+ecx*4]
	lea ecx, dword [ds:ecx+ecx*8]
	lea ecx, dword [ds:ecx*4+]] .. StandartAssortPtr .. [[];
	mov edx, dword [ds:ecx]
	jmp absolute 0x4b7445
	@neq:
	mov eax, dword [ds:0x519328]
	jmp absolute 0x4b7470]])
	asmpatch(0x4b7421, "jmp absolute " .. NewCode)

	--Alchemical shop standart:
	NewCode = asmproc([[
	push eax
	push ecx
	call absolute ]] .. GetCurHouseType .. [[;
	cmp ax, 0x4
	jnz @neq
	call absolute ]] .. GetCurHouseIndexByType .. [[;
	mov esi, eax
	pop ecx
	pop eax
	dec esi
	cmp edi, 0x6
	jge absolute 0x4b73f7
	jmp absolute 0x4b73c1
	@neq:
	pop ecx
	pop eax
	jmp absolute 0x4b7487]])
	asmpatch(0x4b73aa, "jmp absolute " .. NewCode)

	NewCode = asmproc([[
	movsx ebp, word [ds:esi*2+]] .. StRAlcPtr .. [[];
	jmp absolute 0x4b73ff]])
	asmpatch(0x4b73f7, "jmp absolute " .. NewCode)

	-- Alchemical shop store table:
	NewCode = asmproc([[
	call absolute ]] .. GetCurHouseWritePos .. [[;
	mov esi, eax
	lea eax, dword [ds:esi+esi*2]
	lea eax, dword [ds:edi+eax*4]
	lea eax, dword [ds:eax+eax*4]
	lea ecx, dword [ds:eax*4+]] .. StandartAssortPtr .. [[];
	jmp absolute 0x4b73d1]])
	asmpatch(0x4b73c1, "jmp absolute " .. NewCode)

	NewCode = asmproc([[
	call absolute ]] .. GetCurHouseWritePos .. [[;
	mov ecx, eax
	mov eax, dword [ds:0x519328]
	retn]])

	asmpatch(0x4b73d6, "call absolute " .. NewCode)
	for i = 0x4b73db, 0x4b73dd do mem.u1[i] = 0x90 end
	mem.u4[0x4b73e7 + 3] = StandartAssortPtr

	asmpatch(0x4b7454, "call absolute " .. NewCode)
	for i = 0x4b7459, 0x4b745b do mem.u1[i] = 0x90 end
	mem.u4[0x4b7465 + 3] = StandartAssortPtr

	--Setting "identifyied" flag:
	NewCode = asmproc([[
	call absolute ]] .. GetCurHouseWritePos .. [[;
	mov ecx, eax
	mov eax, dword [ds:0x519328]
	lea ecx, dword [ds:ecx+ecx*2]
	lea ecx, dword [ds:edi+ecx*4]
	lea ecx, dword [ds:ecx+ecx*8]
	mov dword [ds:ecx*4+]] .. StandartAssortPtr + 0x14 .. [[], 0x1;
	jmp absolute 0x4b7487]])
	asmpatch(0x4b7470, "jmp absolute " .. NewCode)

	--Fill cycle ending:
	NewCode = asmproc([[
	mov eax, dword [ds:]] .. CurHouseID .. [[];
	mov esi, eax
	mov ecx, esi
	imul ecx, ecx, 0x34
	movsx ecx, word [ds:ecx+]] .. HousesPtr .. [[];
	movzx ecx, byte [ds:ecx+0x500a24];
	inc edi
	cmp edi, ecx
	jmp absolute 0x4b74a0]])
	asmpatch(0x4b7487, "jmp absolute " .. NewCode)

	--Procedure end:
	NewCode = asmproc([[
	push ecx
	call absolute ]] .. GetCurHouseWritePos .. [[;
	pop ecx
	and dword [ds:eax*4+]] .. FillStatePtr2 .. [[], 0;
	pop edi
	pop esi
	jmp absolute 0x4b74b5]])
	asmpatch(0x4b74a8, "jmp absolute " .. NewCode)

	------

	--Weapon shop special:
	NewCode = asmproc([[
	push eax
	push ecx
	call absolute ]] .. GetCurHouseType .. [[;
	cmp ax, 0x1; Index of house type "weapon shop".
	jnz @neq
	call absolute ]] .. GetCurHouseIndexByType .. [[;
	mov esi, eax
	pop ecx
	pop eax
	dec esi
	lea eax, dword [esi+esi*4]
	movsx ebp, word [ds:eax*2+]] .. SpRWepPtr .. [[];
	call absolute 0x4d99f2
	cdq
	push 0x4
	pop ecx
	idiv ecx
	lea eax, dword [ds:esi+esi*4]
	add edx, eax
	movsx ecx, word [ds:edx*2+]] .. SpRWepPtr + 2 .. [[];
	jmp absolute 0x4b75c3
	@neq:
	pop ecx
	pop eax
	jmp absolute 0x4b7511]])
	asmpatch(0x4b74e1, "jmp absolute " .. NewCode)

	--Armor shop special:
	NewCode = asmproc([[
	push eax
	push ecx
	call absolute ]] .. GetCurHouseType .. [[;
	cmp ax, 0x2
	jnz @neq
	call absolute ]] .. GetCurHouseIndexByType .. [[;
	mov esi, eax
	pop ecx
	pop eax
	xor eax, eax
	cmp ebx, 0x3
	setg al
	push eax
	dec esi
	push esi
	lea esi, dword [ds:eax+esi*2]
	nop;mov dword [ss:esp+0x10], eax
	lea eax, dword [ds:esi+esi*4]
	movsx ebp, word [ds:eax*2+]] .. SpRArmPtr .. [[];
	pop esi
	call absolute 0x4d99f2
	cdq
	push 4
	pop ecx
	idiv ecx
	pop eax
	nop;mov eax, dword [ss:esp+0x10]
	lea eax, dword [ds:eax+esi*2]
	lea eax, dword [ds:eax+eax*4]
	add edx, eax
	movsx ecx, word [ds:edx*2+]] .. SpRArmPtr + 2 .. [[];
	jmp absolute 0x4b75c3
	@neq:
	pop ecx
	pop eax
	jmp absolute 0x4b7555]])
	asmpatch(0x4b7511, "jmp absolute " .. NewCode)

	--Magic shop special:
	NewCode = asmproc([[
	push eax
	push ecx
	call absolute ]] .. GetCurHouseType .. [[;
	cmp ax, 0x3
	jnz @neq
	call absolute ]] .. GetCurHouseIndexByType .. [[;
	mov esi, eax
	pop ecx
	pop eax
	dec esi
	movsx ebp, word [ds:esi*2+]] .. SpRMagPtr .. [[];
	push 0x16
	jmp absolute 0x4b75c2
	@neq:
	pop ecx
	pop eax
	jmp absolute 0x4b7566]])
	asmpatch(0x4b7555, "jmp absolute " .. NewCode)

	--Weapon, armor and magic shops store table:
	NewCode = asmproc([[
	push ecx
	call absolute ]] .. GetCurHouseWritePos .. [[;
	pop ecx
	mov esi, eax
	lea eax, dword [ds:esi+esi*2]
	lea eax, dword [ds:ebx+eax*4]
	lea eax, dword [ds:eax+eax*8]
	lea eax, dword [ds:eax*4+]] .. SpecialAssortPtr .. [[];
	push 0x0
	push eax
	push ecx
	push ebp
	jmp absolute 0x4b75d8]])
	asmpatch(0x4b75c3, "jmp absolute " .. NewCode)

	NewCode = asmproc([[
	lea eax, dword [ds:esi+esi*2]
	lea eax, dword [ds:ebx+eax*4]
	lea eax, dword [ds:eax+eax*8]
	mov dword [ds:eax*4+]] .. SpecialAssortPtr + 0x14 .. [[], 0x1; "Identifyied" flag.
	jmp absolute 0x4b7602]])
	asmpatch(0x4b75e2, "jmp absolute " .. NewCode)

	--Alchemical shop special:
	NewCode = asmproc([[
	push eax
	push ecx
	call absolute ]] .. GetCurHouseType .. [[;
	cmp ax, 0x4
	jnz @neq
	call absolute ]] .. GetCurHouseIndexByType .. [[;
	mov esi, eax
	pop ecx
	pop eax
	dec esi
	cmp ebx, 0x6
	jge absolute 0x4b75b8
	jmp absolute 0x4b7574
	@neq:
	pop ecx
	pop eax
	jmp absolute 0x4b7602]])
	asmpatch(0x4b7566, "jmp absolute " .. NewCode)

	NewCode = asmproc([[
	movsx ebp, word [ds:esi*2+]] .. SpRAlcPtr .. [[]; Alhcemical shop rules start (original pointer - 0x500ba0)
	jmp absolute 0x4b75c0]])
	asmpatch(0x4b75b8, "jmp absolute " .. NewCode)

	-- Alchemical shop store table:
	NewCode = asmproc([[
	call absolute ]] .. GetCurHouseWritePos .. [[;
	mov esi, eax
	lea eax, dword [ds:esi+esi*2]
	lea eax, dword [ds:ebx+eax*4]
	lea eax, dword [ds:eax+eax*8]
	lea ecx, dword [ds:eax*4+]] .. SpecialAssortPtr .. [[];
	call absolute 0x403135
	call absolute 0x4d99f2
	cdq
	push 0x20
	pop ecx
	idiv ecx
	mov eax, esi
	lea eax, dword [ds:eax+eax*2]
	lea eax, dword [ds:ebx+eax*4]
	lea eax, dword [ds:eax+eax*8]
	add edx, 0x2bc
	mov dword [ds:eax*4+]] .. SpecialAssortPtr .. [[], edx
	jmp absolute 0x4b7602]])
	asmpatch(0x4b7574, "jmp absolute " .. NewCode)

	--End of cycle:
	NewCode = asmproc([[
	mov eax, dword [ds:]] .. CurHouseID .. [[];
	mov esi, eax
	imul eax, eax, 0x34
	movsx eax, word [ds:eax+]] .. HousesPtr .. [[];
	movzx eax, byte [ds:eax+0x500a24];
	inc ebx
	cmp ebx, eax
	jmp absolute 0x4b761b]])
	asmpatch(0x4b7602, "jmp absolute " .. NewCode)

	--End of procedure
	NewCode = asmproc([[
	call absolute ]] .. GetCurHouseWritePos .. [[;
	and dword [ds:eax*4+]] .. FillStatePtr2 .. [[], 0x0;
	pop edi
	pop esi
	pop ebp
	pop ebx
	pop ecx
	jmp absolute 0x4b7631]])
	asmpatch(0x4b7621, "jmp absolute " .. NewCode)

	-----

	-- events for extra controls
	-- common shops
	autohook2(0x4bb000, function(d)
		local Assortment = Game.ShopItems[d.eax - 1]
		events.cocall("ShopRefilled", Assortment)
	end)

	-- guilds
	autohook2(0x4bb2b1, function(d)
		-- FIXME: show used item sets; show full table
		local t = { House = mem.u4[CurHouseID], Items = {} }
		t.HouseType = Game.Houses[t.House].Type
		--t.RuleId = Game.HousesExtra[t.House].IndexByType
		t.AssortmentId = mem.call(MO.GetGuildAssortId, 1, t.House)
		--local Assortment = Game.GuildItems[Game.HousesExtra[mem.u4[CurHouseID]].IndexByType - 1]
		local Assortment = Game.GuildItems[t.AssortmentId]
		if t.HouseType == 5 or t.HouseType == 14 then
			t.Items[0] = Game.GuildItems[t.AssortmentId][0]
		end
		if t.HouseType == 6 or t.HouseType == 14 then
			t.Items[1] = Game.GuildItems[t.AssortmentId][1]
		end
		if t.HouseType == 7 or t.HouseType == 14 then
			t.Items[2] = Game.GuildItems[t.AssortmentId][2]
		end
		if t.HouseType == 8 or t.HouseType == 14 then
			t.Items[3] = Game.GuildItems[t.AssortmentId][3]
		end
		if t.HouseType == 9 or t.HouseType == 15 then
			t.Items[4] = Game.GuildItems[t.AssortmentId][4]
		end
		if t.HouseType == 10 or t.HouseType == 15 then
			t.Items[5] = Game.GuildItems[t.AssortmentId][5]
		end
		if t.HouseType == 11 or t.HouseType == 15 then
			t.Items[6] = Game.GuildItems[t.AssortmentId][6]
		end
		if t.HouseType == 12 or t.HouseType == 16 then
			t.Items[7] = Game.GuildItems[t.AssortmentId][7]
		end
		if t.HouseType == 13 or t.HouseType == 16 then
			t.Items[8] = Game.GuildItems[t.AssortmentId][8]
		end
		if t.HouseType == 33 then
			t.Items[9] = Game.GuildItems[t.AssortmentId][9]
		end
		if t.HouseType == 34 then
			t.Items[10] = Game.GuildItems[t.AssortmentId][10]
		end
		if t.HouseType == 36 then
			t.Items[11] = Game.GuildItems[t.AssortmentId][11]
		end
		events.cocall("GuildRefilled", Assortment)
	end)

	----Spellbook shops:

		-- Fill state pointers:

	NewCode = asmproc([[
	call absolute ]] .. GetCurHouseWritePos .. [[;
	dec eax
	mov ecx, dword [ds:eax*8+]] .. SBFillStatePtr+4 .. [[];
	jmp absolute 0x4bb298]])
	asmpatch(0x4bb291, "jmp absolute " .. NewCode)
	mem.u4[0x4bb2a2 + 3] = SBFillStatePtr

	NewCode = asmproc([[
	push eax
	push ecx
	call absolute ]] .. GetCurHouseWritePos .. [[;
	dec eax
	mov edi, eax
	pop ecx
	pop eax
	mov dword [ds:edi*8+]] .. SBFillStatePtr .. [[], eax
	mov dword [ds:edi*8+]] .. SBFillStatePtr + 4 .. [[], edx
	jmp absolute 0x4bb2fe]])
	asmpatch(0x4bb2f0, "jmp absolute " .. NewCode)

	NewCode = asmproc([[
	push ecx
	call absolute ]] .. GetCurHouseWritePos .. [[;
	pop ecx
	dec eax
	retn]])

	asmpatch(0x4b4999, "call absolute " .. NewCode)
	for i = 0x4b499e, 0x4b49a0 do mem.u1[i] = 0x90 end
	mem.u4[0x4b49a1 + 3] = SBFillStatePtr
	mem.u4[0x4b49ae + 3] = SBFillStatePtr + 4

		-- Assortment pointers:
		-- TODO: check return value to be bigger than 0 (before dec eax)?
	
	--   Load items icons
	asmpatch(0x4B4815, [[
	push ecx
	mov ecx, eax
	call absolute ]] .. MO.GetGuildAssortId .. [[;
	dec eax
	pop ecx
	]])
	mem.u4[0x4b4829 + 3] = SpellbooksAssortPtr

	asmpatch(0x4B48B6, [[
	push ecx
	mov ecx, eax
	call absolute ]] .. MO.GetGuildAssortId .. [[;
	dec eax
	pop ecx
	]])
	mem.u4[0x4b48ca + 3] = SpellbooksAssortPtr

	asmpatch(0x4B4953, [[
	mov ecx, eax
	call absolute ]] .. MO.GetGuildAssortId .. [[;
	dec eax
	]])
	mem.u4[0x4b4968 + 1] = SpellbooksAssortPtr

	--   Generate items
	--    Set start and end by house type (ecx)
	asmpatch(0x4BA928, [[
	lea edx, [ecx - 5]
	cmp edx, 9
	jl @single
	jz @elem
	sub edx, 0xA
	jz @self
	dec edx
	jz @mirror
	sub edx, 0x11
	jz @elem2
	dec edx
	jz @self2
	mov edx, 0xB
	jmp @single
	@self2:
	mov edx, 0xA
	jmp @single
	@elem2:
	mov edx, 9
	jmp @single
	@mirror:
	mov edx, 7
	mov dword ptr [ebp - 8], edx
	inc edx
	jmp @end
	@self:
	mov edx, 4
	mov dword ptr [ebp - 8], edx
	add edx, 2
	jmp @end
	@elem:
	xor edx, edx
	mov dword ptr [ebp - 8], edx
	add edx, 3
	jmp @end
	@single:
	mov dword ptr [ebp - 8], edx
	@end:
	inc edx
	mov dword ptr [ebp - 4], edx
	]])
	--[=[
	asmpatch(0x4BA928, [[
	and dword ptr [ebp - 8], 0
	mov dword ptr [ebp - 4], 0xC
	]])
	]=]
	
	asmpatch(0x4BA947, [[
	push ecx
	mov ecx, eax
	call absolute ]] .. MO.GetGuildAssortId .. [[;
	dec eax
	pop ecx
	]])
	mem.u4[0x4ba95b + 3] = SpellbooksAssortPtr

	--     Elem2, Self2 and Mirrored2 items (9-11)
	asmpatch(0x4BA974, [[
	mov eax, dword ptr [ebp - 8]
	cmp eax, 9
	jl @std
	push edx
	push eax
	call absolute 0x4D99F2 ;  Rand
	pop ecx
	cdq
	cmp ecx, 0xA
	jl @elem
	jz @self
	push 2
	pop ecx
	idiv ecx
	lea eax, [edx + 7]
	jmp @end
	@self:
	push 3
	pop ecx
	idiv ecx
	lea eax, [edx + 4]
	jmp @end
	@elem:
	push 4
	pop ecx
	idiv ecx
	mov eax, edx
	@end:
	pop edx
	@std:
	imul eax, 0xB
	push 0
	]])

	mem.nop(0x4BA9BA, 4)
	asmpatch(0x4BA9C1, [[
	mov eax, dword ptr [ebp - 4]
	cmp dword ptr [ebp - 8], eax
	]])

	--
	-- Elem2, Self2, Mirrored2 BuySpells house screens
	asmpatch(0x4BB288, [[
	jle @end
	cmp ebp, 0x79
	jl @ff
	cmp ebp, 0x7B
	jle @end
	@ff:
	jmp absolute 0x4BB3F0
	@end:
	]])

	--[=[
	NewCode = asmproc([[
	mov eax, ebp
	sub eax, 0x6e
	mov ecx, eax
	push ecx
	call absolute ]] .. GetCurHouseIndexByType .. [[;
	pop ecx
	dec eax
	lea eax, dword [ds:eax+eax*2]
	lea eax, dword [ds:ecx+eax*4]
	lea eax, dword [ds:eax+eax*2]
	lea eax, dword [ds:edi+eax*4]
	lea eax, dword [ds:eax+eax*8]
	mov eax, dword [ds:eax*4+]] .. SpellbooksAssortPtr .. [[];
	jmp absolute 0x4bb31d]])
	asmpatch(0x4bb300, "jmp absolute " .. NewCode)
	]=]
	asmpatch(0x4BB303, [[
	mov ecx, eax
	call absolute ]] .. MO.GetGuildAssortId .. [[;
	dec eax
	lea ecx, [ebp - 0x6E]
	cmp ecx, 9
	jl @ff
	sub ecx, 2
	@ff:
	lea eax, dword ptr [eax + eax * 2]
	lea eax, dword ptr [ecx + eax * 4]
	]], 0x4BB30D - 0x4BB303)
	mem.u4[0x4BB316 + 3] = SpellbooksAssortPtr

	NewCode = asmproc([[
	push ecx
	call absolute ]] .. GetCurHouseIndexByType .. [[;
	pop ecx
	dec eax
	lea ebx, dword [ds:eax*2+]] .. RSBPtr .. [[]; - Spellbook shops rules start (original pointer - 0x501122)
	jmp absolute 0x4ba93a]])
	asmpatch(0x4ba933, "jmp " .. NewCode .. " - 0x4ba933")

	NewCode = asmproc([[
	;call absolute ]] .. GetCurHouseIndexByType .. [[;
	mov ecx, dword ptr [0x519328]
	mov ecx, dword ptr [ecx + 0x1C]
	call absolute ]] .. MO.GetGuildAssortId .. [[;

	dec eax
	mov ecx, eax
	mov eax, dword [ds:0x518678]
	imul ecx, ecx, 0xc
	add ecx, esi
	imul ecx, ecx, 0xc
	lea ecx, dword [ds:ecx+edx-1]
	imul ecx, ecx, 0x24
	lea esi, dword [ds:ecx+]] .. SpellbooksAssortPtr .. [[];
	push 0x2
	push ebx
	jmp absolute 0x4b4a36]])
	asmpatch(0x4b4a11, "jmp absolute " .. NewCode)

	-- Action 81 (LeftClick/Buy)
	NewCode = asmproc([[
	;call absolute ]] .. GetCurHouseIndexByType .. [[;
	mov ecx, dword ptr [0x519328]
	mov ecx, dword ptr [ecx + 0x1C]
	call absolute ]] .. MO.GetGuildAssortId .. [[;

	dec eax
	mov ecx, eax
	mov eax, dword [ds:0x519328]
	mov eax, dword [ds:eax+0x1c]
	imul eax, eax, 0x34
	fld dword [ds:eax+]] .. HousesPtr + 0x20 .. [[];
	imul ecx, ecx, 0xc
	add ecx, esi
	imul ecx, ecx, 0xc
	lea ecx, dword [ds:ecx+edx-1]
	imul ecx, ecx, 0x24
	lea esi, dword [ds:ecx+]] .. SpellbooksAssortPtr .. [[];
	jmp absolute 0x4bbb0f]])
	asmpatch(0x4bbae4, "jmp absolute " .. NewCode)

	-- Action 81 (LeftClick/Buy) in MagicElem, MagicSelf, MagicMirrored subscreens
	asmpatch(0x4BBA9A, [[
	jle @end
	cmp eax, 0x79
	jl @ff
	cmp eax, 0x7B
	jg @ff
	dec eax
	dec eax
	jmp @end
	@ff:
	jmp absolute 0x4BBD61
	@end:
	]])

	-- El2, Se2, Mi2 BuySpells house screens
	asmpatch(0x4B01B6, [[
	jle @end
	cmp eax, 0x79
	jl @ff
	cmp eax, 0x7B
	jle @end
	@ff:
	jmp absolute 0x4B02BA
	@end:
	]])

	NewCode = asmproc([[
	push ecx
	;call absolute ]] .. GetCurHouseIndexByType .. [[;
	mov ecx, dword ptr [0x519328]
	mov ecx, dword ptr [ecx + 0x1C]
	call absolute ]] .. MO.GetGuildAssortId .. [[;

	pop ecx
	dec eax
	imul eax, eax, 0xc
	mov edx, dword [ds:0xffd408]
	
	cmp edx, 0x76
	jle @std
	sub edx, 2
	@std:

	lea eax, dword [ds:eax+edx-0x6e]
	imul eax, eax, 0xc
	lea eax, dword [ds:eax+ecx-1]
	imul eax, eax, 0x24
	lea ecx, dword [ds:eax+]] .. SpellbooksAssortPtr .. [[];
	jmp absolute 0x4b0228]])
	asmpatch(0x4b0200, "jmp absolute " .. NewCode)


	----

	---- Training halls:

	NewCode = asmproc([[
	push ecx
	call absolute ]] .. GetCurHouseType .. [[;
	cmp ax, 0x1e
	jnz @neq
	call absolute ]] .. GetCurHouseIndexByType .. [[;
	pop ecx
	dec eax
	jmp absolute 0x4b320c
	@neq:
	pop ecx
	jmp absolute 0x4b3911]])
	asmpatch(0x4b31f8, "jmp absolute " .. NewCode)

	NewCode = asmproc([[;
	push ecx
	call absolute ]] .. GetCurHouseIndexByType .. [[;
	pop ecx
	dec eax
	movzx eax, word [ds:eax*2+]] .. RTrHallPtr .. [[]; 0x500caa - original pointer.
	jmp absolute 0x4b324e]])
	asmpatch(0x4b3246, "jmp absolute " .. NewCode)

	NewCode = asmproc([[;
	push ecx
	call absolute ]] .. GetCurHouseIndexByType .. [[;
	pop ecx
	dec eax
	movzx eax, word [ds:eax*2+]] .. RTrHallPtr .. [[];
	jmp absolute 0x4b314f]])
	asmpatch(0x4b313f, "jmp absolute " .. NewCode)

	---- Taverns:

	NewCode = asmproc([[
	call absolute ]] .. GetCurHouseIndexByType .. [[;
	cmp eax, 0x0
	je @Rai
	cmp eax, ]] .. TavCount .. [[;
	jle @norm
	@Rai:
	mov eax, ]] .. math.random(TavCount) .. [[;
	@norm:
	dec eax
	lea eax, dword [ds:eax+eax*2]
	lea eax, dword [ds:eax*8+]] .. RTavernsPtr .. [[];
	jmp absolute 0x40a783]])
	asmpatch(0x40a76e, "jmp absolute " .. NewCode)

	NewCode = asmproc([[
	call absolute ]] .. GetCurHouseType .. [[;
	cmp ax, 0x15
	mov eax, dword [ds:0x519328]
	mov ecx, dword [ds:eax+0x1c]
	mov edi, 0xb20e90
	jnz absolute 0x40e868
	jmp absolute 0x40e804]])
	asmpatch(0x40e7ed, "jmp absolute " .. NewCode)
	--0xb215e4 - "Win in tavern ¹" flags block.

	--New "rules" topic managment.
	NewCode = asmproc([[
	push ecx
	call absolute ]] .. GetCurHouseIndexByType .. [[;
	dec eax
	movzx eax, word [ds:eax*2+]] .. AMRulesTopicsPtr .. [[];
	mov ecx, dword [ds:0x444f76]
	lea eax, dword [ds:eax*8+ecx]
	pop ecx
	push dword [ds:eax]; Pointer to NPCtext, original: 0x75e53c, original start: 0x75e44c .
	jmp absolute 0x4b713d]])
	asmpatch(0x4b712e, "jmp absolute " .. NewCode)

	--Disabling writing "Win in tavern ¹" flag for additional taverns,
	--though player will not get gold and these flags could be needed in future.
	--Adding event.

	-- function events.ArcomageMatchEnd(t) end

	NewCode = asmproc([[
	push eax
	push ecx
	call absolute ]] .. GetCurHouseIndexByType .. [[;
	nop; memhook here.
	nop;
	nop;
	nop;
	nop;
	cmp eax, 0x0
	je @end2
	cmp eax, ]] .. OldTavCount .. [[;
	jg @end2
	pop ecx
	pop eax
	cmp byte [ds:ecx], 0x0
	jnz absolute 0x40e868
	jmp absolute 0x40e80f
	@end2:
	pop eax
	pop ecx
	jmp absolute 0x40e868]])
	asmpatch(0x40e80a, "jmp absolute " .. NewCode)

	do
		local ArcomageWinHandled
		autohook(0x40e7d6, function(d)
			-- result values:
			-- -1 - player canceled match
			-- 0 - tie
			-- 1 - player won
			-- 2 - enemy won
			local t = {House = mem.u4[CurHouseID], result = d.esi, Handled = false}
			ArcomageWinHandled = false
			events.call("ArcomageMatchEnd", t)
			if t.Handled then
				ArcomageWinHandled = true
			end
		end)

		hook(NewCode+7, function(d)
			if ArcomageWinHandled then
				d.eax = 0x0
			end
		end)
	end

	---- Stables and boats:

	NewCode = asmproc([[
	push ecx
	call absolute ]] .. GetCurHouseWritePos .. [[;
	pop ecx
	imul eax, eax, 0x4
	add eax, ebp
	sub eax, 0x69
	movzx edi, byte [ss:eax+]] .. TranIndexPtr ..[[]
	jmp absolute 0x4bab72]])
	asmpatch(0x4bab61, "jmp absolute " .. NewCode)

	NewCode = asmproc([[
	push eax
	push dword [ds:0x518678]
	mov dword [ds:0x518678], edi
	call absolute ]] .. GetCurHouseType .. [[;
	cmp eax, 0x1b
	je @equ
	cmp eax, 0x1c
	jnz @neq
	@equ:
	call absolute ]] .. GetCurHouseWritePos .. [[;
	dec eax
	mov ecx, eax
	pop dword [ds:0x518678]
	pop eax
	jmp absolute 0x443497
	@neq:
	pop dword [ds:0x518678]
	pop eax
	jmp absolute 0x4434a0]])
	asmpatch(0x44348a, "jmp absolute " .. NewCode)
	mem.u4[0x4b50cc + 3] = TranIndexPtr

	NewCode = asmproc([[
	call absolute ]] .. GetCurHouseWritePos .. [[;
	dec eax
	mov ecx, dword [ss:ebp-0xc]
	movzx esi, byte [ds:ecx+eax*4+]] .. TranIndexPtr .. [[]; TransportIndex pointer (0x501118).
	mov eax, dword [ds:0x518678]
	jmp absolute 0x4b558d]])
	asmpatch(0x4b557a, "jmp absolute " .. NewCode)

	NewCode = asmproc([[
	push eax
	push ecx
	call absolute ]] .. GetCurHouseWritePos .. [[;
	dec eax
	sub esi, 0x69
	movzx esi, byte [ds:esi+eax*4+]] .. TranIndexPtr .. [[];
	pop ecx
	pop eax
	jmp absolute 0x4b5193]])
	asmpatch(0x4b518b, "jmp absolute " .. NewCode)

	NewCode = asmproc([[
	push eax
	call absolute ]] .. GetCurHouseType .. [[;
	cmp eax, 0x1c
	movzx ecx, byte [ds:esi+8]
	pop eax
	jmp absolute 0x4b51b7]])
	asmpatch(0x4b51b2, "jmp absolute " .. NewCode)
	mem.nop(0x4b51b7, 2)
	asmpatch(0x4b51bd, "je 0xb")

	---- New condition for non-Wep/Arm/Mag/Alc shops.

	NewCode = asmproc([[
	push eax
	call absolute ]] .. GetCurHouseType .. [[;
	cmp eax, 0x0
	je @end2
	cmp eax, 0x4
	jg @end2
	pop eax
	call absolute ]] .. GetCurHouseWritePos .. [[;
	mov edx, dword [ds:eax*8+]] .. RepPtr2 .. [[];
	mov ecx, dword [ds:eax*8+]] .. RepPtr2+4 .. [[];
	jmp absolute 0x414d54
	@end2:
	pop eax
	jmp absolute 0x41556c]])
	asmpatch(0x414d3d, "jmp absolute " .. NewCode)

	NewCode = asmproc([[
	push eax
	call absolute ]] .. GetCurHouseType .. [[;
	cmp eax, 0x0
	je @end2
	cmp eax, 0x4
	jg @end2
	pop eax
	push ecx
	call absolute ]] .. GetCurHouseWritePos .. [[;
	pop ecx
	mov dword [ds:eax*8+]] .. RepPtr2 .. [[], edi;
	mov dword [ds:eax*8+]] .. RepPtr2+4 .. [[], edi;
	jmp absolute 0x414d8b
	@end2:
	pop eax
	jmp absolute 0x41556c]])
	asmpatch(0x414d74, "jmp absolute " .. NewCode)

	NewCode = asmproc([[
	call absolute ]] .. GetCurHouseWritePos .. [[;
	mov ecx, dword [ds:]] .. CurHouseID .. [[];
	mov eax, dword [ds:eax*8+]] .. RepPtr2+4 .. [[];
	cmp eax, dword [ds:0xb20ec0]
	jl absolute 0x4b05b6
	jg absolute 0x4b0535
	call absolute ]] .. GetCurHouseWritePos .. [[;
	mov ecx, dword [ds:]] .. CurHouseID .. [[];
	mov eax, dword [ds:eax*8+]] .. RepPtr2 .. [[];
	cmp eax, dword [ds:0xb20ebc]
	jmp absolute 0x4b052f]])
	asmpatch(0x4b0505, "jmp absolute " .. NewCode)
	mem.u4[0x4b050d + 3] = RepPtr2+4
	mem.u4[0x4b0522 + 3] = RepPtr2

	NewCode = asmproc([[
	push dword [ds:]] .. CurHouseID .. [[];
	mov dword [ds:]] .. CurHouseID .. [[], eax;
	call absolute ]] .. GetCurHouseType .. [[;
	cmp eax, 0x0
	je @end2
	cmp eax, 0x4
	jg @end2
	call absolute ]] .. GetCurHouseWritePos .. [[;
	mov ecx, eax
	lea eax, dword [ds:eax*8+]] .. RepPtr2 .. [[];
	pop dword [ds:]] .. CurHouseID .. [[];
	jmp absolute 0x4431d5
	@end2:
	mov eax, dword [ds:ebp-0x14]
	pop dword [ds:]] .. CurHouseID .. [[];
	jmp absolute 0x44320a]])
	asmpatch(0x4431c9, "jmp absolute " .. NewCode)

	-- 0x4430b4 - condition for 600 - 601 houses, would be great to dig there.

	----
	---- Reputation pointers:
	--[=[
	-- cthscr: these pointers are for evt CounterN rather than for houses
	NewCode = asmproc([[
	push ecx
	push dword [ds:]] .. CurHouseID .. [[];
	mov dword [ds:]] .. CurHouseID .. [[], eax
	call absolute ]] .. GetCurHouseWritePos .. [[;
	mov esi, dword [ds:eax*8+]] .. RepPtr .. [[];
	mov edi, dword [ds:eax*8+]] .. RepPtr+4 .. [[];
	pop dword [ds:]] .. CurHouseID .. [[];
	pop ecx
	mov eax, esi
	jmp absolute 0x4479a3]])
	asmpatch(0x447993, "jmp absolute " .. NewCode)

	NewCode = asmproc([[
	push ecx
	call absolute ]] .. GetCurHouseWritePos .. [[;
	pop ecx
	mov dword [ds:eax*8+]] .. RepPtr .. [[], ecx
	retn]])

	asmpatch(0x448377, "call absolute " .. NewCode)
	asmpatch(0x448d25, "call absolute " .. NewCode)

	NewCode = asmproc([[
	push ecx
	call absolute ]] .. GetCurHouseWritePos .. [[;
	pop ecx
	mov dword [ds:eax*8+]] .. RepPtr+4 .. [[], ecx
	retn]])

	asmpatch(0x448384, "call absolute " .. NewCode)
	asmpatch(0x448d32, "call absolute " .. NewCode)
	]=]
	----

	---- Assortment pointers:
	NewCode = asmproc([[
	push ecx
	call absolute ]] .. GetCurHouseWritePos .. [[;
	pop ecx
	retn]])

	--Standart assortment:

	asmpatch(0x4b4180, "call absolute " .. NewCode)
	for i = 0x4b4185, 0x4b4187 do mem.u1[i] = 0x90 end
	mem.u4[0x4b4191 + 3] = StandartAssortPtr

	asmpatch(0x4b447c, "call absolute " .. NewCode)
	for i = 0x4b4481, 0x4b4483 do mem.u1[i] = 0x90 end
	mem.u4[0x4b448d + 3] = StandartAssortPtr

	asmpatch(0x4b4554, "call absolute " .. NewCode)
	for i = 0x4b4563, 0x4b4565 do mem.u1[i] = 0x90 end
	mem.u4[0x4b456f + 3] = StandartAssortPtr

	asmpatch(0x4b7f27, "call absolute " .. NewCode)
	for i = 0x4b7f2c, 0x4b7f2e do mem.u1[i] = 0x90 end
	mem.u4[0x4b7f38 + 3] = StandartAssortPtr

	asmpatch(0x4b7fff, "call absolute " .. NewCode)
	for i = 0x4b800e, 0x4b8010 do mem.u1[i] = 0x90 end
	mem.u4[0x4b801a + 3] = StandartAssortPtr

	asmpatch(0x4b8844, "call absolute " .. NewCode)
	for i = 0x4b8849, 0x4b884b do mem.u1[i] = 0x90 end
	mem.u4[0x4b8858 + 3] = StandartAssortPtr

	asmpatch(0x4b8b54, "call absolute " .. NewCode)
	for i = 0x4b8b59, 0x4b8b5b do mem.u1[i] = 0x90 end
	mem.u4[0x4b8b65 + 3] = StandartAssortPtr

	asmpatch(0x4b8c2c, "call absolute " .. NewCode)
	for i = 0x4b8c3b, 0x4b8c3d do mem.u1[i] = 0x90 end
	mem.u4[0x4b8c47 + 3] = StandartAssortPtr

	asmpatch(0x4b9585, "call absolute " .. NewCode)
	for i = 0x4b958a, 0x4b958c do mem.u1[i] = 0x90 end
	mem.u4[0x4b9596 + 3] = StandartAssortPtr

	asmpatch(0x4b9734, "call absolute " .. NewCode)
	for i = 0x4b9739, 0x4b973b do mem.u1[i] = 0x90 end
	mem.u4[0x4b9745 + 3] = StandartAssortPtr

	asmpatch(0x4b980c, "call absolute " .. NewCode)
	for i = 0x4b981b, 0x4b981d do mem.u1[i] = 0x90 end
	mem.u4[0x4b9827 + 3] = StandartAssortPtr

	asmpatch(0x4bbc06, "call absolute " .. NewCode)
	for i = 0x4bbc0b, 0x4bbc0d do mem.u1[i] = 0x90 end
	mem.u4[0x4bbc23 + 3] = StandartAssortPtr

	asmpatch(0x4b4238, "call absolute " .. NewCode)
	for i = 0x4b423d, 0x4b423f do mem.u1[i] = 0x90 end
	mem.u4[0x4b424c + 3] = StandartAssortPtr + 0xd8

	asmpatch(0x4b8901, "call absolute " .. NewCode)
	for i = 0x4b8906, 0x4b8908 do mem.u1[i] = 0x90 end
	mem.u4[0x4b8915 + 3] = StandartAssortPtr + 0xd8

	--Special assortment:

	--0x4b4578, 0x4b8023, 0x4b8c50, 0x4b9830, 0x4bbc2f - for both, corrected above.
	mem.u4[0x4b4578 + 3] = SpecialAssortPtr
	mem.u4[0x4b8023 + 3] = SpecialAssortPtr
	mem.u4[0x4b8c50 + 3] = SpecialAssortPtr
	mem.u4[0x4b9830 + 3] = SpecialAssortPtr
	mem.u4[0x4bbc2f + 3] = SpecialAssortPtr

	asmpatch(0x4b42ed, "call absolute " .. NewCode)
	for i = 0x4b42f2, 0x4b42f4 do mem.u1[i] = 0x90 end
	mem.u4[0x4b42fe + 3] = SpecialAssortPtr

	asmpatch(0x4b44a7, "call absolute " .. NewCode)
	for i = 0x4b44ac, 0x4b44ae do mem.u1[i] = 0x90 end
	mem.u4[0x4b44b8 + 3] = SpecialAssortPtr

	asmpatch(0x4b7e80, "call absolute " .. NewCode)
	for i = 0x4b7e85, 0x4b7e87 do mem.u1[i] = 0x90 end
	mem.u4[0x4b7e94 + 3] = SpecialAssortPtr

	asmpatch(0x4b7f52, "call absolute " .. NewCode)
	for i = 0x4b7f57, 0x4b7f59 do mem.u1[i] = 0x90 end
	mem.u4[0x4b7f63 + 3] = SpecialAssortPtr

	asmpatch(0x4b89c0, "call absolute " .. NewCode)
	for i = 0x4b89c5, 0x4b89c7 do mem.u1[i] = 0x90 end
	mem.u4[0x4b89d4 + 3] = SpecialAssortPtr

	asmpatch(0x4b8b7f, "call absolute " .. NewCode)
	for i = 0x4b8b84, 0x4b8b86 do mem.u1[i] = 0x90 end
	mem.u4[0x4b8b90 + 3] = SpecialAssortPtr

	asmpatch(0x4b9654, "call absolute " .. NewCode)
	for i = 0x4b9659, 0x4b965b do mem.u1[i] = 0x90 end
	mem.u4[0x4b9665 + 3] = SpecialAssortPtr

	asmpatch(0x4b975f, "call absolute " .. NewCode)
	for i = 0x4b9764, 0x4b9766 do mem.u1[i] = 0x90 end
	mem.u4[0x4b9770 + 3] = SpecialAssortPtr

	asmpatch(0x4b9ae6, "call absolute " .. NewCode)
	for i = 0x4b9aeb, 0x4b9aec do mem.u1[i] = 0x90 end
	mem.u4[0x4b9afa + 3] = SpecialAssortPtr

	asmpatch(0x4b43a5, "call absolute " .. NewCode)
	for i = 0x4b43aa, 0x4b43ac do mem.u1[i] = 0x90 end
	mem.u4[0x4b43b9 + 3] = SpecialAssortPtr + 0xd8

	asmpatch(0x4b8a7d, "call absolute " .. NewCode)
	for i = 0x4b8a82, 0x4b8a84 do mem.u1[i] = 0x90 end
	mem.u4[0x4b8a91 + 3] = SpecialAssortPtr + 0xd8

	---- Fill state pointers

	asmpatch(0x4b44dc, "call absolute " .. NewCode)
	for i = 0x4b44e1, 0x4b44e3 do mem.u1[i] = 0x90 end
	mem.u4[0x4b44e4 + 3] = FillStatePtr1
	mem.u4[0x4b44f1 + 3] = FillStatePtr1 + 0x4

	asmpatch(0x4b7f87, "call absolute " .. NewCode)
	for i = 0x4b7f8c, 0x4b7f8e do mem.u1[i] = 0x90 end
	mem.u4[0x4b7f8f + 3] = FillStatePtr1
	mem.u4[0x4b7f9c + 3] = FillStatePtr1 + 0x4

	asmpatch(0x4b8bb4, "call absolute " .. NewCode)
	for i = 0x4b8bb9, 0x4b8bbb do mem.u1[i] = 0x90 end
	mem.u4[0x4b8bbc + 3] = FillStatePtr1
	mem.u4[0x4b8bc9 + 3] = FillStatePtr1 + 0x4

	asmpatch(0x4b9794, "call absolute " .. NewCode)
	for i = 0x4b9799, 0x4b979b do mem.u1[i] = 0x90 end
	mem.u4[0x4b979c + 3] = FillStatePtr1
	mem.u4[0x4b97a9 + 3] = FillStatePtr1 + 0x4

	NewCode = asmproc([[
	push eax
	push ecx
	call absolute ]] .. GetCurHouseWritePos .. [[;
	mov edi, eax
	pop ecx
	pop eax
	mov dword [ds:edi*8+]] .. FillStatePtr1 .. [[], eax;
	mov dword [ds:edi*8+]] .. FillStatePtr1 + 0x4 .. [[], edx;
	jmp absolute 0x4bb053]])
	asmpatch(0x4bb045, "jmp absolute " .. NewCode)
	mem.u4[0x4bb04c + 3] = FillStatePtr1 + 0x4 --to avoid confuses.

	---- Custom assortment pointers:

	NewCode = asmproc([[
	push ecx
	call absolute ]] .. GetCurHouseWritePos .. [[;
	pop ecx
	lea eax, dword [ds:eax+eax*2]
	jmp absolute 0x4b99d0]])
	asmpatch(0x4b99d7, "jmp absolute " .. NewCode)
	mem.u4[0x4b99e3 + 3] = SpecialAssortPtr

	NewCode = asmproc([[
	push ecx
	call absolute ]] .. GetCurHouseWritePos .. [[;
	pop ecx
	dec ecx
	mov dword [ss:ebp-0x18], ecx
	jmp absolute 0x4b9a60]])
	asmpatch(0x4b9a54, "jmp absolute " .. NewCode)
	mem.u4[0x4b9a6c + 3] = SpecialAssortPtr

	NewCode = asmproc([[
	push eax
	call absolute ]] .. GetCurHouseWritePos .. [[;
	mov ecx, eax
	pop eax
	jmp absolute 0x4b7df8]])
	asmpatch(0x4b7def, "jmp absolute " .. NewCode)
	mem.u4[0x4b7e01 + 3] = StandartAssortPtr

	NewCode = asmproc([[
	push ecx
	call absolute ]] .. GetCurHouseWritePos .. [[;
	pop ecx
	lea eax, dword [ds:eax+eax*2]
	lea eax, dword [ds:edi+eax*4]
	nop; lea eax, dword [ds:eax+eax*8]
	retn]])

	asmpatch(0x4bb163, "call absolute " .. NewCode)
	mem.u4[0x4bb16c + 3] = SpecialAssortPtr

	asmpatch(0x4bb1ef, "call absolute " .. NewCode)
	mem.u4[0x4bb1f8 + 3] = SpecialAssortPtr

	asmpatch(0x4bb075, "call absolute " .. NewCode)
	mem.u4[0x4bb07e + 3] = StandartAssortPtr

	asmpatch(0x4bb101, "call absolute " .. NewCode)
	mem.u4[0x4bb10a + 3] = StandartAssortPtr

	---- Rules pointers correction (skills available to learn in shop):

	NewCode = asmproc([[
	push eax
	call absolute ]] .. GetCurHouseIndexByType .. [[;
	dec eax
	mov ecx, eax
	pop eax
	lea ecx, dword [ds:edi+ecx*2]
	lea edx, dword [ds:esi+ecx*4]
	add ecx, edx
	test ebx, ebx
	je @Stand
	movsx ecx, word [ds:ecx*2+]] .. SpRArmPtr .. [[];
	jmp @Spec
	@Stand:
	movsx ecx, word [ds:ecx*2+]] .. StRArmPtr .. [[];
	@Spec:
	jmp absolute 0x4b201d]])
	asmpatch(0x4b1ff5, "jmp absolute " .. NewCode)

	NewCode = asmproc([[
	push eax
	call absolute ]] .. GetCurHouseIndexByType .. [[;
	dec eax
	mov ecx, eax
	pop eax
	lea ebx, dword [ds:esi+ecx*4]
	add ecx, ebx
	test edi, edi
	je @Stand
	movsx ecx, word [ds:ecx*2+]] .. SpRWepPtr .. [[];
	jmp @Spec
	@Stand:
	movsx ecx, word [ds:ecx*2+]] .. StRWepPtr .. [[];
	@Spec:
	jmp absolute 0x4b208d]])
	asmpatch(0x4b2069, "jmp absolute " .. NewCode)

	---- Item identifictaion:

	NewCode = asmproc([[
	push eax
	call absolute ]] .. GetCurHouseWritePos .. [[;
	mov ecx, eax
	pop eax
	cmp dword [ds:0xffd408], 2
	jmp absolute 0x4b029c]])
	asmpatch(0x4b0293, "jmp absolute " .. NewCode)

	NewCode = asmproc([[
	push ecx
	call absolute ]] .. GetCurHouseWritePos .. [[;
	pop ecx
	jmp absolute 0x42057e]])
	asmpatch(0x420576, "jmp absolute " .. NewCode)

	mem.u4[0x420587 + 3] = StIdentCheckPtr--0xb7ca68
	mem.u4[0x4b02a5 + 3] = StIdentCheckPtr
	mem.u4[0x4b02ae + 3] = SpIdentCheckPtr

	----

	mem.u4[0x41B3A1 + 1] = 0x516efc

	local TmpT = {
			0x4130a2, 0x4168dd, 0x4169b1, 0x41f863, 0x42001b, 0x420208, 0x4204f4, 0x420550, 0x42061d,
			0x4212c5, 0x430975, 0x4315e0, 0x43291b, 0x467a62, 0x4b01df, 0x4b0270, 0x4b4536, 0x4b49f3,
			0x4b7fe1, 0x4b8c0e, 0x4b97ee, 0x4b9a2b, 0x4bbac6, 0x4bbbe8}

	for k,v in pairs(TmpT) do
		mem.u4[v+3] = 0x516efc
	end

--~ 	mem.u4[0x4b49f3 + 3] = 0x516efc
--~ 	mem.u4[0x4b97ee + 3] = 0x516efc
--~ 	mem.u4[0x4b7fe1 + 3] = 0x516efc
--~ 	mem.u4[0x4b0270 + 3] = 0x516efc
--~ 	mem.u4[0x4b4536 + 3] = 0x516efc
--~ 	mem.u4[0x4b9a2b + 3] = 0x516efc
--~ 	mem.u4[0x4b8c0e + 3] = 0x516efc
--~ 	mem.u4[0x4b01df + 3] = 0x516efc

	mem.IgnoreProtection(false)

	---- Revival of old single-school guilds:

	-- Refill triggering
	asmpatch(0x4ba916, "cmp ecx, 0x5")

	--   Mirrored, Elem2, Self2, Mirrored2 guilds
	asmpatch(0x4BA922, [[
	jle @end
	cmp ecx, 0x10
	je @end
	cmp ecx, 0x21
	jl @ff
	cmp ecx, 0x23
	jz @ff
	cmp ecx, 0x24
	jle @end
	@ff:
	jmp absolute 0x4BA9D1
	@end:
	]])

	asmpatch(0x4B1C0D, "cmp eax, 0x10")

	asmpatch(0x4B1C81, [[
	jz @end
	cmp eax, 0x21
	jl @ff
	cmp eax, 0x23
	jz @ff
	cmp eax, 0x24
	jg @ff
	call absolute 0x4B46F4
	@ff:
	jmp absolute 0x4B1EBC
	@end:
	]])

	-- Default topics setup
	--   Single school and Mirrored guilds topics
	NewCode = asmproc([[
	je absolute 0x4b254e
	cmp ecx, 0x5
	jl @neq
	cmp ecx, 0xB
	jle @start
	cmp ecx, 0x10
	jnz @neq

	; Mirrored guild
	push 0x75 ;  Light Magic
	pop edx
	xor ecx, ecx
	call absolute 0x4B1F3C
	push 0x76 ;  Dark Magic
	pop edx
	xor ecx, ecx
	inc ecx
	call absolute 0x4B1F3C
	push 0x60 ;  Learn Skills
	pop edx
	push 2
	pop ecx
	call absolute 0x4B1F3C
	push 2
	push 0
	push 1
	push 3
	jmp absolute 0x4B26FC

	@start:
	add ecx, 0x69
	push ecx; 				current guild topic
	pop edx
	xor ecx, ecx; 			topic position
	call absolute 0x4b1f3c

	push 0x60; 				"learn" topic
	pop edx
	xor ecx, ecx
	inc ecx
	call absolute 0x4b1f3c

	push 2
	push 0
	push 1
	push 2
	jmp absolute 0x4b26fc

	@neq:
	jmp absolute 0x4b2707]])
	asmpatch(0x4b2548, "jmp absolute " .. NewCode)

	--   El2, Se2, Mi2 guilds topics
	asmpatch(0x4B264B, [[
	jz @end
	cmp ecx, 0x21
	jl @neq
	cmp ecx, 0x22
	jle @el2se2
	cmp ecx, 0x24
	jnz @neq

	dec ecx
	@el2se2:
	add ecx, 0x58
	push ecx
	pop edx
	xor ecx, ecx
	call absolute 0x4B1F3C
	push 0x60
	pop edx
	xor ecx, ecx
	inc ecx
	call absolute 0x4B1F3C

	push 2
	push 0
	push 1
	push 2
	jmp absolute 0x4B26FC

	@neq:
	jmp absolute 0x4B2707

	@end:
	]])

	asmpatch(0x4B47EB, [[
	jle @end
	cmp eax, 0x79
	jl @ff
	cmp eax, 0x7B
	jg @ff
	sub eax, 2
	jmp @end
	@ff:
	jmp absolute 0x4B4A75
	@end:
	]])

	asmpatch(0x4B4DE5, [[
	jz absolute 0x4B4E36
	dec eax
	jz absolute 0x4B4E2E
	sub eax, 3
	jl @end
	cmp eax, 2
	jg @end
	mov edx, dword ptr [0x601A88] ; Buy Spells
	jmp absolute 0x4B4E4C
	@end:
	]])

	asmpatch(0x4B4F7C, [[
	jz absolute 0x4B4FBE
	dec eax
	jz absolute 0x4B4FB6
	sub eax, 3
	jl @end
	cmp eax, 2
	jg @end
	mov edi, dword ptr [0x601A88] ; Buy Spells
	jmp absolute 0x4B4FD4
	@end:
	]])

	-- "Learn" topic setup
	NewCode = asmproc([[
	je absolute 0x4b20e8

	cmp ecx, 0x5
	jl @neq
	cmp ecx, 0xB
	jg @neq

	add ecx, 0x2b
	mov dword [ss:ebp-0x1c], ecx
	jmp absolute 0x4b20ef

	@neq:
	jmp absolute 0x4b1f9d]])
	asmpatch(0x4b1f97, "jmp absolute " .. NewCode)

	--   Mirrored, Mi2 guilds
	asmpatch(0x4B210A, [[
	dec ecx
	jz @ff
	cmp ecx, 0x14
	jne @end
	@ff:
	mov dword ptr [ebp - 4], 3
	mov dword ptr [ebp - 0x1C], 0x37
	mov dword ptr [ebp - 0x18], 0x38
	mov dword ptr [ebp - 0x14], 0x40
	jmp absolute 0x4B21B2
	@end:
	sub ecx, 5
	jz absolute 0x4B2145
	]])
	--   El2, Se2 guilds
	asmpatch(0x4B2116, [[
	jl @ff
	je @end
	sub ecx, 3
	jz absolute 0x4B2188
	dec ecx
	jz absolute 0x4B2163
	@ff:
	jmp absolute 0x4B21B2
	@end:
	]])

	-- House subscreen / Action 405
	--   Mirrored, El2, Se2, Mi2 guilds
	asmpatch(0x4BACA7, [[
	cmp ecx, 0x10
	je absolute 0x4BAE92
	cmp ecx, 0x21
	jl @end
	cmp ecx, 0x23
	je @end
	cmp ecx, 0x24
	jg @end
	jmp absolute 0x4BAE92
	@end:
	jmp absolute 0x4BB3F0
	]])
	--   Background
	asmpatch(0x4BAC2E, [[
	cmp ecx, 0x21
	jl @end
	cmp ecx, 0x23
	je @end
	cmp ecx, 0x24
	jg @end
	mov ecx, 0xE
	@end:
	cmp ecx, 0x13
	mov edx, ebp
	]])
	--   Buy Spells topics (0x79, 0x7A, 0x7B)
	asmpatch(0x4BB288, [[
	jle @end
	cmp ebp, 0x79
	jl @ff
	cmp ebp, 0x7B
	jle @end
	@ff:
	jmp absolute 0x4BB3F0
	@end:
	]])

	-- Spellbook popup
	asmpatch(0x4B019C, "cmp eax, 0x10")
	asmpatch(0x4B019F, [[
	jle @end
	cmp eax, 0x21
	je @end
	cmp eax, 0x22
	je @end
	cmp eax, 0x24
	je @end
	jmp absolute 0x4B02BA
	@end:
	]])
	asmpatch(0x4B01B6, [[
	jle @end
	cmp eax, 0x79
	jl @ff
	cmp eax, 0x7B
	jle @end
	@ff:
	jmp absolute 0x4B02BA
	@end:
	]])

	---- DrawShopTopics event part

	local ShopTopicsParams = StaticAlloc(20)

	NewCode = asmproc([[
	push ecx
	nop
	nop
	nop
	nop
	nop
	test ecx, ecx
	jnz @neq

	pop ecx
	xor ecx, ecx

	@rep:
	movsx ecx, byte [ds:]] .. ShopTopicsParams + 15 .. [[];
	sub cl, byte [ds:]] .. ShopTopicsParams + 14 .. [[];
	movsx edx, word [ds:ecx*2+]] .. ShopTopicsParams .. [[];
	call absolute 0x4b1f3c
	dec byte [ds:]] .. ShopTopicsParams + 14 .. [[];
	jnz @rep

	push 2
	push 0
	push 1
	push dword [ds:]] .. ShopTopicsParams + 15 .. [[];
	jmp absolute 0x4b26fc

	@neq:
	pop ecx
	cmp ecx, edx
	jg absolute 0x4b2627
	jmp absolute 0x4b2517]])

	-- Topic names
	-- Indexes of GlobalTxt
	local ShopTopicNames = {
		[const.ShopTopics.Empty]		= 223,
		[const.ShopTopics.Standart]		= 134,
		[const.ShopTopics.Special]		= 152,
		[const.ShopTopics.Inventory]	= 159,
		[const.ShopTopics.Learn]		= 160,
		[const.ShopTopics.MagicFire]	= 283,
		[const.ShopTopics.MagicAir]		= 284,
		[const.ShopTopics.MagicWater]	= 285,
		[const.ShopTopics.MagicEarth]	= 286,
		[const.ShopTopics.MagicLight]	= 287,
		[const.ShopTopics.MagicDark]	= 288,
		[const.ShopTopics.MagicSpirit]	= 289,
		[const.ShopTopics.MagicMind]	= 290,
		[const.ShopTopics.MagicBody]	= 291,
		[const.ShopTopics.MagicElem]	= 400,
		[const.ShopTopics.MagicSelf]	= 400,
		[const.ShopTopics.MagicMirrored] = 400,
		[const.ShopTopics.PlayArcomage]	= 611,
	}

	local TopicsBackup = {}
	local NamesChanged = false
	hook(NewCode + 1, function(d)
		local t = {HouseType = d.ecx, NewTopics = {}, Handled = false}
		t.HouseId = GetCurrentHouse()
		events.call("DrawShopTopics", t)
		if t.Handled then
			local Count = 0
			for i = 1, 5 do
				local v = t.NewTopics[i] or 0
				mem.u2[ShopTopicsParams + (i-1)*2] = v
				Count = Count + ((v > 0 and 1) or 0)
			end
			mem.u2[ShopTopicsParams + 14] = Count
			mem.u2[ShopTopicsParams + 15] = Count
			d.ecx = 0

			for k,v in pairs(ShopTopicNames) do
				if not table.find(t.NewTopics, k) then
					NamesChanged = true
					TopicsBackup[v] = TopicsBackup[v] or Game.GlobalTxt[v]
					Game.GlobalTxt[v] = ""
				else
					Game.GlobalTxt[v] = TopicsBackup[v]
				end
			end

		elseif NamesChanged then
			for k,v in pairs(ShopTopicNames) do
				Game.GlobalTxt[v] = TopicsBackup[v]
			end
			NamesChanged = false

		end
	end)

	asmpatch(0x4b2511, "jmp absolute " .. NewCode)

	---- DrawLearnTopics event part

	NewCode = asmproc([[
	push ecx
	nop
	nop
	nop
	nop
	nop
	test ecx, ecx
	jnz @neq

	pop ecx
	xor ecx, ecx

	@rep:
	cmp word [ds:]] .. ShopTopicsParams + 14 .. [[], bx
	je @end

	movsx edx, byte [ds:]] .. ShopTopicsParams + 15 .. [[];
	sub dl, byte [ds:]] .. ShopTopicsParams + 14 .. [[];
	movsx ecx, word [ds:edx*2+]] .. ShopTopicsParams .. [[];
	mov eax, edx
	mov dword [ds:ebp-0x4], eax
	push 0x5
	push edx
	lea edx, dword [ss:ebp-0x1c]
	call absolute 0x4bc016
	mov dword [ds:ebp-0x4], eax
	dec byte [ds:]] .. ShopTopicsParams + 14 .. [[];
	jnz @rep

	@end:
	jmp absolute 0x4b21b2

	@neq:
	pop ecx
	cmp ecx, 0xd
	jg absolute 0x4b20fe
	jmp absolute 0x4b1f97]])

	hook(NewCode + 1, function(d)
		local t = {HouseType = d.ecx, NewTopics = {}, Handled = false}
		t.HouseId = GetCurrentHouse()
		events.call("DrawLearnTopics", t)

		if t.Handled then
			local Count = 0
			for i = 1, 5 do
				local v = t.NewTopics[i] or 0
				mem.u2[ShopTopicsParams + (i-1)*2] = v
				Count = Count + ((v > 0 and 1) or 0)
			end
			mem.u2[ShopTopicsParams + 14] = Count
			mem.u2[ShopTopicsParams + 15] = Count
			d.ecx = 0

		end
	end)

	asmpatch(0x4b1f91, "jmp absolute " .. NewCode)

	-- Repair mercenary guild.

	asmpatch(0x4bac98, [[
	je absolute 0x4bae92
	cmp ecx, 0x12
	je absolute 0x4bae92]])

	asmpatch(0x4b1bf3, [[
	cmp eax, 0x1
	je absolute 0x4b1c4d
	cmp eax, 0x12
	je absolute 0x4b1c25]])

end

local function Init()

	structs.o.GameStructure.HousesExtra = HousesExtraPtr
	internal.SetArrayUpval(Game.HousesExtra, "o", HousesExtraPtr)
	internal.SetArrayUpval(Game.HousesExtra, "count", Game.Houses.count - 1)

	HousesPtr = mem.u4[0x4b7305 + 3]

	local CurID
	local NeedRemoval = false

	local function SetCount(Shop, i)
		local CurIDbyType = Game.HousesExtra[i].IndexByType
		if Shop == nil or Shop < CurIDbyType then
			return CurIDbyType
		end
		return Shop
	end

	for i = 0, Game.Houses.count-1 do
		CurID = Game.Houses[i].Type

		if CurID == 1 then
			WepCount = SetCount(WepCount, i)
			if i+1 > 14 then NeedRemoval = true end
		elseif CurID == 2 then
			ArmCount = SetCount(ArmCount, i)
			if i+1 > 28 or i+1 < 15 then NeedRemoval = true end
		elseif CurID == 3 then
			MagCount = SetCount(MagCount, i)
			if i+1 > 41 or i+1 < 29 then NeedRemoval = true end
		elseif CurID == 4 then
			AlcCount = SetCount(AlcCount, i)
			if i+1 > 53 or i+1 < 42 then NeedRemoval = true end
		--elseif CurID >= 12 and Game.Houses[i].Type <= 15 then
		elseif (CurID >= 5 and CurID <= 16) or CurID == 33 or CurID == 34 or CurID == 36 then
			SpBCount = SetCount(SpBCount, i)
			--if i+1 > 148 or i+1 < 139 then NeedRemoval = true end
			if i+1 > 172 or i+1 < 139 then NeedRemoval = true end
		elseif CurID == 21 then
			TavCount = SetCount(TavCount, i)
			if i+1 > 119 or i+1 < 107 then NeedRemoval = true end
		elseif CurID == 27 then
			StablesCount = SetCount(StablesCount, i)
			if i+1 > 62 or i+1 < 54 then NeedRemoval = true end
		elseif CurID == 28 then
			BoatsCount = SetCount(BoatsCount, i)
			if i+1 > 73 or i+1 < 63 then NeedRemoval = true end
		elseif CurID == 30 then
			TrHCount = SetCount(TrHCount, i)
			if i+1 > 101 or i+1 < 89 then NeedRemoval = true end
		end
	end

	MO.GuildAssortIds = StaticAlloc(SpBCount * 2)
	GuildAssortCount = GetGuildAssortCount()
	if GuildAssortCount > OldGuildAssortCount then NeedRemoval = true end

	local ShopsTable = io.open("Data/Tables/House rules.txt", "r")

	if ShopsTable == nil then
		GenerateTable()
		local ErrStr = ""
		if WepCount > OldWepCount then
			ErrStr = ErrStr .. "Count of weapon shops in '2DEvents.txt' (" .. WepCount .. ") and 'House rules.txt' (" .. OldWepCount .. ") do not match!\n"
		end
		if ArmCount > OldArmCount then
			ErrStr = ErrStr .. "Count of armor shops in '2DEvents.txt' (" .. ArmCount .. ") and 'House rules.txt' (" .. OldArmCount .. ") do not match!\n"
		end
		if MagCount > OldMagCount then
			ErrStr = ErrStr .. "Count of magic shops in '2DEvents.txt' (" .. MagCount .. ") and 'House rules.txt' (" .. OldMagCount .. ") do not match!\n"
		end
		if AlcCount > OldAlcCount then
			ErrStr = ErrStr .. "Count of alchemical shops in '2DEvents.txt' (" .. AlcCount .. ") and 'House rules.txt' (" .. OldAlcCount .. ") do not match!\n"
		end
		if StablesCount > OldStablesCount then
			ErrStr = ErrStr .. "Count of stables in '2DEvents.txt' (" .. StablesCount .. ") and 'House rules.txt' (" .. OldStablesCount .. ") do not match!\n"
		end
		if BoatsCount > OldBoatsCount then
			ErrStr = ErrStr .. "Count of boats in '2DEvents.txt' (" .. BoatsCount .. ") and 'House rules.txt' (" .. OldBoatsCount .. ") do not match!\n"
		end
		if TrHCount > OldTrHCount then
			ErrStr = ErrStr .. "Count of training halls in '2DEvents.txt' (" .. TrHCount .. ") and 'House rules.txt' (" .. OldTrHCount .. ") do not match!\n"
		end
		if SpBCount > OldSpBCount then
			ErrStr = ErrStr .. "Count of spellbook shops in '2DEvents.txt' (" .. SpBCount .. ") and 'House rules.txt' (" .. OldSpBCount .. ") do not match!\n"
		end
		if TavCount > OldTavCount then
			ErrStr = ErrStr .. "Count of taverns in '2DEvents.txt' (" .. TavCount .. ") and 'House rules.txt' (" .. OldTavCount .. ") do not match!\n"
		end

		if string.len(ErrStr) > 0 then
			ErrStr = "House rules.txt generated.\n\n" .. ErrStr .. "\nErrors are possible."
			debug.Message(ErrStr)
		end

		return 0
	end

	local lineCounter = 0
	for line in ShopsTable:lines() do
		if line == "Spellbook shops" then
			lineCounter = (lineCounter-9)/2
		elseif string.len(line) == 0 then
			--nothing
		else
			lineCounter = lineCounter + 1
		end
	end
	ShopsTable:close()
	if lineCounter - 5 > WepCount + ArmCount + MagCount + AlcCount + SpBCount + TrHCount + TavCount then
		NeedRemoval = true
	end

	if NeedRemoval then
		RemoveLimits()
	end

	LoadTable()

end

-- Mir, El2, Se2, Mi2 house types in 2DEvents.txt
--   Only first 3 characters are checked
local mir, el2, se2, mi2 = MF.cstring("mir"), MF.cstring("el2"), MF.cstring("se2"), MF.cstring("mi2")
asmpatch(0x440973, [[
push ]] .. mir .. [[;
push esi
call absolute 0x4DB650
add esp, 0xC
test eax, eax
jnz @el2
mov word ptr [edi], 0x10
jmp absolute 0x440A7A

@el2:
push ebp
push ]] .. el2 .. [[;
push esi
call absolute 0x4DB650
add esp, 0xC
test eax, eax
jnz @se2
mov word ptr [edi], 0x21
jmp absolute 0x440A7A

@se2:
push ebp
push ]] .. se2 .. [[;
push esi
call absolute 0x4DB650
add esp, 0xC
test eax, eax
jnz @mi2
mov word ptr [edi], 0x22
jmp absolute 0x440A7A

@mi2:
push ebp
push ]] .. mi2 .. [[;
push esi
call absolute 0x4DB650
add esp, 0xC
test eax, eax
jnz @spe
mov word ptr [edi], 0x24
jmp absolute 0x440A7A


@spe:
push ebp
push 0x4F7750
]])

function events.GameInitialized2()
	Init()
end

	-- SaveGame management. In future it could be rescripted to use default algorythm of saving data,
	-- in future - when other data in this block will be pulled out of .exe, otherwise it will corrupt savegames after each change in 2DEvents.

local function ClearAssortmentsData()

	mem.fill(Game.ShopItems["?ptr"], Game.ShopItems["?size"])
	mem.fill(Game.ShopSpecialItems["?ptr"], Game.ShopSpecialItems["?size"])
	mem.fill(Game.GuildItems["?ptr"], Game.GuildItems["?size"])

	mem.fill(Game.ShopNextRefill["?ptr"], Game.ShopNextRefill["?size"])
	mem.fill(Game.GuildNextRefill2["?ptr"], Game.GuildNextRefill2["?size"])
	mem.fill(FillStatePtr2, Game.ShopNextRefill.count*4)

	--mem.fill(RepPtr, Game.ShopItems.count*8)
	mem.fill(RepPtr2, Game.ShopItems.count*8)

end

local function LoadAssortmentsData()

	local DataLoaded = false
	local SD = vars.SaveGameData
	if not SD then return end

	if SD.ExtendedShopItems and SD.ExtendedShopSpecialItems and SD.ExtendedGuildItems and type(SD.ExtendedGuildItems) == "string" then
		mem.copy(Game.ShopItems["?ptr"],		SD.ExtendedShopItems, 			math.min(Game.ShopItems["?size"], 			#SD.ExtendedShopItems))
		mem.copy(Game.ShopSpecialItems["?ptr"],	SD.ExtendedShopSpecialItems, 	math.min(Game.ShopSpecialItems["?size"], 	#SD.ExtendedShopSpecialItems))
		mem.copy(Game.GuildItems["?ptr"],		SD.ExtendedGuildItems, 			math.min(Game.GuildItems["?size"], 			#SD.ExtendedGuildItems))
		DataLoaded = true
	end

	if SD.ExtendedFillState and type(SD.ExtendedFillState.ShopNextRefill) == "string" then
		mem.copy(Game.ShopNextRefill["?ptr"],	SD.ExtendedFillState.ShopNextRefill, 	math.min(Game.ShopNextRefill["?size"], #SD.ExtendedFillState.ShopNextRefill))
		mem.copy(Game.GuildNextRefill2["?ptr"],	SD.ExtendedFillState.Spellbooks, 		math.min(Game.GuildNextRefill2["?size"], #SD.ExtendedFillState.Spellbooks))
		mem.copy(FillStatePtr2,					SD.ExtendedFillState.Shops, 			math.min(Game.ShopNextRefill.count*4, #SD.ExtendedFillState.Shops))
		DataLoaded = true
	end

	if SD.ExtendedShopReputation and type(SD.ExtendedShopReputation.First) == "string" then
		--mem.copy(RepPtr, 	SD.ExtendedShopReputation.First, 		math.min(#SD.ExtendedShopReputation.First, Game.ShopItems.count*8))
		mem.copy(RepPtr2, 	SD.ExtendedShopReputation.Second, 		math.min(#SD.ExtendedShopReputation.Second, Game.ShopItems.count*8))
		DataLoaded = true
	end

	return DataLoaded

end

local function SaveAssortmentsData()

	vars.SaveGameData = vars.SaveGameData or {}
	local SD = vars.SaveGameData

	SD.ExtendedShopItems			= mem.string(Game.ShopItems["?ptr"], 		Game.ShopItems["?size"], 		true)
	SD.ExtendedShopSpecialItems		= mem.string(Game.ShopSpecialItems["?ptr"],	Game.ShopSpecialItems["?size"],	true)
	SD.ExtendedGuildItems 			= mem.string(Game.GuildItems["?ptr"], 		Game.GuildItems["?size"], 		true)

	SD.ExtendedFillState = {}
	SD.ExtendedFillState.ShopNextRefill 	= mem.string(Game.ShopNextRefill["?ptr"], 	Game.ShopNextRefill["?size"], 		true)
	SD.ExtendedFillState.Spellbooks			= mem.string(Game.GuildNextRefill2["?ptr"], 	Game.GuildNextRefill2["?size"], 		true)
	SD.ExtendedFillState.Shops 				= mem.string(FillStatePtr2, 	Game.ShopNextRefill.count*4, 	true)

	SD.ExtendedShopReputation = {}
	--SD.ExtendedShopReputation.First			= mem.string(RepPtr, 			Game.ShopItems.count*8, 		true)
	SD.ExtendedShopReputation.Second		= mem.string(RepPtr2, 			Game.ShopItems.count*8, 		true)

end

function events.LoadMapScripts(WasInGame)
	NeedAssortmentsReload = not WasInGame
end

function events.AfterLoadMap()
	if NeedAssortmentsReload then
		if not LoadAssortmentsData() then
			ClearAssortmentsData()
		end
	end
end

function events.BeforeSaveGame()
	SaveAssortmentsData()
end

MF.LogInit2(LogId)

