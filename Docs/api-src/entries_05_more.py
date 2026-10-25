P = lambda n: '<b class="def-param">%s</b>' % n
C = lambda s: '<span class="def-code">%s</span>' % s
H = lambda a, t=None: '<a href="MMExtension.htm#%s">%s</a>' % (a, t or a.split('.')[-1])

GROUPS = [
{'file': r'Scripts\Core\events.lua', 'kind': 'events', 'items': [
 dict(name='GetItemByRightClick', args=['Item'], links={'Item': 'structs.Item'},
      desc='Called after the game has drawn the information card of an item (right click on it). ' + P('Item') + ' is the item. Added by the merge to the core events.'),
]},
{'file': r'Scripts\Maps\hive.lua', 'kind': 'events', 'items': [
 dict(name='MM6Ending', args=['Type', 'Handled'],
      desc='Called before the MM6 ending is shown. ' + P('Type') + ' is "Good" or "Bad". Set ' + P('Handled') + ' to skip the standard movie and the return to the main menu.'),
 dict(name='MM6ReactorKilled', args=['HaveScroll'],
      desc='Called when the Hive reactor is destroyed. ' + P('HaveScroll') + ' says whether a party member carries item 2164; when true, mapvars.ReactorKilled is set and the next step of the good ending starts. Change it to choose.'),
]},
{'file': r'Scripts\Structs\25_MergeFunctions.lua', 'kind': 'events', 'items': [
 dict(name='ConditionApplicablePlayer', args=['PlayerPtr', 'Condition', 'Result'],
      desc='Called when the game checks whether a condition can be given to a character (when it picks a target for a condition). ' + P('PlayerPtr') + ' points to the character, ' + P('Condition') + ' is from ' + H('const.Condition', 'const.Condition') + '. ' + P('Result') + ': above 0 applicable, below 0 not, 0 lets the default check decide (Dead, Stoned and Eradicated characters can\'t get lesser conditions).'),
]},
{'file': r'Scripts\Structs\After\RemoveSpritesToDrawLimit.lua', 'kind': 'functions', 'items': [
 dict(name='SetSpritesToDrawLimit', args='NewCount', glob=True, desc='Raises the number of sprites the game can draw at once (never lowers it).'),
]},
{'file': r'Scripts\Structs\After\HWWater.lua', 'kind': 'functions', 'items': [
 dict(name='LoadHWWater', args='', glob=True, desc='Reads ' + '<a href="#tables.HW_water_textures.txt">HW water textures.txt</a>' + ' and sets up the animated hardware water textures; false if the table is missing.'),
]},
]
for g in GROUPS:
    for it in g['items']:
        if it.pop('glob', None): it['global'] = True
