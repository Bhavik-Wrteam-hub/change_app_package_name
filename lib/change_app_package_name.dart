library change_app_package_name;

import 'dart:io';

import './android_rename_steps.dart';
import './firebase_check.dart';
import './ios_rename_steps.dart';
import './output_style.dart';
import './package_name.dart';
import './rename_plan.dart';

class ChangeAppPackageName {
  /// Exit code for a command line that can't be understood.
  static const int usageError = 64;

  static const String usage = '''
Usage: dart run change_app_package_name:main <new.package.name> [options]

  --android   Rename only the Android application id.
  --ios       Rename only the iOS bundle id.
  --dry-run   Show what would change without writing anything.
  --plain     Print plain text, without emoji or colour.
  --help      Show this message.''';

  static const List<String> _flags = [
    '--android',
    '--ios',
    '--dry-run',
    '--plain',
  ];

  static Future<void> start(List<String> arguments) async {
    exitCode = await run(arguments);
  }

  /// Renames the project in [root] (the current directory by default) and
  /// returns the exit code. Every line the command prints goes to [log],
  /// dressed as [style] says, or as the terminal can show when it is left out.
  static Future<int> run(
    List<String> arguments, {
    Directory? root,
    void Function(String line)? log,
    OutputStyle? style,
  }) async {
    root ??= Directory.current;

    final flags = arguments
        .where((argument) => argument.startsWith('-'))
        .map((argument) => argument.toLowerCase())
        .toList();
    final names =
        arguments.where((argument) => !argument.startsWith('-')).toList();

    final out = _Output(
      log ?? print,
      flags.contains('--plain')
          ? OutputStyle.plain
          : style ?? OutputStyle.detect(),
    );

    if (flags.contains('--help') || flags.contains('-h')) {
      out.line(usage);
      return 0;
    }
    final unknown = flags.where((flag) => !_flags.contains(flag)).toList();
    if (unknown.isNotEmpty) {
      return out.usageError(
          'Invalid argument ${unknown.join(', ')}. Use "--android" or "--ios".');
    }
    if (names.isEmpty) {
      return out.usageError(
          'New package name is missing. Please provide a package name.');
    }
    if (names.length > 1) {
      return out.usageError(
          'Too many arguments. This package accepts only the new package name and an optional platform flag.');
    }
    if (flags.contains('--android') && flags.contains('--ios')) {
      return out.usageError(
          'Use "--android" or "--ios", not both. Leave both out to rename the two platforms.');
    }

    final newPackageName = names.single;
    final dryRun = flags.contains('--dry-run');
    final android = AndroidRenameSteps(newPackageName, root: root);
    final ios = IosRenameSteps(newPackageName, root: root);

    var renameAndroid = !flags.contains('--ios');
    var renameIos = !flags.contains('--android');
    String? skipped;
    if (renameAndroid && renameIos) {
      // A project built for one platform only is still a whole project.
      if (!android.hasPlatform && ios.hasPlatform) {
        skipped = 'No android folder in this project, so only iOS is renamed.';
        renameAndroid = false;
      } else if (!ios.hasPlatform && android.hasPlatform) {
        skipped = 'No ios folder in this project, so only Android is renamed.';
        renameIos = false;
      }
    }

    out.title(
      'Changing package name to ${out.style.bold(newPackageName)}',
      renameAndroid && renameIos
          ? 'Android + iOS'
          : renameAndroid
              ? 'Android only'
              : 'iOS only',
    );
    if (skipped != null) out.note(skipped, indented: true);

    final problem = PackageName.problem(newPackageName,
        android: renameAndroid, ios: renameIos);
    if (problem != null) {
      out.line('');
      out.error(problem);
      return usageError;
    }

    // Both platforms are worked out before either is written, so a project
    // is never left with one of them renamed and the other not.
    final plans = <RenamePlan>[];
    try {
      if (renameAndroid) plans.add(await android.plan());
      if (renameIos) plans.add(await ios.plan());
    } on RenameException catch (error) {
      out.line('');
      out.error(error.message);
      out.line('${out.style.indent}Nothing was changed.');
      return 1;
    }

    for (final plan in plans) {
      out.line('');
      out.platform(plan);
      if (!plan.hasChanges) {
        out.line('${out.style.indent}${out.style.icon('✅')}'
            'Already $newPackageName, nothing to change.');
      }
      for (final change in plan.changes) {
        out.change(change);
      }
      for (final note in plan.notes) {
        out.note(note, indented: true);
      }
    }
    if (PackageName.hasUppercase(newPackageName)) {
      out.line('');
      out.note('$newPackageName has capital letters. The stores treat names '
          'that differ only in case as different apps, so lowercase is safer.');
    }

    if (dryRun) {
      out.line('');
      out.line('${out.style.icon('👀')}'
          '${out.style.yellow('Dry run: nothing was changed.')} '
          'Run it again without --dry-run to apply.');
      return 0;
    }

    for (final plan in plans) {
      await plan.apply();
    }
    out.line('');
    out.success(plans.any((plan) => plan.hasChanges)
        ? 'Package name updated.'
        : 'The project already uses $newPackageName.');

    await _reportFirebase(root, android, ios, out);
    return 0;
  }

  /// Firebase keeps its own copy of both ids. Until its files are regenerated
  /// for the new ones, the renamed app fails to start Firebase.
  static Future<void> _reportFirebase(
    Directory root,
    AndroidRenameSteps android,
    IosRenameSteps ios,
    _Output out,
  ) async {
    final androidId =
        android.hasPlatform ? await android.currentPackageName() : null;
    final iosId = ios.hasPlatform ? await ios.currentPackageName() : null;
    final mismatches =
        FirebaseCheck(root).mismatches(androidId: androidId, iosId: iosId);
    if (mismatches.isEmpty) return;

    final style = out.style;
    out.line('');
    out.line('${style.icon('🔥')}'
        '${style.bold(style.yellow('One more step: update Firebase'))}');
    out.line('${style.indent}Firebase still has the old package name:');
    for (final mismatch in mismatches) {
      out.line('${style.indent}${style.bullet} $mismatch');
    }
    out.line('');
    out.line('${style.indent}Run this with your own Firebase project id:');
    out.line('');
    // On a line of its own, so it can be selected and pasted as it is.
    out.line(style.indent +
        style.cyan('flutterfire configure --project=<your-firebase-project-id>'
            '${androidId == null ? '' : ' --android-package-name=$androidId'}'
            '${iosId == null ? '' : ' --ios-bundle-id=$iosId'}'));
  }
}

/// The lines the command prints, in one place so they read as one design.
class _Output {
  final void Function(String line) line;
  final OutputStyle style;

  /// The file the last change was in, so its other changes list under it.
  String? _file;

  _Output(this.line, this.style);

  void title(String text, String platforms) {
    line('${style.icon('📦')}$text');
    line('${style.indent}${style.dim(platforms)}');
  }

  void platform(RenamePlan plan) {
    _file = null;
    final icon = plan.platform == 'Android' ? '🤖' : '🍎';
    line('${style.icon(icon)}${style.bold(plan.platform)} '
        '${style.dim('${style.separator} ${plan.layout}')}');
  }

  void change(RenameChange change) {
    if (change.path != _file) {
      line('${style.indent}${style.icon('📝')}${change.path}');
      _file = change.path;
    }
    line('${style.indent}${style.indent}${change.label}: '
        '${style.dim(change.oldValue)} ${style.arrow} '
        '${style.green(change.newValue)}');
  }

  void note(String text, {bool indented = false}) {
    line('${indented ? style.indent : ''}'
        '${style.icon('💡', fallback: 'Note:')}$text');
  }

  void success(String text) {
    line('${style.icon('✅')}${style.bold(style.green(text))}');
  }

  void error(String text) {
    line('${style.icon('❌', fallback: 'ERROR::')}${style.red(text)}');
  }

  int usageError(String text) {
    error(text);
    line('');
    line(ChangeAppPackageName.usage);
    return ChangeAppPackageName.usageError;
  }
}
