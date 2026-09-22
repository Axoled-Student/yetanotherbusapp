import 'dart:async';
import 'dart:convert';

import 'package:brotli/brotli.dart' as brotli;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const apiAcceptedEncodings = 'br, gzip';
const apiCompressionHeaders = <String, String>{
  'Accept-Encoding': apiAcceptedEncodings,
};
const apiJsonHeaders = <String, String>{
  'Accept': 'application/json',
  ...apiCompressionHeaders,
};
const apiJsonContentHeaders = <String, String>{
  ...apiJsonHeaders,
  'Content-Type': 'application/json',
};

const apiRequestTimeout = Duration(seconds: 15);
const apiDownloadIdleTimeout = Duration(seconds: 30);

Future<http.Response> apiGet(
  http.Client client,
  Uri uri, {
  Map<String, String>? headers,
}) {
  return client.get(uri, headers: headers).timeout(apiRequestTimeout);
}

Future<http.Response> apiPost(
  http.Client client,
  Uri uri, {
  Map<String, String>? headers,
  Object? body,
}) {
  return client
      .post(uri, headers: headers, body: body)
      .timeout(apiRequestTimeout);
}

Future<http.Response> apiPut(
  http.Client client,
  Uri uri, {
  Map<String, String>? headers,
  Object? body,
}) {
  return client
      .put(uri, headers: headers, body: body)
      .timeout(apiRequestTimeout);
}

class TimedHttpClient extends http.BaseClient {
  TimedHttpClient(this._delegate);

  final http.Client _delegate;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _delegate.send(request).timeout(apiRequestTimeout);
  }

  @override
  void close() => _delegate.close();
}

List<int> apiResponseBodyBytes(http.Response response) {
  return _decodeBodyBytes(response.bodyBytes, _contentEncodings(response));
}

List<int> _decodeBodyBytes(List<int> bytes, List<String> encodings) {
  for (final encoding in encodings.reversed) {
    switch (encoding) {
      case 'br':
        bytes = _tryDecode(() => brotli.brotli.decode(bytes), bytes);
        break;
      case 'gzip':
      case 'x-gzip':
      case 'identity':
        break;
    }
  }
  return bytes;
}

String apiResponseText(http.Response response) {
  return utf8.decode(apiResponseBodyBytes(response));
}

Object? apiDecodeJsonResponse(http.Response response) {
  return jsonDecode(apiResponseText(response));
}

/// Offloads decompression, UTF-8 and JSON decoding for expensive native
/// responses. Small plain responses avoid the cost of starting an isolate.
/// Web uses the same decoder but remains on the browser's main thread.
Future<Object?> apiDecodeJsonResponseAsync(http.Response response) async {
  final encodings = _contentEncodings(response);
  final payload = (response.bodyBytes, encodings);
  if (!kIsWeb &&
      (response.bodyBytes.length >= 64 * 1024 || encodings.contains('br'))) {
    return compute(_decodeJsonPayload, payload, debugLabel: 'api.decodeJson');
  }
  return _decodeJsonPayload(payload);
}

Object? _decodeJsonPayload((Uint8List, List<String>) payload) {
  return jsonDecode(utf8.decode(_decodeBodyBytes(payload.$1, payload.$2)));
}

List<String> _contentEncodings(http.Response response) {
  final header = response.headers.entries
      .where((entry) => entry.key.toLowerCase() == 'content-encoding')
      .map((entry) => entry.value)
      .firstOrNull;
  if (header == null || header.trim().isEmpty) {
    return const [];
  }
  return header
      .split(',')
      .map((value) => value.trim().toLowerCase())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}

List<int> _tryDecode(List<int> Function() decode, List<int> fallback) {
  try {
    return decode();
  } catch (_) {
    return fallback;
  }
}
