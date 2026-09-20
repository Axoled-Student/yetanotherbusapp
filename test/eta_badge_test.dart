import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taiwanbus_flutter/core/models.dart';
import 'package:taiwanbus_flutter/widgets/eta_badge.dart';

void main() {
  const stop = StopInfo(
    routeKey: 1,
    pathId: 0,
    stopId: 1,
    stopName: '測試站',
    sequence: 1,
    lon: 121.5,
    lat: 25,
    sec: 120,
  );

  Widget buildBadge({required bool isLoading}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: EtaBadge(
            stop: stop,
            alwaysShowSeconds: false,
            isLoading: isLoading,
          ),
        ),
      ),
    );
  }

  testWidgets('crossfades from loading to ETA without resizing', (
    tester,
  ) async {
    await tester.pumpWidget(buildBadge(isLoading: true));
    final badge = find.byType(EtaBadge);
    expect(tester.getSize(badge), const Size(58, 58));
    expect(find.text('載入中'), findsOneWidget);

    await tester.pumpWidget(buildBadge(isLoading: false));
    await tester.pump(const Duration(milliseconds: 110));
    expect(find.text('載入中'), findsOneWidget);
    expect(find.text('2分'), findsOneWidget);
    final etaScale = find.ancestor(
      of: find.byKey(const ValueKey('eta-badge-loading-false')),
      matching: find.byType(ScaleTransition),
    );
    expect(tester.widget<ScaleTransition>(etaScale).scale.value, greaterThan(1));
    expect(tester.getSize(badge), const Size(58, 58));

    await tester.pump(const Duration(milliseconds: 420));
    expect(find.text('載入中'), findsNothing);
    expect(find.text('2分'), findsOneWidget);
  });
}
