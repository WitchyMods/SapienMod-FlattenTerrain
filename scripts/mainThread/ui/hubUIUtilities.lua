local hubUIUtilities = nil

local mod = {}

local function override_getPlanProblemStrings()
	local super = hubUIUtilities.getPlanProblemStrings
	hubUIUtilities.getPlanProblemStrings = function(hubUIUtilities_, planStateOrInfo)
		return mod:getPlanProblemStrings(super, planStateOrInfo)
	end
end

function mod:onload(hubUIUtilities_)
	hubUIUtilities = hubUIUtilities_

	override_getPlanProblemStrings()
end

function mod:getPlanProblemStrings(super, planStateOrInfo)
	local result = super(hubUIUtilities, planStateOrInfo)

	if planStateOrInfo.isFlattenPlanBaseVert then
		table.insert(result, "Main vertex for flattening. No action necessary.")
	end

	return result
end

return mod