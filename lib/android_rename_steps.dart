import 'dart:async';
import 'dart:io';

import './file_utils.dart';
import './package_name.dart';
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

  /// `namespace 'com.example.app'`, with either quote and an optional `=`.
  /// Groups: 1 up to the value, 3 the value, 4 the closing quote.
  static final RegExp _namespace =
      RegExp(r'''(\bnamespace\s*=?\s*(['"]))([^'"\r\n]*)(\2)''');

  /// The `package` attribute of the `<manifest>` tag itself, and nothing else
  /// in the file that happens to read `package="..."`.
  /// Groups: 1 up to the value, 2 the value, 3 the closing quote.
  static final RegExp _manifestPackage = RegExp(
      r'''(<manifest\b[^>]*?\bpackage\s*=\s*")([^"]*)(")''',
      dotAll: true);

  /// The package declaration of a Kotlin or Java source.
  /// Groups: 1 up to the name, 2 the name, backticks included.
  static final RegExp _sourcePackage =
      RegExp(r'^(\s*package\s+)([\w.`]+)', multiLine: true);

  static const List<String> _sourceTypes = ['kotlin', 'java'];

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

  /// The School Builder layout. The application id is the fallback a school
  /// build overrides, and it is what the stores and Firebase know the app by.
  ///
  /// The code is renamed with it, so nothing in the project still shows the old
  /// name: `namespace`, the `package` of each manifest, and the package and
  /// folder of the Kotlin and Java sources. A school build never reads these,
  /// so the add-on works the same before and after.
  ///
  /// One case keeps the code as it is: a name with a word Java reserves, such
  /// as `com.new.app`. It is a valid application id, but the Android build
  /// refuses it as a `namespace`, so only the application id takes it.
  Future<RenamePlan> _schoolBuilderPlan(
      String gradleFile, String contents, RegExpMatch hook) async {
    final name = _unescape(hook.group(4)!);
    oldPackageName = name;

    final changes = <RenameChange>[];
    final notes = <String>[];
    final writes = <String, String>{};
    final moved = <String>[];

    var gradle = contents;
    if (name != newPackageName) {
      gradle = contents.replaceRange(hook.start, hook.end,
          '${hook.group(1)}$newPackageName${hook.group(5)}');
      changes
          .add(RenameChange(gradleFile, 'applicationId', name, newPackageName));
    }

    final codePackage = await _codePackage(gradle);
    final reserved = PackageName.javaKeywordsIn(newPackageName);
    if (reserved.isNotEmpty) {
      if (codePackage != null && codePackage != newPackageName) {
        notes.add('$newPackageName is the application id, which is the name '
            'the stores and Firebase use. The code keeps $codePackage '
            '(namespace, manifest package and source folder), because '
            '${reserved.map((word) => '"$word"').join(' and ')} '
            '${reserved.length == 1 ? 'is a reserved word' : 'are reserved words'} '
            'in Java and Android does not accept ${reserved.length == 1 ? 'it' : 'them'} there.');
      }
    } else {
      gradle = _renameNamespace(gradleFile, gradle, changes);
      await _planManifests(changes, writes);
      if (codePackage != null && codePackage != newPackageName) {
        _planSources(codePackage, changes, writes, moved);
      }
    }
    if (gradle != contents) writes[gradleFile] = gradle;

    return RenamePlan(
      platform: 'Android',
      layout: RenamePlan.schoolBuilderLayout,
      changes: changes,
      notes: notes,
      apply: () async {
        for (final write in writes.entries) {
          final file = File(_path(write.key));
          await file.parent.create(recursive: true);
          await file.writeAsString(write.value);
        }
        for (final path in moved) {
          await File(_path(path)).delete();
        }
        for (final type in _sourceTypes) {
          await deleteEmptyDirs(type);
        }
      },
    );
  }

  /// The package the code is in: `namespace`, or the manifest's `package` in a
  /// project old enough to have no `namespace`. Null when neither is there.
  Future<String?> _codePackage(String gradle) async {
    final namespace = _namespace.firstMatch(gradle);
    if (namespace != null) return namespace.group(3);
    final manifest = await readFileAsString(_path(PATH_MANIFEST));
    return manifest == null
        ? null
        : _manifestPackage.firstMatch(manifest)?.group(2);
  }

  String _renameNamespace(
      String gradleFile, String gradle, List<RenameChange> changes) {
    return gradle.replaceAllMapped(_namespace, (match) {
      if (match.group(3) == newPackageName) return match.group(0)!;
      changes.add(RenameChange(
          gradleFile, 'namespace', match.group(3)!, newPackageName));
      return '${match.group(1)}$newPackageName${match.group(4)}';
    });
  }

  /// Only the `package` attribute of the `<manifest>` tag, where there is one.
  Future<void> _planManifests(
      List<RenameChange> changes, Map<String, String> writes) async {
    for (final path in [
      PATH_MANIFEST,
      PATH_MANIFEST_DEBUG,
      PATH_MANIFEST_PROFILE
    ]) {
      final manifest = await readFileAsString(_path(path));
      final match =
          manifest == null ? null : _manifestPackage.firstMatch(manifest);
      if (match == null || match.group(2) == newPackageName) continue;
      changes
          .add(RenameChange(path, 'package', match.group(2)!, newPackageName));
      writes[path] = manifest!.replaceRange(match.start, match.end,
          '${match.group(1)}$newPackageName${match.group(3)}');
    }
  }

  /// Every Kotlin and Java source in [codePackage] or below it gets the new
  /// package and moves to its folder. Imports of the old package follow.
  void _planSources(String codePackage, List<RenameChange> changes,
      Map<String, String> writes, List<String> moved) {
    final imports = RegExp(
        '^(\\s*import\\s+(?:static\\s+)?)${RegExp.escape(codePackage)}(?=\\.)',
        multiLine: true);

    for (final type in _sourceTypes) {
      final base = '$PATH_ACTIVITY$type';
      final directory = Directory(_path(base));
      if (!directory.existsSync()) continue;
      final sources = directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) =>
              file.path.endsWith('.kt') || file.path.endsWith('.java'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      for (final source in sources) {
        final kotlin = source.path.endsWith('.kt');
        String written(String package) =>
            kotlin ? PackageName.inKotlin(package) : package;
        final relative =
            source.path.substring(root.path.length + 1).replaceAll('\\', '/');
        final text = source.readAsStringSync();
        var updated = text.replaceAllMapped(
            imports, (match) => '${match.group(1)}${written(newPackageName)}');

        final declaration = _sourcePackage.firstMatch(updated);
        final package = declaration?.group(2)!.replaceAll('`', '');
        if (declaration == null ||
            package == null ||
            !(package == codePackage || package.startsWith('$codePackage.'))) {
          // A source of another package: only its imports of this one follow.
          if (updated != text) {
            changes.add(
                RenameChange(relative, 'import', codePackage, newPackageName));
            writes[relative] = updated;
          }
          continue;
        }

        final renamed = newPackageName + package.substring(codePackage.length);
        updated = updated.replaceRange(declaration.start, declaration.end,
            '${declaration.group(1)}${written(renamed)}');
        final target = '$base/${renamed.replaceAll('.', '/')}/'
            '${relative.substring(relative.lastIndexOf('/') + 1)}';
        if (target != relative && File(_path(target)).existsSync()) {
          throw RenameException(
              '$target already exists, so $relative can\'t move there. '
              'Remove or rename one of the two first.');
        }
        changes.add(RenameChange(relative, 'package', package, renamed));
        if (target != relative) {
          changes.add(RenameChange(
              relative,
              'moved to',
              relative.substring(0, relative.lastIndexOf('/')),
              target.substring(0, target.lastIndexOf('/'))));
          moved.add(relative);
        }
        writes[target] = updated;
      }
    }
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
