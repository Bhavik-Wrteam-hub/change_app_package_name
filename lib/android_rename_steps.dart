import 'dart:async';
import 'dart:io';

import './file_utils.dart';
import './rename_plan.dart';

class AndroidRenameSteps {
  final String newPackageName;

  /// The Flutter project, the folder that holds `android/`.
  final Directory root;
  String? oldPackageName;

  static const String PATH_BUILD_GRADLE = 'android/app/build.gradle';
  static const String PATH_MANIFEST =
      'android/app/src/main/AndroidManifest.xml';
  static const String PATH_MANIFEST_DEBUG =
      'android/app/src/debug/AndroidManifest.xml';
  static const String PATH_MANIFEST_PROFILE =
      'android/app/src/profile/AndroidManifest.xml';

  static const String PATH_ACTIVITY = 'android/app/src/main/';

  /// How the School Builder layout (eSchool SaaS v1.12.0 and later) keeps the
  /// application id: as the fallback of a property a school build overrides,
  ///
  ///     def schoolApplicationId = schoolProperties.getProperty('applicationId', 'com.example.app')
  ///
  /// Groups: 1 everything up to the value, 4 the value, 5 the rest.
  static final RegExp schoolBuilderApplicationId = RegExp(
      r'''(getProperty\(\s*(['"])applicationId\2\s*,\s*(['"]))((?:\\.|[^'"\\\r\n])*)(\3\s*\))''');

  static final RegExp _standardApplicationId = RegExp(
      r'applicationId\s*=?\s*"(.*)"',
      caseSensitive: true,
      multiLine: false);

  AndroidRenameSteps(this.newPackageName, {Directory? root})
      : root = root ?? Directory.current;

  String _path(String relative) => '${root.path}/$relative';

  /// True when the project has an Android app at all.
  bool get hasPlatform => Directory(_path('android')).existsSync();

  Future<String> _gradleFile() async {
    var gradleFile = PATH_BUILD_GRADLE;
    if (!await File(_path(gradleFile)).exists()) {
      gradleFile = "$gradleFile.kts";
    }
    if (!await File(_path(gradleFile)).exists()) {
      throw RenameException(
          'build.gradle file not found, Check if you have a correct android directory present in your project'
          '\n\nrun " flutter create . " to regenerate missing files.');
    }
    return gradleFile;
  }

  /// The application id the project builds with now, or null when it can't
  /// be read.
  Future<String?> currentPackageName() async {
    try {
      final contents = await readFileAsString(_path(await _gradleFile()));
      final hook = schoolBuilderApplicationId.firstMatch(contents!);
      if (hook != null) return _unescape(hook.group(4)!);
      return _standardApplicationId.firstMatch(contents)?.group(1);
    } on RenameException {
      return null;
    }
  }

  static String _unescape(String value) =>
      value.replaceAllMapped(RegExp(r'\\(.)'), (match) => match.group(1)!);

  /// Works out the rename without writing anything.
  Future<RenamePlan> plan() async {
    final gradleFile = await _gradleFile();
    final contents = (await readFileAsString(_path(gradleFile)))!;

    final hooks = schoolBuilderApplicationId.allMatches(contents).toList();
    if (hooks.length > 1) {
      throw RenameException(
          '$gradleFile sets the applicationId fallback in ${hooks.length} places, '
          'so it is not clear which one to change. Keep a single '
          "getProperty('applicationId', '...') line.");
    }
    if (hooks.length == 1) {
      return _schoolBuilderPlan(gradleFile, contents, hooks.single);
    }

    final match = _standardApplicationId.firstMatch(contents);
    if (match == null) {
      throw RenameException(
          'applicationId not found in build.gradle file, Please file an issue on github with $gradleFile file attached.');
    }
    final name = match.group(1)!;
    oldPackageName = name;
    return RenamePlan(
      platform: 'Android',
      layout: RenamePlan.standardLayout,
      changes: name == newPackageName
          ? const []
          : [RenameChange(gradleFile, 'applicationId', name, newPackageName)],
      notes: name == newPackageName
          ? const []
          : const [
              'The manifests and MainActivity are renamed too, and '
                  'MainActivity moves to the folder of the new package.'
            ],
      apply: () => _applyStandard(gradleFile),
    );
  }

  /// The School Builder layout: only the application id fallback changes.
  /// `namespace`, the manifest's `package` and the Kotlin folder name the code,
  /// not the app, and stay as they are, the same as when the add-on builds a
  /// school under its own application id.
  RenamePlan _schoolBuilderPlan(
      String gradleFile, String contents, RegExpMatch hook) {
    final name = _unescape(hook.group(4)!);
    oldPackageName = name;
    if (name == newPackageName) {
      return RenamePlan(
        platform: 'Android',
        layout: RenamePlan.schoolBuilderLayout,
        changes: const [],
        apply: () async {},
      );
    }
    final updated = contents.replaceRange(hook.start, hook.end,
        '${hook.group(1)}$newPackageName${hook.group(5)}');
    return RenamePlan(
      platform: 'Android',
      layout: RenamePlan.schoolBuilderLayout,
      changes: [
        RenameChange(gradleFile, 'applicationId', name, newPackageName),
      ],
      apply: () => writeFileFromString(_path(gradleFile), updated),
    );
  }

  Future<void> process() async {
    print("Running for android");
    final RenamePlan renamePlan;
    try {
      renamePlan = await plan();
    } on RenameException catch (error) {
      print('ERROR:: ${error.message}');
      return;
    }
    print("Old Package Name: $oldPackageName");
    await renamePlan.apply();
    print('Finished updating android package name');
  }

  Future<void> _applyStandard(String gradleFile) async {
    await _replace(_path(gradleFile));

    var mText = 'package="$newPackageName"';
    var mRegex = 'package="[^"]*"';

    await _replaceInManifest(PATH_MANIFEST, mRegex, mText);
    await _replaceInManifest(PATH_MANIFEST_DEBUG, mRegex, mText);
    await _replaceInManifest(PATH_MANIFEST_PROFILE, mRegex, mText);

    await updateMainActivity();
  }

  /// Not every project has a debug or profile manifest.
  Future<void> _replaceInManifest(
      String manifest, String regex, String replacement) async {
    if (!await File(_path(manifest)).exists()) return;
    await replaceInFileRegex(_path(manifest), regex, replacement);
  }

  Future<void> updateMainActivity() async {
    var path = await findMainActivity(type: 'java');
    if (path != null) {
      await processMainActivity(path, 'java');
    }

    path = await findMainActivity(type: 'kotlin');
    if (path != null) {
      await processMainActivity(path, 'kotlin');
    }
  }

  Future<void> processMainActivity(File path, String type) async {
    var extension = type == 'java' ? 'java' : 'kt';
    await replaceInFileRegex(
        path.path, r'^(package (?:\.|\w)+)', "package ${newPackageName}");

    String newPackagePath = newPackageName.replaceAll('.', '/');
    String newPath = _path('${PATH_ACTIVITY}${type}/$newPackagePath');

    await Directory(newPath).create(recursive: true);
    await path.rename(newPath + '/MainActivity.$extension');

    await deleteEmptyDirs(type);
  }

  Future<void> _replace(String path) async {
    await replaceInFile(path, oldPackageName, newPackageName);
  }

  Future<void> deleteEmptyDirs(String type) async {
    var dirs = await dirContents(Directory(_path(PATH_ACTIVITY + type)));
    dirs = dirs.reversed.toList();
    for (var dir in dirs) {
      if (dir is Directory) {
        if (dir.listSync().toList().isEmpty) {
          dir.deleteSync();
        }
      }
    }
  }

  Future<File?> findMainActivity({String type = 'java'}) async {
    var files = await dirContents(Directory(_path(PATH_ACTIVITY + type)));
    String extension = type == 'java' ? 'java' : 'kt';
    for (var item in files) {
      if (item is File) {
        if (item.path.endsWith('MainActivity.' + extension)) {
          return item;
        }
      }
    }
    return null;
  }

  Future<List<FileSystemEntity>> dirContents(Directory dir) {
    if (!dir.existsSync()) return Future.value([]);
    var files = <FileSystemEntity>[];
    var completer = Completer<List<FileSystemEntity>>();
    var lister = dir.list(recursive: true);
    lister.listen((file) => files.add(file),
        // should also register onError
        onDone: () => completer.complete(files));
    return completer.future;
  }
}
