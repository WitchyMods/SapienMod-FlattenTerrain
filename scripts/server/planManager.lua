local mjm = mjrequire "common/mjm"
local length = mjm.length

local terrain = mjrequire "server/serverTerrain"
local terrainTypes = mjrequire "common/terrainTypes"
local plan = mjrequire "common/plan"

local mod = {}

local planManager = nil
local serverGOM = nil

local function override_init()
    local super = planManager.init
    planManager.init = function(planManager_, serverGOM_, serverWorld_, serverSapien_, serverCraftArea_)
        mod:init(super, serverGOM_, serverWorld_, serverSapien_, serverCraftArea_)
    end
end

local function override_addPlans()
    local super = planManager.addPlans
    planManager.addPlans = function(planManager_, tribeID, userData)
        mod:addPlans(super, tribeID, userData)
    end
end

local function override_cancelPlans()
    local super = planManager.cancelPlans
    planManager.cancelPlans = function(planManager_, tribeID, userData)
        mod:cancelPlans(super, tribeID, userData)
    end
end

local function override_removePlanStateFromTerrainVertForTerrainModification()
    local super = planManager.removePlanStateFromTerrainVertForTerrainModification
    planManager.removePlanStateFromTerrainVertForTerrainModification = function(planManager_, objectOrVertID, planTypeIndex, tribeID, researchTypeIndex, isForCancel)
        mod:removePlanStateFromTerrainVertForTerrainModification(super, objectOrVertID, planTypeIndex, tribeID, researchTypeIndex, isForCancel)
    end
end

local function override_removeAllPlanStatesForObject()
    local super = planManager.removeAllPlanStatesForObject
    planManager.removeAllPlanStatesForObject = function(planManager_, planObject, sharedState, tribeIDOrNilForAll, isForCancel)
        mod:removeAllPlanStatesForObject(super, planObject, sharedState, tribeIDOrNilForAll, isForCancel)
    end
end

local function override_cancelAllPlansForObject()
    local super = planManager.cancelAllPlansForObject
    planManager.cancelAllPlansForObject = function(planManager_, tribeID, objectID)
        mod:cancelAllPlansForObject(super, tribeID, objectID)
    end
end

local function override_prioritizePlans()
    local super = planManager.prioritizePlans
    planManager.prioritizePlans = function(planManager_, tribeID, userData)
        mod:prioritizePlans(super, tribeID, userData)
    end
end

local function override_deprioritizePlans()
    local super = planManager.deprioritizePlans
    planManager.deprioritizePlans = function(planManager_, tribeID, userData)
        mod:deprioritizePlans(super, tribeID, userData)
    end
end

function mod:onload(planManager_)
    planManager = planManager_

    override_init()
    override_addPlans()
    override_cancelPlans()
    override_removePlanStateFromTerrainVertForTerrainModification()
    override_removeAllPlanStatesForObject()
    override_cancelAllPlansForObject()
    override_prioritizePlans()
    override_deprioritizePlans()
end

local function getAltitude(vertInfo)
    local altitudeMeters = mj:pToM(length(vertInfo.pos) - 1.0) - 0.5
	local altitudeMetersRounded = nil
	if altitudeMeters > 0 then
		altitudeMetersRounded = math.floor(altitudeMeters + 1.0)
	else
		altitudeMetersRounded = math.ceil(altitudeMeters)
	end

    return altitudeMetersRounded
end

local function getPlanObject(planObjectID, vert)
    local planObject = serverGOM:getObjectWithID(planObjectID)
    if not planObject then
        terrain:loadArea(vert.normalizedVert) --added in 0.3.6
        planObject = serverGOM:getObjectWithID(planObjectID)
        if not planObject then
            mj:error("planManager:getPlanObject couldn't load plan object for terrain modification")
        end
    end

    return planObject
end

local function getPlanObjectForVertID(vertID, tribeID)
    local vert = terrain:getVertWithID(vertID)
    local planObjectID = serverGOM:getOrCreateObjectIDForTerrainModificationForVertex(vert, tribeID)
    return getPlanObject(planObjectID, vert)
end

local function getAllVertInfosFromVertID(vertID, tribeID)
    local result = {}

    result.vert = terrain:getVertWithID(vertID)
    result.vertInfo = terrain:retrieveVertInfo(vertID)

    local planObjectID = serverGOM:getOrCreateObjectIDForTerrainModificationForVertex(result.vert, tribeID)
                
    result.planObject = getPlanObject(planObjectID, result.vert)    

    return result
end

local function updateFlattenPlanForBaseVertex(baseVertID, tribeID, vertIDToRemove)
    local planObject = getPlanObjectForVertID(baseVertID, tribeID)

    if not planObject then return end

    local objectState = planObject.sharedState

    if not objectState.flattenSettings then -- shouldn't happen but will prevent crashes
        return
    end

    local affectedVertIDs = objectState.flattenSettings.affectedVertIDs
    
    for index, vertID in ipairs(affectedVertIDs) do
        if vertID == vertIDToRemove then
            table.remove(affectedVertIDs, index)
            break
        end
    end

    if not next(affectedVertIDs) then
        planManager:cancelPlans(tribeID, { planTypeIndex = plan.types.flatten.index, objectOrVertIDs = { baseVertID }}) 
    else
        objectState:set("flattenSettings", "affectedVertIDs", affectedVertIDs)
    end
end

local function updateVertexForFlattenPlan(vertID, tribeID, baseVertID)
    local vert = getAllVertInfosFromVertID(vertID, tribeID)
    local baseVertPlanObject = getPlanObjectForVertID(baseVertID, tribeID)

    if not vert.planObject or not baseVertPlanObject then return end

    local flattenSettings = baseVertPlanObject.sharedState.flattenSettings

    local objectState = vert.planObject.sharedState

    if not flattenSettings then -- for some reason the flatten plan was removed but this child vertex still contains flags
        objectState:remove("flattenPlanBaseVertID")
        return
    end

    local altitude = getAltitude(vert.vertInfo)

    -- if now at the correct altitude, we update the parent
    if altitude == flattenSettings.targetAltitude then
        objectState:remove("flattenPlanBaseVertID")
        updateFlattenPlanForBaseVertex(baseVertID, tribeID, vertID)
    else
        local requiredTool = nil
        local requiredSkill = nil 
        local constructableTypeIndex = nil 
        local restrictedResourceObjectTypes = nil
        local restrictedToolObjectTypes = nil
        local planTypeIndexToAdd = nil

        if altitude < flattenSettings.targetAltitude  then
            --needs to fill
            planTypeIndexToAdd = plan.types.fill.index
            constructableTypeIndex = flattenSettings.fillConstructableTypeIndex
            restrictedResourceObjectTypes = flattenSettings.fillRestrictedResourceObjectTypes
            restrictedToolObjectTypes = flattenSettings.fillRestrictedToolObjectTypes
        else
            local terrainBaseType = terrainTypes.baseTypes[vert.vertInfo.baseType]
            if terrainBaseType.requiresMining then
                --needs to mine
                planTypeIndexToAdd = plan.types.mine.index
                    
            else
                --needs to dig
                planTypeIndexToAdd = plan.types.dig.index
            end
        end

        local userData = {
            planTypeIndex = planTypeIndexToAdd,
            objectOrVertIDs = {vertID},
            baseVertID = {vertID},
            constructableTypeIndex = constructableTypeIndex, 
            restrictedResourceObjectTypes = restrictedResourceObjectTypes, 
            restrictedToolObjectTypes = restrictedToolObjectTypes,
        }

        local existingPlan = planManager:getPlanStateForObject(vert.planObject, planTypeIndexToAdd, nil, nil, tribeID, nil)

        if not existingPlan then
            --mj:log("updateVertexForFlattenPlan, adding plan for: ", vertID)
            planManager:addPlans(tribeID, userData)      
        end
    end
end

function mod:init(super, serverGOM_, serverWorld_, serverSapien_, serverCraftArea_)
    super(planManager, serverGOM_, serverWorld_, serverSapien_, serverCraftArea_)

    serverGOM = serverGOM_
end

function mod:addPlans(super, tribeID, userData)
    --mj:log("Adding plans:", userData)

    if userData.planTypeIndex == plan.types.flatten.index then
        if userData then
            local baseVertInfo = terrain:retrieveVertInfo(userData.baseVertID)
            local targetAltitude = getAltitude(baseVertInfo)

            local vertsToFill = {}
            local vertsToDig = {}
            local vertsToMine = {}

            local flattenSettings = {
                fillConstructableTypeIndex = userData.fillConstructableTypeIndex, 
                fillRestrictedResourceObjectTypes = userData.fillRestrictedResourceObjectTypes, 
                fillRestrictedToolObjectTypes = userData.fillRestrictedToolObjectTypes, 
                targetAltitude = targetAltitude,
                affectedVertIDs = {}
            }

            -- we load all verts and filter out those that are already at the correct altitude
            for i, vertID in ipairs(userData.objectOrVertIDs) do
                local vert = getAllVertInfosFromVertID(vertID, tribeID)
                local vertInfo = vert.vertInfo
                local planObject = vert.planObject                
                
                if not planObject then return end 

                local altitude = getAltitude(vertInfo)

                if altitude ~= targetAltitude then
                    local objectState = planObject.sharedState
                    objectState:set("flattenPlanBaseVertID", userData.baseVertID)
                    table.insert(flattenSettings.affectedVertIDs, vertID)

                    if altitude < targetAltitude then
                        table.insert(vertsToFill, vertID)
                    else
                        local terrainBaseType = terrainTypes.baseTypes[vertInfo.baseType]
                        if terrainBaseType.requiresMining then
                            table.insert(vertsToMine, vertID)
                    
                        else
                            table.insert(vertsToDig, vertID)
                        end
                    end
                end
            end

            if not next(flattenSettings.affectedVertIDs) then return end

            if next(vertsToDig) then
                planManager:addTerrainModificationPlan(tribeID, plan.types.dig.index, vertsToDig, nil, nil, nil, nil, nil, nil, nil)
            end

            if next(vertsToMine) then
                planManager:addTerrainModificationPlan(tribeID, plan.types.mine.index, vertsToMine, nil, nil, nil, nil, nil, nil, nil)
            end

            if next(vertsToFill) then
                planManager:addTerrainModificationPlan(tribeID, plan.types.fill.index, vertsToFill, userData.fillConstructableTypeIndex, nil, userData.fillRestrictedResourceObjectTypes, userData.fillRestrictedToolObjectTypes, nil, nil, nil)
            end
            
            -- call the vanilla code to add the planState which we will modify after
            -- we do so because of the local functions are important and I don't feel like copying them all
            super(planManager, tribeID, { planTypeIndex = plan.types.flatten.index, objectOrVertIDs = { userData.baseVertID } })

            local baseVertPlanObject = getPlanObjectForVertID(userData.baseVertID, tribeID)

            local baseVertObjectState = baseVertPlanObject.sharedState
            baseVertObjectState:set("flattenSettings", flattenSettings)

            for planStateIndex, planState in ipairs(baseVertObjectState.planStates[tribeID]) do
                if planState.planTypeIndex == plan.types.flatten.index then
                    baseVertObjectState:set("planStates", tribeID, planStateIndex, "isFlattenPlanBaseVert", true) -- can't complete reason
                    baseVertObjectState:set("planStates", tribeID, planStateIndex, "canComplete", false) -- mark it as can't complete so the sapiens don't do anyting to it
                end
            end
        end
    else
        super(planManager, tribeID, userData)
    end
end

function mod:cancelPlans(super, tribeID, userData)
    --mj:log("cancelPlans ", userData)
    if userData then
        local planTypeIndex = userData.planTypeIndex
        if userData.objectOrVertIDs and ( planTypeIndex == plan.types.dig.index or planTypeIndex == plan.types.mine.index or planTypeIndex == plan.types.fill.index) then
            for i,objectOrVertID in ipairs(userData.objectOrVertIDs) do
                if objectOrVertID then
                    
                    local object = serverGOM:getObjectWithID(objectOrVertID)

                    if object then
                        mj:error("FlattenTerrain mod->planManager:cancelPlans found an object for a terrain modification plan")
                    else
                        planManager:removePlanStateFromTerrainVertForTerrainModification(objectOrVertID, planTypeIndex, tribeID, userData.researchTypeIndex, true)
                    end
                end
            end

            super(planManager, tribeID, {}) -- call the super so it calls it local function "updatePlansForFollowerOrOrderCountChange"
        else
            super(planManager, tribeID, userData)
        end
    end
end

local function checkFlattenPlanPriority(baseVertObject, tribeID)
    local flattenPlanState = planManager:getPlanStateForObject(baseVertObject, plan.types.flatten.index, nil, nil, tribeID, nil)

    if flattenPlanState and flattenPlanState.manuallyPrioritized then
        local nonPrioritzedCount = 0 
        local IDsToPrioritize = {}

        for i, vertID in ipairs(baseVertObject.sharedState.flattenSettings.affectedVertIDs) do
            local isPrioritized = false
            local planObject = getPlanObjectForVertID(vertID)

            if planObject.sharedState.planStates and planObject.sharedState.planStates[tribeID] then
                for k, planState in ipairs(planObject.sharedState.planStates[tribeID]) do
                    if planState.manuallyPrioritized then
                        isPrioritized = true
                    else
                        if not IDsToPrioritize[planState.planTypeIndex] then
                            IDsToPrioritize[planState.planTypeIndex] = {}
                        end

                        table.insert(IDsToPrioritize[planState.planTypeIndex], vertID)
                    end
                end

                if not isPrioritized then
                    nonPrioritzedCount = nonPrioritzedCount + 1
                end
            end
        end

        if nonPrioritzedCount == #baseVertObject.sharedState.flattenSettings.affectedVertIDs then
            for planTypeIndex, vertIDs in pairs(IDsToPrioritize) do
                planManager:prioritizePlans(tribeID, { planTypeIndex = planTypeIndex, objectOrVertIDs = vertIDs})
            end
        end
    end
end

local function cancelOrCompletePlansForFlattening(planObject, objectState, tribeID, isForCancel)
    --mj:log("cancelOrCompletePlansForFlattening for: ", objectState.vertID)

    local baseVertID = objectState.flattenPlanBaseVertID 

    if baseVertID then 
        local baseVertObject = getPlanObjectForVertID(baseVertID, tribeID)
        local vertID = objectState.vertID

        if isForCancel then
            objectState:remove("flattenPlanBaseVertID")
            updateFlattenPlanForBaseVertex(baseVertID, tribeID, vertID)                
        else
            updateVertexForFlattenPlan(vertID, tribeID, baseVertID)
            checkFlattenPlanPriority(baseVertObject, tribeID)
        end
    end

    if objectState.flattenActionCompleted then --old flag I was using in version 1.0.0
        objectState:remove("flattenActionCompleted")
    end

    if objectState.flattenSettings then
        local lastChildVertID = nil
        local index = 1
        while objectState.flattenSettings and objectState.flattenSettings.affectedVertIDs[index] do
            local childVertID = objectState.flattenSettings.affectedVertIDs[index]

            if lastChildVertID == childVertID then
                mj:warn("Stuck in infinite loop")
                index = index + 1 -- we skip the vertices we couldn't remove for some reason
            end

            lastChildVertID = childVertID
            planManager:cancelAllPlansForVert(tribeID, childVertID)
        end

        objectState:remove("flattenSettings")
    end
end

function mod:removePlanStateFromTerrainVertForTerrainModification(super, objectOrVertID, planTypeIndex, tribeID, researchTypeIndex, isForCancel)
    --mj:log("removePlanStateFromTerrainVertForTerrainModification for: ", objectOrVertID, " isForCancel: ", isForCancel)
    local planObject = getPlanObjectForVertID(objectOrVertID, tribeID)
    local objectState = planObject.sharedState

    super(planManager, objectOrVertID, planTypeIndex, tribeID, researchTypeIndex)

    cancelOrCompletePlansForFlattening(planObject, objectState, tribeID, isForCancel)
end

function mod:removeAllPlanStatesForObject(super, planObject, sharedState, tribeIDOrNilForAll, isForCancel)
    --mj:log("removeAllPlanStatesForObject for: ", sharedState.vertID, " isForCancel: ", isForCancel)
    super(planManager, planObject, sharedState, tribeIDOrNilForAll)

    if isForCancel then -- removePlanStateFromTerrainVertForTerrainModification already calls it
        cancelOrCompletePlansForFlattening(planObject, sharedState, tribeIDOrNilForAll, isForCancel)
    end
end

function mod:cancelAllPlansForObject(super, tribeID, objectID)
    --mj:log("cancelAllPlansForObject")
    local object = serverGOM:getObjectWithID(objectID)
    if object then
        local sharedState = object.sharedState
        local planStatesByTribeID = sharedState.planStates
        if planStatesByTribeID then
            local allRemovedPlanTypeIndexes = {}
            local planStates = planStatesByTribeID[tribeID]
            for i,thisPlanState in ipairs(planStates) do
                table.insert(allRemovedPlanTypeIndexes, thisPlanState.planTypeIndex)
            end

            planManager:removeAllPlanStatesForObject(object, object.sharedState, tribeID, true)
                
            for i,planTypeIndex in ipairs(allRemovedPlanTypeIndexes) do
                serverGOM:planWasCancelledForObject(object, planTypeIndex, tribeID)
            end
        end
    end

    super(self, tribeID, objectID) -- we call the super so it calls its local function updatePlansForFollowerOrOrderCountChange
end

local function updatePriorityForFlattenPlan(super, tribeID, userData)
    super(planManager,  tribeID, userData)

    if userData and userData.objectOrVertIDs and userData.planTypeIndex == plan.types.flatten.index then
        for k, baseVertID in ipairs(userData.objectOrVertIDs) do
            local baseVertPlanObject = getPlanObjectForVertID(baseVertID)

            local IDsToPrioritize = {}
            for i, vertID in ipairs(baseVertPlanObject.sharedState.flattenSettings.affectedVertIDs) do
                local planObject = getPlanObjectForVertID(vertID)
                for p, planState in ipairs(planObject.sharedState.planStates[tribeID]) do
                    if not IDsToPrioritize[planState.planTypeIndex] then
                        IDsToPrioritize[planState.planTypeIndex] = {}
                    end

                    table.insert(IDsToPrioritize[planState.planTypeIndex], vertID)
                end
            end

            for planTypeIndex, vertIDs in pairs(IDsToPrioritize) do
                super(planManager, tribeID, { planTypeIndex = planTypeIndex, objectOrVertIDs = vertIDs })
            end
        end
    end
end

function mod:prioritizePlans(super, tribeID, userData)
    updatePriorityForFlattenPlan(super, tribeID, userData)
end

function mod:deprioritizePlans(super, tribeID, userData)
    updatePriorityForFlattenPlan(super, tribeID, userData)
end

return mod