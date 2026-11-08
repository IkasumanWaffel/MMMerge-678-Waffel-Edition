--[[
	MMMWE_PaperdollTuner.lua — place worn items on the paperdoll by hand and save the result

	The paperdoll position of body armor, helms, belts, boots and cloaks comes from
	Data/Tables/Complex item pictures.txt: an X, Y pair per item for each doll type
	(t0..t5, Character doll types.txt). Visible gauntlets (VisibleGauntletsRefactored.lua)
	take theirs from Data/Tables/Visible gauntlets.txt: X, Y per doll type and hand pose.

	Weapons (06.11.26): the right hand weapon, the left hand item and the bow are placed by
	the item's Equip X / Equip Y (Items.txt), the same for every doll type and for both
	hands. A pistol in the left hand is drawn turned (MMMWE_Blasters.lua) and has its own
	offset instead (BlasterSpecs.OffhandIconOffset). Both are kept in
	Data/Tables/Weapon positions.txt, which is applied at every start, over Items.txt.

	On the character screen, for the current character's doll type:
	  Ctrl + arrows            move the selected item 1 pixel (Ctrl + Shift: 5 pixels)
	  Ctrl + PageUp/PageDown   select armor / helm / belt / boots / cloak /
	                           right gauntlet / left gauntlet / right hand weapon /
	                           left hand / bow
	  Ctrl + S                 write the moved positions: armor pieces into Complex item
	                           pictures.txt (the first save keeps the old file as
	                           "...txt.bak"), gauntlets into Visible gauntlets.txt,
	                           weapons into Weapon positions.txt
	A gauntlet moves the pose shown right now (empty hand, weapon, open hand), for that
	gauntlet and doll type only; equip or remove weapons to reach the other poses.
	The status line shows the item, doll type and position after every key.
	Moves take effect at once but are lost on exit unless saved.
--]]

local MF = Merge.Functions
local Tx, Tn, TxN = Merge.Functions.Text, Merge.Functions.TextKey, Merge.Functions.TextN
local K = const.Keys

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local ENABLED = true
local FILE    = "Data/Tables/Complex item pictures.txt"
local WEAPON_FILE = "Data/Tables/Weapon positions.txt"
local BIG_STEP = 5

-- {player slot field, name, gauntlet side, weapon: "R" right hand / bow, "L" left hand}
local SLOTS = {
	{"ItemArmor", "Armor"}, {"ItemHelm", "Helm"}, {"ItemBelt", "Belt"},
	{"ItemBoots", "Boots"}, {"ItemCloak", "Cloak"},
	{"ItemGountlets", Tx"Right gauntlet", "R"}, {"ItemGountlets", Tx"Left gauntlet", "L"},
	{"ItemMainHand", Tx"Right hand", nil, "R"}, {"ItemExtraHand", Tx"Left hand", nil, "L"},
	{"ItemBow", "Bow", nil, "R"},
}

---------------------------------------------------------------------------
-- weapon positions: [item id] = {X, Y, LeftX, LeftY} (Equip X / Y, and the turned left-hand
-- icon's offset; nil where not set)
---------------------------------------------------------------------------

local WeaponPos = {}
local WeaponsChanged = 0

local function offhandOffsets()
	return MF.BlasterSpecs and MF.BlasterSpecs.OffhandIconOffset
end

local function loadWeaponPositions()
	local f = io.open(WEAPON_FILE, "r")
	if not f then return end
	local n = 0
	for line in f:lines() do
		local w = line:gsub("\r$", ""):split("\t")
		local id = tonumber(w[1])
		if id and id > 0 and id <= Game.ItemsTxt.high then
			local t = {tonumber(w[3]), tonumber(w[4]), tonumber(w[5]), tonumber(w[6])}
			WeaponPos[id] = t
			local txt = Game.ItemsTxt[id]
			if t[1] and t[2] then txt.EquipX, txt.EquipY = t[1], t[2] end
			local off = offhandOffsets()
			if t[3] and t[4] and off and off[id] then off[id] = {t[3], t[4]} end
			n = n + 1
		end
	end
	f:close()
	if n > 0 and MF.LogInfo then MF.LogInfo("[PaperdollTuner] %d weapon positions from %s", n, WEAPON_FILE) end
end

-- applied at every start, whether the tuner is on or not
function events.GameInitialized2()
	loadWeaponPositions()
end

local function saveWeapons()
	local ids = {}
	for id in pairs(WeaponPos) do ids[#ids + 1] = id end
	table.sort(ids)
	local out = {"Id\tName\tEquipX\tEquipY\tLeftX\tLeftY"}
	for _, id in ipairs(ids) do
		local t = WeaponPos[id]
		local function v(x) return x and tostring(x) or "" end
		out[#out + 1] = table.concat({id, Game.ItemsTxt[id].Name, v(t[1]), v(t[2]), v(t[3]), v(t[4])}, "\t")
	end
	local f = io.open(WEAPON_FILE, "wb")
	if not f then return end
	f:write(table.concat(out, "\r\n") .. "\r\n")
	f:close()
	WeaponsChanged = 0
	return #ids
end

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
	local hand = SLOTS[slot][4]
	if hand then
		-- shown on screen as + right / + down: the game draws at base - Equip X / Y
		local off = offhandOffsets()
		if hand == "L" and off and off[id] then
			return id, {X = off[id][1], Y = off[id][2], Kind = "offset"}, dt
		end
		local txt = Game.ItemsTxt[id]
		return id, {X = -txt.EquipX, Y = -txt.EquipY, Kind = "equip"}, dt
	end
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
	local n = ChangedCount + GauntletsChanged + WeaponsChanged
	return n > 0 and string.format(Tx"  (%d unsaved)", n) or ""
end

local function show()
	local id, c, dt, pose = selected()
	local what = SLOTS[slot][2]
	if not id then
		Game.ShowStatusText(what .. Tx": nothing worn")
	elseif not c then
		Game.ShowStatusText(string.format(Tx"%s: %s has no paperdoll position", what, Game.ItemsTxt[id].Name))
	else
		local note = ""
		if c.Kind == "equip" then
			note = Tx", all doll types and both hands"
		elseif c.Kind == "offset" then
			note = Tx", turned left-hand icon"
		end
		Game.ShowStatusText(string.format(Tx"%s %d%s, doll type %d: X %d, Y %d%s%s", Game.ItemsTxt[id].Name, id,
			pose and (" " .. pose) or "", dt, c.X, c.Y, note, unsaved()))
	end
end

local function move(dx, dy)
	local id, c, dt, pose = selected()
	if not c then show() return end
	if c.Kind then
		local t = WeaponPos[id] or {}
		WeaponPos[id] = t
		if c.Kind == "offset" then
			local off = offhandOffsets()
			off[id] = {c.X + dx, c.Y + dy}
			t[3], t[4] = off[id][1], off[id][2]
		else
			local txt = Game.ItemsTxt[id]
			txt.EquipX, txt.EquipY = txt.EquipX - dx, txt.EquipY - dy
			t[1], t[2] = txt.EquipX, txt.EquipY
		end
		WeaponsChanged = WeaponsChanged + 1
	elseif pose then
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
		Game.ShowStatusText(Tx"Paperdoll: can't read " .. FILE)
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
		Game.ShowStatusText(Tx"Paperdoll: can't write " .. FILE)
		return
	end
	Changed, ChangedCount = {}, 0
	return written
end

local function save()
	if ChangedCount + GauntletsChanged + WeaponsChanged == 0 then
		Game.ShowStatusText(Tx"Paperdoll: nothing to save")
		return
	end
	local parts = {}
	if ChangedCount > 0 then
		local n = saveArmor()
		if not n then return end
		parts[#parts + 1] = string.format(TxN(n, "%d armor position", "%d armor positions"), n)
	end
	if GauntletsChanged > 0 then
		if not MF.VisibleGauntlets.Save() then
			Game.ShowStatusText("Paperdoll: can't write Visible gauntlets.txt")
			return
		end
		GauntletsChanged = 0
		parts[#parts + 1] = Tx"gauntlet positions"
	end
	if WeaponsChanged > 0 then
		local n = saveWeapons()
		if not n then
			Game.ShowStatusText(Tx"Paperdoll: can't write " .. WEAPON_FILE)
			return
		end
		parts[#parts + 1] = string.format(TxN(n, "%d weapon position", "%d weapon positions"), n)
	end
	Game.ShowStatusText(Tx"Paperdoll: saved " .. table.concat(parts, " and "))
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
