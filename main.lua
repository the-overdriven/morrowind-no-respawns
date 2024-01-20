local debug = false
local isYagdActive = tes3.isModActive('Yet Another Guard Diversity - Regular.ESP')

function tableLength(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

function getSpawnCount()
	if not tes3.player then
		return 'no data'
	end

	return tableLength(tes3.player.data.noRespawns)
end

-- CONFIG
local configPath = "No Respawns"
local config = mwse.loadConfig(configPath, {
		-- default config
    enabled = true
})
local function registerModConfig()
    local template = mwse.mcm.createTemplate({ name = "No Respawns" })

    template:saveOnClose(configPath, config)

    local settings = template:createPage({ label = "Settings" })

    settings:createYesNoButton({
        label = "Enable Mod",
        variable = mwse.mcm:createTableVariable({ id = "enabled", table = config }),
    })
    
		settings:createInfo({
			text = [[Is Yet Another Guard Diversity mod active? ]] .. (isYagdActive and 'yes' or 'no'),
		})

		if not isYagdActive then
		settings:createInfo({
			text = [[Install Yet Another Guard Diversity mod to start tracking killed guards.]],
		})
		end

    local spawnCountLabel = [[Total amount of registered spawns ]] .. (isYagdActive and '(only killed guards counted)' or '(guards not counted)')
    settings:createInfo({
			text = spawnCountLabel .. ': ' .. getSpawnCount(),
			postCreate = function(self)
				self.elements.info.text = spawnCountLabel .. ': ' .. getSpawnCount()
			end
		})

    template:register()
end
event.register(tes3.event.modConfigReady, registerModConfig)

--- @param e leveledCreaturePickedEventData
local function onCreatureSpawn(e)
	if (not config.enabled) then
		return
	end

	if (not tes3.player.data.noRespawns) then
		tes3.player.data.noRespawns = {}
		mwse.log('[No Respawns] created tes3.player.data.noRespawns for the first time')
	end

	-- We only care about leveled creatures that come from a placed leveled creature reference.
	if (e.source ~= "reference") then
		return
	end

	local spawnerData = e.spawner.data
	local spawnIndex = e.cell.id .. '_' .. tostring(e.spawner.position)

	if debug then
		mwse.log('[No Respawns] ')
		mwse.log('[No Respawns] cell id: %s', e.cell.id)
		mwse.log('[No Respawns] list: %s', e.list)
		mwse.log('[No Respawns] picked creature: %s', e.pick)
		mwse.log('[No Respawns] has spawned before (tes3.player.data.noRespawns[spawnIndex])? %s', tes3.player.data.noRespawns[spawnIndex])
		mwse.log('[No Respawns] e.spawner.position: %s', e.spawner.position)
	end

	if (tes3.player.data.noRespawns[spawnIndex]) then
		-- PREVENT SPAWN
		return false
	end

	-- In Yet Another Guard Diversity mod guards are respawned from a leveled list,
	-- but are not stored in the save file. They are always recreated on game load, 
	-- which makes it hard to track if they were killed or not.
	-- Adding them to the list on spawn would make them never spawn again.
	-- We can prevent it here and add them to noRespawns table on death event instead.
	if (isYagdActive and string.find(e.list.id, "guard")) then
		if debug then
			mwse.log('[No Respawns] guard detected, do NOT add to noRespawns list')
		end
		return
	end

	-- We set it even if e.pick is nil (if no creature spawned, due to lvl requirement or chanceForNothing)
	-- this intentionally prevents new spawns when revisiting cells after time, with higher lvl
	tes3.player.data.noRespawns[spawnIndex] = true
end
event.register(tes3.event.leveledCreaturePicked, onCreatureSpawn)


-- Yet Another Guard Diversity patch
local function deathCallback(e)
	if (not isYagdActive or not string.find(e.reference.id, "guard") or not e.reference.isLeveledSpawn) then
		return
	end

	local spawnIndex = e.reference.cell.id .. '_' .. tostring(e.reference.leveledBaseReference.position)
	tes3.player.data.noRespawns[spawnIndex] = true
end
event.register(tes3.event.death, deathCallback)
