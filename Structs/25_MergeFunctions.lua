local LogId = "MergeFunctions"
local MF = Merge.Functions
MF.LogInit1(LogId)
local MM, MO, MV = Merge.ModSettings, Merge.Offsets, Merge.Vars
local memasmpatch, memasmproc, memstaticalloc = mem.asmpatch, mem.asmproc, mem.StaticAlloc
local memhook, memautohook, memautohook2 = mem.hook, mem.autohook, mem.autohook2
local memcall, u1, u4 = mem.call, mem.u1, mem.u4
local floor, max = math.floor, math.max

-- Filter table records that satisfy all the conditions.
--   Conditions are given in triplets: field name, comparison operator, value.
local function table_filter(t, preserve_indexes, ...)
	local function cmp(op, value1, value2)
		if op == "=" then return value1 == value2 end
		if op == "!=" then return value1 ~= value2 end
		if op == ">" then return value1 > value2 end
		if op == ">=" then return value1 >= value2 end
		if op == "<" then return value1 < value2 end
		if op == "<=" then return value1 <= value2 end
		return false
	end

	if t == nil then return nil end
	local args = { ... }
	local n = #args
	if math.floor(n / 3) * 3 ~= n then
		MF.LogWarning("table.filter: invalid number of arguments")
		return nil
	end
	local res = {}
	for k, v in pairs(t) do
		local add = true
		for i = 1, n / 3 do
			if not cmp(args[i * 3 - 1], v[args[i * 3 - 2]], args[i * 3]) then
				add = false
			end
		end
		if add then
			if preserve_indexes == 1 or preserve_indexes == true then
				table.insert(res, k, v)
			else
				table.insert(res, v)
			end
		end
	end
	return res
end

table.filter = table_filter
MF.TableFilter = table_filter

-- Check if table is empty.
local function table_isempty(t)
	return next(t) == nil
end

table.isempty = table_isempty
MF.TableIsEmpty = table_isempty

MF.Asmpatch = function(address, code, sz)
	local res = memasmpatch(address, code, sz)
	if res then
		MF.LogMem("asmpatch at 0x%X, new address 0x%X", address, res)
	elseif sz then
		MF.LogMem("asmpatch at 0x%X, in-place for %d (0x%X) bytes", address, sz, sz)
	else
		MF.LogMem("asmpatch at 0x%X, in-place", address)
	end
	return res
end

MF.Asmproc = function(code)
	local res, sz = memasmproc(code)
	MF.LogMem("asmproc at 0x%X, size %d (0x%X)", res, sz, sz)
	return res, sz
end

MF.Hook = function(address, f, sz)
	local res = memhook(address, f, sz)
	MF.LogMem("hook at 0x%X", address)
	return res
end

MF.Autohook = function(address, f, sz)
	local res = memautohook(address, f, sz)
	MF.LogMem("autohook at 0x%X", address)
	return res
end

MF.Autohook2 = function(address, f, sz)
	local res = memautohook2(address, f, sz)
	MF.LogMem("autohook2 at 0x%X", address)
	return res
end

MF.StaticAlloc = function(sz, StackLvl)
	local res = memstaticalloc(sz)
	MF.LogMem2(StackLvl or 4, "StaticAlloc at 0x%X, size %d (0x%X)", res, sz, sz)
	return res
end

local asmpatch, asmproc, hook, StaticAlloc = MF.Asmpatch, MF.Asmproc, MF.Hook, MF.StaticAlloc

-- Create null-terminated string from given lua string
function mem_cstring(str)
	local ptr = StaticAlloc(#str + 1, 5)
	mem.copy(ptr, str, #str + 1)
	return ptr
end
MF.cstring = mem_cstring

local slots = {0, 1, 2, 3, 4}
local function get_current_player()
	local slot = Game.CurrentPlayer
	if not table.find(slots, slot) then
		local slot2 = u4[0x519350]
		MF.LogWarning("GetCurrentPlayer: current player - %d, current slot - %d", slot, slot2)
		if table.find(slots, slot2 - 1) then
			return slot2 - 1
		else
			return nil
		end
	else
		return slot
	end
end
MF.GetCurrentPlayer = get_current_player

local function get_current_roster_id()
	local slot = get_current_player()
	if slot and slot >= 0 and slot < Party.count then
		return Party.PlayersIndexes[slot]
	end
end
MF.GetCurrentRosterId = get_current_roster_id

--ecx - player ptr
MO.GetRosterIndex = asmproc([[
push ecx
push edx
mov eax, ecx
mov ecx, 0xB2187C
cmp eax, ecx
jl @null
sub eax, ecx
cmp eax, ]] .. (49 * 0x1D28) .. [[;
jg @null
cdq
mov ecx, 0x1D28
idiv ecx
test edx, edx
jnz @null
jmp @end
@null:
xor eax, eax
dec eax
@end:
pop edx
pop ecx
retn
]])

MO.GetMapObjectIndex = asmproc([[
push ecx
push edx
mov eax, ecx
mov ecx, 0x692FB8
cmp eax, ecx
jl @null
sub eax, ecx
cmp eax, ]] .. (999 * 0x70) .. [[;
jg @null
cdq
mov ecx, 0x70
idiv ecx
test edx, edx
jnz @null
jmp @end
@null:
xor eax, eax
dec eax
@end:
pop edx
pop ecx
retn
]])

-- ecx - Map.Monsters index
-- Note: relies heavily on instruction at 0x42D960
MO.GetMapMonsterPtr = asmproc([[
mov eax, ecx
imul eax, 0x3CC
add eax, dword ptr [0x42D962]
retn
]])

-- Returns current time adjusted to turn-based combat duration
--   args: none
MO.GetCurrentTime = asmproc([[
xor eax, eax
xor edx, edx
cmp dword ptr [0xB21728], 0 ; Turn-Based mode
jz @ff
cmp dword ptr [0x509C9C], 2 ; Turn-Based phase
jnz @ff
push 0x64 ; round takes about 216 time units - 101.25 recovery units
pop ecx
sub ecx, dword ptr [0x509CA8]
jle @ff
push ecx
fild dword ptr [esp]
pop ecx
fmul qword ptr [0x4E8448] ; recovery units to time units
call absolute 0x4D967C ; float to qword
@ff:
add eax, dword ptr [0xB20EBC]
adc edx, dword ptr [0xB20EC0]
retn
]])

-- ecx - seconds
-- edx - floor(0)/ceil(1)
MO.Sec2Time = asmproc([[
push edx
mov eax, ecx
sal eax, 8
cdq
mov ecx, 0x3C
idiv ecx
test edx, edx
pop ecx
jz @end
js @neg
test ecx, ecx
jz @end
inc eax
@neg:
test ecx, ecx
jnz @end
dec eax
@end:
retn
]])

-- ecx - recovery units
MO.Recv2Time = asmproc([[
push ecx
fild dword ptr [esp]
pop ecx
fmul qword ptr [0x4E8448] ; recovery units to time units
call absolute 0x4D967C ; float to qword
retn
]])

-- ecx - player ptr
-- edx - stat id
MO.GetPlStatValue = asmproc([[
xor eax, eax
push ecx
push edx
cmp edx, 6
jg @end
je @luck
test edx, edx
jl @end
je @might
dec edx
jz @int
dec edx
jz @pers
dec edx
jz @endur
dec edx
jz @acy
call absolute 0x48C5D6
jmp @end
@int:
call absolute 0x48C462
jmp @end
@pers:
call absolute 0x48C4BF
jmp @end
@endur:
call absolute 0x48C51C
jmp @end
@acy:
call absolute 0x48C579
jmp @end
@luck:
call absolute 0x48C633
jmp @end
@might:
call absolute 0x48C406
jmp @end
@end:
pop edx
pop ecx
nop
nop
nop
nop
nop
retn
]])

hook(MO.GetPlStatValue + 0x50, function(d)
	local t = {PlayerPtr = d.ecx, Stat = d.edx, Result = d.eax}
	events.call("GetPlStatValue", t)
	d.eax = t.Result
end)

-- ecx - player ptr
-- edx - stat id
MO.GetPlStatEffect = asmproc([[
push ebx
xor eax, eax
push ecx
push edx
test edx, edx
jl @end
cmp edx, 6
jg @end
call absolute ]] .. MO.GetPlStatValue .. [[;
mov ebx, eax
push eax
call absolute 0x48E18E ; GetStatisticEffect
@end:
pop edx
pop ecx
nop
nop
nop
nop
nop
pop ebx
retn
]])

hook(MO.GetPlStatEffect + 0x1D, function(d)
	local t = {PlayerPtr = d.ecx, Stat = d.edx, StatValue = d.ebx, Result = d.eax}
	events.call("GetPlStatEffect", t)
	d.eax = t.Result
end)

MF.GetPlayerStatEffect = function(player, stat)
	return memcall(MO.GetPlStatEffect, 2, player["?ptr"], stat)
end

-- ecx - map monster ptr
MO.GetDistanceToMonster = asmproc([[
push esi
mov esi, ecx
movsx ecx, word ptr [esi + 0x96]
sub ecx, dword ptr [0xB21554]
imul ecx, ecx
movsx eax, word ptr [esi + 0x98]
sub eax, dword ptr [0xB21558]
imul eax, eax
add ecx, eax
movsx eax, word ptr [esi + 0x9A]
sub eax, dword ptr [0xB2155C]
imul eax, eax
add ecx, eax
call absolute 0x450304
movsx ecx, word ptr [esi + 0x90]
sub eax, ecx
jns @end
xor eax, eax
@end:
pop esi
retn
]])

-- ecx - item id
MO.GetItemTxtSkill = asmproc([[
lea eax, [ecx + ecx * 2]
shl eax, 4
add eax, dword ptr [0x43BA40]
movzx eax, byte ptr [eax]
retn
]])

-- ecx - item ptr
MO.GetItemSkill = asmproc([[
mov eax, dword ptr [ecx]
lea eax, [eax + eax * 2]
shl eax, 4
add eax, dword ptr [0x43BA40]
movzx eax, byte ptr [eax]
retn
]])

-- ecx - player ptr
MO.PlayerHasBlaster = asmproc([[
push esi
push edi
xor edi, edi
mov esi, ecx
mov eax, dword ptr [esi + 0x1C08]
test eax, eax
jz @off
lea eax, [eax + eax * 8]
lea ecx, [esi + eax * 4 + 0x484]
test byte ptr [ecx + 0x14], 2
jnz @off
call absolute ]] .. MO.GetItemSkill .. [[;
cmp eax, 7
jne @off
inc edi
@off:
mov eax, dword ptr [esi + 0x1C04]
test eax, eax
jz @miss
lea eax, [eax + eax * 8]
lea ecx, [esi + eax * 4 + 0x484]
test byte ptr [ecx + 0x14], 2
jnz @miss
call absolute ]] .. MO.GetItemSkill .. [[;
cmp eax, 7
jne @miss
or edi, 2
@miss:
mov eax, dword ptr [esi + 0x1C0C]
test eax, eax
jz @end
lea eax, [eax + eax * 8]
lea ecx, [esi + eax * 4 + 0x484]
test byte ptr [ecx + 0x14], 2
jnz @end
call absolute ]] .. MO.GetItemSkill .. [[;
cmp eax, 7
jne @end
or edi, 4
@end:
mov eax, edi
pop edi
pop esi
retn
]])

-- ecx - player ptr
-- edx - condition
MO.ConditionApplicablePlayer = asmproc([[
xor eax, eax
nop
nop
nop
nop
nop
test eax, eax
jg @ack
jl @nak
cmp edx, 0xE
jz @dead
cmp edx, 0xF
jz @ston
cmp edx, 0x10
jz @erad
@ston:
mov eax, dword ptr [ecx + 0x78]
or eax, dword ptr [ecx + 0x7C]
jnz @nak
@dead:
mov eax, dword ptr [ecx + 0x70]
or eax, dword ptr [ecx + 0x74]
jnz @nak
@erad:
mov eax, dword ptr [ecx + 0x80]
or eax, dword ptr [ecx + 0x84]
jnz @nak
@ack:
xor eax, eax
inc eax
jmp @end
@nak:
xor eax, eax
@end:
retn
]])

hook(MO.ConditionApplicablePlayer + 2, function(d)
	local t = {PlayerPtr = d.ecx, Condition = d.edx, Result = d.eax}
	events.cocalls("ConditionApplicablePlayer", t)
	d.eax = t.Result
end)

-- FIXME: add all conditions
local applicable = StaticAlloc(8)
-- ecx - condition
MO.SelectConditionSlot = asmproc([[
push esi
push edi
push ebx
mov esi, ecx
xor ebx, ebx
xor edi, edi
@loop1:
push ebx
mov ecx, 0xB20E90
call absolute 0x4026F4
mov ecx, eax
mov edx, esi
call absolute ]] .. MO.ConditionApplicablePlayer .. [[;
test eax, eax
jz @next
mov byte ptr [edi + ]] .. applicable .. [[], bl
inc edi
@next:
inc ebx
cmp ebx, dword ptr [0xB7CA60]
jl @loop1
test edi, edi
jnz @f1
xor eax, eax
dec eax
jmp @end
@f1:
call absolute 0x4D99F2
cdq
idiv edi
movzx eax, byte ptr [edx + ]] .. applicable .. [[]
@end:
pop ebx
pop edi
pop esi
retn
]])

-- ecx - player ptr
-- edx - damage type
MO.CheckResistPlayer = asmproc([[
push esi
push edi
push ebx
mov esi, ecx
mov edi, edx
and edx, 0xF
shl edx, 1
movzx edx, word ptr [edx + ]] .. MO.DamageResist .. [[]
push edx
call absolute 0x48DD6B ; GetResistance
mov ebx, eax
mov edx, edi
shr edx, 4
test edx, edx
jz @out
shl edx, 1
movzx edx, word ptr [edx + ]] .. MO.DamageResist .. [[]
push edx
mov ecx, esi
call absolute 0x48DD6B ; GetResistance
@out:
cmp eax, ebx
jle @f1
mov eax, ebx
@f1:
test eax, eax
jz @end
mov edi, eax
mov ecx, esi
mov edx, 6
call absolute ]] .. MO.GetPlStatEffect .. [[;
add edi, eax
add edi, 30
test edi, edi
jnz @f2
xor eax, eax
jmp @end
@f2:
call absolute 0x4D99F2
cdq
idiv edi
xor eax, eax
cmp edx, 30
jl @end
inc eax
@end:
pop ebx
pop edi
pop esi
retn
]])

local function get_player_from_ptr(ptr)
	if ptr < 0xB2187C or ptr > 0xB7AD24 then
		MF.LogError("%s: invalid player pointer in GetPlayerFromPtr - 0x%X", LogId, ptr)
		return nil, -1
	end
	local player_id = (ptr - Party.PlayersArray["?ptr"])/Party.PlayersArray[0]["?size"]
	return Party.PlayersArray[player_id], player_id
end
MF.GetPlayerFromPtr = get_player_from_ptr

local function get_slot_by_index(player_index)
	if not player_index or player_index < 0 or player_index > 49 then
		return
	end
	for i = 0, Party.count - 1 do
		if Party.PlayersIndexes[i] == player_index then
			return i
		end
	end
end
MF.GetSlotByIndex = get_slot_by_index

local function get_slot_by_ptr(ptr)
	if ptr < 0xB2187C or ptr > 0xB7AD24 then
		MF.LogError("%s: invalid player pointer in GetSlotByPtr - 0x%X", LogId, ptr)
		return
	end
	for i = 0, Party.count - 1 do
		if Party[i]["?ptr"] == ptr then
			return i
		end
	end
end
MF.GetSlotByPtr = get_slot_by_ptr

local function get_npc_map_monster(npc_id)
	if not npc_id or npc_id == 0 then
		return
	end
	for k, v in Map.Monsters do
		if v.NPC_ID == npc_id then
			return k
		end
	end
end
MF.GetNPCMapMonster = get_npc_map_monster

function CheckClassInParty(class)
	local result = false
	for _, pl in Party do
		if pl.Class == class then
			result = true
			break
		end
	end
	return result
end
MF.CheckClassInParty = CheckClassInParty

function RosterHasAward(award)
	for idx = 0, Party.PlayersArray.count - 1 do
		local player = Party.PlayersArray[idx]
		if player.Awards[award] then
			return true
		end
	end
	return false
end
MF.RosterHasAward = RosterHasAward

local function show_award_animation(anim, slot)
	slot = slot or get_current_player() or 0
	local player = Party[slot]
	player:ShowFaceAnimation(anim or 96)
	memcall(0x4A6FCE, 1, u4[u4[0x75CE00]+0xE50], 0x97, slot)
	Game.PlaySound(0xCD, 0x190 + slot * 8 + 4)
end
MF.ShowAwardAnimation = show_award_animation

local function award_add(award, slot)
	slot = slot or get_current_player() or 0
	local player = Party[slot]
	if not player.Awards[award] then
		player.Awards[award] = true
		show_award_animation(96, slot)
	end
end
MF.AwardAdd = award_add

local function qbit_add(qbit)
	if not Party.QBits[qbit] then
		Party.QBits[qbit] = true
		show_award_animation(93)
	end
end
MF.QBitAdd = qbit_add

local function get_continent(map_id)
	return TownPortalControls.MapOfContinent(map_id or Map.MapStatsIndex)
		or not map_id and TownPortalControls.GetCurrentSwitch()
end
MF.GetContinent = get_continent

local function get_day_of_game(t)
	return t.GameYear * 336 + t.Month * 28 + t.Day
end
MF.GetGameDay = get_day_of_game

local masteries = { B = 1, E = 2, M = 3, G = 4}
local function split_req(req)
	if not req or req == "" then return 0, 0, 0 end
	if tonumber(req) then return tonumber(req), 0, 0 end
	local plevel, mastery, level = req:match("^(%d*)([BEMG])(%d+)")
	plevel = tonumber(plevel) or 1
	mastery = masteries[mastery]
	level = tonumber(level)
	if plevel and mastery and level then
		return plevel, mastery, level
	end
end
MF.SplitReq = split_req

local function setting_eq_num(s, val)
	local num = tonumber(s)
	if num and num == val then
		return true
	end
end
MF.SettingEqNum = setting_eq_num

local function setting_gt_num(s, val)
	local num = tonumber(s)
	if num and num > val then
		return true
	end
end
MF.SettingGtNum = setting_gt_num
MF.GtSettingNum = setting_gt_num

local function setting_ne_num(s, val)
	local num = tonumber(s)
	if num and num ~= val then
		return true
	end
end
MF.SettingNeNum = setting_ne_num
MF.NeSettingNum = setting_ne_num

local function get_skill_level_skillpoints(rank)
	return rank * (rank + 1) / 2 - 1
end
MF.GetSkillLevelSkillpoints = get_skill_level_skillpoints

local mastery_spell_level = {
	[0] = 0,
	[1] = 4,
	[2] = 7,
	[3] = 10,
	[4] = 11
}

local function can_player_learn_spell(t)
	local req_level, skill_id, level
	if t.SpellId < 1 then
		return false
	elseif t.SpellId < 100 then
		req_level = (t.SpellId - 1) % 11 + 1
		skill_id = floor((t.SpellId - 1) / 11) + 12
		level = memcall(MO.GetPlayerSkillMastery, 2, t.Player["?ptr"], skill_id)
		level = mastery_spell_level[level]
	elseif t.SpellId < 133 then
		req_level = (t.SpellId - 1) % 11 + 1
		if req_level < 5 then
			req_level = mastery_spell_level[req_level - 1] + 1
			skill_id = floor((t.SpellId - 1) / 11) + 12
			level = memcall(MO.GetPlayerSkillMastery, 2, t.Player["?ptr"], skill_id)
			level = mastery_spell_level[level]
		else
			-- 7 unused spells per ability
			return false
		end
	else
		-- ranged attacks, shouldn't be learnable
		return false
	end
	t.ReqLevel = req_level
	t.Level = level
	events.call("CanPlayerLearnSpell", t)
	return t.Level >= t.ReqLevel
end
MF.CanPlayerLearnSpell = can_player_learn_spell

local mastery_rank = {
	--[0] = 0,
	[1] = 1,
	[2] = 4,
	[3] = 7,
	[4] = 10
}

local function convert_character(t)
	if not t.Player then
		MF.LogError("%s: calling ConvertCharacter without player specified", LogId)
		return
	end
	local from_class, from_race = t.Player.Class, t.Player.Attrs.Race
	local from_maturity = t.Player.Attrs.Maturity or 0
	local class, race, maturity = t.ToClass or from_class,
		t.ToRace or from_race, t.ToMaturity or from_maturity
	if MM.Races and MM.Races.MaxMaturity then
		if MM.Races.MaxMaturity == 1 then
			if maturity == 1 then
				maturity = from_maturity
			elseif maturity > 1 then
				maturity = 1
			end
		elseif maturity > MM.Races.MaxMaturity then
			maturity = MM.Races.MaxMaturity
		end
	end
	if class == from_class and race == from_race and maturity == from_maturity then
		MF.LogWarning("%s: calling ConvertCharacter with the same target parameters", LogId)
		return
	end
	for skill = 0, 38 do
		if t.Player.Skills[skill] > 0 then
			local rank, mastery = SplitSkill(t.Player.Skills[skill])
			local new_mastery = GetMaxAvailableSkill(race, class, skill, maturity)
			if new_mastery == 0 then
				local skillpoints1 = get_skill_level_skillpoints(rank)
				t.Player.Skills[skill] = 0
				t.Player.SkillPoints = t.Player.SkillPoints + skillpoints1
			elseif new_mastery < mastery then
				local skillpoints1 = get_skill_level_skillpoints(rank)
				local new_rank = mastery_rank[new_mastery]
				local skillpoints2 = get_skill_level_skillpoints(new_rank)
				t.Player.Skills[skill] = JoinSkill(new_rank, new_mastery)
				t.Player.SkillPoints = t.Player.SkillPoints + skillpoints1
					- skillpoints2
			end
		end
	end
	t.Player.Class = class
	t.Player.Attrs.Race = race
	t.Player.Attrs.Maturity = maturity
	for spell = 1, 99 do
		if t.Player.Spells[spell] then
			if not can_player_learn_spell({Player = t.Player, SpellId = spell}) then
				t.Player.Spells[spell] = false
			end
		end
	end
	for spell = 100, 132 do
		if can_player_learn_spell({Player = t.Player, SpellId = spell}) then
			t.Player.Spells[spell] = true
		else
			t.Player.Spells[spell] = false
		end
	end
end
MF.ConvertCharacter = convert_character

-- Copy fields of NPC1 onto NPC2
local function npc_copy(src_npc_id, dst_npc_id)
	local npc1 = Game.NPC[src_npc_id]
	local npc2 = Game.NPC[dst_npc_id]
	if not npc1 or not npc2 then
		return false
	end
	npc2.Bits = npc1.Bits
	npc2.EventA = npc1.EventA
	npc2.EventB = npc1.EventB
	npc2.EventC = npc1.EventC
	npc2.EventD = npc1.EventD
	npc2.EventE = npc1.EventE
	npc2.EventF = npc1.EventF
	npc2.Fame = npc1.Fame
	npc2.Greet = npc1.Greet
	npc2.Hired = npc1.Hired
	npc2.House = npc1.House
	npc2.Joins = npc1.Joins
	npc2.NewsTopic = npc1.NewsTopic
	npc2.Pic = npc1.Pic
	npc2.Profession = npc1.Profession
	npc2.Rep = npc1.Rep
	npc2.Sex = npc1.Sex
	npc2.TellsNews = npc1.TellsNews
	npc2.UsedSpells = npc1.UsedSpells
	return true
end
MF.NPCCopy = npc_copy

-- Restore NPC fields from NPCData.txt
local function npc_restore(npc_id)
	local npc = Game.NPC[npc_id]
	local npcdata = Game.NPCDataTxt[npc_id]
	if not npc or not npcdata then
		return false
	end
	npc.Bits = npcdata.Bits
	npc.EventA = npcdata.EventA
	npc.EventB = npcdata.EventB
	npc.EventC = npcdata.EventC
	npc.EventD = npcdata.EventD
	npc.EventE = npcdata.EventE
	npc.EventF = npcdata.EventF
	npc.Fame = npcdata.Fame
	npc.Greet = npcdata.Greet
	npc.Hired = npcdata.Hired
	npc.House = npcdata.House
	npc.Joins = npcdata.Joins
	npc.Name = npcdata.Name
	npc.NewsTopic = npcdata.NewsTopic
	npc.Pic = npcdata.Pic
	npc.Profession = npcdata.Profession
	npc.Rep = npcdata.Rep
	npc.Sex = npcdata.Sex
	npc.TellsNews = npcdata.TellsNews
	npc.UsedSpells = npcdata.UsedSpells
	return true
end
MF.NPCRestore = npc_restore

local function set_last_fountain()
	if not MV.Continent or not TownPortalControls.Sets[MV.Continent] then
		return
	end
	local tpset
	for k, v in pairs(TownPortalControls.Sets[MV.Continent]) do
		if v.Map == MV.Map then
			tpset = k
		end
	end
	if tpset then
		u1[0x51D819] = tpset
	end
end
MF.SetLastFountain = set_last_fountain

MF.LogInit2(LogId)
