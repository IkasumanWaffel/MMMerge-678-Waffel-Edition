--[[
	MMMWE_UnarmedGM.lua — Grand Master Unarmed

	The game's own Grand Master Unarmed evasion only works against one object, the plain
	monster arrow (545), in the missile branch of damage_player_from_monster (0x4380A2).
	It is turned off here and replaced by the rules below. Everything needs Grand Master
	Unarmed and bare hands (MF.IsBareHanded: no weapon in either hand, a shield is fine).

	Evasion
	  Chance = skill x EvadePerSkill %, at most EvadeCap %, halved while cursed, to take no
	  damage at all from a monster's melee hit or a physical missile (arrows, bolts, rocks).
	  Spells and elemental projectiles are left to Dodging. Rolled before Dodging, in
	  events.CalcDamageToPlayer of MMMWE_Main.lua (MF.UnarmedEvade).

	Flurry of blows
	  A bare-handed melee hit has a chance = skill x FlurryPerSkill %, at most FlurryCap %,
	  to be followed at once by another blow at FlurryDamage of its damage. It is carried out
	  like the Dodging riposte (MF.QueueCounterAttack), so it can stun and crit as usual,
	  but can't start another flurry.

	Pressure points (the Master Monk branch: Master Monk, and custom classes on that branch)
	  Bare-handed hits ignore skill x PressurePerSkill % (at most PressureCap %) of the
	  monster's physical damage reduction (its kind's value, MMMWE_DamageKinds.lua).
	  Immune monsters stay immune.
--]]

local MF = Merge.Functions

local U = {
	EvadePerSkill   = 1,      -- %
	EvadeCap        = 50,
	FlurryPerSkill  = 0.75,   -- %
	FlurryCap       = 40,
	FlurryDamage    = 0.6,    -- share of the blow's normal damage
	PressurePerSkill = 1,     -- % of the reduction ignored
	PressureCap     = 50,
	PressureBranch  = "MasterMonk",
}
MF.UnarmedGMSettings = U

local GM = 4

local function round(x) return math.floor(x + 0.5) end

-- the game's arrow-only check: "jl" over it (mastery below GM) becomes "jmp"
mem.asmpatch(0x4380B3, "jmp absolute 0x437FF6")

local function gmUnarmed(pl)
	if not MF.IsBareHanded or not MF.IsBareHanded(pl) then return end
	local S, M = SplitSkill(pl:GetSkill(const.Skills.Unarmed))
	if M >= GM and S > 0 then return S end
end

local function chance(S, per, cap)
	return math.min(cap, S * per)
end

function MF.UnarmedEvadeChance(pl)
	local S = gmUnarmed(pl)
	return S and chance(S, U.EvadePerSkill, U.EvadeCap) or 0
end

function MF.UnarmedFlurryChance(pl)
	local S = gmUnarmed(pl)
	return S and chance(S, U.FlurryPerSkill, U.FlurryCap) or 0
end

function MF.UnarmedPressureShare(pl)
	local S = gmUnarmed(pl)
	if not S or not MF.ClassBranch or MF.ClassBranch(pl) ~= U.PressureBranch then return 0 end
	return chance(S, U.PressurePerSkill, U.PressureCap) / 100
end

---------------------------------------------------------------------------
-- Evasion (called by events.CalcDamageToPlayer, MMMWE_Main.lua)
---------------------------------------------------------------------------

-- hitBy: WhoHitPlayer() of the hit (nil when unknown)
function MF.UnarmedEvade(pl, t, hitBy, curseMult)
	if type(hitBy) ~= "table" or (hitBy.Spell and hitBy.Spell ~= 0) then return false end
	local melee = hitBy.Monster and not hitBy.Object
	local missile = hitBy.Object and t.DamageKind == const.Damage.Phys
	if not (melee or missile) then return false end
	local cond = pl:GetMainCondition()
	if cond == const.Condition.Asleep
			or (cond >= const.Condition.Paralyzed and cond <= const.Condition.Eradicated) then
		return false
	end
	local c = MF.UnarmedEvadeChance(pl) * (curseMult or 1)
	return c > 0 and math.random() * 100 < c
end

---------------------------------------------------------------------------
-- Pressure points and Flurry of blows
---------------------------------------------------------------------------
-- Registered at load: after MMMWE_DamageKinds.lua (kind factor already in t.Result), before
-- the Heroism bonus and the counterattack damage share (GameInitialized2, MMMWE_Main.lua)

function events.CalcDamageToMonster(t)
	if not t.ByPlayer or t.IsSecondary or not t.Melee then return end
	if t.DamageKind ~= const.Damage.Phys then return end
	local pl, mon = t.Player, t.Monster
	if not pl or not mon or not gmUnarmed(pl) then return end

	-- Pressure points
	local share = MF.UnarmedPressureShare(pl)
	if share > 0 and mon.PhysResistance < 65000 and MF.PhysReductionApplied then
		local r = MF.PhysReductionApplied(mon, t.PhysDamageKind)
		if r > 0 then
			local old, new = 1 - r / 100, 1 - r * (1 - share) / 100
			if old > 0 then
				t.Result = round(t.Result * new / old)
			else
				t.Result = round((t.Damage or 0) * new)
			end
		end
	end

	-- Flurry of blows (not from a flurry blow or another counterattack)
	if MF.CounterAttackActive and MF.CounterAttackActive() then return end
	if MF.BlasterSpecs and MF.BlasterSpecs.Forced then return end
	if not t.PlayerIndex or not t.MonsterIndex or not MF.QueueCounterAttack then return end
	local c = MF.UnarmedFlurryChance(pl)
	if c > 0 and math.random() * 100 < c then
		MF.QueueCounterAttack(t.PlayerIndex, t.MonsterIndex,
			string.format("%s strikes again!", pl.Name), U.FlurryDamage)
	end
end
