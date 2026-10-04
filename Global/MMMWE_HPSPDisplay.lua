local LogId = "HPSPOverlay"
local MF = Merge.Functions
MF.LogInit1(LogId)

local MC = Merge.Consts
local MO = Merge.Offsets

local PLAYER_BUFFS_COUNT    = MC.PlayerBuffsCount or 34       -- 27 + 7
local PLAYER_BUFFS2_COUNT   = MC.PlayerBuffs2Count or 7
local PLAYER_DEBUFFS_COUNT  = MC.PlayerDebuffsCount or 20
local PARTY_BUFFS_COUNT     = MC.PartyBuffsCount or 26        -- 20 + 6
local PARTY_BUFFS2_COUNT    = MC.PartyBuffs2Count or 6
local PARTY_DEBUFFS_COUNT   = MC.PartyDebuffsCount or 11
local PLAYER_BUFFS2_START   = 27                              -- 0-26
local PARTY_BUFFS2_START    = 20                               -- 0-19


-- HP/SP Text Overlay + Conditions + Buffs — centered, 1920x1200 base, _G persistence
local user32 = mem.dll.user32
local gdi32 = mem.dll.gdi32
local kernel32 = mem.dll.kernel32

--====================================================
-- КОНФИГ
--====================================================
local CONFIG = {
    baseW    = 1920,
    baseH    = 1200,
    gameW    = 640,
    gameH    = 480,

    fontSize = 24,
    textW    = 180,
    textH    = 18,

    centerPortraits = true,

    -- HP/SP positions (in 1920x1200 coords, dy = offset relative to portrait anchor)
    hp = {
        [0] = {anchor = "portrait", dx = 0, dy = -80},
        [1] = {anchor = "portrait", dx = 0, dy = -80},
        [2] = {anchor = "portrait", dx = 0, dy = -80},
        [3] = {anchor = "portrait", dx = 0, dy = -80},
        [4] = {anchor = "portrait", dx = 0, dy = -80},
    },
    sp = {
        [0] = {anchor = "portrait", dx = 0, dy = -54},
        [1] = {anchor = "portrait", dx = 0, dy = -54},
        [2] = {anchor = "portrait", dx = 0, dy = -54},
        [3] = {anchor = "portrait", dx = 0, dy = -54},
        [4] = {anchor = "portrait", dx = 0, dy = -54},
    },

    --=== Debuffs (Game.PlayersExtra[i].Debuffs[]) ===
    debuffDY       = 880,   
    debuffW        = 180,
    debuffH        = 18,
    debuffLineH   = 20,
    maxDebuffLines = 3,

    --=== Buffs (SpellBuffs + SpellBuffs2) ===
    buffStartDY  = 10,   
    buffW        = 180,
    buffH        = 18,
    buffLineH   = 24,
    maxBuffLines = 8,

    --=== Party buffs (Party.SpellBuffs2) ===
    partyBuffDY       = 970,
    partyBuffW        = 200,
    partyBuffH        = 18,
    partyBuffLineH   = 24,
    maxPartyBuffLines = 10,

    --=== Party debuffs (Party.Debuffs) ===
    partyDebuffDY       = 106,
    partyDebuffW        = 200,
    partyDebuffH        = 18,
    partyDebuffLineH   = 24,
    maxPartyDebuffLines = 4,

    condFontSize = 22,
    buffFontSize = 22,

    -- X-offsets (in 1920x1200 coords)
    -- For player widgets: offset relative to portrait anchor
    debuffDX      = 0,
    buffDX        = 0,
    -- For party widgets: "center" or absolute X in 1920x1200 coords
    partyBuffDX   = 65,
    partyDebuffDX = 65,
	-- Y anchor = true: align line output start at bottom DY of text block
    partyBuffBottomAnchor   = true,
    partyDebuffBottomAnchor = true,
	debuffBottomAnchor 		= true,
}

--====================================================
-- DYNAMIC TABLES
--====================================================
local debuffInfo    = {}
local buffInfo       = {}
local buff2Info      = {}
local partyBuff2Info = {}
local partyDebuffInfo = {}
local partyBuffNames = {}

-- Default debuff colors and labels
local debuffColors = {
    [0]  = {color = 0xAA0055, label = "Curse"				},
    [1]  = {color = 0x00AA88, label = "Weakness"        	},
    [2]  = {color = 0xFF7722, label = "Sleep"           	},
    [3]  = {color = 0x0088AA, label = "Fear"            	},
    [4]  = {color = 0x00DD11, label = "Drunkedness"     	},
    [5]  = {color = 0x00FFFF, label = "Insanity"        	},
    [6]  = {color = 0x22CC22, label = "Poisoning (light)" 	},
    [7]  = {color = 0x2255AA, label = "Disease (light)"   	},
    [8]  = {color = 0x22CC22, label = "Poisoning (moderate)"},
    [9]  = {color = 0x2255AA, label = "Disease (moderate)"  },
    [10] = {color = 0x22CC22, label = "Poisoning (severe)"  },
    [11] = {color = 0x2255AA, label = "Disease (severe)"    },
    [12] = {color = 0xFFCCAA, label = "Paralysis"       	},
    [13] = {color = 0xCCCCCC, label = "Faint"     			},
    [14] = {color = 0x666666, label = "Death Decay"         },
    [15] = {color = 0x337799, label = "Stoned"          	},
    [16] = {color = 0x0000FF, label = "Desintegration"     	},
	[17] = {color = 0x717919, label = "Zombie"          	},
}

-- Extra debuffs (indexes 17-19 + previous 0-16)
local debuffExtraLabels = {
    [17] = {label = "Morbid Transform", color = 0x717919},  -- Morbid Transformation
    [18] = {label = "Feeblemind", color = 0x00DDFF},  -- Feebleminded
    [19] = {label = "Unarmed", color = 0xCCCCCC},  -- Unarmed
}

-- Extra buffs2 colors
local buff2Colors = {
    [0] = {label = "Spirit Res", color = 0xD3D3D3},  -- Spirit Resistance
    [1] = {label = "Light Res", color = 0xFAFAFA},  -- Light Resistance
    [2] = {label = "Dark Res", color = 0x6A6A6A},  -- Dark Resistance
    [3] = {label = "Unk3", color = 0xCCCCCC},
    [4] = {label = "Restore HP", color = 0x6666FF},  -- Restore Health
    [5] = {label = "Restore SP", color = 0xFF6633},  -- Restore Mana
    [6] = {label = "Unk6", color = 0xCCCCCC},
}

local function buildAllTables()
    --=== Debuffs (from 0 to PLAYER_DEBUFFS_COUNT-1) ===
    debuffInfo = {}
    for id = 0, PLAYER_DEBUFFS_COUNT - 1 do
        local info
        if id <= 16 then
            -- Condition-based debuffs
			local generic = debuffColors[id]
            info = {id = id, label = generic and generic.label or ("D" .. id),
                    color = generic.color or 0xCCCCCC}
        else
            -- Extra debuffs
            local extra = debuffExtraLabels[id]
            info = {id = id, label = extra and extra.label or ("D" .. id),
                    color = extra and extra.color or 0xCCCCCC}
        end
        debuffInfo[#debuffInfo + 1] = info
    end

    --=== Original player buffs (0-26) ===
    buffInfo = {}
    if const and const.PlayerBuff then
        for name, id in pairs(const.PlayerBuff) do
            if id >= 0 and id < PLAYER_BUFFS2_START then
                buffInfo[#buffInfo + 1] = {
                    id = id,
                    name = name,
                    label = name,--:sub(1, 5),
                    source = "spell",
                }
            end
        end
    else
        local names = {"Bless","Haste","Shield","Heroism","Stone Skin",
            "Feather Fall","Water Walk","Water Breathing","Fly",
            "Fire Res","Air Res","Water Res","Earth Res",
            "Mind Res","Body Res",
            "Pain Reflect","Hammerhands"}
        for i, name in ipairs(names) do
            buffInfo[#buffInfo + 1] = {
                id = i - 1, name = name, label = name, source = "spell",
            }
        end
    end
    table.sort(buffInfo, function(a, b) return a.id < b.id end)

    --=== Buffs2 (27-33) ===
    buff2Info = {}
    for idx = 0, PLAYER_BUFFS2_COUNT - 1 do
        local info = buff2Colors[idx] or {label = "B2" .. idx, color = 0xCCCCCC}
        buff2Info[#buff2Info + 1] = {
            idx = idx,
            label = info.label,
            color = info.color,
            name = "Buff2-" .. idx,
        }
        -- Insert into buffInfo table
        buffInfo[#buffInfo + 1] = {
            id = PLAYER_BUFFS2_START + idx,
            name = "Buff2-" .. idx,
            label = info.label,
            color = info.color,
            source = "buffs2",
        }
    end

    --=== Party buffs2 (20-25) ===
    partyBuff2Info = {}
    for idx = 0, PARTY_BUFFS2_COUNT - 1 do
        partyBuff2Info[#partyBuff2Info + 1] = {
            idx = idx,
            label = "PB" .. (PARTY_BUFFS2_START + idx),
            color = 0xCCCCCC,
            name = "Party Buff " .. (PARTY_BUFFS2_START + idx),
        }
    end

    --=== Party debuffs (0-10) ===
    partyDebuffInfo = {}
    for idx = 0, PARTY_DEBUFFS_COUNT - 1 do
        partyDebuffInfo[#partyDebuffInfo + 1] = {
            idx = idx,
            label = idx == 0 and "Slow" or ("PD" .. idx),
            color = idx == 0 and 0x00AAFF or 0x6666FF,
            name = "Party Debuff " .. idx,
        }
    end

    --=== Original party buffs (0-19) ===
    partyBuffNames = {}
    if const and const.PartyBuff then
        for name, id in pairs(const.PartyBuff) do
            if id >= 0 and id < PARTY_BUFFS2_START then
                partyBuffNames[id + 1] = name
            end
        end
    else
        partyBuffNames = {"Wizard Eye","Torch Light","Feather Fall","Water Walk",
            "Water Breathing","Fly","Fire Res","Air Res",
            "Water Res","Earth Res","Mind Res","Body Res"}
    end

    MF.LogInfo("%s: Tables built: %d debuff, %d buffs, %d partyBuffs",
        LogId, #debuffInfo, #buffInfo, #partyBuffNames)
end

--====================================================
-- MEMORY ADDRESSES
--====================================================
local ADDR_PORTRAIT_X   = 0x4FD9D0
local ADDR_HP_BAR_X     = 0x4F39AC
local ADDR_SP_BAR_X     = 0x4F39C0
local ADDR_PLAYER_COUNT = 0xB7CA60

local UI_PORTRAIT_Y = 28
local UI_BAR_Y      = 40

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
local COLOR_KEY         = 0x120012
local DT_CENTER           = 0x00000001
local DT_SINGLELINE     = 0x00000020
local DT_NOCLIP         = 0x00000100

local MOUSEEVENTF_RIGHTDOWN = 0x0008
local MOUSEEVENTF_RIGHTUP   = 0x0010

--====================================================
-- _G PERSISTENCY
--====================================================
if not _G.MMOverlay then
    _G.MMOverlay = {}
end
local G = _G.MMOverlay

local function loadOverlayState()
    if vars and vars.OverlayActive ~= nil then
        return vars.OverlayActive
    end
    return true
end

local overlayActive  = loadOverlayState()
local overlayHwnd    = 0
local hFont          = 0
local hFontSmall     = 0
local classAtom      = 0
local classNamePtr   = 0
local lastFontKey    = ""
local lastFontSmallKey = ""

if G.hwnd and G.hwnd ~= 0 and user32.IsWindow(G.hwnd) ~= 0 then
    overlayHwnd = G.hwnd
    hFont = G.font or 0
    hFontSmall = G.fontSmall or 0
    classAtom = G.classAtom or 0
    classNamePtr = G.classNamePtr or 0
end

local rectBuf    = mem.StaticAlloc(16)
local clientRect = mem.StaticAlloc(16)
local drawRect   = mem.StaticAlloc(16)
local pointBuf   = mem.StaticAlloc(8)
local lastValues = {}
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
local centerOffset = 0

--====================================================
-- GAME TIME
--====================================================
local TIME_MINUTE = const.Minute or 256
local TIME_HOUR   = const.Hour or (256 * 60)
local TIME_DAY    = const.Day or (256 * 60 * 24)

local function formatTime(expireTime, currentTime)
    local remaining = expireTime - currentTime
    if remaining <= 0 then return "0m" end
    if remaining < TIME_HOUR then
        return math.ceil(remaining / TIME_MINUTE) .. "m"
    elseif remaining < TIME_DAY then
        local h = math.floor(remaining / TIME_HOUR)
        local m = math.ceil((remaining - h * TIME_HOUR) / TIME_MINUTE)
        if m == 60 then return (h + 1) .. "h" end
        return h .. "h " .. (m > 0 and m or "")..(m > 0 and "m" or "")
    else
        local d = math.floor(remaining / TIME_DAY)
        local h = math.ceil((remaining - d * TIME_DAY) / TIME_HOUR)
        if h == 24 then return (d + 1) .. "d" end
        return d .. "d " .. (h > 0 and h .. "h" or "")
    end
end

--====================================================
-- READ PORTRAIT POSITIONS FROM STACK + TEXT ALIGNMENT AT CENTER 
--====================================================
local function getUISetsParams()
    local ptr = 0
    pcall(function()
        ptr = Merge and Merge.Offsets and Merge.Offsets.UISetsParams or 0
    end)
    return ptr
end

local function getGamePositions()
    local nPlayers = mem.u4[ADDR_PLAYER_COUNT] or 0
    if nPlayers > 5 then nPlayers = 5 end
    if nPlayers < 1 then nPlayers = 1 end

    local uiParams = getUISetsParams()
    local portraitY = 389
    local barY = 430
    if uiParams and uiParams ~= 0 then
        portraitY = mem.i4[uiParams + UI_PORTRAIT_Y] or 389
        barY = mem.i4[uiParams + UI_BAR_Y] or 430
    end

    local portraitX = {}
    local hpBarX = {}
    local spBarX = {}

    for i = 0, nPlayers - 1 do
        portraitX[i] = mem.i2[ADDR_PORTRAIT_X + i * 2] or 0
        hpBarX[i]    = mem.i4[ADDR_HP_BAR_X + i * 4] or 0
        spBarX[i]    = mem.i4[ADDR_SP_BAR_X + i * 4] or 0
    end

    if CONFIG.centerPortraits and nPlayers > 0 then
        local firstX = portraitX[0]+30
        local lastX  = portraitX[nPlayers - 1]+30
        local groupCenter = (lastX + firstX) / 2
        centerOffset = (CONFIG.gameW / 2) - groupCenter
    else
        centerOffset = 0
    end

    return nPlayers, portraitX, hpBarX, spBarX, portraitY, barY
end

--====================================================
-- COORD CALCULATIONS
--====================================================
local toBaseX = CONFIG.baseW / CONFIG.gameW
local toBaseY = CONFIG.baseH / CONFIG.gameH

local function labelScreenXY(cfg, portraitX_i, hpBarX_i, spBarX_i, portraitY, barY)
    local baseX, baseY
    if cfg.anchor == "absolute" then
        baseX = cfg.ax or 0
        baseY = cfg.ay or 0
    else
        local gameX, gameY
        if cfg.anchor == "hpbar" then
            gameX = hpBarX_i + centerOffset
            gameY = barY
        elseif cfg.anchor == "spbar" then
            gameX = spBarX_i + centerOffset
            gameY = barY
        else
            gameX = portraitX_i + centerOffset
            gameY = portraitY
        end
        baseX = gameX * toBaseX + (cfg.dx or 0)
        baseY = gameY * toBaseY + (cfg.dy or 0)
    end
    return math.floor(gameOffsetX + baseX * baseScaleX),
           math.floor(gameOffsetY + baseY * baseScaleY)
end

-- Portrait column X coord in screen coordinate system
local function columnScreenX(portraitX_i)
    local gameX = portraitX_i + centerOffset
    local baseX = gameX * toBaseX
    return math.floor(gameOffsetX + baseX * baseScaleX)
end

--====================================================
-- DATA COLLECTION
--====================================================
--====================================================
-- DATA COLLECTION: DEBUFFS
--====================================================

local function getDebuffs(player, playerIndex)
    local active = {}
    if not player then return active end
pcall(function()
        local extraId = playerIndex
        pcall(function() extraId = player.RosterBitIndex - 400 end)
        local extra = Game.PlayersExtra[extraId]
        if not extra or not extra.Debuffs then return end
        for _, info in ipairs(debuffInfo) do
            if info.id < PLAYER_DEBUFFS_COUNT then
                local buff = extra.Debuffs[info.id]
                if buff then
                    local expireTime = buff.ExpireTime or 0
                    if expireTime and expireTime > 0 then
                        active[#active + 1] = {
                            label = info.label,
                            color = info.color,
                            power = buff.Power or 0,
                            expireTime = expireTime,
                        }
                    end
                end
            end
        end
    end)
    return active
end

--====================================================
-- DATA COLLECTION: BUFFS (SpellBuffs + SpellBuffs2)
--====================================================
local function getBuffs(player, playerIndex, currentTime)
    local active = {}
    if not player then return active end

    -- Original SpellBuffs (0-26)
    for _, info in ipairs(buffInfo) do
        if info.source == "spell" then
            local buff = nil
            pcall(function() buff = player.SpellBuffs[info.id] end)
            if buff then
                local expireTime = nil
                local power = nil
                pcall(function() expireTime = buff.ExpireTime end)
                pcall(function() power = buff.Power end)
                if expireTime and expireTime > currentTime then
                    active[#active + 1] = {
                        label = info.label,
                        name = info.name,
                        power = power or 0,
                        timeStr = formatTime(expireTime, currentTime),
                        expireTime = expireTime,
                    }
                end
            end
        end
    end

    -- SpellBuffs2 (27-33) via Game.PlayersExtra
    pcall(function()
        local extraId = playerIndex
        pcall(function() extraId = player.RosterBitIndex - 400 end)
        local extra = Game.PlayersExtra[extraId]
        if not extra or not extra.SpellBuffs2 then return end
        for _, info in ipairs(buff2Info) do
            local buff = extra.SpellBuffs2[PLAYER_BUFFS2_START + info.idx]
            if buff then
                local expireTime = buff.ExpireTime or 0
                if expireTime and expireTime > currentTime then
                    active[#active + 1] = {
                        label = info.label,
                        name = info.name,
                        power = buff.Power or 0,
                        timeStr = formatTime(expireTime, currentTime),
                        expireTime = expireTime,
                        color = info.color,
                    }
                end
            end
        end
    end)


    -- Descending sort by expireTime
    table.sort(active, function(a, b) return a.expireTime > b.expireTime end)
    return active
end

--====================================================
-- DATA COLLECTION: PARTY BUFFS/DEBUFFS
--====================================================
local function getPartyBuffs(currentTime)
    local active = {}

    -- Original party buffs (0-19) — Party.SpellBuffs[]
    pcall(function()
        if not Party.SpellBuffs then return end
        for i = 0, PARTY_BUFFS2_START - 1 do
            local buff = Party.SpellBuffs[i]
            if buff then
                local expireTime = buff.ExpireTime or 0
                if expireTime and expireTime > currentTime then
                    local label = "PB" .. i
                    local name = "Party Buff " .. i
                    if partyBuffNames[i + 1] then
                        label = partyBuffNames[i + 1]--:sub(1, 4)
                        name = partyBuffNames[i + 1]
                    end
                    active[#active + 1] = {
                        label = label, name = name,
                        timeStr = formatTime(expireTime, currentTime),
                        expireTime = expireTime, color = 0x88FF88,
                    }
                end
            end
        end
    end)


    -- Extra party buffs (20-25) — Party.SpellBuffs2[]
    pcall(function()
        if not Party.SpellBuffs2 then return end
        for _, info in ipairs(partyBuff2Info) do
            local buff = Party.SpellBuffs2[PARTY_BUFFS2_START + info.idx]
            if buff then
                local expireTime = buff.ExpireTime or 0
                if expireTime and expireTime > currentTime then
                    active[#active + 1] = {
                        label = info.label,
                        name = info.name,
                        timeStr = formatTime(expireTime, currentTime),
                        expireTime = expireTime,
                        color = info.color,
                    }
                end
            end
        end
    end)

    table.sort(active, function(a, b) return a.expireTime > b.expireTime end)
    return active
end

local function getPartyDebuffs(currentTime)
    local active = {}
    pcall(function()
        if not Party.Debuffs then return end
        for i = 0, PARTY_DEBUFFS_COUNT - 1 do
            local buff = Party.Debuffs[i]
            if buff then
                local expireTime = buff.ExpireTime or 0
                if expireTime and expireTime > 0 then
                    local label = "PD" .. i
                    local color = 0x6666FF
                    for _, info in ipairs(partyDebuffInfo) do
                        if info.idx == i then
                            label = info.label
                            color = info.color
                            break
                        end
                    end
                    active[#active + 1] = {
                        label = label,
                        name = "Party Debuff " .. i,
                        timeStr = formatTime(expireTime, currentTime),
                        expireTime = expireTime,
                        color = color,
                    }
                end
            end
        end
    end)
    table.sort(active, function(a, b) return a.expireTime > b.expireTime end)
    return active
end

local function getValues(nPlayers)
    local v = {}
    local currentTime = Game.Time or 0
    for i = 0, nPlayers - 1 do
        local p = Party.Players[i]
        if p then
            local maxHP, maxSP = 0, 0
            pcall(function() maxHP = p:GetFullHP() end)
            pcall(function() maxSP = p:GetFullSP() end)
            v[i] = {
                hp = p.HP or 0,
                sp = p.SP or 0,
                maxHP = maxHP,
                maxSP = maxSP,
                exists = true,
                debuffs = getDebuffs(p, i),
                buffs = getBuffs(p, i, currentTime),
            }
        else
            v[i] = {hp = -1, sp = -1, maxHP = 0, maxSP = 0, exists = false,
                    debuffs = {}, buffs = {}}
        end
    end
    v.partyBuffs = getPartyBuffs(currentTime)
    v.partyDebuffs = getPartyDebuffs(currentTime)

    -- Diagnostics: data sources availability check
    if not _G.MMOverlay._debugLogged then
            local extraOk = false
            pcall(function() extraOk = Game.PlayersExtra[0] ~= nil end)
            MF.LogInfo("%s: Game.PlayersExtra: %s", LogId, tostring(extraOk))

            local partyBuffs2Ok = false
            pcall(function() partyBuffs2Ok = Party.SpellBuffs2 ~= nil end)
            MF.LogInfo("%s: Party.SpellBuffs2: %s", LogId, tostring(partyBuffs2Ok))

            local partyDebuffsOk = false
            pcall(function() partyDebuffsOk = Party.Debuffs ~= nil end)
            MF.LogInfo("%s: Party.Debuffs: %s", LogId, tostring(partyDebuffsOk))

            local condOk = false
            pcall(function() condOk = Party.Players[0].Conditions ~= nil end)
            MF.LogInfo("%s: player.Conditions: %s", LogId, tostring(condOk))

            local buffsOk = false
            pcall(function() buffsOk = Party.Players[0].SpellBuffs ~= nil end)
            MF.LogInfo("%s: player.SpellBuffs: %s", LogId, tostring(buffsOk))
        end

    -- Data content debug
    if not _G.MMOverlay._debugLogged then
        for i = 0, nPlayers - 1 do
            if v[i] and v[i].exists then
                local ds, bs = "", ""
                for _, d in ipairs(v[i].debuffs) do ds = ds .. d.label .. " " end
                for _, b in ipairs(v[i].buffs) do bs = bs .. b.label .. "(" .. b.timeStr .. ") " end
                MF.LogInfo("%s: P%d debuff=[%s] buff=[%s]",
                    LogId, i, cs, ds, bs)
            end
        end
        if v.partyBuffs and #v.partyBuffs > 0 then
            local ps = ""
            for _, pb in ipairs(v.partyBuffs) do ps = ps .. pb.label .. "(" .. pb.timeStr .. ") " end
             MF.LogInfo("%s: PartyBuffs: %s", LogId, ps)
        end
        if v.partyDebuffs and #v.partyDebuffs > 0 then
            local ps = ""
            for _, pb in ipairs(v.partyDebuffs) do ps = ps .. pb.label .. "(" .. pb.timeStr .. ") " end
            MF.LogInfo("%s: PartyDebuffs: %s", LogId, ps)
        end
        _G.MMOverlay._debugLogged = true
    end

    return v
end

local function valuesChanged(v, nPlayers)
    for i = 0, nPlayers - 1 do
        local a, b = v[i], lastValues[i]
        if not b then return true end
        if a.hp ~= b.hp or a.sp ~= b.sp or a.maxHP ~= b.maxHP or a.maxSP ~= b.maxSP then
            return true
        end
        -- Debuffs
        if #a.debuffs ~= #(b.debuffs or {}) then return true end
        for j = 1, #a.debuffs do
            local bd = b.debuffs and b.debuffs[j]
            if not bd or a.debuffs[j].label ~= bd.label then
                return true
            end
        end
        -- Buffs
        if #a.buffs ~= #b.buffs then return true end
        for j = 1, #a.buffs do
            if a.buffs[j].label ~= (b.buffs[j] and b.buffs[j].label)
               or a.buffs[j].timeStr ~= (b.buffs[j] and b.buffs[j].timeStr) then
                return true
            end
        end
    end
    -- Party buffs
    local pa, pb = v.partyBuffs or {}, lastValues.partyBuffs or {}
    if #pa ~= #pb then return true end
    for j = 1, #pa do
        if not pb[j] or pa[j].label ~= pb[j].label or pa[j].timeStr ~= pb[j].timeStr then
            return true
        end
    end
    -- Party debuffs
    local da, db = v.partyDebuffs or {}, lastValues.partyDebuffs or {}
    if #da ~= #db then return true end
    for j = 1, #da do
        if not db[j] or da[j].label ~= db[j].label or da[j].timeStr ~= db[j].timeStr then
            return true
        end
    end
    return false
end

--====================================================
-- WINDOW
--====================================================
local function createFont()
    local actualSize = math.max(8, math.floor(CONFIG.fontSize * baseScaleY))
    local key = tostring(actualSize)
    if key ~= lastFontKey or hFont == 0 then
        if hFont ~= 0 then gdi32.DeleteObject(hFont) end
        hFont = gdi32.CreateFontA(actualSize, 0, 0, 0, 700, 0, 0, 0, 1, 0, 0, 0, 0, "Book Antiqua")
        lastFontKey = key
        G.font = hFont
    end
    local smallSize = math.max(7, math.floor(CONFIG.condFontSize * baseScaleY))
    local skey = tostring(smallSize)
    if skey ~= lastFontSmallKey or hFontSmall == 0 then
        if hFontSmall ~= 0 then gdi32.DeleteObject(hFontSmall) end
        hFontSmall = gdi32.CreateFontA(smallSize, 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 5, 0, "Book Antiqua")
        lastFontSmallKey = skey
        G.fontSmall = hFontSmall
    end
end

local function createWindow()
    local hUser32 = kernel32.GetModuleHandleA("user32.dll")
    local defProc = kernel32.GetProcAddress(hUser32, "DefWindowProcA")
    if not defProc or defProc == 0 then return false end

    if classAtom == 0 then
        if classNamePtr == 0 then
            classNamePtr = mem.StaticAlloc(16)
            mem.copy(classNamePtr, "MMOverlay\0", 10)
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
    lastValues = {}
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
    buildAllTables()
    if overlayHwnd ~= 0 and user32.IsWindow(overlayHwnd) ~= 0 then
        return true
    end
    return createWindow()
end

--====================================================
-- DRAW WIDGETS
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
                    DT_CENTER + DT_SINGLELINE + DT_NOCLIP)
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
        DT_CENTER + DT_SINGLELINE + DT_NOCLIP)
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

local function hpColor(hp, maxHP)
    if maxHP <= 0 then return 0x666666 end
    local pct = hp / maxHP
	if pct > 1.00 then return 0x00FF00 end
    if pct > 0.50 then return 0xFFFFFF end
    if pct > 0.25 then return 0x00FFFF end
    return 0x0000FF
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

-- Widget scale on screen
local function screenScale(val)
    return math.max(1, math.floor(val * baseScaleX))
end

local function drawOverlay()
    if not ensureWindow() then return end
    syncPosition()

    if not overlayActive then
        if needRedraw then
            needRedraw = false
            clearOverlay()
        end
        return
    end

    local nPlayers, portraitX, hpBarX, spBarX, portraitY, barY = getGamePositions()

    local v = getValues(nPlayers)
    if needRedraw or valuesChanged(v, nPlayers) then
        lastValues = v
        needRedraw = true
    end

    if not needRedraw then return end
    needRedraw = false

    -- Widget scale on screen
    local cw = screenScale(CONFIG.textW)
    local ch = math.max(1, math.floor(CONFIG.textH * baseScaleY))

    local debuffW = screenScale(CONFIG.debuffW)
    local debuffH = math.max(1, math.floor(CONFIG.debuffH * baseScaleY))
    local debuffLineH = math.max(1, math.floor(CONFIG.debuffLineH * baseScaleY))
    local debuffScreenY = math.floor(gameOffsetY + CONFIG.debuffDY * baseScaleY)

    local buffW = screenScale(CONFIG.buffW)
    local buffH = math.max(1, math.floor(CONFIG.buffH * baseScaleY))
    local buffLineH = math.max(1, math.floor(CONFIG.buffLineH * baseScaleY))
    local buffStartScreenY = math.floor(gameOffsetY + CONFIG.buffStartDY * baseScaleY)

    local pBuffW = screenScale(CONFIG.partyBuffW)
    local pBuffH = math.max(1, math.floor(CONFIG.partyBuffH * baseScaleY))
    local pBuffLineH = math.max(1, math.floor(CONFIG.partyBuffLineH * baseScaleY))
    local pBuffScreenY = math.floor(gameOffsetY + CONFIG.partyBuffDY * baseScaleY)

    local pDebuffW = screenScale(CONFIG.partyDebuffW)
    local pDebuffH = math.max(1, math.floor(CONFIG.partyDebuffH * baseScaleY))
    local pDebuffLineH = math.max(1, math.floor(CONFIG.partyDebuffLineH * baseScaleY))
    local pDebuffScreenY = math.floor(gameOffsetY + CONFIG.partyDebuffDY * baseScaleY)

    local ok, err = pcall(function()
        local hdc = user32.GetDC(overlayHwnd)
        if not hdc or hdc == 0 then return end

        -- Clear all screens
        user32.GetClientRect(overlayHwnd, clientRect)
        fillRect(hdc, 0, 0, mem.u4[clientRect + 8], mem.u4[clientRect + 12], COLOR_KEY)

        --=== HP/SP TEXT ===
        local oldFont = gdi32.SelectObject(hdc, hFont)
        gdi32.SetBkMode(hdc, 1)

        for i = 0, nPlayers - 1 do
            local d = lastValues[i]
            local hpx, hpy = labelScreenXY(CONFIG.hp[i], portraitX[i], hpBarX[i], spBarX[i], portraitY, barY)
            local spx, spy = labelScreenXY(CONFIG.sp[i], portraitX[i], hpBarX[i], spBarX[i], portraitY, barY)
            fillRect(hdc, hpx, hpy, cw, ch, COLOR_KEY)
            fillRect(hdc, spx, spy, cw, ch, COLOR_KEY)

            if d and d.exists then
                drawText(hdc, string.format("%d/%d", d.hp, d.maxHP), hpx, hpy, cw, ch, hpColor(d.hp, d.maxHP))
                drawText(hdc, string.format("%d/%d", d.sp, d.maxSP), spx, spy, cw, ch, 0xFFCCAA)
            end
        end

        -- Switch to small font size for the rest of widgets
        gdi32.SelectObject(hdc, hFontSmall)

        --=== DEBUFFS (Game.PlayersExtra[i].Debuffs[]) ===
        for i = 0, nPlayers - 1 do
            local d = lastValues[i]
            if d and d.exists and #d.debuffs > 0 then
                local colX = columnScreenX(portraitX[i]) + math.floor(CONFIG.debuffDX * baseScaleX)
				for line = 1, math.min(#d.debuffs, CONFIG.maxDebuffLines) do
                    local db = d.debuffs[line]
                    local ly
                    if CONFIG.debuffBottomAnchor then
                        ly = debuffScreenY - line * debuffLineH
                    else
                        ly = debuffScreenY + (line - 1) * debuffLineH
                    end
                    fillRect(hdc, colX, ly, debuffW, debuffH, COLOR_KEY)
                    drawText(hdc, db.label, colX, ly, debuffW, debuffH, db.color)
                end
            end
        end

        --=== BUFFS (SpellBuffs + SpellBuffs2) ===
        for i = 0, nPlayers - 1 do
            local d = lastValues[i]
            if d and d.exists and #d.buffs > 0 then
                 local colX = columnScreenX(portraitX[i]) + math.floor(CONFIG.buffDX * baseScaleX)
                for line = 1, math.min(#d.buffs, CONFIG.maxBuffLines) do
                    local buff = d.buffs[line]
                    local by = buffStartScreenY + (line - 1) * buffLineH
                    fillRect(hdc, colX, by, buffW, buffH, COLOR_KEY)

                    local buffText = string.format("%s %s", buff.label, buff.timeStr)

                    local bColor
                    if buff.color then
                        bColor = buff.color
                    else
                        bColor = 0x88FF88
                        local remaining = buff.expireTime - (Game.Time or 0)
                        if remaining < TIME_HOUR then
                            bColor = 0x00AAFF
                        elseif remaining < TIME_HOUR * 3 then
                            bColor = 0x00FFFF
                        end
                    end
                    drawText(hdc, buffText, colX, by, buffW, buffH, bColor)
                end
            end
        end

        --=== PARTY BUFFS (Party.SpellBuffs2) ===
        if lastValues.partyBuffs and #lastValues.partyBuffs > 0 then
            local pBuffX
            if CONFIG.partyBuffDX == "center" then
                pBuffX = math.floor(gameOffsetX + CONFIG.baseW / 2 * baseScaleX - pBuffW / 2)
            else
                pBuffX = math.floor(gameOffsetX + CONFIG.partyBuffDX * baseScaleX)
            end


            for line = 1, math.min(#lastValues.partyBuffs, CONFIG.maxPartyBuffLines) do
                local pb = lastValues.partyBuffs[line]
                local ly
                if CONFIG.partyBuffBottomAnchor then
                    ly = pBuffScreenY - line * pBuffLineH
                else
                    ly = pBuffScreenY + (line - 1) * pBuffLineH
                end
                fillRect(hdc, pBuffX, ly, pBuffW, pBuffH, COLOR_KEY)

                local pbText = string.format("%s %s", pb.label, pb.timeStr)
                local pbColor = pb.color or 0x88FF88
                local remaining = pb.expireTime - (Game.Time or 0)
                if remaining < TIME_HOUR then
                    pbColor = 0x00AAFF
                elseif remaining < TIME_HOUR * 3 then
                    pbColor = 0x00FFFF
                end
                drawText(hdc, pbText, pBuffX, ly, pBuffW, pBuffH, pbColor)
            end
        end

        --=== PARTY DEBUFFS (Party.Debuffs) ===
        if lastValues.partyDebuffs and #lastValues.partyDebuffs > 0 then
            local pDebuffX
            if CONFIG.partyDebuffDX == "center" then
                pDebuffX = math.floor(gameOffsetX + CONFIG.baseW / 2 * baseScaleX - pDebuffW / 2)
            else
                pDebuffX = math.floor(gameOffsetX + CONFIG.partyDebuffDX * baseScaleX)
            end

            for line = 1, math.min(#lastValues.partyDebuffs, CONFIG.maxPartyDebuffLines) do
                local pd = lastValues.partyDebuffs[line]
                local ly
                if CONFIG.partyDebuffBottomAnchor then
                    ly = pDebuffScreenY - line * pDebuffLineH
                else
                    ly = pDebuffScreenY + (line - 1) * pDebuffLineH
                end
                fillRect(hdc, pDebuffX, ly, pDebuffW, pDebuffH, COLOR_KEY)

                local pdText = string.format("!%s %s", pd.label, pd.timeStr)
                local pdColor = pd.color or 0x6666FF
                local remaining = pd.expireTime - (Game.Time or 0)
                if remaining < TIME_HOUR then
                    pdColor = 0x00AAFF
                elseif remaining < TIME_HOUR * 3 then
                    pdColor = 0x00FFFF
                end
                drawText(hdc, pdText, pDebuffX, ly, pDebuffW, pDebuffH, pdColor)
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

MF.LogInfo("%s: Loaded. active=%s hwnd=%s buffs=%d",
    LogId, tostring(overlayActive), tostring(overlayHwnd), #buffInfo)

--====================================================
-- ShowMovie: hide widgets when cutscenes are shown
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
        lastValues = {}
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
            lastValues = {}
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
        lastValues = {}
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
    lastValues = {}
    lastPX, lastPY, lastW, lastH = -1, -1, -1, -1
    ensureWindow()
    postRenderFallback = 300
    buildAllTables()
	_G.MMOverlay._debugLogged = false
end

--====================================================
-- H: toggle on/off
--====================================================
function events.KeyDown(t)
    if t.Key == const.Keys.H then
        overlayActive = not overlayActive
        if vars then
            vars.OverlayActive = overlayActive
        end
        dialogActive = false
        cutsceneActive = false
        needRedraw = true
        lastValues = {}
        simulateRightClick()
        Game.ShowStatusText("HP/SP overlay " ..
            (overlayActive and "ON" or "OFF"))
    end
end

MF.LogInit2(LogId)