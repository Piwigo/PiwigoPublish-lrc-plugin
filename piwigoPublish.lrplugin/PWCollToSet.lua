--[[
   
    PWCollToSet.lua

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
local function CollToSet()
    log:info("CollToSet")
    local callStatus = {}
    local catalog = LrApplication.activeCatalog()

    local selPhotos =  catalog:getTargetPhotos()
    local sources = catalog:getActiveSources()

    -- is source a LrPublishedCollection or LrPublishedCollectionSet in selected published service
    local useService = nil
    local selectedCollection = nil
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
                    selectedCollection = source
                    publishSettings = thisSettings
                    break
                end
            end
        end
    end

    if not selectedCollection then
        LrDialogs.message("CollToSet - Can't access collection object for this publish collection - check selection","","warning")
        return false
    end
    if selectedCollection:type() == "LrPublishedCollectionSet" then
        LrDialogs.message("CollToSet - You have selected a Published Collection Set - please select a Published Collection","","warning")
        return false   
    end

    if not useService then
        LrDialogs.message("Please select a Collection within a Piwigo Publisher service","","warning")
        return false
    end
    if not publishSettings then
        LrDialogs.message("CollToSet - Can't find publish settings for this publish collection","","warning")
        return false
    end
    local selCollName = selectedCollection:getName()
    local selColParent = selectedCollection:getParent()
    catId = selectedCollection:getRemoteId()
    local selColParentName = nil
    local checkSCName = ""
    -- check that selected collection is not already a special collection
    if selColParent then
        if selCollName == PiwigoAPI.buildSpecialCollectionName(selColParent:getName()) then
            LrDialogs.message("Special Collections cannot be converted to Collection Sets","","warning")
            return false
        end
    end

    local result = LrDialogs.confirm("Covert Publish Collection to Set","Convert " ..selCollName .." to a Publish Collection Set?", "Ok","Cancel")
    if result ~= 'ok' then
        return false
    end

    -- 1 - rename seleted collection to a special collection name
    local newName = PiwigoAPI.buildSpecialCollectionName(selCollName)
    local rv = PiwigoAPI.setCollectionDets(selectedCollection, catalog, publishSettings, newName, catId, selColParent)

    -- 2 - Create new collection set
    -- Set parent and remote id same as selected collection parent
    local newCollSet = PiwigoAPI.createPublishCollectionSet(catalog, useService, publishSettings, selCollName, catId, selColParent)
    if not newCollSet then
        LrDialogs.message("CollToSet - Can't create new collection set " .. selCollName,"","warning")
        return false 
    end
    
    -- 3 - Set parent of selected collection to the new collection set
    rv = PiwigoAPI.setCollectionDets(selectedCollection, catalog, publishSettings, newName, catId, newCollSet)


end

LrTasks.startAsyncTask(CollToSet)