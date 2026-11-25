--[[
	MMMWE_PartySpeed.lua - the party walks as fast as its Speed allows (25.11.26)

	The party's walking speed (MM8 0xB20EAC, the party's "walk speed", read by the indoor and
	outdoor movement code at 0x4718F8 / 0x4729CE every frame) follows the average Speed bonus
	(Game.GetStatisticEffect of each character's Speed) of the characters still standing (dead,
	petrified and eradicated ones don't count):
	  speed = the game's own walk speed x (100% + average bonus x S.PerPoint), between S.Min and
	  S.Max: +1% per point, up to +40% (140%) at an average bonus of +40; a negative average slows
	  the party, down to 80%.
	Running and flying go by the same value, so they scale alike.
--]]

local MF = Merge.Functions
local floor, max, min = math.floor, math.max, math.min

local S = {
	PerPoint = 0.01,
	Min = 0.80, Max = 1.40,
	Every = 32,          -- ticks between updates
}
MF.PartySpeedSettings = S

local WALK = 0xB20EAC
local Base               -- the game's own walk speed
local Last

local function averageBonus()
	local sum, n = 0, 0
	local C = const.Condition
	for i = 0, Party.count - 1 do
		local pl = Party[i]
		local c = pl.Conditions
		if c[C.Dead] == 0 and c[C.Stoned] == 0 and c[C.Eradicated] == 0 then
			sum = sum + Game.GetStatisticEffect(pl:GetSpeed())
			n = n + 1
		end
	end
	return n > 0 and sum / n or 0
end

local function mult()
	return max(S.Min, min(S.Max, 1 + averageBonus() * S.PerPoint))
end
MF.PartySpeedMult = mult

local function update()
	local cur = mem.i4[WALK]
	-- the game's value: taken once, and again if anything else sets a new one
	if not Base or (Last and cur ~= Last) then Base = cur end
	if not Base or Base <= 0 then return end
	local v = floor(Base * mult() + 0.5)
	if v ~= cur then mem.i4[WALK] = v end
	Last = v
end

local acc = 0
function events.Tick()
	acc = acc + 1
	if acc < S.Every then return end
	acc = 0
	pcall(update)
end

function events.AfterLoadMap() pcall(update) end
