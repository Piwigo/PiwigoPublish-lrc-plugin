# PiwigoPublish-lrc-plugin

A Lightroom Classic plugin which publishes images to a Piwigo host via the Piwigo API.

Please see the [Wiki](https://github.com/Piwigo/PiwigoPublish-lrc-plugin/wiki) for documentation

---

## Release Channels

This repository publishes two release channels:

- Modern channel (default): for Piwigo v16 and above, API-key-first support
- Legacy channel: for older Piwigo versions, maintenance fixes only

How to find the right release in GitHub Releases:

- Look for release titles starting with `MODERN -`
- Look for release titles starting with `LEGACY -`
- Read the first compatibility line in the release notes before installing
- Modern tags continue the existing date.build sequence (for example `v20260609.36`)
- The first modern release after the track split includes explicit migration notes and compatibility guidance

Release policy and workflow details are documented in [LEGACY-MAINTENANCE-POLICY.md](LEGACY-MAINTENANCE-POLICY.md).

---

## Disclaimer

With the exception of JSON.lua, Copyright 2010-2017 Jeffrey Friedl, which is released under a Creative Commons CC-BY "Attribution" License: http://creativecommons.org/licenses/by/3.0/deed.en_US, and md5.lua, Copyright (c) 2013 Enrique García Cota + Adam Baldwin + hanzao + Equi 4 Software which is released under an MIT license, this software is released under the GNU General Public License version 3 as published by the Free Software Foundation.
         
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <https://www.gnu.org/licenses/>.

---

## CREDITS

As a user of both Lightroom Classic and Piwigo, the ability use the powerful Publishing Service in LrC to keep my Piwigo galleries up to date is very appealing. I've been a long time user of a popular plugin that has been providing this functionality, but unfortunately since the version 15 release of LrC that has not been available. 

This plugin was developed to allow me to continue publishing to Piwigo from LrC, and I have looked at the work of others for help and ideas in developing this plugin. In particular, the following should be credited:

[All the contributers to Piwigo](https://piwigo.org/)

[Julien Moreau for contributing various improvements](https://julien-moreau.fr/)

[Jeffrey Friedl for JSON.lua](http://regex.info/blog/lua/json)

[Bastian Machek with his Immich Plugin](https://github.com/bmachek/lrc-immich-plugin)

[Min Idzelis with his Immich Plugin](https://github.com/midzelis/mi.Immich.Publisher)

