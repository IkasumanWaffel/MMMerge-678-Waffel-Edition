--[[
	MMMWE_ForgeStory.lua — the Heavenly Forge after the Dark ending of MM7 (11.11.26)

	Once the Forge is running ("Got the sci-fi part", QBit 633):
	  - Kastore talks about it ("The Forge") and sends the party for Governor Padish's Signet
	    (item 2213): the Forge repeats its old patterns until the Governor's seal orders new
	    ones. His researchers found the way with the Dimensional Scanner: thin places in the
	    world, one of them leading to Enroth years back, to the Tomb of VARN (quest bit 875).
	  - In the Tomb of VARN a guardian droid carries the Signet; it is placed while the quest
	    is open, the Signet not with the party, once per map fill.
	  - Kastore takes a look at the Signet and gives it back (QBit 876): his Quartermaster's
	    Forge Outfitter (house 45, an unused armor shop, its door one of the Pit's hostels) sells Heavenly Forge items,
	    blasters and Energy Shields with upgraded boards, and Ancient devices.
	  - Two Forge tablets lie in Castle Gloaming (MMMWE_AncientLore.lua: 1539, 1540).
	The topics are in Global/MMMWE_ForgeQuests.lua; the texts here, for the language files.
--]]

local MF = Merge.Functions
local Tx = MF.Text

local FORGE_DONE   = 633          -- QBit "Got the sci-fi part" (the end of either path)
local DARK_PATH    = 612          -- QBit "Chose the path of Dark"
local SIGNET_QUEST = 875          -- QBit: looking for the Signet
local SIGNET_DONE  = 876          -- QBit: the Forge has read the Signet
local SIGNET       = 2213
local OUTFITTER    = 45           -- house (a placeholder armor shop)
local DOOR_MAP     = "7d26.blv"   -- its door: a hostel of the Pit (Maps/7d26.lua)
local DOOR_EVENT   = 446
local DOOR_HOUSE   = 1081
local GUARDIAN     = 390          -- Assassin Droid

-- what the Outfitter sells (shares of the stock, %): the Heavenly Forge items that aren't
-- artifacts or relics, blasters and Energy Shields with their boards already upgraded
-- (MMMWE_Blasters.lua), and Ancient devices
local STOCK = {
	{Share = 50, Items = {877, 1677, 890, 1690, 1654, 837, 1637, 1624, 1648, 549}},
	{Share = 20, Items = {866, 867}, Upgrades = {2, 4}},          -- blaster pistol, rifle
	{Share = 15, Items = {968}, Upgrades = {1, 3}},               -- Energy Shield
	{Share = 15, Items = {962, 963, 967, 967, 966}},              -- Toolkit, Lantern, Reflector Shield, Jetpack
}

MF.ForgeStory = {
	FORGE_DONE = FORGE_DONE, DARK_PATH = DARK_PATH, SIGNET_QUEST = SIGNET_QUEST, SIGNET_DONE = SIGNET_DONE,
	SIGNET = SIGNET, OUTFITTER = OUTFITTER,
	DOOR_MAP = DOOR_MAP, DOOR_EVENT = DOOR_EVENT, DOOR_HOUSE = DOOR_HOUSE,

	ForgeTopic = Tx"The Forge",
	ForgeText = Tx"Look at it! The Heavenly Forge, alive again after more than a thousand years. It hums day and night, and every hour it turns out blades and mail the like of which this world hasn't seen since the Silence.\n\nAnd yet it only repeats itself. Fourteen old patterns, nothing more. It will not copy our rifles, our armour, anything new. My researchers say it is waiting for an order it will obey.",

	SignetTopic = Tx"Governor's Signet",
	SignetGive = Tx"The Forge answers to one seal: the signet of Colonial Governor Padish. Without it, it is a very expensive copying machine.\n\nMy researchers have been busy with the Dimensional Scanner you brought me. It found thin places in the world, worn through like old cloth, and one of them leads to Enroth - but to Enroth years before our time. At its far end lies the wreck of a VARN ship, the Tomb of VARN. The Governor's household sailed with the colonists. If the signet survived anywhere, it is there, and something will be guarding it.\n\nBring me that signet, and the Forge will make whatever we ask of it.",
	SignetUndone = Tx"No signet? Then the Forge keeps repeating itself. The Tomb of VARN, in Enroth - the thin places will take you there. Go.",
	SignetDone = Tx"The signet! Hold still while the Forge reads it... There. It has learned our designs, and it knows whose hand it answers to now.\n\nKeep the ring. You have earned it, and the Forge will honour whatever you wear of its making. My Quartermaster has taken over the old hostel here in the Pit and opened the Forge's stores in it. Tell him I sent you.",

	SignetAfter = Tx"Listen to it. New designs, every hour, and every one of them ours. The Silence is over, at least here in Deyja.",

}

---------------------------------------------------------------------------
-- the engine for both stories (the Light side registers in MMMWE_GateStory.lua):
--   MF.AncientQuests[i] = {Map = map file, Quest = QBit open, Done = QBit done, Item = item,
--     Guardian = monster id, Key = mapvars name, Shop = house, Stock = {groups as STOCK}}
---------------------------------------------------------------------------

MF.AncientQuests = MF.AncientQuests or {}
table.insert(MF.AncientQuests, {Name = "Forge", Map = "pyramid.blv", Quest = SIGNET_QUEST,
	Done = SIGNET_DONE, Item = SIGNET, Guardian = GUARDIAN, Key = "MMMWE_SignetGuard",
	Shop = OUTFITTER, Stock = STOCK})

local function partyHas(num)
	for _, pl in Party do
		for i = 1, pl.Items.limit or 138 do
			local it = pl.Items[i]
			if it and it.Number == num then return true end
		end
	end
	return Mouse.Item.Number == num
end

-- the guardian carrying the quest item: at the deepest point, where the monster farthest
-- from the entrance stands (or lies); while the quest is open and the party hasn't the item,
-- once per map fill
local function placeGuardian(q)
	if not Party.QBits[q.Quest] or Party.QBits[q.Done] then return end
	if mapvars[q.Key] or partyHas(q.Item) then return end
	local best, bd = nil, -1
	for i, m in Map.Monsters do
		if m.AIState ~= const.AIState.Removed then
			local dx, dy, dz = m.X - Party.X, m.Y - Party.Y, m.Z - Party.Z
			local d = dx * dx + dy * dy + dz * dz
			if d > bd then best, bd = m, d end
		end
	end
	if not best then return end
	local ok, g = pcall(SummonMonster, q.Guardian, best.X, best.Y, best.Z, false)
	if not ok or not g then return end
	pcall(g.LoadFramesAndSounds, g)
	g.Hostile = true
	g.Item = q.Item
	g.GuardX, g.GuardY, g.GuardZ = g.X, g.Y, g.Z
	mapvars[q.Key] = true
	MF.LogInfo("[%s] the guardian of item %d placed at %d %d %d", q.Name, q.Item, g.X, g.Y, g.Z)
end

function events.AfterLoadMap()
	local name = (Map.Name or ""):lower()
	for _, q in ipairs(MF.AncientQuests) do
		if q.Map == name then placeGuardian(q) end
	end
end

-- the shops' doors: a placeholder hostel of the town opens the shop once the quest is done
-- (called by the map scripts, Maps/7d26.lua and Maps/7d25.lua); s = MF.ForgeStory or
-- MF.GateStory, done = its QBit
local function shopOf(s) return s.OUTFITTER or s.SUPPLY end

function MF.AncientShopDoorHint(s, done)
	if (Map.Name or ""):lower() ~= s.DOOR_MAP then return end
	local h = Party.QBits[done] and shopOf(s) or s.DOOR_HOUSE
	evt.Hint[s.DOOR_EVENT] = Game.Houses[h].Name
end

function MF.AncientShopDoor(s, done)
	Game.MapEvtLines:RemoveEvent(s.DOOR_EVENT)
	evt.Map[s.DOOR_EVENT] = function()
		if Party.QBits[done] then
			evt.EnterHouse{shopOf(s)}
		else
			evt.EnterHouse{s.DOOR_HOUSE}
		end
	end
	MF.AncientShopDoorHint(s, done)
end

-- the shops' stock
local function pick(stock)
	local r = math.random(100)
	for _, g in ipairs(stock) do
		r = r - g.Share
		if r <= 0 then return g end
	end
	return stock[1]
end

function events.GenerateItem(t)
	if t.Handled or Game.CurrentScreen ~= const.Screens.House then return end
	local h = MF.GetCurrentHouse and MF.GetCurrentHouse() or (Game.GetCurrentHouse and Game.GetCurrentHouse())
	local stock
	for _, q in ipairs(MF.AncientQuests) do
		if q.Shop == h then stock = q.Stock end
	end
	if not stock then return end
	local g = pick(stock)
	local it = t.Item
	it:Clear()
	it.Number = g.Items[math.random(#g.Items)]
	it.Identified = true
	if g.Upgrades and MF.BlasterSave and MF.BlasterSpecs then
		-- an upgraded board (blasters 2-4 upgrades, shields 1-3), the cell full
		local st = {Stack = {}, Work = 0, Cell = MF.BlasterSpecs.CellFull}
		for _ = 1, math.random(g.Upgrades[1], g.Upgrades[2]) do
			st.Stack[#st.Stack + 1] = {Spec = math.random(1, 4), Fine = false}
		end
		MF.BlasterSave(it, st)
	end
	t.Handled = true
end
