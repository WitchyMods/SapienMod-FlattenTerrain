local planMarkersUI = mjrequire "mainThread/ui/planMarkersUI"

local mod = {}

local logicInterface = nil

local bridge = nil

local registeredVertStateChangeFunctionsByIdAndGroup = {}

local function override_setBridge()
    local super = logicInterface.setBridge
    logicInterface.setBridge = function(logicInterface_, bridge_)
        mod:setBridge(super, bridge_)
    end
end
    
local function override_registerFunctionForVertStateChanges()
    local super = logicInterface.registerFunctionForVertStateChanges
    logicInterface.registerFunctionForVertStateChanges = function(logicInterface_, vertIDs, registrationGroupID, func)
        mod:registerFunctionForVertStateChanges(super, vertIDs, registrationGroupID, func)
    end
end

local function override_deregisterFunctionForVertStateChanges()
    local super = logicInterface.deregisterFunctionForVertStateChanges
    logicInterface.deregisterFunctionForVertStateChanges = function(logicInterface_, vertIDs, registrationGroupID)
        mod:deregisterFunctionForVertStateChanges(super, vertIDs, registrationGroupID)
    end
end

local function add_getRegisteredVertStateChangeFunctionsByIdAndGroup()
    logicInterface.getRegisteredVertStateChangeFunctionsByIdAndGroup = mod.getRegisteredVertStateChangeFunctionsByIdAndGroup
end

function mod:onload(logicInterface_)
    logicInterface = logicInterface_

    override_setBridge()
    override_registerFunctionForVertStateChanges()
    override_deregisterFunctionForVertStateChanges()
    add_getRegisteredVertStateChangeFunctionsByIdAndGroup()
end

function mod:setBridge(super, bridge_)
    bridge = bridge_

    super(logicInterface, bridge)

    bridge:registerMainThreadFunction("registeredVertServerStateChanged", function(vertInfo)
        local funcsForVert = registeredVertStateChangeFunctionsByIdAndGroup[vertInfo.uniqueID]
        if funcsForVert then
            for groupID,registeredVertStateChangeFunction in pairs(funcsForVert) do 
                registeredVertStateChangeFunction(vertInfo)
            end
        end
    end)
end

function mod:registerFunctionForVertStateChanges(super, vertIDs, registrationGroupID, func)
    for i, vertID in ipairs(vertIDs) do
        local funcsForVert = registeredVertStateChangeFunctionsByIdAndGroup[vertID]
        if not funcsForVert then 
            funcsForVert = {}
            registeredVertStateChangeFunctionsByIdAndGroup[vertID] = funcsForVert
        end

        funcsForVert[registrationGroupID] = func
    end

    bridge:callLogicThreadFunction("registerServerStateChangeMainThreadNotificationsForVerts", vertIDs)
end

function mod:deregisterFunctionForVertStateChanges(super, vertIDs, registrationGroupID)
    local vertIdsWithNoCallbacks = {}
    for i, vertID in ipairs(vertIDs) do
        local funcsForVert = registeredVertStateChangeFunctionsByIdAndGroup[vertID]
        if funcsForVert then 
            funcsForVert[registrationGroupID] = nil
        end
        if not next(funcsForVert) then
            table.insert(vertIdsWithNoCallbacks, vertID)
        end
    end

    bridge:callLogicThreadFunction("deregisterServerStateChangeMainThreadNotificationsForVerts", vertIdsWithNoCallbacks)
end

function mod:getRegisteredVertStateChangeFunctionsByIdAndGroup(vertID, registrationGroupID)
    local funcsForVert = registeredVertStateChangeFunctionsByIdAndGroup[vertID] 
    if funcsForVert then 
        return funcsForVert[registrationGroupID]
    end
    return nil
end

return mod