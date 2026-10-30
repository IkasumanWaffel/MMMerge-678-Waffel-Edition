--[[
	MMMWE_EnergyShield.lua — the Energy Shield (belt item 968), after Borderlands shields
	(30.10.26)

	The shield has its own charge, apart from the spell points:
	  Capacity   BaseCapacity + CapacityPerLevel x the wearer's level, +CapacityPerTier
	             for every level of the Capacity spec
	  Absorbs    the damage of every hit (after dodge, parry, block, armor and resistances),
	             until it is empty; the rest goes through. Air (shock) damage drains it
	             ShockCost times as fast.
	  Delay      after any hit the shield doesn't recharge for Delay (game time), shorter
	             with the Recharge delay spec; a broken (emptied) shield waits BrokenDelay
	             times as long
	  Recharge   then RechargeShare of the capacity per game minute, more with the
	             Recharge rate spec
	  Nova       when the shield breaks it bursts: energy damage of NovaShare x the capacity
	             per level of the Nova spec to every hostile monster within NovaRadius

	Tier 4 specials: Nova - Spike (monsters that hit the wearer in melee while the shield
	holds take SpikeShare of the damage absorbed), Recharge rate - Booster (every monster
	the party kills restores BoosterShare of the capacity), Recharge delay - Quick restart
	(a broken shield waits the normal delay), Capacity - Hardened (hits drain HardenedCost
	of their damage).

	Upgrades: MMMWE_Blasters.lua (the same gems, ore and work; the limit by the Blaster
	mastery of the character who installs them: 2 / 4 / 6 / 8). The charge is kept in the
	item's MaxCharges (0..200, 0.5% steps), so it goes with the shield.
	Anyone can wear the shield. No Meditation, spell points or resistances are involved
	any more.

	Shield Projector (Ancient Researcher, MMMWE_Resources.lua, MF.ShieldProjector): every
	shield in the party gets ProjectorShare of its capacity back and recharges at once;
	members without a shield get a barrier of BarrierBase + BarrierPerLevel x the caster's
	level for BarrierTime, which absorbs hits the same way (before a shield).

	Console: Merge.Functions.ShieldInfo(player)
--]]

local MF = Merge.Functions
local floor, min, max = math.floor, math.min, math.max

local S = {
	BaseCapacity     = 20,
	CapacityPerLevel = 3,
	CapacityPerTier  = 0.40,
	Delay            = 3 * const.Minute,
	DelayPerTier     = 0.15,      -- share of the delay taken off per level of the spec
	DelayMin         = const.Minute / 2,
	BrokenDelay      = 2,
	RechargeShare    = 0.20,      -- of the capacity per game minute
	RatePerTier      = 0.30,      -- x recharge per level of the spec
	ShockCost        = 2,
	NovaShare        = 0.25,      -- of the capacity per level of the Nova spec
	NovaRadius       = 600,
	SpikeShare       = 0.25,
	BoosterShare     = 0.15,
	HardenedCost     = 0.80,
	Full             = 200,       -- MaxCharges of a full shield
	ProjectorShare   = 0.50,
	BarrierBase      = 20,
	BarrierPerLevel  = 2,
	BarrierTime      = 3 * const.Minute,
}
MF.EnergyShieldSettings = S

local NOVA, RATE, DELAY, CAP = 1, 2, 3, 4

local function shieldState(item)
	return MF.BlasterState and MF.BlasterState(item)
end

local function capacity(pl, st)
	local base = S.BaseCapacity + S.CapacityPerLevel * max(1, pl.LevelBase)
	return base * (1 + S.CapacityPerTier * st.Levels[CAP])
end

local function delayOf(st, broken)
	local d = max(S.DelayMin, S.Delay * max(0, 1 - S.DelayPerTier * st.Levels[DELAY]))
	if broken and st.Tiers[DELAY] < 4 then d = d * S.BrokenDelay end
	return d
end

local function ratePerMinute(pl, st)
	return S.RechargeShare * (1 + S.RatePerTier * st.Levels[RATE]) * capacity(pl, st)
end

-- per character (PlayersArray index): last hit, broken flag, exact charge
local LastHit, Broken, Exact, LastTick = {}, {}, {}, {}
local Barrier = {}   -- [PlayersArray index] = {Value, Until} (Shield Projector)

-- the shield's charge in points (exact), and a setter
local function charge(pl, pi, it, st)
	local cap = capacity(pl, st)
	if it.MaxCharges > S.Full then it.MaxCharges = S.Full end   -- an old wear byte (ItemDurability.lua)
	local e = Exact[pi]
	if e and e.Ptr == it["?ptr"] and e.Raw == it.MaxCharges then return e.Value, cap end
	local v = cap * it.MaxCharges / S.Full
	Exact[pi] = {Ptr = it["?ptr"], Raw = it.MaxCharges, Value = v}
	return v, cap
end
local function setCharge(pi, it, v, cap)
	v = max(0, min(cap, v))
	local raw = cap > 0 and floor(v / cap * S.Full + 0.5) or 0
	if v > 0 and raw == 0 then raw = 1 end
	it.MaxCharges = raw
	Exact[pi] = {Ptr = it["?ptr"], Raw = raw, Value = v}
end

local function monsterDistance(m, x, y, z)
	local dx, dy, dz = m.X - x, m.Y - y, m.Z - z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function nova(pl, pi, st, cap)
	local lv = st.Levels[NOVA]
	if lv <= 0 or not MF.QueueForcedHit then return end
	local dmg = S.NovaShare * lv * cap
	local n = 0
	for i = 0, Map.Monsters.count - 1 do
		local m = Map.Monsters[i]
		if m.HP > 0 and m.Hostile and m.AIState ~= const.AIState.Removed
				and monsterDistance(m, Party.X, Party.Y, Party.Z) <= S.NovaRadius + (m.BodyRadius or 0) then
			MF.QueueForcedHit(pi, i, dmg)
			n = n + 1
		end
	end
	if n > 0 then Game.ShowStatusText(string.format("%s's shield bursts in a nova!", pl.Name), 3) end
end

---------------------------------------------------------------------------
-- absorbing hits
---------------------------------------------------------------------------

local function onHit(t)
	local pl = t.Player
	if not pl or (t.Result or 0) <= 0 or not MF.ShieldOf then return end
	-- Shield Projector barrier first
	local bpi = pl:GetIndex()
	local br = Barrier[bpi]
	if br then
		if br.Until <= Game.Time then
			Barrier[bpi] = nil
		else
			local a = min(t.Result, floor(br.Value))
			t.Result = t.Result - a
			br.Value = br.Value - a
			if br.Value < 1 then
				Barrier[bpi] = nil
				Game.ShowStatusText(string.format("%s's barrier collapses (%d absorbed)", pl.Name, a), 3)
			else
				Game.ShowStatusText(string.format("%s's barrier absorbs %d", pl.Name, a), 3)
			end
			if t.Result <= 0 then return end
		end
	end
	local it = MF.ShieldOf(pl)
	if not it then return end
	local pi = pl:GetIndex()
	LastHit[pi] = Game.Time
	local st = shieldState(it)
	if not st then return end
	local pool, cap = charge(pl, pi, it, st)
	if pool <= 0 then return end
	local mult = t.DamageKind == const.Damage.Air and S.ShockCost or 1
	if st.Tiers[CAP] >= 4 then mult = mult * S.HardenedCost end
	local absorbed
	if pool >= t.Result * mult then
		absorbed = t.Result
		pool = pool - t.Result * mult
	else
		absorbed = floor(pool / mult)
		pool = 0
	end
	t.Result = t.Result - absorbed
	setCharge(pi, it, pool, cap)
	if pool <= 0 then
		Broken[pi] = true
		Game.ShowStatusText(string.format("%s's shield breaks! (%d absorbed)", pl.Name, absorbed), 3)
		nova(pl, pi, st, cap)
	else
		Game.ShowStatusText(string.format("%s's shield absorbs %d (%d%%)", pl.Name, absorbed,
			floor(pool / cap * 100)), 3)
	end
	-- Spike: the melee attacker takes a share of what the shield took
	if st.Tiers[NOVA] >= 4 and absorbed > 0 and MF.QueueForcedHit and WhoHitPlayer then
		local who = WhoHitPlayer()
		if type(who) == "table" and who.Monster and not who.Object and who.MonsterIndex then
			MF.QueueForcedHit(pi, who.MonsterIndex, S.SpikeShare * absorbed)
		end
	end
end

-- registered on the first map load, from GameInitialized2: after the damage handlers of
-- MMMWE_Main.lua, MMMWE_ArmorEffects.lua and MMMWE_Resources.lua (so it takes the final
-- damage) and before MMMWE_Drains.lua (AfterLoadMap: a hit the shield took doesn't drain)
function events.GameInitialized2()
	local hooked = false
	function events.LoadMap()
		if hooked then return end
		hooked = true
		events.CalcDamageToPlayer = onHit
	end
end

---------------------------------------------------------------------------
-- recharge, Booster
---------------------------------------------------------------------------

function events.Tick()
	local now = Game.Time
	if not MF.ShieldOf then return end
	for slot = 0, Party.count - 1 do
		local pl = Party[slot]
		local pi = Party.PlayersIndexes[slot]
		local it = MF.ShieldOf(pl)
		local last = LastTick[pi]
		LastTick[pi] = now
		if it then
			local st = shieldState(it)
			if st and last and now > last then
				local pool, cap = charge(pl, pi, it, st)
				if pool < cap then
					local since = now - (LastHit[pi] or 0)
					if since >= delayOf(st, Broken[pi]) then
						setCharge(pi, it, pool + ratePerMinute(pl, st) * (now - last) / const.Minute, cap)
					end
				else
					Broken[pi] = nil
				end
			end
		end
	end
end

function events.LeaveMap()
	LastHit, Broken, Barrier = {}, {}, {}
end

-- Shield Projector (caster: the technician)
function MF.ShieldProjector(caster)
	local L = max(1, caster.LevelBase or 1)
	local shields, barriers = 0, 0
	for slot = 0, Party.count - 1 do
		local pl = Party[slot]
		local pi = Party.PlayersIndexes[slot]
		local it = MF.ShieldOf and MF.ShieldOf(pl)
		local st = it and shieldState(it)
		if st then
			local pool, cap = charge(pl, pi, it, st)
			setCharge(pi, it, pool + S.ProjectorShare * cap, cap)
			LastHit[pi], Broken[pi] = nil, nil
			shields = shields + 1
		elseif pl:IsConscious() then
			Barrier[pi] = {Value = S.BarrierBase + S.BarrierPerLevel * L, Until = Game.Time + S.BarrierTime}
			barriers = barriers + 1
		end
	end
	Game.ShowStatusText(string.format("%s projects energy: %d shield(s) recharged, %d barrier(s)", caster.Name, shields, barriers), 3)
end

function events.MonsterKilled()
	if not MF.ShieldOf then return end
	for slot = 0, Party.count - 1 do
		local pl = Party[slot]
		local it = MF.ShieldOf(pl)
		local st = it and shieldState(it)
		if st and st.Tiers[RATE] >= 4 then
			local pi = Party.PlayersIndexes[slot]
			local pool, cap = charge(pl, pi, it, st)
			setCharge(pi, it, pool + S.BoosterShare * cap, cap)
		end
	end
end

---------------------------------------------------------------------------
-- item card, overlay, console
---------------------------------------------------------------------------

-- extra lines of the shield's card (MMMWE_Blasters.lua): for the character shown
function MF.ShieldCardInfo(st)
	local pl = Party:GetCurrentPlayer()
	if not pl then return "" end
	local cap = capacity(pl, st)
	return string.format("\nCapacity %d  Delay %.1f min  Recharge %d/min",
		floor(cap + 0.5), delayOf(st, false) / const.Minute, floor(ratePerMinute(pl, st) + 0.5))
end

-- charge in % of the shield a character wears, or nil (MMMWE_HPSPDisplay.lua)
function MF.ShieldCharge(pl)
	local it = MF.ShieldOf and MF.ShieldOf(pl)
	if not it then return end
	local st = shieldState(it)
	return st and floor(st.Cell / 2)
end

function MF.ShieldInfo(pl)
	pl = pl or Party:GetCurrentPlayer()
	local it = MF.ShieldOf and MF.ShieldOf(pl)
	if not it then return "no energy shield worn" end
	local st = shieldState(it)
	local pi = pl:GetIndex()
	local pool, cap = charge(pl, pi, it, st)
	return string.format("%s: charge %.1f / %.1f, Nova %d Rate %d Delay %d Capacity %d, delay %.2f min%s, recharge %.1f/min",
		pl.Name, pool, cap, st.Tiers[NOVA], st.Tiers[RATE], st.Tiers[DELAY], st.Tiers[CAP],
		delayOf(st, Broken[pi]) / const.Minute, Broken[pi] and " (broken)" or "", ratePerMinute(pl, st))
end
