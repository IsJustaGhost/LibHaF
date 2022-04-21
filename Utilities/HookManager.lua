local Lib = LibJoCommon
local createLogger = function(className, classObject, levelOverride) Lib.CreateLogger(Lib, className, classObject, levelOverride) end

---------------------------------------------------------------------------------------------------------------
-- HookManager adds the ability to "register" and "unregister" Hooks.
---------------------------------------------------------------------------------------------------------------
--[[
	HOOK_MANAGER:RegisterFor*Hook(-string <register name>, -string <functionName>, -function <hookFunction>, -string <dependent> -nilable, -int <sortOrder> -nilable)
	HOOK_MANAGER:RegisterFor*Hook(-string <register name>, -table <object>, -string <functionName>, -function <hookFunction>, -string <dependent> -nilable, -int <sortOrder> -nilable)

	HOOK_MANAGER:RegisterFor*HookHandler(-string <register name>, -userdata <control>, -string <handlerName>, -function <hookFunction>, -string <dependent> -nilable, -int <sortOrder> -nilable)

	EXAMPLE:
		JO_HOOK_MANAGER:RegisterForPreHook('AddonName', RETICLE, 'TryHandlingInteraction', function() d('') end)
		JO_HOOK_MANAGER:RegisterForPreHook('AddonName', RETICLE, 'TryHandlingInteraction', function() d('') end, 'LibHaF', CONTROL_HANDLER_ORDER_BEFORE)

	
	An object is created the first time a function is hooked. This object handles adding and removing hook functions.
	local Hook_Object = RETICLE['TryHandlingInteraction_JO_Hook']

	Registered hook functions are stored within the Hook_Object based on what method the hook was created for.
	Hook_Object.hookTables.PreHook = {}
	Hook_Object.hookTables.PostHook = {}
	Hook_Object.hookTables.PreHookHandler = {}
	Hook_Object.hookTables.PostHookHandler = {}
	Hook_Object.hookTables.SecurePostHook = {}
	
	The first time a hook functions is added for a method, the hook will be created using the 
	corresponding ZO original hook method with an internally created hook function.
	ZO_PreHook(RETICLE, 'TryHandlingInteraction', internalHookFunction)
	The internalHookFunction will handle running registered hooks.
]]

JO_HOOK_ORDER_NONE = CONTROL_HANDLER_ORDER_NONE
JO_HOOK_ORDER_BEFOR = CONTROL_HANDLER_ORDER_BEFOR
JO_HOOK_ORDER_AFTER = CONTROL_HANDLER_ORDER_AFTER

local HookManager = {}
createLogger('HookManager', HookManager)

local JO_Hook = '_JO_Hook'

local HOOK_TYPE_1 = 'PreHook'
local HOOK_TYPE_2 = 'PostHook'
local HOOK_TYPE_3 = 'PreHookHandler'
local HOOK_TYPE_4 = 'PostHookHandler'
local HOOK_TYPE_5 = 'SecurePostHook'
 
local count = 0
local lastHookIdIndex = {}

local isPreHook = {
	['PreHook'] = true,
	['PreHookHandler'] = true,
}

local isHandler = {
	['PreHookHandler'] = true,
	['PostHookHandler'] = true,
}

local validOwnerType = {
	['table'] = true,
	['userdata'] = true,
}

local zo_hooks = {
	['PreHook'] = ZO_PreHook,
	['PostHook'] = ZO_PostHook,
	['PreHookHandler'] = ZO_PreHookHandler,
	['PostHookHandler'] = ZO_PostHookHandler,
	['SecurePostHook'] = SecurePostHook,
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

local function getHookId(owner, existingFunctionName)
	local hookId
	local ownerType = type(owner)
	local objectName = ''
	if ownerType == 'table' and owner[existingFunctionName] ~= nil then
		objectName = getObjectName(owner)
	elseif ownerType == 'userdata' then
		objectName = owner.GetName and owner:GetName() or tostring(owner)
	end
	hookId = string.format('%s["%s"]', objectName, existingFunctionName)

	return hookId
end

local function doHookFunctionsMatch(oldHook, newHook)
	if not newHook then return false end
	
	return tostring(oldHook) == newHook
end

local function hookComparator(entry, registeredName, newHook)
	return entry.registeredName == registeredName or
		doHookFunctionsMatch(entry.hookFunction, newHook)
end

local function getExistingHook(registeredName, hookTable, newHook)
	for k, entry in pairs(hookTable) do
		if hookComparator(entry, registeredName, newHook) then
			return k, entry.registeredName
		end
	end
end

local function getDependentIndex(hookTable, registeredName, sortOrder)
	local index = getExistingHook(registeredName, hookTable)
	
	if index then
		return (sortOrder == CONTROL_HANDLER_ORDER_BEFORE) and index or (index + 1)
	end
end

local function getNextId(calledBy, hookTable, hookFunction)
	local index = (lastHookIdIndex[calledBy] or 0) + 1
	local nextId = 'Default_' .. calledBy .. '_' .. index
	local _, oldName = getExistingHook(nextId, hookTable, tostring(hookFunction))
	
	if oldName then
		if nextId ~= oldName then
			nextId = oldName
		end
	else
		lastHookIdIndex[calledBy] = index
	end
	return nextId
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
	return objectTable, existingFunctionName, hookFunction, dependent, sortOrder
end

-- the functions that will cycle through the registered pre and post hooks
local function getInternalHookFunction(hookObject, hookType)
	local function filterLog(filter)
		for k, strng in pairs({'DebugLogViewer', 'RETICLE'}) do
			if filter:match(strng) then return true end
		end
	end
	
	local function dbug(filter, ...)
		-- reduce logger spam
		if filterLog(filter) then return end
		HookManager:Debug(...)
	end

	
	local function info(filter, ...)
		-- reduce logger spam
		if filterLog(filter) then return end
		HookManager:Info(...)
	end

	if isPreHook[hookType] then
		return function(...)
		--	dbug(hookObject.hookId, 'Run PreHooks for %s', hookObject.hookId)
			local hookTable = hookObject:GetHookTable(hookType)
			if #hookTable == 0 then return false end
			local bypass = false
			for k, entry in ipairs(hookTable) do
			--	dbug(entry.hookId, '-- Registered by %s', entry.registeredName)
				if entry.hookFunction(...) then
					bypass = true
				end
			end
			
			return bypass
		end
	end
	
	return function(...)
	--	dbug(hookObject.hookId, 'Run PostHooks for %s', hookObject.hookId)
		local hookTable = hookObject:GetHookTable(hookType)
		if #hookTable == 0 then return end
		for k, entry in ipairs(hookTable) do
		--	dbug(entry.hookId, '-- Registered by %s', entry.registeredName)
			entry.hookFunction(...)
		end
	end
end

---------------------------------------------------------------------------------------------------------------
-- HookObject
---------------------------------------------------------------------------------------------------------------
local HookObject = ZO_InitializingObject:Subclass()

function HookObject:Initialize(hookType, hookId, objectTable, existingFunctionName)
	self.hookId = hookId
	self.owner = objectTable -- owner = objectTable or control
	self.method = existingFunctionName -- method = existingFunctionName or handlerName
	
	self.hookTables = {}
end

function HookObject:CreateEntry(hookType, registeredName, hookFunction, dependent, sortOrder)
	local hookTable = self:GetHookTable(hookType)
	local entry = {
		['hookId'] = self.hookId,
		['hookType'] = hookType,
		['registeredName'] = registeredName,
		['hookFunction'] = hookFunction,
	}
	
	local index = #hookTable + 1
	
	if index > 1 and dependent and sortOrder > JO_HOOK_ORDER_NONE then
		index = getDependentIndex(hookTable, dependent, sortOrder) or index
	end
	
	return entry, index
end

function HookObject:GetInitializingFuncitons(hookType)
	return zo_hooks[hookType], getInternalHookFunction(self, hookType)
end

function HookObject:CreateHook(hookType)
	local createHook, internalHookFunction = self:GetInitializingFuncitons(hookType)
	createHook(self.owner, self.method, internalHookFunction)
end

function HookObject:Add(hookType, registeredName, hookFunction, dependent, sortOrder)
	local hookTable = self:GetHookTable(hookType)
	if #hookTable == 0 then
		-- If a hook of current type has not been created yet, create it now.
		self:CreateHook(hookType)
	end

	if registeredName == nil then
		registeredName = getNextId(hookType, hookTable, hookFunction)
	end
	
	-- remove existing hook if exists
	self:Remove(hookType, registeredName, hookFunction)
	local entry, index = self:CreateEntry(hookType, registeredName, hookFunction, dependent, sortOrder)
	
	table.insert(hookTable, index, entry)
	
	--HookManager:Info('-- Hook Added for %s, %s', registeredName, self.hookId)
	
	-- count is for debug purposes
	count = count + 1
	JO_HOOK_MANAGER.count = count
end

function HookObject:Remove(hookType, registeredName, hookFunction)
	local hookTable = self:GetHookTable(hookType)
	
	local index, oldName = getExistingHook(registeredName, hookTable, tostring(hookFunction))
	if index then
		count = count - 1
		table.remove(hookTable, index)
		return true
	end
end

function HookObject:GetHookTable(hookType)
	if not self.hookTables[hookType] then
		self.hookTables[hookType] = {}
	end
	
	return self.hookTables[hookType]
end

---------------------------------------------------------------------------------------------------------------
-- HookManager
---------------------------------------------------------------------------------------------------------------
--[[
	-- require name for unregister?
   if register then
       invalid = register and (not hookFunction or type(hookFunction) ~= 'function') or invalid
   else
       invalid = registeredName == nil or invalid
   end
]]
local function validateParamaters(hookType, hookId, registeredName, objectTable, existingFunctionName, hookFunction, register)
	local invalid, resultString = false, ''
	
	invalid = not (hookId and validOwnerType[type(objectTable)] and type(existingFunctionName) == 'string')
	invalid = register and (not hookFunction or type(hookFunction) ~= 'function') or invalid
	
	local tailString = register and ', -function hookFunction, <optional> -string dependent,  <optional> -number sortOrder' or ', <optional> -function hookFunction'
	
	if isHandler[hookType] then
		resultString = '-string name, -usserData control, -string handlerName' .. tailString
	else
		resultString = string.format('%s\n%s',
			'-string name, -string existingFunctionName' .. tailString,
			'-string name, -table object, -string existingFunctionName' .. tailString
		)
	end
	
	if invalid then
		local functionName = (type(existingFunctionName) == 'string' and existingFunctionName) or 'Unknown'
		HookManager:Error('Error %s hook, Hook type = %s, Function name = %s, for %s, Requires arguments:\n%s', (register and 'Registering' or 'Unregistering'), hookType, functionName, hookId, resultString)
	end
	return invalid
end

local function sharedRegister(hookType, registeredName, objectTable, existingFunctionName, hookFunction, dependent, sortOrder)
	--HookManager:Info('Register %s', hookType)
	
	local hookId = getHookId(objectTable, existingFunctionName)
	local invalid = validateParamaters(hookType, hookId, registeredName, objectTable, existingFunctionName, hookFunction, true)
	if invalid then return false end
	
	local Hook_Object = objectTable[existingFunctionName .. JO_Hook]
	if not Hook_Object then
		Hook_Object = HookObject:New(hookType, hookId, objectTable, existingFunctionName)
		objectTable[existingFunctionName .. JO_Hook] = Hook_Object
	end
	
	return Hook_Object:Add(hookType, registeredName, hookFunction, dependent, sortOrder)
end

local function sharedUnregister(hookType, registeredName, objectTable, existingFunctionName, hookFunction)
	local hookId = getHookId(objectTable, existingFunctionName)
	local invalid = validateParamaters(hookType, hookId, registeredName, objectTable, existingFunctionName, hookFunction)
	if invalid then return false end
	--HookManager:Info('Unregister %s', hookType)
	
	local Hook_Object = objectTable[existingFunctionName .. JO_Hook]
	
	if Hook_Object then
		if Hook_Object:Remove(hookType, registeredName, hookFunction) then
			--HookManager:Info('-- Hook Removed for %s, %s', registeredName, Hook_Object.hookId)
		end
	end
end

-- where ... == objectTable, existingFunctionName, hookFunction, dependent, sortOrder
do -- Pre-hooks
	function HookManager:RegisterForPreHook(registeredName, ...)
		return sharedRegister(HOOK_TYPE_1, registeredName, getUpdatedParameters(...))
	end

	function HookManager:UnregisterForPreHook(registeredName, ...)
		return sharedUnregister(HOOK_TYPE_1, registeredName, getUpdatedParameters(...))
	end

	function HookManager:RegisterForPreHookHandler(registeredName, control, handlerName, hookFunction, dependent, sortOrder)
		return sharedRegister(HOOK_TYPE_3, registeredName, control, handlerName, hookFunction)
	end

	function HookManager:UnregisterForPreHookHandler(registeredName, control, handlerName)
		return sharedUnregister(HOOK_TYPE_3, registeredName, control, handlerName)
	end
end

do -- Post-hooks
	function HookManager:RegisterForPostHook(registeredName, ...)
		return sharedRegister(HOOK_TYPE_2, registeredName, getUpdatedParameters(...))
	end

	function HookManager:UnregisterForPostHook(registeredName, ...)
		return sharedUnregister(HOOK_TYPE_2, registeredName, getUpdatedParameters(...))
	end

	function HookManager:RegisterForPostHookHandler(registeredName, control, handlerName, hookFunction, dependent, sortOrder)
		return sharedRegister(HOOK_TYPE_4, registeredName, control, handlerName, hookFunction)
	end

	function HookManager:UnregisterForPostHookHandler(registeredName, control, handlerName)
		return sharedUnregister(HOOK_TYPE_4, registeredName, control, handlerName)
	end
end

do -- Backwards compatibility
	-- We'll determine registeredName later
	ZO_PreHook = function(...)
		return sharedRegister(HOOK_TYPE_1, nil, getUpdatedParameters(...))
	end
	ZO_PostHook = function(...)
		return sharedRegister(HOOK_TYPE_2, nil, getUpdatedParameters(...))
	end
	
	ZO_PreHookHandler = function(...)
		return sharedRegister(HOOK_TYPE_3, nil, ...)
	end
	ZO_PostHookHandler = function(...)
		return sharedRegister(HOOK_TYPE_4, nil, ...)
	end
	
	SecurePostHook = function(...)
		return sharedRegister(HOOK_TYPE_5, nil, getUpdatedParameters(...))
	end
end

JO_HOOK_MANAGER = HookManager
