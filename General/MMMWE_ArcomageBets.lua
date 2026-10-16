--[[
	MMMWE_ArcomageBets.lua — play Arcomage for a stake

	The tavern's Arcomage menu (Rules / Victory Conditions / Play) gets two more lines:
	  Stake: N gold      click to choose the next stake the party can afford
	  Play for a bet     start a match for that stake
	Stakes scale with the tavern: its Val (2DEvents, the same value the first-win prize
	of Val x 100 comes from) times STAKE_STEPS.

	The stake is taken when the match starts, so nothing is lost if the game refuses to
	start it (no deck, etc.):
	  win              STAKE x PAYOUT back (default: the stake doubled)
	  draw             the stake back
	  loss             the stake is lost
	  leaving the game the stake is lost (FORFEIT_ON_LEAVE)
	The first-win prize and awards of a tavern are paid as usual on top.

	The match itself is started through the game's own Play item (house action 405,
	topic 104), so all the usual checks and tavern rules apply.
--]]

local MF = Merge.Functions

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local ENABLED          = true
local STAKE_STEPS      = {10, 25, 50, 100, 200}  -- x tavern Val
local PAYOUT           = 2                        -- x stake paid back on a win
local FORFEIT_ON_LEAVE = true                     -- leaving the match loses the stake
local LINE_HEIGHT      = 20
local GAP              = 6                        -- pixels between Play and the new lines

local PLAY_TOPIC  = 104   -- const.HouseScreens.ArcomagePlay
local HOUSE_ACTION = 405  -- house dialog item action

---------------------------------------------------------------------------

if not ENABLED then return end

local function log(fmt, ...) if MF.LogInfo then MF.LogInfo("[ArcomageBets] " .. fmt, ...) end end

local StakeStep = {}   -- [house] = index into STAKE_STEPS chosen by the player
local Pending          -- {House, Stake, Clock}: Play for a bet was clicked
local Active           -- {House, Stake}: match running for a stake

local function stakeFor(house, step)
	local val = Game.Houses[house] and Game.Houses[house].Val or 0
	return math.max(1, math.floor(val * STAKE_STEPS[step] + 0.5))
end

-- the chosen stake if affordable, otherwise the largest affordable one; nil if none
local function currentStake(house)
	local step = StakeStep[house] or 1
	if stakeFor(house, step) <= Party.Gold then return stakeFor(house, step), step end
	for s = #STAKE_STEPS, 1, -1 do
		if stakeFor(house, s) <= Party.Gold then return stakeFor(house, s), s end
	end
end

-- the Play item of the Arcomage menu on screen now, or nil
local function playItem()
	if Game.CurrentScreen ~= const.Screens.House then return end
	local ok, it = pcall(function()
		local dlg = Game.CurrentNPCDialog
		if not dlg or dlg.LastItemPtr == 0 then return end
		local it = structs.Button:new(dlg.LastItemPtr)
		if it.ActionType == HOUSE_ACTION and it.ActionParam == PLAY_TOPIC then return it end
	end)
	return ok and it or nil
end

---------------------------------------------------------------------------
-- menu lines
---------------------------------------------------------------------------

function events.GameInitialized2()
	if not CustomUI then return end

	local function place(self, line)
		local it = playItem()
		if not it then return false end
		self.X, self.Wt = it.Left, it.Width
		self.Y, self.Ht = it.Top + it.Height + GAP + (line - 1) * LINE_HEIGHT, LINE_HEIGHT
		return true
	end

	CustomUI.CreateText{
		Text = "Stake", Font = Game.Arrus_fnt,
		Width = 140, Height = LINE_HEIGHT,
		ColorStd = RGB(255, 255, 255),
		Layer = 0, Screen = const.Screens.House,
		Condition = function(self)
			if not place(self, 1) then return false end
			local house = Game.GetCurrentHouse()
			local stake = currentStake(house)
			self.Text = stake and string.format("Stake: %d gold", stake) or "Stake: not enough gold"
			return true
		end,
		Action = function(self)
			local house = Game.GetCurrentHouse()
			local _, step = currentStake(house)
			if not step then return end
			-- next affordable step, wrapping round
			for i = 1, #STAKE_STEPS do
				local s = (step + i - 1) % #STAKE_STEPS + 1
				if stakeFor(house, s) <= Party.Gold then StakeStep[house] = s break end
			end
		end,
	}

	CustomUI.CreateText{
		Text = "Play for a bet", Font = Game.Arrus_fnt,
		Width = 140, Height = LINE_HEIGHT,
		ColorStd = RGB(255, 255, 255),
		Layer = 0, Screen = const.Screens.House,
		Condition = function(self)
			return place(self, 2) and currentStake(Game.GetCurrentHouse()) ~= nil
		end,
		Action = function(self)
			local house = Game.GetCurrentHouse()
			local stake = currentStake(house)
			if not stake then return end
			Pending = {House = house, Stake = stake, Clock = os.clock()}
			Game.Actions.Add(HOUSE_ACTION, PLAY_TOPIC)   -- the same as clicking Play
		end,
	}
end

---------------------------------------------------------------------------
-- the bet
---------------------------------------------------------------------------

function events.ArcomageSetup(t, house)
	local p = Pending
	Pending = nil
	Active = nil
	if not p or p.House ~= house or os.clock() - p.Clock > 5 then return end
	if Party.Gold < p.Stake then
		Game.ShowStatusText("Not enough gold for the stake")
		return
	end
	Party.Gold = Party.Gold - p.Stake
	Active = {House = house, Stake = p.Stake}
	Game.ShowStatusText(string.format("You bet %d gold", p.Stake))
	log("house %d: stake %d", house, p.Stake)
end

function events.ArcomageMatchEnd(t)
	local a = Active
	Active = nil
	if not a then return end
	-- result: -1 left the match, 0 draw, 1 won, 2 lost
	if t.result == 1 then
		local pay = math.floor(a.Stake * PAYOUT + 0.5)
		Party.Gold = Party.Gold + pay
		Game.ShowStatusText(string.format("You win the bet: +%d gold!", pay - a.Stake))
	elseif t.result == 0 or (t.result == -1 and not FORFEIT_ON_LEAVE) then
		Party.Gold = Party.Gold + a.Stake
		Game.ShowStatusText(string.format("The stake of %d gold is returned", a.Stake))
	else
		Game.ShowStatusText(string.format("You lose the bet of %d gold", a.Stake))
	end
	log("house %d: stake %d, result %s", a.House, a.Stake, tostring(t.result))
end
