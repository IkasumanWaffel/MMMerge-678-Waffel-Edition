--[[
	MMMWE_Threat.lua — armored characters draw monsters' attacks

	Monsters choose which party member to hit in MonstersTweaks.lua (it replaces
	mon_chooses_player 0x425203): every character gets a weight from the monster's
	class / race / sex / party slot preferences, and the target is picked at random in
	proportion to the weights. This script multiplies each weight by the character's
	threat and picks again, so the monster preference tables keep working; threat only
	tilts the odds. It applies to melee and ranged monster attacks alike.

	Threat = sum over armor pieces of  weight x type factor x (1 + MASTERY_BONUS x mastery)
	         + shield bonus x (1 + MASTERY_BONUS x shield mastery)
	  pieces and weights as in MMMWE_DamageKinds.lua (ARMOR_SLOT_WEIGHT): body armor 50%,
	  helm 15%, boots 15%, gauntlets 10%, belt 10%
	  type factor: none / broken / hat 1.0, leather 1.2, chain 1.5, plate 2.0
	  mastery of the piece's armor skill: Novice +20%, Expert +40%, Master +60%, Grand +80%
	  shield +0.25
	  e.g. Grand Master in a full plate set with a GM shield: 2 x 1.8 + 0.25 x 1.8 = 4.05
	  times a robed caster; plate body armor alone (GM): 0.5 x 3.6 + 0.5 = 2.3

	Hint: "Threat NN%" under the paperdoll on the character screen - the share of attacks this character draws from a monster with no
	preferences (characters who are dead, stoned, eradicated or unconscious draw none,
	paralyzed ones almost none).

	Console: Merge.Functions.PlayerThreat(player) -> threat factor
--]]

local MF = Merge.Functions
local SK = const.Skills

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local ENABLED = true

local ARMOR_THREAT = {
	[SK.Leather] = 1.2,
	[SK.Chain]   = 1.5,
	[SK.Plate]   = 2.0,
}
local NO_ARMOR_THREAT = 1.0
local SHIELD_BONUS    = 0.25
local MASTERY_BONUS   = 0.2      -- per mastery rank of the piece's armor skill

-- used if MMMWE_DamageKinds.lua doesn't provide the weights
local DEFAULT_SLOT_WEIGHT = {
	{"ItemArmor", 0.50}, {"ItemHelm", 0.15}, {"ItemBoots", 0.15},
	{"ItemGauntlets", 0.10}, {"ItemBelt", 0.10},
}

-- Hint under the paperdoll on every page of the character screen (640x480 screen coordinates).
-- The text is centered in a HINT_WIDTH wide box starting at HINT_X: the box is centered
-- on the Dismiss button (x 520..594).
local HINT_WIDTH = 120
local HINT_X     = 557 - HINT_WIDTH / 2
local HINT_Y     = 376
local HINT_COLOR = RGB(255, 255, 155)   -- like the character's name

---------------------------------------------------------------------------
-- Threat
---------------------------------------------------------------------------

local function wornSkill(pl, slot)
	if slot == 0 then return nil end
	local it = pl.Items[slot]
	if it.Number <= 0 or it.Broken then return nil end
	local txt = Game.ItemsTxt[it.Number]
	return txt and txt.Skill
end

local function masteryMul(pl, skill)
	local _, m = SplitSkill(pl:GetSkill(skill))
	return 1 + MASTERY_BONUS * (m or 0)
end

local function playerThreat(pl)
	local threat = 0
	for _, sw in ipairs(MF.ArmorSlotWeights or DEFAULT_SLOT_WEIGHT) do
		local skill = wornSkill(pl, pl[sw[1]])
		local f = skill and ARMOR_THREAT[skill]
		threat = threat + sw[2] * (f and f * masteryMul(pl, skill) or NO_ARMOR_THREAT)
	end
	if wornSkill(pl, pl.ItemExtraHand) == SK.Shield then
		threat = threat + SHIELD_BONUS * masteryMul(pl, SK.Shield)
	end
	return threat
end
MF.PlayerThreat = playerThreat

-- Weight of party member i for monster id (the Merge preferences x threat)
local function weight(id, i)
	local pl = Party[i]
	local w = MF.GetMonsterPlayerPref and MF.GetMonsterPlayerPref(id, i) or 1
	return w * playerThreat(pl)
end

function events.MonsterChooseTargetPlayer(t)
	if not ENABLED or Party.count <= 1 then return end
	local w, sum = {}, 0
	for i = 0, Party.count - 1 do
		w[i] = weight(t.MonsterId, i)
		sum = sum + w[i]
	end
	if sum <= 0 then return end
	local rnd = math.random() * sum
	local acc = 0
	for i = 0, Party.count - 1 do
		acc = acc + w[i]
		if w[i] > 0 and rnd < acc then
			t.Slot = i
			return
		end
	end
end

-- Share (0..1) of attacks party member i draws from a monster with no preferences
local function threatShare(i)
	local sum, mine = 0, 0
	for j = 0, Party.count - 1 do
		local w = weight(0, j)
		sum = sum + w
		if j == i then mine = w end
	end
	return sum > 0 and mine / sum or 0
end
MF.PlayerThreatShare = threatShare

---------------------------------------------------------------------------
-- Hint under the paperdoll
---------------------------------------------------------------------------

local function currentIndex()
	local cur = Party:GetCurrentPlayer()
	if not cur then return nil end
	for i = 0, Party.count - 1 do
		if Party[i]["?ptr"] == cur["?ptr"] then return i end
	end
end

-- right-click tooltip of the hint (shown while the right button is held over it)
local TIP_X, TIP_Y, TIP_W = 300, 200, 330
local function tipText(pl, share)
	return string.format("Threat\n \n"
		.. "Monsters prefer to attack characters in heavier armor. The percent is the share of "
		.. "attacks this character draws from a monster with no preferences of its own (a "
		.. "monster's taste for some classes, races or party positions comes on top).\n \n"
		.. "Each armor piece adds threat by its type - leather x1.2, chain x1.5, plate x2 - and "
		.. "weight: body armor half, helm and boots 15%% each, gauntlets and belt 10%% each; "
		.. "+20%% per mastery rank in its armor skill. A shield adds 0.25 (more with Shield "
		.. "mastery). Characters who are dead, stoned, eradicated or unconscious draw no attacks."
		.. "\n \nThreat factor: %.2f (a robed caster has 1.00)", playerThreat(pl))
end

local function mouseOverHint()
	return Mouse.X >= HINT_X + 20 and Mouse.X <= HINT_X + HINT_WIDTH - 20
		and Mouse.Y >= HINT_Y - 2 and Mouse.Y <= HINT_Y + 14
end

function events.GameInitialized2()
	if not CustomUI or not ENABLED then return end
	CustomUI.CreateText{
		Text      = "Threat 100%",
		Font      = Game.Smallnum_fnt,
		X = HINT_X, Y = HINT_Y,
		Width     = HINT_WIDTH,   -- wide enough to keep "Threat NN%" on one line
		Height    = 16,
		ColorStd  = HINT_COLOR,
		ColorMouseOver = HINT_COLOR,
		Layer     = 0,
		Screen    = const.Screens.Inventory,
		Condition = function(self)
			local i = currentIndex()
			if not i then return false end
			local ok, share = pcall(threatShare, i)
			if not ok then return false end
			self.Text = string.format("Threat %d%%", math.floor(share * 100 + 0.5))
			if Keys.IsPressed(const.Keys.RBUTTON) and mouseOverHint() then
				local ok2, txt = pcall(tipText, Party[i], share)
				if ok2 then CustomUI.ShowTooltip(txt, TIP_X, TIP_Y, TIP_W) end
			end
			return true
		end,
	}
end
