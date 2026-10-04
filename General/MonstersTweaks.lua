local LogId = "MonstersTweaks"
local MF = Merge.Functions
MF.LogInit1(LogId)
local MM, MO, MT = Merge.ModSettings, Merge.Offsets, Merge.Tables

local asmpatch, hook, u2 = mem.asmpatch, mem.hook, mem.u2
local max, min = math.max, math.min

--------------------
-- MapMonster Allies
-- Support Group as negative in Ally (1)
asmpatch(0x4386B6, [[
jns @std
test edi, edi
js absolute 0x4386D8
mov edi, dword ptr [ebx+0x34C]
neg edi
jmp absolute 0x4386D8
@std:
jnz absolute 0x4386C6
movsx eax, word ptr [ecx+0x6A]
]])

-- Support Group as negative in Ally (2)
asmpatch(0x4386C8, [[
jns @std
mov esi, dword ptr [ecx+0x34C]
neg esi
jmp absolute 0x4386D8
@std:
jnz absolute 0x4386D8
movsx eax, word ptr [ebx+0x6A]
]])

-- Use sane comparison first
asmpatch(0x4386DB, [[
cmp esi, edi
jz short 0x43874D - 0x4386DB
push 0x80
pop edx
]], 12)

-- MM7 human, dwarf, elf peasants
asmpatch(0x4386FB, [[
push 0x75
pop ecx
cmp esi, ecx
jl @opt1
cmp esi, edx
jg @end
cmp edi, ecx
jl @end
cmp edi, edx
jg @end
jmp short 0x43874D - 0x4386FB
@opt1:
push 0x69
pop ecx
push 0x6E
pop edx
cmp esi, ecx
jl @end
cmp esi, edx
jg @opt2
cmp edi, ecx
jl @end
cmp edi, edx
jg @end
jmp short 0x43874D - 0x4386FB
@opt2:
push 0x74
pop edx
cmp edi, edx
jle short 0x43874D - 0x4386FB
@end:
]], 0x438737 - 0x4386FB)

-- MM7 goblin peasants, MM6 peasants
asmpatch(0x43872F, [[
push 0x90
pop ecx
push 0x95
pop edx
cmp esi, ecx
jl @end
cmp esi, edx
jg @opt1
cmp edi, ecx
jl @end
cmp edi, edx
jg @end
jmp absolute 0x43874D
@opt1:
push 0xC1
pop ecx
push 0xCB
pop edx
cmp esi, ecx
jl @end
cmp esi, edx
jg @end
cmp edi, ecx
jl @end
cmp edi, edx
jl @end
push 0xC2
pop ecx
push 0xC6
pop edx
cmp esi, ecx
jl @opt2
cmp esi, edx
jg @opt2
cmp edi, ecx
jl @opt2
cmp edi, edx
jg @opt2
jmp @end
@opt2:
push 0xC9
pop ecx
push 0xCA
pop edx
cmp esi, ecx
jl @ok
cmp esi,edx
jg @ok
cmp edi, ecx
jl @ok
cmp edi, edx
jg @ok
jmp @end
@ok:
jmp absolute 0x43874D
@end:
]])

--------------------
-- Combined damage type: to monster
asmpatch(0x425975, [[
push edi
push ebx
xor edi, edi
mov esi, dword ptr [ebp + 0xC]
and esi, 0xF
cmp esi, 0xA
]])
asmpatch(0x4259C4, [[
test edi, edi
jnz @compare
mov esi, dword ptr [ebp + 0xC]
sar esi, 4
test esi, esi
jz @end
add eax, edx
xor edx, edx
mov ebx, eax
mov eax, dword ptr [ebp + 8]
inc edi
cmp esi, 0xA
jmp absolute 0x42597B
@compare:
add eax, edx
xor edx, edx
cmp eax, ebx
jle @end
mov eax, ebx
@end:
pop ebx
pop edi
cmp eax, 0xFDE8
]])

--------------------
-- Get preferred party member
local function load_monster_pref_tables()
	MT.MonsterPrefClass, MT.MonsterPrefRace, MT.MonsterPrefMisc = {}, {}, {}
	local txt_table = io.open("Data/Tables/MonsterPrefClass.txt", "r")
	if not txt_table then
		txt_table = io.open("Data/Tables/MonsterPrefClass.txt", "w")
		txt_table:write("\tMonster")
		for j = 0, Game.ClassNames.high do
			txt_table:write("\t" .. Game.ClassNames[j])
		end
		for i = 1, Game.MonstersTxt.high do
			txt_table:write("\n" .. i .. "\t" .. Game.MonstersTxt[i].Name)
			MT.MonsterPrefClass[i] = {}
			for j = 0, Game.ClassNames.high do
				MT.MonsterPrefClass[i][j] = 0
				txt_table:write("\t0")
			end
		end
	else
		local iter = txt_table:lines()
		iter()
		for line in iter do
			local words = string.split(line, "\9")
			local num = tonumber(words[1])
			MT.MonsterPrefClass[num] = {}
			for i = 3, #words do
				MT.MonsterPrefClass[num][i - 3] = tonumber(words[i]) or 0
			end
		end
	end
	io.close(txt_table)

	txt_table = io.open("Data/Tables/MonsterPrefRace.txt", "r")
	if not txt_table then
		txt_table = io.open("Data/Tables/MonsterPrefRace.txt", "w")
		txt_table:write("\tMonster")
		for j = 0, MT.RacesCount - 1 do
			txt_table:write("\t" .. MT.Races[j].StringId)
		end
		for i = 1, Game.MonstersTxt.high do
			txt_table:write("\n" .. i .. "\t" .. Game.MonstersTxt[i].Name)
			MT.MonsterPrefRace[i] = {}
			for j = 0, MT.RacesCount - 1 do
				MT.MonsterPrefRace[i][j] = 0
				txt_table:write("\t0")
			end
		end
	else
		local iter = txt_table:lines()
		iter()
		for line in iter do
			local words = string.split(line, "\9")
			local num = tonumber(words[1])
			MT.MonsterPrefRace[num] = {}
			for i = 3, #words do
				MT.MonsterPrefRace[num][i - 3] = tonumber(words[i]) or 0
			end
		end
	end
	io.close(txt_table)

	txt_table = io.open("Data/Tables/MonsterPrefMisc.txt", "r")
	if not txt_table then
		txt_table = io.open("Data/Tables/MonsterPrefMisc.txt", "w")
		txt_table:write("\tMonster\tSlot 0\tSlot 1\tSlot 2\tSlot 3\tSlot 4\tMale\tFemale")
		for i = 1, Game.MonstersTxt.high do
			txt_table:write("\n" .. i .. "\t" .. Game.MonstersTxt[i].Name)
			MT.MonsterPrefMisc[i] = {}
			for j = 0, 6 do
				MT.MonsterPrefMisc[i][j] = 0
				txt_table:write("\t0")
			end
		end
	else
		local iter = txt_table:lines()
		iter()
		for line in iter do
			local words = string.split(line, "\9")
			local num = tonumber(words[1])
			MT.MonsterPrefMisc[num] = {}
			for i = 3, #words do
				MT.MonsterPrefMisc[num][i - 3] = tonumber(words[i]) or 0
			end
		end
	end
	io.close(txt_table)
end

local function get_monster_class_pref(id, class_id)
	return MT.MonsterPrefClass and MT.MonsterPrefClass[id]
		and MT.MonsterPrefClass[id][class_id] or 0
end

local function get_monster_race_pref(id, race_id)
	return MT.MonsterPrefRace and MT.MonsterPrefRace[id]
		and MT.MonsterPrefRace[id][race_id] or 0
end

local function get_monster_sex_pref(id, sex_id)
	return MT.MonsterPrefMisc and MT.MonsterPrefMisc[id]
		and MT.MonsterPrefMisc[id][sex_id + 5] or 0
end

local function get_monster_slot_pref(id, slot_id)
	return MT.MonsterPrefMisc and MT.MonsterPrefMisc[id]
		and MT.MonsterPrefMisc[id][slot_id] or 0
end

local function get_party_member_base_pref(slot_id)
	local res = 16
	local pl = Party[slot_id]
	if pl.Paralyzed > 0 then
		-- 0 for vanilla MM8 behavior
		res = 1
	end
	for i = 13, 16 do
		if pl.Conditions[i] > 0 then
			res = 0
		end
	end
	return res
end

local function get_party_member_pref(id, slot_id)
	local pl = Party[slot_id]
	local res = get_party_member_base_pref(slot_id)
	res = res * (8 + get_monster_class_pref(id, pl.Class))
	res = res * (8 + get_monster_race_pref(id, pl.Attrs.Race))
	res = res * (8 + get_monster_sex_pref(id, pl:GetSex()))
	res = res * (8 + get_monster_slot_pref(id, slot_id))
	return res
end
MF.GetMonsterPlayerPref = get_party_member_pref

-- TODO: rewrite in asm
local function get_preferred_party_slot(id)
	local res, sum = {}, 0
	for i = 0, Party.count - 1 do
		res[i] = get_party_member_pref(id, i)
		sum = sum + res[i]
	end
	local rnd = math.random(sum) - 1
	sum = 0
	for i = 0, Party.count - 1 do
		sum = sum + res[i]
		if rnd < sum then
			return i
		end
	end
	return 0
end
MF.GetMonsterPreferredSlot = get_preferred_party_slot

asmpatch(0x425203, [[
mov ecx, dword [esp + 4]
nop
nop
nop
nop
nop
retn 4
]], 0x425210 - 0x425203)

hook(0x425203 + 4, function(d)
	local id = u2[d.ecx + 0x6A]
	local t = {MonsterPtr = d.ecx, MonsterId = id}
	t.Slot = get_preferred_party_slot(id)
	events.call("MonsterChooseTargetPlayer", t)
	d.eax = t.Slot
end)

------------------------
-- Fix monster item loot
if MF.SettingGtNum(MM.FixMonsterItemLoot, 0) then
	asmpatch(0x424FD0, [[
	mov dword ptr [ebp - 8], 1
	mov esi, 0x800000
	jmp absolute 0x425033
	]], 0x424FFD - 0x424FD0)

	asmpatch(0x4250E9, [[
	and byte ptr [ebx + 0x26], 0x7F
	lea eax, [ebx + 0x304]
	]])

	-- Don't overwrite special item message
	asmpatch(0x425077, [[
	cmp dword ptr [ebp - 8], 0
	jnz absolute 0x4250BE
	mov eax, dword ptr [ebp - 0x2C]
	lea eax, [eax+eax*2]
	]])
	asmpatch(0x425105, [[
	cmp dword ptr [ebp - 8], 0
	jnz absolute 0x42514C
	mov eax, dword ptr [ebp - 0x2C]
	lea eax, [eax+eax*2]
	]])
end

-- Multiloot
local pct = tonumber(MM.MonsterMultilootChance)
if pct and pct ~= 10 then
	asmpatch(0x4251F0, "cmp edx, " .. min(127, max(10, 100 - pct)))
end

function events.GameInitialized2()
	load_monster_pref_tables()
end

MF.LogInit2(LogId)

