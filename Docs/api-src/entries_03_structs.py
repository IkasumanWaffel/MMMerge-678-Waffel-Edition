P = lambda n: '<b class="def-param">%s</b>' % n
C = lambda s: '<span class="def-code">%s</span>' % s
L = lambda a, t=None: '<a href="#%s">%s</a>' % (a, t or a.split('.')[-1])
H = lambda a, t=None: '<a href="MMExtension.htm#%s">%s</a>' % (a, t or a.split('.')[-1])

GROUPS = [
{'file': r'Scripts\Structs\RemoveHouseRulesLimits.lua', 'kind': 'events',
 'about': 'Shops, guilds, topics and Arcomage of the houses (Data\\Tables\\House rules.txt).', 'items': [
 {'name': 'GuildRefilled', 'args': 'Assortment',
  'desc': 'A guild (spell shop) has refilled its stock; ' + P('Assortment') + ' is its ' + C('Game.GuildItems') + ' entry.'},
 {'name': 'DrawShopTopics', 'args': ['HouseType', 'HouseId', 'NewTopics', 'Handled'],
  'desc': 'The topics of a shop are about to be shown. Set ' + P('Handled') + ' = true and fill ' + P('NewTopics') + ' (up to 5 topic numbers, '
   + C('const.ShopTopics') + ') to show your own topics; handle them in ' + L('events.ClickShopTopic', 'ClickShopTopic') + '.'},
 {'name': 'DrawLearnTopics', 'args': ['HouseType', 'HouseId', 'NewTopics', 'Handled'],
  'desc': 'As ' + L('events.DrawShopTopics', 'DrawShopTopics') + ', for the "learn skills" topics of a house.'},
 {'name': 'ArcomageMatchEnd', 'args': ['House', 'result', 'Handled'],
  'desc': 'An Arcomage match in a tavern has ended: ' + P('result') + ' = -1 cancelled, 0 tie, 1 the player won, 2 the opponent won. '
   'Set ' + P('Handled') + ' = true to skip the game\'s own prize for a win (e.g. to pay something else).'},
]},
{'file': r'Scripts\Structs\After\InterfaceManager.lua', 'kind': 'events',
 'about': 'Custom interface elements (CustomUI) are drawn in four layers; these events come between them.', 'items': [
 {'name': 'BGInterfaceUpd', 'args': '', 'desc': 'Before the background layer (3) of custom interface elements is drawn.'},
 {'name': 'L2InterfaceUpd', 'args': '', 'desc': 'Between layers 3 and 2.'},
 {'name': 'L1InterfaceUpd', 'args': '', 'desc': 'Between layers 1 and 0.'},
 {'name': 'FGInterfaceUpd', 'args': '', 'desc': 'After the foreground layer (0) is drawn.'},
 {'name': 'RightClickTooltip', 'args': '',
  'desc': 'The right mouse button is pressed: the place for ' + C('CustomUI.ShowTooltip') + ' and other tooltip drawing. It is drawn properly even on screen 0 with the MMPatch UI layout.'},
]},
{'file': r'Scripts\Structs\After\RemoveTransitionLimits.lua', 'kind': 'events', 'items': [
 {'name': 'EnterHouse', 'args': 'HouseId', 'desc': 'The party enters house ' + P('HouseId') + ' (before its dialog is set up).'},
 {'name': 'AfterEnterHouse', 'args': 'HouseId', 'desc': 'The party has entered house ' + P('HouseId') + '.'},
 {'name': 'GetTransitionText', 'args': ['TransId', 'EnterMap', 'Text', 'CustomText'],
  'desc': 'The text of a map transition (a door or exit to another map, ' + P('EnterMap') + ' its file name) is needed. Change ' + P('TransId') + ' (a line of the transition texts; 0 = no text), '
   'or give a text of your own. For houses it is read from ' + P('Text') + '; for the transition dialog the code uses ' + P('CustomText') + ' when ' + P('Text') + ' is set, so set both.'},
]},
{'file': r'Scripts\Structs\CharacterOutfits.lua', 'kind': 'events', 'items': [
 {'name': 'CharacterChosen', 'args': '', 'desc': 'A character has been chosen on the character creation screen.'},
 {'name': 'GetSpecialAttack', 'args': ['Player', 'mon', 'IsRanged', 'Attack'], 'links': {'Player': 'structs.Player'},
  'desc': 'The default attack of a character\'s portrait (a race attack such as a dragon\'s breath) is chosen: ' + P('Attack') + ' is a spell number '
   '(135 for a blaster), ' + P('IsRanged') + ' whether the target ' + P('mon') + ' is farther than 350. Change ' + P('Attack') + ' (0 = none).'},
 {'name': 'CanWearItem', 'args': ['ItemId', 'Player', 'RosterId', 'Available'], 'links': {'Player': 'structs.Player'},
  'desc': 'The game checks whether a character may wear item ' + P('ItemId') + ' (race, class and doll type); change ' + P('Available') + '.'},
]},
{'file': r'Scripts\Structs\25_MergeFunctions.lua', 'kind': 'events', 'items': [
 {'name': 'GetPlStatValue', 'args': ['PlayerPtr', 'Stat', 'Result'],
  'desc': 'The full value of a character\'s stat ' + P('Stat') + ' (' + H('const.Stats', 'const.Stats') + ') is worked out; change ' + P('Result') + '.'},
 {'name': 'GetPlStatEffect', 'args': ['PlayerPtr', 'Stat', 'StatValue', 'Result'],
  'desc': 'The bonus a stat value gives (e.g. 25 Might = +5) is worked out; change ' + P('Result') + '.'},
]},
{'file': r'Scripts\Structs\30_MergeStructs.lua', 'kind': 'events', 'items': [
 {'name': 'CanPlayerCastSpell', 'args': ['PlayerPtr', 'Spell', 'Check', 'Source', 'Result'],
  'desc': 'The game checks whether a character can cast a spell now (e.g. not while feebleminded); change ' + P('Result') + '. '
   + P('Source') + ' = 4 for a scroll (allowed while feebleminded with the FeeblemindedDisableScrolls setting at 0).'},
]},
{'file': r'Scripts\Structs\RacialSkills.lua', 'kind': 'events', 'items': [
 {'name': 'GetMaxSkillLevel', 'args': ['Player', 'PlayerIndex', 'Class', 'Skill', 'Promotions', 'Result', 'Bonus'], 'links': {'Player': 'structs.Player'},
  'desc': 'The highest mastery a character can reach in a skill (race, class and promotions; Data\\Tables\\Race Skills.txt) is worked out; change ' + P('Result') + ' or the racial ' + P('Bonus') + '.'},
]},
{'file': r'Scripts\Structs\After\RemoveClassLimits.lua', 'kind': 'events', 'items': [
 {'name': 'ShowSkillDescr', 'args': ['Skill', 'Class', 'Mastery', 'Player', 'PlayerIndex', 'MaxLevel'], 'links': {'Player': 'structs.Player'},
  'desc': 'A skill description shows how far a class can learn it: ' + P('MaxLevel') + ' from Class Skills.txt. Change it. With ' + P('Mastery') + ' = -1 it is called for every promotion of the class and the highest counts.'},
]},
{'file': r'Scripts\Structs\After\RemoveSkillValueLimits.lua', 'kind': 'events', 'items': [
 {'name': 'GetPlayerSkillMastery', 'args': ['PlayerPtr', 'Player', 'PlayerIndex', 'Skill', 'Result'], 'links': {'Player': 'structs.Player'},
  'desc': 'The game asks for a character\'s mastery in a skill; change ' + P('Result') + '.'},
]},
{'file': r'Scripts\Structs\After\HardcodedTopicFunctions.lua', 'kind': 'events', 'items': [
 {'name': 'DismissCharacter', 'args': ['PlayerId', 'Handled'],
  'desc': 'A character is about to be dismissed from the party (the hireling topic). Set ' + P('Handled') + ' = true to keep them, or change ' + P('PlayerId') + '.'},
]},
{'file': r'Scripts\Structs\After\RemoveNPCTablesLimits.lua', 'kind': 'events', 'items': [
 {'name': 'ClickNPCTopic', 'args': 'Topic',
  'desc': 'An NPC topic is clicked; called before the topic\'s ' + C('evt.Global') + ' event runs.'},
]},
{'file': r'Scripts\Structs\After\HWWater.lua', 'kind': 'events', 'items': [
 {'name': 'BeforeLoadWater', 'args': 'Key, Set',
  'desc': 'A set of hardware water textures (Data\\Tables\\HW water textures.txt) is about to be loaded.'},
]},
{'file': r'Scripts\Structs\RemoveItemsLimits.lua', 'kind': 'events', 'items': [
 {'name': 'ItemGeneratedM', 'args': 'Item',
  'desc': 'An item has been generated (' + H('structs.Item', 'structs.Item') + '); change it. Afterwards items worth 0 and artifacts lose random enchantments.'},
 {'name': 'LoadInventoryPics', 'args': 'Player, PlayerIndex',
  'desc': 'The paperdoll pictures of a character are being loaded.'},
]},
{'file': r'Scripts\Structs\After\RemoveMonstersAndPlacemonLimits.lua', 'kind': 'events', 'items': [
 {'name': 'BeforeArenaStart', 'args': 'ArenaLevel', 'desc': 'An arena fight is about to start; ' + P('ArenaLevel') + ' is the level chosen.'},
 {'name': 'GenerateArenaMonster', 'args': ['MonId', 'ArenaLevel', 'Handled'],
  'desc': 'A monster for the arena is chosen; change ' + P('MonId') + '. Without ' + P('Handled') + ' = true an invalid choice (or a monster of kind 6) is replaced by a random one.'},
]},
]
