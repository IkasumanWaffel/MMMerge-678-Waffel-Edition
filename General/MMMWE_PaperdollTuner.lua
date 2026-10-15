--[[
	MMMWE_PaperdollTuner.lua — place worn items on the paperdoll by hand and save the result

	The paperdoll position of body armor, helms, belts, boots and cloaks comes from
	Data/Tables/Complex item pictures.txt: an X, Y pair per item for each doll type
	(t0..t5, Character doll types.txt). Where a pair is missing (0, 0) the picture is drawn
	at the doll's corner and "floats" - e.g. the MM8 armors 84..98 and Resplendent Chain
	Mail (876) have no doll type 4 position (portraits 61..66).

	On the character screen, for the current character's doll type:
	  Ctrl + arrows            move the selected item 1 pixel (Ctrl + Shift: 5 pixels)
	  Ctrl + PageUp/PageDown   select armor / helm / belt / boots / cloak
	  Ctrl + S                 write the moved positions into Complex item pictures.txt
	                           (the first save keeps the old file as "...txt.bak")
	The status line shows the item, doll type and position after every key.
	Moves take effect at once but are lost on exit unless saved.
--]]

local MF = Merge.Functions
local K = const.Keys

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local ENABLED = true
local FILE    = "Data/Tables/Complex item pictures.txt"
local BIG_STEP = 5

local SLOTS = {
	{"ItemArmor", "Armor"}, {"ItemHelm", "Helm"}, {"ItemBelt", "Belt"},
	{"ItemBoots", "Boots"}, {"ItemCloak", "Cloak"},
}

---------------------------------------------------------------------------

local slot = 1
local Changed = {}          -- [item id][doll type] = {X, Y}
local ChangedCount = 0
local BackupDone = false

local function log(fmt, ...) if MF.LogInfo then MF.LogInfo("[PaperdollTuner] " .. fmt, ...) end end

-- item id, coordinates of its doll type, doll type, player
local function selected()
	local pl = Party:GetCurrentPlayer()
	if not pl then return end
	local idx = pl[SLOTS[slot][1]]
	if not idx or idx == 0 then return nil, nil, nil, pl end
	local id = pl.Items[idx].Number
	local dt = Game.CharacterPortraits[pl.Face].DollType
	local set = Game.ArmorPicsCoords[id]
	local c = set and dt < Game.CharacterDollTypes.count and set[dt]
	return id, c, dt, pl
end

local function show()
	local id, c, dt = selected()
	local what = SLOTS[slot][2]
	if not id then
		Game.ShowStatusText(what .. ": nothing worn")
	elseif not c then
		Game.ShowStatusText(string.format("%s: %s has no paperdoll position", what, Game.ItemsTxt[id].Name))
	else
		Game.ShowStatusText(string.format("%s %d, doll type %d: X %d, Y %d%s", Game.ItemsTxt[id].Name, id, dt,
			c.X, c.Y, ChangedCount > 0 and string.format("  (%d unsaved)", ChangedCount) or ""))
	end
end

local function move(dx, dy)
	local id, c, dt = selected()
	if not c then show() return end
	c.X, c.Y = c.X + dx, c.Y + dy
	Changed[id] = Changed[id] or {}
	if not Changed[id][dt] then ChangedCount = ChangedCount + 1 end
	Changed[id][dt] = {c.X, c.Y}
	show()
end

---------------------------------------------------------------------------
-- saving
---------------------------------------------------------------------------

local function readAll(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

local function writeAll(path, s)
	local f = io.open(path, "wb")
	if not f then return false end
	f:write(s)
	f:close()
	return true
end

local function save()
	if ChangedCount == 0 then
		Game.ShowStatusText("Paperdoll: nothing to save")
		return
	end
	local text = readAll(FILE)
	if not text then
		Game.ShowStatusText("Paperdoll: can't read " .. FILE)
		return
	end
	if not BackupDone then
		if not readAll(FILE .. ".bak") then writeAll(FILE .. ".bak", text) end
		BackupDone = true
	end

	local nl = text:find("\r\n", 1, true) and "\r\n" or "\n"
	local lines, pos = {}, 1
	while pos <= #text do
		local e = text:find("\n", pos, true)
		local line = text:sub(pos, (e or #text + 1) - 1)
		lines[#lines + 1] = line:gsub("\r$", "")
		pos = e and e + 1 or #text + 1
	end
	local endsWithNl = text:sub(-1) == "\n"

	local written = 0
	for i, line in ipairs(lines) do
		local w = line:split("\t")
		local id = tonumber(w[2])
		if id and Changed[id] then
			for dt, xy in pairs(Changed[id]) do
				local cx, cy = 5 + dt * 2, 6 + dt * 2
				for k = #w + 1, cy do w[k] = "" end
				w[cx], w[cy] = tostring(xy[1]), tostring(xy[2])
				written = written + 1
				log("item %d (%s), doll type %d: X %d, Y %d", id, w[3] or "", dt, xy[1], xy[2])
			end
			lines[i] = table.concat(w, "\t")
		end
	end

	if not writeAll(FILE, table.concat(lines, nl) .. (endsWithNl and nl or "")) then
		Game.ShowStatusText("Paperdoll: can't write " .. FILE)
		return
	end
	Changed, ChangedCount = {}, 0
	Game.ShowStatusText(string.format("Paperdoll: %d position%s saved", written, written == 1 and "" or "s"))
end

---------------------------------------------------------------------------

if ENABLED then
	function events.KeyDown(t)
		if Game.CurrentScreen ~= const.Screens.Inventory or not Keys.IsPressed(K.CTRL) then return end
		local step = Keys.IsPressed(K.SHIFT) and BIG_STEP or 1
		local key = t.Key
		if key == K.LEFT then move(-step, 0)
		elseif key == K.RIGHT then move(step, 0)
		elseif key == K.UP then move(0, -step)
		elseif key == K.DOWN then move(0, step)
		elseif key == K.PRIOR then slot = (slot - 2) % #SLOTS + 1; show()
		elseif key == K.NEXT then slot = slot % #SLOTS + 1; show()
		elseif key == K.S then save()
		else return end
		t.Key = 0
		t.Handled = true
	end
end

MF.PaperdollTunerSave = save
