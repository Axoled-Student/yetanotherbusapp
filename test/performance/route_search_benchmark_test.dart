// Run with: flutter test test/performance/route_search_benchmark_test.dart --reporter expanded
// For the browser: add --platform chrome. This is a CPU microbenchmark, not FPS.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:taiwanbus_flutter/core/models.dart';
import 'package:taiwanbus_flutter/core/route_search_ranking.dart';

void main() {
  test('compare route ranking CPU work on a large deterministic fixture', () {
    final routes = List.generate(
      10000,
      (i) => RouteSummary(
        sourceProvider: i.isEven ? 'TXG' : 'TPE',
        hashMd5: '',
        routeKey: i,
        routeId: 'route-$i',
        routeName: ' ${i % 3 == 0 ? '藍' : ''}${i % 1000} ',
        officialRouteName: '',
        description: '起點 $i 至終點 ${i + 1}',
        category: '',
        sequence: i,
        rtrip: 0,
      ),
    )..shuffle(Random(84));
    int priority(BusProvider provider) => provider == BusProvider.txg ? 0 : 1;
    List<RouteSummary> baseline() => routes.toList()
      ..sort(
        (a, b) => compareRouteSummarySearchPriority(
          a,
          b,
          query: '12',
          providerPriority: priority,
        ),
      );
    List<RouteSummary> optimized() => sortRouteSummariesForQuery(
      routes,
      query: '12',
      providerPriority: priority,
    );

    expect(optimized(), baseline());
    for (var i = 0; i < 5; i++) {
      baseline();
      optimized();
    }
    final before = <int>[];
    final after = <int>[];
    void measure(List<RouteSummary> Function() operation, List<int> samples) {
      final clock = Stopwatch()..start();
      operation();
      samples.add(clock.elapsedMicroseconds);
    }

    for (var i = 0; i < 15; i++) {
      // Alternate ordering to reduce warm-up/GC bias.
      if (i.isEven) {
        measure(baseline, before);
        measure(optimized, after);
      } else {
        measure(optimized, after);
        measure(baseline, before);
      }
    }
    before.sort();
    after.sort();
    // No timing assertion: shared CI machines have unpredictable scheduling.
    // ignore: avoid_print
    print(
      '10,000 routes, median of 15: comparator=${before[7]} us, '
      'cached ranks=${after[7]} us',
    );
  });
}
