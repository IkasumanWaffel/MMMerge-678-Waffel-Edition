--[[
	MMMWE_StaggerPoise.lua — monsters' poise: no stun-lock by fast attacks (19.11.26)

	Every hit that leaves a monster alive staggers it (the game's "monster got hit" routine,
	0x4032DD), unless it is already staggered or in the middle of an attack: it plays its
	"got hit" animation and loses what it was doing. There is no chance in it, so attacks with
	a short recovery (blasters above all) can keep a monster staggered for good.

	Poise: after a stagger the monster can't be staggered again for a while. The hits still
	land and do their damage; only the stagger is skipped.
	  window = BASE + Armor Class x PER_AC seconds, at most MAX
	  a stagger that comes within CHAIN seconds after the previous window has run out is part
	  of a chain: each one in a chain makes the window CHAIN_MUL times longer, up to CHAIN_CAP
	  times; a pause of CHAIN seconds without a stagger ends the chain
	e.g. Armor Class 20: 1.25 s, then 1.9 s, 2.8 s, 4.2 s, 5 s; Armor Class 100: 3.25 s,
	then 4.9 s, 7.3 s, 11 s, 13 s. A hit that comes while the monster is attacking or already
	staggered doesn't stagger it (the game's rule) and doesn't start a window either.
	Seconds are real-time seconds of the game's clock (they stop while the game is paused).

	The monster ability Juggernaut (MMMWE_MonsterAbilities.lua) skips every stagger by hits.
	Forced staggers (the Stun spell) and the weapons' stun and paralysis (Mace, Staff, Unarmed,
	the shield bash) have their own rules and are left alone.
	ModSettings: Scripts.StaggerPoise 0 turns poise off (Juggernaut still works).
--]]

local MF, MM = Merge.Functions, Merge.ModSettings

local P = {
	BASE      = 0.75,   -- seconds
	PER_AC    = 0.025,  -- seconds per point of Armor Class
	MAX       = 3.5,    -- the longest first window
	CHAIN     = 3,      -- seconds: a stagger within this after the window is part of a chain
	CHAIN_MUL = 1.5,
	CHAIN_CAP = 4,      -- the window grows at most this many times in a chain
}
MF.StaggerPoise = P

local poiseOn = not (MM.Scripts and MM.Scripts.StaggerPoise ~= nil
	and not MF.GtSettingNum(MM.Scripts.StaggerPoise, 0))

local Poise = {}   -- [monster index] = {Id, Until, Mul}
-- AI states the game doesn't stagger: attacking (2, 3, 12, 13, 18) and staggered (8)
local BUSY = {[2] = true, [3] = true, [8] = true, [12] = true, [13] = true, [18] = true}

function events.AfterLoadMap()
	Poise = {}
end

-- true: the stagger is skipped
local function noStagger(i)
	if i < 0 or i >= Map.Monsters.count then return false end
	if MF.MonsterIsJuggernaut and MF.MonsterIsJuggernaut(i) then return true end
	if not poiseOn then return false end
	local m = Map.Monsters[i]
	if BUSY[m.AIState] then return false end   -- the game won't stagger it anyway
	local now = Game.Time
	local s = Poise[i]
	if s and s.Id ~= m.Id then s = nil end
	if s and now < s.Until then return true end
	local mul = 1
	if s and now - s.Until < P.CHAIN * const.RTSecond then
		mul = math.min(s.Mul * P.CHAIN_MUL, P.CHAIN_CAP)
	end
	local w = math.min(P.MAX, P.BASE + math.max(0, m.ArmorClass) * P.PER_AC) * mul
	Poise[i] = {Id = m.Id, Until = now + math.floor(w * const.RTSecond), Mul = mul}
	return false
end

-- 0x40334B: in the got-hit routine, after the monster has turned hostile and noticed the
-- attacker, reached only when the stagger isn't forced ([ebp-8] the monster's index); the
-- stagger runs from here to 0x4033EA, the routine's end
if mem.u1[0x40334B] == 0x66 and mem.u1[0x40334C] == 0x8B then
	mem.autohook(0x40334B, function(d)
		local ok, skip = pcall(noStagger, mem.i4[d.ebp - 8])
		if ok and skip then
			d:push(0x4033EA)
			return true
		end
	end)
else
	MF.LogWarning("[StaggerPoise] the stagger routine at 0x40334B wasn't found")
end
