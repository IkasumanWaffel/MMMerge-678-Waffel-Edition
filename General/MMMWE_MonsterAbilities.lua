--[[
	MMMWE_MonsterAbilities.lua — abilities of outleveled monsters (09.11.26)

	The bolster (AdaptiveMonstersStats.lua, "Bolster - formulas.txt") raises the stats of the
	monsters a party has outgrown. Their Hit Points grow less than before; instead a monster
	gets abilities by how far the party is above its level (the party's average level over the
	monster's level):
	  below x1.5 (or fewer than MIN_GAP levels)  none
	  x1.5 .. x2.5                               1 ability
	  x2.5 .. x4                                 2
	  x4 and more                                3
	About one monster in LEADER_ONE_IN (with any ability) leads its pack: one ability more,
	from the pack group, and a Champion's +25% Hit Points.

	Defensive  Regeneration     heals 2% of its Hit Points a second
	           Adaptation       the element that hit it last does 40% less for 10 seconds
	           Thorns           15% of the melee damage it takes goes back to the attacker
	           Last Stand       the first time it falls below 30%, it takes no damage for 3 seconds
	           Juggernaut       hits don't stagger it (19.11.26)
	Offensive  Enrage           below 40% of its Hit Points: +50% damage
	           Sundering        +25% physical damage
	           Twin Strike      25% chance to hit twice
	           Cleave           a hit also deals half its damage to another party member
	Control    Concussion       12% chance to knock the target out (Asleep)
	           Mana Burn        a hit burns spell points: half the damage
	           Hamstring        a hit slows the target's recovery
	           Terror           10% chance to frighten the target (Afraid)
	           Slow             15% chance to slow the whole party's movement by 40% for
	                            6 seconds (MMMWE_PartySpeed.lua; 25.11.26)
	Pack       Warlord          monsters near it deal +20% damage and take 10% less
	           Call for Help    below half its Hit Points, it calls two of its kind (once)

	The abilities are kept in the map's variables (mapvars.MMMWE_MonAbilities) by monster
	index and monster id, so they stay with a monster over reloads. A Game.BolsterAmount of 0
	or a map without bolster gives no abilities.
	MF.MonsterAbilities(index) -> list of ability names (for other scripts).
	The monster card (right click) lists a monster's abilities when the selected character
	has Identify Monster at Master or above.
--]]

local MF = Merge.Functions
local Tx = Merge.Functions.Text
local floor, max, min, random = math.floor, math.max, math.min, math.random

local ENABLED       = true
local MIN_GAP       = 8         -- levels the party needs above a monster before it gets any
local TIERS         = {1.5, 2.5, 4}
local LEADER_ONE_IN = 8
local LEADER_HP     = 1.25
local AURA_RANGE    = 1500
local CHECK_TIME    = 2         -- seconds between looks for monsters without a roll

local A = {
	Regeneration = {Group = "Defensive", Name = Tx"Regeneration", Rate = 0.02},
	Adaptation   = {Group = "Defensive", Name = Tx"Adaptation", Mul = 0.6, Time = 10},
	Thorns       = {Group = "Defensive", Name = Tx"Thorns", Share = 0.15},
	LastStand    = {Group = "Defensive", Name = Tx"Last Stand", Below = 0.3, Time = 3},
	Juggernaut   = {Group = "Defensive", Name = Tx"Juggernaut"},
	Enrage       = {Group = "Offensive", Name = Tx"Enrage", Below = 0.4, Mul = 1.5},
	Sundering    = {Group = "Offensive", Name = Tx"Sundering", Mul = 1.25},
	TwinStrike   = {Group = "Offensive", Name = Tx"Twin Strike", Chance = 0.25},
	Cleave       = {Group = "Offensive", Name = Tx"Cleave", Share = 0.5},
	Concussion   = {Group = "Control", Name = Tx"Concussion", Chance = 0.12, Time = 5},   -- minutes between the saves
	ManaBurn     = {Group = "Control", Name = Tx"Mana Burn", Share = 0.5},
	Hamstring    = {Group = "Control", Name = Tx"Hamstring", Delay = 60},
	Terror       = {Group = "Control", Name = Tx"Terror", Chance = 0.10, Time = 15},      -- minutes between the saves
	Slow         = {Group = "Control", Name = Tx"Slow", Chance = 0.15, Mul = 0.6, Time = 6},  -- party speed x Mul, seconds
	Warlord      = {Group = "Pack", Name = Tx"Warlord", DamageMul = 1.2, TakenMul = 0.9},
	CallForHelp  = {Group = "Pack", Name = Tx"Call for Help", Below = 0.5, Count = 2},
	-- (22.11.26) a boss's weakness (MMMWE_Bosses.lua does what it does; listed on the card)
	OldWound     = {Group = "Weakness", Name = Tx"Old Wound"},
}
local POOL = {"Regeneration", "Adaptation", "Thorns", "LastStand", "Juggernaut", "Enrage", "Sundering",
	"TwinStrike", "Cleave", "Concussion", "ManaBurn", "Hamstring", "Terror", "Slow"}
local CASTER_POOL = {"Adaptation", "LastStand", "ManaBurn", "Terror", "Regeneration", "Concussion", "Slow"}
local PACK = {"Warlord", "CallForHelp"}
MF.MonsterAbilitySettings = A

if not ENABLED then return end

---------------------------------------------------------------------------

local function store()
	mapvars.MMMWE_MonAbilities = mapvars.MMMWE_MonAbilities or {}
	return mapvars.MMMWE_MonAbilities
end

local State = {}      -- [monster index] = {per-fight state: adaptation, last stand, call for help}
local Queue = {}      -- effects done on the next tick (not inside the game's damage code)

local function alive(m)
	return m.HP > 0 and m.AIState ~= const.AIState.Dying and m.AIState ~= const.AIState.Dead
		and m.AIState ~= const.AIState.Removed
end

local function partyLevel()
	local sum, n = 0, 0
	for i = 0, Party.count - 1 do
		sum, n = sum + Party[i].LevelBase, n + 1
	end
	return n > 0 and sum / n or 1
end

local function tierOf(m, pl)
	local ml = max(m.Level, 1)
	if pl - ml < MIN_GAP then return 0 end
	local r, t = pl / ml, 0
	for i, v in ipairs(TIERS) do if r >= v then t = i end end
	return t
end

local function pick(list, have)
	local free = {}
	for _, k in ipairs(list) do if not have[k] then free[#free + 1] = k end end
	if #free == 0 then return end
	return free[random(#free)]
end

local function dist2(a, b)
	local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
	return dx * dx + dy * dy + dz * dz
end

-- the abilities of a monster: rolled once (when the party first sees it on the map)
local function roll(i, m, pl)
	local t = tierOf(m, pl)
	local rec = {Id = m.Id, A = {}}
	if t > 0 then
		local have = {}
		local list = (m.Spell or 0) > 0 and CASTER_POOL or POOL
		for _ = 1, t do
			local k = pick(list, have) or pick(POOL, have)
			if k then have[k] = true; rec.A[#rec.A + 1] = k end
		end
		if random(LEADER_ONE_IN) == 1 then
			local leaderNear = false
			for j, r in pairs(store()) do
				if r.Leader and j ~= i and j < Map.Monsters.count
						and dist2(Map.Monsters[j], m) < (2 * AURA_RANGE) ^ 2 then
					leaderNear = true
					break
				end
			end
			if not leaderNear then
				local k = PACK[random(#PACK)]
				rec.A[#rec.A + 1] = k
				rec.Leader = true
				m.FullHP = min(floor(m.FullHP * LEADER_HP), 32000)
				m.HP = min(floor(m.HP * LEADER_HP), 32000)
			end
		end
	end
	store()[i] = rec
	return rec
end

local function abilities(i, m)
	local r = store()[i]
	if r and r.Id == m.Id then return r end
end

local function has(r, k)
	if not r then return false end
	for _, v in ipairs(r.A) do if v == k then return true end end
	return false
end

local function monName(m)
	-- a named monster (Placemon.txt) by its own name, without its colour codes
	if (m.NameId or 0) > 0 and Game.PlaceMonTxt[m.NameId] then
		local s = Game.PlaceMonTxt[m.NameId]:gsub("\f%d%d%d%d%d", "")
		if s ~= "" then return s end
	end
	local t = Game.MonstersTxt[m.Id]
	return t and t.Name or "?"
end

local function status(s) Game.ShowStatusText(s, 2) end

-- the monster behind the hit the party is taking right now (as in MMMWE_Drains.lua)
local function attacker()
	if not WhoHitPlayer then return end
	local who = WhoHitPlayer()
	if type(who) ~= "table" then return end
	if who.Monster then return who.Monster, who.MonsterIndex end
	local o = who.Object
	if o and o.Owner and o.Owner % 8 == 3 then
		local i = floor(o.Owner / 8)
		if i < Map.Monsters.count then return Map.Monsters[i], i end
	end
end

-- a Warlord near the monster (not the monster itself)
local function warlordNear(i, m)
	for j, r in pairs(store()) do
		if j ~= i and r.Leader and has(r, "Warlord") and j < Map.Monsters.count then
			local w = Map.Monsters[j]
			if w.Id == r.Id and alive(w) and dist2(w, m) < AURA_RANGE * AURA_RANGE then return true end
		end
	end
	return false
end

local function enabled()
	return (Game.BolsterAmount or 100) > 0
end

-- (22.11.26) a boss's abilities (MMMWE_Bosses.lua) work whatever the bolster
local function active(r)
	return enabled() or (r ~= nil and r.Boss == true)
end

-- fixed abilities for a boss: Juggernaut and Count more (casters from their own list),
-- kept like the rolled ones
-- Opt: {NoJuggernaut = true, Extra = {ability names put first}}
function MF.SetBossAbilities(i, m, Count, Opt)
	Opt = Opt or {}
	local rec = {Id = m.Id, A = {}, Boss = true}
	local have = {Juggernaut = Opt.NoJuggernaut or nil}
	for _, k in ipairs(Opt.Extra or {}) do have[k] = true; rec.A[#rec.A + 1] = k end
	if not Opt.NoJuggernaut then have.Juggernaut = true; rec.A[#rec.A + 1] = "Juggernaut" end
	local list = (m.Spell or 0) > 0 and CASTER_POOL or POOL
	for _ = 1, Count or 2 do
		local k = pick(list, have) or pick(POOL, have)
		if k then have[k] = true; rec.A[#rec.A + 1] = k end
	end
	store()[i] = rec
	return rec
end

function MF.IsBossAbilityRecord(i, m)
	local r = store()[i]
	return r ~= nil and r.Id == m.Id and r.Boss == true
end

---------------------------------------------------------------------------
-- damage the monsters take
---------------------------------------------------------------------------

function events.CalcDamageToMonster(t)
	if not t.Monster or (t.Result or 0) <= 0 then return end
	local i, m = t.MonsterIndex, t.Monster
	local r = abilities(i, m)
	if not active(r) then return end
	local now = os.clock()
	if r then
		local s = State[i] or {}
		State[i] = s
		if has(r, "LastStand") then
			if s.Invulnerable and now < s.Invulnerable then
				t.Result = 0
				return
			end
			if not s.StandUsed and m.HP - t.Result < m.FullHP * A.LastStand.Below then
				s.StandUsed, s.Invulnerable = true, now + A.LastStand.Time
				t.Result = max(0, min(t.Result, m.HP - 1))
				status(string.format(Tx"%s makes a last stand!", monName(m)))
				return
			end
		end
		if has(r, "Adaptation") then
			if s.AdaptKind == t.DamageKind and now < (s.AdaptUntil or 0) then
				t.Result = floor(t.Result * A.Adaptation.Mul)
			end
			s.AdaptKind, s.AdaptUntil = t.DamageKind, now + A.Adaptation.Time
		end
		if has(r, "Thorns") and t.ByPlayer and t.Melee and t.Player then
			local back = floor(t.Result * A.Thorns.Share)
			if back > 0 then Queue[#Queue + 1] = {Kind = "damage", Player = t.Player, Damage = back} end
		end
		if has(r, "CallForHelp") and not s.Called and m.HP - t.Result < m.FullHP * A.CallForHelp.Below then
			s.Called = true
			Queue[#Queue + 1] = {Kind = "summon", Id = m.Id, X = m.X, Y = m.Y, Z = m.Z, Name = monName(m)}
		end
	end
	if warlordNear(i, m) then
		t.Result = floor(t.Result * A.Warlord.TakenMul)
	end
end

---------------------------------------------------------------------------
-- damage the party takes
---------------------------------------------------------------------------

function events.CalcDamageToPlayer(t)
	if not t.Player or (t.Result or 0) <= 0 then return end
	local m, i = attacker()
	if not m or not i then return end
	local r = abilities(i, m)
	if not active(r) then return end
	local mul = 1
	if warlordNear(i, m) or (r and has(r, "Warlord")) then mul = mul * A.Warlord.DamageMul end
	if r then
		if has(r, "Enrage") and m.HP < m.FullHP * A.Enrage.Below then mul = mul * A.Enrage.Mul end
		if has(r, "Sundering") and t.DamageKind == const.Damage.Phys then mul = mul * A.Sundering.Mul end
		if has(r, "TwinStrike") and random() < A.TwinStrike.Chance then
			mul = mul * 2
			status(string.format(Tx"%s strikes twice!", monName(m)))
		end
	end
	t.Result = floor(t.Result * mul)
	if not r then return end
	local pl = t.Player
	if has(r, "Cleave") then
		Queue[#Queue + 1] = {Kind = "cleave", Except = t.PlayerIndex, Damage = floor(t.Result * A.Cleave.Share),
			DamageKind = t.DamageKind}
	end
	if has(r, "ManaBurn") and pl.SpellPoints > 0 then
		pl.SpellPoints = max(0, pl.SpellPoints - floor(t.Result * A.ManaBurn.Share))
	end
	if has(r, "Hamstring") then
		Queue[#Queue + 1] = {Kind = "slow", Player = pl}
	end
	if has(r, "Concussion") and random() < A.Concussion.Chance then
		Queue[#Queue + 1] = {Kind = "condition", Player = pl, Condition = const.Condition.Asleep,
			Time = A.Concussion.Time, Text = string.format(Tx"%s is knocked out!", pl.Name)}
	end
	if has(r, "Slow") and random() < A.Slow.Chance then
		Queue[#Queue + 1] = {Kind = "slowparty", Name = monName(m)}
	end
	if has(r, "Terror") and random() < A.Terror.Chance then
		Queue[#Queue + 1] = {Kind = "condition", Player = pl, Condition = const.Condition.Afraid,
			Time = A.Terror.Time, Text = string.format(Tx"%s is terrified!", pl.Name)}
	end
end

---------------------------------------------------------------------------
-- every tick: the queued effects; regeneration; rolls for new monsters
---------------------------------------------------------------------------

local function runQueue()
	local q = Queue
	Queue = {}
	for _, e in ipairs(q) do
		local ok, err = pcall(function()
			if e.Kind == "damage" then
				if e.Player:IsConscious() then e.Player:DoDamage(e.Damage, const.Damage.Phys) end
			elseif e.Kind == "cleave" then
				local list = {}
				for k = 0, Party.count - 1 do
					if k ~= e.Except and Party[k]:IsConscious() then list[#list + 1] = k end
				end
				if #list > 0 and e.Damage > 0 then
					Party[list[random(#list)]]:DoDamage(e.Damage, e.DamageKind or const.Damage.Phys)
				end
			elseif e.Kind == "slowparty" then
				if MF.PartySlow then
					MF.PartySlow(A.Slow.Mul, A.Slow.Time)
					status(string.format(Tx"%s slows the party down!", e.Name))
				end
			elseif e.Kind == "slow" then
				e.Player.RecoveryDelay = e.Player.RecoveryDelay + A.Hamstring.Delay
			elseif e.Kind == "condition" then
				-- (25.11.26) until a save succeeds, rolled every Time minutes (MMMWE_Conditions.lua),
				-- with the time to the next roll on the portrait bar
				if e.Player:IsConscious() and e.Player.Conditions[e.Condition] == 0 then
					if MF.TimedCondition and e.Time then
						MF.TimedCondition(e.Player, e.Condition, e.Time * const.Minute, true)
					else
						e.Player.Conditions[e.Condition] = Game.Time
					end
					status(e.Text)
				end
			elseif e.Kind == "summon" then
				for k = 1, A.CallForHelp.Count do
					local a = (k / A.CallForHelp.Count) * 2 * math.pi
					local mon = SummonMonster(e.Id, e.X + floor(200 * math.cos(a)), e.Y + floor(200 * math.sin(a)), e.Z, true)
					if mon then
						mon.Hostile, mon.ShowAsHostile = true, true
						mon.AIState = const.AIState.Pursue
					end
				end
				status(string.format(Tx"%s calls for help!", e.Name))
			end
		end)
		if not ok and MF.LogWarning then MF.LogWarning("MonsterAbilities: %s", tostring(err)) end
	end
end

local LastRegen, LastCheck = 0, 0
function events.Tick()
	if #Queue > 0 then runQueue() end
	if Game.CurrentScreen ~= 0 then return end
	local on = enabled()
	local now = os.clock()
	if now - LastRegen >= 0.5 then
		local dt = min(now - LastRegen, 1)
		LastRegen = now
		for i, r in pairs(store()) do
			if i < Map.Monsters.count and (on or r.Boss) and has(r, "Regeneration") then
				local m = Map.Monsters[i]
				if m.Id == r.Id and alive(m) and m.HP < m.FullHP then
					m.HP = min(m.FullHP, m.HP + max(1, floor(m.FullHP * A.Regeneration.Rate * dt)))
				end
			end
		end
	end
	if on and now - LastCheck >= CHECK_TIME then
		LastCheck = now
		local pl = partyLevel()
		local s = store()
		for i = 0, Map.Monsters.count - 1 do
			local m = Map.Monsters[i]
			local r = s[i]
			if (not r or r.Id ~= m.Id) and alive(m) and m.Hostile then
				roll(i, m, pl)
			end
		end
	end
end

---------------------------------------------------------------------------
-- (19.11.26) Juggernaut: hits don't stagger it.
-- Every hit that does damage (or has an effect) and leaves a monster alive calls the game's
-- "monster got hit" routine (0x4032DD: ecx the monster's index, edx the attacker, arg: forced).
-- There is no chance in it: unless the monster is already staggered or in the middle of an
-- attack (AI states 2, 3, 8, 12, 13, 18), it is put into the Stunned state (8) for the length
-- of its "got hit" animation, which breaks off what it was doing, and the hit sound plays.
-- The routine also makes the monster hostile and aware of the attacker: that part (before
-- 0x40334B) still runs. A Juggernaut skips the stagger itself (MMMWE_StaggerPoise.lua). Forced staggers (the Stun spell) and the
-- weapons' stun and paralysis (Mace, Staff, Unarmed, shield bash) work as before.
---------------------------------------------------------------------------

-- the hook itself is in MMMWE_StaggerPoise.lua (it also spaces out the staggers of every monster)
function MF.MonsterIsJuggernaut(i)
	if i < 0 or i >= Map.Monsters.count then return false end
	local r = abilities(i, Map.Monsters[i])
	return active(r) and has(r, "Juggernaut")
end

function events.AfterLoadMap()
	State, Queue = {}, {}
	LastCheck = 0
end

-- the ability names of a map monster
function MF.MonsterAbilities(i)
	local m = Map.Monsters[i]
	local r = m and abilities(i, m)
	local t = {}
	for _, k in ipairs(r and r.A or {}) do t[#t + 1] = A[k].Name end
	return t, r and r.Leader
end

---------------------------------------------------------------------------
-- (09.11.26) the monster card (right click): with Identify Monster at Master or above
-- (the selected character's, as the game's own checks on the card), the abilities are
-- listed in the card's left column, under the monster's spell effects. The effects list
-- ends at 0x41E398 (edi - the next line's y, [ebp-8] the dialog, [ebp-20h] its font,
-- [ebp-0Ch] its colour, [ebp-10h] the monster shown); the lines are drawn with the
-- game's text function (0x44A50F: ecx dialog, edx font; x, y, colour, text, 0, 0, 0).
---------------------------------------------------------------------------

local CARD_MASTERY = const.Master or 3
local CARD_HEAD_X, CARD_X = 0x0C, 0x1C   -- as the card's "Effects" heading and its lines
local CARD_GAP = 6

-- the map monster the card shows: the card may hold a copy (Game.DialogLogic.MonsterInfoMonster)
local function cardMonster(ptr)
	local size = Map.Monsters[0]["?size"]
	local i = (ptr - Map.Monsters["?ptr"]) / size
	if i >= 0 and i < Map.Monsters.count and i % 1 == 0 then return Map.Monsters[i], i end
	local info = Game.DialogLogic.MonsterInfoMonster
	if info["?ptr"] ~= ptr then return end
	for j = 0, Map.Monsters.count - 1 do
		local m = Map.Monsters[j]
		if m.Id == info.Id and m.X == info.X and m.Y == info.Y and m.Z == info.Z then return m, j end
	end
end

local function cardMastery()
	local k = MF.GetCurrentPlayer and MF.GetCurrentPlayer() or Game.CurrentPlayer
	local pl = Party[k and k >= 0 and k < Party.count and k or 0]
	local _, m = SplitSkill(pl:GetSkill(const.Skills.IdentifyMonster))
	return m
end

mem.autohook(0x41E398, function(d)
	local ok, err = pcall(function()
		local m, i = cardMonster(mem.u4[d.ebp - 0x10])
		if not m then return end
		local r = abilities(i, m)
		if not r or not active(r) or #r.A == 0 or cardMastery() < CARD_MASTERY then return end
		local dlg, font, color = mem.u4[d.ebp - 8], mem.u4[d.ebp - 0x20], mem.u4[d.ebp - 0xC]
		local lineH = mem.u1[font + 5] - 3
		-- edi: the line after the last effect; with no effects the game drew "None" there
		-- without moving on ([ebp-4] = 0)
		local y = d.edi + (mem.i4[d.ebp - 4] == 0 and lineH or 0) + CARD_GAP
		local function line(x, s)
			mem.call(0x44A50F, 2, dlg, font, x, y, color, s, 0, 0, 0)
			y = y + lineH
		end
		line(CARD_HEAD_X, r.Boss and Tx"Abilities (boss)" or r.Leader and Tx"Abilities (pack leader)" or Tx"Abilities")
		for _, k in ipairs(r.A) do line(CARD_X, A[k].Name) end
	end)
	if not ok and MF.LogWarning then MF.LogWarning("MonsterAbilities card: %s", tostring(err)) end
end)
