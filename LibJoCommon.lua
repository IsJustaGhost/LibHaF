-- Lib jo Common

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

local LIB_IDENTIFIER, LIB_VERSION = "LibJoCommon", 01

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
lib.loggerLevelOverride = 'D'
lib.loggerEnabled = true

---------------------------------------------------------------------------------------------------------------
-- Internal
---------------------------------------------------------------------------------------------------------------
local internal = {}

---------------------------------------------------------------------------------------------------------------
-- Logger internal
---------------------------------------------------------------------------------------------------------------
local logger = {}

--[[
	expand table
	show types
]]

JO_LOGGER_OPTION_ENTRY_TYPES	= 1
JO_LOGGER_OPTION_EXPAND_TABLES	= 2

local FORMAT_AS_STRING = {
	[true] = '"%s"',
	[false] = '%s',
}

local function getFormattingForType(arg)
	return FORMAT_AS_STRING[type(arg) == 'string']
end

local function getTypeString(entryType, str)
	if entryType ~= 'table' then
		return 'type(' .. entryType .. ') ' .. tostring(str)
	end
	
	return str
end

local function fmtTableEntry(options, key, value, fmtString)
    local str = '[' .. getFormattingForType(key) .. ']'
	
	if options[JO_LOGGER_OPTION_ENTRY_TYPES] then
		str = getTypeString(type(value), str)
	end
	
	local str = string.format(str , key)
	local str = string.format(str .. ' = %s, ', getFormattingForType(value))
	
	return fmtString .. str
end

function logger.fmtTable(options, arg)
	local tbl, fmtString = {}, '[table] {'
	
	for k, v in pairs(arg) do
		fmtString = fmtTableEntry(options, k, v, fmtString)
		
    	
		if type(v) == 'table' then
			if options[JO_LOGGER_OPTION_EXPAND_TABLES] then
				v = logger.fmtTable(options, v)
			end
		end
	
		table.insert(tbl, tostring(v))
	end
	
	if #tbl > 0 then
		fmtString = fmtString:gsub(', $', '') .. '}'
	--	return logger.format(options, fmtString, unpack(tbl))
		return string.format(fmtString, unpack(tbl))
	end
	
	-- Table is empty.
	return logger.formatString(options, fmtString .. '%s}', '-empty-')
end

function logger.fmtArgs(options, ...)
	local g_strArgs = {}
	
	for i = 1, select("#", ...) do
		local currentArg = select(i, ...)
	
		local argType = type(currentArg)
		if argType == 'userdata' then 
			currentArg = currentArg.GetName and currentArg:GetName() or currentArg
		elseif argType == 'table' then
			currentArg = logger.fmtTable(options, currentArg)
			
		end
		
		table.insert(g_strArgs, tostring(currentArg))
	end
	return g_strArgs
end

function logger.formatString(options, fmtString, ...)
    fmtString = fmtString:gsub(', $', '')
	
	local g_strArgs = logger.fmtArgs(options, ...)

	if #g_strArgs == 0 then
		return tostring(fmtString)
	else
	    
		return string.format(fmtString, unpack(g_strArgs))
	end
end

function logger.format(options, fmtString, ...)
	if type(fmtString) == 'table' then
		return logger.fmtTable(options, fmtString)
    elseif type(fmtString) == 'number' then
		fmtString = tostring(fmtString)
		
    elseif type(fmtString) ~= 'string' then
		fmtString = logger.formatString('%s', fmtString)
	end

    return logger.formatString(options, fmtString, ...)
end

function logger:Create()
	return self
end
function logger:SetMinLevelOverride()
	-- Intentionally empty.
end
function logger:SetEnabled()
	-- Intentionally empty.
end

local logFunctionNames = {"Verbose", "Debug", "Info", "Warn", "Error"}
local logFunctions = {}

if LibDebugLogger then
	for _, logFunctionName in pairs(logFunctionNames) do
	
		logFunctions[logFunctionName] = function(self, ...)
			loggerOptions = self.logger.options
			local logString = logger.format(options, ...)
			
			return self.logger[logFunctionName](self.logger, logString)
		end
	end
else
	for _, logFunctionName in pairs(logFunctionNames) do
		logFunctions[logFunctionName] = function(...) end
	end
end

---------------------------------------------------------------------------------------------------------------
-- Debug Logger
---------------------------------------------------------------------------------------------------------------
function lib:CreateLogger(className, classObject, enabled, loggerLevelOverride)
	enabled = enabled or false
	loggerLevelOverride = loggerLevelOverride or self.loggerLevelOverride
	
	if not self.logger then
		if LibDebugLogger then
			self.logger = LibDebugLogger(className)
			lib.SetLogLevelOverride(self, loggerLevelOverride)
		else
			self.logger = logger
		end
		
		self.logger.options = {}
	else
		enabled = enabled or self.logger.enabled or false
		classObject.logger = self.logger:Create(className)
		classObject.logger:SetMinLevelOverride(loggerLevelOverride)
	end
	
	for logFunctionName, logFunction in pairs(logFunctions) do
		classObject[logFunctionName] = logFunction
	end
	
	classObject.logger:SetEnabled(enabled)
end

function lib:SetLogLevelOverride(loggerLevelOverride)
	self.logger:SetMinLevelOverride(loggerLevelOverride)
	self.loggerLevelOverride = loggerLevelOverride
end

function lib:SetLoggerOption(optionType, enable)
	self.logger.options[optionType] = enable
end

-- Create a logger for use by the library.
lib:CreateLogger('LibJoCommon_Logger', lib, lib.loggerEnabled, loggerLevelOverride)

--[[ Logger usage:
	Initialize the logger:
		local enabled = true
		local loggerLevelOverride = 'D'
		local addon = {name = 'Foo'}
		LibJoCommon.CreateLogger(addon, addon.name, addon, enabled, loggerLevelOverride)

		local addon = JO_Object()
		
		function addon:Initialize()
			self:CreateLogger(self.name, self, self.enabled, self.loggerLevelOverride)
		end

		addon.sub = {}
		local sub = addon.sub
		function sub:Initialize()
			self:CreateLogger('subLogger', sub)
		end
		

	Using the logger:
		-Accepted arguments-
			string, number, bool, userdata, table
			
		-Accepts standard string-
			self:Info('Test')
			
		-Accepts string formatting-
			self:Info('Test = %s, enabled = %s', arg, enabled)
			
			
			local tbl = {bar = true, 'foo'}
			self:Debug(tbl)
				returns formatted table as string
					"[table] {[1] = "foo", ["bar"] = true}"
		
			self:Debug('Test = %s, input = %s', true, tbl)
				returns formatted sting with formatted table as one of the one of the arguments
					"Test = true, input = [table] {[1] = "foo", ["bar"] = true}"


			Setting the logger options to show entry types each table entry will be preceded by the value's type.
			self:SetLoggerOption(JO_LOGGER_OPTION_ENTRY_TYPES, true)
			self:Debug('Test = %s, input = %s', true, tbl)
				"Test = true, input = [table] {type(string) [1] = "foo", type(boolean) ["bar"] = true}"
				
				
]]

---------------------------------------------------------------------------------------------------------------
-- Locals
---------------------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------------------
-- 
---------------------------------------------------------------------------------------------------------------

ZO_CreateStringId("SI_BINDING_NAME_DIALOG_LEFT_TRIGGER", "Left Trigger")
ZO_CreateStringId("SI_BINDING_NAME_DIALOG_RIGHT_TRIGGER", "Right Trigger")