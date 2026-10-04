-- Hardcore mode (quit to main menu and remove all savefiles after total party kill, no saves in battle)
local MV = Merge.Vars

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


function events.DeathMap(t)
  local HardcoreMode = vars.HardCoreMode
  if HardcoreMode == 1 and Party.Deaths > 0 then
    DoGameAction(132, 0, 0, true)
    DoGameAction(132)
    local dir = os.chdir()
    for fname in path.find(dir .. '\\Saves\\*.dod') do
      os.remove(fname, true)
    end
  end
end

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
