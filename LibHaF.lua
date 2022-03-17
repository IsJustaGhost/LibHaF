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
			adds the ability to "register" and "unregister" PreHooks and PostHooks. Allows all hooks to run.
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
local logLevel = debugOverride and LibDebugLogger.LOG_LEVEL_DEBUG or LibDebugLogger.LOG_LEVEL_INFO

local function unpack_unordered_recursive(tbl, key)
  local new_key, value = next(tbl, key)
  if new_key == nil then return end

  return new_key, value, unpack_unordered_recursive(tbl, new_key)
end

local function tryUnpack(tbl)
    if type(tbl) ~= 'table' then return 'Not a table' end
	
    local key, value = next(tbl)
    if key == nil then return end
    
    return key, value, unpack_unordered_recursive(tbl, key)
end

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
    --    formatString = formatString .. ' [table] {%s}'
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

---------------------------------------------------------------------------------------------------------------
-- HookManager adds the ability to "register" and "unregister" PreHooks and PostHooks
---------------------------------------------------------------------------------------------------------------
--[[
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
HookManager.registeredHooks = {}

local function getObjectName(object)
	local tableId = tostring(object)
	if type(object) ~= 'table' then return false end -- '_Not_A_Object_'
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

	return '_Not_Found_'
end

local function getOrCreateHookId(objectTable, existingFunctionName)
	local registeredHooks = objectTable.registeredHooks or {}

	local hookId = registeredHooks[existingFunctionName]
	if hookId == nil then
		local objectName = getObjectName(objectTable)
		if not objectName then return false end
		hookId = string.format('%s["%s"]', objectName, existingFunctionName)
		
		registeredHooks[existingFunctionName] = hookId
		objectTable.registeredHooks = registeredHooks
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
	return objectTable[existingFunctionName .. '_Original'], objectTable[existingFunctionName .. '_PrehookFunctions' ], objectTable[existingFunctionName .. '_PosthookFunctions' ], objectTable.registeredHooks[existingFunctionName]
end

local function updateRegisteredHooks()
	local registeredHooks = {}

	for registeredName, hooks in pairs(HookManager.registeredHooks) do
		if NonContiguousCount(hooks) ~= 0 then
			registeredHooks[registeredName] = hooks
		end
	end

	HookManager.registeredHooks = registeredHooks
end

local function addRegisteredHook(registeredName, hookId)
	local registeredHooks = HookManager.registeredHooks[registeredName] or {}
	if not HookManager.registeredHooks[registeredName] then HookManager.registeredHooks[registeredName] = {} end
	registeredHooks[hookId] = true
	HookManager.registeredHooks[registeredName] = registeredHooks
end

local function removeRegisteredHook(registeredName, hookId)
	if HookManager.registeredHooks[registeredName] then 
		HookManager.registeredHooks[registeredName][hookId] = nil
	end
end

local function resetToOriginal(objectTable, existingFunctionName)
	HookManager:Info('local function resetToOriginal: reset %s', objectTable.registeredHooks[existingFunctionName]) -- hookId

	objectTable[existingFunctionName .. '_Original'] = nil
	objectTable.registeredHooks[existingFunctionName] = nil
	
	if NonContiguousCount(objectTable.registeredHooks) == 0 then
		objectTable.registeredHooks = nil
	end
end

local function getHookPocessingFunctions(prehookFunctions, posthookFunctions)
	local dummyFn = function(...) return false end
	local runPrehooks, runPosthooks = dummyFn, dummyFn

	if prehookFunctions then
		runPrehooks = function(...)
			local bypass = false
			for registeredName, hookFunction in pairs(prehookFunctions) do
				local returns = hookFunction(...)
				HookManager:Debug('-- Run PreHook for: registeredName = %s, Returns = %s', registeredName, returns) 
				if returns then
					bypass = true
				end
			end
			
			HookManager:Debug('Bypass Original = %s', bypass)
			return bypass
		end
	end
	
	if posthookFunctions then
		runPosthooks = function(...)
			for registeredName, hookFunction in pairs(posthookFunctions) do
				local returns = {hookFunction(...)}
				HookManager:Debug('-- Run PostHook for: registeredName = %s, Returns = %s', registeredName, fmt(returns)) 
			end
		end
	end
	
	return runPrehooks, runPosthooks
end

local function getUpdatedFunction(objectTable, existingFunctionName)
	local originalFn, prehookFunctions, posthookFunctions, hookId = getHookTablesAndId(objectTable, existingFunctionName)
	HookManager:Info('local function getUpdatedFunction: for %s', hookId)
	
	if not prehookFunctions and not posthookFunctions then
		resetToOriginal(objectTable, existingFunctionName)
		return originalFn -- 'Original function has been restored.'
	end

	return function(...)
		HookManager:Debug('Run Hooks: %s', hookId)
		
		local runPrehooks, runPosthooks = getHookPocessingFunctions(prehookFunctions, posthookFunctions)
		
		if runPrehooks(...) then
			runPosthooks(...)
			return true
		else
			local returns = {originalFn(...)}
			HookManager:Debug('Run originalFn, Returns = %s', fmt(returns))
			runPosthooks(...)
			return unpack(returns)
		end
	end
end

local function updateHookedFunction(objectTable, existingFunctionName)
	HookManager:Info('local function updateHookedFunction:')
	if not objectTable[existingFunctionName .. '_Original'] then
		-- Store the origainl function for later use.
		objectTable[existingFunctionName .. '_Original'] = objectTable[existingFunctionName]
	end
	
	objectTable[existingFunctionName] = getUpdatedFunction(objectTable, existingFunctionName)
end

local function validateArguments(registeredName, objectTable, existingFunctionName, hookFunction, suffix, hookId)
	-- concidering making an argument validator
--[[
	local errorString = validateArguments(registeredName, objectTable, existingFunctionName, hookFunction, suffix, hookId)
	if errorString then
		self:Info('RegisterForPreHook: errorString = %s', errorString)
		return errorString
	end
]]
end

local function sharedRegister(hookType, registeredName, objectTable, existingFunctionName, hookFunction)
	-- validate arguments?
	HookManager:Info('local function sharedRegister: registeredName = %s', registeredName)
	local objectTable, existingFunctionName, hookFunction, hookId = updateParameters(objectTable, existingFunctionName, hookFunction)

	local suffix = '_' .. hookType .. 'hookFunctions'
	HookManager:Info('-- Begain RegisterFor%sHook: %s', hookType, hookId)
	
	local hookFunctions = objectTable[existingFunctionName .. suffix] or {}
	
	HookManager:Info('Has existing %shook for %s = %s', hookType, registeredName, hookFunctions[registeredName] ~= nil)
	-- allow replacing an already created hook without unregistering first?
	hookFunctions[registeredName] = hookFunction
	addRegisteredHook(registeredName, hookId)
	
	HookManager:Debug('%s%s] = %s', hookId:gsub(']$', '' ), suffix, fmt(hookFunctions))
	objectTable[existingFunctionName .. suffix] = hookFunctions
	
	updateHookedFunction(objectTable, existingFunctionName)
	HookManager:Info('-- Update complete.')
	HookManager:Info('-- End RegisterFor%sHook: %s', hookType, hookId)
end

local function sharedUnregister(hookType, registeredName, objectTable, existingFunctionName)
	-- validate arguments?
	HookManager:Info('local function sharedUnregister: registeredName = %s', registeredName)
	local objectTable, existingFunctionName, hookFunction, hookId = updateParameters(objectTable, existingFunctionName)

	local suffix = '_' .. hookType .. 'hookFunctions'
	HookManager:Info('-- Begain UnregisterFor%sHook: %s', hookType, hookId)
	
	local hookFunctions = objectTable[existingFunctionName .. suffix]
	
	if hookFunctions then
		HookManager:Debug('-- Current no. of hooks = %s', hookId, suffix, NonContiguousCount(hookFunctions))
		if hookFunctions[registeredName] then
			hookFunctions[registeredName] = nil
			
			if NonContiguousCount(hookFunctions) == 0 then
				hookFunctions = nil
			end
			objectTable[existingFunctionName .. suffix] = hookFunctions
			removeRegisteredHook(registeredName, hookId)

			updateHookedFunction(objectTable, existingFunctionName)
			HookManager:Info('-- Update complete.')
		end
	end
	HookManager:Info('-- End UnregisterFor%sHook: %s, Has remaning hooks = %s', hookType, hookId, (hookFunctions ~= nil))
end

do -- Pre-hooks
	local hookType = 'Pre'
	function HookManager:RegisterForPreHook(registeredName, objectTable, existingFunctionName, hookFunction)
		return sharedRegister(hookType, registeredName, objectTable, existingFunctionName, hookFunction)
	end

	function HookManager:UnregisterForPreHook(registeredName, objectTable, existingFunctionName)
		return sharedUnregister(hookType, registeredName, objectTable, existingFunctionName)
	end
end

do -- Post-hooks
	local hookType = 'Post'
	function HookManager:RegisterForPostHook(registeredName, objectTable, existingFunctionName, hookFunction)
		return sharedRegister(hookType, registeredName, objectTable, existingFunctionName, hookFunction)
	end

	function HookManager:UnregisterForPostHook(registeredName, objectTable, existingFunctionName)
		return sharedUnregister(hookType, registeredName, objectTable, existingFunctionName)
	end
end

function HookManager:GetRegisteredHooks()
	updateRegisteredHooks()
	return self.registeredHooks
end

JO_HOOK_MANAGER = HookManager

--[[
/script d(JO_HOOK_MANAGER:GetRegisteredHooks())
add status returns for  un/registering?

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
-- DeferredInitialization - functions that need to be set up after loading
---------------------------------------------------------------------------------------------------------------
--[[ About DeferredInitialization:
	DeferredInitialization is used to initialize modifications of objects that are not created OnInitialize.
]]

local DeferredInitialization = {}
createLogger('DeferredInitialization', DeferredInitialization)

local fishingActions = {
	[GetString(SI_GAMECAMERAACTIONTYPE16)] = true, -- "Fish"
--	[GetString(SI_GAMECAMERAACTIONTYPE17)] = true, -- "Reel In"
}

local function notFishingAction()
	local action = GetGameCameraInteractableActionInfo()
	return not fishingActions[action]
end

local function performDeferredInitialization()
	DeferredInitialization:Info('local function performDeferredInitialization')
	-- Must insure these constants are updated after objects are created.
	local lib_reticle = RETICLE
	local lib_fishing_manager = FISHING_MANAGER
	local lib_fishing_gamepad = FISHING_GAMEPAD
	local lib_fishing_keyboard = FISHING_KEYBOARD

	-- RETICLE:GetInteractPromptVisible and FISHING_MANAGER:StartInteraction are used to disable interactions.
	-- set RETICLE.interactionBlocked = true to disable
	function lib_reticle:GetInteractPromptVisible()
		-- disables interaction in gamepad mode and allows jumping
		-- the aftion must not be for fishing. interactionBlocked == true before bait is selected
		if lib_reticle.interactionBlocked and notFishingAction() then
			return false
		end
		return not self.interact:IsHidden()
	end
	
	function lib_fishing_manager:StartInteraction()
	--	DeferredInitialization:Debug('FISHING_MANAGER: RETICLE.interactionBlocked = %s', lib_reticle.interactionBlocked)
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

local function onPlayerActivated()
	EVENT_MANAGER:UnregisterForEvent(lib.name, EVENT_PLAYER_ACTIVATED)
	
	DeferredInitialization:Info('onPlayerActivated')
	performDeferredInitialization()
end
EVENT_MANAGER:RegisterForEvent(lib.name, EVENT_PLAYER_ACTIVATED, onPlayerActivated)

--[[
	binding handlers for interaction
	- Keyboard 
		<Down>if not FISHING_MANAGER:StartInteraction() then GameCameraInteractStart() end</Down>

	- gamepad
		<Down>
			ZO_SetJumpOrInteractDownAction(ZO_JUMP_OR_INTERACT_DID_NOTHING)

			local interactPromptVisible = RETICLE:GetInteractPromptVisible() --< setting this to false will prevent inteaction

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


