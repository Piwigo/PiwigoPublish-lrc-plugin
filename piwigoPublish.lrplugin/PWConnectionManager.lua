--[[

    PWConnectionManager.lua  (simple version)

    Copyright (C) 2026 Fiona Boston <fiona@fbphotography.uk>.

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
-- persist the Piwigo login session (cookies + token) in plugin prefs, keyed by publish service,
-- because propertyTable copies handed to Lightroom callbacks are unreliable.
--




local PWConnectionManager = {}

-- a stored session older than this is ignored and a fresh login is done.
-- Set this a little under how long your Piwigo server keeps a session alive.
local MAX_AGE_SECONDS = 3600

--*******************************************

local function prefKey(settings)
    local hostKey = string.lower(settings.host or "")
    local userKey = string.lower(settings.userName or "")
    return "piwigoSession_" .. tostring(hostKey) .. "_" .. tostring(userKey)
end

--*******************************************
-- store the session held in propertyTable (call straight after a successful login)
function PWConnectionManager.storeCredentials(propertyTable)
    if propertyTable.cookieHeader == nil or propertyTable.cookieHeader == ""
        or propertyTable.token == nil or propertyTable.token == "" then
        return false
    end
    -- always assign a whole new table so the change is persisted
    local key = prefKey(propertyTable)
    prefs[key] = {
        cookieHeader = propertyTable.cookieHeader,
        token = propertyTable.token,
        SessionCookie = propertyTable.SessionCookie,
        cookies = propertyTable.cookies,
        userStatus = propertyTable.userStatus,
        pwVersion = propertyTable.pwVersion,
        host = propertyTable.host,
        userName = propertyTable.userName,
        savedAt = os.time(),
    }
    log:info("PWConnectionManager.storeCredentials - stored session for service " .. key)
    return true
end

--*******************************************
-- restore the stored session into propertyTable.
-- returns true if a usable session was found, false if the caller needs to log in
function PWConnectionManager.loadCredentials(propertyTable)
    local key = prefKey(propertyTable)
    local s = prefs[key]
    if type(s) ~= "table" or not s.cookieHeader or not s.token then
        return false
    end
    if s.host ~= propertyTable.host or s.userName ~= propertyTable.userName then
        log:info("PWConnectionManager.loadCredentials - stored session is for a different host/user, ignoring")
        return false
    end
    if os.time() - (s.savedAt or 0) > MAX_AGE_SECONDS then
        log:info("PWConnectionManager.loadCredentials - stored session too old, ignoring")
        return false
    end

    propertyTable.pwurl = propertyTable.host .. "/ws.php?format=json"
    propertyTable.cookieHeader = s.cookieHeader
    propertyTable.token = s.token
    propertyTable.SessionCookie = s.SessionCookie
    propertyTable.cookies = s.cookies
    propertyTable.userStatus = s.userStatus
    propertyTable.pwVersion = s.pwVersion
    propertyTable.Connected = true
    propertyTable.ConCheck = false
    propertyTable.ConStatus = "Connected to Piwigo Gallery at " .. tostring(propertyTable.host) .. " as " .. tostring(s.userStatus) .. " - Piwigo version " .. tostring(s.pwVersion)
    log:info("PWConnectionManager.loadCredentials successful - loaded session for service " .. key)
    return true
end

--*******************************************
-- discard the stored session.
-- If failedCookie is given, only clear when the stored session is still that one, so a late failure
-- cannot wipe a newer session that another callback has just created.
-- returns true if something was cleared
function PWConnectionManager.clearCredentials(propertyTable, failedCookie)
    local key = prefKey(propertyTable)
    local s = prefs[key]
    if s == nil then
        return false
    end
    if failedCookie ~= nil and type(s) == "table" and s.cookieHeader ~= failedCookie then
        return false
    end
    prefs[key] = nil
    log:info("PWConnectionManager.clearCredentials - cleared session for service " .. key)
    return true
end

--*******************************************
function PWConnectionManager.ensureConnection(propertyTable)
    -- check connection status and login if necessary
    local rv = PWConnectionManager.loadCredentials(propertyTable)

    if rv then
        return true
    end

    PWConnectionManager.clearCredentials(propertyTable)
    rv = PiwigoAPI.login(propertyTable)
    return rv
end

--*******************************************
function PWConnectionManager.clearCredentialsFromPrefs(prefsTable)
    -- clear all authentication credentials held in prefs
    -- run on initialization and closedown to remove all credentials
    local source = rawget(prefsTable, "< contents >") or prefsTable
    local stale = {}
    for k in pairs(source) do
        if type(k) == "string" and k:find("^piwigoSession_") then
            stale[#stale + 1] = k
        end
    end
    for _, k in ipairs(stale) do
        prefsTable[k] = nil
    end
    log:info("PWConnectionManager.clearCredentialsFromPrefs - cleared " .. #stale .. " stored sessions")
    return #stale
end

--*******************************************
return PWConnectionManager
