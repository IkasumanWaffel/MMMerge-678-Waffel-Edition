--[[
	MMMWE_Shields.lua — shield classes and the block roll

	Shields come in three classes. The class of a shield is taken from CLASS_OVERRIDES (set
	from the item descriptions in Items.txt: light, narrow cavalry and infantry shields are
	medium), otherwise from its not-identified name ("... Large Shield" / "... Small Shield"),
	otherwise from its base armor (up to 4 small, up to 7 medium, more large).

	              block chance (S x M)    cap   dodge / recovery penalty (N, E, M, GM)
	  small         15 + 0.5  per point   55%    -                      (+ the usual 10 at Novice)
	  medium        20 + 0.55 per point   62%   +8, +8, +5, 0
	  large         25 + 0.6  per point   70%   +15, +15, +10, 0

	Block power (% of the hit stopped) = 30 + shield armor + "of Defense" / Shielding bonus,
	plus a quarter of the Shield skill at Master and half of it at Grand Master (max 95%).

	What a block can stop:
	  - physical hits (melee and missiles). Against arrows and other physical missiles the
	    block chance is +10 (large shields +20)
	  - Master: elemental hits aimed at the character (melee, monster missiles, bolt spells);
	    large shields also stop area spells and dragon breath with half the block power
	  - Grand Master: energy hits the same way, with a third of the block power (the Reflector
	    Shield: the full power)
	Grand Master: 15% of blocks are perfect and stop the whole hit.
	Small shields, Master and up: 20% of melee blocks are followed by a counterattack (half
	damage, like the Grand Master dodge riposte).
	Large shields, Grand Master: 15% of melee blocks bash the attacker, who is stunned
	(paralyzed for a moment) unless it resists with its Earth resistance.

	Console: Merge.Functions.ShieldInfo(player)
--]]

local MF = Merge.Functions
local SK = const.Skills

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local CLASSES = {
	small  = {Name = "Small",  Base = 15, PerSM = 0.5,  Cap = 55, MissileBonus = 10, Penalty = {0, 0, 0, 0}},
	medium = {Name = "Medium", Base = 20, PerSM = 0.55, Cap = 62, MissileBonus = 10, Penalty = {8, 8, 5, 0}},
	large  = {Name = "Large",  Base = 25, PerSM = 0.6,  Cap = 70, MissileBonus = 20, Penalty = {15, 15, 10, 0}},
}

local S = {
	PowerBase        = 30,
	PowerPerSkill    = {0, 0, 0.25, 0.5},   -- by mastery
	PowerMax         = 95,
	MagicShare       = 2 / 3,               -- block power against elemental hits (Master)
	EnergyShare      = 1 / 3,               -- against energy hits (Grand Master)
	AreaShare        = 0.5,                 -- large shields against area spells and breath
	PerfectBlockGM   = 15,                  -- % of blocks at Grand Master
	CounterChance    = 20,                  -- small shields, Master and up, % of melee blocks
	BashChance       = 15,                  -- large shields, Grand Master, % of melee blocks
	BashStun         = const.Minute,        -- paralysis time of a bashed monster
	ReflectorShield  = 967,
	EnchantBonus     = {[42] = 1, [43] = 10, [48] = 5},  -- Bonus2 specials that add block power
	DefenseBonus     = 10,                  -- standard bonus 10 (Armor Class) adds its strength
}
MF.ShieldSettings, MF.ShieldClasses = S, CLASSES

-- from the descriptions in Items.txt
local CLASS_OVERRIDES = {
	[101]  = "medium",  -- Regnan Tournament Shield: "light, but tough"
	[883]  = "medium",  -- Horseman's Shield: narrow, made for horseback
	[884]  = "medium",  -- Sterling Shield: "lightweight metal"
	[1684] = "medium",  -- Celestial Shield: "lightweight metal"
	[106]  = "medium",  -- Calvary Shield: knights' steel shield that turns pikes
	[107]  = "medium",  -- Death Head Shield: elite infantry shield "of great strength"
	[1321] = "medium",  -- Glory Shield (base armor 6)
	[1460] = "medium",  -- Contestant's Shield (base armor 6)
	[1474] = "large",   -- Lord Kilburn's Shield ("Signed Large Shield")
	[967]  = "large",   -- Reflector Shield ("Ancient Energy Shield", base armor 8)
}

---------------------------------------------------------------------------
-- shield items
---------------------------------------------------------------------------

-- base armor of an armor or shield entry of Items.txt. A plain number in the Mod1 column
-- may end up as dice count or dice sides, so take whichever holds it.
function MF.ItemArmorBase(txt)
	local c, s = txt.Mod1DiceCount, txt.Mod1DiceSides
	if c <= 1 then return s > 1 and s or c end
	if s <= 1 then return c end
	return c * s
end

local classCache = {}
function MF.ShieldClass(num)
	local c = classCache[num]
	if c then return c end
	local txt = Game.ItemsTxt[num]
	c = CLASS_OVERRIDES[num]
	if not c then
		local name = txt.NotIdentifiedName or ""
		if name:find("Large") then c = "large"
		elseif name:find("Small") then c = "small"
		else
			local base = MF.ItemArmorBase(txt)
			c = base <= 4 and "small" or base <= 7 and "medium" or "large"
		end
	end
	classCache[num] = c
	return c
end

function MF.ShieldClassInfo(num) return CLASSES[MF.ShieldClass(num)] end

-- usable shield in the extra hand: item, its number, class info
local function shieldOf(pl)
	local slot = pl.ItemExtraHand
	if slot <= 0 then return end
	local it = pl.Items[slot]
	if it.Broken then return end
	local txt = Game.ItemsTxt[it.Number]
	if txt.Skill ~= SK.Shield or txt.EquipStat ~= 4 then return end
	return it, it.Number, CLASSES[MF.ShieldClass(it.Number)]
end
MF.EquippedShield = shieldOf

-- extra dodge / recovery penalty of a shield item at a Shield mastery
function MF.ShieldExtraPenalty(num, M)
	local info = CLASSES[MF.ShieldClass(num)]
	return info.Penalty[math.max(M or 1, 1)] or 0
end

-- block power of a shield item (item: structs.Item or nil for the bare item kind)
function MF.ShieldBlockPower(num, item, shS, shM)
	local txt = Game.ItemsTxt[num]
	local p = S.PowerBase + MF.ItemArmorBase(txt) + txt.Mod2
	if item then
		if item.Bonus == S.DefenseBonus then
			p = p + item.BonusStrength
		elseif S.EnchantBonus[item.Bonus2] then
			p = p + S.EnchantBonus[item.Bonus2]
		end
	end
	if shS and shM then
		p = p + (S.PowerPerSkill[shM] or 0) * shS
	end
	return math.min(p, S.PowerMax)
end

-- block chance (%) before curse; missile = physical missile
function MF.ShieldBlockChance(num, shS, shM, missile)
	local info = CLASSES[MF.ShieldClass(num)]
	local c = math.min(info.Cap, info.Base + info.PerSM * shS * shM)
	if missile then c = c + info.MissileBonus end
	return c
end

---------------------------------------------------------------------------
-- the incoming hit
---------------------------------------------------------------------------

-- "melee", "missile" (physical projectile), "projectile" (elemental / energy projectile or
-- bolt spell), "area" (area spells, attacks without an attacker), "breath" (dragons'
-- elemental attacks) or nil (nothing a shield can stop: falling and the like)
function MF.IncomingHitShape(t)
	local who = WhoHitPlayer and WhoHitPlayer()
	local phys = t.DamageKind == const.Damage.Phys
	if type(who) ~= "table" then
		return not phys and "area" or nil, who
	end
	if who.Spell and who.Spell ~= 0 then
		local bolts = MF.DodgeSettings and MF.DodgeSettings.BoltSpells or {}
		return bolts[who.Spell] and "projectile" or "area", who
	end
	if who.Monster and not phys and (who.MonsterAction or 0) <= 1
			and Game.IsMonsterOfKind(who.Monster.Id, const.MonsterKind.Dragon) ~= 0 then
		return "breath", who
	end
	if who.Object then
		return phys and "missile" or "projectile", who
	end
	if who.Monster then return "melee", who end
	return nil, who
end

---------------------------------------------------------------------------
-- the block roll (called by MMMWE_Main.lua for every hit taken)
---------------------------------------------------------------------------

local Pending = {}   -- counterattacks and bashes, carried out on the next tick

-- returns physical, elemental, energy damage multipliers (1 = nothing blocked)
function MF.ShieldBlock(pl, t, curseMult)
	local cond = pl:GetMainCondition()
	if cond == const.Condition.Asleep or (cond >= const.Condition.Paralyzed and cond <= const.Condition.Eradicated) then
		return 1, 1, 1
	end
	local item, num, info = shieldOf(pl)
	if not item then return 1, 1, 1 end
	local shS, shM = SplitSkill(pl:GetSkill(SK.Shield))
	shM = math.max(shM, 1)

	local shape, who = MF.IncomingHitShape(t)
	if not shape then return 1, 1, 1 end
	local large = info == CLASSES.large
	local share = 1
	if shape == "area" or shape == "breath" then
		if not large then return 1, 1, 1 end
		share = S.AreaShare
	end

	local chance = MF.ShieldBlockChance(num, shS, shM, shape == "missile") * (curseMult or 1)
	if math.random() * 100 >= chance then return 1, 1, 1 end

	local power = MF.ShieldBlockPower(num, item, shS, shM) * share
	if shM >= 4 and math.random() * 100 < S.PerfectBlockGM then
		power = 100 * share
		Game.ShowStatusText(string.format("%s blocks the blow completely!", pl.Name), 2)
	end

	local physDR, magicDR, energyDR = 1, 1, 1
	physDR = math.max(0, 1 - 0.01 * power)
	if shM >= 3 then
		magicDR = math.max(0, 1 - 0.01 * power * S.MagicShare)
	end
	if shM >= 4 then
		local es = num == S.ReflectorShield and 1 or S.EnergyShare
		energyDR = math.max(0, 1 - 0.01 * power * es)
	end

	-- melee follow-ups
	if shape == "melee" and who and who.MonsterIndex and t.PlayerIndex then
		if info == CLASSES.small and shM >= 3 and math.random() * 100 < S.CounterChance then
			Pending[#Pending + 1] = {Kind = "counter", pi = t.PlayerIndex, mi = who.MonsterIndex}
		elseif large and shM >= 4 and math.random() * 100 < S.BashChance then
			Pending[#Pending + 1] = {Kind = "bash", pi = t.PlayerIndex, mi = who.MonsterIndex, S = shS, M = shM}
		end
	end
	return physDR, magicDR, energyDR
end

function events.Tick()
	if #Pending == 0 then return end
	local q = Pending
	Pending = {}
	for _, r in ipairs(q) do
		local pl, mon = Party.PlayersArray[r.pi], Map.Monsters[r.mi]
		if pl and mon and mon.HP > 0 and pl:IsConscious() then
			if r.Kind == "counter" then
				if MF.QueueCounterAttack then
					MF.QueueCounterAttack(r.pi, r.mi, string.format("%s blocks and strikes back!", pl.Name))
				end
			else
				local res = mon.Resistances[const.Damage.Earth]
				if res ~= const.MonsterImmune and math.random(5, 100) + r.S + r.M * 2.5 > res then
					local buff = mon.SpellBuffs[const.MonsterBuff.Paralyze]
					buff.ExpireTime = math.max(Game.Time + S.BashStun, buff.ExpireTime)
					Game.ShowStatusText(string.format("%s bashes the attacker with the shield!", pl.Name), 2)
				end
			end
		end
	end
end

function MF.ShieldInfo(pl)
	pl = pl or Party[math.max(Game.CurrentPlayer, 0)]
	local item, num, info = shieldOf(pl)
	if not item then return "no shield" end
	local shS, shM = SplitSkill(pl:GetSkill(SK.Shield))
	shM = math.max(shM, 1)
	return string.format("%s shield: block %.1f%% (missiles %.1f%%), power %d%%, extra dodge/recovery penalty %d",
		info.Name, MF.ShieldBlockChance(num, shS, shM), MF.ShieldBlockChance(num, shS, shM, true),
		MF.ShieldBlockPower(num, item, shS, shM), info.Penalty[shM])
end

function events.GameInitialized2()
	-- how the game stored a shield's armor value (see MF.ItemArmorBase)
	local t = Game.ItemsTxt[99]
	if MF.LogInfo and t then
		MF.LogInfo("[Shields] item 99 Mod1 = %dd%d, Mod2 = %d, base armor %d",
			t.Mod1DiceCount, t.Mod1DiceSides, t.Mod2, MF.ItemArmorBase(t))
	end
end
