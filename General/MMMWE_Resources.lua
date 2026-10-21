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

	Knight family (Knight, Cavalier, Champion, Templar, Black Knight, variants) — Resolve:
	  0..100, +5 per block or parry, +2 per hit taken (doubled in the Defensive stance);
	  after RESOLVE.IdleTime without being hit it drains RESOLVE.DrainPerMinute per game minute.
	  Air page: Power / Agile / Defensive stance (free toggles, one at a time), Challenge
	  (Cavalier+), Rally (Champion / Templar / Black Knight).
	  Champion: Power stance +10% damage; Templar: +1 Resolve per game minute in combat;
	  Black Knight: +15 Resolve per kill.
	Paladin family: spell points as before, and the Defensive stance on the Air page.

	Console: Merge.Functions.ResourceInfo(player)
--]]

local MF, MT = Merge.Functions, Merge.Tables
local u1, u2, u4, i4 = mem.u1, mem.u2, mem.u4, mem.i4

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local ENABLED = true
local DEBUG   = false   -- status line / log messages about ability casts (testing)

-- resources: maximum, drain when idle, portrait bar bitmap, number colour (Windows BGR)
local RESOURCES = {
	Rage    = {Max = 100, IdleTime = 10 * const.Minute, DrainPerMinute = 2, Bar = "manar", Color = 0x3050FF},
	Resolve = {Max = 100, IdleTime = 10 * const.Minute, DrainPerMinute = 1, Bar = "manaY", Color = 0x40D0FF},
}

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
		Lines = {"15 Rage", "+50% damage, 10% more often a critical blow", "Barbarian", "Without enough Rage: a normal attack"},
		Icon = {"sbrg01a", "sbrg01b"},},
	WarCry = {Spell = 5, Stage = 1, Cost = 40, NotTroll = true,
		Name = "War Cry",
		Desc = "A terrifying roar. Monsters around may flee in fear (resisted by Mind resistance), and the party deals +10% melee damage for a while.",
		Lines = {"40 Rage", "Monsters around may flee (Mind resistance); party +10% melee damage", "Berserker (not Trolls)", "Fear lasts 2 minutes, the party bonus 5 minutes"},
		Icon = {"sbrg02a", "sbrg02b"},},
	TrollsBlood = {Spell = 3, Stage = 1, Cost = 40, TrollOnly = true,
		Name = "Troll's Blood",
		Desc = "The troll's blood boils and mends the wounds: heals 20% of maximum Hit Points over a short time.",
		Lines = {"40 Rage", "Heals 20% of maximum Hit Points over 2 minutes", "Troll Berserker", "Trolls have it instead of War Cry"},
		Icon = {"sbrg03a", "sbrg03b"},},
	Berserk = {Spell = 8, Stage = 2, Cost = 70,
		Name = "Berserk",
		Desc = "A frenzy: 20% faster attacks and immunity to fear, sleep and paralysis for a while, but 15% more damage taken.",
		Lines = {"70 Rage", "-20% attack recovery; immune to fear, sleep and paralysis", "Warmonger", "Takes 15% more damage; lasts 5 minutes"},
		Icon = {"sbrg04a", "sbrg04b"},},

	-- Knights (Air page); the Defensive stance also for Paladins
	PowerStance = {Spell = 12, Stage = 0, Cost = 0, Stance = "Power",
		Name = "Power Stance",
		Desc = "A stance for crushing blows: more melee damage and harder critical hits, at the price of slower attacks. Use it again to leave the stance; only one stance is active at a time.",
		Lines = {"Free (a stance)", "+30% melee damage, +20% critical damage", "Knight", "+20% attack recovery; Champion: +10% more damage"},
		Icon = {"sbkn01a", "sbkn01b"},},
	AgileStance = {Spell = 13, Stage = 0, Cost = 0, Stance = "Agile",
		Name = "Agile Stance",
		Desc = "A light-footed stance: quicker attacks and better dodging, but weaker blows. Use it again to leave the stance; only one stance is active at a time.",
		Lines = {"Free (a stance)", "-20% attack recovery, +5% dodge chance (with Dodging)", "Knight", "-15% melee damage"},
		Icon = {"sbkn02a", "sbkn02b"},},
	DefensiveStance = {Spell = 14, Stage = 0, Cost = 0, Stance = "Defensive",
		Name = "Defensive Stance",
		Desc = "A guarded stance: better blocks and parries, more Armor Class, and monsters turn on the defender more often, but blows are weaker. Use it again to leave the stance; only one stance is active at a time.",
		Lines = {"Free (a stance)", "+15% block and parry chance, +20% item Armor Class", "Knight, Paladin", "Draws 50% more attacks; -25% melee damage"},
		Icon = {"sbkn03a", "sbkn03b"},},
	Challenge = {Spell = 18, Stage = 1, Cost = 30,
		Name = "Challenge",
		Desc = "The knight calls out a foe (the one under the cursor or the nearest), and it attacks no one else for a while.",
		Lines = {"30 Resolve", "The target attacks only this knight", "Cavalier", "Lasts 2 minutes, or until the knight falls"},
		Icon = {"sbkn04a", "sbkn04b"},},
	Rally = {Spell = 19, Stage = 2, Cost = 50,
		Name = "Rally",
		Desc = "A rallying shout that steadies the party: fear is gone and every member's wounds close a little.",
		Lines = {"50 Resolve", "Removes fear from the party, heals 5% of maximum Hit Points", "Champion, Templar, Black Knight", "Unconscious members are healed too"},
		Icon = {"sbkn05a", "sbkn05b"},},
}

local RESOLVE = {
	PerDefend       = 5,           -- per block or parry
	PerHitTaken     = 2,
	DefensiveMult   = 2,           -- gains in the Defensive stance
	TemplarPerMinute = 1,          -- Templar: refill per game minute while enemies are near
	BlackKnightKill = 15,          -- Black Knight: per kill
	CombatRadius    = 2000,        -- "in combat": a hostile monster this close
}

-- stances: melee damage, crit damage (added to the multiplier), attack recovery multiplier,
-- dodge chance (%), block and parry chance (%), share of the items' Armor Class added,
-- threat (attacks drawn) multiplier
local STANCES = {
	Power     = {Damage =  0.30, CritDamage = 0.20, Recovery = 1.20},
	Agile     = {Damage = -0.15, Recovery = 0.80, Dodge = 5},
	Defensive = {Damage = -0.25, Defend = 15, AC = 0.20, Threat = 1.5},
}
local CHAMPION_POWER  = 0.10      -- Champion: Power stance damage on top
local STANCE_RECOVERY = 100       -- recovery after a stance switch

local CHALLENGE_TIME  = 2 * const.Minute
local CHALLENGE_RANGE = 3000
local RALLY_HEAL      = 0.05      -- share of each member's maximum Hit Points

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
	[6]  = {Name = "Knight", Resource = "Resolve", Page = 1,
		Abilities = {"PowerStance", "AgileStance", "DefensiveStance", "Challenge", "Rally"}},
	[9]  = {Name = "Paladin", Page = 1, Abilities = {"DefensiveStance"}},   -- spell points
}

local TROLL_RACES = {[15] = true, [16] = true, [17] = true, [18] = true}

MF.ResourceSettings = {Resources = RESOURCES, Rage = RAGE, Resolve = RESOLVE, Stances = STANCES,
	Abilities = ABILITIES, Durations = DUR, Families = FAMILIES}

-- colours of the resource numbers over the portraits (MMMWE_HPSPDisplay.lua, Windows BGR)
MF.ResourceColors = {}
for name, r in pairs(RESOURCES) do MF.ResourceColors[name] = r.Color end
-- the Stats screen's "Spell Points" line (GlobalTxt 212) shows the resource name, its
-- right-click description (the "Spell Points" entry of Stats.txt) the resource's own text,
-- and the regeneration line (MMMWE_Main.lua) MF.ResourceRegenText
local SP_LABEL_TXT = 212
local RESOURCE_DESC = {
	Rage = "Rage fills when the barbarian takes hits (the heavier the blow, the more) and a little with every melee hit landed. After a while without being hit it slowly drains away, so resting empties it; potions and Meditation don't restore it. Every 5 Rage adds 1% melee damage. At 50 Rage and more the barbarian fights recklessly: -10% of the items' Armor Class (Trolls instead take 5% less physical damage). Rage pays for the barbarian's abilities on the Fire page of the spellbook.",
	Resolve = "Resolve grows as the knight holds the line: +5 for every block or parry and +2 for every hit taken, twice as much in the Defensive stance. After a while without being hit it slowly fades, so resting empties it; potions and temples don't restore it. Resolve pays for Challenge and Rally (Air page of the spellbook); the stances there are free.",
}
function MF.ResourceRegenText(res)
	if RESOURCES[res] then return "" end
	return "no regen"
end

---------------------------------------------------------------------------

if not ENABLED then return end

local function log(fmt, ...) if MF.LogInfo then MF.LogInfo("[Resources] " .. fmt, ...) end end
local function debugMsg(fmt, ...)
	local text = string.format(fmt, ...)
	log("%s", text)
	local f = io.open("MMMWE_Resources_debug.txt", "a")   -- in the game folder, flushed at once
	if f then f:write(os.date("%H:%M:%S "), text, "\n") f:close() end
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

-- Knight promotion branch (the class or the one it was promoted from): Champion, Templar,
-- BlackKnight, or nil (Class Extra.txt numbers)
local KNIGHT_BRANCH = {[46] = "Champion", [48] = "Templar", [50] = "BlackKnight"}
local function knightBranch(pl)
	local cur = pl.Class
	for _ = 1, 8 do
		if KNIGHT_BRANCH[cur] then return KNIGHT_BRANCH[cur] end
		local inv = MT.ClassPromotionsInv and MT.ClassPromotionsInv[cur]
		if not inv or not inv[1] then return end
		cur = inv[1]
	end
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

-- name and settings of the player's resource, or nil (spell points)
local function resourceOf(pl)
	local fam = familyOf(pl)
	local name = fam and fam.Resource
	if name then return name, RESOURCES[name] end
end

local function usesRage(pl)
	return resourceOf(pl) == "Rage"
end

local function usesResolve(pl)
	return resourceOf(pl) == "Resolve"
end

function MF.GetResource(pl)
	local name, r = resourceOf(pl)
	if not name then return nil end
	return state(playerIndex(pl)).R, r.Max, name
end

local function addResource(pl, v)
	local name, r = resourceOf(pl)
	if not name then return end
	local e = state(playerIndex(pl))
	e.R = math.max(0, math.min(r.Max, e.R + v))
	pl.SP = math.floor(e.R)
end
local addRage = addResource

-- the resource maximum instead of the spell points
mem.hookfunction(0x48DA18, 1, 0, function(d, def, this)
	local pl = playerFromPtr(this)
	local _, r = pl and resourceOf(pl)
	if r then return r.Max end
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

-- skill names as the spellbook description shows them ("Fire Magic"): 0xBB3090 + page x 4
local SKILL_NAMES = 0xBB3090
local skillNameSaved

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
	if skillNameSaved then
		u4[skillNameSaved[1]] = skillNameSaved[2]
		skillNameSaved = nil
	end
end

local function swapTexts(pl)
	if swappedFor == pl["?ptr"] then return end
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
			local name = a.Name
			if a.Stance and state(playerIndex(pl)).Stance == a.Stance then name = name .. " (on)" end
			u4[p] = cstr(name)
			u4[p + 4] = cstr(name)
			u4[p + 8] = cstr(a.Desc)
			for i = 1, 4 do u4[p + 8 + i * 4] = cstr(a.Lines[i] ~= "" and a.Lines[i] or " ") end
		end
	end
	local fam = familyOf(pl)
	if fam.Resource then
		costTxtSaved = u4[Game.GlobalTxt["?ptr"] + 522 * 4]
		u4[Game.GlobalTxt["?ptr"] + 522 * 4] = cstr(fam.Resource .. " cost")
	end
	-- the school name in the description: the family's abilities
	local addr = SKILL_NAMES + page * 4
	skillNameSaved = {addr, u4[addr]}
	u4[addr] = cstr(fam.Name .. " Ability")
	swappedFor = pl["?ptr"]
end

-- name of a spell as the player sees it (quick slot names)
function MF.SpellDisplayName(pl, spell)
	local _, a = abilityOf(pl, spell)
	return a and a.Name or Game.SpellsTxt[spell].Name
end

-- Ability icons. MM8 builds a spellbook page in 0x4CB328 (page in [ebp+8]): for every known
-- spell it writes the picture names "SB<school><nn>b" ([ebp-74h]) and "SB<school><nn>a"
-- ([ebp-54h]) and the page widget loads them by name. Right after the names are written
-- (0x4CB463) an ability's spot gets its own pictures (MM7 sb?c = normal, sb?s = selected).
-- The spell number is in [ebp-1Ch], the player in [ebp-10h].
local function bitmapPtr(name)
	local ok, idx = pcall(function() return Game.IconsLod:LoadBitmap(name) end)
	if not ok or not idx or idx < 0 then return end
	return Game.IconsLod.Bitmaps[idx]["?ptr"]
end

local function writeName(addr, name)
	mem.copy(addr, name, #name)
	u1[addr + #name] = 0
end
mem.autohook(0x4CB463, function(d)
	local pl = playerFromPtr(u4[d.ebp - 0x10])
	if not pl then return end
	-- the page widget copies the spell names now (hover text), so the texts must be swapped
	if pageOf(pl) == u4[d.ebp + 8] then swapTexts(pl) end
	local _, a = abilityOf(pl, u4[d.ebp - 0x1C])
	if a and a.Icon then
		writeName(d.ebp - 0x54, a.Icon[1])
		writeName(d.ebp - 0x74, a.Icon[2])
	end
end)

-- right-click description of a spell in the book: the ability texts (also kept by the tick)
-- the four line labels of the description (Normal / Expert / Master / Grand: GlobalTxt 431,
-- 433, 432, 96) read Cost / Effect / Rank / Note for an ability, and are put back after it
local LINE_LABELS = {{431, "Cost"}, {433, "Effect"}, {432, "Rank"}, {96, "Note"}}
local labelsSaved
local function setLineLabels(on)
	local base = Game.GlobalTxt["?ptr"]
	if on and not labelsSaved then
		labelsSaved = {}
		for _, l in ipairs(LINE_LABELS) do
			labelsSaved[l[1]] = u4[base + l[1] * 4]
			u4[base + l[1] * 4] = cstr(l[2])
		end
	elseif not on and labelsSaved then
		for id, p in pairs(labelsSaved) do u4[base + id * 4] = p end
		labelsSaved = nil
	end
end

mem.autohook(0x411F3A, function(d)
	local i = u4[0x519350] - 1
	local isAbility = false
	if i >= 0 and i < Party.count and pageOf(Party[i]) then
		local pl = Party[i]
		swapTexts(pl)
		isAbility = abilityOf(pl, pl.SpellBookPage * 11 + u4[d.esp + 4] + 1) ~= nil
	end
	setLineLabels(isAbility)
end)
-- labels back as soon as the description is drawn (0x4121AF: end of rmb_spellbook_spell)
mem.autohook(0x4121AF, function(d) setLineLabels(false) end)
-- an ability's description is short, and the two-line "Barbarian Ability" in the left column
-- would run into the cost line drawn from the bottom of the box: make the box tall enough
mem.autohook(0x41209C, function(d)
	if labelsSaved and i4[d.ebp - 0x58] < 0xC0 then i4[d.ebp - 0x58] = 0xC0 end
end)

-- cost line of the right-click description (word_4F4884 read with the page skill's mastery)
mem.autohook2(0x41216C, function(d)
	local i = u4[0x519350] - 1
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
local Challenged = {}  -- [monster index] = {pi = challenger, Until = time}

local function monsterDistance(mon)
	local dx, dy, dz = mon.X - Party.X, mon.Y - Party.Y, mon.Z - Party.Z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function meleeTarget(targetRef, range)
	range = range or RAGE.MeleeRange
	local mi
	if targetRef and targetRef % 8 == 3 then mi = math.floor(targetRef / 8) end
	if not mi then
		local ok, tg = pcall(function() return Game.Mouse:GetTarget() end)
		if ok and tg and tg.Kind == 3 then mi = tg.Index end
	end
	local function valid(i)
		local m = i and Map.Monsters[i]
		return m and m.HP > 0 and m.AIState ~= const.AIState.Removed
			and monsterDistance(m) <= range + (m.BodyRadius or 0)
	end
	if valid(mi) then return mi end
	local best, bd
	for i = 0, Map.Monsters.count - 1 do
		local m = Map.Monsters[i]
		if m.HP > 0 and m.Hostile then
			local dist = monsterDistance(m)
			if dist <= range + (m.BodyRadius or 0) and (not bd or dist < bd) then best, bd = i, dist end
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
	local resName = resourceOf(pl)
	if DEBUG then debugMsg("%s uses %s (%s %d, cost %d)", pl.Name, a.Name, resName or "SP", e.R, a.Cost) end
	if a.Cost > 0 and e.R < a.Cost then
		if key == "RageStrike" then
			DoGameAction(23, 0, 0)        -- a normal attack, as with spell points
		else
			failCast(pl, string.format("Not enough %s (%d needed)", resName or "spell points", a.Cost))
		end
		return true
	end
	if a.Stance then
		if e.Stance == a.Stance then
			e.Stance = nil
			Game.ShowStatusText(string.format("%s leaves the %s stance", pl.Name, a.Stance))
		else
			e.Stance = a.Stance
			Game.ShowStatusText(string.format("%s takes the %s stance", pl.Name, a.Stance))
		end
		Game.PlaySound(44587)
		swappedFor = nil          -- the "(on)" mark in the book
		pl:SetRecoveryDelay(STANCE_RECOVERY)
		return true
	elseif key == "Challenge" then
		local mi = meleeTarget(targetRef, CHALLENGE_RANGE)
		if not mi then
			failCast(pl, "No enemy to challenge")
			return true
		end
		Challenged[mi] = {pi = pi, Until = Game.Time + CHALLENGE_TIME}
		local mon = Map.Monsters[mi]
		Game.ShowStatusText(string.format("%s challenges %s!", pl.Name, Game.MonstersTxt[mon.Id].Name))
		pl:SetRecoveryDelay(100)
	elseif key == "Rally" then
		local healed = 0
		for s = 0, Party.count - 1 do
			local m = Party[s]
			m.Conditions[const.Condition.Afraid] = 0
			if m.Conditions[const.Condition.Dead] == 0 and m.Conditions[const.Condition.Stoned] == 0
					and m.Conditions[const.Condition.Eradicated] == 0 then
				local full = m:GetFullHP()
				if m.HP < full then
					m.HP = math.min(full, m.HP + math.max(1, math.floor(RALLY_HEAL * full + 0.5)))
					healed = healed + 1
				end
			end
		end
		Game.ShowStatusText(string.format("%s rallies the party!", pl.Name))
		pl:SetRecoveryDelay(100)
	elseif key == "RageStrike" then
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
	if a.Cost > 0 then addResource(pl, -a.Cost) end
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
local RESOURCE_BAR = {}
for name, r in pairs(RESOURCES) do RESOURCE_BAR[name] = r.Bar end
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
		local name = fam and fam.Resource and RESOURCE_BAR[fam.Resource]
		if name then
			barOurs[name] = barOurs[name] or bitmapPtr(name)
			want = barOurs[name] or barOrig
		end
	end
	if want and want ~= cur then u4[d.ebp - 0x18] = want end
end)

-- Stats screen label: the resource name while a character with a resource is shown
local spLabelSaved, spLabelNow, spDescAddr, spDescSaved
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
	-- description: the Spell Points entry of Stats.txt, kept by the game at 0x5E4D54
	-- (the Spell Points tooltip at 0x4177C9 reads GlobalTxt 212 and this pointer)
	spDescAddr = 0x5E4D54
	if spDescAddr then
		if not spDescSaved then spDescSaved = u4[spDescAddr] end
		local desc = want and RESOURCE_DESC[want]
		u4[spDescAddr] = desc and cstr(desc) or spDescSaved
	end
	spLabelNow = want
end

local RiposteVec = mem.StaticAlloc(12)
local nextSpellsUpdate = 0
local nextCombatCheck, inCombat = 0, false

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

	-- in combat: a hostile monster near (checked twice a game minute)
	if now >= nextCombatCheck then
		nextCombatCheck = now + const.Minute / 2
		inCombat = false
		for i = 0, Map.Monsters.count - 1 do
			local m = Map.Monsters[i]
			if m.HP > 0 and m.Hostile and m.AIState ~= const.AIState.Removed
					and monsterDistance(m) <= RESOLVE.CombatRadius then
				inCombat = true
				break
			end
		end
		-- challenges that ran out, or whose monster or knight is gone
		for mi, c in pairs(Challenged) do
			local m = Map.Monsters[mi]
			local k = Party.PlayersArray[c.pi]
			if now >= c.Until or not m or m.HP <= 0 or not k or not k:IsConscious() then Challenged[mi] = nil end
		end
	end

	-- resource: drain and sync into the spell points
	for slot = 0, Party.count - 1 do
		local pl = Party[slot]
		local resName, res = resourceOf(pl)
		if resName then
			local pi = playerIndex(pl)
			local e = state(pi)
			local dt = now - (e.Last or now)
			if dt > 0 and now - (e.LastHit or 0) > res.IdleTime then
				e.R = math.max(0, e.R - res.DrainPerMinute * dt / const.Minute)
			end
			if dt > 0 and inCombat and resName == "Resolve" and knightBranch(pl) == "Templar" then
				e.R = math.min(res.Max, e.R + RESOLVE.TemplarPerMinute * dt / const.Minute)
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
	-- the game's current_player (0x519350, 1-based): Game.CurrentPlayer can be -1 in the book
	local bookSlot = u4[0x519350] - 1
	if Game.CurrentScreen == const.Screens.SpellBook and bookSlot >= 0 and bookSlot < Party.count then
		local pl = Party[bookSlot]
		if pageOf(pl) then swapTexts(pl) else restoreTexts() end
	elseif swappedFor then
		restoreTexts()
	end
end

function events.AfterLoadMap()
	Challenged = {}
	for slot = 0, Party.count - 1 do
		local pl = Party[slot]
		updateSpells(pl)
		if resourceOf(pl) then state(playerIndex(pl)).Last = Game.Time end
	end
end

---------------------------------------------------------------------------
-- combat: gains, passives, effects
---------------------------------------------------------------------------

-- active stance settings of a player (Knights, Paladins), or nil
local function stanceOf(pl)
	local fam = familyOf(pl)
	if not fam then return end
	local e = store()[playerIndex(pl)]
	local st = e and e.Stance
	if not st then return end
	-- a stance the character can't use (class change, Paladin with a Knight stance)
	for _, key in ipairs(fam.Abilities) do
		local a = ABILITIES[key]
		if a.Stance == st and abilityOf(pl, a.Spell) then return STANCES[st], st end
	end
end
MF.StanceOf = function(pl) return select(2, stanceOf(pl)) end

-- MMMWE_Main.lua: dodge chance (%), block and parry chance (%)
function MF.StanceDodgeMod(pl)
	local st = stanceOf(pl)
	return st and st.Dodge or 0
end
function MF.StanceDefendBonus(pl)
	local st = stanceOf(pl)
	return st and st.Defend or 0
end
-- MMMWE_Threat.lua: attacks drawn
function MF.StanceThreatMult(pl)
	local st = stanceOf(pl)
	return st and st.Threat or 1
end
-- MMMWE_Main.lua / MMMWE_Shields.lua: a block or parry happened ("block" / "parry")
function MF.OnDefended(pl, kind)
	if not usesResolve(pl) then return end
	local _, name = stanceOf(pl)
	addResource(pl, RESOLVE.PerDefend * (name == "Defensive" and RESOLVE.DefensiveMult or 1))
end

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

-- AC penalty of a reckless barbarian (not Trolls); Defensive stance AC
function events.CalcStatBonusBySkills(t)
	if t.Stat ~= const.Stats.ArmorClass then return end
	local pl = t.Player
	local st = stanceOf(pl)
	if st and st.AC then
		t.Result = t.Result + math.floor(st.AC * pl:CalcStatBonusByItems(const.Stats.ArmorClass))
	end
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
		elseif usesResolve(pl) then
			local who = WhoHitPlayer and WhoHitPlayer()
			if type(who) == "table" and (who.Monster or who.Object) then
				local _, name = stanceOf(pl)
				addResource(pl, RESOLVE.PerHitTaken * (name == "Defensive" and RESOLVE.DefensiveMult or 1))
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
		local st, stName = stanceOf(pl)
		if st and st.Damage then
			local dmg = st.Damage
			if stName == "Power" and knightBranch(pl) == "Champion" then dmg = dmg + CHAMPION_POWER end
			mult = mult * (1 + dmg)
		end
		if mult ~= 1 then t.Result = math.max(0, math.floor(t.Result * mult + 0.5)) end
		-- Black Knight: Resolve for a kill
		if t.Monster and t.Result >= t.Monster.HP and t.Monster.HP > 0 and usesResolve(pl)
				and knightBranch(pl) == "BlackKnight" then
			addResource(pl, RESOLVE.BlackKnightKill)
		end
	end

	-- Berserk: faster attacks (after MMMWE_Main.lua's recovery handler)
	function events.GetAttackDelay(t)
		local pl = t.Player
		if not pl then return end
		if berserk(playerIndex(pl)) then t.Result = t.Result * BERSERK_SPEED end
		local st = stanceOf(pl)
		if st and st.Recovery then t.Result = t.Result * st.Recovery end
	end

	-- Power stance: harder melee crits (MMMWE_Main.lua reads MF.GetCritStats at every roll)
	local getCrit = MF.GetCritStats
	if getCrit then
		MF.GetCritStats = function(pl, melee, ...)
			local c, d, sk = getCrit(pl, melee, ...)
			if melee and c and c > 0 then
				local st = stanceOf(pl)
				if st and st.CritDamage then d = d + st.CritDamage end
			end
			return c, d, sk
		end
	end

	-- Challenge: the challenged monster picks its challenger (after MMMWE_Threat.lua)
	function events.MonsterChooseTargetPlayer(t)
		if not next(Challenged) or not t.MonsterPtr then return end
		local mi = (t.MonsterPtr - Map.Monsters[0]["?ptr"]) / Map.Monsters[0]["?size"]
		local c = Challenged[mi]
		if not c or Game.Time >= c.Until then return end
		for s = 0, Party.count - 1 do
			if Party.PlayersIndexes[s] == c.pi then
				if Party[s]:IsConscious() then t.Slot = s end
				return
			end
		end
	end
end

function MF.ResourceInfo(pl)
	pl = pl or Party[math.max(Game.CurrentPlayer, 0)]
	local kind, stage = classFamily(pl.Class)
	local fam = FAMILIES[kind]
	if not fam then return string.format("class %d: family kind %d, stage %d, spell points", pl.Class, kind, stage) end
	local e = state(playerIndex(pl))
	local _, stance = stanceOf(pl)
	local res = fam.Resource and string.format("%s %.1f / %d", fam.Resource, e.R, RESOURCES[fam.Resource].Max) or "spell points"
	return string.format("%s family, stage %d%s%s: %s%s", fam.Name, stage, isTroll(pl) and " (Troll)" or "",
		knightBranch(pl) and (" (" .. knightBranch(pl) .. ")") or "", res,
		stance and (", " .. stance .. " stance") or "")
end
