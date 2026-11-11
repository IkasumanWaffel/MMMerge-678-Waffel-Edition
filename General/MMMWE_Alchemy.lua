--[[
	MMMWE_Alchemy.lua — known recipes on the potions' descriptions, brewing in batches (11.11.26)

	1. Recipes. The description of a potion (right click) lists the recipes the party has
	   discovered (their autonotes) that the potion takes part in:
	       Mixes into:  + Harden Item = Minor Fire Resistance
	       Mixed from:  Cure Wounds + Cure Disease
	   A line is green when the party carries what it takes (the other potion; both
	   potions of a "mixed from" line). RECIPE_LINES lines at most of each kind.

	2. Batches. Hold Ctrl while mixing two potions: after the game mixes the pair, every
	   other pair of the same two potions the character has is mixed the same way (the
	   result's strength is the mean of the pair's, an empty bottle is left in the place
	   of the potion poured). Only mixes that give a potion are repeated: the game has
	   done its checks (the Alchemy rank, explosions) on the first pair.
	   Hold Ctrl while putting a reagent into an empty bottle: every other empty bottle is
	   filled the same way while the reagent lasts.
	   Hold a digit with Ctrl to brew at most that many more (Ctrl+3: three more; 0 means
	   ten). Ctrl alone brews as many potions in all as the batch size set with Ctrl + the
	   mouse wheel on the character screen (kept with the game), or every pair there is
	   when the size is "all" (the wheel turned down below 2).
	   What the character has: the backpack, the potions and bottles in the bottle box
	   carried in it (they are changed inside the box; not while the box is open), and for
	   reagents the apothecary satchels in the backpack.

	The mix tables are the game's own (POTION.TXT, POTNOTES.TXT as loaded by
	Structs/RemoveItemsLimits.lua); the order of the potions in them is that of
	Data/Tables/Potion settings.txt.
--]]

local MF = Merge.Functions
local Tx = Merge.Functions.Text
local i4, u1, u2, u4 = mem.i4, mem.u1, mem.u2, mem.u4

local RECIPE_LINES = 8
local BOTTLE = 220
local GREEN, GRAY = {120, 255, 120}, {200, 200, 200}

---------------------------------------------------------------------------
-- the tables
---------------------------------------------------------------------------

local Potions        -- [n] = item id; n: 0 the catalyst, 1.. the rows of the mix table
local IndexOf        -- [item id] = n

local function loadPotions()
	if Potions then return true end
	local f = io.open("Data/Tables/Potion settings.txt", "r")
	if not f then return false end
	local list, index = {}, {}
	local row = 0
	for line in f:lines() do
		row = row + 1
		if row > 2 then      -- the header and the empty bottle
			local w = string.split(line, "\9")
			local item = tonumber(w[2])
			if item then
				list[#list + 1] = item
				index[item] = #list - 1
			end
		end
	end
	f:close()
	Potions, IndexOf = {}, index
	for k, item in ipairs(list) do Potions[k - 1] = item end
	return true
end

-- the result (item id; 1..5 an explosion or the catalyst's rule, 0 nothing) and the
-- autonote of mixing potion a (in hand) into potion b; a, b: rows of the table (1..)
local function mix(a, b)
	local n = u1[0x41591E + 2]
	local k = ((a - 1) * n + (b - 1)) * 2
	return u2[u4[0x415924 + 4] + k], u2[u4[0x415AEE + 4] + k], n
end

local function known(note)
	return note > 0 and Party.AutonotesBits[note]
end

---------------------------------------------------------------------------
-- 1. the recipes on a potion's description
---------------------------------------------------------------------------

local OrigNotes = {}
local Cached = {Time = 0}

local function carried()
	local has = {}
	for _, pl in Party do
		for _, it in pl.Items do
			if it.Number ~= 0 then has[it.Number] = true end
		end
	end
	return has
end

local function colored(c, s)
	return StrColor(c[1], c[2], c[3], s)
end

local function recipeLines(num)
	local x = IndexOf[num]
	if not x or x < 1 then return end
	local _, _, n = mix(1, 1)
	local has = carried()
	local into, from, seen = {}, {}, {}
	for y = 1, n - 1 do
		local other = Potions[y]
		if other and y ~= x then
			for pass = 1, 2 do
				local r, note
				if pass == 1 then r, note = mix(x, y) else r, note = mix(y, x) end
				if r > 5 and known(note) and not seen[y] and Game.ItemsTxt[r] then
					seen[y] = true
					into[#into + 1] = colored(has[other] and GREEN or GRAY,
						string.format("+ %s = %s", Game.ItemsTxt[other].Name, Game.ItemsTxt[r].Name))
				end
			end
		end
	end
	for a = 1, n - 1 do
		for b = a + 1, n - 1 do
			if Potions[a] and Potions[b] then
				local r, note = mix(a, b)
				if r ~= num or not known(note) then r, note = mix(b, a) end
				if r == num and known(note) then
					from[#from + 1] = colored(has[Potions[a]] and has[Potions[b]] and GREEN or GRAY,
						string.format("%s + %s", Game.ItemsTxt[Potions[a]].Name, Game.ItemsTxt[Potions[b]].Name))
				end
			end
		end
	end
	local out = {}
	local function section(title, list)
		if #list == 0 then return end
		out[#out + 1] = title
		for k = 1, math.min(#list, RECIPE_LINES) do out[#out + 1] = list[k] end
		if #list > RECIPE_LINES then out[#out + 1] = string.format(Tx"... and %d more", #list - RECIPE_LINES) end
	end
	section(Tx"Mixed from:", from)
	section(Tx"Mixes into:", into)
	if #out > 0 then return table.concat(out, "\n") end
end

-- sets the description of a potion to its text and the party's known recipes with it
-- (called by the item description hook of MMMWE_Main.lua)
function MF.PotionNotes(num)
	if not loadPotions() or not IndexOf[num] then return end
	local it = Game.ItemsTxt[num]
	if not it then return end
	if not OrigNotes[num] then OrigNotes[num] = it.Notes end
	-- the hook runs every frame the description is shown: the lines are worked out twice
	-- a second at most
	local now = os.clock()
	if Cached.Num ~= num or now - Cached.Time > 0.5 or now < Cached.Time then
		local ok, lines = pcall(recipeLines, num)
		Cached.Num, Cached.Time, Cached.Lines = num, now, ok and lines or nil
	end
	local text = OrigNotes[num]
	if Cached.Lines then text = text .. "\n\n" .. Cached.Lines end
	if it.Notes ~= text then it.Notes = text end
end

---------------------------------------------------------------------------
-- 2. batches
---------------------------------------------------------------------------

local ITEM_SIZE = 0x24
local BOTTLE_BOX = 193
local FIRST_BOX_ID = 1000

local Batch      -- {Player = pointer, Kind = "mix" / "reagent", Poured, Into, Result, Power, Slot, Limit}

-- (11.11.26) how many more to brew: a digit held with Ctrl (the top row or the numeric
-- keypad; 0 means 10); otherwise the batch size set with Ctrl + the mouse wheel on the
-- character screen (vars.MMMWE_BatchSize: the potions in all, the first one included;
-- nil: as many as there are)
local BATCH_MAX = 50

local function batchLimit()
	for d = 0, 9 do
		if Keys.IsPressed(0x30 + d) or Keys.IsPressed(0x60 + d) then
			return d == 0 and 10 or d
		end
	end
	local size = vars and vars.MMMWE_BatchSize
	if size then return size - 1 end
end

local function showBatchSize()
	local size = vars.MMMWE_BatchSize
	Game.ShowStatusText(size and string.format(Tx"Batch brewing (Ctrl): %d potions", size)
		or Tx"Batch brewing (Ctrl): all the potions there are")
end

-- Ctrl + the mouse wheel on the character screen: up for more, down for fewer; below 2 is
-- "all", above it 2 again
function events.WindowMessage(t)
	if t.Msg ~= 0x20A or Game.CurrentScreen ~= const.Screens.Inventory
			or not Keys.IsPressed(const.Keys.CTRL) then
		return
	end
	local up = t.WParam >= 0 and t.WParam < 0x80000000
	local size = vars.MMMWE_BatchSize
	if up then
		size = size and math.min(size + 1, BATCH_MAX) or 2
	else
		size = size and size > 2 and size - 1 or nil
	end
	vars.MMMWE_BatchSize = size
	showBatchSize()
	t.Handled = true
	t.Result = 0
end

-- 0x415AC2: the game is turning the potion at slot [ebp-0Ch] of the character esi into
-- the result [ebp-4] of a mix (the potion in hand is still on the mouse)
mem.autohook(0x415AC2, function(d)
	Batch = nil
	if not Keys.IsPressed(const.Keys.CTRL) then return end
	local slot = i4[d.ebp - 0xC]
	local result = i4[d.ebp - 4]
	local into = i4[d.esi + 0x4A8 + slot * ITEM_SIZE]
	local poured = Mouse.Item.Number
	if result > 5 and poured ~= 0 and into ~= 0 and poured ~= into then
		Batch = {Kind = "mix", Player = d.esi, Poured = poured, Into = into, Result = result, Slot = slot + 1,
			Limit = batchLimit()}
	end
end)

-- 0x415885: the game has turned the empty bottle at slot [ebp-0Ch] of the character esi
-- into a potion with the reagent in hand (still on the mouse)
mem.autohook(0x415885, function(d)
	Batch = nil
	if not Keys.IsPressed(const.Keys.CTRL) then return end
	local slot = i4[d.ebp - 0xC]
	local p = d.esi + 0x4A8 + slot * ITEM_SIZE
	local reagent = Mouse.Item.Number
	if reagent ~= 0 and i4[p] > BOTTLE then
		Batch = {Kind = "reagent", Player = d.esi, Poured = reagent, Into = BOTTLE, Result = i4[p],
			Power = i4[p + 4], Slot = slot + 1, Limit = batchLimit()}
	end
end)

local function int4(n)
	n = n % 0x100000000
	return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end

local function readInt4(s, at)
	local a, b, c, e = s:byte(at, at + 3)
	return a + b * 256 + c * 65536 + e * 16777216
end

-- Everything a character has to brew with, the backpack first, then the bottle box in it
-- (unless it is open): entries {Number, Bonus, Set = function(number, bonus), Remove}
local function supplies(pl, skipSlot)
	local list = {}
	local boxes = {}
	local slots = {}
	for c = 0, 125 do
		local k = pl.Inventory[c]
		if k > 0 then slots[#slots + 1] = {k, c} end
	end
	table.sort(slots, function(a, b) return a[1] < b[1] end)
	for _, sc in ipairs(slots) do
		local k, cell = sc[1], sc[2]
		local it = pl.Items[k]
		if it.Number == BOTTLE_BOX and it.Charges >= FIRST_BOX_ID then boxes[#boxes + 1] = it.Charges end
		if k ~= skipSlot and it.Number ~= 0 and not it.Broken then
			list[#list + 1] = {Number = it.Number, Bonus = it.Bonus,
				Set = function(number, bonus)
					it.Number, it.Bonus = number, bonus
					it.Identified = true
				end,
				Remove = function()
					for c2 = 0, 125 do
						if pl.Inventory[c2] == -(1 + cell) then pl.Inventory[c2] = 0 end
					end
					pl.Inventory[cell] = 0
					mem.fill(it["?ptr"], ITEM_SIZE, 0)
				end}
		end
	end
	local store = vars.MMMWE_Boxes
	local open = MF.OpenBoxId and MF.OpenBoxId()
	for _, id in ipairs(boxes) do
		local rec = store and id ~= open and store[id]
		if rec and rec.Items then
			local keys = {}
			for k in pairs(rec.Items) do keys[#keys + 1] = k end
			table.sort(keys)
			for _, k in ipairs(keys) do
				local data = rec.Items[k]
				if type(data) == "string" and #data >= ITEM_SIZE then
					list[#list + 1] = {Number = readInt4(data, 1), Bonus = readInt4(data, 5), InBox = true,
						Set = function(number, bonus)
							local d = rec.Items[k]
							-- number, bonus, the rest as it was, identified (the bit 1 at +14h)
							local cond = d:byte(0x15)
							rec.Items[k] = int4(number) .. int4(bonus) .. d:sub(9, 0x14)
								.. string.char(cond % 2 == 1 and cond or cond + 1) .. d:sub(0x16)
						end}
				end
			end
		end
	end
	return list
end

-- units of a reagent in the character's satchels: {take = function()} each
local function satchelUnits(pl, reagent)
	local units = {}
	local satchels = MF.ApothecarySatchels
	if not satchels then return units end
	for c = 0, 125 do
		local k = pl.Inventory[c]
		if k > 0 then
			local it = pl.Items[k]
			local kinds = satchels[it.Number]
			if kinds then
				for tier, num in ipairs(kinds) do
					if num == reagent then
						local mul = 100 ^ (tier - 1)
						local count = math.floor(it.Charges / mul) % 100
						for _ = 1, count do
							units[#units + 1] = {Remove = function() it.Charges = it.Charges - mul end}
						end
					end
				end
			end
		end
	end
	return units
end

local function brewRest(b)
	local arr = Party.PlayersArray
	local index = (b.Player - arr[0]["?ptr"]) / arr[0]["?size"]
	if index ~= math.floor(index) or index < 0 or index >= arr.count then return end
	local pl = arr[index]
	local poured, into = {}, {}
	for _, e in ipairs(supplies(pl, b.Slot)) do
		if e.Number == b.Poured then poured[#poured + 1] = e
		elseif e.Number == b.Into then into[#into + 1] = e end
	end
	local fromBox = 0
	local n
	if b.Kind == "reagent" then
		for _, u in ipairs(satchelUnits(pl, b.Poured)) do poured[#poured + 1] = u end
		n = math.min(#poured, #into, b.Limit or math.huge)
		for i = 1, n do
			into[i].Set(b.Result, b.Power)
			poured[i].Remove()
			if into[i].InBox then fromBox = fromBox + 1 end
		end
	else
		n = math.min(#poured, #into, b.Limit or math.huge)
		for i = 1, n do
			local a, t = poured[i], into[i]
			t.Set(b.Result, math.floor((t.Bonus + a.Bonus) / 2))
			a.Set(BOTTLE, 0)       -- the potion poured leaves its bottle (the same size) in its place
			if t.InBox then fromBox = fromBox + 1 end
		end
	end
	if MF.LogInfo then
		MF.LogInfo("[Alchemy] batch %s: %d + %d -> %d, %d more brewed (%d in the box); %d poured and %d to fill found",
			b.Kind, b.Poured, b.Into, b.Result, n, fromBox, #poured, #into)
	end
	if n > 0 then
		local text = string.format(MF.TextN(n, "%d more potion brewed: %s", "%d more potions brewed: %s"),
			n, Game.ItemsTxt[b.Result].Name)
		if fromBox > 0 then
			text = text .. string.format(Tx" (%d in the bottle box)", fromBox)
		end
		Game.ShowStatusText(text)
		Game.NeedRedraw = true
	end
end

function events.Tick()
	if not Batch then return end
	local b = Batch
	Batch = nil
	local ok, err = pcall(brewRest, b)
	if not ok and MF.LogWarning then MF.LogWarning("[Alchemy] batch: %s", tostring(err)) end
end
