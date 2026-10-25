C = lambda s: '<span class="def-code">%s</span>' % s
L = lambda a, t=None: '<a href="#%s">%s</a>' % (a, t or a)
H = lambda a, t=None: '<a href="MMExtension.htm#%s">%s</a>' % (a, t or a.split('.')[-1])
TB = lambda n: '<a href="#tables.%s">%s</a>' % (n.replace(' ', '_'), n)
T = lambda n, d, cols=None: dict(name=n, desc=d, **({'args': cols} if cols else {}))
X = C('x') + ' / ' + C('-')
MAS = 'mastery letters ' + C('B, E, M, G')

GROUPS = [
{'file': r'Data\Tables (MMExtension)', 'kind': 'tables',
 'about': 'Tables of the base MMExtension, loaded by General\\DataTables.lua. See ' + H('More-on-Data-Tables', 'More on Data Tables') + ' in the base help; MMMerge only enlarges them.', 'items': [
 T('Base tables', C('Class HP SP, Class Skills, Class Starting Skills, Class Starting Stats, House Movies, SFT, DecList, PFT, IFT, TFT, Chest, Overlay, ObjList, MonList, Sounds, Tile, Tile2, Tile3, Monster Kinds, Spells2, Town Portal, Transport Index, Transport Locations') + '. '
   'Tile, Tile2 and Tile3 are the tile sets of MM8, MM7 and MM6 maps. Class tables have a column for every class of the merge, Class Starting Stats one for every race ("Might 11/25": start / maximum, "+ add" rows: points per click). '
   'Class Skills cells: ' + MAS + ', ' + C('-') + ' none.'),
]},
{'file': r'Scripts\Structs\RacialSkills.lua, RaceHPSP.lua, Resistances.lua', 'kind': 'tables', 'items': [
 T('Race Skills.txt', 'One row per race, one column per skill. A cell is ' + C('Min/Add/Max/Bonus/Auto') + ': the lowest mastery the race has, mastery steps added to the class limit, the highest mastery, bonus skill points, and whether the skill is learned at the start (1). '
   + C('-') + ' keeps the class default, ' + C('0') + ' forbids the skill; masteries as ' + C('0..4') + ' or ' + MAS + '. Read into ' + L('Game.RaceSkills') + '.', '#, Note, Staff (0) ... one per skill'),
 T('RaceHPSP.txt', 'HP and SP changes of a race to its class numbers: ' + C('HPBase, HPFactor, SPBase, SPFactor') + '; factors may be fractions like ' + C('-4/4') + '.', '#, Note, HPBase, HPFactor, SPBase, SPFactor'),
 T('Resistances.txt', 'Resistance bonuses: race (-1 any) and class (-1 any), the resistance number (' + H('const.Damage', 'const.Damage') + ') and its value. Read into ' + L('Game.Resistances') + '.', '#, Race, RaceName, Class, ClassName, Resistance, Value'),
]},
{'file': r'Scripts\General\Races.lua', 'kind': 'tables', 'items': [
 T('Races.txt', 'The races: their string id, base race, family (undead, vampire, zombie, ghost...) and kind, names, the racial spells per mastery (' + C('SpellsB ... SpellsG') + ', comma lists) and the two special attacks (' + C('SpcM...') + ' melee, ' + C('SpcR...') + ' ranged: Spell, Skill, Dmg, SP, Recv, Bits, CD, Proj, Sound). Read into ' + L('Game.Races') + ' and ' + L('structs.SpcAttack', 'SpcAttack') + '.',
   '#, StringId, BaseRace, Family, Kind, Name, Plural, Adjective, SpellsB..SpellsG, SpcM*, SpcR*'),
]},
{'file': r'Scripts\Structs\After\RemoveClassLimits.lua', 'kind': 'tables', 'items': [
 T('Class Extra.txt', 'Per class: ' + C('Kind') + ' (family, shared by all its promotions), ' + C('Step') + ' (0 base, 1 first promotion, 2 second...), ' + C('Alignment') + ' (light, dark, neutral). Used for maturity, resources (MMMWE_Resources.lua) and class names. Read into ' + L('Game.ClassesExtra') + '.', '#, Kind, Step, Alignment, Note'),
]},
{'file': r'Scripts\General\Promotions.lua', 'kind': 'tables', 'items': [
 T('Promotions.txt', 'The classes a class can be promoted to (one or more columns of class numbers).', '# Class, Note, Promotions...'),
]},
{'file': r'Scripts\General\SpellsLearning.lua', 'kind': 'tables', 'items': [
 T('SpellsLearning.txt', 'Who may learn a spell: one row per class, one column per spell (1..99). A cell is a comma list of requirements, each a mastery letter and a skill level (' + C('B1, E4, M7, G10') + '), optionally with a character level; ' + C('-') + ' or ' + C('0') + ': never. Written with the defaults if missing.', '#, Note, 1 Torch Light ... 99'),
]},
{'file': r'Scripts\General\SpellsExtra.lua', 'kind': 'tables', 'items': [
 T('SpellsExtra.txt', 'Per spell and mastery: success chance (' + C('ChanceBase, ChanceFactor, ChanceMax, ChanceCursed') + '), then the extra numbers of the spell such as Duration and damage, by mastery.', '#, Spell, ChanceBaseNormal ... (by mastery), extras'),
]},
{'file': r'Scripts\Structs\CharacterOutfits.lua', 'kind': 'tables', 'items': [
 T('Character portraits.txt', 'Every portrait: paperdoll type, default class, voice and sex, ' + C('Available at start') + ' (' + X + '), body and helm offsets, background and body part bitmaps, face picture prefix, default melee and ranged attack items, NPC picture and race. Read into ' + L('Game.CharacterPortraits') + '.',
   '#, Paperdoll type, Def class, Def voice, Def sex, Available at start, Body X/Y, Helm X/Y, Background, bod, head, LHd, LHu, LHo, RHb, RHd, RHu, Face pics prefix, ...'),
 T('Character doll types.txt', 'Per doll type: which items it shows (' + X + ' for Bow, Armor, Helm, Belt, Boots, Cloak, Weapon), the hand picture offsets (RHo, RHc, RHf, LHo, LHc, LHf: open, closed, fist) and the main and off hand weapon offsets. Read into ' + L('Game.CharacterDollTypes') + '.', '#, Bow, Armor, Helm, Belt, Boots, Cloak, Weapon, RHo X/Y ... MH Offset X/Y'),
 T('Character voices.txt', 'One row per sound type (several rows for the variants), one column per voice set: the sound ids. Read into ' + L('Game.CharacterVoices') + '.', 'Soundtype/Voicesetid, 0, 1 ...'),
]},
{'file': r'Scripts\General\MenuChooseCharacter.lua, MenuChooseContinent.lua', 'kind': 'tables', 'items': [
 T('Character selection.txt', 'Which race may take which class at character creation (' + X + '), per continent. Read into ' + L('Game.CharSelection') + '.', 'Race/Class, Archer, WarriorMage ...'),
 T('Continent settings.txt', 'Per continent (1 Jadame, 2 Antagarich, 3 Enroth): UI set, Town Portal at start, reputation effects, chest type, reputation fading, profession news, NPC followers, colour saturation and softness, death movie, water texture, the two death maps with ' + C('X, Y, Z, Dir') + ', skies and loading pictures. Read into ' + L('Game.ContinentSettings') + '.',
   '#, Note, UI, TPAtStart, Rep affects shops, Rep affects NPC, ChestType, Rep dec flat, Rep dec min, Tell prof news, NPC Followers, Saturation, Softness, Death movie, Water, death maps, Skies, Loading pics'),
]},
{'file': r'Scripts\General\CustomRaceClassNames.lua', 'kind': 'tables', 'items': [
 T('CustomRaceClassNames.txt', 'Names that replace the race or class name when all key columns match (-1 matches anything): continent, race kind, family, race, alignment, class kind, step, class. Used by ' + L('Merge.Functions.GetRaceName', 'GetRaceName') + ' and ' + L('Merge.Functions.GetClassName', 'GetClassName') + '.', '#, Continent, RaceKind, RaceFamily, Race, Alignment, ClassKind, ClassStep, Class, RaceName, RacePlural, RaceAdj, ClassName'),
]},
{'file': r'Scripts\General\Additional UI.lua', 'kind': 'tables', 'items': [
 T('Additional UI.txt', 'Interface sets: lod file with the pictures, positions of the portraits, the hostile indicator and the other screen parts. Row 1 is the MM8 interface, row 2 the MM7 one. Read into ' + L('Game.UISets') + '.', '#, Lod name, D Lod name, Char Y, Char0..4 X, Show blank hostile indicator, ...'),
]},
{'file': r'Scripts\General\AdaptiveMonstersStats.lua', 'kind': 'tables', 'about': 'Monster bolster (scaling to the party). All read into ' + L('Game.Bolster') + '.', 'items': [
 T('Bolster - monsters.txt', 'Per monster type: type and extra types, creed, gender, style, preferred magic, no bounty hunt, new ranged attacks, spells and summons, size affects HP, replication, extra points and so on.', '#, Note, Type, ExtraType, Creed, Gender, Style, Pref magic, No bounty hunt, ...'),
 T('Bolster - maps.txt', 'Per map: continent, bolster kind (e.g. LowerToEqual), spells, summons, weather, extra bolster, the highest rarity of NPC professions, custom sky.', '#, Note, Continent, Bolster kind, Spells, Summons, Weather, Bolster extra, Profs max rarity, Custom sky'),
 T('Bolster - formulas.txt', 'Lua expressions for each monster stat (HP, AC, damage, ...) by target (' + C('def') + ' for all); they see PartyLevel, MonsterLevel, MonsterPower, MonSettings and the like.', 'Target, Stat, Formula, Notes'),
 T('Bolster-SpcMonsters.txt, Bolster-MapMonsters.txt', 'Special monsters with fixed stats (level, HP, AC, attacks, spells...) and where they are placed (map, monster index, name id).', '#Id, Note, Level, FullHP, AC, ... / #Id, MapId, MapName, Index, NameId, SpcId, Note'),
]},
{'file': r'Scripts\General\MonstersTweaks.lua', 'kind': 'tables', 'items': [
 T('MonsterPrefClass.txt, MonsterPrefRace.txt, MonsterPrefMisc.txt', 'How much each monster type prefers to attack a class, a race, a party slot or a sex. Used by ' + L('Merge.Functions.GetMonsterPlayerPref', 'GetMonsterPlayerPref') + '.', '#, Monster, one column per class / race / Slot 0..4, Male, Female'),
]},
{'file': r'Scripts\General\MMMWE_DamageKinds.lua', 'kind': 'tables', 'items': [
 T('Physical Damage Kinds.txt', 'Per monster type: the modifiers (%) against slashing, piercing and blunt damage and the kind of its own melee hit. Phys and Profile are for reference only. See ' + L('Merge.Functions.PhysKindReduction', 'PhysKindReduction') + '.', '#, Monster, Picture, Slashing, Piercing, Blunt, Phys (reference), Profile (reference), Melee Kind'),
]},
{'file': r'Scripts\Structs\After\RemoveMonPortraitsLimits.lua', 'kind': 'tables', 'items': [
 T('MonPortraits.txt', 'Per monster type: the picture indexes of its portrait (several are picked at random). Read into ' + L('Game.MonsterPortraits') + '.', '#, Pic index, Note'),
]},
{'file': r'Scripts\General\ItemsModifiers.lua', 'kind': 'tables', 'items': [
 T('ItemsExtra.txt', C('ContF') + ': how often an item appears on each continent (factors for Jadame, Antagarich, Enroth, e.g. ' + C('3,1,1') + '); quest items: ' + C('QCont') + ' continent, the quest bits ' + C('LostQBit, StartQBit, EndQBit') + ' and ' + C('PostEnd') + ' (what happens to the item after the quest). MMMWE_Blasters.lua sets the ore factors.', 'Id, Note, ContF, QCont, LostQBit, StartQBit, EndQBit, PostEnd'),
]},
{'file': r'Scripts\Structs\RemoveItemsLimits.lua', 'kind': 'tables', 'items': [
 T('Potion settings.txt', 'Per potion: its item, the Alchemy mastery needed to make it, drinkable and usable (' + X + ').', 'Pot Id, Item Id, Required mastery, Drinkable, Usable, Notes'),
 T('Reagent settings.txt', 'Per reagent: its item and the potion it makes. Read into ' + L('Game.ReagentSettings') + '.', 'Reagent Id, Item Id, Result item id, Notes'),
 T('Complex item pictures.txt', 'Paperdoll positions of armor, helms, belts, boots and cloaks for every doll type (t0..t5: X, Y). Edited in game with the Paperdoll Tuner. Read into ' + L('Game.ArmorPicsCoords') + '.', 'Id, Item id, Notes, X/Y per doll type'),
 T('Complex item pictures offsets.txt', 'Extra offsets of an item picture for one portrait (-1: all).', 'Portrait id, Item id, X, Y'),
]},
{'file': r'Scripts\General\VisibleGauntletsRefactored.lua', 'kind': 'tables', 'items': [
 T('Visible gauntlets.txt', 'Positions of gauntlet pictures on the paperdolls per doll type and hand pose. Written on the first start; edited with the Paperdoll Tuner. See ' + L('Merge.Functions.VisibleGauntlets', 'VisibleGauntlets') + '.', 'Item, Doll type, Pose, X, Y, Notes'),
]},
{'file': r'Scripts\Structs\RemoveHouseRulesLimits.lua', 'kind': 'tables', 'items': [
 T('House rules.txt', 'Sections (a title row such as "Weapon shops Standart") with one row per shop of that type: the treasure level and up to four item types it sells; armor shops have shelf and case parts; guilds, training halls and Arcomage taverns have their own columns. Read into ' + L('Game.HouseRules') + '.', 'Index by type, Quality, Items1..Items4, ...'),
]},
{'file': r'Scripts\Structs\After\RemoveTransitionLimits.lua', 'kind': 'tables', 'items': [
 T('House exits.txt', 'The NPC pictures, the free NPC and the free topic used to show extra house exits (' + L('Game.BlvEntrances') + ').', 'NPC pics: ..., Free NPC:, Free topic:'),
]},
{'file': r'Scripts\General\NPCFollowers.lua, NPCNewsTopics.lua', 'kind': 'tables', 'items': [
 T('NPC professions.txt', 'Per profession: name (Global.txt), rarity, cost per week, percent, personality, action topic, casts per day, joins, recruit, join text and description. Read into ' + L('Game.NPCProf') + '.', '#, Professions, Prof name (Global.txt), Rarity, Cost/w, Percent, Personality, Action Topic, Casts per day, Joins, Recruit, Join Text, Description'),
 T('NPC BTB.txt', 'NPC personalities: whether beg, bribe and threat work, creed, fame and reputation needed, and the text ids of the replies.', ', Beg, Bribe, Threat, Creed, Fame required, Reputation required, texts...'),
 T('NPC names.txt', 'Male and female names of random NPCs.', 'Male, Female'),
 T('NPCDist.txt', 'Per map: the chance (weight) of every profession among the street NPCs.', '# Map Id, -, Smith, Armorer, ...'),
 T('News topics - area.txt, News topics - continent.txt, News topics - profession.txt', 'What street NPCs talk about: by area (map), by continent, and by profession for every day of the week (topic and text ids).', 'Area / Continent / #, Profession name, Monday topic, Monday text ...'),
]},
{'file': r'Scripts\General\NPCTeacherAutonotes.lua, RemoveNPCTablesLimits.lua', 'kind': 'tables', 'items': [
 T('Teacher topics.txt', 'Teaching topics: skill, mastery, text, gold and skill level needed. Read into ' + L('Game.TeacherTopics') + '.', 'TopicId, Notes, SkillId, Mastery, TextId, Req. Gold, Req. Skill'),
 T('Teacher autonotes.txt', 'The autonote written for a teacher NPC who teaches a topic (pairs of NPC and autonote).', 'Topic Id, Notes, NPC Id, Autonote Id, NPC, A ...'),
]},
{'file': r'Scripts\General\Reputation.lua', 'kind': 'tables', 'items': [
 T('Reputation.txt', 'Per world, continent and map: the limits, the daily fading (' + C('DecMult, DecFlat, DecMin') + ', second stage ' + C('Dec2...') + ', fading limits), the donation limits and the gains passed between scopes. See the reputation functions of ' + L('Merge.Functions.ReputationAdd', 'Reputation.lua') + '.', '# World, Note, WorldLimUp, WorldLimBot, WorldDecMult, ...'),
]},
{'file': r'Scripts\General\1_TownPortalSwitch.lua, 2_OutdoorTravels.lua', 'kind': 'tables', 'items': [
 T('TownPortalSwitch.txt', 'Town Portal destinations of every continent: map, position, direction, icon and its place, the quest bit that opens it and the description. A row starting with ' + C('@') + ' names the screen picture and the first quest bit.', '#, Map, X, Y, Z, Direction, LookAngle, IconName, Icon X, Icon Y, IconWidth, IconHeight, QBitIndex, Description'),
 T('Outdoor travels.txt', 'Walking off the edge of an outdoor map: for each side the map reached, the side you arrive on and the days it takes; ' + C('StraightTravel') + '. Read into ' + L('Game.OutdoorTravels') + '.', 'Key map, Up, Side, Days, Down, Side, Days, Left, Side, Days, Right, Side, Days, StraightTravel, Notes'),
]},
{'file': r'Scripts\Structs\10_MergeSettings.lua', 'kind': 'tables', 'items': [
 T('ModSettings.txt', 'Mod settings as name / value pairs (directory, initial skill points and so on), read into ' + C('Merge.ModSettings') + '.', 'Name, Revamp'),
]},
{'file': r'Scripts\Structs\After\HWWater.lua', 'kind': 'tables', 'items': [
 T('HW water textures.txt', 'Software water texture and the hardware animated water textures that replace it.', 'SW texture, HW texture prefix'),
]},
]
