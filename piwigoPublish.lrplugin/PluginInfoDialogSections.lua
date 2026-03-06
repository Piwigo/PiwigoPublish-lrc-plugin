--[[

	PluginInfoDialogSections.lua

	Plugin Manager Dialog Sections for Piwigo Publisher plugin

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

local LrHttp = import 'LrHttp'

PluginInfoDialogSections = {}

-- *************************************************
-- CONSTANTS
-- *************************************************
local GITHUB_URL = "https://github.com/Piwigo/PiwigoPublish-lrc-plugin"

-- *************************************************
-- HELPER FUNCTIONS
-- *************************************************
-- Reset plugin preferences (optionally filtered by prefix)
local function resetPluginPrefs(prefix)
    log:info("resetPluginPrefs \n" .. utils.serialiseVar(prefs))
    for k, _ in prefs:pairs() do
        if prefix then
            if k:find(prefix, 1, true) == 1 then
                prefs[k] = nil
            end
        else
            prefs[k] = nil
        end
    end
end

-- *************************************************
-- DIALOG LIFECYCLE
-- *************************************************
function PluginInfoDialogSections.startDialog(propertyTable)
    -- Initialize update status
    propertyTable.updateStatus = UpdateChecker.getUpdateStatus()

    -- Initialize debug preferences
    if prefs.debugEnabled == nil then
        prefs.debugEnabled = false
    end
    if prefs.debugToFile == nil then
        prefs.debugToFile = false
    end

    -- Initialize update check preference
    if prefs.checkUpdatesOnStartup == nil then
        prefs.checkUpdatesOnStartup = true
    end

    -- Apply debug settings
    if prefs.debugEnabled then
        if prefs.debugToFile then
            log:enable("logfile")
        else
            log:enable("print")
        end
    else
        log:disable()
    end

    propertyTable.debugEnabled = prefs.debugEnabled
    propertyTable.debugToFile = prefs.debugToFile
    propertyTable.checkUpdatesOnStartup = prefs.checkUpdatesOnStartup
end

-- *************************************************
function PluginInfoDialogSections.sectionsForTopOfDialog(f, propertyTable)
    local bind = LrView.bind
    local share = LrView.share

    return {
        -- ===================================
        -- SECTION 1: PLUG-IN INFO
        -- ===================================
        {
            bind_to_object = propertyTable,
            title = "Plug-in Info",
            synopsis = "Piwigo Publisher Plugin  •  Version " .. pluginVersion,
            fill = 1,
            spacing = f:control_spacing(),

            -- Two-column header layout (left: icon+identity, right: credits)
            f:row {
                spacing = f:dialog_spacing(),

                -- Left column: icon + plugin identity
                f:column {
                    spacing = f:control_spacing(),

                    f:row {
                        spacing = f:control_spacing(),

                        f:picture {
                            alignment = 'left',
                            value = iconPath,
                        },

                        f:column {
                            spacing = f:label_spacing(),

                            f:static_text {
                                title = "Piwigo Publisher",
                                font = "<system/bold>",
                                alignment = 'left',
								width = 250,
                            },

                            -- Version @ UpdateStatus on one line, red if not up to date
                            f:view {
                                bind_to_object = propertyTable,
                                f:static_text {
                                    title = LrView.bind {
                                        key = 'updateStatus',
                                        transform = function(value)
                                            return pluginVersion .. "  @  " .. (value or "")
                                        end,
                                    },
                                    font = "<system/small>",
                                    text_color = LrView.bind {
                                        key = 'updateStatus',
                                        transform = function(value)
                                            if value and value ~= "Up to date" then
                                                return LrColor(0.8, 0, 0)
                                            end
                                            return LrColor(0.5, 0.5, 0.5)
                                        end,
                                    },
                                    alignment = 'left',
                                },
                            },
                        },
                    },

                    f:row {
                        f:push_button {
                            title = "Visit Plugin Page…",
                            action = function()
                                LrHttp.openUrlInBrowser(GITHUB_URL)
                            end,
                        },
                    },

                    f:row {
                        f:static_text {
                            title = "Made in England with cider and cheddar cheese in Somerset,\n" ..
                                    "the Land of the Summer People.",
                            font = "<system/small>",
                            text_color = LrColor(0.5, 0.5, 0.5),
                            alignment = 'center',
                            fill_horizontal = 1,
                            height_in_lines = -1,
                        },
                    },
                },

                -- Right column: credits (no outer border — plain column)
                f:column {
                    fill_horizontal = 1,
                    spacing = f:label_spacing(),
                    margin_left = f:dialog_spacing(),

                    -- Developer row
                    f:row {
                        spacing = f:control_spacing(),
                        f:static_text {
                            title = "Developer:",
                            width = share 'credit_label_width',
                            alignment = 'right',
                        },
                        f:column {
                            spacing = f:label_spacing(),
                            f:static_text {
                                title = "Fiona Boston",
                                alignment = 'left',
                            },
                            f:static_text {
                                title = "fiona@fbphotography.uk",
                                alignment = 'left',
                                text_color = LrColor("blue"),
                                mouse_down = function()
                                    LrHttp.openUrlInBrowser("mailto:fiona@fbphotography.uk")
                                end,
                            },
                            f:push_button {
                                title = "Visit website…",
                                action = function()
                                    LrHttp.openUrlInBrowser("https://gallery.coastwisesomerset.org.uk/")
                                end,
                            },
                        },
                    },

                    f:separator { fill_horizontal = 1 },

                    -- Contributor row
                    f:row {
                        spacing = f:control_spacing(),
                        f:static_text {
                            title = "Contributor:",
                            width = share 'credit_label_width',
                            alignment = 'right',
                        },
                        f:column {
                            spacing = f:label_spacing(),
                            f:static_text {
                                title = "Julien Moreau",
                                alignment = 'left',
                            },
                            f:static_text {
                                title = "contact@julien-moreau.fr",
                                alignment = 'left',
                                text_color = LrColor("blue"),
                                mouse_down = function()
                                    LrHttp.openUrlInBrowser("mailto:contact@julien-moreau.fr")
                                end,
                            },
                            f:push_button {
                                title = "Visit website…",
                                action = function()
                                    LrHttp.openUrlInBrowser("https://julien-moreau.fr")
                                end,
                            },
                        },
                    },
                },
            },
        },

        -- ===================================
        -- SECTION 2: PLUG-IN PREFERENCES
        -- ===================================
        {
            bind_to_object = propertyTable,
            title = "Plug-in Preferences",
            fill = 1,
            spacing = f:control_spacing(),

            -- Updates group box
            f:group_box {
                title = "Updates ",
                fill_horizontal = 1,
                spacing = f:control_spacing(),

                f:row {
                    f:checkbox {
                        value = bind 'checkUpdatesOnStartup',
                        title = "Check for updates when Lightroom starts",
                    },
                    f:spacer { fill_horizontal = 1 },
                    f:push_button {
                        title = "Check now",
                        action = function()
                            UpdateChecker.checkForUpdates(false)
                        end,
                    },
                },
            },

            -- Debug logging group box
            f:group_box {
                title = "Diagnostic Logging ",
                fill_horizontal = 1,
                spacing = f:control_spacing(),

                f:row {
                    fill_horizontal = 1,
                    f:static_text {
                        title = "If you experience a problem, enable logging below and reproduce the issue.\n" ..
                                "You can then share the log with support.",
                        fill_horizontal = 1,
                        height_in_lines = 2,
                        alignment = 'left',
                        text_color = LrColor(0.02, 0.15, 0.39),
                    },
                },

                f:row {
                    f:radio_button {
                        value = bind 'debugEnabled',
                        checked_value = false,
                        title = "Logging off",
                    },
                    f:spacer { fill_horizontal = 1 },
                },

                f:row {
                    f:radio_button {
                        value = bind 'debugEnabled',
                        checked_value = true,
                        title = "Live view in Lightroom (Help → Debug Console)",
                    },
                    f:spacer { fill_horizontal = 1 },
                    f:push_button {
                        title = "Open log file",
                        enabled = bind 'debugEnabled',
                        action = function()
                            LrShell.revealInShell(utils.getLogfilePath())
                        end,
                    },
                },

                f:row {
                    f:checkbox {
                        value = bind 'debugToFile',
                        enabled = bind 'debugEnabled',
                    },
                    f:static_text {
                        title = "Also save to log file on disk (recommended for sharing with support)",
                        alignment = 'left',
                        fill_horizontal = 1,
                        width_in_chars = 40,
                    },
                },
            },

            -- Unsafe / developer group box
            f:group_box {
                title = "Unsafe area — Development only ",
                fill_horizontal = 1,
                spacing = f:control_spacing(),

                f:row {
                    fill_horizontal = 1,
                    f:static_text {
                        title = "Intended for plugin development and troubleshooting only.",
                        fill_horizontal = 1,
                        alignment = 'left',
                        text_color = LrColor(0.85, 0.45, 0),
                    },
                    f:push_button {
                        title = "Reset Preferences…",
                        action = function()
                            local result = LrDialogs.confirm(
                                "Reset Plugin Preferences",
                                "This will delete all saved settings for this plugin.\n\n" ..
                                "This cannot be undone.",
                                "Reset",
                                "Cancel"
                            )
                            if result == "ok" then
                                resetPluginPrefs()
                                LrDialogs.message(
                                    "Preferences Reset",
                                    "Plugin preferences have been cleared.",
                                    "info"
                                )
                            end
                        end,
                    },
                },
            },
        },

    }
end

-- *************************************************
function PluginInfoDialogSections.endDialog(propertyTable)
    prefs.debugEnabled = propertyTable.debugEnabled
    prefs.debugToFile = propertyTable.debugToFile
    prefs.checkUpdatesOnStartup = propertyTable.checkUpdatesOnStartup

    -- Apply debug settings
    if prefs.debugEnabled then
        if prefs.debugToFile then
            log:enable("logfile")
        else
            log:enable("print")
        end
    else
        log:disable()
    end
end
