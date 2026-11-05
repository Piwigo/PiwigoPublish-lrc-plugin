--[[

    PWStatusManager.lua

    Copyright (C) 2025 Fiona Boston <fiona@fbphotography.uk>.

    This file is part of PiwigoPublish

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

--*******************************************
-- manage service status between functions

local PWStatusManager = {}

local pwServiceState = {}

-- Lightroom runs each publish in its own Lua environment, so module-level tables are NOT shared
-- between concurrent operations. The busy lock is therefore held in plugin prefs (shared across environments):
-- piwigoBusyOwner = localIdentifier of the service holding the lock, piwigoBusyTime = last heartbeat.
-- A lock with no heartbeat for BUSY_STALE_SECONDS is treated as abandoned (e.g. LrC crashed while busy).
local BUSY_STALE_SECONDS = 600

--*******************************************
local function sharedPrefs()
    return import 'LrPrefs'.prefsForPlugin()
end

--*******************************************
local function currentBusyOwner()
    local p = sharedPrefs()
    local owner = p.piwigoBusyOwner
    if owner == nil or owner == "" then
        return nil
    end
    if os.time() - (p.piwigoBusyTime or 0) > BUSY_STALE_SECONDS then
        log:info("PWStatusManager - ignoring stale busy lock held by service " .. tostring(owner))
        return nil
    end
    return owner
end

--*******************************************
local function ensureState(publishService)
    local id = publishService.localIdentifier
    local state = pwServiceState[id]
    if not state then
        state = {
            PiwigoBusy = false,
            RenderPhotos = false,
            isCloningSync = false,
            RemoteInfoTable = {},
        }
        pwServiceState[id] = state
        log:info("PWStatusManager: created new state for service " .. id)
    end
    return state
end

--*******************************************
function PWStatusManager.getServiceState(publishService)
    -- manage per publish service status flags
    return ensureState(publishService)
end

--*******************************************
function PWStatusManager.setPiwigoBusy(publishService, setValue)
    local id = publishService.localIdentifier
    ensureState(publishService).PiwigoBusy = setValue
    if setValue then
        sharedPrefs().piwigoBusyOwner = id
        sharedPrefs().piwigoBusyTime = os.time()
    elseif sharedPrefs().piwigoBusyOwner == id then
        -- only the holder may release
        sharedPrefs().piwigoBusyOwner = ""
        sharedPrefs().piwigoBusyTime = 0
    end
    log:info("PWStatusManager.setPiwigoBusy - service " .. tostring(id) .. " = " .. tostring(setValue))
end

--*******************************************
-- test-and-set the shared busy lock (no yielding calls between test and set)
-- exclusive across ALL services as they share the catalog write lock and login session
-- returns true if acquired, false if another operation already holds it
function PWStatusManager.tryAcquireBusy(publishService)
    local id = publishService.localIdentifier
    local owner = currentBusyOwner()
    if owner then
        log:info("PWStatusManager.tryAcquireBusy - REFUSED for service " .. tostring(id) ..
            ", held by service " .. tostring(owner))
        return false
    end
    PWStatusManager.setPiwigoBusy(publishService, true)
    log:info("PWStatusManager.tryAcquireBusy - ACQUIRED for service " .. tostring(id))
    return true
end

--*******************************************
-- refresh the heartbeat while a long operation is running
function PWStatusManager.touchBusy(publishService)
    if sharedPrefs().piwigoBusyOwner == publishService.localIdentifier then
        sharedPrefs().piwigoBusyTime = os.time()
    end
end

--*******************************************
-- true if any operation (in any publish service) holds the shared busy lock
function PWStatusManager.isPiwigoBusy(publishService)
    return currentBusyOwner() ~= nil
end

--*******************************************
function PWStatusManager.setRenderPhotos(publishService, setValue)
    ensureState(publishService).RenderPhotos = setValue
end

--*******************************************
function PWStatusManager.setisCloningSync(publishService, setValue)
    ensureState(publishService).isCloningSync = setValue
end

--*******************************************
-- store remote info for a collection
function PWStatusManager.storeRemoteInfo(publishService, collId, RemoteInfoTable)
    local state = ensureState(publishService)
    state.RemoteInfoTable[collId] = RemoteInfoTable
end

--*******************************************
-- get remote info for a collection
function PWStatusManager.getRemoteInfo(publishService, collId)
    local state = ensureState(publishService)
    return state.RemoteInfoTable[collId]
end

--*******************************************
-- clear remote info for a collection
function PWStatusManager.clearRemoteInfo(publishService, collId)
    local state = ensureState(publishService)
    state.RemoteInfoTable[collId] = nil
end

--*******************************************
return PWStatusManager
