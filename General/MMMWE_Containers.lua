--[[
	MMMWE_Containers.lua — boxes that hold items (09.11.26)

	  Bottle Box (193)            potions and potion bottles, full or empty
	  Jewelry Box (2229)          rings, amulets and gemstones
	  Ancient Storage Box (2230)  anything; it doesn't open while enemies are near
	                              (found in the facilities of the Ancients)
	No box (nor an apothecary satchel or an ore bag) goes into a box.

	Pick a box up and click it on a character's portrait: the box goes back into the backpack
	and opens as a chest. Its contents are kept with the saved game (vars.MMMWE_Boxes), by
	the box's number in its Charges (from FIRST_ID up). While a box is open, its items are
	in a spare chest of the map (the one after the map's own chests; on a map with all 20
	chest records, its last chest is lent and restored byte by byte); when the chest screen
	closes they are taken back out and the chest is cleared or restored. A wrong item put into a box goes back to the mouse at once.
	Bottle boxes from before keep their empty bottles: the count in Charges (0..12) turns
	into Potion Bottles in the box the first time it opens.

	MF.BoxCount(charges) -> the number of items in a box (the item descriptions).
--]]

local MF = Merge.Functions
local Tx, TxN = Merge.Functions.Text, Merge.Functions.TextN
local u1, i2, i4 = mem.u1, mem.i2, mem.i4

local FIRST_ID = 1000
local CHEST_COUNT = 0x61C528           -- Map.Chests count (MM8)
local MAX_CHESTS = 20
local CHEST_SCREEN = const.Screens.Chest
local CHEST_INV_SCREEN = const.Screens.InventoryInChest or 15   -- a character's backpack beside the chest
local ESC_WAIT = 30                    -- ticks to wait for the character screen to close
local EMPTY_BOTTLE = 220

local BOTTLE = const.ItemType.Potion - 1
local RING, AMULET = const.ItemType.Ring - 1, const.ItemType.Amulet - 1
local GemType                           -- the gems' EquipStat (Zircon's), when the items are loaded

-- picture: the chest picture the box opens with (Chest.txt)
local BOXES = {
	[193]  = {Name = Tx"Bottle Box", Picture = 2,
		Allow = function(t) return t.EquipStat == BOTTLE end, Only = Tx"Only potions go into the bottle box"},
	[2229] = {Name = Tx"Jewelry Box", Picture = 5,
		Allow = function(t) return t.EquipStat == RING or t.EquipStat == AMULET or t.EquipStat == GemType end,
		Only = Tx"Only rings, amulets and gemstones go into the jewelry box"},
	[2230] = {Name = Tx"Ancient Storage Box", Picture = 7, NotNearEnemies = true,
		Allow = function() return true end},
}
MF.Boxes = BOXES

-- containers of any kind: no box takes them
local CONTAINERS = {[191] = true, [192] = true}
for n = 969, 987 do CONTAINERS[n] = true end
for n in pairs(BOXES) do CONTAINERS[n] = true end

-- the Ancient facilities: map names (MapStats) a box is put into a chest of, once a game
local FACILITIES = {"control center", "hive", "lincoln"}

---------------------------------------------------------------------------

local function store()
	vars.MMMWE_Boxes = vars.MMMWE_Boxes or {Next = FIRST_ID}
	return vars.MMMWE_Boxes
end

local function log(fmt, ...) if MF.LogInfo then MF.LogInfo("[Boxes] " .. fmt, ...) end end

function MF.BoxCount(charges)
	local b = vars and vars.MMMWE_Boxes and vars.MMMWE_Boxes[charges]
	if not b then return 0 end
	local n = 0
	for _ in pairs(b.Items) do n = n + 1 end
	return n
end

local Open        -- {Chest = index, Id = box id, Box = BOXES entry}
local Pending     -- {Player, Number, Charges} to open on the next tick
local Repaint = 0 -- ticks left to redraw the whole interface after a box closes

local ITEM_SIZE = 0x24                  -- structs.Item (MM8)
local function chestItemSize() return ITEM_SIZE end
local GRID_W, GRID_H = 14, 10           -- the chest pictures' grid (Chest.txt)

-- cells an item takes (the game's rule: (pixels - 14) / 32 + 1)
local function cellsOf(num)
	local w, h = 1, 1
	pcall(function()
		local idx = Game.IconsLod:LoadBitmap(Game.ItemsTxt[num].Picture)
		local b = Game.IconsLod.Bitmaps[idx]
		w = math.floor((math.max(b.Width, 14) - 14) / 32) + 1
		h = math.floor((math.max(b.Height, 14) - 14) / 32) + 1
	end)
	return w, h
end

-- puts item record k (number num) on the first free place of a record's grid
local function place(rec, k, num)
	local w, h = cellsOf(num)
	for row = 0, GRID_H - h do
		for col = 0, GRID_W - w do
			local free = true
			for y = row, row + h - 1 do
				for x = col, col + w - 1 do
					if (rec.Grid[y * GRID_W + x + 1] or 0) ~= 0 then free = false end
				end
			end
			if free then
				local main = row * GRID_W + col
				for y = row, row + h - 1 do
					for x = col, col + w - 1 do rec.Grid[y * GRID_W + x + 1] = -(1 + main) end
				end
				rec.Grid[main + 1] = k
				return true
			end
		end
	end
end

-- the box's contents into the spare chest
local function fill(chest, rec)
	for k = 1, 140 do chest.Items[k]:Clear() end
	for c = 0, 139 do chest.Inventory[c] = 0 end
	if not rec then return end
	local size = chestItemSize()
	for k, data in pairs(rec.Items) do
		mem.copy(chest.Items[k]["?ptr"], data, math.min(#data, size))
	end
	local inv = rec.Grid
	for c = 0, 139 do
		chest.Inventory[c] = inv[c + 1] or 0
	end
end

-- the spare chest's contents into the box's record
local function take(chest)
	local rec = {Items = {}, Grid = {}}
	local size = chestItemSize()
	for k = 1, 140 do
		if chest.Items[k].Number ~= 0 then
			rec.Items[k] = mem.string(chest.Items[k]["?ptr"], size, true)
		end
	end
	for c = 0, 139 do rec.Grid[c + 1] = chest.Inventory[c] end
	return rec
end

local function close()
	if not Open then return end
	local ok, err = pcall(function()
		if Open.Chest < i4[CHEST_COUNT] then
			local chest = Map.Chests[Open.Chest]
			store()[Open.Id] = take(chest)
			if Open.Saved then
				-- a chest of the map lent for the box: as it was
				mem.copy(chest["?ptr"], Open.Saved, #Open.Saved)
			else
				fill(chest, nil)
				chest.Bits = 0
			end
			if Open.Added then i4[CHEST_COUNT] = Open.Chest end
		end
	end)
	if not ok then MF.LogWarning("[Boxes] closing: %s", tostring(err)) end
	log("box %d closed (%d items)", Open.Id, MF.BoxCount(Open.Id))
	Open = nil
	-- the chest was opened by a script, so the game doesn't repaint the panels it covered
	-- (nor those of the character screen before it) on its own: a few full redraws
	Repaint = 5
	Game.NeedRedraw = true
end
MF.CloseBox = close

-- the id of a box item, made on its first opening (an old bottle box: its bottles go in)
local function boxId(item)
	if item.Charges >= FIRST_ID then return item.Charges end
	local s = store()
	local id = s.Next
	s.Next = id + 1
	local rec = {Items = {}, Grid = {}}
	if item.Number == 193 and item.Charges > 0 then
		-- the empty bottles of the old box: one cell each, left to right
		for k = 1, math.min(item.Charges, 12) do
			rec.Items[k] = string.char(EMPTY_BOTTLE % 256, math.floor(EMPTY_BOTTLE / 256), 0, 0)
				.. string.rep("\0", 16) .. string.char(1, 0, 0, 0) .. string.rep("\0", ITEM_SIZE - 24)
			place(rec, k, EMPTY_BOTTLE)
		end
	end
	s[id] = rec
	item.Charges = id
	return id
end

local function openNow(p)
	local box = BOXES[p.Number]
	if box.NotNearEnemies and (Party.EnemyDetectorYellow or Party.EnemyDetectorRed) then
		Game.ShowStatusText(Tx"The box locks up tight: there are enemies near")
		return
	end
	if Game.CurrentScreen ~= 0 then
		log("can't open: screen %d", Game.CurrentScreen)
		Game.ShowStatusText(Tx"The box can't be opened here")
		return
	end
	-- a chest after the map's own ones; when the map has all 20 (most maps keep 20 records,
	-- used or not), its last one is lent: kept byte by byte and put back when the box closes
	local index, added, saved = i4[CHEST_COUNT], false, nil
	if index < MAX_CHESTS then
		i4[CHEST_COUNT] = index + 1
		added = true
	else
		index = MAX_CHESTS - 1
	end
	local chest = Map.Chests[index]
	if not added then saved = mem.string(chest["?ptr"], chest["?size"], true) end
	chest.ChestPicture = box.Picture
	chest.Bits = const.ChestBits.ItemsPlaced
	fill(chest, store()[p.Id])
	Open = {Chest = index, Id = p.Id, Box = box, Added = added, Saved = saved}
	log("box %d (%s) opened as chest %d", p.Id, p.Number, index)
	evt.OpenChest(index)
	if Game.CurrentScreen ~= CHEST_SCREEN then
		log("the chest screen didn't open (screen %d)", Game.CurrentScreen)
		Game.ShowStatusText(Tx"The box can't be opened here")
		close()
	end
end

-- using a box: back into the backpack, opened on the next tick
local function useBox(target, item, playerId)
	log("use: item %d, charges %d, screen %d", item.Number, item.Charges, Game.CurrentScreen)
	local box = BOXES[item.Number]
	if not box then return 0 end
	if Open then return 0 end
	if box.NotNearEnemies and (Party.EnemyDetectorYellow or Party.EnemyDetectorRed) then
		Game.ShowStatusText(Tx"The box locks up tight: there are enemies near")
		return 0
	end
	local id = boxId(item)
	Pending = {Number = item.Number, Id = id}
	return 0
end

for n in pairs(BOXES) do
	evt.UseItemEffects[n] = useBox
end

---------------------------------------------------------------------------
-- while a box is open: wrong items back to the mouse; closing
---------------------------------------------------------------------------

local function allowed(box, num)
	if CONTAINERS[num] then return false, Tx"No box or bag goes into a box" end
	local t = Game.ItemsTxt[num]
	if not t or not box.Allow(t) then return false, box.Only end
	return true
end

local function checkOpenBox()
	local chest = Map.Chests[Open.Chest]
	for c = 0, 139 do
		local k = chest.Inventory[c]
		if k > 0 then
			local it = chest.Items[k]
			local ok, why = allowed(Open.Box, it.Number)
			if not ok and Mouse.Item.Number == 0 then
				Mouse:AddItem(it)
				for c2 = 0, 139 do
					if chest.Inventory[c2] == -(1 + c) then chest.Inventory[c2] = 0 end
				end
				chest.Inventory[c] = 0
				it:Clear()
				Game.ShowStatusText(why)
				Game.NeedRedraw = true
				return
			end
		end
	end
end

function events.Tick()
	if Repaint > 0 then
		Repaint = Repaint - 1
		if Game.CurrentScreen == 0 then Game.NeedRedraw = true end
	end
	if Pending then
		local p = Pending
		if Mouse.Item.Number ~= 0 then Mouse:ReleaseItem() end
		-- out of the character screen first: one Esc, as if the key were pressed, and wait
		-- (ExitScreen only handles houses in MM8; opening the chest over the character
		-- screen leaves that screen half alive)
		if Game.CurrentScreen ~= 0 then
			p.Wait = (p.Wait or 0) + 1
			if p.Wait == 1 or p.Wait == ESC_WAIT / 2 then
				log("leaving screen %d", Game.CurrentScreen)
				Game.Actions.Add(113, 0)
			elseif p.Wait > ESC_WAIT then
				Pending = nil
				log("can't open: screen %d", Game.CurrentScreen)
				Game.ShowStatusText(Tx"The box can't be opened here")
			end
			return
		end
		Pending = nil
		local ok, err = pcall(openNow, p)
		if not ok then
			MF.LogWarning("[Boxes] opening: %s", tostring(err))
			close()
		end
		return
	end
	if Open then
		-- the chest view and a character's backpack beside it are both the open box
		local scr = Game.CurrentScreen
		if scr ~= CHEST_SCREEN and scr ~= CHEST_INV_SCREEN then
			log("closing on screen %d", scr)
			close()
		else
			local ok, err = pcall(checkOpenBox)
			if not ok then MF.LogWarning("[Boxes] check: %s", tostring(err)) end
		end
	end
end

function events.BeforeSaveGame() close() end
function events.LeaveMap() close() end
function events.BeforeLoadMap() Open, Pending = nil, nil end

---------------------------------------------------------------------------
-- an Ancient Storage Box in a chest of each Ancient facility, once a game
---------------------------------------------------------------------------

function events.AfterLoadMap()
	if not GemType then GemType = Game.ItemsTxt[177].EquipStat end
	local ms = Game.MapStats[Map.MapStatsIndex]
	local name = ms and ms.Name and ms.Name:lower() or ""
	local hit = false
	for _, f in ipairs(FACILITIES) do if name:find(f, 1, true) then hit = true end end
	if not hit then return end
	local s = store()
	s.Placed = s.Placed or {}
	if s.Placed[Map.Name] then return end
	-- an unopened chest with a free item record (the game places it in the grid when opened)
	for i = 0, Map.Chests.count - 1 do
		local chest = Map.Chests[i]
		if bit.band(chest.Bits, const.ChestBits.ItemsPlaced) == 0 then
			for k = 1, 140 do
				local it = chest.Items[k]
				if it.Number == 0 then
					it:Clear()
					it.Number = 2230
					it.Identified = true
					s.Placed[Map.Name] = true
					log("Ancient Storage Box put into chest %d of %s", i, Map.Name)
					return
				end
			end
		end
	end
	s.Placed[Map.Name] = "no chest"
end
