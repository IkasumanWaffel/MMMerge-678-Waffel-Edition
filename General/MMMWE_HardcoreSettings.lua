--[[
	MMMWE_HardcoreSettings.lua — "Hardcore mode" page of the Extra Settings menu

	  * Hardcore mode button with the confirmation dialog (moved here from the
	    "Interface settings" page, MenuControls.lua).
	  * Party deaths allowed: how many total party kills end the game. 1 = classic hardcore
	    (the first party death removes all save files). With more than 1, every party death
	    before the last one costs the party its belongings: everything carried and worn is
	    removed except special items, artifacts, relics and ancient items (and quest items,
	    see Global/MMMWE_HardcoreMode.lua).
	  * The limit can only be changed while Hardcore mode is off, so it can't be raised
	    in the middle of a hardcore run. Turning Hardcore mode on resets the death counter.

	  * Experience curve: how steeply the experience needed per level grows. Going from level
	    L to L + 1 takes 1000 x L^curve experience; 1.00 is the game's own table (level 50
	    needs 1,225,000 in all). Above 1 the high levels take longer, below 1 they come
	    sooner. Like the death limit it can only be changed while Hardcore mode is off.
	    The game's function for the experience of a level (0x4B30EF, used by training, the
	    character screen and the level-up popup) reads a table built from the curve.

	Saved with the game: vars.HardCoreMode, vars.HCMDeathLimit, vars.HCMDeaths, vars.ExpCurve.
	The death handling itself is in Global/MMMWE_HardcoreMode.lua.
--]]

local MV = Merge.Vars

local MAX_DEATHS = 10

-- experience curve: the exponent of the experience needed per level
local EXP_CURVE_MIN, EXP_CURVE_MAX, EXP_CURVE_STEP = 0.80, 1.50, 0.05
local EXP_TABLE_LEVELS = 5000   -- levels in the table; above it the game's own formula

local DialogShown = false

-- 'vars' (the savegame data) only exists once a game is started or loaded: it is nil while
-- the scripts load and during GameInitialized2, which run at the main menu. Everything here
-- reads it through V(), and writes only happen while a game is running.
local Empty = {}
local function V()       return vars or Empty end
local function HasGame() return vars ~= nil end

local function Deaths()  return V().HCMDeaths or 0 end
local function Limit()   return V().HCMDeathLimit or 1 end
local function IsOn()    return V().HardCoreMode == 1 end

---- Hardcore lock
-- Once Hardcore mode is turned on it can't be turned off for this party. The lock is tied to
-- the first character (Party[0]), the only member who can't be dismissed or replaced in a
-- normal game: vars.HCMLock = {Index = roster index, Name = name} of that character.
-- While Party[0] matches the lock, Hardcore mode stays on (it is switched back on after
-- loading even if vars.HardCoreMode was changed from the console).
local function LeaderId()
	local pl = Party[0]
	return pl and {Index = pl:GetIndex(), Name = pl.Name}
end

local function IsLocked()
	local lock = V().HCMLock
	if not (HasGame() and lock) then
		return false
	end
	local id = LeaderId()
	return id ~= nil and id.Index == lock.Index and id.Name == lock.Name
end

local function SetLock()
	vars.HCMLock = LeaderId()
end

-- Enforce the lock; also locks saves that had Hardcore mode on before the lock existed
local function EnforceLock()
	if not HasGame() then
		return
	end
	if IsLocked() then
		if vars.HardCoreMode ~= 1 then
			vars.HardCoreMode = 1
			MV.HCM = 1
		end
	elseif vars.HardCoreMode == 1 and not vars.HCMLock then
		SetLock()
	end
end
Merge.Functions.HCMIsLocked = IsLocked

---- Experience curve
local function Curve()
	local c = tonumber(V().ExpCurve) or 1
	return math.max(EXP_CURVE_MIN, math.min(EXP_CURVE_MAX, c))
end

-- experience needed to go from level 1 to level `level` with curve `c`
local function ExpForLevel(level, c)
	c = c or Curve()
	local total = 0
	for l = 1, level - 1 do
		total = total + math.floor(1000 * l ^ c + 0.5)
	end
	return total
end
Merge.Functions.ExpForLevel = function(level) return ExpForLevel(level) end

-- table of 64-bit values: [L] = experience to reach level L + 1 (the game's function gets
-- the current level in ecx and returns edx:eax)
local ExpTable = mem.StaticAlloc(EXP_TABLE_LEVELS * 8)
local TableCurve
local function BuildExpTable(c)
	c = c or Curve()
	if c == TableCurve then return end
	local total = 0
	mem.u4[ExpTable], mem.u4[ExpTable + 4] = 0, 0
	for l = 1, EXP_TABLE_LEVELS - 1 do
		total = total + math.floor(1000 * l ^ c + 0.5)
		local hi = math.floor(total / 4294967296)
		mem.u4[ExpTable + l * 8] = total - hi * 4294967296
		mem.u4[ExpTable + l * 8 + 4] = hi
	end
	TableCurve = c
end
BuildExpTable()

mem.asmpatch(0x4B30EF, ([[
	cmp ecx, %d
	jae @calc
	mov eax, [ecx * 8 + %d]
	mov edx, [ecx * 8 + %d]
	ret
@calc:
	xor eax, eax
	xor edx, edx
	test ecx, ecx
	jle @done
@loop:
	lea eax, [eax + edx + 1]
	inc edx
	cmp edx, ecx
	jl @loop
@done:
	jmp absolute 0x4B3100]]):format(EXP_TABLE_LEVELS, ExpTable, ExpTable + 4), 0x4B3100 - 0x4B30EF)

function events.LoadMap()
	BuildExpTable()
end

function events.LeaveGame()
	-- back to the game's own table at the main menu
	BuildExpTable(1)
end

local function Yellow(text)
	return StrColor(255, 255, 150) .. text .. StrColor(255, 255, 255)
end

local function LimitText()
	return tostring(Limit())
end

-- Same columns as the "Enchantment scaling" page: label | "<" | value | ">"
-- (COL_LEFT leaves room for "Party deaths allowed" in the italic Arrus font)
local COL_LABEL, COL_LEFT, COL_VALUE, COL_RIGHT = 80, 275, 295, 400
-- Texts that change after creation need a fixed box, otherwise the box keeps the size of the
-- initial text and longer text wraps word by word
local NOTE_W, VALUE_W, LINE_H = 470, 100, 16

function events.GameInitialized2()
	if not (CustomUI and CustomUI.NewSettingsPage) then
		return
	end
	local Screen = CustomUI.NewSettingsPage("MergeHardcoreSettings", "Hardcore mode", "ExSetScr2")
	local Hide = function() return not DialogShown end
	local UI = {}

	local function Text(t)
		t.Layer = t.Layer or 0
		t.Screen = Screen
		t.Font = t.Font or Game.Arrus_fnt
		t.ColorStd = t.ColorStd or 0xFFFF
		if t.AlignLeft == nil then t.AlignLeft = true end
		return CustomUI.CreateText(t)
	end

	-- refresh all texts / the button picture
	local function Refresh()
		UI.Button.IUpSrc = IsOn() and "hcm_on" or "hcm_off"
		UI.LimitValue.Text = LimitText()
		UI.LimitNote.Text = IsLocked() and "(Hardcore mode is locked for this party)"
			or IsOn() and "(locked while Hardcore mode is on)"
			or (Limit() == 1 and "(the first party death deletes all saves)" or " ")
		UI.DeathsValue.Text = tostring(Deaths()) .. (IsOn() and (" of " .. Limit()) or "")
		local strip = Limit() > 1
		UI.ItemsNote1.Text = strip and "Each party death before the last removes all items" or " "
		UI.ItemsNote2.Text = strip and "except special items, artifacts, relics and ancient items." or " "
		local c = Curve()
		local function M(v) return v >= 1e6 and string.format("%.1fM", v / 1e6) or string.format("%dk", math.floor(v / 1000 + 0.5)) end
		UI.CurveValue.Text = string.format("%.2f", c) .. (math.abs(c - 1) < 1e-9 and " (game)" or "")
		UI.CurveNote.Text = string.format("Level 50: %s exp, level 100: %s (game: %s, %s)",
			M(ExpForLevel(50, c)), M(ExpForLevel(100, c)), M(ExpForLevel(50, 1)), M(ExpForLevel(100, 1)))
		Game.NeedRedraw = true
	end

	---- Hardcore mode button
	UI.Button = CustomUI.CreateButton{
		IconUp        = IsOn() and "hcm_on" or "hcm_off",
		IconDown      = "hcm_ht",
		IconMouseOver = "hcm_ht",
		Action = function(t)
			if not HasGame() then return end
			if IsOn() and IsLocked() then
				Game.PlaySound(27)
				Game.ShowStatusText("Hardcore mode can't be turned off for this party")
				return
			end
			Game.PlaySound(23)
			if IsOn() then
				vars.HardCoreMode = 0
				MV.HCM = 0
				Refresh()
			else
				DialogShown = true
				Game.NeedRedraw = true
			end
		end,
		Condition = Hide,
		Layer = 0,
		Screen = Screen,
		X = 220, Y = 165,
		DynLoad = true,
	}

	---- Party deaths allowed
	Text{Text = Yellow("Party deaths allowed"), X = COL_LABEL, Y = 230, Condition = Hide}

	local function ChangeLimit(side)
		if IsOn() or not HasGame() then
			Game.PlaySound(27)   -- locked
			return
		end
		Game.PlaySound(side < 0 and 24 or 23)
		vars.HCMDeathLimit = math.max(1, math.min(MAX_DEATHS, Limit() + side))
		Refresh()
	end

	Text{Text = "<", X = COL_LEFT, Y = 230, ColorMouseOver = 0xe664, Condition = Hide,
		Action = function() ChangeLimit(-1) end}
	UI.LimitValue = Text{Text = LimitText(), X = COL_VALUE, Y = 230, Condition = Hide,
		Width = VALUE_W, Height = LINE_H}
	Text{Text = ">", X = COL_RIGHT, Y = 230, ColorMouseOver = 0xe664, Condition = Hide,
		Action = function() ChangeLimit(1) end}
	UI.LimitNote = Text{Text = " ", X = COL_LABEL, Y = 250, Condition = Hide,
		Width = NOTE_W, Height = LINE_H}

	Text{Text = Yellow("Party deaths so far"), X = COL_LABEL, Y = 280, Condition = Hide}
	UI.DeathsValue = Text{Text = " ", X = COL_VALUE, Y = 280, Condition = Hide,
		Width = VALUE_W, Height = LINE_H}

	UI.ItemsNote1 = Text{Text = " ", X = COL_LABEL, Y = 310, Condition = Hide,
		Width = NOTE_W, Height = LINE_H}
	UI.ItemsNote2 = Text{Text = " ", X = COL_LABEL, Y = 330, Condition = Hide,
		Width = NOTE_W, Height = LINE_H}

	---- Experience curve
	Text{Text = Yellow("Experience curve"), X = COL_LABEL, Y = 360, Condition = Hide}

	local function ChangeCurve(side)
		if IsOn() or not HasGame() then
			Game.PlaySound(27)   -- locked
			return
		end
		Game.PlaySound(side < 0 and 24 or 23)
		local c = Curve() + side * EXP_CURVE_STEP
		c = math.floor(c / EXP_CURVE_STEP + 0.5) * EXP_CURVE_STEP
		vars.ExpCurve = math.max(EXP_CURVE_MIN, math.min(EXP_CURVE_MAX, c))
		BuildExpTable()
		Refresh()
	end

	Text{Text = "<", X = COL_LEFT, Y = 360, ColorMouseOver = 0xe664, Condition = Hide,
		Action = function() ChangeCurve(-1) end}
	UI.CurveValue = Text{Text = " ", X = COL_VALUE, Y = 360, Condition = Hide,
		Width = VALUE_W, Height = LINE_H}
	Text{Text = ">", X = COL_RIGHT, Y = 360, ColorMouseOver = 0xe664, Condition = Hide,
		Action = function() ChangeCurve(1) end}
	UI.CurveNote = Text{Text = " ", X = COL_LABEL, Y = 380, Condition = Hide,
		Width = NOTE_W, Height = LINE_H}

	---- Confirmation dialog
	local function DialogText()
		local deaths = Limit() == 1
			and ("All save files " .. StrColor(255, 180, 32, "will be deleted ")
				.. "if the entire party is killed.\n\n")
			or ("All save files " .. StrColor(255, 180, 32, "will be deleted ")
				.. "after " .. Limit() .. " party deaths.\n"
				.. "Every party death before that "
				.. StrColor(255, 180, 32, "removes all items ")
				.. "except artifacts, relics, quest, special and ancient items.\n\n")
		return "HARDCORE MODE\n\n" ..
			"Saving, loading and quitting to main menu " ..
			StrColor(255, 180, 32, "are blocked ") .. "while enemies are nearby.\n" ..
			deaths ..
			StrColor(255, 180, 32, "It can't be turned off ") .. "for this party once enabled.\n" ..
			"\nEnable Hardcore Mode?"
	end

	UI.DialogText = CustomUI.CreateText{
		Text      = DialogText(),
		Layer     = 0,
		Screen    = Screen,
		X         = 200, Y = 160,
		Width     = 240, Height = 240,
		ColorStd  = RGB(255, 255, 255),
		ColorHigh = RGB(255, 255, 255),
		AlignLeft = false,
		Font      = Game.Smallnum_fnt,
		Condition = function() return DialogShown end,
	}

	CustomUI.CreateText{
		Text           = "Confirm",
		ColorStd       = RGB(255, 200, 50),
		ColorMouseOver = RGB(255, 255, 150),
		Action = function(t)
			DialogShown = false
			if not HasGame() then return end
			Game.PlaySound(23)
			vars.HardCoreMode = 1
			MV.HCM = 1
			vars.HCMDeaths = 0            -- a new hardcore run starts counting from zero
			SetLock()                     -- can't be turned off for this party any more
			Refresh()
		end,
		Layer     = 0,
		Screen    = Screen,
		X         = 240, Y = 360,
		Condition = function() return DialogShown end,
	}

	CustomUI.CreateText{
		Text           = "Cancel",
		ColorStd       = RGB(180, 180, 180),
		ColorMouseOver = RGB(255, 255, 150),
		Action = function(t)
			Game.PlaySound(24)
			DialogShown = false
			Game.NeedRedraw = true
		end,
		Layer     = 0,
		Screen    = Screen,
		X         = 340, Y = 360,
		Condition = function() return DialogShown end,
	}

	-- keep the dialog text in sync with the chosen limit
	local refresh = Refresh
	Refresh = function()
		refresh()
		UI.DialogText.Text = DialogText()
	end

	function events.OpenExtraSettingsMenu()
		DialogShown = false
		EnforceLock()
		Refresh()
	end
end

-- Message after a non-final party death (set by Global/MMMWE_HardcoreMode.lua)
function events.AfterLoadMap()
	local msg = vars and vars.HCMPendingMessage
	if msg then
		vars.HCMPendingMessage = nil
		coroutine.resume(coroutine.create(function()
			Sleep(1, 1)
			Game.EscMessage(msg)
		end))
	end
end

-- Re-apply the lock whenever a game is loaded or the map changes
function events.AfterLoadMap()
	EnforceLock()
end
