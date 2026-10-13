--[[
	MMMWE_InventorySort.lua — inventory autosort and party consolidation

	Two small text buttons on the inventory page of the character screen:
	  "Sort"    sorts the current character's backpack
	  "Gather"  party consolidation: moves items to the character best suited to carry them
	            (see CONSOLIDATE below), then sorts every backpack

	How it works (MM8, from delete_from_backpack 0x49133B):
	  Player.Inventory[0..125] is the 14 x 9 grid (row * 14 + column). An item's top-left cell
	  holds its Player.Items index, every other cell it covers holds -(top-left cell + 1).
	  Sorting only rewrites this grid: items keep their Items slots, so equipped items,
	  durability, packed bonuses of unidentified items and temporary-enchantment records are
	  untouched. Item sizes are read from the grid itself (the cells each item covers).
	  Gathering copies an item record into a free Items slot of the receiving character and
	  clears it in the giver's (delete_from_backpack is not used: it wipes the record).

	A layout is written only if every item fits; otherwise the backpack is left as it was.

	Three more buttons on the Chest screen:
	  "Take all"     every item and all gold
	  "Take gold"    only gold
	  "Take valued"  gold and valuable items (see VALUED below)
	Items go to the current character first, then to the others in party order, each into
	the first free spot of the backpack. Gold is added like picking it up by hand (Banker
	bonus, followers' share). Items that fit nowhere stay in the chest.
--]]

local MF = Merge.Functions

local COLS, ROWS = 14, 9
local CELLS = COLS * ROWS
local ITEM_SIZE = 0x24

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

-- Buttons (640x480 screen coordinates) — move them if they cover something
local BUTTON_Y      = 322
local SORT_X        = 180
local GATHER_X      = 220
local COLOR_STD     = RGB(150, 140, 110)   -- dim, so they don't draw attention
local COLOR_OVER    = RGB(255, 255, 150)

-- Chest screen buttons (640x480 screen coordinates): stacked in the empty stone panel
-- above the Close button
local CHEST_BUTTON_X = 498
local TAKE_ALL_Y     = 377
local TAKE_GOLD_Y    = 393
local TAKE_VALUED_Y  = 409

-- "Take valued": an item is taken if any of these holds
local VALUED = {
	MinValue    = 500,    -- worth at least this much (the value shown in the shop, enchantments included)
	Special     = true,   -- artifacts, relics and other special items (ItemsTxt Material ~= 0)
	Unidentified = true,  -- unidentified items (their worth is unknown)
	Kinds = {             -- item kinds always taken, by ItemsTxt.EquipStat
		[10] = true,      -- rings
		[11] = true,      -- amulets
		[16] = true,      -- books
	},
}

-- Group order by ItemsTxt.EquipStat (= const.ItemType - 1). Lower = earlier in the backpack.
local GROUP_RANK = {
	[0] = 1, [1] = 1, [2] = 1,   -- weapons, two-handed weapons, bows
	[12] = 2,                    -- wands
	[3] = 3,                     -- body armor
	[4] = 4,                     -- shields
	[5] = 5,                     -- helms
	[8] = 6,                     -- gauntlets
	[9] = 7,                     -- boots
	[6] = 8,                     -- belts
	[7] = 9,                     -- cloaks
	[10] = 10,                   -- rings
	[11] = 11,                   -- amulets
	[14] = 12,                   -- potions
	[13] = 13,                   -- reagents
	[15] = 14,                   -- scrolls
	[16] = 15,                   -- books
	[17] = 16,                   -- message scrolls
}
local OTHER_RANK = 20            -- everything else (misc, quest items ...)

-- Alchemist's kit, laid out in the top-left corner before everything else:
-- one row per satchel color, left to right Novice -> Master, then the bottle boxes right
-- next to the satchels. Item numbers from UsableItems.lua.
local SATCHEL_ROWS = {
	{969, 970, 971, 972, 973},   -- red
	{974, 975, 976, 977, 978},   -- blue
	{979, 980, 981, 982, 983},   -- yellow
	{984, 985, 986, 987},        -- gray
}
local BOTTLE_BOXES = {[193] = true}
local KEEP_KIT_CORNER_CLEAR = false   -- true: other items stay out of the kit's corner

local SatchelPos = {}            -- item number -> {row, order}
for r, list in ipairs(SATCHEL_ROWS) do
	for i, n in ipairs(list) do SatchelPos[n] = {r, i} end
end

-- Party consolidation: each rule moves matching items to the party member with the highest
-- skill (skill x mastery); ties keep the earlier party member. A rule is skipped when nobody
-- has the skill. Rules are applied in order, an item is moved by the first rule it matches.
local CONSOLIDATE = {
	{name = "potions, reagents, apothecary satchels and bottle boxes", skill = const.Skills.Alchemy,
		match = function(it, txt)
			return txt.EquipStat == 13 or txt.EquipStat == 14
				or SatchelPos[it.Number] ~= nil or BOTTLE_BOXES[it.Number] == true
		end},
	{name = "unidentified items", skill = const.Skills.IdentifyItem,
		match = function(it, txt) return not it.Identified end},
	{name = "broken items", skill = const.Skills.Repair,
		match = function(it, txt) return it.Broken end},
}

---------------------------------------------------------------------------
-- Grid helpers
---------------------------------------------------------------------------

-- Items in a backpack: list of {idx, w, h, cell}
local function collect(pl)
	local boxes = {}
	for c = 0, CELLS - 1 do
		local v = pl.Inventory[c]
		local main = v > 0 and c or (v < 0 and -v - 1) or nil
		if main then
			local idx = v > 0 and v or pl.Inventory[main]
			if idx > 0 then
				local b = boxes[main]
				if not b then
					b = {idx = idx, cell = main, c0 = COLS, r0 = ROWS, c1 = -1, r1 = -1}
					boxes[main] = b
				end
				local col, row = c % COLS, math.floor(c / COLS)
				b.c0, b.c1 = math.min(b.c0, col), math.max(b.c1, col)
				b.r0, b.r1 = math.min(b.r0, row), math.max(b.r1, row)
			end
		end
	end
	local list = {}
	for _, b in pairs(boxes) do
		b.w, b.h = b.c1 - b.c0 + 1, b.r1 - b.r0 + 1
		list[#list + 1] = b
	end
	return list
end

local function emptyGrid()
	local g = {}
	for c = 0, CELLS - 1 do g[c] = 0 end
	return g
end

local function fits(g, col, row, w, h)
	if col + w > COLS or row + h > ROWS then return false end
	for r = row, row + h - 1 do
		for c = col, col + w - 1 do
			if g[r * COLS + c] ~= 0 then return false end
		end
	end
	return true
end

local function put(g, col, row, w, h, idx)
	local main = row * COLS + col
	for r = row, row + h - 1 do
		for c = col, col + w - 1 do
			g[r * COLS + c] = -(main + 1)
		end
	end
	g[main] = idx
end

-- First free spot, column by column, top to bottom (from column minCol on)
local function findSpot(g, w, h, minCol)
	for col = minCol or 0, COLS - w do
		for row = 0, ROWS - h do
			if fits(g, col, row, w, h) then return col, row end
		end
	end
end

-- Lay out the items in the given order (into grid g, or an empty one); nil if something
-- doesn't fit
local function pack(items, g)
	g = g or emptyGrid()
	for _, b in ipairs(items) do
		local col, row = findSpot(g, b.w, b.h)
		if not col then return nil end
		put(g, col, row, b.w, b.h, b.idx)
	end
	return g
end

local function writeGrid(pl, g)
	for c = 0, CELLS - 1 do
		pl.Inventory[c] = g[c]
	end
end

local function readGrid(pl)
	local g = {}
	for c = 0, CELLS - 1 do g[c] = pl.Inventory[c] end
	return g
end

---------------------------------------------------------------------------
-- Sorting
---------------------------------------------------------------------------

local function sortKey(pl, b)
	local it = pl.Items[b.idx]
	local txt = Game.ItemsTxt[it.Number]
	b.rank = GROUP_RANK[txt.EquipStat] or OTHER_RANK
	b.skill = (b.rank == 1) and txt.Skill or 0
	b.special = (txt.Material ~= 0) and 0 or 1      -- artifacts, relics, special items first
	b.unknown = it.Identified and 0 or 1
	b.broken = it.Broken and 1 or 0
	b.value = txt.Value or 0
	b.number = it.Number
	b.area = b.w * b.h
end

-- Groups sorted by item number only (ranks from GROUP_RANK)
local BY_NUMBER = {[14] = true, [15] = true}   -- scrolls, books

local function byGroup(a, b)
	if a.rank ~= b.rank then return a.rank < b.rank end
	if BY_NUMBER[a.rank] and a.number ~= b.number then return a.number < b.number end
	if a.skill ~= b.skill then return a.skill < b.skill end
	if a.broken ~= b.broken then return a.broken < b.broken end
	if a.special ~= b.special then return a.special < b.special end
	if a.unknown ~= b.unknown then return a.unknown < b.unknown end
	if a.value ~= b.value then return a.value > b.value end
	if a.number ~= b.number then return a.number < b.number end
	return a.cell < b.cell
end

local function bySize(a, b)
	if a.area ~= b.area then return a.area > b.area end
	if a.h ~= b.h then return a.h > b.h end
	return byGroup(a, b)
end

-- The alchemist's kit in the top-left corner: a row per satchel color, then the bottle
-- boxes in the columns right of the satchels. Returns the grid, or nil if it doesn't fit.
local function placeKit(satchels, boxes)
	local g = emptyGrid()
	local rows = {}
	for _, b in ipairs(satchels) do
		local r = SatchelPos[b.number][1]
		rows[r] = rows[r] or {}
		table.insert(rows[r], b)
	end
	local y, blockW = 0, 0
	for r = 1, #SATCHEL_ROWS do
		local list = rows[r]
		if list then
			table.sort(list, function(a, b)
				local pa, pb = SatchelPos[a.number][2], SatchelPos[b.number][2]
				if pa ~= pb then return pa < pb end
				return a.cell < b.cell
			end)
			local x, bandH = 0, 0
			for _, b in ipairs(list) do
				if x + b.w > COLS or y + b.h > ROWS or not fits(g, x, y, b.w, b.h) then
					return nil
				end
				put(g, x, y, b.w, b.h, b.idx)
				x = x + b.w
				bandH = math.max(bandH, b.h)
			end
			blockW = math.max(blockW, x)
			y = y + bandH
		end
	end
	table.sort(boxes, function(a, b) return a.cell < b.cell end)
	local right, bottom = blockW, y
	for _, b in ipairs(boxes) do
		local col, row = findSpot(g, b.w, b.h, blockW)
		if not col then return nil end
		put(g, col, row, b.w, b.h, b.idx)
		right, bottom = math.max(right, col + b.w), math.max(bottom, row + b.h)
	end
	return g, right, bottom
end

local RESERVED = -1000000

-- Copy of the kit grid; with reserve, the free cells inside the kit's rectangle are kept
-- empty, so other items go to the right of the kit or below it
local function kitCopy(kit, right, bottom, reserve)
	local c = {}
	for i = 0, CELLS - 1 do
		c[i] = kit[i]
		if reserve and c[i] == 0 and i % COLS < right and math.floor(i / COLS) < bottom then
			c[i] = RESERVED
		end
	end
	return c
end

local function unreserve(g)
	for i = 0, CELLS - 1 do
		if g[i] == RESERVED then g[i] = 0 end
	end
	return g
end

-- Sort one backpack; returns true if a new layout was written
local function sortPlayer(pl)
	local items = collect(pl)
	if #items == 0 then return true end
	local satchels, boxes, rest = {}, {}, {}
	for _, b in ipairs(items) do
		sortKey(pl, b)
		if SatchelPos[b.number] then
			satchels[#satchels + 1] = b
		elseif BOTTLE_BOXES[b.number] then
			boxes[#boxes + 1] = b
		else
			rest[#rest + 1] = b
		end
	end

	local g
	local kit, right, bottom
	if #satchels > 0 or #boxes > 0 then
		kit, right, bottom = placeKit(satchels, boxes)
	end
	if kit then
		-- the other items may fill the gaps the kit leaves (absent satchels, short rows,
		-- the space under the bottle boxes). Set KEEP_KIT_CORNER_CLEAR = true to keep the
		-- kit's corner empty instead (gaps are then used only when nothing else fits).
		for _, reserve in ipairs(KEEP_KIT_CORNER_CLEAR and {true, false} or {false}) do
			table.sort(rest, byGroup)
			g = pack(rest, kitCopy(kit, right, bottom, reserve))
			if not g then
				table.sort(rest, bySize)
				g = pack(rest, kitCopy(kit, right, bottom, reserve))
			end
			if g then g = unreserve(g) break end
		end
	end
	if not g then
		-- no kit, or the kit layout leaves too little room: plain sorting, kit first
		for _, b in ipairs(satchels) do b.rank = -2 end
		for _, b in ipairs(boxes) do b.rank = -1 end
		table.sort(items, byGroup)
		g = pack(items)
		if not g then
			-- a tight backpack: largest items first packs better
			table.sort(items, bySize)
			g = pack(items)
		end
	end
	if not g then return false end
	writeGrid(pl, g)
	return true
end

---------------------------------------------------------------------------
-- Party consolidation
---------------------------------------------------------------------------

local function skillPoints(pl, skill)
	if not skill then return 0 end
	local s, m = SplitSkill(pl:GetSkill(skill))
	return s * m
end

-- Party member with the most skill points (and its party index)
local function bestCarrier(skill)
	local best, bestIndex, bestPts = nil, nil, 0
	for i = 0, Party.Count - 1 do
		local pl = Party[i]
		local pts = skillPoints(pl, skill)
		if pts > bestPts then best, bestIndex, bestPts = pl, i, pts end
	end
	return best, bestIndex
end

local function freeItemSlot(pl)
	for j = 1, 138 do
		if pl.Items[j].Number == 0 then return j end
	end
end

-- Move one backpack item (box b of player src) into dst's backpack; true on success
local function moveItem(src, b, dst, dstGrid)
	local col, row = findSpot(dstGrid, b.w, b.h)
	if not col then return false end
	local slot = freeItemSlot(dst)
	if not slot then return false end
	local from, to = src.Items[b.idx]["?ptr"], dst.Items[slot]["?ptr"]
	mem.copy(to, from, ITEM_SIZE)
	-- clear the giver's grid cells and item record
	for c = 0, CELLS - 1 do
		local v = src.Inventory[c]
		if c == b.cell or v == -(b.cell + 1) then
			src.Inventory[c] = 0
		end
	end
	mem.fill(from, ITEM_SIZE, 0)
	put(dstGrid, col, row, b.w, b.h, slot)
	writeGrid(dst, dstGrid)
	return slot
end

local function gatherParty()
	local moved, stuck = 0, 0
	local done = {}          -- items already handled by an earlier rule: [player index][Items idx]
	for i = 0, Party.Count - 1 do done[i] = {} end
	for _, rule in ipairs(CONSOLIDATE) do
		local dst, dstIndex = bestCarrier(rule.skill)
		if dst then
			sortPlayer(dst)                      -- make room first
			local dstGrid = readGrid(dst)
			for i = 0, Party.Count - 1 do
				local src = Party[i]
				for _, b in ipairs(collect(src)) do
					local it = src.Items[b.idx]
					local txt = Game.ItemsTxt[it.Number]
					if not done[i][b.idx] and txt and rule.match(it, txt) then
						done[i][b.idx] = true
						if i ~= dstIndex then
							local slot = moveItem(src, b, dst, dstGrid)
							if slot then
								moved = moved + 1
								done[dstIndex][slot] = true   -- stays with this carrier
							else
								stuck = stuck + 1
							end
						end
					end
				end
			end
		end
	end
	local unsorted = 0
	for i = 0, Party.Count - 1 do
		if not sortPlayer(Party[i]) then unsorted = unsorted + 1 end
	end
	return moved, stuck, unsorted
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------

local function onInventoryPage()
	return Game.CurrentScreen == const.Screens.Inventory
		and Game.CurrentCharScreen == const.CharScreens.Inventory
end

local function busy()
	return Mouse.Item.Number ~= 0
end

local function doSort()
	if busy() then
		Game.ShowStatusText("Put down the item you are holding first")
		return
	end
	local pl = Party:GetCurrentPlayer()
	if not pl then return end
	Game.PlaySound(23)
	if sortPlayer(pl) then
		Game.ShowStatusText("Backpack sorted")
	else
		Game.ShowStatusText("The backpack is too full to rearrange")
	end
	Game.NeedRedraw = true
end

local function doGather()
	if busy() then
		Game.ShowStatusText("Put down the item you are holding first")
		return
	end
	Game.PlaySound(23)
	local moved, stuck, unsorted = gatherParty()
	local msg = string.format("Party gathered: %d item%s moved", moved, moved == 1 and "" or "s")
	if stuck > 0 then
		msg = msg .. string.format(", %d didn't fit", stuck)
	end
	if unsorted > 0 then
		msg = msg .. ", some backpacks too full to sort"
	end
	Game.ShowStatusText(msg)
	Game.NeedRedraw = true
end

---------------------------------------------------------------------------
-- Taking items from a chest
---------------------------------------------------------------------------
-- Map.Chests[id].Items[1..140] holds the records, .Inventory[0..139] the grid
-- (row * width + column, same cell encoding as a backpack); the grid size comes from
-- the chest picture (Game.ChestBin, Chest.txt). The id of the open chest is remembered
-- from the OpenChest event.

local GOLD_EQUIPSTAT = const.ItemType.Gold - 1
local OpenChestId

function events.OpenChest(id)
	OpenChestId = id
end

local function onChestScreen()
	return Game.CurrentScreen == const.Screens.Chest
end

-- Items in the open chest: list of {idx, cell, w, h}
local function chestItems(chest)
	local bin = Game.ChestBin[chest.ChestPicture]
	local W = bin and bin.Width or COLS
	if W <= 0 then W = COLS end
	local boxes = {}
	for c = 0, 139 do
		local v = chest.Inventory[c]
		local main = v > 0 and c or (v < 0 and -v - 1) or nil
		if main and main <= 139 then
			local idx = v > 0 and v or chest.Inventory[main]
			if idx > 0 and idx <= 140 and chest.Items[idx].Number ~= 0 then
				local b = boxes[main]
				if not b then
					b = {idx = idx, cell = main, c0 = 1000, r0 = 1000, c1 = -1, r1 = -1}
					boxes[main] = b
				end
				local col, row = c % W, math.floor(c / W)
				b.c0, b.c1 = math.min(b.c0, col), math.max(b.c1, col)
				b.r0, b.r1 = math.min(b.r0, row), math.max(b.r1, row)
			end
		end
	end
	local list = {}
	for _, b in pairs(boxes) do
		b.w, b.h = b.c1 - b.c0 + 1, b.r1 - b.r0 + 1
		list[#list + 1] = b
	end
	table.sort(list, function(a, b) return a.cell < b.cell end)
	return list
end

local function removeFromChest(chest, b)
	for c = 0, 139 do
		local v = chest.Inventory[c]
		if c == b.cell or v == -(b.cell + 1) then
			chest.Inventory[c] = 0
		end
	end
	chest.Items[b.idx]:Clear()
end

local function isValued(it, txt)
	if VALUED.Special and txt.Material ~= 0 then return true end
	if VALUED.Unidentified and not it.Identified then return true end
	if VALUED.Kinds[txt.EquipStat] then return true end
	local ok, value = pcall(it.GetValue, it)
	value = ok and value or txt.Value or 0
	return value >= VALUED.MinValue
end

-- Party members in the order they receive items: the current one first
local function receivers()
	local list, cur = {}, Party:GetCurrentPlayer()
	if cur then list[1] = cur end
	for i = 0, Party.Count - 1 do
		local pl = Party[i]
		if pl ~= cur and (not cur or pl["?ptr"] ~= cur["?ptr"]) then
			list[#list + 1] = pl
		end
	end
	return list
end

-- Take items from the open chest; mode = "all", "gold" or "valued"
local function takeFromChest(mode)
	local chest = OpenChestId and OpenChestId >= 0 and OpenChestId < Map.Chests.count
		and Map.Chests[OpenChestId]
	if not chest then return nil end
	local gold, taken, left = 0, 0, 0
	local party = receivers()
	local grids = {}
	for i, pl in ipairs(party) do grids[i] = readGrid(pl) end

	for _, b in ipairs(chestItems(chest)) do
		local it = chest.Items[b.idx]
		local txt = Game.ItemsTxt[it.Number]
		if txt and txt.EquipStat == GOLD_EQUIPSTAT then
			gold = gold + it.Bonus2
			removeFromChest(chest, b)
		elseif txt and (mode == "all" or (mode == "valued" and isValued(it, txt))) then
			local done = false
			for i, pl in ipairs(party) do
				local col, row = findSpot(grids[i], b.w, b.h)
				local slot = col and freeItemSlot(pl)
				if slot then
					mem.copy(pl.Items[slot]["?ptr"], it["?ptr"], ITEM_SIZE)
					pl.Items[slot].Refundable = false
					put(grids[i], col, row, b.w, b.h, slot)
					writeGrid(pl, grids[i])
					removeFromChest(chest, b)
					taken, done = taken + 1, true
					break
				end
			end
			if not done then left = left + 1 end
		end
	end
	if gold > 0 then
		local before = Party.Gold
		Party.AddGold(gold, 0)
		gold = math.max(0, Party.Gold - before)   -- after the Banker bonus and followers' share
	end
	return gold, taken, left
end

local function doTake(mode)
	if busy() then
		Game.ShowStatusText("Put down the item you are holding first")
		return
	end
	local gold, taken, left = takeFromChest(mode)
	if not gold then
		Game.ShowStatusText("Can't tell which chest is open")
		return
	end
	if gold == 0 and taken == 0 and left == 0 then
		Game.ShowStatusText(mode == "gold" and "There is no gold here" or "Nothing to take")
		return
	end
	Game.PlaySound(23)
	local parts = {}
	if taken > 0 then
		parts[#parts + 1] = string.format("%d item%s", taken, taken == 1 and "" or "s")
	end
	if gold > 0 then
		parts[#parts + 1] = string.format("%d gold", gold)
	end
	local msg = #parts > 0 and ("Took " .. table.concat(parts, " and ")) or "Took nothing"
	if left > 0 then
		msg = msg .. string.format(", %d didn't fit", left)
	end
	Game.ShowStatusText(msg)
	Game.NeedRedraw = true
end

function events.GameInitialized2()
	if not CustomUI then return end
	local function button(text, x, action)
		return CustomUI.CreateText{
			Text           = text,
			Font           = Game.Smallnum_fnt,
			X = x, Y = BUTTON_Y,
			ColorStd       = COLOR_STD,
			ColorMouseOver = COLOR_OVER,
			Layer          = 0,
			Screen         = const.Screens.Inventory,
			Condition      = onInventoryPage,
			Action         = action,
		}
	end
	button("Sort", SORT_X, doSort)
	button("Gather", GATHER_X, doGather)

	local function chestButton(text, y, action)
		return CustomUI.CreateText{
			Text           = text,
			Font           = Game.Smallnum_fnt,
			X = CHEST_BUTTON_X, Y = y,
			ColorStd       = COLOR_STD,
			ColorMouseOver = COLOR_OVER,
			Layer          = 0,
			Screen         = const.Screens.Chest,
			Condition      = onChestScreen,
			Action         = action,
		}
	end
	chestButton("Take all", TAKE_ALL_Y, function() doTake("all") end)
	chestButton("Take gold", TAKE_GOLD_Y, function() doTake("gold") end)
	chestButton("Take valued", TAKE_VALUED_Y, function() doTake("valued") end)
end

-- for the console / other scripts
MF.SortInventory = sortPlayer
MF.GatherPartyItems = gatherParty
MF.TakeFromChest = takeFromChest
