-- MMMWE: custom class promotions (stage 3 of the custom classes)
--
-- The rulers of the continents promote custom classes once the party has reached a story
-- milestone of that continent. Resurectra and Kastore give the light or the dark second
-- promotion; King Nicolai gives the neutral one.
--
--   Jadame      Bastian Loudrin   base -> first promotion     Overdune, the troll witness, is brought to him
--   Antagarich  Queen Catherine   base -> first promotion     Castle Harmondale is restored
--   Antagarich  Resurectra        first/neutral -> light      the party chose the path of Light
--   Antagarich  Kastore           first/neutral -> dark       the party chose the path of Dark
--   Enroth      King Nicolai      base -> first promotion     the council lets the party in
--   Enroth      King Nicolai      first -> neutral            all four Oracle memory crystals
--
-- Every eligible custom-class party member is promoted at once, as with the preset classes.
-- Skills above the caps of the new class are lowered and the skill points come back
-- (MF.ConvertCharacter), which can only happen when a neutral character goes light or dark.

local MF = Merge.Functions
local Tx, Tn = Merge.Functions.Text, Merge.Functions.TextKey
local CC = MF.CustomClasses
if not CC then
	return
end

local function qbits(...)
	local bits = {...}
	return function()
		for _, b in ipairs(bits) do
			if not Party.QBits[b] then
				return false
			end
		end
		return true
	end
end

-- step numbers: 1 base, 2 first promotion, 3 neutral, 4 light, 5 dark
local PROMOTERS = {
	{NPC = 5, Slot = 1,      -- Bastian Loudrin
		{From = {1}, To = 2, Gate = qbits(59), Need = Tx"you have brought me the witness from the Ironsand Desert"},
	},
	{NPC = 408, Slot = 5,    -- Queen Catherine
		{From = {1}, To = 2, Gate = qbits(610), Need = Tx"Castle Harmondale has been restored"},
	},
	{NPC = 419, Slot = 2,    -- Resurectra
		{From = {2, 3}, To = 4, Gate = qbits(611), Need = Tx"you have chosen the path of Light"},
	},
	{NPC = 423, Slot = 2,    -- Kastore
		{From = {2, 3}, To = 5, Gate = qbits(612), Need = Tx"you have chosen the path of Dark"},
	},
	{NPC = 798, Slot = 2,    -- King Nicolai Ironfist
		{From = {1}, To = 2, Gate = qbits(1191), Need = Tx"the council has allowed you in"},
		{From = {2}, To = 3, Gate = qbits(1124, 1125, 1126, 1127),
			Need = Tx"all four memory crystals are back in the Oracle"},
	},
}

local TOPIC = Tx"Promote custom classes"

local function stepOf(pl)
	local f, step = CC.FamilyOf(pl.Class)
	if f and CC.Builds()[f] then
		return step, f
	end
end

-- the rule of this promoter that applies to a step, if any
local function ruleFor(promoter, step)
	for _, rule in ipairs(promoter) do
		for _, from in ipairs(rule.From) do
			if from == step then
				return rule
			end
		end
	end
end

local function candidates(promoter)
	local list = {}
	for i = 0, Party.Count - 1 do
		local pl = Party[i]
		local step = stepOf(pl)
		local rule = step and ruleFor(promoter, step)
		if rule then
			list[#list + 1] = {Player = pl, Rule = rule}
		end
	end
	return list
end

local function stepName(f, step)
	local fam = CC.Builds()[f]
	local s = fam and fam.Steps[step]
	return s and s.Name ~= "" and s.Name or CC.StepNames[step]
end

local function promoteAll(promoter)
	local done, waiting = {}, {}
	for _, c in ipairs(candidates(promoter)) do
		local pl, rule = c.Player, c.Rule
		local step, f = stepOf(pl)
		if rule.Gate() then
			local refund, err = CC.Promote(pl, rule.To)
			if refund then
				local line = string.format(Tx"%s is now a %s.", pl.Name, stepName(f, rule.To))
				if refund > 0 then
					line = line .. string.format(Tx" %d skill points were refunded.", refund)
				end
				done[#done + 1] = line
			else
				done[#done + 1] = string.format(Tx"%s can't be promoted: the %s build has a problem (%s).",
					pl.Name, stepName(f, rule.To), err)
			end
		else
			waiting[rule.Need] = waiting[rule.Need] or {}
			table.insert(waiting[rule.Need], pl.Name)
		end
	end
	local text = {}
	if #done > 0 then
		text[1] = Tx"You have earned it. " .. table.concat(done, " ")
	end
	for need, names in pairs(waiting) do
		text[#text + 1] = string.format(Tx"%s will be promoted once %s.", table.concat(names, ", "), need)
	end
	Message(table.concat(text, "\n\n"))
end

for _, promoter in ipairs(PROMOTERS) do
	NPCTopic{
		Name = "MMMWE_CustomPromotion_" .. promoter.NPC,
		NPC = promoter.NPC,
		Slot = promoter.Slot,
		Topic = TOPIC,
		NeverGiven = true,
		NeverDone = true,
		CanShow = function() return #candidates(promoter) > 0 end,
		Done = function() promoteAll(promoter) end,
	}
end

---------------------------------------------------------------------------
-- (09.11.26) the preset promoters: a custom class whose base build resembles a preset base
-- class (CC.PresetMatch, at least CC.PresetMatchMin of its skill caps) is promoted by that
-- class's promoters and quests (PromotionTopics.lua) as well - to its own steps. For their
-- checks a custom character counts as the preset class of the same step
-- (MF.PresetClassOf); a preset first promotion then gives the custom first promotion, a
-- light / dark / neutral second promotion the custom light / dark / neutral step.
---------------------------------------------------------------------------

local MT = Merge.Tables

-- the custom step a preset promotion class stands for, and the steps it promotes from
local function stepFor(presetClass)
	local ce = Game.ClassesExtra[presetClass]
	if not ce then return end
	if ce.Step == 1 then return 2, {1} end
	if ce.Step == 2 then
		if ce.Alignment == const.Alignment.Good then return 4, {2, 3} end
		if ce.Alignment == const.Alignment.Evil then return 5, {2, 3} end
		return 3, {2}
	end
end

-- the preset classes of a base class's five steps: base, first promotion, neutral, light, dark
local function presetSteps(base)
	local t = {base}
	local first = MT.ClassPromotions and MT.ClassPromotions[base] and MT.ClassPromotions[base][1]
	t[2] = first or base
	t[3], t[4], t[5] = t[2], t[2], t[2]
	for _, c in ipairs(first and MT.ClassPromotions[first] or {}) do
		local st = stepFor(c)
		if st then t[st] = c end
	end
	return t
end

local Preset = {}         -- [family] = {five preset classes}, kept for the game's builds
local function presetOf(f)
	local fam = CC.Builds()[f]
	if not fam then return end
	local base, score = CC.PresetMatch(fam)
	if not base or score < CC.PresetMatchMin then return end
	return presetSteps(base)
end

-- the preset class a custom class character counts as for the preset promoters (nil for
-- other characters and for builds that resemble no preset class)
function MF.PresetClassOf(pl)
	local f, step = CC.FamilyOf(pl.Class)
	if not f then return end
	local t = presetOf(f)
	return t and t[step]
end

-- a preset promotion of a custom class character becomes the promotion to its own step
local convert = MF.ConvertCharacter
MF.ConvertCharacter = function(t)
	local pl, to = t.Player, t.ToClass
	local f, step = pl and CC.FamilyOf(pl.Class)
	if f and to and not CC.FamilyOf(to) and presetOf(f) then
		local toStep, from = stepFor(to)
		if toStep and table.find(from, step) then
			local refund, err = CC.Promote(pl, toStep)
			if not refund then
				Message(string.format(Tx"%s can't be promoted: the %s build has a problem (%s).",
					pl.Name, stepName(f, toStep), tostring(err)))
			end
			if t.ToMaturity and pl.Attrs then
				convert({Player = pl, ToMaturity = t.ToMaturity})
			end
			return
		end
	end
	return convert(t)
end
