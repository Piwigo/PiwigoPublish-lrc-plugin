--[[

    Init.lua - Global Initialisation

    Copyright (C) 2024 Fiona Boston <fiona@fbphotography.uk>.

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

---@diagnostic disable: undefined-global

-- Global imports
_G.LrHttp = import 'LrHttp'
_G.LrDate = import 'LrDate'
_G.LrPathUtils = import 'LrPathUtils'
_G.LrFileUtils = import 'LrFileUtils'
_G.LrStringUtils = import 'LrStringUtils'
_G.LrTasks = import 'LrTasks'
_G.LrErrors = import 'LrErrors'
_G.LrDialogs = import 'LrDialogs'
_G.LrView = import 'LrView'
_G.LrBinding = import 'LrBinding'
_G.LrColor = import 'LrColor'
_G.LrFunctionContext = import 'LrFunctionContext'
_G.LrApplication = import 'LrApplication'
_G.LrPrefs = import 'LrPrefs'
_G.LrShell = import 'LrShell'
_G.LrSystemInfo = import 'LrSystemInfo'
_G.LrProgressScope = import 'LrProgressScope'
_G.LrHttp = import 'LrHttp'
_G.LrMD5 = import 'LrMD5'
_G.LrExportSession = import 'LrExportSession'
_G.LrExportSettings = import "LrExportSettings"

-- Global requires
_G.JSON = require "JSON"
_G.utils = require "utils"
_G.PiwigoAPI = require "PiwigoAPI"
_G.PWImportService = require "PWImportService"
_G.PWStatusManager = require "PWStatusManager"
_G.vtk_core = require "vtk_core"
_G.vtk_ui   = require "vtk_ui"

-- Global initializations
-- Detect macOS vs Windows based on path separator in Lightroom's standard paths
local testPath = LrPathUtils.getStandardFilePath("documents")
_G.MAC_ENV = testPath:find("/") and not testPath:find("\\") or false
_G.prefs = _G.LrPrefs.prefsForPlugin()
-- logger setup
_G.log = import 'LrLogger' ('PiwigoPublishPlugin')
if prefs.debugEnabled == nil then
    prefs.debugEnabled = false
end
if prefs.clearLogOnReload == nil then
    prefs.clearLogOnReload = false
end
if prefs.debugEnabled then
    if prefs.clearLogOnReload then
        utils.clearLogFiles()  -- truncate log at each reload (dev mode)
    end
    log:enable("logfile")
else
    log:disable()
end

_G.iconPath = _PLUGIN:resourceId("icons/icon_med.png")

-- Build version string from Info.lua VERSION table
--local versionInfo = _PLUGIN.VERSION or { major = 0, minor = 0, revision = 0 }
-- _PLUGIN.VERSION is nil here for some reason, so hardcoding for now
-- just need to ensure both places are updated together

_G.versionInfo = { major=20260305, minor=34, revision=0 }

_G.pluginVersion = string.format("%d.%d", versionInfo.major, versionInfo.minor)
-- Auto-update checker
_G.UpdateChecker = require "UpdateChecker"

-- Check for updates on plugin load (silent check)
LrTasks.startAsyncTask(function()
    -- Wait for Lightroom to fully load
    LrTasks.sleep(5)
    
    -- Only check if interval has passed
    if UpdateChecker.shouldCheckForUpdates() then
        log:info("Init - performing automatic update check")
        UpdateChecker.checkForUpdates(true) -- silent = true
    end
end)

