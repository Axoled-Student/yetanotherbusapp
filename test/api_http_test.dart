import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:taiwanbus_flutter/core/api_http.dart';

void main() {
  test('API headers advertise Brotli before gzip', () {
    expect(apiJsonHeaders['Accept-Encoding'], 'br, gzip');
    expect(apiJsonHeaders['Accept'], 'application/json');
  });

  test('apiResponseText decodes Brotli response bodies', () {
    const encoded = <int>[
      139,
      5,
      128,
      104,
      101,
      108,
      108,
      111,
      32,
      98,
      114,
      111,
      116,
      108,
      105,
      3,
    ];
    final response = http.Response.bytes(
      encoded,
      200,
      headers: const {'Content-Encoding': 'br'},
    );

    expect(apiResponseText(response), 'hello brotli');
  });

  test('async decoder preserves small JSON values and UTF-8', () async {
    for (final value in <Object?>[
      null,
      42,
      ['臺北車站', true],
      {'stops': [], 'name': '公車'},
    ]) {
      final response = http.Response.bytes(utf8.encode(jsonEncode(value)), 200);
      expect(await apiDecodeJsonResponseAsync(response), value);
    }
  });

  test(
    'large JSON can cross the isolate boundary without losing data',
    () async {
      final stops = List.generate(
        5000,
        (index) => {'stopid': index, 'name': '測試站 $index', 'eta': null},
      );
      final response = http.Response.bytes(utf8.encode(jsonEncode(stops)), 200);
      expect(response.bodyBytes.length, greaterThan(64 * 1024));
      expect(await apiDecodeJsonResponseAsync(response), stops);
    },
  );

  test('async decoder handles Brotli and already decoded bodies', () async {
    // Brotli uncompressed block containing the JSON string "hello brotli".
    final compressed = http.Response.bytes(
      [139, 6, 128, ...utf8.encode('"hello brotli"'), 3],
      200,
      headers: {'Content-Encoding': 'br'},
    );
    expect(await apiDecodeJsonResponseAsync(compressed), 'hello brotli');
    final decoded = http.Response.bytes(
      utf8.encode('{"name":"臺北"}'),
      200,
      headers: {'Content-Encoding': 'br'},
    );
    expect(await apiDecodeJsonResponseAsync(decoded), {'name': '臺北'});
  });

  test('async decoder propagates malformed JSON from both paths', () async {
    for (final body in ['{', '${' ' * (64 * 1024)}{']) {
      await expectLater(
        apiDecodeJsonResponseAsync(http.Response(body, 200)),
        throwsFormatException,
      );
    }
  });
}
