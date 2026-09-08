--[[

    pwAPI.lua

    lua functions to accss the Piwigo Web API
    see https://github.com/Piwigo/Piwigo/wiki/Piwigo-Web-API

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

local pwAPI = {}

-- ==========================================================
-- C O N S T A N T S
-- ==========================================================

local MOD = "pwAPI"
local API_BASE_PATH = ''
local HTTP_TIMEOUT_DEFAULT = 5
local HTTP_TIMEOUT_UPLOAD = 15
local DEVICE_ID_STRING = 'Piwigo Publish API Functions'

local SUCCESS_STATUS_GET = 200
local SUCCESS_STATUS_POST = { [200] = true, [201] = true }
local SUCCESS_STATUS_CUSTOM = { [200] = true, [201] = true, [204] = true }

-- ==========================================================
-- L O C A L   F U N C T I O N S
-- ==========================================================

-- - - - - - - - - - - - - - - - - - - - - - - -
local function _utc_iso_now()
    return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

-- - - - - - - - - - - - - - - - - - - - - - - -
local function _random_boundary()
    return "PiwigoUpload" .. tostring(math.random(100000, 999999))
end

-- - - - - - - - - - - - - - - - - - - - - - - -
local function _build_multipart_body(boundary, file_path, fields, contentType)
    -- Build a multipart/form-data body for image upload requests.
    local upload_path = tostring(file_path or ""):match("^%s*(.-)%s*$")
    if upload_path == "" then
        return nil, "No file path provided for upload"
    end

    local fh = io.open(upload_path, "rb")
    if not fh then
        return nil, "Unable to open file for upload: " .. tostring(upload_path)
    end

    local file_bytes = fh:read("*all")
    fh:close()
    if not file_bytes then
        return nil, "Unable to read file for upload: " .. tostring(upload_path)
    end

    local file_name = string.match(upload_path, "[^/\\]+$") or "upload.bin"
    local parts = {}
    for _, item in ipairs(fields or {}) do
        parts[#parts + 1] = "--" .. boundary .. "\r\n"
        parts[#parts + 1] = "Content-Disposition: form-data; name=\"" .. tostring(item.name or "") .. "\"\r\n\r\n"
        parts[#parts + 1] = tostring(item.value or "") .. "\r\n"
    end
    parts[#parts + 1] = "--" .. boundary .. "\r\n"
    parts[#parts + 1] = "Content-Disposition: form-data; name=\"image\"; filename=\"" .. file_name .. "\"\r\n"
    parts[#parts + 1] = "Content-Type: " .. (contentType or "application/octet-stream") .. "\r\n\r\n"
    parts[#parts + 1] = file_bytes
    parts[#parts + 1] = "\r\n--" .. boundary .. "--\r\n"

    return table.concat(parts), nil
end

-- - - - - - - - - - - - - - - - - - - - - - - -

local function _http_request(method, url, headers, body, timeout)
    -- Internal HTTP request helper
    -- @param method string: HTTP method (GET, POST, etc)
    -- @param url string: full URL
    -- @param headers table: HTTP headers
    -- @param body string|nil: request body (for POST/PUT)
    -- @param timeout number|nil: timeout in seconds
    -- @return status (number), response body (string), error (string|nil)
    local response = {}
    local req = {
        url = url,
        method = method,
        headers = headers or {},
        sink = ltn12.sink.table(response),
    }
    if body then
        req.source = ltn12.source.string(body)
        req.headers["content-length"] = tostring(#body)
    end
    if timeout then
        http.TIMEOUT = timeout
    end
    local _, status, resp_headers, status_line = http.request(req)
    local resp_body = table.concat(response)
    return status, resp_body, status_line
end

-- - - - - - - - - - - - - - - - - - - - - - - -
local function doGetRequest(host, apikey, apiPath)
    -- helper for GET requests with error handling and JSON decoding
    host = tostring(host or ""):match("^%s*(.-)%s*$")
    apikey = tostring(apikey or ""):match("^%s*(.-)%s*$")
    if not host or host == "" then
        return nil, "No host URL provided"
    end
    if not apikey or apikey == "" then
        return nil, "No API key provided"
    end

    local path = tostring(apiPath or "")
    local request_url = nil
    if path:match("^https?://") then
        request_url = path
    elseif path:match("^/ws%.php") then
        request_url = host .. path
    else
        request_url = host .. API_BASE_PATH .. path
    end
    local headers = {
        ["X-PIWIGO-API"] = apikey,
        ["Accept"] = "application/json",
    }

    local status, body, status_line = _http_request("GET", request_url, headers, nil, HTTP_TIMEOUT_DEFAULT)
    if status ~= SUCCESS_STATUS_GET then
        log:info("PiwigoPublish - pwAPI.lua - doGetRequest - HTTP status " ..  tostring(status or "?") .. ": " .. (body or status_line or ""))
        log:info("PiwigoPublish - pwAPI.lua - doGetRequest - request_url: " .. tostring(request_url or "?") .. ", headers " .. utils.serialiseVar(headers))
        return nil, "HTTP status " .. tostring(status or "?") .. ": " .. (body or status_line or "")
    end

    local ok, decoded = pcall(function() return JSON:decode(body or "[]") end)
    if not ok or type(decoded) ~= "table" then
        return nil, "Failed to decode JSON response"
    end

    return decoded, nil
end

-- - - - - - - - - - - - - - - - - - - - - - - -
local function doWsGetRequest(host, apikey, method_name, params)
    -- helper for Piwigo ws.php GET calls where callers provide method name and optionally a table of parameters
    local method_value = tostring(method_name or ""):match("^%s*(.-)%s*$")
    if method_value == "" then
        return nil, "No Piwigo method provided"
    end
    local path = "/ws.php?format=json&method=" .. method_value

    -- params can be array style: { {name="image_id", value="123"}, ... }
    for _, p in ipairs(params or {}) do
        local name = tostring(p and p.name or ""):match("^%s*(.-)%s*$")
        local value = tostring(p and p.value or ""):match("^%s*(.-)%s*$")
        if name ~= "" then
            path = path .. "&" .. utils.urlEncode(name) .. "=" .. utils.urlEncode(value)
        end
    end

    return doGetRequest(host, apikey, path)
end

-- - - - - - - - - - - - - - - - - - - - - - - -
local function doWsPostRequest(host, apikey, method_name, params, encoding)
    -- Send a ws.php POST request with scalar parameters encoded in the request body.
    host = tostring(host or ""):match("^%s*(.-)%s*$")
    apikey = tostring(apikey or ""):match("^%s*(.-)%s*$")
    local method_value = tostring(method_name or ""):match("^%s*(.-)%s*$")
    if host == "" then
        return nil, "No host URL provided"
    end
    if apikey == "" then
        return nil, "No API key provided"
    end
    if method_value == "" then
        return nil, "No Piwigo method provided"
    end

    local request_url = host .. "/ws.php?format=json"
    local body_parts = {
        "method=" .. utils.urlEncode(method_value),
    }
    for _, p in ipairs(params or {}) do
        local name = tostring(p and p.name or ""):match("^%s*(.-)%s*$")
        local value = tostring(p and p.value or ""):match("^%s*(.-)%s*$")
        if name ~= "" then
            body_parts[#body_parts + 1] = utils.urlEncode(name) .. "=" .. utils.urlEncode(value)
        end
    end
    local body = table.concat(body_parts, "&")

    local headers = {
        ["X-PIWIGO-API"] = apikey,
        ["Accept"] = "application/json",
        ["Content-Type"] = encoding or "application/x-www-form-urlencoded",
    }

    local status, resp_body, status_line = _http_request("POST", request_url, headers, body, HTTP_TIMEOUT_UPLOAD)
    if not SUCCESS_STATUS_POST[status] then
        return nil, "HTTP status " .. tostring(status or "?") .. ": " .. (resp_body or status_line or "")
    end
    if resp_body == nil or resp_body == "" then
        return nil, "Empty response from Piwigo API"
    end

    local ok_dec, parsed_response = pcall(function() return JSON:decode(resp_body) end)
    if not ok_dec then
        return nil, "Failed to decode JSON response"
    end
    if type(parsed_response) ~= "table" then
        return nil, "Invalid JSON response format"
    end
    if parsed_response.stat ~= "ok" then
        return nil, "Piwigo API error: " .. tostring(parsed_response.message or "Unknown error")
    end

    return parsed_response, nil
end

-- - - - - - - - - - - - - - - - - - - - - - - -
local function doWsPostMultipartRequest(host, apikey, method_name, params, file_path, content_type)
    -- Send a ws.php POST request as multipart/form-data with a required file payload.
    host = tostring(host or ""):match("^%s*(.-)%s*$")
    apikey = tostring(apikey or ""):match("^%s*(.-)%s*$")
    local method_value = tostring(method_name or ""):match("^%s*(.-)%s*$")
    local upload_path = tostring(file_path or ""):match("^%s*(.-)%s*$")
    if host == "" then
        return nil, "No host URL provided"
    end
    if apikey == "" then
        return nil, "No API key provided"
    end
    if method_value == "" then
        return nil, "No Piwigo method provided"
    end
    if upload_path == "" then
        return nil, "No file path provided for upload"
    end

    local boundary = _random_boundary()
    local multipart_fields = {
        { name = "method", value = method_value },
    }
    for _, p in ipairs(params or {}) do
        local name = tostring(p and p.name or ""):match("^%s*(.-)%s*$")
        local value = tostring(p and p.value or ""):match("^%s*(.-)%s*$")
        if name ~= "" then
            multipart_fields[#multipart_fields + 1] = { name = name, value = value }
        end
    end

    local body, body_err = _build_multipart_body(boundary, upload_path, multipart_fields, content_type)
    if not body then
        return nil, body_err
    end

    local request_url = host .. "/ws.php?format=json"
    local headers = {
        ["X-PIWIGO-API"] = apikey,
        ["Accept"] = "application/json",
        ["Content-Type"] = "multipart/form-data; boundary=" .. boundary,
    }

    local status, resp_body, status_line = _http_request("POST", request_url, headers, body, HTTP_TIMEOUT_UPLOAD)
    if not SUCCESS_STATUS_POST[status] then
        return nil, "HTTP status " .. tostring(status or "?") .. ": " .. (resp_body or status_line or "")
    end
    if resp_body == nil or resp_body == "" then
        return nil, "Empty response from Piwigo API"
    end

    local ok_dec, parsed_response = pcall(function() return JSON:decode(resp_body) end)
    if not ok_dec then
        return nil, "Failed to decode JSON response"
    end
    if type(parsed_response) ~= "table" then
        return nil, "Invalid JSON response format"
    end
    if parsed_response.stat ~= "ok" then
        return nil, "Piwigo API error: " .. tostring(parsed_response.message or "Unknown error")
    end

    return parsed_response, nil
end

-- - - - - - - - - - - - - - - - - - - - - - - -
local function doRawGetRequest(host, apikey, apiPath, timeout)
    host = tostring(host or ""):match("^%s*(.-)%s*$")
    apikey = tostring(apikey or ""):match("^%s*(.-)%s*$")
    if not host or host == "" then
        return nil, "No host URL provided"
    end
    if not apikey or apikey == "" then
        return nil, "No API key provided"
    end

    local request_url = host .. API_BASE_PATH .. apiPath
    local headers = {
        ["X-PIWIGO-API"] = apikey,
        ["Accept"] = "*/*",
    }

    local status, body, status_line = _http_request("GET", request_url, headers, nil, timeout or HTTP_TIMEOUT_UPLOAD)
    if status ~= SUCCESS_STATUS_GET then
        return nil, "HTTP status " .. tostring(status or "?") .. ": " .. (body or status_line or "")
    end

    return body or "", nil
end

-- - - - - - - - - - - - - - - - - - - - - - - -
local function doRawGetRequestToFile(host, apikey, apiPath, target_path, timeout)
    -- Stream a raw GET response directly to a local file path.
    host = tostring(host or ""):match("^%s*(.-)%s*$")
    apikey = tostring(apikey or ""):match("^%s*(.-)%s*$")
    target_path = tostring(target_path or ""):match("^%s*(.-)%s*$")
    if not host or host == "" then
        return nil, "No host URL provided"
    end
    if not apikey or apikey == "" then
        return nil, "No API key provided"
    end
    if target_path == "" then
        return nil, "No target file path provided"
    end

    local path = tostring(apiPath or "")
    local request_url = nil
    if path:match("^https?://") then
        request_url = path
    else
        request_url = host .. API_BASE_PATH .. path
    end

    local target_file = io.open(target_path, "wb")
    if not target_file then
        return nil, "Unable to open target file for writing: " .. tostring(target_path)
    end

    if timeout then
        http.TIMEOUT = timeout
    end

    local ok, status_or_err, _, status_line = http.request {
        url = request_url,
        method = "GET",
        headers = {
            ["X-PIWIGO-API"] = apikey,
            ["Accept"] = "*/*",
        },
        sink = ltn12.sink.file(target_file),
    }
    target_file:close()

    if not ok then
        os.remove(target_path)
        return nil, "HTTP request failed: " .. tostring(status_or_err or "Unknown error")
    end
    if status_or_err ~= SUCCESS_STATUS_GET then
        os.remove(target_path)
        return nil, "HTTP status " .. tostring(status_or_err or "?") .. ": " .. tostring(status_line or "")
    end

    return target_path, nil
end

-- - - - - - - - - - - - - - - - - - - - - - - -
local function doJsonRequest(host, apikey, method, apiPath, body_table)
    host = tostring(host or ""):match("^%s*(.-)%s*$")
    apikey = tostring(apikey or ""):match("^%s*(.-)%s*$")
    if not host or host == "" then
        return nil, "No host URL provided"
    end
    if not apikey or apikey == "" then
        return nil, "No API key provided"
    end

    local request_url = host .. API_BASE_PATH .. apiPath
    local json_body = "{}"
    local ok, encoded = pcall(function() return JSON:encode(body_table or {}) end)
    if ok and type(encoded) == "string" and encoded ~= "" then
        json_body = encoded
    else
        return nil, "Failed to encode JSON body"
    end

    local headers = {
        ["X-PIWIGO-API"] = apikey,
        ["Accept"] = "application/json",
        ["Content-Type"] = "application/json",
    }

    local status, body, status_line = _http_request(method, request_url, headers, json_body, HTTP_TIMEOUT_DEFAULT)
    if not SUCCESS_STATUS_CUSTOM[status] then
        return nil, "HTTP status " .. tostring(status or "?") .. ": " .. (body or status_line or "")
    end

    if body == nil or body == "" then
        return {}, nil
    end

    local ok_dec, decoded = pcall(function() return JSON:decode(body) end)
    if not ok_dec then
        return nil, "Failed to decode JSON response"
    end

    if type(decoded) ~= "table" then
        return {}, nil
    end

    return decoded, nil
end

-- - - - - - - - - - - - - - - - - - - - - - - -
local function _as_json_array(values)
    -- Force JSON encoding of list values as an array for API dto validation.
    local list = {}
    for _, value in ipairs(values or {}) do
        local item = tostring(value or ""):match("^%s*(.-)%s*$")
        if item ~= "" then
            list[#list + 1] = item
        end
    end
    return JSON:newArray(list)
end

-- ==========================================================
-- G L O B A L   F U N C T I O N S
-- ==========================================================

-- - - - - - - - - - - - - - - - - - - - - - - -
function pwAPI.getVersion(host, apikey)
    -- Test Piwigo API key using ws.php pwg.getVersion endpoint.
    local response, err = doWsGetRequest(host, apikey, "pwg.getVersion")
    if not response then
        return false, err or "Connection test failed"
    end

    if response.stat == "ok" and response.result ~= nil then
        return true, "**OK** Piwigo Version " .. tostring(response.result)
    end

    return false, "**FAIL** " .. tostring(response.message or "Unknown error")
end

-- - - - - - - - - - - - - - - - - - - - - - - -
function pwAPI.session_getStatus(host, apikey)
    -- Test Piwigo API key using ws.php pwg.session.getStatus endpoint.
    local response, err = doWsGetRequest(host, apikey, "pwg.session.getStatus")
    if not response then
        return false, err or "Connection test failed"
    end

    local successful
    if response.stat == "ok" and type(response.result) == "table" then
        return true, response.result
    else
        return false, response.result.message
    end
end

-- - - - - - - - - - - - - - - - - - - - - - - -
function pwAPI.categories_getAdminList(host, apikey, check_album_id)
    -- returns list of albums with hierarchy-aware fields from pwg.categories.getAdminList
    local parsedResponse, err = doWsGetRequest(host, apikey, "pwg.categories.getAdminList")
    if not parsedResponse then
        return nil, err
    end

    if parsedResponse.stat ~= "ok" then
        return nil, tostring(parsedResponse.message or "Failed to load Piwigo albums")
    end

    local result = parsedResponse.result
    local categories = (type(result) == "table" and type(result.categories) == "table") and result.categories or {}

    local albums = {}
    for i = 1, #categories do
        local row = categories[i]
        if row and row.id and (row.name or row.name_raw) then
            if check_album_id and tostring(row.id) ~= tostring(check_album_id) then
                -- skip this album if we're checking for a specific album id
            else
                local album_id = tostring(row.id)
                local album_name = tostring(row.name_raw or row.name or "")
                local uppercats = tostring(row.uppercats or album_id)

                local uppercat_parts = {}
                for token in string.gmatch(uppercats, "[^,]+") do
                    local trimmed = tostring(token):match("^%s*(.-)%s*$")
                    if trimmed ~= "" then
                        uppercat_parts[#uppercat_parts + 1] = trimmed
                    end
                end
                local depth = math.max(0, #uppercat_parts - 1)

                local fullname_raw = tostring(row.fullname or album_name)
                local fullname_compact = fullname_raw:gsub("\r", " "):gsub("\n", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
                local path_key = fullname_compact:gsub("%s*/%s*", "|")

                table.insert(albums, {
                    title = album_name,
                    value = album_id,
                    albumName = path_key,
                    assetId = album_id,

                    id = album_id,
                    name = album_name,
                    fullname = fullname_compact,
                    path_key = path_key,
                    uppercats = uppercats,
                    depth = depth,
                    status = tostring(row.status or "public"),
                    global_rank = tostring(row.global_rank or ""),
                })
            end
        end
    end

    return albums, nil
end

-- - - - - - - - - - - - - - - - - - - - - - - -
function pwAPI.categories_add(host, apikey, album_name, parent_id)
    -- add new album to Piwigo using /albums endpoint
    if type(album_name) ~= "string" or album_name == "" then
        return nil, "No album name provided"
    end
    local rtnStatus = {
        status = false,
        statusMsg = "",
        pwid = "",
        pwurl = "",
        pwCat = "",
        added = 0,
        updated = 0,
        deleted = 0,
    }

    local ws_params = {
        { name = "name", value = album_name },
        { name = "parent", value = tostring(parent_id or 0) },
    }

    local parsed_response, err = doWsPostRequest(host, apikey, "pwg.categories.add", ws_params)
    if not parsed_response then
        rtnStatus.statusMsg = tostring(err or "Unknown error")
        return nil, rtnStatus
    end
    if parsed_response.stat ~= "ok" then
        rtnStatus.statusMsg = tostring(parsed_response.message or "Failed to add album")
        return nil, rtnStatus
    end
    rtnStatus.status = true
    rtnStatus.statusMsg = "Category added successfully"
    rtnStatus.pwCat = tostring(parsed_response.result and parsed_response.result.id or "")
    return parsed_response, rtnStatus
end

-- - - - - - - - - - - - - - - - - - - - - - - -
function pwAPI.categories_setRepresentative(host, apikey, album_id, asset_id)
    -- set representative image for album using /albums/{album_id}/representative endpoint
    if type(album_id) ~= "string" or album_id == "" then
        return nil, "No album id provided"
    end
    if type(asset_id) ~= "string" or asset_id == "" then
        return nil, "No asset id provided"
    end

    local rtnStatus = {
        status = false,
        statusMsg = "",

    }

    local ws_params = {
        { name = "category_id", value = album_id },
        { name = "image_id", value = asset_id },
    }

    local parsed_response, err = doWsPostRequest(host, apikey, "pwg.categories.setRepresentative", ws_params)
    if not parsed_response then
        rtnStatus.statusMsg = tostring(err or "Unknown error")
        return nil, rtnStatus
    end
    rtnStatus.status = true
    rtnStatus.statusMsg = "Representative image set successfully"
    return parsed_response, rtnStatus
end

-- - - - - - - - - - - - - - - - - - - - - - - -
function pwAPI.getAlbumInfo(host, apikey, album_id)
    -- helper function to get album info for single album using categories_getAdminList
    if type(album_id) ~= "string" or album_id == "" then
        return nil, "No album id provided"
    end

    local albums = pwAPI.categories_getAdminList(host, apikey, album_id)


    return albums, nil
end

-- - - - - - - - - - - - - - - - - - - - - - - -
function pwAPI.getAssetInfo(host, apikey, asset_id)
    -- Backwards-compatible alias for callers using the legacy getAsset name.
    return pwAPI.images_getInfo(host, apikey, asset_id)
end

-- - - - - - - - - - - - - - - - - - - - - - - -
function pwAPI.downloadAsset(host, apikey, asset_id, target_path, download_url)
    if type(asset_id) ~= "string" or asset_id == "" then
        return nil, "No asset id provided"
    end
    if type(target_path) ~= "string" or target_path == "" then
        return nil, "No target path provided"
    end

    local resolved_download_url = tostring(download_url or ""):match("^%s*(.-)%s*$")
    if resolved_download_url == "" then
        -- get download URL via images_getInfo when caller did not provide one
        local info_response, err = pwAPI.images_getInfo(host, apikey, asset_id)
        if not info_response then
            return nil, err
        end
        local image_info = info_response.result and info_response.result[1]
        if not image_info or type(image_info) ~= "table" then
            return nil, "Invalid image info response"
        end
        resolved_download_url = tostring(image_info.download_url or "")
    end

    resolved_download_url = tostring(resolved_download_url):match("^%s*(.-)%s*$")

    if resolved_download_url == nil or resolved_download_url == "" then
        return nil, "No download URL available for asset " .. tostring(asset_id)
    end

    local downloaded_path, download_err = doRawGetRequestToFile(host, apikey, resolved_download_url, target_path, HTTP_TIMEOUT_UPLOAD)
    if not downloaded_path then
        return nil, download_err
    end

    return downloaded_path, nil
end

-- - - - - - - - - - - - - - - - - - - - - - - -
function pwAPI.tags_getAdminList(host, apikey)
    -- get all tags from Piwigo Host
    local parsedResponse, err = doWsGetRequest(host, apikey, "pwg.tags.getAdminList")
    if not parsedResponse then
        return nil, err
    end
    if type(parsedResponse) ~= "table" then
        return {}, nil
    end
    local tagList = (type(parsedResponse.result) == "table" and type(parsedResponse.result.tags) == "table") and parsedResponse.result.tags or {}
    return tagList, nil
end

-- - - - - - - - - - - - - - - - - - - - - - - -
function pwAPI.tags_add(host, apikey, name)
    if type(name) ~= "string" or name == "" then
        return nil, "No tag name provided"
    end
    local rtnStatus = {
        status = false,
        statusMsg = "",
        pwid = "",
        pwurl = "",
        pwCat = "",
        added = 0,
        updated = 0,
        deleted = 0,
    }

    local ws_params = {
        { name = "name", value = name },
    }

    local parsed_response, err = doWsPostRequest(host, apikey, "pwg.tags.add", ws_params)
    if not parsed_response then
        rtnStatus.statusMsg = tostring(err or "Unknown error")
        return nil, rtnStatus
    end
    rtnStatus.status = true
    rtnStatus.statusMsg = "Tag added successfully"
    return parsed_response, rtnStatus
end

-- - - - - - - - - - - - - - - - - - - - - - - -
function pwAPI.images_getInfo(host, apikey, asset_id)
    if type(asset_id) ~= "string" or asset_id == "" then
        return nil, "No asset id provided"
    end

    local params = { {
        name = "image_id",
        value = asset_id
    } }

    local parsed_response, err = doWsGetRequest(host, apikey, "pwg.images.getInfo", params)
    if not parsed_response then
        return nil, err
    end
    if not parsed_response.stat then
        return nil, "Invalid response from server"
    end
    if parsed_response.stat ~= "ok" then
        return nil, tostring(parsed_response.message or "Failed to get image info")
    end
    if not parsed_response.result or type(parsed_response.result) ~= "table" then
        return nil, "Invalid result from server"
    end     
    return parsed_response, nil
end

-- - - - - - - - - - - - - - - - - - - - - - - -
function pwAPI.images_setCategory(host, apikey, album_id, asset_ids, action)
    -- associate/dissociate/move image from/to piwigo album
    local rtnStatus = {
        status = false,
        statusMsg = "",
        pwid = "",
        pwurl = "",
        pwCat = "",
        added = 0,
        updated = 0,
    }
    host = tostring(host or ""):match("^%s*(.-)%s*$")
    apikey = tostring(apikey or ""):match("^%s*(.-)%s*$")
    if not host or host == "" then
        rtnStatus.statusMsg = "No host URL provided"
        return nil, rtnStatus
    end
    if not apikey or apikey == "" then
        rtnStatus.statusMsg = "No API key provided"
        return nil, rtnStatus
    end

    if type(album_id) ~= "string" or album_id == "" then
        rtnStatus.statusMsg = "No album id provided"
        return nil, rtnStatus
    end
    if type(asset_ids) ~= "table" or #asset_ids == 0 then
        rtnStatus.statusMsg = "No asset ids provided"
        return nil, rtnStatus
    end
    if type(action) ~= "string" or (action ~= "associate" and action ~= "dissociate" and action ~= "move") then
        rtnStatus.statusMsg = "Invalid action provided, must be 'associate', 'dissociate', or 'move'"
        return nil, rtnStatus
    end


    for _, asset_id in ipairs(asset_ids) do
        local ws_params = {
            { name = "category_id", value = album_id },
            { name = "image_id",    value = asset_id },
            { name = "action",      value = action },
        }
        --log:info("pwAPI.images_setCategory - calling with params " .. utils.serialiseVar(ws_params))
        local parsed_response, err = doWsPostRequest(host, apikey, "pwg.images.setCategory", ws_params)
        if not parsed_response then
            rtnStatus.statusMsg = tostring(err or "Unknown error")
            return nil, rtnStatus
        end
        --log:info("pwAPI.images_setCategory - " .. "parsed_response is ".. utils.serialiseVar(parsed_response))
        log:info("pwAPI.images_setCategory - " .. action .. " - " .. tostring(asset_id) .. ", album_id " .. tostring(album_id))
    end 



    return true, nil
end

-- - - - - - - - - - - - - - - - - - - - - - - -
function pwAPI.images_setInfo(host, apikey, asset_id, metaData)
    if type(asset_id) ~= "string" or asset_id == "" then
        return false, "No asset id provided"
    end
    if type(metaData) ~= "table" then
        return false, "No metadata fields provided"
    end
    if next(metaData) == nil then
        return true, nil
    end
    local rtnStatus = {
        status = false,
        statusMsg = "",
        pwid = "",
        pwurl = "",
        pwCat = "",
        added = 0,
        updated = 0,
    }
    local params = {
        { name = "method",              value = "pwg.images.setInfo" },
        { name = "image_id",            value = tostring(asset_id) },
        { name = "single_value_mode",   value = "replace" }, -- force metadata to be replaced rather than appended
        { name = "multiple_value_mode", value = "replace" }, -- force tags to be replaced rather than appended
    }

    if metaData.title and metaData.title ~= "" then
        table.insert(params, {
            name = "name",
            value = metaData.title
        })
    end
    if metaData.creator and metaData.creator ~= "" then
        table.insert(params, {
            name = "author",
            value = metaData.creator
        })
    end
    if metaData.dateCreated and metaData.dateCreated ~= "" then
        table.insert(params, {
            name = "date_creation",
            value = metaData.dateCreated
        })
    end
    if metaData.description and metaData.description ~= "" then
        table.insert(params, {
            name = "comment",
            value = metaData.description
        })
    end
    -- GPS coordinates
    if metaData.latitude and metaData.longitude then
        table.insert(params, {
            name = "latitude",
            value = tostring(metaData.latitude)
        })
        table.insert(params, {
            name = "longitude",
            value = tostring(metaData.longitude)
        })
    end
    if metaData.tags and type(metaData.tags) == "table" and #metaData.tags > 0 then
        table.insert(params, {
            name = "tag_ids",
            value = table.concat(metaData.tags, ",")
        })
    end

    log:info("pwAPI.images_setInfo - calling with params " .. utils.serialiseVar(params))

    local parsed_response, err = doWsPostRequest(host, apikey, "pwg.images.setInfo", params)
    if not parsed_response then
        rtnStatus.statusMsg = tostring(err or "Unknown error")
        return nil, rtnStatus
    end
    if err then
        return false, err
    end
    log:info("pwAPI.images_setInfo - " .. "parsed_response is ".. utils.serialiseVar(parsed_response))
    return true, nil
end

-- - - - - - - - - - - - - - - - - - - - - - - -
function pwAPI.images_addSimple(host, apikey, file_path, params)
    -- upload image to Piwigo using ws.php pwg.images.addSimple endpoint

    local rtnStatus = {
        status = false,
        statusMsg = "",
        pwid = "",
        pwurl = "",
        pwCat = "",
        added = 0,
        updated = 0,
    }

    host = tostring(host or ""):match("^%s*(.-)%s*$")
    apikey = tostring(apikey or ""):match("^%s*(.-)%s*$")
    if not host or host == "" then
        rtnStatus.statusMsg = "No host URL provided"
        return nil, rtnStatus
    end
    if not apikey or apikey == "" then
        rtnStatus.statusMsg = "No API key provided"
        return nil, rtnStatus
    end

    local category = tostring(params and params.category or ""):match("^%s*(.-)%s*$")
    local tags = tostring(params and params.tags or ""):match("^%s*(.-)%s*$")
    local name = tostring(params and params.name or ""):match("^%s*(.-)%s*$")
    local comment = tostring(params and params.comment or ""):match("^%s*(.-)%s*$")
    local author = tostring(params and params.author or ""):match("^%s*(.-)%s*$")
    local contentType = tostring((params and params.image_contentType ~= "" and params.image_contentType) or ""):match("^%s*(.-)%s*$")
    local image_id = tostring((params and params.image_id or ""):match("^%s*(.-)%s*$"))

    local multipart_fields = {
        { name = "category", value = category },
        { name = "name",     value = name },
        { name = "comment",  value = comment },
        { name = "author",   value = author },
    }
    if image_id ~= "" then
        -- add existing pwigo image id if set
        table.insert(multipart_fields, { name = "image_id", value = image_id })
    end
    if tags ~= "" then
        table.insert(multipart_fields, { name = "tags", value = tags })
    end

    local upload_response, err = doWsPostMultipartRequest(
        host,
        apikey,
        "pwg.images.addSimple",
        multipart_fields,
        file_path,
        contentType
    )
    if not upload_response then
        rtnStatus.statusMsg = tostring(err or "Unknown error")
        return nil, rtnStatus
    end

    return upload_response, rtnStatus
end

-- - - - - - - - - - - - - - - - - - - - - - - -
function pwAPI.images_uploadCompleted(host, apikey, category_id, image_id)
    -- tell piwigo that imaage upload has finished via pwg.images.uploadCompleted
    local rtnStatus = {
        status = false,
        statusMsg = "",
        pwid = "",
        pwurl = "",
        pwCat = "",
        added = 0,
        updated = 0,
    }

    local params = {
        {
            name = "category_id",
            value = category_id
        },
        {
            name = "image_id",
            value = image_id
        }
    }

    local parsed_response, err = doWsGetRequest(host, apikey, "pwg.images.uploadCompleted", params)
    if not parsed_response then
        return nil, err
    end

    if parsed_response.stat ~= 'ok' then
        log:info("pwAPI.images_uploadCompleted called with " .. utils.serialiseVar(params))
        rtnStatus.statusMsg = ("Failed to flag UploadCompleted for image " .. tostring(image_id) .. " - " .. utils.serialiseVar(parsed_response))
        return nil, rtnStatus
    end


    rtnStatus["status"] = true
    rtnStatus["statusMsg"] = "Upload successful"

    return parsed_response, rtnStatus
end

-- - - - - - - - - - - - - - - - - - - - - - - -
function pwAPI.images_delete(host, apikey, asset_ids)
    local rtnStatus = {
        status = false,
        statusMsg = "",
        pwid = "",
        pwurl = "",
        pwCat = "",
        added = 0,
        updated = 0,
        deleted = 0,
    }
    host = tostring(host or ""):match("^%s*(.-)%s*$")
    apikey = tostring(apikey or ""):match("^%s*(.-)%s*$")
    if not host or host == "" then
        rtnStatus.statusMsg = "No host URL provided"
        return nil, rtnStatus
    end
    if not apikey or apikey == "" then
        rtnStatus.statusMsg = "No API key provided"
        return nil, rtnStatus
    end
    if type(asset_ids) ~= "table" or #asset_ids == 0 then
        rtnStatus.statusMsg = "No asset ids provided"
        return nil, rtnStatus
    end

    for _, asset_id in ipairs(asset_ids) do
        local ws_params = {
            { name = "image_id", value = asset_id },
        }

        local parsed_response, err = doWsPostRequest(host, apikey, "pwg.images.delete", ws_params)
        if not parsed_response then
            rtnStatus.statusMsg = tostring(err or "Unknown error")
            return nil, rtnStatus
        end
        log:info("pwAPI.images_delete - delete asset_id " .. tostring(asset_id))
    end
    rtnStatus.status = true
    rtnStatus.statusMsg = "Delete successful"
    return nil, rtnStatus
end

-- - - - - - - - - - - - - - - - - - - - - - - -
function pwAPI.uploadAsset(host, apikey, upload_file_path, metaData, upload_metadata)
    -- upload image to Piwigo using ws.php pwg.images.addSimple endpoint and flag upload completed_response
    local rtnStatus = {
        status = false,
        statusMsg = "",
        pwid = "",
        pwurl = "",
        pwCat = "",
        added = 0,
        updated = 0,
    }
    host = tostring(host or ""):match("^%s*(.-)%s*$")
    apikey = tostring(apikey or ""):match("^%s*(.-)%s*$")
    if not host or host == "" then
        rtnStatus.statusMsg = "No host URL provided"
        return nil, rtnStatus
    end
    if not apikey or apikey == "" then
        rtnStatus.statusMsg = "No API key provided"
        return nil, rtnStatus
    end
    if type(upload_file_path) ~= "string" or upload_file_path == "" then
        rtnStatus.statusMsg = "No export file path provided"
        return nil, rtnStatus
    end
    local album_id = tostring(upload_metadata.album_id or ""):match("^%s*(.-)%s*$")
    local image_id = tostring(upload_metadata.image_id or ""):match("^%s*(.-)%s*$")

    local params = {
        category = album_id
    }
    if metaData.Title and metaData.Title ~= "" then
        params.name = metaData.Title
    end
    if metaData.Creator and metaData.Creator ~= "" then
        params.author = metaData.Creator
    end
    if metaData.Caption and metaData.Caption ~= "" then
        params.comment = metaData.Caption
    end
    -- keywords
    if metaData.tagString and metaData.tagString ~= "" then
        params.tags = metaData.tagString
    end
    local is_new_image
    if image_id ~= "" then
        -- check if remote photo exists and ignore parameter if not
        local response, err = pwAPI.images_getInfo(host, apikey, image_id)
        if response and response.stat == "ok" then
            -- image exists - so we will update
            params.image_id = tostring(image_id)
            is_new_image = false
        end
    end

    local file_type = LrPathUtils.extension(upload_file_path):lower()
    local contentType = ""
    if file_type == "png" then
        contentType = "image/png"
    elseif file_type == "jpg" or file_type == "jpeg" then
        contentType = "image/jpeg"
    else
        rtnStatus.statusMsg = "Upload failed - forbidden file type"
        return nil, rtnStatus
    end
    params.image_contentType = contentType

    -- upload image to Piwigo via ws.php pwg.images.addSimple endpoint

    local upload_response, uploadstatus = pwAPI.images_addSimple(host, apikey, upload_file_path, params)
    if not upload_response then
        rtnStatus.statusMsg = "pwAPI.uploadAsset failed: " .. tostring(uploadstatus and uploadstatus.statusMsg or "Unknown error")
        return nil, rtnStatus
    end
 
    local pwImageID = tostring(upload_response.result and upload_response.result.image_id or "")
    local pwImageURL = tostring(upload_response.result and upload_response.result.image_url or "")
    if type(pwImageID) ~= "string" or pwImageID == "" then
        rtnStatus.statusMsg = "Upload response did not include id"
        return nil, rtnStatus
    end

    -- flag upload completed via ws.php pwg.images.uploadCompleted endpoint

    local completed_response, completed_status = pwAPI.images_uploadCompleted(host, apikey, album_id, pwImageID)
    if not completed_response then
 
        rtnStatus.statusMsg = "pwAPI.uploadAsset failed to flag upload completed: " .. tostring(completed_status and completed_status.statusMsg or "Unknown error")
        return nil, rtnStatus
    end
    -- delete exported image
    os.remove(upload_file_path)
    rtnStatus.status = true
    rtnStatus.statusMsg = "Upload successful"
    rtnStatus.is_new_image = is_new_image
    rtnStatus.pwid = pwImageID
    rtnStatus.pwurl = pwImageURL
    return pwImageID, rtnStatus
end


-- ==========================================================
-- E N D   O F   F I L E
-- ==========================================================
return pwAPI