-- ========================================
-- Concurrent Enchantments v5.3 Final
-- Permanent + Temporary enchantment stacking
-- ========================================

local MF = Merge.Functions
local LogId = MF.LogInit1("ConcurrentEnchants")
local function log(fmt, ...) MF.LogInfo("[CE] " .. fmt, ...) end

-- Set to false to suppress per-hit combat logs
local DEBUG_HITS = false

local SavedPermBonus = {}
local PendingChecks = {}
local PendingExpires = {}
local CESaveData = {}

-- ========================================
-- DamageKind constants (from const.Damage)
-- ========================================

local DK = {
    Fire   = 0,  Air    = 1,  Water  = 2,  Earth  = 3,
    Phys   = 4,  Magic  = 5,  Spirit = 6,  Mind   = 7,
    Body   = 8,  Light  = 9,  Dark   = 10,
}

local DmgTypeToDK = {
    ["Fire"] = DK.Fire, ["Cold"] = DK.Water, ["Electrical"] = DK.Air,
    ["Body"] = DK.Body, ["Air"] = DK.Air, ["Water"] = DK.Water,
    ["Earth"] = DK.Earth, ["Spirit"] = DK.Spirit,
    ["Mind"] = DK.Mind, ["Light"] = DK.Light, ["Dark"] = DK.Dark,
}

local DKToResField = {
    [0]  = "FireResistance",   [1]  = "AirResistance",
    [2]  = "WaterResistance",  [3]  = "EarthResistance",
    [4]  = "PhysResistance",
    [6]  = "SpiritResistance", [7]  = "MindResistance",
    [8]  = "BodyResistance",   [9]  = "LightResistance",
    [10] = "DarkResistance",
}

-- ========================================
-- Monster resistance calculation
-- ========================================

local resPercentCache = {}

local function CalcMonResPercent(Res)
    if Res >= 65000 then return 0 end
    --if Res <= 0 then return 1 end
    local cached = resPercentCache[Res]
    if cached then return cached end
    local MonEffRes = Res + 30
    local p = 1 - 30 / MonEffRes
    local ResPercent = 1 - (0.5 * p + 0.25 * p^2 + 0.125 * p^3 + 0.0625 * p^4)
    resPercentCache[Res] = ResPercent
    return ResPercent
end

local function getMonsterRes(monsterIndex, damageKind)
    if not monsterIndex or monsterIndex < 0 then return 0 end
    if damageKind == DK.Magic then return 0 end

    local fname = DKToResField[damageKind]
    if not fname then return 0 end

    -- Primary: per-instance resistance (reflects buffs/debuffs)
    local ok, mon = pcall(function() return Map.Monsters[monsterIndex] end)
    if ok and mon then
        local ok2, res = pcall(function() return mon[fname] end)
        if ok2 and type(res) == "number" then return res end

        -- Fallback: base template via .Id
        local ok3, id = pcall(function() return mon.Id end)
        if ok3 and type(id) == "number" then
            local ok4, mt = pcall(function() return Game.MonstersTxt[id] end)
            if ok4 and mt then
                local ok5, res2 = pcall(function()
                    return mt.Resistances[damageKind]
                end)
                if ok5 and type(res2) == "number" then return res2 end
            end
        end
    end

    return 0
end

-- ========================================
-- Parse SPCITEMS damage table
-- ========================================

local EnchantDmg = {}

local function readCString(addr)
    local s = ""
    for i = 0, 255 do
        local ok, b = pcall(function() return mem.u1[addr + i] end)
        if not ok or not b or b == 0 then break end
        s = s .. string.char(b)
    end
    return s
end

local function initEnchantDmg()
    EnchantDmg = {}
    local spcTbl = Game.SpcItemsTxt
    if not spcTbl then
        log("WARNING: Game.SpcItemsTxt not found")
        return
    end

    local spcPtr = spcTbl["?ptr"]
    local spcCount = spcTbl.count or 145
    local entrySize = 0x1C  -- 28 bytes per record

    for idx = 0, spcCount - 1 do
        local entryAddr = spcPtr + idx * entrySize
        local ok, descPtr = pcall(function() return mem.u4[entryAddr + 4] end)
        if ok and descPtr and descPtr > 0x10000 then
            local desc = readCString(descPtr)

            local minD, maxD, dtype = string.match(
                desc, "Adds (%d+)-(%d+) points of (%a+) damage")
            if not minD then
                minD, dtype = string.match(
                    desc, "Adds (%d+) points of (%a+) damage")
                if minD then maxD = minD end
            end

            if minD and maxD then
                local dk = DmgTypeToDK[dtype]
                if dk then
                    -- SpcItemsTxt is 0-indexed; B2 on items is 1-indexed
                    EnchantDmg[idx] = {tonumber(minD), tonumber(maxD), dk}
                    log("EnchantDmg SpcIdx=%d B2=%d: %d-%d dk=%d (%s)",
                        idx, idx + 1, tonumber(minD), tonumber(maxD),
                        dk, dtype)
                end
            end
        end
    end

    local count = 0
    for _ in pairs(EnchantDmg) do count = count + 1 end
    log("Parsed %d enchant damage entries", count)
end

local function calcEnchantDamage(bonus2)
    local idx = bonus2 - 1
    if idx < 0 then return 0, nil end
    local data = EnchantDmg[idx]
    if not data then return 0, nil end
    if data[1] == data[2] then return data[1], data[3] end
    return math.random(data[1], data[2]), data[3]
end

-- ========================================
-- Part 1. Перехват перед наложением временного зачарования
-- Сохраняем постоянные бонусы и обнуляем, чтобы движок
-- записал только временное зачарование
-- ========================================

local function doSaveAndClear(itemPtr, spellName)
    if not itemPtr or itemPtr < 0x10000 or itemPtr > 0x10000000 then return end

    local bonus    = mem.u4[itemPtr + 4]
    local bonus2   = mem.u4[itemPtr + 0xC]
    local bonusStr = mem.u4[itemPtr + 8]

    if bonus == 0 and bonus2 == 0 and bonusStr == 0 then return end

    if not SavedPermBonus[itemPtr] and not PendingChecks[itemPtr] then
        log("%s: item %d B=%d B2=%d S=%d -> saving & clearing",
            spellName, mem.u4[itemPtr], bonus, bonus2, bonusStr)
        PendingChecks[itemPtr] = {
            Bonus = bonus, Bonus2 = bonus2, BonusStrength = bonusStr
        }
    end
    mem.u4[itemPtr + 4] = 0
    mem.u4[itemPtr + 0xC] = 0
    mem.u4[itemPtr + 8] = 0
end

mem.autohook2(0x42729D, function(d)
    doSaveAndClear(mem.u4[d.ebp - 0x24], "Fire Aura")
end)
mem.autohook2(0x42C14E, function(d)
    doSaveAndClear(mem.u4[d.ebp - 0x18], "Vampiric")
end)
mem.autohook2(0x4160F1, function(d)
    doSaveAndClear(d.ecx, "Potion A")
end)
mem.autohook2(0x4161A2, function(d)
    doSaveAndClear(d.ecx, "Potion B")
end)

-- ========================================
-- Part 2. Перехват истечения временного зачарования
-- Восстанавливаем сохранённые постоянные бонусы
-- ========================================

mem.autohook2(0x455B40, function(d)
    local itemPtr = d.ecx
    if SavedPermBonus[itemPtr] then
        log("Temp expiring for item %d", mem.u4[itemPtr])
        PendingExpires[itemPtr] = true
    end
end)

-- ========================================
-- Part 3. Concurrent damage via ItemAdditionalDamage
-- ========================================

_G.CE_PermHitQueue = _G.CE_PermHitQueue or {}

function events.ItemAdditionalDamage(t)
    -- Управление счётчиком вторичных вызовов
    if _G.CE_SecondaryResist and _G.CE_SecondaryResist > 0 then
        _G.CE_SecondaryResist = _G.CE_SecondaryResist - 1
    end
    _G.CE_SecondaryResist = (_G.CE_SecondaryResist or 0) + 1

    local item = t.Item
    if not item or item.Broken then return end

    local ptr = item["?ptr"]
    if not ptr then return end

    local saved = SavedPermBonus[ptr]
    if not saved then return end

    local bonus2 = saved.Bonus2
    local enchDmg, permDK = calcEnchantDamage(bonus2)
    if enchDmg <= 0 or not permDK then return end

    local tempDK = t.DamageKind or 0
    local monIdx = t.MonsterIndex or -1
    local resisted = 0

    if permDK == tempDK then
        -- Та же стихия: добавляем чистый урон, движок применит
        -- сопротивление один раз с правильной стихией
        t.Result = t.Result + enchDmg
        if DEBUG_HITS then
            log("[Stack-same] item=%d B2=%d +%d dk=%d mon=%d -> Result=%d",
                item.Number, bonus2, enchDmg, permDK, monIdx, t.Result)
        end
    else
        -- Разные стихии: применяем сопротивление вручную с permDK,
        -- снимаем HP напрямую. НЕ добавляем в t.Result — иначе движок
        -- применит monster_resists с tempDK (неправильная стихия)
        -- по уже резистнутому урону — двойное сопротивление
        local res = getMonsterRes(monIdx, permDK)
        local pct = CalcMonResPercent(res)
        resisted = round(enchDmg * pct)
        if resisted > 0 and t.Monster then
            t.Monster.HP = t.Monster.HP - resisted
        end
        if DEBUG_HITS then
            local immTag = res >= 65000 and " [IMMUNE]" or ""
            log("[Stack-diff] item=%d B2=%d +%d dk=%d mon=%d res=%d->%.1f%%%s->%d (direct HP), tempDK=%d",
                item.Number, bonus2, enchDmg, permDK, monIdx,
                res, pct * 100, immTag, resisted, tempDK)
        end
    end

    local permDmgForLog = (permDK == tempDK) and enchDmg or resisted
    if permDmgForLog > 0 then
        table.insert(_G.CE_PermHitQueue, {
            monsterIndex = monIdx,
            damageKind   = permDK,
            damage       = permDmgForLog,
            playerIndex  = t.PlayerIndex or 0,
        })
    end
end

-- ========================================
-- Part 4. Тик — подтверждение наложения / истечения
-- ========================================

function events.Tick()
    for ptr, data in pairs(PendingChecks) do
        local cond = mem.u4[ptr + 0x14]
        if bit.band(cond, 0x8) ~= 0 then
            if not SavedPermBonus[ptr] then
                SavedPermBonus[ptr] = data
                log("Enchant applied: item %d {B=%d B2=%d S=%d}",
                    mem.u4[ptr], data.Bonus, data.Bonus2, data.BonusStrength)
            end
        else
            if not SavedPermBonus[ptr] then
                mem.u4[ptr + 4] = data.Bonus
                mem.u4[ptr + 0xC] = data.Bonus2
                mem.u4[ptr + 8] = data.BonusStrength
            end
        end
        PendingChecks[ptr] = nil
    end

    for ptr, _ in pairs(PendingExpires) do
        if SavedPermBonus[ptr] then
            local saved = SavedPermBonus[ptr]
            mem.u4[ptr + 4] = saved.Bonus
            mem.u4[ptr + 0xC] = saved.Bonus2
            mem.u4[ptr + 8] = saved.BonusStrength
            if mmver > 6 then
                mem.u8[ptr + 0x1C] = 0
            end
            SavedPermBonus[ptr] = nil
            log("Expire: restored {B=%d B2=%d S=%d} for item %d",
                saved.Bonus, saved.Bonus2, saved.BonusStrength, mem.u4[ptr])
        end
        PendingExpires[ptr] = nil
    end
end

-- ========================================
-- Part 5. Сохранение / загрузка
-- ========================================

function events.BeforeSaveGame()
    CESaveData = {}
    for ptr, data in pairs(SavedPermBonus) do
        for i = 0, Party.Players.Count - 1 do
            local player = Party.Players[i]
            for j = 1, player.Items.Count do
                if player.Items[j]["?ptr"] == ptr then
                    CESaveData[string.format("%d_%d", i, j)] = {
                        Bonus = data.Bonus, Bonus2 = data.Bonus2,
                        BonusStrength = data.BonusStrength
                    }
                    break
                end
            end
        end
    end
    for ptr, data in pairs(PendingChecks) do
        for i = 0, Party.Players.Count - 1 do
            local player = Party.Players[i]
            for j = 1, player.Items.Count do
                if player.Items[j]["?ptr"] == ptr then
                    CESaveData["p_" .. string.format("%d_%d", i, j)] = {
                        Bonus = data.Bonus, Bonus2 = data.Bonus2,
                        BonusStrength = data.BonusStrength
                    }
                    break
                end
            end
        end
    end
end

function events.AfterLoadMap()
    initEnchantDmg()

    SavedPermBonus = {}
    PendingChecks = {}
    PendingExpires = {}
    if CESaveData and type(CESaveData) == "table" then
        for key, data in pairs(CESaveData) do
            local isPending = key:match("^p_")
            local stripped = isPending and key:sub(3) or key
            local pi, si = stripped:match("(%d+)_(%d+)")
            pi, si = tonumber(pi), tonumber(si)
            if pi and si and Party.Players[pi] then
                local item = Party.Players[pi].Items[si]
                if item and item.Number >= 0 then
                    local ptr = item["?ptr"]
                    local cond = mem.u4[ptr + 0x14]
                    if bit.band(cond, 0x8) ~= 0 then
                        if isPending then
                            PendingChecks[ptr] = data
                        else
                            SavedPermBonus[ptr] = data
                        end
                    end
                end
            end
        end
    end
end

function events.LeaveMap()
    local activePtrs = {}
    for i = 0, Party.Players.Count - 1 do
        local player = Party.Players[i]
        for j = 1, player.Items.Count do
            local item = player.Items[j]
            if item.Number >= 0 then
                activePtrs[item["?ptr"]] = true
            end
        end
    end
    for ptr in pairs(SavedPermBonus) do
        if not activePtrs[ptr] then SavedPermBonus[ptr] = nil end
    end
    for ptr in pairs(PendingChecks) do
        if not activePtrs[ptr] then PendingChecks[ptr] = nil end
    end
end

log("Concurrent Enchantments v5.3 Final loaded.")
