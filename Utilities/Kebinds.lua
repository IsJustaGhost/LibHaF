local Lib = LibJoCommon

---------------------------------------------------------------------------------------------------------------
-- 
---------------------------------------------------------------------------------------------------------------

local function defaultIsDataHeader(data)
    return data.isHeader or data.header
end
	
local function bindKey(layerIndex, categoryIndex, actionIndex, bindingIndex, key)
	CallSecureProtected('BindKeyToAction', layerIndex, categoryIndex, actionIndex, bindingIndex, key, KEY_INVALID, KEY_INVALID, KEY_INVALID, KEY_INVALID)
end

do
	local dialogueTrigerData = {
		['DIALOG_RIGHT_TRIGGER'] = 138,
		['DIALOG_LEFT_TRIGGER'] = 137,
	}
	
	local layerIndex = 5
	local categoryIndex = 1
	local _, numActions = GetActionLayerCategoryInfo(layerIndex, categoryIndex)
	for actionIndex = 1, numActions do
		local actionName = GetActionInfo(layerIndex, categoryIndex, actionIndex)
		local key = dialogueTrigerData[actionName]
		if key ~= nil then
			bindKey(layerIndex, categoryIndex, actionIndex, 1, key)
		end
	end
end

local function createListTriggerKeybindDescriptors(optionalHeaderComparator)
    local leftTrigger = {
		--Ethereal binds show no text, the name field is used to help identify the keybind when debugging. This text does not have to be localized.
		name = "Left Trigger",
		keybind = "DIALOG_LEFT_TRIGGER",
	--	handlesKeyUp = true,
		ethereal = true,
		callback = function(dialogue, onUp)
			local list = dialogue.entryList --need a local copy so the original isn't overwritten on subsequent calls
			if type(list) == "function" then
				list = list()
			end
			
			if list:IsActive() and not list:IsEmpty() and not list:SetPreviousSelectedDataByEval(optionalHeaderComparator or defaultIsDataHeader, ZO_PARAMETRIC_MOVEMENT_TYPES.JUMP_PREVIOUS) then
				list:SetFirstIndexSelected(ZO_PARAMETRIC_MOVEMENT_TYPES.JUMP_PREVIOUS)
			end
		end,
    }

    local rightTrigger = {
			--Ethereal binds show no text, the name field is used to help identify the keybind when debugging. This text does not have to be localized.
			name = "Right Trigger",
			keybind = "DIALOG_RIGHT_TRIGGER",
		--	handlesKeyUp = true,
			ethereal = true,
			callback = function(dialogue, onUp)
				local list = dialogue.entryList --need a local copy so the original isn't overwritten on subsequent calls
				if type(list) == "function" then
					list = list()
				end
				
				if list:IsActive() and not list:IsEmpty() and not list:SetNextSelectedDataByEval(optionalHeaderComparator or defaultIsDataHeader, ZO_PARAMETRIC_MOVEMENT_TYPES.JUMP_NEXT) then
					list:SetLastIndexSelected(ZO_PARAMETRIC_MOVEMENT_TYPES.JUMP_NEXT)
				end
			end,
    }

    return leftTrigger, rightTrigger
end

function JO_Gamepad_AddDialogueListTriggerKeybindDescriptors(dialogueName, optionalHeaderComparator)
	local dialogue = ESO_Dialogs[dialogueName]
	if dialogue then
		local leftTrigger, rightTrigger = createListTriggerKeybindDescriptors(optionalHeaderComparator)
		
		local buttons = dialogue.buttons or {}
		table.insert(buttons, leftTrigger)
		table.insert(buttons, rightTrigger)
		
		dialogue.buttons = buttons
	end
end

