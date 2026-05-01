--[[
   
    Info.lua

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
return {
    LrSdkVersion = 14.3,
    LrSdkMinimumVersion = 6.0,
    LrPluginName = "Piwigo Publisher",
    -- typo in PwigoPublish is noted but can't be changed without forcing all services using this plugin to be re-initialised.
    LrToolkitIdentifier = "fiona.boston.PwigoPublish",
    LrMetadataProvider  = 'CustomMetadata.lua',
    LrMetadataTagsetFactory = 'Tagset.lua',
    LrInitPlugin = "Init.lua",

	LrExportServiceProvider = {
		title = "Piwigo Publisher",
		file = "PublishServiceProvider.lua",
	},

-- define custom metadata data for this plugin
    PublishSettings = {
        publishMetadata = {
            { id = 'myCustomStatus', title = "Status", type = 'string' },
            { id = 'syncToken', title = "Token", type = 'string' },
        },
    },
    
    LrLibraryMenuItems = {
        -- Menu items for Library -> Plug In Extras -> Piwigo Publisher
        --[[
        {
            title = "Piwigo Publisher Extra Options",
            file = "PWExtraOptions.lua",
        },
        ]]
        {
            title = "Set Piwigo Album Cover from Selected Photo",
            file = "PWSetAlbumCover.lua",
        },
        {
            title = "Send Metadata to Piwigo for Selected Photos",
            file = "PWSendMetadata.lua",
        },
        {
            title = "Convert selected Published Collection to Published Collection Set",
            file = "PWCollToSet.lua",
        },
    },
    
	LrPluginInfoProvider = 'PluginInfo.lua',

    VERSION = { major=20260305, minor=34, revision=0 },
}
