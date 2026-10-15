-- Visible Gauntlets - mini-mod
--[[
	Draws worn gauntlets over the paperdoll hands. Each gauntlet needs one bitmap per doll
	type and hand pose, named <item id>v<doll type + 1><pose>, e.g. 600v2RHd:
	  RHd  right hand, empty          RHu  right hand holding a weapon
	  LHd  left hand, empty           LHu  left hand holding a weapon
	  LHo  left hand open (two-handed weapon in the right hand)

	Screen positions (640x480) come from Data/Tables/Visible gauntlets.txt:
	  Item  Doll type  Pose  X  Y
	Item 0 rows are the defaults for every gauntlet; rows with an item id override them for
	that item. The table is created from the built-in defaults if it is missing.
	MMMWE_PaperdollTuner.lua moves the shown gauntlets (Ctrl + PageUp/PageDown to select
	them) and saves item rows here.
--]]
local MF, MM = Merge.Functions, Merge.ModSettings
if not MM.Scripts or not MF.GtSettingNum(MM.Scripts.EnableVisibleGauntlets, 0) then
	return
end

local TABLE_FILE = "Data/Tables/Visible gauntlets.txt"
local POSES = {"RHd", "RHu", "LHd", "LHu", "LHo"}

-- built-in defaults [doll type][pose] = {X, Y}, used to create the table
local DEFAULTS = {
	[0] = {RHd = {492, 170}, RHu = {493, 139}, LHd = {598, 167}, LHu = {598, 167}, LHo = {598, 167}}, -- man
	[1] = {RHd = {491, 177}, RHu = {508, 158}, LHd = {589, 186}, LHu = {589, 187}, LHo = {580, 191}}, -- woman
	[2] = {RHd = {483, 185}, RHu = {477, 189}, LHd = {587, 206}, LHu = {588, 205}, LHo = {588, 209}}, -- minotaur
	[3] = {RHd = {490, 155}, RHu = {508, 163}, LHd = {592, 170}, LHu = {594, 169}, LHo = {582, 169}}, -- troll
	[4] = {RHd = {0, 0},     RHu = {0, 0},     LHd = {0, 0},     LHu = {0, 0},     LHo = {0, 0}},     -- MM6 dolls (portraits 61..66): to be placed
	[5] = {RHd = {0, 0},     RHu = {0, 0},     LHd = {0, 0},     LHu = {0, 0},     LHo = {0, 0}},     -- dragon (no gauntlets)
}

---------------------------------------------------------------------------
-- position table
---------------------------------------------------------------------------

local Pos = {}   -- [item][doll][pose] = {X, Y}

local function setPos(item, doll, pose, x, y)
	Pos[item] = Pos[item] or {}
	Pos[item][doll] = Pos[item][doll] or {}
	Pos[item][doll][pose] = {x, y}
end

-- X, Y of item's pose on doll, and whether the item has its own row
local function getPos(item, doll, pose)
	local own = Pos[item] and Pos[item][doll] and Pos[item][doll][pose]
	if own then return own[1], own[2], true end
	local def = Pos[0] and Pos[0][doll] and Pos[0][doll][pose]
	if def then return def[1], def[2], false end
	return 0, 0, false
end

local function saveTable()
	local f = io.open(TABLE_FILE, "w")
	if not f then return false end
	f:write("Item\tDoll type\tPose\tX\tY\tNotes\n")
	local items = {}
	for item in pairs(Pos) do items[#items + 1] = item end
	table.sort(items)
	for _, item in ipairs(items) do
		local dolls = {}
		for doll in pairs(Pos[item]) do dolls[#dolls + 1] = doll end
		table.sort(dolls)
		for _, doll in ipairs(dolls) do
			for _, pose in ipairs(POSES) do
				local p = Pos[item][doll][pose]
				if p then
					local note = item == 0 and "default" or (Game.ItemsTxt[item] and Game.ItemsTxt[item].Name or "")
					f:write(string.format("%d\t%d\t%s\t%d\t%d\t%s\n", item, doll, pose, p[1], p[2], note))
				end
			end
		end
	end
	f:close()
	return true
end

local function loadTable()
	local f = io.open(TABLE_FILE, "r")
	if not f then
		for doll, poses in pairs(DEFAULTS) do
			for pose, p in pairs(poses) do setPos(0, doll, pose, p[1], p[2]) end
		end
		saveTable()
		return
	end
	local first = true
	for line in f:lines() do
		if first then
			first = false
		else
			local w = line:gsub("\r$", ""):split("\t")
			local item, doll, x, y = tonumber(w[1]), tonumber(w[2]), tonumber(w[4]), tonumber(w[5])
			if item and doll and w[3] and x and y then setPos(item, doll, w[3], x, y) end
		end
	end
	f:close()
end

---------------------------------------------------------------------------

local function CurPlayer()
	return Game.Party[Game.CurrentPlayer]
end

local function CheckGautlets()
	return CurPlayer().ItemGountlets ~= 0
end

local function EquipStatOf(slot)
	local PL = CurPlayer()
	local idx = PL[slot]
	return idx ~= 0 and Game.ItemsTxt[PL.Items[idx].Number].EquipStat or nil
end

local function LeftWeaponEquiped()     return EquipStatOf("ItemExtraHand") == 0 end
local function RightWeaponEquiped()    return EquipStatOf("ItemMainHand") == 0 end
local function RightWeapon2HEquiped()  return EquipStatOf("ItemMainHand") == 1 end

local Conditions = {
	RHd = function() return CurPlayer().ItemMainHand == 0 end,
	RHu = function() return RightWeaponEquiped() or RightWeapon2HEquiped() end,
	LHd = function() return CurPlayer().ItemExtraHand == 0 and not RightWeapon2HEquiped() end,
	LHu = function() return LeftWeaponEquiped() end,
	LHo = function() return RightWeapon2HEquiped() end,
}

local loupeActive = false

function events.GameInitialized2()

	loadTable()

	local function actLupa()
		loupeActive = mem.u4[0x523040] > 0
	end

	local Gauntlets = {}

	-- Icon names will be used for handler's key generation, even though these icons do not exist.
	for _, pose in ipairs(POSES) do
		local cond = Conditions[pose]
		Gauntlets[pose] = CustomUI.CreateIcon{
			Icon = pose,
			X = 0,
			Y = 0,
			Condition = function(v) return CheckGautlets() and cond() end,
			Layer = 4,
			Screen = 7,
			NoPending = true,
			Masked = true}
	end

	local loupeButton = CustomUI.CreateButton{
							IconUp = "MAGNIF-B",
							IconDown = "MAGNIF-B",
							IconMouseOver = "MAGNIF-A",
							X = 603,
							Y = 299,
							Action = actLupa,
							Layer = 1,
							Screen = 7,
							Width = 75,
							Height = 26,
							Masked = true}

	local function apply(ItemId, DollId, Active)
		for k, v in pairs(Gauntlets) do
			v.Active = Active
			if Active then
				v.MainIcon = tostring(ItemId) .. "v" .. (DollId + 1) .. k -- icon name template, current: 000v1RHd - item id + "v" + doll type + key
				v.X, v.Y = getPos(ItemId, DollId, k)
			end
		end
	end

	function events.LoadInventoryPics(PL)
		local Active = PL.ItemGountlets ~= 0
		loupeActive = mem.u4[0x523040] > 0
		apply(Active and PL.Items[PL.ItemGountlets].Number or 0, Game.CharacterPortraits[PL.Face].DollType, Active)
	end

	function events.CanWearItem(t)
		if t.Available and Game.ItemsTxt[t.ItemId].EquipStat == 8 then
			apply(t.ItemId, Game.CharacterPortraits[t.Player.Face].DollType, true)
		end
	end

	-- for MMMWE_PaperdollTuner.lua
	MF.VisibleGauntlets = {
		Poses = POSES,
		Get = getPos,
		-- the pose shown for side "R" or "L" of the current character
		ShownPose = function(side)
			if not CheckGautlets() then return nil end
			for _, pose in ipairs(POSES) do
				if pose:sub(1, 1) == side and Conditions[pose]() then return pose end
			end
		end,
		-- set item's own position and show it at once
		Set = function(item, doll, pose, x, y)
			setPos(item, doll, pose, x, y)
			local v = Gauntlets[pose]
			if v and v.MainIcon == tostring(item) .. "v" .. (doll + 1) .. pose then v.X, v.Y = x, y end
		end,
		Save = saveTable,
	}

end
