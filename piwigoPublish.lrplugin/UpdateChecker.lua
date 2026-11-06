--[[
    UpdateChecker.lua

    Auto-update functionality for Piwigo Publisher plugin
    Checks GitHub Releases API for new versions

    Copyright (C) 2024 Fiona Boston <fiona@fbphotography.uk>.
    Copyright (C) 2026 Julien Moreau

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

local LrHttp = import 'LrHttp'
local LrTasks = import 'LrTasks'
local LrDialogs = import 'LrDialogs'
local LrDate = import 'LrDate'

local UpdateChecker = {}

-- Configuration
UpdateChecker.GITHUB_OWNER = "Piwigo"
UpdateChecker.GITHUB_REPO = "PiwigoPublish-lrc-plugin"
UpdateChecker.CHECK_INTERVAL_DAYS = 1

-- *************************************************
function UpdateChecker.parseVersion(versionStr)
    -- Converts version strings to comparable numbers
    -- Supports two formats:
    --   Date-based: "20260111.26" or "v20260111.26" → YYYYMMDD * 1000 + revision
    --   SemVer: "1.2.3" or "v1.2.3" → major * 1000000 + minor * 1000 + patch

    if not versionStr or versionStr == "" then
        return 0, "unknown"
    end

    -- Remove 'v' prefix if present
    versionStr = tostring(versionStr):gsub("^[vV]", "")

    -- Check if it's date-based (starts with 20xx) or Semantic Versioning (starts with 1.x, 2.x, etc.)
    local firstPart = versionStr:match("^(%d+)")
    if not firstPart then
        return 0, "unknown"
    end

    if tonumber(firstPart) >= 20000000 then
        -- Date-based format: YYYYMMDD.revision
        local major, minor = versionStr:match("^(%d+)%.?(%d*)")
        major = tonumber(major) or 0
        minor = tonumber(minor) or 0
        return major * 1000 + minor, "date"
    else
        -- Semantic Versioning format: major.minor.patch
        local major, minor, patch = versionStr:match("^(%d+)%.?(%d*)%.?(%d*)")
        major = tonumber(major) or 0
        minor = tonumber(minor) or 0
        patch = tonumber(patch) or 0
        return major * 1000000 + minor * 1000 + patch, "semver"
    end
end

-- *************************************************
function UpdateChecker.parseGitHubDate(dateStr)
    -- Parses GitHub ISO 8601 date (e.g., "2026-01-21T15:30:00Z") to timestamp
    if not dateStr then return 0 end

    local year, month, day, hour, min, sec = dateStr:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
    if not year then return 0 end

    -- Convert to comparable number: YYYYMMDDHHMMSS
    return tonumber(string.format("%04d%02d%02d%02d%02d%02d",
        year, month, day, hour, min, sec)) or 0
end

-- *************************************************
function UpdateChecker.getInstalledVersionDate()
    -- Returns the install/build date from the version info
    -- For date-based: extracts YYYYMMDD from "20260111.26"
    -- For semver: uses a stored build date or returns 0

    --local versionInfo = _PLUGIN.VERSION or { major = 0, minor = 0, revision = 0 }
    -- _PLUGIN.VERSION is nil here for some reason
    -- use _G.versionInfo set in Init.lua
    log:info("UpdateChecker.getInstalledVersionDate - versionInfo\n" .. utils.serialiseVar(versionInfo))
    local major = versionInfo.major or 0
    log:info("UpdateChecker.getInstalledVersionDate - major: " .. tostring(major))
    if major >= 20000000 then
        -- Date-based: major IS the date
        return major
    else
        -- SemVer: check if we have a build date stored
        return prefs.pluginBuildDate or 0
    end
end

-- *************************************************
function UpdateChecker.extractMajorVersion(versionStr)
    -- Extracts major version number from SemVer format only.
    -- Returns major number, or nil if not SemVer (e.g., date-based format).
    if not versionStr or versionStr == "" then
        return nil
    end

    versionStr = tostring(versionStr):gsub("^[vV]", "")

    -- Only process SemVer (doesn't start with 20xx)
    local firstPart = versionStr:match("^(%d+)")
    if not firstPart or tonumber(firstPart) >= 20000000 then
        -- Date-based format, not SemVer
        return nil
    end

    -- Extract major from SemVer
    local major = versionStr:match("^(%d+)")
    return tonumber(major)
end

-- *************************************************
function UpdateChecker.fetchAndFilterReleases(targetMajor)
    -- Fetches all releases from GitHub and filters to SemVer versions matching targetMajor.
    -- Returns array of release tables or empty array on error.
    local url = string.format(
        "https://api.github.com/repos/%s/%s/releases?per_page=100",
        UpdateChecker.GITHUB_OWNER,
        UpdateChecker.GITHUB_REPO
    )

    log:info("UpdateChecker.fetchAndFilterReleases - fetching: " .. url)

    local response, headers = LrHttp.get(url, {
        { field = "Accept",     value = "application/vnd.github.v3+json" },
        { field = "User-Agent", value = "PiwigoPublish-Lightroom-Plugin" }
    })

    log:info("UpdateChecker.fetchAndFilterReleases - HTTP status: " .. tostring(headers and headers.status))

    if not response or (headers and headers.status ~= 200) then
        log:info("UpdateChecker.fetchAndFilterReleases - failed to fetch releases")
        return {}
    end

    local ok, releases = pcall(function() return JSON:decode(response) end)
    if not ok or not releases then
        log:info("UpdateChecker.fetchAndFilterReleases - failed to parse JSON")
        return {}
    end

    -- Filter to SemVer releases matching targetMajor
    local filtered = {}
    for _, release in ipairs(releases) do
        local tag = release.tag_name
        --if tag then
        if tag and not release.draft and not release.prerelease and not tag:find("%-") then
            local major = UpdateChecker.extractMajorVersion(tag)
            if major and major == targetMajor then
                table.insert(filtered, release)
                log:info("UpdateChecker.fetchAndFilterReleases - matched: " .. tag .. " (major=" .. major .. ")")
            else
                log:info("UpdateChecker.fetchAndFilterReleases - filtered out: " .. tag)
            end
        end
    end

    return filtered
end

-- *************************************************
function UpdateChecker.shouldCheckForUpdates()
    -- Returns true if enough time has passed since last check
    local lastCheck = prefs.lastUpdateCheck or 0
    local now = LrDate.currentTime()
    local daysSinceCheck = (now - lastCheck) / (24 * 60 * 60)

    log:info("UpdateChecker.shouldCheckForUpdates - days since last check: " .. string.format("%.1f", daysSinceCheck))

    return daysSinceCheck >= UpdateChecker.CHECK_INTERVAL_DAYS
end

-- *************************************************
function UpdateChecker.checkForUpdates(silent)
    log:info("UpdateChecker.checkForUpdates - silent: " .. tostring(silent))

    LrTasks.startAsyncTask(function()
        -- Update last check timestamp
        prefs.lastUpdateCheck = LrDate.currentTime()

        -- Get installed version and extract major version
        local installedMajor = UpdateChecker.extractMajorVersion(pluginVersion)
        log:info("UpdateChecker.checkForUpdates - installed version: " .. pluginVersion .. ", major: " .. tostring(installedMajor))

        -- If installed version is not SemVer, offer migration to v2.x.x (bridge from date-based to SemVer)
        if not installedMajor then
            log:info("UpdateChecker.checkForUpdates - installed version is date-based format, checking for v2.x.x migration path")

            local v2Releases = UpdateChecker.fetchAndFilterReleases(2)

            if #v2Releases > 0 then
                -- Find highest v2.x.x version
                local bestV2Release = nil
                local bestV2Num = 0
                for _, release in ipairs(v2Releases) do
                    local relNum, relFormat = UpdateChecker.parseVersion(release.tag_name)
                    if relNum > bestV2Num then
                        bestV2Num = relNum
                        bestV2Release = release
                    end
                end

                if bestV2Release then
                    local v2Version = bestV2Release.tag_name
                    local v2Changelog = bestV2Release.body or "No changelog available."
                    if #v2Changelog > 500 then
                        v2Changelog = v2Changelog:sub(1, 500) .. "..."
                    end

                    local v2DownloadUrl = bestV2Release.html_url

                    log:info("UpdateChecker.checkForUpdates - offering migration to: " .. v2Version)

                    local result = LrDialogs.confirm(
                        "Migrate to New Version",
                        string.format(
                            "A new major version of Piwigo Publisher is available!\n\n" ..
                            "Current version: %s (Legacy)\n" ..
                            "New version: %s (SemVer Release)\n\n" ..
                            "This new version uses improved versioning and includes important updates.\n\n" ..
                            "Changes:\n%s\n\n" ..
                            "Would you like to download it now?",
                            pluginVersion,
                            v2Version,
                            v2Changelog
                        ),
                        "Download",
                        "Later"
                    )

                    if result == "ok" then
                        UpdateChecker.openDownloadPage(v2DownloadUrl)
                    end
                end
            else
                log:info("UpdateChecker.checkForUpdates - no v2.x.x releases found")
                if not silent then
                    LrDialogs.message(
                        "Update Check",
                        string.format("You are running version %s. A new version format will be available soon.", pluginVersion),
                        "info"
                    )
                end
            end
            return
        end

        -- Fetch all releases and filter by major version
        local filteredReleases = UpdateChecker.fetchAndFilterReleases(installedMajor)

        if #filteredReleases == 0 then
            log:info("UpdateChecker.checkForUpdates - no releases found for major version " .. installedMajor)
            if not silent then
                LrDialogs.message(
                    "No Updates Available",
                    string.format("You are running the latest version (%s).", pluginVersion),
                    "info"
                )
            end
            return
        end

        -- Find the highest version in filtered releases
        local bestRelease = nil
        local bestNum = 0
        for _, release in ipairs(filteredReleases) do
            local relNum, relFormat = UpdateChecker.parseVersion(release.tag_name)
            if relNum > bestNum then
                bestNum = relNum
                bestRelease = release
            end
        end

        if not bestRelease then
            log:info("UpdateChecker.checkForUpdates - failed to parse filtered releases")
            if not silent then
                LrDialogs.message(
                    "Update Check Failed",
                    "Could not parse release information from GitHub.",
                    "warning"
                )
            end
            return
        end

        -- Extract version info from best match
        local remoteVersion = bestRelease.tag_name
        local publishedAt = bestRelease.published_at

        if not remoteVersion then
            log:info("UpdateChecker.checkForUpdates - no tag_name in best release")
            if not silent then
                LrDialogs.message(
                    "Update Check Failed",
                    "No release information found on GitHub.",
                    "warning"
                )
            end
            return
        end

        log:info("UpdateChecker.checkForUpdates - best remote version: " .. remoteVersion)
        log:info("UpdateChecker.checkForUpdates - published_at: " .. tostring(publishedAt))
        log:info("UpdateChecker.checkForUpdates - current version: " .. pluginVersion)

        -- Determine comparison method based on version formats
        local currentNum, currentFormat = UpdateChecker.parseVersion(pluginVersion)
        local remoteNum, remoteFormat = UpdateChecker.parseVersion(remoteVersion)

        log:info("UpdateChecker.checkForUpdates - currentNum: " .. currentNum .. " (" .. currentFormat .. ")")
        log:info("UpdateChecker.checkForUpdates - remoteNum: " .. remoteNum .. " (" .. remoteFormat .. ")")

        local updateAvailable = false

        if currentFormat == remoteFormat then
            -- Same format: direct comparison
            updateAvailable = (remoteNum > currentNum)
            log:info("UpdateChecker.checkForUpdates - same format comparison: " .. tostring(updateAvailable))
        else
            -- Different formats: compare by GitHub publish date vs installed version date
            local remoteDate = UpdateChecker.parseGitHubDate(publishedAt)
            local installedDate = UpdateChecker.getInstalledVersionDate()

            log:info("UpdateChecker.checkForUpdates - cross-format: remoteDate=" .. remoteDate .. ", installedDate=" .. installedDate)

            -- If we can't determine installed date, fall back to assuming update is available
            if installedDate == 0 then
                updateAvailable = true
                log:info("UpdateChecker.checkForUpdates - unknown install date, assuming update available")
            else
                -- Compare: remoteDate is YYYYMMDDHHMMSS, installedDate is YYYYMMDD
                -- Normalize installedDate to same format (assume 00:00:00)
                updateAvailable = (remoteDate > installedDate * 1000000)
            end
        end

        -- If SemVer versions, ensure they match major version (safety check)
        if currentFormat == "semver" and remoteFormat == "semver" then
            local remoteMajor = UpdateChecker.extractMajorVersion(remoteVersion)
            if remoteMajor ~= installedMajor then
                log:info("UpdateChecker.checkForUpdates - major version mismatch, rejecting update")
                updateAvailable = false
            end
        end

        if updateAvailable then
            -- New version available
            local changelog = bestRelease.body or "No changelog available."
            -- Truncate changelog if too long
            if #changelog > 500 then
                changelog = changelog:sub(1, 500) .. "..."
            end

            local downloadUrl = bestRelease.html_url or
                string.format("https://github.com/%s/%s/releases/latest",
                    UpdateChecker.GITHUB_OWNER, UpdateChecker.GITHUB_REPO)

            -- Store for later use
            prefs.latestVersion = remoteVersion
            prefs.latestVersionUrl = downloadUrl

            log:info("UpdateChecker.checkForUpdates - new version available!")

            local result = LrDialogs.confirm(
                "Update Available",
                string.format(
                    "A new version of Piwigo Publisher is available!\n\n" ..
                    "Current version: %s\n" ..
                    "New version: %s\n\n" ..
                    "Changes:\n%s\n\n" ..
                    "Would you like to download it now?",
                    pluginVersion,
                    remoteVersion,
                    changelog
                ),
                "Download",
                "Later"
            )

            if result == "ok" then
                UpdateChecker.openDownloadPage(downloadUrl)
            end
        else
            log:info("UpdateChecker.checkForUpdates - already up to date")
            if not silent then
                LrDialogs.message(
                    "No Updates Available",
                    string.format("You are running the latest version (%s).", pluginVersion),
                    "info"
                )
            end
        end
    end)
end

-- *************************************************
function UpdateChecker.checkForMajorVersionNotice(silent)
    local installedMajor = UpdateChecker.extractMajorVersion(pluginVersion)
    if not installedMajor then return end        -- date-based users handled by existing migration path

    if prefs.notifiedV3Available then return end -- already told them

    local nextMajor = installedMajor + 1
    local releases = UpdateChecker.fetchAndFilterReleases(nextMajor)

    if #releases > 0 then
        prefs.notifiedV3Available = true
        LrDialogs.message(
            "New Major Version Available",
            string.format(
                "Piwigo Publisher v%d.x is now available.\n\n" ..
                "This is a major upgrade that requires switching to Piwigo API key authentication " ..
                "before it will work — please read the release notes before installing.\n\n" ..
                "Major bugs discovered in v%d.x will continue to be fixed and patched, but no new functionality will be added.",
                nextMajor, installedMajor
            ),
            "info"
        )
    end
end

-- *************************************************
function UpdateChecker.openDownloadPage(url)
    log:info("UpdateChecker.openDownloadPage - opening: " .. url)
    LrHttp.openUrlInBrowser(url)

    LrDialogs.message(
        "Download Started",
        "The download page has been opened in your browser.\n\n" ..
        "After downloading:\n" ..
        "1. Quit Lightroom Classic\n" ..
        "2. Replace the plugin folder with the new version\n" ..
        "3. Restart Lightroom Classic",
        "info"
    )
end

-- *************************************************
function UpdateChecker.getUpdateStatus()
    -- Returns a status string for display in Plugin Manager
    local latestVersion = prefs.latestVersion
    local currentNum, currentFormat = UpdateChecker.parseVersion(pluginVersion)
    local latestNum, latestFormat = UpdateChecker.parseVersion(latestVersion or "")

    if latestVersion and latestNum > currentNum and currentFormat == latestFormat then
        return string.format("Update available: %s", latestVersion)
    elseif latestVersion then
        return "Up to date"
    else
        return "Not checked yet"
    end
end

return UpdateChecker
