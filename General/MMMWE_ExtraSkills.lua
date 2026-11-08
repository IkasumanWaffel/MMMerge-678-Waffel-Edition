--[[
	MMMWE_ExtraSkills.lua — skills beyond the game's 39 (07.11.26)

	New skills get ids from 41 up (39 and 40 are MMPatch's Club and Misc item skills):
	  41 Dual-Wield   in the Weapons list
	  42 Robe         in the Armor list
	The character record holds only 39 skills, so the values of the new ones live in a block
	of their own (8 per character, by roster index), kept in the save game
	(vars.MMMWE_ExtraSkills). Values are coded as the old ones (level + mastery bits,
	SplitSkill / JoinSkill).

	The game reads a skill as [player + 0x378 + id*2]; the places the new skills reach go
	through SkillPtr instead (id < 39: the old place, else the block):
	  the Skills screen (the four lists' lines and the weapons and armor buttons),
	  raising a skill with skill points and its message, GetSkill, the skill popup.
	The skill names and the five description tables are moved to longer copies (49 entries)
	and the code that indexes them by skill id is pointed there.

	Class caps of the new skills: MF.ClassSkillCap(class, skill) (RacialSkills.lua and
	RemoveClassLimits.lua ask it for ids above 38); the table is EXTRA.Caps.

	Functions:
	  MF.GetExtraSkill(pl, id)          the value (level + mastery bits)
	  MF.SetExtraSkill(pl, id, value)
	  MF.SkillValue(pl, id)             any skill's base value (old or new)
	  MF.ClassSkillCap(class, id)       the class's mastery cap (0..4)
	  MF.ExtraSkills                    the settings below
--]]

local MF = Merge.Functions
local u1, u2, u4, i4 = mem.u1, mem.u2, mem.u4, mem.i4
local floor = math.floor

local EXTRA = {
	First     = 41,     -- the first id of the new skills
	Slots     = 8,      -- ids 41..48
	TableSize = 49,     -- the length of the moved name and description tables
	Skills = {
		DualWield = 41,
		Robe      = 42,
	},
	-- the Skills screen list each new skill goes to
	Lists = {
		[41] = "WeaponSkills",
		[42] = "ArmorSkills",
	},
	Names = {
		[41] = "Dual-Wield",
		[42] = "Robe",
	},
	Descriptions = {
		[41] = "Fighting with a weapon in each hand. Any weapon in the off hand needs this skill (the Blaster skill still rules a second blaster pistol). With a weapon in each hand the skill adds to Attack: -10 plus 1 per point of skill. Below Master the off hand hits weaker and the attacks are slower; a Master wields two weapons as one would a single weapon; a Grand Master can hold a two-handed weapon in each hand.",
		[42] = "The art of fighting and casting in robes and plain clothes instead of armor. Works while no body armor is worn (and in robes, when there are robes).",
	},
	Normal = {
		[41] = "Weapons of any kind in the off hand. Off-hand damage halved, recovery +20%",
		[42] = "+1 AC per 2 skill points",
	},
	Expert = {
		[41] = "Off-hand damage 75%, recovery +10%",
		[42] = "Spell recovery 1% faster per skill point",
	},
	Master = {
		[41] = "No penalties",
		[42] = "Spells cost 10% less SP",
	},
	GM = {
		[41] = "A two-handed weapon may be held in each hand; two of them: off-hand damage 75%, recovery +20%",
		[42] = "+1 to all magic resistances per skill point",
	},
	-- class caps by class kind (Class Extra.txt "Kind"): the second promotion's; the base
	-- class gets at most Expert and the first promotion at most Master (StepCap)
	KindCaps = {
		--            Dual-Wield  Robe
		[1]  = {[41] = 3, [42] = 3},   -- Archer (Dark Elf)
		[2]  = {[41] = 2, [42] = 4},   -- Cleric
		[3]  = {[41] = 4, [42] = 2},   -- Deerslayer
		[4]  = {[41] = 3, [42] = 0},   -- Dragon
		[5]  = {[41] = 1, [42] = 4},   -- Druid
		[6]  = {[41] = 4, [42] = 0},   -- Knight
		[7]  = {[41] = 4, [42] = 0},   -- Minotaur
		[8]  = {[41] = 2, [42] = 3},   -- Monk
		[9]  = {[41] = 3, [42] = 2},   -- Paladin
		[10] = {[41] = 4, [42] = 2},   -- Ranger
		[11] = {[41] = 4, [42] = 0},   -- Thief
		[12] = {[41] = 4, [42] = 0},   -- Barbarian
		[13] = {[41] = 3, [42] = 3},   -- Vampire
		[14] = {[41] = 1, [42] = 4},   -- Sorcerer, Necromancer
		[15] = {[41] = 3, [42] = 3},   -- Technician
		[16] = {[41] = 2, [42] = 2},   -- Peasant
	},
	StepCap = {[0] = 2, 3, 4},
	-- custom classes (MMMWE_CustomClasses.lua) until their editor has the new skills
	CustomCap = 2,
	Caps = {},          -- [class] = {[id] = mastery}: overrides
	DefaultCap = 0,
}
MF.ExtraSkills = EXTRA
-- (not added to const.Skills: scripts that go through const.Skills expect ids below 39)

local PA = Party.PlayersArray
local PA_BASE, PA_SIZE, PA_COUNT = PA["?ptr"], PA[0]["?size"], PA.count

-- the block: PA_COUNT characters x Slots words, and a dummy word for anything out of range
local Store = mem.StaticAlloc(PA_COUNT * EXTRA.Slots * 2 + 4)
local Dummy = Store + PA_COUNT * EXTRA.Slots * 2
mem.fill(Store, PA_COUNT * EXTRA.Slots * 2 + 4, 0)

local function slotPtr(roster, id)
	local s = id - EXTRA.First
	if roster < 0 or roster >= PA_COUNT or s < 0 or s >= EXTRA.Slots then return end
	return Store + (roster * EXTRA.Slots + s) * 2
end

local function rosterOf(pl)
	local i = (pl["?ptr"] - PA_BASE) / PA_SIZE
	if i >= 0 and i == floor(i) and i < PA_COUNT then return i end
end

function MF.GetExtraSkill(pl, id)
	local r = rosterOf(pl)
	local p = r and slotPtr(r, id)
	return p and u2[p] or 0
end

function MF.SetExtraSkill(pl, id, value)
	local r = rosterOf(pl)
	local p = r and slotPtr(r, id)
	if p then u2[p] = value end
end

function MF.SkillValue(pl, id)
	if id < 39 then return pl.Skills[id] end
	return MF.GetExtraSkill(pl, id)
end

function MF.ClassSkillCap(class, id)
	if id < 39 then return Game.Classes.Skills[class][id] end
	local c = EXTRA.Caps[class]
	if c and c[id] then return c[id] end
	local ce = Game.ClassesExtra and Game.ClassesExtra[class]
	if not ce then return EXTRA.DefaultCap end
	if MF.CustomClassOf and MF.CustomClassOf(class) then return EXTRA.CustomCap end
	local k = EXTRA.KindCaps[ce.Kind]
	local cap = k and k[id] or EXTRA.DefaultCap
	return math.min(cap, EXTRA.StepCap[ce.Step or 0] or cap)
end

---------------------------------------------------------------------------
-- SkillPtr: ecx - player, edx - skill id; returns eax - the address of the skill's word.
-- Keeps every other register.
---------------------------------------------------------------------------

local SkillPtr = mem.asmproc([[
	cmp edx, 39
	jae @extra
	lea eax, [ecx+edx*2+0x378]
	retn
@extra:
	push ebx
	push ecx
	push edx
	mov ebx, edx
	sub ebx, ]] .. EXTRA.First .. [[;
	cmp ebx, ]] .. EXTRA.Slots .. [[;
	jae @dummy
	mov eax, ecx
	sub eax, ]] .. PA_BASE .. [[;
	jb @dummy
	xor edx, edx
	mov ecx, ]] .. PA_SIZE .. [[;
	div ecx
	cmp eax, ]] .. PA_COUNT .. [[;
	jae @dummy
	imul eax, eax, ]] .. EXTRA.Slots .. [[;
	add eax, ebx
	lea eax, [eax*2+]] .. Store .. [[]
	jmp @done
@dummy:
	mov eax, ]] .. Dummy .. [[;
	mov word [eax], 0
@done:
	pop edx
	pop ecx
	pop ebx
	retn
]])
MF.ExtraSkillPtrProc = SkillPtr

local MaxSkillVal = "0xFF"   -- as RemoveSkillValueLimits.lua

-- the Skills screen: the line of a skill in each of the four lists (edi - player, edx - id)
for _, p in ipairs{0x418D82, 0x419125, 0x4194CF, 0x419872} do
	mem.asmpatch(p, [[
	push eax
	push ecx
	mov ecx, edi
	call absolute ]] .. SkillPtr .. [[;
	movzx edx, word [eax]
	pop ecx
	pop eax
	]], 8)
end

-- the Skills screen buttons of the weapons and armor lists: is the skill learned?
-- (edx - player, ecx - id; RemoveSkillValueLimits.lua's test, through SkillPtr)
for _, p in ipairs{0x419E59, 0x419F25} do
	mem.asmpatch(p, [[
	push eax
	push ecx
	push edx
	mov eax, ecx
	mov ecx, edx
	mov edx, eax
	call absolute ]] .. SkillPtr .. [[;
	test word [eax], ]] .. MaxSkillVal .. [[;
	pop edx
	pop ecx
	pop eax
	]])
end

-- raising a skill with skill points (ecx - player, eax - id): the word raised, then its cost
mem.asmpatch(0x43233F, [[
	push ecx
	push edx
	mov edx, eax
	call absolute ]] .. SkillPtr .. [[;
	mov esi, eax
	pop edx
	pop ecx
	]], 7)
mem.asmpatch(0x43236B, [[
	push edx
	push ecx
	mov edx, eax
	call absolute ]] .. SkillPtr .. [[;
	movzx eax, byte [eax]
	pop ecx
	pop edx
	]], 8)
-- its message (edi - player, eax - id); the flags of the "cmp" before are kept for the jump after
for _, p in ipairs{0x4C9E69, 0x4C9EB1} do
	mem.asmpatch(p, [[
	pushfd
	push ecx
	push edx
	mov ecx, edi
	mov edx, eax
	call absolute ]] .. SkillPtr .. [[;
	movzx eax, byte [eax]
	pop edx
	pop ecx
	popfd
	]], 8)
end

-- learning a skill in a house: "has the character this skill?" (cmp word [player+id*2+0x378], reg)
-- in the learn lists of the houses, two passes each
local REG = {eax = true, ecx = true, edx = true}
local function patchSkillCmp(p, base, idx, reg)
	if mem.u1[p] ~= 0x66 or mem.u1[p + 1] ~= 0x39 then
		MF.LogWarning("ExtraSkills: unexpected code at 0x%X, the learn check not patched", p)
		return
	end
	-- the compared register's value: from the saved copy when it's one of the three used here
	local regval = ({ax = "word [esp+8]", cx = "word [esp+4]", dx = "word [esp]"})[reg]
	mem.asmpatch(p, [[
	push eax
	push ecx
	push edx
	push ]] .. base .. [[;
	push ]] .. idx .. [[;
	pop edx
	pop ecx
	call absolute ]] .. SkillPtr .. [[;
	]] .. (regval and ("mov dx, " .. regval .. "\n\tcmp word [eax], dx") or ("cmp word [eax], " .. reg)) .. [[;
	pop edx
	pop ecx
	pop eax
	]], 8)
end
patchSkillCmp(0x4B32FA, "esi", "edi", "ax")
patchSkillCmp(0x4B33F6, "esi", "ebx", "ax")
for _, p in ipairs{0x4B3F70, 0x4B4BBC, 0x4B5919, 0x4B6954, 0x4B7BFA, 0x4B82BE, 0x4B938E} do
	patchSkillCmp(p, "eax", "esi", "bx")
end
for _, p in ipairs{0x4B4065, 0x4B4CB3, 0x4B5A13, 0x4B6A4F, 0x4B7CEF, 0x4B83B3, 0x4B9483} do
	patchSkillCmp(p, "eax", "edi", "bx")
end
-- buying it (edi - player, ebp - the learn topic, 0x24 + id): the word set to 1
mem.asmpatch(0x4BAF79, [[
	push eax
	push ecx
	push edx
	mov ecx, edi
	lea edx, [ebp-0x24]
	call absolute ]] .. SkillPtr .. [[;
	mov ebp, eax
	pop edx
	pop ecx
	pop eax
	]], 7)

-- the learn lists: the new skills' topics (0x24 + id), added to the houses' lists
-- (HousesTweaks.lua's lists first, else the game's own); at most 5 topics a house
EXTRA.LearnAt = {
	[41] = {[18] = true, [30] = true},               -- Dual-Wield: mercenary guilds, training halls
	[42] = {[5] = true, [6] = true, [7] = true, [8] = true, [9] = true, [10] = true, [11] = true,
		[12] = true, [13] = true, [14] = true, [15] = true, [23] = true},   -- Robe: magic guilds, temples
}
local GAME_LEARN = {   -- the game's own learn topics of the houses HousesTweaks.lua leaves alone
	[12] = {0x37, 0x40}, [13] = {0x38, 0x40}, [14] = {0x30, 0x31, 0x33, 0x32, 0x4A},
	[15] = {0x36, 0x35, 0x34, 0x40}, [30] = {0x47, 0x3F},
}
function events.DrawLearnTopics(t)
	local add = {}
	for id, types in pairs(EXTRA.LearnAt) do
		if types[t.HouseType] then add[#add + 1] = 0x24 + id end
	end
	if #add == 0 then return end
	table.sort(add)
	if t.Handled and #t.NewTopics == 0 then return end   -- not a member of the guild (HousesTweaks.lua)
	if not t.Handled then
		local def = GAME_LEARN[t.HouseType]
		if not def then return end
		for i, v in ipairs(def) do t.NewTopics[i] = v end
		t.Handled = true
	end
	for _, v in ipairs(add) do
		local n = #t.NewTopics
		if n >= 5 then break end
		if not table.find(t.NewTopics, v) then t.NewTopics[n + 1] = v end
	end
end

-- GetSkill (edi - player, esi - id): the base value
mem.asmpatch(0x48F056, [[
	push ecx
	push edx
	mov ecx, edi
	mov edx, esi
	call absolute ]] .. SkillPtr .. [[;
	movzx eax, word [eax]
	pop edx
	pop ecx
	]], 8)

-- GetPlayerSkillMastery (RemoveSkillValueLimits.lua's; ecx - player, edx - id): its "lea"
if Merge.Offsets.GetPlayerSkillMastery then
	mem.asmpatch(Merge.Offsets.GetPlayerSkillMastery + 3, [[
	call absolute ]] .. SkillPtr .. [[;
	mov ecx, eax
	]], 7)
end

-- the skill popup (esi / edi - player, ebx - id); 0x417295 replaces RemoveSkillValueLimits.lua's
mem.asmpatch(0x417295, [[
	push eax
	push edx
	mov ecx, esi
	mov edx, ebx
	call absolute ]] .. SkillPtr .. [[;
	movzx ecx, word [eax]
	pop edx
	pop eax
	and eax, ]] .. MaxSkillVal .. [[;
	push 0x4F3BB8
	and ecx, ]] .. MaxSkillVal .. [[;
	jmp absolute 0x4172A7
	]])
mem.asmpatch(0x417417, [[
	push eax
	push edx
	mov ecx, edi
	mov edx, ebx
	call absolute ]] .. SkillPtr .. [[;
	mov edi, eax
	pop edx
	pop eax
	xor ecx, ecx
	]], 7)

-- the skill popup's text went into a 1200-byte buffer (0x517FF0), right before the gamma.pcx
-- object (0x5184A0): longer texts (the Legendary line, the new skills) overwrote it and the game
-- crashed on leaving the character screen. Its two users get a buffer of their own.
local PopupBuf = mem.StaticAlloc(8192)
mem.IgnoreProtection(true)
for _, p in ipairs{0x4174BE, 0x41760B} do
	if u1[p] == 0xBE and u4[p + 1] == 0x517FF0 then
		u4[p + 1] = PopupBuf
	else
		MF.LogWarning("ExtraSkills: unexpected code at 0x%X, the popup buffer not moved", p)
	end
end
mem.IgnoreProtection(false)

---------------------------------------------------------------------------
-- the name and description tables, moved to longer copies
---------------------------------------------------------------------------

-- the code that indexes each table by skill id: the addresses of the table's address in it
local TABLES = {
	{"SkillNames", 0xBB3060, {0x416B41, 0x416B8D, 0x417710, 0x418E0A, 0x418E44, 0x4191B7, 0x4191F1,
		0x419557, 0x419591, 0x4198FA, 0x419934, 0x4334A9, 0x433ADA, 0x4B0FDD, 0x4B10F8, 0x4B1108,
		0x4B3307, 0x4B3409, 0x4B3F7D, 0x4B4078, 0x4B4BC9, 0x4B4CC6, 0x4B5926, 0x4B5A26, 0x4B6961,
		0x4B6A62, 0x4B7C07, 0x4B7D02, 0x4B82CB, 0x4B83C6, 0x4B939B, 0x4B9496, 0x4C60A5, 0x4C624F,
		0x4C643D, 0x4C65BC, 0x4C676B, 0x4C6C04, 0x4C6C30, 0x4C6C8E}},
	{"SkillDescriptions", 0x5E4CB0, {0x416B3B, 0x4174BA, 0x41763C, 0x433AD4}},
	{"SkillDesNormal", 0x5E4C10, {0x4174A6, 0x41762E}},
	{"SkillDesExpert", 0x5E4B70, {0x417498, 0x417620}},
	{"SkillDesMaster", 0x5E4AD0, {0x41748A, 0x417612}},
	{"SkillDesGM", 0x5E4A30, {0x41747C, 0x4175F9}},
}
local TEXTS = {SkillNames = EXTRA.Names, SkillDescriptions = EXTRA.Descriptions, SkillDesNormal = EXTRA.Normal,
	SkillDesExpert = EXTRA.Expert, SkillDesMaster = EXTRA.Master, SkillDesGM = EXTRA.GM}

local moved = false
local function moveTables()
	if moved then return end
	moved = true
	local n = EXTRA.TableSize
	mem.IgnoreProtection(true)
	for _, t in ipairs(TABLES) do
		local name, old, refs = t[1], t[2], t[3]
		local cur = Game[name]["?ptr"]
		local new = mem.StaticAlloc(n * 4)
		mem.fill(new, n * 4, 0)
		mem.copy(new, cur, 39 * 4)
		for _, r in ipairs(refs) do
			r = mem.MovedCode and mem.MovedCode[r] or r
			if u4[r] == old then
				u4[r] = new
			else
				MF.LogWarning("ExtraSkills: %s: unexpected value 0x%X at 0x%X", name, u4[r], r)
			end
		end
		mem.ChangeGameArray(name, new, n)
		-- the empty entries: the new skills' texts, "" for the rest
		for id = 39, n - 1 do
			Game[name][id] = TEXTS[name][id] or ""
		end
	end
	mem.IgnoreProtection(false)
end

---------------------------------------------------------------------------
-- the Skills screen lists
---------------------------------------------------------------------------

local listed = false
local function addToLists()
	if listed then return end
	listed = true
	local DL = Game.DialogLogic
	for id, list in pairs(EXTRA.Lists) do
		local a = DL[list]
		local n = a.count
		a.Resize(n + 1)
		DL[list][n] = id
	end
end

function events.GameInitialized2()
	moveTables()
	addToLists()
end

---------------------------------------------------------------------------
-- the save game
---------------------------------------------------------------------------

local function clearAll()
	mem.fill(Store, PA_COUNT * EXTRA.Slots * 2 + 4, 0)
end

local function toVars()
	local t = {}
	for r = 0, PA_COUNT - 1 do
		for s = 0, EXTRA.Slots - 1 do
			local v = u2[Store + (r * EXTRA.Slots + s) * 2]
			if v ~= 0 then
				t[r] = t[r] or {}
				t[r][EXTRA.First + s] = v
			end
		end
	end
	vars.MMMWE_ExtraSkills = t
end

local function fromVars()
	clearAll()
	for r, skills in pairs(vars.MMMWE_ExtraSkills or {}) do
		for id, v in pairs(skills) do
			local p = slotPtr(r, id)
			if p then u2[p] = v end
		end
	end
end

function events.BeforeSaveGame() toVars() end
function events.BeforeNewGameAutosave() toVars() end
function events.InternalBeforeLoadMap(WasInGame)
	if not WasInGame then fromVars() end
end
function events.NewGame() clearAll() end

-- a roster slot that gets a new character (MF.PlayerAttrsClear, 20_PlayersAttrs.lua)
function events.ScriptsLoaded()
	local clear = MF.PlayerAttrsClear
	if clear then
		MF.PlayerAttrsClear = function(roster, ...)
			if roster then
				for s = 0, EXTRA.Slots - 1 do
					u2[Store + (roster * EXTRA.Slots + s) * 2] = 0
				end
			end
			return clear(roster, ...)
		end
	end
end

-- console: give a character a new skill (JoinSkill(level, mastery))
function MF.LearnExtraSkill(pl, id, level, mastery)
	MF.SetExtraSkill(pl, id, JoinSkill(level or 1, mastery or 1))
end
