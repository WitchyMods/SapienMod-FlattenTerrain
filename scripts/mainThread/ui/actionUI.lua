local plan = mjrequire "common/plan"
local material = mjrequire "common/material"
local model = mjrequire "common/model"
local constructableUIHelper = mjrequire "mainThread/ui/constructableUIHelper"
local uiCommon = mjrequire "mainThread/ui/uiCommon/uiCommon"
local audio = mjrequire "mainThread/audio"
local logicInterface = mjrequire "mainThread/logicInterface"

local mod = {}

local actionUI = nil
local world = nil
local gameUI = nil
local hubUI = nil

local vertIDs = nil

local function override_init()
    local super = actionUI.init
    actionUI.init = function(actionUI_, gameUI_, hubUI_, world_)
        mod:init(super, gameUI_, hubUI_, world_)
    end
end

local function override_show()
    local super = actionUI.show
    actionUI.show = function(actionUI_)
        mod:show(super)
    end
end

function mod:onload(actionUI_)
    actionUI = actionUI_

    override_init()
    override_show()
end

local function onFlattenClick(planInfo)
    local objectOrVertIDs = {}
    for i,vertInfo in ipairs(actionUI.selectedVertInfos) do
        objectOrVertIDs[i] = vertInfo.uniqueID
    end

    local constructableTypeIndex = constructableUIHelper:getTerrainFillConstructableTypeIndex()

    local addInfo = {
        planTypeIndex = planInfo.planTypeIndex,
        objectTypeIndex = planInfo.objectTypeIndex,
        objectOrVertIDs = objectOrVertIDs,
        baseVertID = actionUI.baseVert.uniqueID,
        fillConstructableTypeIndex = constructableTypeIndex,
        fillRestrictedResourceObjectTypes = world:getConstructableRestrictedObjectTypes(constructableTypeIndex, false),
        fillRestrictedToolObjectTypes = world:getConstructableRestrictedObjectTypes(constructableTypeIndex, true)
    }

    logicInterface:callServerFunction("addPlans", addInfo)

end

local function deregisterStateChanges()
    if vertIDs then
        logicInterface:deregisterFunctionForVertStateChanges(vertIDs, logicInterface.stateChangeRegistrationGroups.actionUI)
    end
end

local function animateOutForOptionSelected(optionIndex, animateOutCompletionFuntionOrNil)
    deregisterStateChanges()
    gameUI:stopFollowingObject()
    hubUI:hideInspectUI()
end

local function updateButtons()
	local wheel = actionUI.wheels[actionUI.currentWheelIndex]

	for segmentIndex = 1, actionUI.currentWheelIndex do
        local segment = wheel.segments[segmentIndex]
        local segmentTable = segment.userData

        if segmentTable.planTypeIndex == plan.types.flatten.index then
            if #vertIDs == 1 then
                segmentTable.disabled = true 
                
                local materialIndex = material.types.disabledText.index
                segmentTable.icon:setModel(model:modelIndexForName(plan.types.flatten.icon), { default = materialIndex })
                segmentTable.clickFunction = nil
            else
                segmentTable.clickFunction = function(wasQuickSwipeAction) 
                    audio:playUISound(uiCommon.orderSoundFile)
                    onFlattenClick(segmentTable.planInfo)
                    animateOutForOptionSelected(segmentIndex, nil)
                end
            end                
        end
    end
end

local function registerStateChanges()
    local super_registeredStateChangeFunction = logicInterface:getRegisteredVertStateChangeFunctionsByIdAndGroup(vertIDs[1], logicInterface.stateChangeRegistrationGroups.actionUI)

    if super_registeredStateChangeFunction then
        local newRegisteredStateChangeFunction = function(retrievedVertResponse)
            super_registeredStateChangeFunction(retrievedVertResponse)
            updateButtons()
        end

        logicInterface:registerFunctionForVertStateChanges(vertIDs, logicInterface.stateChangeRegistrationGroups.actionUI, newRegisteredStateChangeFunction)
    end 
end

function mod:init(super, gameUI_, hubUI_, world_)
    super(actionUI, gameUI_, hubUI_, world_)

    world = world_
    hubUI = hubUI_
    gameUI = gameUI_
end

function mod:show(super)
	super(actionUI)

    if actionUI.selectedVertInfos then        
        vertIDs = {}
        for i,vertInfo in ipairs(actionUI.selectedVertInfos) do
            vertIDs[i] = vertInfo.uniqueID
        end

        updateButtons()
        registerStateChanges()
    end
end

return mod