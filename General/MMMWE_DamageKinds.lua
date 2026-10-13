--[[
	MMMWE_DamageKinds.lua — slashing, piercing and blunt physical damage

	Physical damage the party deals to monsters has one of three kinds:
	  Slashing  - Sword, Axe
	  Piercing  - Dagger, Spear, and every ranged physical hit (bows and crossbows)
	  Blunt     - Mace, Staff, unarmed (also a broken main-hand weapon)
	Melee uses the main-hand weapon; with an empty main hand, the off-hand weapon if any.
	(Dual wielding with two different kinds counts as the main-hand kind.)

	Each monster keeps its normal physical resistance (MONSTERS.txt "Phys", bolster
	included) and gets a modifier per kind from Data/Tables/Physical Damage Kinds.txt:
	  #  Monster  Picture  Slashing  Piercing  Blunt  Phys (reference)
	The modifiers are percentage points of damage reduction. The monster's Phys value is
	turned into its damage reduction (resistance curve below), the modifier is added, and
	the hit is reduced by the result, e.g. a skeleton with Phys 15 (20%) and Blunt -20
	takes full damage from maces, and with Piercing +40 takes 40% less from arrows.
	The "Picture", "Phys (reference)" and "Profile (reference)" columns are only for
	reading; editing them changes nothing.

	Phys in MONSTERS.txt is the resistance to physical damage of no particular kind
	(monster against monster, physical spells). For monsters with modifiers it was
	lowered by the average of their three modifiers, so the average protection over the
	three kinds stays about where it was.

	Resistance curve (the same as CalcMonResPercent in MMMWE_Main.lua):
	  Phys   0   3   7  11  15  20  26  33  40  50  62  76  95 120 156 211 306 509 1254
	  %      0   5  10  15  20  25  30  35  40  45  50  55  60  65  70  75  80  85   90
	Reduction for a kind is capped at MAX_REDUCTION. Below 0 the monster is vulnerable:
	-20% = +20% damage, up to +100%. Monsters immune to physical damage stay immune.

	Runs before MMMWE_Main.lua's CalcDamageToMonster handler (file load order), so the
	Might bonus, high ground, crits and the worn weapon penalty work on the new value.
	Weapon enchantments, blasters, spells and monster-to-party damage are not affected.

	Monster card: with the Identify Monster rank that shows resistances, the Physical line
	reads "S 30% P 10% B 25%" - the damage reduction against each kind (only for monsters
	with modifiers; immune monsters keep "Immune").

	Monsters hitting the party: projectiles are Piercing, melee hits use the table's
	"Melee Kind" column. Body armor changes the damage taken by kind (ARMOR_KIND_FACTOR
	below): leather and chain are weaker against piercing, plate against blunt; a Grand
	Master in the armor skill has no weakness.

	Console: Merge.Functions.PhysDamageKindOf(player, melee) -> "Slashing" / "Piercing" / "Blunt"
--]]

local MF = Merge.Functions
local function log(fmt, ...) MF.LogInfo("[PDK] " .. fmt, ...) end

local TABLE_FILE = "Data/Tables/Physical Damage Kinds.txt"
local KINDS = {"Slashing", "Piercing", "Blunt"}

local SK = const.Skills
local KIND_OF_SKILL = {
	[SK.Sword] = "Slashing", [SK.Axe] = "Slashing",
	[SK.Dagger] = "Piercing", [SK.Spear] = "Piercing", [SK.Bow] = "Piercing",
	[SK.Mace] = "Blunt", [SK.Staff] = "Blunt",
}

local function round(x) return math.floor(x + 0.5) end

---------------------------------------------------------------------------
-- table
---------------------------------------------------------------------------

local Mods = {}        -- [monster id] = {Slashing = n, Piercing = n, Blunt = n}
local MeleeKind = {}   -- [monster id] = "Slashing" / "Piercing" / "Blunt" (its physical melee attacks)
local KIND_NAMES = {slashing = "Slashing", piercing = "Piercing", blunt = "Blunt",
	s = "Slashing", p = "Piercing", b = "Blunt"}

local function loadTable()
	local f = io.open(TABLE_FILE, "r")
	if not f then
		log("%s not found - physical damage kinds disabled", TABLE_FILE)
		return false
	end
	local header, count = true, 0
	for line in f:lines() do
		line = line:gsub("\r$", "")
		if header then
			header = false
		else
			local w = string.split(line, "\9")
			local id = tonumber(w[1])
			if id then
				MeleeKind[id] = KIND_NAMES[(w[9] or ""):match("^%s*(.-)%s*$"):lower()]
				local s, p, b = tonumber(w[4]) or 0, tonumber(w[5]) or 0, tonumber(w[6]) or 0
				if s ~= 0 or p ~= 0 or b ~= 0 then
					Mods[id] = {Slashing = s, Piercing = p, Blunt = b}
					count = count + 1
				end
			end
		end
	end
	f:close()
	log("%d monsters with physical damage kind modifiers", count)
	return true
end

local Enabled = false
function events.GameInitialized2()
	Enabled = loadTable()
end

---------------------------------------------------------------------------
-- kind of the hit
---------------------------------------------------------------------------

local function weaponKind(pl, slot)
	if slot == 0 then return nil end
	local it = pl.Items[slot]
	if it.Number <= 0 or it.Broken then return nil end
	return KIND_OF_SKILL[Game.ItemsTxt[it.Number].Skill]
end

local function kindOf(pl, melee)
	if not melee then return "Piercing" end
	return weaponKind(pl, pl.ItemMainHand)
		or (pl.ItemMainHand == 0 and weaponKind(pl, pl.ItemExtraHand))
		or "Blunt"
end
MF.PhysDamageKindOf = kindOf

---------------------------------------------------------------------------
-- resistance
---------------------------------------------------------------------------

local MAX_REDUCTION = 95   -- percent, for a kind (base + modifier)

-- damage reduction (0..1) of a resistance value (same curve as CalcMonResPercent in MMMWE_Main.lua)
local function reductionOf(res)
	if res >= 65000 then return 1 end
	if res <= 0 then return 0 end
	local p = 1 - 30 / (res + 30)
	return 0.5 * p + 0.25 * p^2 + 0.125 * p^3 + 0.0625 * p^4
end

-- damage reduction in percent of monster mon against a kind (nil if it has no modifiers)
local function kindReduction(mon, kind)
	local mods = Mods[mon.Id]
	if not mods then return nil end
	local r = reductionOf(mon.PhysResistance) * 100 + (mods[kind] or 0)
	return math.max(-100, math.min(MAX_REDUCTION, r))
end
MF.PhysKindReduction = kindReduction

function events.CalcDamageToMonster(t)
	if not t.ByPlayer or t.IsSecondary then return end
	if t.DamageKind ~= const.Damage.Phys then return end
	local pl, mon = t.Player, t.Monster
	if not pl or not mon then return end

	-- the kind of every physical hit is reported to later handlers (Combat Log)
	local kind = kindOf(pl, t.Melee)
	t.PhysDamageKind = kind

	if not Enabled then return end
	local base = mon.PhysResistance
	if base >= 65000 then return end   -- immune stays immune
	local r = kindReduction(mon, kind)
	if not r then return end

	-- t.Result already passed the normal physical resistance: swap its factor for the
	-- factor of this kind (keeps anything else the game applied to the hit)
	local old, new = 1 - reductionOf(base), 1 - r / 100
	if old == new then return end
	if old > 0 then
		t.Result = math.max(0, round(t.Result * new / old))
	else
		t.Result = math.max(0, round((t.Damage or 0) * new))
	end
end

---------------------------------------------------------------------------
-- monster card (rmb_monster): Physical line shows the three kinds
---------------------------------------------------------------------------
-- Resistances are listed in a loop at 0x41E85F (only when Identify Monster lets the
-- card show them). The value text ("Resistant" / "None" / "Immune") is pushed just
-- before 0x41E88A; [ebp-14h] is the line offset (0, 4 ... 24h = Physical), [ebp-10h]
-- the monster shown. For the Physical line of a monster with modifiers the value text
-- is replaced with "S 30% P 10% B 25%" (its damage reduction against each kind).

local CardText = mem.StaticAlloc(64)

local function monsterFromPtr(ptr)
	local info = Game.DialogLogic.MonsterInfoMonster
	if info["?ptr"] == ptr then return info end
	local size = Map.Monsters[0]["?size"]
	local i = (ptr - Map.Monsters["?ptr"]) / size
	if i >= 0 and i < Map.Monsters.count and i % 1 == 0 then
		return Map.Monsters[i]
	end
end

local function cardLine(mon)
	if not Mods[mon.Id] or mon.PhysResistance >= 65000 then return nil end   -- keeps "Immune"
	return string.format("S %d%% P %d%% B %d%%",
		round(kindReduction(mon, "Slashing")), round(kindReduction(mon, "Piercing")),
		round(kindReduction(mon, "Blunt")))
end
MF.PhysDamageKindsCardLine = cardLine

mem.autohook(0x41E88A, function(d)
	if not Enabled or mem.i4[d.ebp - 0x14] ~= 0x24 then return end
	local ok, mon = pcall(monsterFromPtr, mem.u4[d.ebp - 0x10])
	if not ok or not mon then return end
	local text = cardLine(mon)
	if not text then return end
	for i = 1, math.min(#text, 63) do mem.u1[CardText + i - 1] = text:byte(i) end
	mem.u1[CardText + math.min(#text, 63)] = 0
	mem.u4[d.esp] = CardText
end)

---------------------------------------------------------------------------
-- monsters hitting the party
---------------------------------------------------------------------------
-- Kind of a monster's physical hit: projectiles (arrows, bolts, thrown weapons) are
-- Piercing; melee uses the "Melee Kind" column of the table (Slashing if empty).
-- The armor worn changes the damage taken by kind (multiplier, applied by
-- MMMWE_Main.lua's CalcDamageToPlayer after all other reductions, and shown on the
-- Character Screen). Each piece counts with its weight (ARMOR_SLOT_WEIGHT, sums to 1):
-- body armor half, helm and boots 15% each, gauntlets and belt 10% each. A piece's type
-- is its Skill Group in ITEMS.txt (Leather / Chain / Plate); an empty slot, a broken
-- piece or a hat (Misc) counts as 1 (no change). A full set of one type gives that
-- type's factor below; mixed pieces give a blend.
-- Above 1 = weakness; with REMOVE_WEAKNESS_AT_GM a piece whose armor skill the
-- character has at Grand Master has no weakness.

local ARMOR_KIND_FACTOR = {
	[SK.Leather] = {Slashing = 0.90, Piercing = 1.05, Blunt = 0.95},
	[SK.Chain]   = {Slashing = 0.85, Piercing = 1.10, Blunt = 1.00},
	[SK.Plate]   = {Slashing = 0.80, Piercing = 0.90, Blunt = 1.10},
}
local REMOVE_WEAKNESS_AT_GM = true

local ARMOR_SLOT_WEIGHT = {
	{"ItemArmor",     0.50},
	{"ItemHelm",      0.15},
	{"ItemBoots",     0.15},
	{"ItemGauntlets", 0.10},
	{"ItemBelt",      0.10},
}

-- kind of the physical hit the party is taking right now (nil if not from a monster or a missile)
function MF.IncomingPhysKind()
	if not WhoHitPlayer then return nil end
	local who = WhoHitPlayer()
	if type(who) ~= "table" then return nil end
	if who.Object then return "Piercing" end
	local mon = who.Monster
	if mon then return MeleeKind[mon.Id] or "Slashing" end
end

-- damage multiplier of one worn piece against a kind (1 if none)
local function pieceFactor(pl, slot, kind)
	if not slot or slot == 0 then return 1 end
	local it = pl.Items[slot]
	if it.Number <= 0 or it.Broken then return 1 end
	local txt = Game.ItemsTxt[it.Number]
	local f = txt and ARMOR_KIND_FACTOR[txt.Skill]
	local v = f and f[kind] or 1
	if v > 1 and REMOVE_WEAKNESS_AT_GM then
		local _, m = SplitSkill(pl:GetSkill(txt.Skill))
		if m >= 4 then v = 1 end
	end
	return v
end

-- damage multiplier of pl's armor (all pieces, weighted) against a kind
function MF.ArmorKindFactor(pl, kind)
	if not kind then return 1 end
	local v = 0
	for _, sw in ipairs(ARMOR_SLOT_WEIGHT) do
		v = v + sw[2] * pieceFactor(pl, pl[sw[1]], kind)
	end
	return v
end
MF.ArmorSlotWeights = ARMOR_SLOT_WEIGHT
MF.ArmorKindFactors = ARMOR_KIND_FACTOR
