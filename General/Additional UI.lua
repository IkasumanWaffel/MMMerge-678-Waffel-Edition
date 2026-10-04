local LogId = "Additional UI"
local MF = Merge.Functions
MF.LogInit1(LogId)
local MO = Merge.Offsets

local asmpatch = MF.Asmpatch

------------------------------------------
-- Fixes

-- unify basebar ptr
mem.asmpatch(0x4c7662, "push 0x4f4388")
mem.asmpatch(0x4c7edc, "push 0x4f4388")

local UISetsParams = mem.StaticAlloc(104)
-- 0 - show blank stat icon
-- 1 - selring on top
-- 2 - align/reserved
-- 3 - align/reserved
-- 4-7 - stat icon Y
-- 8-11 - X offset
-- 12-15 - selring Y
-- 16-19 - X offset
-- 20-23 - spelico Y
-- 24-27 - spelico X offset towards portrait
-- 28-31 - portraits Y
-- 32-35 - manafrm Y
-- 36-39 - manafrm X offset
-- 40-43 - hp/sp bars Y
-- 44-47 - character interface buttons Y
-- 48-51 - armory Y1
-- 52-55 - armory Y2
-- 56-59 - magic shop X1
-- 60-63 - magic shop X increment
-- 64-67 - magic shop Y1
-- 68-71 - magic shop Y2
-- 72-75 - alchemist X1
-- 76-79 - alchemist X increment
-- 80-83 - alchemist Y1
-- 84-87 - alchemist Y2
-- 88-91 - magic guild X1
-- 92-95 - magic guild X increment
-- 96-99 - magic guild Y1
-- 100-103 - magic guild Y2

MO.UISetsParams = UISetsParams

-- Hostile indicator position

mem.asmpatch(0x4c8046, [[
call absolute 0x491514
test eax, eax
jnz @end

cmp byte [ds:]] .. UISetsParams .. [[], 1
je @equ
jmp @end

@equ:
mov eax, dword [ds:0x519118]
jmp absolute 0x4c807a

@end:
]])

mem.asmpatch(0x4c804f, [[
mov eax, dword [ds:0x519118]
cmp word [ds:edi+0x1bf2], 0
je absolute 0x4c8059

cmp byte [ds:]] .. UISetsParams .. [[], 1
je absolute 0x4c807a
jmp absolute 0x4c80ab
]])

mem.nop(0x4c8057, 2)

mem.asmpatch(0x4c8098, [[
push dword [ds:]] .. UISetsParams + 4 ..[[]
add eax, dword[ds:]] .. UISetsParams + 8 ..[[];]])

mem.asmpatch(0x4c80ea, [[
push dword [ds:]] .. UISetsParams + 4 ..[[]
add eax, dword[ds:]] .. UISetsParams + 8 ..[[];]])

mem.u2[UISetsParams + 4] = 0x1ca

-- Keep showing status icon, despite current phase in turn-based mode.
mem.asmpatch(0x4c7fcd, [[

; If status indicator behaivor overriden:
	mov eax, dword [ds:0x509C9C]
	cmp byte [ds:]] .. UISetsParams .. [[], 1
	jne @default

	; fetch blank status icon pointer.
	mov eax, dword [ds:0x519118]
	mov edx, eax
	inc edx
	neg edx
	sbb edx, edx
	lea eax, dword [ds:eax+eax*8]
	lea eax, dword [ds:0x70D624+eax*8]
	and edx, eax
	push edx

	; setup counter
	xor ecx, ecx
	push ecx

@loop:
	movsx eax, word [ds:ecx*2+0x4FD9D0]
	add eax, dword[ds:]] .. UISetsParams + 8 ..[[]
	sub eax, 8

	; show status icon for each character
	push 0
	push edx
	push dword [ds:]] .. UISetsParams + 4 ..[[]
	push eax
	mov ecx, 0xec1980
	call absolute 0x4A419B

	pop ecx
	pop edx
	inc ecx
	push edx
	push ecx
	cmp ecx, dword [ds:0xB7CA60]
	jl @loop

	pop eax
	pop eax

@default:
	cmp dword [ds:0x509C9C], 0x1
	je absolute 0x4c7fd3

@end:
]])

-- selring position

mem.asmpatch(0x4c7a28, [[
cmp byte [ds:]] .. UISetsParams + 1 .. [[], 0;
je @end
call absolute 0x4c7fbb
@end:
mov ecx, dword [ds:0x519350]
]])

mem.asmpatch(0x4C7A39, [[
movsx eax, word ptr [eax * 2 + 0x4FD9D0]
add eax, dword ptr [ds:]] .. (UISetsParams + 16) .. [[]
mov dword ptr [ss:ebp - 4], eax
]], 0x4C7A72 - 0x4C7A39)

mem.asmpatch(0x4c7ac1, [[
cmp byte [ds:]] .. UISetsParams + 1 .. [[], 0;
jnz @end
call absolute 0x4c7fbb
@end:
]])

mem.asmpatch(0x4c7ab0, "push dword [ds:" .. UISetsParams + 12 .. "]")

mem.u4[UISetsParams + 12] = 0x185

-- ib_spelico position and transparency
mem.i4[UISetsParams + 20] = 0x1D0
mem.i4[UISetsParams + 24] = 0x30

mem.asmpatch(0x4C7B64, [[
push 0
push ecx
push dword ptr [ds:]] .. (UISetsParams + 20) .. [[]
add eax, dword ptr [ds:]] .. (UISetsParams + 24) .. [[]
]], 0x4C7B6D - 0x4C7B64)
mem.asmpatch(0x4C7B70, "call absolute 0x4A419B")

-- portraits
mem.i4[UISetsParams + 28] = 389

mem.asmpatch(0x490C23, "mov edi, dword ptr [ds:" .. (UISetsParams + 28) .. "]")
--   default x positions
mem.i2[0x4FD9D0 + 0 * 2] = 19 -- 20	-- 19
mem.i2[0x4FD9D0 + 1 * 2] = 118 -- 116	-- 118
mem.i2[0x4FD9D0 + 2 * 2] = 213 -- 212	-- 213
mem.i2[0x4FD9D0 + 3 * 2] = 308	-- 308
mem.i2[0x4FD9D0 + 4 * 2] = 405 -- 404	-- 405

-- FIXME: spellbuffs
mem.asmpatch(0x4A7650, "mov dword ptr [ebp - 4], 0")
mem.asmpatch(0x4A76B4, [[
push dword ptr []] .. (UISetsParams + 28) .. [[]
mov eax, dword ptr [ebp - 4]
movzx eax, word ptr [eax * 2 + 0x4FD9D0]
push eax
]], 0x4A76BC - 0x4A76B4)
mem.asmpatch(0x4A76DD, [[
inc dword ptr [ebp - 4]
mov eax, dword ptr [0xB7CA60]
cmp eax, dword ptr [ebp - 4]
jg absolute 0x4A7657
]])

-- manafrm
mem.i4[UISetsParams + 32] = 429
mem.i4[UISetsParams + 36] = 64
mem.asmpatch(0x4C7B95, [[
movsx eax, word ptr [eax * 2 + 0x4FD9D0]
add eax, dword ptr [ds:]] .. (UISetsParams + 36) .. [[]
mov dword ptr [ss:ebp - 4], eax
]], 0x4C7BCE - 0x4C7B95)
mem.asmpatch(0x4C7BEA, "push dword ptr [ds:" .. (UISetsParams + 32) .. "]")

-- hp/sp bars
mem.i4[UISetsParams + 40] = 430
mem.asmpatch(0x41AFF0, "mov edi, dword ptr [ds:" .. (UISetsParams + 40) .. "]")
--   default x positions
mem.i4[0x4F39AC + 0 * 4] = 19 + 64
mem.i4[0x4F39AC + 1 * 4] = 118 + 64
mem.i4[0x4F39AC + 2 * 4] = 213 + 64
mem.i4[0x4F39AC + 3 * 4] = 308 + 64
mem.i4[0x4F39AC + 4 * 4] = 405 + 64

mem.i4[0x4F39C0 + 0 * 4] = 19 + 68
mem.i4[0x4F39C0 + 1 * 4] = 118 + 68
mem.i4[0x4F39C0 + 2 * 4] = 213 + 68
mem.i4[0x4F39C0 + 3 * 4] = 308 + 68
mem.i4[0x4F39C0 + 4 * 4] = 405 + 68

-- character interface buttons
mem.i4[UISetsParams + 44] = 340
mem.asmpatch(0x4C982D, [[
mov ebx, dword ptr [ds:]] .. (UISetsParams + 44) .. [[]
mov dword ptr [ebp-0x14], ebx
xor ebx, ebx
]])
mem.asmpatch(0x4C98A9, [[
mov ebx, dword ptr [ds:]] .. (UISetsParams + 44) .. [[]
mov dword ptr [ebp-0x14], ebx
xor ebx, ebx
]])
mem.asmpatch(0x4C9925, [[
mov ebx, dword ptr [ds:]] .. (UISetsParams + 44) .. [[]
mov dword ptr [ebp-0x14], ebx
xor ebx, ebx
]])
mem.asmpatch(0x4C99A1, [[
mov ebx, dword ptr [ds:]] .. (UISetsParams + 44) .. [[]
mov dword ptr [ebp-0x14], ebx
xor ebx, ebx
]])
mem.asmpatch(0x4C9A12, [[
mov ebx, dword ptr [ds:]] .. (UISetsParams + 44) .. [[]
mov dword ptr [ebp-0x14], ebx
xor ebx, ebx
]])

-- Armory
mem.i4[UISetsParams + 48] = 121
mem.i4[UISetsParams + 52] = 166
asmpatch(0x4B95BA, [[
mov edi, dword ptr []] .. (UISetsParams + 48) .. [[]
sub edi, edx
]])
asmpatch(0x4B9610, [[
push dword ptr []] .. (UISetsParams + 52) .. [[]
]])
asmpatch(0x4B968C, [[
mov edi, dword ptr []] .. (UISetsParams + 48) .. [[]
sub edi, edx
]])
asmpatch(0x4B96DA, [[
push dword ptr []] .. (UISetsParams + 52) .. [[]
]])

-- Magic Shop
mem.i4[UISetsParams + 56] = 40
mem.i4[UISetsParams + 60] = 75
mem.i4[UISetsParams + 64] = 206
mem.i4[UISetsParams + 68] = 352
asmpatch(0x4B41A9, "mov esi, dword ptr [" .. (UISetsParams + 64) .. "]")
asmpatch(0x4B41BB, [[
imul edi, dword ptr []] .. (UISetsParams + 60) .. [[]
cdq
sub eax, edx
]])
asmpatch(0x4B41C3, [[
sub edi, eax
add edi, dword ptr []] .. (UISetsParams + 56) .. [[]
]])

asmpatch(0x4B4262, [[
imul esi, dword ptr []] .. (UISetsParams + 60) .. [[]
movsx eax, word ptr [ecx + 0x1A]
]])
asmpatch(0x4B4269, "mov edi, dword ptr [" .. (UISetsParams + 68) .. "]")
asmpatch(0x4B4279, [[
sub esi, eax
add esi, dword ptr []] .. (UISetsParams + 56) .. [[]
]])

asmpatch(0x4B4316, "mov esi, dword ptr [" .. (UISetsParams + 64) .. "]")
asmpatch(0x4B4328, [[
imul edi, dword ptr []] .. (UISetsParams + 60) .. [[]
cdq
sub eax, edx
]])
asmpatch(0x4B4330, [[
sub edi, eax
add edi, dword ptr []] .. (UISetsParams + 56) .. [[]
]])

asmpatch(0x4B43D3, "mov esi, dword ptr [" .. (UISetsParams + 68) .. "]")
asmpatch(0x4B43E8, [[
imul edi, dword ptr []] .. (UISetsParams + 60) .. [[]
cdq
sub eax, edx
]])
asmpatch(0x4B43F0, [[
sub edi, eax
add edi, dword ptr []] .. (UISetsParams + 56) .. [[]
]])

-- Alchemist
mem.i4[UISetsParams + 72] = 40
mem.i4[UISetsParams + 76] = 75
mem.i4[UISetsParams + 80] = 206
mem.i4[UISetsParams + 84] = 352
asmpatch(0x4B8872, "mov esi, dword ptr [" .. (UISetsParams + 80) .. "]")
asmpatch(0x4B8887, [[
imul edi, dword ptr []] .. (UISetsParams + 76) .. [[]
cdq
sub eax, edx
]])
asmpatch(0x4B888F, [[
sub edi, eax
add edi, dword ptr []] .. (UISetsParams + 72) .. [[]
]])

asmpatch(0x4B892F, "mov esi, dword ptr [" .. (UISetsParams + 84) .. "]")
asmpatch(0x4B8944, [[
imul edi, dword ptr []] .. (UISetsParams + 76) .. [[]
cdq
sub eax, edx
]])
asmpatch(0x4B894C, [[
sub edi, eax
add edi, dword ptr []] .. (UISetsParams + 72) .. [[]
]])

asmpatch(0x4B89EE, "mov esi, dword ptr [" .. (UISetsParams + 80) .. "]")
asmpatch(0x4B8A03, [[
imul edi, dword ptr []] .. (UISetsParams + 76) .. [[]
cdq
sub eax, edx
]])
asmpatch(0x4B8A0B, [[
sub edi, eax
add edi, dword ptr []] .. (UISetsParams + 72) .. [[]
]])

asmpatch(0x4B8AAB, "mov esi, dword ptr [" .. (UISetsParams + 84) .. "]")
asmpatch(0x4B8AC0, [[
imul edi, dword ptr []] .. (UISetsParams + 76) .. [[]
cdq
sub eax, edx
]])
asmpatch(0x4B8AC8, [[
sub edi, eax
add edi, dword ptr []] .. (UISetsParams + 72) .. [[]
]])

-- Magic Guild
mem.i4[UISetsParams + 88] = 32
mem.i4[UISetsParams + 92] = 70
mem.i4[UISetsParams + 96] = 206
mem.i4[UISetsParams + 100] = 352
asmpatch(0x4B483D, "mov esi, dword ptr [" .. (UISetsParams + 96) .. "]")
asmpatch(0x4B4803, [[
mov eax, dword ptr []] .. (UISetsParams + 88) .. [[]
mov dword ptr [ebp - 0xC], eax
]])
asmpatch(0x4B4881, [[
mov eax, dword ptr []] .. (UISetsParams + 92) .. [[]
add dword ptr [ebp - 0xC], eax
add dword ptr [ebp - 0x10], 0x118
]])
asmpatch(0x4B488D, "cmp edi, 6")

asmpatch(0x4B48A4, [[
mov eax, dword ptr []] .. (UISetsParams + 88) .. [[]
mov dword ptr [ebp - 0xC], eax
]])
asmpatch(0x4B48DE, "mov esi, dword ptr [" .. (UISetsParams + 100) .. "]")
asmpatch(0x4B4922, [[
mov eax, dword ptr []] .. (UISetsParams + 92) .. [[]
add dword ptr [ebp - 0xC], eax
add dword ptr [ebp - 0x10], 0x118
]])
asmpatch(0x4B492E, "cmp edi, 0xC")


------------------------------------------
-- UI sets table

local function ProcessUITable()

	local TxtTable = io.open("Data/Tables/Additional UI.txt", "r")
	if not TxtTable then
		Game.UISets = {}
		return
	end

	local LineIt = TxtTable:lines()
	LineIt() -- skip header

	local Words
	local UISets = {}

	for line in LineIt do
		Words = string.split(line, "\9")

		UISets[#UISets+1] = {
			LodName 			= Words[2] or "default",
			DLodName			= Words[3] or "",
			CharY = tonumber(Words[4]) or 389,
			Char0X = tonumber(Words[5]) or 19,
			Char1X = tonumber(Words[6]) or 118,
			Char2X = tonumber(Words[7]) or 213,
			Char3X = tonumber(Words[8]) or 308,
			Char4X = tonumber(Words[9]) or 405,
			ShowBlankIndicator 	= string.lower(Words[10]) == "x",
			IndicatorY 			= tonumber(Words[11]) or 458,
			IndicatorXOffset	= tonumber(Words[12]) or 0,
			SelringOnTop		= string.lower(Words[13]) == "x",
			SelringY			= tonumber(Words[14]) or 389,
			SelringXOffset		= tonumber(Words[15]) or 0,
			SpelicoY = tonumber(Words[16]) or 464,
			SpelicoXOffset = tonumber(Words[17]) or 48,
			ManafrmY = tonumber(Words[18]) or 429,
			ManafrmXOffset = tonumber(Words[19]) or 64,
			HPSPBarY = tonumber(Words[20]) or 430,
			HPBarXOffset = tonumber(Words[21]) or 65,
			SPBarXOffset = tonumber(Words[22]) or 69,
			CharBtnY = tonumber(Words[23]) or 340,
			ArmoryX1 = tonumber(Words[24]) or 114,
			ArmoryX2 = tonumber(Words[25]) or 206,
			ArmoryX3 = tonumber(Words[26]) or 296,
			ArmoryX4 = tonumber(Words[27]) or 377,
			ArmoryY1 = tonumber(Words[28]) or 121,
			ArmoryY2 = tonumber(Words[29]) or 166,
			MagicShopX1 = tonumber(Words[30]) or 40,
			MagicShopXInc = tonumber(Words[31]) or 75,
			MagicShopY1 = tonumber(Words[32]) or 206,
			MagicShopY2 = tonumber(Words[33]) or 352,
			AlchemistX1 = tonumber(Words[34]) or 40,
			AlchemistXInc = tonumber(Words[35]) or 75,
			AlchemistY1 = tonumber(Words[36]) or 206,
			AlchemistY2 = tonumber(Words[37]) or 352,
			MagicGuildX1 = tonumber(Words[38]) or 32,
			MagicGuildXInc = tonumber(Words[39]) or 70,
			MagicGuildY1 = tonumber(Words[40]) or 206,
			MagicGuildY2 = tonumber(Words[41]) or 352,

			}
	end

	io.close(TxtTable)

	Game.UISets = UISets

end

------------------------------------------
-- Base functions

local InterfaceIcons = {
"ARMORY","asiL00","asiL01","asiL02","asiL03","asiL04","asiL05","asiL06","asiL07","asiL08","asiL09","asiL10","asiR00","asiR05","asiR06","backhand","bardata","Basebar","but20D","but20H","but20U","but21D","but21H","but21U","but22D",
"but22H","but22U","but23D","but23H","but23U","but24D","but24H","but24U","but25D","but25H","but25U","but26D","but26H","but26U","butn1d","butn1u","butn2d","butn2u","butn3d","butn3u","butn4d","butn4u","cornr_LL",
"cornr_LR","cornr_UL","cornr_UR","c_close_DN","c_close_ht","c_close_up","c_ok_dn","c_ok_ht","c_ok_up","DIVBAR","edge_btm","edge_lf","edge_rt","edge_top","endcap","evt","evtnpc","FACEMASK","fr_award","fr_inven",
"fr_skill","fr_stats","GENSHELF","ia02-001","ia02-002","ia02-003","ia02-004","ia02-005","ia02-006","ia02-007","ia02-008","ia02-009","ia02-010","IB-8pxbar","Ib-Mb-A","IBshield01","IBshield02","IBshield03","IBshield04",
"IB_spelico","IRB-1","IRB-2","IRB-3","IRB-4","IRBgrnd","IRT01b","IRT01r","IRT02b","IRT02r","IRT03b","IRT03r","IRT04b","IRT04r","IRT05b","IRT05r","IRT06b","IRT06r","IRT07b","IRT07r","IRT08b","IRT08r","IRT09b","IRT09r",
"IRT10b","IRT10r","leather","MAGSHELF","manaB","manaFRM","ManaG","manar","manaY","map+dn","map+ht","map+up","map-dn","map-ht","map-up","mapframe","parchment","QUIKREF","R1hD","R1hH","R1hU","R5mD","R5mH","R5mU","R8hD",
"R8hH","R8hU","RdawnD","RdawnH","RdawnU","restmain","RexitD","RexitH","RexitU","rost_bg","scoreBG","selring","sp21a10","sp21a20","sp21a30","sp21a40","sp21a50","sp21a60","sp21a70","sp21a80","statG","statR","statY", "statbl",
"topbar","topbar2", "UIExample"}

local LoadCustomLod = Game.CustomLods.Load
local FreeCustomLod = Game.CustomLods.Free
local FilesPath = "Data/Additional UI/"
local TmpLods = {}
local ReplaceIcon = CustomUI.ReplaceIcon
local CurrentUI = 1
local CurrentAlignment
local DLODPTR = 0x6f330c

local function LoadLod(p, s)
	local res = LoadCustomLod(p, FilesPath .. s)
	TmpLods[res] = true
	MF.LogInfo("LoadLod: %s, 0x%X", FilesPath .. s, res)
	local lods = FilesPath .. "*." .. s
	for lod in path.find(lods) do
		res = LoadCustomLod(p, lod)
		TmpLods[res] = true
		MF.LogInfo("LoadLod: %s, 0x%X", lod, res)
	end
	if (Game.PatchOptions.UILayout or "") == "" then
		return
	end
	s = FilesPath .. path.setext(s, "."..Game.PatchOptions.UILayout..".lod")
	for s in path.find(s) do
		res = LoadCustomLod(p, s)
		TmpLods[res] = true
		MF.LogInfo("LoadLod: %s, 0x%X", s, res)
	end
end

local function ReloadLayout()
	Game.Dll.UILayoutSetVarInt('Merge.UI', CurrentUI)
end

local function LoadUI(i)
	local Old, New, ref

	New = Game.UISets[i]
	if not New then
		return
	end

	for k in pairs(TmpLods) do
		if k ~= 0 then
			FreeCustomLod(k)
		end
	end
	TmpLods = {}

	local iconslod = New.LodName
	if i == 2 then
		if CurrentAlignment == 1 then
			iconslod = Game.UISets[5].LodName
		elseif CurrentAlignment == -1 then
			iconslod = Game.UISets[6].LodName
		end
	end

	if iconslod ~= "default" then
		LoadLod(Game.IconsLod["?ptr"], iconslod)
	end
	if New.DLodName ~= "" then
		LoadLod(DLODPTR, New.DLodName)
	end

	mem.u1[UISetsParams] 	= New.ShowBlankIndicator and 1 or 0
	mem.u1[UISetsParams+1] 	= New.SelringOnTop and 1 or 0
	mem.u4[UISetsParams+4] 	= New.IndicatorY
	mem.u4[UISetsParams+8] 	= New.IndicatorXOffset
	mem.u4[UISetsParams+12]	= New.SelringY
	mem.u4[UISetsParams+16]	= New.SelringXOffset
	mem.i4[UISetsParams + 20] = New.SpelicoY
	mem.i4[UISetsParams + 24] = New.SpelicoXOffset
	mem.i4[UISetsParams + 28] = New.CharY
	mem.i4[UISetsParams + 32] = New.ManafrmY
	mem.i4[UISetsParams + 36] = New.ManafrmXOffset
	mem.i4[UISetsParams + 40] = New.HPSPBarY
	mem.i4[UISetsParams + 44] = New.CharBtnY
	mem.i4[UISetsParams + 48] = New.ArmoryY1
	mem.i4[UISetsParams + 52] = New.ArmoryY2
	mem.i4[UISetsParams + 56] = New.MagicShopX1
	mem.i4[UISetsParams + 60] = New.MagicShopXInc
	mem.i4[UISetsParams + 64] = New.MagicShopY1
	mem.i4[UISetsParams + 68] = New.MagicShopY2
	mem.i4[UISetsParams + 72] = New.AlchemistX1
	mem.i4[UISetsParams + 76] = New.AlchemistXInc
	mem.i4[UISetsParams + 80] = New.AlchemistY1
	mem.i4[UISetsParams + 84] = New.AlchemistY2
	mem.i4[UISetsParams + 88] = New.MagicGuildX1
	mem.i4[UISetsParams + 92] = New.MagicGuildXInc
	mem.i4[UISetsParams + 96] = New.MagicGuildY1
	mem.i4[UISetsParams + 100] = New.MagicGuildY2

	mem.i2[0x4FD9D0 + 0 * 2] = New.Char0X
	mem.i2[0x4FD9D0 + 1 * 2] = New.Char1X
	mem.i2[0x4FD9D0 + 2 * 2] = New.Char2X
	mem.i2[0x4FD9D0 + 3 * 2] = New.Char3X
	mem.i2[0x4FD9D0 + 4 * 2] = New.Char4X

	mem.i4[0x4F39AC + 0 * 4] = New.Char0X + New.HPBarXOffset - 1
	mem.i4[0x4F39AC + 1 * 4] = New.Char1X + New.HPBarXOffset - 1
	mem.i4[0x4F39AC + 2 * 4] = New.Char2X + New.HPBarXOffset - 1
	mem.i4[0x4F39AC + 3 * 4] = New.Char3X + New.HPBarXOffset - 1
	mem.i4[0x4F39AC + 4 * 4] = New.Char4X + New.HPBarXOffset - 1

	mem.i4[0x4F39C0 + 0 * 4] = New.Char0X + New.SPBarXOffset - 1
	mem.i4[0x4F39C0 + 1 * 4] = New.Char1X + New.SPBarXOffset - 1
	mem.i4[0x4F39C0 + 2 * 4] = New.Char2X + New.SPBarXOffset - 1
	mem.i4[0x4F39C0 + 3 * 4] = New.Char3X + New.SPBarXOffset - 1
	mem.i4[0x4F39C0 + 4 * 4] = New.Char4X + New.SPBarXOffset - 1

	mem.prot(true) -- FIXME: why is it protected?
	mem.i4[0x4E89C4 + 0 * 4] = New.ArmoryX1
	mem.i4[0x4E89C4 + 1 * 4] = New.ArmoryX2
	mem.i4[0x4E89C4 + 2 * 4] = New.ArmoryX3
	mem.i4[0x4E89C4 + 3 * 4] = New.ArmoryX4
	mem.i4[0x4E89C4 + 4 * 4] = New.ArmoryX1
	mem.i4[0x4E89C4 + 5 * 4] = New.ArmoryX2
	mem.i4[0x4E89C4 + 6 * 4] = New.ArmoryX3
	mem.i4[0x4E89C4 + 7 * 4] = New.ArmoryX4
	mem.prot(false)

	for k,v in pairs(InterfaceIcons) do
		ReplaceIcon(v,v)
	end

	CurrentUI = i

	if (Game.PatchOptions.UILayout or "") ~= "" then
		Game.Dll.UILayoutClearCache()
		ReloadLayout()
	end
end
Game.LoadUI = LoadUI

function GetCurrentUI()
	return CurrentUI
end

MF.UISendAlignment = function()
	local alignment = 0
	if Party.QBits[611] then
		alignment = 1
	elseif Party.QBits[612] then
		alignment = -1
	end
	Game.Dll.UILayoutSetVarInt('Game.Alignment', alignment)
	if CurrentAlignment ~= alignment then
		CurrentAlignment = alignment
		if CurrentUI == 2 then
			LoadUI(CurrentUI)
		end
	end
end

------------------------------------------
-- Events

function events.GameInitialized1()
	ProcessUITable()
end

function events.LeaveGame()
	Game.LoadUI(1)
end

function events.BeforeLoadMap(WasInGame)
	MF.UISendAlignment()
end

if (Game.PatchOptions.UILayout or "") ~= "" then
	local cast = require('ffi').cast
	Game.Dll.UILayoutOnLoad(tonumber(cast('int', cast('void (*)()', ReloadLayout))))
end

MF.LogInit2(LogId)

