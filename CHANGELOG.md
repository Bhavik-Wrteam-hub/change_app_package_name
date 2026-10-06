## [1.6.0] - (October 06, 2026)

Fork for the eSchool SaaS apps.

* Support the School Builder layout (eSchool SaaS v1.12.0 and later): the Android application id is the fallback of `getProperty('applicationId', '...')` in `build.gradle`, and the iOS bundle id is `SCHOOL_BUNDLE_ID` in `Debug.xcconfig` and `Release.xcconfig`. Version 1.5.0 stopped with `applicationId not found` on Android and overwrote the link in `project.pbxproj` on iOS.
* Put the `$(SCHOOL_BUNDLE_ID)` link back in a `project.pbxproj` that version 1.5.0 overwrote.
* Check both platforms before writing either, so a project is never left half-renamed.
* Validate the package name for the platforms being renamed.
* Report Firebase files that are still for the old ids, with the `flutterfire configure` command to regenerate them.
* Add `--dry-run` and `--help`, and return a non-zero exit code on failure.
* Standard layout: only replace the `package="..."` attribute of a manifest, not the rest of the line.
* Add a test suite.

## [1.5.0] - (February 23, 2025)

* Add support for Flutter 3.29.0 for Android build.gradle.kts file structure.

## [1.4.0] - (September 20, 2024)

* Specify which platform they want to rename the package for. Thanks [@moha-b](moha-b) #43

## [1.3.0] - (July 08, 2024)

* iOS support added

## [1.2.0] - (Jun 03, 2024)

* Support Flutter 3.22.0
* Fix regex to only replace package name in manifest files
* Fix #26 where kotlin directory does not exist so it should not throw error.
* add extra check to make sure the old application id is found before proceeding to next steps.

## [1.1.0] - (April 08, 2021)

* Change MainActivity mechanism to handle different locations.

## [1.0.0] - (April 08, 2021)

* Added null safety.

## [0.1.3] - (April 08, 2021)

* Add extra Files checks. Hopefully fixes #7

## [0.1.2] - (March 16, 2020)

* Bug Fix in README.md

## [0.1.1] - (March 16, 2020)

* Update code as per pub.dev guidelines

## [0.1.0] - (March 16, 2020)

* Change Android Package Name with single command
