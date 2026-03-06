--[[
   
    TagSet.lua

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


return {
title = LOC "$$$/FionaBoston/Title=Piwigo Publisher Metadata", id = 'PWPTagset',
items = {

        'com.adobe.filename',
        'com.adobe.copyname',
        "com.adobe.dateTimeOriginal",
        'com.adobe.folder',
        'com.adobe.separator',

        
        { formatter = 'com.adobe.label', label = "Most Recent Upload",},
        'fiona.boston.PwigoPublish.pwHostURL',
        'fiona.boston.PwigoPublish.pwAlbumName',
        'fiona.boston.PwigoPublish.pwAlbumURL', 
        'fiona.boston.PwigoPublish.pwImageURL',
        'fiona.boston.PwigoPublish.pwUploadDate',
        'fiona.boston.PwigoPublish.pwUploadTime',

        },
}
