--[[
	MMMWE_EnchantScaling.lua — damaging weapon enchantments scale with weapon and/or magic skill

	Every time a weapon enchantment adds damage (events.ItemAdditionalDamage, MM8 0x4378CD),
	the amount the game rolled is multiplied by:

	    (1 + weapon part + magic part)  *  (TwoHandedMul for two-handed weapons)

	  weapon part = PerSkillMastery      * skill * mastery of THAT weapon's skill
	                (a sword's fire damage scales with Sword, a bow's with Bow; in dual-wield
	                each weapon's enchantment uses its own skill)
	  magic part  = PerMagicSkillMastery * skill * mastery of the magic school matching the
	                damage element (Fire -> Fire Magic, Air -> Air Magic, Water -> Water Magic,
	                Earth -> Earth, Spirit, Mind, Body, Light, Dark -> the same school)

	EnchantScaling.Mode picks what counts:
	  "Weapon"  only the weapon skill (default)
	  "Magic"   only the magic school of the element
	  "Both"    both parts added together
	  "None"    no skill scaling (the two-handed bonus still applies)
	Change it in this file, in game on the "Enchantment scaling" page of the Extra Settings
	menu (use the arrows at the bottom to switch pages), or from the console:
	EnchantScaling.SetMode("Both"). The mode and the multipliers chosen in game are saved
	with the game.

	Examples, "Weapon" mode with the defaults (1% per skill x mastery point, x1.5 two-handed):
	  Expert 10 (2):  x1.20      two-handed: x1.80
	  Master 15 (3):  x1.45      two-handed: x2.175
	  GM 20 (4):      x1.80      two-handed: x2.70

	Works together with MMMWE_ConcurrentEnchantments.lua: a weapon's permanent enchantment
	that keeps working under a temporary one (Fire Aura, potions) is scaled the same way.
	The resistance of the monster is applied after scaling, as before.
--]]

EnchantScaling = EnchantScaling or {}
local E = EnchantScaling

E.Enabled         = (E.Enabled == nil) and true or E.Enabled
E.Mode            = E.Mode or "Weapon"          -- "Weapon", "Magic", "Both" or "None"
E.PerSkillMastery = E.PerSkillMastery or 0.01   -- weapon: +1% per point of skill x mastery
E.PerMagicSkillMastery = E.PerMagicSkillMastery or 0.01  -- magic: +1% per point of skill x mastery
E.TwoHandedMul    = E.TwoHandedMul or 1.5       -- two-handed weapons: +50%
E.MinDamage       = E.MinDamage or 1            -- scaled damage is never below this (if it was > 0)
E.DescriptionNote = (E.DescriptionNote == nil) and true or E.DescriptionNote  -- note on item texts

local MF = Merge.Functions
local floor, max = math.floor, math.max

-- Damage element -> magic school
local D, SK = const.Damage, const.Skills
local SchoolByDamage = {
	[D.Fire] = SK.Fire, [D.Air] = SK.Air, [D.Water] = SK.Water, [D.Earth] = SK.Earth,
	[D.Spirit] = SK.Spirit, [D.Mind] = SK.Mind, [D.Body] = SK.Body,
	[D.Light] = SK.Light, [D.Dark] = SK.Dark,
}
E.SchoolByDamage = SchoolByDamage

local Modes = {Weapon = true, Magic = true, Both = true, None = true}

function E.SetMode(mode)
	assert(Modes[mode], 'EnchantScaling.SetMode: use "Weapon", "Magic", "Both" or "None"')
	E.Mode = mode
	vars.EnchantScalingMode = mode
end

local function skillPart(pl, skill, perPoint)
	local S, M = SplitSkill(pl:GetSkill(skill))
	return perPoint * S * M
end

-- Multiplier for an item in a player's hands; damageKind picks the magic school
function E.GetMultiplier(pl, item, damageKind)
	if not (E.Enabled and pl and item) then
		return 1
	end
	local txt = Game.ItemsTxt[item.Number]
	if not txt then
		return 1
	end
	local mode = E.Mode
	local bonus = 0
	if mode == "Weapon" or mode == "Both" then
		local skill = txt.Skill
		if skill and skill >= 0 and skill <= 7 then  -- staff .. blaster
			bonus = bonus + skillPart(pl, skill, E.PerSkillMastery)
		end
	end
	if mode == "Magic" or mode == "Both" then
		local school = damageKind and SchoolByDamage[damageKind]
		if school then
			bonus = bonus + skillPart(pl, school, E.PerMagicSkillMastery)
		end
	end
	local mul = 1 + bonus
	if txt.EquipStat == 1 then                       -- two-handed weapon
		mul = mul * E.TwoHandedMul
	end
	return mul
end

-- Scaled enchantment damage (used here and by MMMWE_ConcurrentEnchantments.lua)
function E.Scale(pl, item, dmg, damageKind)
	if not dmg or dmg <= 0 then
		return dmg
	end
	return max(E.MinDamage, floor(dmg * E.GetMultiplier(pl, item, damageKind) + 0.5))
end
MF.ScaleEnchantDamage = E.Scale

-- Scale the game's enchantment damage. MMMWE_ConcurrentEnchantments.lua may already have
-- added its own (already scaled) part to t.Result and recorded it in t.CEAdded; that part
-- is left alone, so the order of the two handlers doesn't matter.
function events.ItemAdditionalDamage(t)
	if not E.Enabled or not t.Player or not t.Item then
		return
	end
	local added = t.CEAdded or 0
	local native = t.Result - added
	if native > 0 then
		t.Result = E.Scale(t.Player, t.Item, native, t.DamageKind) + added
	end
	t.EnchantScaled = true
end

-- Item descriptions: add a note to every damaging enchantment
local Notes = {
	Weapon = " Scales with weapon skill.",
	Magic  = " Scales with magic skill.",
	Both   = " Scales with weapon and magic skill.",
}

local function updateTexts()
	local note = E.DescriptionNote and Notes[E.Mode] or ""
	for i, v in Game.SpcItemsTxt do
		local s = v.BonusStat
		if s and s:find("points of %a+ damage") then
			-- drop any previous note, then add the one for the current mode
			local base = s
			for _, n in pairs(Notes) do
				local i1 = base:find(n, 1, true)
				if i1 then base = base:sub(1, i1 - 1) end
			end
			local new = base .. note
			if new ~= s then
				v.BonusStat = new
			end
		end
	end
end
E.UpdateTexts = updateTexts

function events.GameInitialized2()
	updateTexts()
end

-- Values that can be changed in the Extra Settings menu and are saved with the game
local SavedFields = {"PerSkillMastery", "PerMagicSkillMastery", "TwoHandedMul"}

function events.BeforeSaveGame()
	vars.EnchantScalingMode = E.Mode
	vars.EnchantScalingValues = vars.EnchantScalingValues or {}
	for _, f in ipairs(SavedFields) do
		vars.EnchantScalingValues[f] = E[f]
	end
end

function events.AfterLoadMap()
	-- the mode and multipliers chosen in game are saved with the savegame
	if vars.EnchantScalingMode and Modes[vars.EnchantScalingMode] then
		E.Mode = vars.EnchantScalingMode
	end
	local saved = vars.EnchantScalingValues
	if saved then
		for _, f in ipairs(SavedFields) do
			if tonumber(saved[f]) then
				E[f] = saved[f]
			end
		end
	end
	updateTexts()
end

local setMode = E.SetMode
function E.SetMode(mode)
	setMode(mode)
	updateTexts()
end

---------------------------------------------------------------------------
-- Extra Settings menu page (same style as "Bolster multipliers")
---------------------------------------------------------------------------

local ModeOrder = {"Weapon", "Magic", "Both", "None"}
local ModeNames = {
	Weapon = "Weapon skill",
	Magic  = "Magic skill",
	Both   = "Weapon + magic",
	None   = "Off",
}

local function MenuText(Screen, Text, X, Y, Action, AlignLeft)
	if AlignLeft == nil then
		AlignLeft = true
	end
	return CustomUI.CreateText{
		Text = Text,
		Font = Game.Smallnum_fnt,
		X = X, Y = Y,
		ColorStd = 0xFFFF,
		ColorMouseOver = Action and 0xe664 or 0xFFFF,
		Layer = 1,
		Screen = Screen,
		AlignLeft = AlignLeft,
		Action = Action,
	}
end

local function Yellow(text)
	return StrColor(255, 255, 150) .. text .. StrColor(255, 255, 255)
end

-- Columns shared by every row (the menu font is proportional, so labels can't be padded
-- with spaces to line up): label | "<" | value | ">"
local COL_LABEL, COL_LEFT, COL_VALUE, COL_RIGHT = 80, 230, 248, 390

-- "<  value  >" selector; Get/Set read and change the value, Show turns it into text
local function Selector(Screen, Y, Header, Get, Set, Show)
	local o = {}
	o.Header = MenuText(Screen, Yellow(Header), COL_LABEL, Y)
	local function refresh()
		o.Value.Text = Show(Get())
		o.Value:UpdateSize()
	end
	o.Left = MenuText(Screen, "<", COL_LEFT, Y, function()
		Game.PlaySound(24)
		Set(-1)
		refresh()
	end)
	o.Value = MenuText(Screen, Show(Get()), COL_VALUE, Y)
	o.Right = MenuText(Screen, ">", COL_RIGHT, Y, function()
		Game.PlaySound(23)
		Set(1)
		refresh()
	end)
	o.Update = refresh
	return o
end

local function stepNumber(field, step, low, high)
	return function(side)
		local v = E[field] + step * side
		v = math.max(low, math.min(high, v))
		E[field] = math.floor(v * 1000 + 0.5) / 1000
	end
end

local function percent(v)
	return string.format("%g%%", v * 100)
end

function events.GameInitialized2()
	if not (CustomUI and CustomUI.NewSettingsPage) then
		return
	end
	local Screen = CustomUI.NewSettingsPage("EnchantScaling", "Enchantment scaling", "ExSetScr2")
	local items = {}

	items[#items + 1] = Selector(Screen, 190, "Scale with",
		function() return E.Mode end,
		function(side)
			local i = table.find(ModeOrder, E.Mode) or 1
			i = (i - 1 + side) % #ModeOrder + 1
			E.SetMode(ModeOrder[i])
		end,
		function(v) return ModeNames[v] or v end)

	items[#items + 1] = Selector(Screen, 220, "Per weapon point",
		function() return E.PerSkillMastery end,
		stepNumber("PerSkillMastery", 0.0025, 0, 0.1),
		percent)

	items[#items + 1] = Selector(Screen, 250, "Per magic point",
		function() return E.PerMagicSkillMastery end,
		stepNumber("PerMagicSkillMastery", 0.0025, 0, 0.1),
		percent)

	items[#items + 1] = Selector(Screen, 280, "Two-handed",
		function() return E.TwoHandedMul end,
		stepNumber("TwoHandedMul", 0.05, 1, 3),
		function(v) return string.format("x%g", v) end)

	MenuText(Screen, "Damage scale = (100 + X) percent x skill x mastery.", COL_LABEL, 320)

	function events.OpenExtraSettingsMenu()
		for _, o in ipairs(items) do
			o.Update()
		end
	end
end
