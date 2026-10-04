local LogId = "ExtraQuickSpells"
local MF = Merge.Functions
MF.LogInit1(LogId)
local MO, MT = Merge.Offsets, Merge.Tables
MT.ExtraKeyBinds = MT.ExtraKeyBinds or {}

ExtraQuickSpells = {}
ExtraQuickSpells.SlotsAmount = 4

local function CurrentPlayer()
	return math.min(math.max(Game.CurrentPlayer, 0), Party.count - 1)
end

local function NewSpellSlots()
	local SpellSlots = {}
	for PlayerId, Player in Party.PlayersArray do
		SpellSlots[PlayerId] = {}
		for i = 1, ExtraQuickSpells.SlotsAmount do
			SpellSlots[PlayerId][i] = 0
		end
	end
	return SpellSlots
end
ExtraQuickSpells.NewSpellSlots = NewSpellSlots
ExtraQuickSpells.SpellSlots = NewSpellSlots()
	
	-- Ignore "Not enough spell points" message and perform standard attack
	mem.autohook(0x4262d9, function(d)
		if d.edx < 0 then				-- if SP after cast attempt is less than 0
			mem.nop(0x4262e2)			-- ignore status text message print
			DoGameAction(23,0,0)		-- perform attack
			---- switch pointer to the next Party member
			if Game.CurrentPlayer >= Party.count-1 then
				Game.CurrentPlayer = 0
			else
				Game.CurrentPlayer = Game.CurrentPlayer + 1
			end
		end
	end)

local function CastSlotSpell(SlotNumber)
	if Game.Paused or Game.CurrentScreen ~= 0 then
		return
	end

	if Game.TurnBasedPhase == 3 then
		-- perform standart attack
		DoGameAction(23,0,0)
		return
	end

	local party_slot = MF.GetCurrentPlayer()
	if not party_slot then
		return
	end

	--local SpellSlots = ExtraQuickSpells.SpellSlots
	Party[party_slot].Attrs.ExtraQuickSpells = Party[party_slot].Attrs.ExtraQuickSpells or {}
	local SpellSlots = Party[party_slot].Attrs.ExtraQuickSpells
	local Player = Party[Game.CurrentPlayer]
	local PlayerId = Party.PlayersIndexes[Game.CurrentPlayer]
	--local SpellId = SpellSlots[PlayerId][SlotNumber] or 0
	local SpellId = SpellSlots[SlotNumber] or 0
	
	if vars.ManaCost == nil then vars.ManaCost = 0 end
	-- check for basic spell cost, despite player's mastery, because only spell with different cost by mastery is wizard eye, rest have same.
	if SpellId == 0 or Player.SP < vars.ManaCost --ManaCost
			or mem.call(MO.CanPlayerCastSpell, 2, Player["?ptr"], SpellId, 3) == 0 then
		-- perform standart attack
		DoGameAction(23,0,0)
	elseif Player.RecoveryDelay > 0 then
		if Game.CurrentPlayer >= Party.count-1 then
			Game.CurrentPlayer = 0
		else
			Game.CurrentPlayer = Game.CurrentPlayer + 1
		end
	else
		CastQuickSpell(Game.CurrentPlayer, SpellId)	-- from HardcodedTopicFunctions.lua
		NWS = {1, 2, 5, 6, 8, 9, 10, 11, 12, 13, 15, 16, 17, 18, 19, 20, 22, 23, 24, 26, 29, 32, 34, 35, 37, 38, 39, 41, 43, 45, 48, 50, 51, 52, 54, 59, 60, 63, 65, 70,73, 75, 76, 77, 78, 79, 80, 82, 83, 84, 85, 86, 87, 88, 90, 92, 93, 95, 96, 97, 98, 103, 111, 112, 113, 114, 122, 123, 125} 
		if table.find(NWS, SpellId) and SlotNumber > 0 then
		Player.SP = Player.SP - vars.ManaCost
		end 
	end
end

local function SetSlotSpell(PartySlot, SlotNumber, SpellId)
	local PlayerId = Party.PlayersIndexes[PartySlot]
	--local SpellSlots = ExtraQuickSpells.SpellSlots
	Party[PartySlot].Attrs.ExtraQuickSpells = Party[PartySlot].Attrs.ExtraQuickSpells or {}
	local SpellSlots = Party[PartySlot].Attrs.ExtraQuickSpells
	--if SpellSlots[PlayerId][SlotNumber] == SpellId then
	if SpellSlots[SlotNumber] == SpellId then
		SpellSlots[SlotNumber] = 0
		Game.PlaySound(142)
	else
		SpellSlots[SlotNumber] = SpellId
		Party[CurrentPlayer()]:ShowFaceAnimation(const.FaceAnimation.SetQuickSpell)
	end
end

function GetSelectedSpellId()
	local PlayerId = Game.CurrentPlayer
	if PlayerId < 0 then
		return 0
	end

	local SpellId = mem.u4[0x517b1c]
	local SpellSchool = mem.u1[Party[PlayerId]["?ptr"] + 0x1c44]

	SpellId = SpellId + SpellSchool*11
	if SpellId > 0 and not Party[PlayerId].Spells[SpellId] then
		SpellId = 0
	end
	return SpellId
end

function ShowSlotSpellName(SlotNumber)
	local SpellId
	local CurPl = CurrentPlayer()
	if SlotNumber == 0 then -- original quick spell
		SpellId = Party[CurPl].QuickSpell
	else
		--local PlayerId = Party.PlayersIndexes[CurPl]
		--SpellId = ExtraQuickSpells.SpellSlots[PlayerId][SlotNumber] or 0
		SpellId = Party[CurPl].Attrs.ExtraQuickSpells[SlotNumber] or 0
	end

	if SpellId == 0 then
		Game.ShowStatusText(Game.GlobalTxt[72])
	else
		Game.ShowStatusText(Game.SpellsTxt[SpellId].Name)
	end
end

local KeyTexts = {}
local function UpdateKeyTexts()
	for i,v in pairs(KeyTexts) do
		local key_name = table.find(const.Keys, MT.ExtraKeyBinds[v.RegKey].Key)
		local label = v.Label
		label.Text = (" %s"):format(key_name or "")
		label.X = 17 - (#label.Text - 2) * 4
		label:UpdateSize()
	end
end

function events.LoadMapScripts(WasInGame)
	if not WasInGame then
		UpdateKeyTexts()
	end
end

events.ExitExtraSettingsMenu = UpdateKeyTexts

function events.GameInitialized2()

	-- new quick spell buttons
	local baseY = 330

	for i = 1, ExtraQuickSpells.SlotsAmount do
		CustomUI.CreateButton{
			IconUp = "stssu",
			IconDown = "stssd",
			Screen = 8,
			Layer = 1,
			DynLoad = true,
			X =	0,
			Y =	baseY - i*50,
			Masked = true,
			Action = function() SetSlotSpell(CurrentPlayer(), i, GetSelectedSpellId()) end,
			MouseOverAction = function() ShowSlotSpellName(i) end
		}

		-- slot number
		local label = CustomUI.CreateText{
			Key = "QSSlotNum_" .. i,
			AlignLeft = true,
			Font =  Game.Smallnum_fnt,
			ColorStd = 1,
			ColorShadow = RGB(255, 255, 255),
			Screen = 8,
			Layer = 0,
			X = 17,
			Y = baseY + 2 - i*50,
			Text = " " .. tostring(i)}

		KeyTexts[i] = {RegKey = KeyTexts[i], Label = label}
	end

	-- overlay for original button
	CustomUI.CreateButton{
			IconUp = "stssu",
			Screen = 8,
			Layer = 3,
			DynLoad = true,
			X =	0,
			Y =	380,
			Action = function() return true end,
			MouseOverAction = function() ShowSlotSpellName(0) end
		}
end

---- events ----
function events.KeyDown(t)
	if Game.Paused or Game.CurrentScreen ~= 0 then
		return
	end
	for k, v in ipairs(MT.ExtraKeyBinds) do
		if v.Key == t.Key then
			t.Handled = true
			if v.Action then
				MF.LogInfo("ExtraKeyBinds %d action: %s", k, v.Label)
				v.Action()
			end
			return
		end
	end
end

---- Registry keys ----

local function SetRegistryValue(Key, Value)
	Game.TextBuffer2 = Key
	mem.call(0x46306B, 2, 0x5E1020, Value)
end
MF.SetRegistryValue = SetRegistryValue

local function GetRegistryValue(Key, Default)
	Game.TextBuffer2 = Key
	return mem.call(0x462D28, 2, 0x5E1020, Default)
end
MF.GetRegistryValue = GetRegistryValue
--[[
local function register_extra_key_bind(t)
	local reg_val
	MT.ExtraKeyBinds = MT.ExtraKeyBinds or {}
	-- Check player key binds
	if t.DefKey > 0x30 and t.DefKey < 0x36 then
		t.DefKey = 0
	end
	-- Check standard game key binds
	for i = 0, 29 do
		if t.DefKey == Game.KeyCodes[i] then
			t.DefKey = 0
		end
	end
	-- Check already present extra key binds
	for k, v in pairs(MT.ExtraKeyBinds) do
		if t.DefKey == v.Key then
			t.DefKey = 0
		end
	end
	-- Read or Create registry value
	if t.RegValue then
		Game.TextBuffer2 = t.RegValue
		t.Key = mem.call(0x462D28, 2, 0x5E1020, t.DefKey)
		reg_val = t.Key
	else
		t.Key = t.DefKey
		reg_val = t.Key
	end
	-- Check keybinds again if Key isn't default
	if t.Key ~= t.DefKey and t.Key ~= 0 then
		-- Check player key binds
		if t.Key > 0x30 and t.Key < 0x36 then
			t.Key = 0
		end
		-- Check standard game key binds
		for i = 0, 29 do
			if t.Key == Game.KeyCodes[i] then
				t.Key = 0
			end
		end
		-- Check already present extra key binds
		for k, v in pairs(MT.ExtraKeyBinds) do
			if t.Key == v.Key then
				t.Key = 0
			end
		end
	end
	-- Update registry value if Key was changed
	if reg_val ~= t.Key then
		Game.TextBuffer2 = t.RegValue
		mem.call(0x46306B, 2, 0x5E1020, t.Key)
	end
	table.insert(MT.ExtraKeyBinds, t)
end
MF.RegisterExtraKeyBind = register_extra_key_bind
]]
--[[
local function update_extra_key_bind(Id, Key)
	MT.ExtraKeyBinds[Id].Key = Key
	Game.TextBuffer2 = MT.ExtraKeyBinds[Id].RegValue
	mem.call(0x46306B, 2, 0x5E1020, Key)
end
]]
-----

 --[[ {Key, DefKey, RegValue, Label, Action}
	Key = number - const.Keys
	DefKey = number - default key - const.Keys
	RegValue = string - registry label
	Label = hotkey label in the UI
	Action = function - code to execute, when hotkey pressed
 ]]
local function register_extra_key_bind(t)
	local function check_keybinds(key)
		-- Check player key binds
		if key > 0x30 and key < 0x36 then
			return 0
		end
		-- Check standard game key binds
		for i = 0, 29 do
			if key == Game.KeyCodes[i] then
				return 0
			end
		end
		-- Check already present extra key binds
		for k, v in pairs(MT.ExtraKeyBinds) do
			if key == v.Key then
				return 0
			end
		end
		return key
	end

	local reg_val

	t.DefKey = check_keybinds(t.DefKey)

	-- Read or Create registry value
	if t.RegValue then
		t.Key = GetRegistryValue(t.RegValue, t.DefKey)
		reg_val = t.Key
	else
		t.Key = t.DefKey
		reg_val = t.Key
	end

	-- Check keybinds again if Key isn't default
	if t.Key ~= t.DefKey and t.Key ~= 0 then
		t.Key = check_keybinds(t.Key)
	end

	-- Update registry value if Key was changed
	if reg_val ~= t.Key then
		SetRegistryValue(t.RegValue, t.Key)
	end
	table.insert(MT.ExtraKeyBinds, t)

	return #MT.ExtraKeyBinds
end
MF.RegisterExtraKeyBind = register_extra_key_bind

local function update_extra_key_bind(Id, Key)
	MT.ExtraKeyBinds[Id].Key = Key
	SetRegistryValue(MT.ExtraKeyBinds[Id].RegValue, Key)
end
MF.UpdateExtraKeyBind = update_extra_key_bind

for i = 1, math.min(ExtraQuickSpells.SlotsAmount, 4) do
	KeyTexts[i] = MF.RegisterExtraKeyBind({DefKey = 115 + i, RegValue = "xkey_qspell" .. i,
		Label = string.format("Q. SPELL %d", i),
		Action = function() CastSlotSpell(i) end})
end
for i = 5, ExtraQuickSpells.SlotsAmount do
	KeyTexts[i] = MF.RegisterExtraKeyBind({DefKey = 0, RegValue = "xkey_qspell" .. i,
		Label = string.format("Q. SPELL %d", i),
		Action = function() CastSlotSpell(i) end})
end
--[[
for i = 1, math.min(ExtraQuickSpells.SlotsAmount, 4) do
	MF.RegisterExtraKeyBind({DefKey = 115 + i, RegValue = "xkey_qspell" .. i,
		Label = string.format("Q. SPELL %d", i),
		Action = function() CastSlotSpell(i) end})
end
for i = 5, ExtraQuickSpells.SlotsAmount do
	MF.RegisterExtraKeyBind({DefKey = 0, RegValue = "xkey_qspell" .. i,
		Label = string.format("Q. SPELL %d", i),
		Action = function() CastSlotSpell(i) end})
end
]]
---- Extra settings menu ----

function events.GameInitialized2()

	local keys_per_column = 5
	local key_labels = {}
	local selection = 0
	local offset = 0
	local ExSetScrKeys = CustomUI.NewSettingsPage("ExtraKeybinds", " Keybinds")

	function events.ExitExtraSettingsMenu()
		if selection and selection ~= 0 then
			key_labels[selection].Label.CStd = 0xFFFF -- white
			selection = 0
		end
	end

	local NOKEY = "-NO KEY-"

	local function choose_key_start(i)
		if selection ~= 0 then
			return
		else
			selection = i
			key_labels[i].Label.CStd = 0xE664 -- gold
		end
	end

	local function choose_key_finish(key)
		--if not SelectionStarted then return end
		if selection == 0 then return end
		-- Check player key binds
		if key > 0x30 and key < 0x36 then
			key = 0
		end
		-- Check standard game key binds
		for i = 0, 29 do
			if key == Game.KeyCodes[i] then
				key = 0
			end
		end
		if key ~= 0 then
			-- Set other extra key binds with the same key to nokey
			for k, v in ipairs(MT.ExtraKeyBinds) do
				if key == v.Key then
					v.Key = 0
					if k > offset and k <= offset + 2 * keys_per_column then
						key_labels[k - offset].KeyText.Text = NOKEY
						key_labels[k - offset].KeyText:UpdateSize()
					end
				end
			end
		end
		MF.UpdateExtraKeyBind(offset + selection, key)
		local key_name = table.find(const.Keys, key)
		local label = key_labels[selection]
		label.KeyText.Text = key_name or NOKEY
		label.KeyText:UpdateSize()
		label.Label.CStd = 0xFFFF -- white
		selection = 0
	end
	local function update_keybinds_labels()
		for i = 1, math.min(2 * keys_per_column, table.getn(MT.ExtraKeyBinds) - offset) do
			local key_name = table.find(const.Keys, MT.ExtraKeyBinds[offset + i].Key)
			local label = key_labels[i]
			label.Label.Text = MT.ExtraKeyBinds[offset + i].Label
			label.KeyText.Text = key_name or NOKEY
			label.KeyText:UpdateSize()
		end
	end

	-- background
	CustomUI.CreateIcon{
		Icon = "ExSetScrK",
		X = 0,
		Y = 0,
		Layer = 1,
		DynLoad = true,
		--[[
		Condition = function()
				if Keys.IsPressed(const.Keys.RETURN) then
					if selection and selection ~= 0 then
					--if SelectionStarted then
						--SelectionStarted = false
						key_labels[selection].Label.CStd = 0xFFFF -- white
						--ActiveText = nil
						selection = nil
					end
				elseif Keys.IsPressed(const.Keys.ESCAPE)
						and (not selection or selection == 0) then
					CustomUI.ExitExtraSettingsMenu()
				end
				return true
			end,
		]]
		BlockBG = true,
		Screen = ExSetScrKeys}

	for i = 1, math.min(2 * keys_per_column, table.getn(MT.ExtraKeyBinds) - offset) do
		Log(Merge.Log.Info, "keys: (%d) %d", i, MT.ExtraKeyBinds[offset + i].Key)
		local x, y
		key_labels[i] = {}
		if i <= keys_per_column then
			x = 107
			y = 193 + i * 28
		else
			x = 334
			y = 193 + (i - keys_per_column) * 28
		end
		key_labels[i].Label =  CustomUI.CreateText{
			Text = MT.ExtraKeyBinds[offset + i].Label,
			X = x, Y = y,
			AlignLeft = true,
			Action = function() choose_key_start(i) end,
			Layer = 0,
			Screen = ExSetScrKeys,
			Font = Game.Lucida_fnt
		}
		local key_name = table.find(const.Keys, MT.ExtraKeyBinds[offset + i].Key)
		key_labels[i].KeyText = CustomUI.CreateText{
			Text = key_name or NOKEY,
			X = x + 110, Y = y,
			AlignLeft = true,
			Layer = 0,
			Screen = ExSetScrKeys,
			Font = Game.Lucida_fnt
		}
	end

	-- register new keybinds
	function events.KeyDown(t)
		--if Game.CurrentScreen == ExSetScrKeys and selection and selection ~= 0 then
		--	choose_key_finish(t.Key)
		--end
		if Game.CurrentScreen ~= ExSetScrKeys then
			return
		end

		if selection == 0 then
			if t.Key == const.Keys.ESCAPE then
				CustomUI.ExitExtraSettingsMenu()
			end
		else
			if t.Key == const.Keys.ESCAPE then
				choose_key_finish(0)
			elseif t.Key == const.Keys.RETURN then
				choose_key_finish(MT.ExtraKeyBinds[selection + offset].Key)
			else
				choose_key_finish(t.Key)
			end
		end

		t.Handled = true
	end

	-- save/load
	--[[
	local function SaveQSlots()
		vars.ExtraSettings = vars.ExtraSettings or {}
		vars.ExtraSettings.SpellSlots = ExtraQuickSpells.SpellSlots
	end

	local function LoadQSlots()
		vars.ExtraSettings = vars.ExtraSettings or {}
		ExtraQuickSpells.SpellSlots = vars.ExtraSettings.SpellSlots or ExtraQuickSpells.NewSpellSlots()
	end

	function events.BeforeSaveGame()
		SaveQSlots()
	end

	function events.LoadMapScripts(WasInGame)
		if not WasInGame then
			LoadQSlots()
		end
	end
	]]
end

MF.LogInit2(LogId)

