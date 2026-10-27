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

	Monk family (Monk, Initiate Monk, Master Monk, Ninja, variants) — Ki:
	  charges, 5 + 2 per promotion stage + 1 per 2 points of Meditation (at most 15);
	  refill 1 charge every 5 game minutes, -2% per point of Meditation (at most -50%);
	  Meditation from the first promotion (Class Skills.txt). Their spells cost spell points / 5 in Ki (at least 1).
	  Water page: Stunning Palm, Inner Peace, Flurry (Initiate+), Iron Body (Master Monk),
	  Vanish (Ninja).

	Thief family (Thief, Rogue, Robber, Spy, Assassin, variants) — Energy and combo points:
	  Energy 0..100, +ENERGY.PerMinute per game minute; their (Novice) spells cost spell
	  points x 5 in Energy. Combo points 0..5: +1 per melee hit on the same target, lost when
	  switching targets or after ENERGY.ComboTime without a hit.
	  Mind page: Finisher, Poisoned Blade (Assassin), Shadow Veil (Spy).

	Dragon family (Dragon, Flight Leader, Great Wyrm, variants) — Breath:
	  0..100, +BREATH.PerMinute per game minute; each breath attack (the dragon's ranged
	  attack, spell 137) costs BREATH.AttackCost, without enough Breath the dragon can't
	  breathe (its turn passes); Dragon school spells cost spell points x 2 in Breath.

	Technician family (Technician, Engineer, Ancient Researcher, Scientist, variants):
	  spell points as before; Earth page: Deploy Droid (Engineer+) - a temporary allied melee
	  robot that draws attacks and helps on single targets; one at a time, it keeps up with
	  the party on the map (teleported when it falls far behind) and is removed on leaving.

	Hybrids on spell points (Archer, Ranger, Dark Elf, Minotaur; Paladin for the refill):
	  +1% of maximum spell points per game minute while hostile monsters are near.
	  Archer (Body page): Aimed Shot, Volley (Master Archer, Sniper). Dark Elf (Body page):
	  Aimed Shot, Darkfire Arrows (Pioneer+). Ranger (Light page): Aimed Shot, Mark Prey (Hunter+). Minotaur (Fire page):
	  Gore, Herd Fury (Headsman+), Mark Prey (third stage).

	Custom classes (MMMWE_CustomClasses.lua) with a resource kit count as the kit's family, at
	their promotion step; their light / dark steps stand for the family's light / dark branch.
	The Minotaur kit works for Minotaurs only.

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
	-- Ki: the maximum and the refill are the Monk's own (KI below); spells cost SP / SpellCostDiv
	Ki      = {Max = 15, Bar = "manaT", Color = 0xE0E040, SpellCostDiv = 5},
	-- Energy: spells cost spell points x SpellCostMul
	Energy  = {Max = 100, Bar = "manaO", Color = 0x30B0FF, SpellCostMul = 5},
	Breath  = {Max = 100, Bar = "manar", Color = 0x2080FF, SpellCostMul = 2},
}

local BREATH = {
	PerMinute    = 10,             -- refill per game minute
	AttackCost   = 25,             -- one breath attack
	OutRecovery  = 50,             -- recovery when out of breath (the turn passes)
	AttackSpell  = 137,            -- the dragon's breath attack in the cast queue
}

local ENERGY = {
	PerMinute     = 10,            -- refill per game minute
	ComboMax      = 5,
	ComboTime     = 5 * const.Minute,  -- combo points are lost after this without a hit
	FinisherDamage = 0.20,         -- per combo point
	FinisherCrit  = 0.10,          -- crit chance per combo point
	AssassinCritDamage = 0.10,     -- Assassin: crit damage per combo point
	PoisonHits    = 5,             -- Poisoned Blade: hits
	PoisonDamage  = 0.25,          -- extra damage of a poisoned hit (not vs Body immune)
	VeilTime      = 10 * const.Minute,  -- Shadow Veil: invisibility and Wizard Eye
}

local ZOMBIE_REFILL = 0.5     -- Ki and Energy refill speed of a zombie (ZombiePlayers.lua
                               -- doesn't drain class resources)

local KI = {
	Base          = 5,
	PerStage      = 2,             -- per promotion stage
	PerMeditation = 0.5,           -- per point of Meditation skill
	Cap           = 15,
	Interval      = 5 * const.Minute,  -- one charge per interval
	IntervalPerMed = 0.02,         -- interval -2% per point of Meditation (at most -50%)
	Refill        = {[0] = 1, 1, 1, 1},   -- charges per interval by promotion stage
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
		Lines = {"30 Resolve", "The target attacks only this knight", "Cavalier", "4 minutes, +5% per Personality bonus point; ends if the knight falls"},
		Icon = {"sbkn04a", "sbkn04b"},},
	Rally = {Spell = 19, Stage = 2, Cost = 50,
		Name = "Rally",
		Desc = "A rallying shout that steadies the party: fear is gone and every member's wounds close a little.",
		Lines = {"50 Resolve", "Removes fear from the party, heals 5% of maximum Hit Points", "Champion, Templar, Black Knight", "Unconscious members are healed too"},
		Icon = {"sbkn05a", "sbkn05b"},},

	-- Monks (Water page)
	StunningPalm = {Spell = 26, Stage = 0, Cost = 1, Attack = true,
		Name = "Stunning Palm",
		Desc = "A blow at the target in melee reach that may stun it (paralysis for a short time; Physical resistance against the Unarmed skill). Use it as the attack spell to strike with it whenever there is Ki; without Ki it is a normal attack.",
		Lines = {"1 Ki", "A melee hit with a chance to stun the target", "Monk", "Stun 1 minute; the chance grows with Unarmed"},
		Icon = {"sbmk01a", "sbmk01b"},},
	InnerPeace = {Spell = 23, Stage = 0, Cost = 3,
		Name = "Inner Peace",
		Desc = "The monk calms body and mind, and poison, disease, fear and weakness leave him.",
		Lines = {"3 Ki", "Cures own poison, disease, fear and weakness", "Monk", "Only the monk himself"},
		Icon = {"sbmk03a", "sbmk03b"},},
	Flurry = {Spell = 29, Stage = 1, Cost = 2,
		Name = "Flurry",
		Desc = "A melee hit followed by two quick extra strikes at the same target.",
		Lines = {"2 Ki", "A hit and two extra strikes, 60% damage each", "Initiate Monk", "Recovery of one attack"},
		Icon = {"sbmk02a", "sbmk02b"},},
	IronBody = {Spell = 25, Stage = 2, Cost = 3, Branch = "MasterMonk",
		Name = "Iron Body",
		Desc = "The monk hardens his body against blows: less physical damage taken for a while.",
		Lines = {"3 Ki", "-20% physical damage taken", "Master Monk", "Lasts 5 minutes"},
		Icon = {"sbmk04a", "sbmk04b"},},
	Vanish = {Spell = 27, Stage = 2, Cost = 3, Branch = "Ninja",
		Name = "Vanish",
		Desc = "The ninja slips out of sight: monsters lose track of him and attack the others, until he strikes again.",
		Lines = {"3 Ki", "Monsters don't pick the ninja as their target", "Ninja", "Lasts 2 minutes; ends when the ninja strikes"},
		Icon = {"sbmk05a", "sbmk05b"},},

	-- Thieves (Mind page)
	Finisher = {Spell = 59, Stage = 0, Cost = 25, Attack = true,
		Name = "Finisher",
		Desc = "A blow that spends all combo points (gained by melee hits on the same target): +20% damage and +10% critical chance per point. With 5 points the thief also tries to steal from the target. Use it as the attack spell; without enough Energy it is a normal attack.",
		Lines = {"25 Energy", "+20% damage, +10% critical chance per combo point", "Thief", "5 points: a steal attempt (Stealing skill)"},
		Icon = {"sbth01a", "sbth01b"},},
	PoisonedBlade = {Spell = 58, Stage = 2, Cost = 30, Branch = "Assassin",
		Name = "Poisoned Blade",
		Desc = "The assassin coats the blade with poison: the next 5 melee hits deal extra damage, unless the target is immune to Body. The assassin's finishers also crit harder.",
		Lines = {"30 Energy", "Next 5 melee hits: +25% damage (poison)", "Assassin", "Finishers: +10% critical damage per combo point"},
		Icon = {"sbth02a", "sbth02b"},},
	ShadowVeil = {Spell = 63, Stage = 2, Cost = 40, Branch = "Spy",
		Name = "Shadow Veil",
		Desc = "The spy hides the party in shadows and scouts ahead: Invisibility and Wizard Eye for the party.",
		Lines = {"40 Energy", "Party Invisibility and Wizard Eye", "Spy", "Lasts 10 minutes; power by the Stealing skill"},
		Icon = {"sbth03a", "sbth03b"},},

	-- Technicians (Earth page)
	DeployDroid = {Spell = 36, Stage = 1, Cost = 25,
		Name = "Deploy Droid",
		Desc = "The technician assembles a combat droid that fights at the party's side in melee, drawing the attackers' attention and helping to bring single foes down. One droid at a time: casting again repairs it and resets its time. It keeps up with the party on the map, and shuts down when its time runs out or the party leaves the map.",
		Lines = {"25 SP", "An allied droid: melee first, an energy shot now and then; grows with level and Repair", "Engineer", "Lasts 20 minutes + 2 per level"},
		Icon = {"sbtc01a", "sbtc01b"},},

	-- Hybrids (spell points). The spot is the family's (FAMILIES[].Spots) when it differs.
	AimedShot = {Spell = 70, Stage = 0, Cost = 3, Shot = true,
		Name = "Aimed Shot",
		Desc = "The next bow shot is carefully aimed: more damage and a better chance of a critical hit. As the attack spell it is used when the target is out of melee reach.",
		Lines = {"3 SP", "Next arrow: +25% damage, +15% critical chance", "Archer, Ranger, Deerslayer", "Needs a bow; stays ready until the next shot"},
		Icon = {"sbhy01a", "sbhy01b"},},
	Volley = {Spell = 69, Stage = 2, Cost = 10, Shot = true, Branches = {MasterArcher = true, Sniper = true},
		Name = "Volley",
		Desc = "A quick series of shots: the next 3 bow attacks recover much faster.",
		Lines = {"10 SP", "Next 3 bow attacks: -66% recovery", "Master Archer, Sniper", "Needs a bow"},
		Icon = {"sbhy02a", "sbhy02b"},},
	DarkfireArrows = {Spell = 69, Stage = 1, Cost = 12, Imbue = true,
		Name = "Darkfire Arrows",
		Desc = "The dark elf imbues the arrows with Darkfire, the blend of Fire and Dark of the Darkfire Bolt: the next 5 arrows deal extra damage that the target resists with its Fire or Dark resistance, whichever is lower.",
		Lines = {"12 SP", "Next 5 arrows: +30% of the arrow's damage +2 per Dark Elf skill point", "Pioneer", "Fire or Dark resistance, the lower one"},
		Icon = {"sbde04a", "sbde04b"},},
	MarkPrey = {Spell = 81, Stage = 1, Cost = 8,
		Name = "Mark Prey",
		Desc = "The hunter marks a foe (the one under the cursor or the nearest), and the whole party hits it harder for a while.",
		Lines = {"8 SP", "The target takes +15% damage from the party", "Hunter, Minotaur Lord", "Lasts 3 minutes"},
		Icon = {"sbhy03a", "sbhy03b"},},
	Gore = {Spell = 2, Stage = 0, Cost = 4, Attack = true,
		Name = "Gore",
		Desc = "A charge with the horns at the target in melee reach: +40% damage and a chance to stagger it. Use it as the attack spell; without enough spell points it is a normal attack.",
		Lines = {"4 SP", "+40% damage, 25% chance to stagger (30 seconds)", "Minotaur", "Melee reach"},
		Icon = {"sbhy04a", "sbhy04b"},},
	HerdFury = {Spell = 5, Stage = 1, Cost = 15,
		Name = "Herd Fury",
		Desc = "The minotaur's battle fury: more melee damage and a tougher hide for a while.",
		Lines = {"15 SP", "+15% melee damage, -10% physical damage taken", "Minotaur Headsman", "Lasts 5 minutes"},
		Icon = {"sbhy05a", "sbhy05b"},},
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

-- Hybrids (spell points)
local HYBRID_REFILL  = 0.01                  -- share of max SP per game minute in combat
local AIMED_DAMAGE   = 0.25                  -- Aimed Shot: damage of the arrow
local AIMED_CRIT     = 0.15                  -- Aimed Shot: extra crit chance
local VOLLEY_SHOTS   = 3                     -- Volley: shots with quick recovery
local VOLLEY_RECOVERY = 0.34                 -- their recovery multiplier
local MARK_TIME      = 3 * const.Minute
local MARK_DAMAGE    = 0.15                  -- damage the marked monster takes from the party
local MARK_RANGE     = 5000
local DARKFIRE_ARROWS = 5                    -- Darkfire Arrows: arrows imbued
local DARKFIRE_SHARE  = 0.30                 -- extra damage: share of the arrow's damage
local DARKFIRE_PER_SKILL = 2                 -- + per point of the Dark Elf racial skill
local GORE_DAMAGE    = 0.40
local GORE_STAGGER   = 25                    -- % chance; paralysis for GORE_STAGGER_TIME
local GORE_STAGGER_TIME = const.Minute / 2
local HERD_TIME      = 5 * const.Minute
local HERD_DAMAGE    = 0.15                  -- melee damage
local HERD_PHYS      = 0.10                  -- physical damage taken -10%

-- Technicians: Deploy Droid
local DROID = {
	-- Engineer: Seeker Droid; Ancient Researcher: Sentinel Droid; Scientist: Assassin Droid
	-- (the "3" class entries are table placeholders, never reached)
	Models      = {[1] = 388, [2] = 389, Scientist = 390},
	-- resistances (set after the summon): machines are immune to Mind, Spirit and Body;
	-- elements, Light and Dark 20 + 2 per point of Repair; Physical 10 + 5 per Repair mastery
	ResBase     = 20, ResPerRepair = 2, ResMax = 150,
	PhysBase    = 10, PhysPerMastery = 5,
	BaseTime    = 20 * const.Minute,
	PerLevel    = 2 * const.Minute,     -- duration per level of the technician
	-- the droid grows with the technician's level and Repair skill (Scientists: Repair or
	-- Alchemy, whichever is better - MF.TechRepairSkill); RSM = Repair skill x mastery
	HP          = 40, HPPerLevel = 8, HPPerRSM = 2,
	AC          = 10, ACPerLevel = 1, ACPerRepair = 1,
	DiceSides   = 8,                    -- damage: (1 + level/8)d8 + level/4 + RSM/8, physical, melee
	ShotChance  = 50,                   -- % for the energy shot (1 + level/12)d8 + level/4 as Attack2
	FollowDist  = 2500,                 -- farther than this from the party: brought back
	SpawnDist   = 250,
}

-- Monks
local STUN_TIME      = const.Minute          -- Stunning Palm: paralysis of a stunned monster
local FLURRY_DAMAGE  = 0.60                  -- each of the two extra strikes
local IRON_BODY      = 0.20                  -- physical damage taken -20%
local IRON_BODY_TIME = 5 * const.Minute
local VANISH_TIME    = 2 * const.Minute

local CHALLENGE_TIME  = 4 * const.Minute   -- base duration (about 4-5 monster attacks)
local CHALLENGE_PERS  = 0.05      -- +5% duration per point of the Personality bonus (never shorter)
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
	[9]  = {Name = "Paladin", Page = 1, Hybrid = true, Abilities = {"DefensiveStance"}},   -- spell points
	[8]  = {Name = "Monk", Resource = "Ki", Page = 2,
		Abilities = {"StunningPalm", "InnerPeace", "Flurry", "IronBody", "Vanish"}},
	[4]  = {Name = "Dragon", Resource = "Breath", Abilities = {}},   -- no ability page
	[15] = {Name = "Technician", Page = 3, Abilities = {"DeployDroid"}},   -- spell points
	[11] = {Name = "Thief", Resource = "Energy", Page = 5,
		Abilities = {"Finisher", "PoisonedBlade", "ShadowVeil"}},
	-- hybrids on spell points (Hybrid = combat refill)
	[1]  = {Name = "Archer", Page = 6, Hybrid = true, Abilities = {"AimedShot", "Volley"}},
	[3]  = {Name = "Dark Elf", Page = 6, Hybrid = true, Abilities = {"AimedShot", "DarkfireArrows"}},
	[10] = {Name = "Ranger", Page = 7, Hybrid = true, Abilities = {"AimedShot", "MarkPrey"},
		Spots = {AimedShot = 78, MarkPrey = 81}},
	[7]  = {Name = "Minotaur", Page = 0, Hybrid = true, Abilities = {"Gore", "HerdFury", "MarkPrey"},
		Spots = {MarkPrey = 6}, Stages = {MarkPrey = 2}},
}

local TROLL_RACES = {[15] = true, [16] = true, [17] = true, [18] = true}

MF.ResourceSettings = {Resources = RESOURCES, Rage = RAGE, Resolve = RESOLVE, Ki = KI, Energy = ENERGY, Breath = BREATH, Stances = STANCES,
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
	Ki = "Ki is the monk's inner strength, counted in charges: 5, +2 for every promotion and +1 for every 2 points of Meditation (at most 15). It refills on its own, 1 charge every 5 minutes, sooner with Meditation (down to half the time). Ki pays for the monk's abilities on the Water page of the spellbook, and for his spells: a fifth of their spell point cost.",
	Breath = "Breath is the fire in the dragon's chest. It refills on its own, 10 every game minute. Every breath attack costs 25, so a dragon breathes every few attacks and fights with claws and teeth in between; without enough Breath it can't breathe at a far target. The Dragon abilities (Fear, Flame Blast, Flight, Wing Buffet) cost 2 Breath per spell point.",
	Energy = "Energy is the thief's quickness. It refills fast, 10 every game minute, and pays for the thief's tricks on the Mind page of the spellbook and for his spells (5 Energy per spell point). Melee hits on the same target build combo points (up to 5, shown in the status line); the Finisher spends them all.",
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
	-- custom classes (MMMWE_CustomClasses.lua): the family of their resource kit, if any; not
	-- cached, the builds change
	if MF.IsCustomClass and MF.IsCustomClass(class) then
		local kit = MF.CustomClassKit and MF.CustomClassKit(class)
		local e = Game.ClassesExtra and Game.ClassesExtra[class]
		return kit and kit.Kind or 0, e and e.Step or 0
	end
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
	-- a custom class's Minotaur kit works for Minotaurs only
	if kind ~= 0 and MF.IsCustomClass and MF.IsCustomClass(pl.Class)
			and MF.CustomClassKitAllowed and not MF.CustomClassKitAllowed(pl, (MF.CustomClassKit(pl.Class) or {}).Key) then
		return nil, stage, 0
	end
	return FAMILIES[kind], stage, kind
end

-- Knight promotion branch (the class or the one it was promoted from): Champion, Templar,
-- BlackKnight, or nil (Class Extra.txt numbers)
local KNIGHT_BRANCH = {[46] = "Champion", [48] = "Templar", [50] = "BlackKnight",
	[64] = "MasterMonk", [66] = "Ninja", [88] = "Spy", [90] = "Assassin",
	[4] = "MasterArcher", [6] = "Sniper"}
local function knightBranch(pl)
	local cur = pl.Class
	if MF.IsCustomClass and MF.IsCustomClass(cur) then
		local kit = MF.CustomClassKit and MF.CustomClassKit(cur)
		return kit and kit.Branch or nil
	end
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

local TempStore = {}
local function store()
	-- vars doesn't exist yet while a game is being loaded (the regeneration tick can run then)
	if not vars then return TempStore end
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

-- maximum of a resource for a player (Ki: by stage and Meditation)
local function kiMax(pl)
	local _, stage = classFamily(pl.Class)
	local med = SplitSkill(pl:GetSkill(const.Skills.Meditation))
	return math.min(KI.Cap, KI.Base + KI.PerStage * math.min(stage, 2) + math.floor(KI.PerMeditation * med))
end
local function resourceMax(pl, name, r)
	if name == "Ki" then return kiMax(pl) end
	return r.Max
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
	return state(playerIndex(pl)).R, resourceMax(pl, name, r), name
end

local function addResource(pl, v)
	local name, r = resourceOf(pl)
	if not name then return end
	local e = state(playerIndex(pl))
	e.R = math.max(0, math.min(resourceMax(pl, name, r), e.R + v))
	pl.SP = math.floor(e.R)
	e.SPw = pl.SP
end
local addRage = addResource

-- what pays for an ability: the class resource, or the spell points of a hybrid
local function abilityPool(pl)
	if resourceOf(pl) then return state(playerIndex(pl)).R end
	return pl.SP
end
local function spendAbility(pl, cost)
	if cost <= 0 then return end
	if resourceOf(pl) then addResource(pl, -cost) else pl.SP = math.max(0, pl.SP - cost) end
end

-- the resource maximum instead of the spell points
mem.hookfunction(0x48DA18, 1, 0, function(d, def, this)
	local pl = playerFromPtr(this)
	local name, r
	if pl then name, r = resourceOf(pl) end
	if r then return resourceMax(pl, name, r) end
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
		local spot = fam.Spots and fam.Spots[key] or a.Spell
		local needStage = fam.Stages and fam.Stages[key] or a.Stage
		if spot == spell and stage >= needStage
				and not (a.TrollOnly and not troll) and not (a.NotTroll and troll)
				and not (a.Branch and knightBranch(pl) ~= a.Branch)
				and not (a.Branches and not a.Branches[knightBranch(pl) or ""]) then
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

-- MM8 spellbook tabs (init_spellbook_dialog): a page's tab is made only if the player has
-- the school's skill ("cmp word [eax+390h+page*2], bx / je skip", eax = player). For the
-- family's ability page the check is skipped. The page shown is read later in the same
-- routine (0x4CAA13), so a book that would open on a page without the skill opens on the
-- ability page.
local TAB_CHECKS = {}
for page = 1, 11 do   -- the checks are 7Bh apart; the tab is made right after the je
	local cmp = 0x4CA3E8 + (page - 1) * 0x7B
	TAB_CHECKS[page] = {cmp, cmp + 9}
end
for page, adr in pairs(TAB_CHECKS) do
	mem.autohook(adr[1], function(d)
		local pl = playerFromPtr(d.eax)
		if not pl or pageOf(pl) ~= page then return end
		local cur = pl.SpellBookPage
		if cur ~= page and pl.Skills[const.Skills.Fire + cur] == 0 then pl.SpellBookPage = page end
		if pl.Skills[const.Skills.Fire + page] == 0 then
			d:push(adr[2])
			return true
		end
	end)
end

-- the family's own page picture and tab for its ability page: the spellbook dialog
-- (init_spellbook_dialog) makes the tabs from the names "stXu"/"stXd" and each page loads
-- its background "SBX000" (language LOD) by name, all from fixed 8-byte strings in .data.
-- Before the tabs are made the strings of the family's page are set to its own pictures
-- (waffel.icons.lod / waffel.D.lod), and put back for everyone else.
local PAGE_ART = {
	Barbarian = {Page = "SBR000", Tab = "STRG"},
	Knight    = {Page = "SBKN000", Tab = "STKN"},
	Paladin   = {Page = "SBKN000", Tab = "STKN"},   -- the Defensive stance comes from the knights
	Monk      = {Page = "SBMK000", Tab = "STMK"},
	Thief     = {Page = "SBTH000"},
	Archer    = {Page = "SBHY000"},
	["Dark Elf"] = {Page = "SBHY000"},
	Ranger    = {Page = "SBHY000"},
}
local ART_STR = {   -- page: background, tab up, tab down
	[0] = {0x502054, 0x50204C, 0x502044}, {0x50205C, 0x50203C, 0x502034}, {0x502064, 0x50202C, 0x502024},
	{0x50206C, 0x50201C, 0x502014}, {0x502074, 0x50200C, 0x502004}, {0x50207C, 0x501FFC, 0x501FF4},
	{0x502084, 0x501FEC, 0x501FE4}, {0x50208C, 0x501FDC, 0x501FD4}, {0x5020C4, 0x501FCC, 0x501FC4},
}
local ART_ORIG = {}
for page, t in pairs(ART_STR) do
	ART_ORIG[page] = {mem.string(t[1]), mem.string(t[2]), mem.string(t[3])}
end
local function setArtString(addr, str)
	if #str > 7 then return end   -- 8-byte slots
	mem.copy(addr, str, #str)
	u1[addr + #str] = 0
end
local function applyPageArt(pl)
	for page, t in pairs(ART_STR) do
		local o = ART_ORIG[page]
		setArtString(t[1], o[1]); setArtString(t[2], o[2]); setArtString(t[3], o[3])
	end
	local fam = pl and familyOf(pl)
	local art = fam and fam.Page and PAGE_ART[fam.Name]
	local t = art and ART_STR[fam.Page]
	if not t then return end
	if art.Page then setArtString(t[1], art.Page) end
	if art.Tab then setArtString(t[2], art.Tab .. "u"); setArtString(t[3], art.Tab .. "d") end
end
MF.ApplyPageArt = applyPageArt
-- init_spellbook_dialog: the player is known ([ebp-10h]), the Fire tab is made next
mem.autohook(0x4CA36A, function(d)
	applyPageArt(playerFromPtr(u4[d.ebp - 0x10]))
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

-- cost of a real spell for a player with a resource (SpellsExtra.lua description):
-- resource name and cost, or nil
function MF.ResourceSpellCost(pl, sp)
	local name, r = resourceOf(pl)
	if not name then return end
	local div = r.SpellCostDiv or 1
	if r.SpellCostMul then return name, sp * r.SpellCostMul end
	return name, div > 1 and math.max(1, math.ceil(sp / div)) or sp
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


local Pending = {}     -- abilities carried out on the next tick
local Effects = {}     -- [pi] = {Berserk = time, TrollsBlood = {Until, PerMinute}}
local PartyEffects = {WarCry = 0}
local RageStrikeActive = false
local FlurryActive = false
local FinisherPoints              -- combo points of the Finisher being struck

-- Finisher with 5 combo points: a quick steal attempt (as Stealing.lua's, without the
-- risk of being caught: the blow covers it)
local function stealFrom(pl, mon)
	local total = GetStealingTotalSkill and GetStealingTotalSkill(pl) or SplitSkill(pl:GetSkill(const.Skills.Stealing))
	if total <= 0 or total < mon.Level then return end
	if not mon.TreasureGenerated then mem.call(0x408E89, 1, mon["?ptr"]) end
	if math.random(100) > total - mon.Level then return end
	if mon.Items[3].Bonus2 > 0 then
		Party.AddGold(mon.Items[3].Bonus2, 0)
		Game.ShowStatusText(string.format(Game.GlobalTxt[302], pl.Name, mon.Items[3].Bonus2))
		mon.Items[3].Bonus2 = 0
		mon.Items[3].Number = 0
		return
	end
	if Mouse.Item.Number ~= 0 then return end
	for i = 0, 2 do
		local it = mon.Items[i]
		if it.Number > 0 then
			mem.call(0x491A27, 1, 0xB20E90, it["?ptr"])
			mem.call(0x403135, 1, it["?ptr"])
			Mouse.Item.Stolen = 1
			Game.ShowStatusText(string.format("%s lifts something from the foe!", pl.Name))
			return
		end
	end
end
local Challenged = {}  -- [monster index] = {pi = challenger, Until = time}
local Marked = {}      -- [monster index] = until (Mark Prey)
local GoreActive = false
-- an ability's melee blow (Rage Strike, Stunning Palm, Flurry, Gore, Finisher) is struck with
-- the game's melee hit routine (0x436E26) from the tick; the damage handlers can't tell it
-- apart from other hits by WhoHitMonster then, so AbilityStrike marks it as melee, and
-- AbilityHit tells whether it landed (the routine rolls the hit itself)
local AbilityStrike, AbilityHit = false, false
local RiposteVec

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

-- abilities that strike a monster in melee reach, and their reach
local MELEE_ABILITIES = {RageStrike = true, StunningPalm = true, Flurry = true, Finisher = true, Gore = true}

-- can the ability be used right now: enough resource, and a monster in reach for the
-- melee ones (Challenge: in its range)
-- bare hands: no weapon in the main hand (a broken one doesn't count), none in the
-- extra hand (a shield is fine) - Stunning Palm and Flurry are unarmed blows
local function bareHanded(pl)
	local main = pl.ItemMainHand
	if main ~= 0 and not pl.Items[main].Broken then return false end
	local extra = pl.ItemExtraHand
	if extra ~= 0 and not pl.Items[extra].Broken then
		local txt = Game.ItemsTxt[pl.Items[extra].Number]
		if txt and txt.Skill ~= const.Skills.Shield then return false end
	end
	return true
end
local UNARMED_ABILITIES = {StunningPalm = true, Flurry = true}

local function hasBow(pl)
	local s = pl.ItemBow
	return s ~= 0 and not pl.Items[s].Broken
end

-- combo points the thief has on a monster in reach now (0 if none)
local function comboInReach(e)
	if not e.Combo or not e.ComboMon then return 0 end
	if meleeTarget(e.ComboMon * 8 + 3) ~= e.ComboMon then return 0 end
	return e.Combo
end

-- Finisher from the attack spell or a quick spell slot: struck when the combo reaches a
-- number rolled from 1 to FINISHER_AUTO_MAX after each finisher (so the thief builds up
-- combos of different length)
local FINISHER_AUTO_MAX = 5

function MF.ClassAbilityUsable(pl, spell)
	local key, a = abilityOf(pl, spell)
	if not a then return false end
	local e = state(playerIndex(pl))
	if a.Cost > 0 and abilityPool(pl) < a.Cost then return false end
	if UNARMED_ABILITIES[key] and not bareHanded(pl) then return false end
	if a.Shot then
		-- armed for the next shot; from a slot only when the game will shoot (no monster in
		-- melee reach) and not already armed
		if not hasBow(pl) then return false end
		if key == "AimedShot" and e.Aimed then return false end
		if key == "Volley" and (e.Volley or 0) > 0 then return false end
		return meleeTarget(nil) == nil
	end
	if key == "MarkPrey" then return meleeTarget(nil, MARK_RANGE) ~= nil end
	if a.Imbue then return hasBow(pl) and (e.Darkfire or 0) <= 0 end
	if key == "Finisher" then
		e.FinisherAt = e.FinisherAt or math.random(1, FINISHER_AUTO_MAX)
		return comboInReach(e) >= e.FinisherAt
	end
	if MELEE_ABILITIES[key] then return meleeTarget(nil) ~= nil end
	if key == "Challenge" then return meleeTarget(nil, CHALLENGE_RANGE) ~= nil end
	return true
end

-- the game lets a character without the school's skill pick the ability. The quick spell
-- key (Source 2, the attack spell) only casts an ability that can be used now; otherwise
-- the game makes its normal attack (a bow shot at a far target) and the turn goes on.
function events.CanPlayerCastSpell(t)
	local pl = playerFromPtr(t.PlayerPtr)
	if not pl or not abilityOf(pl, t.Spell) or t.Source == 4 then return end
	if t.Source == 2 then
		t.Result = MF.ClassAbilityUsable(pl, t.Spell)
	else
		t.Result = true
	end
end

-- Aimed Shot / Volley: pay and arm the next shot(s)
local function armShot(pl, key, a)
	local e = state(playerIndex(pl))
	spendAbility(pl, a.Cost)
	if key == "AimedShot" then
		e.Aimed = true
		Game.ShowStatusText(string.format("%s takes aim", pl.Name), 2)
	else
		e.Volley = VOLLEY_SHOTS
		Game.ShowStatusText(string.format("%s readies a volley", pl.Name), 2)
	end
end

-- The attack spell (MM8patch: the Attack key with an attack spell set, player byte 1C8Eh)
-- and the quick spell key both reach 0x42E84C with the spell in bl and the player in edi;
-- the game then compares the spell's SP cost with the spell points and either queues the
-- cast (0x42E8AF) or makes the normal attack (0x42E923). For an ability the choice is made
-- here: cast it if it can be used now (resource, target in reach, combo), otherwise the
-- normal attack, so a bow shot goes off at a far target and the turn goes on.
mem.autohook(0x42E84C, function(d)
	local pl = playerFromPtr(d.edi)
	local spell = d.ebx % 256
	if not pl or spell == 0 or not abilityOf(pl, spell) then return end
	local key, a = abilityOf(pl, spell)
	local usable = MF.ClassAbilityUsable(pl, spell)
	if usable and a.Shot then
		armShot(pl, key, a)        -- Aimed Shot / Volley: armed, then the game's bow shot
		usable = false
	end
	d:push(usable and 0x42E8AF or 0x42E923)
	return true
end)

local function failCast(pl, text)
	Game.ShowStatusText(text)
	Game.PlaySound(142)
end

-- droids: vars.MMMWE_Resources.Droids[pi] = {Map = map name, Index = monster index, Until = time}
local function droids()
	local st = store()
	st.Droids = st.Droids or {}
	return st.Droids
end
local function isDroidModel(id)
	for _, m in pairs(DROID.Models) do if m == id then return true end end
end
local function monIndex(mon)
	return (mon["?ptr"] - Map.Monsters[0]["?ptr"]) / Map.Monsters[0]["?size"]
end
-- the player's droid on this map, alive, or nil
local function liveDroid(pi)
	local d = droids()[pi]
	if not d or d.Map ~= Map.Name then return end
	local mon = d.Index < Map.Monsters.count and Map.Monsters[d.Index]
	if mon and isDroidModel(mon.Id) and mon.HP > 0 and mon.AIState ~= const.AIState.Removed
			and mon.Ally == 9999 then
		return mon, d
	end
end
local function removeMonster(mon)
	mon.HP = 0
	mon.AIState = const.AIState.Removed
end
local function partyPoint(dist)
	local ang = (Party.Direction or 0) * math.pi / 1024
	return math.floor(Party.X + dist * math.cos(ang)), math.floor(Party.Y + dist * math.sin(ang)), Party.Z
end

local function deployDroid(pl, pi)
	local L = math.max(1, pl.LevelBase or 1)
	local _, stage = classFamily(pl.Class)
	local untilT = Game.Time + DROID.BaseTime + DROID.PerLevel * L
	local mon, d = liveDroid(pi)
	if mon then
		mon.HP = mon.FullHP
		d.Until = untilT
		mon.SpellBuffs[const.MonsterBuff.Summoned or 2].ExpireTime = untilT
		Game.ShowStatusText(string.format("%s repairs the droid", pl.Name))
		return true
	end
	local id = DROID.Models[math.min(math.max(stage, 1), 2)]
	if stage >= 2 and (pl.Class == 126 or pl.Class == 127) then id = DROID.Models.Scientist end
	local x, y, z = partyPoint(DROID.SpawnDist)
	local ok, m, mi = pcall(SummonMonster, id, x, y, z, true)
	if not ok or not m then
		log("Deploy Droid failed: %s", tostring(m))
		return false
	end
	local RS, RM = SplitSkill(MF.TechRepairSkill and MF.TechRepairSkill(pl) or pl:GetSkill(const.Skills.Repair))
	local RSM = RS * RM
	local hp = DROID.HP + DROID.HPPerLevel * L + DROID.HPPerRSM * RSM
	m.Level = math.min(L, 255)
	m.FullHP = hp
	m.HP = hp
	m.ArmorClass = DROID.AC + DROID.ACPerLevel * L + DROID.ACPerRepair * RS
	m.Exp = 0
	m.Bonus, m.BonusMul = 0, 0
	m.SpellChance, m.Spell2Chance = 0, 0
	m.Special = 0
	-- the robot's own energy shot becomes its second attack, used now and then at range
	-- (a melee-first monster with a ranged Attack2 shoots while it can't reach its target)
	local shotType, shotMissile = m.Attack1.Type, m.Attack1.Missile
	m.Attack2Chance = DROID.ShotChance
	m.Attack2.Type = shotType
	m.Attack2.Missile = shotMissile
	m.Attack2.DamageDiceCount = math.min(1 + math.floor(L / 12), 255)
	m.Attack2.DamageDiceSides = DROID.DiceSides
	m.Attack2.DamageAdd = math.min(math.floor(L / 4), 255)
	m.Attack1.Type = const.Damage.Phys
	m.Attack1.DamageDiceCount = math.min(1 + math.floor(L / 8), 255)
	m.Attack1.DamageDiceSides = DROID.DiceSides
	m.Attack1.DamageAdd = math.min(math.floor(L / 4 + RSM / 8), 255)
	m.Attack1.Missile = 0                  -- melee first: it closes in instead of keeping distance
	m.Fly = 0
	pcall(function()
		local res = math.min(DROID.ResMax, DROID.ResBase + DROID.ResPerRepair * RS)
		m.FireResistance, m.AirResistance, m.WaterResistance, m.EarthResistance = res, res, res, res
		m.LightResistance, m.DarkResistance = res, res
		m.MindResistance, m.SpiritResistance, m.BodyResistance = const.MonsterImmune, const.MonsterImmune, const.MonsterImmune
		m.PhysResistance = DROID.PhysBase + DROID.PhysPerMastery * RM
	end)
	m.Ally = 9999                           -- the party's side, as summoned elementals
	m.Group = 0
	m.Summoner = pi * 8 + 4
	pcall(function() m.Hostile = false; m.ShowAsHostile = false end)
	m.GuardX, m.GuardY, m.GuardZ = Party.X, Party.Y, Party.Z
	local b = m.SpellBuffs[const.MonsterBuff.Summoned or 2]
	b.ExpireTime = untilT
	b.Power, b.Skill = 1, 1
	droids()[pi] = {Map = Map.Name, Index = mi or monIndex(m), Until = untilT}
	Game.ShowStatusText(string.format("%s deploys a droid", pl.Name))
	return true
end

-- returns true if the cast was taken over
local function castAbility(pl, pi, spell, targetRef)
	local key, a = abilityOf(pl, spell)
	if not a then return false end
	local e = state(pi)
	local resName = resourceOf(pl)
	if DEBUG then debugMsg("%s uses %s (%s %d, cost %d)", pl.Name, a.Name, resName or "SP", e.R, a.Cost) end
	if a.Cost > 0 and abilityPool(pl) < a.Cost then
		if key == "RageStrike" or a.Attack then
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
		local persBonus = math.max(0, Game.GetStatisticEffect(pl:GetPersonality()))
		Challenged[mi] = {pi = pi, Until = Game.Time + math.floor(CHALLENGE_TIME * (1 + CHALLENGE_PERS * persBonus))}
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
	elseif key == "StunningPalm" or key == "Flurry" then
		if not bareHanded(pl) then
			failCast(pl, string.format("%s needs bare hands", a.Name))
			return true
		end
		local mi = meleeTarget(targetRef)
		if not mi then
			failCast(pl, "No enemy in reach")
			return true
		end
		Pending[#Pending + 1] = {Kind = key, pi = pi, mi = mi}
		pl:SetRecoveryDelay(pl:GetAttackDelay(false))
	elseif a.Shot then
		if not hasBow(pl) then
			failCast(pl, string.format("%s needs a bow", a.Name))
			return true
		end
		armShot(pl, key, a)
		return true
	elseif a.Imbue then
		if not hasBow(pl) then
			failCast(pl, string.format("%s needs a bow", a.Name))
			return true
		end
		e.Darkfire = DARKFIRE_ARROWS
		Game.ShowStatusText(string.format("%s's arrows smoulder with Darkfire", pl.Name))
		pl:SetRecoveryDelay(60)
	elseif key == "MarkPrey" then
		local mi = meleeTarget(targetRef, MARK_RANGE)
		if not mi then
			failCast(pl, "No prey in sight")
			return true
		end
		Marked[mi] = Game.Time + MARK_TIME
		Game.ShowStatusText(string.format("%s marks %s", pl.Name, Game.MonstersTxt[Map.Monsters[mi].Id].Name))
		pl:SetRecoveryDelay(100)
	elseif key == "Gore" then
		local mi = meleeTarget(targetRef)
		if not mi then
			failCast(pl, "No enemy in reach")
			return true
		end
		Pending[#Pending + 1] = {Kind = key, pi = pi, mi = mi}
		pl:SetRecoveryDelay(pl:GetAttackDelay(false))
	elseif key == "DeployDroid" then
		if not deployDroid(pl, pi) then
			failCast(pl, "The droid can't be deployed here")
			return true
		end
		pl:SetRecoveryDelay(150)
	elseif key == "HerdFury" then
		Effects[pi] = Effects[pi] or {}
		Effects[pi].HerdFury = Game.Time + HERD_TIME
		Game.ShowStatusText(string.format("%s is seized by the herd's fury", pl.Name))
		pl:SetRecoveryDelay(60)
	elseif key == "Finisher" then
		local mi = (e.ComboMon and meleeTarget(e.ComboMon * 8 + 3)) or meleeTarget(targetRef)
		if not mi then
			failCast(pl, "No enemy in reach")
			return true
		end
		local pts = (e.ComboMon == mi and e.Combo) or 0
		if pts <= 0 then
			failCast(pl, "No combo points on this target")
			return true
		end
		e.Combo, e.ComboMon = nil, nil
		e.FinisherAt = math.random(1, FINISHER_AUTO_MAX)
		Pending[#Pending + 1] = {Kind = key, pi = pi, mi = mi, Points = pts}
		pl:SetRecoveryDelay(pl:GetAttackDelay(false))
	elseif key == "PoisonedBlade" then
		Effects[pi] = Effects[pi] or {}
		Effects[pi].Poison = ENERGY.PoisonHits
		Game.ShowStatusText(string.format("%s coats the blade with poison", pl.Name))
		pl:SetRecoveryDelay(100)
	elseif key == "ShadowVeil" then
		local S, M = SplitSkill(pl:GetSkill(const.Skills.Stealing))
		for _, id in ipairs({const.PartyBuff.Invisibility, const.PartyBuff.WizardEye}) do
			local b = Party.SpellBuffs[id]
			b.ExpireTime = Game.Time + ENERGY.VeilTime
			b.Power = math.max(S, 1)
			b.Skill = math.max(M, 1)
		end
		Game.ShowStatusText(string.format("%s veils the party in shadows", pl.Name))
		pl:SetRecoveryDelay(100)
	elseif key == "InnerPeace" then
		local C = const.Condition
		for _, c in ipairs({C.Poison1, C.Poison2, C.Poison3, C.Disease1, C.Disease2, C.Disease3, C.Afraid, C.Weak}) do
			pl.Conditions[c] = 0
		end
		Game.ShowStatusText(string.format("%s finds inner peace", pl.Name))
		pl:SetRecoveryDelay(100)
	elseif key == "IronBody" then
		Effects[pi] = Effects[pi] or {}
		Effects[pi].IronBody = Game.Time + IRON_BODY_TIME
		Game.ShowStatusText(string.format("%s's body turns to iron", pl.Name))
		pl:SetRecoveryDelay(60)
	elseif key == "Vanish" then
		Effects[pi] = Effects[pi] or {}
		Effects[pi].Vanish = Game.Time + VANISH_TIME
		Game.ShowStatusText(string.format("%s vanishes from sight", pl.Name))
		pl:SetRecoveryDelay(60)
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
	spendAbility(pl, a.Cost)
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
	-- the dragon's breath attack: paid with Breath; out of breath, the turn passes
	if spell == BREATH.AttackSpell then
		local pl = casterOf(u2[slot + 2], spell)
		if pl and resourceOf(pl) == "Breath" then
			local e = state(playerIndex(pl))
			if e.R >= BREATH.AttackCost then
				addResource(pl, -BREATH.AttackCost)
				return
			end
			Game.ShowStatusText(string.format("%s is out of breath", pl.Name), 2)
			pl:SetRecoveryDelay(BREATH.OutRecovery)
			u2[slot] = 0
			d:push(0x42D45D)
			return true
		end
		return
	end
	if spell <= 0 or spell > 132 then return end
	if bit.band(u1[slot + 8], 1) == 1 then return end          -- spell scroll
	if u2[slot + 10] > 0 then return end                         -- skill set: wand, item, NPC
	local pl = casterOf(u2[slot + 2], spell)
	if DEBUG then
		debugMsg("cast queue: spell %d, caster field %d -> %s", spell, u2[slot + 2], pl and pl.Name or "?")
	end
	if not pl then return end
	if not abilityOf(pl, spell) then
		-- a real spell of a character whose resource pays a share of the spell point cost
		-- (Ki: 1/5): the game sees the resource x SpellCostDiv as spell points for this cast,
		-- and the tick converts what it spent back
		local name, r = resourceOf(pl)
		if r and ((r.SpellCostDiv or 1) > 1 or r.SpellCostMul) then
			local e = state(playerIndex(pl))
			if r.SpellCostMul then
				e.CastSP = math.floor(e.R / r.SpellCostMul)
			else
				e.CastSP = math.floor(e.R) * r.SpellCostDiv
			end
			pl.SP = e.CastSP
		end
		return
	end
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
-- Bitmaps the game itself doesn't load at start (manaO, manaT) are freed by the game when
-- a map is loaded, so a kept pointer goes stale: the bitmap is looked up again whenever the
-- entry at the kept index no longer carries its name (25.10.26).
local RESOURCE_BAR = {}
for name, r in pairs(RESOURCES) do RESOURCE_BAR[name] = r.Bar end
local barOrig, barIdx = nil, {}
local function barPtr(name)
	local lod = Game.IconsLod
	local idx = barIdx[name]
	if idx then
		local ok, same = pcall(function()
			return idx < lod.Bitmaps.count and lod.Bitmaps[idx].Name:lower() == name:lower()
		end)
		if not (ok and same) then idx = nil end
	end
	if not idx then
		local ok, i = pcall(function() return lod:LoadBitmap(name) end)
		if not ok or not i or i < 0 then return end
		idx = i
		barIdx[name] = idx
	end
	return lod.Bitmaps[idx]["?ptr"]
end
local function isOurBar(ptr)
	for name, idx in pairs(barIdx) do
		local ok, p = pcall(function() return Game.IconsLod.Bitmaps[idx]["?ptr"] end)
		if ok and p == ptr then return true end
	end
	return false
end
mem.autohook(0x41B165, function(d)
	local cur = u4[d.ebp - 0x18]
	if not isOurBar(cur) then barOrig = cur end
	local slot = u4[d.ebp - 4]
	local want = barOrig
	if slot < Party.count then
		local fam = familyOf(Party[slot])
		local name = fam and fam.Resource and RESOURCE_BAR[fam.Resource]
		if name then want = barPtr(name) or barOrig end
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

RiposteVec = mem.StaticAlloc(12)
local function abilityBlow(pl, pi, mi, what)
	AbilityStrike, AbilityHit = true, false
	local ok, err = pcall(mem.call, 0x436E26, 2, pi * 8 + 4, mi, RiposteVec)
	AbilityStrike = false
	if not ok then log("%s failed: %s", what, tostring(err)) end
	if not AbilityHit then Game.ShowStatusText(string.format("%s's %s misses", pl.Name, what), 2) end
	return AbilityHit
end
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
					abilityBlow(pl, r.pi, r.mi, "Rage Strike")
					RageStrikeActive = false
				end
			elseif (r.Kind == "StunningPalm" or r.Kind == "Flurry") and pl then
				local mon = Map.Monsters[r.mi]
				if mon and mon.HP > 0 then
					local hit = abilityBlow(pl, r.pi, r.mi, r.Kind == "Flurry" and "Flurry" or "Stunning Palm")
					if r.Kind == "StunningPalm" and hit and mon.HP > 0 then
						local S, M = SplitSkill(pl:GetSkill(const.Skills.Unarmed))
						local res = mon.Resistances[const.Damage.Phys]
						if res ~= const.MonsterImmune and math.random(5, 100) + S + M * 2.5 > res then
							local b = mon.SpellBuffs[const.MonsterBuff.Paralyze]
							b.ExpireTime = math.max(now + STUN_TIME, b.ExpireTime)
							Game.ShowStatusText(string.format("%s stuns %s!", pl.Name, Game.MonstersTxt[mon.Id].Name), 2)
						end
					elseif r.Kind == "Flurry" then
						FlurryActive = true
						for _ = 1, 2 do
							if mon.HP > 0 then abilityBlow(pl, r.pi, r.mi, "Flurry") end
						end
						FlurryActive = false
						Game.ShowStatusText(string.format("%s: Flurry!", pl.Name), 2)
					end
				end
			elseif r.Kind == "Gore" and pl then
				local mon = Map.Monsters[r.mi]
				if mon and mon.HP > 0 then
					Game.ShowStatusText(string.format("%s: Gore!", pl.Name), 2)
					GoreActive = true
					local hit = abilityBlow(pl, r.pi, r.mi, "Gore")
					GoreActive = false
					if hit and mon.HP > 0 and math.random(100) <= GORE_STAGGER then
						local b = mon.SpellBuffs[const.MonsterBuff.Paralyze]
						b.ExpireTime = math.max(now + GORE_STAGGER_TIME, b.ExpireTime)
						Game.ShowStatusText(string.format("%s staggers!", Game.MonstersTxt[mon.Id].Name), 2)
					end
				end
			elseif r.Kind == "Finisher" and pl then
				local mon = Map.Monsters[r.mi]
				if mon and mon.HP > 0 then
					Game.ShowStatusText(string.format("%s: Finisher (%d)!", pl.Name, r.Points), 2)
					FinisherPoints = r.Points
					local hit = abilityBlow(pl, r.pi, r.mi, "Finisher")
					FinisherPoints = nil
					if hit and r.Points >= ENERGY.ComboMax then stealFrom(pl, mon) end
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
		-- droids: shut down when their time is up, brought back when far behind the party
		for pi, d in pairs(droids()) do
			local mon = liveDroid(pi)
			if not mon then
				if d.Map == Map.Name then droids()[pi] = nil end
			elseif now >= d.Until then
				removeMonster(mon)
				droids()[pi] = nil
			else
				mon.GuardX, mon.GuardY, mon.GuardZ = Party.X, Party.Y, Party.Z
				local dx, dy = mon.X - Party.X, mon.Y - Party.Y
				if dx * dx + dy * dy > DROID.FollowDist * DROID.FollowDist then
					local x, y, z = partyPoint(-DROID.SpawnDist)
					mon.X, mon.Y, mon.Z = x, y, z
					mon.AIState = const.AIState.Active
				end
			end
		end
		-- challenges that ran out, or whose monster or knight is gone
		for mi, c in pairs(Challenged) do
			local m = Map.Monsters[mi]
			local k = Party.PlayersArray[c.pi]
			if now >= c.Until or not m or m.HP <= 0 or not k or not k:IsConscious() then Challenged[mi] = nil end
		end
	end

	-- hybrids: spell point refill in combat
	for slot = 0, Party.count - 1 do
		local pl = Party[slot]
		local fam = familyOf(pl)
		if fam and fam.Hybrid and not fam.Resource then
			local e = state(playerIndex(pl))
			local dt = now - (e.HLast or now)
			e.HLast = now
			local C = const.Condition
			if dt > 0 and inCombat and pl.Conditions[C.Dead] == 0 and pl.Conditions[C.Stoned] == 0
					and pl.Conditions[C.Eradicated] == 0 then
				local full = pl:GetFullSP()
				e.HAcc = (e.HAcc or 0) + HYBRID_REFILL * full * dt / const.Minute
				local whole = math.floor(e.HAcc)
				if whole > 0 then
					e.HAcc = e.HAcc - whole
					if pl.SP < full then pl.SP = math.min(full, pl.SP + whole) end
				end
			end
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
			-- a real spell cast with the resource x SpellCostDiv as spell points
			if e.CastSP then
				local spent = e.CastSP - pl.SP
				if spent > 0 then
					local cost = res.SpellCostMul and spent * res.SpellCostMul or math.ceil(spent / res.SpellCostDiv)
					e.R = math.max(0, e.R - cost)
				end
				e.CastSP = nil
			elseif e.SPw and pl.SP < e.SPw then
				-- spent by the game since the last tick (spell point cost): follow
				e.R = math.max(0, e.R - (e.SPw - pl.SP))
			end
			-- refill: none for the dead, stoned and eradicated; half speed for zombies
			local C = const.Condition
			local refill = 1
			if pl.Conditions[C.Dead] ~= 0 or pl.Conditions[C.Stoned] ~= 0 or pl.Conditions[C.Eradicated] ~= 0 then
				refill = 0
			elseif C.Zombie and pl.Conditions[C.Zombie] ~= 0 then
				refill = ZOMBIE_REFILL
			end
			if dt > 0 and resName == "Breath" then
				e.R = math.min(RESOURCES.Breath.Max, e.R + refill * BREATH.PerMinute * dt / const.Minute)
			end
			if dt > 0 and resName == "Energy" then
				e.R = math.min(RESOURCES.Energy.Max, e.R + refill * ENERGY.PerMinute * dt / const.Minute)
				if e.Combo and now - (e.ComboTime or 0) > ENERGY.ComboTime then e.Combo, e.ComboMon = nil, nil end
			end
			if dt > 0 and resName == "Ki" then
				local _, stage = classFamily(pl.Class)
				local med = SplitSkill(pl:GetSkill(const.Skills.Meditation))
				local interval = KI.Interval * math.max(0.5, 1 - KI.IntervalPerMed * med)
				e.R = math.min(kiMax(pl), e.R + refill * (KI.Refill[math.min(stage, 3)] or 1) * dt / interval)
			end
			if dt > 0 and res.IdleTime and now - (e.LastHit or 0) > res.IdleTime then
				e.R = math.max(0, e.R - res.DrainPerMinute * dt / const.Minute)
			end
			if dt > 0 and inCombat and resName == "Resolve" and knightBranch(pl) == "Templar" then
				e.R = math.min(resourceMax(pl, resName, res), e.R + RESOLVE.TemplarPerMinute * dt / const.Minute)
			end
			e.Last = now
			-- anything the game added (refill, potions) is undone
			pl.SP = math.floor(e.R)
			e.SPw = pl.SP

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
	-- droids don't travel between maps: any of the party's droids found here is a leftover
	for i = 0, Map.Monsters.count - 1 do
		local mon = Map.Monsters[i]
		if isDroidModel(mon.Id) and mon.Ally == 9999 and mon.Summoner % 8 == 4 and mon.HP > 0 then
			removeMonster(mon)
		end
	end
	store().Droids = {}
	Challenged = {}
	Marked = {}
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
		local fx = Effects[pi]
		if fx and fx.IronBody and fx.IronBody > Game.Time and t.DamageKind == const.Damage.Phys then
			t.Result = math.max(1, math.floor(t.Result * (1 - IRON_BODY) + 0.5))
		end
		if fx and fx.HerdFury and fx.HerdFury > Game.Time and t.DamageKind == const.Damage.Phys then
			t.Result = math.max(1, math.floor(t.Result * (1 - HERD_PHYS) + 0.5))
		end
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
		if not pl then return end
		-- Mark Prey: the party hits the marked monster harder
		local mk = t.MonsterIndex and Marked[t.MonsterIndex]
		if mk then
			if mk > Game.Time then
				t.Result = math.floor(t.Result * (1 + MARK_DAMAGE) + 0.5)
			else
				Marked[t.MonsterIndex] = nil
			end
		end
		if t.DamageKind == const.Damage.Phys and not t.IsSecondary then
			local who = WhoHitMonster and WhoHitMonster()
			local arrow = not AbilityStrike and type(who) == "table" and who.Object and (who.Spell or 0) == 0 and t.Melee ~= true
			if AbilityStrike then AbilityHit = true end
			local e = state(playerIndex(pl))
			if arrow then
				if e.Aimed then
					e.Aimed = nil
					local m = 1 + AIMED_DAMAGE
					if math.random() < AIMED_CRIT then
						local _, d = MF.GetCritStats(pl, false)
						m = m * math.max(1, d or 1.5)
					end
					t.Result = math.floor(t.Result * m + 0.5)
					Game.ShowStatusText(string.format("%s: Aimed Shot!", pl.Name), 1)
				end
				if (e.Volley or 0) > 0 then e.Volley = e.Volley - 1 end
				-- Darkfire Arrows: extra damage through the lower of Fire and Dark resistance
				if (e.Darkfire or 0) > 0 and t.Monster then
					e.Darkfire = e.Darkfire - 1
					local res = math.min(t.Monster.Resistances[const.Damage.Fire], t.Monster.Resistances[const.Damage.Dark])
					if res ~= const.MonsterImmune then
						local S = SplitSkill(pl:GetSkill(const.Skills.DarkElfAbility))
						local extra = DARKFIRE_SHARE * (t.Damage or t.Result) + DARKFIRE_PER_SKILL * S
						t.Result = t.Result + math.floor(extra * 30 / (30 + math.max(0, res)) + 0.5)
					end
				end
			else
				local fxh = Effects[playerIndex(pl)]
				if fxh and fxh.HerdFury and fxh.HerdFury > Game.Time then
					t.Result = math.floor(t.Result * (1 + HERD_DAMAGE) + 0.5)
				end
				if GoreActive then t.Result = math.floor(t.Result * (1 + GORE_DAMAGE) + 0.5) end
			end
		end
		-- Vanish ends with the ninja's first blow
		local fx = Effects[playerIndex(pl)]
		if fx and fx.Vanish then
			fx.Vanish = nil
			Game.ShowStatusText(string.format("%s reappears", pl.Name))
		end
		if t.DamageKind ~= const.Damage.Phys then return end
		if FlurryActive then t.Result = math.floor(t.Result * FLURRY_DAMAGE + 0.5) end
		if resourceOf(pl) == "Energy" and not t.IsSecondary then
			local isMelee = t.Melee or AbilityStrike
			if not isMelee and t.Melee == nil then
				local who = WhoHitMonster and WhoHitMonster()
				isMelee = type(who) == "table" and not who.Object
			end
			if isMelee then
				local e = state(playerIndex(pl))
				if FinisherPoints then
					local pts = FinisherPoints
					local m = 1 + ENERGY.FinisherDamage * pts
					if pts > 0 and math.random() < ENERGY.FinisherCrit * pts then
						local _, d = MF.GetCritStats(pl, true)
						d = d or 1.5
						if knightBranch(pl) == "Assassin" then d = d + ENERGY.AssassinCritDamage * pts end
						m = m * math.max(1, d)
					end
					t.Result = math.floor(t.Result * m + 0.5)
				elseif t.MonsterIndex then
					if e.ComboMon == t.MonsterIndex then
						e.Combo = math.min(ENERGY.ComboMax, (e.Combo or 0) + 1)
					else
						e.Combo, e.ComboMon = 1, t.MonsterIndex
					end
					e.ComboTime = Game.Time
					Game.ShowStatusText(string.format("%s: combo %d", pl.Name, e.Combo), 1)
				end
				local fxp = Effects[playerIndex(pl)]
				if fxp and fxp.Poison and fxp.Poison > 0 and t.Monster then
					fxp.Poison = fxp.Poison - 1
					if t.Monster.Resistances[const.Damage.Body] ~= const.MonsterImmune then
						t.Result = math.floor(t.Result * (1 + ENERGY.PoisonDamage) + 0.5)
					end
					if fxp.Poison <= 0 then fxp.Poison = nil end
				end
			end
		end
		local melee = t.Melee or AbilityStrike
		if not melee and t.Melee == nil then
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
		-- Volley: quick recovery of the armed bow shots
		local ev = store()[playerIndex(pl)]
		if ev and (ev.Volley or 0) > 0 and t.Ranged then t.Result = t.Result * VOLLEY_RECOVERY end
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
		-- Vanish: a vanished character is not picked while someone else can be
		local slot = t.Slot
		local fxv = slot and slot >= 0 and slot < Party.count and Effects[Party.PlayersIndexes[slot]]
		if fxv and fxv.Vanish and fxv.Vanish > Game.Time then
			local others = {}
			for s = 0, Party.count - 1 do
				local fx2 = Effects[Party.PlayersIndexes[s]]
				if s ~= slot and Party[s]:IsConscious() and not (fx2 and fx2.Vanish and fx2.Vanish > Game.Time) then
					others[#others + 1] = s
				end
			end
			if #others > 0 then t.Slot = others[math.random(#others)] end
		end
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
	local res = fam.Resource and string.format("%s %.1f / %d", fam.Resource, e.R,
		resourceMax(pl, fam.Resource, RESOURCES[fam.Resource])) or "spell points"
	return string.format("%s family, stage %d%s%s: %s%s", fam.Name, stage, isTroll(pl) and " (Troll)" or "",
		knightBranch(pl) and (" (" .. knightBranch(pl) .. ")") or "", res,
		stance and (", " .. stance .. " stance") or "")
end
