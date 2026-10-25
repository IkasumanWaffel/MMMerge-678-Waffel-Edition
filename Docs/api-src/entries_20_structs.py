P = lambda n: '<b class="def-param">%s</b>' % n
C = lambda s: '<span class="def-code">%s</span>' % s
L = lambda a, t=None: '<a href="#%s">%s</a>' % (a, t or a.split('.')[-1])
H = lambda a, t=None: '<a href="MMExtension.htm#%s">%s</a>' % (a, t or a.split('.')[-1])
S = lambda n, d, f=None: dict(name=n, desc=d, **({'args': f} if f else {}))
TB = lambda n: '<a href="#tables.%s">%s</a>' % (n.replace(' ', '_'), n)

GROUPS = [
{'file': r'Scripts\Structs\30_MergeStructs.lua', 'kind': 'structs',
 'about': 'Extra character data: special attacks, extra buffs and debuffs. ' + C('Merge.Consts') + ' holds the counts (PlayerBuffs2Count 7, PlayerDebuffsCount 33, PartyBuffs2Count 6, PartyDebuffsCount 11).', 'items': [
 S('Game.PlayersExtra', 'Array [0..49] of ' + L('structs.PlayerExtra', 'PlayerExtra') + ', one for every ' + C('Party.PlayersArray') + ' entry (index = ' + C('player:GetIndex()') + ').'),
 S('PlayerExtra', C('SpcAttack[0..1]') + ' (also ' + C('SpcAttackMelee') + ', ' + C('SpcAttackRanged') + '): the racial special attacks (' + L('structs.SpcAttack', 'SpcAttack') + '). '
   + C('SpellBuffs2[27..33]') + ': extra character buffs (Spirit, Light, Dark resistance, Restore HP, Restore SP...; ' + H('structs.SpellBuff', 'SpellBuff') + '). '
   + C('Debuffs[0..32]') + ': debuffs: the conditions 0-12, 15, 17-19 shown as debuffs, and the drains 20-32 (MMMWE_Drains.lua: stats, Armor Corrosion, resistances).'),
 S('SpcAttack', 'A racial special attack: ' + C('Spell') + ', ' + C('Skill') + ', ' + C('DamageType') + ', ' + C('SpellPoints') + ', ' + C('Recovery') + ', ' + C('Cooldown') + ', '
   + C('NextTime') + ' (when it can be used again), ' + C('Projectile') + ', ' + C('Sound') + ', ' + C('Bits') + ' with the flags IgnoreByDefault, OverwriteMeleeBlaster, OverwriteMissileBlaster, PreferWand, '
   'Cooldown/RecoveryReducedBySpeed, ...BySkill, ...ByHaste, CooldownOther, UseOtherCooldown. Filled from ' + TB('Races.txt') + '.'),
 S('Party.SpellBuffs2', 'Extra party buffs [20..25] (' + H('structs.SpellBuff', 'SpellBuff') + ').'),
 S('Party.Debuffs', 'Party debuffs [0..10] (' + H('structs.SpellBuff', 'SpellBuff') + ').'),
]},
{'file': r'Scripts\Structs\GlobalTxt.lua', 'kind': 'structs', 'items': [
 S('Game.SpeedModifiers', 'Array [0..3] of floats: the game\'s movement speed factors (MiscTweaks.lua slows the party in turn-based mode through [0] and [1]).'),
 S('Game.PartyLight', C('Radius') + ', ' + C('Falloff') + ': the light around the party (floats in the game code, writable).'),
 S('Game.TurnBasedState', 'Turn-based mode: ' + C('RoundNumber') + ', ' + C('Phase') + ', ' + C('RoundLength') + ', ' + C('ParticipantsCount') + ', ' + C('CombatTimeLeft') + ', ' + C('PartyMoveTimeLeft') + '.'),
 S('Game.TurnBasedQueue', 'The turn-based queue (up to 64): ' + C('EntityRef') + ' with ' + C('Kind') + ' and ' + C('Index') + ' (' + H('const.ObjectRefKind', 'const.ObjectRefKind') + '), '
   + C('RecoveryDelay') + ', ' + C('NextQueueItemId') + '.'),
 S('Game.NPCNewsTopics', 'The news topic column of NPCNews.txt (set up by RemoveNPCTablesLimits.lua).'),
 S('Game.GlobalTxt, Game.TransTxt', 'Defined here when the base structures don\'t have them: the global texts (750) and the transition texts (500).'),
 S('Map.BloodSplats', 'Blood splats on the map (up to 64; ' + C('BloodSplatsCount') + ', ' + C('BloodSplatsCreated') + '): ' + C('X, Y, Z, Radius, R, G, B') + '. The global '
   + C('CreateBloodSplat(X, Y, Z, R, G, B, radius)') + ' makes one.'),
 S('Party.DaysWithoutRest', 'Days the party has gone without resting.'),
]},
{'file': r'Scripts\Structs\CharacterOutfits.lua', 'kind': 'structs', 'items': [
 S('Game.CharacterPortraits', 'Portraits [0..] from ' + TB('Character portraits.txt') + ': ' + C('DollType, DefClass, DefVoice, DefSex, AvailableAtStart, BodyX, BodyY, HelmX, HelmY') + ', the bitmap names '
   + C('Background, Body, Head, LHd, LHu, LHo, RHb, RHd, RHu, FacePrefix') + ', ' + C('DefAttackM, DefAttackR') + ' (default attacks), ' + C('NPCPic') + ', ' + C('Race') + '. '
   'The global ' + C('GetRace(Player)') + ' reads a character\'s race from here.'),
 S('Game.CharacterDollTypes', 'Paperdoll types from ' + TB('Character doll types.txt') + ': which item kinds the doll shows (' + C('Bow, Armor, Helm, Belt, Boots, Cloak, Weapon') + ') and the hand, weapon, bow and shield offsets.'),
 S('Game.CharacterVoices', C('Sounds[voice][sound]') + ', ' + C('Avail[voice][type]') + ': the voice sets of ' + TB('Character voices.txt') + '.'),
 S('Game.StatConditionModifiers', '[7][19] bytes: how much each condition lowers each stat (%).'),
 S('Game.CurrentCharPortrait', 'The portrait being chosen on the character creation screen.'),
]},
{'file': r'Scripts\Structs\RemoveHouseRulesLimits.lua', 'kind': 'structs',
 'about': 'Shop and guild assortments from ' + TB('House rules.txt') + '; the arrays are reallocated, so their size follows the table.', 'items': [
 S('Game.HouseRules', C('WeaponShopsStandart/Special') + ' (' + C('Quality') + ', ' + C('ItemTypes[1..4]') + '), ' + C('ArmorShopsStandart/Special') + ' (shelf and case: quality and item types), '
   + C('MagicShops...') + ', ' + C('Alchemists...') + ', ' + C('SpellbookShops') + ', ' + C('Training') + ' (' + C('Quality') + '), ' + C('Arcomage') + ' (' + C('TowerToWin, ResToWin, TowerAtStart, WallAtStart, Quarry, Magic, Dungeon, Bricks, Gems, Recruits, Ai') + ').'),
 S('Game.HousesExtra', 'Per house: ' + C('IndexByType') + ' (its line in House rules.txt) and ' + C('Map') + '.'),
 S('Game.ShopItems, Game.ShopSpecialItems', 'The standard and special stock of every shop: [shop][0..11] items. The index is the house id; a shop shows only the places its refill filled.'),
 S('Game.GuildItems, Game.GuildAssortIds, Game.GuildNextRefill2', 'Guild (spell shop) stock, the assortment each guild uses, and its next refill time.'),
 S('Game.ShopNextRefill, Game.ShopTheftExpireTime', 'Next refill time of every shop and when a theft ban ends.'),
 S('Game.TransportIndex', 'Stables and boats: the destinations of each.'),
 S('const.ShopTopics', 'Topic numbers of shops: Standart, Special, Inventory, Learn, Heal, Donate, RentRoom, BuyFood, PlayArcomage, StableTravel, BoatTravel, MagicFire ... MagicDark and so on.'),
]},
{'file': r'Scripts\Structs\RemoveItemsLimits.lua', 'kind': 'structs',
 'about': 'Items.txt, StdItems.txt, SpcItems.txt and potions without the original limits.', 'items': [
 S('Game.ArmorPicsCoords', C('Armors, Helms, Belts, Boots') + ' [item][doll type 0..3] {' + C('X, Y') + '}, ' + C('Cloaks') + ' {' + C('X, Y, ColX, ColY') + '}: paperdoll positions from ' + TB('Complex item pictures.txt') + '. '
   + C('Game.ArmorPicsOffsets') + ' holds the extra offsets of ' + TB('Complex item pictures offsets.txt') + '.'),
 S('Game.MixPotions', '[potion][potion] = result of mixing two potions (the alchemy table).'),
 S('Game.ReagentSettings', 'Reagents: ' + C('Item') + ' and the ' + C('Result') + ' potion they make (' + TB('Reagent settings.txt') + ').'),
 S('Game.MessageScrolls', 'Texts of the message scrolls.'),
 S('Game.ItemsChanceByLevelSum, Game.ItemsStdBonusChanceByLevel, Game.ItemsSpcBonusChanceByLevel', '[1..6] by treasure level: the sum of the random item chances, and the chances of a standard and a special enchantment.'),
]},
{'file': r'Scripts\General (Lua tables on Game)', 'kind': 'structs',
 'about': 'Plain Lua tables and functions MMMerge and the Waffel Edition put on ' + C('Game') + ' (not game memory).', 'items': [
 S('Game.ClassesExtra', '[class] = {' + C('Kind') + ' (family), ' + C('Step') + ' (promotion stage), ' + C('Alignment') + '} from ' + TB('Class Extra.txt') + ' (RemoveClassLimits.lua).'),
 S('Game.Races', '[race] = {' + C('Id, StringId, BaseRace, Family, Kind, Name, Plural, Adjective, Spells[mastery], SpcAttack[0..1]') + '} from ' + TB('Races.txt') + '. Also ' + C('Game.RacesCount, RaceKindsCount, RaceFamiliesCount, RaceMaturityMax') + ' (Races.lua).'),
 S('Game.RaceSkills', '[race][maturity][class][skill] = {' + C('Min, Add, Max, Bonus, Auto') + '} from ' + TB('Race Skills.txt') + ' (RacialSkills.lua).'),
 S('Game.Resistances', 'Race and class resistances from ' + TB('Resistances.txt') + '.'),
 S('Game.CustomRaceClassNames', 'The name table of ' + TB('CustomRaceClassNames.txt') + '.'),
 S('Game.CharSelection', C('PortraitsExceptions, ClassesByContinent, RaceByContinent, ClassByRace') + ' from ' + TB('Character selection.txt') + '.'),
 S('Game.ContinentSettings', '[continent] = {' + C('UI, TPAtStart, ChestType, ProfNews, NPCFollowers, Saturation, Softness, DeathMovie, Water, Skies, LoadingPics') + '}; ' + C('Game.DeathMaps') + ' [continent][1..2] = {' + C('n, X, Y, Z, Dir') + '} where the party wakes after death. From ' + TB('Continent settings.txt') + '.'),
 S('Game.Bolster', C('Monsters, Maps, Formulas, SpcMonsters, Multipliers') + ', ' + C('BolsterLevel()') + ', ' + C('OnLoadMap()') + ', ' + C('ReloadTxt()') + ', ' + C('DumpMonstersTxt, LoadMonstersTxt') + ': the bolster data of the Bolster tables. '
   + C('Game.BolsterAmount') + ' (%, extra settings), ' + C('Game.BolsterMonsters()') + ', ' + C('Game.ReBolsterMonsters()') + '.'),
 S('Game.OutdoorTravels', '[map file] = travel rules of ' + TB('Outdoor travels.txt') + '.'),
 S('Game.NPCProf, Game.NPCProfessions, Game.NPCPersonalities, Game.NPCNames', 'NPC professions (' + TB('NPC professions.txt') + '), their names, personalities (' + TB('NPC BTB.txt') + ') and names (' + TB('NPC names.txt') + ').'),
 S('Game.MapNews, Game.ContinentNews, Game.ProfessionNews', 'NPC news topics by area, continent and profession (the News topics tables).'),
 S('Game.TeacherTopics', '[topic] = {' + C('SId') + ' skill, ' + C('Mas') + ' mastery, ' + C('Text') + ', ' + C('Gold') + ', ' + C('Skill') + ' required} from ' + TB('Teacher topics.txt') + '.'),
 S('Game.MonsterPortraits', 'Monster portraits of ' + TB('MonPortraits.txt') + '.'),
 S('Game.HousesByMaps', '[map][house type] = list of houses (NPCMercenaries.lua).'),
 S('Game.BlvEntrances, Game.HouseExtraExitTopic, Game.HouseExtraExitNPCDummy', 'Dungeon entrances and the topic and NPC used for extra house exits (RemoveTransitionLimits.lua, ' + TB('House exits.txt') + ').'),
 S('Game.UISets', 'The interface sets of ' + TB('Additional UI.txt') + '; ' + C('Game.CustomInterface') + ', ' + C('Game.UIDependsOnContinent') + ', ' + C('Game.LoadUI(n)') + ' choose and load one.'),
 S('Game.ItemSounds', '[item] = sound played when a musical instrument is used.'),
 S('Game.SmallerPotionBottles, Game.FrameLimit', 'Options of the extra settings (smaller bottle pictures; frame limit, with ' + C('Game.SetFrameLimit(n)') + ').'),
 S('Game.MapMusicSets', '[map] = the "any time" music tracks of a map (MMMWE_Main.lua), the base of MMMWE_Music.lua.'),
 S('Game functions', C('Game.SetWeather') + ', ' + C('Game.SetMapNote') + ', ' + C('Game.TransformToZombie') + ', ' + C('Game.RecountFoundArtifacts') + ', ' + C('Game.CountItemBonuses') + ', ' + C('Game.GetMonstersInSight') + ', '
   + C('Game.ReInitSprites') + ', ' + C('Game.ReInitSpriteEvent') + ', ' + C('Game.UnloadPalettes') + ', ' + C('Game.PrintEndCard(Text, BackImg)') + ', ' + C('Game.LastCreatedObject()') + ' (the last object made by ' + C('Game.SummonObjects') + ').'),
]},
]
