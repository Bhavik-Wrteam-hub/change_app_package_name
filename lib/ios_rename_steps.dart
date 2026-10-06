import 'dart:async';
import 'dart:io';

import './file_utils.dart';
import './rename_plan.dart';

class IosRenameSteps {
  final String newPackageName;

  /// The Flutter project, the folder that holds `ios/`.
  final Directory root;
  String? oldPackageName;
  static const String PATH_PROJECT_FILE =
      'ios/Runner.xcodeproj/project.pbxproj';

  /// Where the School Builder layout (eSchool SaaS v1.12.0 and later) keeps
  /// the bundle id. Debug builds read the first and release builds the second.
  static const List<String> PATH_XCCONFIGS = [
    'ios/Flutter/Debug.xcconfig',
    'ios/Flutter/Release.xcconfig',
  ];

  /// The build setting the School Builder layout keeps the bundle id in. A
  /// school build overrides it from `School.xcconfig`.
  static const String SCHOOL_BUNDLE_ID = 'SCHOOL_BUNDLE_ID';

  /// What `project.pbxproj` holds in the School Builder layout.
  static const String SCHOOL_BUNDLE_ID_REFERENCE = '"\$($SCHOOL_BUNDLE_ID)"';

  /// Groups: 1 the key and `=`, 2 the value, 3 trailing spaces.
  static final RegExp _xcconfigBundleId = RegExp(
      '^($SCHOOL_BUNDLE_ID[ \\t]*=[ \\t]*)([^\\r\\n]*?)([ \\t]*)\$',
      multiLine: true);

  /// Groups: 1 the key and `=`, 2 the value.
  static final RegExp _projectBundleId = RegExp(
      r'^(\s*PRODUCT_BUNDLE_IDENTIFIER\s*=\s*)([^;\r\n]+);',
      multiLine: true);

  static final RegExp _standardBundleId = RegExp(
      r'PRODUCT_BUNDLE_IDENTIFIER\s*=?\s*(.*);',
      caseSensitive: true,
      multiLine: false);

  IosRenameSteps(this.newPackageName, {Directory? root})
      : root = root ?? Directory.current;

  String _path(String relative) => '${root.path}/$relative';

  /// True when the project has an iOS app at all.
  bool get hasPlatform => Directory(_path('ios')).existsSync();

  /// The xcconfig files of the project that set [SCHOOL_BUNDLE_ID], by path.
  Future<Map<String, String>> _schoolBuilderConfigs() async {
    final configs = <String, String>{};
    for (final path in PATH_XCCONFIGS) {
      final contents = await readFileAsString(_path(path));
      if (contents != null && _xcconfigBundleId.hasMatch(contents)) {
        configs[path] = contents;
      }
    }
    return configs;
  }

  /// The bundle id the project builds with now, or null when it can't be
  /// read. A release build is what reaches the store, so its file wins.
  Future<String?> currentPackageName() async {
    final configs = await _schoolBuilderConfigs();
    for (final path in PATH_XCCONFIGS.reversed) {
      final contents = configs[path];
      if (contents != null) {
        return _xcconfigBundleId.firstMatch(contents)!.group(2);
      }
    }
    final project = await readFileAsString(_path(PATH_PROJECT_FILE));
    if (project == null) return null;
    return _standardBundleId.firstMatch(project)?.group(1);
  }

  /// Works out the rename without writing anything.
  Future<RenamePlan> plan() async {
    final configs = await _schoolBuilderConfigs();
    if (configs.isNotEmpty) {
      return _schoolBuilderPlan(configs);
    }

    if (!await File(_path(PATH_PROJECT_FILE)).exists()) {
      throw RenameException(
          'project.pbxproj file not found, Check if you have a correct ios directory present in your project'
          '\n\nrun " flutter create . " to regenerate missing files.');
    }
    String? contents = await readFileAsString(_path(PATH_PROJECT_FILE));

    var match = _standardBundleId.firstMatch(contents!);
    if (match == null) {
      throw RenameException(
          'Bundle Identifier not found in project.pbxproj file, Please file an issue on github with $PATH_PROJECT_FILE file attached.');
    }
    var name = match.group(1)!;
    oldPackageName = name;
    return RenamePlan(
      platform: 'iOS',
      layout: RenamePlan.standardLayout,
      changes: name == newPackageName
          ? const []
          : [
              RenameChange(PATH_PROJECT_FILE, 'PRODUCT_BUNDLE_IDENTIFIER', name,
                  newPackageName)
            ],
      apply: () => _replace(_path(PATH_PROJECT_FILE)),
    );
  }

  /// The School Builder layout: the bundle id is the [SCHOOL_BUNDLE_ID] line
  /// of each xcconfig file, and `project.pbxproj` only refers to it. Writing
  /// the id into `project.pbxproj` would cut that link, and with it the
  /// add-on's way of giving each school its own bundle id.
  Future<RenamePlan> _schoolBuilderPlan(Map<String, String> configs) async {
    final missing =
        PATH_XCCONFIGS.where((path) => !configs.containsKey(path)).toList();
    if (missing.isNotEmpty) {
      throw RenameException(
          '${missing.join(' and ')} has no $SCHOOL_BUNDLE_ID line, while '
          '${configs.keys.join(' and ')} has one. Debug and release builds '
          'would get different bundle ids, so add the line to both files first.');
    }

    final changes = <RenameChange>[];
    final writes = <String, String>{};
    for (final entry in configs.entries) {
      final matches = _xcconfigBundleId.allMatches(entry.value).toList();
      if (matches.length > 1) {
        throw RenameException(
            '${entry.key} sets $SCHOOL_BUNDLE_ID ${matches.length} times, so it '
            'is not clear which line to change. Keep a single line.');
      }
      final match = matches.single;
      final name = match.group(2)!;
      if (name == newPackageName) continue;
      changes
          .add(RenameChange(entry.key, SCHOOL_BUNDLE_ID, name, newPackageName));
      writes[entry.key] = entry.value.replaceRange(match.start, match.end,
          '${match.group(1)}$newPackageName${match.group(3)}');
    }
    oldPackageName =
        _xcconfigBundleId.firstMatch(configs[PATH_XCCONFIGS.last]!)!.group(2);

    final notes = <String>[];
    final project = await readFileAsString(_path(PATH_PROJECT_FILE));
    if (project != null) {
      final restored = _restoreProjectLink(project);
      if (restored != null) {
        changes.add(RenameChange(PATH_PROJECT_FILE, 'PRODUCT_BUNDLE_IDENTIFIER',
            restored.overwrittenWith, SCHOOL_BUNDLE_ID_REFERENCE));
        writes[PATH_PROJECT_FILE] = restored.contents;
        notes.add('$PATH_PROJECT_FILE had the bundle id written into it, most '
            'likely by an older version of this command. It reads '
            '$SCHOOL_BUNDLE_ID again.');
      }
    }

    return RenamePlan(
      platform: 'iOS',
      layout: RenamePlan.schoolBuilderLayout,
      changes: changes,
      notes: notes,
      apply: () async {
        for (final write in writes.entries) {
          await writeFileFromString(_path(write.key), write.value);
        }
      },
    );
  }

  /// `project.pbxproj` with its link to [SCHOOL_BUNDLE_ID] put back, or null
  /// when the link is intact.
  ///
  /// Version 1.5.0 of this command replaced every `"$(SCHOOL_BUNDLE_ID)"` with
  /// the new id, after which the xcconfig value is ignored. That state is
  /// recognisable: nothing refers to the setting any more and every target
  /// but the tests carries the same literal id. Anything else is left to the
  /// user, since a project may have targets with ids of their own.
  _RestoredProject? _restoreProjectLink(String project) {
    final lines = _projectBundleId.allMatches(project).toList();
    if (lines.isEmpty) return null;
    if (lines.any((line) => line.group(2)!.contains(SCHOOL_BUNDLE_ID))) {
      return null;
    }
    final appLines =
        lines.where((line) => !line.group(2)!.contains('RunnerTests')).toList();
    final ids = appLines.map((line) => line.group(2)!.trim()).toSet();
    if (ids.isEmpty) return null;
    if (ids.length > 1) {
      throw RenameException(
          '$PATH_PROJECT_FILE no longer reads $SCHOOL_BUNDLE_ID, and its '
          'targets use different bundle ids (${ids.join(', ')}), so it is not '
          'clear which of them is the app. Set PRODUCT_BUNDLE_IDENTIFIER of '
          'the Runner target back to $SCHOOL_BUNDLE_ID_REFERENCE and run '
          'this again.');
    }

    final buffer = StringBuffer();
    var end = 0;
    for (final line in appLines) {
      buffer
        ..write(project.substring(end, line.start))
        ..write('${line.group(1)}$SCHOOL_BUNDLE_ID_REFERENCE;');
      end = line.end;
    }
    buffer.write(project.substring(end));
    return _RestoredProject(buffer.toString(), ids.single);
  }

  Future<void> process() async {
    print("Running for ios");
    final RenamePlan renamePlan;
    try {
      renamePlan = await plan();
    } on RenameException catch (error) {
      print('ERROR:: ${error.message}');
      return;
    }
    print("Old Package Name: $oldPackageName");
    await renamePlan.apply();
    print('Finished updating ios bundle identifier');
  }

  Future<void> _replace(String path) async {
    await replaceInFile(path, oldPackageName, newPackageName);
  }
}

class _RestoredProject {
  final String contents;

  /// The literal id the link had been replaced with.
  final String overwrittenWith;

  _RestoredProject(this.contents, this.overwrittenWith);
}
