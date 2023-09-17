local typeMaps = mjrequire "common/typeMaps"

local mod = {}

function mod:onload(plan)
	local flattenPlan = {
        key = "flatten",
        name = "Flatten",
        inProgress = "Flattening",
        icon = "icon_flatten", 
        skipFinalReachableCollisionAndVerticalityPathCheck = true,
        pathProximityDistance = mj:mToP(3.0),
        requiresLight = true,
        checkCanCompleteForRadialUI = true,
        modifiesTerrainHeight = true,
        priorityOffset = plan.mineChopPriorityOffset,
    }

    if not plan.types["flatten"] then
        typeMaps:insert("plan", plan.types, flattenPlan)
    end
end

return mod

