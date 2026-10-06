import 'dart:io';

/// How the command dresses its output: with emoji and colour where the
/// terminal shows them, and as plain text everywhere else.
class OutputStyle {
  final bool emoji;
  final bool color;

  const OutputStyle({required this.emoji, required this.color});

  /// Text only, for logs, scripts and terminals that show neither.
  static const OutputStyle plain = OutputStyle(emoji: false, color: false);

  /// Picks what the terminal the command runs in can show.
  ///
  /// The old Windows console prints emoji as `?` boxes, so on Windows they
  /// are used only in terminals known to draw them. Colour follows the
  /// [NO_COLOR](https://no-color.org) convention and is left out when the
  /// output is not a terminal, so a redirected log holds no escape codes.
  factory OutputStyle.detect({
    Map<String, String>? environment,
    bool? isWindows,
    bool? supportsAnsi,
  }) {
    environment ??= Platform.environment;
    isWindows ??= Platform.isWindows;
    supportsAnsi ??= stdout.hasTerminal && stdout.supportsAnsiEscapes;

    final modernWindowsTerminal = environment.containsKey('WT_SESSION') ||
        environment.containsKey('TERM_PROGRAM') ||
        environment.containsKey('ConEmuPID');
    return OutputStyle(
      emoji: isWindows ? modernWindowsTerminal : environment['TERM'] != 'dumb',
      color: supportsAnsi && !environment.containsKey('NO_COLOR'),
    );
  }

  String get arrow => emoji ? '→' : '->';
  String get bullet => emoji ? '•' : '-';
  String get separator => emoji ? '·' : '-';

  /// Lines under a heading line up with its text, which an icon pushes one
  /// column further right.
  String get indent => emoji ? '   ' : '  ';

  /// [symbol] followed by a space, or [fallback] where emoji are off.
  String icon(String symbol, {String fallback = ''}) {
    if (emoji) return '$symbol ';
    return fallback.isEmpty ? '' : '$fallback ';
  }

  String _paint(String code, String text) =>
      color ? '\x1B[${code}m$text\x1B[0m' : text;

  String bold(String text) => _paint('1', text);
  String dim(String text) => _paint('2', text);
  String red(String text) => _paint('31', text);
  String green(String text) => _paint('32', text);
  String yellow(String text) => _paint('33', text);
  String cyan(String text) => _paint('36', text);
}
