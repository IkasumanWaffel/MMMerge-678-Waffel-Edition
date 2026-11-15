--[[
	MMMWE_EnchantItem.lua — the Enchant Item spell (Water 30) and the flaws of a failed ritual (15.11.26)

	The game's four rank branches of the spell (and SpellsExtra.lua's patches of them) are
	replaced: right after the spell has picked its target item, this script decides the
	outcome and writes it into the item; the game then spends the spell points and shows the
	animation (success) or its failure message.

	Which items: equippable ones (weapons, armor, shields, helms, belts, cloaks, gauntlets,
	boots, rings, amulets), not artifacts, relics or special items, not broken, without an
	enchantment yet. Novice enchants non-weapons only.

	The item's quality Q = QUALITY_BASE + sqrt(value) / QUALITY_DIV (its base value: a
	Longsword ~6, a 5000 gold blade ~22) caps the standard bonus; its tier (1..4, Q by 10s)
	makes it harder.

	  rank      standard bonus (non-weapons) at most         special bonus
	  Novice    3 + skill / 4                                 -
	  Expert    5 + skill / 2                                 rank A
	  Master    10 + skill / 2                                ranks A-B, with a gem
	  GM        skill + 5                                     ranks A-C, with a gem; D: Legendary Water
	The strength is rolled in the upper half of min(that, Q). Weapons only take specials.
	Non-weapons get a special in SPECIAL_SHARE % of the casts (with a gem: SPECIAL_GEM %).
	The special is picked by the slot weights of SPCITEMS.TXT, as found loot.
	A gem in the caster's backpack (the dearest one) is used up for a special above rank A:
	500+ gold allows B, 1250+ C, 2250+ D; every 10 points of the caster's Enchanting skill
	one rank more; never above the Water rank's limit.

	Chance: the game's own (10% per point of Water skill) - 5% per quality tier + 1% per point
	of Enchanting. A failure leaves the item as it was; when Q is more than BREAK_GAP above
	the Water skill, BREAK_CHANCE % of failures break it (repairable).
	Flawed ritual: a success that carries a flaw beside the bonus, FLAW_BASE % + FLAW_PER %
	per point of Q above the Water skill, - 1% per point of Enchanting; never with Legendary
	Water. A special bonus gets a negative standard bonus (a statistic or a resistance, its
	size by Q); a standard bonus gets one of the flaw specials (SPCITEMS 154..159, never in
	loot):
	  154 Brittle      the item wears out twice as fast
	  155 Ill-omened   -10 Luck; monsters pick the bearer more often (threat x1.25)
	  156 Draining     -1 spell point every DRAIN_MINUTES game minutes
	  157 Unsteady     weapons: +5 recovery; other items: -5 Accuracy
	  158 Cursed       -5 to every resistance
	  159 Shadowed     the bearer gains 10% less from all healing
--]]

local MF = Merge.Functions
local Tx = Merge.Functions.Text
local u1, u2, u4, i4 = mem.u1, mem.u2, mem.u4, mem.i4
local floor, ceil, max, min, random, sqrt = math.floor, math.ceil, math.max, math.min, math.random, math.sqrt

local C = {
	QUALITY_BASE = 5, QUALITY_DIV = 4,
	TIER_PENALTY = 5,
	SPECIAL_SHARE = 15, SPECIAL_GEM = 50,
	BREAK_GAP = 10, BREAK_CHANCE = 10,
	FLAW_BASE = 10, FLAW_PER = 3,
	GEM_RANK = {{2250, 4}, {1250, 3}, {500, 2}},
	DRAIN_MINUTES = 5,
	ILL_LUCK = -10, ILL_THREAT = 1.25,
	UNSTEADY_RECOVERY = 5, UNSTEADY_ACCURACY = -5,
	CURSED_RES = -5,
	SHADOW_HEAL = 0.9,
}
MF.EnchantItemSettings = C

local FLAW = {Brittle = 154, IllOmened = 155, Draining = 156, Unsteady = 157, Cursed = 158, Shadowed = 159}
MF.EnchantFlaws = FLAW
local FLAW_LIST = {154, 155, 156, 157, 158, 159}
local FLAW_STD = {1, 2, 3, 4, 5, 6, 7, 11, 12, 13, 14, 15, 16}   -- STDITEMS: the statistics and the resistances
local RANK_CAP = {0, 1, 2, 3}                                     -- specials by Water rank
local WATER = const.Skills.Water

local function log(fmt, ...) if MF.LogInfo then MF.LogInfo("[EnchantItem] " .. fmt, ...) end end
local function status(s) if Game.ShowStatusText then Game.ShowStatusText(s) end end

local function isLegendary(pl, skill)
	return pl and MF.IsLegendary and MF.IsLegendary(pl, skill) or false
end

local function enchanting(pl)
	if not pl or not MF.ExtraSkills or not MF.ExtraSkills.Skills.Enchanting then return 0 end
	local ok, s = pcall(function() return SplitSkill(pl:GetSkill(MF.ExtraSkills.Skills.Enchanting)) end)
	if not ok or not s then
		ok, s = pcall(function() return SplitSkill(MF.GetExtraSkill(pl, MF.ExtraSkills.Skills.Enchanting)) end)
	end
	return (ok and s) or 0
end

local function quality(txt)
	return C.QUALITY_BASE + floor(sqrt(max(0, txt.Value)) / C.QUALITY_DIV)
end

local function tier(q)
	return max(1, min(4, ceil(q / 10)))
end

local function stdCap(rank, skill)
	if rank <= 1 then return 3 + floor(skill / 4)
	elseif rank == 2 then return 5 + floor(skill / 2)
	elseif rank == 3 then return 10 + floor(skill / 2)
	end
	return skill + 5
end

-- the weighted pick of a table's rows for a slot; filter(row, index) -> true to take part
local function pick(tbl, slot, filter)
	local total, list = 0, {}
	for i, v in tbl do
		local w = v.ChanceForSlot[slot] or 0
		if w > 0 and filter(v, i) then
			total = total + w
			list[#list + 1] = {i, w}
		end
	end
	if total <= 0 then return end
	local r = random(total)
	for _, e in ipairs(list) do
		r = r - e[2]
		if r <= 0 then return e[1] end
	end
end

-- the dearest gem in the caster's backpack: its slot index and value
local function bestGem(pl)
	if not pl then return end
	local best, bestV
	local gemType = Game.ItemsTxt[177].EquipStat          -- Zircon: the gems' kind
	for c = 0, 125 do
		local i = pl.Inventory[c]
		local it = i > 0 and pl.Items[i]
		if it and it.Number > 0 then
			local t = Game.ItemsTxt[it.Number]
			if t and t.EquipStat == gemType and (not bestV or t.Value > bestV) then
				best, bestV = i, t.Value
			end
		end
	end
	return best, bestV
end

local function gemRank(v)
	if not v then return 1 end
	for _, g in ipairs(C.GEM_RANK) do
		if v >= g[1] then return g[2] end
	end
	return 1
end

local function removeItem(pl, i)
	-- the backpack grid: the item's index in its main cell, -(1 + main cell) in the others
	for c = 0, 125 do
		if pl.Inventory[c] == i then
			pl.Inventory[c] = 0
			for c2 = 0, 125 do
				if pl.Inventory[c2] == -(1 + c) then pl.Inventory[c2] = 0 end
			end
		end
	end
	pl.Items[i].Number = 0
end

local function itemOk(it, txt)
	if not it or it.Number <= 0 or not txt then return false end
	local es = txt.EquipStat
	if es < 0 or es > 11 then return false end
	if (txt.Material or 0) > 0 then return false end
	if it.Broken or it.Bonus ~= 0 or it.BonusStrength ~= 0 or it.Bonus2 ~= 0 then return false end
	return true
end

-- the outcome; returns "invalid", "fail", "broken" or "ok" (and the texts to show)
local function enchant(caster, target, it, rank, skill, chance)
	local txt = Game.ItemsTxt[it.Number]
	if not itemOk(it, txt) then return "invalid" end
	local es = txt.EquipStat
	local weapon = es <= 2
	if weapon and rank <= 1 then return "invalid" end

	local q = quality(txt)
	local ench = enchanting(caster)
	local legend = isLegendary(caster, WATER)
	chance = chance - C.TIER_PENALTY * tier(q) + ench
	if random(100) > chance then
		if q > skill + C.BREAK_GAP and random(100) <= C.BREAK_CHANCE then
			it.Broken = true
			return "broken"
		end
		return "fail"
	end

	-- a special or a standard bonus
	local gemSlot, gemValue = bestGem(caster)
	local maxRank = RANK_CAP[rank] + (legend and rank >= 4 and 1 or 0)
	local rankGem = maxRank > 1 and gemSlot and min(maxRank, gemRank(gemValue) + floor(ench / 10)) or 1
	local special = weapon or (rank >= 2 and random(100) <= ((gemSlot and rank >= 3) and C.SPECIAL_GEM or C.SPECIAL_SHARE))
	local usedGem = false
	if special then
		local cap = min(maxRank, rankGem)
		local b2 = pick(Game.SpcItemsTxt, es, function(v, i)
			local lv = max(1, v.Lvl or 1)
			return lv <= cap and (i + 1) < FLAW_LIST[1]
		end)
		if b2 then
			it.Bonus2 = b2 + 1
			usedGem = max(1, Game.SpcItemsTxt[b2].Lvl or 1) > 1
		else
			special = false
		end
	end
	if not special then
		if weapon then return "fail" end
		local cap = max(1, min(stdCap(rank, skill), q))
		local b = pick(Game.StdItemsTxt, es - 3, function() return true end)
		if not b then return "fail" end
		it.Bonus = b + 1
		it.BonusStrength = random(max(1, ceil(cap / 2)), cap)
	end
	if usedGem and gemSlot then removeItem(caster, gemSlot) end

	-- a flawed ritual
	local flawChance = legend and 0 or (C.FLAW_BASE + C.FLAW_PER * max(0, q - skill) - ench)
	local flaw
	if flawChance > 0 and random(100) <= flawChance then
		if special then
			it.Bonus = FLAW_STD[random(#FLAW_STD)]
			it.BonusStrength = -max(1, floor(q / 3))
			flaw = Game.StdItemsTxt[it.Bonus - 1] and Game.StdItemsTxt[it.Bonus - 1].BonusStat or "?"
		else
			it.Bonus2 = FLAW_LIST[random(#FLAW_LIST)]
			flaw = Game.SpcItemsTxt[it.Bonus2 - 1] and Game.SpcItemsTxt[it.Bonus2 - 1].NameAdd or "?"
		end
	end
	it.Identified = true
	log("item %d: bonus %d/%d, special %d, flaw %s (Q %d, rank %d, skill %d)",
		it.Number, it.Bonus, it.BonusStrength, it.Bonus2, tostring(flaw), q, rank, skill)
	return "ok", flaw
end

---------------------------------------------------------------------------
-- the hook: Enchant Item has picked its target (0x428CBA: [ebp-0x24] the target player)
---------------------------------------------------------------------------

local SUCCESS, FAIL = 0x4295FE, 0x42961A

local function install()
	mem.autohook2(0x428CBA, function(d)
		local ok, res, flaw = pcall(function()
			local tptr = u4[d.ebp - 0x24]
			local target = MF.GetPlayerFromPtr(tptr)
			local caster = MF.GetPlayerFromPtr(u4[d.ebp - 0x1C]) or target
			local idx = u4[d.ebp - 0x30]
			local itPtr = tptr + idx * 36 + 0x4A8
			local it = structs.Item:new(itPtr)
			local rank = max(1, min(4, u4[d.ebp - 0xC]))
			local skill = i4[d.ebp - 0x3C]
			local chance = i4[d.ebp - 0x18]
			u4[d.ebp - 0x34] = itPtr + 0x14          -- the item's flags, for the game's success code
			return enchant(caster, target, it, rank, skill, chance)
		end)
		if not ok then
			MF.LogWarning("[EnchantItem] %s", tostring(res))
			res = "invalid"
		end
		if res == "ok" then
			if flaw then status(string.format(Tx"The ritual is flawed: %s", flaw)) end
			d:push(SUCCESS)
		else
			u4[d.ebp - 0x8] = 1                       -- the game's "spell failed" text
			if res == "broken" then status(Tx"The ritual fails and the item breaks!") end
			d:push(FAIL)
		end
		return true
	end, 6)
end

---------------------------------------------------------------------------
-- the flaws
---------------------------------------------------------------------------

local function has(pl, b) return pl and pl:HasItemBonus(b) > 0 end

local RES = {"FireResistance", "AirResistance", "WaterResistance", "EarthResistance",
	"MindResistance", "BodyResistance", "SpiritResistance", "LightResistance", "DarkResistance"}
local RES_SET = {}

-- a flawed weapon in hand (Unsteady)
local function unsteadyWeapon(pl)
	for _, s in ipairs{"ItemMainHand", "ItemExtraHand", "ItemBow"} do
		local i = pl[s]
		if i and i > 0 then
			local it = pl.Items[i]
			if it.Bonus2 == FLAW.Unsteady and not it.Broken then return true end
		end
	end
	return false
end

function events.CalcStatBonusByItems(t)
	local pl, st = t.Player, const.Stats
	if not pl then return end
	if t.Stat == st.Luck and has(pl, FLAW.IllOmened) then
		t.Result = t.Result + C.ILL_LUCK
	elseif t.Stat == st.Accuracy and has(pl, FLAW.Unsteady) and not unsteadyWeapon(pl) then
		t.Result = t.Result + C.UNSTEADY_ACCURACY
	elseif RES_SET[t.Stat] and has(pl, FLAW.Cursed) then
		t.Result = t.Result + C.CURSED_RES
	end
end

function events.GetAttackDelay(t)
	local pl = t.Player
	if pl and unsteadyWeapon(pl) then t.Result = t.Result + C.UNSTEADY_RECOVERY end
end

-- Draining and Shadowed, every half second
local LastHP, NextDrain = {}, nil
function events.Tick()
	if Game.CurrentScreen ~= const.Screens.Game then return end
	local now = Game.Time
	local drain = NextDrain and now >= NextDrain
	if not NextDrain or drain then NextDrain = now + C.DRAIN_MINUTES * const.Minute end
	for i, pl in Party do
		if drain and has(pl, FLAW.Draining) and pl.SpellPoints > 0 then
			pl.SpellPoints = pl.SpellPoints - 1
		end
		local hp = pl.HitPoints
		local last = LastHP[i]
		if last and hp > last and last > 0 and has(pl, FLAW.Shadowed) then
			pl.HitPoints = last + floor((hp - last) * C.SHADOW_HEAL)
		end
		LastHP[i] = pl.HitPoints
	end
end
function events.LoadMap() LastHP = {} end

function events.GameInitialized2()
	for _, k in ipairs(RES) do
		if const.Stats[k] then RES_SET[const.Stats[k]] = true end
	end
	-- Brittle: wear (MMMWE_ItemDurability.lua)
	local wear = MF.WearMultiplier
	MF.WearMultiplier = function(pl, it)
		local m = wear and wear(pl, it) or 1
		if it and it.Bonus2 == FLAW.Brittle then m = m * 2 end
		return m
	end
	-- Ill-omened: threat (MMMWE_Threat.lua asks MF.LegendaryThreatMult)
	local threat = MF.LegendaryThreatMult
	MF.LegendaryThreatMult = function(pl)
		local m = threat and threat(pl) or 1
		if has(pl, FLAW.IllOmened) then m = m * C.ILL_THREAT end
		return m
	end
	local ok, err = pcall(install)
	if not ok then MF.LogWarning("[EnchantItem] not installed: %s", tostring(err)) end
end
