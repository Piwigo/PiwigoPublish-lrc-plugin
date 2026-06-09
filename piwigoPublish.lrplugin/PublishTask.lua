--[[

    PublishTask.lua

    Publish Tasks for Piwigo Publisher plugin

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

PublishTask = {}

-- ************************************************
function PublishTask.canAddCommentsToService(publishSettings)
    log:info("PublishTask.canAddCommentToPublishedPhoto")
    -- check if Piwgo has comments enabled
    --local commentsEnabled = PiwigoAPI.pwCheckComments(publishSettings)
    local commentsEnabled = true
    return commentsEnabled
end

-- ************************************************
function PublishTask.didCreateNewPublishService(publishSettings, info)
    log:info("PublishTask.didCreateNewPublishService")
    -- remove default collection if present
    local catalog = LrApplication.activeCatalog()
    local publishService = info.publishService
    local childCollections = publishService:getChildCollections() or {}
    for i, childColl in pairs(childCollections) do
        if childColl:getName() == "default" then
            catalog:withWriteAccessDo("Delete default collection", function()
                childColl:delete()
            end)
        end
    end
end

-- ************************************************
function PublishTask.didUpdatePublishService(publishSettings, info)
    log:info("PublishTask.didUpdatePublishService")
end

-- ************************************************
function PublishTask.shouldDeletePublishService(publishSettings, info)
    -- TODO
    -- Add dialog with details of photos and sub collections that will be orphaned if delete goes ahead
    log:info("PublishTask.shouldDeletePublishService")
end

-- ************************************************
function PublishTask.willDeletePublishService(publishSettings, info)
    -- TODO
    -- Add dialog with details of photos and sub collections that will be orphaned if delete goes ahead
    log:info("PublishTask.willDeletePublishService")
end

-- ************************************************
function PublishTask.shouldDeletePublishedCollection(publishSettings, info)
    -- TODO
    -- Add dialog with details of photos and sub collections that will be orphaned if delete goes ahead
    log:info("PublishTask.shouldDeletePublishedCollection")
end

-- ************************************************
function PublishTask.shouldDeletePhotosFromServiceOnDeleteFromCatalog(publishSettings, nPhotos)
    return nil -- Show builtin Lightroom dialog.
end

-- ************************************************
function PublishTask.imposeSortOrderOnPublishedCollection(publishSettings, info, remoteIdSequence)
    -- Keep this callback intentionally minimal and rely only on fields that are
    -- consistently present in Lightroom's callback payload.
    log:info("PublishTask.imposeSortOrderOnPublishedCollection")

    local finalSequence = remoteIdSequence or {}

    local shouldSync = false
    local collectionSettings = (info and info.collectionSettings) or {}
    local override = collectionSettings.syncSortOrderOverride or "default"
    log:info("PublishTask.imposeSortOrderOnPublishedCollection - syncSortOrderOverride: " .. override)
    if override == "always" then
        shouldSync = true
    elseif override == "never" then
        shouldSync = false
    else
        shouldSync = publishSettings.syncPhotoSortOrder or false
    end

    if shouldSync and #finalSequence > 0 then
        local categoryId = (info and (info.remoteCollectionId or info.remoteId)) or nil
        if categoryId then
            log:info("PublishTask.imposeSortOrderOnPublishedCollection - syncing sort order for category " ..
                tostring(categoryId) .. ", " .. #finalSequence .. " photos")
            -- If the companion server plugin is available, force album sorting to use rank first.
            if PiwigoAPI.hasPiwigoPublishServerPlugin(publishSettings, false) then
                local orderStatus = PiwigoAPI.pwCategoriesSetSortOrder(publishSettings, categoryId, "rank ASC")
                if not orderStatus.status then
                    log:info("PublishTask.imposeSortOrderOnPublishedCollection - unable to set image_order: " ..
                        (orderStatus.statusMsg or "unknown error"))
                end
            end

            local callStatus = PiwigoAPI.pwImagesSetRank(publishSettings, categoryId, finalSequence)
            if not callStatus.status then
                log:info("PublishTask.imposeSortOrderOnPublishedCollection - setRank failed: " ..
                    (callStatus.statusMsg or "unknown error"))
            end
        else
            log:info("PublishTask.imposeSortOrderOnPublishedCollection - no remoteId for collection, skipping sort sync")
        end
    end

    -- Return Lightroom's computed order unchanged.
    return finalSequence
end

-- ************************************************
function PublishTask.validatePublishedCollectionName(name)
    -- look for [ and ]
    if string.sub(name, 1, 1) == "[" or string.sub(name, -1) == "]" then
        return false, "Cannot use [ ] at start and end of album name - clashes with special collections"
    end

    return true
end

-- ************************************************
function PublishTask.getCollectionBehaviorInfo(publishSettings)
    return {
        defaultCollectionName = 'default',
        defaultCollectionCanBeDeleted = true,
        canAddCollection = true,
        -- Allow unlimited depth of collection sets
        -- maxCollectionSetDepth = 0,
    }
end

-- Functions for UI Management
-- *************************************************
local function valueEqual(a, b)
    -- Define a value_equal function for the popup_menu
    return a == b
end

-- ************************************************
-- ************************************************
-- Shared helpers for viewForCollectionSettings / viewForCollectionSetSettings
-- ************************************************
local function initCollectionSettingsDefaults(collectionSettings)
    local defaults = {
        albumDescription      = "",
        albumPrivate          = false,
        enableCustom          = false,
        reSize                = false,
        reSizeParam           = "Long Edge",
        reSizeNoEnlarge       = true,
        reSizeLongEdge        = 1024,
        reSizeShortEdge       = 1024,
        reSizeW               = 1024,
        reSizeH               = 1024,
        reSizeMP              = 5,
        reSizePC              = 50,
        metaData              = "All",
        metaDataNoPerson      = true,
        metaDataNoLocation    = false,
        mdTitle               = "{{title}}",
        mdDescription         = "{{caption}}",
        KwFullHierarchy       = true,
        KwSynonyms            = true,
        KwFilterInclude       = "",
        KwFilterExclude       = "",
        syncSortOrderOverride = "default",
    }
    for key, defaultVal in pairs(defaults) do
        if collectionSettings[key] == nil then
            collectionSettings[key] = defaultVal
        end
    end
end

-- ************************************************
local function buildCommonCollectionUI(f, bind, share, collectionSettings, publishSettings)
    local pwAlbumUI = UIHelpers.createPiwigoAlbumSettingsUI(f, share, bind, collectionSettings, publishSettings)

    local metaDataUI = UIHelpers.createMetaDataUI(f, bind, collectionSettings, publishSettings)

    local kwFilterUI = UIHelpers.createKeywordFilteringUI(f, bind, collectionSettings, publishSettings)

    local sortOrderUI = UIHelpers.createSortOrderUI(f, bind, collectionSettings, publishSettings)

    return pwAlbumUI, metaDataUI, sortOrderUI, kwFilterUI
end
-- ************************************************
function PublishTask.viewForCollectionSettings(f, publishSettings, info)
    log:info("PublishTask.viewForCollectionSettings")

    local thisName = info.name or ""
    if string.sub(thisName, 1, 1) == "[" and string.sub(thisName, -1) == "]" then
        LrDialogs.message(
            "Edit Piwigo Album",
            "Cannot edit special collection " .. thisName .. " created by Piwigo Publisher plugin",
            "info"
        )
        return false
    end

    local bind = LrView.bind
    local share = LrView.share
    local collectionSettings = assert(info.collectionSettings)

    initCollectionSettingsDefaults(collectionSettings)
    local pwAlbumUI, metaDataUI, sortOrderUI, kwFilterUI = buildCommonCollectionUI(f, bind, share, collectionSettings,
        publishSettings)

    local allowCustomAlbumSettings = publishSettings and publishSettings.PWP_customAlbumSettings == true
    local UI
    if allowCustomAlbumSettings then
        local customSettingsUI = UIHelpers.createExportSettingsGroupBox(f, bind, collectionSettings, publishSettings)
        UI = f:column {
            spacing = f:control_spacing(),
            pwAlbumUI,
            metaDataUI,
            sortOrderUI,
            kwFilterUI,
            customSettingsUI,
        }
    else
        UI = f:column {
            spacing = f:control_spacing(),
            pwAlbumUI,
        }
    end
    return UI
end

-- ************************************************
function PublishTask.updateCollectionSettings(publishSettings, info)
    -- this callback is triggered by LrC when a change is made to an existing collection or a new one is created

    -- We use it for the creation of new collections to create a corresponding album on Piwigo
    -- and to update album description on existing albums if set

    local metaData = {}
    local CollectionName = info.name
    local Collection = info.publishedCollection
    local publishService = info.publishService


    if not publishService then
        log:info('updateCollectionSettings - publishSettings:\n' ..
            utils.serialiseVar(utils.anonymisePropertyTable(publishSettings)))
        LrErrors.throwUserError('updateCollectionSettings - cannot connect find publishService')
        return nil
    end
    -- serviceState is a global table containing publishService specific statusData
    local serviceState = PWStatusManager.getServiceState(publishService)
    local serviceId = publishService.localIdentifier
    log:info("PublishTask.updateCollectionSettings")
    if serviceState.PiwigoBusy then
        -- pwigo processing another request - throw error
        error("Piwigo Publisher is busy. Please try later.")
    end

    local callStatus = {
        status = false,
        statusMsg = ""
    }

    local collectionSettings = assert(info.collectionSettings)
    -- piwigo album settings
    if collectionSettings.albumDescription == nil then
        collectionSettings.albumDescription = ""
    end
    if collectionSettings.albumPrivate == nil then
        collectionSettings.albumPrivate = false
    end

    local remoteId = Collection:getRemoteId()

    metaData.name = CollectionName
    metaData.type = "collection"
    metaData.remoteId = remoteId
    metaData.description = collectionSettings.albumDescription or ""
    if collectionSettings.albumPrivate then
        metaData.status = "private"
    else
        metaData.status = "public"
    end
    if not (utils.nilOrEmpty(remoteId)) then
        -- collection has a remoteId so get album from piwigo
        local thisCat = PiwigoAPI.pwCategoriesGetThis(publishSettings, remoteId)
        if not thisCat then
            LrErrors.throwUserError('Publish photos to Piwigo - cannot check category exists on piwigo at ' ..
                publishSettings.host)
            return nil
        end
        CallStatus = PiwigoAPI.pwCategoriesSetinfo(publishSettings, info, metaData)
        return CallStatus
    end

    -- create new album on Piwigo

    if utils.nilOrEmpty(info.parents) then
        -- creating album at root of publish service
        metaData.parentCat = ""
    else
        metaData.parentCat = info.parents[#info.parents].remoteCollectionId or ""
    end

    callStatus = PiwigoAPI.pwCategoriesAdd(publishSettings, info, metaData, callStatus)
    if callStatus.status then
        -- add remote id and url to collection
        local catalog = LrApplication.activeCatalog()

        -- switch to use PiwigoAPI.createPublishCollection
        catalog:withWriteAccessDo("Add Piwigo details to collections", function()
            Collection:setRemoteId(callStatus.newCatId)
            Collection:setRemoteUrl(publishSettings.host .. "/index.php?/category/" .. callStatus.newCatId)
        end)
        LrDialogs.message(
            "New Piwigo Album",
            "New Piwigo Album " .. metaData.name .. " created with Piwigo Cat Id " .. callStatus.newCatId,
            "info"
        )
    end

    return callStatus
end

-- ************************************************
function PublishTask.viewForCollectionSetSettings(f, publishSettings, info)
    local bind = LrView.bind
    local share = LrView.share
    local collectionSettings = assert(info.collectionSettings)


    initCollectionSettingsDefaults(collectionSettings)

    local pwAlbumUI, metaDataUI, sortOrderUI, kwFilterUI = buildCommonCollectionUI(f, bind, share, collectionSettings,
        publishSettings)

    local allowCustomAlbumSettings = publishSettings and publishSettings.PWP_customAlbumSettings == true
    local UI
    if allowCustomAlbumSettings then
        local customSettingsUI = UIHelpers.createExportSettingsGroupBox(f, bind, collectionSettings, publishSettings)
        UI = f:column {
            spacing = f:control_spacing(),
            pwAlbumUI,
            metaDataUI,
            sortOrderUI,
            kwFilterUI,
            customSettingsUI,
        }
    else
        UI = f:column {
            spacing = f:control_spacing(),
            pwAlbumUI,
        }
    end

    return UI
end

-- ************************************************
function PublishTask.updateCollectionSetSettings(publishSettings, info)
    -- this callback is triggered by LrC when a change is made to an existing collectionset and when a new one is created
    -- We use it only for the creation of new collections to create a corresponding album on Piwigo
    -- therefore we need to check if the associated piwigo album already exists and do nothing if so
    log:info("PublishTask.updateCollectionSetSettings")
    local CollectionName = info.name
    local Collection = info.publishedCollection
    local publishService = info.publishService

    if not publishService then
        log:info('updateCollectionSettings - publishSettings:\n' ..
            utils.serialiseVar(utils.anonymisePropertyTable(publishSettings)))
        LrErrors.throwUserError('updateCollectionSettings - cannot connect find publishService')
        return nil
    end
    -- serviceState is a global table containing publishService specific statusData
    local serviceState = PWStatusManager.getServiceState(publishService)
    local serviceId = publishService.localIdentifier
    if serviceState.PiwigoBusy then
        -- pwigo processing another request - throw error
        error("Piwigo Publisher is busy. Please try later.")
    end
    local callStatus = {
        status = false,
        statusMsg = ""
    }



    local collectionSettings = assert(info.collectionSettings)
    local remoteId = Collection:getRemoteId()
    local name = info.name


    -- piwigo album settings
    if collectionSettings.albumDescription == nil then
        collectionSettings.albumDescription = ""
    end
    if collectionSettings.albumPrivate == nil then
        collectionSettings.albumPrivate = false
    end
    -- check if remoteId is present on this collection
    local metaData = {}
    metaData.name = name
    metaData.remoteId = remoteId

    metaData.description = collectionSettings.albumDescription or ""
    if collectionSettings.albumPrivate then
        metaData.status = "private"
    else
        metaData.status = "public"
    end


    -- update albumdesc if album exists and set
    metaData.name = CollectionName
    metaData.type = "collectionset"
    metaData.description = collectionSettings.albumDescription
    log:info("PublishTask.updateCollectionSetSettings - info\n" .. utils.serialiseVar(info))
    log:info("PublishTask.updateCollectionSetSettings - metaData\n" .. utils.serialiseVar(metaData))
    if not (utils.nilOrEmpty(remoteId)) then
        -- collection has a remoteId so get album from piwigo
        local thisCat = PiwigoAPI.pwCategoriesGetThis(publishSettings, remoteId)
        if not thisCat then
            LrErrors.throwUserError('Publish photos to Piwigo - cannot check category exists on piwigo at ' ..
                publishSettings.host)
            return nil
        end
        CallStatus = PiwigoAPI.pwCategoriesSetinfo(publishSettings, info, metaData)
        return CallStatus
    end

    -- create new album on Piwigo

    if utils.nilOrEmpty(info.parents) then
        -- creating album at root of publish service
        metaData.parentCat = ""
    else
        metaData.parentCat = info.parents[#info.parents].remoteCollectionId or ""
    end

    callStatus = PiwigoAPI.pwCategoriesAdd(publishSettings, info, metaData, callStatus)
    if callStatus.status then
        -- add remote id and url to collection
        -- switch to use PiwigoAPI.createPublishCollectionSet
        local catalog = LrApplication.activeCatalog()
        catalog:withWriteAccessDo("Add Piwigo details to collections", function()
            Collection:setRemoteId(callStatus.newCatId)
            Collection:setRemoteUrl(publishSettings.host .. "/index.php?/category/" .. callStatus.newCatId)
        end)
        LrDialogs.message(
            "New Piwigo Album",
            "New Piwigo Album " .. metaData.name .. " created with id " .. callStatus.newCatId,
            "info"
        )
    end

    return callStatus
end

-- ************************************************
function PublishTask.reparentPublishedCollection(publishSettings, info)
    -- ablums being rearranged in publish service
    -- neee to reflect this in piwigo
    log:info("PublishTask.reparentPublishedCollection")

    local publishService = info.publishService
    if not publishService then
        log:info('reparentPublishedCollection - publishSettings:\n' ..
            utils.serialiseVar(utils.anonymisePropertyTable(publishSettings)))
        LrErrors.throwUserError('reparentPublishedCollection - cannot connect find publishService')
        return nil
    end
    -- serviceState is a global table containing publishService specific statusData
    local serviceState = PWStatusManager.getServiceState(publishService)
    local serviceId = publishService.localIdentifier
    if serviceState.PiwigoBusy then
        -- pwigo processing another request - throw error
        error("Piwigo Publisher is busy. Please try later.")
    end

    -- check for special collection and prevent change if so
    local publishCollection = info.publishedCollection

    -- check for special collections and do not delete Piwigo album if so
    -- can't check remote id against parent remote id as parent will be new parent not current
    -- so just check name format
    local thisName = info.name
    if string.sub(thisName, 1, 1) == "[" and string.sub(thisName, -1) == "]" then
        LrErrors.throwUserError("Cannot re-parent a special collection")
        return false
    end

    local callStatus = {}
    local allParents = info.parents
    local myCat = info.remoteId
    local parentCat
    -- which collection is being moved and to where
    if utils.nilOrEmpty(allParents) then
        parentCat = 0 -- move to root
    else
        parentCat = allParents[#allParents].remoteCollectionId
    end
    LrTasks.startAsyncTask(function()
        callStatus = PiwigoAPI.pwCategoriesMove(publishSettings, info, myCat, parentCat, callStatus)
        if not (callStatus.status) then
            LrErrors.throwUserError("Error moving album: " .. callStatus.statusMsg)
            return false
        end
        return true
    end)
end

-- ************************************************
function PublishTask.renamePublishedCollection(publishSettings, info)
    log:info("PublishTask.renamePublishedCollection")
    local callStatus = {}
    callStatus.status = false
    -- called for both collections and collectionsets
    local publishService = info.publishService
    if not publishService then
        log:info('renamePublishedCollection - publishSettings:\n' ..
            utils.serialiseVar(utils.anonymisePropertyTable(publishSettings)))
        LrErrors.throwUserError('renamePublishedCollection - cannot connect find publishService')
        return nil
    end
    -- serviceState is a global table containing publishService specific statusData
    local serviceState = PWStatusManager.getServiceState(publishService)
    local remoteId = info.remoteId
    local newName = info.name
    local collection = info.publishedCollection
    local oldName = collection:getName()
    local collectionSettings = nil
    if collection:type() == "LrPublishedCollectionSet" then
        collectionSettings = collection:getCollectionSetInfoSummary()
    else
        collectionSettings = collection:getCollectionInfoSummary()
    end
    local metaData = {}
    metaData.name = newName
    metaData.remoteId = remoteId
    metaData.oldName = oldName
    metaData.description = collectionSettings.albumDescription or ""
    if collectionSettings.albumPrivate then
        metaData.status = "private"
    else
        metaData.status = "public"
    end
    local serviceId = publishService.localIdentifier
    if string.sub(oldName, 1, 1) == "[" and string.sub(oldName, -1) == "]" then
        callStatus.statusMsg = "Cannot re-name a special collection"
    else
        if utils.nilOrEmpty(remoteId) then
            callStatus.statusMsg = "no album found on Piwigo"
        else
            if serviceState.PiwigoBusy then
                callStatus.statusMsg = "Piwigo Publisher is busy. Please try later."
            else
                callStatus = PiwigoAPI.pwCategoriesSetinfo(publishSettings, info, metaData)
            end
        end
    end
    if (callStatus.status) then
        -- if this is Publishedcollection then need to update metadata in photos in this collection
        -- address metadata changes if any
        -- go through all published photos in this collection and update metadata
        -- need to check that remoteUrl is same as metadata field as photo may be in multiple publish collections
        -- check all published photos in this collection
        log:info(
            "PublishTask.renamePublishedCollection - updating photo metadata in renamed collection - collection is a " ..
            collection:type())
        if collection:type() == "LrPublishedCollection" then
            -- only PublishedCollections have photos
            PiwigoAPI.updateMetaDataforCollection(publishSettings, collection, metaData)
        end
        -- if this is a publishedCollectionSet then need to check for special collection rename that and update photos in it
        if collection:type() == "LrPublishedCollectionSet" then
            -- check for special collection within collectionset and rename that, and check meta of photos in that collection
            PiwigoAPI.updateMetaDataforCollectionSet(publishSettings, collection, metaData)
        end
    else
        LrTasks.startAsyncTask(function()
            LrFunctionContext.callWithContext("revertRename", function(context)
                local cat = LrApplication.activeCatalog()
                cat:withWriteAccessDo("Revert failed rename", function()
                    collection:setName(oldName)
                end)
            end)
        end)
        LrDialogs.message(
            "Rename Failed",
            "The Piwigo rename failed (" .. callStatus.statusMsg .. ").\nThe collection name has been reverted.",
            "warning"
        )
    end
end

-- ************************************************
function PublishTask.deletePublishedCollection(publishSettings, info)
    log:info("PublishTask.deletePublishedCollection")

    local publishService = info.publishService
    local publishCollection = info.publishedCollection
    if not publishService then
        log:info('deletePublishedCollection - publishSettings:\n' ..
            utils.serialiseVar(utils.anonymisePropertyTable(publishSettings)))
        LrErrors.throwUserError('deletePublishedCollection - cannot connect find publishService')
        return nil
    end
    -- serviceState is a global table containing publishService specific statusData
    local serviceState = PWStatusManager.getServiceState(publishService)
    if serviceState.PiwigoBusy then
        -- pwigo processing another request - throw error
        error("Piwigo Publisher is busy. Please try later.")
    end

    -- called for both collections and collectionsets
    local rv
    local callStatus = {}
    callStatus.status = false
    local catToDelete = info.remoteId



    -- check for special collections and do not delete Piwigo album if so
    local thisName = info.name
    local thisRemoteId = info.remoteId
    local parentName = ""
    local parentRemoteId = ""
    local parents = info.parents
    if #parents > 0 then
        parentName = parents[#parents].name
        parentRemoteId = parents[#parents].remoteCollectionId
    end

    if parentRemoteId == thisRemoteId then
        -- this is a special collection with the same remote id as it's parent so do not delete remote album
        -- check photos in collection and remove them from Piwigo
        if publishCollection:type() == "LrPublishedCollection" then
            local photosInCollection = publishCollection:getPublishedPhotos()
            for p, thisPhoto in pairs(photosInCollection) do
                log:info("PublishTask.deletePublishedCollection - delete photo " .. thisPhoto:getRemoteId())
                local pwImageID = thisPhoto:getRemoteId() or ""
                if pwImageID ~= "" then
                    -- delete photo from piwigo
                    local rtnStatus = PiwigoAPI.deletePhoto(publishSettings, thisRemoteId, pwImageID, callStatus)
                end
            end
        end
        --LrDialogs.message("Delete Album","Special Collection - no Piwigo album to delete.", "warning")
        return true
    end

    local metaData = {
        catToDelete = catToDelete,
        publishService = publishService
    }
    if utils.nilOrEmpty(catToDelete) then
        LrDialogs.message("Delete Album", "This collection has no associated Piwigo album to delete.", "warning")
    else
        rv = PiwigoAPI.pwCategoriesDelete(publishSettings, info, metaData, callStatus)
    end
    return true
end

-- ************************************************
function PublishTask.goToPublishedCollection(publishSettings, info)
    log:info("PublishTask.goToPublishedCollection")
    --local remoteId = info.remoteId or ""
end

-- ************************************************
function PublishTask.goToPublishedPhoto(publishSettings, info)
    log:info("PublishTask.goToPublishedPhoto")
    --local remoteId = info.remoteId or ""
end
