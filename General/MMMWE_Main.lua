	local MF = Merge.Functions
	local MM, MO, MS, MV = Merge.ModSettings, Merge.Offsets, Merge.Settings, Merge.Vars
	local asmpatch, asmproc = mem.asmpatch, mem.asmproc

	-- Item durability. The real implementations are installed by ItemDurability.lua;
	-- these stubs keep everything working (old IdRepSt values, zero wear) if that script is absent.
	MF.GetBaseDurability = MF.GetBaseDurability or function(itemNumber) return Game.ItemsTxt[itemNumber].IdRepSt end
	MF.GetItemWear      = MF.GetItemWear      or function(item) return 0 end
	MF.GetItemWearPtr   = MF.GetItemWearPtr   or function(ptr) return 0 end

	-- Armor HR (hit resistance) = weighted armor durability / HR_DIVISOR (was 2.5, now one fifth of durability)
	MF.HR_DIVISOR = 5
	
	function sumArray(t)
		local sum = 0
		for i, value in ipairs(t) do
			sum = sum + value
		end
		return sum
	end
	
	function round(num)
		return num >= 0 and math.floor(num + 0.5) or math.ceil(num - 0.5)
	end
	MF.round = round
	
	function findMax(t)
		if #t == 0 then
			error("Array is empty")
		end
		local maxVal = t[1]
		for i = 2, #t do
			if t[i] > maxVal then
				maxVal = t[i]
			end
		end
		return maxVal
	end
	
	-- Unidentified items give no special bonuses (except artifacts and relics)
	local EXCLUDED_ITEMS = { [866] = true, [867] = true, [966] = true, [967] = true, [1666] = true, [1667] = true}

	local VALID_SCREENS = { [0] = true, [7] = true, [10] = true, [13] = true, [14] = true, [15] = true }

	local PACK_FLAG = 100000000

	--- Packing bonuses into Charges field
	local function packBonuses(it)
		if it.Bonus <= 0 and it.Bonus2 <= 0 then
			return
		end
		local flag = 0
		if it.Bonus > 0 then flag = flag + 1 end
		if it.Bonus2 > 0 then flag = flag + 2 end

		it.Charges = flag * PACK_FLAG
			+ it.Bonus2 * 100000
			+ it.BonusStrength * 1000
			+ it.Bonus
		it.Bonus = 0
		it.BonusStrength = 0
		it.Bonus2 = 0
	end

	--- Unpacking bonuses from Charges field
	local function unpackBonuses(it)
		if it.Charges < PACK_FLAG then
			return
		end
		local packed = it.Charges
		local flag = math.floor(packed / PACK_FLAG)
		local remainder = math.fmod(packed, PACK_FLAG)

		if flag % 2 == 1 then
			it.Bonus = math.fmod(remainder, 1000)
			it.BonusStrength = math.floor(math.fmod(remainder, 100000) / 1000)
		end
		if flag >= 2 then
			it.Bonus2 = math.floor(remainder / 100000)
		end
		it.Charges = 0
	end

	--- Check if item needs processing
	local function shouldProcess(it)
		if not it or not it.Number then
			return false
		end
		if EXCLUDED_ITEMS[it.Number] then
			return false
		end
		if Game.ItemsTxt[it.Number].EquipStat >= 12 then
			return false
		end
		-- A temporary enchantment (Fire Aura, weapon potions) is not a hidden bonus: packing it
		-- would make it permanent once the item is identified. MMMWE_ConcurrentEnchantments.lua
		-- keeps the item's own packed enchantment while a temporary one is on it.
		if it.TemporaryBonus then
			return false
		end
		return true
	end

	--- Single item processing
	local function processItem(it)
		if not shouldProcess(it) then
			return
		end
		if not it.Identified then
			packBonuses(it)
		else
			unpackBonuses(it)
		end
	end

	--- 1. Packing bonuses upon unidentified item generation
	function events.ItemGenerated(t)
		if t.Item and not t.Item.Identified then
			processItem(t.Item)
		end
	end

	-- 2. Unpacking bonuses upon identification (hook to item_rmb_window)
	function events.GetItemByRightClick(t)
		local it = t.Item
		if it and shouldProcess(it) and it.Identified then
			unpackBonuses(it)
		end
	end

	-- 3. Restore the state of item after load map
	function events.AfterLoadMap()
		for _, pl in Party do
			for i = 1, 138 do
				local it = pl.Items[i]
				if it.Number > 0 then
					processItem(it)
				end
			end
		end
	end
	
	-- Hammerhands (22.10.26), as its description says: an unarmed melee hit also deals Body
	-- damage equal to the physical damage of the hit (bare hands, Might, Unarmed skill).
	-- The game deals the extra Body damage at 0x437301 with the buff's power as the amount
	-- (push eax after movzx eax, [player+1A9Ch] at 0x4372FA); the amount becomes the hit's
	-- physical damage before resistances ([ebp-10h], the value just pushed for the physical
	-- part). MF.HammerhandsHit marks that Body call, so the melee bonuses below (crits,
	-- Might, Heroism, durability) are not applied to it again.
	-- (the flag is checked together with the Body damage kind and cleared by the last handler)
	mem.autohook2(0x4372FA, function(d)
		d.eax = math.max(0, mem.i4[d.ebp - 0x10])
		MF.HammerhandsHit = true
	end)
	
	-- Dodging gives no Armor Class: it works through the dodge (mitigation) chance only.
	-- The game's own skill AC is computed again with Dodging set to 0 and used instead.
	-- Registered before the armor skill handler below, so the Result it sees is the game's.
	local DODGING = const.Skills.Dodging
	local NoDodgeACPass = false
	function events.CalcStatBonusBySkills(t)
		if t.Stat ~= const.Stats.ArmorClass or NoDodgeACPass then return end
		local pl = t.Player
		local raw = pl.Skills[DODGING]
		if raw == 0 then return end
		NoDodgeACPass = true
		pl.Skills[DODGING] = 0
		local ok, without = pcall(pl.CalcStatBonusBySkills, pl, const.Stats.ArmorClass)
		pl.Skills[DODGING] = raw
		NoDodgeACPass = false
		if ok and type(without) == "number" then
			t.Result = without
		end
	end

		-- Armor skill bonus changes
	function events.CalcStatBonusBySkills(t)
		-- Stat 9 = ArmorClass
		if t.Stat ~= 9 or t.Result == 0 or NoDodgeACPass then
			return
		end

		local Pl = t.Player
		local slots = {
			Pl.ItemHelm, Pl.ItemArmor, Pl.ItemGauntlets,
			Pl.ItemBoots, Pl.ItemBelt, Pl.ItemExtraHand, Pl.ItemMainHand
		}

		local ratings, counts = {}, {}

		for _, slotIdx in ipairs(slots) do
			if slotIdx > 0 and not Pl.Items[slotIdx].Broken then
				local itemTxt = Game.ItemsTxt[Pl.Items[slotIdx].Number]
				local skill = itemTxt.Skill
				local rating
				if skill == 8 and slotIdx == Pl.ItemExtraHand and MF.ItemArmorBase then
					rating = MF.ItemArmorBase(itemTxt) + itemTxt.Mod2   -- MMMWE_Shields.lua
				else
					rating = itemTxt.Mod1DiceCount + itemTxt.Mod2
				end
				ratings[skill] = (ratings[skill] or 0) + rating
				counts[skill] = (counts[skill] or 0) + 1
			end
		end

		-- Bonus rules by skill:
		-- lowC/highC — S*Rating coeffs for low/high mastery
		-- mC — M*Rating coeff
		-- perItem — bool indicator for penalty from multiple items (true) or flat penalty (false)
		-- hiPenMul — high mastery penalty mult
		-- highM = nil — single tier (no other mastery tiers involved)
		local rules = {
			-- Leather
			{skill=9,  minM=1, highM=3,  lowC=0.025,  highC=0.05,   mC=0.125, perItem=true,  hiPenMul=2},
			-- Chain
			{skill=10, minM=1, highM=4,  lowC=0.025,  highC=0.05,   mC=0.125, perItem=true,  hiPenMul=1},
			-- Plate
			{skill=11, minM=1, highM=3,  lowC=0.025,  highC=0.05,   mC=0.125, perItem=true,  hiPenMul=1},
			-- Shield
			{skill=8,  minM=1, highM=3,  lowC=0.05,   highC=0.1,    mC=0.25,  perItem=false, hiPenMul=2},
			-- Staff
			{skill=0,  minM=2, highM=nil, lowC=0.05,   highC=nil,    mC=0.25,  perItem=false},
			-- Sword
			{skill=1,  minM=4, highM=nil, lowC=0.05,   highC=nil,    mC=0.25,  perItem=true},
			-- Spear
			{skill=4,  minM=4, highM=nil, lowC=0.05,   highC=nil,    mC=0.25,  perItem=false},
		}

		for _, r in ipairs(rules) do
			local count = counts[r.skill]
			if count and count > 0 then
				local S, M = SplitSkill(Pl.Skills[r.skill])
				if M >= r.minM then
					local rating = ratings[r.skill]
					local penalty = r.perItem and (S * count) or S
					local coeff, penMul = r.lowC, 1
					if r.highM and M >= r.highM then
						coeff = r.highC
						penMul = r.hiPenMul or 1
					end
					t.Result = t.Result + coeff * S * rating + r.mC * M * rating - penMul * penalty
				end
			end
		end
	end

	-- Change stat breakpoints and bonuses	
	mem.autohook2(0x48e1af, function(d)
		local ST = 	{400, 	380, 	360, 	340,	320, 	300,	280,	260,	240,	220,	200,	190,	180,	170,	160, 	150,	140,	130,	120,	110,	100,	94,	88, 82, 76, 70, 64, 58, 52, 46, 40, 36, 32, 28, 24, 20, 18, 16, 14, 12, 10,  9,  8,  7,  6,  5,  4,  3,  2,  1,   0,  -2,  -4,  -6,  -8, -10, -12, -14, -16, -18, -20, -25, -30, -35, -40, -50}
		local STB = {40, 	39, 	38,		37,		36, 	35, 	34, 	33, 	32, 	31, 	30, 	29, 	28, 	27, 	26, 	25, 	24, 	23, 	22, 	21, 	20, 	19, 18, 17, 16, 15, 14, 13, 12, 11, 10,  9,  8,  7,  6,  5,  4,  3,  2,  1,  0, -1, -2, -3, -4, -5, -6, -7, -8, -9, -10, -11, -12, -13, -14, -15, -16, -17, -18, -19, -20, -21, -22, -23, -24, -25}
		local effective_stat = 0
		local eff_stat_bonus = 0
		effective_stat = mem.i4[d.esp+4]
		for i = 1,#ST do
			if effective_stat >= ST[i] then
				eff_stat_bonus = STB[i]
				break
			elseif effective_stat < ST[#ST] then
				eff_stat_bonus = STB[#STB]
			end
		end
		d.eax = eff_stat_bonus
	end)

	-- Weapon distinctive parameters
	local WEAPON_TYPES = {
		'Longsword', 'Artifact Longsword', 'Relic Longsword', 'Special Longsword',
		'Two-Handed Sword', 'Artifact Two-Handed Sword', 'Relic Two-Handed Sword', 'Special Two-Handed Sword',
		'Broadsword', 'Artifact Broadsword', 'Relic Broadsword', 'Special Broadsword',
		'Cutlass', 'Artifact Cutlass', 'Relic Cutlass', 'Special Cutlass',
		'Dagger', 'Artifact Dagger', 'Relic Dagger', 'Special Dagger',
		'Long Dagger', 'Artifact Long Dagger', 'Relic Long Dagger', 'Special Long Dagger',
		'Axe', 'Artifact Axe', 'Relic Axe', 'Special Axe',
		'Two-Handed Axe', 'Artifact Two-Handed Axe', 'Relic Two-Handed Axe', 'Special Two-Handed Axe',
		'Spear', 'Artifact Spear', 'Relic Spear', 'Special Spear',
		'Halberd', 'Artifact Halberd', 'Relic Halberd', 'Special Halberd',
		'Trident', 'Artifact Trident', 'Relic Trident', 'Special Trident',
		'Mace', 'Artifact Mace', 'Relic Mace', 'Special Mace',
		'Flail', 'Artifact Flail', 'Relic Flail', 'Special Flail',
		'Hammer', 'Artifact Hammer', 'Relic Hammer', 'Special Hammer',
		'Staff', 'Artifact Staff', 'Relic Staff', 'Special Staff',
		'Warhammer', 'Ancient Relic Warhammer',
		'Artifact Greatsword', 'Relic Greatsword',
		'Saber'
	}

	-- Weapon subtypes (19.10.26): within a family there is a fast crit-chance subtype, a slow
	-- crit-damage one and a defensive one. Tables 4 and 5 are added to the weapon's crit
	-- chance (%) and crit damage multiplier (MF.GetCritStats).
	local WEAPON_BONUSES = {
		-- Parry Chance Bonus
		[1] = {
			10, 10, 10, 10,	-- Longswords
			10, 10, 10, 10,	-- Two-Handed Swords
			3, 3, 3, 3,	-- Broadswords
			8, 8, 8, 8,	-- Cutlasses
			12, 12, 12, 12,	-- Daggers
			18, 18, 18, 18,	-- Long Daggers
			2, 2, 2, 2,	-- Axes
			4, 4, 4, 4,	-- Two-Handed Axes
			15, 15, 15, 15,	-- Spears
			10, 10, 10, 10,	-- Halberds
			22, 22, 22, 22,	-- Tridents
			9, 9, 9, 9,	-- Maces
			0, 0, 0, 0,	-- Flails
			6, 6, 6, 6,	-- Hammers
			22, 22, 22, 22,	-- Staves
			10, 10,	-- Warhammers
			10, 10,	-- Greatswords
			14	-- Sabers
		},
		-- Attack Delay Penalty (recovery; negative = faster)
		[2] = {
			0, 0, 0, 0,	-- Longswords
			0, 0, 0, 0,	-- Two-Handed Swords
			8, 8, 8, 8,	-- Broadswords
			-6, -6, -6, -6,	-- Cutlasses
			-5, -5, -5, -5,	-- Daggers
			0, 0, 0, 0,	-- Long Daggers
			0, 0, 0, 0,	-- Axes
			3, 3, 3, 3,	-- Two-Handed Axes
			-5, -5, -5, -5,	-- Spears
			8, 8, 8, 8,	-- Halberds
			0, 0, 0, 0,	-- Tridents
			0, 0, 0, 0,	-- Maces
			4, 4, 4, 4,	-- Flails
			-5, -5, -5, -5,	-- Hammers
			0, 0, 0, 0,	-- Staves
			2, 2,	-- Warhammers
			8, 8,	-- Greatswords
			-8	-- Sabers
		},
		-- Parry Strength Bonus
		[3] = {
			5, 5, 5, 5,	-- Longswords
			10, 10, 10, 10,	-- Two-Handed Swords
			6, 6, 6, 6,	-- Broadswords
			0, 0, 0, 0,	-- Cutlasses
			1, 1, 1, 1,	-- Daggers
			4, 4, 4, 4,	-- Long Daggers
			5, 5, 5, 5,	-- Axes
			10, 10, 10, 10,	-- Two-Handed Axes
			7, 7, 7, 7,	-- Spears
			12, 12, 12, 12,	-- Halberds
			7, 7, 7, 7,	-- Tridents
			12, 12, 12, 12,	-- Maces
			6, 6, 6, 6,	-- Flails
			8, 8, 8, 8,	-- Hammers
			13, 13, 13, 13,	-- Staves
			8, 8,	-- Warhammers
			14, 14,	-- Greatswords
			0	-- Sabers
		},
		-- Crit Chance Bonus (%)
		[4] = {
			0, 0, 0, 0,	-- Longswords
			0, 0, 0, 0,	-- Two-Handed Swords
			-2, -2, -2, -2,	-- Broadswords
			4, 4, 4, 4,	-- Cutlasses
			3, 3, 3, 3,	-- Daggers
			-3, -3, -3, -3,	-- Long Daggers
			0, 0, 0, 0,	-- Axes
			-2, -2, -2, -2,	-- Two-Handed Axes
			0, 0, 0, 0,	-- Spears
			-3, -3, -3, -3,	-- Halberds
			3, 3, 3, 3,	-- Tridents
			0, 0, 0, 0,	-- Maces
			2, 2, 2, 2,	-- Flails
			2, 2, 2, 2,	-- Hammers
			0, 0, 0, 0,	-- Staves
			-3, -3,	-- Warhammers
			-3, -3,	-- Greatswords
			6	-- Sabers
		},
		-- Crit Damage Bonus (added to the multiplier)
		[5] = {
			0, 0, 0, 0,	-- Longswords
			0.30, 0.30, 0.30, 0.30,	-- Two-Handed Swords
			0.35, 0.35, 0.35, 0.35,	-- Broadswords
			0, 0, 0, 0,	-- Cutlasses
			0, 0, 0, 0,	-- Daggers
			-0.10, -0.10, -0.10, -0.10,	-- Long Daggers
			0.15, 0.15, 0.15, 0.15,	-- Axes
			0.45, 0.45, 0.45, 0.45,	-- Two-Handed Axes
			0, 0, 0, 0,	-- Spears
			0.45, 0.45, 0.45, 0.45,	-- Halberds
			-0.05, -0.05, -0.05, -0.05,	-- Tridents
			0, 0, 0, 0,	-- Maces
			0.30, 0.30, 0.30, 0.30,	-- Flails
			0.10, 0.10, 0.10, 0.10,	-- Hammers
			0, 0, 0, 0,	-- Staves
			0.45, 0.45,	-- Warhammers
			0.60, 0.60,	-- Greatswords
			-0.05	-- Sabers
		}
	}
	MF.WeaponSubtypeBonuses = WEAPON_BONUSES

	function CalcWeaponStatBonusByWType(WeaponNum, WeaponStat)

		local weaponType = Game.ItemsTxt[WeaponNum].NotIdentifiedName
		
		if not WEAPON_BONUSES[WeaponStat] then
			return 0
		end
		
		local weaponIndex = table.ifind(WEAPON_TYPES, weaponType)
		
		return weaponIndex and WEAPON_BONUSES[WeaponStat][weaponIndex] or 0
	end

	-- Change base attack delay values of weapon and armor types
	-- Shield and armor are 0 here: the game would add them as flat values. Their penalties are
	-- applied as percentages of the attack delay in GetAttackDelay below (ArmorRecoveryPct).
--						 Staff	 Sword   Dagger Axe     Spear   Bow     Mace    Blaster  Shield Leather Chain  Plate  Unarmed w|o Skill	
	local Delay_table = {110, 0, 100, 0, 60, 0, 115, 0, 110, 0, 100, 0, 130, 0, 75, 0,   0, 0,  0, 0,   0, 0,  0, 0,  100, 0}
	
	for i = 0, #Delay_table-1, 2 do
		mem.i2[0x4FDF88 + i] = Delay_table[i + 1]
	end
	
	MV.AuxArmorRecoveryPenalty = {}

	-- 9=Leather, 10=Chain, 11=Plate
	-- Index 1-4 = Normal, Expert, Master, Grandmaster
	local AuxArmorPenalties = {
		[9]  = {5, 0, 0, 0},
		[10] = {10, 5, 0, 0},
		[11] = {15, 7.5, 7.5, 0},
	}

	-- % of attack delay added by body armor and a shield (the game's own values and mastery
	-- rules, formerly flat: Shield and Leather 10 at Novice, Chain 20 / 10, Plate 30 / 15 / 15)
	local BodyArmorPenalties = {
		[8]  = {10, 0, 0, 0},    -- Shield (+ medium / large shield extra, MMMWE_Shields.lua)
		[9]  = {10, 0, 0, 0},    -- Leather
		[10] = {20, 10, 0, 0},   -- Chain
		[11] = {30, 15, 15, 0},  -- Plate
	}

	-- Technicians' workarounds (22.10.26):
	--  - the Heavenly Forge chain suits (lore: lighter and more supple than any chain, worn by
	--    Padish's officers before the Silence) count as leather for a Technician: no chain
	--    penalties, leather effects, and the Chain skill is at least the Leather skill;
	--  - the Reflector Shield (967): a Technician's Shield skill is at least the Repair skill;
	--  - Scientists use the better of Repair and Alchemy where Repair is asked (blaster upgrades,
	--    Deploy Droid)
	local HEAVENLY_SUITS = {[877] = true, [1677] = true, [1306] = true}
	local REFLECTOR = 967
	local SCIENTIST = {[126] = true, [127] = true}
	MF.HeavenlySuits = HEAVENLY_SUITS
	local function techn(pl) return MF.IsTechnician and MF.IsTechnician(pl) end
	function MF.LightSuit(pl, num)
		if not num then
			local s = pl.ItemArmor
			if s <= 0 or pl.Items[s].Broken then return false end
			num = pl.Items[s].Number
		end
		return HEAVENLY_SUITS[num] and techn(pl) or false
	end
	-- skill of a piece of armor for its penalties and effects
	function MF.ArmorPieceSkill(pl, num)
		if HEAVENLY_SUITS[num] and techn(pl) then return const.Skills.Leather end
		return Game.ItemsTxt[num].Skill
	end
	local function betterSkill(a, b)
		local sa, ma = SplitSkill(a)
		local sb, mb = SplitSkill(b)
		if mb > ma or (mb == ma and sb > sa) then return b end
		return a
	end
	function MF.TechRepairSkill(pl)
		local r = pl:GetSkill(const.Skills.Repair)
		if SCIENTIST[pl.Class] then r = betterSkill(r, pl:GetSkill(const.Skills.Alchemy)) end
		return r
	end
	function events.GetSkill(t)
		local pl = t.Player
		if not pl then return end
		if t.Skill == const.Skills.Chain then
			if MF.LightSuit(pl) then t.Result = betterSkill(t.Result, pl:GetSkill(const.Skills.Leather)) end
		elseif t.Skill == const.Skills.Shield then
			local sh = pl.ItemExtraHand
			if sh > 0 and pl.Items[sh].Number == REFLECTOR and techn(pl) then
				t.Result = betterSkill(t.Result, MF.TechRepairSkill(pl))
			end
		end
	end

	-- Total % added to (or, if negative, taken from) the attack delay of non-blaster attacks
	-- by armor, shield and armor type effects (MMMWE_ArmorEffects.lua)
	local function ArmorRecoveryPct(Pl)
		local pct = 0
		local function mastery(skill)
			local _, M = SplitSkill(Pl:GetSkill(skill))
			return math.max(M, 1)
		end
		local body = Pl.ItemArmor
		if body > 0 and not Pl.Items[body].Broken then
			local skill = MF.ArmorPieceSkill(Pl, Pl.Items[body].Number)
			local pen = BodyArmorPenalties[skill]
			if pen and skill ~= 8 then pct = pct + pen[mastery(skill)] end
		end
		for _, slotIdx in ipairs{Pl.ItemHelm, Pl.ItemBelt, Pl.ItemGauntlets, Pl.ItemBoots} do
			if slotIdx > 0 and not Pl.Items[slotIdx].Broken then
				local skill = Game.ItemsTxt[Pl.Items[slotIdx].Number].Skill
				local pen = AuxArmorPenalties[skill]
				if pen then pct = pct + pen[mastery(skill)] end
			end
		end
		local sh = Pl.ItemExtraHand
		if sh > 0 and not Pl.Items[sh].Broken and Game.ItemsTxt[Pl.Items[sh].Number].Skill == 8 then
			local M = mastery(8)
			pct = pct + BodyArmorPenalties[8][M]
			if MF.ShieldExtraPenalty then pct = pct + MF.ShieldExtraPenalty(Pl.Items[sh].Number, M) end
		end
		if MF.ArmorRecoveryMod then pct = pct + MF.ArmorRecoveryMod(Pl) end
		return pct
	end
	MF.ArmorRecoveryPct = ArmorRecoveryPct

	-- =====================================================================
	-- Attack recovery (non-blaster attacks): everything as percentages
	-- =====================================================================
	-- The game's get_attack_delay (0x48D62A) adds and subtracts flat values:
	--   weapon recovery (the skill's SkillRecoveryTimes; dual-wield: the slower hand; ranged: the
	--   bow) - Speed effect - weapon skill (sword / axe / bow at Expert+) - Arms Master (melee)
	--   - 25 Haste - 20 Swiftness / of Darkness / some artifacts + 20 Finality (+ armor and
	--   shield, which are 0 in SkillRecoveryTimes now).
	-- Here the flat values are taken back out to get the weapon's base recovery, which is then
	-- multiplied by one factor per modifier:
	--   delay = base x (1 + weapon subtype %) x (1 + armor %) x (1 - skill %) x (1 - Arms Master %)
	--           x (1 - Speed %) x (1 - 25% Haste) x (1 - 20% Swiftness) x ... (see RECOVERY)
	-- The weapon subtype values in WEAPON_BONUSES[2] and the two-handed penalty were set as a
	-- share of the weapon family's base recovery (+20 for a two-handed sword is 20% of 100), so
	-- they are used as value / family base.
	local RECOVERY = {
		TwoHandedPct    = 20,        -- two-handed swords, axes and maces (was +20 / +23 / +26)
		TwoHandedSkills = {[1] = true, [3] = true, [6] = true},
		SkillPct        = 1,         -- % per point: sword, axe (melee) and bow (ranged), Expert+
		SkillBonusSkills = {[1] = true, [3] = true, [5] = true},
		ArmsMasterPct   = {1, 1, 1, 2},  -- % per point by mastery, melee only
		SpeedPct        = 1,         -- % per point of Speed effect (a negative effect slows)
		HastePct        = 25,
		SwiftPct        = 20,        -- of Swiftness, of Darkness, Elderaxe, Wyrm Spitter, ...
		FinalityPct     = 20,        -- Finality (slower)
		CrossbowPct     = 50,        -- crossbows, Might effect takes it off again
		ArtifactPct     = 1,         -- % per point of artifact attack delay mods (ExtraArtifacts.lua)
		MinMelee        = MS.Attack and MS.Attack.MinimalMeleeAttackDelay or 30,
		MinRanged       = MS.Attack and MS.Attack.MinimalRangedAttackDelay or 15,
	}
	MF.RecoverySettings = RECOVERY
	local SwiftB2 = {[0x3B] = true, [0x29] = true}
	local SwiftItems = {[0x1F8] = true, [0x1FA] = true, [0x200] = true, [0x203] = true, [0x206] = true, [0x214] = true}
	local FinalityItem = 0x20D

	local function equipped(pl, slot)
		local idx = pl[slot]
		if idx > 0 then return pl.Items[idx] end
	end

	local function skillRec(item)
		return Game.SkillRecoveryTimes[Game.ItemsTxt[item.Number].Skill] or 0
	end

	-- weapon subtype and two-handed %, as a share of the weapon family's base recovery
	local function subtypePct(item)
		if not item or item.Broken then return 0 end
		local txt = Game.ItemsTxt[item.Number]
		if txt.EquipStat > 1 then return 0 end         -- weapons only (not shields, wands, ...)
		local base = Game.SkillRecoveryTimes[txt.Skill] or 0
		local p = 0
		if base > 0 then p = 100 * CalcWeaponStatBonusByWType(item.Number, 2) / base end
		if txt.EquipStat == 1 and RECOVERY.TwoHandedSkills[txt.Skill] then p = p + RECOVERY.TwoHandedPct end
		return p
	end
	MF.WeaponSubtypeRecoveryPct = subtypePct

	local function hasted(pl)
		local b = pl.SpellBuffs[const.PlayerBuff.Haste]
		local pb = Party.SpellBuffs[const.PartyBuff.Haste]
		return b.ExpireTime > 0 or pb.ExpireTime > 0      -- as the game checks it
	end

	local function factor(p) return math.max(0.05, 1 + 0.01 * p) end

	function events.GetAttackDelay(t)
		local Pl = t.Player
		local main, off, bow = equipped(Pl, "ItemMainHand"), equipped(Pl, "ItemExtraHand"), equipped(Pl, "ItemBow")

		-- Armor, shield and armor type effects (%)
		local armorPct = ArmorRecoveryPct(Pl)
		-- blaster accuracy penalty (CalcStatBonusBySkills): the blaster's 75 plus the armor
		-- penalty, the same numbers as when they were flat (armor type effects left out)
		MV.AuxArmorRecoveryPenalty[Pl.Name] = 75 + armorPct - (MF.ArmorRecoveryMod and MF.ArmorRecoveryMod(Pl) or 0)

		-- Blaster: fixed recovery
		if main and not main.Broken and Game.ItemsTxt[main.Number].Skill == const.Skills.Blaster then
			-- the Capacitor spec sets it (MMMWE_Blasters.lua)
			t.Result = MF.BlasterRecovery(main)
			return
		end
		-- wands keep the game's recovery (their spell's)
		if not t.Ranged and main and Game.ItemsTxt[main.Number].EquipStat == 12 then return end

		-- the item that sets the game's recovery (local_c in get_attack_delay)
		local used
		if t.Ranged then
			used = bow
		elseif not (not main and (not off or Game.ItemsTxt[off.Number].EquipStat == 4)
				and Pl:GetSkill(const.Skills.Unarmed) ~= 0) then
			used = main
			local cur = main and skillRec(main) or Game.SkillRecoveryTimes[0]
			if off and skillRec(off) > cur then used = off end
		end
		local usedTxt = used and Game.ItemsTxt[used.Number]

		-- take the game's flat bonuses back out: the weapon's base recovery
		local speedFx = Game.GetStatisticEffect(Pl:GetSpeed())
		local skillLvl = 0
		if usedTxt and RECOVERY.SkillBonusSkills[usedTxt.Skill] then
			local S, M = SplitSkill(Pl:GetSkill(usedTxt.Skill))
			if M >= 2 then skillLvl = S end
		end
		local amPct, amFlat = 0, 0
		if not t.Ranged then
			local AS, AM = SplitSkill(Pl:GetSkill(const.Skills.Armsmaster))
			if AS > 0 then
				amFlat = AM >= 4 and 2 * AS or AS
				amPct = AS * (RECOVERY.ArmsMasterPct[math.max(AM, 1)] or 1)
			end
		end
		local haste = hasted(Pl)
		local swift = used and (SwiftB2[used.Bonus2] or SwiftItems[used.Number]) or false
		local finality = used and used.Number == FinalityItem or false
		local base = t.Result + speedFx + skillLvl + amFlat + (haste and 25 or 0) + (swift and 20 or 0)
			- (finality and 20 or 0)
		if t.Result <= 0 or base <= 0 then   -- the game cut it at 0: use the recovery table
			base = used and skillRec(used) or Game.SkillRecoveryTimes[0]
		end

		-- percentages
		local d = base
		if t.Ranged then
			local name = usedTxt and usedTxt.NotIdentifiedName or ""
			if name == "Crossbow" or name == "Relic Crossbow" then
				d = d * factor(RECOVERY.CrossbowPct) * factor(-Game.GetStatisticEffect(Pl:GetMight()))
			end
		else
			local wp = subtypePct(main)
			if off and off ~= main then wp = wp + subtypePct(off) end
			d = d * factor(wp)
			d = d * factor(-amPct)
		end
		d = d * factor(armorPct)
		d = d * factor(-RECOVERY.SkillPct * skillLvl)
		d = d * factor(-RECOVERY.SpeedPct * speedFx)
		if haste then d = d * factor(-RECOVERY.HastePct) end
		if swift or (used and MF.HiddenSwift and MF.HiddenSwift(Pl, used)) then
			d = d * factor(-RECOVERY.SwiftPct)
		end
		if finality then d = d * factor(RECOVERY.FinalityPct) end
		local art = MF.ArtifactAttackDelay and MF.ArtifactAttackDelay(t.PlayerIndex, t.Ranged) or 0
		if art ~= 0 then d = d * factor(RECOVERY.ArtifactPct * art) end

		t.Result = math.max(t.Ranged and RECOVERY.MinRanged or RECOVERY.MinMelee, d)
	end

	-- Character screen / console
	function MF.RecoveryInfo(pl)
		pl = pl or Party[math.max(Game.CurrentPlayer, 0)]
		return string.format("melee %d, ranged %d, armor %+d%%", pl:GetAttackDelay(false), pl:GetAttackDelay(true), ArmorRecoveryPct(pl))
	end

	-- Immersive conditions module
	
	---- Temple heal costs per condition: moved to MMMWE_Economy.lua (Economy.Settings.Heal)

	---- Weakness

	local DaysToTravel = 0

	function events.WalkToMap(t)
		vars.RemainingFood = Party.Food
		if not vars.WeaknessCounter then
			vars.WeaknessCounter = {0, 0, 0, 0, 0}
		end
		DaysToTravel = t.Days
		for _, pl in Party do
			vars.WeaknessCounter[pl:GetSlot() + 1] = pl.Conditions[const.Condition.Weak]
		end
	end

	-- House types that don't trigger weakness from travel
	local NoWeaknessHouseTypes = {[24] = true, [25] = true, [27] = true, [28] = true}

	function events.GetTravelDaysCost(t)
		if NoWeaknessHouseTypes[Game.Houses[t.House].Type] then
			DaysToTravel = 0
		end
	end

	-- Daily weakness escalation (insanity, then death). The next check time is saved per
	-- character, so changing maps doesn't add extra rolls.
	local function checkWeakness(pl)
		vars.WeakNextCheck = vars.WeakNextCheck or {}
		local key = pl:GetIndex()
		local weak = pl.Conditions[const.Condition.Weak]
		if weak <= 0 then
			vars.WeakNextCheck[key] = nil
			return
		end
		local nextCheck = vars.WeakNextCheck[key]
		if nextCheck and Game.Time < nextCheck then
			return
		end
		vars.WeakNextCheck[key] = Game.Time + const.Day

		if weak <= Game.Time - const.Day * 3
		   and pl.Conditions[const.Condition.Insane] == 0
		   and math.random(100) <= 25 then
			pl.Conditions[const.Condition.Insane] = weak + const.Day * 3
		end

		if weak <= Game.Time - const.Day * 7
		   and pl.Conditions[const.Condition.Insane] == 0
		   and math.random(100) <= 50 then
			pl.Conditions[const.Condition.Insane] = weak + const.Day * 7
		end

		if weak <= Game.Time - const.Day * 10
		   and pl.Conditions[const.Condition.Dead] == 0
		   and math.random(100) <= 50 then
			pl.Conditions[const.Condition.Dead] = weak + const.Day * 10
			pl.Conditions[const.Condition.Weak] = 0
			pl.Conditions[const.Condition.Insane] = 0
			vars.WeaknessCounter[pl:GetSlot() + 1] = 0
			vars.WeakNextCheck[key] = nil
		end
	end

	---- Poison, Disease and Insanity

	-- Thing → Condition mapping
	local ThingToCond = {
		[5] = 5, [6] = 6, [7] = 8, [8] = 10, [9] = 7, [10] = 9, [11] = 11
	}

	-- Conditions that cancel debuff timers
	local AdverseConditions = {[14] = true, [15] = true, [16] = true, [17] = true, [20] = true}

	-- Debuff type configurations
	local DebuffTypes = {
		Poison = {
			conds      = {6, 8, 10},
			interval   = const.Minute * 10,
			duration   = const.Hour * 6,
			damageType = const.Damage.Body,
			calcDamage = function(cond, fhp)
				return math.max(cond - 4, 0.02 * fhp * cond / 2)
			end,
			onTick = function(pl, cond, expiryTime)
				if Game.Time > expiryTime - const.Hour * 3 - const.Hour * cond / 4
				   and pl.Conditions[const.Condition.Weak] == 0 then
					pl.Conditions[const.Condition.Weak] = Game.Time
				end
				if math.random(100) <= 5 * cond / 2 - 10
				   and pl.Conditions[const.Condition.Asleep] == 0 then
					pl.Conditions[const.Condition.Asleep] = Game.Time
				end
				if math.random(100) <= cond / 2 - 2
				   and pl.Conditions[const.Condition.Paralyzed] == 0 then
					pl.Conditions[const.Condition.Paralyzed] = Game.Time
				end
			end,
		},
		Disease = {
			conds      = {7, 9, 11},
			interval   = const.Minute * 30,
			duration   = const.Day,
			damageType = const.Damage.Body,
			calcDamage = function(cond, fhp)
				return math.max(cond - 5, 0.05 * fhp * cond - 0.3 * fhp)
			end,
			onTick = function(pl, cond, expiryTime)
				if Game.Time > expiryTime - const.Hour * 11 - const.Hour * cond
				   and pl.Conditions[const.Condition.Weak] == 0 then
					pl.Conditions[const.Condition.Weak] = Game.Time
				end
				if math.random(100) <= 5 * cond - 25
				   and pl.Conditions[const.Condition.Asleep] == 0 then
					pl.Conditions[const.Condition.Asleep] = Game.Time
				end
				if math.random(100) <= cond - 8 then
					pl.Conditions[const.Condition.Dead] = Game.Time
				end
			end,
		},
		Insanity = {
			conds      = {5},
			interval   = const.Minute * 15,
			duration   = const.Day,
			damageType = const.Damage.Mind,
			calcDamage = function(cond, fhp)
				return math.random(10) / 100 * fhp
			end,
			onTick = function(pl, cond, expiryTime, ind)
				local fsp = pl:GetFullSP()
				pl.SP = math.max(0, pl.SP - math.floor(math.random(10) / 100 * fsp))
				local feeblemindChance = 12 - 0.5 * math.floor(expiryTime / const.Hour - Game.Time / const.Hour)
				if math.random(100) <= feeblemindChance then
					Game.PlayersExtra[ind].Debuffs[18].ExpireTime = expiryTime
				end
			end,
		},
	}

	-- Build condition
	local CondToType = {}
	for typeName, config in pairs(DebuffTypes) do
		for _, cond in ipairs(config.conds) do
			CondToType[cond] = typeName
		end
	end

	local DebuffTimers = {}

	-- A timer belongs to one condition level; it stops when that level is gone
	-- (e.g. Poison 1 upgraded to Poison 2 no longer ticks twice)
	local function isCured(pl, cond)
		return pl.Conditions[cond] <= 0
	end

	local activeDebuffs = {}
	local scanTimerFunc = nil

	local function startDebuffTimer(pl, cond, typeName, expiryTime, firstFire)
		local config = DebuffTypes[typeName]
		local ind = pl.RosterBitIndex - 400
		local slot = pl:GetSlot()
		local key = slot .. "_" .. cond

		if DebuffTimers[key] then
			RemoveTimer(DebuffTimers[key])
			DebuffTimers[key] = nil
		end

		DebuffTimers[key] = function()
			if Game.Time > expiryTime then
				RemoveTimer(DebuffTimers[key])
				DebuffTimers[key] = nil
				if activeDebuffs[slot] then activeDebuffs[slot][cond] = nil end
				return
			end

			local mainCond = pl:GetMainCondition()
			if AdverseConditions[mainCond] or isCured(pl, cond) then
				Game.PlayersExtra[ind].Debuffs[cond].ExpireTime = 0
				RemoveTimer(DebuffTimers[key])
				DebuffTimers[key] = nil
				if activeDebuffs[slot] then activeDebuffs[slot][cond] = nil end
				return
			end

			Game.PlayersExtra[ind].Debuffs[cond].ExpireTime = expiryTime
			local fhp = pl:GetFullHP()
			local damage = math.max(1, math.floor(config.calcDamage(cond, fhp)))
			evt.DamagePlayer{Player = pl:GetSlot(), DamageType = config.damageType, Damage = damage}
			config.onTick(pl, cond, expiryTime, ind)
		end

		activeDebuffs[slot] = activeDebuffs[slot] or {}
		activeDebuffs[slot][cond] = true

		Timer(DebuffTimers[key], config.interval, firstFire or true)
	end

	---- Unconscious (Debuffs[13]) — periodic Endurance check

	local UnconsciousTimers = {}
	local UNCONSCIOUS_INTERVAL = const.Minute * 10
	local UNCONSCIOUS_CHECK_DC = 10

	local function startUnconsciousTimer(pl)
		local slot = pl:GetSlot() + 1
		local ind = pl.RosterBitIndex - 400

		if UnconsciousTimers[slot] then
			RemoveTimer(UnconsciousTimers[slot])
		end

		UnconsciousTimers[slot] = function()
			local debuff = Game.PlayersExtra[ind].Debuffs[13]
			if not debuff or debuff.ExpireTime <= Game.Time then
				RemoveTimer(UnconsciousTimers[slot])
				UnconsciousTimers[slot] = nil
				return
			end

			if pl.Conditions[13] <= 0 then
				debuff.ExpireTime = 0
				RemoveTimer(UnconsciousTimers[slot])
				UnconsciousTimers[slot] = nil
				return
			end

			local mainCond = pl:GetMainCondition()
			if mainCond >= 14 and mainCond <= 17 then
				debuff.ExpireTime = 0
				RemoveTimer(UnconsciousTimers[slot])
				UnconsciousTimers[slot] = nil
				if mainCond >= 14 and mainCond <= 16 then
					pl.Conditions[13] = 0
				end
				return
			end

			if pl.HP > 0 then
				debuff.ExpireTime = 0
				pl.Conditions[13] = 0
				RemoveTimer(UnconsciousTimers[slot])
				UnconsciousTimers[slot] = nil
				return
			end

			-- Endurance Check: 1d20 + GetStatisticEffect(Endurance) vs DC 10 - (-HP)
			local enduranceBonus = Game.GetStatisticEffect(pl:GetEndurance())
			local roll = math.random(1, 20) + enduranceBonus

			if roll >= UNCONSCIOUS_CHECK_DC - pl.HP then
				pl.HP = math.min(pl.HP + math.random(1, 8), 1)
				if pl.HP > 0 then
					debuff.ExpireTime = 0
					pl.Conditions[13] = 0
					if pl.Conditions[const.Condition.Weak] == 0 then
						pl.Conditions[const.Condition.Weak] = Game.Time
					end
					RemoveTimer(UnconsciousTimers[slot])
					UnconsciousTimers[slot] = nil
				end
			else
				pl.HP = pl.HP - math.random(1, 8)
				-- bled out: same death threshold as the games (HP at or below -Endurance)
				if pl.HP <= -pl:GetEndurance() and pl.SpellBuffs[const.PlayerBuff.Preservation].ExpireTime < Game.Time then
					debuff.ExpireTime = 0
					RemoveTimer(UnconsciousTimers[slot])
					UnconsciousTimers[slot] = nil
				end
			end
		end

		Timer(UnconsciousTimers[slot], UNCONSCIOUS_INTERVAL, true)
	end

	---- General condition debuff maintenance

	-- Conditions handled by debuff timers (poison/disease/insanity)
	local TimerConditions = {
	    [5] = true, [6] = true, [7] = true, [8] = true,
	    [9] = true, [10] = true, [11] = true, [17] = true,
	}

	-- Duration for maintained debuffs
	local CONDITION_DEBUFF_DURATION = const.Day * 7

	-- Maintain debuffs for all conditions except those handled by timers
	local function maintainConditionDebuffs(pl)
		local ind = pl.RosterBitIndex - 400
		for condId = 0, 17 do
			if not TimerConditions[condId] then
				pcall(function()
					local cond = pl.Conditions[condId] or 0
					local debuff = Game.PlayersExtra[ind].Debuffs[condId]
					if not debuff then return end
					if cond > 0 then
						debuff.ExpireTime = Game.Time + CONDITION_DEBUFF_DURATION
					else
						if debuff.ExpireTime and debuff.ExpireTime > 0 then
							debuff.ExpireTime = 0
						end
					end
				end)
			end
		end
	end
	
	local function scanDebuffs()
		for _, pl in Party do
			local slot = pl:GetSlot()
			for i = 5, 11 do
				if pl.Conditions[i] > 0 and CondToType[i] then
					if not (activeDebuffs[slot] and activeDebuffs[slot][i]) then
						local typeName = CondToType[i]
						local ind = pl.RosterBitIndex - 400
						local expiryTime = Game.PlayersExtra[ind].Debuffs[i].ExpireTime
						if expiryTime == 0 or expiryTime <= Game.Time then
							expiryTime = Game.Time + DebuffTypes[typeName].duration
						end
						local config = DebuffTypes[typeName]
						local firstFire = Game.Time + math.fmod(expiryTime - Game.Time, config.interval)
						startDebuffTimer(pl, i, typeName, expiryTime, firstFire)
					end
				end
			end
			-- Debuff maintenance for all conditions
			maintainConditionDebuffs(pl)
			
			if pl.Conditions[13] > 0 and not UnconsciousTimers[slot + 1] then
				startUnconsciousTimer(pl)
			end
		end
	end

	-- Dead and Eradicated stat losses once per hour
	local STAT_LOSS_INTERVAL = const.Hour
	local statFields = {
	    "MightBase", "IntellectBase", "PersonalityBase",
	    "EnduranceBase", "AccuracyBase", "SpeedBase"
	}
	
	local function applyStatLoss()
		for _, pl in Party do
			local ind = pl.RosterBitIndex - 400

			local hasActiveDebuff = false
			pcall(function()
				local erad = Game.PlayersExtra[ind].Debuffs[16]
				local dead = Game.PlayersExtra[ind].Debuffs[14]
				if (erad and erad.ExpireTime > Game.Time) or
				   (dead and dead.ExpireTime > Game.Time) then
					hasActiveDebuff = true
				end
			end)

			if hasActiveDebuff then
				local statName = statFields[math.random(#statFields)]
				local deadExp   = 0
				local eradExp   = 0
				pcall(function()
					deadExp = Game.PlayersExtra[ind].Debuffs[14].ExpireTime or 0
					eradExp = Game.PlayersExtra[ind].Debuffs[16].ExpireTime or 0
				end)

				local loss, condName
				if eradExp > Game.Time then
					loss, condName = 2, "Eradicated"
				elseif deadExp > Game.Time then
					loss, condName = 1, "Dead"
				end

				local current = 0
				pcall(function() current = pl[statName] or 0 end)
				if loss and current > 0 then
					pcall(function()
						pl[statName] = math.max(0, current - loss)
						Game.ShowStatusText(string.format("%s loses %d %s from being %s",
							pl.Name, loss, statName:sub(1, #statName - 4), condName))
					end)
				end
			end
		end
	end

	-- Once per hour of game time; the next time is saved, so changing maps doesn't add losses
	local function checkStatLoss()
		if not vars.StatLossNext or vars.StatLossNext > Game.Time + STAT_LOSS_INTERVAL then
			vars.StatLossNext = Game.Time + STAT_LOSS_INTERVAL
			return
		end
		if Game.Time >= vars.StatLossNext then
			vars.StatLossNext = Game.Time + STAT_LOSS_INTERVAL
			applyStatLoss()
		end
	end


	function events.DoBadThingToPlayer(t)
		if t.Allow == false then return end   -- shrugged off (MMMWE_ArmorEffects.lua)
		local cond = ThingToCond[t.Thing]
		if not cond then return end

		local typeName = CondToType[cond]
		if not typeName then return end

		-- Check ExpireTime existance and setup new ExpireTime if none
		local ind = t.Player.RosterBitIndex - 400
		local expiryTime = Game.PlayersExtra[ind].Debuffs[cond].ExpireTime
		if expiryTime == 0 or expiryTime <= Game.Time then
			expiryTime = Game.Time + DebuffTypes[typeName].duration
		end
		startDebuffTimer(t.Player, cond, typeName, expiryTime)
	end

	function events.AfterLoadMap()
		-- Weakness setup
		if not vars.WeaknessCounter then
			vars.WeaknessCounter = {0, 0, 0, 0, 0}
		end
		if not vars.RemainingFood then
			vars.RemainingFood = Party.Food
		end

		-- Remove old debuff timers
		for key, _ in pairs(DebuffTimers) do
			RemoveTimer(DebuffTimers[key])
		end
		DebuffTimers = {}
		activeDebuffs = {}
		
		for slot, _ in pairs(UnconsciousTimers) do
			RemoveTimer(UnconsciousTimers[slot])
			UnconsciousTimers[slot] = nil
		end

		-- Apply weakness from food depletion during travel
		if Party.Food == 0 and DaysToTravel > vars.RemainingFood then
			for _, pl in Party do
				local slotIdx = pl:GetSlot() + 1
				if vars.WeaknessCounter[slotIdx] == 0
				   and pl.Conditions[const.Condition.Dead] == 0
				   and pl.Conditions[const.Condition.Eradicated] == 0
				   and pl.Conditions[const.Condition.Zombie] == 0 then
					pl.Conditions[const.Condition.Weak] = Game.Time
						- const.Day * DaysToTravel + const.Day * vars.RemainingFood
					vars.WeaknessCounter[slotIdx] = pl.Conditions[const.Condition.Weak]
				else
					pl.Conditions[const.Condition.Weak] = vars.WeaknessCounter[slotIdx]
					vars.WeaknessCounter[slotIdx] = 0
				end
			end
		end

		-- Scan for active conditions and launch missing timers
		scanDebuffs()

		-- Periodic scanning (each minute ~ 2 sec real time): debuffs, weakness, stat loss
		if scanTimerFunc then
			RemoveTimer(scanTimerFunc)
		end
		scanTimerFunc = function()
			scanDebuffs()
			for _, pl in Party do
				checkWeakness(pl)
			end
			checkStatLoss()
		end
		Timer(scanTimerFunc, const.Minute, true)
	end
	
	-- Monsters launch projectiles with random speed and spread

	local ArrowProjectiles = {[545] = true, [550] = true, [565] = true}

	local function modifyProjectile(d, checkArrows)
		if not vars.StoreC then
			vars.StoreC = {0, 0, 0, 0, 0, 0, -1, 0, 0}
		end

		local proj   = d.ecx
		local speed  = d.eax
		local angle  = mem.i4[d.edi + 0x18]
		local vector = d.edx

		-- Projectile acceleration
		local speedMult = math.ceil(1000 * math.log10(10000 - speed) / math.log10(speed / 100))
		local acceleration = math.ceil(speed * math.random(0, speedMult - 1000) / 1000)
			* math.random(100, 200) / 100
		speed = speed + acceleration

		-- Angle spread (dependent on Party z-speed)
		local angleSpread = math.random(-32, 32) * math.max(0.25, vars.StoreC[9] / 100)
		angle = angle + angleSpread

		-- Arrow trajectory correction
		if checkArrows and ArrowProjectiles[proj] then
			angle = angle + 16
		end

		-- Vector spread (dependent on total Party speed)
		local vectorSpread = math.random(-64, 64) * math.max(0.25, vars.StoreC[8] / 100)
		vector = vector + vectorSpread

		d.eax = speed
		mem.i4[d.edi + 0x18] = angle
		d.edx = vector
	end

	function Speedometer()
		if not vars.StoreC then
			vars.StoreC = {0, 0, 0, 0, 0, 0, -1}
		end
		if vars.StoreC[7] == -1 then
			vars.StoreC[1] = Party.X
			vars.StoreC[2] = Party.Y
			vars.StoreC[3] = Party.Z
			vars.StoreC[7] = 1
		elseif vars.StoreC[7] == 1 then
			vars.StoreC[4] = Party.X
			vars.StoreC[5] = Party.Y
			vars.StoreC[6] = Party.Z
			vars.StoreC[7] = -1
		end
		local dx = vars.StoreC[7] * vars.StoreC[1] - vars.StoreC[7] * vars.StoreC[4]
		local dy = vars.StoreC[7] * vars.StoreC[2] - vars.StoreC[7] * vars.StoreC[5]
		local dz = vars.StoreC[7] * vars.StoreC[3] - vars.StoreC[7] * vars.StoreC[6]
		vars.StoreC[8] = math.sqrt(dx * dx + dy * dy + dz * dz)
		vars.StoreC[9] = dz
	end

	function events.AfterLoadMap()
		Timer(Speedometer, const.RTSecond / 8, true)
	end

	mem.autohook(0x404e4e, function(d)  -- launch object (spells)
		modifyProjectile(d, false)
	end)

	mem.autohook(0x404cbb, function(d)  -- launch object (spell-like projectiles and arrows)
		modifyProjectile(d, true)
	end)

	mem.autohook(0x404cf7, function(d)  -- launch object (?)
		modifyProjectile(d, false)
	end)

	mem.autohook(0x404d1f, function(d)  -- launch object (non-magical projectiles)
		modifyProjectile(d, true)
	end)

	

	-- New Game, After Party Death and Monster Heal after 8 hours in loc
	
	function events.DeathMap()
		for _,pl in Party do
			pl.Conditions[17] = Game.Time - const.Week
		end
	end
	
	function events.AfterLoadMap()
		function RestoreMonstersHPAfter8Hours()
			for i,v in Map.Monsters do
				if v.Id > 0 and v.Id < Game.MonstersTxt.Limit then
					v.HP = v.FullHP
				end
			end
		end
		
		local MonsterKindCustomHPRegen = {
		[1]	= 0.015,	[2]	= 0.015,						--MM8 Lizardmen
		[12] = 0.015, 	[13] = 0.015,	[14] = 0.015, 		--MM8 Ratmen and Bestial Animalists
		[17] = 0.025, 	[18] = 0.025,						--MM8 Vampires
		[20] = 0.040, 	[21] = 0.040,						--MM8 Trolls
		[30] = 0.025,										--MM8 Basilisks
		[32] = 0.015,										--MM8 Serpentmen
		[43] = 0.025,										--MM8 Salamanders
		[44] = 0.040,										--MM8 Phoenixes
		[45] = 0.015,										--MM8 Tritons
		[51] = 0.025,										--MM8 Nightmares
		[76] = 0.015,										--MM7 Dragonflies
		[90] = 0.025,										--MM7 Specters
		[96] = 0.020,										--MM7 Hydras
		[97] = 0.015,										--MM7 Liches
		[104] = 0.020,										--MM7 Ooze
		[129] = 0.015,										--MM7 Rats
		[139] = 0.025,										--MM7 Vampires
		[141] = 0.025,										--MM7 Barrow Wights
		[150] = 0.040,										--MM7 Trolls
		[152] = 0.013,										--MM7 Ghouls
		[153] = 0.025,										--MM7 Blaster Guys
		[166] = 0.040,										--MM6 Agar's Pets (Cockatrices)
		[183] = 0.025,										--MM6 Spectres
		[187] = 0.020,										--MM6 Hydras
		[190] = 0.015,										--MM6 Liches
		[197] = 0.020,										--MM6 Ooze
		[207] = 0.015,										--MM6 Rats
		[209] = 0.020,										--MM7 Sea Serpents
		[215] = 0.030										--MM6 Werewolves
		}
		function RestoreMonstersHP()
			for i,v in Map.Monsters do
				if v.Id > 0 and v.Id < Game.MonstersTxt.Limit then
					local MonsterKind = math.ceil(v.Id/3)
					v.HP = v.HP > 0 and math.min(v.FullHP, v.HP + math.ceil((MonsterKindCustomHPRegen[MonsterKind] ~= nil and MonsterKindCustomHPRegen[MonsterKind] or 0.01)*v.FullHP)) or 0
				end
			end
		end
		Timer(RestoreMonstersHPAfter8Hours, const.Hour*8, true)
		Timer(RestoreMonstersHP, const.Minute*5)
	end
	
	function events.OnLeaveMap()
		RemoveTimer(RestoreMonstersHPAfter8Hours)
		RemoveTimer(RestoreMonstersHP)
	end
	
	function RestoreMonstersHPAfterTempleHeal()
		for i,v in Map.Monsters do
			if v.Id > 0 and v.Id < Game.MonstersTxt.Limit then
				v.HP = v.FullHP
				RemoveTimer(RestoreMonstersHPAfterTempleHeal)
			end
		end
	end
	function events.ClickShopTopic(t)
		if t.Topic == const.ShopTopics.Heal then
			local PlayerId = math.max(Game.CurrentPlayer, 0)
			local PlId = Party[PlayerId]:GetIndex()
			for i = 0,19 do
				Game.PlayersExtra[PlId].Debuffs[i].ExpireTime = 0
			end
			Timer(RestoreMonstersHPAfterTempleHeal, const.Minute/2)
		end
	end
	
	-- Negative conditions and armor penalties affect Blaster accuracy
	function events.CalcStatBonusBySkills(t)
		local Pl = t.Player
		local Cond = Pl:GetMainCondition()
		local ArmorPenalty = (MV.AuxArmorRecoveryPenalty[Pl.Name] or 75)
		if t.Stat == const.Stats.MeleeAttack or t.Stat == const.Stats.RangedAttack then
			if Pl.ItemMainHand > 0 and not Pl.Items[Pl.ItemMainHand].Broken and Game.ItemsTxt[Pl.Items[Pl.ItemMainHand].Number].Skill == 7 then
				if Cond == 1 then
					t.Result = math.min(t.Result - 25, t.Result/3)
				end
				if ArmorPenalty > 75 then
					local AP = ArmorPenalty/75 - 1
					t.Result = round(t.Result - Game.ItemsTxt[Pl.Items[Pl.ItemMainHand].Number].Mod2*AP - t.Result*AP - Game.GetStatisticEffect(Pl:GetAccuracy())*AP)
				end
			end
		end
	end
	-- Heroism: the game adds the buffs' power to the melee damage (get_magic_bonus,
	-- MeleeDamageBase); it is taken out here and given as a share of the weapon damage in
	-- the damage handler (registered in GameInitialized2, after the others)
	function events.CalcStatBonusByMagic(t)
		if t.Stat == const.Stats.MeleeDamageBase and MF.HeroismPower then
			t.Result = t.Result - MF.HeroismPower(t.Player)
		end
	end

	function events.CalcStatBonusByMagic(t)
		local Pl = t.Player
		local Cond = Pl:GetMainCondition()
		local ArmorPenalty = (MV.AuxArmorRecoveryPenalty[Pl.Name] or 75)
		if t.Stat == const.Stats.MeleeAttack or t.Stat == const.Stats.RangedAttack then
			if Pl.ItemMainHand > 0 and not Pl.Items[Pl.ItemMainHand].Broken and Game.ItemsTxt[Pl.Items[Pl.ItemMainHand].Number].Skill == 7 then
				if Cond == 1 then
					t.Result = t.Result/3
				end
				if ArmorPenalty > 75 then
					local AP = ArmorPenalty/75 - 1
					t.Result = round(t.Result - t.Result*AP)
				end
			end
		end
	end
	
	-- Blaster scaling
	local CritC = 0
	local CritD = 0
	local CritCB = 0
	local CritDB = 0
	
	-- Blaster balance (19.10.26). Damage grows with skill and upgrade tier separately
	-- (it used to be skill x tier, which left T1-T2 weak and made T4 explode); crit chance
	-- and crit damage grow with skill; eradication depends on the share of the target's HP
	-- each hit takes, so long fights (bosses) are not eradicated more often than short ones.
	-- 25.10.26: damage, fire rate, eradication and the power cell come from the gun's specs
	-- (MMMWE_Blasters.lua); the Blaster skill gives the attack bonus and critical hits.
	local BLASTER = {
		CritChanceBase   = 5,      -- % base crit chance (30.10.26: was 10)
		CritChancePerSkill = 0.5,  -- % crit chance per point of skill (30.10.26: was 1)
		CritDamagePerSkill = 4,    -- % crit damage per point of skill
		EradCritMul      = 1.5,    -- a critical hit's eradication chance multiplier
		EradMaxPerHit    = 0.5,    -- cap per hit
	}
	MF.BlasterBalance = BLASTER

	-- damage multiplier of a blaster item: the Emitter spec (MMMWE_Blasters.lua)
	local function blasterScale(item)
		return (MF.BlasterDamageMult(item))
	end
	MF.BlasterScale = blasterScale

	-- Damage range of the blaster in the main hand before crits (as CalcBlasterDamage
	-- rolls it), or nil. Also shown on the Stats screen.
	local function blasterRange(Player)
		local slot = Player.ItemMainHand
		if slot <= 0 then return end
		local it = Player.Items[slot]
		if Game.ItemsTxt[it.Number].Skill ~= 7 then return end
		local blasterType = it.Number - select(math.floor(it.Number / 800), 865, 1665)
		local scale = blasterScale(it)
		return round(select(blasterType, 10, 15) * scale), round(select(blasterType, 20, 30) * scale)
	end
	MF.BlasterDamageRange = blasterRange

	function CalcBlasterDamage(Player)
		local item = Player.ItemMainHand
		if item <= 0 then
			return
		end

		local itnum = Player.Items[item].Number
		if Game.ItemsTxt[itnum].Skill ~= 7 then
			return
		end

		local BS, BM = SplitSkill(Player:GetSkill(const.Skills.Blaster))

		-- Blaster stats dependent on type (pistol or rifle)
		local base = math.floor(itnum / 800)
		local blasterType = itnum - select(base, 865, 1665)
		local DMin    = select(blasterType, 10, 15)
		local DMax    = select(blasterType, 20, 30)
		local CDBase  = 50
		local CCBase  = BLASTER.CritChanceBase

		-- Item crit bonus (Bonus2 == 145)
		local specCritC, specCritD = 0, 0
		for eqItem, slot in Player:EnumActiveItems() do
			if eqItem.Bonus2 == 145 then
				specCritC, specCritD = 5, 25
				break
			end
		end

		-- Curse mult
		local curseMult = Player.Conditions[0] > 0 and 0.5 or 1

		-- Damage from the Emitter spec only (the skill adds crits)
		local scale = blasterScale(Player.Items[item])
		DMin = round(DMin * scale)
		DMax = round(DMax * scale)

		-- Crit chance
		local critChance = CCBase + Player:GetAccuracy() / 20 + specCritC
			+ BLASTER.CritChancePerSkill * BS
		critChance = critChance * curseMult
		CritC = critChance

		-- Crit damage mult (percent)
		local critDamageP = CDBase + 100 + specCritD + BLASTER.CritDamagePerSkill * BS
		CritD = critDamageP

		-- Crit hit check
		local critProc = 0
		if critChance > 0 and math.random() * 100 < critChance then
			local mult = critDamageP / 100
			DMin = round(DMin * mult)
			DMax = round(DMax * mult)
			critProc = 1
		end

		return math.random(DMin, DMax), critProc
	end
	
	-- =====================================================================
	-- Monster resistance: percentage-based reduction
	-- =====================================================================

	local resPercentCache = {}

	local function CalcMonResPercent(Res)
		if Res >= 65000 then return 0 end
		if Res <= 0 then return 1 end
		local cached = resPercentCache[Res]
		if cached then return cached end
		local MonEffRes = Res + 30

		local p = 1 - 30 / MonEffRes
		local ResPercent = 1 - (0.5 * p + 0.25 * p^2 + 0.125 * p^3 + 0.0625 * p^4)

		resPercentCache[Res] = ResPercent
		return ResPercent
	end

	-- autohook at 0x4259CF (lea esi, [edx+eax+1Eh]), BEFORE the instruction.
	-- Executed only for non-immune monsters (standard code if immune).
	-- eax + edx is the resistance; zeroing them makes the lea give esi = 30, so the
	-- engine's random halving loop that follows (rand() % (res + 30) >= 30 halves the
	-- damage, up to 4 times) never halves. This was autohook2 (after the lea): esi
	-- already held res + 30, so the old random halving still ran on top of the curve -
	-- found with MMMWE_DamageDiag.lua (ENGINE? lines: curve 15 -> engine 7, 42 -> 10).
	mem.autohook(0x4259CF, function(d)
		local res = d.eax + d.edx
		local damage = mem.i4[d.ebp + 0x10]
		local element = mem.i4[d.ebp + 0x0C]  -- второй параметр monster_resists

		local pct = CalcMonResPercent(res)
		local newDmg = round(damage * pct)
		mem.i4[d.ebp + 0x10] = newDmg

		MF.LogInfo("[RES] elem=%d res=%d dmg=%d -> %d (pct=%.3f)",
			element, res, damage, newDmg, pct)

		-- MMMWE_DamageDiag.lua: every pass of the resistance curve is recorded
		local diag = MF.DamageDiagRes
		if diag then
			diag[#diag + 1] = {Elem = element, Res = res, In = damage, Out = newDmg}
		end

		d.eax = 0
		d.edx = 0
	end)


	-- Weapon crit module

	-- index = skill + 1
	local WCDBase   = {0.500, 0.300, 1.000, 0.500, 0.400, 0.500, 0.700, 0.250}
	-- 19.10.26: Sword chance 0.100 -> 0.120 and damage 0.010 -> 0.014, Dagger damage
	-- 0.020 -> 0.012, Axe chance 0.115 -> 0.090 and damage 0.012 -> 0.016, Bow damage 0.015 -> 0.012
	local WCDGrowth = {0.010, 0.014, 0.012, 0.016, 0.011, 0.012, 0.014, 0.013}
	local WCCBase   = {5.000, 7.000, 10.00, 8.000, 7.000, 5.000, 6.000, 6.000}
	local WCCGrowth = {0.050, 0.120, 0.150, 0.090, 0.125, 0.150, 0.085, 0.120}

	local CrossbowNames = {['Crossbow'] = true, ['Relic Crossbow'] = true}

	-- Damage text pointer for asmpatch
	-- Value of [0x601704] by default (standard damage text)
	local CombatMsgAddr = mem.StaticAlloc(4)
	mem.u4[CombatMsgAddr] = mem.u4[0x601704]
	mem.asmpatch(0x43765c, 'push dword ptr [' .. CombatMsgAddr .. ']')

	local function getCritSpcBonus(pl)
		for item, slot in pl:EnumActiveItems() do
			if item.Bonus2 == 145 then
				return 5, 0.250
			end
		end
		return 0, 0
	end

	local function getCurseMult(pl)
		return pl.Conditions[0] > 0 and 0.5 or 1
	end

	-- Crit sounds by weapon skill (33 = unarmed)
	local CritSounds = {
		[0] = {44640, 44641, 44642, 44643, 44644, 44645},
		[1] = {44628, 44629, 44630, 44631, 44632, 44633},
		[2] = {44622, 44623, 44624, 44625, 44626, 44627},
		[3] = {44610, 44611, 44612, 44613, 44614, 44615},
		[4] = {44646, 44647, 44648, 44649, 44650, 44651},
		[5] = {44605, 44606, 44607, 44608, 44609, 44605},
		[6] = {44616, 44617, 44618, 44619, 44620, 44621},
		[7] = {44674, 44675, 44676, 44677, 44678, 44679, 44680},   -- plasmacrit01..07
		[33] = {44634, 44635, 44636, 44637, 44638, 44639},
	}

	-- Sound object reference of a map monster (index*8 + 3): the game plays the sound on the
	-- monster channels (0-3) at the monster's position, so it doesn't cut off interface sounds
	local function MonSoundRef(Mon)
		return Mon:GetIndex() * 8 + 3
	end

	-- Weapon in a slot that can crit in melee: not broken, skill in the allowed set
	local function critWeapon(pl, slot, allowed)
		if slot <= 0 or pl.Items[slot].Broken then return nil end
		local txt = Game.ItemsTxt[pl.Items[slot].Number]
		if not allowed[txt.Skill] then return nil end
		local S, M = SplitSkill(pl:GetSkill(txt.Skill))
		return txt.Skill, S, M, txt
	end
	local MainCritSkills  = {[0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true}
	local ExtraCritSkills = {[1] = true, [2] = true}   -- swords and daggers

	-- Weapon skill damage (19.10.26): non-blaster weapons deal more damage with skill and
	-- mastery, PerSkillMastery per point of skill x mastery (Novice 1 ... Grand Master 4),
	-- like the weapon crits. Two weapons: the average of both. Unarmed and blasters: none.
	local WEAPON_SKILL_DAMAGE = {PerSkillMastery = 0.02}
	MF.WeaponSkillDamage = WEAPON_SKILL_DAMAGE

	-- damage multiplier of the weapons used for a melee (Melee = true) or bow attack
	local function weaponSkillDamageMult(Pl, Melee)
		local k = WEAPON_SKILL_DAMAGE.PerSkillMastery
		if k <= 0 then return 1 end
		if not Melee then
			local slot = Pl.ItemBow
			if slot <= 0 or Pl.Items[slot].Broken then return 1 end
			local txt = Game.ItemsTxt[Pl.Items[slot].Number]
			if txt.Skill ~= const.Skills.Bow then return 1 end
			local S, M = SplitSkill(Pl:GetSkill(txt.Skill))
			return 1 + k * S * M
		end
		local sum, n = 0, 0
		local sk1, S1, M1 = critWeapon(Pl, Pl.ItemMainHand, MainCritSkills)
		if sk1 then sum, n = sum + S1 * M1, n + 1 end
		local sk2, S2, M2 = critWeapon(Pl, Pl.ItemExtraHand, ExtraCritSkills)
		if sk2 then sum, n = sum + S2 * M2, n + 1 end
		if n == 0 then return 1 end
		return 1 + k * sum / n
	end
	MF.WeaponSkillDamageMult = weaponSkillDamageMult

	-- Crit chance (%, before curse) and damage multiplier of one weapon skill
	-- Master Dagger: crit chance per point of Dagger skill (replaces the engine's 10% triple
	-- damage, removed in MMMWE_WeaponEffects.lua)
	local DAGGER_MASTER_CRIT = 0.2
	MF.DaggerMasterCrit = function() return DAGGER_MASTER_CRIT end

	local function skillCrit(pl, skill, S, M, specC, specD)
		local idx = skill + 1
		if skill == const.Skills.Dagger and M >= 3 then
			specC = specC + DAGGER_MASTER_CRIT * S
		end
		return WCCBase[idx] + WCCGrowth[idx] * S * M + pl:GetAccuracy() / 20 + specC,
			1 + WCDBase[idx] + WCDGrowth[idx] * S * M + specD
	end

	-- Crit stats without rolling: chance (%, before curse), damage multiplier, skill for the sound.
	-- Melee: main-hand weapon (two-handed: +50% crit damage bonus), main + extra-hand
	-- (average of both), extra hand only (half crit damage bonus), unarmed (main hand empty,
	-- no extra-hand weapon; a shield is fine). Ranged: bow / crossbow.
	function MF.GetCritStats(Pl, Melee)
		local specC, specD = getCritSpcBonus(Pl)

		if not Melee then
			local slot = Pl.ItemBow
			if slot <= 0 or Pl.Items[slot].Broken then return 0, 1, nil end
			local txt = Game.ItemsTxt[Pl.Items[slot].Number]
			local S, M = SplitSkill(Pl:GetSkill(txt.Skill))
			local c, d = skillCrit(Pl, txt.Skill, S, M, specC, specD)
			if CrossbowNames[txt.NotIdentifiedName] then
				c = c + 5 + 0.05 * S * M
				d = d + 0.5 + 0.005 * S * M
			end
			return c, d, txt.Skill
		end

		local sk1, S1, M1, txt1 = critWeapon(Pl, Pl.ItemMainHand, MainCritSkills)
		local sk2, S2, M2 = critWeapon(Pl, Pl.ItemExtraHand, ExtraCritSkills)

		-- subtype crit bonuses (WEAPON_BONUSES 4 and 5)
		local function subtype(slot)
			local num = Pl.Items[slot].Number
			return CalcWeaponStatBonusByWType(num, 4), CalcWeaponStatBonusByWType(num, 5)
		end

		if sk1 then
			local c, d = skillCrit(Pl, sk1, S1, M1, specC, specD)
			local mc, md = subtype(Pl.ItemMainHand)
			c, d = c + mc, d + md
			-- two-handed weapons, and a spear held in both hands (nothing in the other hand)
			if txt1.EquipStat == 1 or (sk1 == const.Skills.Spear and Pl.ItemExtraHand == 0) then
				d = (d - 1) * 1.5 + 1
			end
			if sk2 then
				local c2, d2 = skillCrit(Pl, sk2, S2, M2, specC, specD)
				local mc2, md2 = subtype(Pl.ItemExtraHand)
				c, d = (c + c2 + mc2) / 2, (d + d2 + md2) / 2
			end
			return c, d, sk1
		end

		if sk2 then
			local c, d = skillCrit(Pl, sk2, S2, M2, specC, 0)
			local mc, md = subtype(Pl.ItemExtraHand)
			return c + mc, 1 + (d + md - 1) / 2 + specD, sk2
		end

		local main = Pl.ItemMainHand
		if main == 0 or Pl.Items[main].Broken then
			local US, UM = SplitSkill(Pl:GetSkill(const.Skills.Unarmed))
			if US > 0 and UM > 0 then
				local c, d = skillCrit(Pl, 7, US, UM, specC, specD)  -- index 8 = unarmed
				return c, d, 33
			end
		end

		return 0, 1, nil
	end

	-- Updates the character screen values; with a monster also rolls the crit and
	-- returns the damage multiplier (1 when no crit)
	function CalcCrits(Player, Melee, Mon)
		local c, d, sndSkill = MF.GetCritStats(Player, Melee)
		local chance = c * getCurseMult(Player)

		if Melee then
			CritC, CritD = chance, d * 100
		else
			CritCB, CritDB = chance, d * 100
		end

		if not Mon then
			return 1
		end

		if chance > 0 and math.random() * 100 < chance then
			local snd = sndSkill and CritSounds[sndSkill]
			if snd and Game.CurrentScreen ~= 7 then
				Game.PlaySound(snd[math.random(1, #snd)], MonSoundRef(Mon))
			end
			return d
		end
		return 1
	end

	-- Durability damage penalty: a worn / damaged weapon or bow deals less damage.
	-- The penalty size comes from ItemDurability.lua (MF.GetWeaponPenalty, 0 if absent).
	-- It is applied from here, at the very end of the handler, so it scales the final damage
	-- after the high-ground / might bonus and crit logic of this script.
	local function applyPenalty(t, it)
		if t.IsSecondary then return end  -- enchantment damage (MMMWE_ConcurrentEnchantments.lua)
		local p = MF.GetWeaponPenalty and MF.GetWeaponPenalty(it) or 0
		if p > 0 then
			t.Result = round(t.Result * (1 - p))
		end
	end

	
	function events.CalcDamageToMonster(t)

		mem.u4[CombatMsgAddr] = mem.u4[0x601704]

		if not t.ByPlayer then
			return
		end

		-- an empty blaster's bash or a Chain disruption hit (MMMWE_Blasters.lua)
		if MF.BlasterSpecs and MF.BlasterSpecs.Forced then
			t.Result = MF.BlasterSpecs.Forced
			return
		end

		local Pl = t.Player
		local Melee = t.Melee

		-- the Body damage of Hammerhands: already the hit's full physical damage
		if MF.HammerhandsHit and t.DamageKind == const.Damage.Body then
			return
		end

		-- Skip secondary calls (from ItemAdditionalDamage enchantment processing)
		-- These are enchantment damage calls where the engine already applied
		-- the correct damage kind via the ItemAdditionalDamage hook.
		-- We must not apply crits, high ground, or durability penalties to them.
		-- (marked by MMMWE_ConcurrentEnchantments.lua, Part 3b)
		if t.IsSecondary then
			return
		end

		if t.DamageKind == const.Damage.Phys or Melee then
			if not Melee then
				local HighGround = Party.Z - t.Monster.Z
				local isCrossbow = Pl.ItemBow > 0
					and CrossbowNames[Game.ItemsTxt[Pl.Items[Pl.ItemBow].Number].NotIdentifiedName]
				local DamageBonusStat = {
					[1] = Game.GetStatisticEffect(Pl:GetMight()),
					[2] = math.floor(Game.GetStatisticEffect(Pl:GetMight())/2),
				}
				-- t.Result has already passed the monster's resistance (t.Damage is the
				-- damage before it), so the Might bonus added here goes through the same
				-- check: it is scaled by the fraction of this hit's damage that got through
				-- (0 for an immune monster).
				local resFactor = t.Damage and t.Damage > 0 and math.max(0, t.Result) / t.Damage or 0
				local mightBonus = (isCrossbow and DamageBonusStat[2] or DamageBonusStat[1]) * resFactor
				t.Result = round(t.Result + t.Result*HighGround/4000 + mightBonus)
			end
			t.Result = t.Result * weaponSkillDamageMult(Pl, Melee)
			t.Result = math.max(0, round(t.Result * CalcCrits(Pl, Melee, t.Monster)))

			local slot = Melee and Pl.ItemMainHand or Pl.ItemBow
			if slot > 0 then
				applyPenalty(t, Pl.Items[slot])
			end
		elseif t.DamageKind == const.Damage.Energy then
			local mainHand = Pl.ItemMainHand
			if mainHand > 0 and Game.ItemsTxt[Pl.Items[mainHand].Number].Skill == 7
			   and not Pl.Items[mainHand].Broken then
				local CritProc = 0
				t.Result, CritProc = CalcBlasterDamage(Pl)

				-- Disruptor spec (Emitter 4: crits count half the Body resistance and
				-- eradicate at tier 1 strength without a Disruptor), MMMWE_Blasters.lua
				local eradStrength, bodyMul = MF.BlasterEradication(Pl.Items[mainHand], CritProc == 1)
				local Mon = t.Monster
				-- Eradication: tier x Body resistance factor x (share of the full HP this hit
				-- takes) x (share of HP already lost) x 2. Over a whole fight the shares add up
				-- to about 1, so the chance per kill does not depend on how many hits it takes.
				local eradicationChance = 0
				if eradStrength > 0 and Mon.FullHP > 0 and Mon.HP > 0 then
					local lost = math.max(0, 1 - Mon.HP / Mon.FullHP)
					local share = math.min(t.Result, Mon.HP) / Mon.FullHP
					local body = Mon.BodyResistance
					if body < 65000 then body = math.floor(body * bodyMul) end
					eradicationChance = eradStrength
						* CalcMonResPercent(body) * share * lost * 2
					if CritProc == 1 then
						eradicationChance = eradicationChance * BLASTER.EradCritMul
					end
					eradicationChance = math.min(eradicationChance, BLASTER.EradMaxPerHit)
				end

				local eradicated = eradicationChance > 0 and math.random() < eradicationChance
				-- a critical hit's sound (plasmacrit01..07); an eradication has its own sound
				if CritProc == 1 and not eradicated and Game.CurrentScreen ~= 7 then
					local snd = CritSounds[7]
					Game.PlaySound(snd[math.random(1, #snd)], MonSoundRef(Mon))
				end
				if eradicated then
					local hit = t.Result
					t.Result = Mon.HP
					if MF.BlasterChain then MF.BlasterChain(Pl, Mon, hit) end
					Game.PlaySound(math.random(44671,44673), MonSoundRef(Mon))   -- blastercrit01..03
					Mon:ChangeLook(241)
					Mon:SetCustomFrames(nil, nil, nil, nil, nil, nil, 'm203x', 'm207d', nil)
					mem.u4[CombatMsgAddr] = mem_cstring(string.format(
						"%s eradicates %s", Pl.Name, Game.MonstersTxt[Mon.Id].Name))
				end
			end
		end
	end

	-- Longbows have less Attack penalty at long range
	--MV.TestVar = {0,0,0,0,0,0,0,0}
	--mem.autohook2(0x42577b, function(d)
	--	local Player = MF.GetPlayerFromPtr(mem.u4[d.ebp+0x8])
	--	local Bow = Player.ItemBow
	--	if Bow > 0 and not Player.Items[Bow].Broken and Game.ItemsTxt[Player.Items[Bow].Number].NotIdentifiedName ~= 'Crossbow' and Game.ItemsTxt[Player.Items[Bow].Number].NotIdentifiedName == 'Relic Crossbow' then
	--		MV.TestVar[1] = d.eax
	--		d.eax = round(d.eax/1.5)
	--		MV.TestVar[2] = d.eax
	--		MV.TestVar[3] = Player:GetIndex()
	--		MV.TestVar[7] = mem.i4[d.ebp+0x10]
	--	end
	--end)
	--mem.autohook2(0x425790, function(d)
	--	local Player = MF.GetPlayerFromPtr(mem.u4[d.ebp+0x8])
	--	local Bow = Player.ItemBow
	--	if Bow > 0 and not Player.Items[Bow].Broken and Game.ItemsTxt[Player.Items[Bow].Number].NotIdentifiedName ~= 'Crossbow' and Game.ItemsTxt[Player.Items[Bow].Number].NotIdentifiedName == 'Relic Crossbow' then
	--		MV.TestVar[4] = d.eax
	--		d.eax = round(d.eax/1.5)
	--		MV.TestVar[5] = d.eax
	--		MV.TestVar[6] = Player:GetIndex()
	--		MV.TestVar[8] = mem.i4[d.ebp+0x10]
	--	end
	--end)
	
	-- Damage reduction module

	mem.asmpatch(0x48ceb2, "fmul dword ptr [0x4e84cc]") -- Remove Plate Master phys damage reduction
	mem.asmpatch(0x48cece, "fmul dword ptr [0x4e84cc]") -- Remove Chain Grand phys damage reduction
	mem.asmpatch(0x42591b, "sub eax, 2000")              -- Monsters always hit with normal attacks

	-- Auxiliary armor dodge penalty mapped by Skill ID -> {Normal, Expert, Master, GM}
	local AuxArmorDodgePenalty = {
		[const.Skills.Leather]		= {5, 0, 0, 0},
		[const.Skills.Chain]		= {10, 5, 0, 0},
		[const.Skills.Plate]		= {15, 7.5, 7.5, 0},
	}

	local AbsorbStrength = {0.2, 0.4, 0.6, 0.8, 1.0}

	-- Helper function to fetch stat values using correct MMExtension Player methods
	local function GetPlayerStatByRes(pl, resStat)
		if resStat == const.Stats.FireResistance or resStat == const.Stats.AirResistance then
			return pl:GetSpeed()
		elseif resStat == const.Stats.WaterResistance or resStat == const.Stats.BodyResistance then
			return pl:GetEndurance()
		elseif resStat == const.Stats.EarthResistance then
			return pl:GetMight()
		elseif resStat == const.Stats.SpiritResistance or resStat == const.Stats.MindResistance then
			return pl:GetPersonality()
		elseif resStat == const.Stats.LightResistance or resStat == const.Stats.DarkResistance then
			return pl:GetLuck()
		end
		return pl:GetLuck()
	end

	-- Damage Kind -> Damage reduction category
	local DamageCategory = {
		[const.Damage.Phys]   = "physical",
		[const.Damage.Fire]   = "elemental",
		[const.Damage.Air]    = "elemental",
		[const.Damage.Water]  = "elemental",
		[const.Damage.Earth]  = "elemental",
		[const.Damage.Spirit] = "elemental",
		[const.Damage.Mind]   = "elemental",
		[const.Damage.Body]   = "elemental",
		[const.Damage.Light]  = "elemental",
		[const.Damage.Dark]   = "elemental",
		[const.Damage.Energy] = "energy",
	}

	-- Damage Kind labels for output (Identify Monster)
	local DamageTypeNames = {
		[const.Damage.Phys]   = "physical",
		[const.Damage.Fire]   = "fire",
		[const.Damage.Air]    = "air",
		[const.Damage.Water]  = "water",
		[const.Damage.Earth]  = "earth",
		[const.Damage.Spirit] = "spirit",
		[const.Damage.Mind]   = "mind",
		[const.Damage.Body]   = "body",
		[const.Damage.Light]  = "light",
		[const.Damage.Dark]   = "dark",
		[const.Damage.Energy] = "energy",
	}

	-- Mapping DamageKind to const.Stats resistance index
	local DamageKindToRes = {
		[const.Damage.Fire]   = const.Stats.FireResistance,
		[const.Damage.Air]    = const.Stats.AirResistance,
		[const.Damage.Water]  = const.Stats.WaterResistance,
		[const.Damage.Earth]  = const.Stats.EarthResistance,
		[const.Damage.Spirit] = const.Stats.SpiritResistance,
		[const.Damage.Mind]   = const.Stats.MindResistance,
		[const.Damage.Body]   = const.Stats.BodyResistance,
		[const.Damage.Light]  = const.Stats.LightResistance,
		[const.Damage.Dark]   = const.Stats.DarkResistance,
	}

	-- Calculate avg damage reduction by resistances
	local function CalcResME(pl, resistanceStat)
		local resValue = pl:GetResistance(resistanceStat)
		local statVal = GetPlayerStatByRes(pl, resistanceStat)

		local effectiveRes = 30 + Game.GetStatisticEffect(statVal) + resValue
		if effectiveRes < 30 or resValue <= 0 then
			effectiveRes = 30
		end

		local probability = 1 - (30 / effectiveRes)
		local reduction = {0.5, 0.25, 0.125, 0.0625}
		local resME = 0

		for i = 1, 4 do
			resME = resME + reduction[i] * (probability ^ i)
		end
		return resME * 100
	end

	-- Capture damage state before engine resistance checks
	local DamageBeforeRes = 0
	mem.autohook(0x48d0af, function(d)
		DamageBeforeRes = mem.i4[d.ebp + 0x8]
		if MV then MV.DBR = DamageBeforeRes end
	end)

	-- Durability calculation with respect towards hardening 
	local function CalcDurability(pl, slot)
		if slot <= 0 or pl.Items[slot].Broken then
			return 0
		end
		local item = pl.Items[slot]
		local dur = MF.GetBaseDurability(item.Number)
		if item.Hardened then
			dur = math.max(dur * 1.25, 10)
		end
		return math.max(dur - MF.GetItemWear(item), 0)
	end

	-- Dodge chance calculation
	-- =====================================================================
	-- Dodging extras
	-- =====================================================================
	local DODGE = {
		SpeedPerPoint  = 0.5,   -- +% dodge chance per point of Speed bonus (negative bonus lowers it)
		CondPenalty    = {      -- -% dodge chance while the character has the condition
			[const.Condition.Weak] = 10, [const.Condition.Afraid] = 10, [const.Condition.Drunk] = 10,
		},
		HasteBonus     = 10,    -- +% while the party is hasted
		KindBonus      = {Blunt = 10},  -- +% against melee hits of this kind (slow, heavy blows)
		MissilePenalty = 10,    -- -% against arrows, bolts and other physical projectiles
		ElementalMissilePenalty = 20,  -- -% against elemental projectiles (fire arrows, breath, bolt spells)
		FullDodge      = {[2] = 10, [3] = 20, [4] = 30},  -- % of successful dodges that avoid the hit completely (by mastery)
		RiposteChance  = 50,    -- Grand Master: % chance to strike back after fully dodging a melee hit
		RiposteDamage  = 0.5,   -- share of the counterattack's normal damage
		-- spells that can be dodged (single-target bolts); area spells and Armageddon can't
		BoltSpells = {[2] = true, [15] = true, [18] = true, [26] = true, [29] = true, [37] = true,
			[39] = true, [59] = true, [65] = true, [70] = true, [76] = true, [78] = true,
			[93] = true, [103] = true, [111] = true},
	}
	MF.DodgeSettings = DODGE

	-- Speed, conditions and Haste (also used by the character screen)
	function MF.DodgeChanceMods(pl)
		local m = DODGE.SpeedPerPoint * Game.GetStatisticEffect(pl:GetSpeed())
		for cond, pen in pairs(DODGE.CondPenalty) do
			if pl.Conditions[cond] ~= 0 then m = m - pen end
		end
		local haste = Party.SpellBuffs[const.PartyBuff.Haste]
		if haste and haste.ExpireTime > Game.Time then m = m + DODGE.HasteBonus end
		if MF.ArmorDodgeMod then m = m + MF.ArmorDodgeMod(pl) end   -- MMMWE_ArmorEffects.lua
		if MF.StanceDodgeMod then m = m + MF.StanceDodgeMod(pl) end -- MMMWE_Resources.lua
		return m
	end

	-- Can the hit being dealt to the party right now be dodged? Weapon hits, projectiles of
	-- any kind (elemental ones with a bigger penalty) and bolt spells: yes. Area spells,
	-- traps, falling, Armageddon (no attacker): no. Second value: the attacker info.
	local function CanDodgeHit(t)
		if not WhoHitPlayer then return true end
		local who = WhoHitPlayer()
		if type(who) ~= "table" then return false end
		if who.Spell and who.Spell ~= 0 then return DODGE.BoltSpells[who.Spell] == true, who end
		if who.Object then return true, who end
		if who.Monster then return true, who end
		return false, who
	end

	-- Grand Master riposte: carried out on the next tick, outside the monster's attack
	local RiposteQueue, RiposteActive = {}, false
	local RiposteVec = mem.StaticAlloc(12)   -- zero velocity for the hit routine
	function events.Tick()
		if #RiposteQueue == 0 then return end
		local q = RiposteQueue
		RiposteQueue = {}
		for _, r in ipairs(q) do
			local pl, mon = Party.PlayersArray[r.pi], Map.Monsters[r.mi]
			if pl and mon and mon.HP > 0 and pl:IsConscious() then
				Game.ShowStatusText(r.msg or string.format("%s dodges and strikes back!", pl.Name), 3)
				RiposteActive = r.mult or DODGE.RiposteDamage
				local ok, err = pcall(mem.call, 0x436E26, 2, r.pi * 8 + 4, r.mi, RiposteVec)  -- party hits monster
				RiposteActive = false
				if not ok then MF.LogWarning("Riposte failed: %s", tostring(err)) end
			end
		end
	end
	-- counterattack of other origins (small shields, MMMWE_Shields.lua; Flurry of blows,
	-- MMMWE_UnarmedGM.lua): the same rules; mult is the share of the hit's damage
	-- (DODGE.RiposteDamage when not given)
	function MF.QueueCounterAttack(pi, mi, msg, mult)
		RiposteQueue[#RiposteQueue + 1] = {pi = pi, mi = mi, msg = msg, mult = mult}
	end
	-- the damage share of the counterattack being carried out, or false
	function MF.CounterAttackActive() return RiposteActive end
	-- base damage of a melee hit for Heroism: the average of the game's melee damage range
	-- (weapon dice and bonus of both hands, Might, the weapon skill and Armsmaster bonuses;
	-- Heroism itself is taken out in CalcStatBonusByMagic) times the weapon skill damage
	-- multiplier; bare hands: 2 + the Unarmed skill bonus + Might
	local function baseMeleeDamage(pl)
		local might = Game.GetStatisticEffect(pl:GetMight())
		if pl.ItemMainHand == 0 then
			local hasWeapon = pl.ItemExtraHand ~= 0 and not pl.Items[pl.ItemExtraHand].Broken
				and Game.ItemsTxt[pl.Items[pl.ItemExtraHand].Number].Skill ~= const.Skills.Shield
			if not hasWeapon then
				local us, um = SplitSkill(pl:GetSkill(const.Skills.Unarmed))
				return math.max(0, 2 + (um >= 3 and us * 2 or um == 2 and us or 0) + might)
			end
		end
		local avg = (pl:GetMeleeDamageMin() + pl:GetMeleeDamageMax()) / 2
		return math.max(0, avg * (MF.WeaponSkillDamageMult and MF.WeaponSkillDamageMult(pl, true) or 1))
	end
	MF.BaseMeleeDamage = baseMeleeDamage

	-- the counterattack deals only a share of its damage; registered late so it scales the final value
	function events.GameInitialized2()
		-- Heroism: + a share of the base weapon damage, through the monster's resistance
		-- (the share of this hit's damage that got through)
		function events.CalcDamageToMonster(t)
			if MF.HammerhandsHit and t.DamageKind == const.Damage.Body then
				MF.HammerhandsHit = false
				return
			end
			if not t.ByPlayer or t.IsSecondary then return end
			if t.DamageKind ~= const.Damage.Phys or (t.Result or 0) <= 0 then return end
			local pl = t.Player
			if not pl then return end
			local melee = t.Melee
			if melee == nil then
				local who = WhoHitMonster and WhoHitMonster()
				melee = type(who) == "table" and not who.Object
			end
			if not melee then return end
			local pct = MF.HeroismPerPower() * MF.HeroismPower(pl)
			if pct <= 0 then return end
			local through = (t.Damage and t.Damage > 0) and math.min(1, t.Result / t.Damage) or 1
			t.Result = t.Result + round(pct * baseMeleeDamage(pl) * through)
		end

		function events.CalcDamageToMonster(t)
			if RiposteActive and t.ByPlayer then
				t.Result = round(t.Result * RiposteActive)
			end
		end
	end

	local function CalcDodgeChance(pl, armorChest, shield, shieldM, dodgeS, dodgeM, curseMult)
		local cond = pl:GetMainCondition()
		if dodgeM <= 0 or cond == const.Condition.Asleep or (cond >= const.Condition.Paralyzed and cond <= const.Condition.Eradicated) then
			return -1
		end

		local chance = math.min(42.5 + 0.125 * dodgeS * dodgeM, 20 + 0.5 * dodgeS * dodgeM)

		-- Shield and Armor penalty lookups
		local protSkills = {
			const.Skills.Shield,
			const.Skills.Leather,
			const.Skills.Chain,
			const.Skills.Plate
		}
		local penalties = {10, 0, 0, 0, 10, 0, 0, 0, 20, 10, 0, 0, 30, 15, 15, 0}

		if shield > 0 and not pl.Items[shield].Broken then
			local shTxt = Game.ItemsTxt[pl.Items[shield].Number]
			if shTxt.Skill == const.Skills.Shield then
				chance = chance - (penalties[math.max(shieldM, 1)] or 0)
					- MF.ShieldExtraPenalty(pl.Items[shield].Number, shieldM)   -- MMMWE_Shields.lua
			end
		end

		-- Armor penalty
		if armorChest > 0 and not pl.Items[armorChest].Broken then
			local armSkill = MF.ArmorPieceSkill(pl, pl.Items[armorChest].Number)
			for i = 1, 3 do
				if armSkill == protSkills[i + 1] then
					local _, armM = SplitSkill(pl:GetSkill(armSkill))
					chance = chance - penalties[armM + 4 * i]
				end
			end
		end

		-- Auxiliary armor penalty
		local auxSlots = {pl.ItemHelm, pl.ItemBelt, pl.ItemGauntlets, pl.ItemBoots}
		for _, slotIdx in ipairs(auxSlots) do
			if slotIdx > 0 and not pl.Items[slotIdx].Broken then
				local skill = Game.ItemsTxt[pl.Items[slotIdx].Number].Skill
				local pen = AuxArmorDodgePenalty[skill]
				if pen then
					local _, m = SplitSkill(pl:GetSkill(skill))
					chance = chance - pen[math.max(m, 1)]
				end
			end
		end

		return math.max(0, chance * curseMult)
	end

	-- Weapon Parry calculations
	-- One source of truth for parry: used by the combat roll (CalcWeaponParry) and by the
	-- character screen (Par value). Covers: one weapon in the main hand, a two-handed weapon,
	-- one weapon in the extra hand only, and dual-wielded weapons.
	local NoParrySkills = {
		[const.Skills.Bow] = true, [const.Skills.Blaster] = true, [const.Skills.Shield] = true,
		[const.Skills.Unarmed] = true, [const.Skills.DragonAbility] = true,
	}

	-- Usable parrying weapon in a slot, or nil (empty, broken, shield, blaster, ...)
	local function ParryWeapon(pl, slot)
		if slot <= 0 then return nil end
		local it = pl.Items[slot]
		if it.Broken then return nil end
		local txt = Game.ItemsTxt[it.Number]
		if NoParrySkills[txt.Skill] or (txt.EquipStat ~= 0 and txt.EquipStat ~= 1) then
			return nil
		end
		local s, m = SplitSkill(pl:GetSkill(txt.Skill))
		return {Num = it.Number, Txt = txt, Skill = txt.Skill, S = s, M = m,
			Damage = txt.Mod1DiceCount * txt.Mod1DiceSides + txt.Mod2}
	end

	-- Returns nil if the character can't parry, otherwise a table:
	-- Chance (%, before curse), Phys/Magic/Energy (parry power, %), Mastery (gates magic/energy
	-- parry), Skill (weapon skill, for sounds)
	function MF.GetParryProfile(pl)
		local cond = pl:GetMainCondition()
		if cond == const.Condition.Asleep
				or (cond >= const.Condition.Paralyzed and cond <= const.Condition.Eradicated) then
			return nil
		end

		local w1 = ParryWeapon(pl, pl.ItemMainHand)
		local w2 = ParryWeapon(pl, pl.ItemExtraHand)
		if not w1 and not w2 then
			return nil
		end

		local p = {}
		if w1 and w2 then
			-- dual-wield: half of each weapon's chance, average of their power, +10 / +20 base
			p.Chance = 10
				+ 0.5 * (w1.S * w1.M + CalcWeaponStatBonusByWType(w1.Num, 1))
				+ 0.5 * (w2.S * w2.M + CalcWeaponStatBonusByWType(w2.Num, 1))
			p.Phys = 20
				+ 0.5 * (w1.Damage + CalcWeaponStatBonusByWType(w1.Num, 3))
				+ 0.5 * (w2.Damage + CalcWeaponStatBonusByWType(w2.Num, 3))
			-- magic/energy parry: the better of the two masteries (they only differ when the
			-- weapons are of different types); the sound follows that weapon
			if w2.M > w1.M then
				p.Mastery, p.Skill = w2.M, w2.Skill
			else
				p.Mastery, p.Skill = w1.M, w1.Skill
			end
		else
			-- single weapon: main hand, two-handed, or extra hand only
			local w = w1 or w2
			p.Chance = 20 + CalcWeaponStatBonusByWType(w.Num, 1) + 0.5 * w.S * w.M
			p.Phys = 10 + CalcWeaponStatBonusByWType(w.Num, 3) + w.Damage
			if w.Txt.EquipStat == 1 then
				p.Phys = p.Phys * 1.25
			end
			p.Mastery = w.M
			p.Skill = w.Skill
		end
		p.Magic = p.Phys * (2 / 3)
		p.Energy = p.Phys / 3
		if MF.StanceDefendBonus then p.Chance = p.Chance + MF.StanceDefendBonus(pl) end   -- MMMWE_Resources.lua
		return p
	end

	-- Returns physical, magic and energy damage multipliers and the parrying weapon skill
	local function CalcWeaponParry(pl, curseMult)
		local p = MF.GetParryProfile(pl)
		if not p then
			return 1, 1, 1
		end

		local physDR, magicDR, energyDR = 1, 1, 1
		if math.random() * 100 < p.Chance * curseMult then
			-- parry power above 100% must not turn damage into healing
			physDR = math.max(0, 1 - 0.01 * p.Phys)
			if p.Mastery >= const.Master then
				magicDR = math.max(0, 1 - 0.01 * p.Magic)
			end
			if p.Mastery == const.GM then
				energyDR = math.max(0, 1 - 0.01 * p.Energy)
			end
			return physDR, magicDR, energyDR, p.Skill
		end

		return physDR, magicDR, energyDR
	end

	-- Shield block: MF.ShieldBlock (MMMWE_Shields.lua)

	-- Energy Shield: 30.10.26 the shield has its own capacity and absorbs the final damage
	-- (MMMWE_EnergyShield.lua); it no longer takes a share of each hit from the spell points
	local function CalcEnergyShieldDR(pl, damageTotal, dodgeDR, weaponDR, shieldDR, absStr)
		return 1, 0
	end

	-- Main Handler
	function events.CalcDamageToPlayer(t)
		local pl = t.Player
		local damageTotal = DamageBeforeRes
		local curseMult = pl.Conditions[const.Condition.Cursed] > 0 and 0.5 or 1  -- cursed at all

		-- --- Resistances ---
		local resStat = DamageKindToRes[t.DamageKind]
		if resStat then
			local resBase = pl:GetBaseResistance(resStat)
			local resME = CalcResME(pl, resStat) / 100
			local overkill = damageTotal - resBase

			if damageTotal <= resBase then
				t.Result = round(damageTotal - damageTotal * resME)
			else
				local resEffect = math.max(0.5, 1 - (overkill / damageTotal))
				t.Result = round(resBase - resBase * resME + overkill - overkill * resME * resEffect)
			end
		end

		-- --- Dodging ---
		local dodgeS, dodgeM = SplitSkill(pl:GetSkill(const.Skills.Dodging))
		local shieldS, shieldM = SplitSkill(pl:GetSkill(const.Skills.Shield))
		local dodgeDR = 1

		local dodgeChance = CalcDodgeChance(pl, pl.ItemArmor, pl.ItemExtraHand, shieldM, dodgeS, dodgeM, curseMult)
		local dodgeable, hitBy = CanDodgeHit(t)

		-- the hit misses completely: Shadow Clone (MMMWE_Resources.lua), Grand Master Unarmed
		-- evasion of melee hits and physical missiles (MMMWE_UnarmedGM.lua). The monster's
		-- special effect of the same attack (poison, ...) is cancelled too (MF.MissedPlayer).
		local areaSpell = type(hitBy) == "table" and hitBy.Spell and hitBy.Spell ~= 0
			and not DODGE.BoltSpells[hitBy.Spell]
		local missText
		if MF.ShadowCloneAbsorb and MF.ShadowCloneAbsorb(pl, hitBy, areaSpell) then
			missText = "%s's shadow clone takes the blow!"
		elseif MF.UnarmedEvade and MF.UnarmedEvade(pl, t, hitBy, curseMult) then
			missText = "%s evades the attack!"
		end
		if missText then
			t.Result = 0
			MF.MissedPlayer = pl["?ptr"]
			pl:ShowFaceAnimation(6)
			Game.PlaySound(16060, 0)
			Game.ShowStatusText(string.format(missText, pl.Name), 5)
			return
		end

		-- Ninja's Evasion (MMMWE_MonkBranches.lua): area spells can be dodged, at half the chance
		local halfDodge = false
		if not dodgeable and areaSpell and MF.NinjaEvasion and MF.NinjaEvasion(pl) then
			dodgeable, halfDodge = true, true
		end

		if not dodgeable then
			dodgeChance = 0
		elseif dodgeChance >= 0 then
			dodgeChance = dodgeChance + MF.DodgeChanceMods(pl) * curseMult
			if hitBy and hitBy.Object and t.DamageKind ~= const.Damage.Phys then
				dodgeChance = dodgeChance - DODGE.ElementalMissilePenalty
			elseif t.DamageKind == const.Damage.Phys then
				if hitBy and hitBy.Object then
					dodgeChance = dodgeChance - DODGE.MissilePenalty
				else
					local kind = MF.IncomingPhysKind and MF.IncomingPhysKind()
					dodgeChance = dodgeChance + (kind and DODGE.KindBonus[kind] or 0)
				end
			end
			dodgeChance = math.min(math.max(0, dodgeChance), 95)
			if halfDodge then dodgeChance = dodgeChance / 2 end
		end
		local fullDodge = false
		if dodgeChance > 0 and math.random() * 100 < dodgeChance then
			dodgeDR = 1 - 0.01 * (10 + 10 * dodgeM)
			local full = DODGE.FullDodge[dodgeM]
			if full and math.random() * 100 < full then
				dodgeDR, fullDodge = 0, true
				-- Grand Master: chance to strike back at a monster that missed in melee
				if dodgeM >= 4 and hitBy and hitBy.Monster and not hitBy.Object
						and (hitBy.MonsterAction or 0) <= 1 and hitBy.MonsterIndex
						and t.PlayerIndex and math.random() * 100 < DODGE.RiposteChance then
					RiposteQueue[#RiposteQueue + 1] = {pi = t.PlayerIndex, mi = hitBy.MonsterIndex}
				end
			end
		end

		-- --- Weapon Parry & Shield Block ---
		local weaponPhysDR, weaponMagicDR, weaponEnergyDR, parrySkill = CalcWeaponParry(pl, curseMult)
		local shieldPhysDR, shieldMagicDR, shieldEnergyDR = MF.ShieldBlock(pl, t, curseMult)   -- MMMWE_Shields.lua
		if MF.OnDefended then   -- Knights' Resolve (MMMWE_Resources.lua)
			if parrySkill then MF.OnDefended(pl, "parry") end
			if shieldPhysDR < 1 or shieldMagicDR < 1 or shieldEnergyDR < 1 then MF.OnDefended(pl, "block") end
		end

		-- --- Energy Shield ---
		local _, medM = SplitSkill(pl:GetSkill(const.Skills.Meditation))
		local absStr = AbsorbStrength[medM + 1] or 0

		-- --- Armor ---
		local armorSlots = {
			{pl.ItemHelm,      0.5},
			{pl.ItemArmor,     1.0},
			{pl.ItemGauntlets, 0.5},
			{pl.ItemBoots,     0.5},
			{pl.ItemBelt,      0.5},
		}
		local totalDur = 0
		for _, entry in ipairs(armorSlots) do
			totalDur = totalDur + CalcDurability(pl, entry[1]) * entry[2]
		end

		local HR = math.ceil(totalDur / MF.HR_DIVISOR)
		local aClass = pl:CalcStatBonusByItems(const.Stats.ArmorClass) 
			+ pl:CalcStatBonusBySkills(const.Stats.ArmorClass)
			+ pl:CalcStatBonusByMagic(const.Stats.ArmorClass) 
			+ Game.GetStatisticEffect(pl:GetSpeed())

		local reducedDamage = damageTotal * math.min(dodgeDR, math.min(weaponPhysDR, shieldPhysDR)) * absStr
		local armorDR
		if reducedDamage <= HR then
			armorDR = (5 + 200 - HR) / (10 + 200 - HR + aClass)
		else
			local apr = math.max(0.25, 1 - (reducedDamage - HR) / reducedDamage)
			armorDR = (5 + 200 - HR * apr) / (5 + 200 - HR * apr + aClass * apr + 5 * apr)
		end

		-- --- Stats & Categories ---
		local mightDR = 1 - 0.01 * Game.GetStatisticEffect(pl:GetMight())
		local category = DamageCategory[t.DamageKind]
		if not category then return end

		local wDR, shDR, arDR, stDR, enshDR, spDrain
		if category == "physical" then
			wDR, shDR, arDR, stDR = weaponPhysDR, shieldPhysDR, armorDR, mightDR
		elseif category == "elemental" then
			wDR, shDR, arDR, stDR = weaponMagicDR, shieldMagicDR, 1, 1
		elseif category == "energy" then
			wDR, shDR, arDR, stDR = weaponEnergyDR, shieldEnergyDR, 1, 1
		end

		enshDR, spDrain = CalcEnergyShieldDR(pl, damageTotal, dodgeDR, wDR, shDR, absStr)

		-- Slashing / piercing / blunt (MMMWE_DamageKinds.lua): the armor worn protects
		-- differently against each kind of physical hit
		local physKind, kindDR = nil, 1
		if category == "physical" and MF.IncomingPhysKind then
			physKind = MF.IncomingPhysKind()
			if physKind then kindDR = MF.ArmorKindFactor(pl, physKind) end
		end

		t.Result = round(t.Result * math.min(dodgeDR, math.min(wDR, shDR)) * enshDR * arDR * stDR * kindDR)
		local negated = damageTotal - t.Result
		local negPercent = damageTotal > 0 and (1 - (t.Result / damageTotal)) * 100 or 100

		-- SP drain application
		if spDrain > 0 then
			pl.SP = math.max(0, pl.SP - spDrain)
		end

		-- --- Item wear (ItemDurability.lua) ---
		if MF.WearOnHit then
			MF.WearOnHit(pl, category, t.Result, wDR, shDR, dodgeDR)
		end

		-- --- Sound Effects Processing ---
		-- Object 0 plays on the party channels (10-12); channel 14 (object -2) is reserved for
		-- the ambience loop of MMMWE_Music.lua
		local DEF_SND = 0
		local playedSound = false

		if category == "physical" then
			if shieldPhysDR < 1 and shieldPhysDR < weaponPhysDR and shieldPhysDR < dodgeDR then
				Game.PlaySound(44587, DEF_SND)
				playedSound = true
			elseif weaponPhysDR < 1 and weaponPhysDR < shieldPhysDR and weaponPhysDR < dodgeDR then
				-- sound of the weapon that actually parried (staff / sword, dagger / axe, spear, mace)
				local snd
				if parrySkill == const.Skills.Staff then
					snd = math.random(44658, 44663)
				elseif parrySkill == const.Skills.Sword or parrySkill == const.Skills.Dagger then
					snd = math.random(44598, 44601)
				else
					snd = math.random(44652, 44657)
				end
				Game.PlaySound(snd, DEF_SND)
				playedSound = true
			end
		elseif category == "elemental" then
			if math.min(shieldMagicDR, weaponMagicDR) < 1 and math.min(shieldMagicDR, weaponMagicDR) < dodgeDR then
				Game.PlaySound(44588, DEF_SND)
				playedSound = true
			end
		elseif category == "energy" then
			if math.min(shieldEnergyDR, weaponEnergyDR) < 1 and math.min(shieldEnergyDR, weaponEnergyDR) < dodgeDR then
				Game.PlaySound(44589, DEF_SND)
				playedSound = true
			end
		end

		if not playedSound and dodgeDR < 1 then
			pl:ShowFaceAnimation(6)
			Game.PlaySound(16060, DEF_SND)
		end

		-- --- Display Status Text ---
		local dmgTypeName = category
		-- Identify Monster at Expert in anyone in the party names the kind of damage for everyone
		local idMonMastery = 0
		for i = 0, Party.Count - 1 do
			local _, m = SplitSkill(Party[i]:GetSkill(const.Skills.IdentifyMonster))
			if m > idMonMastery then idMonMastery = m end
		end
		if idMonMastery >= const.Expert and DamageTypeNames[t.DamageKind] then
			dmgTypeName = DamageTypeNames[t.DamageKind]
			if physKind then dmgTypeName = physKind:lower() end
		end

		if fullDodge then
			Game.ShowStatusText(string.format("%s dodges the attack!", pl.Name), 5)
		else
			Game.ShowStatusText(string.format(
				"%s takes %d %s damage (%d negated, %.1f%%)",
				pl.Name, t.Result, dmgTypeName, negated, negPercent), 5)
		end
	end


	-- Weapon sound overrides
	local MournbringerSwingSounds = {44590, 44591, 44592, 44593, 44594, 44595, 44596}
	 mem.autohook2(0x42dbd3, function(d)
		local Plr = Party:GetCurrentPlayer()
		local Wpn = Plr.ItemMainHand
		local WpnNum = (Wpn > 0) and Plr.Items[Wpn].Number or 0
		
		if WpnNum == 545 then
			mem.u4[d.esp] = MournbringerSwingSounds[math.random(1,7)]
		elseif WpnNum == 1355 then
			mem.u4[d.esp] = 0xAE35
		end
	 end)
	
	-- Bank pays interest once a month

	function events.Tick()
		-- Init
		if vars.YearBankPay == nil then
			vars.YearBankPay = Game.Year
		end
		if vars.MonthBankPay == nil then
			vars.MonthBankPay = Game.Month
		end
		if vars.WeekBankPay == nil then
			vars.WeekBankPay = Game.WeekOfMonth
		end

		-- Max Party Merchant Total Skill
		local maxMerchSkill = 0
		for _, pl in Party.Players do
			local skill = pl:GetMerchantTotalSkill()
			if skill > maxMerchSkill then
				maxMerchSkill = skill
			end
		end

		-- Interests: 10% base + 0.5% weekly, payments every week
		local annualInterest = 1.1 + 0.005 * maxMerchSkill
		local weeklyPercent = annualInterest ^ (1 / 48) - 1

		-- Check if a week has passed
		if vars.YearBankPay ~= Game.Year
		   or vars.MonthBankPay ~= Game.Month
		   or vars.WeekBankPay ~= Game.WeekOfMonth then
			local passedYears  = Game.Year - vars.YearBankPay
			local passedMonths = 12 * passedYears + Game.Month - vars.MonthBankPay
			local passedWeeks   = 4 * passedMonths + Game.WeekOfMonth - vars.WeekBankPay

			if passedWeeks > 0 then
				for _ = 1, passedWeeks do
					evt.Add("BankGold", round(Party.BankGold * weeklyPercent))
				end
			end

			vars.YearBankPay  = Game.Year
			vars.MonthBankPay = Game.Month
			vars.WeekBankPay  = Game.WeekOfMonth
		end
	end
	
	-- Shop, temple, identify and repair prices: moved to MMMWE_Economy.lua (Economy.Settings)

	mem.autohook(0x490295, function(d)
		local Pl = MF.GetPlayerFromPtr(d.ecx)
		local MS, MM = SplitSkill(Pl:GetSkill(25))
		local Rep = Party:GetReputation()
		local Charisma = Game.GetStatisticEffect(Pl:GetPersonality())
		local MSGM = math.max(0, MS*MM-Rep+Charisma)
		mem.asmpatch(0x4902b2, "mov eax, " .. MSGM) -- Merchant skill at GM (current value: skill-, reputation- and personality-dependent, default: 10000)
		mem.asmpatch(0x4902d8, "lea eax, [eax+esi+" .. Charisma .. "]")	--Starting merchant skill bonus is 0.5% per +1 Stat bonus of Personality (default: 7% [eax+esi+7])
	end)
	
	-- Regeneration only works for the living (and zombies)
	local function CanRegen(Player)
		local Cond = Player:GetMainCondition()
		return Cond >= const.Condition.Zombie or Cond < const.Condition.Dead
	end

	-- SP per regen tick from Meditation (0 if none), exact (fractions are kept by the
	-- per-minute payout below). Used by the tick and the character screen.
	local function CalcMeditationSPRegen(Player)
		if not CanRegen(Player) then return 0 end
		local RegS, RegM = SplitSkill(Player:GetSkill(const.Skills.Meditation))
		if RegM <= 0 then return 0 end
		RegS = RegS + Player:CalcStatBonusByItems(const.Stats.Meditation)
		local Add = RegM + RegS/10
		return Add + Add*Game.GetStatisticEffect(Player:GetIntellect())/10 + Add*Game.GetStatisticEffect(Player:GetPersonality())/20
	end

	-- HP per regen tick from the Regeneration skill (0 if none), exact
	local function CalcSkillHPRegen(Player)
		if not CanRegen(Player) then return 0 end
		local RegS, RegM = SplitSkill(Player:GetSkill(const.Skills.Regeneration))
		local RegP = (RegS > 0 and 0.5 or 0) + RegS/10*RegM
		return RegP > 0 and Player:GetFullHP()*RegP/100 or 0
	end

	-- Regeneration spell: the buff's power is a whole number (the game heals it every tick);
	-- the fraction of the exact amount is kept here and added on each tick
	local RegenSpellFrac = {}            -- [PlayersArray index] = fraction
	-- HP per regen tick from an active Regeneration spell, exact
	local function CalcSpellHPRegen(Player)
		if not CanRegen(Player) then return 0 end
		local Buff = Player.SpellBuffs[const.PlayerBuff.Regeneration]
		if Game.Time >= Buff.ExpireTime then return 0 end
		return Buff.Power + (RegenSpellFrac[Player:GetIndex()] or 0)
	end

	-- Regeneration every game minute (23.10.26). The game's regeneration tick (0x491CCE)
	-- runs every 5 game minutes and gives HP and SP at once: items, the Regeneration spell,
	-- artifacts (the RegenTick handlers run inside it). What it gives is taken back and paid
	-- out over the next 5 game minutes instead, a fifth per minute, with fractions adding up.
	-- Exact amounts (Meditation, the Regeneration skill and spell, potions) are handed in with
	-- MF.RegenGive and paid out the same way. Losses (zombies, Fly and other drains) stay as
	-- they are. The tick itself (and everything counted in ticks) is unchanged.
	local REGEN_SPREAD = 5               -- game minutes a gain is spread over
	local RegenDrip = {}                 -- [PlayersArray index] = {HP = streams, SP = streams, HPAcc, SPAcc, Last}
	local function dripOf(pi)
		local d = RegenDrip[pi]
		if not d then
			d = {HP = {}, SP = {}, HPAcc = 0, SPAcc = 0, Last = Game.Time}
			RegenDrip[pi] = d
		end
		return d
	end
	-- a gain of `amount` (fractions welcome) paid out over REGEN_SPREAD game minutes
	local function addStream(streams, amount)
		if amount > 0 then streams[#streams + 1] = {amount, amount / REGEN_SPREAD} end
	end
	function MF.RegenGive(Player, hp, sp)
		local dr = dripOf(Player:GetIndex())
		addStream(dr.HP, hp or 0)
		if not (MF.GetResource and MF.GetResource(Player)) then addStream(dr.SP, sp or 0) end
	end

	mem.hookfunction(0x491CCE, 0, 0, function(d, def)
		if not vars then return def() end      -- a game being loaded: the tick as it is
		local before = {}
		for slot = 0, Party.count - 1 do
			local p = Party[slot]
			before[slot] = {p.HP, p.SP}
		end
		local r = def()
		for slot = 0, Party.count - 1 do
			local p, b = Party[slot], before[slot]
			local dr = dripOf(Party.PlayersIndexes[slot])
			local dh, ds = p.HP - b[1], p.SP - b[2]
			-- waking up (HP from 0 or less to above 0) is left to the tick
			if dh > 0 and b[1] > 0 then
				p.HP = b[1]
				addStream(dr.HP, dh)
			end
			-- class resources (MMMWE_Resources.lua) keep their own rules
			local res = MF.GetResource and MF.GetResource(p)
			if ds > 0 and not res then
				p.SP = b[2]
				addStream(dr.SP, ds)
			end
		end
		return r
	end)

	-- pays out the streams for `mins` game minutes, returns the amount
	local function payStreams(streams, mins)
		local total, i = 0, 1
		while i <= #streams do
			local st = streams[i]
			local give = math.min(st[1], st[2] * mins)
			st[1] = st[1] - give
			total = total + give
			if st[1] <= 1e-9 then table.remove(streams, i) else i = i + 1 end
		end
		return total
	end
	function events.Tick()
		local now = Game.Time
		for slot = 0, Party.count - 1 do
			local p = Party[slot]
			local dr = RegenDrip[Party.PlayersIndexes[slot]]
			if dr then
				local mins = (now - dr.Last) / const.Minute
				dr.Last = now
				if mins > 0 and (#dr.HP > 0 or #dr.SP > 0) then
					if CanRegen(p) then
						dr.HPAcc = dr.HPAcc + payStreams(dr.HP, mins)
						local whole = math.floor(dr.HPAcc)
						if whole > 0 then
							dr.HPAcc = dr.HPAcc - whole
							p.HP = math.min(p:GetFullHP(), p.HP + whole)
							if p.HP > 0 and p.Conditions[13] ~= 0 then p.Conditions[13] = 0 end
						end
						dr.SPAcc = dr.SPAcc + payStreams(dr.SP, mins)
						whole = math.floor(dr.SPAcc)
						if whole > 0 then
							dr.SPAcc = dr.SPAcc - whole
							p.SP = math.min(p:GetFullSP(), p.SP + whole)
						end
					else
						dr.HP, dr.SP = {}, {}     -- the dead don't regenerate
					end
				end
			end
		end
	end
	function events.AfterLoadMap()
		for _, dr in pairs(RegenDrip) do dr.Last = Game.Time end
	end

	-- Technicians (Class Extra.txt kind 15): Construction instead of spell points
	-- (MMMWE_Resources.lua); the energy shield has its own capacity (MMMWE_EnergyShield.lua)
	local TECH_KIND = 15
	local function isTechnician(Player)
		local kind = MF.ClassFamily and MF.ClassFamily(Player.Class)
		if kind == nil then
			local e = Game.ClassesExtra[Player.Class]
			kind = e and e.Kind
		end
		return kind == TECH_KIND
	end
	MF.IsTechnician = isTechnician

	-- Meditation SP, the Regeneration skill HP and the fraction of the Regeneration spell, exact
	function events.RegenTick(Player)
		if not CanRegen(Player) then return end
		local sp = CalcMeditationSPRegen(Player)
		local hp = CalcSkillHPRegen(Player)
		local Buff = Player.SpellBuffs[const.PlayerBuff.Regeneration]
		if Game.Time < Buff.ExpireTime then hp = hp + (RegenSpellFrac[Player:GetIndex()] or 0) end
		if hp > 0 or sp > 0 then MF.RegenGive(Player, hp, sp) end
		if Player.HP > 0 then Player.Conditions[13] = 0 end
	end

	-- Regeneration spell MM7-alike effect: 0.5% of full HP + 0.1% per skill x mastery each
	-- tick; the buff gets the whole part, the fraction is added by the RegenTick above
	mem.autohook(0x4273fc, function(d)
		local Target = Party[mem.u4[d.ebx+4]]
		local Cond = Target:GetMainCondition()
		if Cond >= 17 or Cond < 14 then
			local RegS = mem.i4[d.ebp-0x14]/3600
			local RegM = mem.i4[d.ebp-0xC]
			local FHP = Target:GetFullHP()
			local exact = 0.005*FHP+0.001*RegM*RegS*FHP
			mem.i4[d.ebp-4] = math.floor(exact)
			RegenSpellFrac[Target:GetIndex()] = exact - math.floor(exact)
		end
	end)
		
	-- Character screen additional stats display
	local cstringCache = setmetatable({}, {__mode = "v"})
	local function cachedCstring(str)
		local cached = cstringCache[str]
		if cached then return cached end
		local ptr = MF.cstring(str)
		cstringCache[str] = ptr
		return ptr
	end
	
	local patchValueCache = {}
	local function smartPatch(addr, prefix, value)
		local key = addr
		if patchValueCache[key] == value then return end
		patchValueCache[key] = value
		mem.asmpatch(addr, prefix .. value)
	end
	
	local DICharge = 0
	local EqType = ""
	local ItHardened = 0

	-- Special items
	local SpecialItemGroups = {
		[191] = 1, [192] = 2, [193] = 3,
		[866] = 4, [867] = 4, [1666] = 4, [1667] = 4, [962] = 7, [968] = 8,
		[970] = 5, [971] = 5, [972] = 5, [973] = 5, [975] = 5, [976] = 5,
		[977] = 5, [978] = 5, [980] = 5, [981] = 5, [982] = 5, [983] = 5,
		[984] = 5, [985] = 5, [986] = 5, [987] = 5,
		[969] = 6, [974] = 6, [979] = 6,
	}

	local DICell = 0
	mem.autohook(0x41d3b3, function(d)
		DICharge = mem.i4[d.ecx + 0x10]
		DICell = mem.u1[d.ecx + 0x19]
	end)

	mem.autohook(0x41d217, function(d)
		EqType = mem.pchar[d.edi + 0x8]
	end)

	mem.autohook(0x41d812, function(d)
		ItHardened = math.floor(mem.i2[d.eax + 0x14] / 512)
		MF.TipWear = MF.GetItemWearPtr(d.eax)
	end)

	-- Find item slot by item id
	local function findItemSlot(pl, itemNumber)
		for i = 1, 138 do
			if pl.Items[i].Number == itemNumber then
				return i
			end
		end
		return nil
	end

	local function calcDurability2(itemNum, divisor)
		local d = divisor or 1
		local dur = MF.GetBaseDurability(itemNum) / d
		if ItHardened == 1 then
			dur = math.max(dur * 1.25, 10)
		end
		return dur, math.max(dur - (MF.TipWear or 0) / d, 0)	-- max, current (after wear)
	end
	
	-- "50" while pristine, "37/50 (Worn)" once worn, "Indestructible" for relics
	local function durLine(itemNum, divisor)
		if MF.IsIndestructible and MF.IsIndestructible(itemNum) then
			return "Indestructible"
		end
		local maxDur, curDur = calcDurability2(itemNum, divisor)
		if (MF.TipWear or 0) <= 0 then
			return string.format("%d", round(maxDur))
		end
		-- worn: never round the wear away (half points on helms / belts / gauntlets / boots,
		-- fractional max on Hardened items), so any item the R repair would charge for
		-- shows as worn
		maxDur = round(maxDur)
		curDur = math.min(math.floor(curDur), maxDur - 1)
		local tag = MF.GetDurabilityLabel and MF.GetDurabilityLabel(curDur, maxDur) or ""
		return string.format("%d/%d%s", curDur, maxDur, tag)
	end
	
	-- 5 = Bow (bows and crossbows now have durability too)
	local WItemSkills = {[0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [8] = true}
	local AItemSkills = {[9] = true, [10] = true, [11] = true}
	
	function DefineDurabilityString(ItNumber)
		local item = Game.ItemsTxt[ItNumber]
		if WItemSkills[item.Skill] then
			return cachedCstring(string.format("Type: %s \nDurability: %s", EqType, durLine(ItNumber)))
		elseif AItemSkills[item.Skill] then
			local divisor = item.EquipStat == 3 and 1 or 2
			return cachedCstring(string.format("Type: %s \nDurability: %s", EqType, durLine(ItNumber, divisor)))
		end
		return cachedCstring("Type: %s")
	end

	function DefineShieldString(ItNumber)
		local item = Game.ItemsTxt[ItNumber]
		if item.EquipStat ~= 4 then
			return cachedCstring("%s: +%lu")
		end

		local pl = Party:GetCurrentPlayer()
		local itSlot = findItemSlot(pl, ItNumber)
		if not itSlot then
			return cachedCstring("%s: +%lu")
		end

		local armor = MF.ItemArmorBase(item) + item.Mod2
		local plItem = pl.Items[itSlot]
		local shS, shM = SplitSkill(pl:GetSkill(const.Skills.Shield))
		local block = MF.ShieldBlockPower(ItNumber, plItem, shS, math.max(shM, 1))
		local class = MF.ShieldClassInfo(ItNumber).Name

		return cachedCstring(string.format("Armor: +%d   Block Power: %d%s (%s)", armor, block, "%%", class))
	end

	function DefineWeaponString(ItNumber)
		local item = Game.ItemsTxt[ItNumber]
		if item.EquipStat ~= 0 and item.EquipStat ~= 1 then
			return cachedCstring(" +%d")
		end

		local pl = Party:GetCurrentPlayer()
		local itSlot = findItemSlot(pl, ItNumber)
		if not itSlot then
			return cachedCstring(" +%d")
		end

		local damage = item.Mod1DiceCount * item.Mod1DiceSides + item.Mod2
		local parry = 10 + damage + CalcWeaponStatBonusByWType(ItNumber, 3)
		local twoHandedMult = {1, 1.25}
		parry = math.floor(parry * twoHandedMult[item.EquipStat + 1])

		local parryStr = string.format("\nParry Power: %d%s", parry,"%%")

		if item.Mod2 == 0 then
			return cachedCstring("%s: +%d   %s: %dd%d" .. parryStr)
		else
			return cachedCstring(" +%d" .. parryStr)
		end
	end

	function DefineChargeString(ItNumber)
		local group = SpecialItemGroups[ItNumber]
		if not group then
			return cachedCstring("%s: %lu")
		end

		local ch = DICharge
		if group == 1 then
			return cachedCstring(string.format("Steel: %d Siertal: %d Phylt: %d",
				math.fmod(ch, 100), math.fmod(math.modf(ch / 100), 100), math.modf(ch / 10000)))
		elseif group == 2 then
			return cachedCstring(string.format("Kergar: %d Erudine: %d Stalt: %d",
				math.fmod(ch, 100), math.fmod(math.modf(ch / 100), 100), math.modf(ch / 10000)))
		elseif group == 3 then
			return cachedCstring(string.format("Bottles: %d", ch))
		elseif group == 4 then
			return cachedCstring(MF.BlasterCardText(ch, DICell))
		elseif group == 7 then
			return cachedCstring(MF.ToolkitCardText(ch))
		elseif group == 8 then
			return cachedCstring(MF.ShieldCardText(ch, DICell))
		elseif group == 5 then
			return cachedCstring(string.format("Ant: %d Jad: %d",
				math.fmod(math.modf(ch / 100), 100), math.fmod(ch, 100)))
		elseif group == 6 then
			return cachedCstring(string.format("Enr: %d Ant: %d Jad: %d",
				math.modf(ch / 10000), math.fmod(math.modf(ch / 100), 100), math.fmod(ch, 100)))
		end
		return cachedCstring("%s: %lu")
	end

	function DefineBlasterModString(ItNumber, BS)
		local base = math.floor(ItNumber / 800) == 1 and 865 or 1665
		local bt = ItNumber - base
		local dMin = bt == 1 and 10 or 15
		local dMax = bt == 1 and 20 or 30
		local cBase = bt == 1 and 8 or 12

		-- the Emitter spec of the item shown (read from its raw Charges)
		local scale = MF.BlasterCardDamageMult and MF.BlasterCardDamageMult(DICharge) or 1
		dMin = round(dMin * scale)
		dMax = round(dMax * scale)

		return {
			cachedCstring(string.format('Shoot: +%d    Damage: %d-%d', cBase, dMin, dMax)),
			cachedCstring(' '),
		}
	end

	mem.autohook(0x41ced5, function(d)
		local IN = d.eax
		-- ecx = the item shown: its Charges and power cell for the blaster lines
		DICharge = mem.i4[d.ecx + 0x10]
		DICell = mem.u1[d.ecx + 0x19]
		local pl = Party:GetCurrentPlayer()
		local BS, BM = SplitSkill(pl:GetSkill(7))

		smartPatch(0x41D220, "push ", DefineDurabilityString(IN))

		if Game.ItemsTxt[IN].Skill == 7 then
			local bStrings = DefineBlasterModString(IN, BS)
			smartPatch(0x41d2d9, "push ", bStrings[1])
			smartPatch(0x41d2f8, "push ", bStrings[2])
		elseif (Game.ItemsTxt[IN].EquipStat == 0 or Game.ItemsTxt[IN].EquipStat == 1)
			and Game.CurrentScreen ~= 10 and Game.CurrentScreen ~= 13 and Game.CurrentScreen ~= 14 then
			if Game.ItemsTxt[IN].Mod2 == 0 then
				smartPatch(0x41d2d9, "push ", DefineWeaponString(IN))
				smartPatch(0x41d2f8, "push ", cachedCstring("%s: +%d   %s: %dd%d"))
			else
				smartPatch(0x41d2d9, "push ", cachedCstring("%s: +%d   %s: %dd%d"))
				smartPatch(0x41d2f8, "push ", DefineWeaponString(IN))
			end
		else
			smartPatch(0x41d2d9, "push ", cachedCstring("%s: +%d   %s: %dd%d"))
			smartPatch(0x41d2f8, "push ", cachedCstring(" +%d"))
		end

		smartPatch(0x41d28b, "push ", DefineShieldString(IN))
		smartPatch(0x41D3C1, "push ", DefineChargeString(IN))
	end)


	---- Unarmed + Hammerhands + Heroism damage
	local function isUnarmedMonk(playerPtr)
		local pl = Party.PlayersArray[(playerPtr - Party.PlayersArray["?ptr"]) / Party.PlayersArray[0]["?size"]]
		if pl.ItemMainHand ~= 0 then
			return nil
		end
		local us, um = SplitSkill(pl:GetSkill(const.Skills.Unarmed))
		if us > 0 then
			return pl
		end
		return nil
	end

	-- Heroism (22.10.26): +HEROISM_PER_POWER of the base weapon damage per point of the
	-- buff's power (the character's Heroism and the party's), instead of the flat power
	local HEROISM_PER_POWER = 0.01
	MF.HeroismPerPower = function() return HEROISM_PER_POWER end
	local function heroismPower(pl)
		local power = 0
		local b = pl.SpellBuffs[const.PlayerBuff.Heroism]
		if b and b.ExpireTime > Game.Time then power = power + b.Power end
		local pb = Party.SpellBuffs[const.PartyBuff.Heroism]
		if pb and pb.ExpireTime > Game.Time then power = power + pb.Power end
		return power
	end
	MF.HeroismPower = heroismPower
	local function calcHeroismPct(pl)
		return HEROISM_PER_POWER * heroismPower(pl)
	end

	local function calcUnarmedBonus(pl)
		local us, um = SplitSkill(pl:GetSkill(const.Skills.Unarmed))
		if um >= 3 then
			return us * 2
		elseif um == 2 then
			return us
		end
		return 0
	end

	-- Display range after the durability penalty of `it` (0 for anything not worn)
	local function penalizedRange(it, minD, maxD)
		local p = MF.GetWeaponPenalty and MF.GetWeaponPenalty(it) or 0
		if p <= 0 then return minD, maxD end
		return math.max(0, round(minD * (1 - p))), math.max(0, round(maxD * (1 - p)))
	end

	local function UnarmedDamageHook(ret)
		return function(d)
			-- Armed character with a worn / damaged main-hand weapon: take the game's own
			-- range (GetMeleeDamageMin / Max, as print_melee_damage does) and apply the same
			-- penalty as in combat (applyPenalty). Anything else is left to the game.
			local armed = Party.PlayersArray[(d.ecx - Party.PlayersArray["?ptr"]) / Party.PlayersArray[0]["?size"]]
			-- Blaster: the range CalcBlasterDamage rolls (skill and upgrade tier), not the item dice
			local bMin, bMax = blasterRange(armed)
			if bMin then
				d.edi, d.eax = bMin, bMax
				d:push(ret)
				return true
			end
			if armed.ItemMainHand ~= 0 then
				local it = armed.Items[armed.ItemMainHand]
				local p = MF.GetWeaponPenalty and MF.GetWeaponPenalty(it) or 0
				local mult = weaponSkillDamageMult(armed, true)
				if p > 0 or mult ~= 1 then
					local minD, maxD = armed:GetMeleeDamageMin(), armed:GetMeleeDamageMax()
					minD, maxD = round(minD * mult), round(maxD * mult)
					d.edi, d.eax = penalizedRange(it, minD, maxD)
					d:push(ret)
					return true
				end
			end

			local pl = isUnarmedMonk(d.ecx)
			if not pl then
				return
			end

			local mightBonus = Game.GetStatisticEffect(pl:GetMight())
			local unarmedBonus = calcUnarmedBonus(pl)
			local heroism = 1 + calcHeroismPct(pl)

			-- Heroism: a share of the base (bare hands + Unarmed skill + Might); Hammerhands adds its
			-- Body damage separately and is not part of this range
			local minDamage = round((1 + unarmedBonus + mightBonus) * heroism)
			local maxDamage = round((3 + unarmedBonus + mightBonus) * heroism)

			d.edi = minDamage
			d.eax = maxDamage
			d:push(ret)
			return true
		end
	end

	mem.autohook(0x48CC0D, UnarmedDamageHook(0x48CC32))
	----
	--Bow and Crossbow Damage
	local function hasBow(playerPtr)
		local pl = Party.PlayersArray[(playerPtr - Party.PlayersArray["?ptr"]) / Party.PlayersArray[0]["?size"]]
		return pl.ItemBow == 0 and nil or pl
	end
	
	local function RangedDamageHook(ret)
		return function(d)
			-- a blaster in the main hand is what shoots (Blaster skill and upgrade tier)
			local shooter = Party.PlayersArray[(d.ecx - Party.PlayersArray["?ptr"]) / Party.PlayersArray[0]["?size"]]
			local bMin, bMax = blasterRange(shooter)
			if bMin then
				d.edi, d.eax = bMin, bMax
				d:push(ret)
				return true
			end
			local pl = hasBow(d.ecx)
			if not pl then
				return
			end
			if pl.ItemBow == 0 then return end
			
			local DamageBonusStat = {
			[1] = Game.GetStatisticEffect(pl:GetMight()),
			[2] = math.floor(Game.GetStatisticEffect(pl:GetMight())/2),
			}
			
			local Bow = Game.ItemsTxt[pl.Items[pl.ItemBow].Number]
			local isCrossbow = CrossbowNames[Bow.NotIdentifiedName]
			local BowS, BowM = SplitSkill(pl.Skills[5])
			local minD, maxD = Bow.Mod1DiceCount + Bow.Mod2, Bow.Mod1DiceCount*Bow.Mod1DiceSides + Bow.Mod2
			
			minD = isCrossbow and minD + DamageBonusStat[2] + (BowM >= 4 and BowS or 0) or minD + DamageBonusStat[1] + (BowM >= 4 and BowS or 0)
			maxD = isCrossbow and maxD + DamageBonusStat[2] + (BowM >= 4 and BowS or 0) or maxD + DamageBonusStat[1] + (BowM >= 4 and BowS or 0)
			-- weapon skill damage, then a worn / damaged bow's penalty (as in combat)
			local mult = weaponSkillDamageMult(pl, false)
			minD, maxD = round(minD * mult), round(maxD * mult)
			minD, maxD = penalizedRange(pl.Items[pl.ItemBow], minD, maxD)
			d.edi = minD
			d.eax = maxD
			d:push(ret)
			return true
		end
	end
	
	mem.autohook(0x48CCAA, RangedDamageHook(0x48CCCF))

	-- Widget V-offset patches

	-- The edited fr_stats backgrounds (Data/Icons) have the HP box and the box below it
	-- 8 px higher; everything from the HP line down follows. 0 = original backgrounds.
	local STATS_BOX_SHIFT = 8

	local WidgetVPatches = {
		-- General widgets
		{addr = 0x418037, asm = "lea ebp, [ebp+eax*2-" .. (1 + STATS_BOX_SHIFT) .. "]", desc = "HP"},
		{addr = 0x4180af, asm = "lea eax, [eax+ebp-4]", desc = "SP"},
		{addr = 0x418131, asm = "lea eax, [eax+ebp-4]", desc = "Armor Class"},
		{addr = 0x41819f, asm = "lea eax, [eax+ebp-5]", desc = "Condition (replaced by HR and Phys Res)"},
		{addr = 0x4181f0, asm = "lea ebp, [ebp+eax*2+5]", desc = "Quick spell (replaced by resistances and chances; 4 px higher for the Sla/Pie/Blu line)"},
		{addr = 0x4183a4, asm = "lea eax, [ecx+eax*2]", desc = "Attack"},
		{addr = 0x4183f0, asm = "lea eax, [ecx+eax-4]", desc = "Melee damage"},
		{addr = 0x41843c, asm = "lea eax, [ecx+eax+10]", desc = "Shoot"},
		{addr = 0x418488, asm = "lea eax, [ecx+eax-4]", desc = "Ranged damage"},
		
		-- Resistance widgets
		{addr = 0x4184D4, asm = "lea eax, [ecx+eax*2+4]", desc = "Fire res"},
		{addr = 0x41859e, asm = "lea eax, [ecx+eax-4]", desc = "Air res"},
		{addr = 0x418668, asm = "lea eax, [ecx+eax-4]", desc = "Water res"},
		{addr = 0x418732, asm = "lea eax, [ecx+eax-4]", desc = "Earth res"},
		{addr = 0x4187fc, asm = "lea eax, [ecx+eax-4]", desc = "Mind res"},
		{addr = 0x4188c6, asm = "lea eax, [ecx+eax-4]", desc = "Body res"}
	}

	for _, patch in ipairs(WidgetVPatches) do
		mem.asmpatch(patch.addr, patch.asm)
	end
	
-- Font patches: {addr, register, font_ptr}
	local FontPatches = {
		-- Condition widget font (0x5db91c)
		{0x418194, "eax", 0x5db91c},
		{0x4181d4, "edx", 0x5db91c},

		-- Quick spell widget font (0x5db91c)
		{0x4181e7, "eax", 0x5db91c},
		{0x418224, "edx", 0x5db91c},

		-- 8 stat widgets with font 0x5db934
		{0x417d30, "eax", 0x5db934},
		{0x417d88, "edx", 0x5db934},
		{0x417da5, "eax", 0x5db934},
		{0x417df4, "edx", 0x5db934},
		{0x417e10, "eax", 0x5db934},
		{0x417e60, "edx", 0x5db934},
		{0x417e7c, "eax", 0x5db934},
		{0x417ecc, "edx", 0x5db934},
		{0x417ee8, "eax", 0x5db934},
		{0x417f38, "edx", 0x5db934},
		{0x417f54, "eax", 0x5db934},
		{0x417fa4, "edx", 0x5db934},
		{0x417fc0, "eax", 0x5db934},
		{0x418010, "edx", 0x5db934},

		-- Attack font (0x5db91c)
		{0x418397, "eax", 0x5db91c},
		{0x4183c5, "edx", 0x5db91c},

		-- Melee damage font (0x5db91c)
		{0x4183e3, "eax", 0x5db91c},
		{0x418411, "edx", 0x5db91c},

		-- Shoot font (0x5db91c)
		{0x41842f, "eax", 0x5db91c},
		{0x418461, "edx", 0x5db91c},

		-- Ranged damage font (0x5db91c)
		{0x41847b, "eax", 0x5db91c},
		{0x4184a9, "edx", 0x5db91c},

		-- Fire res font (0x5db91c)
		{0x418576, "edx", 0x5db91c},
		{0x418591, "eax", 0x5db91c},

		-- Air res font (0x5db91c)
		{0x418640, "edx", 0x5db91c},
		{0x41865b, "eax", 0x5db91c},

		-- Water res font (0x5db91c)
		{0x41870a, "edx", 0x5db91c},
		{0x418725, "eax", 0x5db91c},

		-- Earth res font (0x5db91c)
		{0x4187d4, "edx", 0x5db91c},
		{0x4187ef, "eax", 0x5db91c},

		-- Mind res font (0x5db91c)
		{0x41889e, "edx", 0x5db91c},
		{0x4188b9, "eax", 0x5db91c},

		-- Body res font (0x5db91c)
		{0x41895f, "edx", 0x5db91c},
	}

	for _, p in ipairs(FontPatches) do
		mem.asmpatch(p[1], string.format("mov %s, dword ptr [0x%x]", p[2], p[3]))
	end

	-- Stat format edit
	MV.StatFmt  = MF.cstring("%s\f%05u\r428%d\f00000 / \t188%d\n")
	MV.StatFmt2 = MF.cstring("%s\f%05u\r428%d\f00000 / \t188%d\n\n")

	local StatFmtPatches = {
		{0x417D7D, MV.StatFmt},
		{0x417DE5, MV.StatFmt},
		{0x417E51, MV.StatFmt},
		{0x417EBD, MV.StatFmt},
		{0x417F29, MV.StatFmt},
		{0x417F95, MV.StatFmt},
		{0x418001, MV.StatFmt2},
	}

	for _, p in ipairs(StatFmtPatches) do
		mem.asmpatch(p[1], "push " .. p[2])
	end

	-- Character screen combat stats
	local ParryC = 0
	local BlockC = 0
	local ListedStatVals = {0, 0, 0, 0, 0, 0, 0}
	local ListedStatBonuses = {0, 0, 0, 0, 0, 0, 0}

	local DodgePenalties = {10, 0, 0, 0, 10, 0, 0, 0, 20, 10, 0, 0, 30, 15, 15, 0}

	-- Get Item skill by item slot
	local function getItemSkill(pl, slot)
		if slot > 0 and not pl.Items[slot].Broken then
			return Game.ItemsTxt[pl.Items[slot].Number].Skill
		end
		return nil
	end

	local function getItemNum(pl, slot)
		return pl.Items[slot].Number
	end

	-- Dodge chance for Char Screen
	local function calcDodgeChanceUI(pl, armorSlot, shieldSlot)
		local ddgS, ddgM = SplitSkill(pl:GetSkill(const.Skills.Dodging))
		if ddgM <= 0 then
			return 0
		end

		local chance = math.min(42.5 + 0.125 * ddgS * ddgM, 20 + 0.5 * ddgS * ddgM)

		-- Shield Penalty
		local shSkill = getItemSkill(pl, shieldSlot)
		if shSkill == 8 then
			local _, shM = SplitSkill(pl:GetSkill(8))
			shM = math.max(shM, 1)
			local pen = (DodgePenalties[shM] or 0) + MF.ShieldExtraPenalty(getItemNum(pl, shieldSlot), shM)
			chance = chance - pen
		end

		-- Armor Penalty
		local ProtSkills = {8, 9, 10, 11}
		local armSkill = getItemSkill(pl, armorSlot)
		if armSkill then
			for i = 1, 3 do
				if armSkill == ProtSkills[i + 1] then
					local _, armM = SplitSkill(pl:GetSkill(armSkill))
					chance = chance - DodgePenalties[armM + 4 * i]
				end
			end
		end

		-- Aux armor penalty
		local auxSlots = {pl.ItemHelm, pl.ItemBelt, pl.ItemGauntlets, pl.ItemBoots}
		for _, slotIdx in ipairs(auxSlots) do
			local skill = getItemSkill(pl, slotIdx)
			if skill and AuxArmorDodgePenalty[skill] then
				local _, m = SplitSkill(pl:GetSkill(skill))
				chance = chance - AuxArmorDodgePenalty[skill][math.max(m, 1)]
			end
		end

		if ddgM > 0 and MF.DodgeChanceMods then
			chance = chance + MF.DodgeChanceMods(pl)   -- Speed, conditions, Haste
		end
		return math.max(chance, 0)
	end

	-- Total armor durability
	local function calcTotalArmorDurability(pl)
		local dur = 0
		local slots = {
			{pl.ItemArmor,     1},
			{pl.ItemHelm,      0.5},
			{pl.ItemGauntlets, 0.5},
			{pl.ItemBoots,     0.5},
			{pl.ItemBelt,      0.5},
		}
		for _, entry in ipairs(slots) do
			local slot, mult = entry[1], entry[2]
			if slot > 0 and not pl.Items[slot].Broken then
				local it = pl.Items[slot]
				local base = MF.GetBaseDurability(it.Number)
				if it.Hardened then base = base * 1.25 end
				dur = dur + math.max(base - MF.GetItemWear(it), 0) * mult
			end
		end
		return dur
	end
	MF.CalcTotalArmorDurability = calcTotalArmorDurability   -- MMMWE_Drains.lua

	-- Parry chance for the character screen: same rules as the combat roll
	local function calcParryChanceUI(pl, curseMult)
		local p = MF.GetParryProfile(pl)
		return p and math.min(math.max(p.Chance * curseMult, 0), 100) or 0
	end
	
	-- =====================================================================
	-- File-scope constants (created once at script initialization)
	-- =====================================================================

	local WItemSkills = {[0]=true, [1]=true, [2]=true, [3]=true, [4]=true, [6]=true, [8]=true}
	local AItemSkills = {[9]=true, [10]=true, [11]=true}

	local Bonus2Regen = {
		[37] = {2, 0}, [38] = {0, 1}, [44] = {2, 0}, [47] = {0, 1},
		[54] = {2, 0}, [58] = {0, 1}, [66] = {2, 1}, [50] = {3, 0}, [55] = {0, 1},
	}

	local ArtRegen = {
		[509] = {2, 0}, [513] = {0, 3}, [520] = {2, 0}, [550] = {5, 5},
		[1331] = {3, 3}, [1334] = {0, 3}, [1335] = {3, 0},
		[1337] = {3, 0}, [2024] = {0, 3}, [2027] = {3, 0}, [2032] = {0, 3},
		[2033] = {0, 3}, [2034] = {0, 3}, [2035] = {-3, 0}, [1317] = {-3, 0},
	}

	local IMMUNE_THRESHOLD = 65000

	local ProtSkills = {8, 9, 10, 11}
	local AuxSlotFields = {"ItemHelm", "ItemBelt", "ItemGauntlets", "ItemBoots"}
	local DurSlots = {
		{"ItemArmor", 1}, {"ItemHelm", 0.5}, {"ItemGauntlets", 0.5},
		{"ItemBoots", 0.5}, {"ItemBelt", 0.5},
	}

	local ElementalDRList = {
		{res = 10, name = "Fire"}, {res = 11, name = "Air"},
		{res = 12, name = "Water"}, {res = 13, name = "Earth"},
		{res = 14, name = "Mind"}, {res = 15, name = "Body"},
	}

	local ElementalDRAddrs = {0x418534, 0x4185fe, 0x4186c8, 0x418792, 0x41885c, 0x41891f}

	local StatNames = {"Might", "Intellect", "Personality", "Endurance", "Accuracy", "Speed", "Luck"}
	local StatBonusAddrs = {0x417d77, 0x417ddf, 0x417e4b, 0x417eb7, 0x417f23, 0x417f8f, 0x417ffb}

	local DodgePenalties = {10, 0, 0, 0, 10, 0, 0, 0, 20, 10, 0, 0, 30, 15, 15, 0}

	local ResFmtPrefix = "mov dword ptr [esp+0x7C-0x64], "
	local ResFmtPrefix2 = "mov dword ptr [esp+0x78-0x64], "

	local ResFormatPatchAddrs = {
		{0x4184e0, true},  {0x41851c, false},
		{0x4185aa, true},  {0x4185e6, false},
		{0x418674, true},  {0x4186b0, false},
		{0x41873e, true},  {0x41877a, false},
		{0x418808, true},  {0x418844, false},
		{0x4188d2, true},  {0x418909, false},
	}

	local WidgetPatchSpecs = {
		{0x41807a, "push", "HPR"},
		{0x4180f8, "push", "SPR"},
		{0x4181b7, "push", "ADur"},
		{0x4181A8, "push", "PhysRes"},
		{0x4181bd, "push", "STRFMT_1"},
		{0x418219, "push", "ResFmt"},
		{0x418213, "push", "UpperResValues"},
		{0x418204, "mov eax,", "LowerResValues"},
		{0x41820D, "mov eax,", "LowerResValues"},
		{0x418400, "push", "MeleeCritStats"},
		{0x418498, "push", "RangedCritStats"},
	}
	
	-- =====================================================================
	-- Equipment change detection (separate from sigChanged)
	-- =====================================================================

	local EQUIP_SLOT_FIELDS = {
		"ItemMainHand", "ItemExtraHand", "ItemBow",
		"ItemArmor", "ItemHelm", "ItemBelt", "ItemCloak",
		"ItemGauntlets", "ItemBoots", "ItemAmulet",
		"ItemRing1", "ItemRing2",
	}

	-- lastEquip[plIndex] = { {slot, number}, {slot, number}, ... }
	local lastEquip = {}

	local function checkEquipChanged(pl, plIndex)
		local prev = lastEquip[plIndex]
		if not prev then
			prev = {}
			lastEquip[plIndex] = prev
			for i, field in ipairs(EQUIP_SLOT_FIELDS) do
				local slotIdx = pl[field]
				local itemNum = (slotIdx > 0) and pl.Items[slotIdx].Number or 0
				prev[i] = {slotIdx, itemNum}
			end
			return true
		end

		local changed = false
		for i, field in ipairs(EQUIP_SLOT_FIELDS) do
			local slotIdx = pl[field]
			local itemNum = (slotIdx > 0) and pl.Items[slotIdx].Number or 0
			local p = prev[i]

			if slotIdx ~= p[1] or itemNum ~= p[2] then
				p[1] = slotIdx
				p[2] = itemNum
				changed = true
			end
		end
		return changed
	end

	-- "Dirty" flag: the equipment is already changed, the stats are not calculated yet
	local equipDirty = false

	-- =====================================================================
	-- Force recalc (swap current player)
	-- =====================================================================

	local function forceRecalc(pl)
		local slot = pl:GetSlot()
		local other = (slot + 1) % 4
		Party.CurrentPlayer = other
		Party.CurrentPlayer = slot
	end
	
		-- Signature cash
	local sigLast = {}
	local sigCur = {}

	local BROKEN_CHECK_SLOTS = {
		"ItemMainHand", "ItemExtraHand", "ItemBow",
		"ItemArmor", "ItemHelm", "ItemGauntlets", "ItemBoots", "ItemBelt",
	}

	local function sigChanged(pl, plIndex)
		sigCur[1]  = plIndex
		sigCur[2]  = pl:GetMainCondition()
		sigCur[3]  = pl:GetMight()
		sigCur[4]  = pl:GetSpeed()
		sigCur[5]  = pl:GetAccuracy()
		sigCur[6]  = pl:GetEndurance()
		sigCur[7]  = pl:GetIntellect()
		sigCur[8]  = pl:GetPersonality()
		sigCur[9]  = pl:GetLuck()
		sigCur[10] = pl:GetArmorClass()
		sigCur[11] = pl:GetResistance(10)
		sigCur[12] = pl:GetResistance(11)
		sigCur[13] = pl:GetResistance(12)
		sigCur[14] = pl:GetResistance(13)
		sigCur[15] = pl:GetResistance(14)
		sigCur[16] = pl:GetResistance(15)
		sigCur[17] = pl:GetResistance(33)
		sigCur[18] = pl:GetResistance(50)
		sigCur[19] = pl:GetResistance(51)
		sigCur[20] = MV.PotionHPReg[plIndex + 1] or 0
		sigCur[21] = MV.PotionSPReg[plIndex + 1] or 0
		sigCur[22] = MV.ZombieHPDegen[pl.Name] or 0
		sigCur[23] = MV.ZombieSPDegen[pl.Name] or 0

		-- "Broken" state flags (8 slots)
		for i, field in ipairs(BROKEN_CHECK_SLOTS) do
			local slotIdx = pl[field]
			sigCur[23 + i] = (slotIdx > 0 and pl.Items[slotIdx].Broken) and 1 or 0
		end

		-- Weapon and shield skills (parry / block chance)
		local mSk, oSk = getItemSkill(pl, pl.ItemMainHand), getItemSkill(pl, pl.ItemExtraHand)
		sigCur[32] = mSk and pl:GetSkill(mSk) or -1
		sigCur[33] = oSk and pl:GetSkill(oSk) or -1
		sigCur[34] = pl:GetSkill(const.Skills.Shield)

		-- Regeneration inputs (HP/SP regen line)
		sigCur[35] = pl:GetSkill(const.Skills.Regeneration)
		sigCur[36] = pl:GetSkill(const.Skills.Meditation)
		sigCur[37] = pl:GetFullHP()
		sigCur[38] = pl:GetFullSP()
		local rgBuff = pl.SpellBuffs[const.PlayerBuff.Regeneration]
		sigCur[39] = Game.Time < rgBuff.ExpireTime and rgBuff.Power or 0

		-- Curse halves parry / dodge / block / crit even when it isn't the main condition
		sigCur[40] = pl.Conditions[const.Condition.Cursed] > 0 and 1 or 0

		for i = 1, 40 do
			if sigCur[i] ~= sigLast[i] then
				sigLast, sigCur = sigCur, sigLast
				return true
			end
		end
		return false
	end
	
	-- File-scope functions

	-- Text color of a resistance value against its base, from the game's own color_stat
	-- (0x416F77, fastcall: ecx = current, edx = base): above base green, equal default,
	-- below base yellow, below 25% of base red. The game draws the Spirit, Light and Dark
	-- lines from the strings below, not with its own color code, so the color is added
	-- here. color_stat divides by base, so a value below a base of 0 or less is red here.
	local function resColor(cur, base)
		if cur < base and base <= 0 then return RGB(255, 0, 0) end
		return mem.call(0x416F77, 2, cur, base)
	end

	local function spiritString(pl, spiritRes, spiritBase, shortFormat)
		local resME = CalcResME(pl, 33)
		if spiritRes >= IMMUNE_THRESHOLD then
			return string.format("\t   Spirit\t115%s", "Immune")
		end
		local pct = "%%"
		if shortFormat then
			return string.format("\t   Spirit\t55 %3.1f%s\t115\f%05d%d\f00000 / %d",
				resME, pct, resColor(spiritRes, spiritBase), spiritRes, spiritBase)
		else
			return string.format("\t   Spirit\t55 %3.1f%s\r185\f%05d%d\f00000 / %d",
				resME, pct, resColor(spiritRes, spiritBase), spiritRes, spiritBase)
		end
	end

	local function resLine(name, resME, resVal, resBase)
		if resVal >= IMMUNE_THRESHOLD then
			return string.format("\t   %s\t160%s", name, "Immune")
		end
		return string.format("\t   %s\t90 %3.1f%%\t160\f%05d%d\f00000 / %d",
			name, resME, resColor(resVal, resBase), resVal, resBase)
	end

	function CalcHPSPRegen(Player)
		local hpr, spr = 0, 0
		local hasItemBonus = false
		for item, slot in Player:EnumActiveItems() do
			local br = Bonus2Regen[item.Bonus2]
			if br then
				hpr = hpr + br[1]
				spr = spr + br[2]
				if br[1] > 0 or br[2] > 0 then
					hasItemBonus = true
				end
			end
			local ar = ArtRegen[item.Number]
			if ar then
				hpr = hpr + ar[1]
				spr = spr + ar[2]
			end
		end
		if hasItemBonus then
			if hpr > 0 then hpr = hpr + 1 end
			if spr > 0 then spr = spr + 1 end
		end
		return hpr, spr
	end

	local function calcDodgeChanceUI(pl, armorSlot, shieldSlot)
		local ddgS, ddgM = SplitSkill(pl:GetSkill(const.Skills.Dodging))
		if ddgM <= 0 then return 0 end
		local chance = math.min(42.5 + 0.125 * ddgS * ddgM, 20 + 0.5 * ddgS * ddgM)
		local shSkill = getItemSkill(pl, shieldSlot)
		if shSkill == 8 then
			local _, shM = SplitSkill(pl:GetSkill(8))
			shM = math.max(shM, 1)
			local pen = (DodgePenalties[shM] or 0) + MF.ShieldExtraPenalty(getItemNum(pl, shieldSlot), shM)
			chance = chance - pen
		end
		local armSkill = getItemSkill(pl, armorSlot)
		if armSkill then
			for i = 1, 3 do
				if armSkill == ProtSkills[i + 1] then
					local _, armM = SplitSkill(pl:GetSkill(armSkill))
					chance = chance - DodgePenalties[armM + 4 * i]
				end
			end
		end
		for _, slotName in ipairs(AuxSlotFields) do
			local slotIdx = pl[slotName]
			local skill = getItemSkill(pl, slotIdx)
			if skill and AuxArmorDodgePenalty[skill] then
				local _, m = SplitSkill(pl:GetSkill(skill))
				chance = chance - AuxArmorDodgePenalty[skill][math.max(m, 1)]
			end
		end
		if ddgM > 0 and MF.DodgeChanceMods then
			chance = chance + MF.DodgeChanceMods(pl)   -- Speed, conditions, Haste
		end
		return math.max(chance, 0)
	end

	local function calcTotalArmorDurability(pl)
		local dur = 0
		for _, entry in ipairs(DurSlots) do
			local slotName, mult = entry[1], entry[2]
			local slotIdx = pl[slotName]
			if slotIdx > 0 and not pl.Items[slotIdx].Broken then
				local it = pl.Items[slotIdx]
				local base = MF.GetBaseDurability(it.Number)
				if it.Hardened then base = base * 1.25 end
				dur = dur + math.max(base - MF.GetItemWear(it), 0) * mult
			end
		end
		return dur
	end
	
	-- Hook into draw_character_screen function
	mem.autohook(0x4181A3, function(d)
		local Pl = MF.GetPlayerFromPtr(d.ecx)
		local PlIndex = Pl:GetSlot()
		local PlInd = Pl:GetIndex()

		-- Always: check for buff expiry
		if Game.PlayersExtra[PlInd].SpellBuffs2[31].ExpireTime < Game.Time then
			MV.PotionHPReg[PlIndex + 1] = 0
		end
		if Game.PlayersExtra[PlInd].SpellBuffs2[32].ExpireTime < Game.Time then
			MV.PotionSPReg[PlIndex + 1] = 0
		end
		
		local equipChg = checkEquipChanged(Pl, PlIndex)
		
		if equipChg then
			forceRecalc(Pl)
			equipDirty = true
		end
		
		if equipDirty then
			equipDirty = false
			sigLast = {}
			return
		end
		
		-- Skip recalc if signature is unchanged
		if not sigChanged(Pl, PlIndex) then return end

		local curseMult = Pl.Conditions[const.Condition.Cursed] > 0 and 0.5 or 1  -- cursed at all
		local mainSlot = Pl.ItemMainHand
		local mainSkill = getItemSkill(Pl, mainSlot)
		local offSlot = Pl.ItemExtraHand
		local offSkill = getItemSkill(Pl, offSlot)
		local WMH = 0
		local US, UM = SplitSkill(Pl:GetSkill(const.Skills.Unarmed))

		ParryC = 0
		BlockC = 0

		if mainSkill == 7 then
			CalcBlasterDamage(Pl)
			CritCB = CritC
			CritDB = CritD
		elseif mainSkill and mainSkill < 7 then
			CalcCrits(Pl, true)
			WMH = 1
		elseif US > 0 and UM > 0 and (mainSlot == 0 or Pl.Items[mainSlot].Broken) then
			CalcCrits(Pl, true)
		else
			CritD = 100
			CritC = 0
			if offSkill and offSkill < 7 then
				CalcCrits(Pl, true)
			end
		end

		if Pl.ItemBow > 0 and not Pl.Items[Pl.ItemBow].Broken then
			CalcCrits(Pl, false)
		elseif mainSkill == 7 then
			CritDB = CritD
			CritCB = CritC
		else
			CritDB = 100
			CritCB = 0
		end

		-- Parry: one weapon in either hand, two-handed weapon or dual-wield
		ParryC = calcParryChanceUI(Pl, curseMult)

		-- Block: same conditions as MF.ShieldBlock in combat (MMMWE_Shields.lua)
		local blkCond = Pl:GetMainCondition()
		if offSkill == const.Skills.Shield and Game.ItemsTxt[getItemNum(Pl, offSlot)].EquipStat == 4
				and blkCond ~= const.Condition.Asleep
				and not (blkCond >= const.Condition.Paralyzed and blkCond <= const.Condition.Eradicated) then
			local sS, sM = SplitSkill(Pl:GetSkill(const.Skills.Shield))
			local offNum = getItemNum(Pl, offSlot)
			BlockC = math.min(MF.ShieldBlockChance(offNum, sS, math.max(sM, 1)) * curseMult, 100)   -- MMMWE_Shields.lua
		end

		local DodgeC = calcDodgeChanceUI(Pl, Pl.ItemArmor, Pl.ItemExtraHand) * curseMult
		local DUR = calcTotalArmorDurability(Pl)

		local SpiritRes = {Pl:GetResistance(33), Pl:GetBaseResistance(33)}
		local LightRes  = {Pl:GetResistance(50), Pl:GetBaseResistance(50)}
		local DarkRes   = {Pl:GetResistance(51), Pl:GetBaseResistance(51)}

		-- Format (cachedCstring in place of MF.cstring)
		MV.ResFormat      = cachedCstring("%s\f%05u\t115%d\f00000 / %d\n")
		MV.ResLongFormat  = cachedCstring("%s\f%05u\r185%d\f00000 / %d\n")
		MV.STRFMT_1       = cachedCstring("\n%s  \f%05d%s\n")

		MV.ResBodyFormat = cachedCstring(
			"%s\f%05u\t115%d\f00000 / %d\n" .. spiritString(Pl, SpiritRes[1], SpiritRes[2], true))
		MV.ResBodyLongFormat = cachedCstring(
			"%s\f%05u\r185%d\f00000 / %d\n" .. spiritString(Pl, SpiritRes[1], SpiritRes[2], false))

		if SpiritRes[1] >= IMMUNE_THRESHOLD then
			MV.ResBodyImmuneFormat = cachedCstring("%s\n" ..
				string.format("\t   Spirit\t115%s", "Immune"))
		elseif Pl:GetResistance(33) < 100 then
			MV.ResBodyImmuneFormat = cachedCstring("%s\n" .. spiritString(Pl, SpiritRes[1], SpiritRes[2], true))
		else
			MV.ResBodyImmuneFormat = cachedCstring("%s\n" .. spiritString(Pl, SpiritRes[1], SpiritRes[2], false))
		end

		if SpiritRes[1] >= IMMUNE_THRESHOLD and Pl:GetResistance(15) < 100 then
			MV.ResBodyFormat = cachedCstring(
				"%s\f%05u\t115%d\f00000 / %d\n" ..
				string.format("\t   Spirit\t115%s", "Immune"))
		elseif SpiritRes[1] >= IMMUNE_THRESHOLD and Pl:GetResistance(15) >= 100 then
			MV.ResBodyLongFormat = cachedCstring(
				"%s\f%05u\r185%d\f00000 / %d\n" ..
				string.format("\t   Spirit\t115%s", "Immune"))
		end

		-- Resistance format patches (smartPatch in place of asmpatch)
		for i, p in ipairs(ResFormatPatchAddrs) do
			local fmt = p[2] and MV.ResFormat or MV.ResLongFormat
			if i == 11 then fmt = MV.ResBodyFormat
			elseif i == 12 then fmt = MV.ResBodyLongFormat end
			smartPatch(p[1], p[2] and ResFmtPrefix or ResFmtPrefix2, fmt)
		end

		smartPatch(0x418951, "push ", MV.ResBodyImmuneFormat)

		-- HP/SP Regen
		local HPRegFromItems, SPRegFromItems = CalcHPSPRegen(Pl)
		local totalHPR = CalcSkillHPRegen(Pl) + CalcSpellHPRegen(Pl) + HPRegFromItems
			+ (MV.PotionHPReg[PlIndex + 1] or 0) - math.floor(MV.ZombieHPDegen[Pl.Name] or 0)
		local totalSPR = CalcMeditationSPRegen(Pl) + SPRegFromItems
			+ (MV.PotionSPReg[PlIndex + 1] or 0) - math.floor(MV.ZombieSPDegen[Pl.Name] or 0)

		-- per game minute (the regeneration is paid out a fifth per minute)
		local function perMin(v)
			local m = v / REGEN_SPREAD
			return string.format('%s%.1f', m >= 0 and '+' or '', m)
		end
		MV.HPR = cachedCstring(string.format('HP\t30 (%s/min)', perMin(totalHPR)))
		local resName = MF.GetResource and select(3, MF.GetResource(Pl))
		if resName then
			-- class resource (MMMWE_Resources.lua): no regeneration, it drains when idle
			-- the resource name only (it doesn't regenerate; a longer text runs into the value)
			MV.SPR = cachedCstring(resName)
		else
			MV.SPR = cachedCstring(string.format('SP\t30 (%s/min)', perMin(totalSPR)))
		end

		-- Armor Class and Physical Resistance
		MV.ADur = cachedCstring(string.format('HR Class\t65 %3.0f\t100',
			math.ceil(DUR / MF.HR_DIVISOR)))

		local mightEffect = Game.GetStatisticEffect(Pl:GetMight())
		local strengthDR = 1 - mightEffect * 0.01
		local armrNumerator = 5 + 200 - DUR / MF.HR_DIVISOR
		local armrDenominator = 10 + 200 - DUR / MF.HR_DIVISOR + Pl:GetArmorClass()
		local armrDR = armrNumerator / armrDenominator
		local physR = (1 - strengthDR * armrDR) * 100

		MV.PhysRes = cachedCstring(string.format('Phys\t150 %4.2f%%', physR))

		-- Light/Dark
		local lightLine = resLine("Light", CalcResME(Pl, 50), LightRes[1], LightRes[2])
		local darkLine  = resLine("Dark",  CalcResME(Pl, 51), DarkRes[1],  DarkRes[2])
		MO.UpperResValues = cachedCstring(lightLine .. "\n" .. darkLine .. " ")

		-- Dodge/Parry/Block
		-- Physical resistance against slashing / piercing / blunt hits: the Phys value
		-- above with the armor kind factor of all worn pieces (MMMWE_DamageKinds.lua)
		local kindLine = ""
		if MF.ArmorKindFactor then
			local function kr(kind)
				return (1 - strengthDR * armrDR * MF.ArmorKindFactor(Pl, kind)) * 100
			end
			kindLine = string.format('\n\t   Sla\t30 %3.1f%%\t85 Pie\t106 %3.1f%%\t155 Blu\t180 %3.1f%%',
				kr("Slashing"), kr("Piercing"), kr("Blunt"))
		end
		MO.LowerResValues = cachedCstring(string.format(
			'\t   Eva\t30 %3.1f%%\t85 Par\t106 %3.1f%%\t155 Blk\t180 %3.1f%%',
			DodgeC, ParryC, BlockC) .. kindLine)
		MO.ResFmt = cachedCstring("%s\n%s")

		-- Crits
		MV.MeleeCritStats  = cachedCstring(string.format(
			'Crit\t75 x%3.2f (%3.2f%%)\n\t-  Damage', CritD / 100, CritC))
		MV.RangedCritStats = cachedCstring(string.format(
			'Crit\t75 x%3.2f (%3.2f%%)\n\t-  Damage', CritDB / 100, CritCB))

		-- Elemental Resistances
		for i = 1, 6 do
			local edr = ElementalDRList[i]
			local str = cachedCstring(string.format('%s\t55 %3.1f%%',
				edr.name, CalcResME(Pl, edr.res)))
			smartPatch(ElementalDRAddrs[i], "push ", str)
		end

		-- Stat bonuses
		local StatGetters = {
			Pl.GetMight, Pl.GetIntellect, Pl.GetPersonality, Pl.GetEndurance,
			Pl.GetAccuracy, Pl.GetSpeed, Pl.GetLuck
		}

		for i = 1, #StatNames do
			local val = StatGetters[i](Pl)
			local bonus = Game.GetStatisticEffect(val)
			local sign = bonus >= 0 and '+' or '-'
			local str = cachedCstring(string.format('%s\t90 (%s%d)',
				StatNames[i], sign, math.abs(bonus)))
			smartPatch(StatBonusAddrs[i], "push ", str)
			ListedStatVals[i] = val
			ListedStatBonuses[i] = bonus
		end

		-- Widget patches
		for _, p in ipairs(WidgetPatchSpecs) do
			local val = MV[p[3]] or MO[p[3]]
			smartPatch(p[1], p[2] .. " ", val)
		end
	end)
	
	-- =====================================================================
	-- Jetpack
	-- =====================================================================

	local JETPACK_ITEM = 966
	local JUMP_COST = 10

	local flightState = nil  -- {playerIdx, itemSlot, buff}
	local flightTimerFunc

	flightTimerFunc = function()
		local f = flightState
		if not f then return end

		local Player = Party[f.playerIdx]
		if not Player or f.itemSlot <= 0 then
			flightState = nil
			return
		end

		local item = Player.Items[f.itemSlot]

		if not Party.InAir then
			f.buff.ExpireTime = Game.Time
			RemoveTimer(flightTimerFunc)
			flightState = nil
			return
		end

		if item.Charges == 1 then
			f.buff.ExpireTime = Game.Time + const.Minute * 5
			RemoveTimer(flightTimerFunc)
			flightState = nil
			return
		end

		item.Charges = item.Charges - 1
		Game.ShowStatusText(string.format(
			"Flight mode active. Remaining charge: %3.1f%%", item.Charges / 10))

		if item.Charges <= 20 and item.Charges > 0 then
			Game.ShowStatusText(string.format(
				"WARNING! Low charge: %3.1f%%", item.Charges / 10))
			Game.PlaySound(360)
		elseif item.Charges == 0 then
			Game.ShowStatusText("WARNING! Flight mode terminates in 5 minutes!")
			Game.PlaySound(360)
			Game.PlaySound(360)
			Game.PlaySound(360)
		end
	end

	function JetpackJump()
		local Player = Party:GetCurrentPlayer()
		local It = Player.ItemCloak
		if not It or It <= 0 then return end

		local item = Player.Items[It]
		if item.Number ~= JETPACK_ITEM then return end

		local _, BM = SplitSkill(Player:GetSkill(7))
		if BM < 2 then
			Game.ShowStatusText(string.format(
				"Tech mastery (%d/2) is insufficient to use this function", BM))
			Game.PlaySound(358)
			return
		end

		if item.Charges >= JUMP_COST then
			Game.PlaySound(42440)
			CastSpellDirect(16, 15, 4)
			item.Charges = item.Charges - JUMP_COST
			Game.ShowStatusText(string.format(
				"Remaining charge: %3.1f%%.", item.Charges / 10))
		else
			Game.ShowStatusText("Device charge CRITICAL! Operation aborted")
			Game.PlaySound(358)
		end
	end

	Keys[const.Keys.X] = JetpackJump

	function JetpackFlight()
		local Player = Party:GetCurrentPlayer()
		local It = Player.ItemCloak
		if not It or It <= 0 then return end

		local item = Player.Items[It]
		if item.Number ~= JETPACK_ITEM then return end

		local _, BM = SplitSkill(Player:GetSkill(7))
		if BM < 3 then
			Game.ShowStatusText(string.format(
				"Tech mastery (%d/3) is insufficient to use this function", BM))
			Game.PlaySound(358)
			return
		end

		if item.Charges <= 20 then
			Game.ShowStatusText("Device charge CRITICAL! Operation aborted")
			Game.PlaySound(358)
			return
		end

		if flightState then
			flightState.buff.ExpireTime = Game.Time
			RemoveTimer(flightTimerFunc)
			flightState = nil
		end

		evt.PlaySound{42440}
		Game.ShowStatusText("Flight mode activated")
		CastSpellDirect(21, 288, 1)

		flightState = {
			playerIdx = Player:GetIndex(),
			itemSlot = It,
			buff = Party.SpellBuffs[const.PartyBuff.Fly],
		}

		Timer(flightTimerFunc, const.Minute, const.Minute * 3)
	end

	Keys[const.Keys.V] = JetpackFlight

	function events.BeforeSaveGame()
		if flightState then
			flightState.buff.ExpireTime = Game.Time
			CastSpellDirect(16, 3, 1)
			RemoveTimer(flightTimerFunc)
			flightState = nil
		end
	end
	

