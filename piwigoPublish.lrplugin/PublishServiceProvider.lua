--[[
	
	PublishServiceProvider.lua
	
	Publish Service Provider for Piwigo Publisher plugin

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

require "PublishDialogSections"
require "PublishTask"

return {

	-- Dialog Settings
	startDialog = PublishDialogSections.startDialog,
	sectionsForTopOfDialog = PublishDialogSections.sectionsForTopOfDialog,
	sectionsForBottomOfDialog = PublishDialogSections.sectionsForBottomOfDialog,
	endDialog = PublishDialogSections.endDialog,

	hideSections = { 'exportLocation', 'videoFileSettings' },


	-- Behaviour Settings
	allowFileFormats = { "JPEG", "PNG" },
	allowColorSpaces = nil,
	canExportVideo = true,
	allowVideoExportPresets = {
		{ formatID = "original" },  -- LrC does not re-encode; Video Toolkit handles transcoding
	},
	supportsCustomSortOrder = true,
	hidePrintResolution = true,
	supportsIncrementalPublish = 'only', -- plugin only visible in publish services, not export


	-- these fields are stored in the publish service settings by Lightroom
	exportPresetFields = {
		{ key = 'host',                  default = '' },
		{ key = "userName",              default = '' },
		{ key = "userPW",                default = '' },
		{ key = "KwFullHierarchy",       default = true },
		{ key = "KwSynonyms",            default = true },
		{ key = "mdTitle",               default = "{{title}}" },
		{ key = "mdDescription",         default = "{{caption}}" },
		{ key = "albumDescSyncMode",     default = "ask" },
		{ key = "albumStatusSyncMode",   default = "ask" },
		{ key = "syncPhotoSortOrder",    default = false },
		{ key = "syncCommentsPublish",   default = true },
		{ key = "syncCommentsPubOnly",   default = false },
		{ key = "KwFilterInclude",       default = '' },
		{ key = "KwFilterExclude",       default = '' },
		-- Video Toolkit settings (Phase 2B)
		{ key = "vtkEnabled",            default = false },
		{ key = "vtkIncludeVideo",       default = true },
		{ key = "vtkToolkitPath",        default = '' },
		{ key = "vtkDefaultPreset",      default = "medium" },
		{ key = "vtkGeneratePoster",     default = true },
		{ key = "vtkPosterTimestamp",    default = 10 },
		{ key = "vtkPythonPath",         default = '' },
		{ key = "vtkFFmpegPath",         default = '' },
		{ key = "vtkFFprobePath",        default = '' },
		{ key = "vtkExifToolPath",       default = '' },
		{ key = "vtkPresetsFile",        default = '' },
		{ key = "vtkHardwareAccel",     default = 'auto' },
	},

	metadataThatTriggersRepublish = function(publishSettings, photoId, fieldName)
		-- This function is called by Lightroom to determine whether a metadata
		-- change should trigger republishing.
		local triggerFields = {
			title = true,
			caption = true,
			keywords = true,
			gps = true,
			dateCreated = true,
		}
		return triggerFields[fieldName] or false
	end,
	-- canExportToTemporaryLocation = true
	-- canExportToTemporaryLocation = true
	-- showSections = { 'fileNaming', 'fileSettings', etc... }

	-- UI Settings
	small_icon                                       = '/icons/icon_small.png',
	titleForPublishedCollection                      = 'Piwigo album',
	titleForPublishedCollectionSet                   = 'Piwigo album (Set for sub-albums)',
	titleForPublishedSmartCollection                 = 'Piwigo album (Smart collection)',
	titleForGoToPublishedCollection                  = "Go to Album in Piwigo",
	titleForGoToPublishedPhoto                       = "Go to Photo in Piwigo",
	-- titleForPublishedCollectionSet_standalone = ""
	-- titleForPublishedCollection_standalone = ""
	-- titleForPublishedSmartCollection_standalone = ""

	-- Images Processing function
	processRenderedPhotos                            = PublishTask.processRenderedPhotos,
	canAddCommentsToService                          = PublishTask.canAddCommentsToService,
	addCommentToPublishedPhoto                       = PublishTask.addCommentToPublishedPhoto,
	getCommentsFromPublishedCollection               = PublishTask.getCommentsFromPublishedCollection,
	deletePhotosFromPublishedCollection              = PublishTask.deletePhotosFromPublishedCollection,
	shouldDeletePhotosFromServiceOnDeleteFromCatalog = PublishTask.shouldDeletePhotosFromServiceOnDeleteFromCatalog,

	-- PublishService processing functions
	didCreateNewPublishService                       = PublishTask.didCreateNewPublishService,
	didUpdatePublishService                          = PublishTask.didUpdatePublishService,
	shouldDeletePublishService                       = PublishTask.shouldDeletePublishService,
	willDeletePublishService                         = PublishTask.willDeletePublishService,

	-- Published Collections / CollectionSets Processing functions
	getCollectionBehaviorInfo                        = PublishTask.getCollectionBehaviorInfo,
	viewForCollectionSetSettings                     = PublishTask.viewForCollectionSetSettings,
	updateCollectionSetSettings                      = PublishTask.updateCollectionSetSettings,
	viewForCollectionSettings                        = PublishTask.viewForCollectionSettings,
	updateCollectionSettings                         = PublishTask.updateCollectionSettings,
	renamePublishedCollection                        = PublishTask.renamePublishedCollection,
	reparentPublishedCollection                      = PublishTask.reparentPublishedCollection,
	deletePublishedCollection                        = PublishTask.deletePublishedCollection,
	imposeSortOrderOnPublishedCollection			 = PublishTask.imposeSortOrderOnPublishedCollection,
	validatePublishedCollectionName                  = PublishTask.validatePublishedCollectionName,

	-- view on Piwigo Options
	--goToPublishedCollection                          = PublishTask.goToPublishedCollection,
	--goToPublishedPhoto                               = PublishTask.goToPublishedPhoto,
}
