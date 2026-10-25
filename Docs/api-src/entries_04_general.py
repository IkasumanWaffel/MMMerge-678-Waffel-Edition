P = lambda n: '<b class="def-param">%s</b>' % n
C = lambda s: '<span class="def-code">%s</span>' % s
L = lambda a, t=None: '<a href="#%s">%s</a>' % (a, t or a.split('.')[-1])
H = lambda a, t=None: '<a href="MMExtension.htm#%s">%s</a>' % (a, t or a.split('.')[-1])

GROUPS = [
{'file': r'Scripts\General\10_Continents.lua', 'kind': 'events',
 'about': C('Merge.Vars.Continent') + ': 1 Jadame (MM8), 2 Antagarich (MM7), 3 Enroth (MM6).', 'items': [
 {'name': 'ContinentChange1', 'args': '',
  'desc': 'A map of another continent is being loaded (from ' + H('events.LoadMap', 'LoadMap') + '); ' + C('Merge.Vars.Continent') + ' and ' + C('Merge.Vars.PrevContinent') + ' are set.'},
 {'name': 'ContinentChange2', 'args': '', 'desc': 'The same, from ' + H('events.LoadMapScripts', 'LoadMapScripts') + '.'},
 {'name': 'ContinentChange3', 'args': '', 'desc': 'The same, from ' + H('events.AfterLoadMap', 'AfterLoadMap') + '.'},
]},
{'file': r'Scripts\General\MenuChooseContinent.lua', 'kind': 'events', 'items': [
 {'name': 'NewGame', 'args': 'FromGame, Continent',
  'desc': 'A new game starts on ' + P('Continent') + '; ' + P('FromGame') + ' = true when it was started from a running game rather than from the main menu.'},
]},
{'file': r'Scripts\General\MenuExtraSettings.lua', 'kind': 'events', 'items': [
 {'name': 'OpenExtraSettingsMenu', 'args': '', 'desc': 'The extra settings pages (on the game options screen) are opened.'},
 {'name': 'ExitExtraSettingsMenu', 'args': '', 'desc': 'The extra settings pages are closed; settings changed there can be applied here.'},
]},
{'file': r'Scripts\General\2_OutdoorTravels.lua', 'kind': 'events', 'items': [
 {'name': 'LeftToMap', 'args': ['Map', 'Straight'],
  'desc': 'The party walks off the edge of an outdoor map to map ' + P('Map') + ' (' + C('Game.MapStats') + ' index). Set ' + P('Straight') + ' = true to travel there at once without the travel question; '
   'MMMerge does so for maps marked StraightTravel in Data\\Tables\\Outdoor travels.txt.'},
 {'name': 'ShowDeathMovie', 'args': ['movie'],
  'desc': 'The party has died and the death movie of the continent is about to play; change ' + P('movie') + ' ("" = none).'},
]},
{'file': r'Scripts\General\1_TownPortalSwitch.lua', 'kind': 'events', 'items': [
 {'name': 'TownPortalDestiantionName', 'args': ['NamePtr', 'Slot', 'Switch'],
  'desc': 'The name of a Town Portal destination is shown: set ' + P('NamePtr') + ' to a pointer to another name. ' + P('Slot') + ' is the destination, ' + P('Switch') + ' the current set (continent). '
   '(The name of the event is spelled this way in the code.)'},
]},
{'file': r'Scripts\General\Weather.lua', 'kind': 'events', 'items': [
 {'name': 'WeatherChanged', 'args': ['WeatherState', 'CurrentEffect', 'EffectActive', 'Reason', 'Handled'],
  'desc': 'The weather of an outdoor map changes: ' + P('Reason') + ' = "Day" (a new day) or "WeatherEffect" (rain or snow starts or stops). '
   'Change ' + P('CurrentEffect') + ' and ' + P('EffectActive') + ', or set ' + P('Handled') + ' = true to keep the weather as it was.'},
]},
{'file': r'Scripts\General\Resistances.lua', 'kind': 'events',
 'about': 'Race and class resistances (Data\\Tables\\Resistances.txt).', 'items': [
 {'name': 'GetRaceClassResistance', 'args': ['Resistance', 'Player', 'Result'], 'links': {'Player': 'structs.Player'},
  'desc': 'The resistance a character gets from race and class is worked out; change ' + P('Result') + '.'},
 {'name': 'GetResistance', 'args': ['Resistance', 'Player', 'Result'], 'links': {'Player': 'structs.Player'},
  'desc': 'The full value of a character\'s resistance is worked out; change ' + P('Result') + '.'},
]},
{'file': r'Scripts\General\ItemsModifiers.lua', 'kind': 'events', 'items': [
 {'name': 'ItemHasBonus2', 'args': ['PlayerPtr', 'ItemId', 'Bonus2', 'MonsterId', 'Result'],
  'desc': 'The game checks whether a weapon has special bonus ' + P('Bonus2') + ' against monster ' + P('MonsterId') + ' (melee, ranged and the like); set ' + P('Result') + ' = 1 to count it.'},
 {'name': 'ItemHasBonus2OfGroup', 'args': ['ItemId', 'Bonus2', 'Group', 'Result'],
  'desc': 'As ' + L('events.ItemHasBonus2', 'ItemHasBonus2') + ' for the groups of bonuses the damage code checks together (' + P('Group') + ' 1 and 2).'},
 {'name': 'GetItemStdBonusCost', 'args': ['Item', 'StdBonus', 'BonusStrength', 'BaseCost', 'Result'],
  'desc': 'The value of an item with a standard enchantment is worked out; change ' + P('BaseCost') + ' or ' + P('Result') + '.'},
 {'name': 'RemoveConsumedItem', 'args': ['ItemId', 'Handled'],
  'desc': 'A used-up item (a potion, a scroll) is about to be removed from the mouse; set ' + P('Handled') + ' = true to keep it (MMMerge gives back an empty bottle this way when its setting is on).'},
]},
{'file': r'Scripts\General\BountyHunt.lua', 'kind': 'events', 'items': [
 {'name': 'BountyHuntGeneration', 'args': ['MapName', 'Entry', 'Handled', 'Text'],
  'desc': 'A town hall chooses a new bounty hunt: ' + P('Entry') + ' is the hunt ({Month, MonId, ...}); change it. '
   '<b>Note:</b> the code checks a global ' + C('Handled') + ' instead of ' + C('t.Handled') + ', so ' + P('Handled') + ' and ' + P('Text') + ' have no effect at present.'},
 {'name': 'NewBountyHuntCreated', 'args': 'MapName, Entry, Monster', 'desc': 'The monster of a new bounty hunt has been placed on the map.'},
 {'name': 'BountyHuntEliminated', 'args': 'MapName, Entry, Monster', 'desc': 'The party has killed the monster of a bounty hunt.'},
 {'name': 'BountyHuntRewardClaimed', 'args': 'MapName, Reward', 'desc': 'The reward of a bounty hunt has been claimed.'},
]},
{'file': r'Scripts\General\MonstersTweaks.lua', 'kind': 'events', 'items': [
 {'name': 'MonsterChooseTargetPlayer', 'args': ['MonsterPtr', 'MonsterId', 'Slot'],
  'desc': 'A monster chooses which character to attack: ' + P('Slot') + ' (party slot) comes from its preferences (class, race, sex, position). Change it. The Waffel Edition changes it by threat (MMMWE_Threat.lua) and for the Knight\'s Challenge (MMMWE_Resources.lua).'},
]},
{'file': r'Scripts\Global\MonsterPathfinding.lua', 'kind': 'events', 'items': [
 {'name': 'MonsterNeedPathfinding', 'args': ['MonsterIndex', 'Monster', 'Result'], 'links': {'Monster': 'structs.MapMonster'},
  'desc': 'The pathfinder decides whether a monster needs a path to the party (by default: it is pursuing it); change ' + P('Result') + '.'},
]},
]
