--[[
	MMMWE_Conditions.lua - Immersive conditions (moved out of MMMWE_Main.lua, 18.11.26)

	Weakness      starving on the road makes characters Weak; a long Weakness leads to
	              insanity and death (a check a day).
	Poison        damage every 10 minutes (Body); weakens a step every 6 hours by itself:
	              Poison 3 -> 2 -> 1 -> cured.
	Disease       damage every 30 minutes (Body); once a day an Endurance save: success
	              eases it a step (Disease 1 is cured), failure worsens it. Disease 3 drains
	              the health away towards death (no sudden death roll).
	Insanity      Mind damage and lost spell points every 15 minutes, now and then
	              Feeblemind; it lasts until cured.
	Light         Asleep, Afraid, Drunk and Paralyzed are shrugged off by a save roll,
	conditions    made each period after they set in (the status screen shows the time
	              to the next roll).
	Unconscious   an Endurance check every 10 minutes: wake up (Weak) or bleed on.
	Dead,         drain a random base stat: 1 point every 12 hours dead, every 6 hours
	Eradicated    eradicated, counted over rest and travel too.
	Soul fatigue  (24.11.26) each death and revival of a character makes the next drain
	              come sooner: the time per point is divided by 1 + revivals, at most 8
	              (12 h dead: 6 h after the first revival, 4 h after the second ... 1.5 h).
	              A revival counts after 6 minutes dead or eradicated; a revival by Divine
	              Intervention cast at Grand Master or by Aqua Vitae takes one off instead.

	Time that passes all at once (rest, travel, a long wait) is settled when the party is
	back: poison and disease do a fifth of the damage they'd have done tick by tick and
	never kill that way, their course (steps, saves) runs as usual, and after a rest
	with food Poison 1 and Disease 1 may go away.

	Damage goes through evt.DamagePlayer, so Body and Mind resistance reduce it.
	The numbers are in C below. ModSettings: Scripts.ImmersiveConditions 0 turns it off.
--]]
local MF, MM = Merge.Functions, Merge.ModSettings
local Tx = MF.Text
if MM.Scripts and MM.Scripts.ImmersiveConditions ~= nil and not MF.GtSettingNum(MM.Scripts.ImmersiveConditions, 0) then
	return
end

local CO = const.Condition
local C = {
	ScanEvery     = const.Minute,       -- the periodic check
	JumpTicks     = 2,                  -- more ticks than this at once: settled as a jump
	JumpScale     = 0.2,                -- share of the tick-by-tick damage done in a jump
	RestCureChance = 25,                -- % after a rest with food: Poison 1 / Disease 1 cured
	-- poison
	PoisonInterval = const.Minute * 10,
	PoisonStep     = const.Hour * 6,    -- time to weaken by one step
	-- disease
	DiseaseInterval = const.Minute * 30,
	DiseaseStep     = const.Day,        -- time to the Endurance save
	DiseaseDC       = {[CO.Disease1] = 10, [CO.Disease2] = 13, [CO.Disease3] = 16},
	-- insanity
	InsanityInterval = const.Minute * 15,
	InsanityPeriod   = const.Day,
	-- light conditions: period between the save rolls, the stat that saves, the DC
	Light = {
		[CO.Asleep]    = {Period = const.Hour,     Stat = "Endurance",   DC = 8},
		[CO.Afraid]    = {Period = const.Hour,     Stat = "Personality", DC = 11},
		[CO.Drunk]     = {Period = const.Hour * 2, Stat = "Endurance",   DC = 11},
		[CO.Paralyzed] = {Period = const.Hour * 6, Stat = "Endurance",   DC = 14},
	},
	-- unconscious
	UnconsciousInterval = const.Minute * 10,
	UnconsciousDC       = 10,
	-- dead / eradicated
	StatLossDead = const.Hour * 12,     -- one point per this time
	StatLossErad = const.Hour * 6,
	SoulFatigueMax = 8,                 -- the time per point is divided by 1 + revivals, up to this
	SoulFatigueAfter = const.Minute * 6, -- a revival counts after this long dead or eradicated
	BlessedFor = const.Minute * 10,     -- Divine Intervention (GM) / Aqua Vitae: the revival seen within this
	-- the other conditions' status screen timers
	ShownFor = const.Day * 7,
}
MF.ConditionSettings = C

local POISON = {[CO.Poison1] = true, [CO.Poison2] = true, [CO.Poison3] = true}
local DISEASE = {[CO.Disease1] = true, [CO.Disease2] = true, [CO.Disease3] = true}
local POISON_DOWN = {[CO.Poison3] = CO.Poison2, [CO.Poison2] = CO.Poison1, [CO.Poison1] = false}
local DISEASE_DOWN = {[CO.Disease3] = CO.Disease2, [CO.Disease2] = CO.Disease1, [CO.Disease1] = false}
local DISEASE_UP = {[CO.Disease1] = CO.Disease2, [CO.Disease2] = CO.Disease3, [CO.Disease3] = CO.Disease3}
local DOT_ORDER = {CO.Insane, CO.Poison1, CO.Disease1, CO.Poison2, CO.Disease2, CO.Poison3, CO.Disease3}
-- conditions that stop everything (the character is out of the game)
local OUT = {[CO.Dead] = true, [CO.Stoned] = true, [CO.Eradicated] = true, [CO.Zombie or 17] = true}
-- conditions with their own status screen timers here or elsewhere (Zombie: ZombiePlayers.lua)
local OWN_TIMER = {[CO.Insane] = true, [CO.Unconscious] = true, [CO.Zombie or 17] = true}
for c in pairs(POISON) do OWN_TIMER[c] = true end
for c in pairs(DISEASE) do OWN_TIMER[c] = true end
for c in pairs(C.Light) do OWN_TIMER[c] = true end

local function rnd(n) return math.random(n) end
local function statFx(pl, stat) return Game.GetStatisticEffect(pl["Get" .. stat](pl)) end
local function debuffOf(pl, cond)
	local ok, d = pcall(function() return Game.PlayersExtra[pl:GetIndex()].Debuffs[cond] end)
	return ok and d or nil
end
local function show(pl, cond, t)
	local d = debuffOf(pl, cond)
	if d then d.ExpireTime = t end
end
local function state(pl)
	vars.MMMWE_Cond = vars.MMMWE_Cond or {}
	local k = pl:GetIndex()
	vars.MMMWE_Cond[k] = vars.MMMWE_Cond[k] or {}
	return vars.MMMWE_Cond[k]
end
local function outOfGame(pl)
	for c in pairs(OUT) do
		if pl.Conditions[c] ~= 0 then return true end
	end
	return false
end
local function setIfNone(pl, cond, t)
	if pl.Conditions[cond] == 0 then pl.Conditions[cond] = t or Game.Time end
end

---------------------------------------------------------------------------
-- poison, disease, insanity
---------------------------------------------------------------------------

local function interval(cond)
	if POISON[cond] then return C.PoisonInterval end
	if DISEASE[cond] then return C.DiseaseInterval end
	return C.InsanityInterval
end
local function period(cond)
	if POISON[cond] then return C.PoisonStep end
	if DISEASE[cond] then return C.DiseaseStep end
	return C.InsanityPeriod
end
local function tickDamage(pl, cond)
	local fhp = pl:GetFullHP()
	local d
	if POISON[cond] then
		d = math.max(cond - 4, 0.02 * fhp * cond / 2)
	elseif DISEASE[cond] then
		d = math.max(cond - 5, 0.05 * fhp * cond - 0.3 * fhp)
	else
		d = rnd(10) / 100 * fhp
	end
	return math.max(1, math.floor(d))
end
local function damageType(cond)
	return cond == CO.Insane and const.Damage.Mind or const.Damage.Body
end

-- a tick in real time: damage as a hit (resisted), and the side effects
local function tick(pl, cond, s)
	evt.DamagePlayer{Player = pl:GetSlot(), DamageType = damageType(cond), Damage = tickDamage(pl, cond)}
	local left = s.Expire - Game.Time
	if POISON[cond] then
		if left < const.Hour * 3 + const.Hour * cond / 4 then setIfNone(pl, CO.Weak) end
		if rnd(100) <= 5 * cond / 2 - 10 then setIfNone(pl, CO.Asleep) end
		if rnd(100) <= cond / 2 - 2 then setIfNone(pl, CO.Paralyzed) end
	elseif DISEASE[cond] then
		if left < const.Hour * 11 + const.Hour * cond then setIfNone(pl, CO.Weak) end
		if rnd(100) <= 5 * cond - 25 then setIfNone(pl, CO.Asleep) end
	else
		local fsp = pl:GetFullSP()
		pl.SP = math.max(0, pl.SP - math.floor(rnd(10) / 100 * fsp))
		local hours = math.floor(left / const.Hour)
		if rnd(100) <= 12 - 0.5 * hours then
			local fm = debuffOf(pl, 18)
			if fm then fm.ExpireTime = s.Expire end
		end
	end
end

-- n ticks at once (rest, travel): a share of the damage, never below 1 HP
local function jump(pl, cond, n)
	if pl.HP <= 1 then return end
	local dmg = math.floor(tickDamage(pl, cond) * n * C.JumpScale)
	-- the resistance the hit would meet
	local ok, res = pcall(function()
		return pl:GetResistance(cond == CO.Insane and const.Damage.Mind or const.Damage.Body)
	end)
	if ok and res and res > 0 then dmg = math.floor(dmg * 30 / (30 + res)) end
	pl.HP = math.max(1, pl.HP - dmg)
	if cond == CO.Insane then
		pl.SP = math.max(0, pl.SP - math.floor(n * 0.05 * pl:GetFullSP()))
	elseif n * interval(cond) >= const.Hour * 3 then
		setIfNone(pl, CO.Weak)
	end
end

local function message(fmt, ...)
	pcall(Game.ShowStatusText, string.format(fmt, ...))
end

-- the course at the end of a period: poison weakens, disease rolls; returns the condition
-- that goes on (or nil)
local function course(pl, cond, at)
	if cond == CO.Insane then return cond end   -- insanity lasts until cured
	pl.Conditions[cond] = 0
	show(pl, cond, 0)
	if POISON[cond] then
		local nxt = POISON_DOWN[cond]
		if nxt then setIfNone(pl, nxt, at) return nxt end
		message(Tx"%s has shaken off the poison", pl.Name)
		return
	end
	if DISEASE[cond] then
		local roll = rnd(20) + statFx(pl, "Endurance") + math.floor(statFx(pl, "Luck") / 2)
		local nxt
		if roll >= C.DiseaseDC[cond] then
			nxt = DISEASE_DOWN[cond]
			if not nxt then message(Tx"%s has recovered from the disease", pl.Name) return end
		else
			nxt = DISEASE_UP[cond]
			if nxt ~= cond then message(Tx"%s's disease is getting worse", pl.Name) end
		end
		setIfNone(pl, nxt, at)
		return nxt
	end
end

local function runDot(pl, rested)
	local st = state(pl)
	st.Dot = st.Dot or {}
	local now = Game.Time
	local paused = outOfGame(pl)
	for _, cond in ipairs(DOT_ORDER) do
		local s = st.Dot[cond]
		if pl.Conditions[cond] == 0 then
			if s then st.Dot[cond] = nil end
			show(pl, cond, 0)
		elseif paused then
			if s then   -- the clock stops while the character is out of the game
				local d = now - s.Last
				s.Last, s.Expire = now, s.Expire + d
			end
			show(pl, cond, 0)
		else
			if not s then
				local d = debuffOf(pl, cond)
				local exp = d and d.ExpireTime or 0
				if exp <= now then exp = now + period(cond) end
				s = {Last = now, Expire = exp}
				st.Dot[cond] = s
			end
			-- the ticks due, and the course whenever a period ends on the way
			local cur, iv = cond, interval(cond)
			while true do
				local upto = math.min(now, s.Expire)
				local n = math.floor((upto - s.Last) / iv)
				if n > 0 then
					if n <= C.JumpTicks then
						for _ = 1, n do tick(pl, cur, s) end
					else
						jump(pl, cur, n)
					end
					s.Last = s.Last + n * iv
				end
				if now < s.Expire then break end
				local at = s.Expire
				st.Dot[cur] = nil
				local nxt = course(pl, cur, at)
				if not nxt then break end
				local ns = st.Dot[nxt] or {Last = at, Expire = at + period(nxt)}
				st.Dot[nxt] = ns
				if nxt ~= cur then break end   -- the next level is handled in its own turn
				s = ns
			end
			if st.Dot[cond] then show(pl, cond, st.Dot[cond].Expire) end
		end
	end
	-- a rest with food: a chance to get rid of the light poison and disease
	if rested then
		for _, cond in ipairs{CO.Poison1, CO.Disease1} do
			if pl.Conditions[cond] ~= 0 and rnd(100) <= C.RestCureChance then
				pl.Conditions[cond] = 0
				st.Dot[cond] = nil
				show(pl, cond, 0)
				message(Tx"%s feels better after the rest", pl.Name)
			end
		end
	end
end

---------------------------------------------------------------------------
-- light conditions: a save roll each period
---------------------------------------------------------------------------

local function runLight(pl)
	local st = state(pl)
	st.Light = st.Light or {}
	local now = Game.Time
	for cond, L in pairs(C.Light) do
		local since = pl.Conditions[cond]
		if since == 0 or outOfGame(pl) then
			st.Light[cond] = nil
			if since == 0 then show(pl, cond, 0) end
		else
			local nextAt = st.Light[cond]
			if not nextAt or nextAt < since then nextAt = since + L.Period end
			while nextAt <= now and pl.Conditions[cond] ~= 0 do
				if rnd(20) + statFx(pl, L.Stat) >= L.DC then
					pl.Conditions[cond] = 0
				else
					nextAt = nextAt + L.Period
				end
			end
			if pl.Conditions[cond] == 0 then
				st.Light[cond] = nil
				show(pl, cond, 0)
			else
				st.Light[cond] = nextAt
				show(pl, cond, nextAt)
			end
		end
	end
end

---------------------------------------------------------------------------
-- the other conditions on the status screen
---------------------------------------------------------------------------

local function runShown(pl)
	for cond = 0, 17 do
		if not OWN_TIMER[cond] then
			local d = debuffOf(pl, cond)
			if d then
				if pl.Conditions[cond] ~= 0 then
					d.ExpireTime = Game.Time + C.ShownFor
				elseif d.ExpireTime > 0 then
					d.ExpireTime = 0
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- unconscious: an Endurance check every 10 minutes
---------------------------------------------------------------------------

local function runUnconscious(pl)
	local st = state(pl)
	local d = debuffOf(pl, CO.Unconscious)
	if pl.Conditions[CO.Unconscious] == 0 or outOfGame(pl) or pl.HP > 0 then
		st.Unc = nil
		if d and d.ExpireTime > 0 then d.ExpireTime = 0 end
		if pl.HP > 0 and pl.Conditions[CO.Unconscious] ~= 0 and not outOfGame(pl) then
			pl.Conditions[CO.Unconscious] = 0
		end
		return
	end
	local now = Game.Time
	st.Unc = st.Unc or now
	if d then d.ExpireTime = st.Unc + C.UnconsciousInterval end
	local n = 0
	while st.Unc + C.UnconsciousInterval <= now and n < 6 do   -- at most an hour of checks at once
		st.Unc = st.Unc + C.UnconsciousInterval
		n = n + 1
		local roll = rnd(20) + statFx(pl, "Endurance")
		if roll >= C.UnconsciousDC - pl.HP then
			pl.HP = math.min(pl.HP + rnd(8), 1)
			if pl.HP > 0 then
				pl.Conditions[CO.Unconscious] = 0
				setIfNone(pl, CO.Weak)
				st.Unc = nil
				if d then d.ExpireTime = 0 end
				return
			end
		else
			pl.HP = pl.HP - rnd(8)   -- the game kills at -Endurance
			if pl.Conditions[CO.Dead] ~= 0 or pl.HP <= -pl:GetEndurance() then st.Unc = nil return end
		end
	end
	if st.Unc and st.Unc + C.UnconsciousInterval <= now then st.Unc = now end
end

---------------------------------------------------------------------------
-- dead and eradicated: base stats drain over time (rest and travel included)
---------------------------------------------------------------------------

local STATS = {"Might", "Intellect", "Personality", "Endurance", "Accuracy", "Speed"}
local STAT_NAMES = {Might = Tx"Might", Intellect = Tx"Intellect", Personality = Tx"Personality",
	Endurance = Tx"Endurance", Accuracy = Tx"Accuracy", Speed = Tx"Speed"}

local function runStatLoss(pl)
	local st = state(pl)
	local erad = pl.Conditions[CO.Eradicated] ~= 0
	local dead = pl.Conditions[CO.Dead] ~= 0
	if not (erad or dead) then
		st.Loss = nil
		-- back from death: one more revival for the soul fatigue
		if st.Out then
			local outAt = type(st.Out) == "number" and st.Out or Game.Time
			st.Out = nil
			local blessed = st.Blessed and Game.Time - st.Blessed <= C.BlessedFor
			st.Blessed = nil
			if blessed then
				if (st.Revivals or 0) > 0 then
					st.Revivals = st.Revivals - 1
					message(Tx"%s's soul is eased: the weariness of one death is lifted", pl.Name)
				end
			elseif Game.Time - outAt >= C.SoulFatigueAfter then
				st.Revivals = (st.Revivals or 0) + 1
				local mul = math.min(C.SoulFatigueMax, 1 + st.Revivals)
				message(Tx"%s's soul grows weary: after another death the body decays %dx faster", pl.Name, mul)
			end
		end
		return
	end
	-- when the character fell: the earlier of the two conditions' times
	if not st.Out then
		local t0 = Game.Time
		for _, c in ipairs{CO.Dead, CO.Eradicated} do
			local v = pl.Conditions[c]
			if v ~= 0 and v < t0 then t0 = v end
		end
		st.Out = t0
	end
	-- soul fatigue: the revivals so far shorten the time per point
	local every = (erad and C.StatLossErad or C.StatLossDead)
		/ math.min(C.SoulFatigueMax, 1 + (st.Revivals or 0))
	local now = Game.Time
	st.Loss = st.Loss or now
	local n = math.floor((now - st.Loss) / every)
	if n <= 0 then return end
	st.Loss = st.Loss + n * every
	local lost = 0
	for _ = 1, n do
		local name = STATS[rnd(#STATS)]
		local f = name .. "Base"
		if pl[f] > 0 then
			pl[f] = pl[f] - 1
			lost = lost + 1
			if n == 1 then
				message(Tx"%s loses %d %s from being %s", pl.Name, 1, STAT_NAMES[name], erad and Tx"Eradicated" or Tx"Dead")
			end
		end
	end
	if n > 1 and lost > 0 then
		message(Tx"%s has lost %d stat points from being %s", pl.Name, lost, erad and Tx"Eradicated" or Tx"Dead")
	end
end

-- the blessed revivals: Divine Intervention cast at Grand Master (the whole party), Aqua Vitae
local function bless(pl)
	if pl.Conditions[CO.Dead] ~= 0 or pl.Conditions[CO.Eradicated] ~= 0 then
		state(pl).Blessed = Game.Time
	end
end
function events.PlayerCastSpell(t)
	if t.SpellId == 88 and (t.Mastery or 0) >= 4 then
		for _, pl in Party do pcall(bless, pl) end
	end
end
-- Aqua Vitae (potion 71) is set by Global/ExtraPotions.lua, run with each game: wrapped again
-- whenever it is not the wrapper
local AquaWrapper
local function wrapAquaVitae()
	local cur = evt.PotionEffects and evt.PotionEffects[71]
	if not cur or cur == AquaWrapper then return end
	AquaWrapper = function(IsDrunk, Target, ...)
		if IsDrunk and Target then pcall(bless, Target) end
		return cur(IsDrunk, Target, ...)
	end
	evt.PotionEffects[71] = AquaWrapper
end

---------------------------------------------------------------------------
-- weakness from starving on the road; daily escalation
---------------------------------------------------------------------------

local DaysToTravel = 0
local NoWeaknessHouseTypes = {[24] = true, [25] = true, [27] = true, [28] = true}

function events.WalkToMap(t)
	vars.RemainingFood = Party.Food
	vars.WeaknessCounter = vars.WeaknessCounter or {0, 0, 0, 0, 0}
	DaysToTravel = t.Days
	for _, pl in Party do
		vars.WeaknessCounter[pl:GetSlot() + 1] = pl.Conditions[CO.Weak]
	end
end

function events.GetTravelDaysCost(t)
	if NoWeaknessHouseTypes[Game.Houses[t.House].Type] then DaysToTravel = 0 end
end

local function checkWeakness(pl)
	vars.WeakNextCheck = vars.WeakNextCheck or {}
	local key = pl:GetIndex()
	local weak = pl.Conditions[CO.Weak]
	if weak <= 0 then vars.WeakNextCheck[key] = nil return end
	local nextCheck = vars.WeakNextCheck[key]
	if nextCheck and Game.Time < nextCheck then return end
	vars.WeakNextCheck[key] = Game.Time + const.Day
	if pl.Conditions[CO.Insane] == 0 then
		local days = (Game.Time - weak) / const.Day
		if (days >= 7 and rnd(100) <= 50) or (days >= 3 and days < 7 and rnd(100) <= 25) then
			pl.Conditions[CO.Insane] = weak + const.Day * (days >= 7 and 7 or 3)
		end
	end
	if weak <= Game.Time - const.Day * 10 and pl.Conditions[CO.Dead] == 0 and rnd(100) <= 50 then
		pl.Conditions[CO.Dead] = weak + const.Day * 10
		pl.Conditions[CO.Weak] = 0
		pl.Conditions[CO.Insane] = 0
		if vars.WeaknessCounter then vars.WeaknessCounter[pl:GetSlot() + 1] = 0 end
		vars.WeakNextCheck[key] = nil
	end
end

---------------------------------------------------------------------------
-- the scan
---------------------------------------------------------------------------

local Rested = false   -- the party has been on the rest screen since the last scan

local function scan()
	local rested = Rested and Party.Food > 0
	Rested = false
	for _, pl in Party do
		pcall(runDot, pl, rested)
		pcall(runLight, pl)
		pcall(runShown, pl)
		pcall(runUnconscious, pl)
		pcall(runStatLoss, pl)
		pcall(checkWeakness, pl)
	end
end
MF.ConditionsScan = scan

-- cures show at once: a cured condition's status timer goes away in the same frame, and
-- the rest screen is noted for the rest's cure chance
local TickN = 0
local function clearCured()
	if Game.CurrentScreen == const.Screens.Rest then Rested = true end
	for _, pl in Party do
		for _, cond in ipairs(DOT_ORDER) do
			if pl.Conditions[cond] == 0 then
				local d = debuffOf(pl, cond)
				if d and d.ExpireTime > 0 then d.ExpireTime = 0 end
			end
		end
		for cond in pairs(C.Light) do
			if pl.Conditions[cond] == 0 then
				local d = debuffOf(pl, cond)
				if d and d.ExpireTime > 0 then d.ExpireTime = 0 end
			end
		end
	end
end
function events.Tick()
	TickN = TickN + 1
	if TickN % 5 == 0 then pcall(clearCured) end
end

local ScanTimer
function events.AfterLoadMap()
	pcall(wrapAquaVitae)
	vars.WeaknessCounter = vars.WeaknessCounter or {0, 0, 0, 0, 0}
	vars.RemainingFood = vars.RemainingFood or Party.Food
	vars.StatLossNext = nil   -- the old hourly stat loss

	-- weakness from food running out on the way
	if Party.Food == 0 and DaysToTravel > vars.RemainingFood then
		for _, pl in Party do
			local i = pl:GetSlot() + 1
			if vars.WeaknessCounter[i] == 0 and pl.Conditions[CO.Dead] == 0
					and pl.Conditions[CO.Eradicated] == 0 and pl.Conditions[CO.Zombie or 17] == 0 then
				pl.Conditions[CO.Weak] = Game.Time - const.Day * DaysToTravel + const.Day * vars.RemainingFood
				vars.WeaknessCounter[i] = pl.Conditions[CO.Weak]
			else
				pl.Conditions[CO.Weak] = vars.WeaknessCounter[i]
				vars.WeaknessCounter[i] = 0
			end
		end
	end
	DaysToTravel = 0

	scan()   -- settles the time spent on the way
	if ScanTimer then RemoveTimer(ScanTimer) end
	ScanTimer = scan
	Timer(ScanTimer, C.ScanEvery, true)
end
