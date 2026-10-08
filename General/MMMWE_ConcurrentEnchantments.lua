-- ========================================
-- Concurrent Enchantments v5.9
-- Permanent + Temporary enchantment stacking
--
-- v5.9: the temporary enchantment is named in the item tooltip ("Temp. Infernos: 2:hr 14:mn"
--   instead of "Duration: ...") and MF.GetTempEnchant(item) tells other scripts (the HP/SP
--   overlay) which temporary enchantment an item has and when it expires.
-- v5.8: slaying enchantments are reproduced too: while the engine computes melee / ranged
--   damage (CalcMeleeDamage 0x48C759, CalcRangedDamage 0x48CB07 - where it checks the
--   "Slaying" specials against the target), the hidden slaying enchantment is put in the
--   item's Bonus2 for the duration of the call. The Slaying potion (Bonus2 0x28 "of Dragon
--   Slaying", rmb_inventory 0x416140) now works together with a permanent special too.
-- v5.7: Swiftness is reproduced too (get_attack_delay 0x48D62A gives -20 recovery when the
--   weapon that sets the recovery has Bonus2 59 "of Swiftness" or 41 "of Darkness"), so the
--   Swift potion works together with a permanent special enchantment, and a hidden permanent
--   Swiftness keeps working under a Slaying potion.
-- v5.6: both special enchantments work at once. When the temporary enchantment is one the
--   script can reproduce (elemental damage: Fire Aura, Flaming / Freezing / Shocking /
--   Noxious potions; Vampiric Weapon), the item keeps its PERMANENT special enchantment in
--   place, so the engine applies all of its effects (Swiftness, slaying, Carnage, stats ...),
--   and the temporary one is added by this script (v5.7: Swift potion, v5.8: Slaying potion).
--   expire_temp_bonus (0x455B40) is wrapped: it is called on every check, not only at the
--   moment of expiry, so the permanent enchantment is restored only when the temporary one
--   really expired.
-- v5.5: the standard enchantment keeps working under a temporary one; enchantment damage
--   calls are recognized precisely (t.IsSecondary) instead of the _G.CE_SecondaryResist counter.
-- v5.4: the permanent enchantments hidden under a temporary one are saved with the game
--   (vars.CEPermBonus). Records are keyed by the item itself (item number + expiry time of
--   its temporary enchantment), not by its memory address or inventory slot, so they
--   survive map changes, save / load, game restarts, moving the item to another character,
--   to the mouse, into a chest or onto the ground, and party changes at the inn.
-- ========================================

local MF = Merge.Functions
local LogId = MF.LogInit1("ConcurrentEnchants")
local function log(fmt, ...) MF.LogInfo("[CE] " .. fmt, ...) end
local mmver = Game.Version

-- Set to false to suppress per-hit combat logs
local DEBUG_HITS = false


local PendingChecks = {}   -- item ptr -> state saved right before a temporary enchantment

local TEMP_BIT = 0x8       -- item.Condition: temporary enchantment

-- Keep the standard enchantment (item.Bonus / BonusStrength: "+N Might", "of Health" ...)
-- working while a temporary enchantment is on the item. Only the permanent SPECIAL
-- enchantment (item.Bonus2) has to give way to the temporary one; its damage is added
-- back by Part 3.
local KEEP_STANDARD_BONUS = true

-- Keep the permanent SPECIAL enchantment in place too and reproduce the temporary one
-- (when it is elemental damage or vampiric). false = v5.5 behaviour.
local INVERT_WHEN_POSSIBLE = true

-- ItemAdditionalDamage calls waiting for the monster resistance call of their damage
-- (see Part 3b)
local AddDmgQueue = {}

-- ========================================
-- Persistent storage
-- vars.CEPermBonus[key] = {Bonus, Bonus2, BonusStrength, Number, Expire, Mode, TempBonus2}
--   Bonus / Bonus2 / BonusStrength - the item's permanent enchantments
--   Mode = "inv": the permanent Bonus2 is on the item, the temporary one (TempBonus2) is
--                 reproduced by this script
--   Mode = nil:   the temporary Bonus2 is on the item, the permanent one is reproduced
-- key = "<item number>_<expiry time of the temporary enchantment>"
-- ========================================

local function Store()
    if not vars then return nil end
    vars.CEPermBonus = vars.CEPermBonus or {}
    return vars.CEPermBonus
end

local function writeBack(ptr, data)
    mem.u4[ptr + 4]   = data.Bonus
    mem.u4[ptr + 0xC] = data.Bonus2
    mem.u4[ptr + 8]   = data.BonusStrength
end

local function makeKey(number, expire)
    return string.format("%d_%.0f", number, expire)
end

local function hasTemp(ptr)
    return bit.band(mem.u4[ptr + 0x14], TEMP_BIT) ~= 0
end

-- Key of an item with a temporary enchantment (nil if it has none)
local function itemKey(ptr)
    if not hasTemp(ptr) then return nil end
    return makeKey(mem.u4[ptr], mem.u8[ptr + 0x1C])
end

-- Saved permanent enchantment of an item (nil if none)
local function recordOf(ptr)
    local store = Store()
    local key = store and itemKey(ptr)
    return key and store[key], key
end

-- Give a freshly enchanted item an expiry time no other record uses (two identical items
-- enchanted at the same moment, e.g. in the paused inventory, would share a key otherwise).
-- The shift is a few game time units, a fraction of a second.
local function uniqueKey(ptr, store, ignoreKey)
    local number = mem.u4[ptr]
    local expire = mem.u8[ptr + 0x1C]
    local key = makeKey(number, expire)
    while store[key] and key ~= ignoreKey do
        expire = expire + 1
        key = makeKey(number, expire)
    end
    mem.u8[ptr + 0x1C] = expire
    return key, number, expire
end


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
local VampiricB2 = {}   -- item.Bonus2 values of vampiric special enchantments

-- Bonus2 values that make the engine's get_attack_delay (0x48D62A) take 20 off the recovery
-- of the weapon that sets it: 0x3B "of Swiftness", 0x29 "of Darkness"
local SwiftB2 = {[0x3B] = true, [0x29] = true}
-- artifacts with the same built-in effect (item numbers checked by get_attack_delay)
local SwiftItems = {[0x1F8] = true, [0x1FA] = true, [0x200] = true, [0x203] = true,
    [0x206] = true, [0x214] = true}
local SWIFT_BONUS = 20

-- Slaying specials (checked by the engine inside CalcMeleeDamage / CalcRangedDamage).
-- Filled from SPCITEMS ("... Slaying"); 0x28 "of Dragon Slaying" is what the Slaying potion
-- writes (rmb_inventory 0x416140).
local SlayB2 = {[0x28] = true}

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

    VampiricB2 = {}
    SlayB2 = {[0x28] = true}
    for idx, v in Game.SpcItemsTxt do
        local name = (v.NameAdd or ""):lower()
        if name:find("vampir", 1, true) then
            VampiricB2[idx + 1] = true
        end
        if name:find("slay", 1, true) then
            SlayB2[idx + 1] = true
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
-- The hooks sit on the calls of expire_temp_bonus right before the engine's checks
-- "item not broken, Bonus2 == 0, Bonus == 0, weapon" (0x4272A5 / 0x4160F6 / 0x4161A7),
-- so both enchantment slots have to be empty for the engine to accept the new one.
-- Сохраняем постоянные бонусы и обнуляем, чтобы движок
-- записал только временное зачарование
-- ========================================

local function doSaveAndClear(itemPtr, spellName)
    if not itemPtr or itemPtr < 0x10000 or itemPtr > 0x10000000 then return end

    local bonus    = mem.u4[itemPtr + 4]
    local bonus2   = mem.u4[itemPtr + 0xC]
    local bonusStr = mem.u4[itemPtr + 8]

    if bonus == 0 and bonus2 == 0 and bonusStr == 0 then return end

    if not PendingChecks[itemPtr] then
        local pending = {
            -- what is cleared now; written back if the engine doesn't apply the enchantment
            Cleared = {Bonus = bonus, Bonus2 = bonus2, BonusStrength = bonusStr},
        }
        if hasTemp(itemPtr) then
            -- the item already has a temporary enchantment: what is cleared is that one,
            -- not a permanent enchantment
            local rec, key = recordOf(itemPtr)
            pending.OldKey = key
            pending.HasRecord = rec ~= nil
        end
        log("%s: item %d B=%d B2=%d S=%d temp=%s -> saving & clearing",
            spellName, mem.u4[itemPtr], bonus, bonus2, bonusStr, tostring(pending.OldKey))
        PendingChecks[itemPtr] = pending
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

-- expire_temp_bonus(item, time) is called whenever the engine checks an item, so the
-- permanent enchantment is restored only if the temporary one really expired in this call.
mem.hookfunction(0x455B40, 1, 2, function(d, def, this, timeLo, timeHi)
    local store = Store()
    local key = store and itemKey(this)
    local expireBefore = key and mem.u8[this + 0x1C]
    local r = def(this, timeLo, timeHi)
    if key and (not hasTemp(this) or mem.u8[this + 0x1C] ~= expireBefore) then
        local rec = store[key]
        store[key] = nil
        local p = PendingChecks[this]
        if p then
            -- expired right before a new enchantment is applied (Part 1 already emptied
            -- the slots): what was cleared is now just the permanent state
            p.OldKey, p.HasRecord = nil, nil
            if rec then
                p.Cleared = {Bonus = rec.Bonus, Bonus2 = rec.Bonus2,
                    BonusStrength = rec.BonusStrength}
            else
                p.Cleared.Bonus2 = 0   -- it was the temporary enchantment itself
            end
        elseif rec then
            writeBack(this, rec)
            mem.u4[this + 0x14] = bit.band(mem.u4[this + 0x14], bit.bnot(TEMP_BIT))
            mem.u8[this + 0x1C] = 0
            log("Expire: restored {B=%d B2=%d S=%d} for item %d",
                rec.Bonus, rec.Bonus2, rec.BonusStrength, rec.Number)
        end
    end
    return r
end)

-- ========================================
-- Part 3. Concurrent damage via ItemAdditionalDamage
-- ========================================

_G.CE_PermHitQueue = _G.CE_PermHitQueue or {}

function events.ItemAdditionalDamage(t)
    -- the engine calls the monster resistance function for this damage right after;
    -- Part 3b marks that call as secondary. The table itself is queued, so its final
    -- DamageKind (after every handler) is what gets compared.
    AddDmgQueue[#AddDmgQueue + 1] = t

    local item = t.Item
    if not item or item.Broken then return end

    local ptr = item["?ptr"]
    if not ptr then return end

    local saved = recordOf(ptr)
    if not saved then return end

    -- the enchantment the engine doesn't see: the hidden permanent one, or (Mode "inv")
    -- the temporary one. Below, "perm" means this one, "temp" the one the engine applied.
    local inverted = saved.Mode == "inv"
    local bonus2 = inverted and saved.TempBonus2 or saved.Bonus2
    if inverted and VampiricB2[bonus2] then
        t.Vampiric = true
    end
    local enchDmg, permDK = calcEnchantDamage(bonus2)
    if enchDmg <= 0 or not permDK then return end
    -- weapon skill / two-handed scaling (MMMWE_EnchantScaling.lua)
    if MF.ScaleEnchantDamage then
        enchDmg = MF.ScaleEnchantDamage(t.Player, item, enchDmg, permDK)
    end
    -- the engine's enchantment deals no damage (Swiftness, slaying ...): this damage takes
    -- its place and its damage kind, so the engine applies the right resistance
    if t.Result - (t.CEAdded or 0) <= 0 then
        t.DamageKind = permDK
    end

    local tempDK = t.DamageKind or 0
    local monIdx = t.MonsterIndex or -1
    local resisted = 0

    if permDK == tempDK then
        -- Та же стихия: добавляем чистый урон, движок применит
        -- сопротивление один раз с правильной стихией
        t.Result = t.Result + enchDmg
        -- already scaled: tell MMMWE_EnchantScaling.lua not to scale it again
        t.CEAdded = (t.CEAdded or 0) + enchDmg
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
-- Part 3a. Swiftness of the enchantment the engine doesn't see
-- Mirrors get_attack_delay: only the weapon that sets the recovery counts - the bow for
-- ranged attacks; in melee the main hand, or the off-hand weapon if its skill recovers
-- slower. Runs before MMMWE_Main.lua's GetAttackDelay handler (alphabetical order), so the
-- -20 comes before its own penalties and Haste multiplier, like in the engine.
-- ========================================

local function skillRecovery(it)
    local txt = Game.ItemsTxt[it.Number]
    return txt and Game.SkillRecoveryTimes[txt.Skill] or 0
end

local function recoveryWeapon(pl, ranged)
    if ranged then
        local s = pl.ItemBow
        return s > 0 and pl.Items[s] or nil
    end
    local m, o = pl.ItemMainHand, pl.ItemExtraHand
    local main = m > 0 and pl.Items[m] or nil
    local off = o > 0 and pl.Items[o] or nil
    if main and off then
        return skillRecovery(off) > skillRecovery(main) and off or main
    end
    return main or off
end

function events.GetAttackDelay(t)
    local pl = t.Player
    if not pl then return end
    local it = recoveryWeapon(pl, t.Ranged)
    if not it or it.Number == 0 then return end
    local rec = recordOf(it["?ptr"])
    if not rec then return end
    local hiddenB2 = rec.Mode == "inv" and rec.TempBonus2 or rec.Bonus2
    if SwiftB2[hiddenB2] and not SwiftB2[it.Bonus2] and not SwiftItems[it.Number] then
        t.Result = math.max(0, t.Result - SWIFT_BONUS)
    end
end

-- ========================================
-- Part 3c. Slaying enchantment the engine doesn't see
-- The engine checks the slaying specials (item.Bonus2 against the target's kind) inside
-- CalcMeleeDamage / CalcRangedDamage. For the duration of these calls the hidden slaying
-- enchantment is put into Bonus2, so the engine's own rules apply exactly; the visible one
-- is put back right after. Not done when the visible enchantment is a slaying one too
-- (one call can only check one of them).
-- ========================================

local function swapInSlaying(pl, slots)
    local swapped
    for _, slot in ipairs(slots) do
        local idx = pl[slot]
        if idx > 0 then
            local ptr = pl.Items[idx]["?ptr"]
            local rec, key = recordOf(ptr)
            if rec then
                local hidden = rec.Mode == "inv" and rec.TempBonus2 or rec.Bonus2
                local visible = mem.u4[ptr + 0xC]
                if SlayB2[hidden] and hidden ~= visible and not SlayB2[visible] then
                    swapped = swapped or {}
                    swapped[#swapped + 1] = {ptr, visible, key}
                    mem.u4[ptr + 0xC] = hidden
                end
            end
        end
    end
    return swapped
end

local function swapBack(swapped)
    for _, s in ipairs(swapped) do
        local ptr, visible, key = s[1], s[2], s[3]
        -- if the temporary enchantment expired during the call, Part 2 already restored the item
        if itemKey(ptr) == key then
            mem.u4[ptr + 0xC] = visible
        end
    end
end

local MeleeSlots = {"ItemMainHand", "ItemExtraHand"}
local RangedSlots = {"ItemBow"}

local function slayingWrapper(slots)
    return function(d, def, this, ...)
        local ok, swapped = pcall(function()
            local pl = MF.GetPlayerFromPtr(this)
            return pl and swapInSlaying(pl, slots)
        end)
        local r = def(this, ...)
        if ok and swapped then
            swapBack(swapped)
        end
        return r
    end
end

-- CalcMeleeDamage(JustWeaponDamage, IgnoreExtraHand, MonsterId), CalcRangedDamage(MonsterId)
mem.hookfunction(0x48C759, 1, 3, slayingWrapper(MeleeSlots))
mem.hookfunction(0x48CB07, 1, 1, slayingWrapper(RangedSlots))

-- ========================================
-- Part 3b. Mark the resistance calls of enchantment damage
-- The engine resolves a weapon hit as: the hit's own damage -> monster resistance, then for
-- each weapon: ItemAdditionalDamage -> monster resistance of the enchantment damage.
-- The second resistance call is marked with t.IsSecondary = true, so other scripts
-- (crits, high ground, durability) leave it alone. It is matched by the monster and the
-- damage kind, so a stray ItemAdditionalDamage call (e.g. MF.CheckItemAdditionalDamage)
-- can't make the next real hit count as secondary. This handler runs before the
-- CalcDamageToMonster handlers of MMMWE_ItemDurability.lua and MMMWE_Main.lua
-- (scripts load in alphabetical order).
-- ========================================

function events.CalcDamageToMonster(t)
    if not AddDmgQueue[1] or not t.ByPlayer then return end
    for i, p in ipairs(AddDmgQueue) do
        if (p.MonsterIndex == nil or p.MonsterIndex == t.MonsterIndex)
                and p.DamageKind == t.DamageKind then
            table.remove(AddDmgQueue, i)
            t.IsSecondary = true
            return
        end
    end
end

-- for other scripts: is this CalcDamageToMonster call the damage of a weapon enchantment?
MF.IsEnchantDamageCall = function(t) return t.IsSecondary == true end

-- ========================================
-- Part 3d. Showing the temporary enchantment
-- ========================================

-- "of Infernos" -> "Infernos"
local function enchantName(b2)
    local v = b2 and b2 > 0 and Game.SpcItemsTxt[b2 - 1]
    local name = v and v.NameAdd or ""
    name = name:gsub("^%s*[Oo]f%s+", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return name ~= "" and name or nil
end

-- Temporary enchantment of an item: name, expiry time (Game.Time units), Bonus2.
-- nil if the item has none. Works for the game's own temporary enchantments too.
function MF.GetTempEnchant(item)
    local ptr = type(item) == "table" and item["?ptr"] or item
    if not ptr or ptr == 0 or not hasTemp(ptr) then return nil end
    local expire = mem.u8[ptr + 0x1C]
    if expire <= 0 then return nil end
    local rec = recordOf(ptr)
    local b2 = (rec and rec.Mode == "inv") and rec.TempBonus2 or mem.u4[ptr + 0xC]
    return enchantName(b2) or "Enchantment", expire, b2
end

-- Item tooltip (item_rmb_window): the line "Duration: 2:hr 14:mn" is built at 0x41D677 -
-- strcpy(sz, "Duration:") - and the time units are appended after it. Right after the
-- strcpy the label is replaced with the name of the temporary enchantment. The item is
-- [ebp-4], the buffer is esi.
local TOOLTIP_LABEL = "Temp. %s:"
mem.autohook(0x41D682, function(d)
    local ok, name = pcall(MF.GetTempEnchant, mem.u4[d.ebp - 4])
    if ok and name then
        local label = string.format(TOOLTIP_LABEL, name)
        mem.copy(d.esi, label .. "\0", #label + 1)
    end
end)

-- ========================================
-- Part 4. Тик — подтверждение наложения / истечения
-- ========================================

-- The temporary enchantment only uses Bonus2: give the standard enchantment back
local function restoreStandard(ptr, p)
    if not KEEP_STANDARD_BONUS then return end
    local c = p.Cleared
    if c.Bonus == 0 and c.BonusStrength == 0 then return end
    if mem.u4[ptr + 4] == 0 and mem.u4[ptr + 8] == 0 then
        mem.u4[ptr + 4] = c.Bonus
        mem.u4[ptr + 8] = c.BonusStrength
    else
        -- the engine wrote something there itself: leave it alone
        log("Standard bonus not restored for item %d (B=%d S=%d set by the engine)",
            mem.u4[ptr], mem.u4[ptr + 4], mem.u4[ptr + 8])
    end
end

-- Put the permanent special enchantment back on the item and remember the temporary one,
-- if this script can reproduce it (elemental damage or vampiric)
local function tryInvert(ptr, rec)
    rec.Mode, rec.TempBonus2 = nil, nil
    if not INVERT_WHEN_POSSIBLE or rec.Bonus2 == 0 then return end
    local tempB2 = mem.u4[ptr + 0xC]
    if tempB2 == 0 or not (EnchantDmg[tempB2 - 1] or VampiricB2[tempB2] or SwiftB2[tempB2]
            or SlayB2[tempB2]) then
        return
    end
    rec.Mode, rec.TempBonus2 = "inv", tempB2
    mem.u4[ptr + 0xC] = rec.Bonus2
    log("Both enchantments active: item %d permanent B2=%d on the item, temporary B2=%d added",
        rec.Number, rec.Bonus2, tempB2)
end

local function resolvePending()
    local store = Store()
    if not store then return end

    for ptr, p in pairs(PendingChecks) do
        local newKey = itemKey(ptr)
        local applied = newKey ~= nil and newKey ~= p.OldKey
        if not applied then
            -- the engine didn't apply the enchantment: put back what was cleared
            writeBack(ptr, p.Cleared)
        elseif p.OldKey then
            restoreStandard(ptr, p)
            -- a new temporary enchantment over an old one: the permanent enchantment
            -- (if any) moves to the new key
            local rec = store[p.OldKey]
            store[p.OldKey] = nil
            if rec then
                local key, number, expire = uniqueKey(ptr, store)
                rec.Number, rec.Expire = number, expire
                store[key] = rec
                tryInvert(ptr, rec)
                log("Enchant renewed: item %d, permanent {B=%d B2=%d S=%d} kept",
                    number, rec.Bonus, rec.Bonus2, rec.BonusStrength)
            end
        else
            restoreStandard(ptr, p)
            local key, number, expire = uniqueKey(ptr, store)
            local rec = p.Cleared
            rec.Number, rec.Expire = number, expire
            store[key] = rec
            tryInvert(ptr, rec)
            log("Enchant applied: item %d {B=%d B2=%d S=%d}",
                number, rec.Bonus, rec.Bonus2, rec.BonusStrength)
        end
        PendingChecks[ptr] = nil
    end
end

function events.Tick()
    -- a resistance call always follows its ItemAdditionalDamage within the same hit
    if AddDmgQueue[1] then AddDmgQueue = {} end
    if next(PendingChecks) then
        resolvePending()
    end
end

-- ========================================
-- Part 5. Сохранение / загрузка
-- The records live in vars, so they are saved and loaded with the game by itself.
-- ========================================

function events.BeforeSaveGame()
    -- an enchantment applied this very moment is recorded before the game is saved
    resolvePending()
end

function events.AfterLoadMap()
    initEnchantDmg()

    PendingChecks = {}

    -- drop records of items that were lost (sold, destroyed) long ago
    local store = Store()
    if store then
        local limit = Game.Time - const.Month
        for key, rec in pairs(store) do
            if type(rec) ~= "table" or (rec.Expire or 0) < limit then
                store[key] = nil
            end
        end
    end
end

log("Concurrent Enchantments v5.9 loaded.")
