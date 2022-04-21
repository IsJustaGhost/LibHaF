local Lib = LibJoCommon

---------------------------------------------------------------------------------------------------------------
-- JO_UpdateBuffer, JO_UpdateBuffer_Simple
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
Lib:CreateLogger('UpdateBuffer', UpdateBuffer)

function UpdateBuffer:Initialize(id, func, enabled, delay)
	self.updateName = "JO_UpdateBuffer_" .. id
	
	UpdateBuffer:Info('UpdateBuffer:Initialize: updateName = %s', self.updateName)
	
	self.enabled = enabled == nil and true or enabled
	self:SetDelay(delay)
	
	self.CallbackFn = func
end

function UpdateBuffer:OnUpdate(...)
	local params = {...}
	EVENT_MANAGER:UnregisterForUpdate(self.updateName)
	
	local function OnUpdateHandler()
		UpdateBuffer:Debug('-- Fire: %s, Params = %s', self.updateName, params)
		EVENT_MANAGER:UnregisterForUpdate(self.updateName)
		self:CallbackFn(unpack(params))
	end
	
	local enabled = self.enabled
	
	UpdateBuffer:Debug('enabled type = %s', type(self.enabled))
	if type(self.enabled) == 'function' then
		enabled = self.enabled()
	end
	
	UpdateBuffer:Debug('UpdateBuffer:OnUpdate: %s, enabled = %s', self.updateName, enabled)
	
	if enabled then
		EVENT_MANAGER:RegisterForUpdate(self.updateName, self.delay, OnUpdateHandler)
	end
end

function UpdateBuffer:SetDelay(delay)
	delay = delay or 100
	self.delay = delay
end

function UpdateBuffer:SetEnabled(enabled)
	UpdateBuffer:Info('UpdateBuffer:SetEnabled: updateName = %s, enabled = %s', self.updateName, enabled)
	self.enabled = enabled
end

--[[ this isn't really needed. SetEnabled does the same thing. 
function UpdateBuffer:SetEnabledFunciton(enabledFn)
	self.enabled = enabledFn
end
]]

JO_UpdateBuffer = UpdateBuffer

function JO_UpdateBuffer_Simple(id, func, delay)
	local updateName = "JO_UpdateBuffer_Simple_" .. id
	
	delay = delay or 100
	
	return function(self, ...)
		local params = {...}
		EVENT_MANAGER:UnregisterForUpdate(updateName)
		
		local function OnUpdateHandler()
			EVENT_MANAGER:UnregisterForUpdate(updateName)
			func(unpack(params))
		end
		
		EVENT_MANAGER:RegisterForUpdate(updateName, delay, OnUpdateHandler)
	end
end
