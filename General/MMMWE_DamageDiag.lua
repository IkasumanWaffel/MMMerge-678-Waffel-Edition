--[[
	MMMWE_DamageDiag.lua — diagnostics of the player -> monster damage pipeline

	Writes one line per resistance call (monster_resists 0x425951, hooked in
	Core/events.lua as CalcDamageToMonster) to MMMWE_DamageDiag.log in the game folder,
	and flags anything that doesn't look like the intended pipeline:

	  the intended pipeline of one hit
	    engine damage -> monster_resists -> curve of MMMWE_Main.lua (hook 0x4259CF, once,
	    twice for combined damage kinds) -> CalcDamageToMonster handlers
	    (ConcurrentEnchantments, DamageKinds, ItemDurability, Main, CombatLog)
	    -> monster HP goes down by the final t.Result

	  flags
	    NO-CURVE   the resistance curve of MMMWE_Main.lua didn't run in this call (the
	               old engine code decided the result: immune, or a code path that skips
	               the hook)
	    MULTI-CURVE the curve ran more than once in one call (expected only for combined
	               damage kinds); CHAINED if a later pass started from the already reduced
	               damage of an earlier one
	    ENGINE?    the engine's result differs from what the curve produced
	    SAME-HIT   another call with the same player, monster, kind and damage in the
	               same tick (the same hit resolved twice?)
	    HP?        the monster lost a different amount of HP over the tick than the sum of
	               the final results of the calls (damage applied outside the hooks, or
	               twice)
	    NOT-PLAYER damage to a monster while t.ByPlayer is false, from a caller that
	               otherwise belongs to player hits (the player check in Core may fail)
	    CE-LEFT    Core's CE_PendingResistKind is still set after the tick

	  each line: time, caller address, player, monster, source (who launched the
	  projectile / spell, or whose attack it is), kind (and physical kind),
	  input damage, curve passes (res: in->out), engine result, final result, flags

	Console:
	  Merge.Functions.DamageDiag.Enabled = false/true
	  Merge.Functions.DamageDiag.Report()       -- summary (callers, flag counts) to the log
	  Merge.Functions.DamageDiag.Reset()
	Settings below: ENABLED, LOG_ALL (false = flagged lines only), SHOW_FLAGS (status line).
--]]

local MF = Merge.Functions

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local ENABLED    = false
local LOG_ALL    = true      -- false: only lines with flags
local SHOW_FLAGS = true      -- status line message when a hit is flagged
local LOG_FILE   = "MMMWE_DamageDiag.log"

---------------------------------------------------------------------------

local D = {Enabled = ENABLED}
MF.DamageDiag = D

local KindNames = {}
for k, v in pairs(const.Damage) do KindNames[v] = k end

local function kindName(k)
	return KindNames[k] or tostring(k)
end

local logFile
local function out(line)
	if not logFile then
		logFile = io.open(LOG_FILE, "a")
		if not logFile then return end
		logFile:write(string.format("\n==== session %s ====\n", os.date("%Y-%m-%d %H:%M:%S")))
	end
	logFile:write(line, "\n")
	logFile:flush()
end

-- statistics
local Stats
function D.Reset()
	Stats = {Calls = 0, Flags = {}, Callers = {}}
end
D.Reset()

local function count(tbl, key)
	tbl[key] = (tbl[key] or 0) + 1
end

-- the curve records of the current call (filled by MMMWE_Main.lua's 0x4259CF hook)
MF.DamageDiagRes = {}

-- calls of the current tick
local TickCalls = {}       -- list of records
local TickHP = {}          -- [monster index] = HP before the first call this tick
local CurTick = 0

local function monsterName(mon)
	local ok, name = pcall(function() return Game.MonstersTxt[mon.Id].Name end)
	return ok and name or ("#" .. tostring(mon.Id))
end

-- index of ptr in a struct array (array capacity, not the current count), or nil
local function indexIn(arr, ptr, cap)
	if not ptr or ptr == 0 then return nil end
	local ok, base, size = pcall(function() return arr["?ptr"], arr[0]["?size"] end)
	if not ok then return nil end
	local i = (ptr - base) / size
	if i >= 0 and i < cap and i % 1 == 0 then return i end
end

-- "party member X" / "monster Name[i]" / "object" from an owner id (index * 8 + kind)
local function ownerText(owner)
	local kind, idx = owner % 8, math.floor(owner / 8)
	if kind == 4 then
		local ok, pl = pcall(function() return Party[idx] end)
		return "party " .. (ok and pl and pl.Name or ("#" .. idx))
	elseif kind == 3 then
		local ok, mon = pcall(function() return Map.Monsters[idx] end)
		return "monster " .. (ok and mon and monsterName(mon) or "?") .. "[" .. idx .. "]"
	elseif kind == 2 then
		return "object[" .. idx .. "]"
	elseif kind == 5 then
		return "sprite[" .. idx .. "]"
	end
	return string.format("owner %d (kind %d)", owner, kind)
end

-- Callers whose frame doesn't have the party-attack layout (ebp-8 = attacker player,
-- ebp-0x34 = projectile): monster-vs-monster damage. Their frame is searched for an
-- object id (index * 8 + kind) naming another monster or a projectile; the offset found
-- is printed so it can be fixed in place once it proves stable.
local SCAN_FROM, SCAN_TO = -0x60, 0x18

local function frameScan(t)
	local ebp = t.CallerEbp
	if not ebp or ebp == 0 then return nil end
	local found = {}
	for off = SCAN_FROM, SCAN_TO, 4 do
		local ok, v = pcall(function() return mem.i4[ebp + off] end)
		if ok and v and v > 0 then
			local kind, idx = v % 8, math.floor(v / 8)
			local hit
			if kind == 3 and idx ~= t.MonsterIndex and idx < Map.Monsters.count then
				hit = ownerText(v)
			elseif kind == 2 and idx < Map.Objects.count then
				local ok2, o = pcall(function() return Map.Objects[idx] end)
				if ok2 and o and o.Type ~= 0 then
					local by = (o.Owner and o.Owner > 0) and ownerText(o.Owner) or "?"
					hit = string.format("%s via object[%d]%s", by, idx,
						(o.Spell and o.Spell > 0) and string.format(" spell %d %s", o.Spell,
							Game.SpellsTxt[o.Spell] and Game.SpellsTxt[o.Spell].Name or "") or "")
				end
			end
			if hit then
				found[#found + 1] = string.format("%s @ebp%s0x%X", hit, off < 0 and "-" or "+", math.abs(off))
			end
		end
	end
	if #found == 0 then return nil end
	return table.concat(found, " | ")
end

-- Monster-vs-monster damage (found with the frame scan, 14.10.26): both callers keep the
-- attacker's id at [ebp-4] - a monster id (index * 8 + 3) for melee (0x438F1B), a
-- projectile id (index * 8 + 2) for spells and missiles (0x438CF4, area damage too).
local MVM_CALLERS = {[0x438CF4] = true, [0x438F1B] = true}

local function mvmSource(t)
	if not MVM_CALLERS[t.Caller] or not t.CallerEbp then return nil end
	local ok, v = pcall(function() return mem.i4[t.CallerEbp - 4] end)
	if not ok or not v or v <= 0 then return nil end
	local kind, idx = v % 8, math.floor(v / 8)
	if kind == 3 and idx < Map.Monsters.count then
		return "monster-vs-monster: " .. ownerText(v) .. " (melee)"
	elseif kind == 2 and idx < Map.Objects.count then
		local ok2, txt = pcall(function()
			local o = Map.Objects[idx]
			local what = (o.Spell and o.Spell > 0)
				and string.format("spell %d %s", o.Spell, Game.SpellsTxt[o.Spell] and Game.SpellsTxt[o.Spell].Name or "")
				or string.format("missile type %d", o.Type)
			-- a monster's spell keeps its caster in Owner; spells launched by map events
			-- (evt.CastSpell: traps, the cannon-like structures) have no caster
			local ok3, ow = o.Owner % 8, math.floor(o.Owner / 8)
			local caster = (ok3 == 3 and ow < Map.Monsters.count) and ownerText(o.Owner)
				or (ok3 == 4 and ownerText(o.Owner))
				or "no caster - map event / trap"
			return string.format("%s from object[%d] (%s)", what, idx, caster)
		end)
		if ok2 then return "monster-vs-monster: " .. txt end
	end
	return nil
end

-- who caused this damage: the projectile's owner and spell, else the attacker pointer
local function sourceText(t)
	local oi = indexIn(Map.Objects, t.ObjectPtr, 1000)
	if oi then
		local ok, s = pcall(function()
			local o = Map.Objects[oi]
			local txt = ownerText(o.Owner)
			if o.Spell and o.Spell > 0 then
				local name = Game.SpellsTxt[o.Spell] and Game.SpellsTxt[o.Spell].Name or ""
				txt = txt .. string.format(" via spell %d %s", o.Spell, name)
			else
				txt = txt .. string.format(" via object type %d", o.Type)
			end
			return txt
		end)
		if ok then return s end
	end
	local pi = indexIn(Party.PlayersArray, t.AttackerPtr, Party.PlayersArray.count or 50)
	if pi then return "party (attacker ptr)" end
	if not t.ByPlayer then
		local fixed = mvmSource(t)
		if fixed then return fixed end
		local scan = frameScan(t)
		if scan then return "monster-vs-monster (frame scan): " .. scan end
	end
	local mi = indexIn(Map.Monsters, t.AttackerPtr, 500)
	if mi then
		local ok, mon = pcall(function() return Map.Monsters[mi] end)
		return "monster " .. (ok and mon and monsterName(mon) or "?") .. "[" .. mi .. "] (attacker ptr)"
	end
	return string.format("unknown (attacker %08X, object %08X)", t.AttackerPtr or 0, t.ObjectPtr or 0)
end

---------------------------------------------------------------------------
-- First handler: sees the engine's result before any script changes it
-- (this file loads before MMMWE_DamageKinds / _ItemDurability / _Main)
---------------------------------------------------------------------------

function events.CalcDamageToMonster(t)
	local passes = MF.DamageDiagRes
	MF.DamageDiagRes = {}
	if not D.Enabled then return end

	local mon = t.Monster
	local rec = {
		Tick = CurTick,
		Caller = t.Caller or 0,
		ByPlayer = t.ByPlayer,
		Player = t.ByPlayer and t.Player and t.Player.Name or "-",
		PlayerIndex = t.PlayerIndex,
		MonsterIndex = t.MonsterIndex,
		Monster = mon and monsterName(mon) or "?",
		Kind = t.DamageKind,
		Damage = t.Damage,
		Engine = t.Result,
		Secondary = t.IsSecondary,
		Melee = t.Melee,
		Passes = passes,
		Source = sourceText(t),
		Flags = {},
		T = t,
	}
	if mon and t.MonsterIndex and TickHP[t.MonsterIndex] == nil then
		TickHP[t.MonsterIndex] = mon.HP
	end

	-- curve checks
	local immune = false
	if #passes == 0 then
		-- immune monsters (65000) legitimately skip the curve; anything else is the old code
		if t.Result ~= 0 or (t.Damage or 0) == 0 then
			rec.Flags[#rec.Flags + 1] = "NO-CURVE"
		else
			immune = true
		end
	else
		local last = passes[#passes]
		if #passes > 1 then
			rec.Flags[#rec.Flags + 1] = "MULTI-CURVE"
			for i = 2, #passes do
				if passes[i].In ~= passes[1].In then
					rec.Flags[#rec.Flags + 1] = "CHAINED"
					break
				end
			end
		end
		-- the engine returns the curve's output (min of the passes for combined kinds)
		local best = math.huge
		for _, p in ipairs(passes) do best = math.min(best, p.Out) end
		if math.abs((t.Result or 0) - best) > 1 then
			rec.Flags[#rec.Flags + 1] = "ENGINE?"
		end
	end
	rec.Immune = immune

	-- the same hit twice in one tick?
	for _, r in ipairs(TickCalls) do
		if r.ByPlayer and rec.ByPlayer and r.PlayerIndex == rec.PlayerIndex
				and r.MonsterIndex == rec.MonsterIndex and r.Kind == rec.Kind
				and r.Damage == rec.Damage and r.Secondary == rec.Secondary
				and (rec.Damage or 0) > 0 then   -- 0-damage calls: weapons without enchantment
			rec.Flags[#rec.Flags + 1] = "SAME-HIT"
			break
		end
	end

	-- callers that are known to belong to player hits
	if rec.ByPlayer then
		Stats.Callers[rec.Caller] = Stats.Callers[rec.Caller] or {Player = 0, Other = 0}
		Stats.Callers[rec.Caller].Player = Stats.Callers[rec.Caller].Player + 1
	else
		local c = Stats.Callers[rec.Caller] or {Player = 0, Other = 0}
		Stats.Callers[rec.Caller] = c
		c.Other = c.Other + 1
		if c.Player > 0 then rec.Flags[#rec.Flags + 1] = "NOT-PLAYER" end
	end

	TickCalls[#TickCalls + 1] = rec
	Stats.Calls = Stats.Calls + 1
end

---------------------------------------------------------------------------
-- Last handler: the final result (registered on the first tick, after every script's
-- GameInitialized2 has added its own handlers)
---------------------------------------------------------------------------

local function lastHandler(t)
	if not D.Enabled then return end
	local rec = TickCalls[#TickCalls]
	if rec and rec.T == t then
		rec.Final = t.Result
		rec.PhysKind = t.PhysDamageKind
	end
end

---------------------------------------------------------------------------
-- End of tick: HP check, write the lines
---------------------------------------------------------------------------

local function passesText(passes)
	if #passes == 0 then return "-" end
	local parts = {}
	for _, p in ipairs(passes) do
		parts[#parts + 1] = string.format("%s r%d %d->%d", kindName(p.Elem), p.Res, p.In, p.Out)
	end
	return table.concat(parts, ", ")
end

local function flush()
	if #TickCalls == 0 then
		TickHP = {}
		return
	end

	-- HP check per monster
	local finalSum, lastRec = {}, {}
	for _, r in ipairs(TickCalls) do
		if r.MonsterIndex then
			finalSum[r.MonsterIndex] = (finalSum[r.MonsterIndex] or 0) + (r.Final or r.Engine or 0)
			lastRec[r.MonsterIndex] = r
		end
	end
	for mi, before in pairs(TickHP) do
		local ok, mon = pcall(function() return Map.Monsters[mi] end)
		if ok and mon then
			local lost = before - mon.HP
			local expected = finalSum[mi] or 0
			-- a killed monster can't lose more than it had
			if mon.HP <= 0 then expected = math.min(expected, before) lost = math.min(lost, before) end
			if math.abs(lost - expected) > 1 and lastRec[mi] then
				local r = lastRec[mi]
				r.Flags[#r.Flags + 1] = string.format("HP?(lost %d, expected %d)", lost, expected)
			end
		end
	end

	for _, r in ipairs(TickCalls) do
		for _, f in ipairs(r.Flags) do count(Stats.Flags, f:match("^[%w%-%?]+")) end
		if LOG_ALL or #r.Flags > 0 then
			out(string.format("%s caller=%08X %s -> %s[%s] source=%s %s%s%s dmg=%s curve=[%s] engine=%s final=%s%s %s",
				tostring(Game.Time), r.Caller, r.Player, r.Monster, tostring(r.MonsterIndex), r.Source,
				kindName(r.Kind), r.PhysKind and ("/" .. r.PhysKind) or "",
				r.Secondary and " (enchant)" or (r.Melee and " (melee)" or " (ranged/spell)"),
				tostring(r.Damage), passesText(r.Passes), tostring(r.Engine), tostring(r.Final),
				r.Immune and " immune" or "",
				#r.Flags > 0 and ("!! " .. table.concat(r.Flags, " ")) or ""))
		end
		if SHOW_FLAGS and #r.Flags > 0 then
			Game.ShowStatusText("DamageDiag: " .. table.concat(r.Flags, " ") .. " (see log)")
		end
		r.T = nil
	end
	TickCalls = {}
	TickHP = {}
end

local registered = false
function events.Tick()
	if not registered then
		registered = true
		events.CalcDamageToMonster = lastHandler
	end
	CurTick = CurTick + 1
	if D.Enabled then
		flush()
		if _G.CE_PendingResistKind ~= nil then
			count(Stats.Flags, "CE-LEFT")
			out(string.format("%s !! CE-LEFT CE_PendingResistKind = %s was never used",
				tostring(Game.Time), tostring(_G.CE_PendingResistKind)))
		end
	else
		TickCalls, TickHP = {}, {}
	end
end

---------------------------------------------------------------------------
-- Summary
---------------------------------------------------------------------------

function D.Report()
	out(string.format("---- summary: %d calls ----", Stats.Calls))
	for f, n in pairs(Stats.Flags) do
		out(string.format("  %-12s %d", f, n))
	end
	out("  callers (return address of monster_resists): player hits / other")
	for addr, c in pairs(Stats.Callers) do
		out(string.format("    %08X  %d / %d", addr, c.Player, c.Other))
	end
	Game.ShowStatusText("DamageDiag: summary written to " .. LOG_FILE)
end

function events.LeaveMap()
	if D.Enabled and Stats.Calls > 0 then D.Report() end
end
