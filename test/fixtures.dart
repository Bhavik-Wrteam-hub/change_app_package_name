import 'dart:io';

/// Project trees the command is run against, cut down from the real
/// eSchool SaaS apps to the lines the command reads.

const String studentAndroidId = 'com.wrteam.saas.school';
const String studentIosId = 'com.wrteam.eschool.saas';
const String staffId = 'com.wrteam.saas.staff';

String schoolBuilderGradle(String applicationId) => '''
plugins {
    id "com.android.application"
    id "kotlin-android"
}

def schoolOverlay = null
def schoolOverlayPath = project.findProperty('schoolOverlay')?.toString()?.trim()
def schoolProperties = new Properties()

def schoolApplicationId = schoolProperties.getProperty('applicationId', '$applicationId')
def schoolAppName = schoolProperties.getProperty('appName', 'eSchool Saas')

android {
    defaultConfig {
        // Per-school value from addon/config/schools.json; falls back to the stock id.
        applicationId schoolApplicationId
        manifestPlaceholders += [appName: schoolAppName]
    }
    namespace '$applicationId'
}
''';

String standardGradle(String applicationId) => '''
android {
    namespace "$applicationId"
    defaultConfig {
        applicationId "$applicationId"
        minSdkVersion 21
    }
}
''';

String manifest(String package) => '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="$package">
    <application android:label="\${appName}">
        <activity android:name=".MainActivity" />
    </application>
    <!-- Required to query activities that can process text, see:
         https://developer.android.com/training/package-visibility -->
</manifest>
''';

String mainActivity(String package) => '''
package $package

import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity()
''';

String xcconfig(String mode, String bundleId) => '''
#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.$mode.xcconfig"
#include "Generated.xcconfig"

// School Builder addon: stock values, overridden by School.xcconfig during a
// school build. That include must stay last.
SCHOOL_BUNDLE_ID = $bundleId
SCHOOL_APP_DISPLAY_NAME = eschool Saas
SCHOOL_APP_BUNDLE_NAME = eSchool Saas

#include? "School.xcconfig"
''';

const String bundleIdReference = r'"$(SCHOOL_BUNDLE_ID)"';

/// [appBundleId] is the value of the three Runner configurations;
/// [testsBundleId] adds the three RunnerTests ones the Staff app has.
String pbxproj(String appBundleId, {String? testsBundleId}) {
  final buffer = StringBuffer('// !\$*UTF8*\$!\n{\n');
  for (final configuration in ['Profile', 'Debug', 'Release']) {
    buffer.write('''
		$configuration /* Runner */ = {
			buildSettings = {
				INFOPLIST_FILE = Runner/Info.plist;
				PRODUCT_BUNDLE_IDENTIFIER = $appBundleId;
				PRODUCT_NAME = "\$(TARGET_NAME)";
			};
		};
''');
    if (testsBundleId != null) {
      buffer.write('''
		$configuration /* RunnerTests */ = {
			buildSettings = {
				PRODUCT_BUNDLE_IDENTIFIER = $testsBundleId;
			};
		};
''');
    }
  }
  buffer.write('}\n');
  return buffer.toString();
}

String googleServices(List<String> packageNames) => '''
{
  "project_info": {"project_id": "demo-project"},
  "client": [
${packageNames.map((name) => '    {"client_info": {"android_client_info": {"package_name": "$name"}}}').join(',\n')}
  ]
}
''';

String googleServiceInfo(String bundleId) => '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<key>BUNDLE_ID</key>
	<string>$bundleId</string>
</dict>
</plist>
''';

class Project {
  final Directory root;

  Project._(this.root);

  factory Project.empty() =>
      Project._(Directory.systemTemp.createTempSync('rename_test_'));

  void delete() => root.deleteSync(recursive: true);

  File file(String path) => File('${root.path}/$path');

  bool exists(String path) => file(path).existsSync();

  String read(String path) => file(path).readAsStringSync();

  void write(String path, String contents) => file(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);

  /// Every file of the project by relative path, to compare whole trees.
  Map<String, String> snapshot() => {
        for (final entity in root.listSync(recursive: true))
          if (entity is File)
            entity.path.substring(root.path.length + 1):
                entity.readAsStringSync(),
      };

  void _android(String gradle, String applicationId) {
    final folder = applicationId.replaceAll('.', '/');
    write('android/app/build.gradle', gradle);
    write('android/app/src/main/AndroidManifest.xml', manifest(applicationId));
    write('android/app/src/debug/AndroidManifest.xml',
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="$applicationId">\n</manifest>\n');
    write('android/app/src/main/kotlin/$folder/MainActivity.kt',
        mainActivity(applicationId));
  }

  /// The Student/Parent app: different ids on the two platforms.
  factory Project.student() {
    final project = Project.empty();
    project._android(schoolBuilderGradle(studentAndroidId), studentAndroidId);
    project.write(
        'ios/Flutter/Debug.xcconfig', xcconfig('debug', studentIosId));
    project.write(
        'ios/Flutter/Release.xcconfig', xcconfig('release', studentIosId));
    project.write(
        'ios/Runner.xcodeproj/project.pbxproj', pbxproj(bundleIdReference));
    project.write(
        'android/app/google-services.json', googleServices([studentAndroidId]));
    project.write(
        'ios/Runner/GoogleService-Info.plist', googleServiceInfo(studentIosId));
    return project;
  }

  /// The Staff/Teacher app: one id for both platforms, and test targets
  /// with a bundle id of their own.
  factory Project.staff() {
    final project = Project.empty();
    project._android(schoolBuilderGradle(staffId), staffId);
    project.write('ios/Flutter/Debug.xcconfig', xcconfig('debug', staffId));
    project.write('ios/Flutter/Release.xcconfig', xcconfig('release', staffId));
    project.write(
        'ios/Runner.xcodeproj/project.pbxproj',
        pbxproj(bundleIdReference,
            testsBundleId: 'com.example.eschoolSaasStaff.RunnerTests'));
    return project;
  }

  /// A project as `flutter create` lays it out, and as eSchool SaaS was
  /// before v1.12.0.
  factory Project.standard() {
    const id = 'com.example.old_app';
    final project = Project.empty();
    project._android(standardGradle(id), id);
    project.write(
        'ios/Runner.xcodeproj/project.pbxproj', pbxproj('com.example.oldApp'));
    return project;
  }
}
