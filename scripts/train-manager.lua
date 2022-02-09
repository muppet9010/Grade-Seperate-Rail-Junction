-- Has the main state tracking and handling logic for Managed Trains.

--[[
    Notes:
        - All of the ongoing or scheduled functions are protected against an invalid main train references by the train-cached-data module and its tracking of remvoed carriage's train Id's to global.trainManager.trainIdToManagedTrain and if found calling TrainManager.InvalidTrainFound().
--]]
--

local TrainManager = {}
local Utils = require("utility.utils")
local Events = require("utility.events")
local Logging = require("utility.logging")
local EventScheduler = require("utility.event-scheduler")
local PlayerContainer = require("scripts.player-container")
local Common = require("scripts.common")
local TrainManagerRemote = require("scripts.train-manager-remote")
local TunnelShared = require("scripts.tunnel-shared")
local TunnelSignalDirection, TunnelUsageChangeReason, TunnelUsageParts, TunnelUsageState, TunnelUsageAction = Common.TunnelSignalDirection, Common.TunnelUsageChangeReason, Common.TunnelUsageParts, Common.TunnelUsageState, Common.TunnelUsageAction

---@class ManagedTrain
---@field id Id @ uniqiue id of this managed train passing through the tunnel.
---@field tunnelUsageState TunnelUsageState
---@field skipTickCheck boolean @ If TRUE then the mod doesn't check the train this tick. Used to save checking which state function to call when there is none required for a large portion of the managed train's lifetime.
---@field trainTravelDirection defines.direction @ The cardinal direction the train is heading in. Uses the more granular defines.direction to allow natural comparison to Factorio entity direction attributes. Is the direction in relation to the entry portal. -- OVERHAUL - not used by anything any more other than in its populating function. Remove in any final tidyup if still not used.
---@field trainTravelOrientation TrainTravelOrientation @ The orientation of the trainTravelDirection.
---@field force LuaForce @ The force of the train carriages using the tunnel.
---@field trainCachedData TrainCachedData @ Ref to the cached train data. Its popualted as we need them. This is kept in sync with the entities of the pre-entering and leaving train's as the tunnelUsageState changes. This isn't directional and so if the lead carriage is needed it needs to be iterated the right way.
---@field trainFacingForwardsToCacheData? boolean|null @ If the train is moving in the forwards direction in relation to the cached train data. This accounts for if the train has been flipped and/or reversed in comparison to the cache.
---@field directionalTrainSpeedCalculationData Utils_TrainSpeedCalculationData @ The TrainSpeedCalculationData from the trainCachedData for the moving direction of this train right now. As the global trainCachedData has it for both facings. Updated during leaving when speed indicates direction change.
---@field forwardsDirectionalTrainSpeedCalculationDataUpdated boolean @ If the trains trainCachedData forwards directionalTrainSpeedCalculationData has been updated for this train usage. If not then it will need its fuel calculating on when next setting as the active directional data for this managed train.
---@field backwardsDirectionalTrainSpeedCalculationDataUpdated boolean @ If the trains trainCachedData backwards directionalTrainSpeedCalculationData has been updated for this train usage. If not then it will need its fuel calculating on when next setting as the active directional data for this managed train.
---
---@field approachingTrain? LuaTrain|null @ Ref to the approaching train. Cleared when the train enters the tunnel.
---@field approachingTrainId? Id|null @ The approachingTrain LuaTrain id. Cleared when the train enters the tunnel.
---@field approachingTrainMovingForwards? boolean|null @ If the train is moving forwards or backwards from its viewpoint. Cleared when the train enters the tunnel.
---@field approachingTrainExpectedSpeed? double|null @ The speed the train should have been going this tick while approaching the tunnel if it wasn't breaking. Cleared when the train enters the tunnel.
---@field approachingTrainReachedFullSpeed? boolean|null @ If the approaching train has reached its full speed already. Cleared when the train enters the tunnel.
---@field entranceSignalClosingCarriage LuaEntity @ A dummy carriage added on the entrance portal to keep its entry signals closed when the entering train is cloned to the leaving portal. Reference not cleared when train enters tunnel.
---
---@field portalTrackTrain? LuaTrain|null @ The train thats on the portal track and reserved the tunnel. Cleared when the train enters the tunnel.
---@field portalTrackTrainId? Id|null @ The LuaTrain ID of the portalTrackTrain. Cleared when the train enters the tunnel.
---@field portalTrackTrainInitiallyForwards? boolean|null @ If the train is moving forwards or backwards from its viewpoint when it initially triggers the portal track usage detection. Cleared when the train enters the tunnel.
---@field portalTrackTrainBySignal? boolean|null @ If we are tracking the train by the entrance entry signal or if we haven't got to that point yet. Cleared when the train enters the tunnel.
---
---@field traversalTravelDistance double|null @ The length of tunnel the train is travelling through on this traversal. This is the distance for the lead carriage from the entering position to the leaving position.
---@field traversalInitialDuration? Tick|null @ The number of tick's the train takes to traverse the tunnel.
---@field traversalArrivalTick? Tick|null @ The tick the train reaches the far end of the tunnel and is restarted.
---@field trainLeavingSpeedAbsolute? double|null @ The absolute speed the train will be set too at the moment it starts leaving the tunnel.
---@field traversalInitialSpeedAbsolute? double|null @ The absolute speed the train was going at when it started its traversal.
---@field dummyTrainCarriage? LuaEntity|null @ The dummy train carriage used to keep the train stop reservation alive while the main train is traversing the tunel.
---@field targetTrainStop? LuaEntity|null @ The target train stop entity of this train, needed in case the path gets lost as we only have the station name then. Used when checking bad train states and reversing trains.
---@field undergroundTrainHasPlayersRiding boolean @ If there are players riding in the underground train.
---
---@field leavingTrain? LuaTrain|null @ The train created leaving the tunnel on the world surface. This is populated when the train starts traversing the tunnel.
---@field leavingTrainId? Id|null @ The LuaTrain ID of the leaving train. This is populated when the train starts traversing the tunnel.
---@field leavingTrainMovingForwards? boolean|null @ If the leaving train is travelling forwards or not. Populated on first setting of the leaving trains speed. Can be returned to nil if when setting the trains speed its found the train isn't in a state to know its direction any more. This is initially populated when the train starts traversing the tunnel.
---
---@field surface LuaSurface @ The main world surface that this managed train is on.
---@field entrancePortal Portal @ The portal global object of the entrance portal for this tunnel usage instance.
---@field entrancePortalEntryTransitionSignal PortalTransitionSignal @ The transitionSignal global object of the rail signal at the transition point of the entrance portal track for entering trains (forced closed signal).
---@field exitPortal Portal @ Ref to the portal global object of the exit portal for this tunnel usage instance.
---@field exitPortalEntryTransitionSignal PortalTransitionSignal @ Ref to the transitionSignal global object of the rail signal at the end of the exit portal for entering trains (forced closed signal).
---@field exitPortalEntrySignalOut PortalEntrySignal @ Ref to the entrySignal global object on the rail signal at the entrance of the exit portal for leaving trains.
---@field exitPortalExitSignalIn PortalEntrySignal @ Ref to the entrySignal global object on the rail signal at the entrance of the exit portal for entering trains.
---@field tunnel Tunnel @ Ref to the global tunnel object.

---@alias TrainTravelOrientation "0"|"0.25"|"0.5"|"0.75"

---@class TrainIdToManagedTrain
---@field trainId Id @ the LuaTrain id.
---@field managedTrain ManagedTrain
---@field tunnelUsagePart TunnelUsageParts

TrainManager.CreateGlobals = function()
    global.trainManager = global.trainManager or {}
    global.trainManager.nextManagedTrainId = global.trainManager.nextManagedTrainId or 1 ---@type Id
    global.trainManager.managedTrains = global.trainManager.managedTrains or {} ---@type table<Id, ManagedTrain>
    global.trainManager.trainIdToManagedTrain = global.trainManager.trainIdToManagedTrain or {} ---@type table<Id, TrainIdToManagedTrain> @ Used to track trainIds to managedTrainEntries.
end

TrainManager.OnLoad = function()
    MOD.Interfaces.TrainManager = MOD.Interfaces.TrainManager or {}
    MOD.Interfaces.TrainManager.RegisterTrainApproachingPortalSignal = TrainManager.RegisterTrainApproachingPortalSignal
    MOD.Interfaces.TrainManager.RegisterTrainOnPortalTrack = TrainManager.RegisterTrainOnPortalTrack
    MOD.Interfaces.TrainManager.TrainEnterTunnel = TrainManager.TrainEnterTunnel
    MOD.Interfaces.TrainManager.On_TunnelRemoved = TrainManager.On_TunnelRemoved
    MOD.Interfaces.TrainManager.GetTrainIdsManagedTrainDetails = TrainManager.GetTrainIdsManagedTrainDetails
    MOD.Interfaces.TrainManager.InvalidTrainFound = TrainManager.InvalidTrainFound

    Events.RegisterHandlerEvent(defines.events.on_tick, "TrainManager.ProcessManagedTrains", TrainManager.ProcessManagedTrains)
    EventScheduler.RegisterScheduledEventType("TrainManager.TrainUndergroundCompleted_Scheduled", TrainManager.TrainUndergroundCompleted_Scheduled)
end

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--------------------          CORE LOGIC FUNCTIONS          -------------------
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

---@param approachingTrain LuaTrain
---@param approachingTrain_id Id
---@param entrancePortalEntryTransitionSignal PortalTransitionSignal
TrainManager.RegisterTrainApproachingPortalSignal = function(approachingTrain, approachingTrain_id, entrancePortalEntryTransitionSignal)
    -- Check if this train is already using the tunnel in some way.
    local existingTrainIDTrackedObject = global.trainManager.trainIdToManagedTrain[approachingTrain_id]
    local reversedManagedTrain, committedManagedTrain = nil, nil
    if existingTrainIDTrackedObject ~= nil then
        -- Train was using the tunnel already so handle the various states.

        if existingTrainIDTrackedObject.tunnelUsagePart == TunnelUsageParts.leavingTrain then
            -- Train was in left state, but is now re-entering. Happens if the train doesn't fully leave the exit portal signal block before coming back in.
            reversedManagedTrain = existingTrainIDTrackedObject.managedTrain
            -- Terminate the old tunnel reservation, but don't release the tunnel as we will just overwrite its user.
            TrainManager.TerminateTunnelTrip(reversedManagedTrain, TunnelUsageChangeReason.reversedAfterLeft, true)
        elseif existingTrainIDTrackedObject.tunnelUsagePart == TunnelUsageParts.portalTrackTrain then
            -- OVERHAUL - is this removal and re-creation needed, or can we just overwrite some data and let it continue. Seems quite wasteful. Note check what in CreateManagedTrainObject() is only done on traversal as we will need to include an upgrade path through the function. Review UPS cost of doing it current way as it does make code simplier to re-recreate rather than upgrade.
            -- Train was using the portal track and is now entering the tunnel.
            committedManagedTrain = existingTrainIDTrackedObject.managedTrain
            -- Just tidy up the managedTrain's entities and its related globals before the new one overwrites it. No tunnel trip to be dealt with.
            TrainManager.RemoveManagedTrainEntry(committedManagedTrain)
        else
            error("Unsupported situation")
        end
    end

    local managedTrain = TrainManager.CreateManagedTrainObject(approachingTrain, entrancePortalEntryTransitionSignal, true, committedManagedTrain, reversedManagedTrain)
    managedTrain.tunnelUsageState = TunnelUsageState.approaching
    MOD.Interfaces.Tunnel.TrainReservedTunnel(managedTrain)
    if reversedManagedTrain ~= nil then
        -- Include in the new train approaching event the old leavingTrain entry id that has been stopped.
        TrainManagerRemote.TunnelUsageChanged(managedTrain.id, TunnelUsageAction.startApproaching, nil, reversedManagedTrain.id)
    else
        TrainManagerRemote.TunnelUsageChanged(managedTrain.id, TunnelUsageAction.startApproaching)
    end
end

--- Used when a train is on a portal's track and thus the tunnel.
--- if its pathed to the tranisition signal already and claimed the tunnel we just need to record that it has entered the portal tracks in case it aborts its use of the tunnel (downgrades).
--- If its not pathed to the transition signal then we need to reserve the tunnel now for it. Is like the opposite to a leavingTrain monitoring. Only reached by trains that enter the portal track before their breaking distance is the stopping signal or when driven manually. They will claim the signal at a later point (upgrade) and thne that logic will superseed this.
---@param trainOnPortalTrack LuaTrain
---@param portal Portal
---@param managedTrain? ManagedTrain|null @ Populated if this is an alrady approachingTrain entering the portal tracks.
TrainManager.RegisterTrainOnPortalTrack = function(trainOnPortalTrack, portal, managedTrain)
    -- Check if this is a new tunnel usage or part of an exisitng transition signal reservation.
    if managedTrain ~= nil then
        -- Is an already approaching train entering the portal tracks. Just capture this and do nothing further in relation to this.
        managedTrain.portalTrackTrain = managedTrain.approachingTrain
        managedTrain.portalTrackTrainId = managedTrain.approachingTrainId
        managedTrain.portalTrackTrainInitiallyForwards = managedTrain.approachingTrainMovingForwards
        managedTrain.portalTrackTrainBySignal = false
        return
    end

    -- Is a new tunnel usage so do a full handling process.
    managedTrain = TrainManager.CreateManagedTrainObject(trainOnPortalTrack, portal.transitionSignals[TunnelSignalDirection.inSignal], false)
    managedTrain.tunnelUsageState = TunnelUsageState.portalTrack
    MOD.Interfaces.Tunnel.TrainReservedTunnel(managedTrain)
    TrainManagerRemote.TunnelUsageChanged(managedTrain.id, TunnelUsageAction.onPortalTrack)
end

--- Every tick loop over each train and process it as required.
---@param event on_tick
TrainManager.ProcessManagedTrains = function(event)
    -- As we remove managedTrains from this dictionary during looping over it numebric FOR loop isn't a viable option.
    for _, managedTrain in pairs(global.trainManager.managedTrains) do
        -- A managedTrain can be put to sleep by some state changes when its known an external/scheduled event will be what wakes them up or terminates them.
        if not managedTrain.skipTickCheck then
            -- We only need to handle one of these per tick as the transition between these states is either triggered externally or requires no immediate checking of the next state in the same tick as the transition.
            -- These are ordered on frequency of use to reduce per tick check costs.
            if managedTrain.tunnelUsageState == TunnelUsageState.approaching then
                -- Keep on running until either the train reaches the Transition train detector or the train's target stops being the transition signal.
                TrainManager.TrainApproachingOngoing(managedTrain)
            elseif managedTrain.tunnelUsageState == TunnelUsageState.leaving then
                TrainManager.TrainLeavingOngoing(managedTrain)
            elseif managedTrain.tunnelUsageState == TunnelUsageState.portalTrack then
                -- Keep on running until either the train triggers the Transition signal or the train leaves the portal tracks.
                TrainManager.TrainOnPortalTrackOngoing(managedTrain)
            elseif managedTrain.tunnelUsageState == TunnelUsageState.underground then
                if managedTrain.undergroundTrainHasPlayersRiding then
                    -- Only reason we have to update per tick while travelling underground currently.
                    TrainManager.TrainUndergroundOngoing(managedTrain, event.tick)
                else
                    -- Nothing to do, the arrival is scheduled. Should never really be reached due to the "skipTickCheck" ManagedTrain field.
                    return
                end
            end
        end
    end

    TrainManagerRemote.ProcessTicksEvents()
end

-- This tracks a train once it triggers the entry train detector, until it reserves the Transition signal of the Entrance portal or leaves the portal track (turn around and leave). Turning around could be caused by either manual driving or from an extreme edge case of track removal ahead as the train is approaching the transition point and there is a path backwards available. No state change or control of the train is required or applied at this stage.
---@param managedTrain ManagedTrain
TrainManager.TrainOnPortalTrackOngoing = function(managedTrain)
    local entrancePortalEntrySignalEntity = managedTrain.entrancePortal.entrySignals[TunnelSignalDirection.inSignal].entity

    if not managedTrain.portalTrackTrainBySignal then
        -- Not tracking by singal yet. Initially we have to track the trains speed (direction) to confirm that its still using the portal track until it triggers the Entry signal. Tracking by speed is less UPS effecient than using the entry signal.
        if entrancePortalEntrySignalEntity.signal_state == defines.signal_state.closed then
            -- The signal state is now closed, so we can start tracking by signal in the future. Must be closed rather than reserved as this is how we cleanly detect it having left (avoids any overlap with other train reserving it same tick this train leaves it).
            managedTrain.portalTrackTrainBySignal = true
        else
            -- Continue to track by speed until we can start tracking by signal.
            local trainSpeed = managedTrain.portalTrackTrain.speed
            if trainSpeed == 0 then
                -- If the train isn't moving we don't need to check for any state change this tick.
                return
            end
            local trainMovingForwards = trainSpeed > 0
            if trainMovingForwards ~= managedTrain.portalTrackTrainInitiallyForwards then
                -- Train is moving away from the portal track. Try to put the detection entity back to work out if the train has left the portal tracks.
                local placedDetectionEntity = MOD.Interfaces.Portal.AddEnteringTrainUsageDetectionEntityToPortal(managedTrain.entrancePortal, false, false)
                if placedDetectionEntity then
                    TrainManager.TerminateTunnelTrip(managedTrain, TunnelUsageChangeReason.portalTrackReleased)
                end
            end
        end
    else
        -- Track the tunnel's entrance portal entry rail signal so we can mark the tunnel as open for the next train if the current train leaves the portal track. Should the train trigger tunnel usage via the Transition signal this managed train entry will be terminated by that event. We are assuming that no train gets in to the portal rail segment before our main train gets out. This is far more UPS effecient than checking the trains last carriage and seeing if its rear rail signal is our portal entrance one.
        if entrancePortalEntrySignalEntity.signal_state ~= defines.signal_state.closed then
            -- No train in the block so our one must have left.
            TrainManager.TerminateTunnelTrip(managedTrain, TunnelUsageChangeReason.portalTrackReleased)
        end
    end
end

--- The train is approaching the transition signal so maintain its speed.
---@param managedTrain ManagedTrain
TrainManager.TrainApproachingOngoing = function(managedTrain)
    local approachingTrain = managedTrain.approachingTrain ---@type LuaTrain

    -- Check whether the train is still approaching the tunnel portal as its not committed yet it can turn away.
    if approachingTrain.state ~= defines.train_state.arrive_signal or approachingTrain.signal ~= managedTrain.entrancePortalEntryTransitionSignal.entity then
        -- Check if the train had reached the portal tracks yet or not as it affects next step in handling process.
        if managedTrain.portalTrackTrain == nil then
            -- Train never made it to the prtoal tracks, so can just abandon it.
            TrainManager.TerminateTunnelTrip(managedTrain, TunnelUsageChangeReason.abortedApproach)
        else
            -- Train made it to the portal tracks, so need to enable tracking of it until it leaves.
            managedTrain.tunnelUsageState = TunnelUsageState.portalTrack

            -- Update the global train lookup for the downgraded state.
            global.trainManager.trainIdToManagedTrain[managedTrain.portalTrackTrainId].tunnelUsagePart = TunnelUsageParts.portalTrackTrain

            -- This is a downgrade so remove the approaching state data from the managed train.
            managedTrain.approachingTrain = nil
            managedTrain.approachingTrainId = nil
            managedTrain.approachingTrainMovingForwards = nil
            managedTrain.approachingTrainExpectedSpeed = nil
            managedTrain.approachingTrainReachedFullSpeed = nil

            TrainManagerRemote.TunnelUsageChanged(managedTrain.id, TunnelUsageAction.onPortalTrack, TunnelUsageChangeReason.abortedApproach)
        end
        return
    end

    -- This won't keep the train exactly at this speed as it will try and brake increasingly as it appraoches the blocker signal. But will stay reasonably close to its desired speed, as most of the ticks its 5% or less below target, with just the last few ticks it climbing significantly as a % of current speed.
    local newAbsSpeed, newSpeed
    if not managedTrain.approachingTrainReachedFullSpeed then
        -- If the train hasn't yet reached its full speed then work out the new speed.
        newAbsSpeed = Utils.CalculateAcceleratingTrainSpeedForSingleTick(managedTrain.directionalTrainSpeedCalculationData, math.abs(managedTrain.approachingTrainExpectedSpeed))
        if managedTrain.approachingTrainExpectedSpeed == newAbsSpeed then
            -- If the new expected speed is equal to the old expected speed then the train has reached its max speed.
            managedTrain.approachingTrainReachedFullSpeed = true
        end
        if managedTrain.approachingTrainMovingForwards then
            newSpeed = newAbsSpeed
        else
            newSpeed = -newAbsSpeed
        end

        managedTrain.approachingTrainExpectedSpeed = newSpeed
        approachingTrain.speed = newSpeed
    else
        -- Train is at full speed so just maintain it.
        approachingTrain.speed = managedTrain.approachingTrainExpectedSpeed
    end

    -- Theres a transition portal track detector to flag when a train reaches the end of the portal track and is ready to enter the tunnel. So need to check in here.
end

--- This is triggered when the transition train detector triggers at the inner end of the portal. This is just before the train would have stopped at  the blocked end signal.
---@param managedTrain ManagedTrain
---@param tick Tick
TrainManager.TrainEnterTunnel = function(managedTrain, tick)
    local approachingTrain = managedTrain.approachingTrain

    -- Check the target isn't part of this tunnel once
    TrainManager.UpdateScheduleForTargetRailBeingTunnelRail(managedTrain, approachingTrain)

    -- Clone the entering train to the exit position.
    local leavingTrain = TrainManager.CloneEnteringTrainToExit(managedTrain) -- This updates the train cache object and managedTrain.trainCachedData.trainCarriagesCachedData's entities to the leaving train ones.
    local leavingTrainId = leavingTrain.id
    global.trainManager.trainIdToManagedTrain[leavingTrainId] = {
        trainId = leavingTrainId,
        managedTrain = managedTrain,
        tunnelUsagePart = TunnelUsageParts.leavingTrain
    }
    managedTrain.leavingTrain = leavingTrain
    managedTrain.leavingTrainId = leavingTrainId
    local currentAbsSpeed = math.abs(managedTrain.approachingTrainExpectedSpeed)
    managedTrain.traversalInitialSpeedAbsolute = currentAbsSpeed

    -- Clear references and data thats no longer valid before we do anything else to the train. As we need these to be blank for when other functions are triggered from changing the train and its carriages.
    -- Note that some of these may be cached prior to this within this function for use after the clearance.
    global.trainManager.trainIdToManagedTrain[managedTrain.approachingTrainId] = nil
    managedTrain.approachingTrain = nil
    managedTrain.approachingTrainId = nil
    managedTrain.approachingTrainMovingForwards = nil
    managedTrain.approachingTrainExpectedSpeed = nil
    managedTrain.approachingTrainReachedFullSpeed = nil
    managedTrain.portalTrackTrain = nil
    managedTrain.portalTrackTrainId = nil
    managedTrain.portalTrackTrainInitiallyForwards = nil
    managedTrain.portalTrackTrainBySignal = nil

    -- Set up DummyTrain to maintain station requests.
    managedTrain.tunnelUsageState = TunnelUsageState.underground
    managedTrain.targetTrainStop = approachingTrain.path_end_stop
    managedTrain.dummyTrainCarriage = TrainManager.CreateDummyTrain(managedTrain.exitPortal, managedTrain.exitPortal.dummyLocomotivePosition, approachingTrain.schedule, managedTrain.targetTrainStop, false, managedTrain.force)

    -- Work out how long it will take to reach the leaving position assuming the train will have a path and be acelerating/full speed on the far side of the tunnel.
    -- Its the underground distance, portal train waiting length and 17 tiles (3 tiles in to the entry protal part, the 2 blocked portals, 2 tiles to get to the first blocked portal).
    local traversalTravelDistance = managedTrain.tunnel.underground.tilesLength + managedTrain.exitPortal.trainWaitingAreaTilesLength + 17
    -- Estimate how long it will take to complete the distance and then final speed.
    local estimatedTicks = Utils.EstimateAcceleratingTrainTicksToCoverDistance(managedTrain.directionalTrainSpeedCalculationData, currentAbsSpeed, traversalTravelDistance)
    local estimatedSpeedAbsolute, _ = Utils.EstimateAcceleratingTrainSpeedAndDistanceForTicks(managedTrain.directionalTrainSpeedCalculationData, currentAbsSpeed, estimatedTicks)
    managedTrain.traversalTravelDistance = traversalTravelDistance
    managedTrain.traversalInitialDuration = estimatedTicks
    managedTrain.traversalArrivalTick = tick + estimatedTicks
    managedTrain.trainLeavingSpeedAbsolute = estimatedSpeedAbsolute

    -- Remove the entering train's carriage entities. Have to use this reference and not the cached data as it was updated earlier in this function.
    for i, carriage in pairs(approachingTrain.carriages) do
        carriage.destroy {raise_destroy = true} -- Is a standard game entity removed so raise destroyed for other mods.
    end

    -- Add the entry signal closing entity to keep the signals closed as it takes a few ticks for the signals to update from the cloned carriage.
    managedTrain.entranceSignalClosingCarriage = TrainManager.CreateDummyTrain(managedTrain.entrancePortal, managedTrain.entrancePortal.leavingTrainFrontPosition, nil, nil, true, global.force.tunnelForce)

    -- Complete the state transition.
    MOD.Interfaces.Tunnel.TrainFinishedEnteringTunnel(managedTrain)
    TrainManagerRemote.TunnelUsageChanged(managedTrain.id, TunnelUsageAction.entered)

    -- If theres no player in the train we can just forward schedule the arrival. If there is a player then the tick check will pick this up and deal with it.
    if not managedTrain.undergroundTrainHasPlayersRiding then
        EventScheduler.ScheduleEventOnce(managedTrain.traversalArrivalTick, "TrainManager.TrainUndergroundCompleted_Scheduled", managedTrain.id, {managedTrain = managedTrain})
        managedTrain.skipTickCheck = true -- We can ignore this managed train until its arrival tick event fires.
    end
end

--- Runs each tick for when we need to track a train while underground in detail.
--- Only need to track an ongoing underground train if there's a player riding in the train and we need to update their position each tick.
---@param managedTrain ManagedTrain
---@param currentTick Tick
TrainManager.TrainUndergroundOngoing = function(managedTrain, currentTick)
    -- OVERHAUL: use of managedTrain.traversalArrivalTick doesn't handle if the train is delayed. Will mean the player goes at full speed through the tunnel and then sits still for the delayed arrival from the train having to brake. Will also need to store the movement per tick so we can move te player container by that much.
    if currentTick < managedTrain.traversalArrivalTick then
        -- Train still waiting on its arrival time.
        if managedTrain.undergroundTrainHasPlayersRiding then
            PlayerContainer.MoveATrainsPlayerContainer(managedTrain)
        end
    else
        -- Train arrival time has come.

        -- Set the leaving trains speed and handle the unknown direction element. Updates managedTrain.leavingTrainMovingForwards for later use.
        local leavingTrain = managedTrain.leavingTrain
        TrainManager.SetLeavingTrainSpeedInCorrectDirection(leavingTrain, managedTrain.trainLeavingSpeedAbsolute, managedTrain, managedTrain.targetTrainStop)

        TrainManager.TrainUndergroundCompleted(managedTrain)
    end
end

--- Run when the train is scheduled to arrive at the end of the tunnel.
---@param event UtilityScheduledEvent_CallbackObject
TrainManager.TrainUndergroundCompleted_Scheduled = function(event)
    local managedTrain = event.data.managedTrain ---@type ManagedTrain
    local previousBrakingTargetEntityId = event.data.brakingTargetEntityId ---@type UnitNumber
    if managedTrain == nil or managedTrain.tunnelUsageState ~= TunnelUsageState.underground then
        -- Something has happened to the train/tunnel being managed while this has been scheduled, so just give up.
        return
    end

    local leavingTrain = managedTrain.leavingTrain

    -- Set the leaving trains speed and handle the unknown direction element. Updates managedTrain.leavingTrainMovingForwards for later use.
    TrainManager.SetLeavingTrainSpeedInCorrectDirection(leavingTrain, managedTrain.trainLeavingSpeedAbsolute, managedTrain, managedTrain.targetTrainStop)

    -- Check if the train can just leave at its current speed and if so release it here.
    local leavingTrain_state = leavingTrain.state
    if leavingTrain_state == defines.train_state.on_the_path then
        -- Train can leave at full speed.
        TrainManager.TrainUndergroundCompleted(managedTrain)
        return
    end

    -- Train can't just leave at its current speed blindly, so work out how to proceed based on its state.
    local crawlAbsSpeed = 0.03 -- The speed for the train if its going to crawl forwards to the end of the portal.
    local distanceBeyondTrainLeavingPosition, leavingTrainNewAbsoluteSpeed, scheduleFutureArrival, brakingTargetEntityId = 0, nil, nil, nil
    if leavingTrain_state == defines.train_state.path_lost or leavingTrain_state == defines.train_state.no_schedule or leavingTrain_state == defines.train_state.no_path or leavingTrain_state == defines.train_state.destination_full then
        -- Train has no where to go so just pull to the end of the tunnel and then return to its regular broken state.

        local exitPortalEntryRail = managedTrain.exitPortalEntrySignalOut.railEntity
        local schedule = leavingTrain.schedule
        table.insert(
            schedule.records,
            schedule.current,
            {
                rail = exitPortalEntryRail,
                temporary = true
            }
        )
        leavingTrain.schedule = schedule

        leavingTrainNewAbsoluteSpeed = crawlAbsSpeed
        scheduleFutureArrival = false
    elseif leavingTrain_state == defines.train_state.arrive_station then
        -- Train needs to have been braking as its pulling up to its station/rail target, but we can easily get the distance from its path data.
        local leavingTrain_pathEndStop, leavingTrain_pathEndRail = leavingTrain.path_end_stop, leavingTrain.path_end_rail

        -- Handle the end of portal rail differently to a rail on the main network..
        if leavingTrain_pathEndStop == nil and leavingTrain_pathEndRail ~= nil and leavingTrain_pathEndRail.unit_number == managedTrain.exitPortalEntrySignalOut.railEntity_unitNumber then
            -- Its the end of portal rail so just crawl forwards.
            leavingTrainNewAbsoluteSpeed = crawlAbsSpeed
            scheduleFutureArrival = false
        else
            -- Check this isn't a second loop for the same target due to some bug in the braking maths.
            local brakingTargetEntity = leavingTrain_pathEndStop or leavingTrain_pathEndRail
            brakingTargetEntityId = brakingTargetEntity.unit_number
            local skipProcessingForDelay = false
            if previousBrakingTargetEntityId == brakingTargetEntityId then
                -- Is a repeat.
                if global.debugRelease then
                    error("Looped on leaving train for same target station.")
                else
                    -- Just let the mod continue to run, its not the end of the world. As npo main variables are changed from default the train will leave now.
                    skipProcessingForDelay = true
                end
            end

            -- Do the processing assuming this isn't a repeat loop (it shouldn't be a repeat if maths works correctly).
            if not skipProcessingForDelay then
                local leavingTrain_path = leavingTrain.path
                local leavingTrain_path_rails = leavingTrain_path.rails
                distanceBeyondTrainLeavingPosition = leavingTrain_path.total_distance
                distanceBeyondTrainLeavingPosition = distanceBeyondTrainLeavingPosition - Utils.GetRailEntityLength(leavingTrain_path_rails[#leavingTrain_path_rails].type) -- Remove the last rail's length as we want to stop before this.
                scheduleFutureArrival = true
            end
        end
    elseif leavingTrain_state == defines.train_state.arrive_signal then
        -- Train needs to have been braking as its pulling up to its signal.
        local leavingTrain_signal = leavingTrain.signal
        local leavingTrain_signal_unitNumber = leavingTrain_signal.unit_number
        brakingTargetEntityId = leavingTrain_signal_unitNumber

        -- Handle the various portal signals differently to a signal on the main rail network.
        if leavingTrain_signal_unitNumber == managedTrain.exitPortalEntrySignalOut.id then
            -- Its the exit signal of this portal so just crawl forwards.
            leavingTrainNewAbsoluteSpeed = crawlAbsSpeed
            scheduleFutureArrival = false
        elseif leavingTrain_signal_unitNumber == managedTrain.exitPortalExitSignalIn.id then
            -- Its the entry signal of this portal as the leaving train has looped back around to the same tunnel.
            -- Train can NOT just leave at full speed while it has reserved a full path back around to this tunnel portal's signals. As it triggers the portals entry signals before leaving and thus is trying to chained 2 tunnel usages over each other, which isn't supported. So we need to make it leave very slowly so it will complete leaving the tunnel before its path reserved its loop back to its exit portal. It only occurs on a silly edge case when maing a tiny figure 8 through a tunnel with non stop trains and stations.
            leavingTrainNewAbsoluteSpeed = crawlAbsSpeed
            scheduleFutureArrival = false
        elseif leavingTrain_signal_unitNumber == managedTrain.exitPortalEntryTransitionSignal.id then
            -- Its the transition signal of this portal as the leaving train has reversed at speed when trying to leave the tunnel. Occurs for dual direction trains only.
            -- This should never be a reached state with curretn logic, as if the leaving train is reversing it should start at 0 speed, but this state requires it to start at higher speed.
            if global.debugRelease then
                error("leaving train is reversing at starting speed back in to tunnel")
            else
                -- Same logic as if it is the exitPortalExitSignalIn which is an expected and supported usage case.
                leavingTrainNewAbsoluteSpeed = crawlAbsSpeed
                scheduleFutureArrival = false
            end
        else
            -- Signal on main rail network so need to work out the rough distance.

            -- Check this isn't a second loop for the same target due to some bug in the braking maths.
            local skipProcessingForDelay = false
            if previousBrakingTargetEntityId == brakingTargetEntityId then
                -- Is a repeat.
                if global.debugRelease then
                    error("Looped on leaving train for same signal.")
                else
                    -- Just let the mod continue to run, its not the end of the world. As npo main variables are changed from default the train will leave now.
                    skipProcessingForDelay = true
                end
            end

            -- Do the processing assuming this isn't a repeat loop (it shouldn't be a repeat if maths works correctly).
            if not skipProcessingForDelay then
                -- Create a temporary schedule to the signals rail, get the distance and then remove the schedule entry.
                local signalRail = leavingTrain_signal.get_connected_rails()[1]
                local schedule = leavingTrain.schedule
                -- Make the new schedule have a wait condition so we path to this signal rail and not through it towards the real target. Its going to be removed before being acted upon anyways.
                table.insert(
                    schedule.records,
                    schedule.current,
                    {
                        rail = signalRail,
                        temporary = true,
                        wait_conditions = {
                            {
                                type = "time",
                                compare_type = "and",
                                ticks = 1
                            }
                        }
                    }
                )
                leavingTrain.schedule = schedule
                -- Setting a new current schedule record triggers an update of path.
                distanceBeyondTrainLeavingPosition = leavingTrain.path.total_distance
                distanceBeyondTrainLeavingPosition = distanceBeyondTrainLeavingPosition - Utils.GetRailEntityLength(signalRail.type) -- Remove the last rail's length as we want to stop before this.
                table.remove(schedule.records, schedule.current)
                leavingTrain.schedule = schedule
                -- Restore the train to its origional state.
                TrainManager.SetTrainToAuto(leavingTrain, managedTrain.targetTrainStop)

                scheduleFutureArrival = true
            end
        end
    else
        error("unsupported train state for leaving tunnel: " .. leavingTrain_state)
    end

    -- Handle the next steps based on the processing.
    if scheduleFutureArrival then
        -- Calculate the delayed arrival time and delay the schedule to this. This will account for the full speed change and will account for if the train entered the tunnel overly fast, making the total duration and leaving speed correct.

        local currentForcesBrakingBonus = managedTrain.force.train_braking_force_bonus
        distanceBeyondTrainLeavingPosition = distanceBeyondTrainLeavingPosition - 6 -- Remove the 3 straight rails at the end of the portal that are listed in train's path. The train is already on these and so they can't be braked over.

        if distanceBeyondTrainLeavingPosition <= 0 then
            -- This should never be reaced with current code. Indicates the train is doing an incorrect reverse or something has gone wrong.
            if global.debugRelease then
                error("leaving train has 0 or lower initial path distance")
            else
                distanceBeyondTrainLeavingPosition = 0
            end
        end

        -- Work out the speed we should be going when leaving the tunnel to stop at the required location.
        local requiredSpeedAbsoluteAtPortalEnd = Utils.CalculateBrakingTrainInitialSpeedWhenStoppedOverDistance(managedTrain.directionalTrainSpeedCalculationData, distanceBeyondTrainLeavingPosition, currentForcesBrakingBonus)
        managedTrain.trainLeavingSpeedAbsolute = requiredSpeedAbsoluteAtPortalEnd

        -- Work out how much time and distance in the tunnel it takes to change speed to the required leaving speed.
        local ticksSpentMatchingSpeed, distanceSpentMatchingSpeed
        if managedTrain.traversalInitialSpeedAbsolute < requiredSpeedAbsoluteAtPortalEnd then
            -- Need to accelerate within tunnel up to required speed.
            ticksSpentMatchingSpeed, distanceSpentMatchingSpeed = Utils.EstimateAcceleratingTrainTicksAndDistanceFromInitialToFinalSpeed(managedTrain.directionalTrainSpeedCalculationData, managedTrain.traversalInitialSpeedAbsolute, requiredSpeedAbsoluteAtPortalEnd)
        else
            -- Need to brake within tunnel up to required speed.
            ticksSpentMatchingSpeed, distanceSpentMatchingSpeed = Utils.CalculateBrakingTrainDistanceAndTimeFromInitialToFinalSpeed(managedTrain.directionalTrainSpeedCalculationData, managedTrain.traversalInitialSpeedAbsolute, requiredSpeedAbsoluteAtPortalEnd, currentForcesBrakingBonus)
        end
        local remainingTunnelDistanceToCover = managedTrain.traversalTravelDistance - distanceSpentMatchingSpeed

        -- Work out how many ticks within the tunnel it takes to cover the distance gap. We must start and end at the same speed over this distance, so accelerate and brake during it.
        local ticksTraversingRemaingDistance
        if remainingTunnelDistanceToCover > 0 then
            -- Tunnel distance still to cover.
            ticksTraversingRemaingDistance = Utils.EstimateTrainTicksToCoverDistanceWithSameStartAndEndSpeed(managedTrain.directionalTrainSpeedCalculationData, requiredSpeedAbsoluteAtPortalEnd, remainingTunnelDistanceToCover, currentForcesBrakingBonus)
        else
            -- Train has to break longer than the tunnel is. The time spent breaking covers the full amount and we will just ignore the fact that the train was accelerating in to the tunnel when it shouldn't have been.
            ticksTraversingRemaingDistance = 0
        end

        -- Work out the delay for leaving the tunnel.
        local delayTicks = math.ceil(ticksSpentMatchingSpeed + ticksTraversingRemaingDistance - managedTrain.traversalInitialDuration)
        if delayTicks < 0 then
            error("leaving train shouldn't be able to be rescheduled with negative delay compared to previous computing")
        end

        -- If the new time is not the same as the old then we need to reschedule, this is the expected situation. However if the arrival times are the same then just let the code flow in to releasing the train now.
        if delayTicks > 0 then
            -- Schedule the next attempt at releasing the train.
            managedTrain.traversalArrivalTick = managedTrain.traversalArrivalTick + delayTicks
            EventScheduler.ScheduleEventOnce(managedTrain.traversalArrivalTick, "TrainManager.TrainUndergroundCompleted_Scheduled", managedTrain.id, {managedTrain = managedTrain, brakingTargetEntityId = brakingTargetEntityId})

            -- Reset the leaving trains speed and state as we don't want it to do anything yet.
            leavingTrain.speed = 0
            leavingTrain.manual_mode = true
            return
        end
    end

    -- Set the new leaving speed to the train and release it.
    local leavingSpeedAbsolute = leavingTrainNewAbsoluteSpeed or managedTrain.trainLeavingSpeedAbsolute
    if managedTrain.leavingTrainMovingForwards == true then
        leavingTrain.speed = leavingSpeedAbsolute
    elseif managedTrain.leavingTrainMovingForwards == false then
        leavingTrain.speed = -leavingSpeedAbsolute
    else
        -- Train facing not resolvable at previous setting time so have to do it again now from a possibly weird train state.
        leavingTrain.manual_mode = true -- Set train back to a safe state that we can test applying the speed as it will still have a state that errors on backwards speeds.
        -- Set the leaving trains speed and handle the unknown direction element. Updates managedTrain.leavingTrainMovingForwards for later use.
        TrainManager.SetLeavingTrainSpeedInCorrectDirection(leavingTrain, leavingSpeedAbsolute, managedTrain, leavingTrain.path_end_stop)
        if managedTrain.leavingTrainMovingForwards == nil then
            -- Train facing should have been fixed by now.
            error("unknown leaving train facing when trying to set its speed to release it from the tunnel")
        end
    end

    TrainManager.TrainUndergroundCompleted(managedTrain)
end

--- Train has arrived and needs tidying up.
---@param managedTrain ManagedTrain
TrainManager.TrainUndergroundCompleted = function(managedTrain)
    -- Handle any players riding in the train.
    if managedTrain.undergroundTrainHasPlayersRiding then
        PlayerContainer.TransferPlayerFromContainerForClonedUndergroundCarriage(nil, nil)
    end

    -- Return the leaving train carriages to their origional force and let them take damage again.
    local carriage
    for _, carriageData in pairs(managedTrain.trainCachedData.carriagesCachedData) do
        carriage = carriageData.entity
        carriage.force = managedTrain.force
        carriage.destructible = true
    end

    -- Set the per tick event back to running. In some UndergroundOngoing states this was set to skip each tick as not needed due to scheduled events.
    managedTrain.skipTickCheck = false

    -- Tidy up for the leaving train and propigate state updates.
    TrainManager.DestroyDummyTrain(managedTrain)
    TrainManager.DestroyEntranceSignalClosingLocomotive(managedTrain)
    managedTrain.tunnelUsageState = TunnelUsageState.leaving
    TrainManagerRemote.TunnelUsageChanged(managedTrain.id, TunnelUsageAction.leaving)
end

--- Track the tunnel's exit portal entry rail signal so we can mark the tunnel as open for the next train when the current train has left.
---@param managedTrain ManagedTrain
TrainManager.TrainLeavingOngoing = function(managedTrain)
    -- We are assuming that no train gets in to the portal rail segment before our main train gets out. This is far more UPS effecient than checking the trains last carriage and seeing if its rear rail signal is our portal entrance one. Must be closed rather than reserved as this is how we cleanly detect it having left (avoids any overlap with other train reserving it same tick this train leaves it).
    if managedTrain.exitPortalExitSignalIn.entity.signal_state ~= defines.signal_state.closed then
        -- No train in the block so our one must have left.
        global.trainManager.trainIdToManagedTrain[managedTrain.leavingTrainId] = nil
        managedTrain.leavingTrain = nil
        managedTrain.leavingTrainId = nil
        TrainManager.TerminateTunnelTrip(managedTrain, TunnelUsageChangeReason.completedTunnelUsage)
    end
end

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-----------------------          MINOR FUNCTIONS          ---------------------
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

--- Update the passed in train schedule if the train is currently heading for a tunnel or portal rail. If so change the target rail to be the end of the portal. Avoids the train infinite loop pathing through the tunnel trying to reach a tunnel or portal rail it never can.
---@param managedTrain ManagedTrain
---@param train LuaTrain
TrainManager.UpdateScheduleForTargetRailBeingTunnelRail = function(managedTrain, train)
    local targetTrainStop, targetRail = train.path_end_stop, train.path_end_rail
    if targetTrainStop == nil and targetRail ~= nil then
        local targetRail_name = targetRail.name
        if Common.TunnelRailEntityNames[targetRail_name] ~= nil then
            -- The target rail is the type used by a portal/segment for rail, so check if it belongs to the just used tunnel.
            local targetRail_unitNumber = targetRail.unit_number
            if managedTrain.tunnel.tunnelRailEntities[targetRail_unitNumber] ~= nil or managedTrain.tunnel.portalRailEntities[targetRail_unitNumber] ~= nil then
                -- The target rail is part of the currently used tunnel, so update the schedule rail to be the one at the end of the portal and just leave the train to do its thing from there.
                local schedule = train.schedule
                local currentScheduleRecord = schedule.records[schedule.current]
                local exitPortalEntryRail = managedTrain.exitPortalEntrySignalOut.railEntity
                currentScheduleRecord.rail = exitPortalEntryRail
                schedule.records[schedule.current] = currentScheduleRecord
                train.schedule = schedule
            end
        end
    end
end

---@param tunnelRemoved Tunnel
---@param killForce? LuaForce|null @ Populated if the tunnel is being removed due to an entity being killed, otherwise nil.
---@param killerCauseEntity? LuaEntity|null @ Populated if the tunnel is being removed due to an entity being killed, otherwise nil.
TrainManager.On_TunnelRemoved = function(tunnelRemoved, killForce, killerCauseEntity)
    for _, managedTrain in pairs(global.trainManager.managedTrains) do
        if managedTrain.tunnel.id == tunnelRemoved.id then
            if managedTrain.approachingTrainId ~= nil then
                global.trainManager.trainIdToManagedTrain[managedTrain.approachingTrainId] = nil
                if managedTrain.approachingTrain ~= nil and managedTrain.approachingTrain.valid then
                    managedTrain.approachingTrain.manual_mode = true
                    managedTrain.approachingTrain.speed = 0
                end
            end
            if managedTrain.leavingTrainId ~= nil then
                global.trainManager.trainIdToManagedTrain[managedTrain.leavingTrainId] = nil
                if managedTrain.leavingTrain ~= nil and managedTrain.leavingTrain.valid then
                    managedTrain.leavingTrain.manual_mode = true
                    managedTrain.leavingTrain.speed = 0
                end
            end

            if managedTrain.undergroundTrainHasPlayersRiding then
                PlayerContainer.On_TunnelRemoved(managedTrain, killForce, killerCauseEntity)
            end

            TrainManager.TerminateTunnelTrip(managedTrain, TunnelUsageChangeReason.tunnelRemoved)
        end
    end
end

--- Just creates the managed train object for the approaching/on-portal-track train.
---@param train LuaTrain
---@param entrancePortalEntryTransitionSignal PortalTransitionSignal
---@param onApproach boolean
---@param upgradeManagedTrain ManagedTrain @ An existing ManagedTrain object that is being updated/overwritten with fresh data.
---@param reversedManagedTrain ManagedTrain @ An existing ManagedTrain object that is reversing after starting to leave the tunnel back in to the tunnel. This new ManagedTrain being created is this new reversal usage of the tunnel.
---@return ManagedTrain
TrainManager.CreateManagedTrainObject = function(train, entrancePortalEntryTransitionSignal, onApproach, upgradeManagedTrain, reversedManagedTrain)
    local train_id = train.id ---@type Id
    local train_speed = train.speed ---@type double
    if train_speed == 0 then
        error("TrainManager.CreateManagedTrainObject() doesn't support 0 speed\ntrain id: " .. train_id)
    end

    local managedTrainId
    if upgradeManagedTrain ~= nil then
        managedTrainId = upgradeManagedTrain.id
    else
        managedTrainId = global.trainManager.nextManagedTrainId
        global.trainManager.nextManagedTrainId = global.trainManager.nextManagedTrainId + 1 ---@type Id
    end
    ---@type ManagedTrain
    local managedTrain = {
        id = managedTrainId,
        entrancePortalEntryTransitionSignal = entrancePortalEntryTransitionSignal,
        entrancePortal = entrancePortalEntryTransitionSignal.portal,
        tunnel = entrancePortalEntryTransitionSignal.portal.tunnel,
        trainTravelDirection = Utils.LoopDirectionValue(entrancePortalEntryTransitionSignal.entity.direction + 4),
        undergroundTrainHasPlayersRiding = false,
        skipTickCheck = false
    }
    local trainMovingForwards = train_speed > 0

    -- Start building up the carriage data cache for later use.
    if upgradeManagedTrain == nil then
        -- Build data from scratch.
        managedTrain.trainCachedData = MOD.Interfaces.TrainCachedData.GetCreateTrainCache(train, train_id)
    else
        -- Use the old ManagedTrain's data object as it can't have changed within the same ManagedTrain.
        managedTrain.trainCachedData = upgradeManagedTrain.trainCachedData
    end
    managedTrain.force = managedTrain.trainCachedData.carriagesCachedData[1].entity.force

    if onApproach then
        -- Train is on approach for the tunnel, full data capture in preperation.
        managedTrain.approachingTrain = train
        managedTrain.approachingTrainId = train_id

        -- Cache the trains attributes for working out each speed. Only needed if its traversing the tunnel.
        managedTrain.approachingTrainExpectedSpeed = train_speed
        managedTrain.approachingTrainReachedFullSpeed = false
        managedTrain.trainFacingForwardsToCacheData = MOD.Interfaces.TrainCachedData.UpdateTrainSpeedCalculationData(train, train_speed, managedTrain.trainCachedData)
        if managedTrain.trainFacingForwardsToCacheData then
            managedTrain.forwardsDirectionalTrainSpeedCalculationDataUpdated = true
            managedTrain.directionalTrainSpeedCalculationData = managedTrain.trainCachedData.forwardMovingTrainSpeedCalculationData
            managedTrain.backwardsDirectionalTrainSpeedCalculationDataUpdated = false
        else
            managedTrain.backwardsDirectionalTrainSpeedCalculationDataUpdated = true
            managedTrain.directionalTrainSpeedCalculationData = managedTrain.trainCachedData.backwardMovingTrainSpeedCalculationData
            managedTrain.forwardsDirectionalTrainSpeedCalculationDataUpdated = false
        end

        global.trainManager.trainIdToManagedTrain[train_id] = {
            trainId = train_id,
            managedTrain = managedTrain,
            tunnelUsagePart = TunnelUsageParts.approachingTrain
        }

        managedTrain.approachingTrainMovingForwards = trainMovingForwards

        -- If its an upgrade or a reversal populate the portalTrack fields as the train is on the portal track. Any old ManagedTrain has been destroyed before this new create was called.
        if upgradeManagedTrain ~= nil or reversedManagedTrain ~= nil then
            managedTrain.portalTrackTrain = train
            managedTrain.portalTrackTrainId = train_id
            managedTrain.portalTrackTrainInitiallyForwards = trainMovingForwards
            managedTrain.portalTrackTrainBySignal = false
        end
    else
        -- Reserved the tunnel, but not using it yet. Light data capture.
        managedTrain.portalTrackTrain = train
        managedTrain.portalTrackTrainId = train_id
        managedTrain.portalTrackTrainInitiallyForwards = trainMovingForwards
        managedTrain.portalTrackTrainBySignal = false
        global.trainManager.trainIdToManagedTrain[train_id] = {
            trainId = train_id,
            managedTrain = managedTrain,
            tunnelUsagePart = TunnelUsageParts.portalTrackTrain
        }
    end

    global.trainManager.managedTrains[managedTrain.id] = managedTrain
    managedTrain.surface = managedTrain.tunnel.surface
    managedTrain.trainTravelOrientation = managedTrain.trainTravelDirection / 8

    -- Get the exit transition signal on the other portal so we know when to bring the train back in.
    for _, portal in pairs(managedTrain.tunnel.portals) do
        if portal.id ~= entrancePortalEntryTransitionSignal.portal.id then
            managedTrain.exitPortalEntryTransitionSignal = portal.transitionSignals[TunnelSignalDirection.inSignal]
            managedTrain.exitPortal = portal
            managedTrain.exitPortalEntrySignalOut = portal.entrySignals[TunnelSignalDirection.outSignal]
            managedTrain.exitPortalExitSignalIn = portal.entrySignals[TunnelSignalDirection.inSignal]
        end
    end

    return managedTrain
end

---@param managedTrain ManagedTrain
---@param tunnelUsageChangeReason TunnelUsageChangeReason
---@param dontReleaseTunnel? boolean|null @ If true any tunnel reservation isn't released. If false or nil then tunnel is released.
TrainManager.TerminateTunnelTrip = function(managedTrain, tunnelUsageChangeReason, dontReleaseTunnel)
    if managedTrain.undergroundTrainHasPlayersRiding then
        PlayerContainer.On_TerminateTunnelTrip(managedTrain)
    end
    TrainManager.RemoveManagedTrainEntry(managedTrain)

    if not dontReleaseTunnel then
        MOD.Interfaces.Tunnel.TrainReleasedTunnel(managedTrain)
    end
    TrainManagerRemote.TunnelUsageChanged(managedTrain.id, TunnelUsageAction.terminated, tunnelUsageChangeReason)
end

---@param managedTrain ManagedTrain
TrainManager.RemoveManagedTrainEntry = function(managedTrain)
    -- Only remove the global if it points to this managedTrain. The reversal process can have made the approachingTrain references invalid, and MAY have overwritten them, so check before removing.
    if managedTrain.approachingTrain and managedTrain.approachingTrain.valid and global.trainManager.trainIdToManagedTrain[managedTrain.approachingTrain.id] and global.trainManager.trainIdToManagedTrain[managedTrain.approachingTrain.id].managedTrain.id == managedTrain.id then
        global.trainManager.trainIdToManagedTrain[managedTrain.approachingTrain.id] = nil
    elseif managedTrain.approachingTrainId and global.trainManager.trainIdToManagedTrain[managedTrain.approachingTrainId] and global.trainManager.trainIdToManagedTrain[managedTrain.approachingTrainId].managedTrain.id == managedTrain.id then
        global.trainManager.trainIdToManagedTrain[managedTrain.approachingTrainId] = nil
    end

    if managedTrain.leavingTrain and managedTrain.leavingTrain.valid and global.trainManager.trainIdToManagedTrain[managedTrain.leavingTrain.id] and global.trainManager.trainIdToManagedTrain[managedTrain.leavingTrain.id].managedTrain.id == managedTrain.id then
        global.trainManager.trainIdToManagedTrain[managedTrain.leavingTrain.id] = nil
    elseif managedTrain.leavingTrainId and global.trainManager.trainIdToManagedTrain[managedTrain.leavingTrainId] and global.trainManager.trainIdToManagedTrain[managedTrain.leavingTrainId].managedTrain.id == managedTrain.id then
        global.trainManager.trainIdToManagedTrain[managedTrain.leavingTrainId] = nil
    end

    TrainManager.DestroyDummyTrain(managedTrain)
    TrainManager.DestroyEntranceSignalClosingLocomotive(managedTrain)

    if managedTrain.portalTrackTrain and managedTrain.portalTrackTrain.valid and global.trainManager.trainIdToManagedTrain[managedTrain.portalTrackTrain.id] and global.trainManager.trainIdToManagedTrain[managedTrain.portalTrackTrain.id].managedTrain.id == managedTrain.id then
        global.trainManager.trainIdToManagedTrain[managedTrain.portalTrackTrain.id] = nil
    elseif managedTrain.portalTrackTrainId and global.trainManager.trainIdToManagedTrain[managedTrain.portalTrackTrainId] and global.trainManager.trainIdToManagedTrain[managedTrain.portalTrackTrainId].managedTrain.id == managedTrain.id then
        global.trainManager.trainIdToManagedTrain[managedTrain.portalTrackTrainId] = nil
    end

    -- Set all states to finished so that the TrainManager.ProcessManagedTrains() loop won't execute anything further this tick.
    managedTrain.tunnelUsageState = TunnelUsageState.finished

    global.trainManager.managedTrains[managedTrain.id] = nil
end

---@param trainId Id
---@return TrainIdToManagedTrain trainIdToManagedTrain
TrainManager.GetTrainIdsManagedTrainDetails = function(trainId)
    return global.trainManager.trainIdToManagedTrain[trainId]
end

--- Clone the entering train to the front of the exit portal. This will minimise any tracking of the train when leaving.
--- This happens to duplicate the train schedule as a by product of using the entity clone feature.
--- This updates managedTrain.trainCachedData.carriagesCachedData with references to the new entities so the cached data becomes for the leaving train.
---@param managedTrain ManagedTrain
---@return LuaTrain @ Leaving train
TrainManager.CloneEnteringTrainToExit = function(managedTrain)
    -- This currently assumes the portals are in a straight line of each other and that the portal areas are straight.
    local approachingTrain, trainCarriagesForwardOrientation = managedTrain.approachingTrain, managedTrain.trainTravelOrientation
    local targetSurface = managedTrain.surface
    if not managedTrain.approachingTrainMovingForwards then
        trainCarriagesForwardOrientation = Utils.LoopFloatValueWithinRangeMaxExclusive(trainCarriagesForwardOrientation + 0.5, 0, 1)
    end

    local nextCarriagePosition = managedTrain.exitPortal.leavingTrainFrontPosition

    -- Work out which way to iterate down the train's carriage array. Starting with the lead carriage.
    local minCarriageIndex, maxCarriageIndex, carriageIterator
    if (managedTrain.trainFacingForwardsToCacheData) then
        minCarriageIndex, maxCarriageIndex, carriageIterator = 1, #managedTrain.trainCachedData.carriagesCachedData, 1
    elseif (not managedTrain.trainFacingForwardsToCacheData) then
        minCarriageIndex, maxCarriageIndex, carriageIterator = #managedTrain.trainCachedData.carriagesCachedData, 1, -1
    else
        error("TrainManager.CopyEnteringTrainUnderground() doesn't support 0 speed refTrain.\nrefTrain id: " .. approachingTrain.id)
    end

    -- See if any players in the train as a whole. In general there aren't.
    local playersInTrain = #approachingTrain.passengers > 0

    -- Iterate over the carriages and clone them.
    local refCarriageData  ---@type Utils_TrainCarriageData
    local lastPlacedCarriage  ---@type LuaEntity
    local lastPlacedCarriage_name  ---@type string
    local carriageOrientation, carriage_faceingFrontOfTrain, driver
    local newLeadCarriageUnitNumber  ---@type UnitNumber
    for currentSourceTrainCarriageIndex = minCarriageIndex, maxCarriageIndex, carriageIterator do
        refCarriageData = managedTrain.trainCachedData.carriagesCachedData[currentSourceTrainCarriageIndex]
        -- Some carriage data will have been cached by Utils.GetTrainSpeedCalculationData() before this function call. With secodanry tunnel use by same train in same direction having all data pre-cached.

        carriage_faceingFrontOfTrain = refCarriageData.faceingFrontOfTrain
        if carriage_faceingFrontOfTrain == nil then
            -- Data not known so obtain and cache.
            if refCarriageData.entity.speed > 0 == managedTrain.approachingTrainMovingForwards then
                carriage_faceingFrontOfTrain = managedTrain.approachingTrainMovingForwards
            else
                carriage_faceingFrontOfTrain = not managedTrain.approachingTrainMovingForwards
            end
            refCarriageData.faceingFrontOfTrain = carriage_faceingFrontOfTrain
        end
        if carriage_faceingFrontOfTrain then
            carriageOrientation = trainCarriagesForwardOrientation
        else
            -- Functionality from Utils.LoopFloatValueWithinRangeMaxExclusive()
            carriageOrientation = trainCarriagesForwardOrientation + 0.5
            if carriageOrientation >= 1 then
                carriageOrientation = 0 + (carriageOrientation - 1)
            elseif carriageOrientation < 0 then
                carriageOrientation = 1 - (carriageOrientation - 0)
            end
        end

        nextCarriagePosition = TrainManager.GetNextCarriagePlacementPosition(managedTrain.trainTravelOrientation, nextCarriagePosition, lastPlacedCarriage_name, refCarriageData.prototypeName)
        lastPlacedCarriage = TrainManager.CopyCarriage(targetSurface, refCarriageData.entity, nextCarriagePosition, nil, carriageOrientation)
        lastPlacedCarriage_name = refCarriageData.prototypeName

        -- Update data cache.
        refCarriageData.entity = lastPlacedCarriage

        -- If this is the first carriage in the trains carriage cache update the cache's lead carriage unit number for reference in future lookup of the data.
        if currentSourceTrainCarriageIndex == 1 then
            newLeadCarriageUnitNumber = lastPlacedCarriage.unit_number
        end

        -- Make the cloned carriage invunerable so that it can't be killed while "underground".
        lastPlacedCarriage.destructible = false

        -- If the train has any players in it then check each carriage for a player and handle them.
        if playersInTrain then
            driver = lastPlacedCarriage.get_driver()
            if driver ~= nil then
                managedTrain.undergroundTrainHasPlayersRiding = true
                PlayerContainer.PlayerInCarriageEnteringTunnel(managedTrain, driver, lastPlacedCarriage)
            end
        end
    end

    local leavingTrain = lastPlacedCarriage.train

    -- Update the train cache objects Id from the old train id to the new train id. As we've updated the entities in this object already.
    MOD.Interfaces.TrainCachedData.UpdateTrainCacheId(managedTrain.approachingTrainId, leavingTrain.id, newLeadCarriageUnitNumber)

    return leavingTrain
end

--- Get the new carriage's poisition. This currently only handles straight track, but when curved track is introduced it will get more complicated.
---@param trainOrientation RealOrientation
---@param lastPosition Position
---@param lastCarriageEntityName string
---@param nextCarriageEntityName string
---@return Position
TrainManager.GetNextCarriagePlacementPosition = function(trainOrientation, lastPosition, lastCarriageEntityName, nextCarriageEntityName)
    local carriagesDistance = Common.CarriagePlacementDistances[nextCarriageEntityName]
    if lastCarriageEntityName ~= nil then
        carriagesDistance = carriagesDistance + Common.CarriagePlacementDistances[lastCarriageEntityName]
    end
    return Utils.RotateOffsetAroundPosition(trainOrientation, {x = 0, y = carriagesDistance}, lastPosition)
end

--- Copy a carriage by cloning it to the new position and handle rotations.
---@param targetSurface LuaSurface
---@param refCarriage LuaEntity
---@param newPosition Position
---@param safeCarriageFlipPosition Position @ Not used until we need to support corners.
---@param requiredOrientation RealOrientation @ Not used until we need to support corners.
---@return LuaEntity
TrainManager.CopyCarriage = function(targetSurface, refCarriage, newPosition, safeCarriageFlipPosition, requiredOrientation)
    -- until we add support for corners or non straight tunnel portal areas we never need to flip a carriage.
    local sourceCarriage = refCarriage
    if 1 == 0 then
        game.print(safeCarriageFlipPosition, requiredOrientation)
    end

    -- Work out if we will need to flip the cloned carriage or not.
    --[[local orientationDif = math.abs(refCarriage.orientation - requiredOrientation)
    local haveToFlipCarriage = false
    if orientationDif > 0.25 and orientationDif < 0.75 then
        -- Will need to flip the carriage.
        haveToFlipCarriage = true
    elseif orientationDif == 0.25 or orientationDif == 0.75 then
        -- May end up the correct way, depending on what rotation we want. Factorio rotates positive orientation when equally close.
        if Utils.LoopOrientationValue(refCarriage.orientation + 0.25) ~= requiredOrientation then
            -- After a positive rounding the carriage isn't going to be facing the right way.
            haveToFlipCarriage = true
        end
    end

    -- Create an intial clone of the carriage away from the train, flip its orientation, then clone the carriage to the right place. Saves having to disconnect the train and reconnect it.
    local tempCarriage ---@type LuaEntity
    local sourceCarriage ---@type LuaEntity
    if haveToFlipCarriage then
        tempCarriage = refCarriage.clone {position = safeCarriageFlipPosition, surface = targetSurface, create_build_effect_smoke = false}
        if tempCarriage.orientation == requiredOrientation then
            error("underground carriage flipping not needed, but predicted. \nrequiredOrientation: " .. tostring(requiredOrientation) .. "\ntempCarriage.orientation: " .. tostring(tempCarriage.orientation) .. "\nrefCarriage.orientation: " .. tostring(refCarriage.orientation))
        end
        tempCarriage.rotate()
        sourceCarriage = tempCarriage
    else
        sourceCarriage = refCarriage
    end--]]
    -- Transitioning train has its carriages set to be the tunnel force so that the player can't interfear with them or see them as a random stopped train in their train list.
    local placedCarriage = sourceCarriage.clone {position = newPosition, surface = targetSurface, create_build_effect_smoke = false, force = global.force.tunnelForce}
    if placedCarriage == nil then
        error("failed to clone carriage:" .. "\nsurface name: " .. targetSurface.name .. "\nposition: " .. Logging.PositionToString(newPosition) .. "\nsource carriage unit_number: " .. refCarriage.unit_number)
    end

    --[[if haveToFlipCarriage then
        tempCarriage.destroy()
    end
    if placedCarriage.orientation ~= requiredOrientation then
        error("placed underground carriage isn't correct orientation.\nrequiredOrientation: " .. tostring(requiredOrientation) .. "\nplacedCarriage.orientation: " .. tostring(placedCarriage.orientation) .. "\nrefCarriage.orientation: " .. tostring(refCarriage.orientation))
    end]]
    return placedCarriage
end

-- Dummy train can be used to keep the train stop reservations as it has near 0 power and so while actively moving, it will never actaully move any distance. Also can be used without a schedule to block tracks and trigger signals.
---@param exitPortal Portal
---@param dummyTrainPosition Position
---@param trainSchedule TrainSchedule
---@param targetTrainStop LuaEntity
---@param skipScheduling boolean
---@param force LuaForce
---@return LuaEntity dummyTrain
TrainManager.CreateDummyTrain = function(exitPortal, dummyTrainPosition, trainSchedule, targetTrainStop, skipScheduling, force)
    skipScheduling = skipScheduling or false
    local locomotive =
        exitPortal.surface.create_entity {
        name = "railway_tunnel-tunnel_exit_dummy_locomotive",
        position = dummyTrainPosition,
        direction = exitPortal.leavingDirection,
        force = force,
        raise_built = false,
        create_build_effect_smoke = false
    }
    locomotive.destructible = false
    locomotive.operable = false -- Don't let the player try and change the dummy trains orders.

    local dummyTrain = locomotive.train
    if not skipScheduling then
        TrainManager.TrainSetSchedule(dummyTrain, trainSchedule, false, targetTrainStop, false)
        if global.debugRelease and dummyTrain.state == defines.train_state.destination_full then
            -- If the train ends up in one of those states something has gone wrong.
            error("dummy train has unexpected state '" .. tonumber(dummyTrain.state) .. "' at position: " .. Logging.PositionToString(dummyTrainPosition))
        end
    end
    return locomotive
end

---@param managedTrain ManagedTrain
TrainManager.DestroyDummyTrain = function(managedTrain)
    -- Dummy trains are never passed between trainManagerEntries, so don't have to check the global trainIdToManagedTrain's managedTrain id.
    if managedTrain.dummyTrainCarriage ~= nil and managedTrain.dummyTrainCarriage.valid then
        managedTrain.dummyTrainCarriage.destroy()
    end
    managedTrain.dummyTrainCarriage = nil
end

-- Remove the carriage that was forcing closed the entrance portal entry signal if its still present.
---@param managedTrain ManagedTrain
TrainManager.DestroyEntranceSignalClosingLocomotive = function(managedTrain)
    if managedTrain.entranceSignalClosingCarriage ~= nil and managedTrain.entranceSignalClosingCarriage.valid then
        managedTrain.entranceSignalClosingCarriage.destroy {raise_destroy = false} -- Is a special carriage so no other mods need notifying.
    end
    managedTrain.entranceSignalClosingCarriage = nil
end

--- Sets a trains schedule and returns it to automatic, while handling if the train should be in manual mode.
---@param train LuaTrain
---@param schedule TrainSchedule
---@param isManual boolean
---@param targetTrainStop LuaEntity
---@param skipStateCheck boolean
TrainManager.TrainSetSchedule = function(train, schedule, isManual, targetTrainStop, skipStateCheck)
    train.schedule = schedule
    if not isManual then
        TrainManager.SetTrainToAuto(train, targetTrainStop)
        if global.debugRelease and not skipStateCheck and not TrainManager.IsTrainHealthlyState(train) then
            -- Any issue on the train from the previous tick should be detected by the state check. So this should only trigger after misplaced wagons.
            error("train doesn't have positive state after setting schedule.\ntrain id: " .. train.id .. "\nstate: " .. train.state)
        end
    else
        train.manual_mode = true
    end
end

--- Check if a train has a healthy state (not a pathing failure state).
---@param train LuaTrain
---@return boolean
TrainManager.IsTrainHealthlyState = function(train)
    -- Uses state and not LuaTrain.has_path, as a train waiting at a station doesn't have a path, but is a healthy state.
    local trainState = train.state
    if trainState == defines.train_state.no_path or trainState == defines.train_state.path_lost then
        return false
    else
        return true
    end
end

--- Sets the train to automatic and forces the train within a train stops limited train count if required.
---@param train LuaTrain
---@param targetTrainStop LuaEntity
TrainManager.SetTrainToAuto = function(train, targetTrainStop)
    --- Train limits on the original target train stop of the train going through the tunnel might prevent the exiting (dummy or real) train from pathing there, so we have to ensure that the original target stop has a slot open before setting the train to auto. The count of trains on route to a station don't update in real time and so during the tick both the deleted train and our new train will both be heading for the station.
    if targetTrainStop ~= nil and targetTrainStop.valid then
        local oldLimit = targetTrainStop.trains_limit
        targetTrainStop.trains_limit = targetTrainStop.trains_count + 1
        train.manual_mode = false -- This forces the train pathfinder to run and the trains state to settle.
        targetTrainStop.trains_limit = oldLimit
    else
        -- There was no target train stop, so no special handling needed.
        train.manual_mode = false
    end
end

--- Sets a leaving trains speed correctly when we are unsure of the trains facing direction or the direction of its target. Sets managedTrain.leavingTrainMovingForwards for future usage.
---OVERHAUL: DOESN'T ANY MORE: Also updates the managed train's directionalTrainSpeedCalculationData for a direction change.
--- In some cases where this is called the train does a reversal, i.e. when starting to leave a tunnel and finding the forwards path is blocked, but reversing through the tunnel is valid.
---@param train LuaTrain
---@param absoluteSpeed double
---@param managedTrain ManagedTrain
---@param schedulePathEndStop? LuaEntity|null @ Just pass through the targeted schedule end stop value and if its nil it will be handled.
TrainManager.SetLeavingTrainSpeedInCorrectDirection = function(train, absoluteSpeed, managedTrain, schedulePathEndStop)
    local relativeSpeed = absoluteSpeed -- Updated throughout the function as its found to be wrong.
    local initiallySetForwardsSpeed  ---@type boolean
    local speedWasWrongDirection = false -- If unchnaged means final speed dictates if facing right way. Allows some wrong ways having to set a speed to 0 for it just to be set straight back to a new value.

    -- Work out an initial speed to try.
    if managedTrain.leavingTrainMovingForwards == nil then
        -- No previous forwards direction known.

        -- Handle the train differently based on if it has loco's in one or 2 directions
        if managedTrain.trainCachedData.forwardFacingLocomotiveCount == 0 or managedTrain.trainCachedData.backwardFacingLocomotiveCount == 0 then
            -- Train can only go in 1 direction so we can just set one and if it turns out to be wrong set it for correcting at the end of the function.
            if managedTrain.trainFacingForwardsToCacheData then
                train.speed = absoluteSpeed
                initiallySetForwardsSpeed = true
            else
                relativeSpeed = -relativeSpeed
                train.speed = relativeSpeed
                initiallySetForwardsSpeed = false
            end

            -- Set the train to auto as this will trigger Factorio to set the speed to 0 if its an invalid direction speed.
            TrainManager.SetTrainToAuto(train, schedulePathEndStop)

            -- If speed is back to 0 then it was in the wrong direction.
            if train.speed == 0 then
                speedWasWrongDirection = true
            end
        else
            -- With dual direction trains and bi-directional tracks from the tunnel the train can path in both directions to its target conceptually. So we have to do a convoluted check to make sure we set it off in the right direction based on path. This layout could occur on some "normal" rail networks and so has to be handled nicely, despite it baing found in testing with an extreme edge case network (figure 8 through tunnel - BidirectionalTunnelLoop test).

            -- Set the train to auto so it gets a path. We will use the path to work out the correct leaving speed direction for the train.
            TrainManager.SetTrainToAuto(train, schedulePathEndStop)
            local trainPath = train.path
            if trainPath == nil then
                -- No path so just abort this and the calling code will handle this state.
                return
            end
            local initialPathRail_unitNumber = trainPath.rails[1].unit_number

            -- Have to set train back to manual before trying to set its speed as otherwise as it has a path and its the wrong direction it will error.
            train.manual_mode = true

            -- Set an initial best guess on the direction speed to try. The build forwards for the cache data is more accurate than the train's entering forwards state.
            if managedTrain.trainFacingForwardsToCacheData then
                train.speed = absoluteSpeed
                initiallySetForwardsSpeed = true
            else
                relativeSpeed = -relativeSpeed
                train.speed = relativeSpeed
                initiallySetForwardsSpeed = false
            end
            TrainManager.SetTrainToAuto(train, schedulePathEndStop) -- Have to do after setting speed again to get the train state to update right now.

            -- Check if the path with speed has the same first rail as the 0 speed one. If it is then this is the right direction, if its not then we have told a dual direction train to go on some reverse loop.
            local newTrainPath = train.path
            if newTrainPath == nil or newTrainPath.rails[1].unit_number ~= initialPathRail_unitNumber then
                -- Train is pathing the wrong direction or has no path in that direction. This function will correct it later on from the variable being set and will overwrite the speed.
                speedWasWrongDirection = true
                train.manual_mode = true -- Needed so we can correct the speed later on.
            end
        end
    else
        -- Previous forwards known so use this.
        if managedTrain.leavingTrainMovingForwards then
            train.speed = absoluteSpeed
            initiallySetForwardsSpeed = true
        else
            relativeSpeed = -relativeSpeed
            train.speed = relativeSpeed
            initiallySetForwardsSpeed = false
        end

        -- Set the train to auto as this will trigger Factorio to set the speed to 0 if its an invalid direction speed.
        TrainManager.SetTrainToAuto(train, schedulePathEndStop)

        -- If speed is back to 0 then it was in the wrong direction.
        if train.speed == 0 then
            speedWasWrongDirection = true
        end
    end

    -- Check the speed has applied, as if not we have tried to send a train backwards.
    if not speedWasWrongDirection then
        -- Speed was correct direction.
        managedTrain.leavingTrainMovingForwards = initiallySetForwardsSpeed
    else
        -- Speed was wrong direction so try the other direction.
        relativeSpeed = -relativeSpeed
        train.speed = relativeSpeed
        managedTrain.leavingTrainMovingForwards = not initiallySetForwardsSpeed
        TrainManager.SetTrainToAuto(train, schedulePathEndStop) -- Have to do after setting speed again to get the train state to update right now.
        if train.speed == 0 then
            -- Train state not suitable to hold speed in either direction. Set facing back to unknown and it will be handled by the main process functions.
            managedTrain.leavingTrainMovingForwards = nil
        end
    end

    -- OVERHAUL: I don't see why we ever need this. As a train during a single tunnel usage will always be the same direction to the cached data. The actual trains may flip/reverse on cloning, but they are always going the same direction for the concept train carriages that are cached. A change of direction that needs different acceleration data requires a stop on leaving and then the train to reverse and re-enter the tunnel, thus making a new tunnel usage and this will detect as needing the opposite acceleration data via the leading carriage check.
    -- If this is needed then the use of speed below needs replacing with use of managedTrain.trainFacingForwardsToCacheData and possibly this may require re-calculating? But I don't believe this should ever be needed.
    -- Update the managedTrains train speed calculation data if the direction is known.
    --[[
    if managedTrain.leavingTrainMovingForwards ~= nil then
        if managedTrain.leavingTrainMovingForwards then
            -- Train moving forwards.
            if managedTrain.forwardsDirectionalTrainSpeedCalculationDataUpdated then
                -- Data has been updated already for this managed train in this direction so can just use it.
                managedTrain.directionalTrainSpeedCalculationData = managedTrain.trainCachedData.forwardMovingTrainSpeedCalculationData
            else
                -- Data is old or non existint for this direction so get current data.
                MOD.Interfaces.TrainCachedData.UpdateTrainSpeedCalculationData(train, relativeSpeed, managedTrain.trainCachedData)
                managedTrain.directionalTrainSpeedCalculationData = managedTrain.trainCachedData.forwardMovingTrainSpeedCalculationData
                managedTrain.forwardsDirectionalTrainSpeedCalculationDataUpdated = true
            end
        else
            -- Train moving backwards.
            if managedTrain.backwardsDirectionalTrainSpeedCalculationDataUpdated then
                -- Data has been updated already for this managed train in this direction so can just use it.
                managedTrain.directionalTrainSpeedCalculationData = managedTrain.trainCachedData.backwardMovingTrainSpeedCalculationData
            else
                -- Data is old or non existint for this direction so get current data.
                MOD.Interfaces.TrainCachedData.UpdateTrainSpeedCalculationData(train, relativeSpeed, managedTrain.trainCachedData)
                managedTrain.directionalTrainSpeedCalculationData = managedTrain.trainCachedData.backwardMovingTrainSpeedCalculationData
                managedTrain.backwardsDirectionalTrainSpeedCalculationDataUpdated = true
            end
        end
    end]]
end

--- Called when the mod finds an invalid train and handles the situation. Calling function will need to stop processing after this function.
---@param managedTrain ManagedTrain
TrainManager.InvalidTrainFound = function(managedTrain)
    -- Find a suitable target entity for the alert GUI.
    local train, alertEntity
    for _, carriageData in pairs(managedTrain.trainCachedData.carriagesCachedData) do
        local carriage = carriageData.entity
        if carriage.valid then
            local carriage_train = carriage.train

            -- The carriage will have no train if it is being removed and its decoupling has triggered this InvallidTrainFound() function. In this case skip this carriage as it will be gone at the end of the tick.
            if carriage_train ~= nil then
                -- Cache a target for the GUI alert.
                if alertEntity == nil then
                    alertEntity = carriage
                    train = carriage_train
                end

                -- Stop the invalid train's carriages just to make things neater. The carriages may be in multiple trains now so do each one to be safe.
                carriage_train.speed = 0
                carriage_train.manual_mode = true
            end
        end
    end

    -- Only if a valid entity from the old train is found do we add an alert to it.
    if alertEntity ~= nil then
        TunnelShared.AlertOnTrain(train, train.id, alertEntity, managedTrain.force, game.tick, {"message.railway_tunnel-invalid_train"})
    end

    -- Return any leaving train carriages to their origional force and let them take damage again.
    if managedTrain.tunnelUsageState == TunnelUsageState.underground or managedTrain.tunnelUsageState == TunnelUsageState.leaving then
        for _, carriageData in pairs(managedTrain.trainCachedData.carriagesCachedData) do
            local carriage = carriageData.entity
            if carriage.valid then
                carriage.force = managedTrain.force
                carriage.destructible = true
            end
        end
    end

    -- Techncially this isn't ideal as a train remenant that ends up on the portal tracks should be known about. Although the tunnel signals would all be closed at this point anyways. There may be 2 seperate new trains on the portal tracks and the tracking doesn't handle this currently so leave until it actually causes an issue.
    TrainManager.TerminateTunnelTrip(managedTrain, TunnelUsageChangeReason.invalidTrain)
end

return TrainManager
