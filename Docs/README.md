# What is ravynOS? [![Build Status](https://api.cirrus-ci.com/github/ravynsoft/ravynos.svg?branch=main)](https://cirrus-ci.com/github/ravynsoft/ravynos) [![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](CODE_OF_CONDUCT.md)
### Don't speak English? Read this in: [Italiano](README.IT.md), [Türkçe](README.TR.md), [Deutsch](README.DE.md), [Indonesia](README.ID.md), [简体中文](README.zh_CN.md), [繁體中文](README.zh_TW.md), [Português do Brasil](README.pt_BR.md), [한국어](README.KR.md), [فارسی](README.FA.md), [Magyar](README.HU.md)

ravynOS is an open source OS project that aims to provide a similar experience and some compatibility with macOS on x86-64 (and eventually ARM) systems. It builds on the solid foundations of Darwin and FreeBSD, existing open source packages in the same space, and new code to fill the gaps.

The main design goals are:
- Source compatibility with macOS applications (i.e. you could compile a Mac application on ravynOS and run it). Binary compatibility eventually.
- Similar GUI metaphors and familiar UX (file manager, application launcher, top menu bar that reflects the open application, etc)
- Compatible with macOS folder layouts (/Library, /System, /Users, /Volumes, etc) and filesystems (HFS+, APFS) plus other useful filesystems like NTFS, ZFS.
- Self-contained applications in [App Bundles](https://developer.apple.com/documentation/foundation/bundle) with support for DMG files and other archive formats.
- Updated Unix environment with current tools, shells, and power user tools
- Pleasant to use, secure, stable, and performant

### Join us!

* Can you help build the dream? See the current projects/needs in [CONTRIBUTING.md](CONTRIBUTING.md)!
* Our [Discord](https://discord.com/invite/8caJbAGNwY) server.
* `#ravynOS-general:matrix.org` - join via [Element.io](https://app.element.io/#/room/%23ravynOS-general:matrix.org)

[![Packages hosted by: Cloudsmith](https://img.shields.io/badge/OSS%20hosting%20by-cloudsmith-blue?logo=cloudsmith&style=flat-square)](https://cloudsmith.com)
