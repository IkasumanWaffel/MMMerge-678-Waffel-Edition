-- Hardcore mode (quit to main menu and remove all savefiles after total party kill, no saves in battle)
-- Optional limit of party deaths (vars.HCMDeathLimit, set on the "Hardcore mode" page of the Extra
-- Settings menu, MMMWE_HardcoreSettings.lua). Every party death before the last one removes all
-- items of the party except special items, artifacts, relics and ancient items.
local MV = Merge.Vars

-- Also keep quest items (misc. items and message scrolls), so quests can't be broken by a death
local KEEP_QUEST_ITEMS = true

function events.GameInitialized2()
  if vars.HardCoreMode == nil then
    vars.HardCoreMode = 0
  end
  MV.HCM = vars.HardCoreMode
end

function events.NewGameMap()
    if vars.HardCoreMode == nil then
        vars.HardCoreMode = 0
    end
    MV.HCM = vars.HardCoreMode
end

---- Items that survive a party death
local function KeepItem(number)
  local txt = Game.ItemsTxt[number]
  if not txt then
    return true
  end
  -- 1 = artifact, 2 = relic, 3 = special
  if txt.Material ~= 0 then
    return true
  end
  local name = ((txt.Name or "") .. " " .. (txt.NotIdentifiedName or "")):lower()
  if name:find("ancient", 1, true) then
    return true
  end
  if KEEP_QUEST_ITEMS and (txt.EquipStat == const.ItemType.Misc - 1
      or txt.EquipStat == const.ItemType.MScroll - 1) then
    return true
  end
  return false
end

-- Remove one item (Items index) from a character: equipped slots, inventory cells, the item itself
local function RemovePlayerItem(pl, index)
  for slot, idx in pl.EquippedItems do
    if idx == index then
      pl.EquippedItems[slot] = 0
    end
  end
  for cell, v in pl.Inventory do
    if v == index then
      pl.Inventory[cell] = 0
      -- the other cells covered by the item point back to its main cell
      for cell2, v2 in pl.Inventory do
        if v2 == -(cell + 1) then
          pl.Inventory[cell2] = 0
        end
      end
    end
  end
  pl.Items[index].Number = 0
end

local function StripPartyItems()
  local removed = 0
  for _, pl in Party do
    for index, item in pl.Items do
      if item.Number ~= 0 and not KeepItem(item.Number) then
        RemovePlayerItem(pl, index)
        removed = removed + 1
      end
    end
  end
  return removed
end
Merge.Functions.HCMStripPartyItems = StripPartyItems

function events.DeathMap(t)
  if vars.HardCoreMode ~= 1 then
    return
  end
  vars.HCMDeaths = (vars.HCMDeaths or 0) + 1
  local limit = vars.HCMDeathLimit or 1

  if vars.HCMDeaths >= limit then
    -- last allowed death: game over
    DoGameAction(132, 0, 0, true)
    DoGameAction(132)
    local dir = os.chdir()
    for fname in path.find(dir .. '\\Saves\\*.dod') do
      os.remove(fname, true)
    end
  else
    -- revived, but the party's belongings are lost
    local removed = StripPartyItems()
    vars.HCMPendingMessage = string.format(
      "Hardcore mode: the party has fallen (%d of %d deaths).\n" ..
      "%d items were lost. Special items, artifacts, relics and ancient items were kept.",
      vars.HCMDeaths, limit, removed)
  end
end

-- (the message itself is shown by General/MMMWE_HardcoreSettings.lua after the map loads)

function events.CanSaveGame(t)
  local HardcoreMode = vars.HardCoreMode
  if HardcoreMode == 1 and (Party.EnemyDetectorYellow == true or Party.EnemyDetectorRed == true) and t.SaveKind ~= 1 then
    t.Result = false
    Game.ShowStatusText("You can't save in Hardcore mode when enemies are nearby")
  end
end

local function HCMEnemiesNearby()
  return vars.HardCoreMode == 1
    and (Party.EnemyDetectorYellow or Party.EnemyDetectorRed)
end

local HCM_BLOCK_MSG = {
  [125] = "You can't load in Hardcore mode when enemies are nearby",
  [132] = "You can't quit in Hardcore mode when enemies are nearby",
}

function events.Action(t)
  if HCMEnemiesNearby() and HCM_BLOCK_MSG[t.Action] then
    t.Handled = true
    Game.ShowStatusText(HCM_BLOCK_MSG[t.Action])
  end
end
