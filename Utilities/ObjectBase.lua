local Lib = LibJoCommon

---------------------------------------------------------------------------------------------------------------
-- 
---------------------------------------------------------------------------------------------------------------
JO_Object = {}
zo_mixin(JO_Object, ZO_Object)

--[[
function addon:Initialize(control)
	self.control 		= control
	zo_mixin(self, addonData)

	if self.name and self.createLogger then
		self:CreateLogger(self.name, self, self.logLevel)
	end
end

-- "Modual".lua
local Modual = AddonObjectGlobal
local logger = {}
self:CreateLogger('tagName', logger) -- subLogger
]]

JO_Object.CreateLogger = Lib.CreateLogger
JO_Object.SetLogLevelOverride = Lib.SetLogLevelOverride

--[[ Example usage of GetDebugOptions
	LAM2:RegisterAddonPanel(ADDON_SHORT_NAME .. '_LAM', panelData)

	local optionsTable = {
		{
			type = "checkbox",
			name = 'option',
			tooltip = 'option for addon.',
			getFunc = function() return self.savedVars.option end,
			setFunc = function(value) self.savedVars.option = value end,
            width = "full"
		},
		self:GetDebugOptions(ADDON_SHORT_NAME, self.savedVars)
	}
	LAM2:RegisterOptionControls(ADDON_SHORT_NAME.. '_LAM', optionsTable)
]]
function JO_Object:GetDebugOptions(name, savedVars)
	local controlList = {
		{ type = "checkbox",	-- use frame
			name = 'Enable Debug',
			tooltip = '',
			getFunc = function() return savedVars.enableDebug end,
			setFunc = function(value) savedVars.enableDebug = value end,
			width = "half",
			requiresReload = true,
		},
		{ type = "dropdown",
			name = 'Log Level Override',
			choices = {"Verbose", "Debug", "Info", "Warning", "Error"},
			choicesValues = {'V','D','I','W','E'},
			getFunc = function() return savedVars.loggerLevelOverride end,
			setFunc = function(value)
				savedVars.loggerLevelOverride = value
				self:SetLogLevelOverride(value)
			end,
			width = "half",
			disabled = function() return not savedVars.enableDebug end,
		},
	}
	
	local menu = {
		type = "submenu",
		name = 'Debug Options',
		reference = name .. "_DebugOptions_LAM",
		controls = controlList,
	}
	return menu
end

--[[
	self:SetMinLevelOverride(LibDebugLogger.LOG_LEVEL_DEBUG)
	self:SetMinLevelOverride("D")
	Setting this for the main will also set it for all sub loggers, if done set prior to them being created.

	Log level options are				[		v		]
	LibDebugLogger.LOG_LEVEL_VERBOSE	= "V", 0, "verbose"
	LibDebugLogger.LOG_LEVEL_DEBUG		= "D", 1, "debug"
	LibDebugLogger.LOG_LEVEL_INFO		= "I", 2, "info"
	LibDebugLogger.LOG_LEVEL_WARNING	= "W", 3, "warning"
	LibDebugLogger.LOG_LEVEL_ERROR		= "E", 4, "error"
]]

JO_InitializingObject = {}
zo_mixin(JO_InitializingObject, JO_Object)
JO_InitializingObject.__index = JO_InitializingObject

function JO_InitializingObject:New(...)
    local newObject = setmetatable({}, self)
    newObject:Initialize(...)
    return newObject
end

function JO_InitializingObject:Initialize()
    -- To be overridden
end

---------------------------------------------------------------------------------------------------------------
-- Callback Objects
---------------------------------------------------------------------------------------------------------------
local JO_CallbackObjectMixin = {}

local CALLBACK_INDEX	= 1
local ARGUMENT_INDEX	= 2
local DELETED_INDEX		= 3

--Registers a callback to be executed when eventName is triggered.
--You may optionally specify an argument to be passed to the callback.
function JO_CallbackObjectMixin:RegisterCallback(eventName, callback, arg)
    if not eventName or not callback then
        return
    end

    --if this is the first callback then create the registry
    if not self.callbackRegistry then
        self.callbackRegistry = {}
    end

    --create a list to hold callbacks of this type if it doesn't exist
    local registry = self.callbackRegistry[eventName]
    if not registry then
        registry = {}
        self.callbackRegistry[eventName] = registry
    end

    --make sure this callback wasn't already registered
    for _, registration in ipairs(registry) do
        if registration[CALLBACK_INDEX] == callback and registration[ARGUMENT_INDEX] == arg then
            -- If the callback is already registered, make sure it hasn't been flagged for delete
            -- so it won't be unregistered in self:Clean later
            -- This can happen if you attempt to unregister and register for a callback
            -- during a callback, since that will delay the clean until after we have tried to re-register
            registration[DELETED_INDEX] = false
            return
        end
    end

    --store the callback with an optional argument
    --note: the order of the arguments to the table constructor must match the order of the *_INDEX locals above
    table.insert(registry, { callback, arg, false })
end

function JO_CallbackObjectMixin:UnregisterCallback(eventName, callback)
    if not self.callbackRegistry then
        return
    end

    local registry = self.callbackRegistry[eventName]

    if registry then
        --find the entry
        for i = 1,#registry do
            local callbackInfo = registry[i]
            if callbackInfo[CALLBACK_INDEX] == callback then
                callbackInfo[DELETED_INDEX] = true
                self:Clean(eventName)
                return
            end
        end
    end
end

function JO_CallbackObjectMixin:UnregisterAllCallbacks(eventName)
    if not self.callbackRegistry then
        return
    end

    local registry = self.callbackRegistry[eventName]

    if registry then
        --find the entry
        for i = 1, #registry do
            local callbackInfo = registry[i]
            callbackInfo[DELETED_INDEX] = true
        end

        self:Clean(eventName)
    end
end

--Executes all callbacks registered on this object with this event name
--Accepts the event name, and a list of arguments to be passed to the callbacks
--The return value is from the callbacks, the most recently registered non-nil non-false callback return value is returned
function JO_CallbackObjectMixin:FireCallbacks(eventName, ...)
    local result = nil

    if not self.callbackRegistry or not eventName then
        return result
    end

    local registry = self.callbackRegistry[eventName]
    if registry then
        self.fireCallbackDepth = self:GetFireCallbackDepth() + 1

        local callbackInfoIndex = 1
        while callbackInfoIndex <= #registry do
            --pass the arg as the first parameter if it exists
            local callbackInfo = registry[callbackInfoIndex]
            local argument = callbackInfo[ARGUMENT_INDEX]
            local callback = callbackInfo[CALLBACK_INDEX]
            local deleted = callbackInfo[DELETED_INDEX]
            
            if(not deleted) then
                if(argument) then
                    result = callback(argument, ...) or result
                else
                    result = callback(...) or result
                end
            end

            callbackInfoIndex = callbackInfoIndex + 1
        end

        self.fireCallbackDepth = self:GetFireCallbackDepth() - 1

        self:Clean()
    end
    
    return result
end

function JO_CallbackObjectMixin:Clean(eventName)
    local dirtyEvents = self:GetDirtyEvents()
    if eventName then
        dirtyEvents[#dirtyEvents + 1] = eventName
    end

    if self:GetFireCallbackDepth() == 0 then
        while #dirtyEvents > 0 do
            local eventName = dirtyEvents[#dirtyEvents]
            local registry = self.callbackRegistry[eventName]
            if registry then
                local callbackInfoIndex = 1
                while callbackInfoIndex <= #registry do
                    local callbackTable = registry[callbackInfoIndex]
                    if callbackTable[DELETED_INDEX] then
                        table.remove(registry, callbackInfoIndex)
                    else
                        callbackInfoIndex = callbackInfoIndex + 1
                    end
                end
                if #registry == 0 then
                    self.callbackRegistry[eventName] = nil
                end
            end
            dirtyEvents[#dirtyEvents] = nil
        end
    end
end

function JO_CallbackObjectMixin:ClearCallbackRegistry()
    if self.callbackRegistry then
        for eventName, _ in pairs(self.callbackRegistry) do
            self:UnregisterAllCallbacks(eventName)
        end
    end
end

function JO_CallbackObjectMixin:GetFireCallbackDepth()
    return self.fireCallbackDepth or 0
end

function JO_CallbackObjectMixin:GetDirtyEvents()
    if not self.dirtyEvents then
        self.dirtyEvents = {}
    end
    return self.dirtyEvents
end

JO_CallbackObject = {}
zo_mixin(JO_CallbackObject, JO_Object)
zo_mixin(JO_CallbackObject, JO_CallbackObjectMixin)
JO_CallbackObject.__index = JO_CallbackObject

JO_InitializingCallbackObject = {}
zo_mixin(JO_InitializingCallbackObject, JO_InitializingObject)
zo_mixin(JO_InitializingCallbackObject, JO_CallbackObjectMixin)
JO_InitializingCallbackObject.__index = JO_InitializingCallbackObject

--[[
/script TestObject = JO_Object:Subclass()


]]
