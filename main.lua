local debug = true
local isYagdActive = tes3.isModActive('Yet Another Guard Diversity - Regular.ESP')

function tableLength(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

function getSpawnCount()
  if not tes3.player then
    return '(load the game first)'
  end

  if not tes3.player.data.noRespawns then
    return '0'
  end

  return tableLength(tes3.player.data.noRespawns)
end

-- CONFIG
local configPath = 'No Respawns'
local config = mwse.loadConfig(configPath, {
    -- default config
    enabled = true,
    removePermanently = false,
    trackExteriors = true,
    trackGuards = true,
    spawnHighLvl = false,
    spawnChance = 1,
    spawnChanceHighLvlOnly = true
  })
local function registerModConfig()
  local template = mwse.mcm.createTemplate({ name = 'No Respawns' })

  template:saveOnClose(configPath, config)

  local settings = template:createPage({ label = 'Settings' })

  settings:createYesNoButton({
    label = 'Enable Mod',
    variable = mwse.mcm:createTableVariable({ id = 'enabled', table = config }),
  })

  settings:createYesNoButton({
    label = [[Remove spawns permanently (WARNING: spawns will remain deleted in this playthrough, even after disabling mod)]],
    variable = mwse.mcm:createTableVariable({ id = 'removePermanently', table = config }),
  })

  settings:createInfo({
    text = [[Is Yet Another Guard Diversity mod active? ]] .. (isYagdActive and 'yes' or 'no'),
  })

  if not isYagdActive then
    settings:createInfo({
      text = [[Install Yet Another Guard Diversity mod to start tracking killed guards.]],
    })
  end

  local spawnCountLabel = [[Total amount of tracked spawns ]] .. (isYagdActive and '(includes only killed guards)' or '(guards not counted)')
  settings:createInfo({
    text = spawnCountLabel .. ': ' .. getSpawnCount(),
    postCreate = function(self)
      self.elements.info.text = spawnCountLabel .. ': ' .. getSpawnCount()
    end
  })

  settings:createYesNoButton({
    label = [[Track exteriors]],
    variable = mwse.mcm:createTableVariable({ id = 'trackExteriors', table = config }),
  })

  if isYagdActive then
    settings:createYesNoButton({
      label = [[Track guards (everywhere)]],
      variable = mwse.mcm:createTableVariable({ id = 'trackGuards', table = config }),
    })
  end

  settings:createYesNoButton({
    label = [[Spawn high lvl creatures (ignore level list requirements)]],
    variable = mwse.mcm:createTableVariable({ id = 'spawnHighLvl', table = config }),
  })

  settings:createDecimalSlider({
    label = [[Spawn chance (determines random chance of all spawns to happen, 1 = default/always, 0 = never)]],
    min = 0,
    max = 1,
    step = 0.01,
    jump = 0.1,
    decimalPlaces = 2,
    variable = mwse.mcm.createTableVariable({ id = "spawnChance", table = config }),
  })

  settings:createYesNoButton({
    label = [[Apply random spawn chance only to high lvl creatures]],
    variable = mwse.mcm:createTableVariable({ id = 'spawnChanceHighLvlOnly', table = config }),
  })

  template:register()
end
event.register(tes3.event.modConfigReady, registerModConfig)

--- @param e leveledCreaturePickedEventData
local function onCreatureSpawn(e)
	-- We do it even if e.pick is nil (if no creature spawned, due to lvl requirement or chanceForNothing)
  -- this intentionally prevents new spawns when revisiting cells after time, with higher lvl

  if (not config.enabled) then
    return
  end

  if (e.cell.isOrBehavesAsExterior and not config.trackExteriors and not string.find(e.list.id, 'guard')) then
    if debug then
      mwse.log('[No Respawns] exterior cell detected while trackExteriors is disabled, do not track')
    end
    return
  end

  local isHighLvlSpawn = e.list.list[1].levelRequired > tes3.player.object.level

  if config.spawnHighLvl and isHighLvlSpawn then
  	if debug then
  		mwse.log('[No Respawns] is high lvl spawn, spawn %s', e.list.list[1].object)
  	end
  	e.pick = e.list.list[1].object
  end

  if (not tes3.player.data.noRespawns) then
    tes3.player.data.noRespawns = {}
    mwse.log('[No Respawns] created tes3.player.data.noRespawns for the first time')
  end

  -- We only care about leveled creatures that come from a placed leveled creature reference.
  if (e.source ~= 'reference') then
    return
  end

  local spawnIndex = e.cell.id .. '_' .. tostring(e.spawner.position)

  if debug then
    mwse.log('[No Respawns] ')
    mwse.log('[No Respawns] cell id: %s', e.cell.id)
    mwse.log('[No Respawns] e.spawner.position: %s', e.spawner.position)
    mwse.log('[No Respawns] list: %s', e.list)
    mwse.log('[No Respawns] required level: %s', e.list.list[1].levelRequired)
    mwse.log('[No Respawns] picked creature: %s', e.pick)
    mwse.log('[No Respawns] has spawned before (tes3.player.data.noRespawns[spawnIndex])? %s', tes3.player.data.noRespawns[spawnIndex])
  end

  if (tes3.player.data.noRespawns[spawnIndex]) then
    -- PREVENT RESPAWN
    return false
  end

  -- In Yet Another Guard Diversity mod guards are respawned from a leveled list,
  -- but are not stored in the save file. They are always recreated on game load, 
  -- which makes it hard to track if they were killed or not.
  -- Adding them to the list on spawn event would make them never spawn again
  -- (even if we haven't killed them!).
  -- We can prevent it here and add them to noRespawns table on death event instead.
  if (isYagdActive and string.find(e.list.id, 'guard')) then
    if debug then
      mwse.log('[No Respawns] guard detected, do NOT add to noRespawns list')
    end
    return
  end

  -- SPAWN CHANCE (optional)
  -- especially fun with spawnHighLvl option, as it will make spawns unpredictable and diverse in difficulty
  if ((config.spawnChance < 1)) then
  	if (config.spawnChanceHighLvlOnly and not isHighLvlSpawn) then
  		-- required level of the leveled list must be higher than player's level to randomly prevent spawn
  		return
  	end

    if (math.random(1, 100) > (config.spawnChance * 100)) then
      -- i.e. rolled 80 when spawn chance is 70% means spawn is prevented
      -- 0% spawn chance prevents all spawns
      if debug then
    		mwse.log('[No Respawns] spawnChance prevented spawn')
  		end

			timer.start({ duration = math.random(0.44, 0.55), callback = function()
      	-- TODO: delayed jump scare spawn?
			end})

      return false
    end
  end

  if config.removePermanently then
  	-- more nuclear solution:
  	-- removes spawn permanently to spare CPU and save file size 
  	-- (will even prevent triggering this whole event on next re-visit)
		timer.start({ duration = 1, callback = function()
			e.spawner:delete()
		end})
	else
		-- track spawn
  	tes3.player.data.noRespawns[spawnIndex] = true
	end
end
event.register(tes3.event.leveledCreaturePicked, onCreatureSpawn)


-- Yet Another Guard Diversity patch
local function deathCallback(e)
  if (not config.enabled) then
    return
  end

  if (not config.trackGuards) then
    if debug then
      mwse.log('[No Respawns] trackGuards option disabled, do not track')
    end
    return
  end

  if (not isYagdActive or not string.find(e.reference.id, 'guard') or not e.reference.isLeveledSpawn) then
    return
  end

  local spawnIndex = e.reference.cell.id .. '_' .. tostring(e.reference.leveledBaseReference.position)
  tes3.player.data.noRespawns[spawnIndex] = true
end
event.register(tes3.event.death, deathCallback)
