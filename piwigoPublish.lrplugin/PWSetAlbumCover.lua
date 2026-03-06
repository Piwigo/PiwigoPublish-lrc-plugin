--[[

    PWSetAlbumCover.lua

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
local function SetAlbumCover()
    -- alternative routine that does not require a publish service to be selected


    log:info("SetAlbumCover")
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

    -- we now have a single photo.
    local selPhoto = selPhotos[1]
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
        LrDialogs.message("Please select a photo in a Piwigo Publisher service", "", "warning")
        return false
    end
    if not publishSettings then
        LrDialogs.message("SetAlbumCover - Can't find publish settings for this publish collection", "", "warning")
        return false
    end
    if not catId then
        LrDialogs.message("SetAlbumCover - Can't find Piwigo album ID for remoteId for this publish collection", "",
            "warning")
        return false
    end

    if not useSource then
        LrDialogs.message("SetAlbumCover - Can't find publish collection source", "", "warning")
        return false
    end

    -- find publised photo in this collection / set
    local thisPubPhoto = utils.findPhotoInCollectionSet(useSource, selPhoto)
    if not thisPubPhoto then
        LrDialogs.message(
        "PWSetAlbumCover - Can't find this photo in collection set or collections - has it been published?", "",
            "warning")
        return false
    end
    local remoteId = thisPubPhoto:getRemoteId()
    if not remoteId or remoteId == "" then
        LrDialogs.message("PWSetAlbumCover - Can't find Piwigo photo ID for this photo - has it been published?", "", "warning")
        return false
    end

    local result = LrDialogs.confirm("Set Piwigo Album Cover",
        "Set select photo as cover photo for " .. useSource:getName() .. "?", "Ok", "Cancel")
    if result ~= 'ok' then
        return false
    end
    log:info("Setting  photo " .. remoteId .. " as cover for " .. catId)
    -- set as the representative photo for an album.
    -- the Piwigo web service doesn't require that the photo belongs to the album but this function does
    -- use pwg.categories.setRepresentative(categoryId, photoId), POST only, Admin only

    local rv

    -- check connection to piwigo
    if not (publishSettings.Connected) then
        rv = PiwigoAPI.login(publishSettings)
        if not rv then
            LrDialogs.message("SetAlbumCover - cannot connect to piwigo")
            return false
        end
    end

    -- check role is admin level
    if publishSettings.userStatus ~= "webmaster" then
        LrDialogs.message("User needs webmaster role on piwigo gallery at " ..
        publishSettings.host .. " to set album cover")
        return false
    end

    -- now update Piwigo
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

LrTasks.startAsyncTask(SetAlbumCover)
