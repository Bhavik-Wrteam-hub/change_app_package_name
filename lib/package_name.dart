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

  /// Words Java reserves. An application id may contain them, but the Android
  /// build refuses a `namespace` that does, so such a name can't name the code.
  static const Set<String> javaKeywords = {
    'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch', 'char',
    'class', 'const', 'continue', 'default', 'do', 'double', 'else', 'enum',
    'extends', 'false', 'final', 'finally', 'float', 'for', 'goto', 'if',
    'implements', 'import', 'instanceof', 'int', 'interface', 'long', 'native',
    'new', 'null', 'package', 'private', 'protected', 'public', 'return',
    'short', 'static', 'strictfp', 'super', 'switch', 'synchronized', 'this',
    'throw', 'throws', 'transient', 'true', 'try', 'void', 'volatile', 'while',
    '_', //
  };

  /// Words Kotlin reserves everywhere. A package may contain them, written in
  /// backticks: `` package `in`.co.school ``.
  static const Set<String> kotlinHardKeywords = {
    'as', 'break', 'class', 'continue', 'do', 'else', 'false', 'for', 'fun',
    'if', 'in', 'interface', 'is', 'null', 'object', 'package', 'return',
    'super', 'this', 'throw', 'true', 'try', 'typealias', 'typeof', 'val',
    'var', 'when', 'while', //
  };

  /// The parts of [name] that Java reserves, in order and without repeats.
  static List<String> javaKeywordsIn(String name) =>
      name.split('.').where(javaKeywords.contains).toSet().toList();

  /// [name] as Kotlin source writes it.
  static String inKotlin(String name) => name
      .split('.')
      .map((part) => kotlinHardKeywords.contains(part) ? '`$part`' : part)
      .join('.');
}
