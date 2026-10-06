# Change App Package Name for Flutter

Change the Android application id and the iOS bundle id of a Flutter app with one command.

This is a fork of [atiqsamtia/change_app_package_name](https://github.com/atiqsamtia/change_app_package_name). It adds support for the **School Builder layout** used by the eSchool SaaS apps from v1.12.0, where the two ids are build settings that a school build overrides. Projects in the standard Flutter layout are renamed as before.

## How to Use

Add the package to `dev_dependencies:` in your `pubspec.yaml`:

```yaml
dev_dependencies:
  change_app_package_name:
    git:
      url: https://github.com/Bhavik-Wrteam-hub/change_app_package_name.git
      ref: v1.6.0
```

Update dependencies:

```
flutter pub get
```

Run this command from the project root to rename both platforms:

```
dart run change_app_package_name:main com.new.package.name
```

To rename only Android:

```
dart run change_app_package_name:main com.new.package.name --android
```

To rename only iOS:

```
dart run change_app_package_name:main com.new.package.name --ios
```

To see what would change without writing anything:

```
dart run change_app_package_name:main com.new.package.name --dry-run
```

Where `com.new.package.name` is the new package name that you want for your app.

## What It Changes

The command looks at the project and picks the layout by itself.

### School Builder layout (eSchool SaaS v1.12.0 and later)

| Platform | File | What changes |
|----------|------|--------------|
| Android | `android/app/build.gradle` | The second value of `getProperty('applicationId', '...')` |
| iOS | `ios/Flutter/Debug.xcconfig` and `ios/Flutter/Release.xcconfig` | The `SCHOOL_BUNDLE_ID` line |

Nothing else is touched. In particular:

- `namespace`, the `package` of `AndroidManifest.xml` and the Kotlin folder stay as they are. They name the code, not the app: the stores and Firebase only read the application id.
- `ios/Runner.xcodeproj/project.pbxproj` keeps reading `$(SCHOOL_BUNDLE_ID)`, so the Multi-School add-on can still give each school its own bundle id.

These are the same values the School Builder writes with **Save to project**, so the command and the builder always agree.

If version 1.5.0 of this command was run on the project, it wrote the bundle id into `project.pbxproj` and cut the link to `SCHOOL_BUNDLE_ID`. This version detects that and puts the link back.

### Standard Flutter layout

- [x] Update `AndroidManifest.xml` files for release, debug & profile
- [x] Update `build.gradle` or `build.gradle.kts`
- [x] Update the MainActivity file. Both java & kotlin supported.
- [x] Move the MainActivity file to the new package directory structure
- [x] Delete the old package name directory structure
- [x] Update the Product Bundle Identifier in iOS
  - if you have customized `CFBundleIdentifier` in `Info.plist`, it will not be updated. You have to update it manually.

## Package Name Rules

| Used for | Each part may contain |
|----------|-----------------------|
| Both platforms | Letters and digits, starting with a letter |
| `--android` only | Letters, digits and `_`, starting with a letter |
| `--ios` only | Letters, digits and `-` |

A name needs at least two parts, such as `com.yourcompany.app`. Lowercase is recommended, because the stores treat names that differ only in case as different apps.

## Nothing Is Half-Renamed

Both platforms are checked before either is written. If one of them can't be renamed, the command says why, changes nothing and exits with a non-zero code.

## After Renaming: Firebase

Firebase keeps its own copy of both ids. The command checks `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`, and when they are still for the old ids it prints the command to regenerate them:

```
flutterfire configure --project=<your-firebase-project-id> --android-package-name=com.new.package.name --ios-bundle-id=com.new.package.name
```

## Development

```
dart pub get
dart test
```

## Meta

Original package by Atiq Samtia – [@AtiqSamtia](https://twitter.com/atiqsamtia) – me@atiqsamtia.com

Distributed under the MIT license. See `LICENSE`.

Original: [https://github.com/atiqsamtia/change_app_package_name](https://github.com/atiqsamtia/change_app_package_name)
