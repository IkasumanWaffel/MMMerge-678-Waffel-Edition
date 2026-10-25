P = lambda n: '<b class="def-param">%s</b>' % n
C = lambda s: '<span class="def-code">%s</span>' % s
L = lambda a, t=None: '<a href="#%s">%s</a>' % (a, t or a.split('.')[-1])
H = lambda a, t=None: '<a href="MMExtension.htm#%s">%s</a>' % (a, t or a.split('.')[-1])
F = lambda n, a, d, ex=None: dict(name=n, args=a, desc=d, **({'example': ex} if ex else {}))
T = '<i>Table, not a function:</i> '

GROUPS = [
{'file': r'Scripts\General\MMMWE_ArmorEffects.lua', 'kind': 'functions',
 'about': 'Effects of the armor types (leather agile, chain resilient, plate bulwark). Pieces count by slot: body 50%, helm and boots 15%, gauntlets and belt 10%.', 'items': [
 F('ArmorEffectSettings', '', T + 'the numbers of the armor effects (LeatherDodgePerSkill, ChainShrugPerSM, PlateFlatMaster, PlateFlatGM, ...).'),
 F('ArmorDodgeMod', 'pl', 'Dodge chance change from armor, in % points: the leather bonus (Expert and up, per piece) and the Grand Master chain and plate body armor penalties.'),
 F('ChainShrugChance', 'pl', 'Chance (%) that chain armor shrugs off a monster\'s special attack: per skill &times; mastery &times; the chain share of the set.'),
 F('ChainShrugsOff', 'pl', 'Rolls ' + L('Merge.Functions.ChainShrugChance', 'ChainShrugChance') + '; on success shows "<i>name</i>\'s chain mail turns the blow aside" and returns true.'),
 F('PlateFlatReduction', 'pl', 'Damage taken off every physical hit by plate armor (Master: half the Plate skill, Grand Master: the full skill, times the plate share of the set).'),
 F('ArmorRecoveryMod', 'pl', 'Attack recovery change from the body armor\'s type (leather Master: faster, plate Grand Master: slower).'),
 F('ArmorEffectsInfo', 'pl', 'Console: a line with the armor effects of a character (default: the selected one).'),
]},
{'file': r'Scripts\General\MMMWE_ConcurrentEnchantments.lua', 'kind': 'functions',
 'about': 'Temporary weapon enchantments (Fire Aura, weapon potions) next to an item\'s own enchantment.', 'items': [
 F('HiddenSwift', 'pl, it', 'true if weapon ' + P('it') + ' carries a Swiftness or Darkness enchantment the game doesn\'t see while a temporary one is on it (for the attack recovery).'),
 F('IsEnchantDamageCall', 't', 'true if a ' + H('events.CalcDamageToMonster', 'CalcDamageToMonster') + ' call is the extra damage of a weapon enchantment (' + C('t.IsSecondary') + '), not the hit itself.'),
 F('GetTempEnchant', 'item', 'The temporary enchantment of an item (struct or pointer): name ("Infernos"), expiry time (' + C('Game.Time') + ' units) and its Bonus2; nil if it has none.'),
]},
{'file': r'Scripts\General\MMMWE_DamageDiag.lua', 'kind': 'functions', 'items': [
 F('DamageDiag', '', T + 'settings of the damage diagnostics log; ' + C('Enabled') + ' switches it (off by default, ENABLED at the top of the file).'),
 F('DamageDiagRes', '', T + 'the record of the last diagnosed hit.'),
]},
{'file': r'Scripts\General\MMMWE_DamageKinds.lua', 'kind': 'functions',
 'about': 'Slashing, piercing and blunt physical damage (Physical Damage Kinds.txt).', 'items': [
 F('PhysDamageKindOf', 'pl, melee', '"Slashing", "Piercing" or "Blunt": the kind of a character\'s melee hit (by the main-hand weapon; bare hands blunt) or ranged hit (piercing).'),
 F('PhysKindReduction', 'mon, kind', 'Damage reduction (%) of a map monster against a kind: its physical resistance plus its kind modifier, between -100 and the cap; nil if it has no modifiers.'),
 F('PhysDamageKindsCardLine', 'mon', 'The "Sla / Pie / Blu" lines of the monster card, or nil.'),
 F('IncomingPhysKind', '', 'Kind of the physical hit the party is taking right now (missiles piercing, monsters by their attack), or nil.'),
 F('ArmorKindFactor', 'pl, kind', 'Damage multiplier of a character\'s armor against a kind, all pieces weighted by slot.'),
 F('ArmorSlotWeights', '', T + 'the slot weights {slot field, weight}: body armor 0.50, helm 0.15, boots 0.15, gauntlets 0.10, belt 0.10.'),
 F('ArmorKindFactors', '', T + 'the multipliers of leather, chain and plate against each kind.'),
]},
{'file': r'Scripts\General\MMMWE_Drains.lua', 'kind': 'functions', 'items': [
 F('DrainMonsters', '', T + 'monster type &rarr; what it drains (e.g. vampires: {"Might", "Endurance"}).'),
 F('ClearDrains', 'pl', 'Removes all stat, armor and resistance drains of a character.'),
]},
{'file': r'Scripts\General\MMMWE_DroppedItems.lua', 'kind': 'functions', 'items': [
 F('DroppedItemsList', '', 'Console: prints the items the party dropped on the current map (they are restored when the map is loaded again) and returns their number.'),
]},
{'file': r'Scripts\General\MMMWE_EnchantScaling.lua', 'kind': 'functions', 'items': [
 F('ScaleEnchantDamage', 'pl, item, dmg, damageKind', 'Enchantment damage ' + P('dmg') + ' scaled the Waffel Edition way (by the character and the item), at least the minimum damage.'),
]},
{'file': r'Scripts\General\MMMWE_HardcoreSettings.lua', 'kind': 'functions', 'items': [
 F('HCMIsLocked', '', 'true if Hardcore Mode is locked for this party: once on, it stays on while the first character (Party[0]) is the one it was locked to.'),
]},
{'file': r'Scripts\General\MMMWE_InventorySort.lua', 'kind': 'functions', 'items': [
 F('SortInventory', 'pl', 'Sorts a character\'s backpack by item kind (satchels and bottle boxes in their places); true if a new layout was written.'),
 F('GatherPartyItems', '', 'Moves items to the character with the matching skill (potions and reagents to the best alchemist, unidentified items to the best identifier, broken ones to the best repairer), then sorts; returns moved, stuck and unsorted counts.'),
 F('TakeFromChest', 'mode', 'Takes items from the open chest: ' + P('mode') + ' "all", "gold" or "valued". Returns gold, items taken, items left; nil if no chest is open.'),
]},
{'file': r'Scripts\General\MMMWE_ItemDurability.lua', 'kind': 'functions',
 'about': 'Weapon and armor durability; wear is kept in ' + C('Item.MaxCharges') + '.', 'items': [
 F('GetDurabilityLabel', 'cur, max', 'The wear label of the item card for a durability ("(Worn)" and so on).'),
 F('DumpDurability', 'filter', 'Console: lists the durability of items (names matching ' + P('filter') + ').'),
 F('IsIndestructible', 'itemNumber', 'true for item kinds that never wear (relics).'),
 F('WearOnHit', 'pl, category, result, wDR, shDR, dodgeDR', 'Wears the armor, shield or parrying weapon of a character who was hit (called by the damage code of MMMWE_Main.lua with what blocked, parried or dodged).'),
 F('WearItem', 'it, amount, pl', 'Adds ' + P('amount') + ' wear to an item; it breaks when worn out.'),
 F('GetWeaponPenalty', 'it', 'Damage penalty (share, 0..1) of a worn weapon or bow.'),
 F('GetBaseDurability', 'itemNumber', 'Base durability of an item kind, with its rarity multiplier; 0 if it has none. MMMWE_Main.lua has stubs for these functions in case MMMWE_ItemDurability.lua is missing.'),
 F('GetItemWear', 'item', 'Wear points of an item (999 = broken).'),
 F('GetItemWearPtr', 'ptr', 'Wear of the item at a pointer.'),
]},
{'file': r'Scripts\General\MMMWE_PaperdollTuner.lua', 'kind': 'functions', 'items': [
 F('PaperdollTunerSave', '', 'Saves the item positions changed with the Paperdoll Tuner (Ctrl + arrows) into the data tables, as Ctrl + S does.'),
]},
{'file': r'Scripts\General\MMMWE_StatsTooltips.lua', 'kind': 'functions', 'items': [
 F('StatsTooltipAt', 'x, y', 'Which Stats page tooltip is at screen position ' + P('x') + ', ' + P('y') + ': the text and its stats.txt row, or the game\'s own entry; for checking the click fields.'),
]},
{'file': r'Scripts\General\MMMWE_Threat.lua', 'kind': 'functions', 'items': [
 F('PlayerThreat', 'pl', 'Threat factor of a character: armor pieces weighted by slot (heavier armor and higher armor mastery draw more attacks), the shield, and the Knight stance multiplier.'),
 F('PlayerThreatShare', 'i', 'Share (0..1) of the attacks party member ' + P('i') + ' draws from a monster with no preferences (the "Threat NN%" line).'),
]},
{'file': r'Scripts\General\MMMWE_WeaponEffects.lua', 'kind': 'functions', 'items': [
 F('UnarmedStunChance', 'pl', 'Chance (%) of a bare-handed hit to stun: Unarmed skill &times; 0.25 / 0.5 / 0.75 / 1% by mastery.'),
]},
]
