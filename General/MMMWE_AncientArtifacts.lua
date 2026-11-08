--[[
	MMMWE_AncientArtifacts.lua — artifacts and relics of the Ancients (01.11.26)

	Items 2213-2224 (ITEMS.txt; rnditems.txt gives them no chance to be found, so they don't
	appear in the game until their pictures are drawn: the icons are recoloured placeholders).
	Stats, skills and party buffs are in ExtraArtifacts.lua; the effects below need code:

	  Padish's Signet (2213)          Heavenly Forge items worn by the bearer don't wear out,
	                                  armor pieces give +SignetAC Armor Class, weapons +SignetDamage
	  VARN Officer's Visor (2214)     (bonuses only)
	  Servo Gauntlets (2215)          a cestus: 2d8 Energy on bare-handed blows (MMMWE_Cestus.lua)
	  Phase Cloak (2216)              PhaseChance % of hits pass through; PhaseThreat x attacks drawn
	  Gravity Treads (2217)           a worn Jetpack uses half its charge (MMMWE_Main.lua)
	  Officer's Shield Module (2218)  an Energy Shield with a sealed board (MMMWE_Blasters.lua FIXED)
	  Padish's Sidearm (2219)         a blaster pistol with a sealed board; its cell recharges
	                                  outdoors in daylight (SunCharge per SunEvery game minutes)
	  Command Cube (2220)             Construction maximum +CubeConstruction; droids and turrets
	                                  x CubeTime duration, x CubeHP Hit Points (MMMWE_Resources.lua)
	  Plasma Edge (2221, relic)       hits deal their damage as Energy (no physical resistance)
	                                  + EdgeBonus while the cell (Charges) holds; empty: 1-3
	  Ancient Power Core (2222, relic) a new day recharges the bearer's blasters, shields and
	                                  devices; the bearer loses CoreDrain HP per game minute
	  Sentinel Frame (2223, relic)    no recovery penalty for the plate body armor
	  Neural Crown (2224, relic)      +CrownExp % experience (MMMWE_Learning.lua)
--]]

local MF = Merge.Functions
local Tx, Tn = Merge.Functions.Text, Merge.Functions.TextKey
local floor, min, max, random = math.floor, math.min, math.max, math.random

local A = {
	SignetAC        = 5,
	SignetDamage    = 0.10,
	PhaseChance     = 10,
	PhaseThreat     = 0.70,
	SunCharge       = 1,                 -- power cell units (0.5% each) ...
	SunEvery        = 5,                 -- ... per this many game minutes outdoors, 6:00-20:00
	CubeConstruction = 50,
	CubeTime        = 2,
	CubeHP          = 1.25,
	EdgeCell        = 300,               -- hits on a full cell
	EdgeBonus       = 15,
	CoreDrain       = 1,
	CrownExp        = 20,
	PlatePenalty    = {30, 15, 15, 0},   -- body armor recovery % of plate by mastery (MMMWE_Main.lua)
}
MF.AncientArtifactSettings = A

local SIGNET, VISOR, SERVO, PHASE, TREADS, MODULE, SIDEARM, CUBE, EDGE, CORE, FRAME, CROWN =
	2213, 2214, 2215, 2216, 2217, 2218, 2219, 2220, 2221, 2222, 2223, 2224

-- made by the Heavenly Forges of Governor Padish (the item texts say so)
local FORGE = {
	[877] = true, [1677] = true, [1306] = true,      -- Golden and Majestic Chain Mail, Governor's Armor
	[890] = true, [1690] = true,                     -- Majestic and Astral Shield
	[1654] = true, [837] = true, [1637] = true,      -- Thunder Mace, Sublime and Sacred Spear
	[1624] = true, [1648] = true, [549] = true,      -- Divine Dagger, Stellar Bow, Supreme Maul
	[1355] = true, [1356] = true,                    -- Heavenly Warhammer, Okkam's Razor
	[MODULE] = true, [SIDEARM] = true, [EDGE] = true,
	[2228] = true,                                   -- Warscythe (Global\ExtraArtifacts.lua)
}
MF.HeavenlyForgeItems = FORGE

local SLOTS = {"ItemArmor", "ItemHelm", "ItemBelt", "ItemCloak", "ItemGauntlets", "ItemBoots",
	"ItemAmulet", "ItemExtraHand", "ItemMainHand", "ItemBow",
	"ItemRing1", "ItemRing2", "ItemRing3", "ItemRing4", "ItemRing5", "ItemRing6"}

-- the item with this number the player wears (not broken), or nil
local function worn(pl, num, slotName)
	local slots = slotName and {slotName} or SLOTS
	for _, s in ipairs(slots) do
		local idx = pl[s]
		if idx and idx > 0 then
			local it = pl.Items[idx]
			if it.Number == num and not it.Broken then return it end
		end
	end
end
MF.WearsItem = worn

local function hpi(pl) return pl:GetIndex() end

---------------------------------------------------------------------------
-- Padish's Signet
---------------------------------------------------------------------------

function MF.WearMultiplier(pl, it)
	if FORGE[it.Number] and worn(pl, SIGNET) then return 0 end
	return 1
end

function events.CalcStatBonusByItems(t)
	if t.Stat ~= const.Stats.ArmorClass then return end
	local pl = t.Player
	if not pl or not worn(pl, SIGNET) then return end
	for _, s in ipairs{"ItemArmor", "ItemHelm", "ItemBelt", "ItemCloak", "ItemGauntlets", "ItemBoots", "ItemExtraHand"} do
		local idx = pl[s]
		if idx > 0 then
			local it = pl.Items[idx]
			local es = Game.ItemsTxt[it.Number].EquipStat
			if FORGE[it.Number] and not it.Broken and es >= 3 and es <= 9 then   -- armor pieces and shields
				t.Result = t.Result + A.SignetAC
			end
		end
	end
end

---------------------------------------------------------------------------
-- Gravity Treads, Command Cube, Neural Crown (used by other scripts)
---------------------------------------------------------------------------

function MF.JetpackSaver(pl)
	return worn(pl, TREADS, "ItemBoots") ~= nil
end

function MF.ResourceMaxBonus(pl, name)
	if name == "Construction" and worn(pl, CUBE, "ItemAmulet") then return A.CubeConstruction end
	return 0
end
function MF.MachineTimeMult(pl) return worn(pl, CUBE, "ItemAmulet") and A.CubeTime or 1 end
function MF.MachineHPMult(pl) return worn(pl, CUBE, "ItemAmulet") and A.CubeHP or 1 end

function MF.ItemExpBonus(pl)
	return worn(pl, CROWN, "ItemHelm") and A.CrownExp or 0
end

---------------------------------------------------------------------------
-- Plasma Edge: the cell in Charges (1000 + hits left; below 1000: never set up, full)
---------------------------------------------------------------------------

local function edgeCell(it)
	if it.Charges < 1000 then it.Charges = 1000 + A.EdgeCell end
	return it.Charges - 1000
end
local function edgeSet(it, v) it.Charges = 1000 + max(0, min(A.EdgeCell, floor(v))) end
MF.PlasmaEdgeCell = edgeCell

---------------------------------------------------------------------------
-- hits
---------------------------------------------------------------------------

local function onPlayerHit(t)
	local pl = t.Player
	if not pl or (t.Result or 0) <= 0 then return end
	if worn(pl, PHASE, "ItemCloak") and random(100) <= A.PhaseChance then
		t.Result = 0
		MF.MissedPlayer = pl["?ptr"]           -- no special effect either (MMMWE_MonkBranches.lua)
		Game.ShowStatusText(string.format(Tx"The blow passes through %s's phase field!", pl.Name), 2)
	end
end

local function onMonsterHit(t)
	if not t.ByPlayer or t.IsSecondary or not t.Melee or t.DamageKind ~= const.Damage.Phys then return end
	if MF.BlasterSpecs and MF.BlasterSpecs.Forced then return end
	local pl = t.Player
	if not pl then return end
	local slot = pl.ItemMainHand
	local it = slot > 0 and pl.Items[slot]
	if not it or it.Broken then return end
	if it.Number == EDGE then
		local cell = edgeCell(it)
		if cell > 0 then
			edgeSet(it, cell - 1)
			t.Result = (t.Damage or 0) + A.EdgeBonus
			if cell - 1 == floor(A.EdgeCell / 10) then
				Game.ShowStatusText(Tx"The Plasma Edge flickers: its cell is nearly empty.", 2)
			end
		else
			t.Result = random(1, 3)
		end
	end
	if FORGE[it.Number] and worn(pl, SIGNET) then
		t.Result = floor(t.Result * (1 + A.SignetDamage) + 0.5)
	end
end

---------------------------------------------------------------------------
-- recharging
---------------------------------------------------------------------------

local DEVICE_MAX = {[963] = 100, [964] = 100, [965] = 100, [967] = 100, [966] = 1000}

local function rechargeAll(pl)
	for i = 1, pl.Items.limit or 138 do
		local it = pl.Items[i]
		local n = it and it.Number or 0
		if n > 0 then
			if (MF.IsBlasterItem and MF.IsBlasterItem(n)) or (MF.IsShieldItem and MF.IsShieldItem(n)) then
				if MF.BlasterRecharge then MF.BlasterRecharge(it, 100) end
			elseif DEVICE_MAX[n] then
				it.Charges = max(it.Charges, DEVICE_MAX[n])
			elseif n == EDGE then
				edgeSet(it, A.EdgeCell)
			end
		end
	end
end

function events.NewDay(t)
	for _, pl in Party do
		if worn(pl, CORE, "ItemAmulet") then
			rechargeAll(pl)
			Game.ShowStatusText(string.format(Tx"%s's Power Core hums: every device is charged.", pl.Name), 3)
		end
	end
end

-- Sidearm in daylight, Power Core drain: once a game minute
local lastMinute
local sun = {}   -- [PlayersArray index] = game minutes in the sun not yet turned into charge
function events.Tick()
	local now = floor(Game.Time / const.Minute)
	if not lastMinute or now < lastMinute then lastMinute = now return end
	local passed = min(now - lastMinute, 60 * 24)
	if passed <= 0 then return end
	lastMinute = now
	local hour = floor(Game.Time / const.Hour) % 24
	local sunny = hour >= 6 and hour < 20 and Map.IsOutdoor()
	for _, pl in Party do
		if sunny then
			local slot = pl.ItemMainHand
			local it = slot > 0 and pl.Items[slot]
			if it and it.Number == SIDEARM and MF.BlasterState then
				MF.BlasterState(it)                -- sets up the sealed board of a new one
				local i = hpi(pl)
				sun[i] = (sun[i] or 0) + passed
				local units = floor(sun[i] / A.SunEvery)
				if units > 0 then
					sun[i] = sun[i] - units * A.SunEvery
					it.MaxCharges = min(200, it.MaxCharges + A.SunCharge * units)
				end
			end
		end
		if worn(pl, CORE, "ItemAmulet") and pl.HP > 1 then
			pl.HP = max(1, pl.HP - A.CoreDrain * passed)
		end
	end
end

---------------------------------------------------------------------------
-- registration
---------------------------------------------------------------------------

function events.GameInitialized2()
	-- Plasma Edge and the Signet's damage: after MMMWE_DamageKinds.lua, before the crits and
	-- bonuses of MMMWE_Main.lua (registered in its own GameInitialized2, later)
	events.CalcDamageToMonster = onMonsterHit

	-- Phase Cloak: after the damage handlers of MMMWE_Main.lua, before the Energy Shield
	-- (both register on the first map load; this file's GameInitialized2 runs first)
	local hooked = false
	function events.LoadMap()
		if hooked then return end
		hooked = true
		events.CalcDamageToPlayer = onPlayerHit
	end

	-- Phase Cloak: fewer attacks drawn (MMMWE_Threat.lua)
	local stance = MF.StanceThreatMult
	MF.StanceThreatMult = function(pl)
		local m = stance and stance(pl) or 1
		if worn(pl, PHASE, "ItemCloak") then m = m * A.PhaseThreat end
		return m
	end

	-- Sentinel Frame: the plate body armor adds no recovery (MMMWE_Main.lua ArmorRecoveryPct)
	local recMod = MF.ArmorRecoveryMod
	MF.ArmorRecoveryMod = function(pl)
		local r = recMod and recMod(pl) or 0
		if worn(pl, FRAME, "ItemArmor") then
			local _, M = SplitSkill(pl:GetSkill(const.Skills.Plate))
			r = r - (A.PlatePenalty[max(1, min(4, M))] or 0)
		end
		return r
	end

	-- Recharge Item potion: the Plasma Edge's cell
	local potion = evt.PotionEffects and evt.PotionEffects[13]
	if potion then
		evt.PotionEffects[13] = function(IsDrunk, Target, Power, ...)
			if not IsDrunk and Target and Target.Number == EDGE then
				edgeSet(Target, edgeCell(Target) + A.EdgeCell * (Power or 0) / 100)
				Game.ShowStatusText(string.format(Tx"Plasma Edge: %d%%", floor(edgeCell(Target) * 100 / A.EdgeCell)))
				return 3
			end
			return potion(IsDrunk, Target, Power, ...)
		end
	end
end
