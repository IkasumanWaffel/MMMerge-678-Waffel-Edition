--[[
	MMMWE_ArchmagusSet.lua (16.11.26): the Vestments of the Archmagus (2255) and the Hat of the
	Archmagus (2258) worn together. The items' own bonuses are in Global\ExtraArtifacts.lua; the set:
	+SET.SchoolSkill to the nine schools of magic, and their spells cost SET.CostMul as much
	(the spellbook shows it too: SpellsExtra.lua runs the SpellCostRecovery handlers for it).
]]

local VESTMENTS, HAT = 2255, 2258
local SET = {SchoolSkill = 3, CostMul = 0.9}
MF = MF or Merge.Functions
MF.ArchmagusSet = SET

local SK = const.Skills
local SCHOOLS = {}
for _, n in ipairs{"Fire", "Air", "Water", "Earth", "Spirit", "Mind", "Body", "Light", "Dark"} do
	if SK[n] then SCHOOLS[SK[n]] = true end
end

local function wears(pl, num, slot)
	local idx = pl[slot]
	if not idx or idx <= 0 then return false end
	local it = pl.Items[idx]
	return it.Number == num and not it.Broken
end

local function hasSet(pl)
	return pl and wears(pl, VESTMENTS, "ItemArmor") and wears(pl, HAT, "ItemHelm")
end
MF.HasArchmagusSet = hasSet

function events.GetSkill(t)
	if SCHOOLS[t.Skill] and hasSet(t.Player) then
		local s, m = SplitSkill(t.Result)
		if m > 0 then t.Result = JoinSkill(s + SET.SchoolSkill, m) end
	end
end

function events.SpellCostRecovery(t)
	if t.Spell < 1 or t.Spell > 99 then return end
	local pl = Party[math.max(0, t.Caster - 35)]   -- as SpellsExtra.lua finds the caster
	if hasSet(pl) then t.Cost = math.floor(t.Cost * SET.CostMul + 0.5) end
end
