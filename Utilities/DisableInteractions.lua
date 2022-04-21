local Lib = LibJoCommon
local createLogger = function(className, classObject, levelOverride) Lib.CreateLogger(Lib, className, classObject, levelOverride) end

local logger = {}
createLogger('Disable_Interaction', logger)

local lib_reticle = RETICLE
local lib_fishing_manager = FISHING_MANAGER
local lib_fishing_gamepad = FISHING_GAMEPAD
local lib_fishing_keyboard = FISHING_KEYBOARD

---------------------------------------------------------------------------------------------------------------
-- Modifications to allow disabling interactions
---------------------------------------------------------------------------------------------------------------
--[[ About:
	RETICLE:GetInteractPromptVisible and FISHING_MANAGER:StartInteraction are used to disable interactions.
	Here we use RETICLE.interactionDisabled to disable interaction.
	Set RETICLE.interactionDisabled = true to disable
	
	The following method may be used to disable interactions automatically without having to create additional hooks.
	RETICLE:RegisterActionDisabledFilter(addon.name, actionName, function(action, interactableName, currentFrameTimeSeconds) end)
	RETICLE:UnregisterActionDisabledFilter(addon.name, actionName)
	
	
	-- The register loop is used in "IsJusta Disable Actions While Moving"
	local actionsTable = {
		[GetString("SI_GAMECAMERAACTIONTYPE", 1)]	= 1,
		[GetString("SI_GAMECAMERAACTIONTYPE", 2)]	= 2,
	}

	for actionName in pairs(actionsTable) do
		RETICLE:RegisterActionDisabledFilter(addon.name, actionName, function(action, interactableName, currentFrameTimeSeconds)
			-- This first checks to see if the current action is on the list for being disabled based on savedVars and other factors.
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

function lib_reticle:GetInteractPromptVisible()
	-- disables interaction in gamepad mode and allows jumping
	if self.interactionDisabled then
		return false
	end
	return not self.interact:IsHidden()
end

function lib_fishing_manager:StartInteraction()
	--logger:Debug('function StartInteraction: RETICLE.interactionDisabled = %s', lib_reticle.interactionDisabled)
	if lib_reticle.interactionDisabled then
		-- disables interaction in keyboard mode
		-- returning true here will prevent GameCameraInteractStart() from firing
		return true
	end
	
	self.gamepad = IsInGamepadPreferredMode()
	if self.gamepad then
		return lib_fishing_gamepad:StartInteraction()
	else
		return lib_fishing_keyboard:StartInteraction()
	end
end

-- Experimental: can register filter functions used for disabling interactions, instead of custom hook functions.
-- Is currently in use by "IsJusta Disable Actions While Moving". May be in version > 1.4.2
-- This doesn't seem to be working properly with multiple filteres registered for same action. 
-- This may be due to TryHandlingInteraction fireing to quickly in sucsession.
---------------------------------------------------------------------------------------------------------------
lib_reticle.actionFilters = {}

function lib_reticle:SetInteractionDisabled(disabled)
	self.interactionDisabled = disabled
end

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

function lib_reticle:GetActionFilters(action)
	return self.actionFilters[action]
end

function lib_reticle:IsInteractionDisabled(action, interactableName, currentFrameTimeSeconds)
--	logger:Debug('function IsInteractionDisabled: action = %s, interactableName = %s, interactionBlocked = %s, interactionDisabled = %s', action, interactableName, self.interactionBlocked, self.interactionDisabled)

	--d( action, interactableName)
	
	if action == nil then return self.interactionDisabled end
	local actionFilters = self:GetActionFilters(action)
	
	if actionFilters then
		for registeredName, actionFilter in pairs(actionFilters) do
			logger:Debug('-- actionFilter: registeredName = %s, action = %s, Returns = %s', registeredName, action, actionFilter(action, interactableName, currentFrameTimeSeconds))
			if actionFilter(action, interactableName, currentFrameTimeSeconds) then
				return true
			end
		end
	end
	return false
end

JO_HOOK_MANAGER:RegisterForPostHook(Lib.name, lib_reticle, "TryHandlingInteraction", function(self, interactionPossible, currentFrameTimeSeconds)
	local action, interactableName = GetGameCameraInteractableActionInfo()
	
	if not interactionPossible then return end
	self.interactionDisabled = self:IsInteractionDisabled(action, interactableName, currentFrameTimeSeconds)
	if self.interactionDisabled and not self.interactionBlocked then
		self.interactionBlocked = self.interactionDisabled
	end
--	logger:Debug('self.interactionBlocked = %s', self.interactionBlocked)
end)
