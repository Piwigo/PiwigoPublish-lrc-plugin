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

require "UIHelpers"

-- *************************************************
-- Define a value_equal function for the popup_menu
local function valueEqual(a, b)
    return a == b
end

-- *************************************************
local function setAlbumCoverFromSelection(service)
    log:info("PWExtraOptions.setAlbumCoverFromSelection")

    local catalog = LrApplication.activeCatalog()
    local selPhotos = catalog:getTargetPhotos()
    local sources = catalog:getActiveSources()

    if utils.nilOrEmpty(selPhotos) then
        LrDialogs.message("Please select a photo to set as album cover", "", "warning")
        return false
    end
    if #selPhotos > 1 then
        LrDialogs.message("Please select a single photo to set as album cover (" .. #selPhotos .. " currently selected)",
            "", "warning")
        return false
    end

    local selPhoto = selPhotos[1]
    local useSource = nil

    for _, source in pairs(sources or {}) do
        if type(source) == "table" and source.type then
            local srcType = source:type()
            if srcType == "LrPublishedCollection" or srcType == "LrPublishedCollectionSet" then
                local thisService = source:getService()
                if thisService and thisService.localIdentifier == service.localIdentifier then
                    useSource = source
                    break
                end
            end
        end
    end

    if not useSource then
        LrDialogs.message("Please select a photo in a collection from the selected Piwigo Publisher service", "",
            "warning")
        return false
    end

    local publishSettings = service:getPublishSettings()
    local catId = useSource:getRemoteId()
    if not catId then
        LrDialogs.message("SetAlbumCover - Can't find Piwigo album ID for remoteId for this publish collection", "",
            "warning")
        return false
    end

    local thisPubPhoto = utils.findPhotoInCollectionSet(useSource, selPhoto)
    if not thisPubPhoto then
        LrDialogs.message(
            "PWSetAlbumCover - Can't find this photo in collection set or collections - has it been published?", "",
            "warning")
        return false
    end

    local remoteId = thisPubPhoto:getRemoteId()
    if not remoteId or remoteId == "" then
        LrDialogs.message("PWSetAlbumCover - Can't find Piwigo photo ID for this photo - has it been published?", "",
            "warning")
        return false
    end

    local result = LrDialogs.confirm("Set Piwigo Album Cover",
        "Set selected photo as cover photo for " .. useSource:getName() .. "?", "Ok", "Cancel")
    if result ~= 'ok' then
        return false
    end

    if not publishSettings.Connected then
        local rv = PiwigoAPI.login(publishSettings)
        if not rv then
            LrDialogs.message("SetAlbumCover - cannot connect to Piwigo")
            return false
        end
    end

    if publishSettings.userStatus ~= "webmaster" then
        LrDialogs.message("User needs webmaster role on Piwigo gallery at " ..
            publishSettings.host .. " to set album cover")
        return false
    end

    local params = {
        { name = "method",      value = "pwg.categories.setRepresentative" },
        { name = "category_id", value = catId },
        { name = "image_id",    value = remoteId },
    }
    local postResponse = PiwigoAPI.httpPostMultiPart(publishSettings, params)
    if not postResponse.status then
        LrDialogs.message("Unable to set cover photo - " .. postResponse.statusMsg)
        return false
    end

    return true
end

-- *************************************************
local function sendMetadataForSelection(service)
    log:info("PWExtraOptions.sendMetadataForSelection")

    local catalog = LrApplication.activeCatalog()
    local selPhotos = catalog:getTargetPhotos()
    local sources = catalog:getActiveSources()

    if utils.nilOrEmpty(selPhotos) then
        LrDialogs.message("Please select photos to resend metadata", "", "warning")
        return false
    end

    local useSource = nil
    for _, source in pairs(sources or {}) do
        if type(source) == "table" and source.type then
            local srcType = source:type()
            if srcType == "LrPublishedCollection" or srcType == "LrPublishedCollectionSet" then
                local thisService = source:getService()
                if thisService and thisService.localIdentifier == service.localIdentifier then
                    useSource = source
                    break
                end
            end
        end
    end

    if not useSource then
        LrDialogs.message("Please select photos in a collection from the selected Piwigo Publisher service", "", "warning")
        return false
    end

    local publishSettings = service:getPublishSettings()
    if not publishSettings then
        LrDialogs.message("SendMetadata - Can't find publish settings for this publish collection", "", "warning")
        return false
    end

    local result = LrDialogs.confirm("Send Metadata to Piwigo",
        "Send metadata to Piwigo for " .. #selPhotos .. " photo(s) in album " .. useSource:getName() .. "?", "Ok",
        "Cancel")
    if result ~= 'ok' then
        return false
    end

    local progressScope = LrProgressScope {
        title = "Update Metadata...",
        caption = "Starting...",
    }

    for pp, lrPhoto in pairs(selPhotos) do
        if progressScope:isCanceled() then
            break
        end
        progressScope:setPortionComplete(pp, #selPhotos)
        progressScope:setCaption("Processing " .. pp .. " of " .. #selPhotos .. " photographs")

        local thisPubPhoto = utils.findPhotoInCollectionSet(useSource, lrPhoto)
        if not thisPubPhoto then
            LrDialogs.message(
                "SendMetadata - Can't find this photo in collection set or collections - has it been published?", "",
                "warning")
            progressScope:done()
            return false
        end

        local remoteId = thisPubPhoto:getRemoteId()
        if not remoteId then
            LrDialogs.message("SendMetadata - Can't find Piwigo photo ID for this photo - has it been published?", "",
                "warning")
            progressScope:done()
            return false
        end

        local metaData = utils.getPhotoMetadata(publishSettings, lrPhoto, {})
        metaData.Remoteid = remoteId

        local callStatus = PiwigoAPI.updateMetadata(publishSettings, lrPhoto, metaData)
        if not callStatus.status then
            LrDialogs.message("Unable to set metadata for uploaded photo - " .. callStatus.statusMsg)
        end
    end

    progressScope:done()
    return true
end

-- *************************************************
local function convertSelectionCollectionToSet(service)
    log:info("PWExtraOptions.convertSelectionCollectionToSet")

    local catalog = LrApplication.activeCatalog()
    local sources = catalog:getActiveSources()

    local selectedCollection = nil
    for _, source in pairs(sources or {}) do
        if type(source) == "table" and source.type then
            local srcType = source:type()
            if srcType == "LrPublishedCollection" or srcType == "LrPublishedCollectionSet" then
                local thisService = source:getService()
                if thisService and thisService.localIdentifier == service.localIdentifier then
                    selectedCollection = source
                    break
                end
            end
        end
    end

    if not selectedCollection then
        LrDialogs.message("CollToSet - Can't access selected collection in the chosen service", "", "warning")
        return false
    end

    if selectedCollection:type() == "LrPublishedCollectionSet" then
        LrDialogs.message(
            "CollToSet - You selected a Published Collection Set. Please select a Published Collection.", "",
            "warning")
        return false
    end

    local publishSettings = service:getPublishSettings()
    if not publishSettings then
        LrDialogs.message("CollToSet - Can't find publish settings for this publish collection", "", "warning")
        return false
    end

    local selCollName = selectedCollection:getName()
    local selColParent = selectedCollection:getParent()
    local catId = selectedCollection:getRemoteId()

    if selColParent then
        if selCollName == PiwigoAPI.buildSpecialCollectionName(selColParent:getName()) then
            LrDialogs.message("Special collections cannot be converted to Collection Sets", "", "warning")
            return false
        end
    end

    local result = LrDialogs.confirm("Convert Published Collection to Set",
        "Convert " .. selCollName .. " to a Published Collection Set?", "Ok", "Cancel")
    if result ~= 'ok' then
        return false
    end

    local newName = PiwigoAPI.buildSpecialCollectionName(selCollName)
    local rv = PiwigoAPI.setCollectionDets(selectedCollection, catalog, publishSettings, newName, catId, selColParent)

    local newCollSet = PiwigoAPI.createPublishCollectionSet(catalog, service, publishSettings, selCollName, catId,
        selColParent)
    if not newCollSet then
        LrDialogs.message("CollToSet - Can't create new collection set " .. selCollName, "", "warning")
        return false
    end

    rv = PiwigoAPI.setCollectionDets(selectedCollection, catalog, publishSettings, newName, catId, newCollSet)
    return rv
end

-- *************************************************
local function syncCurrentAlbumSortNow(service)
    log:info("PWExtraOptions.syncCurrentAlbumSortNow")

    local catalog = LrApplication.activeCatalog()
    local sources = catalog:getActiveSources()

    local useCollection = nil
    local publishSettings = service and service:getPublishSettings() or nil

    for _, source in pairs(sources or {}) do
        if type(source) == "table" and source.type and source:type() == "LrPublishedCollection" then
            local thisService = source:getService()
            if thisService and thisService.localIdentifier == service.localIdentifier then
                useCollection = source
                break
            end
        end
    end

    if not useCollection then
        LrDialogs.message("Please select a published collection in the selected Piwigo Publisher service.", "", "warning")
        return false
    end

    local categoryId = useCollection:getRemoteId()
    if utils.nilOrEmpty(categoryId) then
        LrDialogs.message("Selected collection has no linked Piwigo album (missing remote ID).", "", "warning")
        return false
    end

    if not publishSettings then
        LrDialogs.message("Cannot read publish settings for the selected collection.", "", "warning")
        return false
    end

    local publishedPhotos = useCollection:getPublishedPhotos() or {}
    if #publishedPhotos == 0 then
        LrDialogs.message("Selected collection has no published photos to sync.", "", "warning")
        return false
    end

    local imageIdSequence = {}
    for _, pubPhoto in ipairs(publishedPhotos) do
        local remoteId = pubPhoto:getRemoteId()
        if not utils.nilOrEmpty(remoteId) then
            table.insert(imageIdSequence, tostring(remoteId))
        end
    end

    if #imageIdSequence == 0 then
        LrDialogs.message("No publishable remote photo IDs were found in the selected collection.", "", "warning")
        return false
    end

    local result = LrDialogs.confirm(
        "Sync Current Album Sort Now",
        "Sync the current Lightroom order for " .. tostring(#imageIdSequence) .. " photo(s) to Piwigo album \"" ..
        useCollection:getName() .. "\"?",
        "Sync",
        "Cancel"
    )

    if result ~= "ok" then
        return false
    end

    local serverPluginAvailable = PiwigoAPI.hasPiwigoPublishServerPlugin(publishSettings, false)
    if not serverPluginAvailable then
        LrDialogs.message(
            "Piwigo server plugin unavailable",
            "The server method pwg.categories.setSortOrder is unavailable.\n" ..
            "Set album sort order manually in Piwigo (Album -> Edit -> Sort order: Manual).",
            "warning"
        )
    end

    if serverPluginAvailable then
        local orderStatus = PiwigoAPI.pwCategoriesSetSortOrder(publishSettings, categoryId, "rank ASC")
        if not orderStatus.status then
            LrDialogs.message("Unable to set album sort mode on Piwigo", orderStatus.statusMsg or "Unknown error",
                "warning")
            return false
        end
    end
    log:info("PWExtraOptions.syncCurrentAlbumSortNow - syncing sort order for category " ..
        tostring(categoryId) .. ", " .. #imageIdSequence .. " photos")
    log:info("Sort order is " .. utils.serialiseVar(imageIdSequence))
    local rankStatus = PiwigoAPI.pwImagesSetRank(publishSettings, categoryId, imageIdSequence)
    if not rankStatus.status then
        LrDialogs.message("Unable to sync current album order to Piwigo", rankStatus.statusMsg or "Unknown error",
            "warning")
        return false
    end

    LrDialogs.message(
        "Album Sort Synced",
        "Synced current Lightroom order for " .. tostring(#imageIdSequence) .. " photo(s) to Piwigo album \"" ..
        useCollection:getName() .. "\".",
        "info"
    )
    return true
end

-- *************************************************
local function main()
    local share = LrView.share
    LrFunctionContext.callWithContext("PWExtraOptionsContext", function(context)
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
                value = i,
            })
        end

        local props = LrBinding.makePropertyTable(context)
        props.selectedService = 1

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
                    value = LrView.bind { key = 'selectedService', bind_to_object = props },
                    items = serviceNames,
                    value_equal = valueEqual,
                    width = 300,
                },
            },

            f:spacer { height = 20 },
            f:row {
                f:static_text {
                    title = "Applies to selected photos/collection",
                    font = "<system/bold>",
                    alignment = 'left',
                    fill_horizontal = 1,
                },
            },

            f:spacer { height = 4 },

            f:spacer { height = 1 },
            f:row {
                f:push_button {
                    title = 'Set Piwigo Album Cover',
                    tooltip = "Sets selected image as Piwigo album cover",
                    width = share 'buttonwidth',
                    action = function()
                        LrTasks.startAsyncTask(function()
                            local serviceNo = props.selectedService
                            local service = serviceItems[serviceNo] and serviceItems[serviceNo].value or nil
                            if not service then
                                LrDialogs.message("Error", "Could not find publish service", "error")
                                return
                            end
                            setAlbumCoverFromSelection(service)
                        end)
                    end,
                },
                f:static_text {
                    title = "Sets selected image as Piwigo album cover for the selected service",
                    alignment = 'left',
                    width_in_chars = 58,
                },
            },

            f:spacer { height = 1 },
            f:row {
                f:push_button {
                    title = 'Send Metadata to Piwigo',
                    tooltip = "Sends metadata for selected photos to Piwigo",
                    width = share 'buttonwidth',
                    action = function()
                        LrTasks.startAsyncTask(function()
                            local serviceNo = props.selectedService
                            local service = serviceItems[serviceNo] and serviceItems[serviceNo].value or nil
                            if not service then
                                LrDialogs.message("Error", "Could not find publish service", "error")
                                return
                            end
                            sendMetadataForSelection(service)
                        end)
                    end,
                },
                f:static_text {
                    title = "Sends metadata for selected photos in the selected service",
                    alignment = 'left',
                    width_in_chars = 58,
                },
            },

            f:spacer { height = 1 },
            f:row {
                f:push_button {
                    title = 'Convert Collection to Collection Set',
                    tooltip = "Converts selected published collection to a collection set",
                    width = share 'buttonwidth',
                    action = function()
                        LrTasks.startAsyncTask(function()
                            local serviceNo = props.selectedService
                            local service = serviceItems[serviceNo] and serviceItems[serviceNo].value or nil
                            if not service then
                                LrDialogs.message("Error", "Could not find publish service", "error")
                                return
                            end
                            convertSelectionCollectionToSet(service)
                        end)
                    end,
                },
                f:static_text {
                    title = "Converts selected published collection to a collection set",
                    alignment = 'left',
                    width_in_chars = 58,
                },
            },
--[[
-- currently commented out as LrC SDK doesn't expose current display order of photos in a published collection
-- will be revisited
            f:spacer { height = 1 },
            f:row {
                f:push_button {
                    title = 'Sync Current Album Sort Now',
                    tooltip = "Sends the current Lightroom order for selected published collection to Piwigo",
                    action = function()
                        LrTasks.startAsyncTask(function()
                            local serviceNo = props.selectedService
                            local service = serviceItems[serviceNo] and serviceItems[serviceNo].value or nil
                            if not service then
                                LrDialogs.message("Error", "Could not find publish service", "error")
                                return
                            end
                            syncCurrentAlbumSortNow(service)
                        end)
                    end,
                },
                f:static_text {
                    title = "Syncs selected published collection's current order to Piwigo",
                    alignment = 'left',
                    width_in_chars = 58,
                },
            },
            ]]
        }

        LrDialogs.presentModalDialog {
            title = "Piwigo Publisher Extra Options",
            contents = c,
            actionVerb = "Close",
            cancelVerb = "< exclude >",
        }
    end)
end

-- *************************************************
-- Run main()
LrTasks.startAsyncTask(main)
