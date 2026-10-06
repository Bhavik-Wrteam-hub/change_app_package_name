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
      ref: v1.7.0
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

The command shows what it changed and what to do next:

```
📦 Changing package name to com.yourcompany.eschool
   Android + iOS

🤖 Android · School Builder layout
   📝 android/app/build.gradle
      applicationId: com.wrteam.saas.school → com.yourcompany.eschool
      namespace: com.wrteam.saas.school → com.yourcompany.eschool
   📝 android/app/src/main/AndroidManifest.xml
      package: com.wrteam.saas.school → com.yourcompany.eschool
   📝 android/app/src/main/kotlin/com/wrteam/saas/school/MainActivity.kt
      package: com.wrteam.saas.school → com.yourcompany.eschool
      moved to: android/app/src/main/kotlin/com/wrteam/saas/school → android/app/src/main/kotlin/com/yourcompany/eschool

🍎 iOS · School Builder layout
   📝 ios/Flutter/Debug.xcconfig
      SCHOOL_BUNDLE_ID: com.wrteam.eschool.saas → com.yourcompany.eschool
   📝 ios/Flutter/Release.xcconfig
      SCHOOL_BUNDLE_ID: com.wrteam.eschool.saas → com.yourcompany.eschool

✅ Package name updated.
```

Emoji and colour are used where the terminal shows them. For plain text, in a script or a log, add `--plain`:

```
dart run change_app_package_name:main com.new.package.name --plain
```

## What It Changes

The command looks at the project and picks the layout by itself.

### School Builder layout (eSchool SaaS v1.12.0 and later)

| Platform | File | What changes |
|----------|------|--------------|
| Android | `android/app/build.gradle` | The application id: the second value of `getProperty('applicationId', '...')` |
| Android | `android/app/build.gradle` | `namespace` |
| Android | `AndroidManifest.xml` (main, debug, profile) | The `package` of the `<manifest>` tag, where it has one |
| Android | Kotlin and Java sources under `android/app/src/main/` | Their `package`, the imports of it, and the folder they are in |
| iOS | `ios/Flutter/Debug.xcconfig` and `ios/Flutter/Release.xcconfig` | The `SCHOOL_BUNDLE_ID` line |

So after a rename no file of the project still shows the old name, apart from the Firebase files, which Firebase regenerates.

- `ios/Runner.xcodeproj/project.pbxproj` keeps reading `$(SCHOOL_BUNDLE_ID)`, so the Multi-School add-on can still give each school its own bundle id.
- The application id and the bundle id are the same values the School Builder writes with **Save to project**, so the command and the builder always agree. A school build overrides them and never reads the code's package, so it works the same before and after.

#### Names with reserved words

A name such as `com.new.package.name` is a valid application id, but the Android build refuses it as a `namespace`, because `new` and `package` are reserved words in Java. For such a name the command renames the application id, which is the name the stores and Firebase use, and leaves the code's package as it is. It says so in its output, and the project keeps building.

Words that only Kotlin reserves, such as `in` in `in.co.school.app`, are fine: the command writes them in backticks in Kotlin sources.

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
