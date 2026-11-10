local LogId = "ItemsModifiers"
-- Item subtypes (Data/Tables/ItemSubtypes.txt) and equip requirements (ItemsExtra.txt
-- Subtype, EquipReq, Equip2Req, Equip3Req) from cthscr's Revamp, merged into Waffel Edition
-- 06.11.26: what can be held in which hand and with which skill comes from the tables
-- (EquipReq: the item at all; Equip2Req: in the left hand, or a two-handed one in one hand;
-- Equip3Req: missile weapons). "B1" = Basic 1 of the item's skill, "M1" Master, "1" no skill,
-- "10M5" player level 10 and Master 5. An empty requirement means it can't be done.
local MF = Merge.Functions
MF.LogInit1(LogId)
local MC, MM, MO, MT, MV = Merge.Consts, Merge.ModSettings, Merge.Offsets, Merge.Tables, Merge.Vars

local asmpatch, asmproc, autohook2, hook = MF.Asmpatch, MF.Asmproc, MF.Autohook2, MF.Hook
local StaticAlloc = MF.StaticAlloc
local i2, i4, u2, u4 = mem.i2, mem.i4, mem.u2, mem.u4
local floor, max, random = math.floor, math.max, math.random

local NewCode

MC.ExtraStatType = {
	RecoveryBase = 0,
	RecoveryMin = 1,
	RecoveryMainLvl = 2,
	RecoveryAddLvl = 3, -- needed?
	AtttackMainLvl = 4,
	AtttackAddLvl = 5, -- needed?
	DamageMainLvl = 6,
	DamageAddLvl = 7,
	ACLvl = 8,
	--Evasion = 9,
	--EvasionLvl = 9,
	CritChanceLvl = 9,
	--CritChanceMax = 10,
	CritDamage = 10,
	StunChanceLvl = 11,
	ParalyzeChanceLvl = 12,
	CorrosionChanceLvl = 13,
	CorrosionFactor = 14,
}

local extra_stat_type_count = 16

local item_extra_fields_offsets = {
	Subtype = 0,
	MaterialGroup = 2,
	Req1PlayerLevel = 4,
	Req1SkillMastery = 6,
	Req1SkillLevel = 8,
	Req2PlayerLevel = 10,
	Req2SkillMastery = 12,
	Req2SkillLevel = 14,
	Req3PlayerLevel = 16,
	Req3SkillMastery = 18,
	Req3SkillLevel = 20,
}

local item_extra_size = 22

local item_subtype_fields_offsets = {
	ItemType = 0,
	MainSkill = 2,
	Flags = 4,
}

local item_subtype_fields_types = {
	ItemType = "u2",
	MainSkill = "i2",
	Flags = "u4",
}

local function ProcessItemsExtraFiles()
	local items_extra = {}
	local table_file = "Data/Tables/ItemsExtra.txt"
	local header = "Id\tNote\tSubtype\tMatGroup\tEquipReq\tEquip2Req\tEquip3Req\tContF\tQCont\tLostQBit\tStartQBit\tEndQBit\tPostEnd"

	-- item numbers run up to Game.ItemsTxt.high, which is .count (the table starts at 1): one
	-- row more than count, or a row for the last item writes past the end (06.11.26: a crash
	-- at start-up once item 2224 got a row)
	local items_high = Game.ItemsTxt.high
	MO.ItemsExtra = StaticAlloc((items_high + 1) * item_extra_size)

	local txt_table = io.open(table_file, "r")
	local ok = true
	if not txt_table then
		MF.LogError("%s: No ItemsExtra.txt found, the equip requirements are off", LogId)
		ok = false
	else
		local iter = txt_table:lines()
		if iter() ~= header then
			MF.LogError("%s: ItemsExtra.txt has wrong header, the equip requirements are off", LogId)
			ok = false
		else
			local line_num = 1
			for line in iter do
				line_num = line_num + 1
				local words = string.split(line, "\t")
				local num = tonumber(words[1])
				if num and (num < 0 or num > items_high) then
					MF.LogWarning("%s: ItemsExtra.txt line %d: no item %d in Items.txt, skipped", LogId, line_num, num)
					num = nil
				end
				if num then
					items_extra[num] = {
						--Subtype = tonumber(words[3]),
						--MaterialGroup = tonumber(words[4]),
						EquipReq = {},
						Equip2Req = {},
						Equip3Req = {},
						ContFactor = {},
						QuestCont = tonumber(words[9]),
						LostQBit  = tonumber(words[10]),
						StartQBit = tonumber(words[11]),
						EndQBit = tonumber(words[12]),
						PostEnd = words[13] == "x"
					}
					i2[MO.ItemsExtra + num * item_extra_size] = tonumber(words[3]) or 0
					i2[MO.ItemsExtra + num * item_extra_size + 2] = tonumber(words[4]) or 0
					local plevel, mastery, level = MF.SplitReq(words[5])
					items_extra[num].EquipReq.PlayerLevel = plevel
					items_extra[num].EquipReq.SkillMastery = mastery
					items_extra[num].EquipReq.SkillLevel = level
					i2[MO.ItemsExtra + num * item_extra_size + 4] = plevel
					i2[MO.ItemsExtra + num * item_extra_size + 6] = mastery
					i2[MO.ItemsExtra + num * item_extra_size + 8] = level
					plevel, mastery, level = MF.SplitReq(words[6])
					items_extra[num].Equip2Req.PlayerLevel = plevel
					items_extra[num].Equip2Req.SkillMastery = mastery
					items_extra[num].Equip2Req.SkillLevel = level
					i2[MO.ItemsExtra + num * item_extra_size + 10] = plevel
					i2[MO.ItemsExtra + num * item_extra_size + 12] = mastery
					i2[MO.ItemsExtra + num * item_extra_size + 14] = level
					plevel, mastery, level = MF.SplitReq(words[7])
					items_extra[num].Equip3Req.PlayerLevel = plevel
					items_extra[num].Equip3Req.SkillMastery = mastery
					items_extra[num].Equip3Req.SkillLevel = level
					i2[MO.ItemsExtra + num * item_extra_size + 16] = plevel
					i2[MO.ItemsExtra + num * item_extra_size + 18] = mastery
					i2[MO.ItemsExtra + num * item_extra_size + 20] = level
					local cf = string.split(words[8] or "", ",")
					for k, v in pairs(cf) do
						items_extra[num].ContFactor[k] = tonumber(v)
					end
					setmetatable(items_extra[num], {
						__index = function(tbl, key)
							if item_extra_fields_offsets[key] then
								return i2[MO.ItemsExtra + num * item_extra_size
									+ item_extra_fields_offsets[key]]
							end
						end,
						__newindex = function(tbl, key, value)
							if item_extra_fields_offsets[key] then
								i2[MO.ItemsExtra + num * item_extra_size
									+ item_extra_fields_offsets[key]] = value
							else
								rawset(tbl, key, value)
							end
						end
					})
				end
			end
		end
		io.close(txt_table)
	end

	MT.ItemsExtra = items_extra

	local item_subtypes = {}
	local subtype_max = 0
	table_file = "Data/Tables/ItemSubtypes.txt"
	txt_table = io.open(table_file, "r")
	if not txt_table then
		MF.LogError("%s: No ItemSubtypes.txt found, the equip requirements are off", LogId)
		ok = false
	else
		local iter = txt_table:lines()
		-- TODO: check header
		local line_num = 1
		for line in iter do
			line_num = line_num + 1
			local words = string.split(line, "\t")
			local num = tonumber(words[1])
			if num and num >= 0 then
				if num > subtype_max then
					subtype_max = num
				end
				item_subtypes[num] = {}
				item_subtypes[num].MainSkill = tonumber(words[3]) or -1
				local flags = 0
				flags = bit.bor(flags, words[4] == "x" and 0x1 or 0)
				flags = bit.bor(flags, words[5] == "x" and 0x2 or 0)
				flags = bit.bor(flags, words[6] == "x" and 0x4 or 0)
				flags = bit.bor(flags, words[7] == "x" and 0x8 or 0)
				flags = bit.bor(flags, words[8] == "x" and 0x10 or 0)
				flags = bit.bor(flags, words[9] == "x" and 0x20 or 0)
				flags = bit.bor(flags, words[10] == "x" and 0x40 or 0)
				flags = bit.bor(flags, words[11] == "x" and 0x80 or 0)
				flags = bit.bor(flags, words[12] == "x" and 0x100 or 0)
				flags = bit.bor(flags, words[13] == "x" and 0x200 or 0)
				flags = bit.bor(flags, words[14] == "x" and 0x400 or 0)
				flags = bit.bor(flags, words[15] == "x" and 0x800 or 0)
				item_subtypes[num].Flags = flags
			end
		end
		io.close(txt_table)
	end
	-- FIXME: replace magic number 8
	MO.ItemSubtypes = StaticAlloc(8 * (subtype_max + 1))
	MT.ItemSubtypes = {}
	for num = 0, subtype_max do
		if item_subtypes[num] then
			i2[MO.ItemSubtypes + 8 * num + 2] = item_subtypes[num].MainSkill
			u4[MO.ItemSubtypes + 8 * num + 4] = item_subtypes[num].Flags
		else
			i2[MO.ItemSubtypes + 8 * num + 2] = -1
			u4[MO.ItemSubtypes + 8 * num + 4] = 0
		end
		MT.ItemSubtypes[num] = {}
		setmetatable(MT.ItemSubtypes[num], {
			__index = function(tbl, key)
				if item_subtype_fields_offsets[key] then
					return mem[item_subtype_fields_types[key]][MO.ItemSubtypes + num * 8
						+ item_subtype_fields_offsets[key]]
				end
			end,
			__newindex = function(tbl, key, value)
				if item_subtype_fields_offsets[key] then
					mem[item_subtype_fields_types[key]][MO.ItemSubtypes + num * 8
						+ item_subtype_fields_offsets[key]] = value
				else
					rawset(tbl, key, value)
				end
			end
		})
	end

	--[=[
	local item_stat_extra = {}
	table_file = "Data/Tables/SkillsExtra.txt"
	--header = ""
	txt_table = io.open(table_file, "r")
	if not txt_table then
		MF.LogWarning("%s: No SkillsExtra.txt found", LogId)
	else
		local iter = txt_table:lines()
		--if iter() ~= header then
		--	MF.LogWarning("%s: SkillsExtra.txt has wrong header", LogId)
		--else
			local line_num = 1
			for line in iter do
				line_num = line_num + 1
				local words = string.split(line, "\t")
				local num = tonumber(words[1])
				if num then
					item_stat_extra[num] = {}
					for i = 0, #words - 3 do
						local vals = string.split(words[i + 3], "/")
						if #vals == 2 then
							item_stat_extra[num][i] = tonumber(vals[1]) or 0
						else
							item_stat_extra[num][i] = tonumber(words[i + 3]) or 0
						end
					end
				end
			end
		--end
		io.close(txt_table)
	end
	MT.ItemStatExtra = item_stat_extra
	]=]
	return ok
end

-- Equippable items (Items.txt Equip Stat 0..12) without the requirement of their slot in
-- ItemsExtra.txt can't be put on at all: they are listed in the log
local function CheckItemsRequirements()
	local missing = {}
	for i = 1, Game.ItemsTxt.high do
		local es = Game.ItemsTxt[i].EquipStat
		if es <= 12 then
			-- missile weapons: Equip3Req, shields: Equip2Req, the rest: EquipReq
			local off = es == 2 and 16 or es == 4 and 10 or 4
			if i2[MO.ItemsExtra + i * item_extra_size + off] <= 0 then
				missing[#missing + 1] = i
			end
		end
	end
	if #missing > 0 then
		MF.LogWarning("%s: %d equippable items have no requirement in ItemsExtra.txt and can't be put on: %s",
			LogId, #missing, table.concat(missing, ", "))
	end
end

-- Base Recovery Time when player has only shield or broken items in arms (i.e. unarmed)
-- MM8 default values: 60 if player has Unarmed skill, 100 otherwise
asmpatch(0x48D6B3, [[
jnz @skill
mov eax, ]] .. (MM.UnarmedDelayNoSkill or 100) .. [[;
;mov dword ptr [ebp - 4], eax
;jmp absolute 0x48D6BE
jmp @end
@skill:
mov eax, ]] .. (MM.UnarmedDelay or 60) .. [[;
@end:
]], 0x48D6BC - 0x48D6B3)

local function SetItemsExtraHooks()
	-- ecx - item id
	-- preserves ecx, edx
	MO.GetItemSubtype = asmproc([[
	mov eax, ecx
	imul eax, ]] .. item_extra_size .. [[;
	add eax, ]] .. MO.ItemsExtra .. [[;
	movzx eax, word ptr [eax]
	retn
	]])

	-- ecx - item id
	-- preserves ecx, edx
	-- WARNING: expects subtype struct size to be 8 bytes
	MO.GetItemMainSkill = asmproc([[
	call absolute ]] .. MO.GetItemSubtype .. [[;
	shl eax, 3
	add eax, ]] .. MO.ItemSubtypes .. [[;
	movsx eax, word ptr [eax + 2]
	retn
	]])

	-- ecx - item id
	-- preserves ecx, edx
	-- WARNING: expects subtype struct size to be 8 bytes
	MO.IsItemTwoHand = asmproc([[
	call absolute ]] .. MO.GetItemSubtype .. [[;
	shl eax, 3
	add eax, ]] .. MO.ItemSubtypes .. [[;
	mov eax, dword ptr [eax + 4]
	and eax, 0x1
	retn
	]])

	-- ecx - item id, edx - slot
	-- preserves ecx
	-- WARNING: expects subtype struct size to be 8 bytes
	MO.IsItemEquipableAtSlot = asmproc([[
	xor eax, eax
	inc eax
	test edx, edx
	jz @f1
	push ecx
	mov ecx, edx
	shl eax, cl
	pop ecx
	@f1:
	mov edx, eax
	call absolute ]] .. MO.GetItemSubtype .. [[;
	shl eax, 3
	add eax, ]] .. MO.ItemSubtypes .. [[;
	mov eax, dword ptr [eax + 4]
	and eax, edx
	test eax, eax
	jz @end
	xor eax, eax
	inc eax
	@end:
	retn
	]])

	-- 0: skill id; 2: req player level; 4: req skill mastery; 6: req skill level
	-- 8: ...; 10: player level; 12: skill mastery; 14: skill level
	MO.SkillReq = StaticAlloc(16)

	-- ecx - player ptr, edx - item id, arg0 - req num
	MO.PlayerFulfillItemSkillReq = asmproc([[
	push esi
	push edi
	push ebx
	mov ebx, dword ptr [esp + 0x10]
	mov esi, ecx
	mov edi, edx
	mov eax, edx
	imul eax, ]] .. item_extra_size .. [[;
	add eax, ]] .. (MO.ItemsExtra + 4) .. [[;
	mov edx, ebx
	dec edx
	lea edx, [edx + edx * 2]
	lea eax, [eax + edx * 2]
	xor edx, edx
	mov dx, word ptr [eax + 4]
	mov word ptr []] .. (MO.SkillReq + 6) .. [[], dx
	mov dx, word ptr [eax + 2]
	mov word ptr []] .. (MO.SkillReq + 4) .. [[], dx
	mov dx, word ptr [eax]
	mov word ptr []] .. (MO.SkillReq + 2) .. [[], dx
	;test dx, dx
	;jz @no
	mov ecx, esi
	call absolute 0x48C3D7 ; Player.GetLevel
	mov word ptr []] .. (MO.SkillReq + 10) .. [[], ax
	;movzx ecx, word ptr []] .. (MO.SkillReq + 2) .. [[]
	;cmp eax, ecx
	;jl @no

	;movzx edx, word ptr []] .. (MO.SkillReq + 4) .. [[]
	;test edx, edx
	;jz @yes
	mov ecx, edi
	call absolute ]] .. MO.GetItemMainSkill .. [[;
	mov word ptr []] .. MO.SkillReq .. [[], ax
	push eax
	mov ecx, esi
	call absolute 0x48EF4F ; Player.GetSkill
	mov ecx, eax
	call absolute ]] .. MO.SplitSkill .. [[;
	mov word ptr []] .. (MO.SkillReq + 12) .. [[], dx
	mov word ptr []] .. (MO.SkillReq + 14) .. [[], ax

	mov cx, word ptr []] .. (MO.SkillReq + 2) .. [[]
	test cx, cx
	jle @no
	cmp cx, word ptr []] .. (MO.SkillReq + 10) .. [[]
	jg @no
	mov cx, word ptr []] .. (MO.SkillReq + 4) .. [[]
	test cx, cx
	jle @yes
	cmp dx, cx
	jl @no
	cmp ax, word ptr []] .. (MO.SkillReq + 6) .. [[]
	jl @no

	@yes:
	xor eax, eax
	inc eax
	jmp @hook
	@no:
	xor eax, eax
	@hook:
	nop
	nop
	nop
	nop
	nop
	@end:
	pop ebx
	pop edi
	pop esi
	retn 4
	]])

	-- events.ItemEquipRequirement(t): t.Player, t.PlayerIndex, t.ItemId, t.Req (1 the item,
	-- 2 the left hand or a two-handed one in one hand, 3 missile weapons), t.Result (true if
	-- the requirement is met; a handler can refuse or allow it)
	hook(MO.PlayerFulfillItemSkillReq + 0xAC, function(d)
		MF.LogVerbose("PlayerFulfillItemSkillReq: %d %d - %d", d.edi, d.ebx, d.eax)
		if events.exists("ItemEquipRequirement") then
			local t = {PlayerPtr = d.esi, ItemId = d.edi, Req = d.ebx, Result = d.eax ~= 0}
			t.Player, t.PlayerIndex = MF.GetPlayerFromPtr(d.esi)
			events.call("ItemEquipRequirement", t)
			d.eax = t.Result and 1 or 0
		end
	end)

	-- ecx - player ptr, edx - item id, arg0 - req num
	MO.PlayerHasItemSkill = asmproc([[
	push esi
	mov esi, ecx
	push dword ptr [esp + 8]
	call absolute ]] .. MO.PlayerFulfillItemSkillReq .. [[;
	test eax, eax
	jnz @yes
	mov ecx, esi
	add ecx, 0xA8
	push ecx
	push dword ptr [0x601554] ; "%s does not have the skill"
	mov esi, 0x5DF0E0 ; TextBuffer
	push esi
	call absolute 0x4D9F10 ; sprintf
	add esp, 0xC
	mov edx, 2
	mov ecx, esi
	call absolute 0x4496C5 ; ShowStatusText
	xor eax, eax
	jmp @end
	@yes:
	xor eax, eax
	inc eax
	@end:
	pop esi
	retn 4
	]])

	-- Equiping item
	--
	--asmpatch(0x4673E2, "sub esp, 0x4C")

	--   Check main hand item for being two-hand only
	--   NOTE: spear is one-hand in vanilla MM8
	--   WARNING: have to preseve edx here
	asmpatch(0x467453, [[
	push edx
	;mov dword ptr [ebp - 0x48], eax
	mov ecx, eax
	call absolute ]] .. MO.IsItemTwoHand .. [[;
	cmp eax, 1
	jnz @end
	mov edx, ecx
	mov ecx, ebx
	push 2
	call absolute ]] .. MO.PlayerFulfillItemSkillReq .. [[;
	test eax, eax
	@end:
	pop edx
	]], 0x467460 - 0x467453)

	--   Two-hand item in mouse
	asmpatch(0x46748A, [[
	call absolute ]] .. MO.IsItemTwoHand .. [[;
	test eax, eax
	jz absolute 0x4674B8
	]])

	--   Player can hold mouse two-hand item in one hand
	asmpatch(0x467493, [[
	mov edx, ecx
	mov ecx, ebx
	push 2
	call absolute ]] .. MO.PlayerFulfillItemSkillReq .. [[;
	cmp eax, 1
	]], 0x4674A6 - 0x467493)

	--   Mouse item equipable in left hand
	asmpatch(0x4674B8, [[
	mov edx, 2
	call absolute ]] .. MO.IsItemEquipableAtSlot .. [[;
	test eax, eax
	jz absolute 0x4674EC
	]], 0x4674C7 - 0x4674B8)

	--   Two-hand item in right hand
	asmpatch(0x4674D5, [[
	mov ecx, eax
	call absolute ]] .. MO.IsItemTwoHand .. [[;
	cmp eax, 1
	]], 0x4674E2 - 0x4674D5)

	--   Missile, armor, etc
	asmpatch(0x467512, [[
	mov ecx, dword ptr [0xB7CA64]
	mov edx, 3
	call absolute ]] .. MO.IsItemEquipableAtSlot .. [[;
	test eax, eax
	jnz @missile
	push 1
	jmp @f1
	@missile:
	push 3
	@f1:
	mov ecx, ebx
	mov edx, dword ptr [0xB7CA64]
	call absolute ]] .. MO.PlayerHasItemSkill .. [[;
	]])

	--   Shield
	asmpatch(0x4675F0, [[
	push 2
	mov ecx, ebx
	mov edx, dword ptr [0xB7CA64]
	call absolute ]] .. MO.PlayerHasItemSkill .. [[;
	]])

	--   One-hand: right
	asmpatch(0x46770E, [[
	push 1
	mov ecx, ebx
	mov edx, dword ptr [0xB7CA64]
	call absolute ]] .. MO.PlayerHasItemSkill .. [[;
	]])
	--   One-hand: left
	asmpatch(0x467722, [[
	push 2
	mov ecx, ebx
	mov edx, dword ptr [0xB7CA64]
	call absolute ]] .. MO.PlayerFulfillItemSkillReq .. [[;
	cmp eax, 1
	]], 0x46774D - 0x467722)

	--   Two-hand: both
	asmpatch(0x46790F, [[
	push 1
	mov ecx, ebx
	mov edx, dword ptr [0xB7CA64]
	call absolute ]] .. MO.PlayerHasItemSkill .. [[;
	]])
	--   Two-hand: single
	asmpatch(0x467925, [[
	cmp dword ptr [ebp - 4], esi
	jz absolute 0x467943
	push 2
	mov ecx, ebx
	mov edx, dword ptr [0xB7CA64]
	call absolute ]] .. MO.PlayerFulfillItemSkillReq .. [[;
	test eax, eax
	jg absolute 0x467943
	]])
	--   Two-hand: single
	asmpatch(0x4679B8, [[
	push 2
	mov ecx, ebx
	mov edx, dword ptr [0xB7CA64]
	call absolute ]] .. MO.PlayerFulfillItemSkillReq .. [[;
	test eax, eax
	jnz absolute 0x467A18
	dec dword ptr [ebp - 4]
	mov eax, dword ptr [ebp -4]
	]])
end


local function get_item_subtype(item_id)
	return mem.call(MO.GetItemSubtype, 1, item_id)
end
MF.GetItemSubtype = get_item_subtype

local function get_item_main_skill(item_id)
	return mem.call(MO.GetItemMainSkill, 1, item_id)
end

local function is_twohand_item(item_id)
	return mem.call(MO.IsItemTwoHand, 1, item_id) ~= 0
end

local function player_fulfill_req(player, item_id, req_num)
	return mem.call(MO.PlayerFulfillItemSkillReq, 2, player["?ptr"], item_id, req_num) ~= 0
end
MF.PlayerFulfillReq = player_fulfill_req

local function can_player_wear_right(player, item_id)
	if not mem.call(MO.IsItemEquipableAtSlot, 2, item_id, 1) then
		return false
	end
	local left = player.ItemExtraHand
	local req = 1
	if left > 0 and is_twohand_item(item_id) then
		req = 2
	end
	if player_fulfill_req(player, item_id, req) then
		return true
	end
	return false
end
MF.CanPlayerWearRight = can_player_wear_right

local function can_player_wear_left(player, item_id)
	if not mem.call(MO.IsItemEquipableAtSlot, 2, item_id, 2) then
		return false
	end
	if is_twohand_item(item_id) then return false end
	local right = player.ItemMainHand  > 0 and player.Items[player.ItemMainHand - 1].Number
	if right and is_twohand_item(right) then
		if not player_fulfill_req(player, right, 2) then
			return false
		end
	end
	if player_fulfill_req(player, item_id, 2) then
		return true
	end
	return false
end
MF.CanPlayerWearLeft = can_player_wear_left

local function can_player_wear_missile(player, item_id)
	if not mem.call(MO.IsItemEquipableAtSlot, 2, item_id, 3) then
		return false
	end
	if player_fulfill_req(player, item_id, 3) then
		return true
	end
	return false
end
MF.CanPlayerWearMissile = can_player_wear_missile

--[=[
local function player_get_item_extra_stat(player, subtype, stat, extra)
	if subtype <= 0 then return 0 end
	local res = 0
	local id = extra_stat_type_count * (2 * (subtype - 1) + (extra and 1 or 0)) + stat
	--if stat < 2 then
	--	if MT.ItemExtraStats and MT.ItemExtraStats[id] then
	--		res = MT.ItemExtraStats[id][stat] or 0
	--	end
	--else
		if MT.ItemExtraStats and MT.ItemExtraStats[id] then
			local sm, val
			for sk = 0, 38 do
				sm = MF.GetPlayerSkillMastery(player, sk)
				if sm > 0 then
					val = MT.ItemExtraStats[id][sk * 4 + sm] or 0
					if stat < 2 then
						res = res + val
					end
				end
			end
			if stat > 1 then
				res = math.floor(res/16)
			end
		end
	--end
	return res
end
MF.PlayerGetItemExtraStat = player_get_item_extra_stat
]=]

local function SetItemsModifiersHooks()

	-------------------------------------
	-- Double Damage item special bonuses
	--   * Extends amount of bonuses
	--   * Allows item to have more than one Double Damage bonus
	--   * Adds event ItemHasBonus2

	-- edx - MonsterId
	-- edi - Player pointer
	-- [ebp+0] - Item.Number
	-- [ebp+0xC] - Item.Bonus2
	NewCode = asmproc([[
	cmp eax, dword ptr [ebp+0xC]
	jz @end
	mov ecx, dword ptr [ebp+0]
	nop
	nop
	nop
	nop
	nop
	@end:
	retn
	]])

	hook(NewCode + 8, function(d)
		local t = {PlayerPtr = d.edi, ItemId = d.ecx, Bonus2 = d.eax, MonsterId = d.edx, Result = 0}
		--Log(Merge.Log.Info, "ItemHasBonus2: 0x%X, %d, %d, %d", t.PlayerPtr, t.ItemId, t.Bonus2, t.MonsterId)
		events.call("ItemHasBonus2", t)
		d.eax = t.Result
	end)

	-- CalcMeleeDamage: Right hand
	--   ebx - MonsterId
	--   edi - Player pointer
	--   esi - Damage
	--   [ebp+0] - Item.Number
	--   [ebp+0xC] - Item.Bonus2
	asmpatch(0x48C810, [[
	mov ebx, ecx
	xor edx, edx
	inc edx
	call absolute 0x436542
	test eax, eax
	jz @dragon
	mov eax, 0x40
	mov edx, ebx
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48C824
	@dragon:
	mov edx, 2
	mov ecx, ebx
	call absolute 0x436542
	test eax, eax
	jz @swimmer
	mov eax, 0x28
	mov edx, ebx
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48C824
	@swimmer:
	mov edx, 3
	mov ecx, ebx
	call absolute 0x436542
	test eax, eax
	jz @ogre
	mov eax, 0x4F
	mov edx, ebx
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48C824
	@ogre:
	mov edx, 7
	mov ecx, ebx
	call absolute 0x436542
	test eax, eax
	jz @elemental
	mov eax, 0x27
	mov edx, ebx
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48C824
	@elemental:
	mov edx, 8
	mov ecx, ebx
	call absolute 0x436542
	test eax, eax
	jz @demon
	mov eax, 0x3F
	mov edx, ebx
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48C824
	@demon:
	mov edx, 9
	mov ecx, ebx
	call absolute 0x436542
	test eax, eax
	jz @titan
	mov eax, 0x4A
	mov edx, ebx
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48C824
	@titan:
	mov edx, 0xA
	mov ecx, ebx
	call absolute 0x436542
	test eax, eax
	jz @elf
	mov eax, 0x41
	mov edx, ebx
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48C824
	@elf:
	mov edx, 0xB
	mov ecx, ebx
	call absolute 0x436542
	test eax, eax
	jz @goblin
	mov eax, 0x4B
	mov edx, ebx
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48C824
	@goblin:
	mov edx, 0xC
	mov ecx, ebx
	call absolute 0x436542
	test eax, eax
	jz @dwarf
	mov eax, 0x4C
	mov edx, ebx
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48C824
	@dwarf:
	mov edx, 0xD
	mov ecx, ebx
	call absolute 0x436542
	test eax, eax
	jz @human
	mov eax, 0x4D
	mov edx, ebx
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48C824
	@human:
	mov edx, 0xE
	mov ecx, ebx
	call absolute 0x436542
	test eax, eax
	jz @end
	mov eax, 0x4E
	mov edx, ebx
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48C824
	@end:
	jmp absolute 0x48C868
	]])

	-- CalcMeleeDamage: Left hand
	--   esi - MonsterId
	--   edi - Player pointer
	--   ebx - Damage
	--   [ebp+0] - Item.Number
	--   [ebp+0xC] - Item.Bonus2
	asmpatch(0x48C92A, [[
	mov esi, ecx
	xor edx, edx
	inc edx
	call absolute 0x436542
	test eax, eax
	jz @dragon
	mov eax, 0x40
	mov edx, esi
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48C93E
	@dragon:
	mov edx, 2
	mov ecx, esi
	call absolute 0x436542
	test eax, eax
	jz @swimmer
	mov eax, 0x28
	mov edx, esi
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48C93E
	@swimmer:
	mov edx, 3
	mov ecx, esi
	call absolute 0x436542
	test eax, eax
	jz @ogre
	mov eax, 0x4F
	mov edx, esi
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48C93E
	@ogre:
	mov edx, 7
	mov ecx, esi
	call absolute 0x436542
	test eax, eax
	jz @elemental
	mov eax, 0x27
	mov edx, esi
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48C93E
	@elemental:
	mov edx, 8
	mov ecx, esi
	call absolute 0x436542
	test eax, eax
	jz @demon
	mov eax, 0x3F
	mov edx, esi
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48C93E
	@demon:
	mov edx, 9
	mov ecx, esi
	call absolute 0x436542
	test eax, eax
	jz @titan
	mov eax, 0x4A
	mov edx, esi
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48C93E
	@titan:
	mov edx, 0xA
	mov ecx, esi
	call absolute 0x436542
	test eax, eax
	jz @elf
	mov eax, 0x41
	mov edx, esi
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48C93E
	@elf:
	mov edx, 0xB
	mov ecx, esi
	call absolute 0x436542
	test eax, eax
	jz @goblin
	mov eax, 0x4B
	mov edx, esi
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48C93E
	@goblin:
	mov edx, 0xC
	mov ecx, esi
	call absolute 0x436542
	test eax, eax
	jz @dwarf
	mov eax, 0x4C
	mov edx, esi
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48C93E
	@dwarf:
	mov edx, 0xD
	mov ecx, esi
	call absolute 0x436542
	test eax, eax
	jz @human
	mov eax, 0x4D
	mov edx, esi
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48C93E
	@human:
	mov edx, 0xE
	mov ecx, esi
	call absolute 0x436542
	test eax, eax
	jz @end
	mov eax, 0x4E
	mov edx, esi
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48C93E
	@end:
	jmp absolute 0x48C971
	]])

	-- Missile
	--   [ebp+8] - MonsterId
	--   ebx - Player pointer
	--   esi - Damage
	--   [edi+0] - Item.Number
	--   [edi+0xC] - Item.Bonus2
	NewCode = asmproc([[
	cmp eax, dword ptr [edi+0xC]
	jz @end
	mov ecx, dword ptr [edi+0]
	mov edx, dword ptr [ebp+8]
	nop
	nop
	nop
	nop
	nop
	@end:
	retn
	]])

	hook(NewCode + 10, function(d)
		local t = {PlayerPtr = d.ebx, ItemId = d.ecx, Bonus2 = d.eax, MonsterId = d.edx, Result = 0}
		--Log(Merge.Log.Info, "ItemHasBonus2: 0x%X, %d, %d, %d", t.PlayerPtr, t.ItemId, t.Bonus2, t.MonsterId)
		events.call("ItemHasBonus2", t)
		d.eax = t.Result
	end)

	-- CalcRangedDamage
	asmpatch(0x48CB80, [[
	xor edx, edx
	inc edx
	call absolute 0x436542
	test eax, eax
	jz @dragon
	mov eax, 0x40
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48CB94
	@dragon:
	mov edx, 2
	mov ecx, dword ptr [ebp+8]
	call absolute 0x436542
	test eax, eax
	jz @swimmer
	mov eax, 0x28
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48CB94
	@swimmer:
	mov edx, 3
	mov ecx, dword ptr [ebp+8]
	call absolute 0x436542
	test eax, eax
	jz @ogre
	mov eax, 0x4F
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48CB94
	@ogre:
	mov edx, 7
	mov ecx, dword ptr [ebp+8]
	call absolute 0x436542
	test eax, eax
	jz @elemental
	mov eax, 0x27
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48CB94
	@elemental:
	mov edx, 8
	mov ecx, dword ptr [ebp+8]
	call absolute 0x436542
	test eax, eax
	jz @demon
	mov eax, 0x3F
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48CB94
	@demon:
	mov edx, 9
	mov ecx, dword ptr [ebp+8]
	call absolute 0x436542
	test eax, eax
	jz @titan
	mov eax, 0x4A
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48CB94
	@titan:
	mov edx, 0xA
	mov ecx, dword ptr [ebp+8]
	call absolute 0x436542
	test eax, eax
	jz @elf
	mov eax, 0x41
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48CB94
	@elf:
	mov edx, 0xB
	mov ecx, dword ptr [ebp+8]
	call absolute 0x436542
	test eax, eax
	jz @goblin
	mov eax, 0x4B
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48CB94
	@goblin:
	mov edx, 0xC
	mov ecx, dword ptr [ebp+8]
	call absolute 0x436542
	test eax, eax
	jz @dwarf
	mov eax, 0x4C
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48CB94
	@dwarf:
	mov edx, 0xD
	mov ecx, dword ptr [ebp+8]
	call absolute 0x436542
	test eax, eax
	jz @human
	mov eax, 0x4D
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48CB94
	@human:
	mov edx, 0xE
	mov ecx, dword ptr [ebp+8]
	call absolute 0x436542
	test eax, eax
	jz @end
	mov eax, 0x4E
	call absolute ]] .. NewCode .. [[;
	test eax, eax
	jnz absolute 0x48CB94
	@end:
	jmp absolute 0x48CBCC
	]])

	---------------------------------
	-- ItemAdditionalDamage

	local CheckItemAddDamageAsm = asmproc([[
	push ebp
	mov ebp, esp
	push esi
	mov esi, dword ptr [ebp+0x10]
	push dword ptr [ebp+0xC]
	push dword ptr [ebp+8]
	call absolute 0x4378CD
	pop esi
	pop esi
	pop ebp
	retn 12
	]])

	-- Test additional damage from item against monster
	--   itemptr - Item struct (like Party[x].Items[y]) or pointer (like Party[x].Items[y]["?ptr"])
	--   playerptr - Player struct (like Party[x]) or pointer (like Party[x]["?ptr"])
	--   monster - either MapMonster pointer (Map.Monsters[z]["?ptr"]) or monster id (less than 65536)
	--     If monster id has been passed - creates monster with AIState = Removed.
	local function check_item_additional_damage(itemptr, playerptr, monster)
		local a = mem.malloc(8)
		local v = a + 4
		local monptr
		if type(itemptr) == "table" then
			itemptr = itemptr["?ptr"]
		end
		if type(playerptr) == "table" then
			playerptr = playerptr["?ptr"]
		end
		if monster < 0x10000 then
			local n = Map.Monsters.Count
			local x, y, z = XYZ(Party)
			mem.call(offsets.SummonMonster, 2, monster, x, y, z)
			if Map.Monsters.Count == n + 1 then
				local mon = Map.Monsters[n]
				local place
				mon.AIState = 11
				for i = 0, n - 1 do
					if Map.Monsters[i].AIState == 11 then  -- const.AIState.Removed
						place = i
						break
					end
				end
				if place then
					local a = Map.Monsters[place]
					mem.copy(a["?ptr"], mon["?ptr"], mon["?size"])
					Map.Monsters.Count = n
					mon = a
				end
				monptr = mon["?ptr"]
			end
		else
			monptr = mon
		end
		local dmg = mem.call(CheckItemAddDamageAsm, 2, itemptr, a, v, playerptr, monptr)
		local res1, res2 = u4[a], u4[v]
		mem.free(a)
		return dmg, res1, res2
	end
	MF.CheckItemAdditionalDamage = check_item_additional_damage

	-- Check for Vampiric bonus
	NewCode = asmpatch(0x4378FA, [[
	nop
	nop
	nop
	nop
	nop
	test eax, eax
	jz @end
	mov dword ptr [edi], 0xA
	mov eax, dword ptr [ebp+8]
	mov dword ptr [eax], 1
	@end:
	mov ebx, 2
	jmp absolute 0x437997
	]])

	hook(NewCode, function(d)
		local t = {ItemId = i4[d.ebx], Bonus2 = i4[d.ebx + 0xC], Group = 2, Result = 0}
		events.call("ItemHasBonus2OfGroup", t)
		--MF.LogInfo("Bonus2OfGroup: %d - %d (%d)", t.ItemId, t.Result, t.Group)
		d.eax = t.Result
	end)

	-- Check for additional damage bonuses
	-- Notes:
	--   * ebx should contain 2
	--   * Vampiric bonuses are ignored here (unlike vanilla MM8)
	NewCode = asmpatch(0x43799A, [[
	nop
	nop
	nop
	nop
	nop
	test eax, eax
	jz absolute 0x43793E
	cmp eax, 0x2E
	jle absolute 0x4379A6
	cmp eax, 0x43
	jl @none
	jz absolute 0x437ABD
	cmp eax, 0x44
	jz absolute 0x437A4E
	sub eax, 0x50
	jl @none
	cmp eax, 9
	jz @none
	jg @bite
	cmp eax, 3
	jle @two
	add eax, 2
	@two:
	mov dword ptr [edi], eax
	jmp absolute 0x437ADC
	@none:
	jmp absolute 0x4378E3
	@bite:
	cmp eax, 0x14
	jge @none
	cmp eax, 0xE
	jg @blow
	sub eax, 0xA
	jnz @f1
	mov eax, 3
	jmp @f5
	@f1:
	dec eax
	jnz @f2
	mov eax, 6
	jmp @f5
	@f2:
	dec eax
	jnz @f3
	mov eax, 7
	jmp @f5
	@f3:
	dec eax
	jnz @f4
	mov eax, 9
	jmp @f5
	@f4:
	mov eax, 0xA
	@f5:
	mov dword ptr [edi], eax
	jmp absolute 0x437A08
	@blow:
	sub eax, 0xF
	jnz @f6
	mov eax, 3
	jmp @f10
	@f6:
	dec eax
	jnz @f7
	mov eax, 6
	jmp @f10
	@f7:
	dec eax
	jnz @f8
	mov eax, 7
	jmp @f10
	@f8:
	dec eax
	jnz @f9
	mov eax, 9
	jmp @f10
	@f9:
	mov eax, 0xA
	@f10:
	mov dword ptr [edi], eax
	jmp absolute 0x4379F9
	]])

	hook(NewCode, function(d)
		local t = {ItemId = i4[d.eax], Bonus2 = i4[d.eax + 0xC], Group = 1, Result = 0}
		events.call("ItemHasBonus2OfGroup", t)
		--MF.LogInfo("Bonus2OfGroup: %d - %d (%d)", t.ItemId, t.Result, t.Group)
		d.eax = t.Result
	end)

	-- Fix bonus 15: use Body rather than Water
	-- fixed in MMPatch 2.5
	--[=[
	asmpatch(0x437AAD, [[
	mov dword ptr [edi], 8
	push 0xC
	jmp absolute 0x437AC5
	]])
	]=]

	---------------------------------
	-- 'of Carnage' bonus
	NewCode = mem.asmpatch(0x42642E, [[
	lea edi, [ebp-0x88]
	cmp dword ptr [edi+0xC], 3
	je @end
	mov eax, dword ptr [edi]
	nop
	nop
	nop
	nop
	nop
	test eax, eax
	jz @end
	mov dword ptr [edi+0xC], 3
	@end:
	or byte ptr [ebp-0x91], 1
	]])

	mem.hook(NewCode + 0xE, function(d)
		local t = {ItemId = d.eax, Bonus2 = 3, Result = 0}
		events.call("ItemHasBonus2", t)
		--Log(Merge.Log.Info, "ItemHasBonus2: %d, %d - %d", t.ItemId, t.Bonus2, t.Result)
		d.eax = t.Result
	end)

	-- Make Carnage bows to deal damage to paralyzed monsters
	-- fixed in MMPatch 2.5
	--[=[
	local ignore_paralyze = mem.malloc(4)
	mem.u4[ignore_paralyze] = 0
	mem.asmpatch(0x436CB3, [[
	mov dword ptr []] .. ignore_paralyze .. [[], 1
	call absolute 0x409069
	mov dword ptr []] .. ignore_paralyze .. [[], 0
	]])
	mem.asmpatch(0x409086, [[
	mov eax, dword ptr []] .. ignore_paralyze .. [[]
	test eax, eax
	jnz absolute 0x40909B
	cmp dword ptr [ecx+0x140], esi
	]])
	]=]

	-- Item cost increase based on StdBonus
	autohook2(0x453D13, function(d)
		local t = {Item = u4[d.esi], BaseCost = d.edi, StdBonus = u4[d.esi+4],
			BonusStrength = u4[d.esi+8], Result = d.eax}
		events.cocall("GetItemStdBonusCost", t)
		d.edi = t.BaseCost
		d.eax = t.Result
	end)

	-- Genie Lamp
	if MM.ItemsGenieLampType == 2 then
		asmpatch(0x466638, [[
		jz @end
		cmp eax, 0x2F9
		jnz absolute 0x4671A1
		@end:
		]])
	end

	-- HP/SP regen spc bonuses on items > 151
	mem.nop2(0x491F7B, 0x491F83)

	-- Show spell scroll power without stdbonus
	if MM.SpellScrollRanks == 1 then
		asmpatch(0x41D365, [[
		jz @ff
		push dword ptr [ecx + 8]
		jmp @end
		@ff:
		mov eax, dword ptr [ecx]
		cmp eax, 1900
		jg @out
		cmp eax, 300
		jl @out
		cmp eax, 399
		jg @mm7
		push 5
		mov eax, 28
		jmp @end
		@mm7:
		cmp eax, 1102
		jl @out
		cmp eax, 1200
		jg @mm6
		push 4
		mov eax, 27
		jmp @end
		@mm6:
		cmp eax, 1802
		jl @out
		push 3
		mov eax, 26
		jmp @end
		@out:
		jmp absolute 0x41D390
		@end:
		]])
		asmpatch(0x41D374, [[
		mov eax, dword ptr [ecx + 4]
		test eax, eax
		jz @ff
		push dword ptr [0x601790] ; "Special"
		jmp @end
		@ff:
		push dword ptr [0x601B4C] ; "Power"
		@end:
		]])
	end

	-- Remove consumed item event
	NewCode = mem.asmpatch(0x4672BD, [[
	xor eax, eax
	nop
	nop
	nop
	nop
	nop
	test eax, eax
	jnz @end
	call absolute 0x467C0A
	@end:
	]])

	mem.hook(NewCode + 2, function(d)
		local t = {ItemId = mem.i4[0xB7CA64]}
		t.Handled = false
		events.cocall("RemoveConsumedItem", t)
		d.eax = t.Handled and 1
	end)
end

-- Spell Scroll stdbonus
function events.ItemGenerated(t)
	if MM.SpellScrollRanks ~= 1 then
		return
	end
	if t.Item.Number > 299 and t.Item.Number < 400 then
		t.Item.Bonus = random(28, 29)
		t.Item.BonusStrength = random(7, 9) + t.Item.Bonus - 28
	elseif t.Item.Number > 1101 and t.Item.Number < 1202 then
		t.Item.Bonus = random(27, 28)
		t.Item.BonusStrength = random(5, 7) + t.Item.Bonus - 27
	elseif t.Item.Number > 1801 and t.Item.Number < 1902 then
		t.Item.Bonus = random(26, 27)
		t.Item.BonusStrength = random(3, 5) + t.Item.Bonus - 26
	else
		return
	end
	MF.LogVerbose("SpellScroll StdBonus: item %d, bonus %d, strength %d", t.Item.Number, t.Item.Bonus, t.Item.BonusStrength)
end

-- Spell Scroll stdbonus cost
function events.GetItemStdBonusCost(t)
	if MM.SpellScrollRanks ~= 1 or t.StdBonus < 26 or t.StdBonus > 29 then
		return
	end
	if t.Item > 299 and t.Item < 400 then
		t.Result = floor(max(2 ^ (t.StdBonus - 28) - 1, -0.75) * t.BaseCost
			+ max(t.BonusStrength - 7, 0) * t.BaseCost / 10)
	elseif t.Item > 1101 and t.Item < 1202 then
		t.Result = floor(max(2 ^ (t.StdBonus - 27) - 1, -0.5) * t.BaseCost
			+ max(t.BonusStrength - 5, 0) * t.BaseCost / 10)
	elseif t.Item > 1801 and t.Item < 1902 then
		t.Result = floor(max(2 ^ (t.StdBonus - 26) - 1, 0) * t.BaseCost
			+ max(t.BonusStrength - 3, 0) * t.BaseCost / 10)
	end
end

-- New resistance stdbonus cost
function events.GetItemStdBonusCost(t)
	if t.StdBonus < 30 or t.StdBonus > 32 then return end
	if t.StdBonus == 30 then
		t.Result = t.BaseCost + 100*t.BonusStrength
	elseif t.StdBonus == 31 or t.StdBonus == 32 then
		t.Result = t.BaseCost + 150*t.BonusStrength
	end
end

local chest_item_map_tres_lvl = {
	[1] = { -- MM8
		1, 1,  1, 1,  1, 1,  1, 1,  1, 1,  1, 1,  1, 1,
		1, 1,  1, 2,  2, 2,  2, 2,  2, 2,  2, 2,  2, 2,
		1, 2,  2, 2,  2, 3,  3, 3,  3, 3,  3, 3,  3, 3,
		2, 2,  2, 3,  3, 3,  3, 4,  4, 4,  4, 4,  4, 4,
		2, 3,  3, 3,  3, 4,  4, 4,  4, 5,  5, 5,  5, 5,
		3, 3,  3, 4,  4, 4,  4, 5,  5, 5,  5, 6,  6, 6,
		7, 7,  7, 7,  7, 7,  7, 7,  7, 7,  7, 7,  7, 7,
	},
	[2] = { -- MM7
		1, 1,  1, 1,  1, 1,  1, 1,  1, 1,  1, 1,  1, 1,
		1, 1,  1, 2,  2, 2,  2, 2,  2, 2,  2, 2,  2, 2,
		1, 2,  2, 2,  2, 3,  3, 3,  3, 3,  3, 3,  3, 3,
		2, 2,  2, 3,  3, 3,  3, 4,  4, 4,  4, 4,  4, 4,
		2, 3,  3, 3,  3, 4,  4, 4,  4, 5,  5, 5,  5, 5,
		3, 3,  3, 4,  4, 4,  4, 5,  5, 5,  5, 6,  6, 6,
		7, 7,  7, 7,  7, 7,  7, 7,  7, 7,  7, 7,  7, 7,
	},
	[3] = { -- MM6
		1, 1,  1, 1,  1, 1,  1, 1,  1, 1,  1, 1,  1, 1,
		1, 1,  1, 2,  2, 2,  2, 2,  2, 2,  2, 2,  2, 2,
		1, 2,  2, 2,  2, 3,  3, 3,  3, 3,  3, 3,  3, 3,
		2, 2,  2, 3,  3, 3,  3, 4,  4, 4,  4, 4,  4, 4,
		2, 3,  3, 3,  3, 4,  4, 4,  4, 5,  5, 5,  5, 5,
		3, 3,  3, 4,  4, 4,  4, 5,  5, 5,  5, 6,  6, 6,
		7, 7,  7, 7,  7, 7,  7, 7,  7, 7,  7, 7,  7, 7,
	}
}

-- Set rnditems continent factor
function events.ContinentChange1()
	MF.LogVerbose("%s: ContinentChange1", LogId)
	local sum = {}
	for j = 1, 6 do
		sum[j] = 0
	end
	for i = 1, Game.ItemsTxt.high do
		local factor = MV.Continent and MT.ItemsExtra[i]
			and MT.ItemsExtra[i].ContFactor[MV.Continent] or 1
		for j = 1, 6 do
			Game.ItemsTxt[i].ChanceByLevel[j] = MT.ItemsChanceByLevel[i][j] * factor
			sum[j] = sum[j] + Game.ItemsTxt[i].ChanceByLevel[j]
		end
	end
	for j = 1, 6 do
		Game.ItemsChanceByLevelSum[j] = sum[j]
	end
	local base = 0x4F7CF0
	local chest_type = MV.Continent and Game.ContinentSettings
		and Game.ContinentSettings[MV.Continent]
		and Game.ContinentSettings[MV.Continent].ChestType or 1
	local chest_tbl = chest_item_map_tres_lvl[chest_type] or chest_item_map_tres_lvl[1]
	for i = 0, 97 do
		mem.u1[base + i] = chest_tbl[i + 1] or (math.floor(i / 14) + 1)
	end
end

-- Replace consumed items
function events.RemoveConsumedItem(t)
	local replacing_item = 0
	if MF.SettingGtNum(MM.PreservePotionBottles, 0) then
		if t.ItemId > 220 and t.ItemId < 291 or t.ItemId >= 293 and t.ItemId <= 299
				or t.ItemId >= 1022 and t.ItemId <= 1028 then   -- MMMWE: the potions 293..299, 1022..1028
			replacing_item = 220
		end
	end
	if replacing_item > 0 then
		MF.LogVerbose("Replace consumed item %d with item %d", t.ItemId, replacing_item)
		mem.fill(0xB7CA64, 0x24, 0)
		mem.i4[0xB7CA64] = replacing_item
		mem.i4[0xB7CA78] = 1
		t.Handled = true
	else
		MF.LogVerbose("Remove consumed item %d", t.ItemId)
	end
end

function events.GameInitialized1()
	MF.LogVerbose("%s: GameInitialized1", LogId)
	SetItemsModifiersHooks()
end

function events.GameInitialized2()
	MF.LogVerbose("%s: GameInitialized2", LogId)
	local ok = ProcessItemsExtraFiles()
	MT.ItemsChanceByLevel = {}
	for i = 1, Game.ItemsTxt.high do
		MT.ItemsChanceByLevel[i] = {}
		for j = 1, 6 do
			MT.ItemsChanceByLevel[i][j] = Game.ItemsTxt[i].ChanceByLevel[j]
		end
	end
	if ok then
		SetItemsExtraHooks()
		CheckItemsRequirements()
	end
end

MF.LogInit2(LogId)

