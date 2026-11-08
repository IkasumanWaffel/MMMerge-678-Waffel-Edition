--[[
	MMMWE_MonkBranches.lua — passives of the two second promotions of the monks

	The Master Monk is the unbreakable fist (D&D Way of the Open Hand, Pathfinder diamond
	body), the Ninja the unseen one (D&D Way of Shadow, Pathfinder ninja). The Ninja is kept
	a bare-handed Ki fighter: no thief skills or weapons (those belong to Spy and Assassin).
	Branches by MF.ClassBranch (MMMWE_Resources.lua): preset classes and custom classes
	whose kit is on that branch.

	Master Monk
	  Diamond Body: immune to poison and disease from monsters' attacks (DoBadThingToPlayer),
	  +1 to Fire, Air, Water, Earth, Mind, Body and Spirit resistance per DiamondResPer
	  points of Meditation (base resistance, GetRaceClassResistance of Resistances.lua).
	  Ki strikes (01.11.26, after the D&D Way of the Four Elements): each bare-handed melee
	  blow also deals KiStrikePerSkill % per point of Unarmed (at most KiStrikeCap %) of its
	  physical damage as the element of Fire, Air, Water and Earth the target resists least,
	  through that resistance (MF.QueueElementalHit, MMMWE_Cestus.lua), so monsters immune to
	  physical damage still take it.
	  Iron Body (Ki) and Pressure points (Grand Master Unarmed) are elsewhere.

	Ninja
	  Evasion: with Dodging, area spells can be dodged at half the dodge chance
	  (MF.NinjaEvasion, used by events.CalcDamageToPlayer of MMMWE_Main.lua).
	  Opportunist: when another party member hits a monster in melee, a bare-handed ninja
	  may follow up at once: chance = Unarmed skill x OpportunistPerSkill %, at most
	  OpportunistCap %, at OpportunistDamage of a blow's damage (MF.QueueCounterAttack).
	  Vanish (the first blow out of it stuns, MMMWE_WeaponEffects.lua) and Shadow Clone (Ki)
	  are in MMMWE_Resources.lua.

	Missed hits: a hit taken by the Shadow Clone or evaded with Grand Master Unarmed also
	cancels the special effect of that attack (MF.MissedPlayer, set by MMMWE_Main.lua).
--]]

local MF = Merge.Functions

local B = {
	DiamondResPer      = 2,      -- Meditation points per +1 resistance
	OpportunistPerSkill = 0.5,   -- %
	OpportunistCap     = 25,
	OpportunistDamage  = 0.6,
	KiStrikePerSkill   = 1,      -- % of the blow's physical damage per point of Unarmed
	KiStrikeCap        = 25,
}
MF.MonkBranchSettings = B

local function branch(pl)
	return MF.ClassBranch and MF.ClassBranch(pl)
end

---------------------------------------------------------------------------
-- Master Monk: Diamond Body
---------------------------------------------------------------------------

local MB = const.MonsterBonus
local DIAMOND_IMMUNE = {[MB.Poison1] = true, [MB.Poison2] = true, [MB.Poison3] = true,
	[MB.Disease1] = true, [MB.Disease2] = true, [MB.Disease3] = true}
-- Resistances.lua indices: Fire, Air, Water, Earth, Spirit, Mind, Body
local DIAMOND_RES = {[0] = true, [1] = true, [2] = true, [3] = true, [6] = true, [7] = true, [8] = true}

function MF.DiamondBodyRes(pl)
	if branch(pl) ~= "MasterMonk" then return 0 end
	local S = SplitSkill(pl:GetSkill(const.Skills.Meditation))
	return math.floor(S / B.DiamondResPer)
end

function events.GetRaceClassResistance(t)
	if t.Player and DIAMOND_RES[t.Resistance] then
		t.Result = t.Result + MF.DiamondBodyRes(t.Player)
	end
end

function events.DoBadThingToPlayer(t)
	if not t.Allow or not t.Player then return end
	-- the attack missed completely (Shadow Clone, Grand Master Unarmed evasion)
	if MF.MissedPlayer and MF.MissedPlayer == t.Player["?ptr"] then
		t.Allow = false
		return
	end
	if DIAMOND_IMMUNE[t.Thing] and branch(t.Player) == "MasterMonk" then
		t.Allow = false
	end
end

function events.Tick()
	MF.MissedPlayer = nil
end

-- Ki strikes
function MF.KiStrikeShare(pl)
	if branch(pl) ~= "MasterMonk" or not (MF.IsBareHanded and MF.IsBareHanded(pl)) then return 0 end
	local S = SplitSkill(pl:GetSkill(const.Skills.Unarmed))
	return math.min(B.KiStrikeCap, S * B.KiStrikePerSkill) / 100
end

function events.CalcDamageToMonster(t)
	if not t.ByPlayer or t.IsSecondary or not t.Melee then return end
	if t.DamageKind ~= const.Damage.Phys or not t.PlayerIndex or not t.MonsterIndex then return end
	if MF.BlasterSpecs and MF.BlasterSpecs.Forced then return end
	local pl, mon = t.Player, t.Monster
	if not pl or not mon or not MF.QueueElementalHit or not MF.LeastResistedElement then return end
	local share = MF.KiStrikeShare(pl)
	local dmg = math.floor((t.Damage or 0) * share + 0.5)
	if dmg > 0 then
		if MF.DealElementalHit then
			MF.DealElementalHit(t, dmg, MF.LeastResistedElement(mon))   -- within the blow (08.11.26)
		else
			MF.QueueElementalHit(t.PlayerIndex, t.MonsterIndex, dmg, MF.LeastResistedElement(mon))
		end
	end
end

---------------------------------------------------------------------------
-- Ninja: Evasion
---------------------------------------------------------------------------

function MF.NinjaEvasion(pl)
	if branch(pl) ~= "Ninja" then return false end
	local S, M = SplitSkill(pl:GetSkill(const.Skills.Dodging))
	return S > 0 and M > 0
end

---------------------------------------------------------------------------
-- Ninja: Opportunist
---------------------------------------------------------------------------

function MF.OpportunistChance(pl)
	if branch(pl) ~= "Ninja" or not (MF.IsBareHanded and MF.IsBareHanded(pl)) then return 0 end
	local S = SplitSkill(pl:GetSkill(const.Skills.Unarmed))
	return math.min(B.OpportunistCap, S * B.OpportunistPerSkill)
end

function events.CalcDamageToMonster(t)
	if not t.ByPlayer or t.IsSecondary or not t.Melee then return end
	if t.DamageKind ~= const.Damage.Phys or not t.PlayerIndex or not t.MonsterIndex then return end
	if not MF.QueueCounterAttack or (MF.CounterAttackActive and MF.CounterAttackActive()) then return end
	if MF.BlasterSpecs and MF.BlasterSpecs.Forced then return end   -- bash, chain, shield hits
	local mon = t.Monster
	if not mon or mon.HP <= 0 then return end
	-- one follow-up per hit, by the first ninja in the party order who gets it
	for s = 0, Party.count - 1 do
		local pi = Party.PlayersIndexes[s]
		local pl = Party[s]
		if pi ~= t.PlayerIndex and pl:IsConscious() then
			local c = MF.OpportunistChance(pl)
			if c > 0 and math.random() * 100 < c then
				MF.QueueCounterAttack(pi, t.MonsterIndex,
					string.format("%s seizes the opening!", pl.Name), B.OpportunistDamage)
				return
			end
		end
	end
end
