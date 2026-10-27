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
	  OK / Cancel       Enter is OK, Esc cancels
	The screen is CCEditor (waffel.icons.lod, made from the stats screen fr_stats); the
	tabs are the c_baseclass ... c_dark buttons (waffel.D.lod), Cancel and OK the game's
	c_cncl / c_ok buttons; skills in Create.fnt.
	A class already taken by a character in the game is read-only in the training hall
	(it can still be taken as it is).
--]]

local MF = Merge.Functions

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local ENABLED       = true
local BACKGROUND    = "CCEditor"         -- 640x480 screen with the boxes (waffel.icons.lod)
-- step tabs and Spells: buttons c_<name>_up / _ht / _dn / _problem (waffel.D.lod), 90 px apart
local TAB_ICONS     = {"c_baseclass", "c_firstpromo", "c_neutral", "c_light", "c_dark"}
local SPELLS_ICONS  = "c_spells"
local TAB_X, TAB_STEP = 54, 90
local FLASH_TIME    = 0.5                -- seconds per phase of a red flashing button
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

local function message(s, ok)
	E.Msg, E.MsgTime, E.MsgOk = s, os.clock(), ok
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
	E.View, E.SpellPage = "skills", 1
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
	local kitOk, kitErr = CC.KitAllowed(pl, f.Kit)
	if not kitOk then message(kitErr:gsub("^%l", string.upper)) return end
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
				if sk >= 12 and sk <= 20 then
					-- the school's first spell the class can learn
					local spells = f.Steps[1].Spells
					for spell = (sk - 12) * 11 + 1, (sk - 12) * 11 + 11 do
						if not spells or spells[spell] then pl.Spells[spell] = true break end
					end
				end
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

local function cycleKit()
	if locked() then message("This class is taken by a character in the game") return end
	if E.Step ~= 1 then message("The kit is chosen on the base class tab") return end
	local f = fam()
	local list, idx = CC.Kits, 0
	for i, k in ipairs(list) do if k.Key == f.Kit then idx = i end end
	local d = Keys.IsPressed(const.Keys.CTRL) and -1 or 1
	idx = (idx + d) % (#list + 1)
	edit(CC.SetKit(f, idx > 0 and list[idx].Key or nil))
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

-- spells view: the step's schools, three per page (a school = a heading and its 11 spells)
local function spellSchools()
	local t, s = {}, spec()
	for i, name in ipairs(CC.MagicSchools) do
		if (s.Skills[const.Skills[name]] or 0) > 0 then t[#t + 1] = i end
	end
	return t
end

local function spellPages()
	return math.max(1, math.ceil(#spellSchools() / 3))
end

-- the Spells button: skills -> spells page 1 -> 2 ... -> skills
local function cycleView()
	if E.View == "skills" then
		if #spellSchools() == 0 then message("Buy a magic school first") return end
		E.View, E.SpellPage = "spells", 1
	elseif E.SpellPage < spellPages() then
		E.SpellPage = E.SpellPage + 1
	else
		E.View = "skills"
	end
end

local function clickSpell(spell)
	if locked() then message("This class is taken by a character in the game") return end
	local s = spec()
	local picked = not s.Spells or s.Spells[spell]   -- older builds: every spell is picked
	local on = not picked and not Keys.IsPressed(const.Keys.CTRL)
	edit(CC.SetSpell(fam(), E.Step, spell, on))
end

-- Ctrl+S: the build to CustomClasses/<name>.txt; Ctrl+L: the next file of that folder
-- into the class shown (each press loads the next one)
local function saveBuild()
	local p, err = CC.ExportBuild(fam())
	message(p and ("Saved to " .. p) or err, p ~= nil)
end

local function loadBuild()
	if locked() then message("This class is taken by a character in the game") return end
	local files = CC.BuildFiles()
	if #files == 0 then message("No builds in the CustomClasses folder") return end
	E.LoadIdx = (E.LoadIdx or 0) % #files + 1
	local p = files[E.LoadIdx]
	local new, err = CC.ImportFile(p)
	if not new then message(err) return end
	CC.Builds()[E.F] = new
	E.Step = 1
	CC.Apply()
	message(string.format("Loaded %s (%d/%d)", p:match("[^/\\]+$") or p, E.LoadIdx, #files), true)
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
	elseif key == 83 and Keys.IsPressed(K.CTRL) then   -- S
		saveBuild()
	elseif key == 76 and Keys.IsPressed(K.CTRL) then   -- L
		loadBuild()
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

-- CustomUI keys texts on screen lists by the first 3 characters of the text and the position,
-- so texts at the same place (skills / spells views) need different initial texts
local TextCount = 0
local function text(t)
	TextCount = TextCount + 1
	local el = CustomUI.CreateText{
		Text = string.format("%03d", TextCount), Font = t.Font, X = t.X, Y = t.Y, Width = t.W, Height = t.H or 14,
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
	local Big, Small, Skill = Game.Arrus_fnt, Game.Lucida_fnt, Game.Create_fnt
	SCREENS = {CREATION_SCREEN, const.Screens.House}

	-- the background (CCEditor, waffel.icons.lod) has recessed boxes for the parts below:
	-- title 8..632 x 8..34, info 8..454 x 78..150, kit / SP 462..632 x 78..150,
	-- skills / spells 8..632 x 158..424, hint 8..450 x 432..472; step tabs and Spells at
	-- y 42 (x 54, 90 apart), Cancel / OK at y 440
	local bg = CustomUI.CreateIcon{
		Icon = BACKGROUND, X = 0, Y = 0, Layer = 0, Screen = SCREENS, BlockBG = true,
		Condition = function() return shown() end}
	Mine[bg] = true

	local function button(t)
		local el = CustomUI.CreateButton{
			IconUp = t.Up, IconDown = t.Down, IconMouseOver = t.Over,
			X = t.X, Y = t.Y, Layer = 0, Screen = SCREENS, DynLoad = true,
			Condition = function(self)
				if not shown() then return false end
				if t.Update then t.Update(self) end
				return true
			end,
			Action = function()
				if not shown() then return end
				if E.Typing then endTyping(true) end
				t.Click()
			end}
		Mine[el] = true
		return el
	end

	-- class choice and points
	text{Font = Big, X = 16, Y = 11, W = 440, H = 19,
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
	text{Font = Big, X = 470, Y = 11, W = 156, H = 19,
		Get = function()
			local total = CC.Cost(spec(), fam().Kit)
			local budget = CC.Budget[E.Step]
			return string.format("Points: %g / %d", total, budget), total > budget and RED or GREEN
		end}

	-- step tabs and Spells: the one shown glows, one with problems flashes red
	-- the game keeps 15 characters of a bitmap's name, and CustomUI reloads a button's picture
	-- whenever the kept name differs from IUpSrc: "c_baseclass_problem" would be loaded anew
	-- every frame until the bitmap list is full. So the pictures are loaded once and the
	-- button gets the pointer and the name as kept.
	local pics = {}
	local function pic(name)
		local p = pics[name]
		if not p then
			p = CustomUI.LoadIcon(name)
			if type(p) ~= "number" or p == 0 then return end
			pics[name] = p
		end
		return p
	end
	local function flash(self, icons, selected, bad)
		local s = icons .. (selected and "_ht" or "_up")
		if bad and math.floor(os.clock() / FLASH_TIME) % 2 == 0 then s = icons .. "_problem" end
		local p = pic(s)
		if p then
			self.IUpPtr = p
			self.IUpSrc = mem.string(p)
			if (self.Wt or 1) <= 1 then   -- the size CustomUI takes from the first picture it loads
				self.Wt, self.Ht = mem.u2[p + 0x18], mem.u2[p + 0x1A]
			end
		end
	end
	for step = 1, 5 do
		local icons = TAB_ICONS[step]
		button{Up = icons .. "_up", Down = icons .. "_dn", Over = icons .. "_ht",
			X = TAB_X + (step - 1) * TAB_STEP, Y = 42,
			Update = function(self) flash(self, icons, step == E.Step, #CC.Problems(fam(), step) > 0) end,
			Click = function() Game.PlaySound(23) E.Step = step end}
	end
	button{Up = SPELLS_ICONS .. "_up", Down = SPELLS_ICONS .. "_dn", Over = SPELLS_ICONS .. "_ht",
		X = TAB_X + 5 * TAB_STEP, Y = 42,
		Update = function(self)
			if E.View == "spells" then
				if #spellSchools() == 0 then E.View = "skills" end
				if E.SpellPage > spellPages() then E.SpellPage = 1 end
			end
			flash(self, SPELLS_ICONS, E.View == "spells", #CC.SpellProblems(fam(), E.Step) > 0)
		end,
		Click = function() Game.PlaySound(23) cycleView() end}

	-- name and tiers
	text{Font = Big, X = 16, Y = 84, W = 430, H = 19, KeepTyping = true,
		Get = function()
			if E.Typing then return "Name: " .. E.TypeBuf .. "_", GOLD end
			return "Name: " .. spec().Name
		end,
		Click = function()
			if locked() then message("This class is taken by a character in the game") return end
			if not E.Typing then E.Typing, E.TypeBuf = true, "" end
		end}
	local function tierRow(y, field, label, tiers)
		text{Font = Big, X = 16, Y = y, W = 370, H = 19,
			Get = function()
				local s = spec()
				local v = tiers[s[field]]
				return string.format("%s: tier %d  (%d + %d per level)", label, s[field], v[1], v[2])
			end}
		text{Font = Big, X = 390, Y = y, W = 26, H = 19,
			Get = function() return "[-]" end, Click = function() changeTier(field, -1) end}
		text{Font = Big, X = 420, Y = y, W = 26, H = 19,
			Get = function() return "[+]" end, Click = function() changeTier(field, 1) end}
	end
	tierRow(106, "HP", "Hit points", CC.HPTiers)
	tierRow(126, "SP", "Spell points", CC.SPTiers)

	-- resource kit (chosen on the base tab, kept by the promotions) and the SP stats
	text{Font = Big, X = 470, Y = 84, W = 156, H = 19,
		Get = function()
			local k = fam().Kit and CC.KitByKey[fam().Kit]
			return "Kit: " .. (k and k.Name or "none"), k and GOLD or (E.Step == 1 and WHITE or GREY)
		end,
		Click = cycleKit}
	text{Font = Small, X = 470, Y = 105, W = 156, H = 17,
		Get = function()
			local k = fam().Kit and CC.KitByKey[fam().Kit]
			if not k then return E.Step == 1 and "click to buy one" or " ", GREY end
			return string.format("%s, %d pts", k.Resource or "Spell points", k.Price), GREY
		end,
		Click = cycleKit}
	text{Font = Big, X = 470, Y = 126, W = 156, H = 19,
		Get = function()
			local s = spec()
			return "SP: " .. (({"Intellect", "Personality", "Int. and Pers."})[s.Stats] or "?"),
				s.SP == 0 and GREY or WHITE
		end,
		Click = cycleStats}

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
		text{Font = Skill, X = 18 + col * 206, Y = 163 + row * 21, W = 196, H = 18,
			Get = function()
				if E.View ~= "skills" then return end
				local f, s = fam(), spec()
				local cap = s.Skills[id] or 0
				local start = false
				for _, sk in ipairs(f.StartSkills or {}) do if sk == id then start = true end end
				return string.format("%s: %s%s", name, SHORT[cap], start and " *" or ""),
					start and GOLD or (cap > 0 and WHITE or GREY)
			end,
			Click = function() clickSkill(id) end}
	end

	-- spells: three schools per page, a heading and the 11 spells each
	local RANK = {"N", "E", "M", "G"}
	local SHORTER = {["Protection from Magic"] = "Prot. from Magic"}
	for col = 0, 2 do
		for row = 0, 11 do
			local function spellAt()
				local schools = spellSchools()
				local school = schools[(E.SpellPage - 1) * 3 + col + 1]
				if not school then return end
				if row == 0 then return school end
				return school, (school - 1) * 11 + row
			end
			text{Font = Skill, X = 18 + col * 206, Y = 163 + row * 21, W = 200, H = 18,
				Get = function()
					if E.View ~= "spells" then return end
					local school, spell = spellAt()
					if not school then return end
					local s = spec()
					if not spell then
						local cap = s.Skills[const.Skills[CC.MagicSchools[school]]] or 0
						return string.format("%s Magic: %s", CC.MagicSchools[school], SHORT[cap]), GREEN
					end
					local name = Game.SpellsTxt[spell].Name
					name = SHORTER[name] or name
					local picked = not s.Spells or s.Spells[spell]
					return string.format("%s (%s)", name, RANK[CC.SpellRank(spell)]), picked and GOLD or GREY
				end,
				Click = function()
					local _, spell = spellAt()
					if spell then clickSpell(spell) end
				end}
		end
	end

	-- hint box: messages, problems or how to use the screen; the keys
	text{Font = Small, X = 14, Y = 435, W = 432, H = 17,
		Get = function()
			if E.Msg and os.clock() - E.MsgTime < MSG_TIME then return E.Msg, E.MsgOk and GREEN or RED end
			if E.Typing then return "Type the name; Enter keeps it, Esc drops it" end
			local bad = CC.Problems(fam(), E.Step)
			if #bad > 0 then return bad[1], RED end
			if E.View == "spells" then
				local cost = CC.SpellCost
				return string.format("Spells %d/%d: click to pick (%g/%g/%g/%g points)", E.SpellPage, spellPages(),
					cost[1], cost[2], cost[3], cost[4])
			end
			return "Click +, Ctrl+click -, Shift+click: start skill " ..
				#(fam().StartSkills or {}) .. "/" .. START_SKILLS
		end}
	text{Font = Small, X = 14, Y = 453, W = 432, H = 17,
		Get = function() return "Ctrl+S: save the build, Ctrl+L: load one", GREY end}

	button{Up = "c_cncl_up", Down = "c_cncl_dn", Over = "c_cncl_ht", X = 459, Y = 440,
		Click = function() Game.PlaySound(24) close() end}
	button{Up = "c_ok_up", Down = "c_ok_dn", Over = "c_ok_ht", X = 546, Y = 440,
		Click = function() done() end}

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
