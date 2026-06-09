--[[

	UIHelpers.lua

	UI Helper Functions for Piwigo Publisher plugin

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

UIHelpers = {}

-- Functions for UI Management
-- *************************************************
local function valueEqual(a, b)
	-- Define a value_equal function for the popup_menu
	return a == b
end

-- *************************************************
-- Create plugin header with icon and version information
-- Returns a row containing icon + plugin name + version
-- *************************************************
function UIHelpers.createPluginHeader(f, share, iconPath, pluginVersion)
	local INDENT_PIXELS = 14

	return f:row {
		f:picture {
			alignment = 'left',
			value = iconPath,
		},
		f:column {
			spacing = f:control_spacing(),
			f:spacer { height = 1 },
			f:row {
				f:spacer { width = INDENT_PIXELS },
				f:static_text {
					title = "Piwigo Publisher Plugin",
					font = "<system/bold>",
					alignment = 'left',
					width = share 'labelWidth',
				},
			},
			f:row {
				f:spacer { width = INDENT_PIXELS },
				f:static_text {
					title = "Plugin Version",
					alignment = 'left',
				},
				f:static_text {
					title = pluginVersion,
					alignment = 'left',
					width = share 'labelWidth',
				},
			},
		},
	}
end

-- *************************************************
-- Create Piwigo Album Settings UI section
-- Returns a group_box with album description and private checkbox
-- *************************************************
function UIHelpers.createPiwigoAlbumSettingsUI(f, share, bind, collectionSettings, publishSettings)
	return f:group_box {
		title = "Piwigo Album Settings",
		font = "<system/bold>",
		size = 'regular',
		fill_horizontal = 1,
		bind_to_object = assert(collectionSettings),
		f:column {
			spacing = f:control_spacing(),

			f:separator { fill_horizontal = 1 },

			f:row {
				fill_horizontal = 1,
				f:static_text { title = "Album Description:", font = "<system>", alignment = 'right', width = share 'label_width', },
				f:edit_field {
					enabled = bind {
						key = 'syncAlbumDescriptions',
						bind_to_object = publishSettings,
					},
					font = "<system>",
					tooltip = "If synchronising album descriptions, description entered here will be sent to Piwigo. If not synchronising album descriptions, description entered here will be ignored.",
					value = bind 'albumDescription',
					fill_horizontal = 1,
					width_in_chars = 70,

					alignment = 'left',
					height_in_lines = 4,
				},
			},

			f:row {
				fill_horizontal = 1,
				f:static_text {
					title = "",
					alignment = 'right',
					width = share 'label_width',
				},
				f:checkbox {
					title = "",
					tooltip = "If checked, this album will be private on Piwigo",
					value = bind 'albumPrivate',
				},
				f:static_text {
					title = "Album is Private",
					font = "<system>",
				}
			},

			f:separator { fill_horizontal = 1 },
			f:row {
				fill_horizontal = 1,
				--[[
				f:static_text {
					title = "",
					alignment = 'right',
					width = share 'label_width',
				},]]
				f:checkbox {
					title = "Enable Custom Export Settings for this Album",
					font = "<system>",
					tooltip = "If checked, settings entered below will override the defaults set in Publish Settings for this album",
					value = bind 'enableCustom',
					enabled = bind {
						key = 'PWP_customAlbumSettings',
						bind_to_object = publishSettings,
						transform = function(value, fromModel)
							if fromModel then
								return value == true
							end
							return value
						end,
					},

				},
			},
		},
	}
end

-- *************************************************
-- Create Keyword Filtering inner elements (help texts + exclusion/inclusion fields)
-- Returns a flat list of UI elements to be inserted into a parent container
-- Options:
--   showOverrideHint (bool) : show "Leave empty to use global settings" text
--   widthInChars (number)   : width of edit fields (default 30)
--   heightInLines (number)  : height of edit fields (default 8)
--   fillColumns (bool)      : apply fill_horizontal on columns
-- *************************************************
function UIHelpers.createKeywordFilteringFields(f, bind, options)
	options               = options or {}
	local widthInChars    = options.widthInChars or 30
	local heightInLines   = options.heightInLines or 8
	local fillColumns     = options.fillColumns or false

	local exclusionColDef = {
		f:static_text {
			title = "Exclusion Rules\n(keywords matching these rules will not be sent to Piwigo)",
			font = "<system/bold>",
		},
		f:edit_field {
			value = bind 'KwFilterExclude',
			font = "<system>",
			alignment = 'left',
			width_in_chars = widthInChars,
			height_in_lines = heightInLines,
			fill_horizontal = fillColumns and 1 or nil,
			multiline = true,
			--tooltip = "Photos with any keyword matching these rules will not be published. One rule per line.",
			tooltip = "Keywords matching these rules will not sent to Piwigo. One rule per line. Overrides inclusion rules - if a keyword matches both exclusion and inclusion rules, it will be excluded.",
		},
	}
	if fillColumns then exclusionColDef.fill_horizontal = 1 end

	local inclusionColDef = {
		f:static_text {
			title = "Inclusion Rules\n(only keywords matching these rules will be sent to Piwigo)",
			font = "<system/bold>",
		},
		f:edit_field {
			value = bind 'KwFilterInclude',
			font = "<system>",
			alignment = 'left',
			width_in_chars = widthInChars,
			height_in_lines = heightInLines,
			fill_horizontal = fillColumns and 1 or nil,
			multiline = true,
			--tooltip = "Photos must have at least one keyword matching these rules to be published. Leave empty to allow all. One rule per line.",
			tooltip = "Only keywords matching these rules will be sent to Piwigo. One rule per line. Exclusion rules take precedence over inclusion rules - if a keyword matches both exclusion and inclusion rules, it will be excluded.",
		},
	}
	if fillColumns then inclusionColDef.fill_horizontal = 1 end
	local elements = {}
	if not options.showOverrideHint then
		-- options.showOverrideHint is set to false for the PublishDialogSections
		elements[#elements + 1] = f:static_text {
			title = "Keyword Filtering Settings",
			font = "<system/bold>",
		}
	end
	elements[#elements + 1] = f:static_text {
		--title = "Use these rules to filter photos based on their keywords when publishing.",
		title = "Use these rules remove keywords from photos in Piwigo when published. ",
		font = "<system>",
	}

	elements[#elements + 1] = f:static_text {
		title = "One rule per line. Use Option+Enter (Mac) or Alt+Enter (Windows) to add a new line.",
		font = "<system>",
	}

	elements[#elements + 1] = f:static_text {
		title = "Wildcards: * matches any number of characters, ? matches exactly one character.",
		font = "<system>",
	}

	elements[#elements + 1] = f:static_text {
		title = "Examples: nature* (nature, natureza, etc.), *photo* (photograph, photoshop, etc.), ?at (bat, cat, hat, etc.)",
		font = "<system>",
	}

	elements[#elements + 1] = f:static_text {
		title = "All levels of hierarchy are considered. If a keyword matches both exclusion and inclusion rules, it will be excluded.",
		font = "<system>",
	}
	if options.allowCustomAlbumSettings then
		if not options.showOverrideHint then
			elements[#elements + 1] = f:static_text {
				title = "Rules can also be set for individual albums, overriding these global settings.",
				font = "<system>",
			}
		end
		if options.showOverrideHint then
			elements[#elements + 1] = f:static_text {
				title = "Leave empty to use global settings from Publish Settings.",
				font = "<system>",
			}
		end
	end
	elements[#elements + 1] = f:spacer { height = 2 }
	elements[#elements + 1] = f:row {
		fill_horizontal = 1,
		spacing = f:control_spacing(),
		f:column(exclusionColDef),
		f:column(inclusionColDef),
	}

	return elements
end

-- *************************************************
-- Create Album Sorting UI section (standalone group_box)
-- -- Used in PublishTask for collection settings dialogs
-- *************************************************
function UIHelpers.createSortOrderUI(f, bind, collectionSettings, publishSettings)
	local sortOrderUI = f:group_box {
		title = "Sort Order",
		visible = bind {
			key = 'enableCustom',
			bind_to_object = collectionSettings,
		},
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
	return sortOrderUI
end

-- *************************************************
-- Create Keyword Filtering UI section (standalone group_box)
-- Returns a group_box with exclusion and inclusion rules
-- Used in PublishTask for collection settings dialogs
-- *************************************************
function UIHelpers.createKeywordFilteringUI(f, bind, collectionSettings, propertyTable)
	local fields = UIHelpers.createKeywordFilteringFields(f, bind, {
		showOverrideHint = true,
		widthInChars = 35,
		heightInLines = 6,
		fillColumns = true,
	})

	local columnContents = {
		spacing = f:control_spacing(),
		fill_horizontal = 1,
		f:separator { fill_horizontal = 1 },
	}
	for _, elem in ipairs(fields) do
		columnContents[#columnContents + 1] = elem
	end

	return f:group_box {
		title = "Keyword Filtering (Overrides defaults set in Publish Settings)",
		visible = bind {
			key = 'enableCustom',
			bind_to_object = collectionSettings,
		},
		font = "<system/bold>",
		size = 'regular',
		fill_horizontal = 1,
		bind_to_object = assert(collectionSettings),
		f:column(columnContents),
	}
end

-- *************************************************
-- Create "Metadata Settings" group_box for PublishDialogSections
-- Contains fields for metadata templates for title and description
-- *************************************************
--UIHelpers.createMetaDataUI(f, bind, collectionSettings, publishSettings)
function UIHelpers.createMetaDataGroupBox(f, bind)
	local metadataGroupDef = {
		title = "Metadata Settings",
		font = "<system/bold>",
		fill_horizontal = 1,

		f:spacer { height = 2 },

		f:row {
			f:static_text {
				title = "Title: ",
				font = "<system>",
				alignment = 'right',
				width_in_chars = 8,
			},
			f:edit_field {
				value = bind 'mdTitle',
				font = "<system>",
				alignment = 'left',
				width_in_chars = 60,
				height_in_lines = 3,
			},
		},
		f:row {
			f:static_text {
				title = "Description: ",
				font = "<system>",
				alignment = 'right',
				width_in_chars = 8,
			},
			f:edit_field {
				value = bind 'mdDescription',
				font = "<system>",
				alignment = 'left',
				width_in_chars = 60,
				height_in_lines = 3,
			},
		},
	}

	return f:group_box(metadataGroupDef)
end

-- *************************************************
-- Create "Metadata Settings" group_box for PublishDialogSections
-- Contains fields for metadata templates for title and description
-- *************************************************
function UIHelpers.createMetaDataUI(f, bind, collectionSettings, publishSettings)
	local metadataGroupDef = {
		title = "Metadata Settings (Overrides defaults set in Publish Settings)",
		visible = bind {
			key = 'enableCustom',
			bind_to_object = collectionSettings,
		},
		font = "<system/bold>",
		size = 'regular',
		fill_horizontal = 1,
		bind_to_object = assert(collectionSettings),
		f:spacer { height = 2 },
		f:row {
			f:static_text {
				title = "Title: ",
				font = "<system>",
				alignment = 'right',
				width_in_chars = 8,
			},
			f:edit_field {
				value = bind 'mdTitle',
				font = "<system>",
				alignment = 'left',
				width_in_chars = 60,
				height_in_lines = 3,
			},
		},
		f:row {
			f:static_text {
				title = "Description: ",
				font = "<system>",
				alignment = 'right',
				width_in_chars = 8,
			},
			f:edit_field {
				value = bind 'mdDescription',
				font = "<system>",
				alignment = 'left',
				width_in_chars = 60,
				height_in_lines = 3,
			},
		},
	}

	local mdBox = f:group_box(metadataGroupDef)

	return mdBox
end



-- *************************************************
-- Create "Album Customisation Settings" group_box for PublishDialogSections
-- Contains checkbox for album association and custom album settings
-- *************************************************
function UIHelpers.createAlbumSettingsGroupBox(f, bind, propertyTable)
	local albumSettingsDef = {
		title = "Album Association and Per Album Export Settings",
		font = "<system/bold>",
		fill_horizontal = 1,

		f:spacer { height = 1 },
		f:row {
			fill_horizontal = 1,
			f:static_text {
				title = "",
				alignment = 'right',
				width_in_chars = 7,
			},
			f:checkbox {
				title = "Use Album Association to share a single image between multiple Piwigo Albums",
				enabled = bind {
					key = 'PWP_customAlbumSettings',
					bind_to_object = propertyTable,
					transform = function(value, fromModel)
						if fromModel then
							return not value -- invert for display
						end
						return value
					end,
				},
				font = "<system>",
				tooltip = "When checked, if the same image is uploaded to multiple albums, it will be uploaded once and associated with the other albums in Piwigo, rather than being uploaded multiple times.",
				value = bind 'PWP_albumAssociation',
			},
		},

		f:row {
			fill_horizontal = 1,
			f:static_text {
				title = "",
				alignment = 'right',
				width_in_chars = 7,
			},
			f:static_text {
				title = "When enabled, if the same image is uploaded to multiple albums, a single copy will be uploaded and associated with the other albums in Piwigo." ..
					"\nWhen disabled (album association not used), if the same image is uploaded to multiple albums, a separate copy will be uploaded in each album." ..
					"\nAlbum association is not compatible with per-album custom settings - if album association is enabled, per-album custom settings will be disabled.",

				font = "<system>",
				wrap = true,

			},
		},

		f:spacer { height = 1 },
		f:row {
			fill_horizontal = 1,
			f:static_text {
				title = "",
				alignment = 'right',
				width_in_chars = 7,
			},
			f:checkbox {
				title = "Per-album custom export settings",
				enabled = bind {
					key = 'PWP_albumAssociation',
					bind_to_object = propertyTable,
					transform = function(value, fromModel)
						if fromModel then
							return not value -- invert for display
						end
						return value
					end,
				},
				font = "<system>",
				tooltip = "When checked, per-album custom export settings will be enabled, allowing different metadata, keyword filtering rules and export rules to be set for each album. Disables album association - if the same image is uploaded to multiple albums, a separate copy will be uploaded in each album.",
				value = bind 'PWP_customAlbumSettings',
			},
		},
		f:row {
			fill_horizontal = 1,
			f:static_text {
				title = "",
				alignment = 'right',
				width_in_chars = 7,
			},
			f:static_text {
				title = "When enabled, custom settings for each album can be set. If disabled, the global settings will be used for all albums." ..
					"\nThese settings include metadata templates for title and description, sorting options, keyword filtering rules and export settings (resizing, metadata stripping etc.)." ..
					"\nPer-album custom settings are not compatible with album association - if per-album custom settings are enabled, album association will be disabled.",
				font = "<system>",
				wrap = true,

			},
		},

	}
	return f:group_box(albumSettingsDef)
end

-- *************************************************
-- Create "Other Settings" group_box for PublishDialogSections
--
-- *************************************************

function UIHelpers.createOtherSettingsGroupBox(f, bind, propertyTable)
	local otherSettingsDef = {
		title = "Other Settings",
		font = "<system/bold>",
		fill_horizontal = 1,
		f:spacer { height = 1 },
		f:row {
			fill_horizontal = 1,
			f:static_text {
				title = "",
				alignment = 'right',
				width_in_chars = 7,
			},
			f:checkbox {
				title = "Synchronise Album Descriptions",
				font = "<system>",
				tooltip = "If checked, Album descriptions will be maintainable in Lightroom and sent to Piwigo",
				value = bind 'syncAlbumDescriptions',
			},
		},

		f:spacer { height = 1 },
		f:row {
			fill_horizontal = 1,
			f:static_text {
				title = "",
				alignment = 'right',
				width_in_chars = 7,
			},
			f:checkbox {
				title = "Synchronise Photo Sort Order",
				font = "<system>",
				tooltip = "If checked, the photo display order in Lightroom will be sent to Piwigo after each publish",
				value = bind 'syncPhotoSortOrder',
			},
		},

		f:spacer { height = 1 },
		f:row {
			fill_horizontal = 1,
			f:static_text {
				title = "",
				alignment = 'right',
				width_in_chars = 7,
			},
			f:checkbox {
				title = "Synchronise comments as part of a Publish Process",
				font = "<system>",
				tooltip = "When checked, comments will be synchronised for all photos in a collection during a publish operation",
				value = bind 'syncCommentsPublish',
			},
		},
		f:row {
			fill_horizontal = 1,
			f:static_text {
				title = "",
				alignment = 'right',
				width_in_chars = 7,
			},
			f:checkbox {
				title = "Only include Published Photos",
				enabled = bind('syncCommentsPublish', propertyTable),
				font = "<system>",
				tooltip = "When checked, only photos being published will have comments synchronised",
				value = bind 'syncCommentsPubOnly',
			},
		},
	}

	return f:group_box(otherSettingsDef)
end

-- *************************************************
-- Create "Keyword Settings" group_box for PublishDialogSections
-- Combines checkboxes (Hierarchy/Synonyms) + filtering fields
-- Built dynamically to allow merging fixed elements with shared filtering fields
-- *************************************************
function UIHelpers.createKeywordSettingsGroupBox(f, bind)
	local filterFields = UIHelpers.createKeywordFilteringFields(f, bind, {
		showOverrideHint = false,
		widthInChars = 30,
		heightInLines = 8,
		fillColumns = false,
	})

	local groupBoxDef = {
		title = "Keyword Settings",
		font = "<system/bold>",
		fill_horizontal = 1,
		-- Checkboxes
		f:spacer { height = 2 },
		f:row {
			fill_horizontal = 1,
			f:static_text {
				title = "",
				alignment = 'right',
				width_in_chars = 7,
			},
			f:checkbox {
				font = "<system>",
				title = "Include Full Keyword Hierarchy",
				tooltip = "If checked, all keywords in a keyword hierarchy will be sent to Piwigo",
				value = bind 'KwFullHierarchy',
			},
		},
		f:spacer { height = 2 },
		f:row {
			fill_horizontal = 1,
			f:static_text {
				title = "",
				alignment = 'right',
				width_in_chars = 7,
			},
			f:checkbox {
				font = "<system>",
				title = "Include Keyword Synonyms",
				tooltip = "If checked, keyword synonyms will be sent to Piwigo",
				value = bind 'KwSynonyms',
			},
		},
		f:spacer { height = 2 },
		f:separator { fill_horizontal = 1 },
		f:spacer { height = 2 },
	}

	-- Append filtering fields dynamically
	for _, elem in ipairs(filterFields) do
		groupBoxDef[#groupBoxDef + 1] = elem
	end

	return f:group_box(groupBoxDef)
end

-- *************************************************
-- Create "Export Settings" group_box for PublishDialogSections
-- Combines checkboxes (Hierarchy/Synonyms) + filtering fields
-- Built dynamically to allow merging fixed elements with shared filtering fields
-- *************************************************
function UIHelpers.createExportSettingsGroupBox(f, bind, collectionSettings, propertyTable)
	local reSizeOptions = {
		{ title = "Long Edge",  value = "Long Edge" },
		{ title = "Short Edge", value = "Short Edge" },
		{ title = "Dimensions", value = "Dimensions" },
		{ title = "Megapixels", value = "MegaPixels" },
		{ title = "Percent",    value = "Percent" },
	}

	local function visibleWhenResizeMode(mode)
		return bind {
			key = 'reSizeParam',
			transform = function(value, fromModel)
				if fromModel then
					return value == mode
				end
				return value
			end,
		}
	end

	local function enabledWhenResize()
		return bind {
			key = 'reSize',
			bind_to_object = collectionSettings,
			transform = function(value, fromModel)
				if fromModel then
					return value and true or false
				end
				return value
			end,
		}
	end
	local metaDataOpts = {
		{ title = "All Metadata",                        value = "All Metadata" },
		{ title = "Copyright only",                      value = "Copyright Only" },
		{ title = "Copyright & Contact Info Only",       value = "Copyright & Contact Info Only" },
		{ title = "All Except Camera Raw Info",          value = "All Except Camera Raw Info" },
		{ title = "All Except Camera & Camera Raw Info", value = "All Except Camera & Camera Raw Info" },
	}

	local pubSettingsUI = f:group_box {
		title = "Custom Publish Settings (Overrides defaults set in Publish Settings)",
		font = "<system/bold>",
		size = 'regular',
		visible = bind {
			key = 'enableCustom',
			bind_to_object = collectionSettings,
			transform = function(value, fromModel)
				if fromModel then
					return (value and true or false) and
						(propertyTable and propertyTable.PWP_customAlbumSettings and true or false)
				end
				return value
			end,
		},
		fill_horizontal = 1,
		bind_to_object = assert(collectionSettings),
		f:column {
			spacing = f:control_spacing(),
			fill_horizontal = 1,
			f:separator { fill_horizontal = 1 },

			f:row {
				f:group_box { -- group for export parameters
					title = "Export Settings",

					font = "<system>",
					fill_horizontal = 1,
					bind_to_object = assert(collectionSettings),
					f:row {
						fill_horizontal = 1,
						spacing = f:label_spacing(),

						f:checkbox {
							title = "Resize Image",
							tooltip = "If checked, published image will be resized using the settings below",
							value = bind 'reSize',
						},
					},

					f:row {
						fill_horizontal = 1,
						spacing = f:label_spacing(),
						enabled = bind {
							key = 'reSize',
							bind_to_object = collectionSettings,
						},
						f:static_text {
							title = "Resize Method:",
							alignment = 'right',
							width_in_chars = 14,
						},
						f:popup_menu {
							value = bind 'reSizeParam',
							items = reSizeOptions,
							value_equal = valueEqual,
							enabled = enabledWhenResize(),
						},
						f:checkbox {
							title = "Allow Enlarge Image",
							tooltip = "If checked, published image will be enlarged if necessary",
							enabled = enabledWhenResize(),
							value = bind {
								key = 'reSizeNoEnlarge',
								transform = function(value)
									return not value
								end,
							},
						},
					},

					f:row {
						fill_horizontal = 1,
						spacing = f:label_spacing(),
						enabled = bind {
							key = 'reSize',
							bind_to_object = collectionSettings,
						},
						visible = visibleWhenResizeMode("Long Edge"),
						f:static_text {
							title = "Long Edge (px):",
							alignment = 'right',
							width_in_chars = 14,
						},
						f:edit_field {
							value = bind 'reSizeLongEdge',
							enabled = enabledWhenResize(),
							width_in_chars = 8,
							tooltip = "Maximum length of the longest edge in pixels",
						},
					},

					f:row {
						fill_horizontal = 1,
						spacing = f:label_spacing(),
						enabled = bind {
							key = 'reSize',
							bind_to_object = collectionSettings,
						},
						visible = visibleWhenResizeMode("Short Edge"),
						f:static_text {
							title = "Short Edge (px):",
							alignment = 'right',
							width_in_chars = 14,
						},
						f:edit_field {
							value = bind 'reSizeShortEdge',
							enabled = enabledWhenResize(),
							width_in_chars = 8,
							tooltip = "Maximum length of the shortest edge in pixels",
						},
					},

					f:row {
						fill_horizontal = 1,
						spacing = f:label_spacing(),
						enabled = bind {
							key = 'reSize',
							bind_to_object = collectionSettings,
						},
						visible = visibleWhenResizeMode("Dimensions"),
						f:static_text {
							title = "Dimensions (px):",
							alignment = 'right',
							width_in_chars = 14,
						},
						f:edit_field {
							value = bind 'reSizeW',
							enabled = enabledWhenResize(),
							width_in_chars = 8,
							tooltip = "Maximum width in pixels",
						},
						f:static_text {
							title = "x",
							alignment = 'center',
							width_in_chars = 2,
						},
						f:edit_field {
							value = bind 'reSizeH',
							enabled = enabledWhenResize(),
							width_in_chars = 8,
							tooltip = "Maximum height in pixels",
						},
					},

					f:row {
						fill_horizontal = 1,
						spacing = f:label_spacing(),
						enabled = bind {
							key = 'reSize',
							bind_to_object = collectionSettings,
						},
						visible = visibleWhenResizeMode("MegaPixels"),
						f:static_text {
							title = "Megapixels:",
							alignment = 'right',
							width_in_chars = 14,
						},
						f:edit_field {
							value = bind 'reSizeMP',
							enabled = enabledWhenResize(),
							width_in_chars = 8,
							tooltip = "Target image size in megapixels",
						},
					},

					f:row {
						fill_horizontal = 1,
						spacing = f:label_spacing(),
						enabled = bind {
							key = 'reSize',
							bind_to_object = collectionSettings,
						},
						visible = visibleWhenResizeMode("Percent"),
						f:static_text {
							title = "Scale Percent:",
							alignment = 'right',
							width_in_chars = 14,
						},
						f:edit_field {
							value = bind 'reSizePC',
							enabled = enabledWhenResize(),
							width_in_chars = 8,
							tooltip = "Scale image by percentage",
						},
						f:static_text {
							title = "%",
							alignment = 'left',
						},

					},
				},
			},
		},
	}

	return pubSettingsUI
end

-- *************************************************
return UIHelpers
