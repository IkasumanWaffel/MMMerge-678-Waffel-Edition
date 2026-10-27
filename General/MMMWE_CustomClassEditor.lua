--[[
	MMMWE_CustomClassEditor.lua — custom classes, stage 2: the points screen

	Design: "Waffel Edition design: custom classes" (Google Doc). The data and the point
	rules are in MMMWE_CustomClasses.lua.

	The editor is drawn over the current screen (CustomUI, layer 0) and blocks it while
	open:
	  party creation    "Custom..." on the creation screen builds a class for the
	                    character being made; the character takes it with Done
	  training halls    a Peasant (the selected character) gets "Become a custom class"
	                    in the hall's main menu; Done converts him (skills the class can't
	                    learn are refunded, as in CustomClass.Give)

	Screen:
	  Class: ...        click to switch between the game's custom classes and the new one
	  tabs              base, first promotion, second promotion neutral / light / dark
	  Name              click and type; Enter or Esc ends
	  HP / SP tiers     - and + ; "SP from" cycles Intellect, Personality, both
	  skills            click raises the cap, Ctrl+click lowers it, Shift+click (base tab)
	                    marks one of the two free starting skills (*)
	  Done / Cancel     Esc also cancels
	A class already taken by a character in the game is read-only in the training hall
	(it can still be taken as it is).
--]]

local MF = Merge.Functions

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local ENABLED       = true
local BACKGROUND    = "ExSetScr2"        -- 640x480 panel (mmmerge.icons.lod)
local PX, PY        = 76, 154            -- top left of the panel's content
local ENTRY_X, ENTRY_Y = 286, 440                -- "Custom" button (83x30) on the creation screen:
-- the bottom row, between the party slot 5 button (ends at 282, MenuChooseCharacter.lua)
-- and the game's Clear (373), Cancel (459) and OK (546) buttons
local ENTRY_ICONS = {"c_custom_up", "c_custom_DN", "c_custom_ht"}   -- up, down, hover (mmmerge.icons.lod)
local EXTRA_SKILLS  = 2                  -- skills the creation screen asks to pick on top
local START_SKILLS  = 2
local CREATION_SCREEN = 21
local MSG_TIME      = 4                  -- seconds a message stays in the bottom line

---------------------------------------------------------------------------

if not ENABLED then return end

local CC                                 -- MF.CustomClasses
local E = {Open = false}                 -- editor state
local Mine, Hidden = {}, {}
local WHITE, GREY, GOLD, RED, GREEN, HOVER

local function log(fmt, ...) if MF.LogInfo then MF.LogInfo("[CustomClassEditor] " .. fmt, ...) end end

local function shown()
	return E.Open and Game.CurrentScreen == E.Screen
end

local function fam()
	return E.F and CC.Builds()[E.F]
end

local function spec()
	local f = fam()
	return f and f.Steps[E.Step]
end

local function message(s)
	E.Msg, E.MsgTime = s, os.clock()
end

local function locked()
	return E.Locked
end

local function members(f)
	local t = CC.Members(f)
	-- the character being changed doesn't count
	for i = #t, 1, -1 do
		if E.Player and t[i]["?ptr"] == E.Player["?ptr"] then table.remove(t, i) end
	end
	return t
end

local function refreshLock()
	E.Locked = E.Mode == "trainer" and E.F ~= E.NewF and #members(E.F) > 0
end

---------------------------------------------------------------------------
-- opening and closing
---------------------------------------------------------------------------

local function hideOthers(screen)
	Hidden = {}
	local ae = CustomUI.ActiveElements[screen]
	if not ae then return end
	for _, list in pairs({ae.Buttons, ae.Texts, ae.Icons}) do
		for _, els in pairs(list) do
			for _, el in pairs(els) do
				if not Mine[el] and el.Active then
					el.Active = false
					Hidden[#Hidden + 1] = el
				end
			end
		end
	end
end

local function restoreOthers()
	for _, el in ipairs(Hidden) do el.Active = true end
	Hidden = {}
end

local function open(mode, player)
	if E.Open then return end
	if mode == "creation" and not CC.IsCreating() then CC.BeginCreation() end
	E.Mode, E.Player, E.Screen = mode, player, Game.CurrentScreen
	E.Step, E.Typing, E.Msg = 1, false, nil
	-- the player's own custom class, or a new one
	local f = CC.FamilyOf(player.Class)
	E.NewF = nil
	if not (f and CC.Builds()[f]) then
		local err
		f, err = CC.NewFamily()
		if not f then
			Game.ShowStatusText(err)
			return
		end
		E.NewF = f
	end
	E.F = f
	refreshLock()
	E.Open = true
	hideOthers(E.Screen)
	log("open (%s), class %d", mode, f)
end

local function dropUnusedNew()
	if E.NewF and E.NewF ~= E.Chosen and #CC.Members(E.NewF) == 0 then
		CC.RemoveFamily(E.NewF)
	end
end

local function close()
	E.Open, E.Typing = false, false
	dropUnusedNew()
	E.NewF, E.Chosen = nil, nil
	restoreOthers()
	CC.Apply()
	if E.Mode == "creation" and MF.CreationRefresh then
		MF.CreationRefresh()
	else
		Game.NeedRedraw = true
	end
end

local function familyList()
	local t = {}
	for f = 1, CC.Families do
		if CC.Builds()[f] then t[#t + 1] = f end
	end
	return t
end

---------------------------------------------------------------------------
-- Done
---------------------------------------------------------------------------

local function purchasable(s)
	local n = 0
	for _, m in pairs(s.Skills) do if m > 0 then n = n + 1 end end
	return n
end

local function validate()
	local f = fam()
	for step = 1, CC.Steps do
		local bad = CC.Problems(f, step)
		if #bad > 0 then
			E.Step = step
			return nil, CC.StepNames[step] .. ": " .. bad[1]
		end
	end
	local need = math.min(START_SKILLS, purchasable(f.Steps[1]))
	if #(f.StartSkills or {}) < need then
		E.Step = 1
		return nil, string.format("Choose %d starting skills (Shift+click)", need)
	end
	-- the creation screen asks for two more skills from the class's other skills
	if E.Mode == "creation" and purchasable(f.Steps[1]) < START_SKILLS + EXTRA_SKILLS then
		E.Step = 1
		return nil, string.format("The base class needs at least %d skills", START_SKILLS + EXTRA_SKILLS)
	end
	return true
end

local function done()
	local ok, err = validate()
	if not ok then message(err) return end
	local f, id = fam(), CC.ClassId(E.F, 1)
	local pl = E.Player
	E.Chosen = E.F
	CC.Apply()
	if E.Mode == "creation" then
		pl.Class = id
		for i = 0, pl.Skills.count - 1 do pl.Skills[i] = 0 end
		for _, sk in ipairs(f.StartSkills) do pl.Skills[sk] = 1 end
		log("creation: %s takes %s", tostring(pl.Name), f.Steps[1].Name)
	else
		local before = pl.SkillPoints
		if MF.ConvertCharacter and pl.Attrs then
			MF.ConvertCharacter({Player = pl, ToClass = id})
		end
		pl.Class = id
		for _, sk in ipairs(f.StartSkills) do
			if pl.Skills[sk] == 0 then
				pl.Skills[sk] = 1
				if sk >= 12 and sk <= 20 then pl.Spells[(sk - 12) * 11 + 1] = true end
			end
		end
		local refund = pl.SkillPoints - before
		Game.ShowStatusText(string.format("%s is now a %s%s", pl.Name, f.Steps[1].Name,
			refund > 0 and string.format(" (%d skill points refunded)", refund) or ""))
		log("trainer: %s takes %s, refund %d", pl.Name, f.Steps[1].Name, refund)
	end
	close()
end

---------------------------------------------------------------------------
-- editing
---------------------------------------------------------------------------

local function defaultName(base, step)
	return ({base, base .. " Adept", base .. " Master", "Light " .. base, "Dark " .. base})[step]
end

local function endTyping(keep)
	if not E.Typing then return end
	local f = fam()
	local new = keep and E.TypeBuf:match("^%s*(.-)%s*$") or ""
	if new ~= "" then
		local old = f.Steps[E.Step].Name
		f.Steps[E.Step].Name = new
		if E.Step == 1 then
			for s = 2, CC.Steps do
				if f.Steps[s].Name == defaultName(old, s) then f.Steps[s].Name = defaultName(new, s) end
			end
		end
		CC.Apply()
	end
	E.Typing = false
end

local function edit(ok, err)
	if not ok then message(err) return end
	CC.Apply()
end

local function changeTier(field, d)
	if locked() then message("This class is taken by a character in the game") return end
	local s = spec()
	edit(CC.SetTier(fam(), E.Step, field, s[field] + d))
end

local function cycleStats()
	if locked() then message("This class is taken by a character in the game") return end
	local s = spec()
	edit(CC.SetStats(fam(), E.Step, s.Stats % 3 + 1))
end

local function clickSkill(id)
	if locked() then message("This class is taken by a character in the game") return end
	local f, s = fam(), spec()
	local cap = s.Skills[id] or 0
	if Keys.IsPressed(const.Keys.SHIFT) then
		if E.Step ~= 1 then message("Starting skills are chosen on the base class tab") return end
		f.StartSkills = f.StartSkills or {}
		for i, sk in ipairs(f.StartSkills) do
			if sk == id then table.remove(f.StartSkills, i) return end
		end
		if cap == 0 then message("Only a skill the class can learn can be a starting skill") return end
		if #f.StartSkills >= START_SKILLS then message("Two starting skills are chosen already") return end
		table.insert(f.StartSkills, id)
		return
	end
	if Keys.IsPressed(const.Keys.CTRL) then
		edit(CC.SetSkill(f, E.Step, id, cap - 1))
	else
		if cap >= 4 then return end
		edit(CC.SetSkill(f, E.Step, id, cap + 1))
	end
end

---------------------------------------------------------------------------
-- keyboard: typing the name, Esc
---------------------------------------------------------------------------

local K = const.Keys
function events.KeyDown(t)
	if not shown() then return end
	local key = t.Key
	t.Key, t.Handled = 0, true
	if E.Typing then
		if key == K.RETURN then endTyping(true)
		elseif key == K.ESCAPE then endTyping(false)
		elseif key == K.BACK then E.TypeBuf = E.TypeBuf:sub(1, -2)
		elseif #E.TypeBuf < 24 then
			local ch
			if key >= 65 and key <= 90 then
				ch = string.char(Keys.IsPressed(K.SHIFT) and key or key + 32)
			elseif key >= 48 and key <= 57 and not Keys.IsPressed(K.SHIFT) then
				ch = string.char(key)
			elseif key == K.SPACE then ch = " "
			elseif key == 189 then ch = "-"
			elseif key == 222 then ch = "'"
			end
			if ch then E.TypeBuf = E.TypeBuf .. ch end
		end
	elseif key == K.ESCAPE then
		close()
	elseif key == K.RETURN then
		done()
	end
end

-- typed characters (WM_CHAR) would also reach the game's own text field (the character's
-- name on the creation screen)
function events.WindowMessage(t)
	if shown() and t.Msg == 0x102 then
		t.Handled = true
		t.Result = 0
	end
end

---------------------------------------------------------------------------
-- the screen
---------------------------------------------------------------------------

local SCREENS

local function text(t)
	local el = CustomUI.CreateText{
		Text = "  ", Font = t.Font, X = t.X, Y = t.Y, Width = t.W, Height = t.H or 14,
		Layer = 0, Screen = SCREENS, AlignLeft = t.Left ~= false,
		ColorStd = WHITE, ColorMouseOver = HOVER,
		Condition = function(self)
			if not shown() then return false end
			local s, c = t.Get()
			if not s then return false end
			self.Text = s
			self.CStd = c or WHITE
			return true
		end,
		Action = t.Click and function(self)
			if shown() then
				if E.Typing and not t.KeepTyping then endTyping(true) end
				t.Click(self)
			end
		end or nil,
	}
	Mine[el] = true
	return el
end

local SKILL_ORDER

local function build()
	local Big, Small = Game.Arrus_fnt, Game.Lucida_fnt
	SCREENS = {CREATION_SCREEN, const.Screens.House}

	local bg = CustomUI.CreateIcon{
		Icon = BACKGROUND, X = 0, Y = 0, Layer = 0, Screen = SCREENS, BlockBG = true,
		Condition = function() return shown() end}
	Mine[bg] = true

	-- class choice and points
	text{Font = Big, X = PX, Y = PY, W = 290, H = 16,
		Get = function()
			local list, idx = familyList(), 1
			for i, f in ipairs(list) do if f == E.F then idx = i end end
			local s = fam().Steps[1].Name
			if E.F == E.NewF then s = s .. " (new)" elseif locked() then s = s .. " (taken, read-only)" end
			return string.format("Class %d/%d: %s", idx, #list, s), GOLD
		end,
		Click = function()
			local list = familyList()
			if #list < 2 then message("There is only this custom class so far") return end
			local idx = 1
			for i, f in ipairs(list) do if f == E.F then idx = i end end
			E.F = list[idx % #list + 1]
			E.Step = 1
			refreshLock()
		end}
	text{Font = Big, X = PX + 300, Y = PY, W = 190, H = 16,
		Get = function()
			local total = CC.Cost(spec())
			local budget = CC.Budget[E.Step]
			return string.format("Points: %g / %d", total, budget), total > budget and RED or GREEN
		end}

	-- step tabs
	local TABS = {"Base", "Promotion", "Neutral", "Light", "Dark"}
	for step = 1, 5 do
		text{Font = Big, X = PX + (step - 1) * 98, Y = PY + 18, W = 94, H = 16,
			Get = function()
				local bad = #CC.Problems(fam(), step) > 0
				return TABS[step] .. (bad and "!" or ""), step == E.Step and GOLD or (bad and RED or GREY)
			end,
			Click = function() E.Step = step end}
	end

	-- name and SP stats
	text{Font = Big, X = PX, Y = PY + 36, W = 290, H = 16, KeepTyping = true,
		Get = function()
			if E.Typing then return "Name: " .. E.TypeBuf .. "_", GOLD end
			return "Name: " .. spec().Name
		end,
		Click = function()
			if locked() then message("This class is taken by a character in the game") return end
			if not E.Typing then E.Typing, E.TypeBuf = true, "" end
		end}
	text{Font = Big, X = PX + 300, Y = PY + 36, W = 190, H = 16,
		Get = function()
			local s = spec()
			return "SP from: " .. (({"Intellect", "Personality", "both"})[s.Stats] or "?"),
				s.SP == 0 and GREY or WHITE
		end,
		Click = cycleStats}

	-- tiers
	local function tierRow(y, field, label, tiers)
		text{Font = Big, X = PX, Y = y, W = 330, H = 16,
			Get = function()
				local s = spec()
				local v = tiers[s[field]]
				return string.format("%s: tier %d  (%d + %d per level)", label, s[field], v[1], v[2])
			end}
		text{Font = Big, X = PX + 340, Y = y, W = 24, H = 16,
			Get = function() return "[-]" end, Click = function() changeTier(field, -1) end}
		text{Font = Big, X = PX + 370, Y = y, W = 24, H = 16,
			Get = function() return "[+]" end, Click = function() changeTier(field, 1) end}
	end
	tierRow(PY + 54, "HP", "Hit points", CC.HPTiers)
	tierRow(PY + 72, "SP", "Spell points", CC.SPTiers)

	-- skills: three columns of twelve
	SKILL_ORDER = {}
	for id = 0, 38 do
		if CC.SkillNames[id] then SKILL_ORDER[#SKILL_ORDER + 1] = id end
	end
	local SHORT = {[0] = "-", "Nov", "Exp", "Mas", "GM"}
	local NICE = {IdentifyItem = "Ident. Item", DisarmTraps = "Disarm Traps", IdentifyMonster = "Ident. Monster",
		Bodybuilding = "Bodybuilding", Repair = "Repair Item"}
	for i, id in ipairs(SKILL_ORDER) do
		local col, row = math.floor((i - 1) / 12), (i - 1) % 12
		local name = CC.SkillNames[id]
		name = NICE[name] or name
		text{Font = Small, X = PX + col * 168, Y = PY + 94 + row * 14, W = 166, H = 14,
			Get = function()
				local f, s = fam(), spec()
				local cap = s.Skills[id] or 0
				local start = false
				for _, sk in ipairs(f.StartSkills or {}) do if sk == id then start = true end end
				return string.format("%s: %s%s", name, SHORT[cap], start and " *" or ""),
					start and GOLD or (cap > 0 and WHITE or GREY)
			end,
			Click = function() clickSkill(id) end}
	end

	-- bottom line
	text{Font = Small, X = 74, Y = 425, W = 360, H = 14,
		Get = function()
			if E.Msg and os.clock() - E.MsgTime < MSG_TIME then return E.Msg, RED end
			if E.Typing then return "Type the name; Enter to keep it, Esc to drop it" end
			local bad = CC.Problems(fam(), E.Step)
			if #bad > 0 then return bad[1], RED end
			return "Click +  Ctrl+click -  Shift+click: start skill " ..
				#(fam().StartSkills or {}) .. "/" .. START_SKILLS
		end}
	text{Font = Big, X = 440, Y = 423, W = 66, H = 16,
		Get = function() return "Cancel" end, Click = function() close() end}
	text{Font = Big, X = 510, Y = 423, W = 58, H = 16,
		Get = function() return "Done", GOLD end, Click = function() done() end}

	-- entry on the creation screen
	local entry = CustomUI.CreateButton{
		IconUp = ENTRY_ICONS[1], IconDown = ENTRY_ICONS[2], IconMouseOver = ENTRY_ICONS[3],
		X = ENTRY_X, Y = ENTRY_Y, Layer = 0, Screen = CREATION_SCREEN, BlockBG = true,
		Condition = function() return not E.Open end,
		Action = function() open("creation", Party[0]) end}
	Mine[entry] = true
end

---------------------------------------------------------------------------
-- training halls: "Become a custom class" for a Peasant
---------------------------------------------------------------------------

local HOUSE_LINE_GAP, HOUSE_LINE_H = 6, 20

local function trainerItem()
	if Game.CurrentScreen ~= const.Screens.House or Game.HouseScreen ~= const.HouseScreens.Main then return end
	local ok, it = pcall(function()
		local house = Game.GetCurrentHouse()
		if not (house and Game.Houses[house] and Game.Houses[house].Type == const.HouseType.Training) then return end
		local pl = Party[math.max(Game.CurrentPlayer, 0)]
		if not pl or pl.Class ~= const.Class.Peasant then return end
		local dlg = Game.CurrentNPCDialog
		if not dlg or dlg.LastItemPtr == 0 then return end
		return structs.Button:new(dlg.LastItemPtr)
	end)
	return ok and it or nil
end

local function buildTrainer()
	local Big = Game.Arrus_fnt
	local line = CustomUI.CreateText{
		Text = "Become a custom class", Font = Big, Width = 180, Height = HOUSE_LINE_H,
		ColorStd = WHITE, ColorMouseOver = HOVER, Layer = 0, Screen = const.Screens.House,
		Condition = function(self)
			if E.Open then return false end
			local it = trainerItem()
			if not it then return false end
			self.X, self.Wt = it.Left - 20, it.Width + 40
			self.Y, self.Ht = it.Top + it.Height + HOUSE_LINE_GAP, HOUSE_LINE_H
			return true
		end,
		Action = function()
			local pl = Party[math.max(Game.CurrentPlayer, 0)]
			if pl and pl.Class == const.Class.Peasant then open("trainer", pl) end
		end}
	Mine[line] = true
end

---------------------------------------------------------------------------

function events.GameInitialized2()
	CC = MF.CustomClasses
	if not (CC and CustomUI) then
		MF.LogError("CustomClassEditor: MMMWE_CustomClasses.lua or CustomUI is missing")
		return
	end
	WHITE, GREY, GOLD = RGB(255, 255, 255), RGB(150, 150, 150), RGB(255, 215, 90)
	RED, GREEN, HOVER = RGB(255, 100, 100), RGB(140, 255, 140), RGB(255, 255, 160)
	build()
	buildTrainer()
end

-- a new party creation starts with no custom classes
function events.MenuAction(t)
	if t.Action == 5 and CC then CC.BeginCreation() end
end

-- leaving the screen some other way closes the editor
function events.Tick()
	if E.Open and Game.CurrentScreen ~= E.Screen then
		E.Open, E.Typing = false, false
		dropUnusedNew()
		restoreOthers()
	end
end

MF.CustomClassEditor = {Open = open, Close = close, State = E}
