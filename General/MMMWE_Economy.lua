--[[
	MMMWE_Economy.lua — full control over shop and temple prices (MM8 / MMMerge Waffel Edition)

	Replaces the mid-function patches that used to live in MMMWE_Main.lua
	("Debalance shop prices" block and ModTempleHealCost). Every price function
	is hooked at its entry and computed here in Lua, so the formulas below are
	the single source of truth. With the default Settings the prices are the
	same as the old Waffel patches produced.

	Hooked functions (MM8):
	  0x4B660B  temple_heal_price      thiscall(player, float baseHealCost)
	  0x4B6691  sell_item_price        thiscall(player, int value, float mult)
	  0x4B66D1  buy_item_price         thiscall(player, int value, float mult)
	  0x4B6708  identify_item_price_0  thiscall(player, float mult)
	  0x4B672E  repair_item_price_0    thiscall(player, int value, float mult)
	  0x4B675A  base_sell_price        stdcall(int value, float mult)
	  0x4B677A  base_buy_item_price    stdcall(int value, float mult)
	  0x4B6792  identify_item_price    stdcall(float mult)
	  0x4B67AC  repair_item_price      stdcall(int value, float mult)

	Kinds: "Heal", "Sell", "Buy", "Identify", "Repair",
	       "BaseSell", "BaseBuy", "BaseIdentify", "BaseRepair",
	       "DarkHeal" (not a game function: the reanimation price charged by
	                   dark temples in ZombiePlayers.lua, via Economy.Price)
	(Base* are the merchant-skill-free prices shown by merchant_reply_2.)

	Ways to control a price, applied in this order:
	  1. Economy.Settings.*            — tune the default formulas (below)
	  2. Economy.Formula[kind] = function(t, F) return price end
	                                    — replace a formula; F holds the default
	                                      formulas, e.g. F.Buy(t)
	  3. Economy.Settings.Mul[kind]    — flat multiplier on top
	  4. events.CalcEconomyPrice(t)    — any script may change t.Result
	  5. Economy.Settings.MinPrice     — final clamp (vanilla: 1)

	Fields of t:
	  Kind, Value (item value; nil for Heal/Identify kinds), Mult (shop price
	  category multiplier; base heal cost for Heal), Result,
	  Player, PlayerIndex, PlayerPtr, MerchantSkill   (nil for Base* kinds),
	  NonItemCosts(cost)  — native merchant adjustment used by identify/repair
	                        (player kinds only),
	  CallOriginal()      — runs the untouched game function (vanilla price).
	  Heal also fills: Condition (main), SeverityMul, Days.

	Settings can be changed at any time from other scripts or the console, e.g.
	  Economy.Settings.Buy.PriceMul = 3
	  Economy.Settings.Mul.Heal = 0.5
--]]

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

Economy = Economy or {}
local E = Economy

---------------------------------------------------------------------------
-- settings (defaults reproduce the previous Waffel Edition economy)
---------------------------------------------------------------------------

E.Settings = E.Settings or {
	Enabled  = true,
	MinPrice = 1,

	Buy = {
		PriceMul      = 2.0,   -- overall buy price mult (vanilla 1.0)
		SkillEffect   = 0.5,   -- % discount per point of merchant skill (vanilla 1.0)
		MaxDiscount   = 100,   -- cap on the merchant discount, %
		NotBelowValue = true,  -- never cheaper than item value (vanilla true)
	},

	Sell = {
		BaseMul       = 0.3,   -- base sell price = value / (mult + MultAdd) * BaseMul (vanilla 1.0)
		MultAdd       = 0.0,   -- added to shop mult (vanilla 2.0)
		SkillEffect   = 0.5,   -- % of item value added per point of merchant skill (vanilla 1.0)
		NotAboveValue = true,  -- never more than item value (vanilla true)
	},

	Identify = {
		Mul = 100.0,           -- price = shop mult * Mul (vanilla 50.0)
	},

	Repair = {
		Divisor = 6.0,         -- price = value / (Divisor - shop mult) * PriceMul (vanilla 6.0)
		PriceMul = 2.0,        -- (vanilla 1.0)
	},

	Heal = {
		-- cost per active condition, summed (vanilla: flat 1 for any of 0..13)
		CondCost = {
			[0] = 2,  [1] = 1,  [2] = 1,  [3] = 1,
			[4] = 1,  [5] = 2,  [6] = 1,  [7] = 1,
			[8] = 2,  [9] = 2,  [10] = 3, [11] = 3,
			[12] = 4, [13] = 1,
		},
		DeadStonedMul = 5,     -- conditions 14 (Dead), 15 (Stoned)
		EradicatedMul = 10,    -- condition 16
		-- Zombie (17) cure outside dark temples (ZombiePlayers.lua rule):
		-- used when the main condition is Zombie, or the character is a zombie
		-- and the main condition ranks below Eradicated. nil = no special rule
		ZombieMul     = 10,
		UseDays       = true,  -- multiply by days in the condition (vanilla true)
	},

	-- Merchant discount applied to training and skill learning
	-- (hook at 0x4B0499; 0.5 halves the discount; vanilla 1.0)
	TrainingSkillEffect = 0.5,

	-- flat multipliers applied after the formulas
	Mul = {
		Heal = 1, Sell = 1, Buy = 1, Identify = 1, Repair = 1,
		BaseSell = 1, BaseBuy = 1, BaseIdentify = 1, BaseRepair = 1,
		DarkHeal = 1,
	},
}
E.Formula = E.Formula or {}
local S = E.Settings
S.Mul.DarkHeal = S.Mul.DarkHeal or 1

-- set by ZombiePlayers.lua on entering a house: dark temples keep normal
-- heal pricing for zombies
E.IsDarkTemple = E.IsDarkTemple or false
-- also set by ZombiePlayers.lua: E.CurrentHouse (house id) and
-- E.DarkHealBaseCost(Player, HouseId) -> base reanimation cost or nil

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------

-- C-style truncation toward zero (__ftol, idiv)
local function trunc(x)
	return x >= 0 and floor(x) or ceil(x)
end
E.trunc = trunc

-- hookfunction passes stack args as raw dwords; reinterpret one as a float
local fbuf = mem.StaticAlloc(4)
local function ToFloat(raw)
	mem.u4[fbuf] = raw % 4294967296
	return mem.r4[fbuf]
end

-- target of a "call rel32" instruction located at 'at'
local function CallTarget(at)
	return at + 5 + mem.i4[at + 1]
end

local N = {
	GetMerchantSkill = CallTarget(0x4B66D2), -- thiscall(player), 0x49028F
	GetMainCondition = CallTarget(0x4B6614), -- thiscall(player)
	ConditionDays    = CallTarget(0x4B663E), -- thiscall(player, cond)
	NonItemCosts     = CallTarget(0x4B671D), -- thiscall(player, cost)
}
E.Native = N

-- addresses of the float constants in .rdata (read from the instructions using them)
local IdentifyMulPtr = mem.u4[0x4B670F]   -- 0x4E89F0
local RepairMulPtr   = mem.u4[0x4B6735]   -- 0x4E8638

-- keep the native constants in sync with Settings, so CallOriginal and any
-- other native code reading them agree with the Lua formulas
function E.SyncNativeConstants()
	mem.IgnoreProtection(true)
	mem.r4[IdentifyMulPtr] = S.Identify.Mul
	mem.r4[RepairMulPtr]   = S.Repair.Divisor
	mem.IgnoreProtection(false)
end
E.SyncNativeConstants()

local function PlayerFromPtr(p)
	local arr = Party.PlayersArray
	local i = (p - arr["?ptr"]) / arr[0]["?size"]
	if i % 1 ~= 0 or i < 0 or i > arr.high then
		return nil
	end
	return arr[i], i
end

---------------------------------------------------------------------------
-- default formulas
---------------------------------------------------------------------------

local F = {}
E.Default = F

local function BuyBase(t)
	return trunc(t.Value * t.Mult) * S.Buy.PriceMul
end

function F.BaseBuy(t)
	return trunc(BuyBase(t))
end

function F.Buy(t)
	local disc = min(trunc(t.MerchantSkill * S.Buy.SkillEffect), S.Buy.MaxDiscount)
	local p = trunc(BuyBase(t) * (100 - disc) / 100)
	if S.Buy.NotBelowValue then
		p = max(p, t.Value)
	end
	return p
end

local function SellBase(t)
	return trunc(trunc(t.Value / (t.Mult + S.Sell.MultAdd)) * S.Sell.BaseMul)
end

function F.BaseSell(t)
	return SellBase(t)
end

function F.Sell(t)
	local bonus = trunc(trunc(t.MerchantSkill * t.Value / 100) * S.Sell.SkillEffect)
	local p = bonus + SellBase(t)
	if S.Sell.NotAboveValue then
		p = min(p, t.Value)
	end
	return p
end

function F.BaseIdentify(t)
	return trunc(t.Mult * S.Identify.Mul)
end

function F.Identify(t)
	return t.NonItemCosts(F.BaseIdentify(t))
end

function F.BaseRepair(t)
	return trunc(trunc(t.Value / (S.Repair.Divisor - t.Mult)) * S.Repair.PriceMul)
end

function F.Repair(t)
	return t.NonItemCosts(F.BaseRepair(t))
end

function F.Heal(t)
	local H = S.Heal
	local ptr = t.PlayerPtr
	local cond = mem.call(N.GetMainCondition, 1, ptr)
	local zombie = t.Player and t.Player.Conditions[17] > 0
	local mul, days
	if H.ZombieMul and not E.IsDarkTemple and (cond == 17 or zombie and cond < 16) then
		-- ZombiePlayers.lua: curing a zombie costs as much as eradication;
		-- days are taken from the main condition, as in its asm patch
		mul, days = H.ZombieMul, mem.call(N.ConditionDays, 1, ptr, cond)
	elseif cond == 14 or cond == 15 then
		mul, days = H.DeadStonedMul, mem.call(N.ConditionDays, 1, ptr, cond)
	elseif cond == 16 then
		mul, days = H.EradicatedMul, mem.call(N.ConditionDays, 1, ptr, cond)
	else
		mul, days = 0, 0
		local conds = t.Player and t.Player.Conditions
		for i = 0, 13 do
			if conds and conds[i] > 0 then
				mul = mul + (H.CondCost[i] or 1)
			end
			days = max(days, mem.call(N.ConditionDays, 1, ptr, i))
		end
		mul = max(mul, 1)
		if days == 0 then days = 1 end
	end
	if not H.UseDays then
		days = 1
	end
	t.Condition, t.SeverityMul, t.Days = cond, mul, days
	return trunc(days * mul * t.Mult)
end

-- dark temple reanimation / cure: the base cost is decided by ZombiePlayers.lua
function F.DarkHeal(t)
	return t.BaseCost
end

---------------------------------------------------------------------------
-- price pipeline: Formula -> Mul -> CalcEconomyPrice event -> MinPrice
-- Economy.Price(kind, t) can also be called by other scripts for prices
-- they charge themselves, so those go through the same controls.
---------------------------------------------------------------------------

function E.Price(kind, t)
	-- In a dark temple the heal topic must show what ZombiePlayers.lua charges.
	-- When it charges its own reanimation price, price the topic the same way;
	-- otherwise (cost nil) the game heals normally and the Heal formula applies.
	if kind == "Heal" and E.IsDarkTemple and E.DarkHealBaseCost
			and t.Player and E.CurrentHouse then
		local cost = E.DarkHealBaseCost(t.Player, E.CurrentHouse)
		if cost then
			t.BaseCost = cost
			t.HouseId = E.CurrentHouse
			t.Mult = Game.Houses[E.CurrentHouse].Val
			return E.Price("DarkHeal", t)
		end
	end

	t.Kind = kind
	local f = E.Formula[kind] or F[kind]
	t.Result = f(t, F) * (S.Mul[kind] or 1)
	events.call("CalcEconomyPrice", t)
	return max(S.MinPrice, trunc(t.Result))
end

---------------------------------------------------------------------------
-- hooks
---------------------------------------------------------------------------

local Hooks = {
	-- address,  kind,          player in ecx, int value arg
	{0x4B660B, "Heal",         true,  false},
	{0x4B6691, "Sell",         true,  true },
	{0x4B66D1, "Buy",          true,  true },
	{0x4B6708, "Identify",     true,  false},
	{0x4B672E, "Repair",       true,  true },
	{0x4B675A, "BaseSell",     false, true },
	{0x4B677A, "BaseBuy",      false, true },
	{0x4B6792, "BaseIdentify", false, false},
	{0x4B67AC, "BaseRepair",   false, true },
}

for _, h in ipairs(Hooks) do
	local addr, kind, hasPlayer, hasValue = h[1], h[2], h[3], h[4]

	mem.hookfunction(addr, hasPlayer and 1 or 0, hasValue and 2 or 1, function(d, def, ...)
		if not S.Enabled then
			return def(...)
		end

		local a = {...}
		local n = select("#", ...)
		local i = 1
		local t = {Kind = kind}

		t.CallOriginal = function()
			return def(unpack(a, 1, n))
		end

		if hasPlayer then
			local ptr = a[1]
			t.PlayerPtr = ptr
			t.Player, t.PlayerIndex = PlayerFromPtr(ptr)
			t.MerchantSkill = mem.call(N.GetMerchantSkill, 1, ptr)
			t.NonItemCosts = function(cost)
				return mem.call(N.NonItemCosts, 1, ptr, trunc(cost))
			end
			i = 2
		end
		if hasValue then
			t.Value = a[i]
			i = i + 1
		end
		t.Mult = ToFloat(a[i])

		return E.Price(kind, t)
	end)
end

-- merchant discount on training / skill learning (inside non_item_costs)
mem.autohook(0x4B0499, function(d)
	d.ecx = trunc(d.ecx * S.TrainingSkillEffect)
end)

---------------------------------------------------------------------------
-- examples (copy into your own script)
---------------------------------------------------------------------------

-- Cap merchant discount at 30% and allow buying below item value:
-- Economy.Settings.Buy.MaxDiscount = 30
-- Economy.Settings.Buy.NotBelowValue = false

-- Selling never yields more than 60% of item value:
-- Economy.Formula.Sell = function(t, F)
-- 	return math.min(F.Sell(t), t.Value * 0.6)
-- end

-- Temple healing doesn't grow with days spent in the condition:
-- Economy.Settings.Heal.UseDays = false

-- 50% inflation on everything sold by shops:
-- function events.CalcEconomyPrice(t)
-- 	if t.Kind == "Buy" or t.Kind == "BaseBuy" then
-- 		t.Result = t.Result * 1.5
-- 	end
-- end
