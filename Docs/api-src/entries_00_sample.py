GROUPS = [
{'file': r'Scripts\General\ExtraEvents.lua', 'kind': 'events', 'items': [
 {'name': 'NewDay',
  'args': ['DayOfMonth', 'DayOfWeek', 'GameDay', 'GameYear', 'Month', 'NewMonth', 'NewWeek', 'NewYear',
           'PrevDayOfMonth', 'PrevGameDay', 'PrevMonth', 'PrevYear', 'Type', 'Week', 'Year'],
  'desc': 'Called once when the game date changes to a new day. <a href="#events.NewWeek">NewWeek</a>, '
   '<a href="#events.NewMonth">NewMonth</a> and <a href="#events.NewYear">NewYear</a> are called before it with the same table, '
   'and set <b class="def-param">NewWeek</b>, <b class="def-param">NewMonth</b>, <b class="def-param">NewYear</b> to <b class="def-param">true</b> when they happened, '
   'so a NewDay handler can tell what else changed.<br>'
   '<b class="def-param">DayOfMonth</b>, <b class="def-param">Month</b>, <b class="def-param">Week</b>, <b class="def-param">DayOfWeek</b> start from 0. '
   '<b class="def-param">Year</b> is the calendar year, <b class="def-param">GameYear</b> the years since the start of the game. '
   '<b class="def-param">GameDay</b> and <b class="def-param">PrevGameDay</b> count days since the start '
   '(<a href="#Merge.Functions.GetGameDay">GetGameDay</a>: 28 days a month, 12 months a year); the difference shows how many days passed at once. '
   '<b class="def-param">Prev*</b> are the date before the change.<br>'
   '<b class="def-param">Type</b>: 1 = the game clock, 2 = a jump in time (travel, rest, training and the like), '
   '3 = a jump while walking to another map: delayed until the new map is loaded, '
   '4 = a new game (called on the first map load with day 0).',
  'example': '''function events.NewDay(t)
	if t.NewWeek then
		Game.ShowStatusText("A new week begins")
	end
	local passed = t.GameDay - (t.PrevGameDay or t.GameDay)  -- several days at once after travel
end'''},
 {'name': 'NewWeek', 'args': ['(same as NewDay)'],
  'desc': 'Called before <a href="#events.NewDay">NewDay</a> when a new week starts (every 7 days of the month; also with each new month). Same table as NewDay.'},
 {'name': 'NewMonth', 'args': ['(same as NewDay)'],
  'desc': 'Called before <a href="#events.NewWeek">NewWeek</a> when a new month starts (also with each new year). Same table as <a href="#events.NewDay">NewDay</a>.'},
 {'name': 'NewYear', 'args': ['(same as NewDay)'],
  'desc': 'Called first when a new year starts. Same table as <a href="#events.NewDay">NewDay</a>.'},
]},
{'file': r'Scripts\General\MMMWE_Economy.lua', 'kind': 'events', 'items': [
 {'name': 'CalcEconomyPrice',
  'args': ['Kind', 'Value', 'Mult', 'Result', 'Player', 'PlayerIndex', 'PlayerPtr', 'MerchantSkill',
           'NonItemCosts', 'CallOriginal', 'Condition', 'SeverityMul', 'Days'],
  'links': {'Player': 'structs.Player'},
  'desc': 'Called for every shop and temple price, after the Waffel Edition formula and the multipliers of '
   '<span class="def-code">Economy.Settings</span>; change <b class="def-param">Result</b> to set the price (it is clamped to <span class="def-code">Economy.Settings.MinPrice</span> afterwards).<br>'
   '<b class="def-param">Kind</b>: "Heal", "Sell", "Buy", "Identify", "Repair", the merchant-skill-free "BaseSell", "BaseBuy", "BaseIdentify", "BaseRepair" '
   '(shown by the merchant), or "DarkHeal" (the reanimation price of dark temples, ZombiePlayers.lua).<br>'
   '<b class="def-param">Value</b> is the item value (none for Heal and Identify), <b class="def-param">Mult</b> the shop\'s price multiplier (the base heal cost for Heal). '
   '<b class="def-param">Player</b>, <b class="def-param">MerchantSkill</b> are nil for the Base kinds. '
   '<b class="def-param">NonItemCosts</b>(cost) applies the game\'s merchant adjustment for identify and repair; '
   '<b class="def-param">CallOriginal</b>() returns the price of the untouched game function.<br>'
   'Heal also fills <b class="def-param">Condition</b> (main condition), <b class="def-param">SeverityMul</b> and <b class="def-param">Days</b>.',
  'example': '''-- temples heal for half the price
function events.CalcEconomyPrice(t)
	if t.Kind == "Heal" then t.Result = math.ceil(t.Result / 2) end
end'''},
]},
{'file': r'Scripts\General\MMMWE_Music.lua', 'kind': 'events', 'items': [
 {'name': 'ChooseMapTrack', 'args': ['Track', 'Pool', 'MapIndex', 'Night', 'Season', 'Reason'],
  'desc': 'Called whenever a map music track is chosen; set <b class="def-param">Track</b> to play another track (nil: the game\'s default).<br>'
   '<b class="def-param">Track</b> is already drawn at random from <b class="def-param">Pool</b>, the tracks collected for the map, the part of the day, the season and the matching rules '
   '(the previous track left out when there is a choice). <b class="def-param">Night</b> = true at night, <b class="def-param">Season</b> 0..3, '
   '<b class="def-param">Reason</b> = "map" (entering a map), "loop" (the music starts again) or "daynight" (day and night changed).'},
]},
{'file': r'Scripts\Structs\RemoveHouseRulesLimits.lua', 'kind': 'events', 'items': [
 {'name': 'ShopRefilled', 'args': 'Assortment',
  'desc': 'Called after a shop (weapons, armor, magic, alchemy) has refilled its stock; <b class="def-param">Assortment</b> is meant to be the shop\'s '
   '<a href="MMExtension.htm#structs.GameStructure">Game.ShopItems</a> entry, an array of 12 <a href="MMExtension.htm#structs.Item">items</a>.<br>'
   '<b>Caution:</b> the array passed is taken one place before the one the refill returns, and in testing (25.10.26) it was not the stock of the shop being refilled. '
   'MMMWE_Blasters.lua therefore notes the item numbers of all <span class="def-code">Game.ShopItems</span> before the refill and takes the list that changed. '
   'A shop shows only the places its refill filled; empty places of the 12 are not displayed.'},
]},
{'file': r'Scripts\General\MMMWE_Main.lua', 'kind': 'functions', 'items': [
 {'name': 'RegenGive', 'args': 'Player, hp, sp',
  'desc': 'Gives a character regeneration the Waffel Edition way: the amounts (fractions are fine) are paid out over the next 5 game minutes, a fifth every minute, '
   'and fractions add up. <b class="def-param">sp</b> is ignored for characters with a class resource (Rage, Resolve, Ki, Energy, Breath). '
   'Use it from a <span class="def-code">RegenTick</span> handler for anything that should regenerate like Meditation or the Regeneration skill.',
  'example': '''function events.RegenTick(Player)
	-- +0.4 Hit Points per 5 minutes for every character
	Merge.Functions.RegenGive(Player, 0.4, 0)
end'''},
]},
{'file': r'Scripts\General\MMMWE_Blasters.lua', 'kind': 'functions', 'items': [
 {'name': 'BlasterState', 'args': 'item',
  'desc': 'State of a blaster <a href="MMExtension.htm#structs.Item">item</a>: a table with <b class="def-param">Stack</b> (the installed upgrades in order, each {Spec, Fine}), '
   '<b class="def-param">Tiers</b> and <b class="def-param">Levels</b> (per spec 1 Emitter, 2 Capacitor, 3 Disruptor, 4 Power cell; a Fine tier adds 0.5 to the level), '
   '<b class="def-param">Count</b>, <b class="def-param">Work</b> (0..100) and <b class="def-param">Cell</b> (0..200, half percents).<br>'
   'Converts old blasters (tier &times; 1000 + progress in Charges) and never-used ones (random charge, maybe a random upgrade) in place. '
   'Change the table and write it back with <a href="#Merge.Functions.BlasterSave">BlasterSave</a>.',
  'example': '''local MF = Merge.Functions
local gun = MF.BlasterOf(Party[0])        -- blaster in the main hand, or nil
if gun then
	local st = MF.BlasterState(gun)
	st.Cell = 200                         -- full power cell
	MF.BlasterSave(gun, st)
end'''},
]},
{'file': r'Scripts\General\MMMWE_Shields.lua', 'kind': 'functions', 'items': [
 {'name': 'ShieldBlockPower', 'args': 'num, item, shS, shM',
  'desc': 'Block power (% of a hit stopped, at most <span class="def-code">PowerMax</span>) of shield item number <b class="def-param">num</b>: the base power + the shield\'s armor + its "of Defense" or Shielding bonus '
   '(when <b class="def-param">item</b>, a <a href="MMExtension.htm#structs.Item">structs.Item</a>, is given) + the Shield skill bonus for skill <b class="def-param">shS</b> at mastery <b class="def-param">shM</b> (both optional).'},
]},
]
