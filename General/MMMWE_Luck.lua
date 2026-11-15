--[[
	MMMWE_Luck.lua — mild effects of Luck where fortune is expected to help (15.11.26)

	The game uses Luck for the resistance rolls (damage and conditions), for keeping one's
	buffs against a monster's Dispel Magic and in map events; Merge and the Waffel Edition
	for the Light and Dark resistances, being caught when stealing, the Fine blaster
	installs, resisting zombification and the genie lamp. Added here, by the character's Luck
	bonus (the stat's effect, as on the stats screen: +5 at 25 Luck, +10 at 100, ...):

	  critical hits           +CRIT % chance per point (weapons, bows, blasters)
	  dodging                 +DODGE % per point (MF.DodgeChanceMods, MMMWE_Main.lua)
	  gold found              +GOLD % per point of the party's average Luck bonus (the
	                          conscious members; a negative average finds less)
	  chest traps             +DISARM % per point to the disarm chance (MMMWE_Chests.lua)
	  hidden chest items      +FIND % per point to the Perception roll (MMMWE_Chests.lua)
	  stealing                +1 total Stealing per STEAL points (Stealing.lua)
	  Enchant Item            +ENCHANT % success and -FLAW % flaw chance per point of the
	                          caster's (MMMWE_EnchantItem.lua)
	Negative Luck bonuses (low Luck, curses, drains) work the other way.
	MF.LuckBonus(pl) -> the bonus; MF.LuckSettings: the numbers.
--]]

local MF = Merge.Functions
local floor = math.floor

local L = {
	CRIT = 0.2, DODGE = 0.1, GOLD = 0.5, DISARM = 1, FIND = 0.5, STEAL = 2,
	ENCHANT = 0.25, FLAW = 0.5,
}
MF.LuckSettings = L

local function luck(pl)
	if not pl then return 0 end
	local ok, v = pcall(function() return Game.GetStatisticEffect(pl:GetLuck()) end)
	return ok and v or 0
end
MF.LuckBonus = luck

MF.LuckDisarmBonus = function(pl) return L.DISARM * luck(pl) end
MF.LuckFindBonus = function(pl) return L.FIND * luck(pl) end
MF.LuckStealBonus = function(pl) return floor(luck(pl) / L.STEAL) end
MF.LuckEnchantBonus = function(pl)
	local b = luck(pl)
	return L.ENCHANT * b, L.FLAW * b
end

-- gold found: the party's average
function events.BeforeGotGold(t)
	local sum, n = 0, 0
	for _, pl in Party do
		if pl:IsConscious() then sum, n = sum + luck(pl), n + 1 end
	end
	if n > 0 and sum ~= 0 then
		t.Amount = math.max(0, floor(t.Amount * (1 + L.GOLD * sum / n / 100)))
	end
end

-- critical hits and dodging: wrapped once the other scripts have placed theirs
local wrapped = false
function events.LoadMap()
	if wrapped then return end
	wrapped = true
	local getCrit = MF.GetCritStats
	if getCrit then
		MF.GetCritStats = function(pl, melee, ...)
			local c, d, sk = getCrit(pl, melee, ...)
			if c and c > 0 then c = math.max(0, c + L.CRIT * luck(pl)) end
			return c, d, sk
		end
	end
	local blaster = MF.BlasterCritChanceBonus
	MF.BlasterCritChanceBonus = function(pl)
		return (blaster and blaster(pl) or 0) + L.CRIT * luck(pl)
	end
	local dodge = MF.DodgeChanceMods
	if dodge then
		MF.DodgeChanceMods = function(pl)
			return dodge(pl) + L.DODGE * luck(pl)
		end
	end
end
