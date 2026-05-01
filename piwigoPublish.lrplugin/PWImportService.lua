--[[

    PWImportService.lua

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

---@diagnostic disable: undefined-global

local PWIMportService = {}

local SPECIAL_PREFIX = "※" -- U+203B Reference Mark used by another plugin to identify super collections

local PublishLocks = PublishLocks or {}

-- *************************************************
local function acquirePublishLock(serviceId)
    while PublishLocks[serviceId] do
        LrTasks.sleep(0.2)
    end
    PublishLocks[serviceId] = true
end

-- *************************************************
local function releasePublishLock(serviceId)
    PublishLocks[serviceId] = false
end


-- *************************************************
-- Define a value_equal function for the popup_menu
local function valueEqual(a, b)
    return a == b
end

-- *************************************************
local function buildPhotoSet(pubPhotos)
    -- build set of photos for comparison
    local set = {}
    for _, pubPhoto in pairs(pubPhotos) do
        set[pubPhoto:getPhoto()] = true
    end
    return set
end

-- *************************************************
local function setsEqual(a, b)
    -- compare 2 sets and return true if they are equal
    for k in pairs(a) do
        if not b[k] then
            return false
        end
    end
    for k in pairs(b) do
        if not a[k] then
            return false
        end
    end
    return true
end

-- *************************************************
local function isSpecialCollection(name)
    return type(name) == "string"
        and name:sub(1, #SPECIAL_PREFIX) == SPECIAL_PREFIX
end

-- *************************************************
local function buildChildrenIndex(collMap)
    local index = {}
    for _, node in pairs(collMap) do
        local pid = node.parentId or "__root__"
        index[pid] = index[pid] or {}
        table.insert(index[pid], node)
    end
    return index
end

-- *************************************************
local function processSmartCollectionQueue(smartColls, publishService, propertyTable, index, progressScope, stats)
    log:info("processSmartCollectionQueue - processing smart collection " .. index .. " of " .. #smartColls)
    local catalog = LrApplication.activeCatalog()
    local serviceId = publishService.localIdentifier

    -- now get lock to prevent other publishNow processes running concurrently
    acquirePublishLock(serviceId)

    if not smartColls or index > #smartColls then
        releasePublishLock(serviceId)
        progressScope:done()
        LrDialogs.message("Clone completed", "Publish Service Clone Complete.", "info")
        return
    end

    local entry = smartColls[index]
    if not entry then
        releasePublishLock(serviceId)
        progressScope:done()
        LrDialogs.message("Clone completed", "Publish Service Clone Complete.", "info")
        return -- done
    end

    local collection = entry.collection
    local node = entry.node
    local name = node.name
    local extra = node.extra or nil
    local remoteAlbumId = node.remoteId
    local albumUrl = propertyTable.host .. "/index.php?/category/" .. remoteAlbumId
    local oldPubPhotos
    if extra then
        oldPubPhotos = extra.pubphotos or {}
    end
    if #oldPubPhotos == 0 then
        releasePublishLock(serviceId)
        return
    end

    log:info("processSmartCollectionQueue - processing smart collection " ..
        name .. " with " .. #oldPubPhotos .. " photos")

    -- set flags to ensure correct render process runs
    local collectionInfo = collection:getCollectionInfoSummary()
    local collectionSettings = collectionInfo.collectionSettings
    local publishSettings = collectionInfo.publishSettings

    PWStatusManager.setisCloningSync(publishService, true)
    local serviceState = PWStatusManager.getServiceState(publishService)
    log:info("processSmartCollectionQueue - serviceState\n" .. utils.serialiseVar(serviceState))

    -- we only care about oldPubPhotos that have a remote Id - i.e. have been uploaded to Piwigo
    -- 1. Create a lookup table for the old published photos
    -- store in PWStatusManager to ensure visibility in render process

    local RemoteInfoTable = {}
    local collId = collection.localIdentifier
    log:info("processSmartCollectionQueue - building RemoteInfoTable for collection " ..
        collection:getName() .. " (" .. collId .. ")")
    for _, oldPubPhoto in ipairs(oldPubPhotos) do
        local lrPhoto = oldPubPhoto:getPhoto()
        local photoId = lrPhoto.localIdentifier
        local remoteId = oldPubPhoto:getRemoteId() or ""
        local remoteUrl = oldPubPhoto:getRemoteUrl() or ""
        RemoteInfoTable[photoId] = RemoteInfoTable[photoId] or {}
        RemoteInfoTable[photoId] = {
            remoteId = remoteId,
            remoteUrl = remoteUrl,
        }
    end

    -- need to use local collectionInfo = publishedCollection:getCollectionInfoSummary()
    -- to pass data to the publish process,

    PWStatusManager.storeRemoteInfo(publishService, collId, RemoteInfoTable)
    serviceState = PWStatusManager.getServiceState(publishService)
    log:info("processSmartCollectionQueue - serviceState after RemoteInfoTable build\n" ..
        utils.serialiseVar(serviceState))
    -- add serviceState to collectionSettings to ensure it is passed to renderPhotos
    collectionSettings.serviceState = serviceState
    catalog:withWriteAccessDo("Add serviceState to collection", function()
        collection:setCollectionSettings(collectionSettings)
    end)

    -- now force publish and subsequent render process
    collection:publishNow(function(status)
        log:info("smart collection - dummy publish complete for " .. collection:getName())
        local lrPhotos = collection:getPhotos()
        log:info("smart collection - there are " ..
            (#collection:getPublishedPhotos() or 0) .. " published photos in the collection")
        --PWStatusManager.setisCloningSync(publishService, false)
        -- The images are now 'published' but were never actually uploaded - can now add remoteIds etc
        for pp, thispubPhoto in pairs(collection:getPublishedPhotos()) do
            log:info("smart collection " .. collection:getName() .. " - processing published photo " .. pp)
            local thisLrPhoto = thispubPhoto:getPhoto()
            local thisLrPhotoId = thisLrPhoto.localIdentifier
            local remoteInfo = RemoteInfoTable[thisLrPhotoId]


            if remoteInfo then
                -- Found the old published photo
                -- check  image exists on Piwigo before setting metadata
                local remoteId = remoteInfo.remoteId
                local oldremoteUrl = remoteInfo.remoteUrl
                local rtnStatus = PiwigoAPI.checkPhoto(propertyTable, remoteId)
                if rtnStatus.status then
                    local imageDets = rtnStatus.imageDets
                    local remoteUrl = imageDets.page_url or oldremoteUrl
                    --  apply the metadata to the published photo
                    catalog:withWriteAccessDo("Add Piwigo details to image", function()
                        thispubPhoto:setRemoteId(remoteId)
                        thispubPhoto:setRemoteUrl(remoteUrl)
                    end)
                    local pluginData = {
                        pwHostURL = propertyTable.host,
                        albumName = name,
                        albumUrl = propertyTable.host .. "/index.php?/category/" .. remoteAlbumId,
                        imageUrl = remoteUrl,
                        pwUploadDate = os.date("%Y-%m-%d"),
                        pwUploadTime = os.date("%H:%M:%S"),
                        pwCommentSync = ""
                    }
                    PiwigoAPI.storeMetaData(catalog, thisLrPhoto, pluginData)
                end
                stats.imagesCloned = stats.imagesCloned + 1
                progressScope:setPortionComplete(stats.imagesCloned, stats.images)
                progressScope:setCaption("Cloning Images... " ..
                    stats.imagesCloned .. " of " .. stats.images .. " images")
            end
        end

        -- now remove serviceeState from collectionSettings
        collectionSettings.serviceState = nil
        catalog:withWriteAccessDo("Add serviceState to collection", function()
            collection:setCollectionSettings(collectionSettings)
        end)
        releasePublishLock(serviceId)
        log:info("processSmartCollectionQueue - finished processing collection " .. collection:getName())
        -- move to next smart collection
        LrTasks.startAsyncTask(function()
            processSmartCollectionQueue(smartColls, publishService, propertyTable, index + 1, progressScope, stats)
        end)
    end)
end


-- *************************************************
local function populateCollections(stdColls, smartColls, publishService, propertyTable, pwDetails, progressScope, stats)
    -- add images to collections
    local catalog = LrApplication.activeCatalog()
    local serviceId = publishService.localIdentifier

    if stdColls then
        for sc, entry in pairs(stdColls) do
            local collection = entry.collection
            local node = entry.node
            local name = node.name
            local extra = node.extra or nil
            local oldPubPhotos
            local oldlrPhotos
            local publishedIds
            if extra then
                oldPubPhotos = extra.pubphotos or {}
                oldlrPhotos = extra.lrPhotos or {}
                publishedIds = extra.publishedIds or {}
            end

            log:info("processing collection " .. name .. " with " .. #oldPubPhotos .. " photos")
            local lrPhotosToAdd = {} -- photos to add without piwigo metadata
            if #oldPubPhotos > 0 then
                local albumUrl = collection:getRemoteUrl()
                for pp, pubPhoto in pairs(oldPubPhotos) do
                    local lrPhoto = pubPhoto:getPhoto()
                    local photoId = lrPhoto.localIdentifier
                    if pwDetails.isPiwigo and pwDetails.isSameHost then
                        -- this is the same Piwigo host then we can copy remote ids etc
                        local pubFlag = false
                        local remoteId = pubPhoto:getRemoteId()
                        -- check remote id - does image exist on Piwigo
                        local rtnStatus = PiwigoAPI.checkPhoto(propertyTable, remoteId)
                        if rtnStatus.status and albumUrl then
                            -- album and photo exists on Piwigo - add and set metadata
                            local imageDets = rtnStatus.imageDets
                            -- image and album exists on Piwigo so set metadata
                            local remoteUrl = imageDets.page_url
                            pubFlag = true
                            catalog:withWriteAccessDo("Add Photo to collection", function()
                                collection:addPhotoByRemoteId(lrPhoto, remoteId, remoteUrl, pubFlag)
                            end)
                            -- now set metadata
                            local pluginData = {
                                pwHostURL = propertyTable.host,
                                albumName = name,
                                albumUrl = albumUrl,
                                imageUrl = remoteUrl,
                                pwUploadDate = os.date("%Y-%m-%d"),
                                pwUploadTime = os.date("%H:%M:%S"),
                                pwCommentSync = ""
                            }
                            PiwigoAPI.storeMetaData(catalog, lrPhoto, pluginData)
                            stats.imagesCloned = stats.imagesCloned + 1
                            progressScope:setPortionComplete(stats.imagesCloned, stats.images)
                            progressScope:setCaption("Cloning Images... " ..
                                stats.imagesCloned .. " of " .. stats.images .. " images")
                        else
                            -- album / photo don't exist on Piwigo
                            -- add photo but don't set and piwigo details
                            table.insert(lrPhotosToAdd, lrPhoto)
                        end
                    else
                        -- non piwigo or different piwigo host service being cloned - add photos but don't set any piwigo details
                        table.insert(lrPhotosToAdd, lrPhoto)
                    end
                end
            end
            -- now add any remaining lrPhotos that were not published photos - from oldlrPhotos
            for _, lrPhoto in pairs(oldlrPhotos) do
                local photoId = lrPhoto.localIdentifier
                if not publishedIds[photoId] then
                    table.insert(lrPhotosToAdd, lrPhoto)
                end
            end
            if #lrPhotosToAdd > 0 then
                catalog:withWriteAccessDo("Add Photos to collection", function()
                    collection:addPhotos(lrPhotosToAdd)
                end)
                stats.imagesCloned = stats.imagesCloned + #lrPhotosToAdd
                progressScope:setPortionComplete(stats.imagesCloned, stats.images)
                progressScope:setCaption("Cloning Images... " ..
                    stats.imagesCloned .. " of " .. stats.images .. " images")
            end
        end
    end

    -- now add Piwigo metadata to images in smartCollections
    if #smartColls > 0 and pwDetails.isPiwigo and pwDetails.isSameHost then
        processSmartCollectionQueue(smartColls, publishService, propertyTable, 1, progressScope, stats)
    else
        progressScope:done()
        if pwDetails.isPiwigo and pwDetails.isSameHost then
            LrDialogs.message("Clone completed", "Publish Service Clone Complete.", "info")
        else
            LrDialogs.message("Clone completed",
                "Clone Complete. Check and Link Piwigo Structure will now be run", "info")
            --LrTasks.startAsyncTask(function()
                PiwigoAPI.validatePiwigoStructure(propertyTable)
            --end)
        end
    end
end


-- *************************************************
local function createTree(nodes, parentSet, publishService, created, childrenIndex, statusData, propertyTable, pwDetails,
                          stdColls, smartColls, progressScope, stats)
    -- nodes is a table of collection / sets details

    local catalog = LrApplication.activeCatalog()
    local serviceId = publishService.localIdentifier

    for _, node in ipairs(nodes) do
        local name = node.name
        local extra = node.extra or nil
        local isSpecialColl = false
        -- Special collection renaming

        if isSpecialCollection(node.name) and parentSet then
            -- Use the parent collection/set name
            name = "[Photos in " .. parentSet:getName() .. " ]"
            isSpecialColl = true
            -- ensure correct remoteId is used
        end

        local remoteAlbumId = node.remoteId
        local comment = ""
        local status = "public" -- ensure default is public
        local isSmartColl = false
        local searchDesc
        if extra then
            if extra.collSettings then
                comment = extra.collSettings.comment or ""
                status = extra.collSettings.status or "public"
            end
            isSmartColl = extra.isSmartColl
            searchDesc = extra.searchDesc
        end

        local newCollorSet

        if node.kind == "set" then
            catalog:withWriteAccessDo("Create PublishedCollectionSet ", function()
                newCollorSet = publishService:createPublishedCollectionSet(name, parentSet, true)
            end)
            if newCollorSet == nil then
                LrErrors.throwUserError("Error in createCollection: Failed to create PublishedCollectionSet " ..
                    name .. " under parent " .. parentSet:getName())
                return
            end
            created[node.id] = newCollorSet

            -- now add remoteids and urls to collections and collection sets, and description and status
            local albumUrl = ""
            if pwDetails.isPiwigo then
                local collectionSettings = newCollorSet:getCollectionSetInfoSummary().collectionSettings or {}
                -- album settings set to correspond to service being cloned
                collectionSettings.albumDescription = comment
                if status == "private" then
                    collectionSettings.albumPrivate = true
                else
                    collectionSettings.albumPrivate = false
                end

                if remoteAlbumId then
                    local thisCat = PiwigoAPI.pwCategoriesGetThis(propertyTable, remoteAlbumId)
                    if thisCat then
                        -- use settings directly from Piwigo, overriding local settings
                        collectionSettings.albumDescription = thisCat.description or ""
                        if thisCat.status == "public" then
                            collectionSettings.albumPrivate = false
                        else
                            collectionSettings.albumPrivate = true
                        end
                        albumUrl = propertyTable.host .. "/index.php?/category/" .. remoteAlbumId
                        catalog:withWriteAccessDo("Add Piwigo details to collections", function()
                            newCollorSet:setRemoteId(remoteAlbumId)
                            newCollorSet:setRemoteUrl(albumUrl)
                            newCollorSet:setCollectionSetSettings(collectionSettings)
                        end)
                    end
                end
            end
            stats.collectionsCloned = stats.collectionsCloned + 1
            progressScope:setPortionComplete(stats.collectionsCloned, stats.collections)
            progressScope:setCaption("Cloning Collections... " ..
                stats.collectionsCloned ..
                " of " .. stats.collections + stats.collectionSets + stats.smartCollections .. " collections")
            -- recurse into children (if any)
            local children = childrenIndex[node.id]
            if children then
                createTree(children, newCollorSet, publishService, created, childrenIndex, statusData, propertyTable,
                    pwDetails, stdColls, smartColls, progressScope, stats)
            end
        elseif node.kind == "collection" then
            if isSmartColl then
                catalog:withWriteAccessDo("Create PublishedCollection ", function()
                    newCollorSet = publishService:createPublishedSmartCollection(name, searchDesc, parentSet, true)
                end)
                -- build table of smart collections for later processing
                if pwDetails.isPiwigo and pwDetails.isSameHost then
                    table.insert(smartColls, {
                        collection = newCollorSet,
                        node = node,
                    })
                end
            else
                if newCollorSet == nil then
                    catalog:withWriteAccessDo("Create PublishedCollection ", function()
                        newCollorSet = publishService:createPublishedCollection(name, parentSet, true)
                    end)
                end
                if newCollorSet == nil then
                    LrErrors.throwUserError("Error in createCollection: Failed to create PublishedCollection " ..
                        name .. " under parent " .. parentSet:getName())
                    return
                end
                -- build table of collections for later processing
                table.insert(stdColls, {
                    collection = newCollorSet,
                    node = node,
                })
            end
            created[node.id] = newCollorSet
            -- now add remoteids and urls to collections and collection sets, and description and status
            local albumUrl = ""
            if pwDetails.isPiwigo and pwDetails.isSameHost then
                -- this is the same Piwigo host then we can copy remote ids etc
                local collectionSettings = newCollorSet:getCollectionInfoSummary().collectionSettings or {}
                collectionSettings.albumDescription = comment
                if status == "private" then
                    collectionSettings.albumPrivate = true
                else
                    collectionSettings.albumPrivate = false
                end
                if remoteAlbumId then
                    -- check if remoote album exists and add to collection if so
                    local thisCat = PiwigoAPI.pwCategoriesGetThis(propertyTable, remoteAlbumId)
                    if thisCat then
                        collectionSettings.albumDescription = thisCat.description or ""
                        if thisCat.status == "public" then
                            collectionSettings.albumPrivate = false
                        else
                            collectionSettings.albumPrivate = true
                        end
                        albumUrl = propertyTable.host .. "/index.php?/category/" .. remoteAlbumId
                        catalog:withWriteAccessDo("Add Piwigo details to collections", function()
                            newCollorSet:setRemoteId(remoteAlbumId)
                            newCollorSet:setRemoteUrl(albumUrl)
                            newCollorSet:setCollectionSettings(collectionSettings)
                        end)
                    end
                end
            end
            stats.collectionsCloned = stats.collectionsCloned + 1
            progressScope:setPortionComplete(stats.collectionsCloned, stats.collections)
            progressScope:setCaption("Cloning Collections... " ..
                stats.collectionsCloned ..
                " of " .. stats.collections + stats.collectionSets + stats.smartCollections .. " collections")
        end
    end
end

-- *************************************************
local function importService(propertyTable, thisService, impService, serviceIndex, pwDetails, stats)
    -- build service
    local catalog = LrApplication.activeCatalog()
    local collMap = serviceIndex
    local childrenIndex = buildChildrenIndex(serviceIndex)
    local created = {}
    log:info("importService - importing " .. impService:getName() .. " to " .. thisService:getName())
    log:info("pwDetails - " .. utils.serialiseVar(pwDetails))
    --
    local statusData = {
        existing = 0,
        collectionSets = 0,
        collections = 0,
        errors = 0,
        maxDepth = 0
    }
    -- start at roots (parentId == nil)
    local nodes = childrenIndex["__root__"] or {}
    local parentSet = nil
    local smartColls = {}
    local stdColls = {}

    local progressScope = LrProgressScope {
        title = "Cloning Collections...",
        caption = "Starting...",
        functionContext = context,
    }

    stats.collectionsCloned = 0
    -- build collection structure
    createTree(nodes, parentSet, thisService, created, childrenIndex, statusData, propertyTable, pwDetails, stdColls,
        smartColls, progressScope, stats)

    progressScope:done()
    stats.imagesCloned = 0
    progressScope = LrProgressScope {
        title = "Cloning Images...",
        caption = "Starting...",
        functionContext = context,
    }

    -- add images
    populateCollections(stdColls, smartColls, thisService, propertyTable, pwDetails, progressScope, stats)

    return true
end


-- *************************************************
local function importServicePrelim(propertyTable, thisService, impService)
    -- check and verify selected service

    local catalog = LrApplication.activeCatalog()
    local thisHost = propertyTable.host
    local thisUser = propertyTable.userName

    -- Check attributes and configuration of impService
    local publishSettings = impService:getPublishSettings()
    -- check for specific fields to make sure this is a Piwigo related service
    -- we will clone non-Piwigo services but only try and populate Piwigo specific data if it is a Piwigo related service
    local pwDetails = {
        isPiwigo = false,
        isSameHost = false,
        user = "",
        host = "",
    }
    if publishSettings.LR_exportServiceProviderTitle == "Piwigo" then
        -- this is a legacy Piwigo Publish service
        pwDetails.isPiwigo = true
        pwDetails.host = publishSettings.MM_ServerUrl
        if string.sub(pwDetails.host, -1) == "/" then
            if pwDetails.host == propertyTable.host .. "/" then
                pwDetails.isSameHost = true
            end
        else
            if pwDetails.host == propertyTable.host then
                pwDetails.isSameHost = true
            end
        end
        pwDetails.user = publishSettings.AP_authUser
    end
    if publishSettings.LR_exportServiceProviderTitle == "Piwigo Publisher" then
        -- this is another instance of this service
        pwDetails.isPiwigo = true
        pwDetails.host = publishSettings.host
        if pwDetails.host == propertyTable.host then
            pwDetails.isSameHost = true
        end
        pwDetails.user = publishSettings.userName
    end
    local indexByPath, indexById = PiwigoAPI.buildNormalisedCollectionTables(impService)


    local stats = {
        collections = 0,
        smartCollections = 0,
        remColls = 0,
        pwColls = 0,
        collectionSets = 0,
        images = 0,
        remImages = 0,
        pwImages = 0,
        unpublishedCollImages = 0,
        unpublishedSmartCollImages = 0,
    }
    local canClone = true
    for id, collDets in pairs(indexById) do
        local extraCollDets = {}
        local thisColl = catalog:getPublishedCollectionByLocalIdentifier(id)
        if thisColl then
            local colType = thisColl:type()
            local info = {}
            local pubphotos = nil
            local lrPhotos = nil
            local isSmartColl = false
            local searchDesc = {}
            if colType == "LrPublishedCollection" then
                info = thisColl:getCollectionInfoSummary()
                pubphotos = thisColl:getPublishedPhotos()
                lrPhotos = thisColl:getPhotos()
                -- check for smart collection
                isSmartColl = thisColl:isSmartCollection()
                if isSmartColl then
                    -- count number of lrPhotos in collection
                    -- a different to number of published photos indicates un published photos
                    -- which means we cannot proceed with cloning
                    local numlrPhotos = #lrPhotos
                    local numPubPhotos = #pubphotos
                    if numlrPhotos > numPubPhotos then
                        stats.unpublishedSmartCollImages = stats.unpublishedSmartCollImages +
                            (numlrPhotos - numPubPhotos)
                        canClone = false
                    end
                    searchDesc = thisColl:getSearchDescription()
                    stats.smartCollections = stats.smartCollections + 1
                else
                    local numlrPhotos = #thisColl:getPhotos()
                    local numPubPhotos = #thisColl:getPublishedPhotos()
                    if numlrPhotos > numPubPhotos then
                        stats.unpublishedCollImages = stats.unpublishedCollImages + (numlrPhotos - numPubPhotos)
                    end
                    stats.collections = stats.collections + 1
                end
            elseif colType == "LrPublishedCollectionSet" then
                info = thisColl:getCollectionSetInfoSummary()
                stats.collectionSets = stats.collectionSets + 1
            end
            local parentColl = thisColl:getParent()
            local remoteId = thisColl:getRemoteId() or ""
            local remoteUrl = thisColl:getRemoteUrl() or ""

            local collSettings
            local pubSettings
            if info then
                collSettings = info.collectionSettings
                pubSettings = info.publishSettings
            end
            local publishedIds = {}
            if pubphotos then
                for pp, pubPhoto in pairs(pubphotos) do
                    stats.images = stats.images + 1
                    local lrPhoto = pubPhoto:getPhoto()
                    publishedIds[lrPhoto.localIdentifier] = true
                    local fileName = ""
                    local remId = pubPhoto:getRemoteId() or ""
                    local remUrl = pubPhoto:getRemoteUrl() or ""
                    if remId ~= "" then
                        stats.pwImages = stats.pwImages + 1
                    else
                        if isSmartColl then
                            stats.unpublishedSmartCollImages = stats.unpublishedSmartCollImages + 1
                        end
                    end
                    if lrPhoto then
                        fileName = lrPhoto:getFormattedMetadata("fileName")
                    end
                end
            end
            extraCollDets.parentColl = parentColl
            extraCollDets.remoteId = remoteId
            extraCollDets.remoteUrl = remoteUrl
            extraCollDets.isSmartColl = isSmartColl
            extraCollDets.searchDesc = searchDesc
            extraCollDets.collSettings = collSettings
            extraCollDets.lrPhotos = lrPhotos
            extraCollDets.pubphotos = pubphotos
            extraCollDets.publishedIds = publishedIds
            collDets.extra = extraCollDets
        end
    end

    -- display dialog to confirm details before proceeding
    local text1 = "Cloning from " .. impService:getName() .. " (" .. impService:getPluginId() .. ")"

    local textTo = thisService:getName() .. " Publish Service"

    local text2 = ""
    local text3 = ""
    local text4 = ""
    local text5 = ""
    if pwDetails.isPiwigo then
        if pwDetails.isSameHost then
            text2 = "The service being cloned is a Piwigo service connected to the same Piwigo host as this service."
            if not canClone then
                text3 =
                "** The service being cloned has smart collections with unpublished images - please fix before cloning **"

                if stats.unpublishedSmartCollImages > 0 then
                    text5 = "*** Unpublished Smart Collection Images : " .. stats.unpublishedSmartCollImages .. " ***"
                end
            else
                text3 = "Collections/Sets will be cloned as will links to Piwigo albums and images if present"

                if stats.unpublishedCollImages > 0 then
                    text4 = "*** Unpublished Collection Images : " .. stats.unpublishedCollImages .. " ***"
                else
                    text4 = ""
                end
                text5 = ""
            end
        else
            text2 =
            "The service being cloned is a Piwigo service but connected to a different Piwigo host."
            text3 = "Collections/Sets and images will be cloned but links to Piwigo will not"
        end
    else
        text2 = "The service being cloned is not a Piwigo service."
        text3 = "Collections/Sets and images will be cloned but no links to Piwigo albums or images will be made"
    end
    local f = LrView.osFactory()
    local c = f:column {
        spacing = f:dialog_spacing(),
        f:row {
            f:column {
                spacing = f:control_spacing(),
                f:spacer { height = 3 },
                f:row {
                    f:static_text {
                        title = "Clone : ",
                        font = "<system>",
                        alignment = 'right',

                        height_in_lines = 1,
                    },
                    --},
                    --f:row {
                    f:static_text {
                        title = impService:getName() .. " (" .. impService:getPluginId() .. ")",
                        font = "<system/bold>",
                        alignment = 'left',

                        height_in_lines = 1,
                    },
                },

                f:row {
                    f:static_text {
                        title = "      to : ",
                        font = "<system>",
                        alignment = 'right',

                        height_in_lines = 1,
                    },
                    --},
                    --f:row {
                    f:static_text {
                        title = thisService:getName(),
                        font = "<system/bold>",
                        alignment = 'left',

                        height_in_lines = 1,
                    },
                },
                f:spacer { height = 3 },
                f:row {
                    f:static_text {
                        title = text2,
                        font = "<system/bold>",
                        alignment = 'left',
                        fill_horizontal = 1,
                        height_in_lines = 1,
                    },
                },
                f:spacer { height = 1 },
                f:row {
                    f:static_text {
                        title = text3,
                        font = "<system/bold>",
                        alignment = 'left',
                        fill_horizontal = 1,
                        height_in_lines = 1,
                    },
                },
                -- display details to be cloned
                f:row {
                    f:static_text {
                        alignment = 'center',
                        title = "Collection Sets to clone : " .. stats.collectionSets,
                        font = "<system>",
                        fill_horizontal = 1,
                    }
                },

                f:row {
                    f:static_text {
                        alignment = 'center',
                        title = "Collections to clone : " .. stats.collections,
                        font = "<system>",
                        fill_horizontal = 1,
                    }
                },
                f:row {
                    f:static_text {
                        alignment = 'center',
                        title = "Smart Collections to clone : " .. stats.smartCollections,
                        font = "<system>",
                        fill_horizontal = 1,
                    }
                },


                f:row {
                    f:static_text {
                        title = "Images to clone : " .. stats.images,
                        font = "<system>",
                        alignment = 'center',
                        fill_horizontal = 1,
                    }
                },

                f:row {
                    f:static_text {
                        title = text4,
                        font = "<system/bold>",
                        alignment = 'center',
                        fill_horizontal = 1,
                    }
                },

                f:row {
                    f:static_text {
                        title = text5,
                        font = "<system/bold>",
                        alignment = 'center',
                        fill_horizontal = 1,
                    }
                },
            },
        },
    }

    if canClone then
        local dialog = LrDialogs.presentModalDialog({
            title = "Confirm details of Publish Service to be cloned",
            contents = c,
            actionVerb = "Clone",
            cancelVerb = "Cancel",
        })
        if dialog == "ok" then
            local rv = importService(propertyTable, thisService, impService, indexById, pwDetails, stats)
        end
    else
        local dialog = LrDialogs.presentModalDialog({
            title = "Details of Publish Service to be cloned",
            contents = c,
            actionVerb = "Cancel Clone",
            cancelVerb = "< exclude >",
        })
    end
end

-- *************************************************
function PWIMportService.selectService(propertyTable)
    -- start of clone service function
    local foundService, thisService = PiwigoAPI.getPublishService(propertyTable)
    if not foundService or not thisService then
        log:info("PWIMportService.selectService - cannot find this Publish Service")
        return false
    end
    local catalog = LrApplication.activeCatalog()

    -- check if current service has any published collections/sets - exit if so
    local childColls = thisService:getChildCollections() or nil
    local childCollSets = thisService:getChildCollectionSets() or nil
    if not (utils.nilOrEmpty(childColls)) or not (utils.nilOrEmpty(childCollSets)) then
        --if thisService:getChildCollections() or thisService:getChildCollectionSets() then
        LrDialogs.message("Error", "Cannot clone into this service as it already contains Published Collections or Sets.",
            "info")
        return
    end

    LrFunctionContext.callWithContext("PWImportServiceContext", function(context)
        -- Create a property table inside the context


        local allServices = catalog:getPublishServices() or {}
        if #allServices == 0 then
            LrDialogs.message("No publish services found.")
            return
        end
        local serviceItems = {}
        local serviceNames = {}
        -- build list of publish services excluding this one
        local availableServices = {}
        for i, s in pairs(allServices) do
            if s:getName() ~= thisService:getName() then
                table.insert(availableServices, s)
            end
        end
        for i, s in ipairs(availableServices) do
            table.insert(serviceItems, {
                title = s:getName(),
                value = s,
            })
            table.insert(serviceNames, {
                title = s:getName(),
                value = i
            })
        end

        local props = LrBinding.makePropertyTable(context)
        local bind = LrView.bind
        props = bind {
            selectedService = 1, -- default to first service
        }
        local f = LrView.osFactory()
        local c = f:column {
            spacing = f:dialog_spacing(),
            f:row {
                -- TOP: icon + version block
                f:picture {
                    alignment = 'left',
                    value = iconPath,
                },
                f:column {
                    spacing = f:control_spacing(),
                    f:spacer { height = 3 },
                    f:row {
                        f:static_text {
                            title = "    Clone selected Publish Service to " .. thisService:getName() .. " Publish Service",
                            font = "<system/bold>",
                            alignment = 'left',
                            fill_horizontal = 1,
                            height_in_lines = 2,
                        },
                    },
                },

            },

            f:row {
                spacing = f:label_spacing(),
                f:spacer { height = 3 },
                f:static_text {
                    title = "                    ",
                    alignment = 'left',
                },
                f:static_text {
                    title = "Select Publish Service to clone:",
                    alignment = 'right',
                    width = 200,
                },

                f:popup_menu {
                    value = LrView.bind { key = 'selectedService', bind_to_object = props },
                    items = serviceNames,
                    value_equal = valueEqual,
                    width = 250,
                },
            },
            f:row {
                f:spacer { height = 2 },
                f:static_text {
                    title = "        Please ensure selected service is up to date - i.e. with no outstanding photographs to be published",
                    alignment = 'left',
                },
            }

        }

        local dialog = LrDialogs.presentModalDialog({
            title = "Piwigo Publisher - Clone Existing Publish Service",
            contents = c,
            actionVerb = "Next",
            cancelVerb = "Cancel",
        })

        if dialog == "ok" then
            -- get the actual service object
            local serviceNo = props.selectedService
            -- get service object for selected service
            local selService = serviceItems[serviceNo].value
            if not selService then
                LrDialogs.message("Error", "Could not find publish service", "error")
                return
            end
            LrTasks.startAsyncTask(function()
                importServicePrelim(propertyTable, thisService, selService)
            end)
        end
    end)
end

-- *************************************************
return PWIMportService
