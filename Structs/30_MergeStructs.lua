local LogId = "MergeStructs"
local MF = Merge.Functions
MF.LogInit1(LogId)
local MC, MM, MO = Merge.Consts, Merge.ModSettings, Merge.Offsets

local asmpatch, asmproc, hook, StaticAlloc = MF.Asmpatch, MF.Asmproc, MF.Hook, MF.StaticAlloc

function structs.f.SpcAttack(define)
	define
	.u2 'Spell'
	.u1 'Skill'
	.u1 'DamageType'
	.u2 'SpellPoints'
	.u2 'Recovery'
	.i8 'NextTime'
	.bit('IgnoreByDefault', 0x1)
	.bit('OverwriteMeleeBlaster', 0x2)
	.bit('OverwriteMissileBlaster', 0x4)
	.bit('PreferWand', 0x8)
	.bit('CooldownReducedBySpeed', 0x10)
	.bit('RecoveryReducedBySpeed', 0x20)
	.bit('CooldownReducedBySkill', 0x40)
	.bit('RecoveryReducedBySkill', 0x80)
	.bit('CooldownReducedByHaste', 0x100)
	.bit('RecoveryReducedByHaste', 0x200)
	.bit('CooldownOther', 0x400)
	.bit('UseOtherCooldown', 0x800)
	.u4 'Bits'
	.u4 'Cooldown'
	.i4 'Projectile'
	.i4 'Sound'
end

MC.PlayerBuffs2Count = 7
MC.PlayerBuffsCount = 27 + MC.PlayerBuffs2Count
MC.PlayerDebuffsCount = 20 -- Conditions 0-12,15,17-19

MC.PartyBuffs2Count = 6
MC.PartyBuffsCount = 20 + MC.PartyBuffs2Count
MC.PartyDebuffsCount = 11

function structs.f.PlayerExtra(define)
	define
	.alt.array(2).struct(structs.SpcAttack) 'SpcAttack'
	.struct(structs.SpcAttack) 'SpcAttackMelee'
	.struct(structs.SpcAttack) 'SpcAttackRanged'
	.array(27, 27 + MC.PlayerBuffs2Count - 1).struct(structs.SpellBuff) 'SpellBuffs2'
	.array(MC.PlayerDebuffsCount).struct(structs.SpellBuff) 'Debuffs'
	.size = 0x40 + 0x10 * (MC.PlayerBuffs2Count + MC.PlayerDebuffsCount)
end

MC.PlayerBuffs2Offset = 0x40
MC.PlayerDebuffsOffset = 0x40 + 0x10 * MC.PlayerBuffs2Count

local player_extra_size = structs.PlayerExtra["?size"]
MC.PlayerExtraSize = player_extra_size

MO.PlayersExtra = StaticAlloc(50 * player_extra_size)

MO.PartyBuffs2 = StaticAlloc((MC.PartyBuffs2Count + MC.PartyDebuffsCount) * 0x10)
MO.PartyDebuffs = MO.PartyBuffs2 + MC.PartyBuffs2Count * 0x10

-- ecx - player ptr
MO.GetPlayerExtraPtr = asmproc([[
movsx eax, word ptr [ecx + 0x1BF0]
sub eax, 400
imul eax, ]] .. player_extra_size .. [[;
add eax, ]] .. MO.PlayersExtra .. [[;
retn
]])

-----------------------------------
-- Extra Conditions, Buffs, Debuffs
-----------------------------------

-- ecx - player ptr, edx - buff index
MO.GetPlayerBuffPtr = asmproc([[
push esi
push edi
mov esi, ecx
mov edi, edx
cmp edi, 27
jge @buffs2
mov eax, esi
add eax, 0x1A34
mov ecx, edi
jmp @common
@buffs2:
call absolute ]] .. MO.GetPlayerExtraPtr .. [[;
add eax, ]] .. MC.PlayerBuffs2Offset .. [[;
mov ecx, edi
sub ecx, 27
@common:
imul ecx, 0x10
add eax, ecx
pop edi
pop esi
retn
]])

-- ecx - player ptr, edx - debuff index
MO.GetPlayerDebuffPtr = asmproc([[
push esi
push edi
mov esi, ecx
mov edi, edx
call absolute ]] .. MO.GetPlayerExtraPtr .. [[;
add eax, ]] .. MC.PlayerDebuffsOffset .. [[;
mov ecx, edi
imul ecx, 0x10
add eax, ecx
pop edi
pop esi
retn
]])

-- ecx - buff index
MO.GetPartyBuffPtr = asmproc([[
cmp ecx, 20
jge @buffs2
mov eax, 0xB21738
jmp @end
@buffs2:
mov eax, ]] .. MO.PartyBuffs2 .. [[;
sub ecx, 20
@end:
imul ecx, 0x10
add eax, ecx
retn
]])

-- ecx - debuff index
MO.GetPartyDebuffPtr = asmproc([[
mov eax, ecx
imul eax, 0x10
add eax, ]] .. MO.PartyDebuffs .. [[;
retn
]])

-- ecx - player ptr, edx - condition index
MO.CheckConditionDebuff = asmproc([[
push ebx
xor ebx, ebx
mov eax, dword ptr [ecx + edx * 8]
or eax, dword ptr [ecx + edx * 8 + 4]
jz @debuff
inc ebx
@debuff:
call absolute ]] .. MO.GetPlayerDebuffPtr .. [[;
mov ecx, eax
xor eax, eax
cmp dword ptr [ecx + 4], eax
jl @end
jg @pos
cmp dword ptr [ecx], eax
jbe @end
@pos:
inc eax
inc eax
@end:
add eax, ebx
pop ebx
retn
]])

-- ecx - player ptr
MO.ClearExpiredPlayerBuffs2 = asmproc([[
push esi
push edi
push ebx
mov esi, dword ptr [0xB20EC0]
mov edi, dword ptr [0xB20EBC]
call absolute ]] .. MO.GetPlayerExtraPtr .. [[;
mov ecx, eax
mov ebx, ]] .. MC.PlayerBuffs2Count .. [[;
test ebx, ebx
jz @end
add ecx, ]] .. MC.PlayerBuffs2Offset .. [[;
@loop:
mov eax, dword ptr [ecx + 4]
or eax, dword ptr [ecx]
jz @next
cmp dword ptr [ecx + 4], esi
jg @next
jl @clear
cmp dword ptr [ecx], edi
ja @next
@clear:
xor eax, eax
mov dword ptr [ecx], eax
mov dword ptr [ecx + 4], eax
mov dword ptr [ecx + 8], eax
mov dword ptr [ecx + 0xC], eax
@next:
add ecx, 0x10
dec ebx
jnz @loop
@end:
pop ebx
pop edi
pop esi
retn
]])

-- ecx - player ptr
MO.ClearExpiredPlayerDebuffs = asmproc([[
push esi
push edi
push ebx
mov esi, dword ptr [0xB20EC0]
mov edi, dword ptr [0xB20EBC]
call absolute ]] .. MO.GetPlayerExtraPtr .. [[;
mov ecx, eax
mov ebx, ]] .. MC.PlayerDebuffsCount .. [[;
test ebx, ebx
jz @end
add ecx, ]] .. MC.PlayerDebuffsOffset .. [[;
@loop:
mov eax, dword ptr [ecx + 4]
or eax, dword ptr [ecx]
jz @next
cmp dword ptr [ecx + 4], esi
jg @next
jl @clear
cmp dword ptr [ecx], edi
ja @next
@clear:
xor eax, eax
mov dword ptr [ecx], eax
mov dword ptr [ecx + 4], eax
mov dword ptr [ecx + 8], eax
mov dword ptr [ecx + 0xC], eax
@next:
add ecx, 0x10
dec ebx
jnz @loop
@end:
pop ebx
pop edi
pop esi
retn
]])

-- ecx - player ptr
MO.ClearExpiredPlayerBuffs2Debuffs = asmproc([[
push esi
push edi
push ebx
mov esi, dword ptr [0xB20EC0]
mov edi, dword ptr [0xB20EBC]
call absolute ]] .. MO.GetPlayerExtraPtr .. [[;
mov ecx, eax
mov ebx, ]] .. (MC.PlayerBuffs2Count + MC.PlayerDebuffsCount) .. [[;
test ebx, ebx
jz @end
add ecx, ]] .. MC.PlayerBuffs2Offset .. [[;
@loop:
mov eax, dword ptr [ecx + 4]
or eax, dword ptr [ecx]
jz @next
cmp dword ptr [ecx + 4], esi
jg @next
jl @clear
cmp dword ptr [ecx], edi
ja @next
@clear:
xor eax, eax
mov dword ptr [ecx], eax
mov dword ptr [ecx + 4], eax
mov dword ptr [ecx + 8], eax
mov dword ptr [ecx + 0xC], eax
@next:
add ecx, 0x10
dec ebx
jnz @loop
@end:
pop ebx
pop edi
pop esi
retn
]])

MO.ClearExpiredPartyDebuffs = asmproc([[
push esi
push edi
push ebx
mov esi, dword ptr [0xB20EC0]
mov edi, dword ptr [0xB20EBC]
xor edx, edx
mov ebx, ]] .. MC.PartyDebuffsCount .. [[;
test ebx, ebx
jz @end
mov ecx, ]] .. MO.PartyDebuffs .. [[;
@loop:
mov eax, dword ptr [ecx + 4]
or eax, dword ptr [ecx]
jz @next
cmp dword ptr [ecx + 4], esi
jg @next
jl @clear
cmp dword ptr [ecx], edi
ja @next
@clear:
inc edx
xor eax, eax
mov dword ptr [ecx], eax
mov dword ptr [ecx + 4], eax
mov dword ptr [ecx + 8], eax
mov dword ptr [ecx + 0xC], eax
@next:
add ecx, 0x10
dec ebx
jnz @loop
@end:
mov eax, edx
pop ebx
pop edi
pop esi
retn
]])

MO.ClearExpiredPartyBuffs2Debuffs = asmproc([[
push esi
push edi
push ebx
mov esi, dword ptr [0xB20EC0]
mov edi, dword ptr [0xB20EBC]
mov ebx, ]] .. (MC.PartyBuffs2Count + MC.PartyDebuffsCount) .. [[;
test ebx, ebx
jz @end
mov ecx, ]] .. MO.PartyBuffs2 .. [[;
@loop:
mov eax, dword ptr [ecx + 4]
or eax, dword ptr [ecx]
jz @next
cmp dword ptr [ecx + 4], esi
jg @next
jl @clear
cmp dword ptr [ecx], edi
ja @next
@clear:
xor eax, eax
mov dword ptr [ecx], eax
mov dword ptr [ecx + 4], eax
mov dword ptr [ecx + 8], eax
mov dword ptr [ecx + 0xC], eax
@next:
add ecx, 0x10
dec ebx
jnz @loop
@end:
pop ebx
pop edi
pop esi
retn
]])

-- ecx: buff ptr, arg0+arg4 - duration
MO.ShrinkBuff = asmproc([[
mov eax, dword ptr [ecx]
mov edx, dword ptr [ecx + 4]
sub eax, dword ptr [esp + 4]
sbb edx, dword ptr [esp + 8]
cmp edx, dword ptr [0xB20EC0]
jl @clear
jg @shrink
cmp eax, dword ptr [0xB20EBC]
jbe @clear
@shrink:
mov dword ptr [ecx], eax
mov dword ptr [ecx + 4], edx
xor eax, eax
inc eax
jmp @end
@clear:
xor eax, eax
mov dword ptr [ecx], eax
mov dword ptr [ecx + 4], eax
@end:
retn 8
]])

-- Condition colorer
asmpatch(0x416FF3, [[
cmp ebx, 0x13
ja absolute 0x417011
cmp ebx, 0x10
ja absolute 0x417006
]])

-- Condition name
MO.GetConditionName = asmproc([[
cmp ecx, 0x14
jae @good
mov eax, dword ptr [ecx*4 + 0xBB3010]
retn
@good:
mov eax, dword ptr [0x6015D0]
retn
]])

asmpatch(0x4178DD, [[
push eax
mov ecx, edi
call absolute ]] .. MO.GetConditionName .. [[;
pop ecx
push eax
mov eax, ecx
]])
asmpatch(0x41796E, "cmp dword ptr [ebp - 0x8], 0x4FDFF8")
asmpatch(0x4181A8, [[
mov ecx, eax
call absolute ]] .. MO.GetConditionName .. [[;
push eax
mov eax, ecx
]])
asmpatch(0x41AAD3, [[
mov ecx, ebp
call absolute ]] .. MO.GetConditionName .. [[;
push eax
]])
asmpatch(0x41CADC, [[
mov ecx, eax
call absolute ]] .. MO.GetConditionName .. [[;
push eax
mov eax, ecx
]])
asmpatch(0x4304E7, [[
mov ecx, eax
call absolute ]] .. MO.GetConditionName .. [[;
push eax
]])
asmpatch(0x43260F, [[
mov ecx, eax
call absolute ]] .. MO.GetConditionName .. [[;
push eax
]])
asmpatch(0x432790, [[
mov ecx, eax
call absolute ]] .. MO.GetConditionName .. [[;
push eax
]])
asmpatch(0x4669AB, [[
mov ecx, eax
call absolute ]] .. MO.GetConditionName .. [[;
push eax
]])
asmpatch(0x466A11, [[
mov ecx, eax
call absolute ]] .. MO.GetConditionName .. [[;
push eax
]])
asmpatch(0x4C915F, [[
mov ecx, eax
call absolute ]] .. MO.GetConditionName .. [[;
push eax
]])
-- Load condition names for Unarmed and Feebleminded
asmpatch(0x45073E, [[
mov ecx, dword ptr [0x60157C]
mov dword ptr [0xBB305C], ecx
mov ecx, dword ptr [0x601D90]
]])
asmpatch(0x48BCC8, [[
mov eax, dword ptr [0x60157C]
mov dword ptr [0xBB305C], eax
mov eax, dword ptr [0x601D90]
]])

-- ecx - player ptr
MO.GetMainCondDebuff = asmproc([[
push esi
push edi
push ebx
mov esi, ecx
xor edi, edi
@loop:
mov ebx, dword ptr [edi*4 + 0x4FDFA8]
mov eax, dword ptr [esi + ebx*8]
or eax, dword ptr [esi + ebx*8 + 4]
;test eax, eax
jnz @end
cmp ebx, 0xD
je @next
cmp ebx, 0xE
je @next
cmp ebx, 0x10
je @next
mov edx, ebx
mov ecx, esi
call absolute ]] .. MO.GetPlayerDebuffPtr .. [[;
mov ecx, eax
call absolute 0x42D70E
test eax, eax
jnz @end
@next:
inc edi
cmp edi, 0x14
jl @loop
mov ebx, edi
@end:
mov eax, ebx
pop ebx
pop edi
pop esi
retn
]])

-- ecx - player ptr, edx - spell, arg0 - source
--   Source:
--     1 - player spell book
--     2 - quick spell
--     3 - extra quick spells
--     4 - spell scroll
MO.CanPlayerCastSpell = asmproc([[
push ebx
mov ebx, dword ptr [esp + 8]
push esi
push edi
mov esi, ecx
mov edi, edx
push 0x12
pop edx
call absolute ]] .. MO.CheckConditionDebuff .. [[;
nop
nop
nop
nop
nop
pop edi
pop esi
pop ebx
retn 4
]])

hook(MO.CanPlayerCastSpell + 0x13, function(d)
	local t = {PlayerPtr = d.esi, Spell = d.edi, Check = d.eax,
		Source = d.ebx, Result = (d.eax == 0) and true or false}
	if t.Source == 4 and t.Result == false then
		t.Result = MF.SettingEqNum(MM.FeeblemindedDisableScrolls, 0)
	end
	events.call("CanPlayerCastSpell", t)
	d.eax = t.Result and 1 or 0
end)

-- Feebleminded condition/debuff
--   Quick Spell key pressed
asmpatch(0x42E846, [[
movzx ebx, byte ptr [edi + 0x1C45]
test ebx, ebx
jz absolute 0x42E923
mov ecx, edi
mov edx, ebx
push 2
call absolute ]] .. MO.CanPlayerCastSpell .. [[;
test eax, eax
jz absolute 0x42E923
]])
--   Action 142 (Cast Spell)
asmpatch(0x4320B7, [[
jz absolute 0x43036D
mov ecx, 0xB20E90
push dword ptr [esp + 0x20]
call absolute 0x4026F4
mov ecx, eax
mov edx, dword ptr [esp + 0x10]
push 1
call absolute ]] .. MO.CanPlayerCastSpell .. [[;
test eax, eax
jz absolute 0x43036D
]])
--   Action 146 (Use SpellScroll)
asmpatch(0x4320C9, [[
jz absolute 0x43036D
mov ecx, 0xB20E90
push dword ptr [esp + 0x20]
call absolute 0x4026F4
mov ecx, eax
mov edx, dword ptr [esp + 0x10]
push 4
call absolute ]] .. MO.CanPlayerCastSpell .. [[;
test eax, eax
jz absolute 0x43036D
]])

-- Unarmed condition/debuff
--   zero phys damage to monster (like Mistform buff)
asmpatch(0x437260, [[
push eax
mov ecx, eax
mov edx, 0x13
call absolute ]] .. MO.CheckConditionDebuff .. [[;
test eax, eax
pop eax
jg absolute 0x437268
cmp dword [eax + 0x1BD4], ebx
]])

-- Get main condition stat modifier
if MF.SettingGtNum(MM.AllConditionsModifiers, 0) then
	-- Use minimal stat modifier of all current conditions
	asmpatch(0x48E14E, [[
	push esi
	push edi
	mov esi, ecx
	mov edi, dword ptr [esp + 0xC]
	push ebx
	imul edi, 0x13
	add edi, 0x4FDFF8
	mov ebx, 0x64
	xor ecx, ecx
	@loop:
	mov eax, dword ptr [esi+ecx*8]
	or eax, dword ptr [esi+ecx*8+4]
	test eax, eax
	jnz @f1
	; check debuff
	mov edx, ecx
	push ecx
	mov ecx, esi
	call absolute ]] .. MO.GetPlayerDebuffPtr .. [[;
	mov ecx, eax
	call absolute 0x42D70E
	pop ecx
	test eax, eax
	jz @next
	@f1:
	movzx eax, byte ptr [edi+ecx]
	cmp eax, 0x64
	je @next
	jl @lower
	cmp ebx, 0x64
	je @set
	@lower:
	cmp ebx, eax
	jle @next
	@set:
	mov ebx, eax
	@next:
	inc ecx
	cmp ecx, 0x12
	jl @loop
	mov eax, ebx
	pop ebx
	pop edi
	pop esi
	retn 4
	]])
else
	-- Apply main condition modifiers only
	asmpatch(0x48E14E, [[
	call absolute 0x48E127
	cmp eax, 0x12
	jbe @end
	mov eax, 0x12
	@end:
	]])
end
--
asmpatch(0x48E13B, "cmp edx, 0x14")
asmpatch(0x48E140, "push 0x14")

asmpatch(0x44775E, "cmp edi, 0x14")
asmpatch(0x48FB8D, "cmp eax, 0x14")
asmpatch(0x4B57C5, "cmp eax, 0x14")

-- Check condition and debuff for face expressions
asmpatch(0x48FB88, "call absolute " .. MO.GetMainCondDebuff)

-- Face expressions for Feebleminded and Unarmed
asmpatch(0x48FBF1, [[
jbe @end
cmp eax, 0x12
jne @f1
mov eax, 0x1A
jmp @f2
@f1:
cmp eax, 0x13
jne @f3
mov eax, 0x1C
@f2:
mov word ptr [esi + 0x1C86], ax
@f3:
jmp absolute 0x48FE3D
@end:
]])

-- Clear party SpellBuffs2 and expired Debuffs after the rest
asmpatch(0x48FEA4, [[
mov ebx, ]] .. (MC.PartyBuffs2Count + MC.PartyDebuffsCount) .. [[;
test ebx, ebx
jz @end
mov esi, ]] .. MO.PartyBuffs2 .. [[;
@loop:
mov ecx, esi
call absolute 0x455E3C
add esi, 0x10
dec ebx
jnz @loop
@end:
call absolute ]] .. MO.ClearExpiredPartyDebuffs .. [[;
mov esi, 0xB21738
]])
-- Clear all 26 player buffs after the rest (rather than 20)
if MF.SettingGtNum(MM.ClearAllBuffsAfterRest, 0) then
	asmpatch(0x48FEDE, "push 0x1B")
end
-- Clear player SpellBuffs2 and expired Debuffs after the rest
asmpatch(0x48FEF6, [[
call absolute ]] .. MO.GetPlayerExtraPtr .. [[;
add eax, ]] .. MC.PlayerBuffs2Offset .. [[;
mov edi, eax
mov ebp, ]] .. MC.PlayerBuffs2Count .. [[;
test ebp, ebp
jz @end
@loop:
mov ecx, edi
call absolute 0x455E3C
add edi, 0x10
dec ebp
jnz @loop
@end:
mov ecx, esi
call absolute ]] .. MO.ClearExpiredPlayerDebuffs .. [[;
mov ecx, esi
call absolute 0x48F9B2
]])
-- Clear conditions 18-19, debuffs 1-4,18-19
asmpatch(0x48FF25, [[
mov ebp, 4
@loop1:
mov ecx, esi
mov edx, ebp
call absolute ]] .. MO.GetPlayerDebuffPtr .. [[;
mov ecx, eax
call absolute 0x455E3C
dec ebp
jnz @loop1
mov ebp, 2
@loop2:
mov ecx, esi
mov edx, ebp
add edx, 0x11
call absolute ]] .. MO.GetPlayerDebuffPtr .. [[;
mov ecx, eax
call absolute 0x455E3C
dec ebp
jnz @loop2
mov ecx, esi
mov dword ptr [esi + 0x90], ebx
mov dword ptr [esi + 0x94], ebx
mov dword ptr [esi + 0x98], ebx
mov dword ptr [esi + 0x9C], ebx
mov dword ptr [esi + 0x68], ebx
]])

-- Clear everything _after_ the rest
asmpatch(0x41EB33, [[
mov ecx, 0xB20E90
call absolute 0x48FE9C
mov eax, dword ptr [0x51E330]
]])
-- Don't clear everything before the rest
-- TODO: clear buffs still?
mem.nop(0x431B07, 5)

-- Clear expired player SpellBuffs2 and debuffs
asmpatch(0x49292B, [[
mov ecx, esi
call absolute ]] .. MO.ClearExpiredPlayerBuffs2Debuffs .. [[;
lea edi, [esi+0x1A34]
]])
-- Clear expired party SpellBuffs2 and debuffs
asmpatch(0x49299E, [[
call absolute ]] .. MO.ClearExpiredPartyBuffs2Debuffs .. [[;
test eax, eax
jz @end
xor eax, eax
inc eax
mov dword ptr [0x587ADC], eax ; Game.NeedRedraw
@end:
mov esi, 0xB21738
]])

-- Draw player SpellBuffs/Debuffs
MO.PlayerBuffsSort = StaticAlloc(MC.PlayerBuffsCount * 2)
MO.PlayerDebuffsSort = StaticAlloc(MC.PlayerDebuffsCount * 2)
MO.PlayerBuffs2Names = StaticAlloc(MC.PlayerBuffs2Count * 4)
MO.PlayerDebuffsNames = StaticAlloc(MC.PlayerDebuffsCount * 4)
MO.PlayerBuffs2Colors = StaticAlloc(MC.PlayerBuffs2Count * 3)
MO.PlayerDebuffsColors = StaticAlloc(MC.PlayerDebuffsCount * 3)
for i = 0, MC.PlayerBuffsCount - 1 do
	mem.u2[MO.PlayerBuffsSort + i * 2] = i
end
for i = 0, MC.PlayerDebuffsCount - 1 do
	mem.u2[MO.PlayerDebuffsSort + i * 2] = i
end
--   count SpellBuffs2 and Debuffs
asmpatch(0x41C85B, [[
push edx
mov edx, 0x1B
mov ecx, ebx
call absolute ]] .. MO.GetPlayerBuffPtr .. [[;
pop edx
mov ecx, ]] .. MC.PlayerBuffs2Count .. [[;
@loop:
cmp dword ptr [eax + 4], esi
jl @end
jg @buff
cmp dword ptr [eax], esi
jbe @end
@buff:
inc edx
@end:
add eax, 0x10
dec ecx
jg @loop
push edx
xor edx, edx
mov ecx, ebx
call absolute ]] .. MO.GetPlayerDebuffPtr .. [[;
pop edx
mov ecx, ]] .. MC.PlayerDebuffsCount .. [[;
@loop2:
cmp dword ptr [eax + 4], esi
jl @end2
jg @debuff
cmp dword ptr [eax], esi
jbe @end2
@debuff:
inc edx
@end2:
add eax, 0x10
dec ecx
jg @loop2
mov ecx, dword ptr [0x5DB918]
]])
--   reduce inter-line space
asmpatch(0x41C86D, [[
movzx ecx, byte ptr [ecx + 5]
sub ecx, 5
dec edx
]])
asmpatch(0x41CB97, [[
sub esi, 5
mov eax, dword ptr [ebp + 0xC]
imul esi, eax
add esi, dword ptr [ebp + 8]
xor eax, eax
]])
--   preserve player ptr (ebx)
asmpatch(0x41CB03, "mov al, byte ptr [ebx + 0x1C45]")
asmpatch(0x41CB0C, "test al, al")
asmpatch(0x41CB10, "movzx eax, al")
--   debuffs
asmpatch(0x41CB5A, [[
mov dword ptr [ebp + 8], esi
mov dword ptr [ebp - 4], esi
]], 0x41CB60 - 0x41CB5A)
asmpatch(0x41CB60, [[
@loop:
mov edx, dword ptr [ebp - 4]
movzx edx, word ptr [edx * 2 + ]] .. MO.PlayerDebuffsSort .. [[]
mov ecx, ebx
call absolute ]] .. MO.GetPlayerDebuffPtr .. [[;
mov ecx, dword ptr [eax + 4]
cmp ecx, esi
jl @end
jg @debuff
mov edx, dword ptr [eax]
cmp edx, esi
jbe @end
@debuff:
sub edx, dword ptr [0xB20EBC]
sbb ecx, dword ptr [0xB20EC0]
mov dword ptr [ebp - 0x10], edx
mov dword ptr [ebp - 0xC], ecx
xor eax, eax
push eax
push eax
push eax

mov edx, dword ptr [ebp - 4]
mov eax, dword ptr [edx * 4 + ]] .. MO.PlayerDebuffsNames .. [[]
push eax

lea edx, [edx + edx * 2 + ]] .. (MO.PlayerDebuffsColors + 1) .. [[]
movzx ecx, byte ptr [edx - 1]
movzx eax, byte ptr [edx + 1]
movzx edx, byte ptr [edx]
push eax
call absolute 0x40F247
push eax

mov eax, dword ptr [ebp - 8]
movzx eax, byte ptr [eax + 5]
sub eax, 5
imul eax, dword ptr [ebp + 8]
add eax, 0x80
mov esi, eax
push eax
push 0x34
mov edx, dword ptr [ebp - 8]
lea ecx, [ebp - 0x64]
call absolute 0x44A50F
push dword ptr [ebp - 8]
push dword ptr [ebp - 0xC]
push dword ptr [ebp - 0x10]
lea edx, [ebp - 0x64]
mov ecx, esi
call absolute 0x41C5F1

inc dword ptr [ebp + 8]
xor esi, esi
@end:
inc dword ptr [ebp - 4]
cmp dword ptr [ebp - 4], ]] .. MC.PlayerDebuffsCount .. [[;
jl @loop
mov edx, dword ptr [ebp + 8]
test edx, edx
mov eax, dword ptr [0x6016AC] ; "None"
jz @none
mov eax, dword ptr [ebp - 8]
movzx eax, byte ptr [eax + 5]
sub eax, 5
imul eax, edx
mov dword ptr [ebp + 8], eax
mov eax, 0x517B40
@none:
add dword ptr [ebp + 8], 0x10
push eax
push dword ptr [0x601D34] ; "Debuffs"
push 0x4F3C88 ; "%s: %s"
push edi
call absolute 0x4D9F10
add esp, 0x10
mov edx, dword ptr [0x5DB918]
push esi
push esi
push esi
push edi
push esi
push 0x70
push 0xE
lea ecx, [ebp - 0x64]
call absolute 0x44A50F
]])
--   buffs1/2
asmpatch(0x41CB65, [[
mov dword ptr [ebp + 0xC], esi
xor edx, edx
]], 0x41CB6C - 0x41CB65)
asmpatch(0x41CB6F, [[
mov edx, dword ptr [ebp - 4]
movzx edx, word ptr [edx * 2 + ]] .. MO.PlayerBuffsSort .. [[]
mov ecx, ebx
call absolute ]] .. MO.GetPlayerBuffPtr .. [[;
mov edx, eax
mov ecx, dword ptr [edx + 4]
cmp ecx, esi
]])
asmpatch(0x41CB7E, [[
mov edx, dword ptr [ebp - 4]
cmp edx, 0x1A
jg @extra
lea edx, [edx + edx * 2 + 0x4F39D9]
jmp @end
@extra:
lea edx, [edx + edx * 2 + ]] .. (MO.PlayerBuffs2Colors - 80) .. [[]
@end:
sub eax, dword ptr [0xB20EBC]
]], 0x41CB87 - 0x41CB7E)
asmpatch(0x41CBA0, [[
mov eax, dword ptr [ebp - 4]
cmp eax, 0x1A
jg @extra
mov eax, dword ptr [eax * 4 + 0x517F70]
jmp @end
@extra:
sub eax, 0x1B
mov eax, dword ptr [eax * 4 + ]] .. MO.PlayerBuffs2Names .. [[]
@end:
push eax
movzx eax, byte ptr [edx + 1]
mov dword ptr [ebp - 0xC], ecx
movzx ecx, byte ptr [edx - 1]
movzx edx, byte ptr [edx]
]], 0x41CBB0 - 0x41CBA0)
asmpatch(0x41CBE6, [[
inc dword ptr [ebp - 4]
cmp dword ptr [ebp - 4], ]] .. MC.PlayerBuffsCount,
0x41CBFA - 0x41CBE6)
asmpatch(0x41CC17, [[
call absolute 0x4D9F10
mov eax, dword ptr [ebp + 8]
add eax, 0x72
]])
asmpatch(0x41CC2A, "push eax")

-- Draw party SpellBuffs/Debuffs
MO.PartyBuffsSort = StaticAlloc(MC.PartyBuffsCount * 2)
MO.PartyDebuffsSort = StaticAlloc(MC.PartyDebuffsCount * 2)
MO.PartyBuffs2Names = StaticAlloc(MC.PartyBuffs2Count * 4)
MO.PartyDebuffsNames = StaticAlloc(MC.PartyDebuffsCount * 4)
MO.PartyBuffs2Colors = StaticAlloc(MC.PartyBuffs2Count * 3)
MO.PartyDebuffsColors = StaticAlloc(MC.PartyDebuffsCount * 3)
for i = 0, MC.PartyBuffsCount - 1 do
	mem.u2[MO.PartyBuffsSort + i * 2] = i
end
for i = 0, MC.PartyDebuffsCount - 1 do
	mem.u2[MO.PartyDebuffsSort + i * 2] = i
end
--   count SpellBuffs2 and Debuffs
asmpatch(0x41CC56, [[
mov eax, ]] .. MO.PartyDebuffs .. [[;
xor edx, edx
@loop:
cmp dword ptr [eax + 4], ebx
jl @end
jg @buff
cmp dword ptr [eax], ebx
jbe @end
@buff:
inc edx
@end:
add eax, 0x10
cmp eax, ]] .. (MO.PartyDebuffs + MC.PartyDebuffsCount * 0x10) .. [[;
jl @loop
mov dword ptr [ebp - 8], edx
test edx, edx
jg @f1
inc edx
@f1:
mov dword ptr [ebp - 0x10], edx
mov eax, ]] .. MO.PartyBuffs2 .. [[;
xor edx, edx
@loop2:
cmp dword ptr [eax + 4], ebx
jl @end2
jg @debuff
cmp dword ptr [eax], ebx
jbe @end2
@debuff:
inc edx
@end2:
add eax, 0x10
cmp eax, ]] .. MO.PartyDebuffs .. [[;
jl @loop2
mov dword ptr [ebp - 4], edx
mov eax, 0xB21738
]])
--    window size
asmpatch(0x41CC7C, [[
mov edx, dword ptr [ebp - 4]
test edx, edx
jg @f1
inc edx
@f1:
add edx, dword ptr [ebp - 0x10]
sal eax, 1
add eax, 0x28
]])
--   (also fix wrong font's size used in calculation)
asmpatch(0x41CC85, [[
movzx ecx, byte ptr [edi+5]
sub ecx, 5
]], 0x41CC90 - 0x41CC85)
--   debuffs
asmpatch(0x41CCE6, [[
mov edx, dword ptr [0x5DB918]
mov ecx, esi
push 3
push dword ptr [0x601D34] ; "Debuffs"
push ebx
push 0xC
push ebx
call absolute 0x44AAE3
cmp dword ptr [ebp - 8], ebx
jg @debuffs
push 3
push dword ptr [0x6016AC] ; "None"
mov edx, edi
push ebx
push 0x20
push ebx
mov ecx, esi
call absolute 0x44AAE3
jmp @end
@debuffs:
push dword ptr [ebp - 0x10]
mov dword ptr [ebp - 8], ebx
mov dword ptr [ebp - 0x10], ebx
@loop:
mov ecx, dword ptr [ebp - 8]
movzx ecx, word ptr [ecx * 2 + ]] .. MO.PartyDebuffsSort .. [[]
mov edi, ecx
call absolute ]] .. MO.GetPartyDebuffPtr .. [[;
mov ecx, eax
mov eax, dword ptr [ecx]
mov edx, dword ptr [ecx+4]
test edx, edx
jl @next
jg @dbf
test eax, eax
jbe @next

@dbf:
sub eax, dword ptr [0xB20EBC]
sbb edx, dword ptr [0xB20EC0]
mov dword ptr [ebp - 0x18], eax
mov dword ptr [ebp - 0x14], edx
xor eax, eax
push eax
push eax
push eax
mov eax, dword ptr [edi * 4 + ]] .. MO.PartyDebuffsNames .. [[]
push eax
mov edx, edi
lea edx, [edx + edx * 2 + ]] .. (MO.PartyDebuffsColors + 1) .. [[]
movzx ecx, byte ptr [edx-1]
movzx eax, byte ptr [edx+1]
movzx edx, byte ptr [edx]
push eax
call absolute 0x40F247
push eax
mov edx, dword ptr [ebp - 0xC]
movzx edi, byte ptr [edx+5]
sub edi, 5
imul edi, dword ptr [ebp - 0x10]
add edi, 0x20
push edi
push 0x34
mov ecx, esi
call absolute 0x44A50F

push dword ptr [ebp - 0xC]
push dword ptr [ebp - 0x14]
push dword ptr [ebp - 0x18]
mov edx, esi
mov ecx, edi
call absolute 0x41C5F1

inc dword ptr [ebp - 0x10]
@next:
inc dword ptr [ebp - 8]
cmp dword ptr [ebp - 8], ]] .. MC.PartyDebuffsCount .. [[;
jl @loop
pop dword ptr [ebp - 0x10]
@end:
mov edx, dword ptr [0x5DB918]
]])
--   buffs1/2
asmpatch(0x41CCF4, [[
push ebx
mov edi, dword ptr [ebp - 0xC]
movzx eax, byte ptr [edi+5]
sub eax, 5
mov ecx, dword ptr [ebp - 0x10]
imul eax, ecx
add eax, 0x28
push eax
mov ecx, esi
]])
asmpatch(0x41CD0C, [[
push ebx
mov edi, dword ptr [ebp - 0xC]
movzx eax, byte ptr [edi+5]
sub eax, 5
mov edx, dword ptr [ebp - 0x10]
imul eax, edx
add eax, 0x3C
push eax
mov edx, edi
]])

asmpatch(0x41CD19, [[
mov eax, dword ptr [ebp - 0x10]
mov dword ptr [ebp - 4], eax
mov dword ptr [ebp - 8], ebx
]], 0x41CD35 - 0x41CD19)

asmpatch(0x41CD38, [[
movzx ecx, word ptr [ecx * 2 + ]] .. MO.PartyBuffsSort .. [[]
cmp ecx, 20
jge @buffs2
lea eax, [ecx * 4 + 0x517F20]
lea edx, [ecx * 2 + ecx + 0x4F3A2D]
jmp @f1
@buffs2:
mov eax, ecx
sub eax, 20
lea edx, [eax * 2 + eax + ]] .. (MO.PartyBuffs2Colors + 1) .. [[]
lea eax, [eax * 4 + ]] .. MO.PartyBuffs2Names .. [[]
@f1:
mov dword ptr [ebp - 0x10], eax
mov ebx, edx
call absolute ]] .. MO.GetPartyBuffPtr .. [[;
mov ecx, eax
mov eax, dword ptr [ecx]
mov ecx, dword ptr [ecx+4]
test ecx, ecx
]])

asmpatch(0x41CD57, [[
sub edi, 5
imul edi, dword ptr [ebp - 4]
add edi, 0x14
movzx edx, byte ptr [ebx]
]])

asmpatch(0x41CDA5, [[
inc dword ptr [ebp - 8]
cmp dword ptr [ebp - 8], ]] .. MC.PartyBuffsCount .. [[;
]], 0x41CDB7 - 0x41CDA5)

local function SetBuffs2DebuffsNames()
	mem.u4[MO.PlayerBuffs2Names + 0 * 4] = mem_cstring(string.format("%s", "Spirit Resistance"))
	mem.u4[MO.PlayerBuffs2Names + 1 * 4] = mem_cstring(string.format("%s", "Light Resistance"))
	mem.u4[MO.PlayerBuffs2Names + 2 * 4] = mem_cstring(string.format("%s", "Dark Resistance"))
	mem.u4[MO.PlayerBuffs2Names + 3 * 4] = mem.u4[0x601448 + 461 * 4]
	mem.u4[MO.PlayerBuffs2Names + 4 * 4] = mem_cstring(string.format("%s", "Restore Health"))
	mem.u4[MO.PlayerBuffs2Names + 5 * 4] = mem_cstring(string.format("%s", "Restore Mana"))

	mem.u4[MO.PlayerBuffs2Colors + 0 * 3] = tonumber('D3D3D3',16)
	mem.u4[MO.PlayerBuffs2Colors + 1 * 3] = tonumber('FAFAFA',16)
	mem.u4[MO.PlayerBuffs2Colors + 2 * 3] = tonumber('0A0A0A',16)
	mem.u4[MO.PlayerBuffs2Colors + 4 * 3] = tonumber('6666FF',16)
	mem.u4[MO.PlayerBuffs2Colors + 5 * 3] = tonumber('FF6666',16)

	mem.u4[MO.PlayerDebuffsNames + 0 * 4] = mem_cstring(string.format("%s", "Curse"					))	--mem.u4[0x601448 + 52 * 4] -- Cursed
	mem.u4[MO.PlayerDebuffsNames + 1 * 4] = mem_cstring(string.format("%s", "Weakness"				))	--mem.u4[0x601448 + 241 * 4] -- Weak
	mem.u4[MO.PlayerDebuffsNames + 2 * 4] = mem_cstring(string.format("%s", "Sleep"					))	--mem.u4[0x601448 + 14 * 4] -- Asleep
	mem.u4[MO.PlayerDebuffsNames + 3 * 4] = mem_cstring(string.format("%s", "Fear"					))	--mem.u4[0x601448 + 4 * 4] -- Afraid
	mem.u4[MO.PlayerDebuffsNames + 4 * 4] = mem_cstring(string.format("%s", "Drunkedness"			))	--mem.u4[0x601448 + 69 * 4] -- Drunk
	mem.u4[MO.PlayerDebuffsNames + 5 * 4] = mem_cstring(string.format("%s", "Insanity"				))	--mem.u4[0x601448 + 117 * 4] -- Insane
	mem.u4[MO.PlayerDebuffsNames + 6 * 4] = mem_cstring(string.format("%s", "Poisoning (light)" 	))	--mem.u4[0x601448 + 166 * 4] -- Poison
	mem.u4[MO.PlayerDebuffsNames + 7 * 4] = mem_cstring(string.format("%s", "Disease (light)"   	))	--mem.u4[0x601448 + 65 * 4] -- Diseased
	mem.u4[MO.PlayerDebuffsNames + 8 * 4] = mem_cstring(string.format("%s", "Poisoning (moderate)"	))	--mem.u4[0x601448 + 166 * 4] -- Poison
	mem.u4[MO.PlayerDebuffsNames + 9 * 4] = mem_cstring(string.format("%s", "Disease (moderate)"  	))	--mem.u4[0x601448 + 65 * 4] -- Diseased
	mem.u4[MO.PlayerDebuffsNames + 10 * 4] = mem_cstring(string.format("%s", "Poisoning (severe)"	)) 	--mem.u4[0x601448 + 166 * 4] -- Poison
	mem.u4[MO.PlayerDebuffsNames + 11 * 4] = mem_cstring(string.format("%s", "Disease (severe)"    	)) 	--mem.u4[0x601448 + 65 * 4] -- Diseased
	mem.u4[MO.PlayerDebuffsNames + 12 * 4] = mem_cstring(string.format("%s", "Paralysis"			))	--mem.u4[0x601448 + 162 * 4] -- Paralyzed
	mem.u4[MO.PlayerDebuffsNames + 13 * 4] = mem_cstring(string.format("%s", "Faint" 				))	--mem.u4[0x601448 + 593 * 4] -- Slowed
	mem.u4[MO.PlayerDebuffsNames + 14 * 4] = mem_cstring(string.format("%s", "Death Decay" 			))
	mem.u4[MO.PlayerDebuffsNames + 15 * 4] = mem_cstring(string.format("%s", "Stoned" 				))	--mem.u4[0x601448 + 220 * 4] -- Stoned
	mem.u4[MO.PlayerDebuffsNames + 16 * 4] = mem_cstring(string.format("%s", "Desintegration" 		))
	mem.u4[MO.PlayerDebuffsNames + 17 * 4] = mem_cstring(string.format("%s", "Morbid Transformation"))  --mem.u4[0x601448 + 601 * 4] -- Zombie
	mem.u4[MO.PlayerDebuffsNames + 18 * 4] = mem_cstring(string.format("%s", "Feeblemind"			))	--mem.u4[0x601448 + 594 * 4] -- Feebleminded
	mem.u4[MO.PlayerDebuffsNames + 19 * 4] = mem_cstring(string.format("%s", "Unarmed"				))	--mem.u4[0x601448 + 77 * 4] -- Unarmed
	
	mem.u4[MO.PlayerDebuffsColors + 0 * 3] 	= tonumber('AA0055',16)
	mem.u4[MO.PlayerDebuffsColors + 1 * 3] 	= tonumber('00AA88',16)
	mem.u4[MO.PlayerDebuffsColors + 2 * 3] 	= tonumber('FF7722',16)
	mem.u4[MO.PlayerDebuffsColors + 3 * 3] 	= tonumber('0088AA',16)
	mem.u4[MO.PlayerDebuffsColors + 4 * 3] 	= tonumber('00DD11',16)
	mem.u4[MO.PlayerDebuffsColors + 5 * 3] 	= tonumber('00FFFF',16)
	mem.u4[MO.PlayerDebuffsColors + 6 * 3] 	= tonumber('22CC22',16)
	mem.u4[MO.PlayerDebuffsColors + 7 * 3] 	= tonumber('2255AA',16)
	mem.u4[MO.PlayerDebuffsColors + 8 * 3] 	= tonumber('22CC22',16)
	mem.u4[MO.PlayerDebuffsColors + 9 * 3]  = tonumber('2255AA',16)
	mem.u4[MO.PlayerDebuffsColors + 10 * 3] = tonumber('22CC22',16)
	mem.u4[MO.PlayerDebuffsColors + 11 * 3] = tonumber('2255AA',16)
	mem.u4[MO.PlayerDebuffsColors + 12 * 3] = tonumber('FFCCAA',16)
	mem.u4[MO.PlayerDebuffsColors + 13 * 3] = tonumber('CCCCCC',16)
	mem.u4[MO.PlayerDebuffsColors + 14 * 3] = tonumber('666666',16)
	mem.u4[MO.PlayerDebuffsColors + 15 * 3] = tonumber('337799',16)
	mem.u4[MO.PlayerDebuffsColors + 16 * 3] = tonumber('0000FF',16)
	mem.u4[MO.PlayerDebuffsColors + 17 * 3] = tonumber('717919',16)
	mem.u4[MO.PlayerDebuffsColors + 18 * 3] = tonumber('00DDFF',16)
	mem.u4[MO.PlayerDebuffsColors + 19 * 3] = tonumber('СССССС',16)

	mem.u4[MO.PartyDebuffsNames + 0 * 4] = mem.u4[0x601448 + 593 * 4] -- Slowed
end

function events.GameInitialized1()
	MF.LogVerbose("%s: GameInitialized1", LogId)
	SetBuffs2DebuffsNames()
end

MF.LogInit2(LogId)        	
