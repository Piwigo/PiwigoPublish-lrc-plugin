--[[
    vtk_ui.lua - Video Toolkit UI section

    Extracted from PublishDialogSections.lua. Provides:
      - vtk_ui.videoDialog(f, propertyTable) : LrView section for Video Settings

    All globals (LrView, LrTasks, LrDialogs, LrPathUtils, LrSystemInfo,
    utils, JSON) are provided by Init.lua.

    Copyright (C) 2024 Fiona Boston <fiona@fbphotography.uk>.
    This file is part of PiwigoPublish (GPLv3).
]]

---@diagnostic disable: undefined-global

local vtk_ui = {}

local VTK_PRESETS       = { "small", "medium", "large", "xlarge", "xxl", "origin" }
local VTK_PRESET_LABELS = { "Small (480p)", "Medium (720p)", "Large (1080p)", "XLarge (1440p)", "XXL (2160p)", "Origin (no transcode)" }

-- Download URLs for external tools
local DL_PYTHON   = "https://www.python.org/downloads/"
local DL_FFMPEG   = "https://ffmpeg.org/download.html"
local DL_EXIFTOOL = "https://exiftool.org/"

function vtk_ui.videoDialog(f, propertyTable)
	local bind = LrView.bind
	local share = LrView.share

	-- Build preset items list for popup_menu
	local presetItems = {}
	for i, key in ipairs(VTK_PRESETS) do
		presetItems[#presetItems + 1] = { title = VTK_PRESET_LABELS[i], value = key }
	end

	-- Helper: section header row
	local function sectionHeader(title)
		return f:row {
			f:static_text {
				title = title,
				fill_horizontal = 1,
				font = "<system/bold>",
				text_color = LrColor(0.4, 0.4, 0.4),
			},
		}
	end

	-- Helper: download button (small, opens URL)
	local function dlButton(url, tip)
		return f:push_button {
			title = "Download",
			tooltip = tip,
			width_in_chars = 9,
			action = function() LrHttp.openUrlInBrowser(url) end,
		}
	end

	return {
		title = "Video Settings",
		bind_to_object = propertyTable,

		f:group_box {
			title = "Video Toolkit",
			fill_horizontal = 1,

			f:spacer { height = 2 },

			-- "Include" first (intent), then "Enable" (mechanism)
			f:row {
				fill_horizontal = 1,
				f:checkbox {
					title = "Include video files in publications",
					fill_horizontal = 1,
					value = bind "vtkIncludeVideo",
					tooltip = "Include video files in publications.",
				},
			},

			f:row {
				fill_horizontal = 1,
				f:checkbox {
					title = "Enable Video Toolkit (local transcoding)",
					fill_horizontal = 1,
					value = bind "vtkEnabled",
					tooltip = "When enabled, videos are transcoded locally by the Video Toolkit before upload.",
					enabled = bind "vtkIncludeVideo",
				},
			},

			f:spacer { height = 4 },

			-- Encoding Settings
			f:separator { fill_horizontal = 1 },
			sectionHeader("Encoding Settings"),
			f:column {
				fill_horizontal = 1,
				enabled = bind "vtkEnabled",

				f:spacer { height = 2 },

				-- Default preset + Hardware accel on same row
				f:row {
					f:static_text {
						title = "Default preset:",
						alignment = 'right',
						width = share 'vtk_label_w',
					},
					f:popup_menu {
						value = bind "vtkDefaultPreset",
						items = presetItems,
						tooltip = "Preset applied to all videos unless overridden per collection.",
					},
					f:spacer { width = 16 },
					f:static_text {
						title = "Hardware accel:",
						alignment = 'right',
					},
					f:popup_menu {
						value = bind "vtkHardwareAccel",
						items = {
							{ title = "Auto (detect GPU)", value = "auto" },
							{ title = "CPU only (libx264)", value = "cpu" },
							{ title = "GPU (force)", value = "gpu" },
						},
						tooltip = "GPU hardware acceleration. Auto detects the best available encoder. HDR sources always use CPU (tonemap).",
					},
				},

				f:spacer { height = 2 },

				-- Poster thumbnail + Poster at on same row
				f:row {
					f:static_text {
						title = "Poster thumbnail:",
						alignment = 'right',
						width = share 'vtk_label_w',
					},
					f:checkbox {
						title = "Generate poster (JPG)",
						value = bind "vtkGeneratePoster",
						tooltip = "Extract a JPG thumbnail from the video and upload as representative image.",
					},
					f:spacer { width = 16 },
					f:static_text {
						title = "Poster at:",
						alignment = 'right',
					},
					f:edit_field {
						value = bind "vtkPosterTimestamp",
						width_in_chars = 4,
						tooltip = "Percentage of video duration for the thumbnail frame (0-95).",
						enabled = bind "vtkGeneratePoster",
					},
					f:static_text {
						title = "% of duration",
						alignment = 'left',
					},
				},
			},

			f:spacer { height = 4 },

			-- Status (before Advanced)
			f:separator { fill_horizontal = 1 },
			sectionHeader("Status"),
			f:column {
				fill_horizontal = 1,
				enabled = bind "vtkEnabled",

				f:spacer { height = 2 },

				f:row {
					f:static_text {
						title = LrView.bind {
							keys = { "vtkEnabled", "vtkIncludeVideo" },
							operation = function(_, values, _)
								if not values.vtkIncludeVideo then
									return "Video files not included."
								end
								if not values.vtkEnabled then
									return "Video Toolkit disabled - videos uploaded as-is."
								end
								return "Use 'Check Tools' to verify installation."
							end,
						},
						fill_horizontal = 1,
						alignment = 'left',
						font = "<system/small>",
					},
				},

				f:spacer { height = 2 },

				f:row {
					f:push_button {
						title = "Check Tools...",
						width = share 'buttonwidth',
						enabled = bind "vtkEnabled",
						tooltip = "Run Video Toolkit to verify Python, FFmpeg and ExifTool installations.",
						action = function(_)
							LrTasks.startAsyncTask(function()
								local python     = utils.resolveTool(propertyTable.vtkPythonPath, "python")
								local plugin     = rawget(_G, "_PLUGIN")
								local toolkitPath = utils.resolveToolkitPath(propertyTable.vtkToolkitPath, plugin.path)
								local isWindows  = (LrSystemInfo.osVersion():lower():find("win") ~= nil)
								local installCmd = isWindows and "winget install --id Gyan.FFmpeg" or "brew install ffmpeg"

								local tools = {
									{ key = "vtkFFmpegPath",   name = "FFmpeg",   val = propertyTable.vtkFFmpegPath },
									{ key = "vtkFFprobePath",  name = "FFprobe",  val = propertyTable.vtkFFprobePath },
									{ key = "vtkExifToolPath", name = "ExifTool", val = propertyTable.vtkExifToolPath },
								}
								for _, t in ipairs(tools) do
									if t.val and t.val ~= "" and not utils.fileExists(t.val) then
										LrDialogs.message("Video Toolkit - Invalid Path",
											"The configured path for " .. t.name .. " is invalid:\n" .. t.val .. "\n\nFix the path in Advanced settings, or clear the field to let the toolkit detect it automatically.", "critical")
										return
									end
								end

								if not utils.fileExists(python) then
									LrDialogs.message("Video Toolkit - Python Not Found",
										"Python was not found at:\n" .. python .. "\n\nFix the path in Advanced settings, or clear the field for auto-detect.", "critical")
									return
								end
								if not utils.fileExists(toolkitPath) then
									LrDialogs.message("Video Toolkit - Script Not Found",
										"video_toolkit.py not found at:\n" .. toolkitPath .. "\n\nFix the path in Advanced settings, or clear the field for auto-detect.", "critical")
									return
								end

								local outFile = LrPathUtils.child(LrPathUtils.getStandardFilePath("temp"), "vtk_check.json")
								local innerCmd = '"' .. python .. '" "' .. toolkitPath .. '" --mode check > "' .. outFile .. '" 2>&1'
								local cmd = isWindows and ('cmd /c "' .. innerCmd .. '"') or innerCmd
								local result = LrTasks.execute(cmd)
								local checkOutput = ""
								local fh = io.open(outFile, "r")
								if fh then checkOutput = fh:read("*a"); fh:close() end

								if result == 0 then
									local ok, parsed = pcall(JSON.decode, JSON, checkOutput)
									if ok and parsed then
										local function fillIfEmpty(key, val)
											if val and val ~= "not found" and (not propertyTable[key] or propertyTable[key] == "") then
												propertyTable[key] = val
											end
										end
										fillIfEmpty("vtkFFmpegPath",  parsed.ffmpeg)
										fillIfEmpty("vtkFFprobePath", parsed.ffprobe)
										fillIfEmpty("vtkExifToolPath", parsed.exiftool)
									end
									if not (propertyTable.vtkPythonPath and propertyTable.vtkPythonPath ~= "") then
										propertyTable.vtkPythonPath = python
									end
									if not (propertyTable.vtkToolkitPath and propertyTable.vtkToolkitPath ~= "") then
										propertyTable.vtkToolkitPath = toolkitPath
									end
									LrDialogs.message("Video Toolkit - OK",
										"All tools verified and working.\n\nDetected paths have been filled in Advanced settings.", "info")
								else
									LrDialogs.message("Video Toolkit - FFprobe Not Found",
										"Python and the toolkit are working, but ffprobe was not found.\n\n"
										.. "Install FFmpeg (includes ffprobe):\n  " .. installCmd .. "\n\n"
										.. "Or set the FFprobe path in Advanced settings.", "critical")
								end
							end)
						end,
					},
				},

				f:spacer { height = 2 },
			},

			f:spacer { height = 4 },

			-- Advanced paths (after Status)
			f:separator { fill_horizontal = 1 },
			sectionHeader("Advanced - Tool Paths"),
			f:column {
				fill_horizontal = 1,
				enabled = bind "vtkEnabled",

				f:spacer { height = 2 },

				f:row {
					f:static_text {
						title = "Python:",
						alignment = 'right',
						width = share 'vtk_label_w',
					},
					f:edit_field {
						value = bind "vtkPythonPath",
						fill_horizontal = 1,
						tooltip = "Full path to python.exe (leave blank for auto-detect).",
						placeholder_string = "(auto-detect)",
					},
					dlButton(DL_PYTHON, "Download Python from python.org"),
				},

				f:row {
					f:static_text {
						title = "FFmpeg:",
						alignment = 'right',
						width = share 'vtk_label_w',
					},
					f:edit_field {
						value = bind "vtkFFmpegPath",
						fill_horizontal = 1,
						tooltip = "Full path to ffmpeg.exe (leave blank for auto-detect).",
						placeholder_string = "(auto-detect)",
					},
					dlButton(DL_FFMPEG, "Download FFmpeg from ffmpeg.org (includes ffprobe)"),
				},

				f:row {
					f:static_text {
						title = "FFprobe:",
						alignment = 'right',
						width = share 'vtk_label_w',
					},
					f:edit_field {
						value = bind "vtkFFprobePath",
						fill_horizontal = 1,
						tooltip = "Full path to ffprobe.exe (leave blank for auto-detect). Included in the FFmpeg package.",
						placeholder_string = "(auto-detect)",
					},
					dlButton(DL_FFMPEG, "Download FFmpeg from ffmpeg.org (includes ffprobe)"),
				},

				f:row {
					f:static_text {
						title = "ExifTool:",
						alignment = 'right',
						width = share 'vtk_label_w',
					},
					f:edit_field {
						value = bind "vtkExifToolPath",
						fill_horizontal = 1,
						tooltip = "Full path to exiftool.exe (leave blank for auto-detect, optional).",
						placeholder_string = "(auto-detect, optional)",
					},
					dlButton(DL_EXIFTOOL, "Download ExifTool from exiftool.org"),
				},

				f:row {
					f:static_text {
						title = "Presets file:",
						alignment = 'right',
						width = share 'vtk_label_w',
					},
					f:edit_field {
						value = bind "vtkPresetsFile",
						fill_horizontal = 1,
						tooltip = "Path to a custom presets.json file (leave blank for built-in presets).",
						placeholder_string = "(built-in presets)",
					},
				},

				f:spacer { height = 2 },
			},
		},
	}
end

return vtk_ui
