--[[
	MMMWE_Slaying.lua — the "Slaying" enchantments double the whole hit of their weapon (15.11.26)

	The checks themselves are the Revamp's (General/ItemsModifiers.lua, CalcMeleeDamage
	0x48C810 / 0x48C92A for each hand, CalcRangedDamage 0x48CB80 for the bow): a weapon whose
	enchantment or artifact bonus (event ItemHasBonus2) fits the target's kind gets its dice
	damage doubled. The kinds:
	  39 Ogre, 40 Dragon, 63 Elemental, 64 Undead, 65 Titan (Of David), 74 Demon, 75 Elf,
	  76 Goblin, 77 Dwarf, 78 Human, 79 Sea monsters (of Sea Hunting), 146 Construct (new)
	as Game.IsMonsterOfKind sees them (the Monster Kinds table and the Type and ExtraType
	columns of "Bolster - monsters.txt").

	Added here:
	  * the doubling marks which weapon slew; at the end of CalcMeleeDamage the Might, skill
	    and other bonus damage the game adds to the weapons is doubled too, by the share of
	    the slaying weapon (one hand of two weapons: that hand's share of the bonus); the bow
	    also doubles its Grand Master skill bonus. MUL is the multiplier (the game's own 2)
	  * EXTRA: weapons that slay by their descriptions (Ebonest, Sword of Whistlebone)
--]]

local MF = Merge.Functions
local u1, u2, i4 = mem.u1, mem.u2, mem.i4
local floor = math.floor

local MUL = 2

local EXTRA = {
	[539] = {40},   -- Ebonest: Dragon Slaying
	[540] = {40},   -- Sword of Whistlebone: Dragon Slaying
}

function events.ItemHasBonus2(t)
	local l = EXTRA[t.ItemId]
	if l then
		for _, b in ipairs(l) do
			if b == t.Bonus2 then t.Result = 1 end
		end
	end
end

-- the marks: [F] main hand, [F+1] off hand, [F+2] bow
local F = mem.StaticAlloc(4)
mem.u4[F] = 0

local function findNops(p, len)
	for i = p, p + (len or 64) do
		if u1[i] == 0x90 and u1[i+1] == 0x90 and u1[i+2] == 0x90 and u1[i+3] == 0x90 and u1[i+4] == 0x90 then
			return i
		end
	end
end

local function install()
	-- the doublings of ItemsModifiers jump here: mark the weapon
	mem.asmpatch(0x48C824, string.format([[
	shl esi, 1
	mov byte [%d], 1
	jmp absolute 0x48C868
	]], F), 5)
	mem.asmpatch(0x48C93E, string.format([[
	shl ebx, 1
	mov byte [%d], 1
	jmp absolute 0x48C971
	]], F + 1), 5)
	mem.asmpatch(0x48CB94, string.format([[
	shl esi, 1
	mov byte [%d], 1
	jmp absolute 0x48CBCC
	]], F + 2), 5)

	-- CalcMeleeDamage's end (esi: weapons + bonus, [esp+0x14] / [esp+0x18]: the two hands)
	local p = mem.asmpatch(0x48C9EB, string.format([[
	cmp word [%d], 0
	jz @std
	mov eax, [esp+0x14]
	mov edx, [esp+0x18]
	nop
	nop
	nop
	nop
	nop
	mov word [%d], 0
	@std:
	xor eax, eax
	inc eax
	cmp esi, eax
	]], F, F), 5)
	local h = p and findNops(p)
	if h then
		mem.hook(h, function(d)
			local main, off = u1[F] ~= 0, u1[F + 1] ~= 0
			local a, b = d.eax, d.edx
			local weapons = a + b
			local bonus = d.esi - weapons
			if bonus > 0 and weapons > 0 then
				local share = (main and a or 0) + (off and b or 0)
				d.esi = d.esi + floor(bonus * share / weapons * (MUL - 1))
			end
		end)
	else
		MF.LogWarning("[Slaying] the melee bonus hook wasn't placed")
	end

	-- CalcRangedDamage after the dice (ebx: the player): the Grand Master bow bonus once more
	p = mem.asmpatch(0x48CBCC, string.format([[
	cmp byte [%d], 0
	jz @std
	nop
	nop
	nop
	nop
	nop
	mov byte [%d], 0
	@std:
	add ebx, 0x382
	]], F + 2, F + 2), 6)
	h = p and findNops(p)
	if h then
		mem.hook(h, function(d)
			local pl = MF.GetPlayerFromPtr and MF.GetPlayerFromPtr(d.ebx)
			if not pl then return end
			local s, m = SplitSkill(pl:GetSkill(const.Skills.Bow))
			if m >= 4 then d.esi = d.esi + s * (MUL - 1) end
		end)
	else
		MF.LogWarning("[Slaying] the ranged bonus hook wasn't placed")
	end
end

function events.GameInitialized2()
	local ok, err = pcall(install)
	if not ok then MF.LogWarning("[Slaying] %s", tostring(err)) end
end
