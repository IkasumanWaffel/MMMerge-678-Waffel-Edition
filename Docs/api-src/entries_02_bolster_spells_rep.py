P = lambda n: '<b class="def-param">%s</b>' % n
C = lambda s: '<span class="def-code">%s</span>' % s
L = lambda a, t=None: '<a href="#%s">%s</a>' % (a, t or a.split('.')[-1])
H = lambda a, t=None: '<a href="MMExtension.htm#%s">%s</a>' % (a, t or a.split('.')[-1])

GROUPS = [
{'file': r'Scripts\General\AdaptiveMonstersStats.lua', 'kind': 'events',
 'about': 'Bolster: monsters are made stronger to match the party (formulas and tables in Data\\Tables\\Bolster*.txt).', 'items': [
 {'name': 'CalcBolsterLevel', 'args': ['Result'],
  'desc': 'The party level the monsters are bolstered to is worked out from the party\'s fame and size; change ' + P('Result') + '.'},
 {'name': 'BeforeMapBolster', 'args': ['Handled'],
  'desc': 'The monsters of the current map are about to be bolstered; set ' + P('Handled') + ' = true to skip it for this map. '
   + L('events.AfterMapBolster', 'AfterMapBolster') + ' follows either way.'},
 {'name': 'AfterMapBolster', 'args': '', 'desc': 'The monsters of the map have been bolstered.'},
 {'name': 'BeforeMonsterBolster', 'args': ['TxtId', 'Id', 'Monster', 'Handled'], 'links': {'Monster': 'structs.MapMonster'},
  'desc': 'A monster is about to be bolstered: called for the monster type (' + P('TxtId') + ', MONSTERS.txt; ' + P('Id') + ' is nil) and for every map monster '
   '(' + P('Id') + ' its index, ' + P('Monster') + ' the monster). Set ' + P('Handled') + ' = true to leave it as it is.'},
 {'name': 'BolsterOnLoadMap', 'args': ['Handled'],
  'desc': 'Called after a map is loaded, before the bolster of that map; set ' + P('Handled') + ' = true to skip it.'},
 {'name': 'NeedRebolster', 'args': ['Need'],
  'desc': 'The extra settings menu is closed: ' + P('Need') + ' = true when the bolster amount or the monster bolster switch was changed, and all monsters are bolstered again. Change ' + P('Need') + '.'},
 {'name': 'GetArmorClass', 'args': ['Monster', 'MonsterIndex', 'AC', 'Player'], 'links': {'Monster': 'structs.MapMonster', 'Player': 'structs.Player'},
  'desc': 'A monster attacks ' + P('Player') + ': ' + P('AC') + ' is the character\'s Armor Class against this attack, after the bolster formula "PlayerAC". Change it.'},
]},
{'file': r'Scripts\General\SpellsExtra.lua', 'kind': 'events',
 'about': 'Spell settings from Data\\Tables\\SpellsExtra.txt; these events let other scripts change single values.', 'items': [
 {'name': 'SpellCostRecovery', 'args': ['Spell', 'SkillMastery', 'Caster', 'Cost', 'Recovery'],
  'desc': 'The spell point cost and the recovery of a spell are worked out; change ' + P('Cost') + ' and ' + P('Recovery') + '. '
   'SpellsExtra then adds its skill and Speed scaling for spells below 133.'},
 {'name': 'SpellFailCheck', 'args': ['Spell', 'Roll', 'Cursed', 'Mastery', 'Level', 'Type', 'Player', 'PlayerIndex', 'Chance'], 'links': {'Player': 'structs.Player'},
  'desc': 'The chance (%) that a spell works is set: ' + P('Chance') + ' from SpellsExtra.txt by ' + P('Mastery') + ' and skill ' + P('Level') + ' (lower when '
   + P('Cursed') + '); change it. ' + P('Type') + ': 0 = cast from the spellbook, 1 = from a scroll, 2 and 3 = with a set skill (items, NPCs; always 100).'},
 {'name': 'PlayerSpellProc', 'args': ['Spell', 'Caster', 'Flags'],
  'desc': 'A queued spell of a character is about to be processed; ' + P('Spell') + ' and ' + P('Flags') + ' may be changed (e.g. to replace the spell).'},
 {'name': 'PlayerSpellVar', 'args': ['Spell', 'VarNum', 'Value', 'Target', 'Mastery', 'Level', 'Flags', 'Type', 'Player', 'PlayerIndex'], 'links': {'Player': 'structs.Player'},
  'desc': 'A spell cast by a character reads one of its variables (power, duration, number of targets and so on; ' + P('VarNum') + ' as in SpellsExtra.txt). Change ' + P('Value') + '. '
   + P('Type') + ' as in ' + L('events.SpellFailCheck', 'SpellFailCheck') + '.'},
 {'name': 'SpellVar', 'args': ['Spell', 'VarNum', 'Value', 'Mastery', 'Level', 'CasterType', 'CasterIndex'],
  'desc': 'As ' + L('events.PlayerSpellVar', 'PlayerSpellVar') + ' for spells whose caster may be anyone (e.g. Blades, spell 44). ' + P('CasterType') + ' is a '
   + H('const.ObjectRefKind', 'const.ObjectRefKind') + ' value.'},
 {'name': 'SpellDmgVar', 'args': ['Spell', 'Level', 'Mastery', 'DmgVar', 'Value', 'CasterType', 'CasterIndex'],
  'desc': 'The damage of a spell is worked out: ' + P('DmgVar') + ' is "DmgConst", "DmgAdd" or "DmgRnd" (the fixed part, the part per skill level and the dice). Change ' + P('Value') + '.'},
 {'name': 'SpellTargetType', 'args': ['Spell', 'CasterSlot', 'Caster', 'Flags'],
  'desc': 'A character chooses the target of a spell; ' + P('Flags') + ' are the target flags of the spell and may be changed (e.g. to let a spell target a character or a monster).'},
]},
{'file': r'Scripts\General\Reputation.lua', 'kind': 'events',
 'about': 'Reputation per map or continent (Data\\Tables\\Reputation.txt). As in the game, a negative reputation is a good one.', 'items': [
 {'name': 'GetReputationRank', 'args': ['Reputation', 'Rank'],
  'desc': 'The rank of a reputation value is worked out (negative ranks are good, positive bad; the scale depends on the RepRanks setting); change ' + P('Rank') + '.'},
 {'name': 'GetReputationRankStr', 'args': ['Reputation', 'Rank', 'Ptr'],
  'desc': 'The text of a reputation rank is needed: set ' + P('Ptr') + ' to a pointer to the string. Reputation.lua sets it from the global texts by the RepRanks setting.'},
 {'name': 'DonationCost', 'args': ['Cost', 'HouseId'],
  'desc': 'The price of a donation in temple ' + P('HouseId') + '; change ' + P('Cost') + '.'},
 {'name': 'ReputationChanged', 'args': ['CurrentValue', 'PreviousValue'],
  'desc': 'A temple donation has changed the reputation from ' + P('PreviousValue') + ' to ' + P('CurrentValue') + '.'},
 {'name': 'DonationSpell', 'args': ['Spell', 'SkillLevel', 'SkillMastery', 'Reputation', 'Rank', 'DonationsMade', 'DonationsRequired', 'Caster', 'Cast'],
  'desc': 'After a donation the temple may cast a spell on the party: ' + P('Cast') + ' = true when enough donations were made. Change ' + P('Spell') + ' (by default 86), its skill, or ' + P('Cast') + '.'},
 {'name': 'ReputationTradeEffect', 'args': ['RepTradeEffect'],
  'desc': 'The effect of reputation on prices is worked out; change ' + P('RepTradeEffect') + '. The ReputationMaxTradeEffect setting limits it afterwards.'},
 {'name': 'DonationReputationChange', 'args': ['Limit', 'Subtractor', 'Reputation'],
  'desc': '<i>Not raised in this build: the code is commented out in Reputation.lua.</i>'},
]},
]
