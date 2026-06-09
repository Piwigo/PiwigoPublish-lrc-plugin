# Changelog
## [20260327.35]
### Fixed
Plugin extra options consolidated to single menu item in Library -> Plug-in Extras -> Piwigo Publisher Extra Options

### Added
Custom Sort Order optionally synchronised to Piwigo when used in LrC. Requires Photos sort order to be set to Manual on album in Piwigo. A Piwigo plugin is under development to automate this setting - in the meantime needs to be set in Piwigo Administration -> Albums -> Edit album

## [20260305.34]
### Fixed
Fix #45 Unable to remove photos from Piwigo
Associating an existing image with a new album should force re-upload of image if it had been changed in LrC since first upload to Piwigo
### Added
Image assoication behaviour made optional to allow per-album custom export settings
Fix #12 Feature request: Keyword removal by filtering when publising images to Piwigo
Fix #14 Incorporate per-album custom export settings

## [20260221.33] - 2026-02-21
### Fixed
Fix #52 New "private" album aren't private
Fix #57 Problem transferring album descriptions to Piwigo in LrC 15.2
### Added
GPS coordinates can now be sent to Piwigo without republishing image - via Send Metadata to Piwigo for Selected Photos option

## [20260208.32] - 2026-02-08
### Fixed
Fix #41 Issue with Import albums - public/private setting

## [20260207.31] - 2026-02-06
### Fixed
Problem with Clone Existing Publish Service - smart collections

## [20260206.30] - 2026-02-06
### Fixed
Fix #41 Problem with 'Clone Existing Publish Service - public/private setting

### Added
- Preparation for locatalistion

## [20260126.29] - 2026-01-26
### Fixed
Fix #41 Allow clone service to include unpublished photos from standard published collections

## [20260124.28] - 2026-01-24
### Added
 - Synchronisation of photos based on the Lr parameter: photoId, and Update system compatible with GitHub RCs. - PR (#40) - thank you @Gotcha26


## [20260122.27] - 2026-01-22
### Fixed
#37 An error occurred while deleting images
Fixed validation of Publish Service Description - now sets a default service name if left blank.
Removed default collection that was created when a new publish service is created

### Added
Option to clone an existing publish service, retaining Piwigo connection if present
Option to maintain public/private setting on albums

## [20260111.26] - 2026-01-09
### Fixed
Fix #30 Cannot get tag list from Piwigo - error 401. Incorrect error message fixed.

### Added
Comments synchronised between Piwigo and LrC

## [20260106.25] - 2026-01-06
### Fixed
Fix #27 - Album formatting lost on import to LrC

## [20260106.24] - 2026-01-06
### Fixed
Fix #23 - Keyword settings in publish service settings dialog get cut-off
Fix #21 - bad argument #1 to '?' - see readme note on embedded metadata


## [20260105.23] - 2026-01-05
### Fixed
Fix #24 rename album does not update custom metadata. Also fix error that incorrect albumname was used for metadata with special collections 
Fix regression introduced by 20260104.22 causing crash when creating new album or album set

## [20260104.22] - 2026-01-04
### Fixed
Changes to Category (album) visibility in Piwigo could cause duplicates to be created by plugin if a previously public album was changed to private in Piwigo and then a photo published to it. The plugin now effectively ignores public/private settings and can access all albums on the Piwigo host.

### Added
Album descriptions can be maintained by the plugin. Right-click on an album to display dialog where Album Description can be edited - see Readme for more information

## [20260102.21] - 2026-01-02
### Fixed
Fix #23 Check / link Piwigo Structure: mistake of using albums from other publishing setup from same site

## [20260101.20] - 2026-01-01
### Fixed
Fixed #13 - new option to allow different metadata to be used for title and description

### Added
New option in Lightroom Publishing Manager panel - Metadata Settings. Allows tokenised strings to be used for image Title and Description as sent to Piwigo - tokens idenfified by {{token}} will be subtituted for image specific values on export. Supports all metadata documented in photo:getFormattedMetadata and photo:getRawMetadata from the Lightroom Classic SDK. See Wiki for more information.

## [20251229.19] - 2025-12-29
Fixed #22 - Error 1003 - Keyword already exisits. Required normalisation of keywords - all lower case, remove accents etc - for comparison between LrC and Piwigo keyword names as Piwigo effectively does accent-folding + case-folding and Lrc retains original.

Fixed #16 (after re-opening) - New option to check local collection / set structure against existing Piwigo album structure - missing Piwigo albums will be created and incorrect links between collections / sets will be updated. Mis-named special collections will be renamed.

## [20251227.18] - 2025-12-27
### Fixed
Fixed #16 - When importing a smart collection album a publishing error occurs - Running Import Smart Collection Settings created a collection within the Publish Service but a corresponding Piwigo album wasn't. This fix checks for missing albums during the Publish process and creates them if needed

## [20251227.17] - 2025-12-27
Fixed bug introduced by fix in previous release

## [20251224.16] - 2025-12-24
### Added
- Custom metadata displaying details of most recent upload for an image is maintained. Note that if the same image is published via multiple instances of this plugin (for example to different Piwigo hosts) then only details of the most recent upload will be displayed. Details of the previous upload are overwritten. This metadata is for display / information purposes only so the overwrite has no functional impact. Images published with earlier versions of the plugin will not display the metadata - re-publishing them will refresh it. When an image is removed from a published collection this metadata is cleared, regardless of whether it has also been published via a different instance of this plugin.

### Fixed
Fixed #18 Setting up another publish service on a different catalogue generates an error message 'PiwigoAPI.lua 694 attempt to concatenate local statusDes (a nil value) - note this fixes the crash rather than the underlying issue that triggered the crash which is still being investigated

## [20251223.15] - 2025-12-23
### Fixed
- Set Piwigo Album Cover from Selected Photo would only allow setting the cover for the selected photo's album or immediate parent. This fix allow any album cover in the selected photo's album hierarchy to be set to the selected photo

## [20251219.14] - 2025-12-19
### Added
- A new menu item has been added Library->Plug-in Extras->Piwigo Publisher->Convert selected Published Collection to Published Collection Set.  This option enables a Publish Collection to be converted to a Publish Collection Set, enabling sub albums to be created under this album.

## [20251218.13] - 2025-12-18
### Fixed
- Send Metadata to Piwigo for Selected Photos crashed when photos weren't selected from a Publish Service
- Crash when imagick failed to process an uploaded photo correctly


## [20251216.12] - 2025-12-16
- Improve handling of Piwigo keywords

## [20251204.11] - 2025-12-04
### Fixed #7 Adding keywords to a photo directly via Piwigo API intermittently generates error 1003 Keyword already exists
- 

## [20251203.10] - 2025-12-03
### Added
- Metadata and keywords are sent directly to Piwigo without relying on exif/iptc
  - as part of a publish process or via a seperate menu option so a re-publish of a photo isn't required to change metadata.
  - Keyword synonyms and full keyword hierarchy can optionally be included
  - Include on Export option in LrC Keyword Tag editor is respected

## [20251201.9] - 2025-12-01
### Added
- Library -> Plug-in Extras menu item to set Piwigo album cover directly

## [20251201.8] - 2025-12-01
### Added
- Can set Piwigo album cover from plugin

## [20251130.7] - 2025-11-30
### Fixed
- Bug when deleting Special Collections removed incorrect album in Piwigo

## [20251129.6] - 2025-11-29
### Added
- Special Collections can be created, allowing Piwigo albums with sub-albums to also have photos published in them

## [20251129.5] - 2025-11-29
### Fixed
- Error on startup when no Piwigo hosts defined

## [20251128.4] - 2025-11-28
### Fixed
- non-unique album names within Piwigo Album hierarchy were not properly created during import albums process. See updated readme for more details on this.

## [20251127.3] - 2025-11-27
### Added
- Checked compatibility with Piwigo v16.0.0 and API Keys
- Missing albums are recreated (with a new Piwigo Cat ID) during Publish process

### Fixed
- Crashes when Piwigo albums are removed from Piwigo directly, leaving the Plugin collections inconsistent. 
- Inconsistent connection messages when multiple publish services using this plugin are created.
- Regression bug causing images to be duplicated rather then refreshed
- Correct behaviour when additional new publish services are created 
- refactored calls to LrHttp.get function

## [20251117.1] - 2025-11-17
### Added
- Check image presence on Piwigo during publish operation to prevent 404 error if previously published image is missing
- New versioning system based on date+release number

### Fixed
- Crashes due to concurrent Piwigo activities clashing. Attempting to carry out one of these operations whilst a publish operation active will result in a warning and the reversion of the changes:
    - reparent collection
    - rename collection
    - create Piwigo album
    - create collection set
