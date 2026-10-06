/// Checks a package name against what each store accepts.
///
/// Android application ids take letters, digits and `_`, with every segment
/// starting with a letter. iOS bundle ids take letters, digits and `-`. A name
/// used for both platforms has to satisfy both, which leaves letters and digits.
class PackageName {
  static final RegExp _android = RegExp(r'^[A-Za-z][A-Za-z0-9_]*$');
  static final RegExp _ios = RegExp(r'^[A-Za-z0-9-]+$');

  /// Why [name] can't be used, or null when it can.
  static String? problem(
    String name, {
    required bool android,
    required bool ios,
  }) {
    final segments = name.split('.');
    if (segments.length < 2) {
      return '"$name" needs at least two parts separated by a dot, '
          'for example com.yourcompany.app.';
    }
    for (final segment in segments) {
      if (segment.isEmpty) {
        return '"$name" has an empty part. Check for a double dot, or a dot '
            'at the start or end.';
      }
      if (android && ios) {
        if (!_android.hasMatch(segment) || !_ios.hasMatch(segment)) {
          return '"$segment" in "$name" can\'t be used for both platforms. '
              'Each part must start with a letter and use only letters and '
              'digits. ("_" is accepted with --android, "-" with --ios.)';
        }
      } else if (android && !_android.hasMatch(segment)) {
        return 'Android does not accept "$segment" in "$name". Each part must '
            'start with a letter and use only letters, digits and "_".';
      } else if (ios && !_ios.hasMatch(segment)) {
        return 'iOS does not accept "$segment" in "$name". Each part may use '
            'only letters, digits and "-".';
      }
    }
    return null;
  }

  /// True when [name] has capital letters. The stores accept them, but treat
  /// `com.App` and `com.app` as two different apps.
  static bool hasUppercase(String name) => name != name.toLowerCase();
}
