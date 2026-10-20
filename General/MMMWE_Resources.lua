--[[
	MMMWE_Resources.lua — class resources and class abilities (framework + Barbarian Rage)

	Design: "Waffel Edition design - class resources and abilities (v2)".

	Resource: for a class family with a resource of its own, the character's spell points ARE
	that resource (the same value, so saves, the portrait bar and the Stats screen keep
	working). The script keeps the real value (vars.MMMWE_Resources) and writes it into the
	spell points every tick, so the game's own spell point refill, potions and resting don't
	change it. Maximum: GetFullSP returns the resource maximum.

	Abilities: spells of a spellbook page the family can never learn (route 1). For a member
	of the family the page tab is shown, the ability spots are marked as learned and, while
	the spellbook is open, their names, descriptions and cost line are swapped. A cast of such
	a spell by a family member is taken over at 0x42609E (cast queue processing): the
	resource is checked and spent, the ability runs and the recovery is set; the game's own
	spell is skipped. Monsters, scrolls, wands and other classes keep the real spell.

	Barbarian family (Barbarian, Berserker, Warmonger, light / dark / third-stage variants) — Rage:
	  0..100, +100 x damage taken / max HP per hit (at most 40), +2 per melee hit landed;
	  after RAGE.IdleTime without being hit it drains RAGE.DrainPerMinute per game minute.
	  Passive: +1% melee damage per 5 Rage; at 50+ Rage -10% of the items' Armor Class
	  (Trolls: +5% physical resistance instead).
	  Fire page: Rage Strike (Fire Bolt spot), War Cry (Haste spot, Berserker+),
	  Berserk (Immolation spot, Warmonger+), Troll's Blood (Fire Resistance spot, Trolls,
	  instead of War Cry).

	Console: Merge.Functions.ResourceInfo(player)
--]]

local MF, MT = Merge.Functions, Merge.Tables
local u1, u2, u4, i4 = mem.u1, mem.u2, mem.u4, mem.i4

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local ENABLED = true
local DEBUG   = false   -- status line / log messages about ability casts (testing)

local RAGE = {
	Max             = 100,
	PerHitTakenMax  = 40,          -- gain from one hit taken
	PerHitLanded    = 2,
	IdleTime        = 10 * const.Minute,   -- game time without being hit before Rage drains
	DrainPerMinute  = 2,           -- Rage per game minute
	DamagePer5      = 0.01,        -- +1% melee damage per 5 Rage
	RecklessAt      = 50,          -- Rage from which the AC penalty / Troll hide applies
	RecklessAC      = 0.10,        -- share of the items' Armor Class lost
	TrollHide       = 0.05,        -- Trolls: physical damage taken -5% instead
	MeleeRange      = 400,         -- reach of Rage Strike (+ the monster's body radius)
}

-- spell spots the abilities use, the page they are on (0 = Fire), and when they unlock
local ABILITIES = {
	RageStrike = {Spell = 2, Stage = 0, Cost = 15, NotTroll = false,
		Name = "Rage Strike",
		Desc = "A furious blow at the target in melee reach: +50% damage, and 10% more often a critical blow. Use it as the attack spell to strike with it whenever there is enough Rage; without enough Rage it is a normal attack.",
		Lines = {"15 Rage", "", "", ""},
		Icon = {"sbmc04", "sbms04"},},
	WarCry = {Spell = 5, Stage = 1, Cost = 40, NotTroll = true,
		Name = "War Cry",
		Desc = "A terrifying roar. Monsters around may flee in fear (resisted by Mind resistance), and the party deals +10% melee damage for a while.",
		Lines = {"40 Rage (Berserker)", "", "", ""},
		Icon = {"sbmc08", "sbms08"},},
	TrollsBlood = {Spell = 3, Stage = 1, Cost = 40, TrollOnly = true,
		Name = "Troll's Blood",
		Desc = "The troll's blood boils and mends the wounds: heals 20% of maximum Hit Points over a short time.",
		Lines = {"40 Rage (Troll, Berserker)", "", "", ""},
		Icon = {"sbbc05", "sbbs05"},},
	Berserk = {Spell = 8, Stage = 2, Cost = 70,
		Name = "Berserk",
		Desc = "A frenzy: 20% faster attacks and immunity to fear, sleep and paralysis for a while, but 15% more damage taken.",
		Lines = {"70 Rage (Warmonger)", "", "", ""},
		Icon = {"sbmc07", "sbms07"},},
}

local DUR = {
	WarCryFear  = 2 * const.Minute,
	WarCryParty = 5 * const.Minute,
	Berserk     = 5 * const.Minute,
	TrollsBlood = 2 * const.Minute,
}
local WAR_CRY_RADIUS = 2000
local WAR_CRY_BONUS  = 0.10
local BERSERK_SPEED  = 0.80
local BERSERK_TAKEN  = 1.15
local TROLLS_BLOOD   = 0.20

-- class families: Class Extra.txt "Kind" of the family's first class
local FAMILIES = {
	[12] = {Name = "Barbarian", Resource = "Rage", Page = 0,
		Abilities = {"RageStrike", "WarCry", "TrollsBlood", "Berserk"}},
}

local TROLL_RACES = {[15] = true, [16] = true, [17] = true, [18] = true}

MF.ResourceSettings = {Rage = RAGE, Abilities = ABILITIES, Durations = DUR, Families = FAMILIES}

-- colours of the resource numbers over the portraits (MMMWE_HPSPDisplay.lua, Windows BGR)
MF.ResourceColors = {Rage = 0x3050FF}
-- the Stats screen's "Spell Points" line (GlobalTxt 212) shows the resource name
local SP_LABEL_TXT = 212

---------------------------------------------------------------------------

if not ENABLED then return end

local function log(fmt, ...) if MF.LogInfo then MF.LogInfo("[Resources] " .. fmt, ...) end end
local function debugMsg(fmt, ...)
	local text = string.format(fmt, ...)
	log("%s", text)
	print("[Resources] " .. text)
	Game.ShowStatusText(text, 4)
end

-- family kind and promotion stage (0..3) of a class, light / dark / third-stage variants
-- included (they have Kind 0 in Class Extra.txt and are found through Promotions.txt)
local familyCache = {}
local function classFamily(class)
	local c = familyCache[class]
	if c then return c[1], c[2] end
	local kind, stage, cur, guard = 0, 0, class, 0
	local ce = Game.ClassesExtra
	while guard < 8 do
		guard = guard + 1
		local e = ce and ce[cur]
		if e and e.Kind and e.Kind ~= 0 then
			kind = e.Kind
			stage = stage + (e.Step or 0)
			break
		end
		local inv = MT.ClassPromotionsInv and MT.ClassPromotionsInv[cur]
		if not inv or not inv[1] then break end
		cur = inv[1]
		stage = stage + 1
	end
	familyCache[class] = {kind, stage}
	return kind, stage
end
MF.ClassFamily = classFamily

local function familyOf(pl)
	local kind, stage = classFamily(pl.Class)
	return FAMILIES[kind], stage, kind
end

local function isTroll(pl)
	local r = GetCharRace and GetCharRace(pl)
	return r and TROLL_RACES[r] or false
end

local function playerIndex(pl)
	return pl:GetIndex()
end

local function playerFromPtr(ptr)
	local arr = Party.PlayersArray
	local i = (ptr - arr["?ptr"]) / arr[0]["?size"]
	if i >= 0 and i < arr.count and i == math.floor(i) then return arr[i], i end
end

---------------------------------------------------------------------------
-- resource state (saved)
---------------------------------------------------------------------------

local function store()
	vars.MMMWE_Resources = vars.MMMWE_Resources or {}
	return vars.MMMWE_Resources
end

local function state(pi)
	local s = store()
	local e = s[pi]
	if not e then
		e = {R = 0, LastHit = 0, Last = Game.Time}
		s[pi] = e
	end
	return e
end

local function usesRage(pl)
	local fam = familyOf(pl)
	return fam and fam.Resource == "Rage"
end

function MF.GetResource(pl)
	if not usesRage(pl) then return nil end
	return state(playerIndex(pl)).R, RAGE.Max, "Rage"
end

local function addRage(pl, v)
	local e = state(playerIndex(pl))
	e.R = math.max(0, math.min(RAGE.Max, e.R + v))
	pl.SP = math.floor(e.R)
end

-- the resource maximum instead of the spell points
mem.hookfunction(0x48DA18, 1, 0, function(d, def, this)
	local pl = playerFromPtr(this)
	if pl and usesRage(pl) then return RAGE.Max end
	return def(this)
end)

---------------------------------------------------------------------------
-- abilities: which spots, learned flags
---------------------------------------------------------------------------

-- ability key of spell `spell` for player `pl`, or nil
local function abilityOf(pl, spell)
	local fam, stage = familyOf(pl)
	if not fam then return end
	local troll = isTroll(pl)
	for _, key in ipairs(fam.Abilities) do
		local a = ABILITIES[key]
		if a.Spell == spell and stage >= a.Stage
				and not (a.TrollOnly and not troll) and not (a.NotTroll and troll) then
			return key, a
		end
	end
end
MF.ClassAbilityOf = abilityOf
function MF.IsClassAbility(pl, spell) return abilityOf(pl, spell) ~= nil end

local function pageOf(pl)
	local fam = familyOf(pl)
	return fam and fam.Page
end

-- mark the family's abilities as learned, the rest of its ability page as not learned
local function updateSpells(pl)
	local page = pageOf(pl)
	if not page then return end
	for spot = 1, 11 do
		local id = page * 11 + spot
		pl.Spells[id] = abilityOf(pl, id) ~= nil
	end
end

---------------------------------------------------------------------------
-- spellbook: tab, texts, cost line
---------------------------------------------------------------------------

-- Fire tab (cmp [edi+390h], bx / jz at 0x4124EA; tab button at 0x4124F8, next tab 0x412516)
mem.autohook(0x4124EA, function(d)
	local pl = playerFromPtr(d.edi)
	if pl and pl.Skills[const.Skills.Fire] == 0 and pageOf(pl) == 0 then
		d:push(0x4124F8)
		return true
	end
end)

local cstrCache = {}
local function cstr(s)
	local p = cstrCache[s]
	if p then return p end
	p = mem.StaticAlloc(#s + 1)
	mem.copy(p, s, #s)
	u1[p + #s] = 0
	cstrCache[s] = p
	return p
end

local SpellsTxtBase, SpellsTxtSize
local function spellsTxtPtr(id)
	if not SpellsTxtBase then
		SpellsTxtBase = Game.SpellsTxt[0]["?ptr"]
		SpellsTxtSize = Game.SpellsTxt[1]["?ptr"] - SpellsTxtBase
	end
	return SpellsTxtBase + id * SpellsTxtSize
end
local swapped = {}      -- [spell] = {name, short, desc, n, e, m, g} original pointers
local swappedFor        -- player the texts are swapped for
local costTxtSaved

local function restoreTexts()
	for spell, o in pairs(swapped) do
		local p = spellsTxtPtr(spell)
		for i = 0, 6 do u4[p + i * 4] = o[i + 1] end
	end
	swapped = {}
	swappedFor = nil
	if costTxtSaved then
		u4[Game.GlobalTxt["?ptr"] + 522 * 4] = costTxtSaved
		costTxtSaved = nil
	end
end

local function swapTexts(pl)
	if swappedFor == pl then return end
	restoreTexts()
	local page = pageOf(pl)
	if not page then return end
	for spot = 1, 11 do
		local id = page * 11 + spot
		local key, a = abilityOf(pl, id)
		if a then
			local p = spellsTxtPtr(id)
			local o = {}
			for i = 0, 6 do o[i + 1] = u4[p + i * 4] end
			swapped[id] = o
			u4[p] = cstr(a.Name)
			u4[p + 4] = cstr(a.Name)
			u4[p + 8] = cstr(a.Desc)
			for i = 1, 4 do u4[p + 8 + i * 4] = cstr(a.Lines[i] ~= "" and a.Lines[i] or " ") end
		end
	end
	local fam = familyOf(pl)
	costTxtSaved = u4[Game.GlobalTxt["?ptr"] + 522 * 4]
	u4[Game.GlobalTxt["?ptr"] + 522 * 4] = cstr(fam.Resource .. " cost")
	swappedFor = pl
end

-- name of a spell as the player sees it (quick slot names)
function MF.SpellDisplayName(pl, spell)
	local _, a = abilityOf(pl, spell)
	return a and a.Name or Game.SpellsTxt[spell].Name
end

-- Ability icons. The page's pictures are in two tables of 12 (index 1..11 = the spots):
-- 0x5179D8 the normal picture (SB..a), 0x5179A8 the selected one (SB..b); both are read by
-- init_spellbook_dialog (0x412414) and the page drawing, and unloaded at 0x412209 when the
-- book closes. Our pictures (MM7 sb?c / sb?s) are loaded and put in when the book is set up,
-- and the originals are put back before the game unloads them.
local ICON_A, ICON_B = 0x5179D8, 0x5179A8
local iconSaved = {}   -- [address] = {orig = original pointer, ours = our pointer}

local function bitmapPtr(name)
	local ok, idx = pcall(function() return Game.IconsLod:LoadBitmap(name) end)
	if not ok or not idx or idx < 0 then return end
	return Game.IconsLod.Bitmaps[idx]["?ptr"]
end

local function restoreIcons()
	for addr, e in pairs(iconSaved) do
		if u4[addr] == e.ours then u4[addr] = e.orig end
	end
	iconSaved = {}
end

local function swapIcons(pl)
	restoreIcons()
	local page = pageOf(pl)
	if not page or pl.SpellBookPage ~= page then return end
	for spot = 1, 11 do
		local _, a = abilityOf(pl, page * 11 + spot)
		if a and a.Icon then
			for k, base in ipairs{ICON_A, ICON_B} do
				local ptr = bitmapPtr(a.Icon[k])
				local addr = base + spot * 4
				log("icon %s for spot %d: %s, table entry %X", a.Icon[k], spot, tostring(ptr), u4[addr])
				if ptr and u4[addr] ~= 0 then
					iconSaved[addr] = {orig = u4[addr], ours = ptr}
					u4[addr] = ptr
				end
			end
		end
	end
end

mem.autohook(0x412414, function(d)
	-- the game's current_player (0x519350, 1-based), as init_spellbook_dialog uses it
	local i = u4[0x519350] - 1
	log("spellbook init for slot %d", i)
	if i >= 0 and i < Party.count then
		local ok, err = pcall(swapIcons, Party[i])
		if not ok then log("icons: %s", tostring(err)) end
	end
end)
-- The originals go back before the game unloads the page pictures. 0x412209 can't be
-- hooked itself (its loop jumps back to 0x41220C, inside the first 5 bytes), so its call
-- in the dialog removal (0x41B990, call 0x412209) is replaced.
mem.hookcall(0x41B990, 0, 0, function(d, def)
	restoreIcons()
	def()
end)

-- right-click description of a spell in the book: the ability texts (also kept by the tick)
mem.autohook(0x411F3A, function(d)
	local i = Game.CurrentPlayer
	if i >= 0 and i < Party.count and pageOf(Party[i]) then swapTexts(Party[i]) end
end)

-- cost line of the right-click description (word_4F4884 read with the page skill's mastery)
mem.autohook2(0x41216C, function(d)
	local i = Game.CurrentPlayer
	if i < 0 or i >= Party.count then return end
	local pl = Party[i]
	local page = pl.SpellBookPage
	local spot = u4[d.ebp + 8] + 1
	local _, a = abilityOf(pl, page * 11 + spot)
	if a then d.eax = a.Cost end
end)

---------------------------------------------------------------------------
-- casting
---------------------------------------------------------------------------

-- the game lets a character without the school's skill pick the ability
function events.CanPlayerCastSpell(t)
	local pl = playerFromPtr(t.PlayerPtr)
	if pl and abilityOf(pl, t.Spell) and t.Source ~= 4 then t.Result = true end
end

local Pending = {}     -- abilities carried out on the next tick
local Effects = {}     -- [pi] = {Berserk = time, TrollsBlood = {Until, PerMinute}}
local PartyEffects = {WarCry = 0}
local RageStrikeActive = false

local function monsterDistance(mon)
	local dx, dy, dz = mon.X - Party.X, mon.Y - Party.Y, mon.Z - Party.Z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function meleeTarget(targetRef)
	local mi
	if targetRef and targetRef % 8 == 3 then mi = math.floor(targetRef / 8) end
	if not mi then
		local ok, tg = pcall(function() return Game.Mouse:GetTarget() end)
		if ok and tg and tg.Kind == 3 then mi = tg.Index end
	end
	local function valid(i)
		local m = i and Map.Monsters[i]
		return m and m.HP > 0 and m.AIState ~= const.AIState.Removed
			and monsterDistance(m) <= RAGE.MeleeRange + (m.BodyRadius or 0)
	end
	if valid(mi) then return mi end
	local best, bd
	for i = 0, Map.Monsters.count - 1 do
		local m = Map.Monsters[i]
		if m.HP > 0 and m.Hostile then
			local dist = monsterDistance(m)
			if dist <= RAGE.MeleeRange + (m.BodyRadius or 0) and (not bd or dist < bd) then best, bd = i, dist end
		end
	end
	return best
end

local function failCast(pl, text)
	Game.ShowStatusText(text)
	Game.PlaySound(142)
end

-- returns true if the cast was taken over
local function castAbility(pl, pi, spell, targetRef)
	local key, a = abilityOf(pl, spell)
	if not a then return false end
	local e = state(pi)
	if DEBUG then debugMsg("%s uses %s (Rage %d, cost %d)", pl.Name, a.Name, e.R, a.Cost) end
	if e.R < a.Cost then
		if key == "RageStrike" then
			DoGameAction(23, 0, 0)        -- a normal attack, as with spell points
		else
			failCast(pl, string.format("Not enough Rage (%d needed)", a.Cost))
		end
		return true
	end
	if key == "RageStrike" then
		local mi = meleeTarget(targetRef)
		if not mi then
			failCast(pl, "No enemy in reach")
			return true
		end
		Pending[#Pending + 1] = {Kind = key, pi = pi, mi = mi}
		pl:SetRecoveryDelay(pl:GetAttackDelay(false))
	elseif key == "WarCry" then
		Pending[#Pending + 1] = {Kind = key, pi = pi}
		pl:SetRecoveryDelay(100)
	elseif key == "Berserk" then
		Effects[pi] = Effects[pi] or {}
		Effects[pi].Berserk = Game.Time + DUR.Berserk
		Game.ShowStatusText(string.format("%s goes berserk!", pl.Name))
		pl:SetRecoveryDelay(60)
	elseif key == "TrollsBlood" then
		Effects[pi] = Effects[pi] or {}
		Effects[pi].TrollsBlood = {Until = Game.Time + DUR.TrollsBlood,
			PerTick = TROLLS_BLOOD * pl:GetFullHP() / DUR.TrollsBlood}
		Game.ShowStatusText(string.format("%s's troll blood boils", pl.Name))
		pl:SetRecoveryDelay(60)
	end
	addRage(pl, -a.Cost)
	return true
end

-- caster of a queued spell: the field holds the caster's Party.PlayersArray index (tested:
-- first member 0, second member 36), i.e. Party.PlayersIndexes[slot]
local function casterOf(v, spell)
	for s = 0, Party.count - 1 do
		if Party.PlayersIndexes[s] == v then return Party[s] end
	end
end

-- cast queue processing (the slot being processed: 0x51D820 + [ebp-0C8h] x 14h)
mem.autohook(0x42609E, function(d)
	local slot = 0x51D820 + u4[d.ebp - 0xC8] * 0x14
	local spell = u2[slot]
	if spell <= 0 or spell > 132 then return end
	if bit.band(u1[slot + 8], 1) == 1 then return end          -- spell scroll
	if u2[slot + 10] > 0 then return end                         -- skill set: wand, item, NPC
	local pl = casterOf(u2[slot + 2], spell)
	if DEBUG then
		debugMsg("cast queue: spell %d, caster field %d -> %s", spell, u2[slot + 2], pl and pl.Name or "?")
	end
	if not pl or not abilityOf(pl, spell) then return end
	local pi = playerIndex(pl)
	local ok, res = pcall(castAbility, pl, pi, spell, u2[slot + 0xC])
	if not ok then
		log("ability error: %s", tostring(res))
		return
	end
	if res then
		u2[slot] = 0
		d:push(0x42D45D)
		return true
	end
end)

---------------------------------------------------------------------------
-- tick: resource sync, drain, effects, pending abilities
---------------------------------------------------------------------------

-- Portrait bar: the spell point bar (texture in [ebp-18h] of the bars routine, 0x41B165 is
-- the start of each character's SP bar) is drawn with RESOURCE_BAR[resource] instead
local RESOURCE_BAR = {Rage = "manar"}
local barOrig, barOurs = nil, {}
mem.autohook(0x41B165, function(d)
	local cur = u4[d.ebp - 0x18]
	local isOurs = false
	for _, p in pairs(barOurs) do if p == cur then isOurs = true end end
	if not isOurs then barOrig = cur end
	local slot = u4[d.ebp - 4]
	local want = barOrig
	if slot < Party.count then
		local fam = familyOf(Party[slot])
		local name = fam and RESOURCE_BAR[fam.Resource]
		if name then
			barOurs[name] = barOurs[name] or bitmapPtr(name)
			want = barOurs[name] or barOrig
		end
	end
	if want and want ~= cur then u4[d.ebp - 0x18] = want end
end)

-- Stats screen label: the resource name while a character with a resource is shown
local spLabelSaved, spLabelNow
local function updateStatsLabel()
	local want
	if Game.CurrentScreen == const.Screens.Inventory and Game.CurrentPlayer >= 0 and Game.CurrentPlayer < Party.count then
		local fam = familyOf(Party[Game.CurrentPlayer])
		want = fam and fam.Resource
	end
	if want == spLabelNow then return end
	local addr = Game.GlobalTxt["?ptr"] + SP_LABEL_TXT * 4
	if not spLabelSaved then spLabelSaved = u4[addr] end
	u4[addr] = want and cstr(want) or spLabelSaved
	spLabelNow = want
end

local RiposteVec = mem.StaticAlloc(12)
local nextSpellsUpdate = 0

function events.Tick()
	local now = Game.Time

	-- pending abilities
	if #Pending > 0 then
		local q = Pending
		Pending = {}
		for _, r in ipairs(q) do
			local pl = Party.PlayersArray[r.pi]
			if r.Kind == "RageStrike" then
				local mon = Map.Monsters[r.mi]
				if pl and mon and mon.HP > 0 then
					Game.ShowStatusText(string.format("%s: Rage Strike!", pl.Name), 2)
					RageStrikeActive = true
					local ok, err = pcall(mem.call, 0x436E26, 2, r.pi * 8 + 4, r.mi, RiposteVec)
					RageStrikeActive = false
					if not ok then log("Rage Strike failed: %s", tostring(err)) end
				end
			elseif r.Kind == "WarCry" and pl then
				local feared = 0
				local power = (pl.LevelBase or 1) / 2
				for i = 0, Map.Monsters.count - 1 do
					local m = Map.Monsters[i]
					if m.HP > 0 and m.Hostile and monsterDistance(m) <= WAR_CRY_RADIUS then
						local res = m.Resistances[const.Damage.Mind]
						if res ~= const.MonsterImmune and math.random(5, 100) + power > res then
							local b = m.SpellBuffs[const.MonsterBuff.Fear]
							b.ExpireTime = math.max(now + DUR.WarCryFear, b.ExpireTime)
							feared = feared + 1
						end
					end
				end
				PartyEffects.WarCry = now + DUR.WarCryParty
				Game.ShowStatusText(string.format("%s's war cry! %d monster(s) flee", pl.Name, feared), 3)
			end
		end
	end

	-- resource: drain and sync into the spell points
	for slot = 0, Party.count - 1 do
		local pl = Party[slot]
		if usesRage(pl) then
			local pi = playerIndex(pl)
			local e = state(pi)
			local dt = now - (e.Last or now)
			if dt > 0 and now - (e.LastHit or 0) > RAGE.IdleTime then
				e.R = math.max(0, e.R - RAGE.DrainPerMinute * dt / const.Minute)
			end
			e.Last = now
			-- spent by the game (spell point cost): follow; anything that adds is undone
			if pl.SP < math.floor(e.R) then e.R = math.max(0, pl.SP) end
			pl.SP = math.floor(e.R)

			-- Troll's Blood
			local fx = Effects[pi]
			if fx and fx.TrollsBlood then
				local tb = fx.TrollsBlood
				if now < tb.Until and dt > 0 then
					local before = pl.HP
					tb.Acc = (tb.Acc or 0) + tb.PerTick * dt
					local whole = math.floor(tb.Acc)
					if whole > 0 then
						tb.Acc = tb.Acc - whole
						pl.HP = math.min(pl:GetFullHP(), pl.HP + whole)
						tb.Healed = (tb.Healed or 0) + (pl.HP - before)
					end
				elseif now >= tb.Until then
					fx.TrollsBlood = nil
					if DEBUG then debugMsg("%s: Troll's Blood healed %d HP", pl.Name, tb.Healed or 0) end
				end
			end
		end
	end

	-- learned flags and spellbook texts
	if now >= nextSpellsUpdate then
		nextSpellsUpdate = now + const.Minute
		for slot = 0, Party.count - 1 do updateSpells(Party[slot]) end
	end
	updateStatsLabel()
	if Game.CurrentScreen == const.Screens.SpellBook and Game.CurrentPlayer >= 0 and Game.CurrentPlayer < Party.count then
		local pl = Party[Game.CurrentPlayer]
		if pageOf(pl) then swapTexts(pl) else restoreTexts() end
	elseif swappedFor then
		restoreTexts()
	end
end

function events.AfterLoadMap()
	for slot = 0, Party.count - 1 do
		local pl = Party[slot]
		updateSpells(pl)
		if usesRage(pl) then state(playerIndex(pl)).Last = Game.Time end
	end
end

---------------------------------------------------------------------------
-- combat: gains, passives, effects
---------------------------------------------------------------------------

local function berserk(pi)
	local fx = Effects[pi]
	return fx and fx.Berserk and fx.Berserk > Game.Time
end

-- Berserk: immune to fear, sleep and paralysis
local BerserkImmune = {[const.MonsterBonus.Afraid] = true, [const.MonsterBonus.Asleep] = true,
	[const.MonsterBonus.Paralyze] = true}
function events.DoBadThingToPlayer(t)
	if t.Allow and t.Player and BerserkImmune[t.Thing] and berserk(playerIndex(t.Player)) then
		t.Allow = false
	end
end

-- AC penalty of a reckless barbarian (not Trolls)
function events.CalcStatBonusBySkills(t)
	if t.Stat ~= const.Stats.ArmorClass then return end
	local pl = t.Player
	if not usesRage(pl) or isTroll(pl) then return end
	if state(playerIndex(pl)).R >= RAGE.RecklessAt then
		t.Result = t.Result - math.floor(RAGE.RecklessAC * pl:CalcStatBonusByItems(const.Stats.ArmorClass))
	end
end

local hooked = false
function events.LoadMap()
	if hooked then return end
	hooked = true
	-- registered on the first map load, after the damage handlers of MMMWE_Main.lua and
	-- MMMWE_ArmorEffects.lua, so these work on the final values

	function events.CalcDamageToPlayer(t)
		local pl = t.Player
		if not pl or (t.Result or 0) <= 0 then return end
		local pi = playerIndex(pl)
		if usesRage(pl) then
			if t.DamageKind == const.Damage.Phys and isTroll(pl) and state(pi).R >= RAGE.RecklessAt then
				t.Result = math.max(1, math.floor(t.Result * (1 - RAGE.TrollHide) + 0.5))
			end
			if berserk(pi) then t.Result = math.floor(t.Result * BERSERK_TAKEN + 0.5) end
			local who = WhoHitPlayer and WhoHitPlayer()
			if type(who) == "table" and (who.Monster or who.Object) then
				local full = math.max(1, pl:GetFullHP())
				addRage(pl, math.min(RAGE.PerHitTakenMax, 100 * t.Result / full))
				state(pi).LastHit = Game.Time
			end
		end
	end

	function events.CalcDamageToMonster(t)
		local pl = t.Player
		if not pl or t.DamageKind ~= const.Damage.Phys then return end
		local melee = t.Melee
		if melee == nil then
			local who = WhoHitMonster and WhoHitMonster()
			melee = type(who) == "table" and not who.Object
		end
		if not melee then return end
		local mult = 1
		if PartyEffects.WarCry > Game.Time then mult = mult + WAR_CRY_BONUS end
		if usesRage(pl) then
			local e = state(playerIndex(pl))
			mult = mult + RAGE.DamagePer5 * e.R / 5
			if RageStrikeActive then
				mult = mult * 1.5
				if math.random() < 0.10 then mult = mult * 1.5 end
			end
			addRage(pl, RAGE.PerHitLanded)
		end
		if mult ~= 1 then t.Result = math.floor(t.Result * mult + 0.5) end
	end

	-- Berserk: faster attacks (after MMMWE_Main.lua's recovery handler)
	function events.GetAttackDelay(t)
		local pl = t.Player
		if pl and berserk(playerIndex(pl)) then t.Result = t.Result * BERSERK_SPEED end
	end
end

function MF.ResourceInfo(pl)
	pl = pl or Party[math.max(Game.CurrentPlayer, 0)]
	local kind, stage = classFamily(pl.Class)
	local fam = FAMILIES[kind]
	if not fam then return string.format("class %d: family kind %d, stage %d, spell points", pl.Class, kind, stage) end
	local e = state(playerIndex(pl))
	return string.format("%s family, stage %d%s: %s %.1f / %d", fam.Name, stage, isTroll(pl) and " (Troll)" or "",
		fam.Resource, e.R, RAGE.Max)
end
