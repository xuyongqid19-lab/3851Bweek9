import 'package:flutter/foundation.dart';

/// Portable builds use the launcher's same-origin proxy, including its chosen port.
String? portableApiUrl(String service) {
  if (kIsWeb && const bool.fromEnvironment('PORTABLE_WEB')) {
    return Uri.base.resolve('/api/$service').toString();
  }
  return null;
}
