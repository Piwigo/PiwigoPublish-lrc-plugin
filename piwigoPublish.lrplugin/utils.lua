--[[

    utils.lua - generic utility functions

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


local utils = {}


-- *************************************************
function utils.getFileMd5(fName)
    -- return md5 sum of file fName
    local f = io.open(fName, "rb")
    if not f then
        return nil, "Unable to open file: " .. fName
    end
    local content = f:read("*all")
    f:close()
    if not content then
        return nil, "Unable to read file: " .. fName
    end
    log:info("DEBUG getFileMd5 - file: " .. fName .. ", size: " .. tostring(#content) .. " bytes")
    local md5sum = LrMD5.digest(content)

    return md5sum, "MD5 calculated successfully"
end

-- *************************************************
function utils.anonymisePropertyTable(propertyTable)
    -- return copy of property table with sensitive data removed (for logging etc)
    if type(propertyTable) ~= "table" then
        return propertyTable
    end

    local redactedKeys = {
        userpw = true,
        username = true,
        host = true,
        pwurl = true,
        cookieheader = true,
        sessioncookie = true,
        token = true,
        cookies = true,
    }

    local droppedKeys = {
        tagtable = true,
        _tagindex = true,
    }

    local visited = {}

    local function anonymiseValue(value)
        if type(value) ~= "table" then
            return value
        end
        if visited[value] then
            return visited[value]
        end

        local copy = {}
        visited[value] = copy

        for k, v in pairs(value) do
            local keyName = type(k) == "string" and string.lower(k) or nil
            if keyName and droppedKeys[keyName] then
                copy[k] = nil
            elseif keyName and redactedKeys[keyName] then
                copy[k] = "****"
            else
                copy[k] = anonymiseValue(v)
            end
        end

        return copy
    end

    return anonymiseValue(propertyTable)
end

-- *************************************************
function utils.anonymiseRenditionParams(renditionParams)
    -- return copy of renditionParams with sensitive data removed (for logging etc)
    if type(renditionParams) ~= "table" then
        return renditionParams
    end

    local visited = {}

    local function deepCopy(value)
        if type(value) ~= "table" then
            return value
        end
        if visited[value] then
            return visited[value]
        end

        local copy = {}
        visited[value] = copy
        for k, v in pairs(value) do
            copy[k] = deepCopy(v)
        end
        return copy
    end

    local rpCopy = deepCopy(renditionParams)

    if type(rpCopy.exportContext) == "table" and type(rpCopy.exportContext.propertyTable) == "table" then
        rpCopy.exportContext.propertyTable = utils.anonymisePropertyTable(rpCopy.exportContext.propertyTable)
    end

    if type(rpCopy.propertyTable) == "table" then
        rpCopy.propertyTable = utils.anonymisePropertyTable(rpCopy.propertyTable)
    end

    return rpCopy
end

-- *************************************************
function utils.stripHtml(s)
    -- Strip HTML tags from string
    if not s or s == "" then return s end
    -- Strip all HTML tags
    s = s:gsub("<[^>]+>", "")
    -- Decode common HTML entities
    s = s:gsub("&nbsp;", " "):gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub(
        "&#39;", "'")
    -- Linearize: replace newlines/carriage returns with a single space
    s = s:gsub("[\r\n]+", " ")
    -- Collapse multiple spaces
    s = s:gsub("  +", " ")
    -- Trim
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

-- *************************************************
function utils.serialiseVar(value, indent)
    -- serialises an unknown variable
    indent = indent or ""
    local t = type(value)

    if t == "table" then
        local parts = {}
        table.insert(parts, "{\n")
        local nextIndent = indent .. "  "
        for k, v in pairs(value) do
            local key
            if type(k) == "string" then
                key = string.format("%q", k)
            else
                key = tostring(k)
            end
            table.insert(parts, nextIndent .. "[" .. key .. "] = " .. utils.serialiseVar(v, nextIndent) .. ",\n")
        end
        table.insert(parts, indent .. "}")
        return table.concat(parts)
    elseif t == "string" then
        return string.format("%q", value)
    else
        return tostring(value)
    end
end

-- *************************************************
function utils.uuid()
    -- create uuid in form xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
end

-- *************************************************
function utils.extractNumber(inStr)
    -- Extract first number (integer or decimal, optional sign) from a string

    local num = string.match(inStr, "[-+]?%d+%.?%d*")
    if num then
        return tonumber(num)
    end
    return nil -- no number found
end

-- *************************************************
-- Convert input value to a positive number; return nil if missing/invalid/non-positive.
function utils.toPositiveNumber(value)
    local n = tonumber(value)
    if n and n > 0 then
        return n
    end
    return nil
end

-- *************************************************
-- Lightroom can pass property tables wrapped as { ["< contents >"] = {...} }.
-- Return effective settings table plus the original owner table.
function utils.getEffectivePropertyTable(propertyTable)
    if type(propertyTable) == "table" and type(propertyTable["< contents >"]) == "table" then
        return propertyTable["< contents >"], propertyTable
    end
    return propertyTable, propertyTable
end

-- *************************************************
-- Compare effective Lightroom resize-related export settings and report first difference.
function utils.resizeSettingsDiffer(originalSettings, newSettings)
    local keyDefs = {
        { name = 'LR_size_doConstrain', type = 'bool' },
        { name = 'LR_size_userWantsConstrain', type = 'bool' },
        { name = 'LR_size_doNotEnlarge', type = 'bool', aliases = { 'LR_size_dontEnlarge' } },
        { name = 'LR_size_maxWidth', type = 'number', aliases = { 'LR_size_maxW' } },
        { name = 'LR_size_maxHeight', type = 'number', aliases = { 'LR_size_maxH' } },
        { name = 'LR_size_percentage', type = 'number' },
        { name = 'LR_size_resizeType', type = 'string' },
        { name = 'LR_size_units', type = 'string' },
    }

    local function getValue(settings, keyDef)
        local value = settings[keyDef.name]
        if value == nil and keyDef.aliases then
            for _, alias in ipairs(keyDef.aliases) do
                value = settings[alias]
                if value ~= nil then
                    break
                end
            end
        end
        return value
    end

    for _, keyDef in ipairs(keyDefs) do
        local originalRaw = getValue(originalSettings, keyDef)
        local newRaw = getValue(newSettings, keyDef)
        local originalValue = originalRaw
        local newValue = newRaw

        if keyDef.type == 'bool' then
            originalValue = originalRaw and true or false
            newValue = newRaw and true or false
        elseif keyDef.type == 'number' then
            originalValue = tonumber(originalRaw)
            newValue = tonumber(newRaw)
        else
            originalValue = originalRaw ~= nil and tostring(originalRaw) or nil
            newValue = newRaw ~= nil and tostring(newRaw) or nil
        end

        if originalValue ~= newValue then
            return true, keyDef.name, originalRaw, newRaw
        end
    end

    return false
end

-- *************************************************
function utils.dumpPropertyTableToDesktop(tableToDump, collectionSettings, context)
    local desktopDir = LrPathUtils.getStandardFilePath('desktop')
    local debugDir = LrPathUtils.child(desktopDir, "PiwigoPublishDebug")

    if not debugDir or debugDir == "" then
        log:warn("Unable to resolve Desktop path for propertyTable dump")
        return
    end

    LrFileUtils.createAllDirectories(debugDir)

    local timestamp = os.date("%Y%m%d-%H%M%S")
    local dumpPath = LrPathUtils.child(debugDir, "PiwigoPublish-propertyTable-" .. timestamp .. ".lua")

    local dumpText = "-- PiwigoPublish propertyTable debug dump\n" ..
        "-- Generated: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n" ..
        "-- Context: " .. (context or "runCustomRenderForCollection") .. "\n\n" ..
        "collectionSettings = " .. utils.serialiseVar(collectionSettings) .. "\n\n" ..
        "propertyTable = " .. utils.serialiseVar(tableToDump) .. "\n"

    local file, err = io.open(dumpPath, "w")
    if not file then
        log:warn("Failed to write propertyTable dump file: " .. tostring(err))
        return
    end

    file:write(dumpText)
    file:close()
    log:info("propertyTable dump written to: " .. dumpPath)
end

-- *************************************************
function utils.reverseTable(t)
    local reversed = {}
    for i = #t, 1, -1 do
        reversed[#reversed + 1] = t[i]
    end
    return reversed
end

-- *************************************************
function utils.dmsToDecimal(deg, min, sec, hemi)
    -- convert DMS (degrees, minutes, seconds + direction) to decimal degrees
    local decimal = tonumber(deg) + tonumber(min) / 60
    if sec and sec ~= "" then
        decimal = decimal + tonumber(sec) / 3600
    end
    if hemi == "S" or hemi == "W" then
        decimal = -decimal
    end
    return decimal
end

-- *************************************************
function utils.parseSingleGPS(coordStr)
    -- Try parsing a single coordinate (works for DMS or DM)
    local deg, min, sec, hemi = string.match(coordStr, "(%d+)°(%d+)'([%d%.]+)\"%s*([NSEW])")
    if deg then
        return utils.dmsToDecimal(deg, min, sec, hemi)
    end

    local deg2, min2, hemi2 = string.match(coordStr, "(%d+)°([%d%.]+)'%s*([NSEW])")
    if deg2 then
        return utils.dmsToDecimal(deg2, min2, nil, hemi2)
    end

    return nil -- not matched
end

-- *************************************************
function utils.parseGPS(coordStr)
    -- parse a coordinate string like: 51°13'31.9379" N 3°38'5.0159" W
    -- Split into two parts (latitude + longitude)
    local latStr, lonStr = string.match(coordStr, "^(.-)%s+([%d°'\"%sNSEW%.]+)$")
    if not latStr or not lonStr then
        return nil, nil, "Invalid coordinate format"
    end

    local lat = utils.parseSingleGPS(latStr)
    local lon = utils.parseSingleGPS(lonStr)

    return lat, lon
end

-- *************************************************
function utils.timeStamp(dateStrISO)
    if not dateStrISO or dateStrISO == "" then
        return nil
    end
    -- check for ISO
    if dateStrISO:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$") then
        local year, month, day, hour, min, sec = dateStrISO:match("(%d+)%-(%d+)%-(%d+) (%d+):(%d+):(%d+)")
        local timestamp = os.time({
            year  = year,
            month = month,
            day   = day,
            hour  = tonumber(hour),
            min   = tonumber(min),
            sec   = tonumber(sec),
        })
        return timestamp
    end
    return nil
end

-- *************************************************
function utils.formattedToISO(dateStr)
    if not dateStr or dateStr == "" then
        return nil
    end
    -- check for ISO
    if dateStr:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$") then
        return dateStr
    end
    -- Convert Lightroom-formatted date/time (with optional fractional seconds)
    local t = utils.normaliseDateTime(dateStr)
    if not t then
        return nil
    end


    -- Format as YYYY-MM-DD HH:MM
    return LrDate.formatShortDateTime(t, "%Y-%m-%d %H:%M")
end

-- *************************************************
function utils.normaliseDateTime(dateStr)
    if not dateStr or dateStr == "" then
        return nil
    end

    -- Try to match: MM/DD/YYYY HH:MM[:SS][.fff]
    local month, day, year, hour, min = dateStr:match(
        "(%d%d)/(%d%d)/(%d%d%d%d)%s+(%d%d):(%d%d)"
    )

    if month and day and year and hour and min then
        return string.format("%04d-%02d-%02d %02d:%02d",
            tonumber(year), tonumber(month), tonumber(day),
            tonumber(hour), tonumber(min))
    end

    -- If match fails, try DD/MM/YYYY or other common formats as needed
    return nil
end

-- *************************************************
function utils.findNode(xmlNode, nodeName)
    -- iteratively find nodeName in xmlNode

    if xmlNode:name() == nodeName then
        return xmlNode
    end

    for i = 1, xmlNode:childCount() do
        local child = xmlNode:childAtIndex(i)
        if child:type() == "element" then
            local found = utils.findNode(child, nodeName)
            if found then return found end
        end
    end
    return nil
end

-- *************************************************
function utils.fileExists(fName)
    local f = io.open(fName, "r")
    if f then
        io.close(f)
        return true
    end
    return false
end

-- *************************************************
function utils.stringtoTable(inString, delim)
    -- create table based on passed in delimited string
    local rtnTable = {}

    for substr in string.gmatch(inString, "[^" .. delim .. "]*") do
        if substr ~= nil and string.len(substr) > 0 then
            table.insert(rtnTable, substr)
        end
    end

    return rtnTable
end

-- *************************************************
function utils.tabletoString(inTable, delim)
    local rtnString = ""
    for ss, value in pairs(inTable) do
        if rtnString == "" then
            rtnString = value
        else
            rtnString = rtnString .. delim .. value
        end
    end

    return rtnString
end

-- *************************************************
function utils.tagParse(tag)
    -- parse hierarchical tag structure (delimted by |) into table of individual elements
    local tag_table = {}
    for line in (tag .. "|"):gmatch("([^|]*)|") do
        table.insert(tag_table, line)
    end
    return tag_table
end

-- *************************************************
function utils.handleError(logMsg, userErrorMsg)
    -- function to log errors and throw user errors
    log:error(logMsg)
    LrDialogs.showError(userErrorMsg)
end

-- *************************************************
function utils.cutApiKey(key)
    -- replace characters of private string with elipsis
    return string.sub(key, 1, 20) .. '...'
end

-- *************************************************
function utils.clean_spaces(text)
    --removes spaces from the front and back of passed in text
    text = string.gsub(text, "^%s*", "")
    text = string.gsub(text, "%s*$", "")
    return text
end

-- *************************************************
function utils.nilOrEmpty(val)
    -- check if val is nil or empty

    if val == nil then
        return true
    end
    if type(val) == "string" and val == "" then
        return true
    end
    if type(val) == "table" then
        -- Check if table has any elements (non-empty)
        for _ in pairs(val) do
            return false
        end
        return true
    end
    return false
end

---- *************************************************
function utils.nonEmpty(v)
    return (v ~= nil and v ~= "") and v or nil
end

---- *************************************************
function utils.GetKWHierarchy(kwHierarchy, thisKeyword, pos)
    -- build hierarchical list of parent keywords
    -- returns table of keywords with leaf node at pos 1 and each parent in subsequent positions
    kwHierarchy[pos] = thisKeyword
    if thisKeyword:getParent() == nil then
        return kwHierarchy
    end
    pos = pos + 1
    return (utils.GetKWHierarchy(kwHierarchy, thisKeyword:getParent(), pos))
end

---- *************************************************
function utils.GetKWfromHeirarchy(LrKeywords, kwStructure, logger)
    -- returns keyword from lowest element of hierarchical kwStructure (in form level1|level2|level3 ...)

    -- spilt kwStructure into individual elements
    local kwTable = utils.tagParse(kwStructure)
    local thisKW = nil
    local lastKWName = kwTable[#kwTable]
    if kwTable then
        for kk, kwName in ipairs(kwTable) do
            if thisKW then
                if thisKW:getName() == lastKWName then
                    return thisKW
                else
                    thisKW = utils.GetLrKeyword(thisKW:getChildren(), kwName)
                end
            else
                thisKW = utils.GetLrKeyword(LrKeywords, kwName)
            end
        end
    end
    return thisKW
end

-- *************************************************
function utils.GetLrKeyword(LrKeywords, keywordName)
    -- recursive function to return keyword with name matching keywordName
    for _, thisKeyword in ipairs(LrKeywords) do
        if thisKeyword:getName() == keywordName then
            return thisKeyword
        end
        -- Recursively search children
        local childMatch = utils.GetLrKeyword(thisKeyword:getChildren(), keywordName)
        if childMatch then
            return childMatch
        end
    end
    return nil
end

-- *************************************************
function utils.checkKw(thisPhoto, searchKw)
    -- does image contain keyword - returns keyword  or nil
    -- searchKw is string containing keyword to search for

    local kwHierarchy = {}
    local thisKwName = ""

    -- searchKw may be hierarchical - so split into each level
    local searchKwTable = utils.tagParse(searchKw)
    local searchKwLevels = #searchKwTable
    local foundKW = nil -- return the keyword we find in this variable
    local stopSearch = false
    for ii, thisKeyword in ipairs(thisPhoto:getRawMetadata("keywords")) do
        -- thisKeyword is leaf node
        -- now need to build full hierarchical structure for thiskeyword
        kwHierarchy = {}
        kwHierarchy = utils.GetKWHierarchy(kwHierarchy, thisKeyword, 1)
        local thisKwLevels = #kwHierarchy
        for kk, kwLevel in ipairs(kwHierarchy) do
            local kwLevelName = kwLevel:getName()
            --log:info("Level " .. kk .. " is " .. kwLevelName)
            if not stopSearch then
                if kwLevelName == searchKwTable[1] then
                    -- if we're looking for hierarchical kw need to check other levels for match aswell
                    if searchKwLevels > 1 then
                        if thisKwLevels >= searchKwLevels then
                            local foundHKW = true
                            for hh = 2, searchKwLevels do
                                if searchKwTable[hh] ~= kwHierarchy[kk - hh + 1]:getName() then
                                    foundHKW = false
                                end
                            end
                            if foundHKW then
                                foundKW = thisKeyword
                                stopSearch = true
                            end
                        end
                    else
                        foundKW = thisKeyword
                        stopSearch = true
                    end
                end
            end
        end
    end
    return foundKW
end

-- *************************************************
function utils.checkTagUnique(tag, tagTable)
    -- look for string (tag) in table of strings(tags) and return true if found

    for tt, thisTag in pairs(tagTable) do
        if thisTag == tag then
            return false
        end
    end
    return true
end

-- *************************************************
function utils.buildTagIndex(propertyTable)
    -- build reverse index of tagIds to speed up tag processing
    local pwTagTable = propertyTable.tagTable or {}
    local index = {}
    for _, pwTag in pairs(pwTagTable or {}) do
        local pwTagName = pwTag.name_raw or pwTag.name or ""
        local normalized = utils.normaliseWord(pwTagName)
        if normalized ~= "" then
            index[normalized] = pwTag.id
        end
    end
    propertyTable._tagIndex = index
end

-- *************************************************
function utils.tagsToIds(propertyTable, tagString)
    -- convert tagString to list of assoiciated tag ids
    -- use _tagIndex which is a reverse lookup table created in utils.buildTagIndex(propertyTable) when tagTable is refreshed via PiwigoAPI.getTagList(propertyTable)
    -- tagString = comma delimted list of tags for which we want the associated Piwigo Tag ID

    local pwTagTable = propertyTable.tagTable or {}
    local pwTagIndex = propertyTable._tagIndex or {}
    local tagIdList = ""
    local missingTags = {}

    -- convert tagString to table
    local tagTable = utils.stringtoTable(tagString, ",")
    local tagIds = {}
    for _, thisTag in pairs(tagTable) do
        local tagId = ""
        local foundTag = false
        -- look for thisTag in pwTagTable - use pwTagIndex
        local n_thisTag = utils.normaliseWord(thisTag)
        local thisTagId = pwTagIndex[n_thisTag]
        if thisTagId then
            table.insert(tagIds, thisTagId)
        else
            table.insert(missingTags, thisTag)
        end
    end
    tagIdList = table.concat(tagIds, ",")
    return tagIdList, missingTags
end

-- *************************************************
function utils.BuildTagString(propertyTable, lrPhoto, collectionSettings)
    -- build text string of keywords on lrPhoto - to be sent to Piwigo
    -- respect LrC includeOnExport flag set in keyword tag editor
    -- respect KwFullHierarchy and KwSynonyms set in publish manager settings
    -- respect keyword filters set at publish service or collections level

    -- set up custom export filters if set
    local KwFullHierarchy = propertyTable.KwFullHierarchy
    local KwSynonyms      = propertyTable.KwSynonyms
    local excludePatterns = utils.parseFilterPatterns(propertyTable.KwFilterExclude)
    local includePatterns = utils.parseFilterPatterns(propertyTable.KwFilterInclude)
    if propertyTable.PWP_customAlbumSettings and collectionSettings and collectionSettings.enableCustom then
        if collectionSettings then
            if collectionSettings.KwFullHierarchy ~= nil then
                KwFullHierarchy = collectionSettings.KwFullHierarchy
            end
            if collectionSettings.KwSynonyms ~= nil then
                KwSynonyms = collectionSettings.KwSynonyms
            end
            if collectionSettings.KwFilterExclude then
                excludePatterns = utils.parseFilterPatterns(collectionSettings.KwFilterExclude)
            end
            if collectionSettings.KwFilterInclude then
                includePatterns = utils.parseFilterPatterns(collectionSettings.KwFilterInclude)
            end
        end
    end

    local hasIncludeRules = includePatterns and #includePatterns > 0
    local hasExcludeRules = excludePatterns and #excludePatterns > 0
    -- build tagTable which will contain the list of unique keywords to be sent to Piwigo
    local tagTable = {}
    for _, thisKeyword in ipairs(lrPhoto:getRawMetadata("keywords")) do
        local kwHierarchy = utils.GetKWHierarchy({}, thisKeyword, 1) -- leaf at [1], parents upwards
        local thisKwHierarchy = {}                                   -- will contain list of keywords to be sent to Piwigo for this kwHierarchy
        local kwLevels = #kwHierarchy

        -- Hierarchy-level filter result:
        -- include if ANY level matches include rule (when include rules exist)
        -- exclude if ANY level matches exclude rule
        local hierarchyIncludeMatch = not hasIncludeRules
        local hierarchyExcludeMatch = false

        for kk = kwLevels, 1, -1 do
            -- traverse the hierarchy from root down to leaf - this way we can check each level against filter rules and stop processing if any level fails filter criteria
            local kwLevel = kwHierarchy[kk]
            local kwAtts = kwLevel:getAttributes()
            if kwAtts.includeOnExport then
                -- this keyword is marked for export - so get name and synonyms and add to tagTable if they satisfy filter rules
                local kwLevelName = kwLevel:getName()
                -- evaluate filters against every hierarchy element
                if hasIncludeRules and not hierarchyIncludeMatch then
                    hierarchyIncludeMatch = utils.checkIncludeKeywordFilter(kwLevelName, includePatterns)
                end
                if hasExcludeRules and not hierarchyExcludeMatch then
                    hierarchyExcludeMatch = utils.checkExcludeKeywordFilter(kwLevelName, excludePatterns)
                end
                local kwLevelSyn = kwLevel:getSynonyms()
                if kk > 1 then
                    if KwFullHierarchy then
                        -- only process beyond leaf node if full hierarchy option is set
                        table.insert(thisKwHierarchy, kwLevelName)
                        if KwSynonyms then
                            -- include Synonyms if option is set
                            for _, syn in pairs(kwLevelSyn) do
                                table.insert(thisKwHierarchy, syn)
                            end
                        end
                    end
                else
                    -- leaf node - always include if export flag is set and it satisfies filter criteria
                    table.insert(thisKwHierarchy, kwLevelName)
                    if propertyTable.KwSynonyms then
                        for _, syn in pairs(kwLevelSyn) do
                            table.insert(thisKwHierarchy, syn)
                        end
                    end
                end
            end
        end

        local includeThisHierarchy = hierarchyIncludeMatch and (not hierarchyExcludeMatch)
        -- add thisKwHierarchy to tagTable
        if includeThisHierarchy then
            for _, kw in ipairs(thisKwHierarchy) do
                if utils.checkTagUnique(kw, tagTable) then
                    table.insert(tagTable, kw)
                end
            end
        end
    end


    -- tagString is comma delimited list of keywords to be sent to Piwigo - convert tagTable to string
    local tagString = ""
    tagString = utils.tabletoString(tagTable, ",")
    return tagString
end

-- *************************************************
function utils.wildcardMatch(pattern, text)
    -- match text against a wildcard pattern (* = any chars, ? = single char)
    -- case-insensitive
    local p = pattern:lower()
    local t = text:lower()
    -- escape Lua magic characters except * and ?
    p = p:gsub("([%.%+%-%^%$%(%)%%])", "%%%1")
    p = p:gsub("%[", "%%[")
    p = p:gsub("%]", "%%]")
    -- convert wildcards to Lua patterns
    p = p:gsub("%*", ".*")
    p = p:gsub("%?", ".")
    -- anchor the pattern
    p = "^" .. p .. "$"
    return t:match(p) ~= nil
end

-- *************************************************
function utils.parseFilterPatterns(filterString)
    -- parse filter patterns string into a table (one rule per line, also accepts commas)
    local patterns = {}
    if not filterString or filterString == "" then
        return patterns
    end
    for token in filterString:gmatch("[^\r\n,]+") do
        local trimmed = utils.clean_spaces(token)
        if trimmed ~= "" then
            table.insert(patterns, trimmed)
        end
    end
    return patterns
end

-- *************************************************
function utils.buildFilteredKeywordList(keywords, includePatterns, excludePatterns)
    -- build list of keywords to send to Piwigo based on include/exclude patterns
    -- keywords is a table of Class LrKeyword
    local includeKeywords = {}

    for _, kw in ipairs(keywords) do
        local isAllowed = true
        local kwName = kw:getName()
        if excludePatterns and #excludePatterns > 0 then
            for _, pat in ipairs(excludePatterns) do
                if utils.wildcardMatch(pat, kwName) then
                    isAllowed = false
                    break
                end
            end
        end
        if isAllowed and includePatterns and #includePatterns > 0 then
            local found = false
            for _, pat in ipairs(includePatterns) do
                if utils.wildcardMatch(pat, kwName) then
                    found = true
                    break
                end
            end
            if not found then
                isAllowed = false
            end
        end

        if isAllowed then
            table.insert(includeKeywords, kw)
        end
    end

    return includeKeywords
end

-- *************************************************
function utils.checkIncludeKeywordFilter(kwName, includePatterns)
    -- check if a  keyword satisfies include/exclude filter rules
    -- returns: doInclude (bool), doExclude (bool)

    local doInclude = false

    --log:info("utils.checkIncludeKeywordFilter - kwName: " .. kwName)
    -- check include rules first
    if includePatterns and #includePatterns > 0 then
        for _, pat in ipairs(includePatterns) do
            if utils.wildcardMatch(pat, kwName) then
                doInclude = true
                break
            end
        end
    else
        -- if no include patterns set, then we want to include all keywords which are not excluded by the exclude patterns
        doInclude = true
    end



    return doInclude
end

-- *************************************************
function utils.checkExcludeKeywordFilter(kwName, excludePatterns)
    -- check if a  keyword satisfies include/exclude filter rules
    -- returns: doInclude (bool), doExclude (bool)


    local doExclude = false
    --log:info("utils.checkExcludeKeywordFilter - kwName: " .. kwName)


    -- check exclude rules
    if excludePatterns and #excludePatterns > 0 then
        for _, pat in ipairs(excludePatterns) do
            if utils.wildcardMatch(pat, kwName) then
                doExclude = true
                break
            end
        end
    end

    return doExclude
end

-- *************************************************
function utils.getPhotoMetadata(publishSettings, lrPhoto, collectionSettings)
    -- build set of metadata to be send to Piwigo
    local metaData = {}

    local useTitleFormat = publishSettings.mdTitle
    local useCaptionFormat = publishSettings.mdDescription
    if publishSettings.PWP_customAlbumSettings and collectionSettings then
        if collectionSettings.mdTitle and collectionSettings.mdTitle ~= "" then
            useTitleFormat = collectionSettings.mdTitle
        end
        if collectionSettings.mdDescription and collectionSettings.mdDescription ~= "" then
            useCaptionFormat = collectionSettings.mdDescription
        end
    end

    if useTitleFormat and useTitleFormat ~= "" then
        metaData.Title = utils.setCustomMetadata(lrPhoto, useTitleFormat)
    else
        metaData.Title = lrPhoto:getFormattedMetadata("title") or ""
    end

    if useCaptionFormat and useCaptionFormat ~= "" then
        metaData.Caption = utils.setCustomMetadata(lrPhoto, useCaptionFormat)
    else
        metaData.Caption = lrPhoto:getFormattedMetadata("caption") or ""
    end

    metaData.Creator = lrPhoto:getFormattedMetadata("creator") or ""
    metaData.fileName = lrPhoto:getFormattedMetadata("fileName") or ""

    -- find a populated date field
    local dtOriginal = lrPhoto:getRawMetadata("dateTimeOriginal")
    local dtDigitized = lrPhoto:getRawMetadata("dateTimeDigitized")
    local dt = lrPhoto:getRawMetadata("dateTime")
    local rawDate = nil
    if dtOriginal and dtOriginal ~= 0 then
        rawDate = dtOriginal
    elseif dtDigitized and dtDigitized ~= 0 then
        rawDate = dtDigitized
    elseif dt and dt ~= 0 then
        rawDate = dt
    end
    if not rawDate then
        -- last try - get the source file creation date
        local sourceFile = lrPhoto:getRawMetadata("path")
        if LrFileUtils.exists(sourceFile) then
            rawDate = LrFileUtils.fileAttributes(sourceFile).fileCreationDate
        end
    end
    local useDate = LrDate.timeToUserFormat(rawDate, "%Y-%m-%d %H:%M:%S")
    metaData.dateCreated = useDate or ""


    metaData.tagString = utils.BuildTagString(publishSettings, lrPhoto, collectionSettings)

    -- GPS coordinates
    local gps = lrPhoto:getRawMetadata("gps")
    if gps then
        metaData.latitude = gps.latitude
        metaData.longitude = gps.longitude
    end
    return metaData
end

-- *************************************************
local function normaliseId(id)
    -- Normalise IDs for consistent comparison
    if id == nil then return nil end
    return tostring(id)
end


-- *************************************************
function utils.normaliseWord(word)
    -- Normalise Name for consistent comparison
    -- handles accents etc
    local accentMap = {
        ["à"] = "a",
        ["á"] = "a",
        ["â"] = "a",
        ["ã"] = "a",
        ["ä"] = "a",
        ["å"] = "a",
        ["À"] = "a",
        ["Á"] = "a",
        ["Â"] = "a",
        ["Ã"] = "a",
        ["Ä"] = "a",
        ["Å"] = "a",

        ["è"] = "e",
        ["é"] = "e",
        ["ê"] = "e",
        ["ë"] = "e",
        ["È"] = "e",
        ["É"] = "e",
        ["Ê"] = "e",
        ["Ë"] = "e",

        ["ì"] = "i",
        ["í"] = "i",
        ["î"] = "i",
        ["ï"] = "i",
        ["Ì"] = "i",
        ["Í"] = "i",
        ["Î"] = "i",
        ["Ï"] = "i",

        ["ò"] = "o",
        ["ó"] = "o",
        ["ô"] = "o",
        ["õ"] = "o",
        ["ö"] = "o",
        ["Ò"] = "o",
        ["Ó"] = "o",
        ["Ô"] = "o",
        ["Õ"] = "o",
        ["Ö"] = "o",

        ["ù"] = "u",
        ["ú"] = "u",
        ["û"] = "u",
        ["ü"] = "u",
        ["Ù"] = "u",
        ["Ú"] = "u",
        ["Û"] = "u",
        ["Ü"] = "u",

        ["ý"] = "y",
        ["ÿ"] = "y",
        ["Ý"] = "y",

        ["ç"] = "c",
        ["Ç"] = "c",
        ["ñ"] = "n",
        ["Ñ"] = "n",

        ["œ"] = "oe",
        ["Œ"] = "oe",
        ["æ"] = "ae",
        ["Æ"] = "ae",
    }

    if not word or word == "" then
        return ""
    end

    -- lowercase first
    word = word:lower()

    -- replace accented characters
    word = word:gsub("[%z\1-\127\194-\244][\128-\191]*", function(c)
        return accentMap[c] or c
    end)

    -- normalize whitespace
    word = word:gsub("%s+", " ")
    word = word:gsub("^%s+", ""):gsub("%s+$", "")

    return word
end

-- ************************************************
function utils.getValidMetadataTokens()
    local formattedTokenTable = {

        -- Formatted metadata tokens
        -- Keywords
        keywordTags = true,
        keywordTagsForExport = true,

        -- File info
        fileName = true,
        preservedFileName = true,
        copyName = true,
        folderName = true,
        fileSize = true,
        fileType = true,

        -- Rating & labels
        rating = true,
        label = true,
        -- Descriptive
        title = true,
        caption = true,

        -- Dimensions
        dimensions = true,
        croppedDimensions = true,

        -- Exposure
        exposure = true,
        shutterSpeed = true,
        aperture = true,
        brightnessValue = true,
        exposureBias = true,
        flash = true,
        exposureProgram = true,
        meteringMode = true,
        isoSpeedRating = true,
        focalLength = true,
        focalLength35mm = true,
        lens = true,
        subjectDistance = true,

        -- Dates
        dateTimeOriginal = true,
        dateTimeDigitized = true,
        dateTime = true,
        -- Camera
        cameraMake = true,
        cameraModel = true,
        cameraSerialNumber = true,

        -- Creator / software
        artist = true,
        software = true,

        -- GPS
        gps = true,
        gpsAltitude = true,

        -- IPTC creator fields
        creator = true,
        creatorJobTitle = true,
        creatorAddress = true,
        creatorCity = true,
        creatorStateProvince = true,
        creatorPostalCode = true,
        creatorCountry = true,
        creatorPhone = true,
        creatorEmail = true,
        creatorUrl = true,

        -- IPTC content
        headline = true,
        iptcSubjectCode = true,
        descriptionWriter = true,
        iptcCategory = true,
        iptcOtherCategories = true,
        dateCreated = true,
        intellectualGenre = true,
        scene = true,

        -- Location shown
        location = true,
        city = true,
        stateProvince = true,
        country = true,
        isoCountryCode = true,

        -- Rights / usage
        jobIdentifier = true,
        instructions = true,
        provider = true,
        source = true,
        copyright = true,
        copyrightState = true,
        rightsUsageTerms = true,
        copyrightInfoUrl = true,

        -- People / events
        personShown = true,
        nameOfOrgShown = true,
        codeOfOrgShown = true,
        event = true,

        -- Locations (tables)
        locationCreated = true,
        locationShown = true,

        -- Artwork / objects
        artworksShown = true,

        -- Model release
        additionalModelInfo = true,
        modelAge = true,
        minorModelAge = true,
        modelReleaseStatus = true,
        modelReleaseID = true,

        -- Image supplier / registry
        imageSupplier = true,
        imageSupplierImageId = true,
        registryId = true,

        -- Image sizing
        maxAvailWidth = true,
        maxAvailHeight = true,

        -- Source & creators
        sourceType = true,
        imageCreator = true,

        -- Rights / licensing (PLUS)
        copyrightOwner = true,
        licensor = true,
        propertyReleaseID = true,
        propertyReleaseStatus = true,

        -- Identifiers
        digImageGUID = true,
        plusVersion = true,

        gpsImgDirection = true,

        altTextAccessibility = true,
        extDescrAccessibility = true,
    }
    local rawTokenTable = {
        -- Raw metadata tokens
        -- Core (SDK ≤ 1.x)
        fileSize = true,
        rating = true,
        dimensions = true,
        croppedDimensions = true,
        shutterSpeed = true,
        aperture = true,
        exposureBias = true,
        flash = true,
        isoSpeedRating = true,
        focalLength = true,
        focalLength35mm = true,
        dateTimeOriginal = true,
        dateTimeDigitized = true,
        dateTime = true,
        gps = true,
        gpsAltitude = true,
        countVirtualCopies = true,
        virtualCopies = true,
        masterPhoto = true,
        isVirtualCopy = true,
        countStackInFolderMembers = true,
        stackInFolderMembers = true,
        isInStackInFolder = true,
        stackInFolderIsCollapsed = true,
        stackPositionInFolder = true,
        topOfStackInFolderContainingPhoto = true,
        colorNameForLabel = true,

        -- SDK ≥ 2.0
        fileFormat = true,
        width = true,
        height = true,
        aspectRatio = true,
        isCropped = true,
        dateTimeOriginalISO8601 = true,
        dateTimeDigitizedISO8601 = true,
        dateTimeISO8601 = true,
        lastEditTime = true,
        editCount = true,
        copyrightState = true,

        -- SDK ≥ 3.0
        uuid = true,
        path = true,
        isVideo = true,
        durationInSeconds = true,
        keywords = true,
        customMetadata = true,

        -- SDK ≥ 4.0
        pickStatus = true,

        -- SDK ≥ 4.1
        trimmedDurationInSeconds = true,
        durationRatio = true,
        trimmedDurationRatio = true,
        locationIsPrivate = true,

        -- SDK ≥ 5.0
        smartPreviewInfo = true,

        -- SDK ≥ 6.0
        gpsImgDirection = true,

        -- SDK ≥ 12.1
        bitDepth = true,

        -- SDK ≥ 13.2 (Accessibility)
        --RAW_altTextAccessibility = true,
        --RAW_extDescrAccessibility = true,

        -- SDK ≥ 13.3
        isExported = true,

    }
    return formattedTokenTable, rawTokenTable
end

-- ************************************************
local function safeGetMetadata(lrPhoto, key, mdType)
    local value = key

    if mdType == "F" then
        value = lrPhoto:getFormattedMetadata(key)
        return value
    end
    if mdType == "R" then
        value = lrPhoto:getRawMetadata(key)
        return value
    end

    return value
end

-- ************************************************
function utils.setCustomMetadata(lrPhoto, mdTemplate)
    -- set custom metadata based on template string
    local metaStr = mdTemplate
    local formattedTokenTable, rawTokenTable = utils.getValidMetadataTokens()

    -- find all {{ }} tokens in the string
    for token in string.gmatch(metaStr, "{{(.-)}}") do
        local replaceValue
        if string.sub(token, 1, 4) == "RAW_" then
            -- raw metadata token
            local rawToken = string.sub(token, 5)
            if rawTokenTable[rawToken] then
                replaceValue = safeGetMetadata(lrPhoto, rawToken, "R")
            else
                replaceValue = "{{" .. token .. "}} not recognised"
            end
        elseif string.sub(token, 1, 4) == "FMT_" then
            -- formatted metadata token
            local fmtToken = string.sub(token, 5)
            if formattedTokenTable[fmtToken] then
                replaceValue = safeGetMetadata(lrPhoto, fmtToken, "F")
            else
                replaceValue = "{{" .. token .. "}} not recognised"
            end
        else
            -- check both formatted and raw token tables
            -- prefer formatted if both exist
            if formattedTokenTable[token] then
                replaceValue = safeGetMetadata(lrPhoto, token, "F")
            elseif rawTokenTable[token] then
                replaceValue = safeGetMetadata(lrPhoto, token, "R")
            else
                replaceValue = "{{" .. token .. "}} not recognised"
            end
        end
        -- ensure replaceValue is string
        if type(replaceValue) ~= "string" then
            replaceValue = utils.serialiseVar(replaceValue)
        end
        -- replace token with value
        metaStr = string.gsub(metaStr, "{{" .. token .. "}}", replaceValue)
    end

    return metaStr
end

-- ************************************************
function utils.makePathKey(name)
    -- trim
    name = name:gsub("^%s+", ""):gsub("%s+$", "")

    -- normalize internal whitespace
    name = name:gsub("%s+", " ")

    -- replace path separator with lookalike or token
    name = name:gsub("/", "∕") -- second / is a U+2215 division slash

    return name
end

-- *************************************************
function utils.findPhotoInCollectionSet(pubCollOrSet, selPhoto)
    -- recursivly search published collection set hierarchy for a photo and return publishedphoto object
    --log:info("utils.findPhotoInCollectionSet - pubCollOrSet " .. pubCollOrSet:getName() .. ", selPhoto " .. selPhoto.localIdentifier)

    if pubCollOrSet:type() == "LrPublishedCollection" then
        --log:info("utils.findPhotoInCollectionSet - searching in LrPublishedCollection " .. pubCollOrSet:getName())
        -- publishedcollection - look for photo
        local publishedPhotos = pubCollOrSet:getPublishedPhotos()
        local thisPubPhoto = nil
        for p, pubPhoto in pairs(publishedPhotos) do
            local thisPhoto = pubPhoto:getPhoto()
            if thisPhoto.localIdentifier == selPhoto.localIdentifier then
                thisPubPhoto = pubPhoto
                return thisPubPhoto
            end
        end
    end

    if pubCollOrSet:type() == "LrPublishedCollectionSet" then
        -- publishedcollectionset - Search child collections recursively
        if pubCollOrSet:getChildCollections() then
            --log:info("utils.findPhotoInCollectionSet - searching in child collections of " .. pubCollOrSet:getName())
            local childColls = pubCollOrSet:getChildCollections()
            if childColls then
                for _, childCol in ipairs(childColls) do
                    local thisPubPhoto = utils.findPhotoInCollectionSet(childCol, selPhoto)
                    if thisPubPhoto then
                        return thisPubPhoto
                    end
                end
            end
        end
        -- search child collection sets
        if pubCollOrSet:getChildCollectionSets() then
            --log:info("utils.findPhotoInCollectionSet - searching in child collection sets of " .. pubCollOrSet:getName())
            local childSets = pubCollOrSet:getChildCollectionSets()
            if childSets then
                for _, childSet in pairs(childSets) do
                    local thisPubPhoto = utils.findPhotoInCollectionSet(childSet, selPhoto)
                    if thisPubPhoto then
                        return thisPubPhoto
                    end
                end
            end
        end
    end
end

-- *************************************************
function utils.recursePubCollectionSets(collNode, allSets)
    -- Recursively search for all published collection sets

    if collNode:type() == 'LrPublishedCollectionSet' then
        table.insert(allSets, collNode)
    end

    -- Search child sets recursively
    if collNode:getChildCollectionSets() then
        local collSets = collNode:getChildCollectionSets()
        if collSets then
            for _, set in ipairs(collSets) do
                local thisSet = utils.recursePubCollectionSets(set, allSets)
            end
        end
    end
    return allSets
end

-- *************************************************
function utils.recursivePubCollectionSearchByRemoteID(collNode, findID)
    -- Recursively search for a published collection or published collection set matching a given remoteId (string or number)

    -- Check this collNode if it has a remote ID (only if collNode is a collection or set)
    if collNode:type() == 'LrPublishedCollection' or collNode:type() == 'LrPublishedCollectionSet' then
        local thisID = collNode:getRemoteId()
        if thisID == findID then
            return collNode
        end
    end
    -- Search immediate child collections
    local children = collNode:getChildCollections()
    if children then
        if children then
            for _, coll in ipairs(children) do
                local type = coll:type()
                local thisID = coll:getRemoteId()
                if thisID == findID then
                    -- this collection matches
                    return coll
                end
            end
        end
    end

    -- Search child sets recursively
    if collNode:getChildCollectionSets() then
        local collSets = collNode:getChildCollectionSets()
        if collSets then
            for _, set in ipairs(collSets) do
                local foundSet = utils.recursivePubCollectionSearchByRemoteID(set, findID)
                if foundSet then
                    -- this set matches
                    return foundSet
                end
            end
        end
    end
    -- nothing found
    return nil
end

-- *************************************************
function utils.findPublishNodeByName(service, name)
    -- call utils.recursiveSearch(service, normaliseId(name))
    if not service or not name then
        return nil
    end
    return utils.recursiveSearch(service, normaliseId(name))
end

-- *************************************************
-- http utils
-- *************************************************
function utils.urlEncode(str)
    -- urlencode a string

    if str then
        str = string.gsub(str, "\n", "\r\n")
        str = string.gsub(str, "([^%w _%%%-%.~])",
            function(c) return string.format("%%%02X", string.byte(c)) end)
        str = string.gsub(str, " ", "+")
    end
    return str
end

-- *************************************************
function utils.buildGet(url, params)
    -- Helper to build GET URL with params
    local encoded = {}
    for k, param in pairs(params) do
        local name = utils.urlEncode(param.name) or ""
        local value = utils.urlEncode(param.value) or ""
        table.insert(encoded, name .. "=" .. value)
    end
    return url .. "&" .. table.concat(encoded, "&")
end

-- *************************************************
function utils.buildPost(params)
    -- Helper to build urlencoded POST params
    local post = {}
    for k, v in pairs(params) do
        table.insert(post, k .. "=" .. utils.urlEncode(v))
    end
    return table.concat(post, "&")
end

-- *************************************************
function utils.buildPostBodyFromParams(params)
    -- Helper to build urlencoded POST params
    -- take param table with name value pairs and return urlencoded string

    local parts = {}
    for _, pair in ipairs(params) do
        local name  = utils.urlEncode(pair.name or "")
        local value = utils.urlEncode(pair.value or "")
        table.insert(parts, string.format("%s=%s", name, value))
    end
    return table.concat(parts, "&")
end

-- *************************************************
function utils.buildHeader(params)
    -- Helper to build GET URL with params

    --[[
    local header = {}
    for k, param in pairs(params) do
        local name = param.name
able.concat(post, "&")        local value = param.value
        table.insert(header, name .. "=" ..value)
    end
    return table.concat(header, "&")
    ]]
    return params
end

-- *************************************************
function utils.mergeSplitCookies(headers)
    -- fix issue where LrHttp splits headers on commas, breaking some date values in cookies

    local merged = {}
    local lastWasCookie = false

    for _, h in ipairs(headers or {}) do
        if h.field:lower() == "set-cookie" then
            if lastWasCookie and h.value:match("^%s*%d%d%s") then
                -- This looks like a continuation of an Expires date (e.g. "Thu, 01 Jan 1970...")
                merged[#merged].value = merged[#merged].value .. ", " .. h.value
            else
                table.insert(merged, { field = h.field, value = h.value })
            end
            lastWasCookie = true
        else
            lastWasCookie = false
        end
    end

    return merged
end

-- *************************************************
function utils.extract_cookies(raw)
    -- Helper function to parse Set-Cookie headers into "key=value" pairs

    local cookies = {}
    -- Split by comma to separate multiple Set-Cookie headers
    for _, cookieStr in ipairs(raw) do
        -- A cookie string looks like: "SESSIONID=abc123; Path=/; HttpOnly"
        local firstPart = cookieStr:match("^[^;]+") -- take only before first ";"
        if firstPart then
            local k, v = firstPart:match("^%s*([^=]+)=(.*)$")
            if k and v then
                cookies[k] = v
            end
        end
    end
    return cookies
end

-- *************************************************
function utils.getLogfilePath()
    -- get logfile path based on os and version
    local filename = 'PiwigoPublishPlugin.log'
    local macPath14 = LrPathUtils.getStandardFilePath('home') .. "/Library/Logs/Adobe/Lightroom/LrClassicLogs/"
    local winPath14 = LrPathUtils.getStandardFilePath('home') ..
        "\\AppData\\Local\\Adobe\\Lightroom\\Logs\\LrClassicLogs\\"
    local macPathOld = LrPathUtils.getStandardFilePath('documents') .. "/LrClassicLogs/"
    local winPathOld = LrPathUtils.getStandardFilePath('documents') .. "\\LrClassicLogs\\"

    local lightroomVersion = LrApplication.versionTable()

    if lightroomVersion.major >= 14 then
        if MAC_ENV then
            return macPath14 .. filename
        else
            return winPath14 .. filename
        end
    else
        if MAC_ENV then
            return macPathOld .. filename
        else
            return winPathOld .. filename
        end
    end
end

-- *************************************************
function utils.pwBusyMessage(callingFunction, displayFunction)
    -- display Piwigo Busy message

    LrDialogs.message("Piwigo Publisher is busy. Please try " .. displayFunction .. " later.")
end

-- *************************************************
function utils.extractPwImageIdFromUrl(url, expectedHost)
    -- Extracts the Piwigo image_id from a URL like "http://host/picture.php?/822/..."
    -- Verifies that the URL matches the expected host
    if not url or url == "" then return nil end
    if expectedHost and not url:find(expectedHost, 1, true) then return nil end

    local imageId = url:match("picture%.php%?/(%d+)")
    return imageId
end

-- *************************************************
function utils.findExistingPwImageId(publishService, lrPhoto, excludeCollection)
    -- Searches if this LR photo is already published in another collection of the same service
    -- Returns the Piwigo remoteId if found, nil otherwise

    -- excludeCollection is an optional parameter -
    -- if provided, this collection will be skipped in the search to avoid finding the same photo in the current collection when checking for duplicates

    local foundPubPhoto = nil
    local foundPubCollection = nil
    local pubPhotoExists = false
    local excludeId = excludeCollection and excludeCollection.localIdentifier


    local function searchInCollection(collection)
        if foundPubPhoto then return end
        if excludeId and collection.localIdentifier == excludeId then
            -- skip excludeCollection
            return
        end

        local pubPhotos = collection:getPublishedPhotos()
        for _, pubPhoto in ipairs(pubPhotos) do
            if pubPhoto:getPhoto().localIdentifier == lrPhoto.localIdentifier then
                local rid = pubPhoto:getRemoteId()
                if rid and rid ~= "" then
                    foundPubPhoto = pubPhoto
                    foundPubCollection = collection
                    pubPhotoExists = true
                    return
                end
            end
        end
    end

    local function searchInSet(collectionSet)
        if foundPubPhoto then return end
        -- Search in child collections
        local childColls = collectionSet:getChildCollections()
        if childColls then
            for _, coll in ipairs(childColls) do
                searchInCollection(coll)
                if foundPubPhoto then return end
            end
        end
        -- Search in child sets (recursive)
        local childSets = collectionSet:getChildCollectionSets()
        if childSets then
            for _, childSet in ipairs(childSets) do
                searchInSet(childSet)
                if foundPubPhoto then return end
            end
        end
    end

    -- Start search from service root
    searchInSet(publishService)

    return pubPhotoExists, foundPubPhoto, foundPubCollection
end

-- *************************************************
function utils.buildAlbumSummary(publishService)
    -- Recursively build a tree of collection sets and collections with photo counts.
    -- Returns a flat list of display nodes, each being either a "set" (parent) or "collection" (leaf).
    -- Set nodes include aggregated sub-totals. Collection nodes include individual counts.
    -- Returns: { nodes = { ... }, totals = {published, modified, new} }
    --   node fields: type ("set"|"collection"), name, path, depth, published, modified, new

    local nodes = {}
    local totals = { published = 0, modified = 0, new = 0 }

    local function countCollection(collection)
        local published, modified, new = 0, 0, 0
        local pubPhotos = collection:getPublishedPhotos()
        for _, pubPhoto in ipairs(pubPhotos) do
            local remoteId = pubPhoto:getRemoteId()
            if not remoteId or remoteId == "" then
                new = new + 1
            elseif pubPhoto:getEditedFlag() then
                modified = modified + 1
            else
                published = published + 1
            end
        end
        return published, modified, new
    end

    local function collectFromSet(collectionSet, path, depth)
        local name = collectionSet:getName()
        local fullPath = path ~= "" and (path .. " / " .. name) or name
        local setPub, setMod, setNew = 0, 0, 0
        local childNodes = {}

        -- Child collections
        local childColls = collectionSet:getChildCollections()
        if childColls then
            for _, coll in ipairs(childColls) do
                local p, m, n = countCollection(coll)
                if p > 0 or m > 0 or n > 0 then
                    table.insert(childNodes, {
                        type = "collection",
                        name = coll:getName(),
                        path = fullPath .. " / " .. coll:getName(),
                        depth = depth + 1,
                        published = p,
                        modified = m,
                        new = n,
                    })
                    setPub = setPub + p
                    setMod = setMod + m
                    setNew = setNew + n
                end
            end
        end

        -- Child sets (recursive)
        local childSets = collectionSet:getChildCollectionSets()
        if childSets then
            for _, childSet in ipairs(childSets) do
                local subNodes, sp, sm, sn = collectFromSet(childSet, fullPath, depth + 1)
                for _, node in ipairs(subNodes) do
                    table.insert(childNodes, node)
                end
                setPub = setPub + sp
                setMod = setMod + sm
                setNew = setNew + sn
            end
        end

        -- Only emit if this set has content
        local result = {}
        if setPub > 0 or setMod > 0 or setNew > 0 then
            -- Insert set header with sub-totals
            table.insert(result, {
                type = "set",
                name = name,
                path = fullPath,
                depth = depth,
                published = setPub,
                modified = setMod,
                new = setNew,
            })
            -- Then all children
            for _, node in ipairs(childNodes) do
                table.insert(result, node)
            end
        end

        return result, setPub, setMod, setNew
    end

    -- Root-level collections (no parent set)
    local childColls = publishService:getChildCollections()
    if childColls then
        for _, coll in ipairs(childColls) do
            local p, m, n = countCollection(coll)
            if p > 0 or m > 0 or n > 0 then
                table.insert(nodes, {
                    type = "collection",
                    name = coll:getName(),
                    path = coll:getName(),
                    depth = 0,
                    published = p,
                    modified = m,
                    new = n,
                })
                totals.published = totals.published + p
                totals.modified = totals.modified + m
                totals.new = totals.new + n
            end
        end
    end

    -- Root-level sets
    local childSets = publishService:getChildCollectionSets()
    if childSets then
        for _, set in ipairs(childSets) do
            local subNodes, sp, sm, sn = collectFromSet(set, "", 0)
            for _, node in ipairs(subNodes) do
                table.insert(nodes, node)
            end
            totals.published = totals.published + sp
            totals.modified = totals.modified + sm
            totals.new = totals.new + sn
        end
    end

    return { nodes = nodes, totals = totals }
end

return utils
