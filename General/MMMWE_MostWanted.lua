--[[
	MMMWE_MostWanted.lua (23.11.26): "Most Wanted" - the town halls' bounty on a renegade band.

	Besides the monthly bounty on one monster (BountyHunt.lua), every town hall posts a bounty
	on a band of renegades: troops of the usually good side (elves, soldiers, knights, monks,
	priests of the Sun, dwarves, wizards, angels...) who have turned on their own. The band is
	placed on the town's map when the month's bounty is first read; the bounty is paid at the
	town hall once every one of them is dead, and lapses at the end of the month.

	The kind is one the party is ready for (the A, B or C line of a kind by the party's level),
	the band's size grows with the party's level (S.Count).
	State: vars.MMMWE_MostWanted[map] = {Month, Id, Count, Left, Done, Claimed}
	(defined in Global\MMMWE_Vars.lua).
--]]

local MF = Merge.Functions
local Tx = MF.Text
local floor, min, max, random = math.floor, math.min, math.max, math.random

local S = {
	Count = {3, 8},          -- band size: 3, +1 per CountStep of party level, at most 8
	CountStep = 20,
	RewardPerLevel = 75,     -- gold per monster level per renegade
	Group = 41,              -- (BountyHunt.lua uses 39, the siege 200-203)
	Spread = 500,
	LevelSlack = 5,          -- a kind's line may be this many levels above the party
}
MF.MostWantedSettings = S

-- the A line of each kind (B = +1, C = +2)
local KINDS = {
	250,   -- Elven Warrior, Defender, Lancer
	247,   -- Elven Archer, Scout, Ranger
	253,   -- Conscript, Soldier, Fighter
	202,   -- Archer, Bowman, Elite Archer
	403,   -- Swordsman, Guard, Adventurer
	259,   -- Initiate, Champion, Master of the Sword
	304,   -- Monk, Initiate, Master
	217,   -- Acolyte, Cleric, Priest of the Sun
	229,   -- Dwarven Soldier, Lieutenant, Commander
	292,   -- Sorcerer, Wizard, Archmage
	199,   -- Angel, Angel Lord, Archangel
}

local TEXT = {
	Wanted = Tx"Most Wanted: a band of %d renegades (%s) who have turned on their own and now prey on the roads near here. Reward for the whole band: %d gold.",
	Paid = Tx"Most Wanted: the renegade band (%s) is no more. Here is the reward for the band: %d gold.",
	Claimed = Tx"Most Wanted: no renegades are wanted here until next month.",
}

local function store() return vars.MMMWE_MostWanted end

local function partyLevel()
	local sum, n = 0, 0
	for i = 0, Party.count - 1 do sum, n = sum + Party[i].LevelBase, n + 1 end
	return n > 0 and sum / n or 1
end

-- the strongest line of a random kind the party is ready for
local function pickKind()
	local pl = partyLevel()
	local options = {}
	for _, base in ipairs(KINDS) do
		local best
		for t = 0, 2 do
			local txt = Game.MonstersTxt[base + t]
			if txt and txt.Level <= pl + S.LevelSlack then best = base + t end
		end
		if best then options[#options + 1] = best end
	end
	if #options == 0 then options = {KINDS[random(#KINDS)]} end
	return options[random(#options)]
end

local function plural(id) return Game.MonstersTxt[id].Name end

local function spawnBand(e)
	local X, Y, Z = BountyHuntFunctions.NewBHSpawnPoint()
	local n = 0
	for _ = 1, e.Count do
		local ok, m = pcall(SummonMonster, e.Id, X + random(-S.Spread, S.Spread), Y + random(-S.Spread, S.Spread), Z, false)
		if ok and m then
			pcall(m.LoadFramesAndSounds, m)
			m.Group = S.Group
			m.Ally = 0
			m.Hostile = true
			pcall(function() m.ShowAsHostile = true end)
			pcall(function() m.HostileType = 4 end)
			n = n + 1
		end
	end
	e.Count, e.Left = n, n
end

local function reward(e)
	return floor(e.Count * Game.MonstersTxt[e.Id].Level * S.RewardPerLevel / 100 + 0.5) * 100
end

local function mostWanted()
	local s = store()
	if not s then return end
	local e = s[Map.Name]
	if not e or e.Month ~= Game.Month then
		e = {Month = Game.Month, Id = pickKind(), Done = false, Claimed = false}
		local pl = partyLevel()
		e.Count = min(S.Count[2], S.Count[1] + floor(pl / S.CountStep))
		s[Map.Name] = e
		spawnBand(e)
		if e.Count == 0 then e.Done, e.Claimed = true, true end
		return string.format(TEXT.Wanted, e.Count, plural(e.Id), reward(e))
	end
	if e.Claimed then return TEXT.Claimed end
	if e.Done then
		local gold = reward(e)
		BountyHuntFunctions.AddBountyHuntReward(gold)
		e.Claimed = true
		return string.format(TEXT.Paid, plural(e.Id), gold)
	end
	return string.format(TEXT.Wanted, e.Left, plural(e.Id), reward(e))
end

-- the town hall's bounty text, with the Most Wanted after it
local orig = BountyHuntFunctions.SetCurrentHunt
BountyHuntFunctions.SetCurrentHunt = function(...)
	local text = orig(...)
	local ok, extra = pcall(mostWanted)
	if not ok then
		if MF.LogWarning then MF.LogWarning("MostWanted: %s", tostring(extra)) end
		return text
	end
	if not extra then return text end
	return (text and text ~= "" and (text .. "\n\n") or "") .. StrColor(255, 200, 120, extra)
end

function events.MonsterKilled(mon)
	if mon.Group ~= S.Group then return end
	local e = store() and store()[Map.Name]
	if e and not e.Done and e.Month == Game.Month and mon.Id == e.Id then
		e.Left = max(0, (e.Left or 1) - 1)
		if e.Left == 0 then
			e.Done = true
			Game.ShowStatusText(Tx"The renegade band is destroyed! Claim the Most Wanted reward at the town hall.", 4)
		end
	end
end
