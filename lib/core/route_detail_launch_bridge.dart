import 'dart:async';

import 'app_launch_service.dart';

typedef RouteDetailLaunchHandler =
    Future<bool> Function(AppLaunchAction action);

class RouteDetailLaunchBridge {
  RouteDetailLaunchBridge._();

  static final RouteDetailLaunchBridge instance = RouteDetailLaunchBridge._();

  final List<RouteDetailLaunchHandler> _handlers = <RouteDetailLaunchHandler>[];

  void attach(RouteDetailLaunchHandler handler) {
    _handlers.remove(handler);
    _handlers.add(handler);
  }

  void detach(RouteDetailLaunchHandler handler) {
    _handlers.remove(handler);
  }

  Future<bool> tryHandle(AppLaunchAction action) async {
    for (final handler in _handlers.reversed.toList()) {
      if (await handler(action)) {
        return true;
      }
    }
    return false;
  }
}
