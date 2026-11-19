--[[
	MMMWE_BlackMarket.lua — fences who buy stolen goods (19.11.26)

	The shops won't buy an item marked as stolen (the game's own rule, 0x4BB65A). One fence
	on each continent buys them, through a topic "Sell stolen goods":
	  Antagarich  William Lasker, the Master Thief of Harmondale
	  Enroth      Hejaz Mawsil, who takes new members to the thieves' guild of New Sorpigal
	  Jadame      the Dread Pirate Stanley in the Pirate's Rest tavern of Regna
	The topic offers a price for the stolen things in the active character's backpack
	(equipped items aren't touched); a second click within OFFER_MINUTES game minutes sells them.

	The price of an item: what a shop of the fence's house would give for it were it honest
	(Economy's Sell price: the item value, the house's price level and the seller's
	Merchant), times BASE_SHARE, plus STEAL_PER_POINT for each point of the seller's Stealing
	(the skill and its mastery together, as for stealing: GetStealingTotalSkill), at most
	MAX_SHARE of the honest price.
--]]

local MF = Merge.Functions
local Tx, TxN = Merge.Functions.Text, Merge.Functions.TextN

local BASE_SHARE      = 0.5
local STEAL_PER_POINT = 0.005
local MAX_SHARE       = 0.8
local OFFER_MINUTES   = 30       -- game minutes an offer stands

-- NPC = the fence, Slot = a free topic slot, House = the house the price level comes from
local FENCES = {
	{NPC = 354,  Slot = 1, House = 1162, Where = "Antagarich"},   -- William Lasker
	{NPC = 1073, Slot = 1, House = 191,  Where = "Enroth"},       -- Hejaz Mawsil
	{NPC = 108,  Slot = 1, House = 236,  Where = "Jadame"},       -- Dread Pirate Stanley
}
MF.BlackMarkets = FENCES

local function currentPlayer()
	local i = Party.CurrentPlayer
	if i and i >= 0 and i < Party.Count then return Party[i], i end
end

local function isEquipped(pl, k)
	for e = 0, 15 do
		if pl.EquippedItems[e] == k then return true end
	end
	return false
end

-- the merchant skill the shops use (Economy: the call at 0x4B66D2)
local function merchantSkill(pl)
	local ok, v = pcall(function()
		local at = 0x4B66D2
		local target = at + 5 + mem.i4[at + 1]
		return mem.call(target, 1, pl["?ptr"])
	end)
	return ok and v or 0
end

local function honestPrice(pl, it, house)
	local value = it:GetValue()
	local mult = Game.Houses[house] and Game.Houses[house].Val or 1
	if mult <= 0 then mult = 1 end
	if Economy and Economy.Price then
		return Economy.Price("Sell", {Value = value, Mult = mult, Player = pl,
			MerchantSkill = merchantSkill(pl)})
	end
	return math.max(1, math.floor(value / (mult + 2)))
end

local function share(pl)
	local steal = GetStealingTotalSkill and GetStealingTotalSkill(pl) or 0
	return math.min(MAX_SHARE, BASE_SHARE + STEAL_PER_POINT * math.max(0, steal))
end

-- the stolen things in the backpack and what the fence pays for them
local function appraise(pl, house)
	local list, total = {}, 0
	local k = share(pl)
	for i = 1, 138 do
		local it = pl.Items[i]
		if it.Number > 0 and it.Stolen and not isEquipped(pl, i) then
			local p = math.max(1, math.floor(honestPrice(pl, it, house) * k))
			list[#list + 1] = {Index = i, Price = p}
			total = total + p
		end
	end
	return list, total, k
end

local function removeItem(pl, i)
	for c = 0, 125 do
		if pl.Inventory[c] == i then
			for c2 = 0, 125 do
				if pl.Inventory[c2] == -(1 + c) then pl.Inventory[c2] = 0 end
			end
			pl.Inventory[c] = 0
		end
	end
	pl.Items[i].Number = 0
end

local Offer   -- {Player index, Fence NPC, Total, Count, Time}

local function fence(f)
	local pl, pi = currentPlayer()
	if not pl then return end
	local list, total, k = appraise(pl, f.House)
	if #list == 0 then
		Offer = nil
		Message(string.format(Tx"You carry nothing I'd call merchandise, %s.", pl.Name))
		return
	end
	local o = Offer
	if o and o.Player == pi and o.NPC == f.NPC and o.Total == total and o.Count == #list
			and Game.Time - o.Time < const.Minute * OFFER_MINUTES then
		Offer = nil
		for _, e in ipairs(list) do removeItem(pl, e.Index) end
		Party.Gold = Party.Gold + total
		Game.PlaySound(14)   -- coins
		Message(string.format(TxN(#list, "No questions asked: %d gold for %d item, %s.",
			"No questions asked: %d gold for %d items, %s."), total, #list, pl.Name))
		return
	end
	Offer = {Player = pi, NPC = f.NPC, Total = total, Count = #list, Time = Game.Time}
	Message(string.format(TxN(#list,
		"%d gold for the %d thing you'd rather not show a merchant, %s (%d%% of an honest price). Ask again and the deal is done.",
		"%d gold for the %d things you'd rather not show a merchant, %s (%d%% of an honest price). Ask again and the deal is done."),
		total, #list, pl.Name, math.floor(k * 100 + 0.5)))
end

for _, f in ipairs(FENCES) do
	NPCTopic{
		Name = string.format("MMMWE_BlackMarket_%d", f.NPC),
		NPC = f.NPC,
		Slot = f.Slot,
		Topic = Tx"Sell stolen goods",
		NeverGiven = true,
		NeverDone = true,
		Done = function() fence(f) end,
	}
end
