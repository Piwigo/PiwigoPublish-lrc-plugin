--[[

    PWSendMetadata.lua

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

--*******************************************
local function SendMetadata()
    log:info("SendMetadata")
    local callStatus = {}
    local catalog = LrApplication.activeCatalog()

    local selPhotos = catalog:getTargetPhotos()
    local sources = catalog:getActiveSources()
    if utils.nilOrEmpty(selPhotos) then
        LrDialogs.message("Please select photos to resend metadata", "", "warning")
        return false
    end

    -- is source a LrPublishedCollection or LrPublishedCollectionSet in selected published service
    local useService = nil
    local useSource = nil
    local catId = nil
    local publishSettings = nil
    for s, source in pairs(sources) do
        if type(source) == "table" and source.type then
            local srcType = source:type()
            if srcType == "LrPublishedCollection" or srcType == "LrPublishedCollectionSet" then
                local thisService = source:getService()
                local thisSettings = thisService:getPublishSettings()
                -- is this publish service using this plugin?
                local thisPluginId = thisService:getPluginId()
                if thisPluginId == _PLUGIN.id then
                    useService = thisService
                    useSource = source
                    catId = source:getRemoteId()
                    publishSettings = thisSettings
                    break
                end
            end
        end
    end
    if not useService then
        LrDialogs.message("Please select photos in a Piwigo Publisher service", "", "warning")
        return false
    end
    if not publishSettings then
        LrDialogs.message("SendMetadata - Can't find publish settings for this publish collection", "", "warning")
        return false
    end

    if not useSource then
        LrDialogs.message("SendMetadata - Can't find publish collection source", "", "warning")
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
        functionContext = context,
    }

    for pp, lrPhoto in pairs(selPhotos) do
        if progressScope:isCanceled() then
            break
        end
        progressScope:setPortionComplete(pp, #selPhotos)
        progressScope:setCaption("Processing " .. pp .. " of " .. #selPhotos .. " photographs")
        -- find publised photo in this collection / set
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
        callStatus = {}
        local metaData = {}
        local collectionSettings = {}
        -- todo - get collections for collection this photo is in so  collection level overrides can be applied when building metadata structure
        -- build metadata structure
        metaData = utils.getPhotoMetadata(publishSettings, lrPhoto,  collectionSettings)
        metaData.Remoteid = remoteId

        -- get keyword filters from publishSettings and build include / exclude patterns

        callStatus = PiwigoAPI.updateMetadata(publishSettings, lrPhoto, metaData)
        if not callStatus.status then
            LrDialogs.message("Unable to set metadata for uploaded photo - " .. callStatus.statusMsg)
        end
    end
    progressScope:done()
end

LrTasks.startAsyncTask(SendMetadata)
