--[[
	MMMWE_Learning.lua — the experience bonus (01.11.26)

	The game's Learning percentage (Player:GetLearningTotalSkill, 0x49036E, as patched in
	RemoveSkillValueLimits.lua) is used for every experience gain: kills (AddKillExp) and
	events (Learning.lua). It was
	    mastery multiplier x Learning level  +  other bonuses (items, hirelings)  +  9
	so the hirelings' bonus (Scholar 5, Teacher 10, Instructor 15, NPCFollowersSkills.lua,
	added to the skill through events.GetSkill) and item bonuses were added flat.

	Now:
	    Mult x Learning level  +  BonusMult x (items + hirelings)  +  9
	  + IntellectPerPoint x the Intellect bonus (negative bonuses lower it)
	Mult is the game's: Novice 1, Expert 2, Master 3, Grand Master 5; the bonuses from
	items and hirelings grow more gently with the mastery (BonusMult).
	A character without the Learning skill gets the hirelings' and items' bonus once
	(Novice) and the 9% start, as before, plus the Intellect part.
	Experience is never lowered by more than MinPercent.
--]]

local MF = Merge.Functions

local L = {
	IntellectPerPoint = 2,      -- % experience per point of the Intellect bonus (-25 .. +40)
	Base              = 9,      -- the game's starting bonus with any Learning
	MinPercent        = -90,    -- the total never takes away more than this
	Mult              = {[0] = 1, 1, 2, 3, 5},     -- trained Learning, by mastery (the game's)
	BonusMult         = {[0] = 1, 1, 1.5, 2, 3},   -- items and hirelings, by Learning mastery
}
MF.LearningSettings = L

local LEARNING = const.Skills.Learning

-- the Learning part: trained level x Mult + (items + hirelings) x BonusMult + 9
function MF.LearningPercent(pl)
	local S, M = SplitSkill(pl:GetSkill(LEARNING))       -- with items and hirelings
	if S <= 0 then return 0 end
	local raw = SplitSkill(pl.Skills[LEARNING])
	raw = math.min(raw, S)
	return raw * (L.Mult[M] or 1) + (S - raw) * (L.BonusMult[M] or 1) + L.Base
end

function MF.IntellectExpPercent(pl)
	return L.IntellectPerPoint * Game.GetStatisticEffect(pl:GetIntellect())
end

function events.GetLearningTotalSkill(t)
	local pl = t.Player
	if not pl then return end
	local ok, learn, int = pcall(function() return MF.LearningPercent(pl), MF.IntellectExpPercent(pl) end)
	if not ok then return end
	local items = MF.ItemExpBonus and MF.ItemExpBonus(pl) or 0     -- Neural Crown (MMMWE_AncientArtifacts.lua)
	t.Result = math.max(L.MinPercent, math.floor(learn + int + items))
end
