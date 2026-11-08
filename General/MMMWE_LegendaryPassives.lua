--[[
	MMMWE_LegendaryPassives.lua — the passive abilities of the Legendary skills (07.11.26)

	The fifth mastery (MMMWE_LegendaryMastery.lua) gives each Legendary skill one passive
	ability, set here: its name and text (LEGEND.Passives, shown in the skill's popup and by
	the teacher) and its effect. The numbers are in P below.

	Weapons
	  Staff    Spellstaff       wielding a staff: spells cost 15% less SP; a second stun roll
	  Sword    Riposte          10%: a monster's melee blow is parried and answered
	  Dagger   Assassin         a dagger in hand: double crit chance; crits ignore physical resistance
	  Axe      Cleave           an axe blow also hits a foe next to the target for 50%
	  Spear    Impale           a spear in hand: hits as if the target had half its AC; +AC = Spear skill
	  Bow      Volley           three arrows a shot
	  Mace     Crushing Blows   a second stun and paralyze roll; the target gets no resistance roll
	  Blaster  Overcharge       half the cell charge a shot; +20% damage
	Armor
	  Shield   Bulwark          a shield in hand: 20% to block a missile or a spell bolt
	  Leather  Light Step       leather armor: 10% to evade a monster's blow or missile
	  Chain    Interlinked      chain armor: -20% Fire, Air, Water and Earth damage
	  Plate    Unbreakable      plate armor takes no wear; Paralysis and Stone don't hold
	Magic (the school's spells: -25% SP and +25% effect - damage, durations, powers, healing)
	  Fire     half the target's fire resistance is ignored
	  Air      the school's spells recover 25% faster
	  Water    Town Portal and Lloyd's Beacon cost no SP
	  Earth    Stone Skin and Rock Blast twice as strong
	  Spirit   Raise Dead and Resurrection leave no Weakness
	  Mind     Charm, Berserk, Mass Fear and Enslave can't be resisted by a monster of the
	           caster's level or lower
	  Body     Heal and Power Cure cure Poison and Disease as well
	  Light    the school's buffs last twice as long
	  Dark     the school's damage heals the caster for 10% of it
	Racial (the ability's spells) +50% power
	Misc
	  Identify Item  Appraiser         the party's items get identified; this character sells 10% dearer
	  Merchant       Trade Prince      this character buys at half price and sells at full value
	  Repair         Master Smith      the party's equipment wears at half the rate; broken items
	                                    are mended while resting
	  Bodybuilding   Titan             HP from Bodybuilding doubled; no Weakness
	  Meditation     Clarity           SP from Meditation doubled; 1% of SP back every 5 minutes
	  Perception     Sixth Sense       chest and map traps do the party no harm; +20% gold found
	  Regeneration   Undying           once a day a fatal blow leaves 1 HP
	  Disarm Traps   Lockbreaker       chests open with their traps disarmed
	  Dodging        Shadow            15% to evade any attack, spells too
	  Unarmed        Iron Fist         bare-handed blows always hit and strike twice
	  Identify Monster Know Thy Enemy  the whole party deals +10% damage
	  Armsmaster     Weapon Master     weapon skills count 5 higher; 10% faster recovery
	  Stealing       Phantom           shop theft costs no reputation; double gold from corpses
	  Alchemy        Philosopher's Stone  potions brewed from reagents are 50% stronger
	  Learning       Sage              +10% experience for the whole party

	Mixed abilities (party-wide ones) work while their owner is in the party.
--]]

local MF = Merge.Functions
local Tx, Tn = Merge.Functions.Text, Merge.Functions.TextKey
local LEGEND = MF.LegendarySettings
if not LEGEND then
	return
end

local SK = const.Skills
local CD = const.Condition
local DMG = const.Damage
local floor, max, min, random = math.floor, math.max, math.min, math.random
local u2, u4, i4 = mem.u2, mem.u4, mem.i4

local P = {
	StaffSPMul        = 0.85,
	RiposteChance     = 0.10,
	DaggerCritMul     = 2,
	CleaveShare       = 0.5,
	CleaveRange       = 350,
	BowArrows         = 3,
	BlasterCellMul    = 0.5,
	BlasterDamageMul  = 1.2,
	ShieldBlock       = 0.20,
	LeatherEvade      = 0.10,
	ChainElementMul   = 0.8,
	SchoolSPMul       = 0.75,
	SchoolEffectMul   = 1.25,
	AirRecoveryMul    = 0.75,
	EarthDoubleMul    = 2,
	LightDurationMul  = 2,
	DarkLeech         = 0.10,
	RacialMul         = 1.5,
	AppraiserSellMul  = 1.1,
	MerchantBuyMul    = 0.5,
	RepairWearMul     = 0.5,
	MeditationRegen   = 0.01,
	PerceptionGoldMul = 1.2,
	DodgeChance       = 0.15,
	KnowEnemyMul      = 1.1,
	ArmsmasterSkill   = 5,
	ArmsmasterDelay   = 0.9,
	CorpseGoldMul     = 2,
	AlchemyMul        = 1.5,
	LearningBonus     = 10,
}
LEGEND.Effects = P

local function passive(skill, name, text)
	LEGEND.Passives[skill] = {Name = name, Text = text}
end
passive(SK.Staff, Tx"Spellstaff", Tx"wielding a staff, spells cost 15% less SP and blows get a second stun roll")
passive(SK.Sword, Tx"Riposte", Tx"10% chance to parry a monster's melee blow completely and strike back (sword in hand)")
passive(SK.Dagger, Tx"Assassin", Tx"with a dagger in hand, double critical chance; critical hits ignore physical resistance")
passive(SK.Axe, Tx"Cleave", Tx"each axe blow also hits a foe next to the target for 50% damage")
passive(SK.Spear, Tx"Impale", Tx"with a spear in hand, blows hit as if the target had half its AC, and +AC equal to the Spear skill")
passive(SK.Bow, Tx"Volley", Tx"three arrows a shot")
passive(SK.Mace, Tx"Crushing Blows", Tx"a second stun and paralyze roll, and the target gets no resistance roll against them")
passive(SK.Blaster, Tx"Overcharge", Tx"shots use half the cell charge and deal 20% more damage")
passive(SK.Shield, Tx"Bulwark", Tx"with a shield in hand, 20% chance to block a missile or a spell bolt completely")
passive(SK.Leather, Tx"Light Step", Tx"in leather armor, 10% chance to evade a monster's blow or missile")
passive(SK.Chain, Tx"Interlinked", Tx"in chain armor, 20% less Fire, Air, Water and Earth damage")
passive(SK.Plate, Tx"Unbreakable", Tx"worn plate armor takes no wear; Paralysis and Stone don't hold")
local SCHOOL_TEXT = Tx"the school's spells cost 25% less SP and are 25% stronger (damage, duration, power, healing)"
passive(SK.Fire, Tx"Archmage of Fire", SCHOOL_TEXT .. Tx"; half the target's fire resistance is ignored")
passive(SK.Air, Tx"Archmage of Air", SCHOOL_TEXT .. Tx"; they recover 25% faster")
passive(SK.Water, Tx"Archmage of Water", SCHOOL_TEXT .. Tx"; Town Portal and Lloyd's Beacon cost no SP")
passive(SK.Earth, Tx"Archmage of Earth", SCHOOL_TEXT .. Tx"; Stone Skin and Rock Blast are twice as strong instead")
passive(SK.Spirit, Tx"Archmage of Spirit", SCHOOL_TEXT .. Tx"; Raise Dead and Resurrection leave no Weakness")
passive(SK.Mind, Tx"Archmage of Mind", SCHOOL_TEXT .. Tx"; Charm, Berserk, Mass Fear and Enslave can't be resisted by monsters of the caster's level or lower")
passive(SK.Body, Tx"Archmage of Body", SCHOOL_TEXT .. Tx"; Heal and Power Cure cure Poison and Disease as well")
passive(SK.Light, Tx"Archmage of Light", SCHOOL_TEXT .. Tx"; the durations are doubled instead")
passive(SK.Dark, Tx"Archmage of Dark", SCHOOL_TEXT .. Tx"; their damage heals the caster for 10% of it")
passive(SK.DarkElfAbility, Tx"Heir of the Dark Elves", Tx"the Dark Elf abilities are 50% stronger")
passive(SK.VampireAbility, Tx"Elder Blood", Tx"the Vampire abilities are 50% stronger")
passive(SK.DragonAbility, Tx"Ancient Wyrm", Tx"the Dragon abilities and the breath are 50% stronger")
passive(SK.IdentifyItem, Tx"Appraiser", Tx"every item the party carries is identified, and this character sells 10% dearer")
passive(SK.Merchant, Tx"Trade Prince", Tx"this character buys at half price and sells at full value")
passive(SK.Repair, Tx"Master Smith", Tx"the party's equipment wears at half the rate, and broken items are mended while resting")
passive(SK.Bodybuilding, Tx"Titan", Tx"HP from Bodybuilding doubled, and Weakness doesn't hold")
passive(SK.Meditation, Tx"Clarity", Tx"SP from Meditation doubled, and 1% of SP comes back every 5 minutes")
passive(SK.Perception, Tx"Sixth Sense", Tx"chest and map traps do the party no harm, and 20% more gold is found")
passive(SK.Regeneration, Tx"Undying", Tx"once a day, a fatal blow leaves 1 HP instead")
passive(SK.DisarmTraps, Tx"Lockbreaker", Tx"chests always open with their traps disarmed")
passive(SK.Dodging, Tx"Shadow", Tx"15% chance to evade any attack, spells included")
passive(SK.Unarmed, Tx"Iron Fist", Tx"bare-handed blows always hit and strike twice")
passive(SK.IdentifyMonster, Tx"Know Thy Enemy", Tx"the whole party deals 10% more damage")
passive(SK.Armsmaster, Tx"Weapon Master", Tx"all weapon skills count 5 higher, and recovery is 10% faster")
-- (08.11.26) the new skill of MMMWE_ExtraSkills.lua (its effect: MMMWE_ExtraSkillsEffects.lua)
passive(41, Tx"Twin Titans", Tx"a two-handed weapon in each hand without penalties")
passive(42, Tx"Unseen", Tx"without body armor, monsters pick this character as a target half as often (threat halved)")

-- Robe: the threat of MMMWE_Threat.lua halved while no body armor is worn (as Robe's own effects)
P.RobeThreatMul = 0.5
function MF.LegendaryThreatMult(pl)
	if not MF.IsLegendary(pl, 42) then return 1 end
	local slot = pl.ItemArmor
	if slot > 0 and not pl.Items[slot].Broken and pl.Items[slot].Number > 0 then return 1 end
	return P.RobeThreatMul
end
passive(SK.Stealing, Tx"Phantom", Tx"stealing from shops costs no reputation, and corpses give double gold")
passive(SK.Alchemy, Tx"Philosopher's Stone", Tx"potions brewed from reagents are 50% stronger")
passive(SK.Learning, Tx"Sage", Tx"the whole party gains 10% more experience")

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------

local function any()
	local s = vars and vars.MMMWE_Legendary
	return s ~= nil and next(s) ~= nil
end

local L = MF.IsLegendary

local function rosterOf(pl)
	local arr = Party.PlayersArray
	return floor((pl["?ptr"] - arr["?ptr"]) / arr[0]["?size"] + 0.5)
end

local function monsterFromPtr(p)
	local arr = Map.Monsters
	local i = (p - arr["?ptr"]) / arr[0]["?size"]
	if i >= 0 and i < arr.count and i == floor(i) then return arr[i], i end
end

local function playerFromPtr(p)
	local arr = Party.PlayersArray
	local i = (p - arr["?ptr"]) / arr[0]["?size"]
	if i >= 0 and i < arr.count and i == floor(i) then return arr[i], i end
end

-- the Legendary owner of a skill in the party, if any
local function partyLegend(skill)
	if not any() then return end
	for i = 0, Party.Count - 1 do
		local pl = Party[i]
		if L(pl, skill) and pl:IsConscious() then return pl end
	end
end

local function itemSkill(pl, slot)
	if slot <= 0 then return end
	local it = pl.Items[slot]
	if it.Number <= 0 or it.Broken then return end
	return Game.ItemsTxt[it.Number].Skill
end
local function mainSkill(pl) return itemSkill(pl, pl.ItemMainHand) end
local function extraSkill(pl) return itemSkill(pl, pl.ItemExtraHand) end
local function armorSkill(pl) return itemSkill(pl, pl.ItemArmor) end

local function bareHanded(pl)
	if MF.IsBareHanded then return MF.IsBareHanded(pl) end
	return pl.ItemMainHand == 0
end

local function skillLevel(pl, skill)
	return (SplitSkill(pl:GetSkill(skill)))
end

-- the school (skill) of a spell, and the racial ability of the racial spells
local function spellSkill(spell)
	if not spell or spell <= 0 then return end
	if spell <= 99 then return 12 + floor((spell - 1) / 11) end
	if spell >= 100 and spell <= 110 then return SK.DarkElfAbility end
	if spell >= 111 and spell <= 121 then return SK.VampireAbility end
	if (spell >= 122 and spell <= 132) or spell == 137 then return SK.DragonAbility end
end
local RACIAL = {[SK.DarkElfAbility] = true, [SK.VampireAbility] = true, [SK.DragonAbility] = true}

local function status(text)
	Game.ShowStatusText(text, 2)
end

---------------------------------------------------------------------------
-- spell variables: the names of the variables of SpellsExtra.txt (VarNum -> name)
---------------------------------------------------------------------------

local VarNames = {}
do
	local f = io.open("Data/Tables/SpellsExtra.txt", "r")
	if f then
		for line in f:lines() do
			local w = {}
			for s in (line .. "\t"):gmatch("([^\t]*)\t") do w[#w + 1] = s end
			local spell = tonumber(w[1])
			if spell then
				local names, k, i = {}, 1, 47
				while w[i] do
					local n = w[i]:match("^%s*(.-)%s*$")
					if n ~= "" and not tonumber(n) then names[k] = n end
					k, i = k + 1, i + 5
				end
				VarNames[spell] = names
			end
		end
		f:close()
	end
end

-- variables that are an effect's strength or duration
local EFFECT_VARS = {}
for _, n in ipairs{"Duration", "DurationConst", "Duration1", "Duration1Const", "Duration2", "Duration2Const",
		"ArmorBonus", "ArmorPerLevel", "AttrBonus", "AttrPerLevel", "BonusHPPerLevel", "DamageBonus",
		"DamagePerLevel", "HPBonus", "HPPerLevel", "HealBonus", "HealPerLevel", "Power", "PowerBonus",
		"PowerPerLevel", "ResBonus", "ResPerLevel", "StatBonus", "StatPerLevel", "ToHitBonus", "ToHitConst",
		"ToHitPerLevel", "CountBonus", "CountPerLevel", "CondDuration", "CondDurationConst", "SpcBonus"} do
	EFFECT_VARS[n] = true
end
local DURATION_VAR = {Duration = true, DurationConst = true, Duration1 = true, Duration1Const = true,
	Duration2 = true, Duration2Const = true}

local function scale(v, m)
	if type(v) ~= "number" or v == 0 then return v end
	return floor(v * m + 0.5)
end

---------------------------------------------------------------------------
-- spell cost and recovery: Staff, the schools (and Water's portals, Air's recovery)
---------------------------------------------------------------------------

function events.SpellCostRecovery(t)
	if not any() or t.Spell >= 133 then return end
	local pl = Party[max(0, t.Caster - 35)]   -- as SpellsExtra.lua finds the caster
	if not pl then return end
	local school = spellSkill(t.Spell)
	local mul = 1
	if L(pl, SK.Staff) and mainSkill(pl) == SK.Staff then mul = mul * P.StaffSPMul end
	if school and L(pl, school) then
		mul = mul * P.SchoolSPMul
		if school == SK.Water and (t.Spell == 31 or t.Spell == 33) then mul = 0 end
		if school == SK.Air then t.Recovery = floor(t.Recovery * P.AirRecoveryMul + 0.5) end
	end
	if mul ~= 1 then t.Cost = floor(t.Cost * mul + 0.5) end
end

---------------------------------------------------------------------------
-- spell variables: +25% effect, Light's durations, Stone Skin, racial abilities,
-- Spirit's revivals and Body's cures
---------------------------------------------------------------------------

local Revived = {}    -- {slot, until}: Weakness to lift once the character is up

local function cureBody(pl)
	for _, c in ipairs{CD.Poison1, CD.Poison2, CD.Poison3, CD.Disease1, CD.Disease2, CD.Disease3} do
		pl.Conditions[c] = 0
	end
end

function events.PlayerSpellVar(t)
	if not any() or not t.Player then return end
	local pl, spell = t.Player, t.Spell
	local skill = spellSkill(spell)
	if not skill or not L(pl, skill) then return end
	local name = VarNames[spell] and VarNames[spell][t.VarNum]
	if name and EFFECT_VARS[name] then
		local m
		if RACIAL[skill] then
			m = P.RacialMul
		elseif skill == SK.Light and DURATION_VAR[name] then
			m = P.LightDurationMul
		elseif spell == 38 and (name == "ArmorBonus" or name == "ArmorPerLevel") then
			m = P.EarthDoubleMul
		else
			m = P.SchoolEffectMul
		end
		t.Value = scale(t.Value, m)
	end
	-- once per cast is enough for these: the first variable read
	if t.VarNum == 1 then
		if skill == SK.Spirit and (spell == 53 or spell == 55) then
			Revived[#Revived + 1] = {Slot = t.Target, Until = Game.Time + const.Hour}
		elseif skill == SK.Body and spell == 68 then
			local target = Party[t.Target]
			if target then cureBody(target) end
		elseif skill == SK.Body and spell == 77 then
			for i = 0, Party.Count - 1 do cureBody(Party[i]) end
		end
	end
end

---------------------------------------------------------------------------
-- Mind: control spells against monsters of the caster's level or lower can't be resisted
---------------------------------------------------------------------------

local MIND_CONTROL = {[60] = true, [62] = true, [63] = true, [66] = true}
local SpellCtx       -- {Spell, Player} of the spell being processed
local MaceTarget     -- the monster a Legendary mace blow is hitting (this tick)

function events.PlayerSpellProc(t)
	SpellCtx = nil
	if not any() then return end
	local pl = Party.PlayersArray[t.Caster]
	if pl and MIND_CONTROL[t.Spell] and L(pl, SK.Mind) then
		SpellCtx = {Spell = t.Spell, Player = pl}
	end
end

-- monster_resists_condition (this, monster, damage kind): 1 = the spell or blow takes
mem.hookfunction(0x425A4F, 1, 2, function(d, def, this, mon, kind)
	local ctx = SpellCtx
	if ctx and kind == DMG.Mind then
		local m = monsterFromPtr(mon)
		if m and m.Level <= (ctx.Player.LevelBase or 0) then
			return 1
		end
	end
	if kind == DMG.Earth and MaceTarget and MaceTarget == mon then
		return 1   -- Mace: the paralysis of the target of a Legendary mace blow
	end
	return def(this, mon, kind)
end)

---------------------------------------------------------------------------
-- melee: Staff's and Mace's second rolls, Mace without resistance roll
---------------------------------------------------------------------------

-- damage_monster_from_party, after the stun ([ebp-0x24]) and paralyze ([ebp-0x38]) rolls
mem.autohook(0x437239, function(d)
	if not any() then return end
	local pl = playerFromPtr(u4[d.ebp - 8])
	if not pl then return end
	local ms = mainSkill(pl)
	if ms == SK.Staff and L(pl, SK.Staff) then
		if i4[d.ebp - 0x24] == 0 and random(100) <= skillLevel(pl, SK.Staff) then i4[d.ebp - 0x24] = 1 end
	elseif ms == SK.Mace and L(pl, SK.Mace) then
		MaceTarget = d.esi
		local lvl = skillLevel(pl, SK.Mace)
		if i4[d.ebp - 0x24] == 0 and random(100) <= lvl then i4[d.ebp - 0x24] = 1 end
		if i4[d.ebp - 0x38] == 0 and random(100) <= lvl then i4[d.ebp - 0x38] = 1 end
	end
end)

-- the stun's resistance roll (0x437713) is decided by SpellsTweaks.lua's hook, which asks this;
-- the paralysis's goes through the hook of 0x425A4F above (MaceTarget)
function MF.LegendaryMaceNoResist(d)
	if not any() then return false end
	local pl = playerFromPtr(u4[d.ebp - 8])
	return pl ~= nil and mainSkill(pl) == SK.Mace and L(pl, SK.Mace)
end

---------------------------------------------------------------------------
-- hitting: Unarmed always hits, Spear against half the AC
---------------------------------------------------------------------------

-- CalcHitOrMiss (this, player, monster, range, bonus)
mem.hookfunction(0x4256DB, 1, 4, function(d, def, this, plp, monp, range, bonus)
	if any() then
		local pl = playerFromPtr(plp)
		if pl then
			if range == 0 and bareHanded(pl) and L(pl, SK.Unarmed) then
				return 1
			end
			if mainSkill(pl) == SK.Spear and L(pl, SK.Spear) then
				local ac = i4[monp + 0x78]
				i4[monp + 0x78] = floor(ac / 2)
				local r = def(this, plp, monp, range, bonus)
				i4[monp + 0x78] = ac
				return r
			end
		end
	end
	return def(this, plp, monp, range, bonus)
end)

---------------------------------------------------------------------------
-- Bow: three arrows (the case of the arrows in the cast code: [ebp-0x34] arrows)
---------------------------------------------------------------------------

mem.autohook(0x42634E, function(d)
	if not any() then return end
	local pl = playerFromPtr(u4[d.ebp - 0x1C])
	if pl and L(pl, SK.Bow) and i4[d.ebp - 0x34] < P.BowArrows then
		i4[d.ebp - 0x34] = P.BowArrows
	end
end)

---------------------------------------------------------------------------
-- Alchemy: a potion brewed from a reagent (reagent power + Alchemy skill, 0x415818)
---------------------------------------------------------------------------

mem.autohook(0x415818, function(d)
	if not any() then return end
	local pl = playerFromPtr(d.esi)
	if pl and L(pl, SK.Alchemy) then
		d.eax = floor(d.eax * P.AlchemyMul)
	end
end)

---------------------------------------------------------------------------
-- stats: Bodybuilding, Meditation, Spear's AC; Armsmaster's skills and recovery
---------------------------------------------------------------------------

function events.CalcStatBonusBySkills(t)
	if not any() or not t.Player then return end
	local pl = t.Player
	if t.Stat == const.Stats.HP and L(pl, SK.Bodybuilding) then
		t.Result = t.Result * 2
	elseif t.Stat == const.Stats.SP and L(pl, SK.Meditation) then
		t.Result = t.Result * 2
	elseif t.Stat == const.Stats.ArmorClass and mainSkill(pl) == SK.Spear and L(pl, SK.Spear) then
		t.Result = t.Result + (SplitSkill(pl.Skills[SK.Spear]))
	end
end

local WEAPON_SKILL = {[SK.Staff] = true, [SK.Sword] = true, [SK.Dagger] = true, [SK.Axe] = true,
	[SK.Spear] = true, [SK.Bow] = true, [SK.Mace] = true, [SK.Blaster] = true}

function events.GetSkill(t)
	if not WEAPON_SKILL[t.Skill] or not any() or not t.Player then return end
	if L(t.Player, SK.Armsmaster) then
		local lvl = t.Result % 0x100
		if t.Result > 0 and lvl + P.ArmsmasterSkill <= 0xFF then
			t.Result = t.Result + P.ArmsmasterSkill
		end
	end
end

function events.GetAttackDelay(t)
	if any() and t.Player and L(t.Player, SK.Armsmaster) then
		t.Result = floor(t.Result * P.ArmsmasterDelay)
	end
end

function events.GetLearningTotalSkill(t)
	if partyLegend(SK.Learning) then
		t.Result = t.Result + P.LearningBonus
	end
end

---------------------------------------------------------------------------
-- regeneration: Meditation; resting: Repair mends broken items
---------------------------------------------------------------------------

function events.Regeneration(t)
	if not any() or not t.Player then return end
	local pl = t.Player
	if L(pl, SK.Meditation) and pl:IsConscious() then
		t.SP = (t.SP or 0) + max(1, floor(pl:GetFullSP() * P.MeditationRegen))
	end
end

function events.RegenTick(pl)
	if Game.CurrentScreen ~= const.Screens.Rest or not partyLegend(SK.Repair) then return end
	for j = 1, pl.Items.high do
		local it = pl.Items[j]
		if it.Number > 0 and it.Broken then it.Broken = false end
	end
end

---------------------------------------------------------------------------
-- prices (MMMWE_Economy.lua): Merchant and Identify Item
---------------------------------------------------------------------------

function events.CalcEconomyPrice(t)
	if not any() or not t.Player then return end
	local pl = t.Player
	if t.Kind == "Buy" and L(pl, SK.Merchant) then
		t.Result = max(1, floor(t.Result * P.MerchantBuyMul))
	elseif t.Kind == "Sell" then
		if L(pl, SK.Merchant) and t.Value then
			t.Result = max(t.Result, t.Value)
		elseif L(pl, SK.IdentifyItem) then
			t.Result = floor(t.Result * P.AppraiserSellMul)
		end
	end
end

---------------------------------------------------------------------------
-- gold and traps: Perception, Disarm Traps, Stealing
---------------------------------------------------------------------------

local CorpseGold = false

function events.PickCorpse(t)
	CorpseGold = partyLegend(SK.Stealing) ~= nil
end

function events.BeforeGotGold(t)
	if not any() then return end
	local mul = 1
	if partyLegend(SK.Perception) then mul = mul * P.PerceptionGoldMul end
	if CorpseGold then mul = mul * P.CorpseGoldMul end
	CorpseGold = false
	if mul ~= 1 then t.Amount = floor(t.Amount * mul) end
end

function events.BeforeChestTrapTriggered(t)
	local pl = partyLegend(SK.DisarmTraps) or partyLegend(SK.Perception)
	if pl then
		t.Handled = true
		t.CanOpenChest = true
		status(string.format(L(pl, SK.DisarmTraps) and Tx"%s disarms the trap" or Tx"%s sidesteps the trap", pl.Name))
	end
end

-- Stealing.lua asks this for its shop reputation
function MF.LegendaryNoTheftReputation(pl)
	return pl ~= nil and L(pl, SK.Stealing)
end

---------------------------------------------------------------------------
-- equipment wear (MMMWE_ItemDurability.lua): Plate, Repair
---------------------------------------------------------------------------

local function wearMul(pl, it)
	if not any() then return 1 end
	local m = 1
	if pl and L(pl, SK.Plate) and Game.ItemsTxt[it.Number].Skill == SK.Plate then m = 0 end
	if partyLegend(SK.Repair) then m = m * P.RepairWearMul end
	return m
end

---------------------------------------------------------------------------
-- attacks on the party: Dodging, Shield, Leather, Sword
---------------------------------------------------------------------------

function events.PlayerAttacked(t, attacker)
	if t.Handled or not any() or type(attacker) ~= "table" then return end
	local pl = t.Player
	if not pl or not pl:IsConscious() then return end
	local spellBolt = attacker.Spell ~= nil and attacker.Spell ~= 0
	local melee = attacker.Monster ~= nil and not attacker.Object and not spellBolt
	local bolt = attacker.Object ~= nil or spellBolt
	if L(pl, SK.Dodging) and random() < P.DodgeChance then
		t.Handled = true
		status(string.format(Tx"%s evades the attack", pl.Name))
	elseif bolt and L(pl, SK.Shield) and extraSkill(pl) == SK.Shield and random() < P.ShieldBlock then
		t.Handled = true
		status(string.format(Tx"%s blocks it with the shield", pl.Name))
	elseif (melee or (bolt and not spellBolt)) and L(pl, SK.Leather) and armorSkill(pl) == SK.Leather
			and random() < P.LeatherEvade then
		t.Handled = true
		status(string.format(Tx"%s slips aside", pl.Name))
	elseif melee and L(pl, SK.Sword) and mainSkill(pl) == SK.Sword and random() < P.RiposteChance then
		t.Handled = true
		if MF.QueueCounterAttack and attacker.MonsterIndex then
			MF.QueueCounterAttack(rosterOf(pl), attacker.MonsterIndex,
				string.format(Tx"%s parries and strikes back!", pl.Name), 1)
		end
	end
end

---------------------------------------------------------------------------
-- damage to monsters
---------------------------------------------------------------------------

local DaggerCrit = false

-- first, before the other scripts: the game's result (after the resistance)
function events.CalcDamageToMonster(t)
	t.LegendRaw = t.Result
end

-- the spell of the hit and its caster: the projectile's, else the spell being cast
local function hitSpell(t)
	local op = t.ObjectPtr
	if op and op ~= 0 then
		local objs = Map.Objects
		local i = (op - objs["?ptr"]) / objs[0]["?size"]
		if i >= 0 and i == floor(i) and i < objs.count then
			local o = objs[i]
			if o.Spell and o.Spell > 0 then
				local owner = o.Owner
				local pl = owner % 8 == 4 and Party.PlayersArray[floor(owner / 8)] or t.Player
				return o.Spell, pl
			end
		end
		return
	end
	local spell = u2[0x51D820]
	if spell > 0 then return spell, Party.PlayersArray[u2[0x51D822]] or t.Player end
end

local function nearFoe(target, range)
	local best, bestD
	for i = 0, Map.Monsters.count - 1 do
		local m = Map.Monsters[i]
		if m ~= target and m.Hostile and (not MF.LiveFoe or MF.LiveFoe(m)) and m.HP > 0 then
			local dx, dy, dz = m.X - target.X, m.Y - target.Y, m.Z - target.Z
			local dd = dx * dx + dy * dy + dz * dz
			if dd <= range * range and (not bestD or dd < bestD) then best, bestD = i, dd end
		end
	end
	return best
end

local function finalMonsterDamage(t)
	if not t.ByPlayer or not any() or t.IsSecondary then DaggerCrit = false return end
	local pl = t.Player
	local raw = t.LegendRaw or t.Result
	local spell, caster = hitSpell(t)
	local skill = spellSkill(spell)
	local mul = 1

	if partyLegend(SK.IdentifyMonster) then mul = mul * P.KnowEnemyMul end

	if spell and caster and skill and L(caster, skill) then
		if RACIAL[skill] then
			mul = mul * P.RacialMul
		elseif spell == 41 then
			mul = mul * P.EarthDoubleMul
		else
			mul = mul * P.SchoolEffectMul
		end
		if skill == SK.Fire and t.DamageKind == DMG.Fire and raw > 0 and (t.Damage or 0) > raw then
			mul = mul * (1 + t.Damage / raw) / 2
		end
	elseif not spell and pl then
		if t.Melee and DaggerCrit and raw > 0 and (t.Damage or 0) > raw then
			mul = mul * t.Damage / raw
		end
		if t.Melee and bareHanded(pl) and L(pl, SK.Unarmed) then
			mul = mul * 2
		end
	end
	DaggerCrit = false

	if mul ~= 1 then t.Result = floor(t.Result * mul + 0.5) end

	-- Dark: the caster heals
	if spell and caster and skill == SK.Dark and L(caster, SK.Dark) and t.Result > 0 then
		caster.HP = min(caster:GetFullHP(), caster.HP + floor(t.Result * P.DarkLeech))
	end

	-- Axe: cleave into a foe next to the target (not from a cleave or counterattack)
	if not spell and pl and t.Melee and t.Result > 0 and mainSkill(pl) == SK.Axe and L(pl, SK.Axe)
			and MF.QueueCounterAttack and not (MF.CounterAttackActive and MF.CounterAttackActive()) then
		local mi = nearFoe(t.Monster, P.CleaveRange)
		if mi then
			MF.QueueCounterAttack(rosterOf(pl), mi, string.format(Tx"%s cleaves through!", pl.Name), P.CleaveShare)
		end
	end
end

---------------------------------------------------------------------------
-- damage to the party
---------------------------------------------------------------------------

local ELEMENT = {[DMG.Fire] = true, [DMG.Air] = true, [DMG.Water] = true, [DMG.Earth] = true}

local function undyingDay()
	return floor(Game.Time / const.Day)
end

local function finalPlayerDamage(t)
	if not any() or not t.Player or t.Result <= 0 then return end
	local pl = t.Player
	if ELEMENT[t.DamageKind] and L(pl, SK.Chain) and armorSkill(pl) == SK.Chain then
		t.Result = floor(t.Result * P.ChainElementMul + 0.5)
	end
	-- a map trap's missile (no monster, no character behind it)
	if WhoHitPlayer and partyLegend(SK.Perception) then
		local who = WhoHitPlayer()
		if type(who) == "table" and who.Object and not who.Monster and not who.Player then
			t.Result = 0
			return
		end
	end
	if L(pl, SK.Regeneration) and pl.HP > 0 and t.Result >= pl.HP then
		vars.MMMWE_LegendUndying = vars.MMMWE_LegendUndying or {}
		local idx = rosterOf(pl)
		if vars.MMMWE_LegendUndying[idx] ~= undyingDay() then
			vars.MMMWE_LegendUndying[idx] = undyingDay()
			t.Result = pl.HP - 1
			status(string.format(Tx"%s refuses to fall!", pl.Name))
		end
	end
end

---------------------------------------------------------------------------
-- every tick: conditions that don't hold, revivals, identifying, the spell context
---------------------------------------------------------------------------

local nextIdentify = 0

function events.Tick()
	SpellCtx, MaceTarget = nil, nil
	if not any() then return end
	for i = 0, Party.Count - 1 do
		local pl = Party[i]
		if L(pl, SK.Plate) and armorSkill(pl) == SK.Plate then
			if pl.Conditions[CD.Paralyzed] ~= 0 then pl.Conditions[CD.Paralyzed] = 0 end
			if pl.Conditions[CD.Stoned] ~= 0 then pl.Conditions[CD.Stoned] = 0 end
		end
		if L(pl, SK.Bodybuilding) and pl.Conditions[CD.Weak] ~= 0 then
			pl.Conditions[CD.Weak] = 0
		end
	end
	if #Revived > 0 then
		local keep = {}
		for _, r in ipairs(Revived) do
			local pl = Party[r.Slot]
			if pl and pl.Conditions[CD.Dead] == 0 and pl.Conditions[CD.Eradicated] == 0 then
				pl.Conditions[CD.Weak] = 0
			elseif Game.Time < r.Until then
				keep[#keep + 1] = r
			end
		end
		Revived = keep
	end
	local now = os.clock()
	if now >= nextIdentify then
		nextIdentify = now + 0.5
		if partyLegend(SK.IdentifyItem) then
			for i = 0, Party.Count - 1 do
				local items = Party[i].Items
				for j = 1, items.high do
					local it = items[j]
					if it.Number > 0 and not it.Identified then it.Identified = true end
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- after all the scripts: the last damage handlers and the wrappers of other scripts' functions
---------------------------------------------------------------------------

function events.ScriptsLoaded()
	-- the damage handlers last of all: after the ones other scripts add in GameInitialized2
	-- (MMMWE_Main.lua's Heroism and counterattack share)
	function events.GameInitialized2()
		events.CalcDamageToMonster = finalMonsterDamage
		events.CalcDamageToPlayer = finalPlayerDamage
	end

	-- Dagger: double crit chance (MF.GetCritStats, MMMWE_Main.lua) and the crit marked
	local getCrit = MF.GetCritStats
	if getCrit then
		MF.GetCritStats = function(pl, melee, ...)
			local c, d, s = getCrit(pl, melee, ...)
			if melee and any() and L(pl, SK.Dagger)
					and (mainSkill(pl) == SK.Dagger or extraSkill(pl) == SK.Dagger) then
				c = c * P.DaggerCritMul
			end
			return c, d, s
		end
	end
	local calcCrits = CalcCrits
	if calcCrits then
		CalcCrits = function(pl, melee, mon, ...)
			local r = calcCrits(pl, melee, mon, ...)
			if mon and melee and r > 1 and any() and L(pl, SK.Dagger)
					and (mainSkill(pl) == SK.Dagger or extraSkill(pl) == SK.Dagger) then
				DaggerCrit = true
			end
			return r
		end
	end

	-- Blaster: +20% damage (MF.BlasterShotDamageMul) and half the cell use (MF.BlasterCellUseMul)
	local shotMul = MF.BlasterShotDamageMul
	if shotMul then
		MF.BlasterShotDamageMul = function(pl, gun)
			local m = shotMul(pl, gun)
			if any() and L(pl, SK.Blaster) then m = m * P.BlasterDamageMul end
			return m
		end
	end
	MF.BlasterCellUseMul = function(pl)
		return (any() and L(pl, SK.Blaster)) and P.BlasterCellMul or 1
	end

	-- wear (MF.WearMultiplier, MMMWE_ItemDurability.lua)
	local wear = MF.WearMultiplier
	MF.WearMultiplier = function(pl, it)
		return (wear and wear(pl, it) or 1) * wearMul(pl, it)
	end
end
