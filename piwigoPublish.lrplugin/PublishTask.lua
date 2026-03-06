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

---@diagnostic disable: undefined-global

PublishTask = {}

-- ************************************************
-- Reconcile album metadata (description, privacy) between Lightroom and Piwigo.
-- Returns true to proceed, false if cancelled by user.
local function reconcileAlbumMeta(publishSettings, collectionSettings, thisCat)
    if not thisCat then return true end

    local lrDesc = collectionSettings.albumDescription or ""
    local pwDesc = thisCat.comment or ""
    local lrPrivate = collectionSettings.albumPrivate or false
    local pwPrivate = (thisCat.status == "private")

    local descDiff = (lrDesc ~= pwDesc)
    local statusDiff = (lrPrivate ~= pwPrivate)

    if not descDiff and not statusDiff then return true end

    local descMode = publishSettings.albumDescSyncMode or "ask"
    local statusMode = publishSettings.albumStatusSyncMode or "ask"

    -- Resolve automatically when a forced mode is set
    if descDiff and descMode == "piwigo" then
        collectionSettings.albumDescription = pwDesc
        descDiff = false
    end
    if statusDiff and statusMode == "piwigo" then
        collectionSettings.albumPrivate = pwPrivate
        statusDiff = false
    end
    if descDiff and descMode == "lightroom" then
        descDiff = false
    end
    if statusDiff and statusMode == "lightroom" then
        statusDiff = false
    end

    -- If all diffs resolved by forced modes, proceed
    if not descDiff and not statusDiff then return true end

    -- Strip HTML tags for display
    local function stripHtml(s)
        if not s or s == "" then return s end
        -- Strip all HTML tags
        s = s:gsub("<[^>]+>", "")
        -- Decode common HTML entities
        s = s:gsub("&nbsp;", " "):gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&#39;", "'")
        -- Linearize: replace newlines/carriage returns with a single space
        s = s:gsub("[\r\n]+", " ")
        -- Collapse multiple spaces
        s = s:gsub("  +", " ")
        -- Trim
        s = s:gsub("^%s+", ""):gsub("%s+$", "")
        return s
    end

    -- Build conflict dialog with formatted view
    local f = LrView.osFactory()
    local rows = {}

    table.insert(rows, f:static_text {
        title = "Differences detected between Lightroom and Piwigo:",
        font = "<system/bold>",
        fill_horizontal = 1,
    })
    table.insert(rows, f:static_text { title = " ", height_in_lines = 1 })

    if descDiff then
        table.insert(rows, f:static_text {
            title = "Album Description",
            font = "<system/bold>",
        })
        table.insert(rows, f:static_text { title = " ", height_in_lines = 2 })
        table.insert(rows, f:row {
            f:static_text { title = "Lightroom:", font = "<system>", width = 80 },
            f:static_text {
                title = lrDesc == "" and "(empty)" or stripHtml(lrDesc),
                font = "<system/italic>",
                width_in_chars = 50,
                height_in_lines = 3,
            },
        })
        table.insert(rows, f:row {
            f:static_text { title = "Piwigo:", font = "<system>", width = 80 },
            f:static_text {
                title = pwDesc == "" and "(empty)" or stripHtml(pwDesc),
                font = "<system/italic>",
                width_in_chars = 50,
                height_in_lines = 3,
            },
        })
        table.insert(rows, f:static_text { title = " ", height_in_lines = 1 })
    end

    if statusDiff then
        table.insert(rows, f:static_text {
            title = "Album Privacy Status",
            font = "<system/bold>",
        })
        table.insert(rows, f:static_text { title = " ", height_in_lines = 1 })
        table.insert(rows, f:row {
            f:static_text { title = "Lightroom:", font = "<system>", width = 80 },
            f:static_text {
                title = lrPrivate and "Private" or "Public",
                font = "<system/italic>",
            },
        })
        table.insert(rows, f:row {
            f:static_text { title = "Piwigo:", font = "<system>", width = 80 },
            f:static_text {
                title = pwPrivate and "Private" or "Public",
                font = "<system/italic>",
            },
        })
        table.insert(rows, f:static_text { title = " ", height_in_lines = 1 })
    end

    table.insert(rows, f:separator { fill_horizontal = 1 })
    table.insert(rows, f:static_text { title = " ", height_in_lines = 1 })
    table.insert(rows, f:static_text {
        title = "Your choice will overwrite the other version. This cannot be undone.",
        font = "<system/bold>",
        text_color = LrColor(0.8, 0, 0),
        fill_horizontal = 1,
    })

    local contents = f:column(rows)

    local dialogResult = LrDialogs.presentModalDialog({
        title = "Album conflict: " .. (thisCat.name or ""),
        contents = contents,
        actionVerb = "Keep Lightroom (overwrite Piwigo)",
        cancelVerb = "Cancel",
        otherVerb = "Keep Piwigo (overwrite Lightroom)",
    })

    if dialogResult == "cancel" then
        return false
    elseif dialogResult == "other" then
        if descDiff then collectionSettings.albumDescription = pwDesc end
        if statusDiff then collectionSettings.albumPrivate = pwPrivate end
    end

    return true
end

-- ************************************************
function PublishTask.processRenderedPhotos(functionContext, exportContext)
    -- render photos and upload to Piwigo

    log:info("PublishTask.processRenderedPhotos - version: " .. utils.serialiseVar(_PLUGIN.VERSION))
    local callStatus = {}
    local catalog = LrApplication.activeCatalog()
    local exportSession = exportContext.exportSession
    local propertyTable = exportContext.propertyTable

    local publishedCollection = exportContext.publishedCollection
    local publishService = publishedCollection:getService()
    local rv
    if not publishService then
        log:info('PublishTask.processRenderedPhotos - publishSettings:\n' .. utils.serialiseVar(propertyTable))
        LrErrors.throwUserError('Publish photos to Piwigo - cannot connect find publishService')
        return nil
    end

    local collectionInfo = publishedCollection:getCollectionInfoSummary()
    local collectionSettings = collectionInfo.collectionSettings or {}
    local collServiceState = {}
    local serviceState = {}
    if collectionSettings then
        collServiceState = collectionSettings.serviceState or {}
    end
    -- serviceState is a table containing publishService specific statusData
    if collServiceState then
        serviceState = collServiceState
    else
        serviceState = PWStatusManager.getServiceState(publishService)
    end
    log:info("PublishTask.processRenderedPhotos - serviceState " .. utils.serialiseVar(serviceState))
    if serviceState.isCloningSync and serviceState.isCloningSync == true then
        PWStatusManager.setisCloningSync(publishService, false)
        -- use minimal render photos for smart collection cloning
        PublishTask.processCloneSync(functionContext, exportContext)
        return
    end
    if serviceState.PiwigoBusy then
        return nil
    end
    PWStatusManager.setPiwigoBusy(publishService, true)

    -- Set progress title.
    local nPhotos = exportSession:countRenditions()
    local progressScope = exportContext:configureProgress {
        title = "Publishing " .. nPhotos .. " photos to " .. propertyTable.host
    }
    -- check connection to piwigo
    if not (propertyTable.Connected) then
        rv = PiwigoAPI.login(propertyTable)
        if not rv then
            log:info('PublishTask.processRenderedPhotos - publishSettings:\n' .. utils.serialiseVar(propertyTable))
            PWStatusManager.setPiwigoBusy(publishService, false)
            LrErrors.throwUserError('Publish photos to Piwigo - cannot connect to piwigo at ' .. propertyTable.host)
            return nil
        end
    end

    -- log:info('PublishTask.processRenderedPhotos - collectionInfo:\n' .. utils.serialiseVar(collectionInfo))
    local parentCollSet = publishedCollection:getParent()
    local parentID = ""
    local albumName = publishedCollection:getName()
    -- check if album is special collection and and use name of parent album if so
    if string.sub(albumName, 1, 1) == "[" and string.sub(albumName, -1) == "]" then
        if parentCollSet then
            albumName = parentCollSet:getName()
        end
    end
    local albumId = publishedCollection:getRemoteId()
    local albumUrl = publishedCollection:getRemoteUrl()

    local requestRepub = false
    if parentCollSet then
        parentID = parentCollSet:getRemoteId()
    end
    local checkCats
    -- Check that collection exists as an album on Piwigo and create if not
    if albumId then
        rv, checkCats = PiwigoAPI.pwCategoriesGet(propertyTable, albumId)
        if not rv then
            PWStatusManager.setPiwigoBusy(publishService, false)
            LrErrors.throwUserError('Publish photos to Piwigo - cannot check category exists on piwigo at ' ..
                propertyTable.host)
            return nil
        end
    end
    if not utils.nilOrEmpty(checkCats) and albumId then
        -- album exists on Piwigo — reconcile metadata before updating
        local thisCat = PiwigoAPI.pwCategoriesGetThis(propertyTable, albumId)
        if not reconcileAlbumMeta(propertyTable, collectionSettings, thisCat) then
            PWStatusManager.setPiwigoBusy(publishService, false)
            return nil
        end
        local metaData = {}
        metaData.name = albumName
        metaData.remoteId = albumId
        metaData.description = collectionSettings.albumDescription or ""
        if collectionSettings.albumPrivate then
            metaData.status = "private"
        else
            metaData.status = "public"
        end
        PiwigoAPI.pwCategoriesSetinfo(propertyTable, publishedCollection, metaData)
    end
    if utils.nilOrEmpty(checkCats) or not (albumId) then
        -- create missing album on piwigo (may happen if album is deleted directly on Piwigo rather than via this plugin, or if smartcollectionimport is run)
        local metaData = {}
        callStatus = {}
        metaData.name = albumName
        metaData.parentCat = parentID
        if collectionSettings.albumPrivate then
            metaData.status = "private"
        else
            metaData.status = "public"
        end
        callStatus = PiwigoAPI.pwCategoriesAdd(propertyTable, publishedCollection, metaData, callStatus)
        if callStatus.status then
            -- reset album id to newly created one
            albumId = callStatus.newCatId
            exportSession:recordRemoteCollectionId(albumId)
            exportSession:recordRemoteCollectionUrl(callStatus.albumURL)
            LrDialogs.message("*** Missing Piwigo album ***", albumName .. ", Piwigo Cat ID " .. albumId .. " created")
            requestRepub = true
        else
            PWStatusManager.setPiwigoBusy(publishService, false)
            LrErrors.throwUserError('Publish photos to Piwigo - cannot create Piwigo album for  ' .. albumName)
            return nil
        end
    end

    -- Keyword filter setup
    local kwFilterInclude = propertyTable.KwFilterInclude or ""
    local kwFilterExclude = propertyTable.KwFilterExclude or ""
    -- collection-level override if non-empty
    if not utils.nilOrEmpty(collectionSettings.KwFilterInclude) then
        kwFilterInclude = collectionSettings.KwFilterInclude
    end
    if not utils.nilOrEmpty(collectionSettings.KwFilterExclude) then
        kwFilterExclude = collectionSettings.KwFilterExclude
    end
    local includePatterns = utils.parseFilterPatterns(kwFilterInclude)
    local excludePatterns = utils.parseFilterPatterns(kwFilterExclude)
    local kwFilterActive = #includePatterns > 0 or #excludePatterns > 0
    local blockedPhotos = {}

    log:info("KeywordFilter - active: " .. tostring(kwFilterActive)
        .. " include: '" .. kwFilterInclude .. "'"
        .. " exclude: '" .. kwFilterExclude .. "'")

    local resetConnectioncount = 0
    local renditionParams = {
        stopIfCanceled = true,
    }
    -- flag to allow sync comments to manage process in PublishTask.getCommentsFromPublishedCollection
    PWStatusManager.setRenderPhotos(publishService, true)

    -- Video pre-scan + server support check (delegated to vtk_core)
    local batchTotalCount = exportSession:countRenditions()
    local videoPhotos, batchVideoCount = vtk_core.preScan(exportSession, propertyTable, collectionSettings)
    if batchVideoCount == 0 then
        log:info("PublishTask - pre-scan: no videos detected in batch")
    else
        log:info("PublishTask - pre-scan: " .. batchVideoCount .. " video(s) detected in batch of " .. batchTotalCount)
    end

    local videoUploadBlocked, serverMaxBytes, companionAvailable, shouldAbort =
        vtk_core.checkServerSupport(propertyTable, videoPhotos, batchVideoCount, batchTotalCount,
                                    exportSession, publishService)
    if shouldAbort then return end

    -- -----------------------------------------------------------------------
    -- Phase 2C/2D — Video Toolkit (delegated to vtk_core)
    -- -----------------------------------------------------------------------
    local vtkResults, metadataOnlyVideos

    if not videoUploadBlocked and batchVideoCount > 0 and propertyTable.vtkEnabled then
        log:info("PublishTask - Video Toolkit enabled, processing " .. batchVideoCount .. " video(s)")
        -- Remove ALL videos from export session to prevent LrC "This file is a video" dialog
        for _, vEntry in ipairs(videoPhotos) do
            exportSession:removePhoto(vEntry.photo)
        end

        -- Run VTK batch + upload variants (delegated to vtk_core)
        vtkResults, metadataOnlyVideos = vtk_core.runBatch(
            videoPhotos, batchVideoCount, propertyTable, collectionSettings, progressScope)
        vtk_core.uploadVariants(
            vtkResults, propertyTable, collectionSettings,
            albumId, albumName, albumUrl,
            catalog, publishedCollection,
            companionAvailable, serverMaxBytes, progressScope)
    end

    vtkResults         = vtkResults         or {}
    metadataOnlyVideos = metadataOnlyVideos or {}

    progressScope:setCaption("Publishing to Piwigo...")
    progressScope:setPortionComplete(0, 100)

    -- now wait for photos to be exported and then upload to Piwigo
    for i, rendition in exportContext:renditions(renditionParams) do
        -- reset connection every 75 uploads
        resetConnectioncount = resetConnectioncount + 1
        if resetConnectioncount > 75 then
            resetConnectioncount = 0
            log:info("PublishTask.processRenderedPhotos - resetting Piwigo connection after 75 uploads")
            rv = PiwigoAPI.login(propertyTable)
            if not rv then
                PWStatusManager.setPiwigoBusy(publishService, false)
                PWStatusManager.setRenderPhotos(publishService, false)
                log:info("PublishTask.processRenderedPhotos - renditionSettings\n" ..
                    utils.serialiseVar(renditionParams))
                LrErrors.throwUserError('Publish photos to Piwigo - cannot connect to piwigo at ' ..
                    propertyTable.host)
                break
            end
        end

        local lrPhoto = rendition.photo
        local remoteId = rendition.publishedPhotoId or ""
        local fileFormat = lrPhoto:getRawMetadata("fileFormat")
        local isVideo = (fileFormat == "VIDEO")

        -- Video: blocked/VTK videos already removed before the loop via removePhoto
        local videoBlocked = false
        if isVideo then
            log:info("PublishTask.processRenderedPhotos - video detected: "
                .. (lrPhoto:getFormattedMetadata("fileName") or "unknown"))
        end

        -- Keyword filter check
        local kwBlocked = false
        if not videoBlocked and kwFilterActive then
            local keywords = utils.getPhotoDirectKeywords(lrPhoto)
            local allowed, reason = utils.checkKeywordFilter(keywords, includePatterns, excludePatterns)
            if not allowed then
                local fileName = lrPhoto:getFormattedMetadata("fileName") or "unknown"
                log:info("KeywordFilter - BLOCKED: " .. fileName .. " - " .. reason)
                table.insert(blockedPhotos, { name = fileName, reason = reason })
                -- wait for render to complete then discard
                local bSuccess, bPath = rendition:waitForRender()
                if bSuccess and LrFileUtils.exists(bPath) then
                    LrFileUtils.delete(bPath)
                end
                rendition:uploadFailed("Skipped (keyword filter): " .. reason)
                kwBlocked = true
            end
        end

        if not kwBlocked and not videoBlocked then
            -- Detect photo already published in this service (multi-album support)
            local existingPwImageId = nil
            if remoteId == "" then
                -- Method 1: Via custom metadata (photos published with plugin >= 20251224.16)
                local storedImageUrl = lrPhoto:getPropertyForPlugin(_PLUGIN, "pwImageURL")
                local storedHost = lrPhoto:getPropertyForPlugin(_PLUGIN, "pwHostURL")

                if storedHost == propertyTable.host and storedImageUrl then
                    existingPwImageId = utils.extractPwImageIdFromUrl(storedImageUrl, propertyTable.host)
                end

                -- Method 2: Search in other collections of the service (fallback)
                if not existingPwImageId then
                    local publishService = publishedCollection:getService()
                    existingPwImageId = utils.findExistingPwImageId(publishService, lrPhoto)
                end

                -- Verify the image still exists on Piwigo
                if existingPwImageId then
                    local checkStatus = PiwigoAPI.checkPhoto(propertyTable, existingPwImageId)
                    if not checkStatus.status then
                        existingPwImageId = nil
                    end
                end
            end

            -- Wait for next photo to render.
            local success, pathOrMessage = rendition:waitForRender()
            -- Check for cancellation again after photo has been rendered.
            if progressScope:isCanceled() then
                if LrFileUtils.exists(pathOrMessage) then
                    LrFileUtils.delete(pathOrMessage)
                end
                break
            end

            if success then
                -- upload to Piwigo
                callStatus = {}
                local filePath = pathOrMessage

                -- If photo already exists on Piwigo, associate instead of uploading
                if existingPwImageId then
                    log:info("Photo exists on Piwigo (ID " .. existingPwImageId .. "), associating to album " .. albumId)
                    callStatus = PiwigoAPI.associateImageToCategory(propertyTable, existingPwImageId, albumId)

                    if callStatus.status then
                        rendition:recordPublishedPhotoId(callStatus.remoteid)
                        rendition:recordPublishedPhotoUrl(callStatus.remoteurl)
                        rendition:renditionIsDone(true)
                        LrFileUtils.delete(pathOrMessage)
                    else
                        log:warn("Association failed: " .. (callStatus.statusMsg or "") .. ", falling back to upload")
                        existingPwImageId = nil
                    end
                end

                if not existingPwImageId then
                    -- Begin existing upload block (indent all upload code until end of if success)
                    local metaData = {}
                    -- build metadata structure
                    metaData = utils.getPhotoMetadata(propertyTable, lrPhoto)
                    metaData.Albumid = albumId
                    metaData.Remoteid = remoteId
                    -- run to build missingTags - tags that will be created on upload to Piwigo
                    -- will use this to decide whether to run build tagtable cache
                    -- means we don't have to rebuild after each uploaded photo
                    local tagIdList, missingTags = utils.tagsToIds(propertyTable, metaData.tagString)

                    -- do the upload
                    callStatus = PiwigoAPI.updateGallery(propertyTable, filePath, metaData)
                    -- check status and complete rendition
                    if callStatus.status then
                        rendition:recordPublishedPhotoId(callStatus.remoteid or "")
                        rendition:recordPublishedPhotoUrl(callStatus.remoteurl or "")
                        rendition:renditionIsDone(true)
                        -- set metadata for photo
                        local pluginData = {
                            pwHostURL = propertyTable.host,
                            albumName = albumName,
                            albumUrl = albumUrl,
                            imageUrl = callStatus.remoteurl,
                            pwUploadDate = os.date("%Y-%m-%d"),
                            pwUploadTime = os.date("%H:%M:%S"),
                            pwCommentSync = ""
                        }
                        if propertyTable.syncCommentsPublish then
                            -- set to allow comments to sync for this photo if flag set
                            pluginData.pwCommentSync = "YES"
                        end

                        -- store / update custom metadata


                        PiwigoAPI.storeMetaData(catalog, lrPhoto, pluginData)

                        -- photo was uploaded with keywords included, but existing keywords aren't replaced by this process,
                        -- so force a metadata update using pwg.images.setInfo with single_value_mode set to "replace" to force old metadata/keywords to be replaced
                        metaData.Remoteid = callStatus.remoteid
                        if missingTags then
                            -- refresh cached tag list as new tags have been created during updateGallery
                            rv, propertyTable.tagTable = PiwigoAPI.getTagList(propertyTable)
                            if not rv then
                                LrDialogs.message("PiwigoAPI:updateMetadata - cannot get taglist from Piwigo")
                            else
                                utils.buildTagIndex(propertyTable)
                            end
                        end
                        callStatus = PiwigoAPI.updateMetadata(propertyTable, lrPhoto, metaData)
                        if not callStatus.status then
                            LrDialogs.message("Unable to set metadata for uploaded photo - " .. callStatus.statusMsg)
                        end
                    else
                        rendition:uploadFailed(callStatus.message or "Upload failed")
                    end

                    -- When done with photo, delete temp file.
                    LrFileUtils.delete(pathOrMessage)
                end -- end if not existingPwImageId
            else
                rendition:uploadFailed(pathOrMessage or "Render failed")
            end
        end -- end if not kwBlocked
    end

    -- Phase 4C — Metadata-only video updates (delegated to vtk_core)
    vtk_core.updateMetadataOnly(
        metadataOnlyVideos, propertyTable, albumId,
        catalog, publishedCollection,
        companionAvailable, progressScope)

    progressScope:done()
    PWStatusManager.setPiwigoBusy(publishService, false)
end

-- ************************************************
function PublishTask.processCloneSync(functionContext, exportContext)
    -- minimal render function for service cloning
    log:info("PublishTask.processCloneSync")
    local exportSession = exportContext.exportSession
    local propertyTable = exportContext.propertyTable

    local publishedCollection = exportContext.publishedCollection
    local publishService = publishedCollection:getService()


    local collectionInfo = publishedCollection:getCollectionInfoSummary()
    local collectionSettings = collectionInfo.collectionSettings or {}
    local collServiceState = {}
    local serviceState = {}
    if collectionSettings then
        collServiceState = collectionSettings.serviceState or {}
    end

    local collId = publishedCollection.localIdentifier
    local remoteInfoTable = collServiceState.RemoteInfoTable[collId] or {}

    local renditionParams = {
        stopIfCanceled = true,
    }
    for _, rendition in exportContext:renditions(renditionParams) do
        --rendition:skipRender()
        local lrPhoto = rendition.photo
        local photoId = lrPhoto.localIdentifier
        log:info("PublishTask.processCloneSync - photo " .. lrPhoto:getFormattedMetadata("fileName"))

        local success, pathOrMessage = rendition:waitForRender()
        if not success then
            rendition:renditionIsDone(false, pathOrMessage)
            return
        end
        if LrFileUtils.exists(pathOrMessage) then
            LrFileUtils.delete(pathOrMessage)
        end
        -- extract remoteid and url
        local remoteInfo = remoteInfoTable[photoId]
        local remoteId = ""
        local remoteUrl = ""
        if remoteInfo then
            remoteId = remoteInfo.remoteId or ""
            remoteUrl = remoteInfo.remoteUrl or ""
        end

        if remoteId == "" then
            rendition:uploadFailed("Render failed - No remote id found")
        else
            rendition:recordPublishedPhotoId(remoteId)
            rendition:recordPublishedPhotoUrl(remoteUrl or "")
            rendition:renditionIsDone(true)
        end
    end
end

-- ************************************************
function PublishTask.deletePhotosFromPublishedCollection(publishSettings, arrayOfPhotoIds, deletedCallback,
                                                         localCollectionId)
    local callStatus = {}
    local errStatus = ""


    -- build tables to allow access to catalog LrPhoto object
    local catalog = LrApplication.activeCatalog()
    local publishedCollection = catalog:getPublishedCollectionByLocalIdentifier(localCollectionId)
    local publishedPhotos = publishedCollection:getPublishedPhotos()
    local publishService = publishedCollection:getService()
    if not publishService then
        log:info('deletePhotosFromPublishedCollection - publishSettings:\n' .. utils.serialiseVar(publishSettings))
        LrErrors.throwUserError('Publish photos to Piwigo - cannot connect find publishService')
        return nil
    end
    -- serviceState is a global table containing publishService specific statusData
    local serviceState = PWStatusManager.getServiceState(publishService)
    if serviceState.PiwigoBusy then
        return nil
    end
    PWStatusManager.setPiwigoBusy(publishService, true)

    -- build lookup table to access photos by remoteId
    local photosToUnpublish = {}
    local pubPhotoByRemoteID = {}
    for _, pubPhoto in pairs(publishedPhotos) do
        pubPhotoByRemoteID[pubPhoto:getRemoteId()] = pubPhoto
    end

    -- build table of photo objects for each item in arrayofphotoids
    local arrayPos = 1
    for i = 1, #arrayOfPhotoIds do
        local pwImageID = arrayOfPhotoIds[i] or nil
        if pwImageID then
            local pubPhoto = pubPhotoByRemoteID[pwImageID]
            local lrphoto = pubPhoto:getPhoto()
            photosToUnpublish[arrayPos] = {}
            photosToUnpublish[arrayPos][1] = lrphoto
            photosToUnpublish[arrayPos][2] = pwImageID
            photosToUnpublish[arrayPos][3] = pubPhoto
            arrayPos = arrayPos + 1
        end
    end

    -- piwigo album id
    local pwCatID = publishedCollection:getRemoteId()

    -- check connection to piwigo
    if not (publishSettings.Connected) then
        local rv = PiwigoAPI.login(publishSettings)
        if not rv then
            PWStatusManager.setPiwigoBusy(publishService, false)
            LrErrors.throwUserError('Delete Photos from Collection - cannot connect to piwigo at ' .. publishSettings
                .url)
            return nil
        end
    end

    -- set up async prococess for piwigo calls
    LrTasks.startAsyncTask(function()
        -- now go through each photo in photosToUnpublish and remove from Piwigo
        for i, thisPhotoToUnpublish in pairs(photosToUnpublish) do
            local thisLrPhoto = thisPhotoToUnpublish[1]
            local thispwImageID = thisPhotoToUnpublish[2]
            local thisPubPhoto = thisPhotoToUnpublish[3]

            -- Use dissociate instead of delete to preserve multi-album associations
            log:info("PublishTask.deletePhotosFromPublishedCollection - dissociating photo " ..
                thispwImageID .. " from category " .. pwCatID)
            callStatus = PiwigoAPI.dissociateImageFromCategory(publishSettings, thispwImageID, pwCatID)
            if callStatus.status then
                -- Only clear metadata if photo is no longer in any other published collection
                -- Check if photo exists in other collections of this service
                local publishService = publishedCollection:getService()
                local stillPublished = utils.findExistingPwImageId(publishService, thisLrPhoto)

                if not stillPublished then
                    -- Photo is no longer published anywhere, clear all metadata
                    log:info("PublishTask.deletePhotosFromPublishedCollection - photo " ..
                        thispwImageID .. " orphaned, clearing metadata")
                    catalog:withWriteAccessDo("Updating " .. thisLrPhoto:getFormattedMetadata("fileName"),
                        function()
                            thisLrPhoto:setPropertyForPlugin(_PLUGIN, "pwHostURL", "")
                            thisLrPhoto:setPropertyForPlugin(_PLUGIN, "pwAlbumName", "")
                            thisLrPhoto:setPropertyForPlugin(_PLUGIN, "pwAlbumURL", "")
                            thisLrPhoto:setPropertyForPlugin(_PLUGIN, "pwImageURL", "")
                            thisLrPhoto:setPropertyForPlugin(_PLUGIN, "pwUploadDate", "")
                            thisLrPhoto:setPropertyForPlugin(_PLUGIN, "pwUploadTime", "")
                            thisLrPhoto:setPropertyForPlugin(_PLUGIN, "pwCommentSync", "")
                        end)
                else
                    log:info("PublishTask.deletePhotosFromPublishedCollection - photo " ..
                        thispwImageID .. " still in other collections, keeping metadata")
                end
                thisPhotoToUnpublish[4] = true
            else
                PWStatusManager.setPiwigoBusy(publishService, false)
                LrErrors.throwUserError(
                    'Failed to delete photo ' .. thispwImageID .. ' from Piwigo - ' .. callStatus.statusMsg,
                    'Failed to delete photo')
            end
        end
    end, errStatus)

    -- now finish process via deletedCallback
    for i, thisPhotoToUnpublish in pairs(photosToUnpublish) do
        local thispwImageID = thisPhotoToUnpublish[2]
        deletedCallback(thispwImageID)
    end


    PWStatusManager.setPiwigoBusy(publishService, false)
end

-- ************************************************
function PublishTask.getCommentsFromPublishedCollection(publishSettings, arrayOfPhotoInfo, commentCallback)
    log:info("PublishTask.getCommentsFromPublishedCollection")

    --[[
    This callback is invoked in the following situations:
    1 - For every photo in the Published Collection whenever any photo in that collection is published or re-published.
    2 - When the user clicks Refresh in the Library module ▸ Comments panel.
    3 - After the user adds a new comment to a photo in the Library module ▸ Comments panel.
]]

    local rv, publishService = PiwigoAPI.getPublishService(publishSettings)
    if not (publishService) or not (rv) then
        log:info('PublishTask.getCommentsFromPublishedCollection - publishSettings:\n' ..
            utils.serialiseVar(publishSettings))
        LrErrors.throwUserError('PublishTask.getCommentsFromPublishedCollection - cannot find publishService')
        return nil
    end
    -- serviceState is a global table containing publishService specific statusData
    local serviceState = PWStatusManager.getServiceState(publishService)
    local serviceId = publishService.localIdentifier
    -- check serviceState.PiwigoBusy flag
    if serviceState.PiwigoBusy then
        utils.pwBusyMessage("PublishTask.getCommentsFromPublishedCollection", "Sync Comments")
        return
    end

    -- check if being called by processRenderedPhotos
    local syncPubOnly = false
    if serviceState.RenderPhotos then
        PWStatusManager.setRenderPhotos(publishService, false)
        -- should we sync comments as part of the processRenderedPhotos operation
        if not (publishSettings.syncCommentsPublish) then
            log:info("PublishTask.getCommentsFromPublishedCollection - syncComments not enabled for publish")
            return
        end
        -- should we sync comments only for photos published in preceding publish process
        if publishSettings.syncCommentsPubOnly then
            syncPubOnly = true
        end
    end

    local catalog = LrApplication.activeCatalog()
    -- loop through all photos to check for any with pwCommentSync set to "NO"
    for i, photoInfo in ipairs(arrayOfPhotoInfo) do
        --log:info("PublishTask.getCommentsFromPublishedCollection - photoInfo:\n" .. utils.serialiseVar(photoInfo))
        local thisPubPhoto = photoInfo.publishedPhoto
        local thisLrPhoto = thisPubPhoto:getPhoto()
        -- assume to sync comments for all photos in arrayofphotoids
        local syncThisPhoto = true
        if syncPubOnly then
            -- syncPubOnly will be set to true if getCommentsFromPublishedCollection has been called following processRenderedPhotos
            -- and user has checked the option Only Include Published Photos
            -- "pwCommentSync" gets set to YES by the renderphotos process indicating this photo is part of the latest publish process
            local commentSync = thisLrPhoto:getPropertyForPlugin(_PLUGIN, "pwCommentSync")
            if commentSync == "YES" then
                -- reset metadata
                catalog:withWriteAccessDo("Updating " .. thisLrPhoto:getFormattedMetadata("fileName"),
                    function()
                        thisLrPhoto:setPropertyForPlugin(_PLUGIN, "pwCommentSync", "")
                    end)
            else
                -- this photo was not part of recent processRenderedPhotos so ignore
                syncThisPhoto = false
            end
        end

        if syncThisPhoto then
            -- get table of comments for this photo from Piwigo
            local metaData = {}
            metaData.remoteId = photoInfo.remoteId
            local pwComments = PiwigoAPI.getComments(publishSettings, metaData)
            -- convert pwComments to format required by commentCallback
            --log:info("PublishTask.getCommentsFromPublishedCollection - commentList:\n" .. utils.serialiseVar(pwComments))
            local commentList = {}
            if pwComments and #pwComments > 0 then
                for _, comment in ipairs(pwComments) do
                    local dateCreated = comment.date
                    local timeStamp = utils.timeStamp(dateCreated)
                    log:info("dateCreated " .. dateCreated .. ", timeStamp " .. timeStamp)
                    table.insert(commentList, {
                        commentId = comment.id,
                        commentText = comment.content,
                        dateCreated = LrDate.timeFromPosixDate(tonumber(timeStamp)),
                        username = comment.author,
                        realname = comment.author,
                        url = comment.page_url,
                    })
                end
            end
            --log:info("PublishTask.getCommentsFromPublishedCollection - commentList:\n" .. utils.serialiseVar(commentList))
            commentCallback { publishedPhoto = photoInfo, comments = commentList }
        end
    end
end

-- ************************************************
function PublishTask.canAddCommentsToService(publishSettings)
    log:info("PublishTask.canAddCommentToPublishedPhoto")
    -- check if Piwgo has comments enabled
    --local commentsEnabled = PiwigoAPI.pwCheckComments(publishSettings)
    local commentsEnabled = true
    return commentsEnabled
end

-- ************************************************
function PublishTask.addCommentToPublishedPhoto(publishSettings, remotePhotoId, commentText)
    log:info("PublishTask.addCommentToPublishedPhoto")
    -- add comment to Piwigo Photo

    local metaData = {}
    metaData.remoteId = remotePhotoId
    metaData.comment = commentText

    local rv = PiwigoAPI.addComment(publishSettings, metaData)
    return rv
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
    -- This callback is called by Lightroom after each publish.
    -- It handles two tasks:
    --   1. For smart collections: filter out photos that no longer meet the criteria
    --   2. Sync sort order to Piwigo via pwg.images.setRank (if enabled)
    log:info("PublishTask.imposeSortOrderOnPublishedCollection")

    local publishedCollection = info.publishedCollection
    if not publishedCollection then
        return nil
    end

    local finalSequence = remoteIdSequence
    local isSmartCollection = publishedCollection:isSmartCollection()

    -- PART 1: Smart collection filtering (existing logic)
    if isSmartCollection then
        local validSequence = {}
        local currentPhotos = publishedCollection:getPhotos()
        local currentPhotoIds = {}
        for _, photo in ipairs(currentPhotos) do
            currentPhotoIds[photo.localIdentifier] = true
        end

        local publishedPhotos = publishedCollection:getPublishedPhotos()
        local remoteIdToPhoto = {}
        for _, pubPhoto in ipairs(publishedPhotos) do
            local remoteId = pubPhoto:getRemoteId()
            if remoteId then
                remoteIdToPhoto[remoteId] = pubPhoto
            end
        end

        for _, remoteId in ipairs(remoteIdSequence) do
            local pubPhoto = remoteIdToPhoto[remoteId]
            if pubPhoto then
                local lrPhoto = pubPhoto:getPhoto()
                if lrPhoto and currentPhotoIds[lrPhoto.localIdentifier] then
                    table.insert(validSequence, remoteId)
                end
            end
        end

        log:info("PublishTask.imposeSortOrderOnPublishedCollection - " ..
            #remoteIdSequence .. " published, " ..
            #validSequence .. " still match criteria, " ..
            (#remoteIdSequence - #validSequence) .. " to delete")

        finalSequence = validSequence
    end

    -- PART 2: Sync sort order to Piwigo
    local shouldSync = false
    local collectionInfo = publishedCollection:getCollectionInfoSummary()
    local collectionSettings = collectionInfo.collectionSettings or {}
    local override = collectionSettings.syncSortOrderOverride or "default"

    if override == "always" then
        shouldSync = true
    elseif override == "never" then
        shouldSync = false
    else
        shouldSync = publishSettings.syncPhotoSortOrder or false
    end

    if shouldSync and #finalSequence > 0 then
        local categoryId = info.remoteCollectionId
        if categoryId then
            log:info("PublishTask.imposeSortOrderOnPublishedCollection - syncing sort order for category " ..
                tostring(categoryId) .. ", " .. #finalSequence .. " photos")
            local callStatus = PiwigoAPI.pwImagesSetRank(publishSettings, categoryId, finalSequence)
            if not callStatus.status then
                log:info("PublishTask.imposeSortOrderOnPublishedCollection - setRank failed: " ..
                    (callStatus.statusMsg or "unknown error"))
            end
        else
            log:info("PublishTask.imposeSortOrderOnPublishedCollection - no remoteId for collection, skipping sort sync")
        end
    end

    if isSmartCollection then
        return finalSequence
    end
    return nil
end

-- ************************************************
function PublishTask.validatePublishedCollectionName(name)
    log:info("PublishTask.validatePublishedCollectionName")
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
        albumDescription       = "",
        albumPrivate           = false,
        enableCustom           = false,
        reSize                 = false,
        reSizeParam            = "Long Edge",
        reSizeNoEnlarge        = true,
        reSizeLongEdge         = 1024,
        reSizeShortEdge        = 1024,
        reSizeW                = 1024,
        reSizeH                = 1024,
        reSizeMP               = 5,
        reSizePC               = 50,
        metaData               = "All",
        metaDataNoPerson       = true,
        metaDataNoLocation     = false,
        KwFullHierarchy        = true,
        KwSynonyms             = true,
        KwFilterInclude        = "",
        KwFilterExclude        = "",
        syncSortOrderOverride  = "default",
        vtkPresetOverride      = "",   -- 5C: "" = use service default
    }
    for key, defaultVal in pairs(defaults) do
        if collectionSettings[key] == nil then
            collectionSettings[key] = defaultVal
        end
    end
end

local function buildCommonCollectionUI(f, bind, share, collectionSettings)
    local pwAlbumUI = UIHelpers.createPiwigoAlbumSettingsUI(f, share, bind, collectionSettings)
    local kwFilterUI = UIHelpers.createKeywordFilteringUI(f, bind, collectionSettings)
    local sortOrderUI = f:group_box {
        title = "Sort Order",
        font = "<system/bold>",
        size = 'regular',
        fill_horizontal = 1,
        bind_to_object = assert(collectionSettings),
        f:row {
            fill_horizontal = 1,
            f:static_text {
                title = "Sync sort order to Piwigo:",
                font = "<system>",
                alignment = 'right',
            },
            f:popup_menu {
                value = bind 'syncSortOrderOverride',
                items = {
                    { title = "Use global setting", value = "default" },
                    { title = "Always sync",        value = "always" },
                    { title = "Never sync",         value = "never" },
                },
            },
        },
    }
    return pwAlbumUI, sortOrderUI, kwFilterUI
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

    -- build UI
    local reSizeOptions = {
        { title = "Long Edge",  value = "Long Edge" },
        { title = "Short Edge", value = "Short Edge" },
        { title = "Dimensions", value = "Dimensions" },
        { title = "Megapixels", value = "MegaPixels" },
        { title = "Percent",    value = "Percent" },
    }
    local metaDataOpts = {
        { title = "All Metadata",                        value = "All Metadata" },
        { title = "Copyright only",                      value = "Copyright Only" },
        { title = "Copyright & Contact Info Only",       value = "Copyright & Contact Info Only" },
        { title = "All Except Camera Raw Info",          value = "All Except Camera Raw Info" },
        { title = "All Except Camera & Camera Raw Info", value = "All Except Camera & Camera Raw Info" },
    }

    local pwAlbumUI, sortOrderUI, kwFilterUI = buildCommonCollectionUI(f, bind, share, collectionSettings)

    local pubSettingsUI = f:group_box {
        title = "Custom Publish Settings (Overrides defaults set in Publish Settings)",
        font = "<system/bold>",
        size = 'regular',
        fill_horizontal = 1,
        bind_to_object = assert(collectionSettings),
        f:column {
            spacing = f:control_spacing(),
            fill_horizontal = 1,
            f:separator { fill_horizontal = 1 },
            f:row {
                f:checkbox {
                    title = "Use custom settings for this album",
                    tooltip = "If checked, these settings will replace the defaults set in Publish Settings",
                    value = bind 'enableCustom',
                }
            },
            f:row {
                f:group_box { -- group for export parameters
                    title = "Export Settings",
                    visible = bind 'enableCustom',
                    font = "<system>",
                    fill_horizontal = 1,
                    f:row {
                        fill_horizontal = 1,
                        spacing = f:label_spacing(),

                        f:checkbox {
                            title = "Resize Image",
                            tooltip = "If checked, published image will be resized per these settings",
                            value = bind 'reSize',
                        },
                        f:static_text {
                            title = "Use :",
                            alignment = 'right',
                            fill_horizontal = 1,
                        },

                        f:popup_menu {
                            value = bind 'reSizeParam',
                            items = sizeOpts,
                            value_equal = valueEqual,
                        },
                        f:checkbox {
                            title = "Allow Enlarge Image",
                            tooltip = "If checked, published image will be enlarged if necessary",
                            value = bind 'reSizeEnlarge',
                        },

                    },


                },
            },
            f:row {
                f:group_box { -- group for Metadata parameters
                    title = "Metadata Settings",
                    visible = bind 'enableCustom',
                    font = "<system>",
                    fill_horizontal = 1,
                    f:spacer { height = 2 },

                    f:checkbox { title = "Include Full Keyword Hierarchy",
                        tooltip = "If checked, all keywords in a keyword hierarchy will be sent to Piwigo",
                        value = bind 'KwFullHierarchy',
                    },
                    f:checkbox { title = "Include Keywords Synonyms",
                        tooltip = "If checked, keywords synonyms will be sent to Piwigo",
                        value = bind 'KwSynonyms',
                    }

                },
            },
        },
    }

    -- 5C — Video preset override per collection
    local vtkPresetItems = {
        { title = "Use service default", value = "" },
        { title = "Small (480p)",        value = "small"  },
        { title = "Medium (720p)",       value = "medium" },
        { title = "Large (1080p)",       value = "large"  },
        { title = "XLarge (1440p)",      value = "xlarge" },
        { title = "XXL (2160p)",         value = "xxl"    },
        { title = "Origin (no transcode)", value = "origin" },
    }
    local vtkVideoUI = f:group_box {
        title = "Video Preset Override",
        font = "<system/bold>",
        size = 'regular',
        fill_horizontal = 1,
        bind_to_object = assert(collectionSettings),
        f:spacer { height = 2 },
        f:row {
            fill_horizontal = 1,
            f:static_text {
                title = "Video preset:",
                font = "<system>",
                alignment = 'right',
            },
            f:popup_menu {
                value = bind 'vtkPresetOverride',
                items = vtkPresetItems,
                tooltip = "Override the service-level video preset for this album only. 'Use service default' keeps the global setting.",
            },
        },
        f:spacer { height = 2 },
    }

    local UI = f:column {
        spacing = f:control_spacing(),
        pwAlbumUI,
        sortOrderUI,
        kwFilterUI,
        vtkVideoUI,
        --pubSettingsUI,
    }
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
        log:info('updateCollectionSettings - publishSettings:\n' .. utils.serialiseVar(publishSettings))
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
        if not reconcileAlbumMeta(publishSettings, collectionSettings, thisCat) then
            return { status = false, statusMsg = "Cancelled by user" }
        end
        metaData.description = collectionSettings.albumDescription or ""
        metaData.status = collectionSettings.albumPrivate and "private" or "public"
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

    local pwAlbumUI, sortOrderUI, kwFilterUI = buildCommonCollectionUI(f, bind, share, collectionSettings)

    local UI = f:column {
        spacing = f:control_spacing(),
        pwAlbumUI,
        sortOrderUI,
        kwFilterUI,
    }
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
        log:info('updateCollectionSettings - publishSettings:\n' .. utils.serialiseVar(publishSettings))
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
        if not reconcileAlbumMeta(publishSettings, collectionSettings, thisCat) then
            return { status = false, statusMsg = "Cancelled by user" }
        end
        metaData.description = collectionSettings.albumDescription or ""
        metaData.status = collectionSettings.albumPrivate and "private" or "public"
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
        log:info('reparentPublishedCollection - publishSettings:\n' .. utils.serialiseVar(publishSettings))
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
        log:info('renamePublishedCollection - publishSettings:\n' .. utils.serialiseVar(publishSettings))
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
    -- Reconcile metadata with Piwigo before renaming
    if not utils.nilOrEmpty(remoteId) then
        local thisCat = PiwigoAPI.pwCategoriesGetThis(publishSettings, remoteId)
        if not reconcileAlbumMeta(publishSettings, collectionSettings, thisCat) then
            return { status = false, statusMsg = "Cancelled by user" }
        end
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
        log:info('deletePublishedCollection - publishSettings:\n' .. utils.serialiseVar(publishSettings))
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
