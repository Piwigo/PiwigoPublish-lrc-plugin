--[[
    vtk_core.lua — Video Toolkit core orchestration

    Extracted from PublishTask.lua. Contains all VTK logic:
      - preScan        : detect videos in batch before rendering
      - checkServerSupport : verify Piwigo server is ready for video
      - runBatch       : launch VTK Python process, parse results
      - uploadVariants : upload VTK-produced variants to Piwigo
      - updateMetadataOnly : update metadata for already-published videos

    All globals (log, JSON, utils, PiwigoAPI, LrTasks, LrFileUtils,
    LrPathUtils, LrDialogs, LrFunctionContext) are provided by Init.lua.

    Copyright (C) 2024 Fiona Boston <fiona@fbphotography.uk>.
    This file is part of PiwigoPublish (GPLv3).
]]

---@diagnostic disable: undefined-global

local vtk_core = {}

-- ---------------------------------------------------------------------------
-- vtk_core.preScan
-- Scan the export session for video files BEFORE rendering starts.
-- Returns videoPhotos table and batchVideoCount.
--
-- videoPhotos[i] = {
--   photo, existingImageId, appliedPreset, republishMode
-- }
-- republishMode : "new" | "re_upload"
-- ---------------------------------------------------------------------------
function vtk_core.preScan(exportSession, propertyTable, collectionSettings)
    local batchVideoCount = 0
    local videoPhotos = {}

    for photo in exportSession:photosToExport() do
        local fmt = photo:getRawMetadata("fileFormat")
        if fmt == "VIDEO" then
            batchVideoCount = batchVideoCount + 1
            local existingImageId = nil
            local appliedPreset   = nil
            local republishMode   = "new"

            local storedHost = photo:getPropertyForPlugin(_PLUGIN, "pwHostURL")
            local storedUrl  = photo:getPropertyForPlugin(_PLUGIN, "pwImageURL")
            if storedHost == propertyTable.host and storedUrl then
                existingImageId = utils.extractPwImageIdFromUrl(storedUrl, propertyTable.host)
            end
            if existingImageId then
                local checkStatus = PiwigoAPI.checkPhoto(propertyTable, existingImageId)
                if not checkStatus.status then
                    log:info("vtk_core.preScan - video image_id=" .. existingImageId .. " no longer exists on Piwigo, treating as new")
                    existingImageId = nil
                    republishMode = "new"
                else
                    appliedPreset = photo:getPropertyForPlugin(_PLUGIN, "pwVideoPreset") or ""
                    local currentPreset = (collectionSettings.vtkPresetOverride and collectionSettings.vtkPresetOverride ~= "")
                        and collectionSettings.vtkPresetOverride
                        or ((propertyTable.vtkDefaultPreset and propertyTable.vtkDefaultPreset ~= "")
                            and propertyTable.vtkDefaultPreset or "medium")
                    if appliedPreset == "" then
                        republishMode = "re_upload"
                    elseif appliedPreset ~= currentPreset then
                        republishMode = "re_upload"
                    else
                        -- Same preset — still re_upload (VTK cache decides whether to re-encode)
                        republishMode = "re_upload"
                    end
                end
            end

            table.insert(videoPhotos, {
                photo           = photo,
                existingImageId = existingImageId,
                appliedPreset   = appliedPreset,
                republishMode   = republishMode,
            })
        end
    end

    return videoPhotos, batchVideoCount
end

-- ---------------------------------------------------------------------------
-- vtk_core.checkServerSupport
-- Check Piwigo server video capabilities.
-- Also removes blocked videos from the export session.
-- Returns: videoUploadBlocked, serverMaxBytes, companionAvailable
--
-- NOTE: exportSession, batchVideoCount, batchTotalCount, videoPhotos,
--       publishService, and PWStatusManager are needed for side-effects
--       (removePhoto, return-early dialogs). They are passed explicitly.
-- ---------------------------------------------------------------------------
function vtk_core.checkServerSupport(propertyTable, videoPhotos, batchVideoCount, batchTotalCount,
                                      exportSession, publishService)
    local videoUploadBlocked = false
    local serverMaxBytes     = nil
    local companionAvailable = false

    -- Check if user disabled video inclusion
    if propertyTable.vtkIncludeVideo == false then
        log:info("vtk_core.checkServerSupport - video inclusion disabled by user")
        videoUploadBlocked = true
        for _, vEntry in ipairs(videoPhotos) do
            local vName = vEntry.photo:getFormattedMetadata("fileName") or "unknown"
            log:info("vtk_core.checkServerSupport - removing video (disabled): " .. vName)
            exportSession:removePhoto(vEntry.photo)
        end
        if batchVideoCount >= batchTotalCount then
            log:info("vtk_core.checkServerSupport - batch contained only videos, all disabled")
            LrDialogs.message("Video Publishing Disabled",
                "Video inclusion is disabled in this publish service settings.\n\n"
                .. "Enable 'Include video files' in the Video section to publish videos.\n\n"
                .. "No photos to publish in this batch.",
                "info")
            PWStatusManager.setPiwigoBusy(publishService, false)
            PWStatusManager.setRenderPhotos(publishService, false)
            return videoUploadBlocked, serverMaxBytes, companionAvailable, true  -- true = abort
        end
        return videoUploadBlocked, serverMaxBytes, companionAvailable, false
    end

    -- Check server video support
    local warnings = {}
    local videoSupport = PiwigoAPI.getServerVideoSupport(propertyTable)

    if not videoSupport.status then
        videoUploadBlocked = true
        table.insert(warnings, "- Cannot verify server video support (connection issue).")
    elseif not videoSupport.companionAvailable then
        companionAvailable = false
        videoUploadBlocked = true
        table.insert(warnings, "- The 'Lightroom Companion' plugin is not installed on your Piwigo server.")
        table.insert(warnings, "  Without it, video upload cannot be authorized.")
        table.insert(warnings, "\nInstall and activate the 'Lightroom Companion' plugin in Piwigo,")
        table.insert(warnings, "then use 'Server Info' > 'Enable Video Support' to configure the server.")
    else
        companionAvailable = true
        local cfg = videoSupport.serverConfig
        if cfg and cfg.piwigo then
            if cfg.piwigo.video_ready then
                log:info("vtk_core.checkServerSupport - server video_ready = true")
                if cfg.php and cfg.php.upload_max_filesize then
                    serverMaxBytes = utils.parsePhpSize(cfg.php.upload_max_filesize)
                    local postMax = utils.parsePhpSize(cfg.php.post_max_size or "0")
                    if postMax and postMax > 0 and (not serverMaxBytes or postMax < serverMaxBytes) then
                        serverMaxBytes = postMax
                    end
                    if serverMaxBytes then
                        log:info("vtk_core.checkServerSupport - server max upload = " .. serverMaxBytes .. " bytes")
                    end
                end
            else
                videoUploadBlocked = true
                if not cfg.piwigo.upload_form_all_types then
                    table.insert(warnings, "- Server does NOT accept all file types (upload_form_all_types = false)")
                end
                local vExts = cfg.piwigo.video_ext_configured or {}
                if type(vExts) ~= "table" or #vExts == 0 then
                    table.insert(warnings, "- No video extensions configured on the server.")
                end
                table.insert(warnings, "\nUse 'Server Info' > 'Enable Video Support' to fix this automatically.")
            end

            if not videoSupport.videoJsInstalled then
                table.insert(warnings, "- VideoJS plugin is NOT installed (videos won't play in gallery)")
            elseif not videoSupport.videoJsActive then
                table.insert(warnings, "- VideoJS plugin is installed but INACTIVE")
            end

            if cfg.ffmpeg and not cfg.ffmpeg.installed then
                log:info("vtk_core.checkServerSupport - FFmpeg not installed (non-blocking)")
            end
        else
            videoUploadBlocked = true
            table.insert(warnings, "- Companion plugin responded but returned no configuration data.")
        end
    end

    if videoUploadBlocked then
        for _, vEntry in ipairs(videoPhotos) do
            local vName = vEntry.photo:getFormattedMetadata("fileName") or "unknown"
            log:info("vtk_core.checkServerSupport - removing blocked video: " .. vName)
            exportSession:removePhoto(vEntry.photo)
        end
        if batchVideoCount >= batchTotalCount then
            local reason = (#warnings > 0)
                and ("Video upload is not authorized:\n\n" .. table.concat(warnings, "\n") .. "\n\nNo photos to publish in this batch.")
                or "Video inclusion is disabled in this publish service settings.\n\nNo photos to publish in this batch."
            log:info("vtk_core.checkServerSupport - batch contained only videos, all blocked")
            LrDialogs.message("Video Upload Blocked", reason, "critical")
            PWStatusManager.setPiwigoBusy(publishService, false)
            PWStatusManager.setRenderPhotos(publishService, false)
            return videoUploadBlocked, serverMaxBytes, companionAvailable, true  -- abort
        else
            local reason = (#warnings > 0)
                and ("Video upload is not authorized:\n\n" .. table.concat(warnings, "\n") .. "\n\n" .. batchVideoCount .. " video(s) skipped.\nPhotos will still be published.")
                or ("Video inclusion is disabled.\n\n" .. batchVideoCount .. " video(s) skipped.\nPhotos will still be published.")
            LrDialogs.message("Video Upload Blocked", reason, "critical")
        end
    else
        -- Per-file size check (only when VTK is disabled)
        if serverMaxBytes and not propertyTable.vtkEnabled then
            local oversizedVideos = {}
            for idx = #videoPhotos, 1, -1 do
                local vEntry = videoPhotos[idx]
                local vPhoto = vEntry.photo
                if vEntry.republishMode ~= "metadata_only" then
                    local vName = vPhoto:getFormattedMetadata("fileName") or "unknown"
                    local filePath = vPhoto:getRawMetadata("path")
                    if filePath then
                        local attrs = LrFileUtils.fileAttributes(filePath)
                        if attrs and attrs.fileSize and attrs.fileSize > serverMaxBytes then
                            local sizeMB = string.format("%.1f", attrs.fileSize / (1024*1024))
                            local limitMB = string.format("%.1f", serverMaxBytes / (1024*1024))
                            log:info("vtk_core.checkServerSupport - removing oversized video: " .. vName
                                .. " (" .. sizeMB .. " MB > " .. limitMB .. " MB)")
                            table.remove(videoPhotos, idx)
                            table.insert(oversizedVideos, vName .. " (" .. sizeMB .. " MB)")
                        end
                    end
                end
            end
            if #oversizedVideos > 0 then
                local limitMB = string.format("%.1f", serverMaxBytes / (1024*1024))
                LrDialogs.message("Video Too Large",
                    "The following video(s) exceed the server upload limit (" .. limitMB .. " MB):\n\n"
                    .. "- " .. table.concat(oversizedVideos, "\n- ")
                    .. "\n\nThese videos will be skipped. Other files will still be published.",
                    "warning")
            end
        end

        if #warnings > 0 then
            local warningText = table.concat(warnings, "\n")
            LrDialogs.message("Video Support Warning",
                "Issues detected on your Piwigo server:\n\n" .. warningText ..
                "\n\nVideo upload will proceed.",
                "warning")
        end
    end

    return videoUploadBlocked, serverMaxBytes, companionAvailable, false
end

-- ---------------------------------------------------------------------------
-- vtk_core.runBatch
-- Launch VTK Python process in batch mode and parse results.
-- Returns: vtkResults, metadataOnlyVideos
-- ---------------------------------------------------------------------------
function vtk_core.runBatch(videoPhotos, batchVideoCount, propertyTable, collectionSettings, progressScope)
    local vtkResults         = {}
    local metadataOnlyVideos = {}

    if batchVideoCount == 0 or not propertyTable.vtkEnabled then
        return vtkResults, metadataOnlyVideos
    end

    log:info("vtk_core.runBatch - processing " .. batchVideoCount .. " video(s)")

    -- Remove ALL videos from export session to prevent LrC "This file is a video" dialog
    for _, vEntry in ipairs(videoPhotos) do
        -- (already removed by checkServerSupport if blocked; safe to call again)
    end

    local python = utils.resolveTool(propertyTable.vtkPythonPath, "python")
    log:info("vtk_core.runBatch - python resolved to: " .. python)
    local toolkitScript = utils.resolveToolkitPath(propertyTable.vtkToolkitPath, _PLUGIN.path)
    log:info("vtk_core.runBatch - toolkitScript resolved to: " .. toolkitScript)

    local preset = (collectionSettings.vtkPresetOverride and collectionSettings.vtkPresetOverride ~= "")
        and collectionSettings.vtkPresetOverride
        or ((propertyTable.vtkDefaultPreset and propertyTable.vtkDefaultPreset ~= "")
            and propertyTable.vtkDefaultPreset or "medium")
    log:info("vtk_core.runBatch - video preset effective: " .. preset
        .. (collectionSettings.vtkPresetOverride ~= "" and " (collection override)" or " (service default)"))

    local statusFilePath = LrPathUtils.child(
        LrPathUtils.getStandardFilePath("temp"),
        "piwigoPublish_vtk_status.json"
    )
    local batchFilePath = LrPathUtils.child(
        LrPathUtils.getStandardFilePath("temp"),
        "piwigoPublish_vtk_batch.json"
    )

    local batchVideos = {}
    for _, vEntry in ipairs(videoPhotos) do
        local filePath = vEntry.photo:getRawMetadata("path")
        if filePath then
            if vEntry.republishMode == "metadata_only" then
                table.insert(metadataOnlyVideos, vEntry)
            else
                table.insert(batchVideos, {
                    input  = filePath,
                    preset = preset,
                    force  = (vEntry.republishMode == "re_upload"),
                })
            end
        end
    end

    if #batchVideos == 0 then
        log:info("vtk_core.runBatch - all videos are metadata-only, skipping Video Toolkit")
        return vtkResults, metadataOnlyVideos
    end

    local batchData = {
        videos      = batchVideos,
        status_file = statusFilePath,
    }
    local batchFile = io.open(batchFilePath, "w")
    if batchFile then
        batchFile:write(JSON:encode(batchData))
        batchFile:close()
    end

    local ffmpegArg   = (propertyTable.vtkFFmpegPath  and propertyTable.vtkFFmpegPath  ~= "")
        and (' --ffmpeg-path "'  .. propertyTable.vtkFFmpegPath  .. '"') or ""
    local exiftoolArg = (propertyTable.vtkExifToolPath and propertyTable.vtkExifToolPath ~= "")
        and (' --exiftool-path "' .. propertyTable.vtkExifToolPath .. '"') or ""
    local presetsArg  = (propertyTable.vtkPresetsFile and propertyTable.vtkPresetsFile ~= "")
        and (' --config "' .. propertyTable.vtkPresetsFile .. '"') or ""
    local hwaccelArg  = (propertyTable.vtkHardwareAccel and propertyTable.vtkHardwareAccel ~= ""
        and propertyTable.vtkHardwareAccel ~= "auto")
        and (' --hwaccel "' .. propertyTable.vtkHardwareAccel .. '"') or ""

    local vtkResultPath = utils.getVtkResultPath()
    local cmd = '"' .. python .. '" "' .. toolkitScript .. '"'
        .. ' --mode batch'
        .. ' --batch-file "' .. batchFilePath .. '"'
        .. ' --status-file "' .. statusFilePath .. '"'
        .. ' --log-file "' .. vtkResultPath .. '"'
        .. ffmpegArg .. exiftoolArg .. presetsArg .. hwaccelArg

    -- Delete old result file to avoid reading stale results if VTK crashes
    if LrFileUtils.exists(vtkResultPath) then
        LrFileUtils.delete(vtkResultPath)
    end

    -- Write .bat wrapper to work around nested-quotes bug with LrTasks.execute on Windows
    local batPath = LrPathUtils.child(LrPathUtils.getStandardFilePath("temp"), "piwigoPublish_vtk_run.bat")
    local batFh = io.open(batPath, "w")
    if batFh then
        batFh:write("@echo off\r\n")
        batFh:write(cmd .. "\r\n")
        batFh:close()
    end

    log:info("vtk_core.runBatch - VTK command: " .. cmd)
    log:info("vtk_core.runBatch - VTK bat file: " .. batPath)
    log:info("vtk_core.runBatch - VTK result file: " .. vtkResultPath)
    local bfDiag = io.open(batchFilePath, "r")
    if bfDiag then
        log:info("vtk_core.runBatch - VTK batch content: " .. (bfDiag:read("*all") or ""))
        bfDiag:close()
    end

    progressScope:setCaption("Video Toolkit — Processing " .. batchVideoCount .. " video(s)...")

    LrDialogs.message(
        "Video Toolkit — Processing",
        "Video Toolkit is about to process " .. batchVideoCount .. " video(s).\n\n"
        .. "HDR videos will be transcoded to SDR — this can take several minutes per video.\n\n"
        .. "Lightroom will appear frozen during processing. Please wait.",
        "info")

    local vtkExitCode = LrTasks.execute('"' .. batPath .. '"')
    log:info("vtk_core.runBatch - LrTasks.execute returned: " .. tostring(vtkExitCode) .. " (type=" .. type(vtkExitCode) .. ")")

    if not LrFileUtils.exists(vtkResultPath) then
        log:info("vtk_core.runBatch - waiting for VTK result file...")
        for _ = 1, 20 do
            LrTasks.sleep(0.5)
            if LrFileUtils.exists(vtkResultPath) then break end
        end
    end

    if vtkExitCode ~= 0 and vtkExitCode ~= nil then
        log:warn("vtk_core.runBatch - VTK exit code: " .. tostring(vtkExitCode) .. " — checking result file for actual status")
    end

    local vtkOutput = nil
    local lf = io.open(vtkResultPath, "r")
    if lf then
        local raw = lf:read("*all") or ""
        lf:close()
        -- Forward VTK result into the plugin log for unified diagnostics
        log:info("vtk_core.runBatch - VTK result: " .. raw)
        local ok, parsed = pcall(function() return JSON:decode(raw) end)
        if ok and parsed then
            vtkOutput = parsed
        else
            log:warn("vtk_core.runBatch - VTK result parse failed: " .. raw:sub(1, 500))
        end
    else
        log:warn("vtk_core.runBatch - VTK result file not found: " .. vtkResultPath)
    end

    if vtkOutput and vtkOutput.status == "ok" and vtkOutput.results then
        local resultsByPath = {}
        for _, r in ipairs(vtkOutput.results) do
            if r.input then resultsByPath[r.input] = r end
        end
        for _, vEntry in ipairs(videoPhotos) do
            if vEntry.republishMode ~= "metadata_only" then
                local filePath = vEntry.photo:getRawMetadata("path")
                local r = filePath and resultsByPath[filePath]
                if r then
                    table.insert(vtkResults, {
                        photo           = vEntry.photo,
                        existingImageId = vEntry.existingImageId,
                        republishMode   = vEntry.republishMode,
                        variantPath     = r.variant   or "",
                        thumbnailPath   = r.thumbnail or "",
                        videoWidth      = r.width     or 0,
                        videoHeight     = r.height    or 0,
                        videoDuration   = r.duration  or 0,
                        videoSize       = r.size      or 0,
                        origData        = r.orig      or nil,
                        convData        = r.conv      or nil,
                        status          = r.status    or "error",
                        error           = r.error     or "",
                    })
                else
                    table.insert(vtkResults, {
                        photo           = vEntry.photo,
                        existingImageId = vEntry.existingImageId,
                        republishMode   = vEntry.republishMode,
                        status          = "error",
                        error           = "No result from Video Toolkit for " .. (filePath or "?"),
                    })
                end
            end
        end
    else
        local reason = (vtkOutput and vtkOutput.status) or "no output"
        log:warn("vtk_core.runBatch - VTK failed: " .. reason)
        LrDialogs.message("Video Toolkit Error",
            "Video Toolkit failed.\n\nCheck the plugin log for details.\n\nVideos will be skipped.",
            "critical")
    end

    progressScope:setCaption("Publishing to Piwigo...")
    progressScope:setPortionComplete(0, 100)

    return vtkResults, metadataOnlyVideos
end

-- ---------------------------------------------------------------------------
-- vtk_core.uploadVariants
-- Upload VTK-produced video variants to Piwigo and mark them Published in LrC.
-- ---------------------------------------------------------------------------
function vtk_core.uploadVariants(vtkResults, propertyTable, collectionSettings,
                                  albumId, albumName, albumUrl,
                                  catalog, publishedCollection,
                                  companionAvailable, serverMaxBytes, progressScope)
    if #vtkResults == 0 then return end

    log:info("vtk_core.uploadVariants - uploading " .. #vtkResults .. " video variant(s)")
    progressScope:setCaption("Uploading video variants...")

    local preset = (collectionSettings.vtkPresetOverride and collectionSettings.vtkPresetOverride ~= "")
        and collectionSettings.vtkPresetOverride
        or ((propertyTable.vtkDefaultPreset and propertyTable.vtkDefaultPreset ~= "")
            and propertyTable.vtkDefaultPreset or "medium")

    local vtkFailedVideos = {}

    for idx, vr in ipairs(vtkResults) do
        local vPhoto = vr.photo
        local vName  = vPhoto:getFormattedMetadata("fileName") or "unknown"

        if vr.status ~= "ok" or vr.variantPath == "" then
            local errMsg = vr.error or "Unknown toolkit error"
            log:warn("vtk_core.uploadVariants - skipping (toolkit error): " .. vName .. " — " .. errMsg)
            table.insert(vtkFailedVideos, "• " .. vName .. "\n  " .. errMsg)
        else
            log:info("vtk_core.uploadVariants - uploading variant: " .. vr.variantPath)
            progressScope:setCaption("Uploading video: " .. vName)
            progressScope:setPortionComplete(idx - 1, #vtkResults)

            local metaData = utils.getPhotoMetadata(propertyTable, vPhoto)
            metaData.Albumid  = albumId
            metaData.Remoteid = vr.existingImageId or ""

            local uploadStatus
            local variantAttrs = LrFileUtils.fileAttributes(vr.variantPath)
            local variantSize  = variantAttrs and variantAttrs.fileSize or 0
            local useChunked   = serverMaxBytes and (variantSize > serverMaxBytes)

            if useChunked then
                log:info(string.format(
                    "vtk_core.uploadVariants - %s (%d bytes) > server limit (%d) → chunked upload",
                    vName, variantSize, serverMaxBytes))
                progressScope:setCaption("Uploading (chunked): " .. vName)
                uploadStatus = PiwigoAPI.uploadVideoChunked(propertyTable, vr.variantPath, metaData)
            else
                log:info("vtk_core.uploadVariants - " .. vName .. " → addSimple upload")
                uploadStatus = PiwigoAPI.updateGallery(propertyTable, vr.variantPath, metaData)
            end

            if uploadStatus.status then
                local imageId = uploadStatus.remoteid or ""
                log:info("vtk_core.uploadVariants - uploaded, image_id=" .. imageId)

                -- Upload poster
                if vr.thumbnailPath and vr.thumbnailPath ~= ""
                        and LrFileUtils.exists(vr.thumbnailPath) then
                    if companionAvailable then
                        log:info("vtk_core.uploadVariants - uploading poster: " .. vr.thumbnailPath)
                        progressScope:setCaption("Uploading poster: " .. vName)
                        local posterStatus = PiwigoAPI.setRepresentative(
                            propertyTable, imageId, vr.thumbnailPath)
                        if posterStatus.status then
                            log:info("vtk_core.uploadVariants - poster set for image_id=" .. imageId)
                        else
                            log:warn("vtk_core.uploadVariants - poster upload failed: "
                                .. (posterStatus.statusMsg or ""))
                        end
                    end
                end

                -- Set video dimensions via Companion
                if companionAvailable and vr.videoWidth > 0 and vr.videoHeight > 0 then
                    log:info("vtk_core.uploadVariants - setting video info: "
                        .. vr.videoWidth .. "x" .. vr.videoHeight
                        .. " size=" .. vr.videoSize)
                    PiwigoAPI.setVideoInfo(
                        propertyTable, imageId,
                        vr.videoWidth, vr.videoHeight, vr.videoSize)
                end

                -- Extended video metadata (codec, fps, bitrate, format)
                if companionAvailable and vr.origData then
                    PiwigoAPI.setVideoMeta(
                        propertyTable, imageId,
                        vr.origData, vr.convData)
                end

                -- Update Piwigo metadata
                metaData.Remoteid = imageId
                PiwigoAPI.updateMetadata(propertyTable, vPhoto, metaData)

                vr.uploadedImageId   = imageId
                vr.uploadedRemoteUrl = uploadStatus.remoteurl or ""

                -- Store plugin-side metadata
                local pluginData = {
                    pwHostURL     = propertyTable.host,
                    albumName     = albumName,
                    albumUrl      = albumUrl,
                    imageUrl      = uploadStatus.remoteurl or "",
                    pwUploadDate  = os.date("%Y-%m-%d"),
                    pwUploadTime  = os.date("%H:%M:%S"),
                    pwCommentSync = "",
                    pwVideoPreset = preset,
                }
                PiwigoAPI.storeMetaData(catalog, vPhoto, pluginData)

                -- Cleanup VTK temp files (variant + poster) after successful upload.
                -- Never delete the variant if it IS the source file (preset=origin, same path).
                local sourcePath = vPhoto:getRawMetadata("path") or ""
                if vr.variantPath ~= "" and vr.variantPath ~= sourcePath
                        and LrFileUtils.exists(vr.variantPath) then
                    LrFileUtils.delete(vr.variantPath)
                    log:info("vtk_core.uploadVariants - deleted temp variant: " .. vr.variantPath)
                end
                if vr.thumbnailPath ~= "" and LrFileUtils.exists(vr.thumbnailPath) then
                    LrFileUtils.delete(vr.thumbnailPath)
                    log:info("vtk_core.uploadVariants - deleted temp poster: " .. vr.thumbnailPath)
                end

                -- Mark video as Published in LrC
                catalog:withWriteAccessDo("Mark video published", function()
                    publishedCollection:addPhotoByRemoteId(
                        vPhoto, tostring(imageId),
                        uploadStatus.remoteurl or "", true)
                    log:info("vtk_core.uploadVariants - marked published: " .. vName .. " (image_id=" .. imageId .. ")")
                end, { timeout = 5 })
            else
                log:warn("vtk_core.uploadVariants - upload failed: " .. vName
                    .. " — " .. (uploadStatus.statusMsg or ""))
                table.insert(vtkFailedVideos, "• " .. vName .. "\n  " .. (uploadStatus.statusMsg or ""))
            end
        end
    end

    if #vtkFailedVideos > 0 then
        LrDialogs.message("Video Toolkit — Processing Errors",
            #vtkFailedVideos .. " video(s) could not be processed by the Video Toolkit "
            .. "and were skipped:\n\n"
            .. table.concat(vtkFailedVideos, "\n\n")
            .. "\n\nCheck the Video Toolkit log for details.",
            "warning")
    end
end

-- ---------------------------------------------------------------------------
-- vtk_core.updateMetadataOnly
-- Update metadata on Piwigo for videos that are already published (same preset).
-- ---------------------------------------------------------------------------
function vtk_core.updateMetadataOnly(metadataOnlyVideos, propertyTable, albumId,
                                      catalog, publishedCollection,
                                      companionAvailable, progressScope)
    if #metadataOnlyVideos == 0 then return end

    log:info("vtk_core.updateMetadataOnly - updating metadata for " .. #metadataOnlyVideos .. " video(s)")
    progressScope:setCaption("Updating video metadata...")

    for _, vEntry in ipairs(metadataOnlyVideos) do
        local vPhoto  = vEntry.photo
        local imageId = vEntry.existingImageId or ""
        local vName   = vPhoto:getFormattedMetadata("fileName") or "unknown"

        if imageId ~= "" then
            log:info("vtk_core.updateMetadataOnly - image_id=" .. imageId .. " (" .. vName .. ")")
            local metaData = utils.getPhotoMetadata(propertyTable, vPhoto)
            metaData.Albumid  = albumId
            metaData.Remoteid = imageId
            PiwigoAPI.updateMetadata(propertyTable, vPhoto, metaData)
            log:info("vtk_core.updateMetadataOnly - metadata updated for image_id=" .. imageId)

            -- setVideoInfo from .vtk cache file
            if companionAvailable then
                local srcPath = vPhoto:getRawMetadata("path") or ""
                local preset  = vEntry.appliedPreset or ""
                if srcPath ~= "" and preset ~= "" then
                    local stem    = LrPathUtils.removeExtension(LrPathUtils.leafName(srcPath))
                    local vtkFile = LrPathUtils.child(LrPathUtils.parent(srcPath), ".vtk")
                    vtkFile       = LrPathUtils.child(vtkFile, stem .. ".json")
                    local fh = io.open(vtkFile, "r")
                    if fh then
                        local raw = fh:read("*all"); fh:close()
                        local ok, vtk = pcall(function() return JSON:decode(raw) end)
                        if ok and vtk and vtk.variants and vtk.variants[preset] then
                            local v  = vtk.variants[preset]
                            local vw = v.width  or 0
                            local vh = v.height or 0
                            local vs = v.size   or 0
                            if (vw == 0 or vh == 0) and v.resolution then
                                vw, vh = v.resolution:match("^(%d+)x(%d+)$")
                                vw = tonumber(vw) or 0
                                vh = tonumber(vh) or 0
                            end
                            if vw > 0 and vh > 0 then
                                log:info("vtk_core.updateMetadataOnly - setVideoInfo image_id="
                                    .. imageId .. " " .. vw .. "x" .. vh .. " size=" .. vs)
                                PiwigoAPI.setVideoInfo(propertyTable, imageId, vw, vh, vs)
                            end
                        else
                            log:info("vtk_core.updateMetadataOnly - no .vtk variant data for preset=" .. preset .. " (" .. vName .. ")")
                        end
                    else
                        log:info("vtk_core.updateMetadataOnly - .vtk file not found for " .. vName)
                    end
                end
            end

            -- Mark video as Published in LrC
            catalog:withWriteAccessDo("Mark video published", function()
                local publishedPhotos = publishedCollection:getPublishedPhotos()
                for _, pubPhoto in ipairs(publishedPhotos) do
                    if pubPhoto:getPhoto().localIdentifier == vPhoto.localIdentifier then
                        pubPhoto:setRemoteId(tostring(imageId))
                        pubPhoto:setRemoteUrl("")
                        pubPhoto:setEditedFlag(false)
                        log:info("vtk_core.updateMetadataOnly - marked published: " .. vName)
                        break
                    end
                end
            end, { timeout = 5 })
        else
            log:warn("vtk_core.updateMetadataOnly - no image_id for " .. vName .. ", skipping")
        end
    end
end

return vtk_core
