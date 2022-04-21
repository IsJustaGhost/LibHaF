local Lib = LibJoCommon
local createLogger = function(className, classObject, levelOverride) Lib.CreateLogger(Lib, className, classObject, levelOverride) end

---------------------------------------------------------------------------------------------------------------
-- JO_CallLater and JO_CallLaterOnScene and jo_callLaterOnNextScene
---------------------------------------------------------------------------------------------------------------
--[[ About:
	These functions will not stack the callback if called several times in a row.
	
	JO_CallLater is similar to zo_callLater, but can be ran several times in a row without stacking.

	JO_CallLaterOnScene is useful for situations where you want it to run after a specified scene is shown.

	JO_CallLaterOnNextScene is useful for situations where you want it to run after scenes change.


	JO_CallLater('_test', function() end, 100)
	JO_CallLaterOnScene(addon.name .. '_test', 'hud', function() end)
	JO_CallLaterOnNextScene(addon.name .. '_test', function() end)
]]

local logger = {}
createLogger('CallLater', logger)

jo_callLater = function(id, func, ms, ...)
	local params = {...}
	if ms == nil then ms = 0 end
	local name = "JO_CallLater_".. id
	EVENT_MANAGER:UnregisterForUpdate(name)
	
	EVENT_MANAGER:RegisterForUpdate(name, ms,
		function()
			EVENT_MANAGER:UnregisterForUpdate(name)
			func(unpack(params))
		end)
	return id
end

jo_callLaterOnScene = function(id, sceneName, func, ...)
	local params = {...}
	if not sceneName or type(sceneName) ~= 'string' then return end
	
	local updateName = "JO_CallLaterOnScene_" .. id
	EVENT_MANAGER:UnregisterForUpdate(updateName)
	
	local function OnUpdateHandler()
		if SCENE_MANAGER:GetCurrentSceneName() == sceneName then
			EVENT_MANAGER:UnregisterForUpdate(updateName)
			func(unpack(params))
		end
	end
	
	EVENT_MANAGER:RegisterForUpdate(updateName, 100, OnUpdateHandler)
end

jo_callLaterOnNextScene = function(id, func, ...)
	local params = {...}
	local sceneName = SCENE_MANAGER:GetCurrentSceneName()
	local updateName = "JO_CallLaterOnNextScene_" .. id
	EVENT_MANAGER:UnregisterForUpdate(updateName)
	
	local function OnUpdateHandler()
		if SCENE_MANAGER:GetCurrentSceneName() ~= sceneName then
			EVENT_MANAGER:UnregisterForUpdate(updateName)
			func(unpack(params))
		end
	end
	
	EVENT_MANAGER:RegisterForUpdate(updateName, 100, OnUpdateHandler)
end
