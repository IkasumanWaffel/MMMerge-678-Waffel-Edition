P = lambda n: '<b class="def-param">%s</b>' % n
C = lambda s: '<span class="def-code">%s</span>' % s
L = lambda a, t=None: '<a href="#%s">%s</a>' % (a, t or a.split('.')[-1])
H = lambda a, t=None: '<a href="MMExtension.htm#%s">%s</a>' % (a, t or a.split('.')[-1])
F = lambda n, a, d, ex=None: dict(name=n, args=a, desc=d, **({'example': ex} if ex else {}))

GROUPS = [
{'file': r'Scripts\General\20_PlayersAttrs.lua', 'kind': 'functions',
 'about': 'Extra character data (race, maturity, alignment, extra buffs) kept in ' + C('Merge.Vars.PlayersAttrs') + ' and ' + C('Game.PlayersExtra') + '.', 'items': [
 F('SetRaceSpcAttack', 'roster_id, race, ranged, face', 'Sets the special melee (' + P('ranged') + ' false/0) or ranged attack of a roster character from the race table (Races.txt).'),
 F('DeterminePlayerMaturity', 'player', 'Maturity (promotion stage) of a character from its class (ClassesExtra Step), at most the MaxMaturity setting.'),
 F('PlayerAttrsClear', 'roster_id', 'Clears the extra data of a roster character: race, maturity, alignment, promotion awards, extra quick spells, extra buffs and debuffs.'),
 F('ResetPlayersAttrs', '', 'PlayerAttrsClear for the whole roster.'),
]},
{'file': r'Scripts\General\AdaptiveMonstersStats.lua', 'kind': 'functions', 'items': [
 F('GetMonsterKindSex', 'mon_kind, expanded', 'Gender of a monster kind from the bolster table (Bolster - monsters.txt). Without ' + P('expanded') + ': 0 male, 1 female.'),
]},
{'file': r'Scripts\General\Additional UI.lua', 'kind': 'functions', 'items': [
 F('UISendAlignment', '', 'Tells the UI layout the party\'s alignment (quest bits 611 light, 612 dark) and reloads the MM7 layout when it changed.'),
]},
{'file': r'Scripts\General\CustomRaceClassNames.lua', 'kind': 'functions', 'items': [
 F('GetRaceName', 'RaceId, ContinentId, AlignmentId, ClassId, NameType', 'Name of a race, which may differ by continent, alignment and class (CustomRaceClassNames.txt). Arguments may also be one table {RaceId = ..., ...}. Also a global function.'),
 F('GetClassName', 'ClassId, ContinentId, RaceId, AlignmentId', 'Name of a class, as GetRaceName. Also a global function.'),
]},
{'file': r'Scripts\General\ExtraQuickSpells.lua', 'kind': 'functions', 'items': [
 F('SetRegistryValue', 'Key, Value', 'Writes a number to the game\'s registry settings.'),
 F('GetRegistryValue', 'Key, Default', 'Reads a number from the game\'s registry settings, or ' + P('Default') + '.'),
 F('RegisterExtraKeyBind', 't', 'Adds a key binding to the extra key binds (shown in the controls menu): ' + C('t.DefKey') + ' the default key (refused when the game or another bind uses it), ' + C('t.RegValue') + ' the registry name to keep it in, plus the bind\'s own fields (action, name). Returns its number.'),
 F('UpdateExtraKeyBind', 'Id, Key', 'Changes the key of an extra key bind and saves it.'),
]},
{'file': r'Scripts\General\ItemsModifiers.lua', 'kind': 'functions', 'items': [
 F('CheckItemAdditionalDamage', 'itemptr, playerptr, monster', 'The extra damage of an item\'s enchantment against a monster (an index or a pointer; a monster type id summons a test monster for the check). Items and players may be structs or pointers. Returns the damage and the game\'s two result values (damage kind and the like).'),
]},
{'file': r'Scripts\General\MonsterKillStat.lua', 'kind': 'functions', 'items': [
 F('PrintMKS', '', 'Prints to the console a table of the monsters each character and the party have killed.'),
]},
{'file': r'Scripts\General\MonstersTweaks.lua', 'kind': 'functions', 'items': [
 F('GetMonsterPlayerPref', 'id, slot_id', 'Weight with which monster type ' + P('id') + ' picks the character in party slot ' + P('slot_id') + ' (base weight &times; class, race, sex and slot preferences).'),
 F('GetMonsterPreferredSlot', 'id', 'A party slot chosen at random by those weights (the game\'s target choice; see ' + L('events.MonsterChooseTargetPlayer', 'MonsterChooseTargetPlayer') + ').'),
]},
{'file': r'Scripts\General\NPCFollowers.lua', 'kind': 'functions',
 'about': 'Hirelings (' + C('vars.HiredNPC') + ') and quest followers (' + C('vars.NPCFollowers') + ').', 'items': [
 F('GetFollower', 'idx', 'NPC id of follower number ' + P('idx') + ' (hirelings first, then followers).'),
 F('FollowersCount', '', 'Number of hirelings and followers.'),
 F('ToggleNPCPanel', 'State', 'Opens or closes the followers panel (true / false; nothing switches it over).'),
 F('NPCFollowerRemove', 'i', 'Removes NPC ' + P('i') + ' from the quest followers; true if it was one.'),
 F('NPCFollowerAdd', 'i', 'Adds NPC ' + P('i') + ' to the quest followers; true if it wasn\'t one.'),
 F('NPCInGroup', 'id', 'Place of NPC ' + P('id') + ' among the hirelings or followers, or nil.'),
 F('NPCDismiss', 'NPCId, NoExit', 'Dismisses a hireling and sends it back to its house (' + P('NoExit') + ': stay in the dialog).'),
 F('HasNPCProfession', 'Prof', 'NPC id of a hireling with profession ' + P('Prof') + ', or nil.'),
 F('RemoveNPCProfession', 'Prof', 'Dismisses the first hireling with profession ' + P('Prof') + '; returns its id.'),
 F('NPCHire', 'NPCId, NoExit', 'Hires an NPC (default: the one being talked to), if there is room and the fees allow it.'),
]},
{'file': r'Scripts\General\Races.lua', 'kind': 'functions', 'items': [
 F('GetAbilitySpells', 'Skill, Mastery', 'Racial ability spells (100..132) given by ' + P('Skill') + ' at ' + P('Mastery') + '.'),
 F('GetRaceAbilitySpells', 'Race, Skill, Mastery, full', 'Spells of a race (Races.txt) of the school of ' + P('Skill') + ' at ' + P('Mastery') + ' (with ' + P('full') + ': up to it).'),
]},
{'file': r'Scripts\General\Reputation.lua', 'kind': 'functions',
 'about': 'Reputation by map, continent and world (Reputation.txt). Scope: 0 the current place (the change is shared out to its map, continent and world by the gains in Reputation.txt; bounty hunts use their own gains), 1 a map, 2 a continent, 3 the world. Source: 1 bounty hunt, 2 evt, 3 script.', 'items': [
 F('GetReputation', '', 'The current reputation (as the game reads it). Alias ReputationRead.'),
 F('ReputationRead', '', 'Alias of ' + L('Merge.Functions.GetReputation', 'GetReputation') + '.'),
 F('ReputationWrite', 'value', 'Writes the current reputation.'),
 F('ReputationRecalc', 'save', 'Works out the current reputation again from its map, continent and world parts.'),
 F('ReputationAdd', 'value, source, scope, target, norecalc', 'Adds ' + P('value') + ' to the reputation of ' + P('scope') + ' / ' + P('target') + ' (a map, continent or world number) within its limits, and recalculates the current one unless ' + P('norecalc') + '.',
   '-- the party is known for a good deed on the whole continent\nMerge.Functions.ReputationSub(10, 3, 2, Merge.Vars.Continent)'),
 F('ReputationSub', 'value, source, scope, target, norecalc', 'As ReputationAdd, subtracting (a lower reputation is a better one). Alias ReputationSubtract.'),
 F('ReputationSubtract', 'value, source, scope, target, norecalc', 'Alias of ' + L('Merge.Functions.ReputationSub', 'ReputationSub') + '.'),
 F('GetReputationMaxRank', '', 'Highest (worst) reputation rank of the current scale.'),
 F('GetReputationMinRank', '', 'Lowest (best) rank.'),
 F('GetReputationRank', 'reputation', 'Rank of a reputation value (raises ' + L('events.GetReputationRank', 'GetReputationRank') + ').'),
 F('GetReputationRankStr', 'rep', 'Name of the rank of a reputation value.'),
 F('CalcDecRep', 'rep, dec_mult, dec_flat, dec_min, lim_bot, lim_up, days', 'Reputation after ' + P('days') + ' days of fading towards the limits: per day a flat part, a share and a minimum, stopping at ' + P('lim_bot') + ' / ' + P('lim_up') + '.'),
]},
{'file': r'Scripts\General\SpellsExtra.lua', 'kind': 'functions', 'items': [
 F('DayOfProtectionPower', '', 'Resistance power of an active Day of Protection on the party, or 0 (recognised by its set of party buffs).'),
]},
{'file': r'Scripts\General\VisibleGauntletsRefactored.lua', 'kind': 'functions', 'items': [
 F('VisibleGauntlets', '', 'Table, not a function: ' + C('Poses') + ', ' + C('Get') + ', ' + C('ShownPose(side)') + ', ' + C('Set(item, doll, pose, x, y)') + ' and so on, for the gauntlet positions of the paperdolls (Visible gauntlets.txt); used by the Paperdoll Tuner.'),
]},
{'file': r'Scripts\Global\ExtraArtifacts.lua', 'kind': 'functions', 'items': [
 F('ArtifactAttackDelay', 'PlayerIndex, Ranged', 'Attack recovery change from a character\'s artifacts (melee or ranged); MMMWE_Main.lua applies it as a percentage.'),
]},
{'file': r'Scripts\Global\MMMWE_HardcoreMode.lua', 'kind': 'functions', 'items': [
 F('HCMStripPartyItems', '', 'Hardcore Mode: removes every item of the party except the kept ones; returns how many were removed.'),
]},
]
