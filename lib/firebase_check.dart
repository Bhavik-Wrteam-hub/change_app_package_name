import 'dart:convert';
import 'dart:io';

/// Reports Firebase files that still belong to another package name. Firebase
/// refuses to start for an app whose id is not in these files, so a rename is
/// only finished once they are regenerated.
class FirebaseCheck {
  static const String PATH_GOOGLE_SERVICES = 'android/app/google-services.json';
  static const String PATH_GOOGLE_SERVICE_INFO =
      'ios/Runner/GoogleService-Info.plist';

  final Directory root;

  FirebaseCheck(this.root);

  /// The Android package names `google-services.json` has an app for, or null
  /// when the file is missing or unreadable.
  Set<String>? androidPackageNames() {
    final file = File('${root.path}/$PATH_GOOGLE_SERVICES');
    if (!file.existsSync()) return null;
    try {
      final json = jsonDecode(file.readAsStringSync());
      final names = <String>{};
      for (final client in (json['client'] as List? ?? const [])) {
        final name =
            client?['client_info']?['android_client_info']?['package_name'];
        if (name is String) names.add(name);
      }
      return names;
    } catch (_) {
      return null;
    }
  }

  /// The bundle id `GoogleService-Info.plist` was generated for, or null when
  /// the file is missing or has none.
  String? iosBundleId() {
    final file = File('${root.path}/$PATH_GOOGLE_SERVICE_INFO');
    if (!file.existsSync()) return null;
    final match = RegExp(r'<key>BUNDLE_ID</key>\s*<string>([^<]*)</string>')
        .firstMatch(file.readAsStringSync());
    return match?.group(1);
  }

  /// One line per Firebase file that does not cover the given id. An id left
  /// null is not checked.
  List<String> mismatches({String? androidId, String? iosId}) {
    final lines = <String>[];
    final androidNames = androidPackageNames();
    if (androidId != null &&
        androidNames != null &&
        !androidNames.contains(androidId)) {
      lines.add('$PATH_GOOGLE_SERVICES has no app for $androidId.');
    }
    final bundleId = iosBundleId();
    if (iosId != null && bundleId != null && bundleId != iosId) {
      lines.add('$PATH_GOOGLE_SERVICE_INFO is for $bundleId, not $iosId.');
    }
    return lines;
  }
}
