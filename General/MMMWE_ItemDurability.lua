-- ========================================================================
-- Item Durability (wear & tear) for MMMerge 678 Waffel Edition
--
-- Works together with the patched MMMWE_Main.lua (see MMMWE_Main_edits.md):
--   * MMMWE_Main.lua owns the READ side. Effective durability is
--       base durability (x1.25 if Hardened)  -  wear
--     and feeds WE's armor hardness formula and the tooltip, so worn armor
--     protects less. (WE's old "weapon/shield may break on a hard hit" rolls
--     have been removed: items now break only by wearing out.)
--   * This file owns the BASE durability, the WRITE side (wear, breaking,
--     repair reset), the tooltip label and the gold-priced field repair (R).
--
-- BASE DURABILITY no longer comes from Items.txt IdRepSt. It is derived from
-- the item's gold Value:
--   1. items are grouped by slot type (weapon, bow, shield, body armor, helm,
--      belt, gauntlets, boots)
--   2. inside a group the REGULAR items are ranked by Value (ties share a rank)
--      and the rank is mapped to 1..150
--   3. special / artifact items are placed on the same scale by their own
--      Value, then multiplied (x1.5 special, x2 artifact)
--   4. relics are indestructible
--
-- Wear storage: Item.MaxCharges (u1, byte at item+0x19). It is unused on
-- weapons and armor (Item.Charges is NOT usable: WE packs enchant bonuses into it).
--     0 = pristine, 1..254 = wear, 255 = "broken" marker
-- One stored unit is 1 durability point, or 2 points for items whose maximum
-- durability would not fit in a byte (see ensureCache). The value lives in the
-- item struct, so it follows the item and is saved with the game.
-- ========================================================================

local MF = Merge.Functions
local LogId = MF.LogInit1 and MF.LogInit1("ItemDurability")
local function log(fmt, ...)
	if MF.LogInfo then MF.LogInfo("[DUR] " .. fmt, ...) end
end

local function round(x) return math.floor(x + 0.5) end

-- ========================================================================
-- CONFIG
-- ========================================================================

local CONFIG = {
	enabled      = true,    -- false = stop accruing wear (existing wear still counts)
	debug        = false,
	showMessages = true,    -- status-bar messages on Worn / Damaged / Broken

	-- ---- base durability ------------------------------------------------
	baseMin = 1,
	baseMax = 150,
	curve   = 1.0,          -- 1 = even spread; >1 pushes most items lower, <1 higher
	-- score used to rank items inside a group (default: gold value from Items.txt)
	scoreOf = function(txt, n) return txt.Value end,
	rarityMult = { regular = 1, special = 1.5, artifact = 2, relic = 2 },
	-- relic durability above is only the number WE's formulas see; relics never wear
	relicIndestructible = true,
	relicAutoRepair     = true,  -- un-break indestructible items (e.g. hit by monster "break item" attacks)

	-- Per-item overrides.
	--   classOverrides[itemNumber] = "regular" | "special" | "artifact" | "relic"
	--   baseOverrides[itemNumber]  = final durability (multipliers NOT applied)
	--   indestructible[itemNumber] = true
	classOverrides = {},
	baseOverrides  = {},
	indestructible = {},

	-- ---- wear -----------------------------------------------------------
	weaponWearChance = 0.20,   -- per melee hit, main-hand weapon
	offhandWearMult  = 0.50,    -- off-hand weapon (dual wield) wears at this fraction
	bowWearChance    = 0.20,   -- per arrow / bolt that hits
	parryWearChance  = 0.25,   -- per successful weapon parry
	blockWearChance  = 0.25,   -- per successful shield block
	armorWearChance  = 0.20,   -- per physical hit that gets through; ONE armor piece is picked
	wearAmount       = 1,

	-- Stage thresholds (fraction of max durability remaining)
	wornThreshold    = 0.66,
	damagedThreshold = 0.33,

	-- Damage penalty by stage for melee weapons and bows
	weaponDamagePenalty = { worn = 0.10, damaged = 0.25 },

	-- ---- field repair (hotkey, costs gold) -------------------------------
	-- Repairs the current character's items. Needs the Repair skill; restores up to
	-- 50% / 75% / 100% of max durability (Normal / Expert / Master and above).
	-- Broken items still need a shop/Repair-skill repair.
	-- NOTE: R is also the stock "Rest" key. While it is bound here the game never
	-- sees it on the main view (rest with the button instead).
	repairHotkey = const.Keys.R,      -- nil = disabled
	fieldRepair = {
		costMult     = 0.5,           -- gold = item Value x (fraction of max durability restored) x costMult
		minCost      = 1,             -- gold, per item
		equippedOnly = false,         -- true = leave backpack items alone
		screens      = {[0] = true, [7] = true},  -- Game.CurrentScreen values where the hotkey works (0 = main view)
	},
}

-- ========================================================================
-- ITEM GROUPS (by ItemsTxt.EquipStat) AND RARITY CLASSES
-- ========================================================================

-- 0 weapon, 1 two-handed, 2 missile (bows), 3 body armor, 4 shield, 5 helm,
-- 6 belt, 8 gauntlets, 9 boots. Cloaks, rings, amulets, wands: no durability.
local GROUP_OF_EQUIP = {
	[0] = "weapon", [1] = "weapon", [2] = "bow",
	[3] = "body", [4] = "shield", [5] = "helm", [6] = "belt", [8] = "gauntlets", [9] = "boots",
}

local SKILL_BOW, SKILL_BLASTER = 5, 7

local function groupOf(txt)
	local g = GROUP_OF_EQUIP[txt.EquipStat]
	if not g then return nil end
	if g == "bow" then
		if txt.Skill ~= SKILL_BOW then return nil end         -- blasters etc. excluded
	elseif g == "weapon" then
		if txt.Skill == SKILL_BLASTER or txt.Skill == SKILL_BOW then return nil end
	end
	return g
end

-- MMMerge marks rarity in NotIdentifiedName ("Artifact Longsword", "Relic Large
-- Shield", "Special Dagger", "Ancient Relic Warhammer", see WEAPON_TYPES in
-- MMMWE_Main.lua); Items.txt "Material" (1 artifact, 2 relic, 3 special) is the fallback.
local function classify(n, txt)
	local o = CONFIG.classOverrides[n]
	if o then return o end

	local name = txt.NotIdentifiedName or ""
	if name:find("^Relic ") or name:find("^Ancient") then return "relic" end
	if name:find("^Artifact ") then return "artifact" end
	if name:find("^Special ") then return "special" end

	local ok, m = pcall(function() return txt.Material end)
	if ok then
		if m == 1 then return "artifact" end
		if m == 2 then return "relic" end
		if m == 3 then return "special" end
	end
	return "regular"
end

-- ========================================================================
-- BASE DURABILITY TABLES (built once, lazily)
-- ========================================================================

local function countLess(arr, x)
	local lo, hi = 1, #arr + 1
	while lo < hi do
		local mid = math.floor((lo + hi) / 2)
		if arr[mid] < x then lo = mid + 1 else hi = mid end
	end
	return lo - 1
end

local function countLessEq(arr, x)
	local lo, hi = 1, #arr + 1
	while lo < hi do
		local mid = math.floor((lo + hi) / 2)
		if arr[mid] <= x then lo = mid + 1 else hi = mid end
	end
	return lo - 1
end

-- percentile of `score` inside the sorted population, mapped to baseMin..baseMax
local function normalize(pop, score)
	local n = #pop
	local span = CONFIG.baseMax - CONFIG.baseMin
	if n == 0 then return CONFIG.baseMin + span / 2 end
	local frac
	if n == 1 then
		frac = 0.5
	else
		local lo, hi = countLess(pop, score), countLessEq(pop, score)
		local r = lo + (hi - lo - 1) / 2          -- mean rank for ties, half-rank for outsiders
		r = math.max(0, math.min(n - 1, r))
		frac = r / (n - 1)
	end
	return CONFIG.baseMin + span * (frac ^ CONFIG.curve)
end

local cache

local function ensureCache()
	if cache then return cache end

	local c = {group = {}, class = {}, base = {}, unit = {}}
	local entries, pops = {}, {}

	for n, txt in Game.ItemsTxt do
		if n > 0 then
			local g = groupOf(txt)
			if g then
				local cls = classify(n, txt)
				local score = CONFIG.scoreOf(txt, n) or 0
				entries[#entries + 1] = {n = n, g = g, cls = cls, score = score}
				if cls == "regular" then
					local p = pops[g]
					if not p then p = {}; pops[g] = p end
					p[#p + 1] = score
				end
			end
		end
	end
	for _, p in pairs(pops) do table.sort(p) end

	for _, e in ipairs(entries) do
		local base = CONFIG.baseOverrides[e.n]
		if not base then
			base = round(normalize(pops[e.g] or {}, e.score))
			base = math.max(CONFIG.baseMin, math.min(CONFIG.baseMax, base))
			base = base * (CONFIG.rarityMult[e.cls] or 1)
		end
		c.group[e.n] = e.g
		c.class[e.n] = e.cls
		c.base[e.n]  = base
		-- stored wear is one byte (max 254): use 2-point units if a Hardened item could exceed that
		c.unit[e.n]  = (base * 1.25 > 254) and 2 or 1
	end

	cache = c
	if #entries == 0 then log("WARNING: no weapon/armor items found in Game.ItemsTxt") end
	log("Base durability built for %d items", #entries)
	return c
end

local function baseOf(n)       return ensureCache().base[n] or 0 end
local function classOf(n)      return ensureCache().class[n] end
local function groupOfNum(n)   return ensureCache().group[n] end

local function isIndestructible(n)
	if CONFIG.indestructible[n] then return true end
	return (CONFIG.relicIndestructible and classOf(n) == "relic") or false
end

local function isTracked(it)
	return it ~= nil and it.Number > 0 and groupOfNum(it.Number) ~= nil
end

local function canWear(it)
	return isTracked(it) and not isIndestructible(it.Number)
end

-- Max durability of a concrete item (Hardened: x1.25, shields without the minimum of 10 - same as WE)
local function maxDurability(it)
	local d = baseOf(it.Number)
	if d <= 0 then return 0 end
	if it.Hardened then
		if groupOfNum(it.Number) == "shield" then
			d = d * 1.25
		else
			d = math.max(d * 1.25, 10)
		end
	end
	return d
end

-- ========================================================================
-- WEAR STORAGE
-- ========================================================================

local WEAR_OFFSET   = 0x19      -- Item.MaxCharges
local BROKEN_MARK   = 255
local BROKEN_POINTS = 999       -- what GetItemWear reports for a broken item

local function unitOf(n) return ensureCache().unit[n] or 1 end

local function pointsOf(byte, n)
	if byte >= BROKEN_MARK then return BROKEN_POINTS end
	return byte * unitOf(n)
end

local function getWear(it)      return pointsOf(mem.u1[it["?ptr"] + WEAR_OFFSET], it.Number) end
local function getWearPtr(ptr)  return pointsOf(mem.u1[ptr + WEAR_OFFSET], mem.i4[ptr]) end
local function getByte(it)      return mem.u1[it["?ptr"] + WEAR_OFFSET] end
local function setByte(it, b)   mem.u1[it["?ptr"] + WEAR_OFFSET] = math.max(0, math.min(BROKEN_MARK, b)) end

local function setWearPoints(it, points)
	setByte(it, math.min(BROKEN_MARK - 1, round(points / unitOf(it.Number))))
end

-- adds wear in points; 2-point units use stochastic rounding so the expectation stays exact
local function addWear(it, points)
	local units = points / unitOf(it.Number)
	local whole = math.floor(units)
	if math.random() < units - whole then whole = whole + 1 end
	setByte(it, math.min(BROKEN_MARK - 1, getByte(it) + whole))
end

-- ========================================================================
-- STAGES
-- ========================================================================

local LABELS = {worn = " (Worn)", damaged = " (Damaged)", broken = " (Broken)"}

local function stageOf(cur, max)
	if max <= 0 then return "pristine" end
	if cur <= 0 then return "broken" end
	local f = cur / max
	if f <= CONFIG.damagedThreshold then return "damaged" end
	if f <= CONFIG.wornThreshold then return "worn" end
	return "pristine"
end

local function itemStage(it)
	local max = maxDurability(it)
	if max <= 0 then return "pristine" end
	return stageOf(math.max(0, max - getWear(it)), max)
end

-- used by the tooltip in MMMWE_Main.lua
function MF.GetDurabilityLabel(cur, max)
	return LABELS[stageOf(cur, max)] or ""
end

local function itemName(it)
	local txt = Game.ItemsTxt[it.Number]
	return it.Identified and txt.Name or txt.NotIdentifiedName
end

local function say(it, stage, pl)
	if not CONFIG.showMessages then return end
	if stage == "broken" then
		Game.ShowStatusText(string.format("%s's %s has broken!", pl.Name, itemName(it)))
	elseif stage == "damaged" then
		Game.ShowStatusText(string.format("%s's %s is badly damaged!", pl.Name, itemName(it)))
	elseif stage == "worn" then
		Game.ShowStatusText(string.format("%s's %s is showing wear.", pl.Name, itemName(it)))
	end
end

-- ========================================================================
-- APPLYING WEAR
-- ========================================================================

local function wearItem(it, amount, pl)
	if not canWear(it) or it.Broken then return end

	local before = itemStage(it)
	addWear(it, amount or 1)
	local after = itemStage(it)

	if after == "broken" then
		it.Broken = true
		setByte(it, BROKEN_MARK)
		Game.PlaySound(44603, -2)
		if pl then pl:ShowFaceAnimation(40) end
		say(it, "broken", pl)
		log("BROKEN: item %d", it.Number)
	elseif after ~= before then
		say(it, after, pl)
		log("%s: item %d (was %s)", after, it.Number, before)
	elseif CONFIG.debug then
		log("wear: item %d wear=%d/%d", it.Number, getWear(it), maxDurability(it))
	end
end

local function itemInSlot(pl, slotField, group)
	local slot = pl[slotField]
	if slot <= 0 then return nil end
	local it = pl.Items[slot]
	if isTracked(it) and groupOfNum(it.Number) == group and not it.Broken then return it end
end

-- Weapon that is parrying: main hand if it is a real weapon, else the off hand
-- (mirrors CalcWeaponParry in MMMWE_Main.lua)
local function parryingWeapon(pl)
	return itemInSlot(pl, "ItemMainHand", "weapon") or itemInSlot(pl, "ItemExtraHand", "weapon")
end

local ARMOR_SLOTS = {
	{"ItemArmor",     1.0},
	{"ItemHelm",      0.5},
	{"ItemGauntlets", 0.5},
	{"ItemBoots",     0.5},
	{"ItemBelt",      0.5},
}

-- Pick one worn armor piece (chest counts double, like in WE's hardness formula)
local function wearRandomArmor(pl)
	local pool, total = {}, 0
	for _, e in ipairs(ARMOR_SLOTS) do
		local slot = pl[e[1]]
		if slot > 0 then
			local it = pl.Items[slot]
			if canWear(it) and not it.Broken then
				total = total + e[2]
				pool[#pool + 1] = {it, total}
			end
		end
	end
	if total <= 0 then return end
	local r = math.random() * total
	for _, p in ipairs(pool) do
		if r <= p[2] then
			wearItem(p[1], CONFIG.wearAmount, pl)
			return
		end
	end
end

-- Called from CalcDamageToPlayer in MMMWE_Main.lua after all damage reductions.
local function wearOnHit(pl, category, result, wDR, shDR, dodgeDR)
	if not CONFIG.enabled then return end

	-- weapon parried the hit
	if wDR < 1 and wDR < dodgeDR and wDR < shDR and math.random() < CONFIG.parryWearChance then
		local it = parryingWeapon(pl)
		if it then wearItem(it, CONFIG.wearAmount, pl) end
	end

	-- shield blocked the hit
	if shDR < 1 and shDR < dodgeDR and shDR < wDR and math.random() < CONFIG.blockWearChance then
		local it = itemInSlot(pl, "ItemExtraHand", "shield")
		if it then wearItem(it, CONFIG.wearAmount, pl) end
	end

	-- armor: only physical damage that actually got through (armor does nothing
	-- against elemental / energy damage in WE)
	if category == "physical" and result > 0 and math.random() < CONFIG.armorWearChance then
		wearRandomArmor(pl)
	end
end

-- ========================================================================
-- OUTGOING HITS: melee weapons and bows (wear)
-- The damage penalty for worn / damaged weapons is NOT applied here any more:
-- MMMWE_Main.lua applies it (applyPenalty in its CalcDamageToMonster), after its own
-- damage and monster-resistance logic. This file only reports the penalty size.
-- ========================================================================

-- Fraction of damage lost by a weapon / bow in its current stage (0 for anything else)
local function weaponPenalty(it)
	if not isTracked(it) or it.Broken or isIndestructible(it.Number) then return 0 end
	local g = groupOfNum(it.Number)
	if g ~= "weapon" and g ~= "bow" then return 0 end
	return CONFIG.weaponDamagePenalty[itemStage(it)] or 0
end

function events.CalcDamageToMonster(t)
    if not CONFIG.enabled then return end
    if not t.ByPlayer then return end
    
    -- Не изнашиваем оружие от вторичных вызовов (зачарования)
    if _G.CE_SecondaryResist and _G.CE_SecondaryResist > 0 then return end
    
	local pl = t.Player
	if not pl then return end

	if t.Melee then
		local it = itemInSlot(pl, "ItemMainHand", "weapon")
		if it and math.random() < CONFIG.weaponWearChance then
			wearItem(it, CONFIG.wearAmount, pl)
		end

		-- dual wielding: off-hand weapon wears more slowly
		it = itemInSlot(pl, "ItemExtraHand", "weapon")
		if it and math.random() < CONFIG.weaponWearChance * CONFIG.offhandWearMult then
			wearItem(it, CONFIG.wearAmount, pl)
		end

	elseif t.DamageKind == const.Damage.Phys then
		-- physical, not melee = arrow or bolt (same rule MMMWE_Main.lua uses)
		local it = itemInSlot(pl, "ItemBow", "bow")
		if it and math.random() < CONFIG.bowWearChance then
			wearItem(it, CONFIG.wearAmount, pl)
		end
	end
end

-- ========================================================================
-- BROKEN <-> REPAIRED BOOKKEEPING
--   Broken item      -> wear forced to 255 (covers breaks by wear, monster
--                       "break item" attacks and anything else)
--   Un-broken item   -> wear 255 means it was repaired (shop / Repair skill):
--                       restore to full
--   Indestructible   -> never stays broken, never carries wear
-- Stateless: only looks at the item itself, so it survives save/load.
-- ========================================================================

local scanFailed = false

local function scanInventories()
	for _, pl in Party.Players do
		for j = 1, 138 do
			local it = pl.Items[j]
			if it.Number > 0 and isTracked(it) then
				local b = getByte(it)
				if isIndestructible(it.Number) then
					if it.Broken and CONFIG.relicAutoRepair then
						it.Broken = false
						log("Indestructible item %d un-broken", it.Number)
					end
					if b ~= 0 then setByte(it, 0) end
				elseif it.Broken then
					if b ~= BROKEN_MARK then setByte(it, BROKEN_MARK) end
				elseif b == BROKEN_MARK then
					setByte(it, 0)
					log("Repaired: item %d restored to full durability", it.Number)
				end
			end
		end
	end
end

local tickCounter = 0
function events.Tick()
	if scanFailed then return end
	tickCounter = tickCounter + 1
	if tickCounter < 30 then return end
	tickCounter = 0
	local ok, err = pcall(scanInventories)
	if not ok then
		scanFailed = true
		log("Inventory scan disabled after error: %s", tostring(err))
	end
end

-- ========================================================================
-- FIELD REPAIR (hotkey, costs gold)
-- ========================================================================

local EQUIP_FIELDS = {"ItemMainHand", "ItemExtraHand", "ItemBow", "ItemArmor",
                      "ItemHelm", "ItemGauntlets", "ItemBoots", "ItemBelt"}

local function repairCost(it, restoredPoints, max)
	local FR = CONFIG.fieldRepair
	local value = Game.ItemsTxt[it.Number].Value or 0
	return math.max(FR.minCost, math.ceil(value * (restoredPoints / max) * FR.costMult))
end

-- Repairs pl's items up to `limit` (fraction of max durability), most important first:
-- equipped before backpack, most worn first. Stops at the first item the party can't afford.
-- Returns repaired, gold spent, items needing repair, cost of the item it could not afford.
local function fieldRepair(pl, limit)
	local FR = CONFIG.fieldRepair

	local equipped = {}
	for _, f in ipairs(EQUIP_FIELDS) do
		local slot = pl[f]
		if slot > 0 then equipped[slot] = true end
	end

	local jobs = {}
	for j = 1, 138 do
		local it = pl.Items[j]
		if it.Number > 0 and canWear(it) and not it.Broken and (equipped[j] or not FR.equippedOnly) then
			local max = maxDurability(it)
			local cur = math.max(0, max - getWear(it))
			local target = math.floor(max * limit)
			if cur < target then
				jobs[#jobs + 1] = {
					it = it, max = max, target = target,
					eq = equipped[j] and 1 or 0, frac = cur / max,
					cost = repairCost(it, target - cur, max),
				}
			end
		end
	end
	table.sort(jobs, function(x, y)
		if x.eq ~= y.eq then return x.eq > y.eq end
		return x.frac < y.frac
	end)

	local gold, spent, done, blockedCost = Party.Gold, 0, 0, nil
	for _, job in ipairs(jobs) do
		if spent + job.cost > gold then blockedCost = job.cost; break end
		setWearPoints(job.it, math.max(0, job.max - job.target))
		spent, done = spent + job.cost, done + 1
	end
	if spent > 0 then Party.Gold = gold - spent end
	return done, spent, #jobs, blockedCost
end

if CONFIG.repairHotkey then
	function events.KeyDown(t)
		if t.Key ~= CONFIG.repairHotkey then return end
		if not CONFIG.fieldRepair.screens[Game.CurrentScreen] then return end
		t.Handled = true   -- R is the stock "Rest" key: keep the game from also resting

		local pl = Party:GetCurrentPlayer()
		if not pl then return end

		local s, m = SplitSkill(pl:GetSkill(const.Skills.Repair))
		if s <= 0 or m <= 0 then
			Game.ShowStatusText("No Repair skill")
			return
		end

		local limit = (m >= 3 and 1.0) or (m == 2 and 0.75) or 0.50
		local done, spent, total, blocked = fieldRepair(pl, limit)

		if total == 0 then
			Game.PlaySound(27,-1,0)
			Game.ShowStatusText("Nothing to repair")
		elseif done == 0 then
			Game.PlaySound(27,-1,0)
			Game.ShowStatusText(string.format("Not enough gold (%d needed)", blocked))
		elseif done < total then
			Game.PlaySound(146,-1,0)
			Game.ShowStatusText(string.format("Repaired %d of %d items for %d gold - out of gold", done, total, spent))
		else
			Game.PlaySound(146,-1,0)
			Game.ShowStatusText(string.format("Repaired %d item(s) for %d gold", done, spent))
		end
		log("Field repair: %d/%d items, %d gold (mastery=%d)", done, total, spent, m)
	end
end

-- ========================================================================
-- CONSOLE HELPER:  Merge.Functions.DumpDurability()  or  ("artifact" | "relic" | "special" | "bow" ...)
-- Prints class counts, and lists the items of one class or group with their durability.
-- ========================================================================

function MF.DumpDurability(filter)
	local c = ensureCache()
	local counts, list = {}, {}
	for n, cls in pairs(c.class) do
		counts[cls] = (counts[cls] or 0) + 1
		counts[c.group[n]] = (counts[c.group[n]] or 0) + 1
		if filter and (filter == cls or filter == c.group[n]) then list[#list + 1] = n end
	end
	print(string.format("regular=%d special=%d artifact=%d relic=%d | weapon=%d bow=%d shield=%d body=%d helm=%d belt=%d gauntlets=%d boots=%d",
		counts.regular or 0, counts.special or 0, counts.artifact or 0, counts.relic or 0,
		counts.weapon or 0, counts.bow or 0, counts.shield or 0, counts.body or 0,
		counts.helm or 0, counts.belt or 0, counts.gauntlets or 0, counts.boots or 0))
	table.sort(list)
	for _, n in ipairs(list) do
		local txt = Game.ItemsTxt[n]
		print(string.format("%5d  %-28s  %-10s %-9s value=%-7s durability=%s",
			n, tostring(txt.NotIdentifiedName), c.group[n], c.class[n], tostring(txt.Value),
			isIndestructible(n) and "indestructible" or tostring(c.base[n])))
	end
end

-- ========================================================================
-- EXPORTS for MMMWE_Main.lua (read side) and other scripts
-- ========================================================================

MF.GetBaseDurability = baseOf                 -- (itemNumber) -> base durability incl. rarity multiplier, 0 if the item has none
MF.IsIndestructible  = isIndestructible       -- (itemNumber)
MF.GetItemWear       = getWear                -- (item)  -> wear points (999 = broken)
MF.GetItemWearPtr    = getWearPtr             -- (ptr)   -> same, from a raw item pointer (tooltip hook)
MF.WearOnHit         = wearOnHit              -- called by CalcDamageToPlayer in MMMWE_Main.lua
MF.WearItem          = function(it, amount, pl) wearItem(it, amount, pl) end
MF.GetWeaponPenalty  = weaponPenalty          -- (item)  -> damage penalty fraction (0 / worn / damaged), used by applyPenalty in MMMWE_Main.lua

log("Item Durability loaded (enabled=%s)", tostring(CONFIG.enabled))
