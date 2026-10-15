--[[
	MMMWE_PaperdollTuner.lua — place worn items on the paperdoll by hand and save the result

	The paperdoll position of body armor, helms, belts, boots and cloaks comes from
	Data/Tables/Complex item pictures.txt: an X, Y pair per item for each doll type
	(t0..t5, Character doll types.txt). Visible gauntlets (VisibleGauntletsRefactored.lua)
	take theirs from Data/Tables/Visible gauntlets.txt: X, Y per doll type and hand pose.

	On the character screen, for the current character's doll type:
	  Ctrl + arrows            move the selected item 1 pixel (Ctrl + Shift: 5 pixels)
	  Ctrl + PageUp/PageDown   select armor / helm / belt / boots / cloak /
	                           right gauntlet / left gauntlet
	  Ctrl + S                 write the moved positions: armor pieces into Complex item
	                           pictures.txt (the first save keeps the old file as
	                           "...txt.bak"), gauntlets into Visible gauntlets.txt
	A gauntlet moves the pose shown right now (empty hand, weapon, open hand), for that
	gauntlet and doll type only; equip or remove weapons to reach the other poses.
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

-- {player slot field, name, gauntlet side}
local SLOTS = {
	{"ItemArmor", "Armor"}, {"ItemHelm", "Helm"}, {"ItemBelt", "Belt"},
	{"ItemBoots", "Boots"}, {"ItemCloak", "Cloak"},
	{"ItemGountlets", "Right gauntlet", "R"}, {"ItemGountlets", "Left gauntlet", "L"},
}

---------------------------------------------------------------------------

local slot = 1
local Changed = {}          -- [item id][doll type] = {X, Y}
local ChangedCount = 0
local GauntletsChanged = 0
local BackupDone = false

local function log(fmt, ...) if MF.LogInfo then MF.LogInfo("[PaperdollTuner] " .. fmt, ...) end end

-- item id, position (X, Y fields; nil if none), doll type, gauntlet pose
local function selected()
	local pl = Party:GetCurrentPlayer()
	if not pl then return end
	local idx = pl[SLOTS[slot][1]]
	if not idx or idx == 0 then return end
	local id = pl.Items[idx].Number
	local dt = Game.CharacterPortraits[pl.Face].DollType
	local side = SLOTS[slot][3]
	if side then
		local VG = MF.VisibleGauntlets
		local pose = VG and VG.ShownPose(side)
		if not pose then return id, nil, dt end
		local x, y = VG.Get(id, dt, pose)
		return id, {X = x, Y = y}, dt, pose
	end
	local set = Game.ArmorPicsCoords[id]
	local c = set and dt < Game.CharacterDollTypes.count and set[dt]
	return id, c, dt
end

local function unsaved()
	local n = ChangedCount + GauntletsChanged
	return n > 0 and string.format("  (%d unsaved)", n) or ""
end

local function show()
	local id, c, dt, pose = selected()
	local what = SLOTS[slot][2]
	if not id then
		Game.ShowStatusText(what .. ": nothing worn")
	elseif not c then
		Game.ShowStatusText(string.format("%s: %s has no paperdoll position", what, Game.ItemsTxt[id].Name))
	else
		Game.ShowStatusText(string.format("%s %d%s, doll type %d: X %d, Y %d%s", Game.ItemsTxt[id].Name, id,
			pose and (" " .. pose) or "", dt, c.X, c.Y, unsaved()))
	end
end

local function move(dx, dy)
	local id, c, dt, pose = selected()
	if not c then show() return end
	if pose then
		MF.VisibleGauntlets.Set(id, dt, pose, c.X + dx, c.Y + dy)
		GauntletsChanged = GauntletsChanged + 1
	else
		c.X, c.Y = c.X + dx, c.Y + dy
		Changed[id] = Changed[id] or {}
		if not Changed[id][dt] then ChangedCount = ChangedCount + 1 end
		Changed[id][dt] = {c.X, c.Y}
	end
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

-- armor pieces into Complex item pictures.txt; number of positions written, or nil
local function saveArmor()
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
	return written
end

local function save()
	if ChangedCount + GauntletsChanged == 0 then
		Game.ShowStatusText("Paperdoll: nothing to save")
		return
	end
	local parts = {}
	if ChangedCount > 0 then
		local n = saveArmor()
		if not n then return end
		parts[#parts + 1] = string.format("%d armor position%s", n, n == 1 and "" or "s")
	end
	if GauntletsChanged > 0 then
		if not MF.VisibleGauntlets.Save() then
			Game.ShowStatusText("Paperdoll: can't write Visible gauntlets.txt")
			return
		end
		GauntletsChanged = 0
		parts[#parts + 1] = "gauntlet positions"
	end
	Game.ShowStatusText("Paperdoll: saved " .. table.concat(parts, " and "))
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
