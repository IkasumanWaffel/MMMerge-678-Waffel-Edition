P = lambda n: '<b class="def-param">%s</b>' % n
C = lambda s: '<span class="def-code">%s</span>' % s
L = lambda a, t=None: '<a href="#%s">%s</a>' % (a, t or a.split('.')[-1])
H = lambda a, t=None: '<a href="MMExtension.htm#%s">%s</a>' % (a, t or a.split('.')[-1])
F = r'Scripts\General\ExtraEvents.lua'

GROUPS = [{'file': F, 'kind': 'events', 'about': 'Events added by MMMerge to many places of the game code.', 'items': [

{'name': 'SetOutdoorLight', 'args': ['Hour', 'Minute'],
 'desc': 'Called when the game reads the time of day to work out the outdoor light and sky. Each call passes the field the game is reading at that moment; '
  'change it to light the outdoors as if it were another time (e.g. keep a map in daylight).'},

{'name': 'TileSound', 'args': ['X', 'Y', 'Run', 'Sound'],
 'desc': 'Outdoors: a footstep sound is chosen for the ground tile at ' + P('X') + ', ' + P('Y') + '. Change ' + P('Sound') + ' for another sound (e.g. for an extra tile set); '
  + P('Run') + ' tells whether the party runs. ' + L('events.TileSoundChosen', 'TileSoundChosen') + ' follows with the final sound, for anything that should happen on a step.'},
{'name': 'TileSoundChosen', 'args': ['X', 'Y', 'Run', 'Sound'],
 'desc': 'Called after ' + L('events.TileSound', 'TileSound') + ' with the sound that will be played. Meant for reacting to steps on a tile, not for changing the sound.'},
{'name': 'StepSound', 'args': ['Sound', 'Run', 'Facet'],
 'desc': 'A footstep sound is chosen for the facet the party walks on: a facet of an indoor map or of an outdoor model. Change ' + P('Sound') + '. ' + P('Run') + ' is 1 when running. '
  + L('events.StepSoundChosen', 'StepSoundChosen') + ' follows with the final sound.'},
{'name': 'StepSoundChosen', 'args': ['Sound', 'Run', 'Facet'],
 'desc': 'Called after ' + L('events.StepSound', 'StepSound') + ' with the sound that will be played.'},

{'name': 'GotItem', 'args': 'ItemNumber',
 'desc': 'The party has just got an item onto the mouse cursor (e.g. picked up from the ground); ' + P('ItemNumber') + ' is ' + C('Mouse.Item.Number') + '.'},

{'name': 'RegenTick', 'args': 'Player, PlayerIndex',
 'desc': 'The game\'s regeneration tick of a character, every 5 game minutes; unlike timers it keeps ticking while the party rests. '
  'The Waffel Edition pays the gains of a tick out over the next 5 minutes (see ' + L('Merge.Functions.RegenGive', 'RegenGive') + ').'},

{'name': 'CalcRestFoodCost', 'args': ['Amount'],
 'desc': 'The food needed to rest is worked out; change ' + P('Amount') + '.'},
{'name': 'CalcJumpHeight', 'args': ['Height'],
 'desc': 'The height of a jump is worked out; change ' + P('Height') + '. MMMerge itself limits it to 420 here.'},
{'name': 'CanCastTownPortal', 'args': ['CanCast', 'Handled', 'Mastery'],
 'desc': 'Town Portal is about to be cast (it is checked from the ' + C('SpellFailCheck') + ' event). Set ' + P('CanCast') + ' = false to make it fail, or '
  + P('Handled') + ' = true to make it succeed for sure. ' + P('Mastery') + ' is the caster\'s Water mastery.'},

{'name': 'CanOpenChest', 'args': ['CanOpen', 'ChestId'],
 'desc': 'A chest is about to be opened; set ' + P('CanOpen') + ' = false to keep it closed. Meant also for changing the list of items before it is shown. '
  'If it opens, the old ' + L('events.OpenChest', 'OpenChest') + ' follows.'},
{'name': 'OpenChest', 'args': 'ChestId',
 'desc': 'Kept for older scripts: called after ' + L('events.CanOpenChest', 'CanOpenChest') + ' allowed the chest to open.'},
{'name': 'BeforeChestTrapTriggered', 'args': ['Handled', 'CanOpenChest', 'ChestId', 'TrapRef'],
 'desc': 'A chest trap is about to go off. Set ' + P('Handled') + ' = true to skip the game\'s trap (e.g. for a trap of your own); ' + P('CanOpenChest')
  + ' then decides whether the chest opens. Otherwise ' + L('events.ChestTrapTriggered', 'ChestTrapTriggered') + ' follows.'},
{'name': 'ChestTrapTriggered', 'args': 'ChestId, TrapRef',
 'desc': 'The trap of chest ' + P('ChestId') + ' goes off (not called when ' + L('events.BeforeChestTrapTriggered', 'BeforeChestTrapTriggered') + ' handled it).'},
{'name': 'BeforeGotGold', 'args': ['Amount'],
 'desc': 'The party finds gold (on a corpse or as a gold item); change ' + P('Amount') + '.'},
{'name': 'PickObject', 'args': ['Handled', 'ObjectId'],
 'desc': 'The party tries to pick up object ' + C('Map.Objects[ObjectId]') + ': by a mouse click, with the space bar or with Telekinesis. Set ' + P('Handled')
  + ' = true to leave it where it is. MMMerge also stops the space bar from picking up objects farther than 500 from the party.'},

{'name': 'ClickShopTopic', 'args': ['Handled', 'Topic', 'HouseId'],
 'desc': 'A topic is clicked in a shop (topic numbers in ' + C('const.ShopTopics') + ', from RemoveHouseRulesLimits.lua). Set ' + P('Handled')
  + ' = true to do your own thing instead of the game\'s. Changing ' + P('Topic') + ' is possible but will most probably crash the game.'},
{'name': 'GetFameBase', 'args': ['Handled', 'Result', 'Base'],
 'desc': 'The party\'s fame is worked out: the game divides ' + P('Base') + ' (the first character\'s experience) by 250. Change ' + P('Base')
  + ', or set ' + P('Handled') + ' = true and ' + P('Result') + ' to the fame itself.'},
{'name': 'GetLoadingPic', 'args': ['Pic'],
 'desc': 'The picture of the loading screen is chosen; set ' + P('Pic') + ' to another bitmap name.'},
{'name': 'CanShowHealTopic', 'args': ['CanShow'],
 'desc': 'A temple decides whether to show its Heal topic; change ' + P('CanShow') + '.'},
{'name': 'GetTravelDaysCost', 'args': ['Days', 'House'],
 'desc': 'The days of a trip by stable or boat from house ' + P('House') + ' are worked out; change ' + P('Days') + '.'},
{'name': 'CalcTrainingTime', 'args': ['House', 'Time'],
 'desc': 'The time spent training in a training hall (' + P('House') + ') is worked out; change ' + P('Time') + ' (game time units, see ' + H('const.Minute', 'const.Minute') + ').'},

{'name': 'CanIdentifyItem', 'args': ['CanIdentify', 'Player', 'Item', 'Object', 'ObjectIndex'], 'links': {'Player': 'structs.Player', 'Item': 'structs.Item'},
 'desc': 'The current character ' + P('Player') + ' is checked for identifying ' + P('Item') + '; change ' + P('CanIdentify') + '. '
  + P('Object') + ' and ' + P('ObjectIndex') + ' are set when the item lies on the map.'},
{'name': 'CanRepairItem', 'args': ['CanRepair', 'Player', 'Item', 'Object', 'ObjectIndex'], 'links': {'Player': 'structs.Player', 'Item': 'structs.Item'},
 'desc': 'As ' + L('events.CanIdentifyItem', 'CanIdentifyItem') + ', for repairing a broken item; change ' + P('CanRepair') + '.'},
{'name': 'ArtifactGenerated', 'args': ['ItemId'],
 'desc': 'The game has picked a random artifact (for a chest, a monster or a reward); change ' + P('ItemId') + ' to give another one.'},
{'name': 'ArrowProjectile', 'args': ['ObjId', 'PlayerIndex'],
 'desc': 'A character (' + C('Party.PlayersArray[PlayerIndex]') + ') shoots an arrow; ' + P('ObjId') + ' is the object kind of the missile (ObjList). Change it for another missile.'},
{'name': 'DragonBreathProjectile', 'args': ['ObjId', 'PlayerIndex'],
 'desc': 'As ' + L('events.ArrowProjectile', 'ArrowProjectile') + ', for the breath attack of a Dragon character.'},
{'name': 'GetSpellSkill', 'args': ['Player', 'PlayerIndex', 'Skill', 'Result', 'Spell'], 'links': {'Player': 'structs.Player'},
 'desc': 'Called from ' + H('events.GetSkill', 'GetSkill') + ' while a spell (' + P('Spell') + ') is being cast and the game asks for the skill of its school. '
  'Spells 135 (blaster shot) and 137 (dragon breath) count as Blaster and Dragon Ability. Change ' + P('Result') + ' to cast the spell at another skill.'},
{'name': 'BeforeLeaveGame', 'args': '',
 'desc': 'Called before ' + H('events.LeaveGame', 'LeaveGame') + ', when Quit is clicked the second time; the map data is still there.'},
{'name': 'MonsterDropItem', 'args': ['MonsterIndex', 'Monster', 'ItemId', 'Handled'], 'links': {'Monster': 'structs.MapMonster'},
 'desc': 'A dead monster drops an item: the item it carried, or (MonsterItems.lua) the extra item of its kind. Change ' + P('ItemId') + ', or set '
  + P('Handled') + ' = true to drop nothing.'},
{'name': 'TurnBasedStarted', 'args': '', 'desc': 'Turn-based mode is switched on.'},
{'name': 'TurnBasedStopped', 'args': '', 'desc': 'Turn-based mode is switched off.'},
{'name': 'MonsterCanCastSpell', 'args': ['Spell', 'Monster', 'MonsterIndex', 'Target', 'TargetRef', 'Distance', 'Result'], 'links': {'Monster': 'structs.MapMonster'},
 'desc': 'A monster checks whether it may cast ' + P('Spell') + ' now; change ' + P('Result') + '. ' + P('Target') + ' is ' + C('Party') + ', a monster, or 0; '
  + P('TargetRef') + ' its kind (4 party, 3 monster, see ' + H('const.ObjectRefKind', 'const.ObjectRefKind') + '); ' + P('Distance') + ' the distance to it.'},
{'name': 'MonsterCastSpellM', 'args': ['Spell', 'Monster', 'Target', 'TargetRef', 'Handled'], 'links': {'Monster': 'structs.MapMonster'},
 'desc': 'A monster is about to cast ' + P('Spell') + ' at ' + P('Target') + '. Change ' + P('Spell') + ' for another one, or set ' + P('Handled') + ' = true to cancel the cast. '
  'For the effect of a monster spell see ' + H('events.MonsterCastSpell', 'MonsterCastSpell') + '.'},
{'name': 'MonstersProcessed', 'args': '',
 'desc': 'The game has finished its pass over all monsters (movement and actions).'},
{'name': 'OnEnterShop', 'args': ['HouseId', 'Banned'],
 'desc': 'The party enters a shop; set ' + P('Banned') + ' to a nonzero value to refuse entry.'},
{'name': 'IsMonsterOfKind', 'args': ['Id', 'Kind', 'Result'],
 'desc': 'The game checks whether monster type ' + P('Id') + ' is of kind ' + P('Kind') + ' (' + H('const.MonsterKind', 'const.MonsterKind') + ': undead, dragon and so on, e.g. for "of Slaying" items); change ' + P('Result') + '.'},
{'name': 'OnHasItemBonus', 'args': ['Bonus2', 'Player', 'PlayerIndex', 'Result'], 'links': {'Player': 'structs.Player'},
 'desc': 'The game looked for special bonus ' + P('Bonus2') + ' on the items a character wears and found none. Set ' + P('Result') + ' = 1 to give the bonus anyway (e.g. from an artifact or a buff).'},
{'name': 'CanPlayerLearnSpell', 'args': ['ReqLevel', 'Level', 'Player', 'PlayerIndex', 'BookIndex', 'SpellId'], 'links': {'Player': 'structs.Player'},
 'desc': 'A character tries to learn a spell from book ' + P('BookIndex') + ' (spell ' + P('SpellId') + '). The spell is learned when ' + P('Level') + ' &ge; ' + P('ReqLevel')
  + ' (the spell\'s level); ' + P('Level') + ' &ge; 64 learns it even without the magic skill. Change ' + P('Level') + '. Also called by ' + L('Merge.Functions.CanPlayerLearnSpell', 'Merge.Functions.CanPlayerLearnSpell') + '.'},
{'name': 'SpellScrollSkillValue', 'args': ['SpellId', 'Player', 'PlayerId', 'SkillLevel', 'SkillMastery', 'Item'], 'links': {'Player': 'structs.Player'},
 'desc': 'A spell scroll is read; change ' + P('SkillLevel') + ' and ' + P('SkillMastery') + ' to set the skill it casts at (by default from the scroll, or by its game part with the SpellScrollRanks setting).'},
{'name': 'ItemSold', 'args': ['Item', 'Value'],
 'desc': 'An item is sold in a shop: ' + P('Item') + ' is its number, ' + P('Value') + ' the gold received.'},
{'name': 'PlayerYell', 'args': '', 'desc': 'A character yells (the Yell key).'},
{'name': 'PlayerCastSpell', 'args': ['SpellId', 'Player', 'PlayerIndex', 'SPCost', 'Skill', 'Mastery', 'TargetKind', 'TargetId', 'InventorySlot', 'IsSpellScroll', 'CurseInterrupt', 'Handled'],
 'desc': '<i>Not raised in this build: the code is commented out in ExtraEvents.lua.</i> Was meant to be called for every spell a character casts, with '
  + C('PlayerCastSpellFirst') + ' and ' + C('PlayerCastSpellLast') + ' around it in multiplayer.'},
{'name': 'PlayerCastSpellFirst', 'args': '(see PlayerCastSpell)', 'desc': '<i>Not raised in this build</i> (see ' + L('events.PlayerCastSpell', 'PlayerCastSpell') + ').'},
{'name': 'PlayerCastSpellLast', 'args': '(see PlayerCastSpell)', 'desc': '<i>Not raised in this build</i> (see ' + L('events.PlayerCastSpell', 'PlayerCastSpell') + ').'},
]}]
