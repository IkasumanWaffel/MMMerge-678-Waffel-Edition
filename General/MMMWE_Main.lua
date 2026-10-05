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
	
	-- Hammerhands fix
	local HHSM = {[1] = 0, [2] = 0}
	mem.autohook(0x42B17F, function(d)
		HHSM[1], HHSM[2] = d.edi, mem.u4[d.ebp - 0xC]
	end)
	
		-- Armor skill bonus changes
	function events.CalcStatBonusBySkills(t)
		-- Stat 9 = ArmorClass
		if t.Stat ~= 9 or t.Result == 0 then
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
				if skill == 8 and slotIdx == Pl.ItemExtraHand then
					rating = itemTxt.Mod1DiceCount * itemTxt.Mod1DiceSides + itemTxt.Mod2
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
			{skill=10, minM=1, highM=4,  lowC=0.025,  highC=0.0375, mC=0.125, perItem=true,  hiPenMul=1},
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

	local WEAPON_BONUSES = {
		-- Parry Chance Bonus
		[1] = {
			5, 5, 5, 5,     -- Longswords
			10, 10, 10, 10, -- Two-Handed Swords
			3, 3, 3, 3,     -- Broadswords
			7, 7, 7, 7,     -- Cutlasses
			12, 12, 12, 12, -- Daggers
			15, 15, 15, 15, -- Long Daggers
			2, 2, 2, 2,     -- Axes
			10, 10, 10, 10, -- Two-Handed Axes
			15, 15, 15, 15, -- Spears
			10, 10, 10, 10, -- Halberds
			20, 20, 20, 20, -- Tridents
			9, 9, 9, 9,     -- Maces
			0, 0, 0, 0,     -- Flails
			6, 6, 6, 6,     -- Hammers
			20, 20, 20, 20, -- Staves
			10, 10,         -- Warhammers
			10, 10,         -- Greatswords
			12             	-- Sabers
		},
		
		-- Attack Delay Penalty
		[2] = {
			0, 0, 0, 0,     -- Longswords
			0, 0, 0, 0,     -- Two-Handed Swords
			5, 5, 5, 5,     -- Broadswords
			-5, -5, -5, -5, -- Cutlasses
			-5, -5, -5, -5, -- Daggers
			3, 3, 3, 3,     -- Long Daggers
			0, 0, 0, 0,     -- Axes
			0, 0, 0, 0,     -- Two-Handed Axes
			-5, -5, -5, -5, -- Spears
			5, 5, 5, 5,     -- Halberds
			0, 0, 0, 0,     -- Tridents
			0, 0, 0, 0,     -- Maces
			3, 3, 3, 3,     -- Flails
			-5, -5, -5, -5, -- Hammers
			0, 0, 0, 0,     -- Staves
			0, 0,           -- Warhammers
			5, 5,           -- Greatswords
			-7             	-- Sabers
		},
    
    -- Parry Strength Bonus
		[3] = {
			2, 2, 2, 2,     -- Longswords
			8, 8, 8, 8,     -- Two-Handed Swords
			5, 5, 5, 5,     -- Broadswords
			0, 0, 0, 0,     -- Cutlasses
			1, 1, 1, 1,     -- Daggers
			3, 3, 3, 3,     -- Long Daggers
			5, 5, 5, 5,     -- Axes
			10, 10, 10, 10, -- Two-Handed Axes
			7, 7, 7, 7,     -- Spears
			10, 10, 10, 10, -- Halberds
			7, 7, 7, 7,     -- Tridents
			12, 12, 12, 12, -- Maces
			6, 6, 6, 6,     -- Flails
			10, 10, 10, 10, -- Hammers
			12, 12, 12, 12, -- Staves
			8, 8,           -- Warhammers
			12, 12,         -- Greatswords
			0              	-- Sabers
		}
	}

	function CalcWeaponStatBonusByWType(WeaponNum, WeaponStat)

		local weaponType = Game.ItemsTxt[WeaponNum].NotIdentifiedName
		
		if not WEAPON_BONUSES[WeaponStat] then
			return 0
		end
		
		local weaponIndex = table.ifind(WEAPON_TYPES, weaponType)
		
		return weaponIndex and WEAPON_BONUSES[WeaponStat][weaponIndex] or 0
	end

	-- Change base attack delay values of weapon and armor types
--						 Staff	 Sword   Dagger Axe     Spear   Bow     Mace    Blaster  Shield Leather Chain  Plate  Unarmed w|o Skill	
	local Delay_table = {110, 0, 100, 0, 60, 0, 115, 0, 110, 0, 100, 0, 130, 0, 75, 0,   10, 0, 10, 0,  20, 0, 30, 0, 100, 0}
	
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

	local LargeShieldNames = {
		['Large Shield'] = true,
		['Artifact Large Shield'] = true,
		['Relic Large Shield'] = true,
	}

	-- Common Attack Recovery Delay modifiers
	local function applySpeed(Pl, result)
		local spd = Game.GetStatisticEffect(Pl:GetSpeed())
		result = result + spd
		return result - 0.01 * result * spd
	end

	local function applyArmsMaster(Pl, result)
		local AS, AM = SplitSkill(Pl.Skills[35])
		if AM >= 1 and AM < 4 then
			result = result - 0.01 * result * AS + AS
		elseif AM == 4 then
			result = result - 0.02 * result * AS + 2 * AS
		end
		return result
	end

	local function applyHaste(Pl, result)
		local Buff = Pl.SpellBuffs[const.PlayerBuff.Haste]
		if Buff.ExpireTime > Game.Time then
			result = result + 25
			return result * 0.75
		end
		return result
	end

	function events.GetAttackDelay(t)
		local Pl = t.Player
		local WeapSlot = Pl.ItemMainHand
		local ShieldSlot = Pl.ItemExtraHand
		local BowSlot = Pl.ItemBow

		-- Auxiliary armor penalties (helm, gauntlets, belt, boots)
		local auxSlots = {Pl.ItemHelm, Pl.ItemBelt, Pl.ItemGauntlets, Pl.ItemBoots}
		for _, slotIdx in ipairs(auxSlots) do
			if slotIdx > 0 and not Pl.Items[slotIdx].Broken then
				local skill = Game.ItemsTxt[Pl.Items[slotIdx].Number].Skill
				local pen = AuxArmorPenalties[skill]
				if pen then
					local _, M = SplitSkill(Pl:GetSkill(skill))
					t.Result = t.Result + pen[math.max(M, 1)]
				end
			end
		end

		-- Large shield penalty
		if ShieldSlot > 0 and not Pl.Items[ShieldSlot].Broken
		   and Game.ItemsTxt[Pl.Items[ShieldSlot].Number].Skill == 8 then
			local shieldName = Game.ItemsTxt[Pl.Items[ShieldSlot].Number].NotIdentifiedName
			if LargeShieldNames[shieldName] then
				local _, ShieldM = SplitSkill(Pl:GetSkill(8))
				t.Result = t.Result + select(math.max(ShieldM, 1), 15, 15, 10, 0)
			end
		end

		MV.AuxArmorRecoveryPenalty[Pl.Name] = t.Result

		local hasWeapon = WeapSlot > 0 and not Pl.Items[WeapSlot].Broken

		-- Non-blaster weapon in main hand
		if hasWeapon then
			local WeapNum = Pl.Items[WeapSlot].Number
			local WeapEquipStat = Game.ItemsTxt[WeapNum].EquipStat
			local WeapType = Game.ItemsTxt[WeapNum].Skill

			t.Result = t.Result + CalcWeaponStatBonusByWType(WeapNum, 2)

			if WeapEquipStat == 1 and WeapType then
				local WeapSkills = {1, 3, 6}  -- Sword, Axe, Mace
				if table.find(WeapSkills, WeapType) then
					t.Result = t.Result + select(table.ifind(WeapSkills, WeapType), 20, 23, 26)
					local WS, WM = SplitSkill(Pl.Skills[WeapType])
					if WeapType ~= 6 and WM >= 2 then
						t.Result = t.Result - 0.01 * t.Result * WS + WS
					end
				end
			end

			t.Result = applySpeed(Pl, t.Result)
			t.Result = applyArmsMaster(Pl, t.Result)
			t.Result = applyHaste(Pl, t.Result)
		end

		-- Ranged weapon (bows and crossbows)
		if t.Ranged and BowSlot > 0 and not Pl.Items[BowSlot].Broken then
			local BowType = Game.ItemsTxt[Pl.Items[BowSlot].Number].NotIdentifiedName
			if BowType == 'Crossbow' or BowType == 'Relic Crossbow' then
				t.Result = t.Result + 50 - t.Result*Game.GetStatisticEffect(Pl:GetMight())/100
			end

			local BS, BM = SplitSkill(Pl.Skills[5])
			if BM >= 2 then
				t.Result = t.Result - 0.01 * t.Result * BS + BS
			end

			t.Result = applySpeed(Pl, t.Result)
			t.Result = applyHaste(Pl, t.Result)
		end

		-- Unarmed / Extra hand weapon
		if (WeapSlot == 0 or Pl.Items[WeapSlot].Broken)
		   and (ShieldSlot == 0 or Pl.Items[ShieldSlot].Broken) then
			t.Result = applySpeed(Pl, t.Result)
			t.Result = applyHaste(Pl, t.Result)
		elseif ShieldSlot > 0 and not Pl.Items[ShieldSlot].Broken
		   and Game.ItemsTxt[Pl.Items[ShieldSlot].Number].Skill ~= 8 then
			t.Result = t.Result + CalcWeaponStatBonusByWType(Pl.Items[ShieldSlot].Number, 2)
			t.Result = applySpeed(Pl, t.Result)
			t.Result = applyArmsMaster(Pl, t.Result)
			t.Result = applyHaste(Pl, t.Result)
		end

		-- Blaster fixed Attack Recovery Delay
		if hasWeapon and Game.ItemsTxt[Pl.Items[WeapSlot].Number].Skill == 7 then
			local item = Pl.Items[WeapSlot]
			local base = select(math.floor(item.Number / 800), 865, 1665)
			local idx = item.Number - base
			local chargeMod = math.floor(item.Charges / 1000) * 5
			t.Result = select(idx, 50 - chargeMod, 35 - chargeMod)
		end
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
	
	local CritChanceBSMods  = {0, 0.01, 0.015, 0.02}
	local CritDamageBSMods  = {0, 0,    0.02,  0.04}

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
		local CCBase  = 10

		local modTier = math.floor(Player.Items[item].Charges / 1000)

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

		-- Mod Tier damage scaling
		if modTier > 0 then
			local scale = 1 + modTier * 0.05 * BS
			DMin = round(DMin * scale)
			DMax = round(DMax * scale)
		end

		-- Crit chance
		local critChance = CCBase + Player:GetAccuracy() / 20 + specCritC
		if modTier > 0 then
			critChance = critChance + CCBase * CritChanceBSMods[modTier] * BS
		end
		critChance = critChance * curseMult
		CritC = critChance

		-- Crit damage mult (percent)
		local critDamageP = CDBase + 100 + specCritD
		if modTier > 0 then
			critDamageP = critDamageP + CDBase * CritDamageBSMods[modTier] * BS
		end
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

	-- autohook2 at 0x4259CF (lea esi, [edx+eax+1Eh])
	-- Executed only for non-immune monsters (standard code if immune)
	mem.autohook2(0x4259CF, function(d)
		local res = d.eax + d.edx
		local damage = mem.i4[d.ebp + 0x10]
		local element = mem.i4[d.ebp + 0x0C]  -- второй параметр monster_resists

		local pct = CalcMonResPercent(res)
		local newDmg = round(damage * pct)
		mem.i4[d.ebp + 0x10] = newDmg

		MF.LogInfo("[RES] elem=%d res=%d dmg=%d -> %d (pct=%.3f)",
			element, res, damage, newDmg, pct)

		d.eax = 0
		d.edx = 0
	end)


	-- Weapon crit module

	-- index = skill + 1
	local WCDBase   = {0.500, 0.300, 1.000, 0.500, 0.400, 0.500, 0.700, 0.250}
	local WCDGrowth = {0.010, 0.010, 0.020, 0.012, 0.011, 0.015, 0.014, 0.013}
	local WCCBase   = {5.000, 7.000, 10.00, 8.000, 7.000, 5.000, 6.000, 6.000}
	local WCCGrowth = {0.050, 0.100, 0.150, 0.115, 0.125, 0.150, 0.085, 0.120}

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
		[7] = {44671, 44672, 44673, 44671, 44672, 44673},
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

	-- Crit chance (%, before curse) and damage multiplier of one weapon skill
	local function skillCrit(pl, skill, S, M, specC, specD)
		local idx = skill + 1
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

		if sk1 then
			local c, d = skillCrit(Pl, sk1, S1, M1, specC, specD)
			if txt1.EquipStat == 1 then
				d = (d - 1) * 1.5 + 1
			end
			if sk2 then
				local c2, d2 = skillCrit(Pl, sk2, S2, M2, specC, specD)
				c, d = (c + c2) / 2, (d + d2) / 2
			end
			return c, d, sk1
		end

		if sk2 then
			local c, d = skillCrit(Pl, sk2, S2, M2, specC, 0)
			return c, 1 + (d - 1) / 2 + specD, sk2
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
				Game.PlaySound(snd[math.random(1, 6)], MonSoundRef(Mon))
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
		if _G.CE_SecondaryResist and _G.CE_SecondaryResist > 0 then return end
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

		local Pl = t.Player
		local Melee = t.Melee

		-- Skip secondary calls (from ItemAdditionalDamage enchantment processing)
		-- These are enchantment damage calls where the engine already applied
		-- the correct damage kind via the ItemAdditionalDamage hook.
		-- We must not apply crits, high ground, or durability penalties to them.
		if _G.CE_SecondaryResist and _G.CE_SecondaryResist > 0 then
			_G.CE_SecondaryResist = _G.CE_SecondaryResist - 1
			return
		end

		-- Hammerhands fix (merged from the overwritten first handler)
		if Pl then
			local Weapon = Pl.ItemMainHand
			local Buff = Pl.SpellBuffs[const.PlayerBuff.Hammerhands]
			if Buff.ExpireTime > Game.Time then
				if t.DamageKind == const.Damage.Phys and Weapon == 0 then
					local HHPower = HHSM[1]
					local BuffMas = HHSM[2]
					local HHBonus = 0.2 + 0.01*BuffMas*HHPower + 0.01*HHPower
					t.Result = round(t.Result + t.Result*HHBonus - HHPower)
				end
			end
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
				t.Result = round(t.Result + t.Result*HighGround/4000)
					+ (isCrossbow and DamageBonusStat[2] or DamageBonusStat[1])
			end
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

				local modTier = math.floor(Pl.Items[mainHand].Charges / 1000)
				local Mon = t.Monster
				local eradicationChance = (1 - Mon.HP / Mon.FullHP) * 100
					* modTier * CalcMonResPercent(Mon.BodyResistance)

				if CritProc == 1 then
					eradicationChance = eradicationChance * (2 + modTier*2)
					Game.PlaySound(math.random(44671,44673), MonSoundRef(Mon))
				end

				if math.random(1, 10000) <= eradicationChance then
					t.Result = Mon.HP
					Game.PlaySound(math.random(44671,44673), MonSoundRef(Mon))
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

	local LargeShieldNames = {
		["Large Shield"]			= true,
		["Artifact Large Shield"]	= true,
		["Relic Large Shield"]		= true,
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
				if LargeShieldNames[shTxt.NotIdentifiedName] then
					local extraPen = ({15, 15, 10, 0})[shieldM] or 0
					penalties[shieldM] = penalties[shieldM] + extraPen
				end
				chance = chance - penalties[shieldM]
			end
		end

		-- Armor penalty
		if armorChest > 0 and not pl.Items[armorChest].Broken then
			local armSkill = Game.ItemsTxt[pl.Items[armorChest].Number].Skill
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

	-- Shield Block calculation
	local function CalcShieldBlock(pl, shield, shieldS, shieldM, curseMult)
		local cond = pl:GetMainCondition()
		if shield <= 0 or cond == const.Condition.Asleep or (cond >= const.Condition.Paralyzed and cond <= const.Condition.Eradicated) then
			return 1, 1, 1
		end

		local shNum = pl.Items[shield].Number
		if Game.ItemsTxt[shNum].EquipStat ~= 4 or pl.Items[shield].Broken then
			return 1, 1, 1
		end

		local blockChance = 20 + 0.5 * shieldS * shieldM
		if LargeShieldNames[Game.ItemsTxt[shNum].NotIdentifiedName] then
			blockChance = 30 + 0.75 * shieldS * shieldM
		end

		local blockStrength = 30 + Game.ItemsTxt[shNum].Mod1DiceSides + Game.ItemsTxt[shNum].Mod2
		local shItem = pl.Items[shield]
		
		if shItem.Bonus == 10 then
			blockStrength = blockStrength + shItem.BonusStrength
		else
			local shieldEnchants = {[42] = 1, [43] = 10, [48] = 5}
			if shieldEnchants[shItem.Bonus2] then
				blockStrength = blockStrength + shieldEnchants[shItem.Bonus2]
			end
		end

		local magicStr = blockStrength * (2 / 3)
		local energyStr = blockStrength / 3

		blockChance = blockChance * curseMult
		local physDR, magicDR, energyDR = 1, 1, 1

		if math.random() * 100 < blockChance then
			physDR = math.max(0, 1 - 0.01 * blockStrength)
			if shieldM >= const.Master then
				magicDR = math.max(0, 1 - 0.01 * magicStr)
			end
			if shieldM == const.GM then
				if shNum == 968 then -- Energy Shield Relic
					energyStr = blockStrength
				end
				energyDR = math.max(0, 1 - 0.01 * energyStr)
			end
		end

		return physDR, magicDR, energyDR
	end

	-- Energy Shield Absorb
	local function CalcEnergyShieldDR(pl, damageTotal, dodgeDR, weaponDR, shieldDR, absStr)
		local slot = pl.ItemBelt
		if slot <= 0 then return 1, 0 end
		
		local itnum = pl.Items[slot].Number
		if itnum ~= 968 or pl.SP <= 0 then
			return 1, 0
		end

		local spDrain = damageTotal * math.min(dodgeDR, math.min(weaponDR, shieldDR)) * absStr
		local esDR

		if pl.SP >= spDrain then
			esDR = 1 - absStr
		else
			local coeff = pl.SP / spDrain
			pl.SP = 0
			esDR = 1 - (coeff * absStr)
		end

		return esDR, spDrain
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
		if dodgeChance > 0 and math.random() * 100 < dodgeChance then
			dodgeDR = 1 - 0.01 * (10 + 10 * dodgeM)
		end

		-- --- Weapon Parry & Shield Block ---
		local weaponPhysDR, weaponMagicDR, weaponEnergyDR, parrySkill = CalcWeaponParry(pl, curseMult)
		local shieldPhysDR, shieldMagicDR, shieldEnergyDR = CalcShieldBlock(pl, pl.ItemExtraHand, shieldS, shieldM, curseMult)

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

		t.Result = round(t.Result * math.min(dodgeDR, math.min(wDR, shDR)) * enshDR * arDR * stDR)
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
		local _, idMonMastery = SplitSkill(pl:GetSkill(const.Skills.IdentifyMonster))
		if idMonMastery >= const.Expert and DamageTypeNames[t.DamageKind] then
			dmgTypeName = DamageTypeNames[t.DamageKind]
		end

		Game.ShowStatusText(string.format(
			"%s takes %d %s damage (%d negated, %.1f%%)",
			pl.Name, t.Result, dmgTypeName, negated, negPercent), 5)
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
		_G.CE_SecondaryResist = 0
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

	-- SP per regen tick from Meditation (0 if none). Used by the tick and the character screen.
	local function CalcMeditationSPRegen(Player)
		if not CanRegen(Player) then return 0 end
		local RegS, RegM = SplitSkill(Player:GetSkill(const.Skills.Meditation))
		if RegM <= 0 then return 0 end
		RegS = RegS + Player:CalcStatBonusByItems(const.Stats.Meditation)
		local Add = RegM + RegS/10
		return round(Add + Add*Game.GetStatisticEffect(Player:GetIntellect())/10 + Add*Game.GetStatisticEffect(Player:GetPersonality())/20)
	end

	-- HP per regen tick from the Regeneration skill (0 if none)
	local function CalcSkillHPRegen(Player)
		if not CanRegen(Player) then return 0 end
		local RegS, RegM = SplitSkill(Player:GetSkill(const.Skills.Regeneration))
		local RegP = (RegS > 0 and 0.5 or 0) + RegS/10*RegM
		return RegP > 0 and math.ceil(Player:GetFullHP()*RegP/100) or 0
	end

	-- HP per regen tick from an active Regeneration spell (healed by the game itself)
	local function CalcSpellHPRegen(Player)
		if not CanRegen(Player) then return 0 end
		local Buff = Player.SpellBuffs[const.PlayerBuff.Regeneration]
		return Game.Time < Buff.ExpireTime and Buff.Power or 0
	end

	-- Add a bit of sp regeneration by meditation skill
	function events.RegenTick(Player)
		local Add = CalcMeditationSPRegen(Player)
		if Add > 0 then
			Player.SP = math.min(Player:GetFullSP(), Player.SP + Add)
		end
	end
	
	-- Make regeneration skill and spell mm7-alike
	-- TODO: move everything into regeneration part of mm8 proc?
	function events.RegenTick(Player)
		if CanRegen(Player) then
			local Add = CalcSkillHPRegen(Player)
			if Add > 0 then
				Player.HP = math.min(Player.HP + Add, Player:GetFullHP())
			end
			if Player.HP > 0 then
				Player.Conditions[13] = 0
			end
		end
	end

	mem.autohook(0x4273fc, function(d)			-- Regeneration spell MM7-alike effect
		local Target = Party[mem.u4[d.ebx+4]]
		local Cond = Target:GetMainCondition()
		if Cond >= 17 or Cond < 14 then
			local RegS = mem.i4[d.ebp-0x14]/3600
			local RegM = mem.i4[d.ebp-0xC]
			local FHP = Target:GetFullHP()
			mem.i4[d.ebp-4] = math.ceil(0.005*FHP+0.001*RegM*RegS*FHP)
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
		[866] = 4, [867] = 4, [1666] = 4, [1667] = 4,  
		[970] = 5, [971] = 5, [972] = 5, [973] = 5, [975] = 5, [976] = 5,
		[977] = 5, [978] = 5, [980] = 5, [981] = 5, [982] = 5, [983] = 5,
		[984] = 5, [985] = 5, [986] = 5, [987] = 5,
		[969] = 6, [974] = 6, [979] = 6,
	}

	local ShieldEnchBonus = {
		[42] = 1,
		[43] = 10,
		[48] = 5,
	}

	mem.autohook(0x41d3b3, function(d)
		DICharge = mem.i4[d.ecx + 0x10]
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
		maxDur, curDur = round(maxDur), round(curDur)
		if curDur >= maxDur then
			return string.format("%d", maxDur)
		end
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

		local armor = item.Mod1DiceCount + item.Mod2
		local block = 30 + armor
		local plItem = pl.Items[itSlot]

		if plItem.Bonus == 10 then
			block = block + plItem.BonusStrength
		elseif ShieldEnchBonus[plItem.Bonus2] then
			block = block + ShieldEnchBonus[plItem.Bonus2]
		end

		return cachedCstring(string.format("Armor: +%d   Block Power: %d%s", armor, block,"%%"))
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
			return cachedCstring(string.format("Upgrade: T%d    Mod Progress: %d%s",
				math.floor(ch / 1000), math.fmod(ch, 1000),"%%"))
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
		local modTier = math.floor(DICharge / 1000)
		local dMin = bt == 1 and 10 or 15
		local dMax = bt == 1 and 20 or 30
		local cBase = bt == 1 and 8 or 12

		if modTier > 0 then
			dMin = round(dMin + modTier * 0.05 * dMin * BS)
			dMax = round(dMax + modTier * 0.05 * dMax * BS)
		end

		return {
			cachedCstring(string.format('Shoot: +%d    Damage: %d-%d', cBase, dMin, dMax)),
			cachedCstring(' '),
		}
	end

	mem.autohook(0x41ced5, function(d)
		local IN = d.eax
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

	local function calcHammerhandsBonus(pl)
		local buff = pl.SpellBuffs[const.PlayerBuff.Hammerhands]
		if not buff or buff.ExpireTime <= Game.Time then
			return 0
		end
		local power, skill = buff.Power, buff.Skill
		
		return 0.2 + 0.01 * skill * power + 0.01 * power
	end

	local function calcHeroismBonus(pl)
		local buff = pl.SpellBuffs[const.PlayerBuff.Heroism]
		if buff and buff.ExpireTime > Game.Time then
			return buff.Power
		end
		return 0
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

	local function UnarmedDamageHook(ret)
		return function(d)
			local pl = isUnarmedMonk(d.ecx)
			if not pl then
				return
			end

			local mightBonus = Game.GetStatisticEffect(pl:GetMight())
			local unarmedBonus = calcUnarmedBonus(pl)
			local heroismBonus = calcHeroismBonus(pl)

			local minDamage = 1 + mightBonus + unarmedBonus + heroismBonus
			local maxDamage = 3 + mightBonus + unarmedBonus + heroismBonus

			local hhBonus = calcHammerhandsBonus(pl)
			if hhBonus > 0 then
				minDamage = round(minDamage + minDamage * hhBonus)
				maxDamage = round(maxDamage + maxDamage * hhBonus)
			end

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
			d.edi = minD
			d.eax = maxD
			d:push(ret)
			return true
		end
	end
	
	mem.autohook(0x48CCAA, RangedDamageHook(0x48CCCF))

	-- Widget V-offset patches
	local WidgetVPatches = {
		-- General widgets
		{addr = 0x418037, asm = "lea ebp, [ebp+eax*2-1]", desc = "HP"},
		{addr = 0x4180af, asm = "lea eax, [eax+ebp-4]", desc = "SP"},
		{addr = 0x418131, asm = "lea eax, [eax+ebp-4]", desc = "Armor Class"},
		{addr = 0x41819f, asm = "lea eax, [eax+ebp-5]", desc = "Condition (replaced by HR and Phys Res)"},
		{addr = 0x4181f0, asm = "lea ebp, [ebp+eax*2+9]", desc = "Quick spell (replaced by resistances and chances)"},
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
			local pen = DodgePenalties[shM] or 0
			if LargeShieldNames[Game.ItemsTxt[getItemNum(pl, shieldSlot)].NotIdentifiedName] then
				pen = pen + select(shM, 15, 15, 10, 0)
			end
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
		[968] = {0, 5}, [1331] = {3, 3}, [1334] = {0, 3}, [1335] = {3, 0},
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
	local function spiritString(pl, spiritRes, spiritBase, shortFormat)
		local resME = CalcResME(pl, 33)
		if spiritRes >= IMMUNE_THRESHOLD then
			return string.format("\t   Spirit\t115%s", "Immune")
		end
		local pct = "%%"
		if shortFormat then
			return string.format("\t   Spirit\t55 %3.1f%s\t115%d\f00000 / %d",
				resME, pct, spiritRes, spiritBase)
		else
			return string.format("\t   Spirit\t55 %3.1f%s\r185%d\f00000 / %d",
				resME, pct, spiritRes, spiritBase)
		end
	end

	local function resLine(name, resME, resVal, resBase)
		if resVal >= IMMUNE_THRESHOLD then
			return string.format("\t   %s\t160%s", name, "Immune")
		end
		return string.format("\t   %s\t90 %3.1f%%\t160%d\f00000 / %d",
			name, resME, resVal, resBase)
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
			local pen = DodgePenalties[shM] or 0
			if LargeShieldNames[Game.ItemsTxt[getItemNum(pl, shieldSlot)].NotIdentifiedName] then
				pen = pen + select(shM, 15, 15, 10, 0)
			end
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

		-- Block: same conditions as CalcShieldBlock in combat
		local blkCond = Pl:GetMainCondition()
		if offSkill == const.Skills.Shield and Game.ItemsTxt[getItemNum(Pl, offSlot)].EquipStat == 4
				and blkCond ~= const.Condition.Asleep
				and not (blkCond >= const.Condition.Paralyzed and blkCond <= const.Condition.Eradicated) then
			local sS, sM = SplitSkill(Pl:GetSkill(const.Skills.Shield))
			local offNum = getItemNum(Pl, offSlot)
			BlockC = 20 + 0.5 * sS * sM
			if LargeShieldNames[Game.ItemsTxt[offNum].NotIdentifiedName] then
				BlockC = 30 + 0.75 * sS * sM
			end
			BlockC = math.min(BlockC * curseMult, 100)
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

		MV.HPR = cachedCstring(string.format('HP\t30 (%s%d/RTick)',
			totalHPR >= 1 and '+' or '', totalHPR))
		MV.SPR = cachedCstring(string.format('SP\t30 (%s%d/RTick)',
			totalSPR >= 1 and '+' or '', totalSPR))

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
		MO.LowerResValues = cachedCstring(string.format(
			'\t   Eva\t30 %3.1f%%\t80 Par\t105 %3.1f%%\t155 Blk\t180 %3.1f%%',
			DodgeC, ParryC, BlockC))
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
	
	-- Random music for all maps
	do
		local MapMusicSets = {} -- map id = {}
		
		-- MM8 Music
		MapMusicSets[46	] = {2,117							}			--Escaton's Palace
				
		MapMusicSets[15 ] = {2								}			--Tutorial
		MapMusicSets[21 ] = {2,118							}			--Escaton's Crystal
		MapMusicSets[24 ] = {2,20							}			--Troll Tomb
		MapMusicSets[29 ] = {2,12							}			--Naga Vault
		MapMusicSets[57 ] = {2,10,89						}			--Church of Eep
					
		MapMusicSets[3  ] = {3,92,98,113,114,127			}			--Alvar
		MapMusicSets[10 ] = {3,97,123						}			--Plane of Earth
		MapMusicSets[16 ] = {3,122							}			--Abandoned Temple
		MapMusicSets[32 ] = {3,54,57,63						}			--Vampire Crypt
		MapMusicSets[37 ] = {3,54,57,63						}			--The Crypt of Korbu
		MapMusicSets[47 ] = {3								}			--Prison of the Lord of Air
		MapMusicSets[52 ] = {3,54,56,61					    }			--Dark Dwarf Compound
		MapMusicSets[205] = {3,115,116,117,118,119			}			--The Breach
					
		MapMusicSets[1  ] = {4,59							}			--Dagger Wound Island
		MapMusicSets[20 ] = {4								}			--Merchant House of Alvar
		MapMusicSets[25 ] = {4,31,89						}			--Cyclops Larder
		MapMusicSets[38 ] = {4,134							}			--Castle of Air
		MapMusicSets[58 ] = {4,60							}			--Old Loeb's Cave
					
		MapMusicSets[19 ] = {5,56							}			--Dire Wolf Den
		MapMusicSets[48 ] = {5								}			--Prison of the Lord of Fire
		MapMusicSets[53 ] = {5								}			--Arena
					
		MapMusicSets[4  ] = {6,58,90,105					}			--Ironsand Desert
		MapMusicSets[5  ] = {6,87,92,128					}			--Garrote Gorge
		MapMusicSets[8  ] = {6,93,95,96						}			--Ravage Roaming
		MapMusicSets[40 ] = {6,79,86,103					}			--Castle of Fire
		MapMusicSets[61 ] = {6								}			--NWC
					
		MapMusicSets[12 ] = {7,84,107						}			--Plane of Water
		MapMusicSets[26 ] = {7,79,103						}			--Chain of Fire
		MapMusicSets[41 ] = {7,86,103						}			--War Camp
		MapMusicSets[51 ] = {7,24,134						}			--Uplifted Library
		MapMusicSets[59 ] = {7,60							}			--Ilsingore's Cave
					
		MapMusicSets[49 ] = {8,136							}			--Prison of the Lord of Water
		MapMusicSets[54 ] = {8,136							}			--Ancient Troll Home
					
		MapMusicSets[2  ] = {9,53,114						}			--Ravenshore
		MapMusicSets[9  ] = {9,76,64						}			--Plane of Air
		MapMusicSets[27 ] = {9,89,130						}			--Dragon Hunter's Camp
		MapMusicSets[36 ] = {9,89							}			--Barbarian Fortress
		MapMusicSets[60 ] = {9,60							}			--Yaardrake's Cave
					
		MapMusicSets[11 ] = {10,68,86,79,103			    }			--Plane of Fire
		MapMusicSets[13 ] = {59,94,107					    }			--Regna
		MapMusicSets[17 ] = {10,134							}			--Pirate Outpost
		MapMusicSets[50 ] = {10,123							}			--Prison of the Lord of Earth
		MapMusicSets[55 ] = {10,88,89						}			--Grand Temple of Eep
					
		MapMusicSets[6  ] = {11,64,66,72,121				}			--Shadowspire
		MapMusicSets[18 ] = {11,54,56				 		}			--Smuggler's Cove
		MapMusicSets[30 ] = {11,72,106,134				    }			--Necromancers' Guild
		MapMusicSets[35 ] = {11,116,137						}			--Balthazar Lair
		MapMusicSets[45 ] = {11,116							}			--Small Sub Pen
					
		MapMusicSets[22 ] = {12,56				  		    }			--Wasp Nest
		MapMusicSets[34 ] = {12,97,123						}			--Druid Circle
		MapMusicSets[39 ] = {12,20							}			--Tomb of Lord Brinne
		MapMusicSets[42 ] = {12,62,89,134					}			--Pirate Stronghold
		MapMusicSets[43 ] = {12,62,89,134					}			--Abandoned Pirate Keep
		MapMusicSets[44 ] = {12,60						    }			--Passage Under Regna
					
		MapMusicSets[7  ] = {13,55,64,67  				    }			--Murmurwoods
		MapMusicSets[23 ] = {13,56,62,89					}			--Ogre Fortress
		MapMusicSets[28 ] = {13,60							}			--Dragon Cave
		MapMusicSets[33 ] = {13,132							}			--Temple of the Sun
					
		MapMusicSets[56 ] = {14								}			--Chapel of Eep
					
		MapMusicSets[14 ] = {15,106,117,116,115,118,119	    }			--Plane Between Planes
					
		MapMusicSets[31 ] = {86,88,106						}			--Mad Necromancer's Lab 
		
		-- MM7 Music
		MapMusicSets[66 ] = {17,58,74,101,104			    }			--Deyja
		MapMusicSets[67 ] = {17,58,81,91,105				}			--The Bracada Desert
		
		MapMusicSets[75 ] = {18,56,62					    }			--The Erathian Sewers
		MapMusicSets[76 ] = {18,54,62,70				    }			--The Maze
		MapMusicSets[82 ] = {18,54,56,62				    }			--The Tularean Caves
		MapMusicSets[84 ] = {18,60,62,68,123				}			--The Breeding Zone
		MapMusicSets[85 ] = {18,60,62,76,116				}			--The Walls of Mist
		MapMusicSets[86 ] = {18,86,88					    }			--Clanker's Laboratory
		MapMusicSets[89 ] = {18,54,68,72					}			--Watchtower 6
		MapMusicSets[90 ] = {56,57,63,68				    }			--The Wine Cellar
		MapMusicSets[91 ] = {18,56,62 					    }			--The Tidewater Caverns
		MapMusicSets[95 ] = {18,54,56,61				    }			--White Cliff Cave
		MapMusicSets[96 ] = {18,84,133					    }			--The Hall under the Hill
		MapMusicSets[108] = {18,54,56,61				    }			--The Red Dwarf Mines
		MapMusicSets[109] = {18,60,61,119				    }			--Nighon Tunnels
		MapMusicSets[111] = {57,63,68,117				    }			--The Haunted Mansion
		MapMusicSets[127] = {18,60						    }			--Wromthrax's Cave
		MapMusicSets[129] = {18,62,117					    }			--The Hidden Tomb
		MapMusicSets[136] = {18,60,62,68				    }			--The Hall of the Pit
		
		MapMusicSets[63 ] = {19,102,110,111,112,114,127		}			--Harmondale
		MapMusicSets[72 ] = {19,65,83,126,128 				}			--Tatalia
		MapMusicSets[73 ] = {19,73,85,87,109				}			--Avlee
					
		MapMusicSets[87 ] = {20,	57,	63,	68,	115			}			--Zokarr's Tomb
		MapMusicSets[112] = {20,	57,	63,	68,	115			}			--Barrow VII
		MapMusicSets[113] = {20,	57,	63,	68,	115			}			--Barrow IV
		MapMusicSets[114] = {20,	57,	63,	68,	115			}			--Barrow II
		MapMusicSets[115] = {20,	57,	63,	68,	115			}			--Barrow XIV
		MapMusicSets[116] = {20,	57,	63,	68,	115			}			--Barrow III
		MapMusicSets[117] = {20,	57,	63,	68,	115			}			--Barrow IX
		MapMusicSets[118] = {20,	57,	63,	68,	115			}			--Barrow VI
		MapMusicSets[119] = {20,	57,	63,	68,	115			}			--Barrow I
		MapMusicSets[120] = {20,	57,	63,	68,	115			}			--Barrow VIII
		MapMusicSets[121] = {20,	57,	63,	68,	115			}			--Barrow XIII
		MapMusicSets[122] = {20,	57,	63,	68,	115			}			--Barrow X
		MapMusicSets[123] = {20,	57,	63,	68,	115			}			--Barrow XII
		MapMusicSets[124] = {20,	57,	63,	68,	115			}			--Barrow V
		MapMusicSets[125] = {20,	57,	63,	68,	115			}			--Barrow XI
		MapMusicSets[126] = {20,	57,	63,	68,	115			}			--Barrow XV
					
		MapMusicSets[68 ] = {21,129							}			--Evenmorn Island
					
		MapMusicSets[77 ] = {22,72,108,117				    }			--Castle Gloaming
		MapMusicSets[100] = {22,72,117,121,134				}			--The Pit
					
		MapMusicSets[79 ] = {23								}			--The Arena
		MapMusicSets[97 ] = {23,116							}			--The Lincoln
					
		MapMusicSets[74 ] = {24								}			--Shoals
					
		MapMusicSets[99 ] = {25,99,75,132				    }			--Celeste
					
		MapMusicSets[69 ] = {26,71,76,126					}			--Mount Nighon
					
		MapMusicSets[70 ] = {27,101,120						}			--The Barrow Downs
		MapMusicSets[71 ] = {27,101,120,126					}			--The Land of the Giants
					
		MapMusicSets[78 ] = {28,134							}			--The Temple of Baa
		MapMusicSets[80 ] = {28,134							}			--The Temple of the Moon
		MapMusicSets[93 ] = {28,134							}			--Grand Temple of the Moon
		MapMusicSets[101] = {122,123						}			--Colony Zod
		MapMusicSets[102] = {28,60							}			--The Dragon's Lair
		MapMusicSets[133] = {28,132							}			--Temple of the Light
		MapMusicSets[134] = {28,134							}			--Temple of the Dark
		MapMusicSets[135] = {28,132							}			--Grand Temple of the Sun
					
		MapMusicSets[106] = {29,109							}			--Castle Navan
		MapMusicSets[107] = {29,100							}			--Castle Gryphonheart
					
		MapMusicSets[104] = {30,31,75						}			--Castle Lambent
					
		MapMusicSets[81 ] = {31,70,79					    }			--Thunderfist Mountain
		MapMusicSets[83 ] = {31,71,137					    }			--The Titans' Stronghold
		MapMusicSets[110] = {31,54,61,71				    }			--Tunnels to Eeofol
		MapMusicSets[130] = {31,71						    }			--The Dragon Caves
					
		MapMusicSets[64 ] = {32,69,80,111,112,114,128,131	}			--Erathia
					
		MapMusicSets[65 ] = {33,73,85,87,91,114,131,133		}			--The Tularean Forest
					
		MapMusicSets[88 ] = {34,	76						}			--The School of Sorcery
		MapMusicSets[92 ] = {34								}			--Lord Markham's Manor
		MapMusicSets[94 ] = {34								}			--The Mercenary Guild
		MapMusicSets[98 ] = {34,	70,	84,					}			--Stone City
		MapMusicSets[103] = {34,	111,112					}			--Castle Harmondale
		MapMusicSets[105] = {34								}			--Fort Riverstride
		MapMusicSets[128] = {34								}			--William Setag's Tower
		MapMusicSets[131] = {34								}			--The Bandit Caves
		MapMusicSets[132] = {34								}			--The Small House
		MapMusicSets[207] = {34								}			--The Strange Temple
					
		MapMusicSets[62 ] = {35,83,114					    }			--Emerald Island
		
		-- MM6 Music
		MapMusicSets[146] = {37,38,39,67,73,78,114,127	    }			--Silver Cove
		MapMusicSets[147] = {37,38,39,92,94				    }			--Bootleg Bay
		MapMusicSets[148] = {37,38,39,78,80,112,127,128,131 }			--Castle Ironfist
		MapMusicSets[149] = {37,38,39,91,94				    }			--Eel Infested Waters
		MapMusicSets[150] = {37,38,39,90,91,94,113,130		}			--Misty Islands
		MapMusicSets[151] = {37,38,39,111,114,127,128	    }			--New Sorpigal
		MapMusicSets[203] = {37,	38,	39					}			--New World Computing
		MapMusicSets[204] = {37,	38,	39,					}			--The Breach
					
		MapMusicSets[137] = {40,104,134					    }			--Sweet Water
		MapMusicSets[187] = {122,123						}			--The Hive
		
		MapMusicSets[139] = {41,58,105 					    }			--Hermit's Isle
		MapMusicSets[141] = {41,67,90,92				    }			--Blackshire
		MapMusicSets[142] = {41,58,81,105					}			--Dragonsand
		
		MapMusicSets[154] = {41,42,43,56,61,62			    }			--Shadow Guild Hideout
		MapMusicSets[155] = {41,	42,	43,					}			--Hall of the Fire Lord
		MapMusicSets[156] = {41,	42,	43,	54,	56,	61		}			--Snergle's Caverns
		MapMusicSets[157] = {41,42,43,56,61,62				}			--Dragoons' Caverns
		MapMusicSets[158] = {41,	42,	43,134,137			}			--Silver Helm Outpost
		MapMusicSets[159] = {41,	42,	43					}			--Shadow Guild
		MapMusicSets[160] = {41,	42,	43,	54,	56,	61		}			--Snergle's Iron Mines
		MapMusicSets[161] = {41,42,43,56,61,62				}			--Dragoons' Keep
		MapMusicSets[162] = {41,	42,	43,	63,	115			}			--Corlagon's Estate
		MapMusicSets[163] = {41,	42,	43					}			--Silver Helm Stronghold
		MapMusicSets[164] = {41,	42,	43					}			--The Monolith
		MapMusicSets[165] = {41,42,43,57,115,116			}			--Tomb of Ethric the Mad
		MapMusicSets[166] = {41,42,43,62,89					}			--Icewind Keep
		MapMusicSets[167] = {41,42,43,62,89 				}			--Warlord's Fortress
		MapMusicSets[168] = {41,	42,	43,	54				}			--Lair of the Wolf
		MapMusicSets[169] = {41,42,	43,86,88			    }			--Gharik's Forge
		MapMusicSets[170] = {41,42,	43,86,88				}			--Agar's Laboratory
		MapMusicSets[171] = {41,42,	43,56,62				}			--Caves of the Dragon Riders
		
		MapMusicSets[189] = {42,60							}			--Dragon's Lair
		MapMusicSets[192] = {42								}			--Warehouse
		MapMusicSets[202] = {42								}			--Devil Outpost
		MapMusicSets[206] = {42								}			--Basement of the Breach
					
		MapMusicSets[152] = {43,62							}			--Goblinwatch
					
		MapMusicSets[153] = {44								}			--Abandoned Temple
		MapMusicSets[183] = {44,	56,	62					}			--Free Haven Sewer
					
		MapMusicSets[188] = {45								}			--The Arena
					
		MapMusicSets[184] = {46,116							}			--Tomb of VARN
		MapMusicSets[185] = {46,116							}			--Oracle of Enroth
		MapMusicSets[186] = {46,116							}			--Control Center
					
		MapMusicSets[140] = {47,	82,	91					}			--Kriegspire
		MapMusicSets[143] = {47,	82,	91,	95,	75			}			--Frozen Highlands
		
		MapMusicSets[145] = {48,	65,	83					}			--Mire of the Damned
		
		MapMusicSets[173] = {49,	50						}			--Temple of the Fist
		MapMusicSets[174] = {49,	50						}			--Temple of Tsantsa
		MapMusicSets[175] = {49,	50						}			--Temple of the Sun
		MapMusicSets[176] = {49,	50						}			--Temple of the Moon
		MapMusicSets[179] = {49,	50						}			--Temple of the Snake
		MapMusicSets[172] = {49,	50						}			--Temple of Baa
		MapMusicSets[177] = {49,	50						}			--Supreme Temple of Baa
		MapMusicSets[178] = {49,	50						}			--Superior Temple of Baa
		
		MapMusicSets[180] = {50								}			--Castle Alamos
		MapMusicSets[181] = {50								}			--Castle Darkmoor
		MapMusicSets[182] = {50								}			--Castle Kriegspire
					
		MapMusicSets[138] = {51,	58						}			--Paradise Valley
		MapMusicSets[144] = {51,77,92,93,127,130,131	    }			--Free Haven

		-- These are each map's "any time" tracks. Track choice, day / night and seasonal
		-- tracks (incl. the winter tracks 82 / 22) are handled by MMMWE_Music.lua.
		Game.MapMusicSets = MapMusicSets
	end
	
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
	

