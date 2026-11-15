--[[
	MMMWE (15.11.26): the Nightwyrm Staff (2257) and the Lichweave Shroud (2256) worn together.
	The staff's own bonuses are in Global\ExtraArtifacts.lua; this adds the set bonus:
	Dark magic skill +SET.DarkSkill and +SET.SP spell points while both are worn (not broken).
]]

local STAFF, SHROUD = 2257, 2256
local SET = {DarkSkill = 5, SP = 40}
MF = MF or {}
MF.NightwyrmSet = SET

local function wears(pl, num, slot)
	local idx = pl[slot]
	if not idx or idx <= 0 then return false end
	local it = pl.Items[idx]
	return it.Number == num and not it.Broken
end

local function has_set(pl)
	return pl and wears(pl, SHROUD, "ItemArmor")
		and (wears(pl, STAFF, "ItemMainHand") or wears(pl, STAFF, "ItemExtraHand"))
end
MF.HasNightwyrmSet = has_set

function events.GetSkill(t)
	if t.Skill == const.Skills.Dark and has_set(t.Player) then
		local s, m = SplitSkill(t.Result)
		if m > 0 then t.Result = JoinSkill(s + SET.DarkSkill, m) end
	end
end

function events.CalcStatBonusByItems(t)
	if t.Stat == (const.Stats.SP or const.Stats.SpellPoints) and has_set(t.Player) then
		t.Result = t.Result + SET.SP
	end
end
