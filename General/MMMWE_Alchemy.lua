--[[
	MMMWE_Alchemy.lua — known recipes on the potions' descriptions, brewing in batches (11.11.26)

	1. Recipes. The description of a potion (right click) lists the recipes the party has
	   discovered (their autonotes) that the potion takes part in:
	       Mixes into:  + Harden Item = Minor Fire Resistance
	       Mixed from:  Cure Wounds + Cure Disease
	   A line is green when the party carries what it takes (the other potion; both
	   potions of a "mixed from" line). RECIPE_LINES lines at most of each kind.

	2. Batches. Hold Ctrl while mixing two potions: after the game mixes the pair, every
	   other pair of the same two potions in that character's backpack is mixed the same
	   way (the result's strength is the mean of the pair's, an empty bottle is left in
	   the place of the potion poured). Only mixes that give a potion are repeated: the
	   game has done its checks (the Alchemy rank, explosions) on the first pair.

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

local Batch      -- {Player = pointer, Poured = item id, Into = item id, Result = item id, Slot = the first pair's}

-- 0x415AC2: the game is turning the potion at slot [ebp-0Ch] of the character esi into
-- the result [ebp-4] of a mix (the potion in hand is still on the mouse)
mem.autohook(0x415AC2, function(d)
	Batch = nil
	if not Keys.IsPressed(const.Keys.CTRL) then return end
	local slot = i4[d.ebp - 0xC]
	local result = i4[d.ebp - 4]
	local into = i4[d.esi + 0x4A8 + slot * 0x24]
	local poured = Mouse.Item.Number
	if result > 5 and poured ~= 0 and into ~= 0 and poured ~= into then
		Batch = {Player = d.esi, Poured = poured, Into = into, Result = result, Slot = slot + 1}
	end
end)

local function inBackpack(pl)
	local set = {}
	for c = 0, 125 do
		local k = pl.Inventory[c]
		if k > 0 then set[k] = true end
	end
	return set
end

local function brewRest(b)
	local arr = Party.PlayersArray
	local index = (b.Player - arr[0]["?ptr"]) / arr[0]["?size"]
	if index ~= math.floor(index) or index < 0 or index >= arr.count then return end
	local pl = arr[index]
	local packed = inBackpack(pl)
	local poured, into = {}, {}
	for k in pairs(packed) do
		local it = pl.Items[k]
		if k ~= b.Slot and not it.Broken then
			if it.Number == b.Poured then poured[#poured + 1] = k
			elseif it.Number == b.Into then into[#into + 1] = k end
		end
	end
	table.sort(poured); table.sort(into)
	local n = math.min(#poured, #into)
	for i = 1, n do
		local a, t = pl.Items[poured[i]], pl.Items[into[i]]
		t.Number = b.Result
		t.Bonus = math.floor((t.Bonus + a.Bonus) / 2)
		t.Identified = true
		-- the potion poured leaves its bottle (the same size) in its place
		a.Number = BOTTLE
		a.Bonus = 0
		a.Identified = true
	end
	if n > 0 then
		Game.ShowStatusText(string.format(MF.TextN(n, "%d more potion brewed: %s", "%d more potions brewed: %s"),
			n, Game.ItemsTxt[b.Result].Name))
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
