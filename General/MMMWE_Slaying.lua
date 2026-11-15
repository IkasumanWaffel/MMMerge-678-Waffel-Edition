--[[
	MMMWE_Slaying.lua — the "Slaying" enchantments, double damage against a kind of monster (15.11.26)

	The game checked the slaying enchantments inside its weapon damage (CalcMeleeDamage
	0x48C759 for each hand, CalcRangedDamage 0x48CB07 for the bow), and only four of them:
	Undead, Ogre, Dragon (the main hand only) and Elemental, and only in an item's own
	enchantment. Demon, Elf, Goblin, Dwarf and Human Slaying did nothing, nor did the slaying
	bonuses of the artifacts (Gibbet, Ghoulsbane, Justice, Old Nick, Elfbane, Conan ...).

	Now the three checks are made here, the same for the main hand, the off hand and the bow:
	the weapon's dice damage is doubled (MUL) if any slaying bonus of the weapon fits the
	target - its enchantment (item.Bonus2), its artifact bonuses (ItemSpcBonuses of
	Global/ExtraArtifacts.lua) or its own (EXTRA below). One doubling, however many fit.
	The kinds are those of Game.IsMonsterOfKind: the Monster Kinds table and the Type and
	ExtraType columns of "Bolster - monsters.txt".

	A temporary slaying enchantment (the Slaying potion) is seen too: MMMWE_ConcurrentEnchantments
	puts it into Bonus2 for the duration of the damage calls.
--]]

local MF = Merge.Functions
local MK = const.MonsterKind
local u4, i4 = mem.u4, mem.i4

local MUL = 2

-- special bonus (SPCITEMS number) -> monster kind
local SLAY = {
	[39] = MK.Ogre,       -- of Ogre Slaying
	[40] = MK.Dragon,     -- of Dragon Slaying
	[63] = MK.Elemental,  -- of Elemental Slaying
	[64] = MK.Undead,     -- of Undead Slaying
	[74] = MK.Demon,      -- of Demon Slaying
	[75] = MK.Elf,        -- of Elf Slaying
	[76] = MK.Goblin,     -- of Goblin Slaying
	[77] = MK.Dwarf,      -- of Dwarf Slaying
	[78] = MK.Human,      -- of Human Slaying
}
MF.SlayingKinds = SLAY

-- items that slay by themselves (the game's own: Judicious Measure, Wyrm Spitter; the dragon
-- hunters' weapons whose descriptions say so)
local EXTRA = {
	[503] = {39},   -- Judicious Measure
	[506] = {40},   -- Wyrm Spitter
	[539] = {40},   -- Ebonest
	[540] = {40},   -- Sword of Whistlebone
}

local function isKind(monId, kind)
	return kind and Game.IsMonsterOfKind(monId, kind) ~= 0
end

-- true if the item (its record at ptr) slays the monster (its MONSTERS.TXT id)
local function slays(ptr, monId)
	if not ptr or ptr == 0 or not monId or monId <= 0 then return false end
	local num, b2 = i4[ptr], i4[ptr + 0xC]
	if isKind(monId, SLAY[b2]) then return true end
	local lists = {EXTRA[num], MF.ArtifactSpcBonuses and MF.ArtifactSpcBonuses[num]}
	for _, l in ipairs(lists) do
		for _, b in ipairs(l or {}) do
			if isKind(monId, SLAY[b]) then return true end
		end
	end
	return false
end
MF.ItemSlaysMonster = function(item, monId)
	return slays(item and item["?ptr"], monId)
end

-- one check site of the game: the item pointer, the damage register, where to go on
local function site(addr, itemReg, dmgReg, continue)
	-- the site begins with "mov eax, [reg + 0xC]; cmp eax, 0x40" (6 bytes)
	if u4[addr] ~= 0x830C478B and u4[addr] ~= 0x830C458B then
		MF.LogWarning("[Slaying] unexpected code at 0x%X, the game's own check stays", addr)
		return
	end
	mem.autohook(addr, function(d)
		local ok, res = pcall(slays, d[itemReg], d.ecx)
		if ok and res then
			d[dmgReg] = d[dmgReg] * MUL
		elseif not ok then
			MF.LogWarning("[Slaying] %s", tostring(res))
		end
		d:push(continue)
		return true
	end, 6)
end

site(0x48C810, "ebp", "esi", 0x48C868)   -- CalcMeleeDamage, main hand
site(0x48C92A, "ebp", "ebx", 0x48C971)   -- CalcMeleeDamage, off hand
site(0x48CB80, "edi", "esi", 0x48CBCC)   -- CalcRangedDamage, the bow
