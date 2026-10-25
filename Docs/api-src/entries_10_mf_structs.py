P = lambda n: '<b class="def-param">%s</b>' % n
C = lambda s: '<span class="def-code">%s</span>' % s
L = lambda a, t=None: '<a href="#%s">%s</a>' % (a, t or a.split('.')[-1])
H = lambda a, t=None: '<a href="MMExtension.htm#%s">%s</a>' % (a, t or a.split('.')[-1])
F = lambda n, a, d, ex=None: dict(name=n, args=a, desc=d, **({'example': ex} if ex else {}))

GROUPS = [
{'file': r'Scripts\Structs\15_MergeLog.lua', 'kind': 'functions',
 'about': 'Writes to the MMMerge log (MMMergeLog.txt); the level, times and sources are set in ' + C('Merge.Settings.Logging') + '.', 'items': [
 F('Log', 'LogLevel, Fmt, ...', 'Writes ' + C('string.format(Fmt, ...)') + ' to the log at ' + P('LogLevel') + ' (' + C('Merge.Log.Error') + ', ' + C('Warning') + ', ' + C('Info') + ', ' + C('Verbose') + '), if the log level setting is high enough. A formatting error is written instead of failing.'),
 F('LogError', 'Fmt, ...', 'Log at the Error level.'),
 F('LogWarning', 'Fmt, ...', 'Log at the Warning level.'),
 F('LogInfo', 'Fmt, ...', 'Log at the Info level.'),
 F('LogVerbose', 'Fmt, ...', 'Log at the Verbose level.'),
 F('LogInit1', 'log_id', '"Init started: log_id" at the Verbose level; scripts call it first thing.'),
 F('LogInit2', 'log_id', '"Init finished: log_id"; called at the end of a script.'),
 F('LogMem', 'Fmt, ...', 'Verbose log entry for memory patches (the source shown is the caller of the patch function).'),
 F('LogMem2', 'StackLvl, Fmt, ...', 'As LogMem, with the stack level of the source to show.'),
]},
{'file': r'Scripts\Structs\25_MergeFunctions.lua', 'kind': 'functions', 'about': 'General helpers.', 'items': [
 F('TableFilter', 't, preserve_indexes, ...',
   'Records of table ' + P('t') + ' that meet all conditions, given as triplets: field name, operator ("=", "!=", "&gt;", "&gt;=", "&lt;", "&lt;="), value. With ' + P('preserve_indexes') + ' = true the keys are kept. Also ' + C('table.filter') + '.',
   'local t = {{Name = "a", Level = 5}, {Name = "b", Level = 20}}\nlocal high = Merge.Functions.TableFilter(t, false, "Level", ">=", 10)  -- {{Name = "b", Level = 20}}'),
 F('TableIsEmpty', 't', 'true if the table has no entries.'),
 F('Asmpatch', 'address, code, sz', H('mem.asmpatch', 'mem.asmpatch') + ' that also writes the patch to the log (Verbose).'),
 F('Asmproc', 'code', H('mem.asmproc', 'mem.asmproc') + ' with a log entry; returns the address and the size.'),
 F('Hook', 'address, f, sz', H('mem.hook', 'mem.hook') + ' with a log entry.'),
 F('Autohook', 'address, f, sz', H('mem.autohook', 'mem.autohook') + ' with a log entry.'),
 F('Autohook2', 'address, f, sz', H('mem.autohook2', 'mem.autohook2') + ' with a log entry.'),
 F('StaticAlloc', 'sz, StackLvl', H('mem.StaticAlloc', 'mem.StaticAlloc') + ' with a log entry.'),
 F('cstring', 'str', 'Copies a Lua string into newly allocated memory as a null-terminated string and returns the pointer (also the global ' + C('mem_cstring') + '). The memory is never freed: cache pointers you use often.'),
 F('GetCurrentPlayer', '', 'Party slot of the selected character (' + C('Game.CurrentPlayer') + ', checked against the slots in use), or nil.'),
 F('GetCurrentRosterId', '', C('Party.PlayersArray') + ' index of the selected character, or nil.'),
 F('GetPlayerStatEffect', 'player, stat', 'The bonus the game gives for the value of stat ' + P('stat') + ' (' + H('const.Stats', 'const.Stats') + ') of ' + P('player') + ' (e.g. +5 for 25 Might).'),
 F('GetPlayerFromPtr', 'ptr', 'The ' + H('structs.Player', 'player') + ' at a memory address and its ' + C('Party.PlayersArray') + ' index (nil, -1 for an invalid pointer).'),
 F('GetSlotByIndex', 'player_index', 'Party slot of the ' + C('Party.PlayersArray') + ' index, or nil if that character is not in the party.'),
 F('GetSlotByPtr', 'ptr', 'Party slot of the character at a memory address, or nil.'),
 F('GetNPCMapMonster', 'npc_id', 'Index of the map monster that stands for NPC ' + P('npc_id') + ', or nil.'),
 F('CheckClassInParty', 'class', 'true if a party member has class ' + P('class') + ' (also a global function).'),
 F('RosterHasAward', 'award', 'true if any character of the roster (' + C('Party.PlayersArray') + ') has award ' + P('award') + ' (also global).'),
 F('ShowAwardAnimation', 'anim, slot', 'Plays the award face animation (default 96), sparkles and sound for the character in ' + P('slot') + ' (default: the selected one).'),
 F('AwardAdd', 'award, slot', 'Gives an award to a character (default: the selected one) with the animation, unless they have it already.'),
 F('QBitAdd', 'qbit', 'Sets a quest bit with the quest animation, unless it is set already.'),
 F('GetContinent', 'map_id', 'Continent (1 Jadame, 2 Antagarich, 3 Enroth) of a map (' + C('Game.MapStats') + ' index; default: the current map).'),
 F('GetGameDay', 't', 'Days since the start of the game for ' + C('t = {GameYear, Month, Day}') + ' (all from 0): GameYear &times; 336 + Month &times; 28 + Day.'),
 F('SplitReq', 'req', 'Splits a requirement string such as "2M10" into promotion level, mastery (B/E/M/G as 1..4) and skill level: returns 2, 3, 10. A plain number gives that number, 0, 0; "" gives 0, 0, 0.'),
 F('SettingEqNum', 's, val', 'true if setting ' + P('s') + ' (a string from ModSettings.txt) is a number equal to ' + P('val') + '. Also SettingGtNum / GtSettingNum (greater than) and SettingNeNum / NeSettingNum (not equal).'),
 F('SettingGtNum', 's, val', 'true if setting ' + P('s') + ' is a number greater than ' + P('val') + ' (alias GtSettingNum).'),
 F('GtSettingNum', 's, val', 'Alias of ' + L('Merge.Functions.SettingGtNum', 'SettingGtNum') + '.'),
 F('SettingNeNum', 's, val', 'true if setting ' + P('s') + ' is a number other than ' + P('val') + ' (alias NeSettingNum). A setting that isn\'t a number gives nil.'),
 F('NeSettingNum', 's, val', 'Alias of ' + L('Merge.Functions.SettingNeNum', 'SettingNeNum') + '.'),
 F('GetSkillLevelSkillpoints', 'rank', 'Skill points spent to raise a skill from 1 to ' + P('rank') + ': rank &times; (rank + 1) / 2 &minus; 1.'),
 F('CanPlayerLearnSpell', 't', 'true if ' + C('t.Player') + ' can learn spell ' + C('t.SpellId') + ' by the mastery of its school (racial abilities 100..132 included); raises ' + L('events.CanPlayerLearnSpell', 'CanPlayerLearnSpell') + '.'),
 F('ConvertCharacter', 't', 'Changes ' + C('t.Player') + ' to ' + C('t.ToClass') + ', ' + C('t.ToRace') + ', ' + C('t.ToMaturity') + ' (any of them): skills above what the new class and race allow are lowered and the skill points given back, spells that can\'t be learned any more are removed and racial abilities set.'),
 F('NPCCopy', 'src_npc_id, dst_npc_id', 'Copies the fields of one NPC (events, greeting, house, picture, profession and so on) onto another; false if either doesn\'t exist.'),
 F('NPCRestore', 'npc_id', 'Restores an NPC\'s fields from NPCData.txt.'),
 F('SetLastFountain', '', 'Sets the Town Portal "last fountain" to the destination of the current map, if it has one.'),
]},
{'file': r'Scripts\Structs\After\RemoveClassLimits.lua', 'kind': 'functions', 'items': [
 F('GetAllPromos', 't, Class, inc_self', 'Adds every class ' + P('Class') + ' can be promoted to (all stages, Promotions.txt) to table ' + P('t') + '; with ' + P('inc_self') + ' the class itself too.'),
 F('GetSkillPromos', 't1, t2, Skill, Mastery, Race, MinMaturity, MaxMaturity', 'Adds to ' + P('t1') + ' the classes of ' + P('t2') + ' (and their promotions) that reach ' + P('Mastery') + ' in ' + P('Skill') + ' for ' + P('Race') + '; used for the skill description.'),
 F('GetSkillPromoNames', 'Class, Skill, Mastery', 'Names of the promotions of ' + P('Class') + ' in which the selected character could reach ' + P('Mastery') + ' in ' + P('Skill') + ' (the "can be learned by" line of skill descriptions).'),
]},
{'file': r'Scripts\Structs\After\RemoveSkillValueLimits.lua', 'kind': 'functions', 'items': [
 F('GetPlayerSkillMastery', 'player, skill', 'The game\'s mastery of a character in a skill (raises ' + L('events.GetPlayerSkillMastery', 'GetPlayerSkillMastery') + ').'),
]},
{'file': r'Scripts\Structs\CharacterOutfits.lua', 'kind': 'functions', 'items': [
 F('GetPortraitSpcAttack', 'portrait, ranged', 'The default melee or ranged attack (a spell number) of a portrait in Character portraits.txt.'),
]},
{'file': r'Scripts\Structs\RaceHPSP.lua', 'kind': 'functions', 'items': [
 F('GetRaceHPSPTbl', 't', 'The Hit Point and Spell Point bonuses of ' + C('t.Race') + ' and ' + C('t.Class') + ' from RaceHPSP.txt (the class line or the race\'s default line), or nil.'),
]},
{'file': r'Scripts\Structs\RacialSkills.lua', 'kind': 'functions', 'items': [
 F('GetRaceSkillTbl', 't', 'The Race Skills.txt entry for ' + C('t.Race') + ', ' + C('t.Maturity') + ', ' + C('t.Class') + ' and ' + C('t.Skill') + '.'),
 F('GetMaxSkillMastery', 'a, b, c, d', 'Highest mastery a character can reach in a skill: ' + C('(Race, Class, Skill, Maturity)') + ' or ' + C('(Player, Skill, Maturity)') + '. Returns the mastery and the racial bonus.'),
]},
{'file': r'Scripts\Structs\RemoveHouseRulesLimits.lua', 'kind': 'functions', 'items': [
 F('GetCurrentHouse', '', 'The house the party is in (also a global function).'),
 F('GetGuildAssortCount', '', 'Number of guild assortments in House rules.txt.'),
]},
]
