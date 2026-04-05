import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

class IOSWidgetIntegration {
  IOSWidgetIntegration._();

  static const _channel = MethodChannel(
    'tw.avianjay.taiwanbus.flutter/ios_widgets',
  );

  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> syncFavoriteGroups(
    Map<String, List<FavoriteStop>> favoriteGroups,
  ) async {
    if (!_isIOS) {
      return;
    }

    final payload = favoriteGroups.map(
      (key, value) =>
          MapEntry(key, value.map((item) => item.toJson()).toList()),
    );
    try {
      await _channel.invokeMethod<void>('syncFavoriteGroups', {
        'json': jsonEncode(payload),
      });
    } on MissingPluginException {
      // Widgets are not wired on every Apple platform/runtime.
    } on PlatformException {
      // Ignore widget sync failures so the main app still works.
    }
  }
}
