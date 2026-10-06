/// A rename that could not be worked out. Nothing has been written when this
/// is thrown.
class RenameException implements Exception {
  final String message;

  RenameException(this.message);

  @override
  String toString() => message;
}

/// One value a rename replaces, for the summary the command prints.
class RenameChange {
  /// Path relative to the project root.
  final String path;

  /// What the value is, e.g. `applicationId`.
  final String label;
  final String oldValue;
  final String newValue;

  RenameChange(this.path, this.label, this.oldValue, this.newValue);
}

/// What renaming one platform will do, worked out before anything is written
/// so that a problem on either platform leaves both untouched.
class RenamePlan {
  /// `Android` or `iOS`.
  final String platform;

  /// How the project keeps its package name: [schoolBuilderLayout] or
  /// [standardLayout].
  final String layout;

  final List<RenameChange> changes;

  /// Things the user should know that are not errors.
  final List<String> notes;

  final Future<void> Function() _apply;

  static const String schoolBuilderLayout = 'School Builder layout';
  static const String standardLayout = 'standard Flutter layout';

  RenamePlan({
    required this.platform,
    required this.layout,
    required this.changes,
    required Future<void> Function() apply,
    this.notes = const [],
  }) : _apply = apply;

  bool get hasChanges => changes.isNotEmpty;

  Future<void> apply() => _apply();
}
