-- Lib Hooks and Functions

local LIB_IDENTIFIER, LIB_VERSION = "LibHaF", 01

if _G[LIB_IDENTIFIER] and _G[LIB_IDENTIFIER].version > LIB_VERSION then
	return
end

local lib = {}
lib.name = LIB_IDENTIFIER
lib.version = LIB_VERSION
_G[LIB_IDENTIFIER] = lib

--[[
	ftSt = formatString -- '%s'
	
logger:SetEnabled(true)
/script libGlobals:debugFrmt('string 1 = %s, string 2 = %s, bool = %s', 'foo', 'bar', true)
/script libGlobals:Debug('string 1 = %s, string 2 = %s, bool = %s', 'foo', 'bar', true)
/script libGlobals:Debug('TEST')
/script libGlobals:Info('TEST')
/script libGlobals.logger:SetEnabled(true)
/script libGlobals.logger:SetLogTracesOverride(true)
/script libGlobals.logger:SetMinLevelOverride(LibDebugLogger.LOG_LEVEL_DEBUG)
	dbug('string 1 = %s, string 2 = %s, bool = %s', 'foo', 'bar', true)
	'string 1 = foo, string 2 = bar, bool = true'
	
	dbug('', )
]]

local debugOverride = true
local logLevel = debugOverride and LibDebugLogger.LOG_LEVEL_DEBUG or LibDebugLogger.LOG_LEVEL_INFO

local g_append = false
local function stfmt(ftSt, ...)
    ftSt = ftSt:gsub(', $', '')
	local g_strArgs = {}
	for i = 1, select("#", ...) do
		local currentArg = select(i, ...)
		if type(currentArg) == 'userdata' then 
			currentArg = currentArg.GetName and currentArg:GetName() or currentArg
		end
		g_strArgs[i] = tostring(currentArg)
	end

	if #g_strArgs == 0 then
		return tostring(ftSt)
	else
		return string.format(ftSt, unpack(g_strArgs))
	end
end

local function fmt(formatString, ...)
--	if not lib.enableDebug then return end
    
    if g_append then
        formatString = formatString .. ' [table] %s'
    end
	
	if type(formatString) == 'table' then
		g_append = true
		local tbl, fmtStr = {}, ''
		
		for k, v in pairs(formatString) do
			fmtStr = fmtStr .. k .. ' = %s, '
			table.insert(tbl, v)
		end
		return stfmt(fmtStr, unpack(tbl))
    elseif type(formatString) == 'number' then
		formatString = tostring(formatString)
    else
        g_append = false
	end
	
    return (stfmt(formatString, ...))
end

local logFunctions = {}
if LibDebugLogger then
	lib.logger = LibDebugLogger(LIB_IDENTIFIER)
	local logFunctionNames = {"Verbose", "Debug", "Info", "Warn", "Error"}
	for _, logFunctionName in pairs(logFunctionNames) do
		logFunctions[logFunctionName] = function(self, ...) return self.logger[logFunctionName](self.logger, fmt(...)) end
		lib[logFunctionName] = logFunctions[logFunctionName]
	end
	lib.logger:SetMinLevelOverride(logLevel)
else
	local logFunctionNames = {"Verbose", "Debug", "Info", "Warn", "Error"}
	for _, logFunctionName in pairs(logFunctionNames) do
		logFunctions[logFunctionName] = function(...) end
		lib[logFunctionName] = logFunctions[logFunctionName]
	end
end

local function createLogger(name, moduleTable)
	if lib.logger then
		moduleTable.logger = lib.logger:Create(name)
		moduleTable.logger:SetMinLevelOverride(logLevel)
	end
	for logFunctionName, logFunction in pairs(logFunctions) do
		moduleTable[logFunctionName] = logFunction
	end
end


--lib.debugFrmt = dbug
---------------------------------------------------------------------------------------------------------------
-- HookManager adds the ability to "register" and "unregister" PreHooks and PostHooks
---------------------------------------------------------------------------------------------------------------
--[[
	
	The hookId is used to identify the hook in the debug
		hookId = objectTable[existingFunctionName] as string 'FISHING_MANAGER[StartInteraction]'
	
	
	All original functions, posthooks, prehooks, hookIds are appended to the objectTable to be used later.
	
	objectTable[existingFunctionName .. '_Original'] = originalFunciton
	objectTable[existingFunctionName .. '_PrehookFunctions'] = {[name_given_at_register] = hookFunciton}
	objectTable[existingFunctionName .. '_PosthookFunctions'] = {[name_given_at_register] = hookFunciton}
	
	FISHING_MANAGER.StartInteraction_Original = originalFunciton
	FISHING_MANAGER.StartInteraction_PrehookFunctions = {[name_given_at_register] = hookFunciton}
	FISHING_MANAGER.StartInteraction_PosthookFunctions = {[name_given_at_register] = hookFunciton}
	
	FISHING_MANAGER.registeredHooks = {[StartInteraction] = 'FISHING_MANAGER[StartInteraction]'}
	
	
	RETICLE.OnUpdate_Original = originalFunciton
	RETICLE.OnUpdate_PrehookFunctions = {[name_given_at_register] = hookFunciton}
	RETICLE.OnUpdate_PosthookFunctions = {[name_given_at_register] = hookFunciton}
	
	RETICLE.TryHandlingInteraction_Original = originalFunciton
	RETICLE.TryHandlingInteraction_PrehookFunctions = {[name_given_at_register] = hookFunciton}
	RETICLE.TryHandlingInteraction_PosthookFunctions = {[name_given_at_register] = hookFunciton}
	RETICLE.TryHandlingInteraction = modifiedHookFunction
	
	
	RETICLE.registeredHooks = {
		[OnUpdate] = 'RETICLE[OnUpdate]',
		[TryHandlingInteraction] = 'FISHING_MANAGER[TryHandlingInteraction]',
	}
	
	hookIds are appended as objectTable[registeredHooks] {[existingFunctionName] = hookId}
]]


local HookManager = {}
createLogger('HookManager', HookManager)

local registerdHooks = {}
local function getObjectName(object)
	local objectId = tostring(object)
	if type(object) ~= 'table' then return '_Not_A_Object_' end
	if objectId == tostring(_G) then
		return '_G'
	end
	
	for key, value in zo_insecurePairs(_G) do
	    if type(value) == 'table' then
    		if tostring(value) == objectId then
    			return key
    		end
		end
	end
	return '_Not_Found_'
end

local function getOrCreateHookId(objectTable, existingFunctionName)
	local registeredHooks = objectTable['registeredHooks'] or {}

	local hookId = registeredHooks[existingFunctionName]
	if hookId == nil then
		hookId = string.format('%s[%s]', getObjectName(objectTable), existingFunctionName)
		
		registeredHooks[existingFunctionName] = hookId
		objectTable['registeredHooks'] = registeredHooks
	end
	
	return hookId
end

local function updateParameters(objectTable, existingFunctionName, hookFunction)
	if type(objectTable) == "string" then
		hookFunction = existingFunctionName
		existingFunctionName = objectTable
		objectTable = _G
	end
	
	local hookId = getOrCreateHookId(objectTable, existingFunctionName)
	return objectTable, existingFunctionName, hookFunction, hookId
end

local function getHookTablesAndId(objectTable, existingFunctionName)
	return objectTable[existingFunctionName .. '_Original'], objectTable[existingFunctionName .. '_PrehookFunctions' ], objectTable[existingFunctionName .. '_PosthookFunctions' ], objectTable['registeredHooks'][existingFunctionName]
end

local function resetToOriginal(originalFn, objectTable, existingFunctionName)
	HookManager:Info('local function resetToOriginal: reset %s', objectTable['registeredHooks'][existingFunctionName])

	objectTable[existingFunctionName] = originalFn
	objectTable[existingFunctionName .. '_Original'] = nil
	objectTable['registeredHooks'][existingFunctionName] = nil
	
	if NonContiguousCount(objectTable['registeredHooks']) == 0 then
		objectTable['registeredHooks'] = nil
	end
end

local function getHookPocessingFunctions(prehookFunctions, posthookFunctions)
	local preHooks, posthooks
	if prehookFunctions then
		preHooks = function(...)
			local bypass = false
			for name, hookFunction in pairs(prehookFunctions) do
				local returns = hookFunction(...)
				HookManager:Debug('Run PreHooks: name = %s, Returns = %s', name, returns) 
				if returns then
					bypass = true
				end
			end
			
			HookManager:Debug('Bypass Original = %s', bypass)
			return bypass
		end
	else
		preHooks = function(...) 
			HookManager:Debug('No Prehooks, Bypass Original = %s', false)
			return false
		end
	end
	
	if posthookFunctions then
		posthooks = function(...)
			for name, hookFunction in pairs(posthookFunctions) do
				local returns = hookFunction(...)
				HookManager:Debug('Run PostHooks: name = %s, Returns = %s', name, returns) 
			end
		end
	else
		posthooks = function(...) end
	end
	
	return preHooks, posthooks
end

local function getModifiedHookFunction(originalFn, prehookFunctions, posthookFunctions, hookId)

	return function(...)
	--	local hookId = objectTable['registeredHooks'][existingFunctionName]
		HookManager:Debug('Run Hooks: %s', hookId) 
		
		local runPrehooks, runPosthooks = getHookPocessingFunctions(prehookFunctions, posthookFunctions)
		
		if runPrehooks(...) then
			runPosthooks(...)
			return true
		else
			local returns = {originalFn(...)}
			HookManager:Debug('Run originalFn', fmt(returns))
			runPosthooks(...)
			return unpack(returns)
		end
	end
end

local function updateHooks(objectTable, existingFunctionName)
	HookManager:Info('local function updateHooks:')
	if not objectTable[existingFunctionName .. '_Original'] then
		objectTable[existingFunctionName .. '_Original'] = objectTable[existingFunctionName]
	end
	
	local originalFn, prehookFunctions, posthookFunctions, hookId = getHookTablesAndId(objectTable, existingFunctionName)
	HookManager:Info('updateHooks: %s', hookId)
	
	if not prehookFunctions and not posthookFunctions then
		HookManager:Info('updateHooks: %s', hookId)
		resetToOriginal(originalFn, objectTable, existingFunctionName)
		return
	end

	objectTable[existingFunctionName] = getModifiedHookFunction(originalFn, prehookFunctions, posthookFunctions, hookId)
	HookManager:Info('Update complete.')
end

local function registerHooks(name, objectTable, existingFunctionName, hookFunction, suffix, hookId)
	HookManager:Info('local function registerHooks: name = %s', name)
	local hookFunctions = objectTable[existingFunctionName .. suffix] or {}
	
	-- allow re-registering an already created hook without unregistering first
	HookManager:Info('registerHooks: name = %s, Has existing = %s', name, hookFunctions[name] ~= nil)
	hookFunctions[name] = hookFunction
	
	HookManager:Debug('%s%s = ', hookId:gsub(']$', '' ), suffix, fmt(hookFunctions))
	objectTable[existingFunctionName .. suffix] = hookFunctions
	
	updateHooks(objectTable, existingFunctionName)
end

local function unregisterHooks(name, objectTable, existingFunctionName, suffix, hookId)
	HookManager:Info('local function unregisterHooks: name = %s', name)
	local hookFunctions = objectTable[existingFunctionName .. suffix]
	
	if hookFunctions then
		HookManager:Debug('Start unregistering: %s, %s, #hooks = %s', hookId, suffix, NonContiguousCount(hookFunctions))
		if hookFunctions[name] then
			hookFunctions[name] = nil
			
			if NonContiguousCount(hookFunctions) == 0 then
				hookFunctions = nil
			end
			objectTable[existingFunctionName .. suffix] = hookFunctions
			
			updateHooks(objectTable, existingFunctionName)
		end
	end
	HookManager:Debug('End  unregistering: %s, %s, Has hooks = %s', hookId, suffix, (hookFunctions ~= nil))
end

function HookManager:RegisterForPreHook(name, objectTable, existingFunctionName, hookFunction)
	if not name then return end
	objectTable, existingFunctionName, hookFunction, hookId = updateParameters(objectTable, existingFunctionName, hookFunction)
	
	HookManager:Info('RegisterForPreHook: name = %s, %s', name, hookId)
	registerHooks(name, objectTable, existingFunctionName, hookFunction, '_PrehookFunctions', hookId)
end

function HookManager:UnregisterForPreHook(name, objectTable, existingFunctionName)
	if not name then return end
	objectTable, existingFunctionName, hookFunction, hookId = updateParameters(objectTable, existingFunctionName, hookFunction)
	
	HookManager:Info('UnregisterForPreHook: name = %s, %s', name, hookId)
	unregisterHooks(name, objectTable, existingFunctionName, '_PrehookFunctions', hookId)
end

function HookManager:RegisterForPostHook(name, objectTable, existingFunctionName, hookFunction)
	if not name then return end
	objectTable, existingFunctionName, hookFunction, hookId = updateParameters(objectTable, existingFunctionName, hookFunction)
	
	HookManager:Info('RegisterForPostHook: name = %s, %s', name, hookId)
	registerHooks(name, objectTable, existingFunctionName, hookFunction, '_PosthookFunctions', hookId)
end

function HookManager:UnregisterForPostHook(name, objectTable, existingFunctionName)
	if not name then return end
	objectTable, existingFunctionName, hookFunction, hookId = updateParameters(objectTable, existingFunctionName, hookFunction)
	
	HookManager:Info('UnregisterForPostHook: name = %s, %s', name, hookId)
	unregisterHooks(name, objectTable, existingFunctionName, '_PosthookFunctions', hookId)
end

JO_HOOK_MANAGER = HookManager

--[[
add status returns for  un/registering
/script HOOK_MANAGER:RegisterForPreHook('_HookTest2', 'ZO_CraftingUtils_GetMultipleItemsTextureFromSmithingDeconstructionType', function(self) end)

/script d(tostring(SMITHING_GAMEPAD.refinementPanel.inventory.owner))
/script d(tostring(SMITHING_GAMEPAD))

HOOK_MANAGER:RegisterForPreHook(addon.name .. '_HookTest', 'SomeFunction', function(self)
	return doThis()
end)
HOOK_MANAGER:UnregisterForPreHook(addon.name .. '_HookTest', 'SomeFunction')

HOOK_MANAGER:RegisterForPostHook(addon.name .. '_HookTest', SomeObject, 'SomeFunction', function(self)
	return doThat()
end)
HOOK_MANAGER:UnregisterForPostHook(addon.name .. '_HookTest', SomeObject, 'SomeFunction')
]]
---------------------------------------------------------------------------------------------------------------
-- ZO_FilteredNumericallyIndexedTableIterator
---------------------------------------------------------------------------------------------------------------
--[[
function ZO_FilteredNumericallyIndexedTableIterator(tbl, filterFunctions)
	local numFilters = filterFunctions and #filterFunctions or 0
	if numFilters > 0 then
		local nextKey, nextData = next(tbl)
		return function()
			while nextKey do
				local currentKey, currentData = nextKey, nextData
				nextKey, nextData = next(tbl, nextKey)

				local passesFilter = true
				for filterIndex = 1, numFilters do
					if not filterFunctions[filterIndex](currentData) then
						passesFilter = false
						break
					end
				end

				if passesFilter then
					return currentKey, currentData
				end
			end
		end
	else
		return pairs(tbl)
	end
end
]]

do
    -- this version will iterate any number index, including decimals and below 1. (example[-∞] to example[∞])
	-- including tables where indices are not consecutive. 1,2,4,7
	-- if there are non numeric indexes in table, they will be skipped without preventing table iterations.
	local function getIndexList(t)
		local indexList = {}
		for k,v in pairs(t) do
			table.insert(indexList, k)
		end
		table.sort(indexList, function(a, b) return a < b end)
		return indexList
	end
	function ZO_FilteredNumericallyIndexedTableIterator(tbl, filterFunctions)
		local indexList = getIndexList(tbl)
		local numFilters = filterFunctions and #filterFunctions or 0
		local index = 0
		local count = #indexList
		if numFilters > 0  then
			return function()
				index = index + 1
				while index <= count do
					local passesFilter = true
					local data = tbl[indexList[index]]
					if data ~= nil then
						for filterIndex = 1, numFilters do
							if not filterFunctions[filterIndex](data) then
								passesFilter = false
								break
							end
						end
						if passesFilter then
							return index, data
						else
							index = index + 1
						end
					else
						index = index + 1
					end
				end
			end
		else
			return function()
				index = index + 1
				while index <= count do
					local data = tbl[indexList[index]]
					if data ~= nil then
						return index, data
					else
						index = index + 1
					end
				end
			end
		end
	end
end

--[[
a modified version of ZO_FilteredNumericallyIndexedTableIterator that will iterate any numerically indexed table, including <1 and decimals.

EVENT_MANAGER:RegisterForEvent('libGlobals', EVENT_PLAYER_ACTIVATED,function()
		EVENT_MANAGER:UnregisterForEvent('libGlobals', EVENT_PLAYER_ACTIVATED)
	
    local function getIndexList(tbl)
        local indexList = {}
        for k,v in pairs(tbl) do
			if type(k) == 'number' then
         	   table.insert(indexList, k)
			end
        end
        table.sort(indexList, function(a, b) return a < b end)
        return indexList
    end
/script d(ZO_SkillTypeData:GetSkillLineDataByIndex(1))
/script d(ZO_SkillTypeData:GetSkillLineDataByIndex(9))
/script d(ZO_SkillTypeData.orderedSkillLines)


function SKILLS_DATA_MANAGER:SkillTypeIterator(skillTypeFilterFunctions)
    -- This only works because we use the skillTypeObjectPool like a numerically indexed table
    return ZO_FilteredNumericallyIndexedTable(self.skillTypeObjectPool:GetActiveObjects(), skillTypeFilterFunctions)
end

function ZO_SkillTypeData:SkillLineIterator(skillLineFilterFunctions)
    return ZO_FilteredNumericallyIndexedTable(self.orderedSkillLines, skillLineFilterFunctions)
end


/script testFilter = function(data) return (tonumber(data) >= 1) end
/script d(testFilter('3'))

/script for k, v in ZO_FilteredNumericallyIndexedTableIterator({[0.1] = '0.1', [2] = '2'}, {testFilter}) do d(k,v) end
/script for k, v in ZO_FilteredNumericallyIndexedTableIterator({[0.1] = '0.1', [2] = '2'}) do d(k,v) end

/script for k, v in ZO_FilteredNumericallyIndexedTable({[0.1] = '0.1', [2] = '2'}, {testFilter}) do d(k,v) end
/script for k, v in ZO_FilteredNumericallyIndexedTable({[0.1] = '0.1', [2] = '2'}) do d(k,v) end
]]


local onPlayerActivatedLogger = {}
createLogger('onPlayerActivated', onPlayerActivatedLogger)

local fishingActions = {
	[GetString(SI_GAMECAMERAACTIONTYPE16)] = true,
	[GetString(SI_GAMECAMERAACTIONTYPE17)] = true,
}

local function notFishingAction()
	local action, interactableName = GetGameCameraInteractableActionInfo()
	return not fishingActions[action]
end

local function onPlayerActivated()
	EVENT_MANAGER:UnregisterForEvent(lib.name, EVENT_PLAYER_ACTIVATED)
	
	onPlayerActivatedLogger:Info('onPlayerActivated')
	
	local lib_reticle = RETICLE
	local lib_fishing_manager = FISHING_MANAGER
	local lib_fishing_gamepad = FISHING_GAMEPAD
	local lib_fishing_keyboard = FISHING_KEYBOARD

	-- RETICLE:GetInteractPromptVisible and FISHING_MANAGER:StartInteraction are used to disable interactions.
	-- set RETICLE.interactionBlocked == true to disable
	function lib_reticle:GetInteractPromptVisible()
		-- disables interaction in gamepad mode and allows jumping
		if lib_reticle.interactionBlocked and notFishingAction() then
			return false
		end
		return not self.interact:IsHidden()
	end
	
	function lib_fishing_manager:StartInteraction()
	--	dbug('FISHING_MANAGER: RETICLE.interactionBlocked = %s', lib_reticle.interactionBlocked)
		if lib_reticle.interactionBlocked and notFishingAction() then
			-- disables interaction in keyboard mode
			-- returning true here will prevent GameCameraInteractStart() form firing
			return true
		end
		
		self.gamepad = IsInGamepadPreferredMode()
		if self.gamepad then
			return lib_fishing_gamepad:StartInteraction()
		else
			return lib_fishing_keyboard:StartInteraction()
		end
	end
--	/script d(RETICLE.interactionBlocked)
end

EVENT_MANAGER:RegisterForEvent(lib.name, EVENT_PLAYER_ACTIVATED, onPlayerActivated)
