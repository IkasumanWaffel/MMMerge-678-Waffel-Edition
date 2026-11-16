--[[
	MMMWE_WildMagic.lua — wild magic: surges and backfires (15.11.26)

	A cast of the nine schools (spells 1-99) is rolled against its success chance in
	Data/Tables/SpellsExtra.txt (base + factor x skill, up to a cap; a curse lowers the cap).
	Scrolls, wands and the class abilities are left alone.

	Characters
	  Surge (on a success): chance = SURGE_BASE + the cast's failure chance / SURGE_RISK
	    + SURGE_LUCK per point of Luck bonus, halved while cursed. The spell is cast at
	    SURGE_LEVEL x the skill level (at least +SURGE_MIN), which raises its damage, healing,
	    duration and power; a spell its skill doesn't change (REFUND) gives half its spell
	    points back instead. Enchant Item has its own rolls and doesn't surge.
	  Backfire (on a failure): BACKFIRE_SKILL % of the failures from a low skill and
	    BACKFIRE_CURSE % of those the curse caused (the roll would have passed without it),
	    -1 % per point of Luck bonus. One backfire in RANDOM_SHARE rolls on the wild surge
	    table (playerTable), the others by the school (tier = the spell's circle, 1-4):
	      Fire, Air, Water, Earth, Body   damage of the element, tier x 5 + 1d10
	                                      (Body at tier 1-3 also weakens)
	      Spirit                          cursed for tier x 30 minutes
	      Mind                            afraid (insane at tier 4) for tier x 30 minutes
	      Light                           half the spell's cost drained again
	      Dark                            Dark damage and -10 Luck for tier x 30 minutes
	    Out of Hardcore mode a backfire leaves at least 1 HP; in Hardcore mode it can kill.
	  Even a Grandmaster can fail while cursed, and then backfire.

	Monsters (MMExt's MonsterCastSpell)
	  The same table with the monster's spell skill; the failure chance is halved and Fear
	  plays the part of a curse. A failed spell isn't cast; a surge casts it at the higher
	  skill; a backfire hurts or hinders the caster (monsterBackfire, monsterTable).
	  Damage a monster does to itself is credited to the party.
--]]

local MF = Merge.Functions
local Tx = MF.Text
local floor, ceil, max, min, random, sqrt = math.floor, math.ceil, math.max, math.min, math.random, math.sqrt
local C, D = const.Condition, const.Damage
local MB = const.MonsterBuff

local W = {
	SURGE_BASE = 2, SURGE_RISK = 5, SURGE_LUCK = 0.2, SURGE_LEVEL = 1.5, SURGE_MIN = 3,
	BACKFIRE_SKILL = 25, BACKFIRE_CURSE = 50, BACKFIRE_LUCK = 1,
	RANDOM_SHARE = 3,                  -- 1 in 3 backfires roll on the wild surge table
	DMG_TIER = 5, DMG_DIE = 10,        -- tier x 5 + 1d10
	COND_TIME = 30,                    -- minutes per tier
	DARK_LUCK = -10,
	MONSTER_FAIL = 0.5,                -- monsters fail half as often
	MONSTER_DMG_TIER = 8,              -- tier x 8 + skill x 2 + 1d10
	MONSTER_BUFF_TIME = 3,             -- minutes per tier
	MESSAGE_RANGE = 5000,              -- monster messages within this distance of the party
}
MF.WildMagicSettings = W

-- spells whose skill level doesn't change them: a surge refunds half the cost instead
local REFUND = {[23] = true, [31] = true, [33] = true, [40] = true, [42] = true, [49] = true,
	[53] = true, [55] = true, [57] = true, [61] = true, [64] = true, [67] = true, [72] = true,
	[74] = true, [88] = true}
local NO_SURGE = {[30] = true}     -- Enchant Item (MMMWE_EnchantItem.lua rolls its own)

local SCHOOL_DAMAGE = {D.Fire, D.Air, D.Water, D.Earth, D.Spirit, D.Mind, D.Body, D.Light, D.Dark}

local function school(spell) return ceil(spell / 11) end      -- 1 Fire ... 9 Dark
local function tier(spell)
	local n = (spell - 1) % 11 + 1
	return n <= 4 and 1 or n <= 7 and 2 or n <= 10 and 3 or 4
end

local function luck(pl) return MF.LuckBonus and MF.LuckBonus(pl) or 0 end
local function hardcore() return vars and vars.HardCoreMode == 1 end
local function roll(pct) return pct > 0 and random() * 100 < pct end

local function store()
	vars.MMMWE_WildMagic = vars.MMMWE_WildMagic or {Timed = {}}
	return vars.MMMWE_WildMagic
end

-- success chance of a cast from SpellsExtra.txt; cursed: under the curse cap
local function tableChance(spell, mastery, level, cursed)
	local SE = Merge.Tables and Merge.Tables.SpellsExtra and Merge.Tables.SpellsExtra[spell]
	if not SE then return 100 end
	mastery = max(1, min(4, mastery))
	local c = (SE.ChanceBase[mastery] or 100) + (SE.ChanceFactor[mastery] or 0) * level
	local cap = cursed and (SE.ChanceCursed[mastery] or 50) or (SE.ChanceMax[mastery] or 100)
	return min(c, cap)
end

local function say(fmt, ...)
	Game.ShowStatusText(string.format(fmt, ...))
end

---------------------------------------------------------------------------
-- characters: timed effects
---------------------------------------------------------------------------

-- a condition that wears off after the given minutes (if nothing else set it again)
local function timedCondition(pl, cond, minutes)
	if pl.Conditions[cond] ~= 0 then return end
	pl.Conditions[cond] = Game.Time
	local s = store()
	s.Timed[#s.Timed + 1] = {pi = pl:GetIndex(), c = cond, set = pl.Conditions[cond],
		till = Game.Time + minutes * const.Minute}
end

local function darkDrain(pl, minutes)
	local s = store()
	s.Dark = s.Dark or {}
	s.Dark[pl:GetIndex()] = Game.Time + minutes * const.Minute
end

local nextCheck = 0
function events.Tick()
	if not vars or not vars.MMMWE_WildMagic or Game.Time < nextCheck then return end
	nextCheck = Game.Time + const.Minute
	local s = vars.MMMWE_WildMagic
	for i = #s.Timed, 1, -1 do
		local e = s.Timed[i]
		if Game.Time >= e.till then
			local pl = Party.PlayersArray[e.pi]
			if pl and pl.Conditions[e.c] == e.set then pl.Conditions[e.c] = 0 end
			table.remove(s.Timed, i)
		end
	end
	if s.Dark then
		for pi, till in pairs(s.Dark) do
			if Game.Time >= till then s.Dark[pi] = nil end
		end
	end
end

function events.CalcStatBonusByItems(t)
	if t.Stat ~= const.Stats.Luck or not t.Player or not vars or not vars.MMMWE_WildMagic then return end
	local d = vars.MMMWE_WildMagic.Dark
	local till = d and d[t.Player:GetIndex()]
	if till and Game.Time < till then t.Result = t.Result + W.DARK_LUCK end
end

-- damage of an element; out of Hardcore mode it leaves at least 1 HP
local function hurt(pl, dmg, kind)
	if dmg <= 0 or pl.Conditions[C.Dead] ~= 0 or pl.Conditions[C.Eradicated] ~= 0 then return 0 end
	if not hardcore() then
		dmg = min(dmg, pl.HP - 1)       -- resistances can only lower it
		if dmg <= 0 then return 0 end
	end
	local before = pl.HP
	pl:DoDamage(dmg, kind)
	return max(0, before - pl.HP)       -- what was lost after resistances
end

local function backfireDamage(tr)
	return tr * W.DMG_TIER + random(1, W.DMG_DIE)
end

---------------------------------------------------------------------------
-- characters: the wild surge table
---------------------------------------------------------------------------

local function nearbyMonsterId()
	local ids = {}
	for i = 0, Map.Monsters.count - 1 do
		local m = Map.Monsters[i]
		if m.HP > 0 and m.Hostile and m.AIState ~= const.AIState.Removed then ids[#ids + 1] = m.Id end
	end
	return #ids > 0 and ids[random(#ids)]
end

local function fireworks(pl)
	say(Tx"Sparks and colours burst from %s's hands", pl.Name)
end

local playerTable = {
	{w = 3, f = function(pl, spell, tr)        -- the spell rebounds on another member
		local others = {}
		for _, p in Party do
			if p ~= pl and p:IsConscious() then others[#others + 1] = p end
		end
		local target = #others > 0 and others[random(#others)] or pl
		local lost = hurt(target, backfireDamage(tr), SCHOOL_DAMAGE[school(spell)])
		say(Tx"%s's spell rebounds on %s! (%d damage)", pl.Name, target.Name, lost)
	end},
	{w = 2, f = function(pl, spell, tr)
		timedCondition(pl, C.Drunk, tr * W.COND_TIME)
		say(Tx"%s feels strangely tipsy", pl.Name)
	end},
	{w = 2, f = function(pl, spell, tr)
		timedCondition(pl, C.Asleep, tr * W.COND_TIME)
		say(Tx"%s falls into a magical slumber", pl.Name)
	end},
	{w = 1, f = function(pl)
		pl.AgeBonus = pl.AgeBonus + 1
		say(Tx"%s ages a year in an instant", pl.Name)
	end},
	{w = 2, f = function(pl, spell, tr)
		local amount = random(1, 50 * tr)
		if random(2) == 1 then
			Party.Gold = Party.Gold + amount
			say(Tx"Gold coins rain on the party! (+%d)", amount)
		else
			amount = min(amount, Party.Gold)
			Party.Gold = Party.Gold - amount
			say(Tx"Some of the party's gold vanishes! (-%d)", amount)
		end
	end},
	{w = 1, f = function(pl)
		pl.SP = max(pl.SP, pl:GetFullSP())
		say(Tx"%s's spell points well up", pl.Name)
	end},
	{w = 2, f = fireworks},
	{w = 1, f = function(pl, spell, tr)
		local id = tr >= 2 and nearbyMonsterId()
		if not id then return fireworks(pl) end
		local a = Party.Direction * math.pi / 1024
		local mon = SummonMonster(id, Party.X + floor(math.cos(a) * 300), Party.Y + floor(math.sin(a) * 300), Party.Z + 50, true)
		if mon then mon.Hostile = true end
		say(Tx"%s's spell tears open a rift!", pl.Name)
	end},
	{w = 1, f = function(pl, spell, tr)
		local lost = min(Party.Food, random(1, tr + 1))
		Party.Food = Party.Food - lost
		say(Tx"Some of the party's food turns to dust")
	end},
}

local function pick(tbl)
	local sum = 0
	for _, e in ipairs(tbl) do sum = sum + e.w end
	local r = random() * sum
	for _, e in ipairs(tbl) do
		r = r - e.w
		if r < 0 then return e end
	end
	return tbl[#tbl]
end

---------------------------------------------------------------------------
-- characters: backfire and surge
---------------------------------------------------------------------------

local function playerBackfire(pl, spell, mastery)
	local tr, sc = tier(spell), school(spell)
	pl:ShowFaceAnimation(const.FaceAnimation.SpellFailed)
	if random(W.RANDOM_SHARE) == 1 then
		say(Tx"Wild magic! %s loses control of the spell", pl.Name)
		pick(playerTable).f(pl, spell, tr)
		return
	end
	local minutes = tr * W.COND_TIME
	if sc <= 4 or sc == 7 then
		local lost = hurt(pl, backfireDamage(tr), SCHOOL_DAMAGE[sc])
		if sc == 7 then timedCondition(pl, tr >= 4 and C.Poison1 or C.Weak, minutes) end
		say(Tx"%s's spell backfires! (%d damage)", pl.Name, lost)
	elseif sc == 5 then
		timedCondition(pl, C.Cursed, minutes)
		say(Tx"%s's spell backfires! (cursed for %d minutes)", pl.Name, minutes)
	elseif sc == 6 then
		timedCondition(pl, tr >= 4 and C.Insane or C.Afraid, minutes)
		say(Tx"%s's spell backfires! (%s for %d minutes)", pl.Name, tr >= 4 and Tx"insane" or Tx"afraid", minutes)
	elseif sc == 8 then
		local cost = Game.Spells[spell].SpellPoints[max(1, mastery)] or 0
		local drained = min(pl.SP, ceil(cost / 2))
		pl.SP = pl.SP - drained
		say(Tx"%s's spell backfires! (-%d spell points)", pl.Name, drained)
	else
		local lost = hurt(pl, backfireDamage(tr), D.Dark)
		darkDrain(pl, minutes)
		say(Tx"%s's spell backfires! (%d damage, -%d Luck for %d minutes)", pl.Name, lost, -W.DARK_LUCK, minutes)
	end
end

-- after SpellsExtra.lua's and ExtraEvents.lua's handlers (this file loads later)
function events.SpellFailCheck(t)
	local spell, pl = t.Spell, t.Player
	if t.Type ~= 0 or not pl or spell < 1 or spell > 99 or (t.Chance or 0) <= 0 then return end
	local chance = min(100, t.Chance)
	if t.Roll <= chance then
		if NO_SURGE[spell] then return end
		local c = W.SURGE_BASE + (100 - chance) / W.SURGE_RISK + W.SURGE_LUCK * luck(pl)
		if t.Cursed then c = c / 2 end
		if not roll(c) then return end
		if REFUND[spell] then
			local cost = Game.Spells[spell].SpellPoints[max(1, t.Mastery)] or 0
			pl.SP = pl.SP + floor(cost / 2)
			say(Tx"%s's spell surges with wild magic! (+%d spell points back)", pl.Name, floor(cost / 2))
		else
			local was = t.Level
			t.Level = max(t.Level + W.SURGE_MIN, floor(t.Level * W.SURGE_LEVEL))
			say(Tx"%s's spell surges with wild magic! (skill %d -> %d)", pl.Name, was, t.Level)
		end
		pl:ShowFaceAnimation(const.FaceAnimation.LearnSpell)
		return
	end
	-- a failure: by the curse when the roll would have passed without it
	local byCurse = t.Cursed and t.Roll <= tableChance(spell, t.Mastery, t.Level, false)
	local c = (byCurse and W.BACKFIRE_CURSE or W.BACKFIRE_SKILL) - W.BACKFIRE_LUCK * luck(pl)
	if roll(c) then playerBackfire(pl, spell, t.Mastery) end
end

---------------------------------------------------------------------------
-- monsters
---------------------------------------------------------------------------

local function monName(mon)
	local ok, n = pcall(function() return Game.MonstersTxt[mon.Id].Name end)
	return ok and n or "?"
end

local function nearParty(mon)
	local dx, dy, dz = mon.X - Party.X, mon.Y - Party.Y, mon.Z - Party.Z
	return sqrt(dx*dx + dy*dy + dz*dz) <= W.MESSAGE_RANGE
end

local function monSay(mon, fmt, ...)
	if nearParty(mon) then say(fmt, monName(mon), ...) end
end

local function buffed(mon, b)
	local sb = b and mon.SpellBuffs[b]
	return sb and sb.ExpireTime > Game.Time
end

local function setBuff(mon, b, minutes, power)
	if b and mon.SpellBuffs[b] then
		mon.SpellBuffs[b]:Set(Game.Time + minutes * const.Minute, 1, power or 1)
	end
end

local function creditIndex()
	local pl = Party[0]
	return pl and pl:GetIndex() or 0
end

local function monsterHurt(mi, dmg, kind)
	if MF.QueueElementalHit then MF.QueueElementalHit(creditIndex(), mi, dmg, kind) end
end

local function monsterDamage(spell, skill)
	return tier(spell) * W.MONSTER_DMG_TIER + skill * 2 + random(1, W.DMG_DIE)
end

local monsterTable = {
	{w = 2, f = function(mon, mi, spell)       -- the spell burns out for good
		if mon.Spell == spell then mon.Spell = 0 elseif mon.Spell2 == spell then mon.Spell2 = 0 end
		monSay(mon, Tx"%s burns out its magic")
	end},
	{w = 2, f = function(mon, mi, spell, skill)  -- the spell rebounds on everyone around
		local dmg, kind = monsterDamage(spell, skill), SCHOOL_DAMAGE[school(spell)]
		for i = 0, Map.Monsters.count - 1 do
			local m = Map.Monsters[i]
			if m.HP > 0 and m.AIState ~= const.AIState.Removed then
				local dx, dy, dz = m.X - mon.X, m.Y - mon.Y, m.Z - mon.Z
				if sqrt(dx*dx + dy*dy + dz*dz) <= 600 then monsterHurt(i, dmg, kind) end
			end
		end
		monSay(mon, Tx"%s's spell rebounds on its allies")
	end},
	{w = 2, f = function(mon, mi, spell)
		setBuff(mon, MB.Wander, tier(spell) * W.MONSTER_BUFF_TIME)
		monSay(mon, Tx"%s wanders off in a daze")
	end},
	{w = 1, f = function(mon, mi, spell)       -- good for the monster
		setBuff(mon, MB.Haste, tier(spell) * W.MONSTER_BUFF_TIME)
		monSay(mon, Tx"%s draws strength from the wild magic")
	end},
	{w = 1, f = function(mon)                  -- good for the monster
		mon.HP = min(mon.FullHP, mon.HP + ceil(mon.FullHP / 4))
		monSay(mon, Tx"%s is healed by the wild magic")
	end},
	{w = 2, f = function(mon)
		monSay(mon, Tx"%s's spell bursts into harmless sparks")
	end},
}

local function monsterBackfire(mon, mi, spell, skill)
	if random(W.RANDOM_SHARE) == 1 then
		pick(monsterTable).f(mon, mi, spell, skill)
		return
	end
	monSay(mon, Tx"%s's spell backfires!")
	local tr, sc = tier(spell), school(spell)
	local minutes = tr * W.MONSTER_BUFF_TIME
	if sc == 5 then
		setBuff(mon, MB.Slow, minutes, 2)
	elseif sc == 6 then
		setBuff(mon, tr >= 4 and MB.Berserk or MB.Fear, minutes)
	elseif sc == 8 then
		setBuff(mon, MB.Paralyze, tr, 1)
	else
		monsterHurt(mi, monsterDamage(spell, skill), SCHOOL_DAMAGE[sc])
		if sc == 9 then setBuff(mon, MB.DamageHalved, minutes) end
	end
end

function events.MonsterCastSpell(t)
	local spell, mon, mi = t.Spell, t.Monster, t.MonsterIndex
	if t.Handled or not mon or not spell or spell < 1 or spell > 99 or not t.Skill then return end
	local skill, mastery = SplitSkill(t.Skill)
	if skill <= 0 then return end
	local feared = buffed(mon, MB.Fear)
	local chance = tableChance(spell, mastery, skill, feared)
	chance = 100 - (100 - chance) * W.MONSTER_FAIL
	local r = random(1, 100)
	if r <= chance then
		if NO_SURGE[spell] or REFUND[spell] then return end
		if roll(W.SURGE_BASE + (100 - chance) / W.SURGE_RISK) then
			local surged = max(skill + W.SURGE_MIN, floor(skill * W.SURGE_LEVEL))
			monSay(mon, Tx"%s's spell surges with wild magic! (skill %d -> %d)", skill, surged)
			t.CallDefault(nil, JoinSkill(surged, mastery))
		end
		return
	end
	t.Handled = true          -- the spell isn't cast
	local free = 100 - (100 - tableChance(spell, mastery, skill, false)) * W.MONSTER_FAIL
	local byFear = feared and r <= free
	if roll(byFear and W.BACKFIRE_CURSE or W.BACKFIRE_SKILL) then
		monsterBackfire(mon, mi, spell, skill)
	else
		monSay(mon, Tx"%s's spell fizzles")
	end
end
