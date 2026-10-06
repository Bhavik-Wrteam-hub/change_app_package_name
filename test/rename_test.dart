import 'dart:io';

import 'package:change_app_package_name/android_rename_steps.dart';
import 'package:change_app_package_name/change_app_package_name.dart';
import 'package:change_app_package_name/ios_rename_steps.dart';
import 'package:change_app_package_name/output_style.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

const String newId = 'com.yourcompany.eschool';

/// What the School Builder add-on reads the two ids with
/// (addon/tools/defaultapp.py). The command must leave both readable.
final RegExp addonApplicationId =
    RegExp(r"getProperty\('applicationId',\s*'((?:\\.|[^'\\\n])*)'\)");
final RegExp addonBundleId =
    RegExp(r'^SCHOOL_BUNDLE_ID[ \t]*=[ \t]*([^\n]*?)[ \t]*$', multiLine: true);

class Run {
  final int exitCode;
  final List<String> lines;

  Run(this.exitCode, this.lines);

  String get output => lines.join('\n');
}

/// Runs the command as a script or a plain terminal sees it, unless a [style]
/// is given.
Future<Run> run(
  Project project,
  List<String> arguments, {
  OutputStyle style = OutputStyle.plain,
}) async {
  final lines = <String>[];
  final code = await ChangeAppPackageName.run(arguments,
      root: project.root, log: lines.add, style: style);
  return Run(code, lines);
}

void main() {
  late Project project;

  tearDown(() => project.delete());

  group('School Builder layout, Student/Parent app', () {
    setUp(() => project = Project.student());

    test('renames both platforms with one command', () async {
      final result = await run(project, [newId]);

      expect(result.exitCode, 0, reason: result.output);
      expect(
          addonApplicationId
              .firstMatch(project.read('android/app/build.gradle'))!
              .group(1),
          newId);
      for (final path in IosRenameSteps.PATH_XCCONFIGS) {
        expect(addonBundleId.allMatches(project.read(path)), hasLength(1));
        expect(addonBundleId.firstMatch(project.read(path))!.group(1), newId);
      }
    });

    test('changes nothing but the two ids', () async {
      final before = project.snapshot();
      await run(project, [newId]);
      final after = project.snapshot();

      expect(after.keys, before.keys, reason: 'no file is added or moved');
      final changed =
          before.keys.where((path) => before[path] != after[path]).toSet();
      expect(changed, {
        'android/app/build.gradle',
        'ios/Flutter/Debug.xcconfig',
        'ios/Flutter/Release.xcconfig',
      });
      expect(
        after['android/app/build.gradle'],
        before['android/app/build.gradle']!.replaceFirst(
            "getProperty('applicationId', '$studentAndroidId')",
            "getProperty('applicationId', '$newId')"),
        reason: 'namespace and every other line stay as they were',
      );
      expect(
        after['ios/Flutter/Release.xcconfig'],
        before['ios/Flutter/Release.xcconfig']!
            .replaceFirst(studentIosId, newId),
      );
    });

    test('keeps the hooks the add-on builds schools through', () async {
      await run(project, [newId]);

      expect(project.read('android/app/build.gradle'),
          contains("project.findProperty('schoolOverlay')"));
      expect(project.read('android/app/build.gradle'),
          contains('applicationId schoolApplicationId'));
      for (final path in IosRenameSteps.PATH_XCCONFIGS) {
        expect(project.read(path).trimRight(),
            endsWith('#include? "School.xcconfig"'));
      }
      expect(
          RegExp(RegExp.escape(
                  'PRODUCT_BUNDLE_IDENTIFIER = $bundleIdReference;'))
              .allMatches(project.read('ios/Runner.xcodeproj/project.pbxproj')),
          hasLength(3));
    });

    test('--android leaves iOS alone', () async {
      final before = project.snapshot();
      final result = await run(project, [newId, '--android']);
      final after = project.snapshot();

      expect(result.exitCode, 0);
      expect(before.keys.where((path) => before[path] != after[path]),
          ['android/app/build.gradle']);
    });

    test('--ios leaves Android alone', () async {
      final before = project.snapshot();
      final result = await run(project, ['--ios', newId]);
      final after = project.snapshot();

      expect(result.exitCode, 0);
      expect(before.keys.where((path) => before[path] != after[path]).toSet(),
          {'ios/Flutter/Debug.xcconfig', 'ios/Flutter/Release.xcconfig'});
    });

    test('--dry-run reports the changes and writes none', () async {
      final before = project.snapshot();
      final result = await run(project, [newId, '--dry-run']);

      expect(result.exitCode, 0);
      expect(result.output, contains('$studentAndroidId -> $newId'));
      expect(result.output, contains('$studentIosId -> $newId'));
      expect(result.output, contains('nothing was changed'));
      expect(project.snapshot(), before);
    });

    test('a second run with the same name changes nothing', () async {
      await run(project, [newId]);
      final once = project.snapshot();
      final result = await run(project, [newId]);

      expect(result.exitCode, 0);
      expect(result.output, contains('already uses $newId'));
      expect(project.snapshot(), once);
    });

    test('can be renamed again, and back', () async {
      await run(project, [newId]);
      await run(project, ['com.second.name']);
      expect(
          await AndroidRenameSteps('x.y', root: project.root)
              .currentPackageName(),
          'com.second.name');
      expect(
          await IosRenameSteps('x.y', root: project.root).currentPackageName(),
          'com.second.name');

      final original = Project.student();
      addTearDown(original.delete);
      await run(project, [studentAndroidId, '--android']);
      await run(project, [studentIosId, '--ios']);
      expect(project.snapshot(), original.snapshot());
    });

    test('keeps Windows line endings', () async {
      for (final path in [
        'android/app/build.gradle',
        ...IosRenameSteps.PATH_XCCONFIGS
      ]) {
        project.write(path, project.read(path).replaceAll('\n', '\r\n'));
      }
      final result = await run(project, [newId]);

      expect(result.exitCode, 0, reason: result.output);
      for (final path in [
        'android/app/build.gradle',
        ...IosRenameSteps.PATH_XCCONFIGS
      ]) {
        final contents = project.read(path);
        expect(contents, contains(newId));
        expect(contents.replaceAll('\r\n', ''), isNot(contains('\n')),
            reason: '$path has a bare line feed');
      }
      expect(project.read('ios/Flutter/Debug.xcconfig'),
          contains('SCHOOL_BUNDLE_ID = $newId\r\n'));
    });

    test('says which Firebase files are still for the old ids', () async {
      final result = await run(project, [newId]);

      expect(
          result.output, contains('Firebase still has the old package name'));
      expect(result.output,
          contains('android/app/google-services.json has no app for $newId'));
      expect(
          result.output,
          contains(
              'GoogleService-Info.plist is for $studentIosId, not $newId'));
      expect(
          result.output,
          contains('flutterfire configure --project=<your-firebase-project-id>'
              ' --android-package-name=$newId --ios-bundle-id=$newId'));
    });

    test('says nothing about Firebase once its files match', () async {
      project.write('android/app/google-services.json',
          googleServices([studentAndroidId, newId]));
      project.write(
          'ios/Runner/GoogleService-Info.plist', googleServiceInfo(newId));
      final result = await run(project, [newId]);

      expect(result.exitCode, 0);
      expect(result.output, isNot(contains('Firebase')));
    });

    test('after --android, the Firebase hint keeps the iOS id it has',
        () async {
      final result = await run(project, [newId, '--android']);

      expect(
          result.output,
          contains('--android-package-name=$newId'
              ' --ios-bundle-id=$studentIosId'));
    });
  });

  group('School Builder layout, Staff/Teacher app', () {
    setUp(() => project = Project.staff());

    test('renames both platforms and leaves the test targets alone', () async {
      final before = project.snapshot();
      final result = await run(project, [newId]);
      final after = project.snapshot();

      expect(result.exitCode, 0, reason: result.output);
      expect(before.keys.where((path) => before[path] != after[path]).toSet(), {
        'android/app/build.gradle',
        'ios/Flutter/Debug.xcconfig',
        'ios/Flutter/Release.xcconfig',
      });
      expect(
          addonApplicationId
              .firstMatch(after['android/app/build.gradle']!)!
              .group(1),
          newId);
      expect(
          addonBundleId
              .firstMatch(after['ios/Flutter/Release.xcconfig']!)!
              .group(1),
          newId);
      expect(after['ios/Runner.xcodeproj/project.pbxproj'],
          contains('com.example.eschoolSaasStaff.RunnerTests'));
    });
  });

  group('a project the 1.5.0 command was already run on', () {
    const typed = 'com.typed.earlier';

    test('gets its link to SCHOOL_BUNDLE_ID back', () async {
      project = Project.student();
      project.write('ios/Runner.xcodeproj/project.pbxproj', pbxproj(typed));
      final intact = Project.student();
      addTearDown(intact.delete);

      final result = await run(project, [newId]);

      expect(result.exitCode, 0, reason: result.output);
      expect(result.output, contains('reads SCHOOL_BUNDLE_ID again'));
      expect(project.read('ios/Runner.xcodeproj/project.pbxproj'),
          intact.read('ios/Runner.xcodeproj/project.pbxproj'));
      expect(
          addonBundleId
              .firstMatch(project.read('ios/Flutter/Release.xcconfig'))!
              .group(1),
          newId);
    });

    test('keeps the test targets of the Staff app out of the repair', () async {
      project = Project.staff();
      project.write(
          'ios/Runner.xcodeproj/project.pbxproj',
          pbxproj(typed,
              testsBundleId: 'com.example.eschoolSaasStaff.RunnerTests'));
      final intact = Project.staff();
      addTearDown(intact.delete);

      final result = await run(project, [newId]);

      expect(result.exitCode, 0, reason: result.output);
      expect(project.read('ios/Runner.xcodeproj/project.pbxproj'),
          intact.read('ios/Runner.xcodeproj/project.pbxproj'));
    });

    test('is repaired even when the name itself is already right', () async {
      project = Project.student();
      project.write('ios/Runner.xcodeproj/project.pbxproj', pbxproj(typed));

      final result = await run(project, [studentIosId, '--ios']);

      expect(result.exitCode, 0);
      expect(project.read('ios/Runner.xcodeproj/project.pbxproj'),
          contains('PRODUCT_BUNDLE_IDENTIFIER = $bundleIdReference;'));
      expect(project.read('ios/Runner.xcodeproj/project.pbxproj'),
          isNot(contains(typed)));
    });

    test('is refused, untouched, when its targets disagree', () async {
      project = Project.student();
      project.write(
          'ios/Runner.xcodeproj/project.pbxproj',
          pbxproj(typed).replaceFirst('PRODUCT_BUNDLE_IDENTIFIER = $typed;',
              'PRODUCT_BUNDLE_IDENTIFIER = $typed.NotificationService;'));
      final before = project.snapshot();

      final result = await run(project, [newId]);

      expect(result.exitCode, 1);
      expect(result.output, contains('Nothing was changed'));
      expect(project.snapshot(), before,
          reason: 'Android is not renamed when iOS cannot be');
    });

    test('is left alone when another target has an id of its own', () async {
      project = Project.student();
      final withExtension = pbxproj(bundleIdReference).replaceFirst(
          '}\n',
          '\t\tExtension = {\n\t\t\tbuildSettings = {\n'
              '\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.other.extension;\n'
              '\t\t\t};\n\t\t};\n}\n',
          pbxproj(bundleIdReference).lastIndexOf('}\n'));
      project.write('ios/Runner.xcodeproj/project.pbxproj', withExtension);

      final result = await run(project, [newId]);

      expect(result.exitCode, 0, reason: result.output);
      expect(
          project.read('ios/Runner.xcodeproj/project.pbxproj'), withExtension);
    });
  });

  group('a project that cannot be renamed safely', () {
    setUp(() => project = Project.student());

    test('with SCHOOL_BUNDLE_ID in only one xcconfig, is left untouched',
        () async {
      project.write(
          'ios/Flutter/Release.xcconfig',
          project
              .read('ios/Flutter/Release.xcconfig')
              .replaceFirst(RegExp(r'SCHOOL_BUNDLE_ID = .*\n'), ''));
      final before = project.snapshot();

      final result = await run(project, [newId]);

      expect(result.exitCode, 1);
      expect(
          result.output,
          contains(
              'ios/Flutter/Release.xcconfig has no SCHOOL_BUNDLE_ID line'));
      expect(project.snapshot(), before);
    });

    test('with two applicationId fallbacks, is left untouched', () async {
      project.write(
          'android/app/build.gradle',
          project.read('android/app/build.gradle') +
              "\ndef other = props.getProperty('applicationId', 'com.other.app')\n");
      final before = project.snapshot();

      final result = await run(project, [newId]);

      expect(result.exitCode, 1);
      expect(result.output, contains('in 2 places'));
      expect(project.snapshot(), before);
    });

    test('without a build.gradle, is left untouched', () async {
      project.file('android/app/build.gradle').deleteSync();
      final before = project.snapshot();

      final result = await run(project, [newId]);

      expect(result.exitCode, 1);
      expect(result.output, contains('build.gradle file not found'));
      expect(project.snapshot(), before);
    });
  });

  group('package names', () {
    setUp(() => project = Project.student());

    final refused = {
      'eschool': 'two parts',
      'com..eschool': 'empty part',
      '.com.eschool': 'empty part',
      'com.eschool.': 'empty part',
      'com.1school.app':
          '"1school" in "com.1school.app" can\'t be used for both',
      'com.my-school.app':
          '"my-school" in "com.my-school.app" can\'t be used for both',
      'com.my_school.app':
          '"my_school" in "com.my_school.app" can\'t be used for both',
      'com.my school.app':
          '"my school" in "com.my school.app" can\'t be used for both',
    };
    refused.forEach((name, reason) {
      test('"$name" is refused for both platforms', () async {
        final before = project.snapshot();
        final result = await run(project, [name]);

        expect(result.exitCode, ChangeAppPackageName.usageError);
        expect(result.output, contains(reason));
        expect(project.snapshot(), before);
      });
    });

    test('"_" is accepted for Android alone', () async {
      final result = await run(project, ['com.my_school.app', '--android']);

      expect(result.exitCode, 0, reason: result.output);
      expect(project.read('android/app/build.gradle'),
          contains("'com.my_school.app'"));
    });

    test('"-" is refused for Android alone, and says why', () async {
      final result = await run(project, ['com.my-school.app', '--android']);

      expect(result.exitCode, ChangeAppPackageName.usageError);
      expect(result.output, contains('Android does not accept "my-school"'));
    });

    test('"_" is refused for iOS alone, and says why', () async {
      final result = await run(project, ['com.my_school.app', '--ios']);

      expect(result.exitCode, ChangeAppPackageName.usageError);
      expect(result.output, contains('iOS does not accept "my_school"'));
    });

    test('"-" is accepted for iOS alone', () async {
      final result = await run(project, ['com.my-school.app', '--ios']);

      expect(result.exitCode, 0, reason: result.output);
      expect(project.read('ios/Flutter/Release.xcconfig'),
          contains('SCHOOL_BUNDLE_ID = com.my-school.app\n'));
    });

    test('capital letters are accepted with a note', () async {
      final result = await run(project, ['com.YourCompany.eschool']);

      expect(result.exitCode, 0);
      expect(result.output, contains('has capital letters'));
    });
  });

  group('command line', () {
    setUp(() => project = Project.student());

    final refused = {
      'no name': <String>[],
      'only a flag': ['--android'],
      'two names': ['com.one.app', 'com.two.app'],
      'an unknown flag': [newId, '--web'],
      'both platform flags': [newId, '--android', '--ios'],
    };
    refused.forEach((description, arguments) {
      test('$description is a usage error and changes nothing', () async {
        final before = project.snapshot();
        final result = await run(project, arguments);

        expect(result.exitCode, ChangeAppPackageName.usageError);
        expect(project.snapshot(), before);
      });
    });

    test('--help prints the usage and changes nothing', () async {
      final before = project.snapshot();
      final result = await run(project, ['--help']);

      expect(result.exitCode, 0);
      expect(result.output, contains('Usage: dart run'));
      expect(project.snapshot(), before);
    });
  });

  group('standard Flutter layout', () {
    setUp(() => project = Project.standard());

    test('is renamed as before: gradle, manifests, MainActivity, pbxproj',
        () async {
      final result = await run(project, [newId]);

      expect(result.exitCode, 0, reason: result.output);
      expect(project.read('android/app/build.gradle'),
          contains('applicationId "$newId"'));
      expect(project.read('android/app/build.gradle'),
          contains('namespace "$newId"'));
      expect(project.read('android/app/src/main/AndroidManifest.xml'),
          contains('package="$newId">'));
      expect(project.read('android/app/src/debug/AndroidManifest.xml'),
          contains('package="$newId">'));
      expect(
          project.read(
              'android/app/src/main/kotlin/com/yourcompany/eschool/MainActivity.kt'),
          startsWith('package $newId\n'));
      expect(
          Directory(
                  '${project.root.path}/android/app/src/main/kotlin/com/example')
              .existsSync(),
          isFalse,
          reason: 'the old package folders are removed');
      expect(
          RegExp('PRODUCT_BUNDLE_IDENTIFIER = $newId;')
              .allMatches(project.read('ios/Runner.xcodeproj/project.pbxproj')),
          hasLength(3));
    });

    test('keeps the rest of a manifest line that mentions a package', () async {
      await run(project, [newId]);

      expect(
          project.read('android/app/src/main/AndroidManifest.xml'),
          contains(
              'https://developer.android.com/training/package-visibility -->'));
      expect(
          project.read('android/app/src/debug/AndroidManifest.xml'),
          startsWith(
              '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="$newId">'));
    });

    test('with only an android folder, renames Android', () async {
      Directory('${project.root.path}/ios').deleteSync(recursive: true);
      final result = await run(project, [newId]);

      expect(result.exitCode, 0, reason: result.output);
      expect(result.output, contains('only Android is renamed'));
      expect(project.read('android/app/build.gradle'),
          contains('applicationId "$newId"'));
    });

    test('build.gradle.kts is found too', () async {
      project
          .file('android/app/build.gradle')
          .renameSync('${project.root.path}/android/app/build.gradle.kts');
      project.write('android/app/build.gradle.kts',
          'android {\n    defaultConfig {\n        applicationId = "com.example.old_app"\n    }\n}\n');
      final result = await run(project, [newId, '--android']);

      expect(result.exitCode, 0, reason: result.output);
      expect(project.read('android/app/build.gradle.kts'),
          contains('applicationId = "$newId"'));
    });
  });
}
