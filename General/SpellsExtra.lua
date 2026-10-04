local LogId = "SpellsExtra"
Log(Merge.Log.Info, "Init started: %s", LogId)
local MF, MM, MO, MT, MV = Merge.Functions, Merge.ModSettings, Merge.Offsets, Merge.Tables, Merge.Vars

local floor, max, min = math.floor, math.max, math.min
local asmpatch, asmproc, hook, nop, nop2 = mem.asmpatch, mem.asmproc, mem.hook, mem.nop, mem.nop2
local i2, i4, u2, u4 = mem.i2, mem.i4, mem.u2, mem.u4
local max_spell = 137
local max_mastery = 4
local spell_dmg_vars_size = 2
local spell_dmg_vars_count = 3
local spell_dmg_vars_offsets = {
	DmgConstNormal = 0,
	DmgConstExpert = 2,
	DmgConstMaster = 4,
	DmgConstGM = 6,
	DmgRndNormal = 8,
	DmgRndExpert = 10,
	DmgRndMaster = 12,
	DmgRndGM = 14,
	DmgAddNormal = 16,
	DmgAddExpert = 18,
	DmgAddMaster = 20,
	DmgAddGM = 22,
}
local spell_dmg_vars_line_size = spell_dmg_vars_count * max_mastery * spell_dmg_vars_size

local function ProcessSpellsExtraTxt()
	local spells_extra_tbl = {}
	local TableFile = "Data/Tables/SpellsExtra.txt"
	local null_tbl = {Mastery = 0, Level = 0}
	local masteries = {B = 1, E = 2, M = 3, G = 4}

	MO.SpellsDmgVars = mem.StaticAlloc(max_spell * spell_dmg_vars_line_size)

	local TxtTable = io.open(TableFile, "r")
	if not TxtTable then
		TxtTable = io.open(TableFile, "w")
		TxtTable:write("#\9Spell\9ChanceBaseNormal\9ChanceFactorNormal\9ChanceMaxNormal\9ChanceCursedNormal")
		TxtTable:write("\9ChanceBaseExpert\9ChanceFactorExpert\9ChanceMaxExpert\9ChanceCursedExpert")
		TxtTable:write("\9ChanceBaseMaster\9ChanceFactorMaster\9ChanceMaxMaster\9ChanceCursedMaster")
		TxtTable:write("\9ChanceBaseGM\9ChanceFactorGM\9ChanceMaxGM\9ChanceCursedGM")
		TxtTable:write("\9ScrollChanceBaseNormal\9ScrollChanceFactorNormal\9ScrollChanceMaxNormal\9ScrollChanceCursedNormal")
		TxtTable:write("\9ScrollChanceBaseExpert\9ScrollChanceFactorExpert\9ScrollChanceMaxExpert\9ScrollChanceCursedExpert")
		TxtTable:write("\9ScrollChanceBaseMaster\9ScrollChanceFactorMaster\9ScrollChanceMaxMaster\9ScrollChanceCursedMaster")
		TxtTable:write("\9ScrollChanceBaseGM\9ScrollChanceFactorGM\9ScrollChanceMaxGM\9ScrollChanceCursedGM")
		TxtTable:write("\9Var1\9Var1Normal\9Var1Expert\9Var1Master\9Var1GM\9Var2\9Var2Normal")
		TxtTable:write("\9Var2Expert\9Var2Master\9Var2GM\n")
		for i = 1, max_spell do
			TxtTable:write(i .. "\9" .. (i > 132 and i or Game.SpellsTxt[i].Name))
			if i < 100 then
				TxtTable:write("\009100\0090\009100\00950\009100\0090\009100\00950\009100\0090\009100\00950\009100\0090\009100\00950")
				TxtTable:write("\009100\0090\009100\00950\009100\0090\009100\00950\009100\0090\009100\00950\009100\0090\009100\00950\n")
			else
				TxtTable:write("\009100\0090\009100\009100\009100\0090\009100\009100\009100\0090\009100\009100\009100\0090\009100\009100")
				TxtTable:write("\009100\0090\009100\009100\009100\0090\009100\009100\009100\0090\009100\009100\009100\0090\009100\009100\n")
			end
			spells_extra_tbl[i] = {
				ChanceBase = {100, 100, 100, 100},
				ChanceFactor = {0, 0, 0, 0},
				ChanceMax = {100, 100, 100, 100},
				ChanceCursed = i < 100 and {50, 50, 50, 50} or {100, 100, 100, 100},
				ScrollChanceBase = {100, 100, 100, 100},
				ScrollChanceFactor = {0, 0, 0, 0},
				ScrollChanceMax = {100, 100, 100, 100},
				ScrollChanceCursed = i < 100 and {50, 50, 50, 50} or {100, 100, 100, 100},
			}
		end
	else
		local iter = TxtTable:lines()
		iter()	-- skip header
		for line in iter do
			local words = string.split(line, "\9")
			if string.len(words[1]) == 0 then
				break
			end
			if tonumber(words[1]) then
				local spell = tonumber(words[1])
				spells_extra_tbl[spell] = {
					ChanceBase = {
						words[3] and tonumber(words[3]),
						words[7] and tonumber(words[7]),
						words[11] and tonumber(words[11]),
						words[15] and tonumber(words[15])
					},
					ChanceFactor = {
						words[4] and tonumber(words[4]),
						words[8] and tonumber(words[8]),
						words[12] and tonumber(words[12]),
						words[16] and tonumber(words[16])
					},
					ChanceMax = {
						words[5] and tonumber(words[5]),
						words[9] and tonumber(words[9]),
						words[13] and tonumber(words[13]),
						words[17] and tonumber(words[17])
					},
					ChanceCursed = {
						words[6] and tonumber(words[6]),
						words[10] and tonumber(words[10]),
						words[14] and tonumber(words[14]),
						words[18] and tonumber(words[18])
					},
					ScrollChanceBase = {
						words[19] and tonumber(words[19]),
						words[23] and tonumber(words[23]),
						words[27] and tonumber(words[27]),
						words[31] and tonumber(words[31])
					},
					ScrollChanceFactor = {
						words[20] and tonumber(words[20]),
						words[24] and tonumber(words[24]),
						words[28] and tonumber(words[28]),
						words[32] and tonumber(words[32])
					},
					ScrollChanceMax = {
						words[21] and tonumber(words[21]),
						words[25] and tonumber(words[25]),
						words[29] and tonumber(words[29]),
						words[33] and tonumber(words[33])
					},
					ScrollChanceCursed = {
						words[22] and tonumber(words[22]),
						words[26] and tonumber(words[26]),
						words[30] and tonumber(words[30]),
						words[34] and tonumber(words[34])
					},
					Var1Normal = words[48] and tonumber(words[48]),
					Var1Expert = words[49] and tonumber(words[49]),
					Var1Master = words[50] and tonumber(words[50]),
					Var1GM = words[51] and tonumber(words[51]),
					Var2Normal = words[53] and tonumber(words[53]),
					Var2Expert = words[54] and tonumber(words[54]),
					Var2Master = words[55] and tonumber(words[55]),
					Var2GM = words[56] and tonumber(words[56]),
					Var3Normal = words[58] and tonumber(words[58]),
					Var3Expert = words[59] and tonumber(words[59]),
					Var3Master = words[60] and tonumber(words[60]),
					Var3GM = words[61] and tonumber(words[61]),
					Var4Normal = words[63] and tonumber(words[63]),
					Var4Expert = words[64] and tonumber(words[64]),
					Var4Master = words[65] and tonumber(words[65]),
					Var4GM = words[66] and tonumber(words[66]),
					Var5Normal = words[68] and tonumber(words[68]),
					Var5Expert = words[69] and tonumber(words[69]),
					Var5Master = words[70] and tonumber(words[70]),
					Var5GM = words[71] and tonumber(words[71]),
					Var6Normal = words[73] and tonumber(words[73]),
					Var6Expert = words[74] and tonumber(words[74]),
					Var6Master = words[75] and tonumber(words[75]),
					Var6GM = words[76] and tonumber(words[76]),
				}
				if spell >= 1 and spell <= max_spell then
					setmetatable(spells_extra_tbl[spell], {
						__index = function(tbl, key)
							if spell_dmg_vars_offsets[key] then
								return u2[MO.SpellsDmgVars + (spell - 1) * spell_dmg_vars_line_size
									+ spell_dmg_vars_offsets[key]]
							end
							--if key == "DmgConstNormal" then
							--	return u2[MO.SpellsDmgVars + (spell - 1) * 3 * 2 * max_mastery]
							--end
						end,
						__newindex = function(tbl, key, value)
							if spell_dmg_vars_offsets[key] then
								if not tonumber(value) then return end
								u2[MO.SpellsDmgVars + (spell - 1) * spell_dmg_vars_line_size
									+ spell_dmg_vars_offsets[key]] = value
							else
								tbl[key] = value
							end
						end
					})
				end
				if spell >= 1 and spell <= max_spell then
					if spell == 10 then
						spells_extra_tbl[spell].DmgConstNormal = words[35] and tonumber(words[35]) or 2
						spells_extra_tbl[spell].DmgConstExpert = words[36] and tonumber(words[36]) or 2
						spells_extra_tbl[spell].DmgConstMaster = words[37] and tonumber(words[37]) or 2
						spells_extra_tbl[spell].DmgConstGM = words[38] and tonumber(words[38]) or 2
					elseif spell == 43 then
						spells_extra_tbl[spell].DmgConstNormal = words[35] and tonumber(words[35]) or 2
						spells_extra_tbl[spell].DmgConstExpert = words[36] and tonumber(words[36]) or 2
						spells_extra_tbl[spell].DmgConstMaster = words[37] and tonumber(words[37]) or 2
						spells_extra_tbl[spell].DmgConstGM = words[38] and tonumber(words[38]) or 2
					elseif spell == 52 then
						spells_extra_tbl[spell].DmgConstNormal = words[35] and tonumber(words[35]) or 1
						spells_extra_tbl[spell].DmgConstExpert = words[36] and tonumber(words[36]) or 1
						spells_extra_tbl[spell].DmgConstMaster = words[37] and tonumber(words[37]) or 1
						spells_extra_tbl[spell].DmgConstGM = words[38] and tonumber(words[38]) or 1
					else
						spells_extra_tbl[spell].DmgConstNormal = words[35] and tonumber(words[35]) or 0
						spells_extra_tbl[spell].DmgConstExpert = words[36] and tonumber(words[36]) or 0
						spells_extra_tbl[spell].DmgConstMaster = words[37] and tonumber(words[37]) or 0
						spells_extra_tbl[spell].DmgConstGM = words[38] and tonumber(words[38]) or 0
					end
					if spell == 7 then
						spells_extra_tbl[spell].DmgRndNormal = words[39] and tonumber(words[39]) or 8
						spells_extra_tbl[spell].DmgRndExpert = words[40] and tonumber(words[40]) or 8
						spells_extra_tbl[spell].DmgRndMaster = words[41] and tonumber(words[41]) or 8
						spells_extra_tbl[spell].DmgRndGM = words[42] and tonumber(words[42]) or 10
					elseif spell == 10 then
						spells_extra_tbl[spell].DmgRndNormal = words[39] and tonumber(words[39]) or 0
						spells_extra_tbl[spell].DmgRndExpert = words[40] and tonumber(words[40]) or 0
						spells_extra_tbl[spell].DmgRndMaster = words[41] and tonumber(words[41]) or 0
						spells_extra_tbl[spell].DmgRndGM = words[42] and tonumber(words[42]) or 0
					elseif spell == 43 then
						spells_extra_tbl[spell].DmgRndNormal = words[39] and tonumber(words[39]) or 0
						spells_extra_tbl[spell].DmgRndExpert = words[40] and tonumber(words[40]) or 0
						spells_extra_tbl[spell].DmgRndMaster = words[41] and tonumber(words[41]) or 0
						spells_extra_tbl[spell].DmgRndGM = words[42] and tonumber(words[42]) or 0
					elseif spell == 52 then
						spells_extra_tbl[spell].DmgRndNormal = words[39] and tonumber(words[39]) or 7
						spells_extra_tbl[spell].DmgRndExpert = words[40] and tonumber(words[40]) or 7
						spells_extra_tbl[spell].DmgRndMaster = words[41] and tonumber(words[41]) or 7
						spells_extra_tbl[spell].DmgRndGM = words[42] and tonumber(words[42]) or 7
					elseif spell == 111 then
						spells_extra_tbl[spell].DmgRndNormal = words[39] and tonumber(words[39]) or 3
						spells_extra_tbl[spell].DmgRndExpert = words[40] and tonumber(words[40]) or 3
						spells_extra_tbl[spell].DmgRndMaster = words[41] and tonumber(words[41]) or 5
						spells_extra_tbl[spell].DmgRndGM = words[42] and tonumber(words[42]) or 7
					elseif spell == 123 then
						spells_extra_tbl[spell].DmgRndNormal = words[39] and tonumber(words[39]) or 10
						spells_extra_tbl[spell].DmgRndExpert = words[40] and tonumber(words[40]) or 10
						spells_extra_tbl[spell].DmgRndMaster = words[41] and tonumber(words[41]) or 11
						spells_extra_tbl[spell].DmgRndGM = words[42] and tonumber(words[42]) or 12
					elseif spell == 136 then
						spells_extra_tbl[spell].DmgRndNormal = words[39] and tonumber(words[39]) or 4
						spells_extra_tbl[spell].DmgRndExpert = words[40] and tonumber(words[40]) or 6
						spells_extra_tbl[spell].DmgRndMaster = words[41] and tonumber(words[41]) or 8
						spells_extra_tbl[spell].DmgRndGM = words[42] and tonumber(words[42]) or 10
					elseif spell < 133 then
						spells_extra_tbl[spell].DmgRndNormal = words[39] and tonumber(words[39])
							or Game.Spells[spell].DamageDiceSides
						spells_extra_tbl[spell].DmgRndExpert = words[40] and tonumber(words[40])
							or Game.Spells[spell].DamageDiceSides
						spells_extra_tbl[spell].DmgRndMaster = words[41] and tonumber(words[41])
							or Game.Spells[spell].DamageDiceSides
						spells_extra_tbl[spell].DmgRndGM = words[42] and tonumber(words[42])
							or Game.Spells[spell].DamageDiceSides
					else
						spells_extra_tbl[spell].DmgRndNormal = words[39] and tonumber(words[39]) or 0
						spells_extra_tbl[spell].DmgRndExpert = words[40] and tonumber(words[40]) or 0
						spells_extra_tbl[spell].DmgRndMaster = words[41] and tonumber(words[41]) or 0
						spells_extra_tbl[spell].DmgRndGM = words[42] and tonumber(words[42]) or 0
					end
					if spell == 44 then
						-- Mass Distortion stored percents there, now they moved away
						spells_extra_tbl[spell].DmgAddNormal = words[43] and tonumber(words[43]) or 0
						spells_extra_tbl[spell].DmgAddExpert = words[44] and tonumber(words[44]) or 0
						spells_extra_tbl[spell].DmgAddMaster = words[45] and tonumber(words[45]) or 0
						spells_extra_tbl[spell].DmgAddGM = words[46] and tonumber(words[46]) or 0
					elseif spell == 111 then
						spells_extra_tbl[spell].DmgAddNormal = words[43] and tonumber(words[43]) or 3
						spells_extra_tbl[spell].DmgAddExpert = words[44] and tonumber(words[44]) or 3
						spells_extra_tbl[spell].DmgAddMaster = words[45] and tonumber(words[45]) or 5
						spells_extra_tbl[spell].DmgAddGM = words[46] and tonumber(words[46]) or 7
					elseif spell == 123 then
						spells_extra_tbl[spell].DmgAddNormal = words[43] and tonumber(words[43]) or 10
						spells_extra_tbl[spell].DmgAddExpert = words[44] and tonumber(words[44]) or 10
						spells_extra_tbl[spell].DmgAddMaster = words[45] and tonumber(words[45]) or 11
						spells_extra_tbl[spell].DmgAddGM = words[46] and tonumber(words[46]) or 12
					elseif spell == 137 then
						spells_extra_tbl[spell].DmgAddNormal = words[43] and tonumber(words[43]) or 10
						spells_extra_tbl[spell].DmgAddExpert = words[44] and tonumber(words[44]) or 10
						spells_extra_tbl[spell].DmgAddMaster = words[45] and tonumber(words[45]) or 10
						spells_extra_tbl[spell].DmgAddGM = words[46] and tonumber(words[46]) or 10
					elseif spell < 133 then
						spells_extra_tbl[spell].DmgAddNormal = words[43] and tonumber(words[43])
							or Game.Spells[spell].DamageAdd
						spells_extra_tbl[spell].DmgAddExpert = words[44] and tonumber(words[44])
							or Game.Spells[spell].DamageAdd
						spells_extra_tbl[spell].DmgAddMaster = words[45] and tonumber(words[45])
							or Game.Spells[spell].DamageAdd
						spells_extra_tbl[spell].DmgAddGM = words[46] and tonumber(words[46])
							or Game.Spells[spell].DamageAdd
					else
						spells_extra_tbl[spell].DmgAddNormal = words[43] and tonumber(words[43]) or 0
						spells_extra_tbl[spell].DmgAddExpert = words[44] and tonumber(words[44]) or 0
						spells_extra_tbl[spell].DmgAddMaster = words[45] and tonumber(words[45]) or 0
						spells_extra_tbl[spell].DmgAddGM = words[46] and tonumber(words[46]) or 0
					end
				end
			end
		end
	end
	io.close(TxtTable)
	MT.SpellsExtra = spells_extra_tbl
end

local function SetSpellsExtraHooks()
	MO.WaterWalk5Mins = mem.StaticAlloc(16) -- 0xB21734?
	MO.SpellKeyMods = MO.WaterWalk5Mins + 1
	MO.LastArmageddonCaster = MO.WaterWalk5Mins + 4
	MO.CalcSpellDamageCaster = MO.WaterWalk5Mins + 8
	MO.SummonType = MO.WaterWalk5Mins + 12
	local spellflags1_ctrl = 0x10
	local spellflags1_special = 0x80

	-- Get Spell SkillId
	MO.GetSpellSkillId = asmproc([[
	xor eax, eax
	dec eax
	cmp ecx, 132
	jle @ff
	cmp ecx, 136
	jne @f1
	mov eax, 21
	jmp @end
	@f1:
	cmp ecx, 137
	jne @end
	mov eax, 23
	jmp @end
	@ff:
	push ecx
	push edx
	mov eax, ecx
	dec eax
	xor edx, edx
	mov ecx, 0xB
	idiv ecx
	add eax, 0xC
	pop edx
	pop ecx
	@end:
	retn
	]])

	-- Spell SP cost and recovery
	-- ecx - spell_id [1-132], edx - skill_mastery, arg0 - caster, arg4 - skill_value (0 SP if non-zero)
	-- returns: eax - SPCost, edx - Recovery
	MO.SpellCostRecovery = asmproc([[
	push esi
	push edi
	push ebx
	xor esi, esi
	mov eax, ecx
	lea eax, [eax + eax * 4]
	lea eax, [edx + eax * 2]
	shl eax, 1
	movzx edi, word ptr [eax + 0x4F4876] ; Recovery
	cmp dword ptr [esp + 0x14], 0
	jnz @end
	movzx esi, word ptr [eax + 0x4F486E] ; SP
	mov eax, dword ptr [0xB215C0] ; Game.Minute
	test eax, eax
	jnz @end
	call absolute ]] .. MO.GetSpellSkillId .. [[;
	mov ebx, eax
	mov eax, dword ptr [0xB215BC] ; Game.Hour
	cmp eax, 0xC
	jnz @ff
	cmp ebx, 0x13
	jnz @ff
	xor esi, esi
	@ff:
	test eax, eax
	jnz @end
	cmp ebx, 0x14
	jnz @end
	xor esi, esi
	@end:
	mov eax, dword ptr [esp + 0x10]
	nop
	nop
	nop
	nop
	nop
	mov eax, esi
	mov edx, edi
	pop ebx
	pop edi
	pop esi
	retn 8
	]])
	
	-- Auxiliary armor penalties
	local AuxArmorDelayPenalty = {
		[9]  = {5, 0, 0, 0},
		[10] = {10, 5, 0, 0},
		[11] = {15, 7.5, 7.5, 0},
	}

	-- Armor and shield penalties
	local ArmorDelayTable = {
		[8]  = {10, 0, 0, 0},    -- Shield
		[9]  = {10, 0, 0, 0},    -- Leather
		[10] = {20, 10, 0, 0},   -- Chain
		[11] = {30, 15, 15, 0},  -- Plate
	}
	
	local LargeShieldNames = {
		['Large Shield'] = true,
		['Artifact Large Shield'] = true,
		['Relic Large Shield'] = true,
	}

	-- Large shield additional penalties
	local LargeShieldDelayPenalty = {15, 15, 10, 0}

	function CalcSpellDelay(Player, SpellId)
		local DelayBonus = 0

		-- Auxiliary armor (helm, belt, gauntlets, boots)
		local auxSlots = {Player.ItemHelm, Player.ItemBelt, Player.ItemGauntlets, Player.ItemBoots}
		for _, slot in ipairs(auxSlots) do
			if slot > 0 and not Player.Items[slot].Broken then
				local skill = Game.ItemsTxt[Player.Items[slot].Number].Skill
				local pen = AuxArmorDelayPenalty[skill]
				if pen then
					local _, m = SplitSkill(Player:GetSkill(skill))
					DelayBonus = DelayBonus + pen[math.max(m, 1)]
				end
			end
		end

		-- Armor
		local armorSlot = Player.ItemArmor
		if armorSlot > 0 and not Player.Items[armorSlot].Broken then
			local skill = Game.ItemsTxt[Player.Items[armorSlot].Number].Skill
			local delays = ArmorDelayTable[skill]
			if delays then
				local _, m = SplitSkill(Player:GetSkill(skill))
				DelayBonus = DelayBonus + delays[math.max(m, 1)]
			end
		end

		-- Shield
		local shieldSlot = Player.ItemExtraHand
		if shieldSlot > 0 and not Player.Items[shieldSlot].Broken then
			local shieldNum = Player.Items[shieldSlot].Number
			local shieldSkill = Game.ItemsTxt[shieldNum].Skill
			if shieldSkill == 8 then
				local _, sm = SplitSkill(Player:GetSkill(8))
				sm = math.max(sm, 1)
				local shieldPen = ArmorDelayTable[8][sm]
				-- Large shield additional penalty
				if LargeShieldNames[Game.ItemsTxt[shieldNum].NotIdentifiedName] then
					shieldPen = shieldPen + LargeShieldDelayPenalty[sm]
				end
				DelayBonus = DelayBonus + shieldPen
			end
		end

		-- Stat bonuses by magic school
		local intBonus = Game.GetStatisticEffect(Player:GetIntellect())
		local perBonus = Game.GetStatisticEffect(Player:GetPersonality())
		local spdBonus = Game.GetStatisticEffect(Player:GetSpeed())
		
		DelayBonus = DelayBonus - spdBonus
		
		if SpellId < 45 then
			-- Elemental magic (Fire, Air, Water, Earth) — Intellect
			DelayBonus = DelayBonus - intBonus
		elseif SpellId < 78 then
			-- Spirit, Mind, Body — Personality
			DelayBonus = DelayBonus - perBonus
		elseif SpellId < 100 then
			-- Light and Dark — average of Intellect and Personality
			DelayBonus = DelayBonus - math.floor(intBonus / 2 + perBonus / 2)
		else
			DelayBonus = 0
		end

		return DelayBonus
	end
	
	local function GetPlayerFromPtr(ptr)
		local PlayerId = (ptr - Party.PlayersArray["?ptr"])/Party.PlayersArray[0]["?size"]
		return Party.PlayersArray[PlayerId], PlayerId
	end
	
	hook(MO.SpellCostRecovery + 84, function(d)
		local t = {Spell = d.ecx, SkillMastery = d.edx, Caster = d.eax, Cost = d.esi, Recovery = d.edi}
		events.call("SpellCostRecovery", t)
		if t.Spell < 133 then
			local Pl = Party[math.max(0, d.eax-35)]
			local MS,MM = SplitSkill(Pl:GetSkill(math.floor(t.Spell/11 - 1/11) + 12))
			local spdBonus = Game.GetStatisticEffect(Pl:GetSpeed())
			d.esi = t.Cost + t.Cost*0.025*MS*MM
			d.edi = math.max(30, t.Recovery - t.Recovery*0.01*MS + t.Recovery*0.01*CalcSpellDelay(Pl, t.Spell))
			if vars.ManaCost == nil then vars.ManaCost = 0 end
			vars.ManaCost = d.esi
			if vars.CastDelay == nil then vars.CastDelay = 0 end
			vars.CastDelay = d.edi
		else
			d.esi = t.Cost
			d.edi = t.Recovery
		end
	end)
	
	mem.asmpatch(0x412191, [[
		movzx eax, byte ptr [edx]
	]])

	mem.autohook(0x411f6c, function(d)
		local SpellNum = d.eax / 9 + 1
		if SpellNum >= 133 then
			mem.asmpatch(0x412180, "push " .. MF.cstring("%s\n%d"))
			return
		end

		local Pl = Party:GetCurrentPlayer()
		local MS, MM = SplitSkill(Pl:GetSkill(math.floor(SpellNum / 11 - 1 / 11) + 12))

		-- Spell mastery (1-4) by spell index in magic school
		local idx = (SpellNum - 1) % 11
		local rank
		if idx < 4 then
			rank = 1
		elseif idx < 7 then
			rank = 2
		elseif idx < 10 then
			rank = 3
		else
			rank = 4
		end

		local baseChance = 100 - rank * 20
		local castCh

		if Pl.Conditions[const.Condition.Cursed] > 0 then
			castCh = (4 - rank) * 10 + 5 * MM
		elseif rank == 1 then
			castCh = math.min(baseChance + MS * MM, 100)
		else
			castCh = math.min(baseChance + MS * MM, math.min(baseChance + 20 * MM, 100))
		end

		local ManaCost = Game.Spells[SpellNum].SpellPoints[MM] * (1 + 0.025 * MS * MM)
		local BaseDelay = Game.Spells[SpellNum].Delay[MM]
		local SpellRecovery = math.max(30, BaseDelay - BaseDelay*0.01*MS + BaseDelay*0.01*CalcSpellDelay(Pl, SpellNum))

		mem.asmpatch(0x412180, "push " .. MF.cstring(string.format(
			'SP Cost: %d \nDelay: %d \nSuccess: %d%%', ManaCost, SpellRecovery, castCh)))
	end)

	-- Add buffs2 with spells
	-- Preservation adds to Spirit Resistance
	function events.CalcStatBonusByMagic(t)
		if t.Stat ~= 33 then
			return
		end

		local Pl = t.Player
		local buff = Pl.SpellBuffs[const.PlayerBuff.Preservation]
		if not buff or buff.ExpireTime <= Game.Time then
			return
		end

		local SpellMastery = buff.Skill
		local ET = buff.ExpireTime - const.Hour - Game.Time

		local baseBonus = SpellMastery > 0 and 5*SpellMastery or 0
		local timeBonus = SpellMastery > 0 and select(SpellMastery,
			ET / const.Minute + 31,
			2 * ET / 5 / const.Minute + 1,
			3 * ET / 5 / const.Minute + 1,
			4 * ET / 15 / const.Minute + 1
		) or 2 * ET / const.Hour + 1

		t.Result = baseBonus + timeBonus

		local extraBuff = Game.PlayersExtra[Pl:GetIndex()].SpellBuffs2[27]
		if extraBuff then
			extraBuff.ExpireTime = buff.ExpireTime
		end
	end


	local function get_spell_var_value(Spell, VarNum, Mastery, DefValue)
		Mastery = min(max(Mastery, 1), 4)
		local res = MT.SpellsExtra[Spell]["Var" .. VarNum .. select(Mastery, "Normal", "Expert", "Master", "GM")]
		if not res then
			if type(DefValue) == "table" then
				res = DefValue[Mastery]
			else
				res = DefValue
			end
		end
		return res
	end
	--MF.GetSpellVarValue = get_spell_var_value

	-- Get casted spell cost and recovery
	asmpatch(0x426269, [[
	movzx eax, word ptr [ebx + 0xA]
	push eax
	movsx eax, word ptr [ebx + 2]
	push eax
	movsx ecx, word ptr [ebx]
	mov edx, dword ptr [ebp - 0xC]
	call absolute ]] .. MO.SpellCostRecovery .. [[;
	mov dword ptr [ebp - 8], eax
	mov dword ptr [ebp - 0xB8], edx
	xor ecx, ecx
	mov cx, word ptr [ebx]
	]], 0x4262C5 - 0x426269)

	-- Check abilities for sufficient SP as well
	asmpatch(0x4262C5, [[
	mov eax, dword ptr [ebp-0x1C]
	cmp cx, 0x85
	]])

	-- Spell fail check
	local new_code = asmpatch(0x4262EC, [[
	cmp cx, 0x85
	jge absolute 0x42630D
	xor ecx, ecx
	mov edx, [eax]
	or edx, [eax+4]
	setnz cl
	push ecx
	call absolute 0x4D99F2
	push 0x64
	cdq
	pop ecx
	idiv ecx
	movzx ecx, word ptr [ebx]
	pop eax
	inc edx
	push edi
	push 0x64
	pop edi
	cmp ecx, edi
	jge @one
	test eax, eax
	jz @one
	push 0x32
	pop edi
	@one:
	nop
	nop
	nop
	nop
	nop
	cmp edi, edx
	pop edi
	]], 0x426307 - 0x4262EC)
	hook((new_code or 0x4262EC) + 0x35, function(d)
		local t = {Spell = d.ecx, Roll = d.edx, Cursed = d.eax > 0,
			Mastery = u4[d.ebp - 0xC], Level = u4[d.ebp - 0x3C]}
		local flags = u2[d.ebx + 8]
		t.Type = u2[d.ebx + 0xA] > 0 and (bit.band(flags, 0x1) > 0 and 1 or (bit.band(flags, 0x20) > 0 and 2 or 3)) or 0
		t.Player, t.PlayerIndex = MF.GetPlayerFromPtr(u4[d.ebp - 0x1C])
		local SE = MT.SpellsExtra[t.Spell]
		if t.Type == 0 then
			t.Chance = SE
				and (min((SE.ChanceBase[t.Mastery] or 100)
					+ (SE.ChanceFactor[t.Mastery] or 0) * t.Level,
					(t.Cursed and (SE.ChanceCursed[t.Mastery] or 50)
						or (SE.ChanceMax[t.Mastery] or 100))))
				or d.edi
		elseif t.Type == 1 then
			t.Chance = SE
				and (min(SE.ScrollChanceBase[t.Mastery]
					+ SE.ScrollChanceFactor[t.Mastery] * t.Level,
					(t.Cursed and (SE.ScrollChanceCursed[t.Mastery] or 50)
						or (SE.ScrollChanceMax[t.Mastery] or 100))))
				or d.edi
		else
			t.Chance = 100
		end
		events.call("SpellFailCheck", t)
		d.edi = t.Chance
	end)

	new_code = asmpatch(0x42630D, [[
	movsx ecx, word ptr [ebx]
	nop
	nop
	nop
	nop
	nop
	lea eax, [ecx-1]
	]])
	hook(new_code + 0x3, function(d)
		local t = {Spell = d.ecx, Caster = i2[d.ebx + 0x2], Flags = u4[d.ebx + 0x8]}
		events.call("PlayerSpellProc", t)
		d.ecx = t.Spell
		u2[d.ebx] = t.Spell
		u4[d.ebx + 0x8] = t.Flags
	end)

	-------- Player Spell Var event --------
	local function player_spell_var(d, num, value)
		local t = {Spell = u2[d.ebx], VarNum = num, Value = value and value[1] or d.eax, Target = u4[d.ebp - 0x30],
			Mastery = u4[d.ebp - 0xC], Level = u4[d.ebp - 0x3C]}
		t.Flags = u2[d.ebx + 8]
		t.Type = u2[d.ebx + 0xA] > 0 and (bit.band(t.Flags, 0x1) > 0 and 1 or (bit.band(t.Flags, 0x20) > 0 and 2 or 3)) or 0
		t.Player, t.PlayerIndex = MF.GetPlayerFromPtr(u4[d.ebp - 0x1C])
		events.call("PlayerSpellVar", t)
		if value then
			value[1] = t.Value
		else
			d.eax = t.Value
		end
	end
	local function player_spell_var1(d)
		player_spell_var(d, 1)
	end
	local function player_spell_var2(d)
		player_spell_var(d, 2)
	end
	local function player_spell_var3(d)
		player_spell_var(d, 3)
	end
	local function player_spell_var4(d)
		player_spell_var(d, 4)
	end

	-------- 1: Torch Light --------
	asmpatch(0x4265E0, [[
	dec eax
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov dword ptr [ebp - 0x18], ]] .. (MT.SpellsExtra[1].Var1GM or 3600) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[1].Var2GM or 0) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[1].Var3GM or 4) .. [[;
	jmp @end
	@master:
	mov dword ptr [ebp - 0x18], ]] .. (MT.SpellsExtra[1].Var1Master or 3600) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[1].Var2Master or 0) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[1].Var3Master or 4) .. [[;
	jmp @end
	@expert:
	mov dword ptr [ebp - 0x18], ]] .. (MT.SpellsExtra[1].Var1Expert or 3600) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[1].Var2Expert or 0) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[1].Var3Expert or 3) .. [[;
	jmp @end
	@normal:
	mov dword ptr [ebp - 0x18], ]] .. (MT.SpellsExtra[1].Var1Normal or 3600) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[1].Var2Normal or 0) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[1].Var3Normal or 2) .. [[;
	@end:
	]])
	new_code = asmpatch(0x4265E5, [[
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 0x4], eax
	mov eax, ecx
	nop
	nop
	nop
	nop
	nop
	mov ecx, eax
	mov eax, dword ptr [ebp - 0x18]
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	adc edx, esi
	]], 0x42660F - 0x4265E5)
	hook(new_code or 0x4265E5, player_spell_var3)
	hook((new_code or 0x4265E5) + 0xA, player_spell_var2)
	hook((new_code or 0x4265E5) + 0x14, player_spell_var1)
	nop2(0x426612, 0x426618)
	nop(0x42661B, 1)
	-- fix buff caster
	asmpatch(0x426636, [[
	inc eax
	push eax
	]])
	asmpatch(0x42663E, "push esi")

	-------- Resistances: 3, 14, 25, 36, 58, 69 --------
	new_code = asmpatch(0x427438, [[
	xor eax, eax
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 0x24], eax
	mov eax, 0xE10
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, dword ptr [ebp - 0x24]
	adc edx, esi
	mov dword ptr [ebp - 0x14], eax
	mov dword ptr [ebp - 0x10], edx
	]], 0x42746D - 0x427438)
	hook((new_code or 0x427438) + 0x2, function(d)
		local spell, mastery = d.ecx, u4[d.ebp - 0xC]
		local power = {}
		power[1] = get_spell_var_value(spell, 3, mastery, {1, 2, 3, 4})
		player_spell_var(d, 3, power)
		power[2] = power[1]
		power[1] = get_spell_var_value(spell, 4, mastery, 0)
		player_spell_var(d, 4, power)
		-- check for being not lower than 1
		power[2] = floor(power[2] * d.edi + power[1])
		if power[2] == 0 and d.edi > 0 then
			power[2] = 1
		end
		u4[d.ebp - 0x4] = power[2]

		d.eax = get_spell_var_value(spell, 2, mastery, 0)
		player_spell_var(d, 2)
	end)
	hook((new_code or 0x427438) + 0xF, function(d)
		local spell, mastery = d.ecx, u4[d.ebp - 0xC]
		d.eax = get_spell_var_value(spell, 1, mastery, 3600)
		player_spell_var(d, 1)
	end)
	-- do not use spells 17,38,51 code
	asmpatch(0x427525, [[
	call absolute 0x4D967C
	mov ecx, dword ptr [ebp - 0x20]
	add eax, dword ptr [0xB20EBC]
	adc edx, dword ptr [0xB20EC0]
	shl ecx, 4
	add ecx, 0xB21738
	jmp absolute 0x42665C
	]])

	-------- 4: Fire Aura --------
	asmpatch(0x42720D, [[
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[4].Var3GM or 12) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[4].Var2GM or 0) .. [[;
	mov dword ptr [ebp - 0x18], ]] .. (MT.SpellsExtra[4].Var1GM or 0) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[4].Var3Master or 12) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[4].Var2Master or 0) .. [[;
	mov dword ptr [ebp - 0x18], ]] .. (MT.SpellsExtra[4].Var1Master or 3600) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[4].Var3Expert or 11) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[4].Var2Expert or 0) .. [[;
	mov dword ptr [ebp - 0x18], ]] .. (MT.SpellsExtra[4].Var1Expert or 3600) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[4].Var3Normal or 10) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[4].Var2Normal or 0) .. [[;
	mov dword ptr [ebp - 0x18], ]] .. (MT.SpellsExtra[4].Var1Normal or 3600) .. [[;
	@end:
	]])
	new_code = asmpatch(0x427212, [[
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 4], eax
	mov eax, ecx
	nop
	nop
	nop
	nop
	nop
	mov ecx, eax
	mov eax, dword ptr [ebp - 0x18]
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	adc edx, esi
	]], 0x427249 - 0x427212)
	hook(new_code or 0x427212, player_spell_var3)
	hook((new_code or 0x427212) + 0xA, player_spell_var2)
	hook((new_code or 0x427212) + 0x14, player_spell_var1)
	-- Permanent bonus if duration is 0
	asmpatch(0x4272E4, [[
	mov eax, dword ptr [ebp - 0x14]
	mov edx, dword ptr [ebp - 0x10]
	or eax, edx
	mov eax, dword ptr [ebp - 4]
	]])

	-------- 5: Haste --------
	asmpatch(0x42752D, [[
	dec eax
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[5].Var2GM or 3600) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[5].Var1GM or 240) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[5].Var2Master or 3600) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[5].Var1Master or 180) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[5].Var2Expert or 3600) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[5].Var1Expert or 60) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[5].Var2Normal or 3600) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[5].Var1Normal or 60) .. [[;
	@end:
	]])
	new_code = asmpatch(0x427534, [[
	nop
	nop
	nop
	nop
	nop
	push eax
	mov eax, ecx
	pop ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	adc edx, esi
	]], 0x42755D - 0x427534)
	hook(new_code or 0x427534, player_spell_var2)
	hook((new_code or 0x427534) + 9, player_spell_var1)
	-- Check for weak players (note: ecx is already set)
	asmpatch(0x427584, [[
	cmp dword ptr [ebp - 0xC], 1
	jg @party
	movzx eax, word ptr [ebx + 4]
	mov dword ptr [ebp - 0x24], eax
	mov dword ptr [ebp - 0x8], eax
	jmp @common
	@party:
	call absolute 0x42D776
	mov dword ptr [ebp - 0x24], eax
	mov dword ptr [ebp - 0x8], 0
	@common:
	]], 0x427590 - 0x427584)
	asmpatch(0x4275AA, "mov eax, dword ptr [ebp - 0x24]")
	asmpatch(0x4275B7, [[
	jnz @end
	mov eax, ]] .. (MF.GtSettingNum(MM.SpellsHasteSingleWeakNonFail, 0) and 1 or 0) .. [[;
	test eax, eax
	jz absolute 0x42D3AB
	@end:
	]])
	-- Use player SpellBuff instead of party one
	asmpatch(0x4275BD, [[
	cmp dword ptr [ebp - 0xC], 1
	jg @party
	movzx eax, word ptr [ebx + 4]
	mov dword ptr [ebp - 0x24], eax
	mov dword ptr [ebp - 0x8], eax
	jmp @common
	@party:
	mov ecx, 0xB20E90
	call absolute 0x42D776
	mov dword ptr [ebp - 0x24], eax
	mov dword ptr [ebp - 0x8], 0
	@common:
	fild qword ptr [ebp - 0x14]
	fmul dword ptr [0x4E8568]
	call absolute 0x4D967C
	add eax, dword ptr [0xB20EBC]
	adc edx, dword ptr [0xB20EC0]
	mov dword ptr [ebp - 0x17C], eax
	mov dword ptr [ebp - 0x178], edx

	@loop:
	push dword ptr [ebp - 0x8]
	mov ecx, 0xB20E90
	call absolute 0x4026F4
	mov edi, eax

	mov eax, dword ptr [edi + 0x8]
	or eax, dword ptr [edi + 0xC]
	jnz @next

	mov eax, ]] .. (MF.GtSettingNum(MM.SpellsBuffSkipNonConscious, 0) and 1 or 0) .. [[;
	test eax, eax
	jz @ff
	mov ecx, edi
	call absolute 0x491514
	test eax, eax
	jz @next

	@ff:
	mov ecx, edi

	push esi
	push esi
	push esi
	push dword ptr [ebp - 0xC]
	mov eax, dword ptr [ebp - 0x17C]
	mov edx, dword ptr [ebp - 0x178]
	push edx
	push eax
	add ecx, 0x1AA4
	call absolute 0x455D97
	push dword ptr [ebp - 0x8]
	movzx eax, word ptr [ebx]
	push eax
	mov ecx, dword ptr [0x75CE00]
	call absolute 0x42D747
	mov ecx, eax
	call absolute 0x4A6FCE
	@next:
	inc dword ptr [ebp - 0x8]
	mov eax, dword ptr [ebp - 0x24]
	cmp eax, dword ptr [ebp - 0x8]
	jg @loop
	]], 0x427643 - 0x4275BD)

	-------- 7: Fire Spike --------
	new_code = asmpatch(0x42666D, [[
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[7].Var1GM or 9) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[7].Var1Master or 7) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[7].Var1Expert or 5) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[7].Var1Normal or 3) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 4], eax
	]], 0x426697 - 0x42666D)
	hook((new_code or 0x42666D) + 0x21, player_spell_var1)

	-------- 8: Immolation --------
	asmpatch(0x427A65, [[
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov ecx, ]] .. (MT.SpellsExtra[8].Var1GM or 600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[8].Var2GM or 0) .. [[;
	jmp @end
	@master:
	mov ecx, ]] .. (MT.SpellsExtra[8].Var1Master or 60) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[8].Var2Master or 0) .. [[;
	jmp @end
	@expert:
	mov ecx, ]] .. (MT.SpellsExtra[8].Var1Expert or 30) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[8].Var2Expert or 0) .. [[;
	jmp @end
	@normal:
	mov ecx, ]] .. (MT.SpellsExtra[8].Var1Normal or 10) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[8].Var2Normal or 0) .. [[;
	@end:
	]])
	new_code = asmpatch(0x427A6A, [[
	nop
	nop
	nop
	nop
	nop
	push eax
	mov eax, ecx
	pop ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	adc edx, esi
	]], 0x427A7C - 0x427A6A)
	hook(new_code or 0x427A6A, player_spell_var2)
	hook((new_code or 0x427A6A) + 9, player_spell_var1)
	nop(0x427A82, 1)

	-------- 9: Meteor Shower --------
	new_code = asmpatch(0x427B1B, [[
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[9].Var1GM or 20) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[9].Var1Master or 16) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[9].Var1Expert or 12) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[9].Var1Normal or 8) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp-0x34], eax
	]], 0x427B36 - 0x427B1B)
	hook((new_code or 0x427B1B) + 0x22, player_spell_var1)

	-------- 12: Wizard Eye --------
	asmpatch(0x427FEF, [[
	call absolute 0x425B1A
	test eax, eax
	jz absolute 0x42D3AB
	]], 0x427FFE - 0x427FEF)
	asmpatch(0x427FFE, [[
	mov eax, dword ptr [ebp - 0xC]
	dec eax
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov ecx, ]] .. (MT.SpellsExtra[12].Var1GM or 3600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[12].Var2GM or 0) .. [[;
	mov dword ptr [ebp - 4], ]] .. (MT.SpellsExtra[12].Var3GM or 4) .. [[;
	jmp @end
	@master:
	mov ecx, ]] .. (MT.SpellsExtra[12].Var1Master or 3600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[12].Var2Master or 0) .. [[;
	mov dword ptr [ebp - 4], ]] .. (MT.SpellsExtra[12].Var3Master or 3) .. [[;
	jmp @end
	@expert:
	mov ecx, ]] .. (MT.SpellsExtra[12].Var1Expert or 3600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[12].Var2Expert or 0) .. [[;
	mov dword ptr [ebp - 4], ]] .. (MT.SpellsExtra[12].Var3Expert or 2) .. [[;
	jmp @end
	@normal:
	mov ecx, ]] .. (MT.SpellsExtra[12].Var1Normal or 3600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[12].Var2Normal or 0) .. [[;
	mov dword ptr [ebp - 4], ]] .. (MT.SpellsExtra[12].Var3Normal or 1) .. [[;
	@end:
	]])
	new_code = asmpatch(0x428003, [[
	nop
	nop
	nop
	nop
	nop
	push eax
	mov eax, ecx
	pop ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	adc edx, esi
	mov dword ptr [ebp - 0x14], eax
	mov dword ptr [ebp - 0x10], edx
	mov eax, dword ptr [ebp - 4]
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 4], eax
	movsx eax, word ptr [ebx + 0x2]
	inc eax
	push eax
	push esi
	push esi
	push dword ptr [ebp - 4]
	]], 0x428016 - 0x428003)
	hook(new_code or 0x428003, player_spell_var2)
	hook((new_code or 0x428003) + 9, player_spell_var1)
	hook((new_code or 0x428003) + 0x1D, player_spell_var3)

	-------- 13: Feather Fall --------
	asmpatch(0x42805B, [[
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov ecx, ]] .. (MT.SpellsExtra[13].Var1GM or 3600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[13].Var2GM or 0) .. [[;
	jmp @end
	@master:
	mov ecx, ]] .. (MT.SpellsExtra[13].Var1Master or 3600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[13].Var2Master or 0) .. [[;
	jmp @end
	@expert:
	mov ecx, ]] .. (MT.SpellsExtra[13].Var1Expert or 600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[13].Var2Expert or 0) .. [[;
	jmp @end
	@normal:
	mov ecx, ]] .. (MT.SpellsExtra[13].Var1Normal or 300) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[13].Var2Normal or 0) .. [[;
	@end:
	]])
	new_code = asmpatch(0x428060, [[
	nop
	nop
	nop
	nop
	nop
	push eax
	mov eax, ecx
	pop ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	adc edx, esi
	]], 0x428083 - 0x428060)
	hook(new_code or 0x428060, player_spell_var2)
	hook((new_code or 0x428060) + 0x9, player_spell_var1)
	-- fix buff caster
	asmpatch(0x4280DD, [[
	inc eax
	push eax
	push esi
	push esi
	]])

	-------- 15: Sparks --------
	new_code = asmpatch(0x428120, [[
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[15].Var1GM or 9) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[15].Var1Master or 7) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[15].Var1Expert or 5) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[15].Var1Normal or 3) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 4], eax
	]], 0x42814D - 0x428120)
	hook((new_code or 0x428120) + 0x22, player_spell_var1)

	-------- 16: Jump --------
	new_code = asmpatch(0x4282DE, [[
	mov eax, dword ptr [ebp - 0xC]
	dec eax
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[16].Var1GM or 1000) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[16].Var1Master or 1000) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[16].Var1Expert or 1000) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[16].Var1Normal or 750) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [0xB21588], eax
	]])
	hook(new_code + 0x26, player_spell_var1)

	-------- 17, 38, 51: Shield, Stone Skin, Heroism --------
	new_code = asmpatch(0x42794A, [[
	test eax, eax
	jle @normal
	cmp eax, 4
	jle @hook
	mov eax, 4
	jmp @hook
	@normal:
	mov eax, 1
	@hook:
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	adc edx, esi
	mov dword ptr [ebp - 0x14], eax
	mov dword ptr [ebp - 0x10], edx
	movzx ecx, word ptr [ebx]

	cmp ecx, 0x11
	jz @shield
	cmp ecx, 0x26
	jz @stone
	cmp ecx, 0x33
	jnz absolute 0x42D45D
	mov eax, 8
	jmp @end
	@stone:
	mov eax, 0xE
	jmp @end
	@shield:
	mov dword ptr [ebp - 0x4], esi
	mov eax, 0xD
	@end:
	shl eax, 4
	add eax, 0x1A34
	mov dword ptr [ebp - 0x20], eax

	push dword ptr [ebp - 0x8]
	mov ecx, dword ptr [ebp - 0x1C]
	call absolute 0x425B1A
	test eax, eax
	jz absolute 0x42D3AB
	cmp dword ptr [ebp - 0xC], 1
	jg @party
	movzx eax, word ptr [ebx + 4]
	mov dword ptr [ebp - 0x24], eax
	mov dword ptr [ebp - 0x8], eax
	jmp @common
	@party:
	mov ecx, 0xB20E90
	call absolute 0x42D776
	mov dword ptr [ebp - 0x24], eax
	mov dword ptr [ebp - 0x8], esi
	@common:
	movzx edi, word ptr [ebx]
	inc edi
	fild qword ptr [ebp - 0x14]
	fmul dword ptr [0x4E8568]
	call absolute 0x4D967C
	add eax, dword ptr [0xB20EBC]
	adc edx, dword ptr [0xB20EC0]
	mov dword ptr [ebp - 0x14C], eax
	mov dword ptr [ebp - 0x148], edx

	@loop:
	push esi
	push edi
	push dword ptr [ebp - 0x4]
	push dword ptr [ebp - 0xC]
	push dword ptr [ebp - 0x148]
	push dword ptr [ebp - 0x14C]
	push dword ptr [ebp - 0x8]
	mov ecx, 0xB20E90
	call absolute 0x4026F4
	mov ecx, eax
	add ecx, dword ptr [ebp - 0x20]
	call absolute 0x455D97
	push dword ptr [ebp - 0x8]
	movzx eax, word ptr [ebx]
	push eax
	mov ecx, dword ptr [0x75CE00]
	call absolute 0x42D747
	mov ecx, eax
	call absolute 0x4A6FCE
	inc dword ptr [ebp - 0x8]
	mov eax, dword ptr [ebp - 0x24]
	cmp eax, dword ptr [ebp - 0x8]
	jg @loop
	jmp absolute 0x42C200
	]], 0x427A60 - 0x42794A)
	hook((new_code or 0x42794A) + 0x15, function(d)
		local spell, mastery, skill = d.ecx, d.eax, d.edi
		--local Player, PlayerIndex = MF.GetPlayerFromPtr(u4[d.ebp - 0x1C])
		--local power = {}
		local StoneskinPower = 0.01*skill + 0.05 + mastery*0.05
		local spellpower = {
		[38] = math.ceil((-5+210*StoneskinPower)/(1 - StoneskinPower)),
		[51] = math.ceil(skill*select(mastery, 1, 1, 2, 2) + 5*mastery + 5)
		}
		if spell ~= 17 then
			
			--power[1] = get_spell_var_value(spell, 3, mastery, 1)
			--player_spell_var(d, 3, power)
			--power[2] = power[1]
			--power[1] = get_spell_var_value(spell, 4, mastery, 5)
			--player_spell_var(d, 4, power)
			u4[d.ebp - 0x4] = spellpower[spell] --floor(power[2] * d.edi + power[1])
		end
		d.eax = get_spell_var_value(spell, 2, mastery, 3600)
		player_spell_var(d, 2)
		d.ecx = d.eax
		d.eax = get_spell_var_value(spell, 1, mastery, {300, 300, 900, 3600})
		player_spell_var(d, 1)
	end)

	-------- 19: Invisibility --------
	asmpatch(0x4282F1, [[
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[19].Var2GM or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[19].Var1GM or 3600) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[19].Var2Master or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[19].Var1Master or 600) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[19].Var2Expert or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[19].Var1Expert or 600) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[19].Var2Normal or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[19].Var1Normal or 600) .. [[;
	@end:
	]])
	new_code = asmpatch(0x4282F6, [[
	nop
	nop
	nop
	nop
	nop
	push eax
	mov eax, ecx
	pop ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	adc edx, esi
	]], 0x428327 - 0x4282F6)
	hook(new_code or 0x4282F6, function(d)
		local mastery = u4[d.ebp - 0xC]
		local power = {}
		power[1] = get_spell_var_value(19, 3, mastery, {1, 2, 3, 4})
		player_spell_var(d, 3, power)
		u4[d.ebp - 0x4] = floor(power[1] * d.edi)
		player_spell_var(d, 2)
	end)
	hook((new_code or 0x4282F6) + 0x9, player_spell_var1)
	-- fix buff caster
	asmpatch(0x42838E, [[
	inc eax
	push eax
	push esi
	]])

	-------- 21, 124: Fly, Flight --------
	new_code = asmpatch(0x428406, [[
	mov dword ptr [ebp - 0x24], eax
	jnz @ok
	movzx eax, word ptr [ebx + 0x8]
	and eax, 0x21
	jz absolute 0x428A5F
	@ok:
	mov eax, dword ptr [ebp - 0xC]
	cmp eax, esi
	jg @upper
	mov eax, 1
	jmp @end
	@upper:
	cmp eax, 4
	jle @end
	mov eax, 4
	@end:
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	adc edx, esi
	mov dword ptr [ebp - 0x14], eax
	mov dword ptr [ebp - 0x10], edx

	mov eax, dword ptr [ebp - 0x4]
	test eax, eax
	jz @ff2
	movzx eax, word ptr [ebx + 0x8]
	and ah, ]] .. spellflags1_special .. [[;
	test ah, ah
	jnz @ff1
	mov eax, dword ptr [ebp - 0x24]
	test eax, eax
	jz absolute 0x428A5F
	jmp @ff2
	@ff1:
	mov dword ptr [ebp - 0x4], esi
	@ff2:
	]], 0x428432 - 0x428406)
	hook((new_code or 0x428406) + 0x2A, function(d)
		local spell, mastery = u2[d.ebx], d.eax
		d.eax = get_spell_var_value(spell, 3, mastery, {1, 1, 1, 0})
		player_spell_var(d, 3)
		u4[d.ebp - 0x4] = d.eax
		d.eax = get_spell_var_value(spell, 2, mastery, 0)
		player_spell_var(d, 2)
		d.ecx = d.eax
		d.eax = get_spell_var_value(spell, 1, mastery, {300, 600, 3600, 3600})
		player_spell_var(d, 1)
	end)
	-- Allow to fly with 0 sp if tick SP cost is 0
	asmpatch(0x472AD0, [[
	jg @end
	cmp word ptr [0xB217B0], 0
	jz @end
	jmp absolute 0x47316C
	@end:
	]])

	-------- 22: Starburst --------
	new_code = asmpatch(0x42848F, [[
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[22].Var1GM or 20) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[22].Var1Master or 16) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[22].Var1Expert or 12) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[22].Var1Normal or 8) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 0x4], eax
	]], 0x428495 - 0x42848F)
	hook((new_code or 0x42848F) + 0x21, player_spell_var1)
	asmpatch(0x428584, [[
	mov eax, dword ptr [ebp - 0x4]
	mov dword ptr [ebp - 0x30], eax
	]])

	-------- 23: Awaken --------
	asmpatch(0x4287AA, [[
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov ecx, ]] .. (MT.SpellsExtra[23].Var1GM or 0) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[23].Var2GM or 0) .. [[;
	jmp @end
	@master:
	mov ecx, ]] .. (MT.SpellsExtra[23].Var1Master or 86400) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[23].Var2Master or 0) .. [[;
	jmp @end
	@expert:
	mov ecx, ]] .. (MT.SpellsExtra[23].Var1Expert or 3600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[23].Var2Expert or 0) .. [[;
	jmp @end
	@normal:
	mov ecx, ]] .. (MT.SpellsExtra[23].Var1Normal or 180) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[23].Var2Normal or 0) .. [[;
	@end:
	]])
	new_code = asmpatch(0x4287AF, [[
	nop
	nop
	nop
	nop
	nop
	push eax
	mov eax, ecx
	pop ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	mov dword ptr [ebp - 0x4], eax
	]], 0x4287D0 - 0x4287AF)
	hook(new_code or 0x4287AF, player_spell_var2)
	hook((new_code or 0x4287AF) + 0x9, player_spell_var1)
	asmpatch(0x4287FA, "cmp dword ptr [ebp - 0x4], esi")

	-------- 24: Poison Spray --------
	new_code = asmpatch(0x42889A, [[
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[24].Var1GM or 7) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[24].Var1Master or 5) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[24].Var1Expert or 3) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[24].Var1Normal or 1) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 4], eax
	]], 0x4288C4 - 0x42889A)
	hook((new_code or 0x42889A) + 0x21, player_spell_var1)

	-------- 27: Water Walk --------
	asmpatch(0x428A56, [[
	call absolute 0x48DA18
	mov dword ptr [ebp - 0x24], eax
	movzx eax, word ptr [ebx + 0x8]
	and eax, 0x21
	jnz @ok
	mov eax, dword ptr [ebp - 0x24]
	@ok:
	]])
	new_code = asmpatch(0x428A8E, [[
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[27].Var2GM or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[27].Var1GM or 3600) .. [[;
	mov dword ptr [ebp - 0x4], ]] .. (MT.SpellsExtra[27].Var3GM or 0) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[27].Var2Master or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[19].Var1Master or 3600) .. [[;
	mov dword ptr [ebp - 0x4], ]] .. (MT.SpellsExtra[27].Var3Master or 1) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[27].Var2Expert or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[27].Var1Expert or 600) .. [[;
	mov dword ptr [ebp - 0x4], ]] .. (MT.SpellsExtra[27].Var3Expert or 1) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[27].Var2Normal or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[27].Var1Normal or 300) .. [[;
	mov dword ptr [ebp - 0x4], ]] .. (MT.SpellsExtra[27].Var3Normal or 1) .. [[;
	@end:
	]])
	new_code = asmpatch(0x428A93, [[
	nop
	nop
	nop
	nop
	nop
	push eax
	mov eax, ecx
	pop ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	adc edx, esi
	mov dword ptr [ebp - 0x14], eax
	mov dword ptr [ebp - 0x10], edx
	mov eax, dword ptr [ebp - 0x4]
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 0x4], eax
	test eax, eax
	jz @ff2
	movzx eax, word ptr [ebx + 0x8]
	and ah, ]] .. spellflags1_special .. [[;
	test eax, eax
	jnz @ff1
	mov eax, dword ptr [ebp - 0x24]
	test eax, eax
	jz absolute 0x428A5F
	jmp @ff2
	@ff1:
	mov dword ptr [ebp - 0x4], esi
	@ff2:
	]], 0x428AAC - 0x428A93)
	hook(new_code or 0x428A93, player_spell_var2)
	hook((new_code or 0x428A93) + 0x9, player_spell_var1)
	hook((new_code or 0x428A93) + 0x1D, player_spell_var3)
	nop2(0x428AB2, 0x428AB9)
	asmpatch(0x428B57, [[
	xor eax, eax
	mov byte ptr []] .. MO.WaterWalk5Mins .. [[], al
	cmp dword ptr [ebp - 0x4], esi
	jnz @ff1
	inc eax
	@ff1:
	test byte ptr [ebx + 0x9], ]] .. spellflags1_special .. [[;
	jz @ff2
	or al, 2
	@ff2:
	mov byte ptr [0xB21867], al
	]], 0x428B68 - 0x428B57)
	-- Reduce SP per 20 mins
	asmpatch(0x491DD1, [[
	movzx ebx, byte ptr []] .. MO.WaterWalk5Mins .. [[]
	add ebx, eax
	cmp ebx, 4
	jge @ff
	mov byte ptr []] .. MO.WaterWalk5Mins .. [[], bl
	jmp absolute 0x491DE7
	@ff:
	mov edi, ebx
	and ebx, 0x3
	mov byte ptr []] .. MO.WaterWalk5Mins .. [[], bl
	shr edi, 2
	movzx ebx, word ptr [0xB21860]
	imul ebx, edi
	xor edi, edi
	add ecx, 0x1BFC
	sub dword ptr [ecx], ebx
	]], 0x491DD9 - 0x491DD1)
	-- FIXME: Disable MM8Patch hook
	asmpatch(0x491DAD, "test byte ptr [0xB21867], 1", 0x491DB4 - 0x491DAD)

	-------- 28: Recharge Item --------
	new_code = asmpatch(0x428BC5, [[
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[28].Var1GM or 80) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[28].Var1Master or 70) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[28].Var1Expert or 50) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[28].Var1Normal or 30) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	add edi, eax
	movzx eax, byte ptr [ecx + 0x19]
	cmp edi, 0x64
	jge @ff
	imul edi
	mov edi, 0x64
	idiv edi
	@ff:
	]], 0x428C2F - 0x428BC5)
	hook((new_code or 0x428BC5) + 0x22, function(d)
		local mastery = u4[d.ebp - 0xC]
		player_spell_var(d, 1)
		local mult = {}
		mult[1] = MT.SpellsExtra[28]["Var2" .. select(mastery, "Normal", "Expert", "Master", "GM")] or 1
		player_spell_var(d, 2, mult)
		d.edi = floor(mult[1] * d.edi)
	end)

	-------- 30: Enchant Item --------
	asmpatch(0x428CC1, "jle absolute 0x42947E")
	nop2(0x428CD6, 0x428CDC)
	if MV.SpcVal == nil then MV.SpcVal = 0 end
	--   GM non-weapon value
	new_code = asmpatch(0x428D47, [[
	mov ecx, eax
	mov eax, ]] .. (MT.SpellsExtra[30].Var1GM or 450) .. [[;
	nop
	nop
	nop
	nop
	nop
	cmp ecx, eax
	]])
	hook((new_code or 0x428D47) + 7, player_spell_var1)
	mem.autohook(0x428D47, function(d)
		local item_value = d.eax
		local Player = MF.GetPlayerFromPtr(u4[d.ebp - 0x1C])
		local ItemNum = mem.i4[d.edi]
		local ItemIdRepSt = Game.ItemsTxt[ItemNum].IdRepSt
		local WS, WM = SplitSkill(Player:GetSkill(const.Skills.Water))
		mem.asmpatch(0x428E91, "mov esi, " .. math.min(WS, ItemIdRepSt))
		mem.asmpatch(0x428E97, "mov ecx, " .. math.min(0, math.floor(WS/2 - item_value/100)))
		MV.SpcVal = math.random(1, math.min(math.floor(ItemIdRepSt/6), 4))
	end)
	--   GM weapon value
	new_code = asmpatch(0x428D55, [[
	mov ecx, eax
	mov eax, ]] .. (MT.SpellsExtra[30].Var2GM or 250) .. [[;
	nop
	nop
	nop
	nop
	nop
	cmp ecx, eax
	]])
	hook((new_code or 0x428D55) + 7, player_spell_var2)
	mem.autohook(0x428D47, function(d)
		local item_value = d.eax
		local Player = MF.GetPlayerFromPtr(u4[d.ebp - 0x1C])
		local ItemNum = mem.i4[d.edi]
		local ItemIdRepSt = Game.ItemsTxt[ItemNum].IdRepSt
		local WS, WM = SplitSkill(Player:GetSkill(const.Skills.Water))
		mem.asmpatch(0x428E91, "mov esi, " .. math.min(WS, ItemIdRepSt))
		mem.asmpatch(0x428E97, "mov ecx, " .. math.min(0, math.floor(WS/2 - item_value/100)))
		MV.SpcVal = math.random(1, math.min(math.floor(ItemIdRepSt/6), 4))
	end)
	--   GM max StdBonus strength
	--new_code = asmpatch(0x428E91, [[
	--push eax
	--mov eax, ]] .. (MT.SpellsExtra[30].Var4GM or 17) .. [[;
	--nop
	--nop
	--nop
	--nop
	--nop
	--mov esi, eax
	--pop eax
	--]])
	--hook((new_code or 0x428E91) + 6, player_spell_var4)
	----   GM min StdBonus strength
	--new_code = asmpatch(0x428E97, [[
	--push eax
	--mov eax, ]] .. (MT.SpellsExtra[30].Var3GM or 10) .. [[;
	--nop
	--nop
	--nop
	--nop
	--nop
	--mov ecx, eax
	--pop eax
	--]])
	--hook((new_code or 0x428E97) + 6, player_spell_var3)
	-- GM min/max SpcBonus Level
	--mov eax, ]] .. (MT.SpellsExtra[30].Var6GM or 1) .. [[;
	new_code = asmpatch(0x428EC3, [[
	movzx esi, al
	mov eax, ]] .. (MT.SpellsExtra[30].Var5GM or 0) .. [[;
	nop
	nop
	nop
	nop
	nop
	cmp esi, eax
	jl absolute 0x428EF5
	mov eax, ]] .. (MV.SpcVal or 1) .. [[;
	nop
	nop
	nop
	nop
	nop
	cmp esi, eax
	jg absolute 0x428EF5
	]], 0x428ECB - 0x428EC3)
	hook((new_code or 0x428EC3) + 8, function(d)
		player_spell_var(d, 5)
	end)
	hook((new_code or 0x428EC3) + 0x1A, function(d)
		player_spell_var(d, 6)
	end)

	--   Master non-weapon value
	new_code = asmpatch(0x428FDA, [[
	mov ecx, eax
	mov eax, ]] .. (MT.SpellsExtra[30].Var1Master or 450) .. [[;
	nop
	nop
	nop
	nop
	nop
	cmp ecx, eax
	]])
	hook((new_code or 0x428FDA) + 7, player_spell_var1)
	mem.autohook(0x428FDA, function(d)
		local item_value = d.eax
		local Player = MF.GetPlayerFromPtr(u4[d.ebp - 0x1C])
		local ItemNum = mem.i4[d.edi]
		local ItemIdRepSt = Game.ItemsTxt[ItemNum].IdRepSt
		local WS, WM = SplitSkill(Player:GetSkill(const.Skills.Water))
		mem.asmpatch(0x429124, "mov esi, " .. math.min(math.min(WS, 15), ItemIdRepSt))
		mem.asmpatch(0x42912A, "mov ecx, " .. math.min(0, math.floor(WS/2 - item_value/100)))
		MV.SpcVal = math.random(1, math.min(math.floor(ItemIdRepSt/6), 3))
	end)
	--   Master weapon value
	new_code = asmpatch(0x428FE8, [[
	mov ecx, eax
	mov eax, ]] .. (MT.SpellsExtra[30].Var2Master or 250) .. [[;
	nop
	nop
	nop
	nop
	nop
	cmp ecx, eax
	]])
	hook((new_code or 0x428FE8) + 7, player_spell_var2)
	mem.autohook(0x428FE8, function(d)
		local item_value = d.eax
		local Player = MF.GetPlayerFromPtr(u4[d.ebp - 0x1C])
		local ItemNum = mem.i4[d.edi]
		local ItemIdRepSt = Game.ItemsTxt[ItemNum].IdRepSt
		local WS, WM = SplitSkill(Player:GetSkill(const.Skills.Water))
		mem.asmpatch(0x429124, "mov esi, " .. math.min(math.min(WS, 15), ItemIdRepSt))
		mem.asmpatch(0x42912A, "mov ecx, " .. math.min(0, math.floor(WS/2 - item_value/100)))
		MV.SpcVal = math.random(1, math.min(math.floor(ItemIdRepSt/6), 3))
	end)
	--   Master max StdBonus strength
	--new_code = asmpatch(0x429124, [[
	--push eax
	--mov eax, ]] .. (MT.SpellsExtra[30].Var4Master or 12) .. [[;
	--nop
	--nop
	--nop
	--nop
	--nop
	--mov esi, eax
	--pop eax
	--]])
	--hook((new_code or 0x429124) + 6, player_spell_var4)
	----   Master min StdBonus strength
	--new_code = asmpatch(0x42912A, [[
	--push eax
	--mov eax, ]] .. (MT.SpellsExtra[30].Var3Master or 6) .. [[;
	--nop
	--nop
	--nop
	--nop
	--nop
	--mov ecx, eax
	--pop eax
	--]])
	--hook((new_code or 0x42912A) + 6, player_spell_var3)
	-- Master min/max SpcBonus Level
	--mov eax, ]] .. (MT.SpellsExtra[30].Var6Master or 1) .. [[;
	new_code = asmpatch(0x429156, [[
	movzx esi, al
	mov eax, ]] .. (MT.SpellsExtra[30].Var5Master or 0) .. [[;
	nop
	nop
	nop
	nop
	nop
	cmp esi, eax
	jl absolute 0x429188
	mov eax, ]] .. (MV.SpcVal or 1) .. [[;
	nop
	nop
	nop
	nop
	nop
	cmp esi, eax
	jg absolute 0x429188
	]], 0x42915E - 0x429156)
	hook((new_code or 0x429156) + 8, function(d)
		player_spell_var(d, 5)
	end)
	hook((new_code or 0x429156) + 0x1A, function(d)
		player_spell_var(d, 6)
	end)

	--   Expert non-weapon value
	new_code = asmpatch(0x429281, [[
	mov ecx, eax
	mov eax, ]] .. (MT.SpellsExtra[30].Var1Expert or 450) .. [[;
	nop
	nop
	nop
	nop
	nop
	cmp ecx, eax
	]])
	hook((new_code or 0x429281) + 7, player_spell_var1)
	mem.autohook(0x42927A, function(d)
		local ItemNum = u4[d.eax]
		mem.autohook(0x429281, function(d)
			local item_value = d.eax
			local Player = MF.GetPlayerFromPtr(u4[d.ebp - 0x1C])			
			local ItemIdRepSt = Game.ItemsTxt[ItemNum].IdRepSt
			local WS, WM = SplitSkill(Player:GetSkill(const.Skills.Water))
			mem.asmpatch(0x429384, "mov edi, " .. math.min(math.min(WS, 10), ItemIdRepSt))
			mem.asmpatch(0x42938A, "mov ecx, " .. math.min(0,math.floor(WS/2 - item_value/100)))
			MV.SpcVal = math.random(1, math.min(math.floor(ItemIdRepSt/6), 2))
			--Game.ShowStatusText(MV.SpcVal)
		end)
	end)
	--   Expert max StdBonus strength
	--new_code = asmpatch(0x429384, [[
	--push eax
	--mov eax, ]] .. (MT.SpellsExtra[30].Var4Expert or 12) .. [[;
	--nop
	--nop
	--nop
	--nop
	--nop
	--mov edi, eax
	--pop eax
	--]])
	--hook((new_code or 0x429384) + 6, player_spell_var4)
	----   Expert min StdBonus strength
	--new_code = asmpatch(0x42938A, [[
	--push eax
	--mov eax, ]] .. (MT.SpellsExtra[30].Var3Expert or 6) .. [[;
	--nop
	--nop
	--nop
	--nop
	--nop
	--mov ecx, eax
	--pop eax
	--]])
	--hook((new_code or 0x42938A) + 6, player_spell_var3)
	-- Expert min/max SpcBonus Level
	--mov eax, ]] .. (MT.SpellsExtra[30].Var6Expert or 1) .. [[;
	new_code = asmpatch(0x4293C4, [[
	movzx edi, al
	mov eax, ]] .. (MT.SpellsExtra[30].Var5Expert or 0) .. [[;
	nop
	nop
	nop
	nop
	nop
	cmp edi, eax
	jl absolute 0x4293F6
	mov eax, ]] .. (MV.SpcVal or 1) .. [[;
	nop
	nop
	nop
	nop
	nop
	cmp edi, eax
	jg absolute 0x4293F6
	]], 0x4293CC - 0x4293C4)
	hook((new_code or 0x4293C4) + 8, function(d)
		player_spell_var(d, 5)
	end)
	hook((new_code or 0x4293C4) + 0x1A, function(d)
		player_spell_var(d, 6)
	end)
	-- Beginner non-weapon value
	new_code = asmpatch(0x4294F8, [[
	mov ecx, eax
	mov eax, ]] .. (MT.SpellsExtra[30].Var1Normal or 450) .. [[;
	nop
	nop
	nop
	nop
	nop
	cmp ecx, eax
	]])
	hook((new_code or 0x4294F8) + 7, player_spell_var1)
	mem.autohook(0x4294f8, function(d)
		local item_value = d.eax
		local Player = MF.GetPlayerFromPtr(u4[d.ebp - 0x1C])
		local ItemNum = mem.i4[d.edi]
		local ItemIdRepSt = Game.ItemsTxt[ItemNum].IdRepSt
		local WS, WM = SplitSkill(Player:GetSkill(const.Skills.Water))
		mem.asmpatch(0x4295e7, "mov esi, " .. math.min(math.min(WS, 5), ItemIdRepSt))
		mem.asmpatch(0x4295ed, "mov ecx, " .. math.min(0, math.floor(WS/2 - item_value/100)))
	end)
	
	-- Beginner non-weapon value
	--new_code = asmpatch(0x4294F8, [[
	--mov ecx, eax
	--mov eax, ]] .. (MT.SpellsExtra[30].Var1Normal or 450) .. [[;
	--nop
	--nop
	--nop
	--nop
	--nop
	--cmp ecx, eax
	--]])
	--hook((new_code or 0x4294F8) + 7, player_spell_var1)
	----   Beginner max StdBonus strength
	--new_code = asmpatch(0x4295E7, [[
	--push eax
	--mov eax, ]] .. (MT.SpellsExtra[30].Var4Normal or 12) .. [[;
	--nop
	--nop
	--nop
	--nop
	--nop
	--mov esi, eax
	--pop eax
	--]])
	--hook((new_code or 0x4295E7) + 6, player_spell_var4)
	----   Beginner min StdBonus strength
	--new_code = asmpatch(0x4295ED, [[
	--push eax
	--mov eax, ]] .. (MT.SpellsExtra[30].Var3Normal or 6) .. [[;
	--nop
	--nop
	--nop
	--nop
	--nop
	--mov ecx, eax
	--pop eax
	--]])
	--hook((new_code or 0x4295ED) + 6, player_spell_var3)

	-------- 31: Town Portal --------
	new_code = asmpatch(0x42968B, [[
	mov eax, dword ptr [ebp - 0xC]
	dec eax
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[31].Var1GM or 1) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[31].Var1Master or 0) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[31].Var1Expert or 0) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[31].Var1Normal or 0) .. [[;
	@end:
	mov cx, word ptr [ebx + 0x8]
	and ch, ]] .. spellflags1_special .. [[;
	test ch, ch
	jz @hook
	mov eax, 1
	@hook:
	nop
	nop
	nop
	nop
	nop
	test eax, eax
	mov ecx, dword ptr [0x601BC8]
	jz absolute 0x427361
	]], 0x429695 - 0x42968B)
	hook((new_code or 0x42968B) + 0x36, player_spell_var1)
	asmpatch(0x429695, [[
	mov eax, dword ptr [ebp - 0xC]
	cmp eax, 2
	jg @end
	je @ff
	cmp dword ptr [0x6F39A0], 2
	je @ff
	@none:
	jmp absolute 0x42735B
	@ff:
	mov ecx, 0x51D818
	cmp byte ptr [ecx + 1], 0
	jle @none
	mov al, byte ptr [ebx + 2]
	mov byte ptr [ecx], al
	movzx eax, byte ptr [ecx + 1]
	push esi
	push eax
	push 0xC2
	mov ecx, 0x51E330
	call absolute 0x42D7A7
	jmp absolute 0x42C200
	@end:
	]], 0x4296AF - 0x429695)

	-------- 33: Lloyd's Beacon --------
	--   Lloyd's Beacon slots
	new_code = asmpatch(0x4D147E, [[
	mov eax, dword ptr [0x51791C]
	dec eax
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[33].Var3GM or 5) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[33].Var3Master or 3) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[33].Var3Expert or 2) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[33].Var3Normal or 1) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp-0x14], eax
	]], 0x4D14A9 - 0x4D147E)
	hook((new_code or 0x4D147E) + 0x28, function(d)
		local t = {Spell = 33, VarNum = 3, Value = d.eax, Mastery = u4[0x51791C]}
		t.Player, t.PlayerIndex = MF.GetPlayerFromPtr(d.ecx)
		events.call("PlayerSpellVar", t)
		d.eax = t.Value
	end)
	--   Lloyd's Beacon slots
	new_code = asmpatch(0x4D1736, [[
	mov eax, dword ptr [0x51791C]
	dec eax
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[33].Var3GM or 5) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[33].Var3Master or 3) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[33].Var3Expert or 2) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[33].Var3Normal or 1) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp-0x18], eax
	]], 0x4D175D - 0x4D1736)
	hook((new_code or 0x4D1736) + 0x28, function(d)
		local t = {Spell = 33, VarNum = 3, Value = d.eax, Mastery = u4[0x51791C]}
		t.Player, t.PlayerIndex = MF.GetPlayerFromPtr(d.edi)
		events.call("PlayerSpellVar", t)
		d.eax = t.Value
	end)
	--   Lloyd's Beacon duration
	new_code = asmpatch(0x4296CD, [[
	mov eax, dword ptr [ebp-0xC]
	dec eax
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov ecx, ]] .. (MT.SpellsExtra[33].Var1GM or 604800) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[33].Var2GM or 0) .. [[;
	jmp @end
	@master:
	mov ecx, ]] .. (MT.SpellsExtra[33].Var1Master or 86400) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[33].Var2Master or 0) .. [[;
	jmp @end
	@expert:
	mov ecx, ]] .. (MT.SpellsExtra[33].Var1Expert or 21600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[33].Var2Expert or 0) .. [[;
	jmp @end
	@normal:
	mov ecx, ]] .. (MT.SpellsExtra[33].Var1Normal or 3600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[33].Var2Normal or 0) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	push eax
	mov eax, ecx
	pop ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	adc edx, esi
	]], 0x4296D6 - 0x4296CD)
	hook((new_code or 0x4296CD) + 0x3A, player_spell_var2)
	hook((new_code or 0x4296CD) + 0x43, player_spell_var1)
	-- Store spell skill mastery
	asmpatch(0x429736, [[
	mov dword ptr [0x517918], eax
	mov eax, dword ptr [ebp - 0xC]
	mov dword ptr [0x51791C], eax
	]])

	-------- 35: Slow --------
	new_code = asmpatch(0x426F1C, [[
	dec eax
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[35].Var2GM or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[35].Var1GM or 300) .. [[;
	mov dword ptr [ebp - 0x4], ]] .. (MT.SpellsExtra[35].Var3GM or 8) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[35].Var2Master or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[35].Var1Master or 300) .. [[;
	mov dword ptr [ebp - 0x4], ]] .. (MT.SpellsExtra[35].Var3Master or 4) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[35].Var2Expert or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[35].Var1Expert or 300) .. [[;
	mov dword ptr [ebp - 0x4], ]] .. (MT.SpellsExtra[35].Var3Expert or 2) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[35].Var2Normal or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[35].Var1Normal or 180) .. [[;
	mov dword ptr [ebp - 0x4], ]] .. (MT.SpellsExtra[35].Var3Normal or 2) .. [[;
	@end:
	]])
	new_code = asmpatch(0x426F21, [[
	nop
	nop
	nop
	nop
	nop
	push eax
	mov eax, ecx
	pop ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	adc edx, esi
	mov dword ptr [ebp - 0x14], eax
	mov dword ptr [ebp - 0x10], edx
	mov eax, dword ptr [ebp - 0x4]
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 0x4], eax
	]], 0x426F5E - 0x426F21)
	hook(new_code or 0x426F21, player_spell_var2)
	hook((new_code or 0x426F21) + 0x9, player_spell_var1)
	hook((new_code or 0x426F21) + 0x1D, player_spell_var3)
	nop2(0x426F64, 0x426F6B)

	-------- 40: Stone to Flesh --------
	new_code = asmpatch(0x42976A, [[
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov ecx, ]] .. (MT.SpellsExtra[40].Var1GM or 0) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[40].Var2GM or 0) .. [[;
	jmp @end
	@master:
	mov ecx, ]] .. (MT.SpellsExtra[40].Var1Master or 86400) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[40].Var2Master or 0) .. [[;
	jmp @end
	@expert:
	mov ecx, ]] .. (MT.SpellsExtra[40].Var1Expert or 3600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[40].Var2Expert or 0) .. [[;
	jmp @end
	@normal:
	mov ecx, ]] .. (MT.SpellsExtra[40].Var1Normal or 180) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[40].Var2Normal or 0) .. [[;
	@end:
	]])
	new_code = asmpatch(0x42976F, [[
	nop
	nop
	nop
	nop
	nop
	push eax
	mov eax, ecx
	pop ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	mov dword ptr [ebp - 4], eax
	]], 0x42977B - 0x42976F)
	hook(new_code or 0x42976F, player_spell_var2)
	hook((new_code or 0x42976F) + 0x9, player_spell_var1)
	asmpatch(0x4297AB, "cmp dword ptr [ebp - 4], 0")

	-------- 45: Detect Life --------
	asmpatch(0x429A17, [[
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov ecx, ]] .. (MT.SpellsExtra[45].Var1GM or 3600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[45].Var2GM or 0) .. [[;
	jmp @end
	@master:
	mov ecx, ]] .. (MT.SpellsExtra[45].Var1Master or 3600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[45].Var2Master or 0) .. [[;
	jmp @end
	@expert:
	mov ecx, ]] .. (MT.SpellsExtra[45].Var1Expert or 1800) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[45].Var2Expert or 0) .. [[;
	jmp @end
	@normal:
	mov ecx, ]] .. (MT.SpellsExtra[45].Var1Normal or 600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[45].Var2Normal or 0) .. [[;
	@end:
	]])
	new_code = asmpatch(0x429A1C, [[
	nop
	nop
	nop
	nop
	nop
	push eax
	mov eax, ecx
	pop ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	adc edx, esi
	]], 0x429A3B - 0x429A1C)
	hook(new_code or 0x429A1C, player_spell_var2)
	hook((new_code or 0x429A1C) + 0x9, player_spell_var1)
	nop(0x429A41, 1)

	-------- 46: Bless --------
	asmpatch(0x42764C, [[
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov ecx, ]] .. (MT.SpellsExtra[46].Var1GM or 3600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[46].Var2GM or 3600) .. [[;
	jmp @end
	@master:
	mov ecx, ]] .. (MT.SpellsExtra[46].Var1Master or 900) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[46].Var2Master or 3600) .. [[;
	jmp @end
	@expert:
	mov ecx, ]] .. (MT.SpellsExtra[46].Var1Expert or 300) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[46].Var2Expert or 3600) .. [[;
	jmp @end
	@normal:
	mov ecx, ]] .. (MT.SpellsExtra[46].Var1Normal or 300) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[46].Var2Normal or 3600) .. [[;
	@end:
	]])
	new_code = asmpatch(0x427651, [[
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 0x14], eax
	mov eax, ecx
	mov ecx, dword ptr [ebp - 0x14]
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	adc edx, esi
	]], 0x427677 - 0x427651)
	nop2(0x427683, 0x427689)
	hook(new_code or 0x427651, function(d)
		local mastery, backup = u4[d.ebp - 0xC], d.eax
		local power = {}
		power[1] = MT.SpellsExtra[46]["Var3" .. select(mastery, "Normal", "Expert", "Master", "GM")] or 1
		player_spell_var(d, 3, power)
		d.eax = MT.SpellsExtra[46]["Var4" .. select(mastery, "Normal", "Expert", "Master", "GM")] or 5
		player_spell_var(d, 4)
		u4[d.ebp - 0x4] = floor(power[1] * d.edi) + d.eax
		d.eax = backup
		player_spell_var(d, 2)
	end)
	hook((new_code or 0x427651) + 0xD, player_spell_var1)

	-------- 47: Fate --------
	new_code = asmpatch(0x429ADA, [[
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov ecx, ]] .. (MT.SpellsExtra[47].Var1GM or 0) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[47].Var2GM or 300) .. [[;
	mov dword ptr [ebp - 0x4], ]] .. (MT.SpellsExtra[47].Var4GM or 0) .. [[;
	mov dword ptr [ebp - 0x18], ]] .. (MT.SpellsExtra[47].Var3GM or 6) .. [[;
	jmp @end
	@master:
	mov ecx, ]] .. (MT.SpellsExtra[47].Var1Master or 0) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[47].Var2Master or 300) .. [[;
	mov dword ptr [ebp - 0x4], ]] .. (MT.SpellsExtra[47].Var4Master or 0) .. [[;
	mov dword ptr [ebp - 0x18], ]] .. (MT.SpellsExtra[47].Var3Master or 4) .. [[;
	jmp @end
	@expert:
	mov ecx, ]] .. (MT.SpellsExtra[47].Var1Expert or 0) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[47].Var2Expert or 300) .. [[;
	mov dword ptr [ebp - 0x4], ]] .. (MT.SpellsExtra[47].Var4Expert or 0) .. [[;
	mov dword ptr [ebp - 0x18], ]] .. (MT.SpellsExtra[47].Var3Expert or 2) .. [[;
	jmp @end
	@normal:
	mov ecx, ]] .. (MT.SpellsExtra[47].Var1Normal or 0) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[47].Var2Normal or 300) .. [[;
	mov dword ptr [ebp - 0x4], ]] .. (MT.SpellsExtra[47].Var4Normal or 0) .. [[;
	mov dword ptr [ebp - 0x18], ]] .. (MT.SpellsExtra[47].Var3Normal or 1) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 0x14], eax
	mov dword ptr [ebp - 0x10], esi
	mov eax, ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add dword ptr [ebp - 0x14], eax
	adc dword ptr [ebp - 0x10], edx
	mov eax, dword ptr [ebp - 0x4]
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 0x4], eax
	mov eax, dword ptr [ebp - 0x18]
	nop
	nop
	nop
	nop
	nop
	imul edi
	add dword ptr [ebp - 0x4], eax
	]], 0x429B05 - 0x429ADA)
	hook((new_code or 0x429ADA) + 0x6D, player_spell_var2)
	hook((new_code or 0x429ADA) + 0x7A, player_spell_var1)
	hook((new_code or 0x429ADA) + 0x8A, player_spell_var4)
	hook((new_code or 0x429ADA) + 0x95, player_spell_var3)
	asmpatch(0x429B3D, "fild qword ptr [ebp - 0x14]")
	asmpatch(0x429B4A, "fmul dword ptr [0x4E8568]")
	asmpatch(0x429BBC, "fild qword ptr [ebp - 0x14]")
	asmpatch(0x429BC6, "fmul dword ptr [0x4E8568]")

	-------- 48: Turn Undead --------
	new_code = asmpatch(0x429E64, [[
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[48].Var2GM or 180) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[48].Var1GM or 300) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[48].Var2Master or 180) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[48].Var1Master or 300) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[48].Var2Expert or 180) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[48].Var1Expert or 180) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[48].Var2Normal or 180) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[48].Var1Normal or 60) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 4], eax
	mov eax, ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, dword ptr [ebp - 4]
	adc edx, esi
	]], 0x429E81 - 0x429E64)
	hook((new_code or 0x429E64) + 0x35, player_spell_var2)
	hook((new_code or 0x429E64) + 0x3F, player_spell_var1)
	nop(0x429E87, 1)

	-------- 49: Remove Curse --------
	asmpatch(0x429C04, [[
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov ecx, ]] .. (MT.SpellsExtra[49].Var1GM or 0) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[49].Var2GM or 0) .. [[;
	jmp @end
	@master:
	mov ecx, ]] .. (MT.SpellsExtra[49].Var1Master or 86400) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[49].Var2Master or 0) .. [[;
	jmp @end
	@expert:
	mov ecx, ]] .. (MT.SpellsExtra[49].Var1Expert or 3600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[49].Var2Expert or 0) .. [[;
	jmp @end
	@normal:
	mov ecx, ]] .. (MT.SpellsExtra[49].Var1Normal or 180) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[49].Var2Normal or 0) .. [[;
	@end:
	]])
	new_code = asmpatch(0x429C09, [[
	nop
	nop
	nop
	nop
	nop
	push eax
	mov eax, ecx
	pop ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	mov dword ptr [ebp - 4], eax
	]], 0x429C22 - 0x429C09)
	hook(new_code or 0x429C09, player_spell_var2)
	hook((new_code or 0x429C09) + 0x9, player_spell_var1)
	asmpatch(0x429C51, "cmp dword ptr [ebp - 4], 0")

	-------- 50: Preservation --------
	new_code = asmpatch(0x429CDF, [[
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[50].Var2GM or 3600) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[50].Var1GM or 900) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[50].Var2Master or 3600) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[50].Var1Master or 300) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[50].Var2Expert or 3600) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[50].Var1Expert or 300) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[50].Var2Normal or 1800) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[50].Var1Normal or 60) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 4], eax
	mov eax, ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, dword ptr [ebp - 4]
	adc edx, esi
	]], 0x429CFB - 0x429CDF)
	hook((new_code or 0x429CDF) + 0x35, player_spell_var2)
	hook((new_code or 0x429CDF) + 0x3F, player_spell_var1)
	nop(0x429D01, 1)

	-------- 52: Spirit Lash --------
	asmpatch(0x42788D, [[
	mov eax, edi
	dec eax
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[52].Var1GM or 256) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[52].Var1Master or 256) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[52].Var1Expert or 256) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[52].Var1Normal or 512) .. [[;
	@end:
	]])
	nop2(0x427892, 0x427899)
	hook(0x427892, player_spell_var1)

	-------- 53: Raise Dead --------
	new_code = asmpatch(0x42A041, [[
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[53].Var2GM or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[53].Var1GM or 0) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[53].Var2Master or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[53].Var1Master or 86400) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[53].Var2Expert or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[53].Var1Expert or 3600) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[53].Var2Normal or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[53].Var1Normal or 180) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 4], eax
	mov eax, ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add dword ptr [ebp - 4], eax
	]], 0x42A057 - 0x42A041)
	hook((new_code or 0x42A041) + 0x35, player_spell_var2)
	hook((new_code or 0x42A041) + 0x3F, player_spell_var1)
	asmpatch(0x42A093, "cmp dword ptr [ebp - 0x4], esi")

	-------- 54: Shared Life --------
	new_code = asmpatch(0x42A148, [[
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[54].Var1GM or 4) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[54].Var1Master or 3) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[54].Var1Expert or 2) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[54].Var1Normal or 1) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	imul edi
	mov edi, eax
	]], 0x42A158 - 0x42A148)
	hook((new_code or 0x42A148) + 0x21, player_spell_var1)

	-------- 55: Resurrection --------
	new_code = asmpatch(0x42A29B, [[
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[55].Var2GM or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[55].Var1GM or 0) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[55].Var2Master or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[55].Var1Master or 86400) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[55].Var2Expert or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[55].Var1Expert or 3600) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[55].Var2Normal or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[55].Var1Normal or 180) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 4], eax
	mov eax, ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add dword ptr [ebp - 4], eax
	]], 0x42A2C4 - 0x42A29B)
	hook((new_code or 0x42A29B) + 0x36, player_spell_var2)
	hook((new_code or 0x42A29B) + 0x40, player_spell_var1)
	asmpatch(0x42A338, "cmp dword ptr [ebp - 0x4], esi")

	-------- 57: Remove Fear --------
	new_code = asmpatch(0x42A512, [[
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[57].Var2GM or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[57].Var1GM or 0) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[57].Var2Master or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[57].Var1Master or 86400) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[57].Var2Expert or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[57].Var1Expert or 3600) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[57].Var2Normal or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[57].Var1Normal or 180) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 4], eax
	mov eax, ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	mov edi, eax
	add edi, dword ptr [ebp - 4]
	]], 0x42A534 - 0x42A512)
	hook((new_code or 0x42A512) + 0x35, player_spell_var2)
	hook((new_code or 0x42A512) + 0x3F, player_spell_var1)
	asmpatch(0x42A584, "cmp edi, esi")

	-------- 60: Charm --------
	asmpatch(0x427055, [[
	dec eax
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov ecx, ]] .. (MT.SpellsExtra[60].Var1GM or 0) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[60].Var2GM or 0x1BAF800) .. [[;
	jmp @end
	@master:
	mov ecx, ]] .. (MT.SpellsExtra[60].Var1Master or 600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[60].Var2Master or 0) .. [[;
	jmp @end
	@expert:
	mov ecx, ]] .. (MT.SpellsExtra[60].Var1Expert or 300) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[60].Var2Expert or 0) .. [[;
	jmp @end
	@normal:
	mov ecx, ]] .. (MT.SpellsExtra[60].Var1Normal or 150) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[60].Var2Normal or 0) .. [[;
	@end:
	]])
	new_code = asmpatch(0x42705C, [[
	nop
	nop
	nop
	nop
	nop
	push eax
	mov eax, ecx
	pop ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	adc edx, esi
	]], 0x427087 - 0x42705C)
	hook(new_code or 0x42705C, player_spell_var2)
	hook((new_code or 0x42705C) + 0x9, player_spell_var1)

	-------- 61: Cure Paralysis --------
	new_code = asmpatch(0x42A45E, [[
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[61].Var2GM or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[61].Var1GM or 0) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[61].Var2Master or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[61].Var1Master or 86400) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[61].Var2Expert or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[61].Var1Expert or 3600) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[61].Var2Normal or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[61].Var1Normal or 180) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 4], eax
	mov eax, ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	mov edi, eax
	add edi, dword ptr [ebp - 4]
	]], 0x42A478 - 0x42A45E)
	hook((new_code or 0x42A45E) + 0x35, player_spell_var2)
	hook((new_code or 0x42A45E) + 0x3F, player_spell_var1)
	asmpatch(0x42A4C8, "cmp edi, esi")

	-------- 62: Berserk --------
	new_code = asmpatch(0x42A799, [[
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[62].Var2GM or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[62].Var1GM or 3600) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[62].Var2Master or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[62].Var1Master or 600) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[62].Var2Expert or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[62].Var1Expert or 300) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[62].Var2Normal or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[62].Var1Normal or 60) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 4], eax
	mov eax, ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, dword ptr [ebp - 4]
	]], 0x42A7BD - 0x42A799)
	hook((new_code or 0x42A799) + 0x35, player_spell_var2)
	hook((new_code or 0x42A799) + 0x3F, player_spell_var1)

	-------- 63: Mass Fear --------
	new_code = asmpatch(0x42A992, [[
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[63].Var2GM or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[63].Var1GM or 300) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[63].Var2Master or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[63].Var1Master or 180) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[63].Var2Expert or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[63].Var1Expert or 120) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[63].Var2Normal or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[63].Var1Normal or 60) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 4], eax
	mov eax, ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, dword ptr [ebp - 4]
	]], 0x42A9AC - 0x42A992)
	hook((new_code or 0x42A992) + 0x35, player_spell_var2)
	hook((new_code or 0x42A992) + 0x3F, player_spell_var1)

	-------- 64: Cure Insanity --------
	new_code = asmpatch(0x42AB62, [[
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[64].Var2GM or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[64].Var1GM or 0) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[64].Var2Master or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[64].Var1Master or 86400) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[64].Var2Expert or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[64].Var1Expert or 3600) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[64].Var2Normal or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[64].Var1Normal or 180) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 4], eax
	mov eax, ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add dword ptr [ebp - 4], eax
	]], 0x42AB78 - 0x42AB62)
	hook((new_code or 0x42AB62) + 0x35, player_spell_var2)
	hook((new_code or 0x42AB62) + 0x3F, player_spell_var1)
	asmpatch(0x42ABF1, "cmp dword ptr [ebp - 0x4], esi")

	-------- 66: Enslave --------
	new_code = asmpatch(0x42A8AC, [[
	mov eax, dword ptr [ebp - 0xC]
	dec eax
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[66].Var2GM or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[66].Var1GM or 600) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[66].Var2Master or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[66].Var1Master or 180) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[66].Var2Expert or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[66].Var1Expert or 120) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[66].Var2Normal or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[66].Var1Normal or 60) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 4], eax
	mov eax, ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add dword ptr [ebp - 4], eax
	mov ecx, dword ptr [ebp - 0x30]
	]], 0x42A8BA - 0x42A8AC)
	hook((new_code or 0x42A8AC) + 0x3A, player_spell_var2)
	hook((new_code or 0x42A8AC) + 0x44, player_spell_var1)

	-------- 67: Cure Weakness --------
	new_code = asmpatch(0x42ADEC, [[
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[67].Var2GM or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[67].Var1GM or 0) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[67].Var2Master or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[67].Var1Master or 86400) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[67].Var2Expert or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[67].Var1Expert or 3600) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[67].Var2Normal or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[67].Var1Normal or 180) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 4], eax
	mov eax, ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add dword ptr [ebp - 4], eax
	]], 0x42AE12 - 0x42ADEC)
	hook((new_code or 0x42ADEC) + 0x35, player_spell_var2)
	hook((new_code or 0x42ADEC) + 0x3F, player_spell_var1)
	asmpatch(0x42AE61, "cmp dword ptr [ebp - 0x4], esi")

	-------- 68: Heal --------
	new_code = asmpatch(0x42AEAB, [[
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[68].Var2GM or 5) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[68].Var1GM or 5) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[68].Var2Master or 5) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[68].Var1Master or 4) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[68].Var2Expert or 5) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[68].Var1Expert or 3) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[68].Var2Normal or 5) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[68].Var1Normal or 2) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 4], eax
	mov eax, ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	mov edi, eax
	add edi, dword ptr [ebp - 4]
	]], 0x42AECC - 0x42AEAB)
	hook((new_code or 0x42AEAB) + 0x35, player_spell_var2)
	hook((new_code or 0x42AEAB) + 0x3F, player_spell_var1)

	-------- 71: Regeneration --------
	asmpatch(0x427385, [[
	mov eax, dword ptr [ebp - 0xC]
	dec eax
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov ecx, ]] .. (MT.SpellsExtra[71].Var1GM or 3600) .. [[;
	mov dword ptr [ebp - 0x18], ]] .. (MT.SpellsExtra[71].Var2GM or 0) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[71].Var3GM or 4) .. [[;
	jmp @end
	@master:
	mov ecx, ]] .. (MT.SpellsExtra[71].Var1Master or 3600) .. [[;
	mov dword ptr [ebp - 0x18], ]] .. (MT.SpellsExtra[71].Var2Master or 0) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[71].Var3Master or 3) .. [[;
	jmp @end
	@expert:
	mov ecx, ]] .. (MT.SpellsExtra[71].Var1Expert or 3600) .. [[;
	mov dword ptr [ebp - 0x18], ]] .. (MT.SpellsExtra[71].Var2Expert or 0) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[71].Var3Expert or 2) .. [[;
	jmp @end
	@normal:
	mov ecx, ]] .. (MT.SpellsExtra[71].Var1Normal or 3600) .. [[;
	mov dword ptr [ebp - 0x18], ]] .. (MT.SpellsExtra[71].Var2Normal or 0) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[71].Var3Normal or 1) .. [[;
	@end:
	]])
	new_code = asmpatch(0x42738D, [[
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 4], eax
	mov eax, dword ptr [ebp - 0x18]
	nop
	nop
	nop
	nop
	nop
	push eax
	mov eax, ecx
	pop ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	adc edx, esi
	mov dword ptr [ebp - 0x14], eax
	mov dword ptr [ebp - 0x10], edx
	]], 0x4273C5 - 0x42738D)
	hook(new_code or 0x42738D, player_spell_var3)
	hook((new_code or 0x42738D) + 0xB, player_spell_var2)
	hook((new_code or 0x42738D) + 0x14, player_spell_var1)

	-------- 72: Cure Poison --------
	new_code = asmpatch(0x42AF78, [[
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[72].Var2GM or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[72].Var1GM or 0) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[72].Var2Master or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[72].Var1Master or 86400) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[72].Var2Expert or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[72].Var1Expert or 3600) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[72].Var2Normal or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[72].Var1Normal or 180) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 4], eax
	mov eax, ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add dword ptr [ebp - 4], eax
	]], 0x42AF96 - 0x42AF78)
	hook((new_code or 0x42AF78) + 0x35, player_spell_var2)
	hook((new_code or 0x42AF78) + 0x3F, player_spell_var1)
	asmpatch(0x42B00D, "cmp dword ptr [ebp - 0x4], esi")

	-------- 73: Hammerhands --------
	new_code = asmpatch(0x42B170, [[
	push ecx
	mov eax, dword ptr [ebp - 0xC]
	dec eax
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[73].Var1GM or 3600) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[73].Var2GM or 0) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[73].Var1Master or 3600) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[73].Var2Master or 0) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[73].Var1Expert or 600) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[73].Var2Expert or 0) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[73].Var1Normal or 300) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[73].Var2Normal or 0) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	imul edi
	mov dword ptr [ebp - 0x14], eax
	mov dword ptr [ebp - 0x10], edx
	mov eax, ecx
	nop
	nop
	nop
	nop
	nop
	add dword ptr [ebp - 0x14], eax
	adc dword ptr [ebp - 0x10], esi
	pop ecx
	]], 0x42B17F - 0x42B170)
	hook((new_code or 0x42B170) + 0x3B, player_spell_var1)
	hook((new_code or 0x42B170) + 0x4A, player_spell_var2)

	-------- 74: Cure Disease --------
	new_code = asmpatch(0x42B2FA, [[
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[74].Var2GM or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[74].Var1GM or 0) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[74].Var2Master or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[74].Var1Master or 86400) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[74].Var2Expert or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[74].Var1Expert or 3600) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[74].Var2Normal or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[74].Var1Normal or 180) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 4], eax
	mov eax, ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add dword ptr [ebp - 4], eax
	]], 0x42B310 - 0x42B2FA)
	hook((new_code or 0x42B2FA) + 0x35, player_spell_var2)
	hook((new_code or 0x42B2FA) + 0x3F, player_spell_var1)
	asmpatch(0x42B387, "cmp dword ptr [ebp - 0x4], esi")

	-------- 75: Protection from Magic --------
	new_code = asmpatch(0x42B0C7, [[
	mov eax, dword ptr [ebp - 0xC]
	dec eax
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[75].Var2GM or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[75].Var1GM or 3600) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[75].Var2Master or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[75].Var1Master or 3600) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[75].Var2Expert or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[75].Var1Expert or 600) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[75].Var2Normal or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[75].Var1Normal or 300) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	push eax
	mov eax, ecx
	pop ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	adc edx, esi
	mov ecx, dword ptr [ebp - 0x1C]
	]], 0x42B0D6 - 0x42B0C7)
	hook((new_code or 0x42B0C7) + 0x3A, function(d)
		local mastery = u4[d.ebp - 0xC]
		local power = {}
		power[1] = MT.SpellsExtra[75]["Var4" .. select(mastery, "Normal", "Expert", "Master", "GM")] or 0
		player_spell_var(d, 4, power)
		power[2] = power[1]
		power[1] = MT.SpellsExtra[75]["Var3" .. select(mastery, "Normal", "Expert", "Master", "GM")] or 1
		player_spell_var(d, 3, power)
		-- check for being not lower than 1
		power[2] = floor(power[1] * d.edi) + power[2]
		if power[2] == 0 and d.edi > 0 then
			power[2] = 1
		end
		u4[d.ebp - 0x4] = power[2]
		power[1] = MT.SpellsExtra[75]["Var5" .. select(mastery, "Normal", "Expert", "Master", "GM")] or mastery
		player_spell_var(d, 5, power)
		u4[d.ebp - 0x2C] = power[1]
		player_spell_var(d, 2)
	end)
	hook((new_code or 0x42B0C7) + 0x43, player_spell_var1)
	-- Fix caster, set adjusted Skill and Power
	nop(0x42B12B, 1)
	asmpatch(0x42B12D, [[
	push eax
	push esi
	push dword ptr [ebp - 0x4]
	push dword ptr [ebp - 0x2C]
	]])

	-------- 77: Power Cure --------
	new_code = asmpatch(0x42B444, [[
	push ecx
	mov eax, dword ptr [ebp - 0xC]
	dec eax
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[77].Var2GM or 10) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[77].Var1GM or 5) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[77].Var2Master or 10) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[77].Var1Master or 3) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[77].Var2Expert or 10) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[77].Var1Expert or 2) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[77].Var2Normal or 10) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[77].Var1Normal or 1) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 4], eax
	mov eax, ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add dword ptr [ebp - 4], eax
	pop ecx
	]], 0x42B44B - 0x42B444)
	hook((new_code or 0x42B444) + 0x3B, player_spell_var2)
	hook((new_code or 0x42B444) + 0x45, player_spell_var1)

	-------- 81: Paralyze --------
	new_code = asmpatch(0x426EB4, [[
	mov eax, dword ptr [ebp - 0xC]
	dec eax
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov ecx, ]] .. (MT.SpellsExtra[81].Var1GM or 180) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[81].Var2GM or 0) .. [[;
	jmp @end
	@master:
	mov ecx, ]] .. (MT.SpellsExtra[81].Var1Master or 180) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[81].Var2Master or 0) .. [[;
	jmp @end
	@expert:
	mov ecx, ]] .. (MT.SpellsExtra[81].Var1Expert or 180) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[81].Var2Expert or 0) .. [[;
	jmp @end
	@normal:
	mov ecx, ]] .. (MT.SpellsExtra[81].Var1Normal or 180) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[81].Var2Normal or 0) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	push eax
	mov eax, ecx
	pop ecx
	nop
	nop
	nop
	nop
	nop
	imul edi, eax
	add edi, ecx
	]])
	hook((new_code or 0x426EB4) + 0x3A, player_spell_var2)
	hook((new_code or 0x426EB4) + 0x43, player_spell_var1)
	asmpatch(0x426EC6, "fmul dword ptr [0x4E8568]")

	-------- 82: Summon Wisp --------
	asmpatch(0x42B6DB, [[
	dec eax
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[82].Var3GM or 0) .. [[;
	mov dword ptr [ebp - 0x4], ]] .. (MT.SpellsExtra[82].Var4GM or 5) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[82].Var2GM or 0) .. [[;
	mov dword ptr [ebp - 0x18], ]] .. (MT.SpellsExtra[82].Var1GM or 900) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[82].Var3Master or 0) .. [[;
	mov dword ptr [ebp - 0x4], ]] .. (MT.SpellsExtra[82].Var4GM or 3) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[82].Var2Master or 0) .. [[;
	mov dword ptr [ebp - 0x18], ]] .. (MT.SpellsExtra[82].Var1Master or 900) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[82].Var3Expert or 0) .. [[;
	mov dword ptr [ebp - 0x4], ]] .. (MT.SpellsExtra[82].Var4GM or 1) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[82].Var2Expert or 0) .. [[;
	mov dword ptr [ebp - 0x18], ]] .. (MT.SpellsExtra[82].Var1Expert or 300) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[82].Var3Normal or 0) .. [[;
	mov dword ptr [ebp - 0x4], ]] .. (MT.SpellsExtra[82].Var4GM or 1) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[82].Var2Normal or 0) .. [[;
	mov dword ptr [ebp - 0x18], ]] .. (MT.SpellsExtra[82].Var1Normal or 60) .. [[;
	@end:
	]])

	new_code = asmpatch(0x42B6E0, [[
	nop
	nop
	nop
	nop
	nop
	mov dword ptr []] .. MO.SummonType .. [[], eax
	mov eax, dword ptr [ebp - 0x4]
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 0x4], eax
	mov eax, ecx
	nop
	nop
	nop
	nop
	nop
	mov ecx, eax
	mov eax, dword ptr [ebp - 0x18]
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	]], 0x42B716 - 0x42B6E0)
	hook((new_code or 0x42B6E0), player_spell_var3)
	hook((new_code or 0x42B6E0) + 0xD, player_spell_var4)
	hook((new_code or 0x42B6E0) + 0x17, player_spell_var2)
	hook((new_code or 0x42B6E0) + 0x23, player_spell_var1)

	-- Summon familiar (0x44D1C3)
	asmpatch(0x44D1D5, [[
	mov ecx, 0x61C534
	mov eax, dword ptr []] .. MO.SummonType .. [[]
	test eax, eax
	jle @std
	cmp eax, 651 ; Game.MonstersTxt.high
	jg @std
	dec eax
	mov edi, eax
	jmp absolute 0x44D1E9
	@std:
	cmp edx, 4
	]])

	-------- 83: Day of the Gods --------
	new_code = asmpatch(0x42B7A6, [[
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[83].Var2GM or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[83].Var1GM or 7200) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[83].Var2Master or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[83].Var1Master or 10800) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[83].Var2Expert or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[83].Var1Expert or 14400) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[83].Var2Normal or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[83].Var1Normal or 18000) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	push eax
	mov eax, ecx
	pop ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	adc edx, esi
	]], 0x42B7D9 - 0x42B7A6)
	hook((new_code or 0x42B7A6) + 0x35, function(d)
		local mastery, backup = u4[d.ebp - 0xC], d.eax
		local power = {}
		power[1] = MT.SpellsExtra[83]["Var3" .. select(mastery, "Normal", "Expert", "Master", "GM")]
			or select(mastery, 2, 3, 4, 5)
		player_spell_var(d, 3, power)
		power[2] = power[1]
		power[1] = MT.SpellsExtra[83]["Var4" .. select(mastery, "Normal", "Expert", "Master", "GM")] or 10
		player_spell_var(d, 4, power)
		-- check for being not lower than 1
		power[2] = floor(power[2] * d.edi) + power[1]
		if power[2] == 0 and d.edi > 0 then
			power[2] = 1
		end
		u4[d.ebp - 0x4] = power[2]
		d.eax = backup
		player_spell_var(d, 2)
	end)
	hook((new_code or 0x42B7A6) + 0x3E, player_spell_var1)
	nop(0x42B7DF, 1)
	asmpatch(0x42B7E6, "mov edi, dword ptr [ebp - 0x4]")
	-- TODO: fix caster?

	-------- 85: Day of Protection --------
	new_code = asmpatch(0x42B9F8, [[
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[85].Var2GM or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[85].Var1GM or 7200) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[85].Var2Master or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[85].Var1Master or 10800) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[85].Var2Expert or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[85].Var1Expert or 14400) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[85].Var2Normal or 0) .. [[;
	mov ecx, ]] .. (MT.SpellsExtra[85].Var1Normal or 18000) .. [[;
	@end:
	nop
	nop
	nop
	nop
	nop
	push eax
	mov eax, ecx
	pop ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	adc edx, esi
	]], 0x42BA25 - 0x42B9F8)
	hook((new_code or 0x42B9F8) + 0x35, function(d)
		local mastery = u4[d.ebp - 0xC]
		local power = {}
		power[1] = MT.SpellsExtra[85]["Var3" .. select(mastery, "Normal", "Expert", "Master", "GM")]
			or select(mastery, 2, 3, 4, 5)
		player_spell_var(d, 3, power)
		power[2] = power[1]
		power[1] = MT.SpellsExtra[85]["Var4" .. select(mastery, "Normal", "Expert", "Master", "GM")] or 0
		player_spell_var(d, 4, power)
		-- check for being not lower than 1
		power[2] = floor(power[2] * d.edi) + power[1]
		if power[2] == 0 and d.edi > 0 then
			power[2] = 1
		end
		u4[d.ebp - 0x4] = power[2]
		player_spell_var(d, 2)
	end)
	hook((new_code or 0x42B9F8) + 0x3E, player_spell_var1)
	nop(0x42BA2B, 1)

	-------- 86: Hour of Power --------
	asmpatch(0x42BC1A, [[
	push dword ptr [ebp - 0x8]
	mov ecx, dword ptr [ebp - 0x1C]
	call absolute 0x425B1A
	test eax, eax
	jz absolute 0x42D3AB
	mov eax, dword ptr [ebp - 0xC]
	dec eax
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov ecx, ]] .. (MT.SpellsExtra[86].Var1GM or 4500) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[86].Var2GM or 60) .. [[;
	mov dword ptr [ebp - 0x38], ]] .. (MT.SpellsExtra[86].Var4GM or 3600) .. [[;
	mov dword ptr [ebp - 0x18], ]] .. (MT.SpellsExtra[86].Var3GM or 1200) .. [[;
	jmp @end
	@master:
	mov ecx, ]] .. (MT.SpellsExtra[86].Var1Master or 3600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[86].Var2Master or 60) .. [[;
	mov dword ptr [ebp - 0x38], ]] .. (MT.SpellsExtra[86].Var4Master or 3600) .. [[;
	mov dword ptr [ebp - 0x18], ]] .. (MT.SpellsExtra[86].Var3Master or 720) .. [[;
	jmp @end
	@expert:
	mov ecx, ]] .. (MT.SpellsExtra[86].Var1Expert or 1200) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[86].Var2Expert or 60) .. [[;
	mov dword ptr [ebp - 0x38], ]] .. (MT.SpellsExtra[86].Var4Expert or 3600) .. [[;
	mov dword ptr [ebp - 0x18], ]] .. (MT.SpellsExtra[86].Var3Expert or 240) .. [[;
	jmp @end
	@normal:
	mov ecx, ]] .. (MT.SpellsExtra[86].Var1Normal or 1200) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[86].Var2Normal or 60) .. [[;
	mov dword ptr [ebp - 0x38], ]] .. (MT.SpellsExtra[86].Var4Normal or 3600) .. [[;
	mov dword ptr [ebp - 0x18], ]] .. (MT.SpellsExtra[86].Var3Normal or 240) .. [[;
	@end:
	]])

	new_code = asmpatch(0x42BC1F, [[
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 0x14], eax
	mov dword ptr [ebp - 0x10], esi
	mov eax, ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add dword ptr [ebp - 0x14], eax
	adc dword ptr [ebp - 0x10], edx
	mov eax, dword ptr [ebp - 0x38]
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 0x38], eax
	mov dword ptr [ebp - 0x34], esi
	mov eax, dword ptr [ebp - 0x18]
	nop
	nop
	nop
	nop
	nop
	imul edi
	add dword ptr [ebp - 0x38], eax
	adc dword ptr [ebp - 0x34], edx
	fild qword ptr [ebp - 0x14]
	fmul dword ptr [0x4E8568]
	call absolute 0x4D967C
	add eax, dword ptr [0xB20EBC]
	adc edx, dword ptr [0xB20EC0]
	mov dword ptr [ebp - 0x14], eax
	mov dword ptr [ebp - 0x10], edx
	fild qword ptr [ebp - 0x38]
	fmul dword ptr [0x4E8568]
	call absolute 0x4D967C
	add eax, dword ptr [0xB20EBC]
	adc edx, dword ptr [0xB20EC0]
	mov dword ptr [ebp - 0x38], eax
	mov dword ptr [ebp - 0x34], edx

	mov dword ptr [ebp - 0x2C], esi
	cmp dword ptr [ebp - 0xC], 1
	jg @party
	movzx eax, word ptr [ebx + 4]
	mov dword ptr [ebp - 0x8], eax
	mov dword ptr [ebp - 0x24], eax
	jmp @loop
	@party:
	mov ecx, 0xB20E90
	call absolute 0x42D776
	mov dword ptr [ebp - 0x8], esi
	mov dword ptr [ebp - 0x24], eax
	mov eax, ]] .. (MF.GtSettingNum(MM.SpellsHourHasteSingleWeakNonFail, 0) and 1 or 0) .. [[;
	test eax, eax
	jnz @loop
	@check:
	push dword ptr [ebp - 0x8]
	mov ecx, 0xB20E90
	call absolute 0x4026F4
	mov ecx, dword ptr [eax + 0x8]
	or ecx, dword ptr [eax +0xC]
	jz @ff1
	inc dword ptr [ebp - 0x2C]
	@ff1:
	inc dword ptr [ebp - 0x8]
	mov eax, dword ptr [ebp - 0x24]
	cmp eax, dword ptr [ebp - 0x8]
	jg @check
	mov dword ptr [ebp - 0x8], esi

	@loop:
	push dword ptr [ebp - 0x8]
	mov ecx, 0xB20E90
	call absolute 0x4026F4
	mov edi, eax

	mov eax, ]] .. (MF.GtSettingNum(MM.SpellsBuffSkipNonConscious, 0) and 1 or 0) .. [[;
	test eax, eax
	jz @ff2
	mov ecx, edi
	call absolute 0x491514
	test eax, eax
	jz @next

	@ff2:
	push dword ptr [ebp - 0x8]
	movzx eax, word ptr [ebx]
	push eax
	mov ecx, dword ptr [0x75CE00]
	call absolute 0x42D747
	mov ecx, eax
	call absolute 0x4A6FCE

	push esi
	push esi
	push dword ptr [ebp - 0x4]
	push dword ptr [ebp - 0xC]
	push dword ptr [ebp - 0x10]
	push dword ptr [ebp - 0x14]
	mov ecx, edi
	add ecx, 0x1A44
	call absolute 0x455D97

	push esi
	push esi
	push dword ptr [ebp - 0x4]
	push dword ptr [ebp - 0xC]
	push dword ptr [ebp - 0x10]
	push dword ptr [ebp - 0x14]
	mov ecx, edi
	add ecx, 0x1AB4
	call absolute 0x455D97

	push esi
	push esi
	push dword ptr [ebp - 0x4]
	push dword ptr [ebp - 0xC]
	push dword ptr [ebp - 0x10]
	push dword ptr [ebp - 0x14]
	mov ecx, edi
	add ecx, 0x1B04
	call absolute 0x455D97

	push esi
	push esi
	push dword ptr [ebp - 0x4]
	push dword ptr [ebp - 0xC]
	push dword ptr [ebp - 0x10]
	push dword ptr [ebp - 0x14]
	mov ecx, edi
	add ecx, 0x1B14
	call absolute 0x455D97

	mov eax, dword ptr [ebp - 0x2C]
	test eax, eax
	jnz @next

	mov eax, dword ptr [edi + 0x8]
	or eax, dword ptr [edi +0xC]
	jnz @next

	push esi
	push esi
	push dword ptr [ebp - 0x4]
	push dword ptr [ebp - 0xC]
	push dword ptr [ebp - 0x34]
	push dword ptr [ebp - 0x38]
	mov ecx, edi
	add ecx, 0x1AA4
	call absolute 0x455D97

	@next:
	inc dword ptr [ebp - 0x8]
	mov eax, dword ptr [ebp - 0x24]
	cmp eax, dword ptr [ebp - 0x8]
	jg @loop
	jmp absolute 0x42C200
	]], 0x42BDF4 - 0x42BC1F)
	hook(new_code or 0x42BC1F, function(d)
		local mastery = u4[d.ebp - 0xC]
		local power = {}
		power[1] = get_spell_var_value(86, 5, mastery, 1)
		player_spell_var(d, 5, power)
		power[2] = power[1]
		power[1] = get_spell_var_value(86, 6, mastery, 5)
		player_spell_var(d, 6, power)
		-- check for being not lower than 1
		power[2] = floor(power[2] * d.edi) + power[1]
		if power[2] == 0 and d.edi > 0 then
			power[2] = 1
		end
		u4[d.ebp - 0x4] = power[2]
		player_spell_var(d, 2)
	end)
	hook((new_code or 0x42BC1F) + 0xD, player_spell_var1)
	hook((new_code or 0x42BC1F) + 0x1D, player_spell_var4)
	hook((new_code or 0x42BC1F) + 0x2B, player_spell_var3)

	-------- 88: Divine Intervention --------
	asmpatch(0x42BDF7, [[
	dec eax
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov ecx, ]] .. (MT.SpellsExtra[88].Var1GM or 3) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[88].Var2GM or 10) .. [[;
	jmp @end
	@master:
	mov ecx, ]] .. (MT.SpellsExtra[88].Var1Master or 3) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[88].Var2Master or 10) .. [[;
	jmp @end
	@expert:
	mov ecx, ]] .. (MT.SpellsExtra[88].Var1Expert or 2) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[88].Var2Expert or 10) .. [[;
	jmp @end
	@normal:
	mov ecx, ]] .. (MT.SpellsExtra[88].Var1Normal or 1) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[88].Var2Normal or 10) .. [[;
	@end:
	]])
	new_code = asmpatch(0x42BDFC, [[
	test byte ptr [ebx + 0x9], 0x80
	jz @std
	xor eax, eax
	@std:
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 0x4], eax
	mov eax, ecx
	nop
	nop
	nop
	nop
	nop
	mov ecx, dword ptr [ebp - 0x1C]
	cmp byte ptr [ecx + 0x1D24], al
	]], 0x42BE0D - 0x42BDFC)
	hook((new_code or 0x42BDFC) + 0x8, player_spell_var2)
	hook((new_code or 0x42BDFC) + 0x12, player_spell_var1)
	nop(0x42BE16, 2)
	asmpatch(0x42BEB2, [[
	add esi, dword ptr [ebp - 0x4]
	cmp esi, 0x78
	]])
	asmpatch(0x42BEBA, [[
	add ecx, dword ptr [ebp - 0x4]
	mov word ptr [eax], cx
	]])
	-- do not increase casts count for special cast
	asmpatch(0x42BED3, [[
	test byte ptr [ebx + 0x9], 0x80
	jnz @end
	inc byte ptr [edx + 0x1D24]
	@end:
	]])

	-------- 89: Reanimate --------
	asmpatch(0x42BEE3, [[
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov ecx, ]] .. (MT.SpellsExtra[89].Var3GM or 50) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[89].Var4GM or 0) .. [[;
	jmp @end
	@master:
	mov ecx, ]] .. (MT.SpellsExtra[89].Var3Master or 40) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[89].Var4Master or 0) .. [[;
	jmp @end
	@expert:
	mov ecx, ]] .. (MT.SpellsExtra[89].Var3Expert or 30) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[89].Var4Expert or 0) .. [[;
	jmp @end
	@normal:
	mov ecx, ]] .. (MT.SpellsExtra[89].Var3Normal or 20) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[89].Var4Normal or 0) .. [[;
	@end:
	]])
	new_code = asmpatch(0x42BEE8, [[
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 0x34], eax
	mov eax, ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add dword ptr [ebp - 0x34], eax
	]], 0x42BEFF - 0x42BEE8)
	hook(new_code or 0x42BEE8, function(d)
		local mastery = u4[d.ebp - 0xC]
		local power = {}
		power[1] = get_spell_var_value(89, 1, mastery, {2, 3, 4, 5})
		player_spell_var(d, 1, power)
		power[2] = power[1]
		power[1] = get_spell_var_value(89, 2, mastery, 0)
		player_spell_var(d, 2, power)
		-- check for being not lower than 1
		power[2] = floor(power[2] * d.edi) + power[1]
		if power[2] == 0 and d.edi > 0 then
			power[2] = 1
		end
		u4[d.ebp - 0x4] = power[2]
		player_spell_var(d, 4)
	end)
	hook((new_code or 0x42BEE8) + 0xA, player_spell_var3)
	nop(0x42BF05, 3)
	asmpatch(0x42C0AD, [[
	mov eax, dword ptr [ebp - 0x34]
	cmp edx, eax
	jle @end
	mov word ptr [edi + 0x28], ax
	@end:
	]], 0x42C0C3 - 0x42C0AD)

	-------- 91: Vampiric Weapon --------
	asmpatch(0x42C0D7, [[
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov ecx, ]] .. (MT.SpellsExtra[91].Var1GM or 0) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[91].Var2GM or 0) .. [[;
	mov dword ptr [ebp - 0x4], ]] .. (MT.SpellsExtra[91].Var3GM or 16) .. [[;
	jmp @end
	@master:
	mov ecx, ]] .. (MT.SpellsExtra[91].Var1Master or 3600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[91].Var2Master or 0) .. [[;
	mov dword ptr [ebp - 0x4], ]] .. (MT.SpellsExtra[91].Var3Master or 16) .. [[;
	jmp @end
	@expert:
	mov ecx, ]] .. (MT.SpellsExtra[91].Var1Expert or 3600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[91].Var2Expert or 0) .. [[;
	mov dword ptr [ebp - 0x4], ]] .. (MT.SpellsExtra[91].Var3Expert or 16) .. [[;
	jmp @end
	@normal:
	mov ecx, ]] .. (MT.SpellsExtra[91].Var1Normal or 3600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[91].Var2Normal or 0) .. [[;
	mov dword ptr [ebp - 0x4], ]] .. (MT.SpellsExtra[91].Var3Normal or 16) .. [[;
	@end:
	]])
	new_code = asmpatch(0x42C0DE, [[
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 0x14], eax
	mov dword ptr [ebp - 0x10], esi
	mov eax, ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add dword ptr [ebp - 0x14], eax
	adc dword ptr [ebp - 0x10], edx
	mov eax, dword ptr [ebp - 0x4]
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 0x4], eax
	]], 0x42C100 - 0x42C0DE)
	hook(new_code or 0x42C0DE, player_spell_var2)
	hook((new_code or 0x42C0DE) + 0xD, player_spell_var1)
	hook((new_code or 0x42C0DE) + 0x1D, player_spell_var3)
	asmpatch(0x42C19D, [[
	mov edi, dword ptr [ebp - 0x18]
	mov eax, dword ptr [ebp - 0x4]
	mov dword ptr [edi + 0xC], eax
	mov eax, dword ptr [ebp - 0x14]
	or eax, dword ptr [ebp - 0x10]
	]], 0x42C1AB - 0x42C19D)

	-------- 93: Shrapmetal --------
	asmpatch(0x42C20F, [[
	dec eax
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[93].Var1GM or 9) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[93].Var1Master or 7) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[93].Var1Expert or 5) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[93].Var1Normal or 3) .. [[;
	@end:
	]])
	new_code = asmpatch(0x42C214, [[
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 0x4], eax
	]], 0x42C230 - 0x42C214)
	hook(new_code or 0x42C214, player_spell_var1)

	-------- 94: Control Undead --------
	asmpatch(0x42C3B4, [[
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov ecx, ]] .. (MT.SpellsExtra[94].Var1GM or 0) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[94].Var2GM or 29030400) .. [[;
	jmp @end
	@master:
	mov ecx, ]] .. (MT.SpellsExtra[94].Var1Master or 300) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[94].Var2Master or 0) .. [[;
	jmp @end
	@expert:
	mov ecx, ]] .. (MT.SpellsExtra[94].Var1Expert or 180) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[94].Var2Expert or 0) .. [[;
	jmp @end
	@normal:
	mov ecx, ]] .. (MT.SpellsExtra[94].Var1Normal or 60) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[94].Var2Normal or 0) .. [[;
	@end:
	]])
	new_code = asmpatch(0x42C3B9, [[
	nop
	nop
	nop
	nop
	nop
	push eax
	mov eax, ecx
	pop ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	adc edx, esi
	]], 0x42C3DE - 0x42C3B9)
	hook(new_code or 0x42C3B9, player_spell_var2)
	hook((new_code or 0x42C3B9) + 0x9, player_spell_var1)

	-------- 95: Pain Reflection --------
	asmpatch(0x42C57F, [[
	mov eax, dword ptr [ebp - 0xC]
	dec eax
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov ecx, ]] .. (MT.SpellsExtra[95].Var1GM or 60) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[95].Var2GM or 1800) .. [[;
	jmp @end
	@master:
	mov ecx, ]] .. (MT.SpellsExtra[95].Var1Master or 300) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[95].Var2Master or 3600) .. [[;
	jmp @end
	@expert:
	mov ecx, ]] .. (MT.SpellsExtra[95].Var1Expert or 300) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[95].Var2Expert or 3600) .. [[;
	jmp @end
	@normal:
	mov ecx, ]] .. (MT.SpellsExtra[95].Var1Normal or 900) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[95].Var2Normal or 3600) .. [[;
	@end:
	]])
	new_code = asmpatch(0x42C584, [[
	nop
	nop
	nop
	nop
	nop
	push eax
	mov eax, ecx
	pop ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	adc edx, esi
	]], 0x42C5A5 - 0x42C584)
	hook(new_code or 0x42C584, function(d)
		local mastery = u4[d.ebp - 0xC]
		local power = {}
		power[1] = get_spell_var_value(95, 3, mastery, 1)
		player_spell_var(d, 3, power)
		power[2] = power[1]
		power[1] = get_spell_var_value(95, 4, mastery, 5)
		player_spell_var(d, 4, power)
		-- check for being not lower than 1
		power[2] = floor(power[2] * d.edi) + power[1]
		if power[2] == 0 and d.edi > 0 then
			power[2] = 1
		end
		u4[d.ebp - 0x4] = power[2]
		player_spell_var(d, 2)
	end)
	hook((new_code or 0x42C584) + 0x9, player_spell_var1)
	asmpatch(0x42C5B4, "mov edi, dword ptr [ebp - 0x4]")

	-------- 98: Armageddon --------
	asmpatch(0x42C99E, [[
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov eax, ]] .. (MT.SpellsExtra[98].Var1GM or 4) .. [[;
	jmp @end
	@master:
	mov eax, ]] .. (MT.SpellsExtra[98].Var1Master or 3) .. [[;
	jmp @end
	@expert:
	mov eax, ]] .. (MT.SpellsExtra[98].Var1Expert or 2) .. [[;
	jmp @end
	@normal:
	mov eax, ]] .. (MT.SpellsExtra[98].Var1Normal or 1) .. [[;
	@end:
	]])
	new_code = asmpatch(0x42C9A3, [[
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 0x4], eax
	]], 0x42C9B4 - 0x42C9A3)
	hook(new_code or 0x42C9A3, player_spell_var1)
	-- Write caster, calc and write damage
	--   FIXME: spell queue values (spell and caster) are actually signed
	--   TODO: store caster somewhere in Party struct
	asmpatch(0x42C9F3, [[
	push eax
	movzx eax, word ptr [ebx + 2]
	shl eax, 3
	or eax, 4
	mov dword ptr []] .. MO.LastArmageddonCaster .. [[], eax
	mov dword ptr []] .. MO.CalcSpellDamageCaster .. [[], eax
	push esi
	push dword ptr [ebp - 0xC]
	mov edx, edi
	movzx ecx, word ptr [ebx]
	call absolute 0x438B05
	mov dword ptr [0xBB2E08], eax
	pop eax
	]])
	-- Don't increase damage by 50 second time
	nop(0x401B5F, 3)
	-- Set proper killer data
	asmpatch(0x401BB9, [[
	mov edx, dword ptr []] .. MO.LastArmageddonCaster .. [[]
	call absolute 0x402E78
	]])

	-------- 99: Souldrinker --------
	new_code = asmpatch(0x42C7D2, [[
	mov eax, 7
	nop
	nop
	nop
	nop
	nop
	imul edi, eax
	mov eax, 0x19
	nop
	nop
	nop
	nop
	nop
	add edi, eax
	]])
	hook(new_code + 5, function(d)
		local mastery = u4[d.ebp - 0xC]
		d.eax = get_spell_var_value(99, 1, mastery, d.eax)
		player_spell_var(d, 1)
	end)
	hook(new_code + 0x12, function(d)
		local mastery = u4[d.ebp - 0xC]
		d.eax = get_spell_var_value(99, 2, mastery, d.eax)
		player_spell_var(d, 2)
	end)

	-------- 100: Glamour --------
	asmpatch(0x42CAAD, [[
	dec eax
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov ecx, ]] .. (MT.SpellsExtra[100].Var1GM or 7200) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[100].Var2GM or 0) .. [[;
	jmp @end
	@master:
	mov ecx, ]] .. (MT.SpellsExtra[100].Var1Master or 3600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[100].Var2Master or 0) .. [[;
	jmp @end
	@expert:
	mov ecx, ]] .. (MT.SpellsExtra[100].Var1Expert or 300) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[100].Var2Expert or 0) .. [[;
	jmp @end
	@normal:
	mov ecx, ]] .. (MT.SpellsExtra[100].Var1Normal or 300) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[100].Var2Normal or 0) .. [[;
	@end:
	]])
	new_code = asmpatch(0x42CAB4, [[
	nop
	nop
	nop
	nop
	nop
	push eax
	mov eax, ecx
	pop ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	adc edx, esi
	]], 0x42CADD - 0x42CAB4)
	hook(new_code or 0x42CAB4, function(d)
		local mastery = u4[d.ebp - 0xC]
		local power = {}
		power[1] = get_spell_var_value(100, 3, mastery, 0.5)
		player_spell_var(d, 3, power)
		power[2] = power[1]
		power[1] = get_spell_var_value(100, 4, mastery, 2.5)
		player_spell_var(d, 4, power)
		-- check for being not lower than 1
		power[2] = floor(power[2] * d.edi + power[1])
		if power[2] == 0 and d.edi > 0 then
			power[2] = 1
		end
		u4[d.ebp - 0x4] = power[2]
		player_spell_var(d, 2)
	end)
	hook((new_code or 0x42CAB4) + 0x9, player_spell_var1)
	asmpatch(0x42CAF3, "mov edi, dword ptr [ebp - 0x4]")

	-------- 101: Travelers' Boon --------
	asmpatch(0x42CB57, [[
	dec eax
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov ecx, ]] .. (MT.SpellsExtra[101].Var1GM or 7200) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[101].Var2GM or 0) .. [[;
	mov dword ptr [ebp - 0x4], ]] .. (MT.SpellsExtra[101].Var3GM or 2) .. [[;
	jmp @end
	@master:
	mov ecx, ]] .. (MT.SpellsExtra[101].Var1Master or 3600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[101].Var2Master or 0) .. [[;
	mov dword ptr [ebp - 0x4], ]] .. (MT.SpellsExtra[101].Var3Master or 2) .. [[;
	jmp @end
	@expert:
	mov ecx, ]] .. (MT.SpellsExtra[101].Var1Expert or 1800) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[101].Var2Expert or 0) .. [[;
	mov dword ptr [ebp - 0x4], ]] .. (MT.SpellsExtra[101].Var3Expert or 2) .. [[;
	jmp @end
	@normal:
	mov ecx, ]] .. (MT.SpellsExtra[101].Var1Normal or 600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[101].Var2Normal or 0) .. [[;
	mov dword ptr [ebp - 0x4], ]] .. (MT.SpellsExtra[101].Var3Normal or 2) .. [[;
	@end:
	]])
	new_code = asmpatch(0x42CB5E, [[
	push eax
	mov eax, dword ptr [ebp - 0x4]
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 0x4], eax
	pop eax
	nop
	nop
	nop
	nop
	nop
	push eax
	mov eax, ecx
	pop ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	adc edx, esi
	]], 0x42CB87 - 0x42CB5E)
	hook((new_code or 0x42CB5E) + 0x4, player_spell_var3)
	hook((new_code or 0x42CB5E) + 0xD, player_spell_var2)
	hook((new_code or 0x42CB5E) + 0x16, player_spell_var1)
	asmpatch(0x42CBD9, [[
	fild qword ptr [ebp - 0x14]
	fmul dword ptr [0x4E8568]
	call absolute 0x4D967C
	add eax, dword ptr [0xB20EBC]
	adc edx, dword ptr [0xB20EC0]
	mov dword ptr [ebp - 0x38], eax
	mov dword ptr [ebp - 0x34], edx
	movsx eax, word ptr [ebx + 2]
	inc eax
	mov dword ptr [ebp - 0x18], eax
	push esi
	push eax
	push esi
	push dword ptr [ebp - 0x4]
	push dword ptr [ebp - 0x34]
	push dword ptr [ebp - 0x38]
	mov ecx, 0xB21788
	call absolute 0x455D97
	push esi
	push dword ptr [ebp - 0x18]
	push 3
	push dword ptr [ebp - 0x4]
	push dword ptr [ebp - 0x34]
	push dword ptr [ebp - 0x38]
	mov ecx, 0xB21838
	call absolute 0x455D97
	push esi
	push dword ptr [ebp - 0x18]
	push esi
	push dword ptr [ebp - 0x4]
	push dword ptr [ebp - 0x34]
	push dword ptr [ebp - 0x38]
	]], 0x42CC7D - 0x42CBD9)

	-------- 112: Levitate --------
	asmpatch(0x42CC8A, [[
	dec eax
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov ecx, ]] .. (MT.SpellsExtra[112].Var1GM or 10800) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[112].Var2GM or 0) .. [[;
	jmp @end
	@master:
	mov ecx, ]] .. (MT.SpellsExtra[112].Var1Master or 3600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[112].Var2Master or 0) .. [[;
	jmp @end
	@expert:
	mov ecx, ]] .. (MT.SpellsExtra[112].Var1Expert or 600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[112].Var2Expert or 0) .. [[;
	jmp @end
	@normal:
	mov ecx, ]] .. (MT.SpellsExtra[112].Var1Normal or 180) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[112].Var2Normal or 0) .. [[;
	@end:
	]])
	new_code = asmpatch(0x42CC91, [[
	nop
	nop
	nop
	nop
	nop
	push eax
	mov eax, ecx
	pop ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	adc edx, esi
	]], 0x42CCBA - 0x42CC91)
	hook(new_code or 0x42CC91, player_spell_var2)
	hook((new_code or 0x42CC91) + 0x9, player_spell_var1)

	-------- 114: Mistform --------
	asmpatch(0x42CD16, [[
	mov eax, dword ptr [ebp - 0xC]
	dec eax
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov ecx, ]] .. (MT.SpellsExtra[114].Var1GM or 600) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[114].Var2GM or 0) .. [[;
	jmp @end
	@master:
	mov ecx, ]] .. (MT.SpellsExtra[114].Var1Master or 60) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[114].Var2Master or 0) .. [[;
	jmp @end
	@expert:
	mov ecx, ]] .. (MT.SpellsExtra[114].Var1Expert or 30) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[114].Var2Expert or 0) .. [[;
	jmp @end
	@normal:
	mov ecx, ]] .. (MT.SpellsExtra[114].Var1Normal or 10) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[114].Var2Normal or 0) .. [[;
	@end:
	]])
	new_code = asmpatch(0x42CD1B, [[
	nop
	nop
	nop
	nop
	nop
	push eax
	mov eax, ecx
	pop ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	adc edx, esi
	]], 0x42CD2A - 0x42CD1B)
	hook(new_code or 0x42CD1B, player_spell_var2)
	hook((new_code or 0x42CD1B) + 0x9, player_spell_var1)

	-------- 122: Fear --------
	asmpatch(0x42CD86, [[
	mov eax, dword ptr [ebp - 0xC]
	dec eax
	dec eax
	jz @expert
	jl @normal
	dec eax
	jz @master
	mov ecx, ]] .. (MT.SpellsExtra[122].Var1GM or 300) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[122].Var2GM or 0) .. [[;
	jmp @end
	@master:
	mov ecx, ]] .. (MT.SpellsExtra[122].Var1Master or 300) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[122].Var2Master or 0) .. [[;
	jmp @end
	@expert:
	mov ecx, ]] .. (MT.SpellsExtra[122].Var1Expert or 300) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[122].Var2Expert or 0) .. [[;
	jmp @end
	@normal:
	mov ecx, ]] .. (MT.SpellsExtra[122].Var1Normal or 180) .. [[;
	mov eax, ]] .. (MT.SpellsExtra[122].Var2Normal or 0) .. [[;
	@end:
	]])
	new_code = asmpatch(0x42CD8C, [[
	nop
	nop
	nop
	nop
	nop
	push eax
	mov eax, ecx
	pop ecx
	nop
	nop
	nop
	nop
	nop
	imul edi
	add eax, ecx
	adc edx, esi
	]], 0x42CDA7 - 0x42CD8C)
	hook(new_code or 0x42CD8C, player_spell_var2)
	hook((new_code or 0x42CD8C) + 0x9, player_spell_var1)
	new_code = asmpatch(0x42CDF9, [[
	nop
	nop
	nop
	nop
	nop
	push eax
	]])
	hook(new_code or 0x42CDF9, function(d)
		local mastery = u4[d.ebp - 0xC]
		d.eax = get_spell_var_value(122, 3, mastery, 512)
		player_spell_var(d, 3)
	end)
	new_code = asmpatch(0x42CE0E, [[
	nop
	nop
	nop
	nop
	nop
	push eax
	]])
	hook(new_code or 0x42CE0E, function(d)
		local mastery = u4[d.ebp - 0xC]
		d.eax = get_spell_var_value(122, 4, mastery, 4096)
		player_spell_var(d, 4)
	end)

	-------- 125: Wing Buffet --------
	new_code = asmpatch(0x42D0F3, [[
	mov ecx, eax
	nop
	nop
	nop
	nop
	nop
	mov dword ptr [ebp - 0x4], eax
	push eax
	mov eax, ecx
	]])
	hook((new_code or 0x42D0F3) + 2, function(d)
		local mastery = u4[d.ebp - 0xC]
		d.eax = get_spell_var_value(125, 1, mastery, 2048)
		player_spell_var(d, 1)
	end)
	asmpatch(0x42D2AE, "push dword ptr [ebp - 0x4]")

	-------- Select target type --------
	asmpatch(0x425BC8, [[
	cmp ecx, 5
	jnz @shield
	mov ecx, dword ptr [ebp + 8]
	test ecx, ecx
	jnz absolute 0x425C11
	push 12
	jmp absolute ]] .. MO.SkillMasteryTarget2 .. [[;
	@shield:
	cmp ecx, 17
	jnz @stoneskin
	mov ecx, dword ptr [ebp + 8]
	test ecx, ecx
	jnz absolute 0x425C11
	push 13
	jmp absolute ]] .. MO.SkillMasteryTarget2 .. [[;
	@stoneskin:
	cmp ecx, 38
	jnz @heroism
	mov ecx, dword ptr [ebp + 8]
	test ecx, ecx
	jnz absolute 0x425C11
	push 15
	jmp absolute ]] .. MO.SkillMasteryTarget2 .. [[;
	@heroism:
	cmp ecx, 51
	jnz @hour
	mov ecx, dword ptr [ebp + 8]
	test ecx, ecx
	jnz absolute 0x425C11
	push 16
	jmp absolute ]] .. MO.SkillMasteryTarget2 .. [[;
	@hour:
	cmp ecx, 86
	jnz @std
	mov ecx, dword ptr [ebp + 8]
	test ecx, ecx
	jnz absolute 0x425C11
	push 19
	jmp absolute ]] .. MO.SkillMasteryTarget2 .. [[;
	@std:
	add ecx, 0xFFFFFFFE
	cmp ecx, 0x79
	]])
	new_code = asmpatch(0x425C5F, [[
	nop
	nop
	nop
	nop
	nop
	mov edi, 0x3CA
	]])
	hook(new_code, function(d)
		local t = {Spell = u4[d.ebp - 0x14], CasterSlot = u4[d.ebp - 0x10], Flags = u4[d.ebp + 0xC]}
		t.Caster = Party.PlayersIndexes[t.CasterSlot]
		events.call("SpellTargetType", t)
		u4[d.ebp + 0xC] = t.Flags
	end)

	-- Ctrl-click in spell book
	--   Action 86
	asmpatch(0x431F27, [[
	mov byte ptr []] .. MO.SpellKeyMods .. [[], 0
	push 0x11
	call dword ptr [ds:0x4E8280]
	test ah, ah
	jns @end
	or byte ptr []] .. MO.SpellKeyMods .. "], " .. spellflags1_ctrl .. [[;
	@end:
	mov eax, dword ptr [0x519350]
	]])
	--   Set flags
	asmpatch(0x425BBE, [[
	push eax
	mov al, byte ptr []] .. MO.SpellKeyMods .. [[]
	or byte ptr [ebp + 0xD], al
	mov byte ptr []] .. MO.SpellKeyMods .. [[], 0
	pop eax
	test byte ptr [ebp + 0xC], 0x10
	jnz absolute 0x425C5F
	]])

	-- Additional actions: 194
	new_code = asmpatch(0x42EE99, [[
	cmp eax, 0xBD
	jnz @end
	mov eax, dword ptr [esp + 0x10]
	nop
	nop
	nop
	nop
	nop
	movzx eax, byte ptr [0x51D818]
	cmp eax, ebx
	jl @first
	cmp eax, 0x32
	jl @second
	@first:
	xor eax, eax
	@second:
	imul eax, 0x1D28
	add eax, 0xB2187C
	movzx ecx, word ptr [0x51D81A]
	push ecx
	mov ecx, eax
	call absolute 0x425B1A
	jmp absolute 0x430370
	@end:
	cmp eax, 0x1EF
	]])
	-- FIXME: get rid of evt.MoveToMap
	hook((new_code or 0x42EE99) + 0xB, function(d)
		if d.eax < 1 or not TownPortalControls.Sets[MV.Continent]
				or not TownPortalControls.Sets[MV.Continent][d.eax] then
			return
		end
		local tpset = TownPortalControls.Sets[MV.Continent][d.eax]
		local mapname
		if tpset.Map == MV.Map then
			mapname = "0"
		else
			mapname = Game.MapStats[tpset.Map].FileName
		end
		evt.MoveToMap{Name = mapname, X = tpset.X, Y = tpset.Y, Z = tpset.Z, Direction = tpset.Dir, LookAngle = tpset.LA}
	end)

	-------- Spell Damage --------
	local function spell_dmg_var(d, var)
		local t = {Spell = d.ebx, Level = d.edi, Mastery = u4[d.ebp + 0x8], DmgVar = var, Value = d.eax}
		t.CasterType = bit.band(u4[MO.CalcSpellDamageCaster], 7)
		t.CasterIndex = bit.arshift(u4[MO.CalcSpellDamageCaster], 3)
		events.call("SpellDmgVar", t)
		d.eax = t.Value
	end
	-- Set caster
	--   damageMonsterFromParty: Blades
	asmpatch(0x4370B4, [[
	mov eax, dword ptr [ebp - 0x30]
	mov dword ptr []] .. MO.CalcSpellDamageCaster .. [[], eax
	call absolute 0x438B05
	]])
	--   damageMonsterFromParty: default
	asmpatch(0x437148, [[
	mov eax, dword ptr [ebp - 0x30]
	mov dword ptr []] .. MO.CalcSpellDamageCaster .. [[], eax
	call absolute 0x438B05
	]])
	--   DamagePlayerFromObjAny
	asmpatch(0x438403, [[
	mov ecx, ebx
	call absolute ]] .. MO.GetMapObjectIndex .. [[;
	shl eax, 3
	or eax, 2
	mov dword ptr []] .. MO.CalcSpellDamageCaster .. [[], eax
	mov ecx, edi
	call absolute 0x48D9B4
	]])
	--   DamageMonsterFromEvent
	asmpatch(0x438CCC, [[
	mov eax, dword ptr [ebp - 0x4]
	mov dword ptr []] .. MO.CalcSpellDamageCaster .. [[], eax
	call absolute 0x438B05
	]])

	-- CalcSpellDamage
	--   ecx - spell id, edx - skill level, [ebp+8] - skill mastery, [ebp+0xC] - monster hp
	new_code = asmpatch(0x438B0A, [[
	push edi
	push esi
	push ebx
	test ecx, ecx
	jle @end
	cmp ecx, ]] .. max_spell .. [[;
	jg @end
	mov edi, edx
	xor esi, esi
	mov ebx, ecx
	; check mastery
	mov ecx, dword ptr [ebp + 0x8]
	test ecx, ecx
	jg @ff1
	mov dword ptr [ebp + 0x8], 1
	@ff1:
	cmp ecx, ]] .. max_mastery .. [[;
	jle @ff2
	mov dword ptr [ebp + 0x8], ]] .. max_mastery .. [[;
	@ff2:
	; Mass Distortion
	cmp ebx, 0x2C
	jne @const
	mov eax, 0x19
	nop
	nop
	nop
	nop
	nop
	imul eax, dword ptr [ebp + 0xC]
	cdq
	push 0x64
	pop ecx
	idiv ecx
	mov esi, eax
	@const:
	; const per level
	mov ecx, dword ptr [ebp + 0x8]
	dec ecx
	imul ecx, ]] .. spell_dmg_vars_size .. [[;
	mov eax, ebx
	dec eax
	imul eax, ]] .. spell_dmg_vars_line_size .. [[;
	add eax, ecx
	movzx eax, word ptr [eax + ]] .. MO.SpellsDmgVars .. [[]
	nop
	nop
	nop
	nop
	nop
	imul eax, edi
	add esi, eax
	; dmg add
	mov eax, ebx
	dec eax
	imul eax, ]] .. spell_dmg_vars_line_size .. [[;
	add eax, ecx
	movzx eax, word ptr [eax + ]] .. (MO.SpellsDmgVars + 2 * max_mastery * spell_dmg_vars_size) .. [[]
	nop
	nop
	nop
	nop
	nop
	add esi, eax
	; rnd per level
	mov eax, ebx
	dec eax
	imul eax, ]] .. spell_dmg_vars_line_size .. [[;
	add eax, ecx
	movzx eax, word ptr [eax + ]] .. (MO.SpellsDmgVars + max_mastery * spell_dmg_vars_size) .. [[]
	nop
	nop
	nop
	nop
	nop
	mov edx, eax
	mov ecx, edi
	call absolute 0x450394
	add eax, esi
	@end:
	pop ebx
	pop esi
	]], 0x438C69 - 0x438B0A)
	hook((new_code or 0x438B0A) + 0x41, function(d)
		local mastery = u4[d.ebp + 0x8]
		local t = {Spell = 44, VarNum = 1, Value = get_spell_var_value(44, 1, mastery, 2),
			Mastery = mastery, Level = d.edi}
		t.CasterType = bit.band(u4[MO.CalcSpellDamageCaster], 7)
		t.CasterIndex = bit.arshift(u4[MO.CalcSpellDamageCaster], 3)
		events.call("SpellVar", t)
		local var1 = t.Value
		t.VarNum = 2
		t.Value = get_spell_var_value(44, 2, mastery, 25)
		events.call("SpellVar", t)
		local var2 = t.Value
		t.VarNum = 3
		t.Value = get_spell_var_value(44, 3, mastery, 0)
		events.call("SpellVar", t)
		local res = floor(var1 * d.edi) + var2
		if res == 0 and d.edi > 0 then
			res = 1
		end
		if t.Value > 0 then
			res = min(res, t.Value)
		end
		d.eax = res
	end)
	hook((new_code or 0x438B0A) + 0x68, function(d)
		spell_dmg_var(d, "DmgConst")
	end)
	hook((new_code or 0x438B0A) + 0x81, function(d)
		spell_dmg_var(d, "DmgAdd")
	end)
	hook((new_code or 0x438B0A) + 0x97, function(d)
		spell_dmg_var(d, "DmgRnd")
	end)

	-- Monster Spells
	asmpatch(0x404DA5, [[
	jbe @end
	cmp ecx, 0x73
	jnz absolute 0x405FC0
	mov ecx, dword ptr [ebp + 0x10]
	call absolute 0x455B09
	inc eax
	mov edx, dword ptr [ebp - 0x4]
	imul eax, edx
	push eax
	call absolute 0x4D99F2 ; Rand
	cdq
	mov ecx, 0x64
	idiv ecx
	pop ecx
	cmp edx, ecx
	jge @fin
	mov eax, dword ptr [edi + 0x20]
	and eax, 7
	cmp eax, 4
	jnz @mon
	mov ecx, 0xE
	call absolute ]] .. MO.SelectConditionSlot .. [[;
	test eax, eax
	jl @fin
	push eax
	mov ecx, 0xB20E90
	call absolute 0x4026F4
	mov ecx, eax
	push ecx
	movzx edx, byte ptr [0x5E9308] ; SpellsTxt[117].DamageType
	call absolute ]] .. MO.CheckResistPlayer .. [[;
	pop ecx
	test eax, eax
	jnz @fin
	push 1
	push 0xE
	call absolute 0x49165D
	@mon:
	@fin:
	xor ebx, ebx
	jmp absolute 0x4055F8
	@end:
	]])
end

function events.GameInitialized1()
	ProcessSpellsExtraTxt()
	SetSpellsExtraHooks()
end

function events.GameInitialized2()
	-------- Spell Damage --------
	-- Set caster
	--   CalcMonsterDamage
	asmpatch(0x439140, [[
	mov ebx, esi
	cmp edx, 2
	jnz absolute 0x43914F
	]])
	asmpatch(0x439157, [[
	mov ecx, ebx
	call absolute ]] .. MO.GetMapMonsterIndex .. [[;
	shl eax, 3
	or eax, 3
	mov dword ptr []] .. MO.CalcSpellDamageCaster .. [[], eax
	xor ecx, ecx
	push ecx
	mov ecx, edi
	call absolute 0x455B09
	]], 0x43915F - 0x439157)
end

Log(Merge.Log.Info, "Init finished: %s", LogId)

