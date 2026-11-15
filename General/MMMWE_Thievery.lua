--[[
	MMMWE_Thievery.lua — the special bonus "of Thievery" (35) for treasure hunters (15.11.26)

	Before, the bonus did two different things on its two items: the game doubled the Disarm
	Traps skill of Pendragon's wearer, Stealing.lua doubled his Stealing, and Hades (without
	the bonus) gave a flat Disarm Traps +10. Now the bonus is the same everywhere:
	  Disarm Traps   +DISARM skill points (the game's doubling is switched off)
	  Stealing       +STEALING skill points (Stealing.lua asks MF.ThieveryStealing)
	  gold           GOLD_MUL x the gold the party finds (corpses, chests, gold piles) while
	                 a conscious character with the bonus is in the party (once, not per item)
	The items: Pendragon (2030) and Hades (2035), ItemSpcBonuses in Global/ExtraArtifacts.lua.
--]]

local MF = Merge.Functions
local Tx = Merge.Functions.Text
local floor = math.floor

-- the shop text of Stealing.lua (Ctrl + right click on an item), translatable here
MF.StealChanceText = Tx"Chance to steal this item is %d percent."

local BONUS     = 35
local DISARM    = 10
local STEALING  = 5
local GOLD_MUL  = 1.15

-- the game's Disarm Traps total (0x49031C): "jz" over "add esi, esi" (double the skill
-- with the bonus) becomes "jmp"
local DOUBLE_JZ = 0x490358
if mem.u1[DOUBLE_JZ] == 0x74 and mem.u1[DOUBLE_JZ + 2] == 0x03 then
	mem.prot(true)
	mem.u1[DOUBLE_JZ] = 0xEB
	mem.prot(false)
else
	MF.LogWarning("[Thievery] the Disarm Traps doubling wasn't found at 0x%X", DOUBLE_JZ)
end

local function has(pl)
	return pl and pl:HasItemBonus(BONUS) > 0
end

function events.GetSkill(t)
	if t.Skill == const.Skills.DisarmTraps and has(t.Player) then
		local s, m = SplitSkill(t.Result)
		if m > 0 then t.Result = JoinSkill(s + DISARM, m) end
	end
end

-- Stealing.lua: the skill points the bonus adds to the character's Stealing
function MF.ThieveryStealing(pl)
	return has(pl) and STEALING or 0
end

function events.BeforeGotGold(t)
	for _, pl in Party do
		if pl:IsConscious() and has(pl) then
			t.Amount = floor(t.Amount * GOLD_MUL)
			return
		end
	end
end
