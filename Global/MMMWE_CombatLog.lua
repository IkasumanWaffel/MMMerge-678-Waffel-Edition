-- Status Text History Overlay — last N messages, _G persistence, any resolution
-- v2: Added permanent enchantment damage from Concurrent Enchantments
local LogId = "CombatLog"
local MF = Merge.Functions
MF.LogInit1(LogId)

local user32 = mem.dll.user32
local gdi32 = mem.dll.gdi32
local kernel32 = mem.dll.kernel32

--====================================================
-- CONFIG
--====================================================
local CONFIG = {
    baseW    = 1920,
    baseH    = 1200,
    gameW    = 640,
    gameH    = 480,

    fontSize = 16,
    maxMessages = 10,
    lineSpacing = 20,

    anchor = "absolute",
    ax = 1480,
    ay = 620,
    gx = 160,
    gy = 144,

    textW = 300,
    textH = 18,

    newestColor = 0xFFFFFF,
    oldestColor = 0x666666,
	
	LogClearDelay = 20	--Time in real-time seconds before the log widget is cleared
}

--====================================================
-- WIN32 CONSTANTS
--====================================================
local WS_EX_LAYERED     = 0x00080000
local WS_EX_TRANSPARENT = 0x00000020
local WS_EX_TOPMOST     = 0x00000008
local WS_POPUP          = 0x80000000
local LWA_COLORKEY      = 0x00000001
local SW_SHOWNORMAL     = 1
local CS_HREDRAW        = 0x0002
local CS_VREDRAW        = 0x0001
local SWP_NOACTIVATE    = 0x0010
local COLOR_KEY         = 0x1A001A
local DT_SINGLELINE     = 0x00000020
local DT_NOCLIP         = 0x00000100
local DT_LEFT           = 0x00000000

local MOUSEEVENTF_RIGHTDOWN = 0x0008
local MOUSEEVENTF_RIGHTUP   = 0x0010

--====================================================
-- _G PERSISTENCY
--====================================================
if not _G.MMStatusOverlay then
    _G.MMStatusOverlay = {}
end
local G = _G.MMStatusOverlay

local function loadOverlayState()
    if vars and vars.CombatLogActive ~= nil then
        return vars.CombatLogActive
    end
    return true
end

local overlayActive    = loadOverlayState()
local overlayHwnd      = 0
local hFont            = 0
local classAtom        = 0
local classNamePtr     = 0
local lastFontKey      = ""

if G.hwnd and G.hwnd ~= 0 and user32.IsWindow(G.hwnd) ~= 0 then
    overlayHwnd = G.hwnd
    hFont = G.font or 0
    classAtom = G.classAtom or 0
    classNamePtr = G.classNamePtr or 0
end

local messages = G.messages or {}
local lastMessageTime = os.clock()

local rectBuf    = mem.StaticAlloc(16)
local clientRect = mem.StaticAlloc(16)
local drawRect   = mem.StaticAlloc(16)
local pointBuf   = mem.StaticAlloc(8)
local lastPX, lastPY, lastW, lastH = -1, -1, -1, -1
local needRedraw = true

local dialogActive   = false
local afterDrawFired = false
local cutsceneActive = false
local mouseEvent = nil
local postRenderFallback = 0

local screenW     = 0
local screenH     = 0
local gameScale   = 1
local gameOffsetX = 0
local gameOffsetY = 0
local baseScaleX  = 1
local baseScaleY  = 1
local baseScaleUI = 1   -- game UI scale: uniform, centered horizontally (same as MMMWE_HPSPDisplay)

local toBaseX = CONFIG.baseW / CONFIG.gameW
local toBaseY = CONFIG.baseH / CONFIG.gameH

--====================================================
-- ShowStatusText INTERCEPT
--====================================================
local originalShowStatusText = Game.ShowStatusText

local function pushMessage(text, damageKind)
    if not text or text == "" then return end
    if not overlayActive then return end           
    local n = CONFIG.maxMessages
    for i = n - 1, 1, -1 do
        messages[i] = messages[i - 1]
    end
    messages[0] = {text = text, damageKind = damageKind}
    G.messages = messages
    needRedraw = true
	lastMessageTime = os.clock()
end

Game.ShowStatusText = function(text, duration)
    pushMessage(tostring(text))
    if originalShowStatusText then
        originalShowStatusText(text, duration)
    end
end

--====================================================
-- DAMAGE TO MONSTER DATA INTERCEPT
--====================================================
local damageTypes = {
    [0]  = "Fire",    [1]  = "Air",     [2]  = "Water",   [3]  = "Earth",
    [4]  = "Phys",    [5]  = "Magic",   [6]  = "Spirit",  [7]  = "Mind",
    [8]  = "Body",    [9]  = "Light",   [10] = "Dark",    [12] = "Energy",
    [50] = "Dragon",
    -- physical damage dealt by the party, split by MMMWE_DamageKinds.lua (t.PhysDamageKind)
    [101] = "Slashing", [102] = "Piercing", [103] = "Blunt",
}
local PHYS_KIND_KEY = {Slashing = 101, Piercing = 102, Blunt = 103}

-- Color per damage type (BGR format for Win32 SetTextColor)
local damageTypeColors = {
    [0]  = 0x0066FF,   -- Fire: orange-red
    [1]  = 0x99FFFF,   -- Air: pale yellow
    [2]  = 0xFF6633,   -- Water: blue
    [3]  = 0x00AA44,   -- Earth: green
    [4]  = 0xC8C8C8,   -- Phys: light gray
    [5]  = 0xFF00CC,   -- Magic: magenta
    [6]  = 0x00D7FF,   -- Spirit: gold
    [7]  = 0xCC00FF,   -- Mind: purple
    [8]  = 0x44FF44,   -- Body: bright green
    [9]  = 0xFFFFCC,   -- Light: pale cyan
    [10] = 0x990099,   -- Dark: dark purple
    [12] = 0xD0C220,   -- Energy: teal
    [50] = 0x0033AA,   -- Dragon: dark red
    [101] = 0xE0E0E0,  -- Slashing: near white
    [102] = 0xA8C8D8,  -- Piercing: light tan
    [103] = 0xA0A0A0,  -- Blunt: mid gray
}
local function getMonsterName(monsterIndex)
    local name = "?"
    pcall(function()
        local mon = Map.Monsters[monsterIndex]
        if mon then name = mon.Name or "?" end
    end)
    if name == "?" or name == "" then
        pcall(function()
            local mon = Map.Monsters[monsterIndex]
            if mon then name = Game.MonstersTxt[mon.Id].Name or "?" end
        end)
    end
    return name
end

local function getPlayerName(playerIndex)
    local name = "?"
    pcall(function()
        local p = Party.Players[playerIndex]
        if p then name = p.Name or "?" end
    end)
    return name
end

-- Damage is collected per ATTACK: every CalcDamageToMonster call of one player against one
-- monster that arrives within ATTACK_WINDOW seconds (the weapon hit, then each weapon's
-- enchantment, including the permanent ones MMMWE_ConcurrentEnchantments.lua deals directly).
-- The attack is posted as soon as a different player / monster is hit or the window passes,
-- as ONE line ("Alice hits Goblin for 17 damage (12 Phys, 5 Fire)"), so a dual-wield hit
-- with two enchantments can't push its own parts (or other players' hits) out of the log.
local ATTACK_WINDOW = 0.15          -- seconds (real time)
local KIND_ORDER = {101, 102, 103, 4, 12, 0, 1, 2, 3, 6, 7, 8, 9, 10, 5, 50}   -- Phys first, then the rest

local attack = nil                  -- {key, playerName, monsterName, parts = {[kind] = part}, last}

local function postAttack(a)
    local parts, total, biggest = {}, 0, nil
    local listed = {}
    local function add(kind, part)
        if listed[kind] then return end
        listed[kind] = true
        parts[#parts + 1] = string.format("%d %s%s", part.damage,
            damageTypes[kind] or "?", part.enchant and " (enchant)" or "")
        total = total + part.damage
        if not biggest or part.damage > a.parts[biggest].damage then biggest = kind end
    end
    for _, kind in ipairs(KIND_ORDER) do
        if a.parts[kind] then add(kind, a.parts[kind]) end
    end
    for kind, part in pairs(a.parts) do add(kind, part) end   -- kinds not in KIND_ORDER
    if total <= 0 then return end
    local msg
    if #parts == 1 then
        msg = string.format("%s hits %s for %s damage", a.playerName, a.monsterName, parts[1])
    else
        msg = string.format("%s hits %s for %d damage (%s)", a.playerName, a.monsterName,
            total, table.concat(parts, ", "))
    end
    pushMessage(msg, biggest)
end

local function addPart(a, kind, damage, enchant)
    local part = a.parts[kind]
    if part then
        part.damage = part.damage + damage
        part.enchant = part.enchant and enchant
    else
        a.parts[kind] = {damage = damage, enchant = enchant}
    end
end

-- Permanent-enchantment damage that MMMWE_ConcurrentEnchantments.lua took off the monster
-- directly (different element from the temporary enchantment)
local function takePermHits(a, playerIdx, monIdx)
    local q = _G.CE_PermHitQueue
    if not q or #q == 0 then return end
    for i = #q, 1, -1 do
        local ph = q[i]
        if ph.monsterIndex == monIdx and (ph.playerIndex or playerIdx) == playerIdx then
            addPart(a, ph.damageKind, ph.damage, true)
            table.remove(q, i)
        end
    end
end

local function flushDamageAccum()
    if attack then
        if overlayActive then
            postAttack(attack)
        end
        attack = nil
    end
    -- leftovers that belong to no attack (posted on their own)
    local q = _G.CE_PermHitQueue
    if q and #q > 0 then
        if overlayActive then
            for _, ph in ipairs(q) do
                local a = {playerName = getPlayerName(ph.playerIndex or 0),
                    monsterName = getMonsterName(ph.monsterIndex), parts = {}}
                addPart(a, ph.damageKind, ph.damage, true)
                postAttack(a)
            end
        end
        _G.CE_PermHitQueue = {}
    end
end

function events.CalcDamageToMonster(t)
    if not overlayActive then return end
    local pl = nil
    pcall(function() pl = t.Player end)
    if not pl then return end

    local playerIdx = nil
    pcall(function() playerIdx = pl:GetSlot() end)
    if not playerIdx or type(playerIdx) ~= "number" then return end
    if playerIdx < 0 or playerIdx > 4 then return end

    local monIdx = nil
    pcall(function() monIdx = t.MonsterIndex end)
    if monIdx == nil then
        pcall(function() monIdx = t.Monster end)
    end
    if type(monIdx) == "table" or type(monIdx) == "userdata" then
        local realIdx = nil
        pcall(function() realIdx = monIdx.Index end)
        monIdx = realIdx
    end

    local key = tostring(playerIdx) .. "_" .. tostring(monIdx)
    local now = os.clock()
    if attack and (attack.key ~= key or now - attack.last > ATTACK_WINDOW) then
        flushDamageAccum()
    end
    if not attack then
        attack = {key = key, playerName = getPlayerName(playerIdx),
            monsterName = getMonsterName(monIdx), parts = {}}
    end
    attack.last = now

    -- the permanent-enchantment part comes right before this call, even when this
    -- call's own damage was fully resisted
    takePermHits(attack, playerIdx, monIdx)

    local result = nil
    pcall(function() result = t.Result end)
    if result and result > 0 then
        local dmgKind = 0
        pcall(function() dmgKind = t.DamageKind or 0 end)
        if dmgKind == 4 and t.PhysDamageKind and PHYS_KIND_KEY[t.PhysDamageKind] then
            dmgKind = PHYS_KIND_KEY[t.PhysDamageKind]   -- Slashing / Piercing / Blunt
        end
        addPart(attack, dmgKind, result, t.IsSecondary == true)
    end
end

local function checkDamageFlush()
    if attack and os.clock() - attack.last > ATTACK_WINDOW then
        flushDamageAccum()
    end
end

--====================================================
-- WINDOW
--====================================================
local function createFont()
    local actualSize = math.max(8, math.floor(CONFIG.fontSize * baseScaleY))
    local key = tostring(actualSize)
    if key == lastFontKey and hFont ~= 0 then return end
    if hFont ~= 0 then gdi32.DeleteObject(hFont) end
    hFont = gdi32.CreateFontA(actualSize, 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 5, 0, "Book Antiqua")
    lastFontKey = key
    G.font = hFont
end

local function createWindow()
    local hUser32 = kernel32.GetModuleHandleA("user32.dll")
    local defProc = kernel32.GetProcAddress(hUser32, "DefWindowProcA")
    if not defProc or defProc == 0 then return false end

    if classAtom == 0 then
        if classNamePtr == 0 then
            classNamePtr = mem.StaticAlloc(16)
            mem.copy(classNamePtr, "MMStatus\0", 9)
        end
        local wc = mem.StaticAlloc(40)
        mem.u4[wc + 0]  = CS_HREDRAW + CS_VREDRAW
        mem.u4[wc + 4]  = defProc
        mem.u4[wc + 8]  = 0
        mem.u4[wc + 12] = 0
        mem.u4[wc + 16] = 0
        mem.u4[wc + 20] = 0
        mem.u4[wc + 24] = 0
        mem.u4[wc + 28] = gdi32.CreateSolidBrush(COLOR_KEY)
        mem.u4[wc + 32] = 0
        mem.u4[wc + 36] = classNamePtr
        classAtom = user32.RegisterClassA(wc)
    end

    overlayHwnd = user32.CreateWindowExA(
        WS_EX_LAYERED + WS_EX_TRANSPARENT + WS_EX_TOPMOST,
        classNamePtr, classNamePtr, WS_POPUP,
        0, 0, 0, 0, 0, 0, 0, 0)
    if overlayHwnd == 0 then return false end

    user32.SetLayeredWindowAttributes(overlayHwnd, COLOR_KEY, 0, LWA_COLORKEY)
    user32.ShowWindow(overlayHwnd, SW_SHOWNORMAL)

    createFont()
    G.hwnd = overlayHwnd
    G.classAtom = classAtom
    G.classNamePtr = classNamePtr
    lastPX, lastPY, lastW, lastH = -1, -1, -1, -1
    needRedraw = true
    messages = {}
    G.messages = messages
    return true
end

local function ensureWindow()
    if overlayHwnd ~= 0 and user32.IsWindow(overlayHwnd) ~= 0 then
        return true
    end
    overlayHwnd = 0
    G.hwnd = 0
    return createWindow()
end

local function init()
    local ok, fn = pcall(function() return user32.mouse_event end)
    if ok and fn then mouseEvent = fn end
    if overlayHwnd ~= 0 and user32.IsWindow(overlayHwnd) ~= 0 then
        return true
    end
    return createWindow()
end

--====================================================
-- DRAW WIDGET
--====================================================
local function fillRect(hdc, x, y, w, h, color)
    local b = gdi32.CreateSolidBrush(color)
    mem.u4[rectBuf + 0]  = x
    mem.u4[rectBuf + 4]  = y
    mem.u4[rectBuf + 8]  = x + w
    mem.u4[rectBuf + 12] = y + h
    user32.FillRect(hdc, rectBuf, b)
    gdi32.DeleteObject(b)
end

local OUTLINE_COLOR = 0x505050

local function drawText(hdc, text, x, y, w, h, color)
    -- 8-directional contour
    gdi32.SetTextColor(hdc, OUTLINE_COLOR)
    for dx = -1, 1 do
        for dy = -1, 1 do
            if dx ~= 0 or dy ~= 0 then
                mem.u4[drawRect + 0]  = x + dx
                mem.u4[drawRect + 4]  = y + dy
                mem.u4[drawRect + 8]  = x + dx + w
                mem.u4[drawRect + 12] = y + dy + h
                user32.DrawTextA(hdc, text, #text, drawRect,
                    DT_LEFT + DT_SINGLELINE + DT_NOCLIP)
            end
        end
    end
    -- Main text
    gdi32.SetTextColor(hdc, color)
    mem.u4[drawRect + 0]  = x
    mem.u4[drawRect + 4]  = y
    mem.u4[drawRect + 8]  = x + w
    mem.u4[drawRect + 12] = y + h
    user32.DrawTextA(hdc, text, #text, drawRect,
        DT_LEFT + DT_SINGLELINE + DT_NOCLIP)
end


local function clearOverlay()
    if not ensureWindow() then return end
    pcall(function()
        local hdc = user32.GetDC(overlayHwnd)
        if not hdc or hdc == 0 then return end
        user32.GetClientRect(overlayHwnd, clientRect)
        fillRect(hdc, 0, 0, mem.u4[clientRect + 8], mem.u4[clientRect + 12], COLOR_KEY)
        user32.ReleaseDC(overlayHwnd, hdc)
    end)
end

local function syncPosition()
    local gameHwnd = mem.u4[offsets.MainWindow]
    if not gameHwnd or gameHwnd == 0 then return end
    if user32.IsWindow(gameHwnd) == 0 then return end

    user32.GetClientRect(gameHwnd, clientRect)
    local w = mem.u4[clientRect + 8]
    local h = mem.u4[clientRect + 12]
    mem.u4[pointBuf + 0] = 0
    mem.u4[pointBuf + 4] = 0
    user32.ClientToScreen(gameHwnd, pointBuf)
    local px = mem.u4[pointBuf + 0]
    local py = mem.u4[pointBuf + 4]

    if px ~= lastPX or py ~= lastPY or w ~= lastW or h ~= lastH then
        lastPX, lastPY, lastW, lastH = px, py, w, h
        user32.SetWindowPos(overlayHwnd, -1, px, py, w, h, SWP_NOACTIVATE)
        screenW = w
        screenH = h

        -- Y: game window scale (retains game viewport vertical positioning)
        gameScale = math.min(w / CONFIG.gameW, h / CONFIG.gameH)
        gameOffsetY = math.floor(h - CONFIG.gameH * gameScale)
        baseScaleY = gameScale * CONFIG.gameH / CONFIG.baseH

        -- X: full window width scale
        gameOffsetX = 0
        baseScaleX = screenW / CONFIG.baseW

        -- game UI: uniform scale, centered horizontally (used by anchor = "game")
        baseScaleUI = gameScale * CONFIG.gameW / CONFIG.baseW

        needRedraw = true
        createFont()
    end
end


local function simulateRightClick()
    if not mouseEvent then return end
    pcall(function()
        mouseEvent(MOUSEEVENTF_RIGHTDOWN, 0, 0, 0, 0)
        mouseEvent(MOUSEEVENTF_RIGHTUP, 0, 0, 0, 0)
    end)
end

local function screenScale(val)
    return math.max(1, math.floor(val * baseScaleX))
end

local function getLineColor(idx, total, baseColor)
    local bc = baseColor or CONFIG.newestColor
    if total <= 1 then return bc end
    local t = idx / (total - 1)
    local nr = bc % 256
    local ng = math.floor(bc / 256) % 256
    local nb = math.floor(bc / 65536) % 256
    local orr = CONFIG.oldestColor % 256
    local og = math.floor(CONFIG.oldestColor / 256) % 256
    local ob = math.floor(CONFIG.oldestColor / 65536) % 256
    local r = math.floor(nr + (orr - nr) * t)
    local g = math.floor(ng + (og - ng) * t)
    local b = math.floor(nb + (ob - nb) * t)
    return r + g * 256 + b * 65536
end

local function drawOverlay()
    if not ensureWindow() then return end
    syncPosition()
    checkDamageFlush()
	
	-- Clear old entries in the log after some time
    if overlayActive and messages[0] then
        if os.clock() - lastMessageTime > CONFIG.LogClearDelay then
            messages = {}
            G.messages = messages
            clearOverlay()
            needRedraw = false
            return
        end
    end
	
    if not overlayActive then
        if needRedraw then
            needRedraw = false
            clearOverlay()
        end
        return
    end

    needRedraw = true

    local ch = math.max(1, math.floor(CONFIG.textH * baseScaleY))
    local lineH = math.max(1, math.floor(CONFIG.lineSpacing * baseScaleY))

    local cw, sx, sy
    if CONFIG.anchor == "game" then
        -- game coordinates (640x480): the game UI is scaled uniformly and centered,
        -- so X is measured from the screen center with the same scale
        local baseX = (CONFIG.gx - CONFIG.gameW / 2) * toBaseX
        local baseY = CONFIG.gy * toBaseY
        cw = math.max(1, math.floor(CONFIG.textW * baseScaleUI))
        sx = math.floor(screenW / 2 + baseX * baseScaleUI)
        sy = math.floor(gameOffsetY + baseY * baseScaleY)
    else
        -- absolute (1920x1200): X follows the full window width
        cw = screenScale(CONFIG.textW)
        sx = math.floor(gameOffsetX + CONFIG.ax * baseScaleX)
        sy = math.floor(gameOffsetY + CONFIG.ay * baseScaleY)
    end

    local n = CONFIG.maxMessages

    local ok, err = pcall(function()
        local hdc = user32.GetDC(overlayHwnd)
        if not hdc or hdc == 0 then return end

        user32.GetClientRect(overlayHwnd, clientRect)
        fillRect(hdc, 0, 0, mem.u4[clientRect + 8], mem.u4[clientRect + 12], COLOR_KEY)

        local oldFont = gdi32.SelectObject(hdc, hFont)
        gdi32.SetBkMode(hdc, 1)

        for i = 0, n - 1 do
            local entry = messages[i]
            if entry then
                local msg, dk
                if type(entry) == "string" then
                    msg = entry
                else
                    msg = entry.text
                    dk = entry.damageKind
                end
                if msg and msg ~= "" then
                    local ly = sy + i * lineH
                    fillRect(hdc, sx, ly, cw, ch, COLOR_KEY)
                    local baseColor = (dk ~= nil and damageTypeColors[dk]) or CONFIG.newestColor
                    local color = getLineColor(i, n, baseColor)
                    drawText(hdc, msg, sx, ly, cw, ch, color)
                end
            end
        end

        gdi32.SelectObject(hdc, oldFont)
        user32.ReleaseDC(overlayHwnd, hdc)
    end)

    if not ok then
        MF.LogWarning("%s: draw error: %s", LogId, tostring(err))
    end
end

--====================================================
-- INITIALIZATION
--====================================================
if not init() then
    MF.LogWarning("%s: Init failed", LogId)
    return
end

MF.LogInfo("%s: Loaded. active=%s hwnd=%s",
    LogId, tostring(overlayActive), tostring(overlayHwnd))

--====================================================
-- ShowMovie: hide widget when cutscenes are shown
--====================================================
function events.ShowMovie(t)
    cutsceneActive = true
    clearOverlay()
end

--====================================================
-- PostRender
--====================================================
function events.PostRender()
    if cutsceneActive and Game.CurrentScreen ~= 16 then
        cutsceneActive = false
        needRedraw = true
    end

    if cutsceneActive then
        afterDrawFired = false
        return
    end

    if not afterDrawFired then
        if not dialogActive then
            dialogActive = true
            clearOverlay()
        end
        if postRenderFallback > 0 then
            postRenderFallback = postRenderFallback - 1
            drawOverlay()
        end
    else
        if dialogActive then
            dialogActive = false
            needRedraw = true
        end
        postRenderFallback = 0
    end
    afterDrawFired = false
end

--====================================================
-- AfterDrawNoDialogs
--====================================================
function events.AfterDrawNoDialogs()
    afterDrawFired = true
    if cutsceneActive then return end
    if dialogActive then
        dialogActive = false
        needRedraw = true
        simulateRightClick()
    end
    drawOverlay()
end

--====================================================
-- AfterLoadMap
--====================================================
function events.AfterLoadMap()
    overlayActive = loadOverlayState()
    dialogActive = false
    afterDrawFired = false
    cutsceneActive = false
    needRedraw = true
    lastPX, lastPY, lastW, lastH = -1, -1, -1, -1
    ensureWindow()
    postRenderFallback = 300
    flushDamageAccum()
end

--====================================================
-- B: toggle on/off
--====================================================
function events.KeyDown(t)
    if t.Key == const.Keys.B then
        overlayActive = not overlayActive
        if vars then
            vars.CombatLogActive = overlayActive
        end
        dialogActive = false
        cutsceneActive = false
        needRedraw = true
        if not overlayActive then
            messages = {}
            G.messages = messages
            clearOverlay()
        end
        simulateRightClick()
        Game.ShowStatusText("Combat Log " ..
            (overlayActive and "ON" or "OFF"))
    end
end

MF.LogInit2(LogId)
