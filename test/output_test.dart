import 'package:change_app_package_name/change_app_package_name.dart';
import 'package:change_app_package_name/output_style.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

const String newId = 'com.yourcompany.eschool';
const String kotlin = 'android/app/src/main/kotlin';
const OutputStyle emoji = OutputStyle(emoji: true, color: false);
const OutputStyle colour = OutputStyle(emoji: true, color: true);

Future<List<String>> output(
  Project project,
  List<String> arguments,
  OutputStyle style,
) async {
  final lines = <String>[];
  await ChangeAppPackageName.run(arguments,
      root: project.root, log: lines.add, style: style);
  return lines;
}

void main() {
  late Project project;

  setUp(() => project = Project.student());
  tearDown(() => project.delete());

  group('a rename, in a terminal that shows emoji', () {
    test('reads as one screen from title to next step', () async {
      expect(await output(project, [newId], emoji), [
        '📦 Changing package name to $newId',
        '   Android + iOS',
        '',
        '🤖 Android · School Builder layout',
        '   📝 android/app/build.gradle',
        '      applicationId: $studentAndroidId → $newId',
        '      namespace: $studentAndroidId → $newId',
        '   📝 android/app/src/main/AndroidManifest.xml',
        '      package: $studentAndroidId → $newId',
        '   📝 android/app/src/debug/AndroidManifest.xml',
        '      package: $studentAndroidId → $newId',
        '   📝 $kotlin/com/wrteam/saas/school/MainActivity.kt',
        '      package: $studentAndroidId → $newId',
        '      moved to: $kotlin/com/wrteam/saas/school → $kotlin/com/yourcompany/eschool',
        '',
        '🍎 iOS · School Builder layout',
        '   📝 ios/Flutter/Debug.xcconfig',
        '      SCHOOL_BUNDLE_ID: $studentIosId → $newId',
        '   📝 ios/Flutter/Release.xcconfig',
        '      SCHOOL_BUNDLE_ID: $studentIosId → $newId',
        '',
        '✅ Package name updated.',
        '',
        '🔥 One more step: update Firebase',
        '   Firebase still has the old package name:',
        '   • android/app/google-services.json has no app for $newId.',
        '   • ios/Runner/GoogleService-Info.plist is for $studentIosId, not $newId.',
        '',
        '   Run this with your own Firebase project id:',
        '',
        '   flutterfire configure --project=<your-firebase-project-id>'
            ' --android-package-name=$newId --ios-bundle-id=$newId',
      ]);
    });

    test('puts the Firebase command on a line of its own, ready to copy',
        () async {
      final lines = await output(project, [newId], colour);
      final command =
          lines.singleWhere((line) => line.contains('flutterfire configure'));

      expect(
          command.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '').trim(),
          'flutterfire configure --project=<your-firebase-project-id>'
          ' --android-package-name=$newId --ios-bundle-id=$newId');
    });

    test('a dry run says so, and how to apply it', () async {
      final lines = await output(project, [newId, '--dry-run'], emoji);

      expect(lines.last,
          '👀 Dry run: nothing was changed. Run it again without --dry-run to apply.');
      expect(lines, isNot(contains('✅ Package name updated.')));
    });

    test('a second run says there is nothing to do', () async {
      await output(project, [newId], emoji);
      final lines = await output(project, [newId], emoji);

      expect(lines, contains('   ✅ Already $newId, nothing to change.'));
      expect(lines, contains('✅ The project already uses $newId.'));
    });

    test('an error is marked, and says nothing was changed', () async {
      project.file('android/app/build.gradle').deleteSync();
      final lines = await output(project, [newId], emoji);

      expect(lines.where((line) => line.startsWith('❌ ')), hasLength(1));
      expect(lines.last, '   Nothing was changed.');
    });

    test('a name that cannot be used is marked as an error', () async {
      final lines = await output(project, ['com.my-school.app'], emoji);

      expect(lines.last, startsWith('❌ "my-school" in "com.my-school.app"'));
    });

    test('a missing name shows the usage under the error', () async {
      final lines = await output(project, [], emoji);

      expect(lines.first,
          '❌ New package name is missing. Please provide a package name.');
      expect(lines.last, ChangeAppPackageName.usage);
    });
  });

  group('a rename, in plain text', () {
    test('reads the same without emoji', () async {
      expect(await output(project, [newId, '--android'], OutputStyle.plain), [
        'Changing package name to $newId',
        '  Android only',
        '',
        'Android - School Builder layout',
        '  android/app/build.gradle',
        '    applicationId: $studentAndroidId -> $newId',
        '    namespace: $studentAndroidId -> $newId',
        '  android/app/src/main/AndroidManifest.xml',
        '    package: $studentAndroidId -> $newId',
        '  android/app/src/debug/AndroidManifest.xml',
        '    package: $studentAndroidId -> $newId',
        '  $kotlin/com/wrteam/saas/school/MainActivity.kt',
        '    package: $studentAndroidId -> $newId',
        '    moved to: $kotlin/com/wrteam/saas/school -> $kotlin/com/yourcompany/eschool',
        '',
        'Package name updated.',
        '',
        'One more step: update Firebase',
        '  Firebase still has the old package name:',
        '  - android/app/google-services.json has no app for $newId.',
        '',
        '  Run this with your own Firebase project id:',
        '',
        '  flutterfire configure --project=<your-firebase-project-id>'
            ' --android-package-name=$newId --ios-bundle-id=$studentIosId',
      ]);
    });

    test('holds only characters every terminal and log can show', () async {
      final lines = await output(project, [newId], OutputStyle.plain);

      for (final line in lines) {
        expect(line.codeUnits.every((unit) => unit >= 32 && unit < 127), isTrue,
            reason: 'not plain: $line');
      }
    });

    test('keeps the ERROR:: mark scripts look for', () async {
      project.file('android/app/build.gradle').deleteSync();
      final lines = await output(project, [newId], OutputStyle.plain);

      expect(lines.where((line) => line.startsWith('ERROR:: ')), hasLength(1));
    });

    test('--plain turns emoji and colour off in any terminal', () async {
      final lines = await output(project, [newId, '--plain'], colour);

      for (final line in lines) {
        expect(line.codeUnits.every((unit) => unit >= 32 && unit < 127), isTrue,
            reason: 'not plain: $line');
      }
    });
  });

  group('colour', () {
    test('is used only when the style asks for it', () async {
      final coloured = await output(project, [newId, '--dry-run'], colour);
      final uncoloured = await output(project, [newId, '--dry-run'], emoji);

      expect(coloured.join('\n'), contains('\x1B['));
      expect(uncoloured.join('\n'), isNot(contains('\x1B[')));
      expect(
          coloured
              .map((line) => line.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), ''))
              .toList(),
          uncoloured,
          reason: 'colour never changes the words');
    });
  });

  group('the style picked for a terminal', () {
    OutputStyle detect(
      Map<String, String> environment, {
      bool windows = false,
      bool ansi = true,
    }) =>
        OutputStyle.detect(
            environment: environment, isWindows: windows, supportsAnsi: ansi);

    test('macOS and Linux get emoji and colour', () {
      final style = detect({'TERM': 'xterm-256color'});

      expect(style.emoji, isTrue);
      expect(style.color, isTrue);
    });

    test('the old Windows console gets no emoji', () {
      expect(detect({}, windows: true).emoji, isFalse);
    });

    test('Windows Terminal and the VS Code terminal get emoji', () {
      expect(detect({'WT_SESSION': 'abc'}, windows: true).emoji, isTrue);
      expect(detect({'TERM_PROGRAM': 'vscode'}, windows: true).emoji, isTrue);
    });

    test('a dumb terminal gets no emoji', () {
      expect(detect({'TERM': 'dumb'}).emoji, isFalse);
    });

    test('NO_COLOR turns colour off', () {
      expect(detect({'NO_COLOR': '1'}).color, isFalse);
    });

    test('output that is not a terminal gets no colour', () {
      expect(detect({}, ansi: false).color, isFalse);
    });
  });
}
