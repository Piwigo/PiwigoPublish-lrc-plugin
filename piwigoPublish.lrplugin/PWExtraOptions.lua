--[[
   
    PWExtraOptions.lua

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

require "UIHelpers"

-- *************************************************
-- Define a value_equal function for the popup_menu
local function valueEqual(a, b)

    return a == b
end
-- *************************************************
local function main()
	local share = LrView.share
    LrFunctionContext.callWithContext("PWExtraOptionsContext", function(context)
        -- Create a property table inside the context
        
        log:info("PWExtraOptions")

        local allServices = PiwigoAPI.getPublishServicesForPlugin(_PLUGIN.id)
        if #allServices == 0 then
            LrDialogs.message("No Piwigo publish services found.")
            return
        end
        local serviceItems = {}
        local serviceNames = {}
        for i, s in ipairs(allServices) do
            table.insert(serviceItems, {
                title = s:getName(),
                value = s,
            })
            table.insert(serviceNames, {
                title = s:getName(),
                value = i
            })
        end
        log:info("serviceItems\n" .. utils.serialiseVar(serviceItems))
        log:info("serviceNames\n" .. utils.serialiseVar(serviceNames))
        local props = LrBinding.makePropertyTable(context)
        local bind = LrView.bind
        -- Property table for UI bindings
        local props = bind {
            selectedService = 1, -- default to first service
        }

        local f = LrView.osFactory()
        local c = f:column {
            spacing = f:dialog_spacing(),

            UIHelpers.createPluginHeader(f, share, iconPath, pluginVersion),

            f:row {
                spacing = f:label_spacing(),

                f:static_text {
                    title = "Select publish service:",
                    alignment = 'right',
                    width = 150,
                },

                f:popup_menu {
                    value = LrView.bind{ key = 'selectedService', bind_to_object = props },
                    items = serviceNames,
                    value_equal = valueEqual,
                    width = 300,
                },
            },
            f:spacer { height = 20 },
            f:row {
                f:static_text {
                    title = "Applies to selected images",
                    font = "<system/bold>",
                    alignment = 'left',
                    fill_horizontal = 1,
                },
            },
            f:spacer { height = 1 },
            f:row {
                f:push_button {
                    title = "Set Piwigo Album Cover",
                    tooltip = "Sets selected image as Piwigo album cover ",
                    action = function(button)
                        LrTasks.startAsyncTask(function()
                            local serviceNo = props.selectedService
                            -- get service object for selected service
                            local service = serviceItems[serviceNo].value
                            if not service then
                                LrDialogs.message("Error", "Could not find publish service", "error")
                                return
                            end
                            PiwigoAPI.setAlbumCover(service )

                        end)
                    end,
                },
                f:static_text {
                    title = "Sets selected image as Piwigo album cover for this collection",
                    alignment = 'left',
                    -- width = share 'labelWidth',
                    width_in_chars = 50,
                },
            },
        }

        dialog = LrDialogs.presentModalDialog({
            title = "Piwigo Extra Options",
            contents = c,
            actionVerb = "Close",
        })
    end)
end

-- *************************************************
-- Run main()
LrTasks.startAsyncTask(main)