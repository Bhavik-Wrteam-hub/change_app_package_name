library change_app_package_name;

import 'dart:io';

import './android_rename_steps.dart';
import './firebase_check.dart';
import './ios_rename_steps.dart';
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
  --help      Show this message.''';

  static Future<void> start(List<String> arguments) async {
    exitCode = await run(arguments);
  }

  /// Renames the project in [root] (the current directory by default) and
  /// returns the exit code. Every line the command prints goes to [log].
  static Future<int> run(
    List<String> arguments, {
    Directory? root,
    void Function(String line)? log,
  }) async {
    log ??= print;
    root ??= Directory.current;

    final flags = arguments
        .where((argument) => argument.startsWith('-'))
        .map((argument) => argument.toLowerCase())
        .toList();
    final names =
        arguments.where((argument) => !argument.startsWith('-')).toList();

    if (flags.contains('--help') || flags.contains('-h')) {
      log(usage);
      return 0;
    }
    final unknown = flags
        .where((flag) => !['--android', '--ios', '--dry-run'].contains(flag))
        .toList();
    if (unknown.isNotEmpty) {
      log('Invalid argument ${unknown.join(', ')}. Use "--android" or "--ios".');
      log(usage);
      return usageError;
    }
    if (names.isEmpty) {
      log('New package name is missing. Please provide a package name.');
      log(usage);
      return usageError;
    }
    if (names.length > 1) {
      log('Too many arguments. This package accepts only the new package name and an optional platform flag.');
      log(usage);
      return usageError;
    }
    if (flags.contains('--android') && flags.contains('--ios')) {
      log('Use "--android" or "--ios", not both. Leave both out to rename the two platforms.');
      return usageError;
    }

    final newPackageName = names.single;
    final dryRun = flags.contains('--dry-run');
    final android = AndroidRenameSteps(newPackageName, root: root);
    final ios = IosRenameSteps(newPackageName, root: root);

    var renameAndroid = !flags.contains('--ios');
    var renameIos = !flags.contains('--android');
    if (renameAndroid && renameIos) {
      log('Renaming package for both Android and iOS.');
      // A project built for one platform only is still a whole project.
      if (!android.hasPlatform && ios.hasPlatform) {
        log('No android folder in this project, so only iOS is renamed.');
        renameAndroid = false;
      } else if (!ios.hasPlatform && android.hasPlatform) {
        log('No ios folder in this project, so only Android is renamed.');
        renameIos = false;
      }
    } else if (renameAndroid) {
      log('Renaming package for Android only.');
    } else {
      log('Renaming package for iOS only.');
    }

    final problem = PackageName.problem(newPackageName,
        android: renameAndroid, ios: renameIos);
    if (problem != null) {
      log('ERROR:: $problem');
      return usageError;
    }

    // Both platforms are worked out before either is written, so a project
    // is never left with one of them renamed and the other not.
    final plans = <RenamePlan>[];
    try {
      if (renameAndroid) plans.add(await android.plan());
      if (renameIos) plans.add(await ios.plan());
    } on RenameException catch (error) {
      log('ERROR:: ${error.message}');
      log('Nothing was changed.');
      return 1;
    }

    for (final plan in plans) {
      log('');
      log('${plan.platform} (${plan.layout})');
      if (!plan.hasChanges) {
        log('  Already $newPackageName, nothing to change.');
      }
      for (final change in plan.changes) {
        log('  ${change.path}');
        log('    ${change.label}: ${change.oldValue} -> ${change.newValue}');
      }
      for (final note in plan.notes) {
        log('  Note: $note');
      }
    }
    if (PackageName.hasUppercase(newPackageName)) {
      log('');
      log('Note: $newPackageName has capital letters. The stores treat names '
          'that differ only in case as different apps, so lowercase is safer.');
    }

    if (dryRun) {
      log('');
      log('Dry run: nothing was changed.');
      return 0;
    }

    for (final plan in plans) {
      await plan.apply();
    }
    log('');
    log(plans.any((plan) => plan.hasChanges)
        ? 'Finished updating the package name.'
        : 'The project already uses $newPackageName.');

    await _reportFirebase(root, android, ios, log);
    return 0;
  }

  /// Firebase keeps its own copy of both ids. Until its files are regenerated
  /// for the new ones, the renamed app fails to start Firebase.
  static Future<void> _reportFirebase(
    Directory root,
    AndroidRenameSteps android,
    IosRenameSteps ios,
    void Function(String line) log,
  ) async {
    final androidId =
        android.hasPlatform ? await android.currentPackageName() : null;
    final iosId = ios.hasPlatform ? await ios.currentPackageName() : null;
    final mismatches =
        FirebaseCheck(root).mismatches(androidId: androidId, iosId: iosId);
    if (mismatches.isEmpty) return;

    log('');
    log('Next step: Firebase still has the old package name.');
    for (final mismatch in mismatches) {
      log('  $mismatch');
    }
    log('Regenerate the Firebase files, with your own Firebase project id:');
    log('  flutterfire configure --project=<your-firebase-project-id>'
        '${androidId == null ? '' : ' --android-package-name=$androidId'}'
        '${iosId == null ? '' : ' --ios-bundle-id=$iosId'}');
  }
}
