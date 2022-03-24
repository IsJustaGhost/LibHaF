-- Lib Hooks and Functions

--[[ TODO:
	Create a Constants section.

]]

--[[ About lib:
	Requirements of modified functions:
		the modified function must not change how it is used in the base game.
		the modified function must not cause conflicts with existing addons.
	
	Custom functions:
		use JO_ as prefix. Mainly for humor.

	Currently contains:
		HookManager
			adds the ability to "register" and "unregister" PreHooks and PostHooks and, Handler PreHooks and PostHooks. Allows all hooks to run.
		ZO_FilteredNumericallyIndexedTableIterator
			this version will iterate any number index, including decimals and below 1. (example[-∞] to example[∞])
		RETICLE:GetInteractPromptVisible() and FISHING_MANAGER:StartInteraction()
			used to disable interactions with RETICLE.interactionBlocked == true, unless target is 'Fish'.
]]

local LIB_IDENTIFIER, LIB_VERSION = "LibHaF", 01

if _G[LIB_IDENTIFIER] and _G[LIB_IDENTIFIER].version > LIB_VERSION then
	return
end

local lib = {}
lib.name = LIB_IDENTIFIER
lib.version = LIB_VERSION
_G[LIB_IDENTIFIER] = lib

---------------------------------------------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------------------------------------------


---------------------------------------------------------------------------------------------------------------
-- Debug
---------------------------------------------------------------------------------------------------------------
--[[ About debug:
	Debug input auto-formats numbers, strings, bools, userdata.
		usedata is returned as userdata:GetName() or "userdata"
		example:
			local fooBar = true
			lib:Info('foo %s, %s, control = %s', 'bar', fooBar, ZO_ProvisionerTopLevel)
			will format as string.format('foo %s, %s, control = %s', 'bar', tostring(fooBar), ZO_ProvisionerTopLevel:GetName() or 'userdata')
			will outut as 'foo bar, true, control = ZO_ProvisionerTopLevel'

	Tables can also be formated by using fmt(tbl) as input. It will auto-append ' [table] {%s}' to the format string.
		example:
			local tbl = {'foo'. 'bar'}
			lib:Info('foo %s', 'bar', fmt(tbl))
			will format as string.format('foo %s [table] = {%s}', 'bar', '1 = foo, 2 = bar')
			will output as 'foo bar [table] = {1 = foo, 2 = bar}'

	Adding new objects
		local newObject = {}
		createLogger('newObject', newObject)

		It will create a subLogger for the new object
		newObject:Verbose()
		newObject:Debug()
		newObject:Warn()
		newObject:Error()
]]

local debugOverride = true
local logLevel

local g_append = false
local function stfmt(ftSt, ...)
--	if not ftSt then return end
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
        formatString = formatString .. ' %s'
    end
	
	if type(formatString) == 'table' then
		g_append = true
		local tbl, fmtStr = {}, '[table] {'
		
		for k, v in pairs(formatString) do
			local keyformat = type(k) == 'string' and '["%s"]' or '[%s]'
			k = string.format(type(k) == 'string' and '["%s"]' or '[%s]', k)
			if type(v) == 'string' then
				fmtStr = fmtStr .. k .. ' = "%s", '
			else
				fmtStr = fmtStr .. k .. ' = %s, '
			end
			table.insert(tbl, v)
		end
		if #tbl > 0 then
			fmtStr = fmtStr:gsub(', $', '') .. '}'
			return stfmt(fmtStr, unpack(tbl))
		end
        g_append = false
		return 'nil'
    elseif type(formatString) == 'number' then
		formatString = tostring(formatString)
    else
        g_append = false
	end
	
    return (stfmt(formatString, ...))
end

local logFunctions = {}
local logFunctionNames = {"Verbose", "Debug", "Info", "Warn", "Error"}
if LibDebugLogger then
	logLevel = debugOverride and LibDebugLogger.LOG_LEVEL_DEBUG or LibDebugLogger.LOG_LEVEL_INFO
	lib.logger = LibDebugLogger(LIB_IDENTIFIER)
	for _, logFunctionName in pairs(logFunctionNames) do
		logFunctions[logFunctionName] = function(self, ...) return self.logger[logFunctionName](self.logger, fmt(...)) end
		lib[logFunctionName] = logFunctions[logFunctionName]
	end
	lib.logger:SetMinLevelOverride(logLevel)
else
	for _, logFunctionName in pairs(logFunctionNames) do
		logFunctions[logFunctionName] = function(...) end
		lib[logFunctionName] = logFunctions[logFunctionName]
	end
end
lib:Info('Initialize')

local function createLogger(name, moduleTable)
	if lib.logger then
		moduleTable.logger = lib.logger:Create(name)
		moduleTable.logger:SetMinLevelOverride(logLevel)
	end
	for logFunctionName, logFunction in pairs(logFunctions) do
		moduleTable[logFunctionName] = logFunction
	end
end

---------------------------------------------------------------------------------------------------------------
-- HookManager adds the ability to "register" and "unregister" Hooks.
---------------------------------------------------------------------------------------------------------------
--[[
	HOOK_MANAGER:RegisterFor*Hook(-string <register name>, -string <functionName>, -function <hookFunction>, -string <dependent> -nilable, -int <sortOrder> -nilable)
	HOOK_MANAGER:RegisterFor*Hook(-string <register name>, -table <object>, -string <functionName>, -function <hookFunction>, -string <dependent> -nilable, -int <sortOrder> -nilable)

	HOOK_MANAGER:RegisterFor*HookHandler(-string <register name>, -userData <control>, -string <handlerName>, -function <hookFunction>, -string <dependent> -nilable, -int <sortOrder> -nilable)

	EXAMPLE:
		JO_HOOK_MANAGER:RegisterForPreHook('AddonName', RETICLE, 'TryHandlingInteraction', function() d('') end)
		JO_HOOK_MANAGER:RegisterForPreHook('AddonName', RETICLE, 'TryHandlingInteraction', function() d('') end, 'LibHaF', CONTROL_HANDLER_ORDER_BEFORE)


	The hookId is used to identify the hook as a string. Mainly used for debug.
		hookId = objectTable[existingFunctionName] as string 'FISHING_MANAGER["StartInteraction"]'
	
	All original functions, posthooks, prehooks, hookIds are appended to the objectTable to be used later.
	
	objectTable[existingFunctionName .. '_Original'] = originalFunciton
	objectTable[existingFunctionName .. '_PrehookFunctions'] = {["name_given_at_register"] = hookFunciton}
	objectTable[existingFunctionName .. '_PosthookFunctions'] = {["name_given_at_register"] = hookFunciton}
	hookIds are appended as objectTable["registeredHooks"] {[existingFunctionName] = hookId}
	
	examples:
		RETICLE.OnUpdate_Original = originalFunciton
		RETICLE.OnUpdate_PrehookFunctions = {["name_given_at_register"] = hookFunciton}
		RETICLE.OnUpdate_PosthookFunctions = {["name_given_at_register"] = hookFunciton}
		RETICLE.OnUpdate = modifiedHookFunction
		
		RETICLE.TryHandlingInteraction_Original = originalFunciton
		RETICLE.TryHandlingInteraction_PrehookFunctions = {["name_given_at_register"] = hookFunciton}
		RETICLE.TryHandlingInteraction_PosthookFunctions = {["name_given_at_register"] = hookFunciton}
		RETICLE.TryHandlingInteraction = modifiedHookFunction
		
		RETICLE.registeredHooks = {
			[OnUpdate] = 'RETICLE["OnUpdate"]',
			[TryHandlingInteraction] = 'RETICLE["TryHandlingInteraction"]',
		}
	
	For functions that are nested the hookId will be '_Not_Found_[existingFunctionName]'
	There would need to be a traceback to figure out the full 'path' of the objectTable and I am not sure how to do this.
	Take 'SMITHING_GAMEPAD.deconstructionPanel.inventory' as an example.
	If a registered prehook returns true, then true is the only aregument returned,
	otherwise it wil return full arguments from originalFn.
]]

local HookManager = {}
createLogger('HookManager', HookManager)

local HOOK_TYPE_1 = 'Pre'
local HOOK_TYPE_2 = 'Post'

local zo_hooks = {
	['ZO_PreHook'] = ZO_PreHook,
	['ZO_PostHook'] = ZO_PostHook,
	['ZO_PreHookHandler'] = ZO_PreHookHandler,
	['ZO_PostHookHandler'] = ZO_PostHookHandler,
}

local function getObjectName(objectTable)
	local tableId = tostring(objectTable)
	if type(objectTable) ~= 'table' then return false end -- '_Not_A_Object_'
	if tableId == tostring(_G) then
		return '_G'
	end
	
	for key, value in zo_insecurePairs(_G) do
	    if type(value) == 'table' then
    		if tostring(value) == tableId then
    			return key
    		end
		end
	end

	return tostring(objectTable) -- '_Not_Found_'
end

local function getOrCreateHookId(objectTable, existingFunctionName)
	local registeredHooks = objectTable.registeredHooks or {}

	local hookId = registeredHooks[existingFunctionName]
	if hookId == nil then
		local objectName = ''
		if type(objectTable) == 'table' then
			objectName = getObjectName(objectTable) or ''
			hookId = string.format('%s["%s"]', objectName, existingFunctionName)
		else
			objectName = objectTable.GetName and objectTable:GetName() or tostring(objectTable)
			hookId = string.format('("%s")%s', existingFunctionName, objectName)
		end
		if objectName == '' then return false end
		
		registeredHooks[existingFunctionName] = hookId
		objectTable.registeredHooks = registeredHooks
	end
	
	return hookId
end

local function getUpdatedParameters(objectTable, existingFunctionName, hookFunction, dependent, sortOrder)
	if type(objectTable) == "string" then
		sortOrder = dependent
		dependent = hookFunction
		hookFunction = existingFunctionName
		existingFunctionName = objectTable
		objectTable = _G
	end
	
	sortOrder = sortOrder or 0
	
	local hookId = getOrCreateHookId(objectTable, existingFunctionName)
	return objectTable, existingFunctionName, hookFunction, hookId, dependent, sortOrder
end

local function getHookTable(objectTable, existingFunctionName, suffix)
	return objectTable[existingFunctionName .. suffix]
end

-- the functions that will cycle through the registered pre and post hooks
local function getCustomHookFunction(hookType, objectTable, existingFunctionName, hookId)
	local function dbug(hookId, ...)
		-- reduce logger spam
		if hookId:match('DebugLogViewer') or hookId:match('RETICLE') then return end
		HookManager:Debug(...)
	end

	if hookType == HOOK_TYPE_1 then
		return function(...)
			local hookTable = getHookTable(objectTable, existingFunctionName, '_PreHookFunctions')
			if hookTable == nil then return false end
			dbug(hookId, 'Run PreHooks for %s', hookId)
			
			local bypass = false
			for k, entry in ipairs(hookTable) do
				dbug(hookId, '-- Registered by %s', entry.name)
				if entry.hookFunction(...) then
					bypass = true
				end
			end
			
			return bypass
		end
	end
	
	return function(...)
		local hookTable = getHookTable(objectTable, existingFunctionName, '_PostHookFunctions')
		if hookTable == nil then return end
		dbug(hookId, 'Run PostHooks for %s', hookId)
				
		for k, entry in ipairs(hookTable) do
			dbug(hookId, '-- Registered by %s', registeredName)
			
			entry.hookFunction(...)
		end
	end
end

local function getExistingHook(hookTable, registeredName)
	for k, entry in pairs(hookTable) do
		if entry.name == registeredName then
			return k
		end
	end
end

local function getDependentIndex(hookTable, dependent, sortOrder)
	local index = getExistingHook(hookTable, dependent)
	
	if index then
		return (sortOrder == CONTROL_HANDLER_ORDER_BEFORE) and index or (index + 1)
	end
end

local count = 0
local function removeHook(hookTable, registeredName)
	local index = getExistingHook(hookTable, registeredName)
	
	if index then
		count = count - 1
		JO_HOOK_MANAGER.count = count
		
		HookManager:Info('-- Hook removed for: %s', registeredName)
		table.remove(hookTable, index)
	end
end

local function addHook(registeredName, hookFunction, hookTable, dependent, sortOrder)
	-- remove existing hook if exists
	removeHook(hookTable, registeredName)
	local pos = #hookTable + 1
	
	if pos > 1 and dependent and sortOrder > CONTROL_HANDLER_ORDER_NONE then
		pos = getDependentIndex(hookTable, dependent, sortOrder) or pos
	end
	
	local entry = {
		['name'] = registeredName,
		['hookFunction'] = hookFunction,
	}
	
	table.insert(hookTable, pos, entry)
	
	-- count is for debug purposes
	count = count + 1
	JO_HOOK_MANAGER.count = count
end

local function sharedUnregister(hookType, registeredName, objectTable, existingFunctionName, hookFunction, hookId)
	local suffix = '_' .. hookType .. 'HookFunctions'
	local hookTable = objectTable[existingFunctionName .. suffix]
	HookManager:Info('Unregister: %s registeredName = %s, %s', hookType, registeredName, hookId)
	
	if hookTable then
		HookManager:Debug('', fmt(hookTable))
		removeHook(hookTable, registeredName)
		
		if NonContiguousCount(hookTable) == 0 then
			hookTable = nil
		end
		objectTable[existingFunctionName .. suffix] = hookTable
	end
end

local function register_Hook(hookType, registeredName, objectTable, existingFunctionName, hookFunction, hookId, dependent, sortOrder)
	HookManager:Info('Register %sHook: registeredName = %s, %s', hookType, registeredName, hookId)
	local suffix = '_' .. hookType .. 'HookFunctions'
	
	local hookTable = objectTable[existingFunctionName .. suffix]
	if not hookTable then
		hookTable = {}
		local customHookFunction = getCustomHookFunction(hookType, objectTable, existingFunctionName, hookId)
		zo_hooks['ZO_' .. hookType .. 'Hook'](objectTable, existingFunctionName, customHookFunction)
	end

	addHook(registeredName, hookFunction, hookTable, dependent, sortOrder)
	objectTable[existingFunctionName .. suffix] = hookTable
end

local function register_Handler(hookType, registeredName, control, handlerName, hookFunction, dependent, sortOrder)
	local hookId = getOrCreateHookId(control, handlerName)
	HookManager:Info('Register %sHookHandler: registeredName = %s, %s', hookType, registeredName, hookId)
	local suffix = '_' .. hookType .. 'HookFunctions'
	
	local hookTable = control[handlerName .. suffix]
	if not hookTable then
		hookTable = {}
		local customHookFunction = getCustomHookFunction(hookType, control, handlerName, hookId)
		zo_hooks['ZO_' .. hookType .. 'HookHandler'](control, handlerName, customHookFunction)
	end

	addHook(registeredName, hookFunction, hookTable, dependent, sortOrder)
	control[handlerName .. suffix] = hookTable
end

-- where ... == objectTable, existingFunctionName, hookFunction, dependent, sortOrder
do -- Pre-hooks
	function HookManager:RegisterForPreHook(registeredName, ...)
		return register_Hook(HOOK_TYPE_1, registeredName, getUpdatedParameters(...))
	end

	function HookManager:UnregisterForPreHook(registeredName, ...)
		return sharedUnregister(HOOK_TYPE_1, registeredName, getUpdatedParameters(...))
	end

	function HookManager:RegisterForPreHookHandler(registeredName, control, handlerName, hookFunction, dependent, sortOrder)
		return register_Handler(HOOK_TYPE_1, registeredName, control, handlerName, hookFunction)
	end

	function HookManager:UnregisterForPreHookHandler(registeredName, control, handlerName)
		return sharedUnregister(HOOK_TYPE_1, registeredName, control, handlerName)
	end
end

do -- Post-hooks
	function HookManager:RegisterForPostHook(registeredName, ...)
		return register_Hook(HOOK_TYPE_2, registeredName, getUpdatedParameters(...))
	end

	function HookManager:UnregisterForPostHook(registeredName, ...)
		return sharedUnregister(HOOK_TYPE_2, registeredName, getUpdatedParameters(...))
	end

	function HookManager:RegisterForPostHookHandler(registeredName, objectTable, handlerName, hookFunction, dependent, sortOrder)
		return register_Handler(HOOK_TYPE_2, registeredName, objectTable, handlerName, hookFunction)
	end

	function HookManager:UnregisterForPostHookHandler(registeredName, control, handlerName)
		return sharedUnregister(HOOK_TYPE_2, registeredName, control, handlerName)
	end
end

do -- Backwards compatibility
	local lastIndex = {}
	local function getNextId(calledBy)
		local index = lastIndex[calledBy] or 0
		lastIndex[calledBy] = index + 1
		return (calledBy .. '_' .. lastIndex[calledBy])
	end
	
	ZO_PreHook = function(...)
		return register_Hook(HOOK_TYPE_1, getNextId('ZO_PreHook'), getUpdatedParameters(...))
	end
	ZO_PostHook = function(...)
		return register_Hook(HOOK_TYPE_2, getNextId('ZO_PostHook'), getUpdatedParameters(...))
	end
	
	ZO_PreHookHandler = function(...)
		return register_Handler(HOOK_TYPE_1, getNextId('ZO_PreHookHandler'), ...)
	end
	ZO_PostHookHandler = function(...)
		return register_Handler(HOOK_TYPE_2, getNextId('ZO_PostHookHandler'), ...)
	end
end

function HookManager:GetRegisteredHooks(objectTable, existingFunctionName)
	local registeredHooks
	
	for k, hookType in pairs({'Pre', 'Post'}) do
		local suffix = '_' .. hookType .. 'HookFunctions'
		local hookTable = objectTable[existingFunctionName .. suffix]
		
		if hookTable then
			registeredHooks = registeredHooks or {}
			registeredHooks[hookType .. 'Hooks'] = hookTable
		end
	end
	
	return registeredHooks
end
	
JO_HOOK_MANAGER = HookManager

--[[
	local registeredHooks = JO_HOOK_MANAGER:GetRegisteredHooks(RETICLE, 'TryHandlingInteraction').PreHooks
	if registeredHooks and hookFunctions[name] then
	
	
	
add status returns for  un/registering?
HOOK_MANAGER:RegisterForPreHook(self.name, RETICLE, 'OnUpdate', function(self)
	return doThis()
end, 'registeredName', CONTROL_HANDLER_ORDER_BEFORE)

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
	table.sort(tbl)
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
	local logger = {}
	createLogger('TableIterator', logger)
	
    -- this version will iterate any number index, including decimals and below 1. (example[-∞] to example[∞])
	-- including tables where indices are not consecutive. 1,2,4,7
	-- if there are non numeric indexes in table, they will be skipped without preventing table iterations. -- not currently true
	-- removed the type check due to causing errors
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
/script testFilter = function(data) return (tonumber(data) >= 1) end

/script for k, v in ZO_FilteredNumericallyIndexedTableIterator({[0.1] = '0.1', [2] = '2'}, {testFilter}) do d(k,v) end
/script for k, v in ZO_FilteredNumericallyIndexedTableIterator({[0.1] = '0.1', [2] = '2'}) do d(k,v) end

/script for k, v in ZO_FilteredNumericallyIndexedTable({[0.1] = '0.1', [2] = '2'}, {testFilter}) do d(k,v) end
/script for k, v in ZO_FilteredNumericallyIndexedTable({[0.1] = '0.1', [2] = '2'}) do d(k,v) end
]]


---------------------------------------------------------------------------------------------------------------
-- ZO_Object Enhancments
---------------------------------------------------------------------------------------------------------------
-- Allows the un/registering of hooks via self:
--[[ This was just a thought.
function ZO_Object:RegisterForPreHook(...)
	return HOOK_MANAGER:RegisterForPreHook(tostring(self), ...)
end

function ZO_Object:UnregisterForPreHook(...)
	return HOOK_MANAGER:UnregisterForPreHook(tostring(self), ...)
end

function ZO_Object:RegisterForPostHook(...)
	return HOOK_MANAGER:RegisterForPostHook(tostring(self), ...)
end

function ZO_Object:UnregisterForPostHook(...)
	return HOOK_MANAGER:UnregisterForPostHook(tostring(self), ...)
end
]]


---------------------------------------------------------------------------------------------------------------
-- JO_CallLater and JO_CallLaterOnScene
---------------------------------------------------------------------------------------------------------------
--[[ About:
	These functions will not stack the callback if called several times in a row.
	
	JO_CallLater is simmular to zo_callLater, but can be ran several times in a row without stacking.

	JO_CallLaterOnScene is useful for situations where you want changes applied after a specified scene is shown.

	JO_CallLaterOnNextScene is useful for situations where you want changes applied after scenes change.


	JO_CallLater('_test', function() end, 100)
	JO_CallLaterOnScene(addon.name .. '_test', 'hud', function() end)
	JO_CallLaterOnNextScene(addon.name .. '_test', function() end)
]]
do	
	local logger = {}
	createLogger('CallLater', logger)
	
	jo_callLater = function(id, func, ms)
		if ms == nil then ms = 0 end
		local name = "JO_CallLater_".. id
		EVENT_MANAGER:UnregisterForUpdate(name)
		
		EVENT_MANAGER:RegisterForUpdate(name, ms,
			function()
				EVENT_MANAGER:UnregisterForUpdate(name)
				func(id)
			end)
		return id
	end

	jo_callLaterOnScene = function(id, sceneName, func)
		if not sceneName or type(sceneName) ~= 'string' then return end
		
		local updateName = "JO_CallLaterOnScene_" .. id
		EVENT_MANAGER:UnregisterForUpdate(updateName)
		
		local function OnUpdateHandler()
			if SCENE_MANAGER:GetCurrentSceneName() == sceneName then
				EVENT_MANAGER:UnregisterForUpdate(updateName)
				func()
			end
		end
		
		EVENT_MANAGER:RegisterForUpdate(updateName, 100, OnUpdateHandler)
	end

	jo_callLaterOnNextScene = function(id, func)
		local sceneName = SCENE_MANAGER:GetCurrentSceneName()
		local updateName = "JO_CallLaterOnNextScene_" .. id
		EVENT_MANAGER:UnregisterForUpdate(updateName)
		
		local function OnUpdateHandler()
			if SCENE_MANAGER:GetCurrentSceneName() ~= sceneName then
				EVENT_MANAGER:UnregisterForUpdate(updateName)
				func()
			end
		end
		
		EVENT_MANAGER:RegisterForUpdate(updateName, 100, OnUpdateHandler)
	end
end

---------------------------------------------------------------------------------------------------------------
-- JO_UpdateBuffer
---------------------------------------------------------------------------------------------------------------
--[[ About JO_UpdateBuffe:
	Useful when multiple triggers can fire the function but only want it to fire on the final call.
		for an example of it being used, see: "IsJusta Gamepad UI Visibility Helper" in dynamicChat.lua
	
	JO_UpdateBuffer
		local ENABLED = bool or nil
		self.UpdateBuffer = JO_UpdateBuffer('TEST', function(self, ...) end, ENABLED)
		or
		self.UpdateBuffer = JO_UpdateBuffer('TEST', function(self, ...) end)

		self.UpdateBuffer:Enable(enabled)
		self.UpdateBuffer:OnUpdate(arg1, arg2, ...)

	JO_UpdateBuffer_Simple
		self.OnUpdate = JO_UpdateBuffer_Simple('TEST', function(self, ...)
			d( '--	TestUpdateBuffer', ...)
		end)
		
		self:OnUpdate(arg1, arg2, ...)
	
	/script self:OnUpdate('1'); self:OnUpdate('2'); self:OnUpdate('3'); self:OnUpdate('4')
	would result only in 
		'--	TestUpdateBuffer'
		'4'

	/script TestClass = JO_UpdateBuffer:Subclass()
]]

local UpdateBuffer = ZO_InitializingObject:Subclass()
createLogger('UpdateBuffer', UpdateBuffer)

function UpdateBuffer:Initialize(id, func, enabled)
	self.updateName = "JO_UpdateBuffer_" .. id
	
	self:Info('UpdateBuffer:Initialize: updateName = %s', self.updateName)
	
	self.enabled = enabled or true
	self.delay = 100
	
	self.CallbackFn = func
end

function UpdateBuffer:OnUpdate(...)
	local params = {...}
	EVENT_MANAGER:UnregisterForUpdate(self.updateName)
	
	self:Debug('UpdateBuffer:OnUpdate: %s', self.updateName)
	local function OnUpdateHandler()
		self:Debug('-- Fire: %s', self.updateName, fmt(params))
		EVENT_MANAGER:UnregisterForUpdate(self.updateName)
		self:CallbackFn(unpack(params))
	end
	
	if self.enabled then
		EVENT_MANAGER:RegisterForUpdate(self.updateName, self.delay, OnUpdateHandler)
	end
end

function UpdateBuffer:SetDelay(delay)
	self.delay = delay
end

function UpdateBuffer:SetEnabled(enabled)
	self:Info('UpdateBuffer:SetEnabled: updateName = %s, enabled = %s', self.updateName, enabled)
	self.enabled = enabled
end

JO_UpdateBuffer = UpdateBuffer

function JO_UpdateBuffer_Simple(id, func)
	local updateName = "JO_UpdateBuffer_Simple_" .. id

	return function(...)
		local params = {...}
		EVENT_MANAGER:UnregisterForUpdate(updateName)
		
		local function OnUpdateHandler()
			EVENT_MANAGER:UnregisterForUpdate(updateName)
			func(unpack(params))
		end
		
		EVENT_MANAGER:RegisterForUpdate(updateName, 100, OnUpdateHandler)
	end
end

---------------------------------------------------------------------------------------------------------------
-- Modifications to allow disabling interactions
---------------------------------------------------------------------------------------------------------------
local lib_reticle = RETICLE
local lib_fishing_manager = FISHING_MANAGER
local lib_fishing_gamepad = FISHING_GAMEPAD
local lib_fishing_keyboard = FISHING_KEYBOARD

do
	local logger = {}
	createLogger('Disable_Interaction', logger)
	
	-- RETICLE:GetInteractPromptVisible and FISHING_MANAGER:StartInteraction are used to disable interactions.
	-- set RETICLE.interactionDisabled = true to disable
	function lib_reticle:GetInteractPromptVisible()
		-- disables interaction in gamepad mode and allows jumping
		if self.interactionDisabled then
			return false
		end
		return not self.interact:IsHidden()
	end

	function lib_fishing_manager:StartInteraction()
		logger:Debug('function StartInteraction: RETICLE.interactionDisabled = %s', lib_reticle.interactionDisabled)
		if lib_reticle.interactionDisabled then
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

	-- Experimental: can register filter functions used for diabeling interactions, instead of custom hook functions.
	-- Is currently in use by "IsJusta Disable Actions While Moving". May be in > 1.4.2
	---------------------------------------------------------------------------------------------------------------
	lib_reticle.actionFilters = {}

	function lib_reticle:SetInteractionDisabled(disabled)
		self.interactionDisabled = disabled
	end

	-- comparator, filter, ??
	function lib_reticle:RegisterActionDisabledFilter(registerdName, action, filter)
		if not self.actionFilters[action] then self.actionFilters[action] = {} end
		self.actionFilters[action][registerdName] = filter
		return filter
	end

	function lib_reticle:UnregisterActionDisabledFilter(registerdName, action)
		if self.actionFilters[action] and self.actionFilters[action][registerdName] then
			self.actionFilters[action][registerdName] = nil
		end
	end

	function lib_reticle:GetActionBlockedFunctions(action)
		return self.actionFilters[action]
	end

	function lib_reticle:IsInteractionDisabled(currentFrameTimeSeconds)
		local action, interactableName = GetGameCameraInteractableActionInfo()
		logger:Debug('function IsInteractionDisabled: action = %s, interactableName = %s, interactionBlocked = %s, interactionDisabled = %s', action, interactableName, self.interactionBlocked, self.interactionDisabled)
		if action == nil then return self.interactionDisabled end
		local actionFilters = self:GetActionBlockedFunctions(action)
		
		if actionFilters then
			for registeredName, actionFilter in pairs(actionFilters) do
				logger:Debug('-- actionFilter: registeredName = %s, actionFilter Returns = %s', registeredName, actionFilter(action, interactableName, currentFrameTimeSeconds))
				if actionFilter(action, interactableName, currentFrameTimeSeconds) then
					return true
				end
			end
		end
		return false
	end

	JO_HOOK_MANAGER:RegisterForPostHook(lib.name, lib_reticle, "TryHandlingInteraction", function(self, interactionPossible, currentFrameTimeSeconds)
		if not interactionPossible then return end
		self.interactionDisabled = self:IsInteractionDisabled(currentFrameTimeSeconds)
	--	logger:Debug('self.interactionBlocked = %s', self.interactionBlocked)
	end)
end

--[[ Example usage.

	local actionsTable = {
		[GetString("SI_GAMECAMERAACTIONTYPE", 1)]	= 1,
		[GetString("SI_GAMECAMERAACTIONTYPE", 2)]	= 2,
	}

	-- The register loop used in "IsJusta Disable Actions While Moving"
	for actionName in pairs(actionsTable) do
		RETICLE:RegisterActionDisabledFilter(addon.name, actionName, function(action, interactableName, currentFrameTimeSeconds)
			ii This first checks to see if the current action is on the list for being disabled based on savedVars and other factors.
			if disabledInteractions(action, interactableName) then
				-- Next it checks to see if the action should be disabled based on action or interactableName and currentFrameTimeSeconds
				-- currentFrameTimeSeconds is not required. Using here to re-enable after a set time.
				if isActionDisabled(action, interactableName, currentFrameTimeSeconds) then
					playFromStart()
					return true
				else
					playInstantlyToEnd()
				end
			end
			return false
		end)
	end
]]

--[[
/script d(RETICLE.actionFilters)

	binding handlers for interaction
	- Keyboard 
		<Down>if not FISHING_MANAGER:StartInteraction() then GameCameraInteractStart() end</Down>

	- gamepad
		<Down>
			ZO_SetJumpOrInteractDownAction(ZO_JUMP_OR_INTERACT_DID_NOTHING)

			local interactPromptVisible = RETICLE:GetInteractPromptVisible() --< setting this to false will prevent interaction

			local isInactiveClickableFixture = IsGameCameraClickableFixture() and not IsGameCameraClickableFixtureActive()
			if not IsBlockActive() then  --don't allow Interactions or Jumps while blocking on Gamepad as it will trigger a roll anyway.
				if interactPromptVisible and not isInactiveClickableFixture then
					ZO_SetJumpOrInteractDownAction(ZO_JUMP_OR_INTERACT_DID_INTERACT)

					if not FISHING_MANAGER:StartInteraction() then GameCameraInteractStart() end

				else
					ZO_SetJumpOrInteractDownAction(ZO_JUMP_OR_INTERACT_DID_JUMP)
					JumpAscendStart()
				end
			end
		</Down>
]]

---------------------------------------------------------------------------------------------------------------
-- DeferredInitialization - functions that need to be set up after loading
---------------------------------------------------------------------------------------------------------------
--[[ About DeferredInitialization:
	DeferredInitialization is used to initialize modifications of objects that are not created OnInitialize.
]]

local DeferredInitialization = {}
createLogger('DeferredInitialization', DeferredInitialization)


--[[
-- Registering and Unregistering hooks combines the familiar way of registering events and hooks.
-- Use a unique name. This could simply be the addon's name.

-- "Replace ZO_PreHoook("
	with
-- "JO_HOOK_MANAGER:RegisterForPreHook(addon.name, "

-- Unregistering is not required, all hooks will run regardless on how they return. However, the option now is available without having to reload.

-- For global functions...('UniqueIdentifier', 'FunctionName', hookFunction)
JO_HOOK_MANAGER:RegisterForPreHook(addon.name .. '_HookTest', 'SomeFunction', hookFunction)
JO_HOOK_MANAGER:UnregisterForPreHook(addon.name .. '_HookTest', 'SomeFunction')

-- For nested functions... ('UniqueIdentifier', Object, 'FunctionName', hookFunction)
JO_HOOK_MANAGER:RegisterForPostHook(addon.name, SomeObject, 'SomeFunction', hookFunction)
JO_HOOK_MANAGER:UnregisterForPostHook(addon.name, SomeObject, 'SomeFunction')

JO_HOOK_MANAGER:RegisterForPreHookHandler(addon.name, control, 'OnMouseOver', hookFunction)
JO_HOOK_MANAGER:UnregisterForPreHookHandler(addon.name, control, 'OnMouseOver')
JO_HOOK_MANAGER:RegisterForPostHookHandler(addon.name, control, 'OnMouseOver', hookFunction)
JO_HOOK_MANAGER:UnregisterForPostHookHandler(addon.name, control, 'OnMouseOver')

JO_HOOK_MANAGER:RegisterForPostHook('Wonderland', FOO, 'Bar', hookFunction)
-- Running the same register with the same parameters will replace an already registered hookFunction. It will not add an additional hook.
JO_HOOK_MANAGER:RegisterForPostHook('Wonderland', FOO, 'Bar', hookFunction_2)


-- Disabling interaction is now super simple using RETICLE.interactionBlocked
-- RETICLE.interactionBlocked is already part of the RETICLE object. Setting it true will normally set the interaction keybind to disabled.
-- However, this only turns the keybind gray while still allowing interaction. Now it will also prevent interaction, without hindering game function.
JO_HOOK_MANAGER:RegisterForPreHook('IsJustaDAWM', RETICLE, "TryHandlingInteraction", function(self, interactionPossible, currentFrameTimeSeconds)
	if not interactionPossible then return end
	self.interactionBlocked = false
	
	local action, interactableName = GetGameCameraInteractableActionInfo()
	if not action then return false end
	
	if isActionDisabled(action, interactableName, currentFrameTimeSeconds) then
		self.interactionBlocked = true
		
		-- Format interaction text
	end
	
	return self.interactionBlocked
end)

JO_HOOK_MANAGER:RegisterForPostHook('IsJustaDAWM', RETICLE, "TryHandlingInteraction", function(self, interactionPossible, currentFrameTimeSeconds)
	if not interactionPossible then return end
	local action, interactableName = GetGameCameraInteractableActionInfo()
	if not action then return end
	
	-- use a custom function to determine if the current action should be disabled.
	self.interactionBlocked = isActionDisabled(action, interactableName, currentFrameTimeSeconds)
end)



JO_HOOK_MANAGER:RegisterForPreHook(addon.name, 'SomeFunction', 'MapPins', CONTROL_HANDLER_ORDER_BEFORE)

]]