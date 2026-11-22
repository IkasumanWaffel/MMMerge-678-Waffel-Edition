-- MMMWE (20.11.26): the save variables (vars) of General scripts, defined when a game is
-- started or loaded. The General scripts run once at the game's start, before any game is
-- loaded, so they can't define their vars themselves; the Global scripts run with every
-- loaded game, after vars has come from the save.

vars.ZombieInfection = vars.ZombieInfection or {}   -- ZombiePlayers.lua: infected characters
vars.PlayerFaces     = vars.PlayerFaces or {}       -- ZombiePlayers.lua: faces and voices before turning
vars.MMMWE_Cond      = vars.MMMWE_Cond or {}        -- MMMWE_Conditions.lua: condition timers
vars.WeakNextCheck   = vars.WeakNextCheck or {}     -- MMMWE_Conditions.lua: daily Weakness checks
vars.WeaknessCounter = vars.WeaknessCounter or {0, 0, 0, 0, 0}
vars.MMMWE_MostWanted = vars.MMMWE_MostWanted or {}   -- MMMWE_MostWanted.lua: renegade bands by town map
vars.MMMWE_Lycanthropy = vars.MMMWE_Lycanthropy or {}   -- MMMWE_Werewolves.lua: cursed characters by roster index
