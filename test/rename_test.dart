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

    test('renames the code with the app, so no old name is left on Android',
        () async {
      const oldActivity =
          'android/app/src/main/kotlin/com/wrteam/saas/school/MainActivity.kt';
      const newActivity =
          'android/app/src/main/kotlin/com/yourcompany/eschool/MainActivity.kt';
      final before = project.snapshot();
      await run(project, [newId]);
      final after = project.snapshot();

      expect(
        after['android/app/build.gradle'],
        before['android/app/build.gradle']!
            .replaceFirst("getProperty('applicationId', '$studentAndroidId')",
                "getProperty('applicationId', '$newId')")
            .replaceFirst(
                "namespace '$studentAndroidId'", "namespace '$newId'"),
        reason: 'the application id and the namespace, and no other line',
      );
      for (final manifest in [
        'android/app/src/main/AndroidManifest.xml',
        'android/app/src/debug/AndroidManifest.xml',
      ]) {
        expect(
            after[manifest],
            before[manifest]!.replaceFirst(
                'package="$studentAndroidId"', 'package="$newId"'));
      }
      expect(after.containsKey(oldActivity), isFalse);
      expect(after[newActivity],
          before[oldActivity]!.replaceFirst(studentAndroidId, newId));
      expect(
          Directory(
                  '${project.root.path}/android/app/src/main/kotlin/com/wrteam')
              .existsSync(),
          isFalse,
          reason: 'the emptied folders of the old package are removed');

      expect(
          after.keys
              .where((path) => path.startsWith('android/'))
              .where((path) => path != 'android/app/google-services.json')
              .where((path) => after[path]!.contains(studentAndroidId)),
          isEmpty,
          reason: 'only the Firebase file, which Firebase regenerates');
    });

    test('touches no file but the ones a rename is made of', () async {
      final before = project.snapshot();
      await run(project, [newId]);
      final after = project.snapshot();

      final changed = {
        ...before.keys.where((path) => before[path] != after[path]),
        ...after.keys.where((path) => !before.containsKey(path)),
      };
      expect(changed, {
        'android/app/build.gradle',
        'android/app/src/main/AndroidManifest.xml',
        'android/app/src/debug/AndroidManifest.xml',
        'android/app/src/main/kotlin/com/wrteam/saas/school/MainActivity.kt',
        'android/app/src/main/kotlin/com/yourcompany/eschool/MainActivity.kt',
        'ios/Flutter/Debug.xcconfig',
        'ios/Flutter/Release.xcconfig',
      });
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
      expect(after['android/app/build.gradle'], contains("namespace '$newId'"));
      for (final path in before.keys.where((path) => path.startsWith('ios/'))) {
        expect(after[path], before[path], reason: '$path changed');
      }
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
      expect({
        ...before.keys.where((path) => before[path] != after[path]),
        ...after.keys.where((path) => !before.containsKey(path)),
      }, {
        'android/app/build.gradle',
        'android/app/src/main/kotlin/com/wrteam/saas/staff/MainActivity.kt',
        'android/app/src/main/kotlin/com/yourcompany/eschool/MainActivity.kt',
        'ios/Flutter/Debug.xcconfig',
        'ios/Flutter/Release.xcconfig',
      });
      expect(after['android/app/build.gradle'], contains('namespace "$newId"'),
          reason: 'the quote the file uses is kept');
      expect(
          after[
              'android/app/src/main/kotlin/com/yourcompany/eschool/MainActivity.kt'],
          startsWith('package $newId\n'));
      expect(after['android/app/src/main/AndroidManifest.xml'],
          before['android/app/src/main/AndroidManifest.xml'],
          reason: 'a manifest with no package attribute is left as it is, '
              'its comment that reads package="..." included');
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

  group('the code package', () {
    const kotlin = 'android/app/src/main/kotlin';
    const oldActivity = '$kotlin/com/wrteam/saas/school/MainActivity.kt';

    setUp(() => project = Project.student());

    test('a name with words Java reserves renames the app and keeps the code',
        () async {
      const reserved = 'com.new.package.name';
      final before = project.snapshot();
      final result = await run(project, [reserved]);
      final after = project.snapshot();

      expect(result.exitCode, 0, reason: result.output);
      expect(
        after['android/app/build.gradle'],
        before['android/app/build.gradle']!.replaceFirst(
            "getProperty('applicationId', '$studentAndroidId')",
            "getProperty('applicationId', '$reserved')"),
        reason: 'Android refuses this name as a namespace, so it stays',
      );
      expect(after['android/app/src/main/AndroidManifest.xml'],
          before['android/app/src/main/AndroidManifest.xml']);
      expect(after[oldActivity], before[oldActivity]);
      expect(
          result.output,
          contains('The code keeps $studentAndroidId (namespace, manifest '
              'package and source folder), because "new" and "package" are '
              'reserved words in Java'));
    });

    test('one reserved word is named on its own', () async {
      final result = await run(project, ['com.school.default', '--android']);

      expect(result.exitCode, 0);
      expect(
          result.output, contains('because "default" is a reserved word in'));
    });

    test('says nothing once the app has the name and the code never will',
        () async {
      await run(project, ['com.new.package.name']);
      final result = await run(project, ['com.new.package.name']);

      expect(result.output, contains('already uses com.new.package.name'));
    });

    test('words only Kotlin reserves are written in backticks', () async {
      const name = 'in.co.myschool.app';
      final result = await run(project, [name, '--android']);

      expect(result.exitCode, 0, reason: result.output);
      expect(project.read('android/app/build.gradle'),
          contains("namespace '$name'"));
      expect(project.read('$kotlin/in/co/myschool/app/MainActivity.kt'),
          startsWith('package `in`.co.myschool.app\n'));
    });

    test('an app renamed earlier without its code gets the code on a rerun',
        () async {
      project.write('android/app/build.gradle',
          schoolBuilderGradle(newId, namespace: studentAndroidId));
      final result = await run(project, [newId, '--android']);

      expect(result.exitCode, 0, reason: result.output);
      expect(result.output, contains('namespace: $studentAndroidId -> $newId'));
      expect(project.read('android/app/build.gradle'),
          contains("namespace '$newId'"));
      expect(project.exists(oldActivity), isFalse);
      expect(project.exists('$kotlin/com/yourcompany/eschool/MainActivity.kt'),
          isTrue);
    });

    test('sources below the package, and imports of it, follow', () async {
      project.write('$kotlin/com/wrteam/saas/school/util/Helper.kt',
          'package $studentAndroidId.util\n\nimport $studentAndroidId.MainActivity\n');
      project.write('android/app/src/main/java/io/other/Plugin.java',
          'package io.other;\n\nimport $studentAndroidId.R;\nimport static $studentAndroidId.Keys.NAME;\n');
      final result = await run(project, [newId, '--android']);

      expect(result.exitCode, 0, reason: result.output);
      expect(project.read('$kotlin/com/yourcompany/eschool/util/Helper.kt'),
          'package $newId.util\n\nimport $newId.MainActivity\n');
      expect(project.exists('$kotlin/com/wrteam'), isFalse);
      expect(project.read('android/app/src/main/java/io/other/Plugin.java'),
          'package io.other;\n\nimport $newId.R;\nimport static $newId.Keys.NAME;\n',
          reason: 'a source of another package stays where it is');
    });

    test('a project with no namespace takes the package from its manifest',
        () async {
      project.write(
          'android/app/build.gradle',
          project
              .read('android/app/build.gradle')
              .replaceFirst("    namespace '$studentAndroidId'\n", ''));
      final result = await run(project, [newId, '--android']);

      expect(result.exitCode, 0, reason: result.output);
      expect(project.read('android/app/src/main/AndroidManifest.xml'),
          contains('package="$newId">'));
      expect(project.exists('$kotlin/com/yourcompany/eschool/MainActivity.kt'),
          isTrue);
    });

    test('a file already at the new place stops the rename, untouched',
        () async {
      project.write('$kotlin/com/yourcompany/eschool/MainActivity.kt',
          mainActivity(newId));
      final before = project.snapshot();
      final result = await run(project, [newId]);

      expect(result.exitCode, 1);
      expect(result.output, contains('already exists'));
      expect(project.snapshot(), before);
    });

    test('a dry run lists the whole rename and writes none of it', () async {
      final before = project.snapshot();
      final result = await run(project, [newId, '--dry-run', '--android']);

      expect(
          result.lines,
          containsAll(<String>[
            '  android/app/build.gradle',
            '    applicationId: $studentAndroidId -> $newId',
            '    namespace: $studentAndroidId -> $newId',
            '  android/app/src/main/AndroidManifest.xml',
            '    package: $studentAndroidId -> $newId',
            '  $oldActivity',
            '    moved to: $kotlin/com/wrteam/saas/school -> $kotlin/com/yourcompany/eschool',
          ]));
      expect(project.snapshot(), before);
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
