local LogId = "ItemsModifiers"
local MF = Merge.Functions
MF.LogInit1(LogId)
local MM, MT, MV = Merge.ModSettings, Merge.Tables, Merge.Vars

local asmpatch, asmproc, autohook2, hook = mem.asmpatch, mem.asmproc, mem.autohook2, mem.hook
local i4, u4 = mem.i4, mem.u4
local floor, max, random = math.floor, math.max, math.random

local NewCode

local function ProcessItemsExtraTxt()
	local items_extra = {}
	local table_file = "Data/Tables/ItemsExtra.txt"
	local header = "Id\9Note\9ContF\9QCont\9LostQBit\9StartQBit\9EndQBit\9PostEnd"

	local txt_table = io.open(table_file, "r")
	if not txt_table then
		MF.LogWarning("%s: No ItemsExtra.txt found", LogId)
	else
		local iter = txt_table:lines()
		if iter() ~= header then
			MF.LogWarning("%s: ItemsExtra.txt has wrong header", LogId)
		else
			local line_num = 1
			for line in iter do
				line_num = line_num + 1
				local words = string.split(line, "\9")
				local num = tonumber(words[1])
				if num then
					items_extra[num] = {
						--Continent = tonumber(words[3]),
						ContFactor = {},
						--QuestItem = words[4] == "x",
						QuestCont = tonumber(words[4]),
						LostQBit  = tonumber(words[5]),
						StartQBit = tonumber(words[6]),
						EndQBit = tonumber(words[7]),
						PostEnd = words[8] == "x"
					}
					local cf = string.split(words[3], ",")
					for k, v in pairs(cf) do
						items_extra[num].ContFactor[k] = tonumber(v)
					end
				end
			end
		end
		io.close(txt_table)
	end

	MT.ItemsExtra = items_extra
end

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
		if t.ItemId > 220 and t.ItemId < 291 then
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
	ProcessItemsExtraTxt()
	MT.ItemsChanceByLevel = {}
	for i = 1, Game.ItemsTxt.high do
		MT.ItemsChanceByLevel[i] = {}
		for j = 1, 6 do
			MT.ItemsChanceByLevel[i][j] = Game.ItemsTxt[i].ChanceByLevel[j]
		end
	end
end

MF.LogInit2(LogId)

