
-- Enter Throne Room

Game.MapEvtLines:RemoveEvent(5)
evt.Hint[5] = evt.str[20]
evt.Map[5] = function()
	if Party.QBits[611] or not Party.QBits[612]
		or Party.EnemyDetectorYellow
		or Party.EnemyDetectorRed then

		Game.ShowStatusText(evt.str[21])
	elseif Party.QBits[710] then
		evt.EnterHouse{221}
	else
		evt.EnterHouse{219}
	end
end

function events.LoadMap()
	if vars.Quest_CrossContinents and Party.QBits[633] then
		vars.Quest_CrossContinents.ContinentFinished[2] = true
	end
end

function events.AfterLoadMap()
	-- music after QBit 630: MMMWE_Music.lua (Music.QuestMusic)
	-- after the Dark ending, the Forge garrison (Blaster Guys and Droids on the party's side):
	-- MMMWE_ForgeGarrison.lua
end
