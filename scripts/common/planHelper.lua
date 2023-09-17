local locale = mjrequire "common/locale"
local terrainTypes = mjrequire "common/terrainTypes"
local research = mjrequire "common/research"
local skill = mjrequire "common/skill"
local plan = mjrequire "common/plan"
local tool = mjrequire "common/tool"

local mod = {}

local completedSkillsByTribeID = {}
local discoveriesByTribeID = {}

local planHelper = nil

local function override_updateCompletedSkillsForDiscoveriesChange()
    local super = planHelper.updateCompletedSkillsForDiscoveriesChange 
    planHelper.updateCompletedSkillsForDiscoveriesChange = function(planHelper_, tribeID)
        mod:updateCompletedSkillsForDiscoveriesChange(super, tribeID)
    end
end

local function override_setDiscoveriesForTribeID()
    local super = planHelper.setDiscoveriesForTribeID
    planHelper.setDiscoveriesForTribeID = function(planHelper_, tribeID, discoveries, craftableDiscoveries)
        mod:setDiscoveriesForTribeID(super, tribeID, discoveries, craftableDiscoveries)
    end
end

local function override_availablePlansForVertInfos()
    local super = planHelper.availablePlansForVertInfos
    planHelper.availablePlansForVertInfos = function(planHelper_, vertInfos, tribeID)
        return mod:availablePlansForVertInfos(super, vertInfos, tribeID)
    end
end

function mod:onload(planHelper_)
    planHelper = planHelper_

    override_updateCompletedSkillsForDiscoveriesChange()
    override_setDiscoveriesForTribeID()
    override_availablePlansForVertInfos()
end

function mod:updateCompletedSkillsForDiscoveriesChange(super, tribeID)
    super(planHelper, tribeID)

    for researchTypeIndex,discoveryInfo in pairs(discoveriesByTribeID[tribeID]) do
        if discoveryInfo.complete then
            local researchType = research.types[researchTypeIndex]
            if researchType then
                local skillTypeIndex = researchType.skillTypeIndex
                if skillTypeIndex then
                    completedSkillsByTribeID[tribeID][skillTypeIndex] = true
                end
            end
        end
    end
end

function mod:setDiscoveriesForTribeID(super, tribeID, discoveries, craftableDiscoveries)
    discoveriesByTribeID[tribeID] = discoveries
    completedSkillsByTribeID[tribeID] = {}

    super(planHelper, tribeID, discoveries, craftableDiscoveries)
end

function mod:availablePlansForVertInfos(super, vertInfos, tribeID)
	local plans = super(planHelper, vertInfos, tribeID)

    local hasDigDiscovery = false
    local hasMineDiscovery = false

    if completedSkillsByTribeID[tribeID] then
        if completedSkillsByTribeID[tribeID][skill.types.digging.index] then
            hasDigDiscovery = true
        end
        if completedSkillsByTribeID[tribeID][skill.types.mining.index] then
            hasMineDiscovery = true
        end
    end

    if not hasDigDiscovery or not hasMineDiscovery then
        return plans
    end

    local diggableVertexCount = 0
    local mineableVertexCount = 0
    local softChiselableVertexCount = 0
    local hardChiselableVertexCount = 0
    local clearableVertexCount = 0
    local fertilizeableVertexCount = 0

    for i,vertInfo in ipairs(vertInfos) do
        local variations = vertInfo.variations
        if variations then
            for terrainVariationTypeIndex,v in pairs(variations) do
                local terrainVariationType = terrainTypes.variations[terrainVariationTypeIndex]
                if terrainVariationType.canBeCleared then
                    clearableVertexCount = clearableVertexCount + 1
                    break
                end
            end
        end

        local terrainBaseType = terrainTypes.baseTypes[vertInfo.baseType]
        if terrainBaseType.requiresMining then
            mineableVertexCount = mineableVertexCount + 1
        else
            diggableVertexCount = diggableVertexCount + 1
        end

        if terrainBaseType.chiselOutputs then
            if terrainBaseType.isSoftRock then
                softChiselableVertexCount = softChiselableVertexCount + 1
            else
                hardChiselableVertexCount = hardChiselableVertexCount + 1
            end
        end

        if terrainBaseType.fertilizedTerrainTypeKey then
            fertilizeableVertexCount = fertilizeableVertexCount + 1
        end
    end

    local availablePlanCounts = {}
    local queuedPlanInfos = planHelper:getQueuedPlanInfos(vertInfos, tribeID, true)

    local clearPlanInfo = {
        planTypeIndex = plan.types.clear.index,
        requirements = {
            skill = skill.types.gathering.index,
        }
    }
    local clearHash = planHelper:getPlanHash(clearPlanInfo)
    availablePlanCounts[clearHash] = clearableVertexCount

    local digPlanInfo = {
        planTypeIndex = plan.types.dig.index,
        requirements = {
            toolTypeIndex = tool.types.dig.index,
            skill = skill.types.digging.index,
        },
    }
    local digHash = planHelper:getPlanHash(digPlanInfo)
    availablePlanCounts[digHash] = diggableVertexCount

    local fillPlanInfo = {
        planTypeIndex = plan.types.fill.index,
        allowsObjectTypeSelection = true,
        requirements = {
            skill = skill.types.digging.index,
        }
    }
    local fillHash = planHelper:getPlanHash(fillPlanInfo)
    availablePlanCounts[fillHash] = #vertInfos

    local fertilizePlanInfo = {
        planTypeIndex = plan.types.fertilize.index,
        requirements = {
            skill = skill.types.mulching.index,
        }
    }
    local fertilizeHash = planHelper:getPlanHash(fertilizePlanInfo)
    availablePlanCounts[fertilizeHash] = fertilizeableVertexCount
        
    local minePlanInfo = {
        planTypeIndex = plan.types.mine.index,
        requirements = {
            toolTypeIndex = tool.types.mine.index,
            skill = skill.types.mining.index,
        },
    }
    local mineHash = planHelper:getPlanHash(minePlanInfo)
    availablePlanCounts[mineHash] = mineableVertexCount

    local chiselToolTypeIndex = tool.types.hardChiselling.index
    if softChiselableVertexCount > 0 then
        chiselToolTypeIndex = tool.types.softChiselling.index
    end
        
    local chiselPlanInfo = {
        planTypeIndex = plan.types.chiselStone.index,
        requirements = {
            toolTypeIndex = chiselToolTypeIndex,
            skill = skill.types.chiselStone.index,
        },
    }
    local chiselHash = planHelper:getPlanHash(chiselPlanInfo)
    availablePlanCounts[chiselHash] = softChiselableVertexCount + hardChiselableVertexCount

    local flattenPlanInfo = {
        planTypeIndex = plan.types.flatten.index,
        digPlanRequirements = digPlanInfo.requirements,
        minePlanRequirements = minePlanInfo.requirements,
        fillPlanRequirements = fillPlanInfo.requirements,
    }
    local flattenHash = planHelper:getPlanHash(flattenPlanInfo)
    availablePlanCounts[flattenHash] = #vertInfos

    if queuedPlanInfos[digHash] then
        availablePlanCounts[fillHash] = availablePlanCounts[fillHash] - queuedPlanInfos[digHash].count
        availablePlanCounts[clearHash] = availablePlanCounts[clearHash] - queuedPlanInfos[digHash].count
        availablePlanCounts[fertilizeHash] = availablePlanCounts[fertilizeHash] - queuedPlanInfos[digHash].count
        availablePlanCounts[flattenHash] = 0
    end

    if queuedPlanInfos[fillHash] then
        availablePlanCounts[digHash] = availablePlanCounts[digHash] - queuedPlanInfos[fillHash].count
        availablePlanCounts[mineHash] = availablePlanCounts[mineHash] - queuedPlanInfos[fillHash].count
        availablePlanCounts[chiselHash] = availablePlanCounts[chiselHash] - queuedPlanInfos[fillHash].count
        availablePlanCounts[clearHash] = availablePlanCounts[clearHash] - queuedPlanInfos[fillHash].count
        availablePlanCounts[fertilizeHash] = availablePlanCounts[fertilizeHash] - queuedPlanInfos[fillHash].count
        availablePlanCounts[flattenHash] = 0
    end
        
    if queuedPlanInfos[clearHash] then
        availablePlanCounts[digHash] = availablePlanCounts[digHash] - queuedPlanInfos[clearHash].count
        availablePlanCounts[mineHash] = availablePlanCounts[mineHash] - queuedPlanInfos[clearHash].count
        availablePlanCounts[chiselHash] = availablePlanCounts[chiselHash] - queuedPlanInfos[clearHash].count
        availablePlanCounts[fillHash] = availablePlanCounts[fillHash] - queuedPlanInfos[clearHash].count
        availablePlanCounts[fertilizeHash] = availablePlanCounts[fertilizeHash] - queuedPlanInfos[clearHash].count
        availablePlanCounts[flattenHash] = availablePlanCounts[flattenHash] - queuedPlanInfos[clearHash].count
    end
        
    if queuedPlanInfos[mineHash] then
        availablePlanCounts[fillHash] = availablePlanCounts[fillHash] - queuedPlanInfos[mineHash].count
        availablePlanCounts[clearHash] = availablePlanCounts[clearHash] - queuedPlanInfos[mineHash].count
        availablePlanCounts[fertilizeHash] = availablePlanCounts[fertilizeHash] - queuedPlanInfos[mineHash].count
        availablePlanCounts[chiselHash] = availablePlanCounts[chiselHash] - queuedPlanInfos[mineHash].count
        availablePlanCounts[flattenHash] = 0
    end
        
    if queuedPlanInfos[chiselHash] then
        availablePlanCounts[fillHash] = availablePlanCounts[fillHash] - queuedPlanInfos[chiselHash].count
        availablePlanCounts[clearHash] = availablePlanCounts[clearHash] - queuedPlanInfos[chiselHash].count
        availablePlanCounts[fertilizeHash] = availablePlanCounts[fertilizeHash] - queuedPlanInfos[chiselHash].count
        availablePlanCounts[mineHash] = availablePlanCounts[mineHash] - queuedPlanInfos[chiselHash].count
        availablePlanCounts[flattenHash] = 0
    end
        
    if queuedPlanInfos[fertilizeHash] then
        availablePlanCounts[fillHash] = availablePlanCounts[fillHash] - queuedPlanInfos[fertilizeHash].count
        availablePlanCounts[clearHash] = availablePlanCounts[clearHash] - queuedPlanInfos[fertilizeHash].count
        availablePlanCounts[digHash] = availablePlanCounts[digHash] - queuedPlanInfos[fertilizeHash].count
        availablePlanCounts[mineHash] = availablePlanCounts[mineHash] - queuedPlanInfos[fertilizeHash].count
        availablePlanCounts[flattenHash] = availablePlanCounts[flattenHash] - queuedPlanInfos[fertilizeHash].count
    end

    if queuedPlanInfos[flattenHash] then
        availablePlanCounts[fillHash] = 0
        availablePlanCounts[clearHash] = availablePlanCounts[clearHash] - queuedPlanInfos[flattenHash].count
        availablePlanCounts[digHash] = 0
        availablePlanCounts[mineHash] = 0
        availablePlanCounts[flattenHash] = 0
    end

    local function addUnavailableReason(vertexCount, hash, planInfo)
        if vertexCount > 0 and availablePlanCounts[hash] == 0 then
            planInfo.unavailableReasonText = locale:get("ui_plan_unavailable_stopOrders")
        end
    end

    table.insert(plans, flattenPlanInfo)

    planHelper:addPlanExtraInfo(clearPlanInfo, queuedPlanInfos, availablePlanCounts)
    planHelper:addPlanExtraInfo(digPlanInfo, queuedPlanInfos, availablePlanCounts)
    planHelper:addPlanExtraInfo(fillPlanInfo, queuedPlanInfos, availablePlanCounts)
    planHelper:addPlanExtraInfo(minePlanInfo, queuedPlanInfos, availablePlanCounts)
    planHelper:addPlanExtraInfo(chiselPlanInfo, queuedPlanInfos, availablePlanCounts)
    planHelper:addPlanExtraInfo(fertilizePlanInfo, queuedPlanInfos, availablePlanCounts)
    planHelper:addPlanExtraInfo(flattenPlanInfo, queuedPlanInfos, availablePlanCounts)

    addUnavailableReason(clearableVertexCount, clearHash, clearPlanInfo)
    addUnavailableReason(diggableVertexCount, digHash, digPlanInfo)
    addUnavailableReason(#vertInfos, fillHash, fillPlanInfo)
    addUnavailableReason(fertilizeableVertexCount, fertilizeHash, fertilizePlanInfo)
    addUnavailableReason(mineableVertexCount, mineHash, minePlanInfo)
    addUnavailableReason(softChiselableVertexCount + hardChiselableVertexCount, chiselHash, chiselPlanInfo)
    addUnavailableReason(#vertInfos, flattenHash, flattenPlanInfo)

    return plans
end


return mod