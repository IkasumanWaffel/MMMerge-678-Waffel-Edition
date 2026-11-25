--[[
	MMMWE_BankLoans.lua - loans and term deposits in the banks (25.11.26)

	A bank clerk (NPC 716, an unused "contest winner" row, renamed) stands in every bank, next
	to the banker's own Deposit / Withdraw (the weekly savings interest, MMMWE_Main.lua).

	Terms depend on the reputation the bank's map sees (MF.GetReputation: the map's in
	Antagarich, the continent's in Jadame and Enroth; lower is better), turned into
	q = -reputation / 25, from -1 (notorious) to +1 (respected), and on the party's best
	Merchant (total skill):
	  Loan: one at a time, for B.LoanMonths months; the limit is B.LoanPerLevel x the party's
	    average level x (1 + q), none at reputation B.NoLoanRep or worse; the interest
	    B.LoanRate - B.LoanRateRep x q - B.LoanMerchant x Merchant a year (at least
	    B.LoanRateMin), charged once for the term; offered as a quarter, half or all of the limit.
	  Term deposits: 1, 3, 6 or 12 months at B.DepositRate[months] x (1 + B.DepositRep x q)
	    + B.DepositMerchant x Merchant a year, simple interest; up to B.MaxDeposits on each
	    continent. At the end of the term the money and the interest go into the bank account
	    (Party.BankGold). Closed early, a deposit gives back only the money put in.
	  Repaying: at any bank; everything (from the gold carried, the rest from the bank
	    account), or whatever gold is carried.
	  Not repaid by the due date:
	    the debt is taken from the bank account, then from the term deposits (their money
	    only, the interest is lost);
	    what is left is overdue: the reputation on the loan's map and continent worsens by
	    B.DefaultRep at once and by B.OverdueRep every further week, and the debt grows by
	    B.PenaltyWeekly every week;
	    debt collectors (a band of thugs, mercenaries or guards the party's match) come after
	    the party on the outdoor maps of the loan's continent, at most once a week on a map.

	State: vars.MMMWE_Bank = {Loan = {Debt, Taken, Due, Cont, Map, Overdue, Weeks},
	                          Deposits = {{Amount, Interest, Due, Cont, Months}, ...}}
--]]

local MF = Merge.Functions
local Tx = MF.Text
local floor, ceil, min, max, random = math.floor, math.ceil, math.min, math.max, math.random

local B = {
	Clerk = 716, ClerkPic = 465,
	LoanMonths = 3,
	LoanPerLevel = 500,
	NoLoanRep = 10,
	LoanRate = 0.30, LoanRateRep = 0.10, LoanMerchant = 0.005, LoanRateMin = 0.10,
	DepositRate = {[1] = 0.12, [3] = 0.15, [6] = 0.18, [12] = 0.22},
	Terms = {1, 3, 6, 12},
	DepositRep = 0.25, DepositMerchant = 0.005,
	DepositAmounts = {1000, 5000, 25000},
	MaxDeposits = 6,
	DefaultRep = 3, OverdueRep = 1, PenaltyWeekly = 0.02,
	Collectors = {Kinds = {538, 256, 193, 553}, Count = {2, 5}, CountStep = 25, Group = 42,
		Slack = 5, Near = {1500, 2500}},
}
MF.BankSettings = B

local function bank()
	vars.MMMWE_Bank = vars.MMMWE_Bank or {Deposits = {}}
	vars.MMMWE_Bank.Deposits = vars.MMMWE_Bank.Deposits or {}
	return vars.MMMWE_Bank
end

local function cont() return Merge.Vars and Merge.Vars.Continent or 1 end

local function partyLevel()
	local sum, n = 0, 0
	for i = 0, Party.count - 1 do sum, n = sum + Party[i].LevelBase, n + 1 end
	return n > 0 and sum / n or 1
end

local function merchant()
	local best = 0
	for i = 0, Party.count - 1 do
		local ok, s = pcall(Party[i].GetMerchantTotalSkill, Party[i])
		if ok and s and s > best then best = s end
	end
	return best
end

local function reputation()
	local ok, r = pcall(MF.GetReputation)
	return ok and r or 0
end

local function q()
	return max(-1, min(1, -reputation() / 25))
end

local function round100(x) return floor(x / 100 + 0.5) * 100 end
local function pct(x) return string.format("%.1f", x * 100) end

local function loanRate()
	return max(B.LoanRateMin, B.LoanRate - B.LoanRateRep * q() - B.LoanMerchant * merchant())
end

local function loanLimit()
	if reputation() >= B.NoLoanRep then return 0 end
	return max(0, round100(B.LoanPerLevel * partyLevel() * (1 + q())))
end

local function depositRate(months)
	return B.DepositRate[months] * (1 + B.DepositRep * q()) + B.DepositMerchant * merchant()
end

local function loanInterest(amount)
	return ceil(amount * loanRate() * B.LoanMonths / 12)
end

local function dateStr(t)
	local d = floor(t / const.Day)
	local y = floor(d / 336)
	local m = floor((d - y*336) / 28)
	local day = d - y*336 - m*28
	return string.format("%d.%d.%d", day + 1, m + 1, y + Game.BaseYear)
end

local function contDeposits(c)
	local list = {}
	for _, d in ipairs(bank().Deposits) do
		if d.Cont == (c or cont()) then list[#list + 1] = d end
	end
	return list
end

local function say(text) Game.ShowStatusText(text, 6) end

---------------------------------------------------------------------------
-- loans
---------------------------------------------------------------------------

local function takeLoan(amount)
	local b = bank()
	if b.Loan then return end
	local debt = amount + loanInterest(amount)
	b.Loan = {Debt = debt, Taken = Game.Time, Due = Game.Time + B.LoanMonths * const.Month,
		Cont = cont(), Map = Merge.Vars and Merge.Vars.Map, Overdue = false, Weeks = 0}
	Party.Gold = Party.Gold + amount
	Message(string.format(Tx"[The clerk counts out %d gold] Sign here. You owe the bank %d gold, due by %s. Repay at any of our banks. A word of advice: the bank always collects.",
		amount, debt, dateStr(b.Loan.Due)))
end

local function repayAll()
	local b = bank()
	local L = b.Loan
	if not L then return end
	local need = L.Debt
	if Party.Gold + Party.BankGold < need then
		Message(string.format(Tx"You owe %d gold, and you have only %d with you and %d in your account.",
			need, Party.Gold, Party.BankGold))
		return
	end
	local fromHand = min(Party.Gold, need)
	Party.Gold = Party.Gold - fromHand
	Party.BankGold = Party.BankGold - (need - fromHand)
	b.Loan = nil
	Message(string.format(Tx"The loan is repaid in full: %d gold. It is a pleasure to do business with you.", need))
end

local function repaySome()
	local b = bank()
	local L = b.Loan
	if not L or Party.Gold <= 0 then return end
	local pay = min(Party.Gold, L.Debt)
	Party.Gold = Party.Gold - pay
	L.Debt = L.Debt - pay
	if L.Debt <= 0 then
		b.Loan = nil
		Message(string.format(Tx"The loan is repaid in full: %d gold. It is a pleasure to do business with you.", pay))
	else
		Message(string.format(Tx"%d gold paid. You still owe %d gold.", pay, L.Debt))
	end
end

---------------------------------------------------------------------------
-- deposits
---------------------------------------------------------------------------

local ChosenTerm = 1

local function openDeposit(amount)
	if amount <= 0 or Party.Gold < amount then return end
	local b = bank()
	if #contDeposits() >= B.MaxDeposits then
		Message(string.format(Tx"You already have %d deposits with us. Wait until one of them ends.", B.MaxDeposits))
		return
	end
	local m = ChosenTerm
	local interest = floor(amount * depositRate(m) * m / 12)
	Party.Gold = Party.Gold - amount
	local d = {Amount = amount, Interest = interest, Due = Game.Time + m * const.Month, Cont = cont(), Months = m}
	table.insert(b.Deposits, d)
	Message(string.format(Tx"%d gold deposited for %d month(s). On %s, %d gold will go into your account.",
		amount, m, dateStr(d.Due), amount + interest))
	ExitQuestBranch(true)
end

local function closeEarly()
	local b = bank()
	local back, n = 0, 0
	for i = #b.Deposits, 1, -1 do
		local d = b.Deposits[i]
		if d.Cont == cont() then
			back, n = back + d.Amount, n + 1
			table.remove(b.Deposits, i)
		end
	end
	if n > 0 then
		Party.Gold = Party.Gold + back
		Message(string.format(Tx"%d deposit(s) closed before their term: %d gold back, without interest.", n, back))
	end
end

---------------------------------------------------------------------------
-- the clerk
---------------------------------------------------------------------------

local function summary()
	local b = bank()
	local lines = {}
	local limit = loanLimit()
	lines[#lines + 1] = string.format(Tx"Our terms for you here: loans up to %d gold for %d months at %s%% a year; term deposits at %s%% (1 month), %s%% (3), %s%% (6), %s%% (12) a year.",
		limit, B.LoanMonths, pct(loanRate()), pct(depositRate(1)), pct(depositRate(3)), pct(depositRate(6)), pct(depositRate(12)))
	if limit == 0 then
		lines[#lines + 1] = Tx"With your reputation hereabouts, the bank lends you nothing."
	end
	local L = b.Loan
	if L then
		lines[#lines + 1] = L.Overdue
			and string.format(Tx"Your loan is OVERDUE: %d gold, and it grows every week.", L.Debt)
			or string.format(Tx"Your loan: %d gold, due by %s.", L.Debt, dateStr(L.Due))
	end
	local ds = contDeposits()
	for _, d in ipairs(ds) do
		lines[#lines + 1] = string.format(Tx"Deposit: %d gold for %d month(s), %d gold on %s.",
			d.Amount, d.Months, d.Amount + d.Interest, dateStr(d.Due))
	end
	return table.concat(lines, "\n")
end

Greeting{
	Name = "MMMWE_Bank_Greet",
	NPC = B.Clerk,
	GetGreeting = function()
		return Tx"Loans and term deposits, at your service. Every bank of ours keeps the same books." .. "\n\n" .. summary()
	end,
}

local function topic(name, branch, slot, t)
	t.Name = "MMMWE_Bank_" .. name
	t.NPC = B.Clerk
	t.Branch = branch
	t.Slot = slot
	t.Quest = false
	return Quest(t)
end

-- main
topic("Loans", "", 0, {Texts = {Topic = Tx"Loans"}, Execute = function() QuestBranchScreen("Loans") end})
topic("Deposits", "", 1, {Texts = {Topic = Tx"Term deposits"}, Execute = function() QuestBranchScreen("Deposits") end})
topic("Accounts", "", 2, {Texts = {Topic = Tx"Our terms and your accounts"}, Execute = function() Message(summary()) end})

-- loans
for k, part in ipairs{0.25, 0.5, 1} do
	local function amount() return round100(loanLimit() * part) end
	topic("Borrow" .. k, "Loans", k - 1, {
		CanShow = function() return not bank().Loan and amount() >= 100 end,
		GetTopic = function() return string.format(Tx"Borrow %d gold", amount()) end,
		Execute = function() takeLoan(amount()) end,
	})
end
topic("NoLoan", "Loans", 3, {
	CanShow = function() return not bank().Loan and loanLimit() < 100 end,
	Texts = {Topic = Tx"Ask for a loan"},
	Execute = function() Message(Tx"I am sorry. With your reputation hereabouts, the bank cannot lend you anything.") end,
})
topic("RepayAll", "Loans", 0, {
	CanShow = function() return bank().Loan ~= nil end,
	GetTopic = function() return string.format(Tx"Repay everything (%d gold)", bank().Loan.Debt) end,
	Execute = repayAll,
})
topic("RepaySome", "Loans", 1, {
	CanShow = function() return bank().Loan ~= nil and Party.Gold > 0 and Party.Gold < bank().Loan.Debt end,
	GetTopic = function() return string.format(Tx"Pay what I carry (%d gold)", Party.Gold) end,
	Execute = repaySome,
})
topic("LoansBack", "Loans", 5, {Texts = {Topic = Tx"Back"}, Execute = function() ExitQuestBranch() end})

-- deposits: the term
for k, m in ipairs(B.Terms) do
	topic("Term" .. m, "Deposits", k - 1, {
		GetTopic = function() return string.format(Tx"%d month(s) at %s%% a year", m, pct(depositRate(m))) end,
		Execute = function() ChosenTerm = m; QuestBranchScreen("DepositAmount") end,
	})
end
topic("CloseEarly", "Deposits", 4, {
	CanShow = function() return #contDeposits() > 0 end,
	Texts = {Topic = Tx"Close my deposits early"},
	Execute = closeEarly,
})
topic("DepositsBack", "Deposits", 5, {Texts = {Topic = Tx"Back"}, Execute = function() ExitQuestBranch() end})

-- deposits: the amount
for k, a in ipairs(B.DepositAmounts) do
	topic("Amount" .. k, "DepositAmount", k - 1, {
		CanShow = function() return Party.Gold >= a end,
		GetTopic = function() return string.format(Tx"Deposit %d gold", a) end,
		Execute = function() openDeposit(a) end,
	})
end
topic("AmountAll", "DepositAmount", 3, {
	CanShow = function() return Party.Gold > 0 end,
	GetTopic = function() return string.format(Tx"Deposit all my gold (%d)", Party.Gold) end,
	Execute = function() openDeposit(Party.Gold) end,
})
topic("AmountBack", "DepositAmount", 5, {Texts = {Topic = Tx"Back"}, Execute = function() ExitQuestBranch() end})

-- the clerk joins the banker: he is put into the bank of the map on every map load (as
-- NPCMercenaries.lua puts the mercenaries into the taverns), and into the bank the party
-- walks into if the map has more than one
local function prepareClerk()
	local npc = Game.NPC[B.Clerk]
	local name = Tx"Bank Clerk"
	if npc.Name ~= name then npc.Name = name end
	npc.Pic = B.ClerkPic
	for i = 0, 5 do npc.Events[i] = 0 end
end

local function mapBank()
	for i, v in Game.HousesExtra do
		if v.Map == Map.MapStatsIndex and Game.Houses[i].Type == const.HouseType.Bank then
			return i
		end
	end
end

local function placeClerk(house)
	if not house then return end
	prepareClerk()
	if Game.NPC[B.Clerk].House ~= house then evt.MoveNPC{B.Clerk, house} end
end

function events.LoadMap()
	local ok, err = pcall(function() placeClerk(mapBank()) end)
	if not ok and MF.LogWarning then MF.LogWarning("MMMWE bank clerk: " .. tostring(err)) end
end

function events.OnEnterShop(t)
	local h = Game.Houses[t.HouseId]
	if h and h.Type == const.HouseType.Bank then pcall(placeClerk, t.HouseId) end
end

---------------------------------------------------------------------------
-- the bank's calendar: deposits ending, loans falling due
---------------------------------------------------------------------------

local function seize(L)
	local took = min(Party.BankGold, L.Debt)
	Party.BankGold = Party.BankGold - took
	L.Debt = L.Debt - took
	local b = bank()
	for i = #b.Deposits, 1, -1 do
		if L.Debt <= 0 then break end
		local d = b.Deposits[i]
		local use = min(d.Amount, L.Debt)
		L.Debt = L.Debt - use
		took = took + use
		if use >= d.Amount then
			table.remove(b.Deposits, i)
		else
			d.Amount, d.Interest = d.Amount - use, 0
		end
	end
	return took
end

local function worsen(L, value)
	pcall(MF.ReputationAdd, value, 3, 2, L.Cont)
	if L.Map then pcall(MF.ReputationAdd, value, 3, 1, L.Map) end
end

local function process()
	local b = bank()
	local now = Game.Time
	for i = #b.Deposits, 1, -1 do
		local d = b.Deposits[i]
		if now >= d.Due then
			Party.BankGold = Party.BankGold + d.Amount + d.Interest
			table.remove(b.Deposits, i)
			say(string.format(Tx"A term deposit has ended: %d gold went into your bank account.", d.Amount + d.Interest))
		end
	end
	local L = b.Loan
	if not L then return end
	if not L.Overdue and now >= L.Due then
		local took = seize(L)
		if L.Debt <= 0 then
			b.Loan = nil
			say(string.format(Tx"Your loan fell due: the bank took %d gold from your savings.", took))
			return
		end
		L.Overdue, L.Weeks, L.Week = true, 0, now
		worsen(L, B.DefaultRep)
		say(string.format(Tx"Your loan is overdue! The bank took %d gold from your savings; %d gold is still owed.", took, L.Debt))
	elseif L.Overdue then
		while now >= (L.Week or now) + const.Week do
			L.Week = (L.Week or now) + const.Week
			L.Weeks = L.Weeks + 1
			L.Debt = ceil(L.Debt * (1 + B.PenaltyWeekly))
			worsen(L, B.OverdueRep)
		end
	end
end

local acc = 0
function events.Tick()
	acc = acc + 1
	if acc < 128 then return end
	acc = 0
	if vars.MMMWE_Bank then pcall(process) end
end

---------------------------------------------------------------------------
-- debt collectors
---------------------------------------------------------------------------

local function pickKind()
	local pl = partyLevel()
	local options = {}
	for _, base in ipairs(B.Collectors.Kinds) do
		local best = base
		for t = 0, 2 do
			local txt = Game.MonstersTxt[base + t]
			if txt and txt.Level <= pl + B.Collectors.Slack then best = base + t end
		end
		options[#options + 1] = best
	end
	return options[random(#options)]
end

local function nearParty()
	local C = B.Collectors
	for _ = 1, 12 do
		local a = random() * 2 * math.pi
		local r = random(C.Near[1], C.Near[2])
		local x, y = Party.X + floor(r * math.cos(a)), Party.Y + floor(r * math.sin(a))
		if x > -30000 and x < 30000 and y > -30000 and y < 30000 then
			local tx, ty = floor(64 + x / 512), floor(64 - y / 512)
			local v = Map.TileMap[ty][tx]
			if v >= 90 then
				local set = min(floor((v - 90) / 36), 3)
				v = Map.Tilesets[set].Offset + (v - 90 - 36*set)
			end
			local tile = Game.CurrentTileBin[v]
			local z = Map.GetGroundLevel(x, y)
			if tile and not tile.Water and math.abs(z - Party.Z) < 800 then return x, y, z end
		end
	end
	return BountyHuntFunctions.NewBHSpawnPoint()
end

local function sendCollectors()
	local L = bank().Loan
	if not (L and L.Overdue and L.Cont == cont()) or not Map.IsOutdoor() then return end
	local week = floor(Game.Time / const.Week)
	if mapvars.MMMWE_Collectors == week then return end
	mapvars.MMMWE_Collectors = week
	local C = B.Collectors
	local id = pickKind()
	local n = min(C.Count[2], C.Count[1] + floor(partyLevel() / C.CountStep))
	local X, Y, Z = nearParty()
	local sent = 0
	for _ = 1, n do
		local ok, m = pcall(SummonMonster, id, X + random(-300, 300), Y + random(-300, 300), Z, false)
		if ok and m then
			pcall(m.LoadFramesAndSounds, m)
			m.Group = C.Group
			m.Ally = 0
			m.Hostile = true
			pcall(function() m.ShowAsHostile = true end)
			pcall(function() m.HostileType = 4 end)
			sent = sent + 1
		end
	end
	if sent > 0 then
		say(string.format(Tx"Debt collectors from the bank are after you: you owe %d gold!", L.Debt))
	end
end

function events.AfterLoadMap()
	local ok, err = pcall(sendCollectors)
	if not ok and MF.LogWarning then MF.LogWarning("MMMWE bank: " .. tostring(err)) end
end
