-- libGlobals

local LIB_IDENTIFIER, LIB_VERSION = "LibHaF", 01

if _G[LIB_IDENTIFIER] and _G[LIB_IDENTIFIER].version > LIB_VERSION then
	return
end

local lib = {}
lib.name = LIB_IDENTIFIER
lib.version = LIB_VERSION
_G[LIB_IDENTIFIER] = lib

---------------------------------------------------------------------------------------------------------------
-- HookManager adds the ability to "register" and "unregister" PreHooks and PostHooks
---------------------------------------------------------------------------------------------------------------
local HookManager = {}
local function updateParameters(objectTable, existingFunctionName, hookFunction)
	if type(objectTable) == "string" then
		hookFunction = existingFunctionName
		existingFunctionName = objectTable
		objectTable = _G
	end
	return objectTable, existingFunctionName, hookFunction
end

local function getHookFunctions(objectTable, existingFunctionName)
	return objectTable[existingFunctionName .. '_Original'], objectTable[existingFunctionName .. '_PrehookFunctions' ], objectTable[existingFunctionName .. '_PosthookFunctions' ]
end

local function update(objectTable, existingFunctionName)
	if not objectTable[existingFunctionName .. '_Original'] then
		objectTable[existingFunctionName .. '_Original'] = objectTable[existingFunctionName]
	end
	
	local originalFn, prehookFunctions, posthookFunctions = getHookFunctions(objectTable, existingFunctionName)
	
	if not prehookFunctions and not posthookFunctions then
		objectTable[existingFunctionName] = originalFn
		objectTable[existingFunctionName .. '_Original'] = nil
		return
	end

	local newFn = function(...)
		local function runPosthooks(...)
			if posthookFunctions then
				for name, hookFunction in pairs(posthookFunctions) do
					hookFunction(...)
				end
			end
		end
		
		local bypass = false
		if prehookFunctions then
			for name, hookFunction in pairs(prehookFunctions) do
				if hookFunction(...) then
					bypass = true
				end
			end
		end

		if bypass then
			runPosthooks(...)
			return true
		else
			local returns = {originalFn(...)}
			runPosthooks(...)
			return unpack(returns)
		end
	end
	objectTable[existingFunctionName] = newFn
end

local function registerHooks(name, objectTable, existingFunctionName, hookFunction, suffix)
	if not name then return end
	local hookFunctions = objectTable[existingFunctionName .. suffix] or {}
	
	-- allow re-registering an already created hook without unregistering first
	hookFunctions[name] = hookFunction
	objectTable[existingFunctionName .. suffix] = hookFunctions
	
	update(objectTable, existingFunctionName)
end

local function unregisterHooks(name, objectTable, existingFunctionName, suffix)
	if not name then return end
	local hookFunctions = objectTable[existingFunctionName .. suffix]
	if hookFunctions then
		if hookFunctions[name] then
			hookFunctions[name] = nil
			
			if NonContiguousCount(hookFunctions) == 0 then
				hookFunctions = nil
			end
			objectTable[existingFunctionName .. suffix] = hookFunctions
			
			update(objectTable, existingFunctionName)
		end
	end
end

function HookManager:RegisterForPreHook(name, objectTable, existingFunctionName, hookFunction)
	objectTable, existingFunctionName, hookFunction = updateParameters(objectTable, existingFunctionName, hookFunction)
	
	registerHooks(name, objectTable, existingFunctionName, hookFunction, '_PrehookFunctions')
end

function HookManager:UnregisterForPreHook(name, objectTable, existingFunctionName)
	objectTable, existingFunctionName, hookFunction = updateParameters(objectTable, existingFunctionName, hookFunction)
	
	unregisterHooks(name, objectTable, existingFunctionName, '_PrehookFunctions')
end

function HookManager:RegisterForPostHook(name, objectTable, existingFunctionName, hookFunction)
	objectTable, existingFunctionName, hookFunction = updateParameters(objectTable, existingFunctionName, hookFunction)
	
	registerHooks(name, objectTable, existingFunctionName, hookFunction, '_PosthookFunctions')
end

function HookManager:UnregisterForPostHook(name, objectTable, existingFunctionName)
	objectTable, existingFunctionName, hookFunction = updateParameters(objectTable, existingFunctionName, hookFunction)
	
	unregisterHooks(name, objectTable, existingFunctionName, '_PosthookFunctions')
end

HOOK_MANAGER = HookManager

--[[
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

local fishingActions = {
	[GetString(SI_GAMECAMERAACTIONTYPE16)] = true,
	[GetString(SI_GAMECAMERAACTIONTYPE17)] = true,
}

local function notFishingAction()
	local action, interactableName = GetGameCameraInteractableActionInfo()
	return not fishingActions[action]
end

local function onPlayerActivated()
	EVENT_MANAGER:UnregisterForEvent('LibHaF', EVENT_PLAYER_ACTIVATED)
	
	-- RETICLE:GetInteractPromptVisible and FISHING_MANAGER:StartInteraction are used to disable interactions.
	-- set RETICLE.interactionBlocked == true to disable
	function RETICLE:GetInteractPromptVisible()
		-- disables interaction in gamepad mode and allows jumping
		if RETICLE.interactionBlocked and notFishingAction() then
			return false
		end
		return not self.interact:IsHidden()
	end
	
	function FISHING_MANAGER:StartInteraction()
		if RETICLE.interactionBlocked and notFishingAction() then
	--	if RETICLE.interactionBlocked then
			-- disables interaction in keyboard mode
			-- returning true here will prevent GameCameraInteractStart() form firing
			return true
		end
		
		self.gamepad = IsInGamepadPreferredMode()
		if self.gamepad then
			return FISHING_GAMEPAD:StartInteraction()
		else
			return FISHING_KEYBOARD:StartInteraction()
		end
	end
--	/script d(RETICLE.interactionBlocked)
end

EVENT_MANAGER:RegisterForEvent('LibHaF', EVENT_PLAYER_ACTIVATED, onPlayerActivated)
