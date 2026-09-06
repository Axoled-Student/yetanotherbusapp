import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taiwanbus_flutter/core/auth_token_store.dart';
import 'package:taiwanbus_flutter/core/weather_service.dart';
import 'package:taiwanbus_flutter/screens/weather_screen.dart';
import 'package:taiwanbus_flutter/widgets/weather_app_bar_title.dart';

http.Response _okResponse(Object body) =>
    http.Response(jsonEncode(body), 200, headers: const {
      'content-type': 'application/json; charset=utf-8',
    });

String _two(int value) => value.toString().padLeft(2, '0');

/// Open-Meteo's `timezone=auto` shape: naive local time, no offset suffix.
String _isoMinute(DateTime time) =>
    '${time.year}-${_two(time.month)}-${_two(time.day)}'
    'T${_two(time.hour)}:${_two(time.minute)}';

String _isoDate(DateTime time) =>
    '${time.year}-${_two(time.month)}-${_two(time.day)}';

const int _taipeiOffsetSeconds = 8 * 3600;

/// Top of the current hour in Taipei, as the service will compute it.
///
/// If the hour is about to roll over, wait it out — otherwise the payload and
/// the service's own clock read could land in different hours.
Future<DateTime> _locationHour() async {
  const offset = Duration(seconds: _taipeiOffsetSeconds);
  var now = DateTime.now().toUtc().add(offset);
  if (now.minute == 59 && now.second >= 55) {
    await Future<void>.delayed(const Duration(seconds: 6));
    now = DateTime.now().toUtc().add(offset);
  }
  return DateTime.utc(now.year, now.month, now.day, now.hour);
}

void main() {
  tearDown(() {
    AuthTokenStore.token = null;
  });

  test('fetchCurrent requests only current temperature and weather code', () async {
    late Uri captured;
    final service = WeatherService(
      client: MockClient((request) async {
        captured = request.url;
        return _okResponse({
          'current': {'temperature_2m': 32.4, 'weather_code': 0},
        });
      }),
    );

    final snapshot = await service.fetchCurrent(
      latitude: 25.03746,
      longitude: 121.56398,
    );

    expect(captured.host, 'api.open-meteo.com');
    expect(captured.path, '/v1/forecast');
    expect(captured.queryParameters['current'], 'temperature_2m,weather_code');
    // Coordinates are rounded to ~1.1km before leaving the device.
    expect(captured.queryParameters['latitude'], '25.04');
    expect(captured.queryParameters['longitude'], '121.56');
    expect(captured.queryParameters.containsKey('hourly'), isFalse);
    expect(captured.queryParameters.containsKey('daily'), isFalse);
    expect(snapshot.temperatureC, 32.4);
    expect(snapshot.displayTemperature, 32);
    expect(snapshot.weatherCode, 0);
  });

  test('fetchCurrent never sends the signed-in auth token to Open-Meteo', () async {
    AuthTokenStore.token = 'test-token';
    Map<String, String> captured = const {};
    final service = WeatherService(
      client: MockClient((request) async {
        captured = request.headers;
        return _okResponse({
          'current': {'temperature_2m': 20.0, 'weather_code': 3},
        });
      }),
    );

    await service.fetchCurrent(latitude: 25.0, longitude: 121.5);

    expect(captured['Authorization'] ?? captured['authorization'], isNull);
  });

  test('fetchCurrent accepts a whole-number temperature', () async {
    final service = WeatherService(
      client: MockClient(
        (request) async => _okResponse({
          'current': {'temperature_2m': 26, 'weather_code': 61},
        }),
      ),
    );

    final snapshot = await service.fetchCurrent(
      latitude: 25.0,
      longitude: 121.5,
    );

    expect(snapshot.temperatureC, 26.0);
    expect(snapshot.displayTemperature, 26);
  });

  test('fetchCurrent tolerates a missing weather code', () async {
    final service = WeatherService(
      client: MockClient(
        (request) async => _okResponse({
          'current': {'temperature_2m': 18.2},
        }),
      ),
    );

    final snapshot = await service.fetchCurrent(
      latitude: 25.0,
      longitude: 121.5,
    );

    expect(snapshot.weatherCode, isNull);
  });

  test('fetchCurrent serves the cache within the TTL and refetches on force', () async {
    var calls = 0;
    final service = WeatherService(
      client: MockClient((request) async {
        calls += 1;
        return _okResponse({
          'current': {'temperature_2m': 30.0, 'weather_code': 0},
        });
      }),
    );

    await service.fetchCurrent(latitude: 25.0, longitude: 121.5);
    await service.fetchCurrent(latitude: 25.001, longitude: 121.502);
    expect(calls, 1);

    await service.fetchCurrent(
      latitude: 25.0,
      longitude: 121.5,
      force: true,
    );
    expect(calls, 2);
  });

  test('fetchCurrent refetches when the rounded location changes', () async {
    var calls = 0;
    final service = WeatherService(
      client: MockClient((request) async {
        calls += 1;
        return _okResponse({
          'current': {'temperature_2m': 30.0, 'weather_code': 0},
        });
      }),
    );

    await service.fetchCurrent(latitude: 25.0, longitude: 121.5);
    await service.fetchCurrent(latitude: 22.63, longitude: 120.3);

    expect(calls, 2);
  });

  test('fetchCurrent throws a readable error on a failed response', () async {
    final service = WeatherService(
      client: MockClient((request) async => http.Response('nope', 503)),
    );

    await expectLater(
      service.fetchCurrent(latitude: 25.0, longitude: 121.5),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('天氣'),
        ),
      ),
    );
  });

  test('fetchCurrent throws on malformed payloads', () async {
    Future<void> expectRejects(String body) async {
      final service = WeatherService(
        client: MockClient((request) async => http.Response(body, 200)),
      );
      await expectLater(
        service.fetchCurrent(latitude: 25.0, longitude: 121.5),
        throwsA(isA<Exception>()),
      );
    }

    await expectRejects('not json');
    await expectRejects('{}');
    await expectRejects('{"current":"x"}');
    await expectRejects('{"current":{"temperature_2m":"warm"}}');
  });

  test('weatherConditionLabel ports the WMO mapping', () {
    expect(weatherConditionLabel(0), '晴');
    expect(weatherConditionLabel(1), '晴時多雲');
    expect(weatherConditionLabel(3), '陰');
    expect(weatherConditionLabel(45), '霧');
    expect(weatherConditionLabel(51), '小雨');
    expect(weatherConditionLabel(61), '小雨');
    expect(weatherConditionLabel(56), '凍雨');
    expect(weatherConditionLabel(75), '大雪');
    expect(weatherConditionLabel(82), '大陣雨');
    expect(weatherConditionLabel(99), '雷陣雨伴冰雹');
    // Unmapped and null codes fall back instead of throwing.
    expect(weatherConditionLabel(52), '多雲');
    expect(weatherConditionLabel(null), '多雲');
  });

  test('weatherConditionIcon covers the ported ranges', () {
    expect(weatherConditionIcon(null), Icons.cloud_outlined);
    expect(weatherConditionIcon(0), Icons.wb_sunny);
    expect(weatherConditionIcon(2), Icons.wb_cloudy);
    expect(weatherConditionIcon(3), Icons.cloud);
    expect(weatherConditionIcon(48), Icons.blur_on);
    // Codes the label map omits still resolve because the icon map is ranged.
    expect(weatherConditionIcon(52), Icons.grain);
    expect(weatherConditionIcon(64), Icons.opacity);
    expect(weatherConditionIcon(74), Icons.ac_unit);
    expect(weatherConditionIcon(81), Icons.grain);
    expect(weatherConditionIcon(86), Icons.ac_unit);
    expect(weatherConditionIcon(95), Icons.flash_on);
  });

  test('fetchForecast asks for current, hourly and daily in one call', () async {
    late Uri captured;
    final service = WeatherService(
      client: MockClient((request) async {
        captured = request.url;
        return _okResponse({
          'utc_offset_seconds': _taipeiOffsetSeconds,
          'current': {'temperature_2m': 32.4, 'weather_code': 0},
        });
      }),
    );

    await service.fetchForecast(latitude: 25.03746, longitude: 121.56398);

    final query = captured.queryParameters;
    expect(captured.host, 'api.open-meteo.com');
    expect(captured.path, '/v1/forecast');
    // Coordinates stay rounded on the heavier call too.
    expect(query['latitude'], '25.04');
    expect(query['longitude'], '121.56');
    expect(query['current'], contains('apparent_temperature'));
    expect(query['current'], contains('relative_humidity_2m'));
    expect(query['current'], contains('wind_speed_10m'));
    expect(query['hourly'], 'temperature_2m,precipitation_probability,weather_code');
    expect(query['daily'], contains('temperature_2m_max'));
    expect(query['daily'], contains('precipitation_probability_max'));
    expect(query['daily'], contains('sunrise'));
    expect(query['timezone'], 'auto');
    expect(query['forecast_days'], '7');
  });

  test('fetchForecast reads current conditions beyond the temperature', () async {
    final service = WeatherService(
      client: MockClient(
        (request) async => _okResponse({
          'utc_offset_seconds': _taipeiOffsetSeconds,
          'current': {
            'temperature_2m': 32.4,
            'weather_code': 1,
            'apparent_temperature': 35.1,
            'relative_humidity_2m': 68,
            'wind_speed_10m': 12.3,
          },
        }),
      ),
    );

    final forecast = await service.fetchForecast(
      latitude: 25.0,
      longitude: 121.5,
    );

    expect(forecast.current.displayTemperature, 32);
    expect(forecast.current.weatherCode, 1);
    expect(forecast.apparentTemperatureC, 35.1);
    expect(forecast.relativeHumidity, 68);
    expect(forecast.windSpeedKph, 12.3);
    // Missing hourly/daily blocks degrade to empty rather than throwing.
    expect(forecast.hourly, isEmpty);
    expect(forecast.daily, isEmpty);
    expect(forecast.sunrise, isNull);
  });

  test('fetchForecast keeps the hour in progress and caps at 24 hours', () async {
    final base = await _locationHour();
    // Two stale slots, then the hour in progress plus 29 future hours.
    final times = <String>[
      _isoMinute(base.subtract(const Duration(hours: 3))),
      _isoMinute(base.subtract(const Duration(hours: 2))),
      for (var i = 0; i < 30; i++) _isoMinute(base.add(Duration(hours: i))),
    ];

    final service = WeatherService(
      client: MockClient(
        (request) async => _okResponse({
          'utc_offset_seconds': _taipeiOffsetSeconds,
          'current': {'temperature_2m': 30.0, 'weather_code': 0},
          'hourly': {
            'time': times,
            'temperature_2m': [
              for (var i = 0; i < times.length; i++) 20.0 + i,
            ],
            'weather_code': [for (var i = 0; i < times.length; i++) 0],
            'precipitation_probability': [
              for (var i = 0; i < times.length; i++) i,
            ],
          },
        }),
      ),
    );

    final forecast = await service.fetchForecast(
      latitude: 25.0,
      longitude: 121.5,
    );

    expect(forecast.hourly, hasLength(WeatherService.forecastHourCount));
    expect(forecast.hourly.first.time, base);
    expect(
      forecast.hourly.last.time,
      base.add(const Duration(hours: 23)),
    );
    // Index 2 of the payload is the first kept slot.
    expect(forecast.hourly.first.temperatureC, 22.0);
    expect(forecast.hourly.first.precipitationProbability, 2);
    // Stale slots never make it through.
    expect(
      forecast.hourly.any(
        (hour) => hour.time.isBefore(base.subtract(const Duration(hours: 1))),
      ),
      isFalse,
    );
  });

  test('forecast times stay on the location wall clock', () async {
    final service = WeatherService(
      client: MockClient(
        (request) async => _okResponse({
          // Deliberately not the test machine's offset.
          'utc_offset_seconds': -8 * 3600,
          'current': {'temperature_2m': 18.0, 'weather_code': 3},
          'daily': {
            'time': ['2026-09-06'],
            'temperature_2m_max': [24.0],
            'temperature_2m_min': [15.0],
            'weather_code': [3],
            'precipitation_probability_max': [10],
            'sunrise': ['2026-09-06T05:42'],
            'sunset': ['2026-09-06T19:07'],
          },
        }),
      ),
    );

    final forecast = await service.fetchForecast(
      latitude: 37.77,
      longitude: -122.42,
    );

    // The digits are preserved exactly, whatever timezone the test runs in.
    expect(forecast.sunrise, DateTime.utc(2026, 9, 6, 5, 42));
    expect(forecast.sunset, DateTime.utc(2026, 9, 6, 19, 7));
    expect(clockLabel(forecast.sunrise), '05:42');
    expect(clockLabel(forecast.sunset), '19:07');
    expect(forecast.daily.single.date, DateTime.utc(2026, 9, 6));
  });

  test('forecast times survive wall clocks inside a DST gap', () async {
    // 2026-03-08T02:30 does not exist in US timezones (spring forward) and
    // 2026-03-29T02:30 does not exist in most of Europe. Parsing either as a
    // local time would shift it an hour, duplicating one hourly slot and
    // dropping another for anyone in those zones.
    final service = WeatherService(
      client: MockClient(
        (request) async => _okResponse({
          'utc_offset_seconds': -5 * 3600,
          'current': {'temperature_2m': 8.0, 'weather_code': 3},
          'daily': {
            'time': ['2026-03-08'],
            'temperature_2m_max': [12.0],
            'temperature_2m_min': [3.0],
            'weather_code': [3],
            'precipitation_probability_max': [20],
            'sunrise': ['2026-03-08T02:30'],
            'sunset': ['2026-03-29T02:30'],
          },
        }),
      ),
    );

    final forecast = await service.fetchForecast(
      latitude: 40.71,
      longitude: -74.01,
    );

    expect(forecast.sunrise, DateTime.utc(2026, 3, 8, 2, 30));
    expect(forecast.sunset, DateTime.utc(2026, 3, 29, 2, 30));
    expect(clockLabel(forecast.sunrise), '02:30');
  });

  test('fetchForecast caps the week and clamps rain percentages', () async {
    final start = DateTime.utc(2026, 9, 6);
    final service = WeatherService(
      client: MockClient(
        (request) async => _okResponse({
          'utc_offset_seconds': _taipeiOffsetSeconds,
          'current': {'temperature_2m': 30.0, 'weather_code': 0},
          'daily': {
            'time': [
              for (var i = 0; i < 10; i++)
                _isoDate(start.add(Duration(days: i))),
            ],
            'temperature_2m_max': [
              for (var i = 0; i < 10; i++) 30.0 + i,
            ],
            'temperature_2m_min': [for (var i = 0; i < 10; i++) 24.0],
            'weather_code': [for (var i = 0; i < 10; i++) 61],
            // Out of range, negative, absent and non-numeric all normalise.
            'precipitation_probability_max': [150, -20, null, 'x', 40],
          },
        }),
      ),
    );

    final forecast = await service.fetchForecast(
      latitude: 25.0,
      longitude: 121.5,
    );

    expect(forecast.daily, hasLength(WeatherService.forecastDayCount));
    expect(forecast.daily.first.date, start);
    expect(forecast.daily.first.displayHigh, 30);
    expect(forecast.daily.first.displayLow, 24);
    expect(
      forecast.daily.map((day) => day.precipitationProbability).toList(),
      [100, 0, 0, 0, 40, 0, 0],
    );
  });

  test('fetchForecast caches and honours force', () async {
    var calls = 0;
    final service = WeatherService(
      client: MockClient((request) async {
        calls += 1;
        return _okResponse({
          'utc_offset_seconds': _taipeiOffsetSeconds,
          'current': {'temperature_2m': 30.0, 'weather_code': 0},
        });
      }),
    );

    await service.fetchForecast(latitude: 25.0, longitude: 121.5);
    await service.fetchForecast(latitude: 25.001, longitude: 121.502);
    expect(calls, 1);

    await service.fetchForecast(
      latitude: 25.0,
      longitude: 121.5,
      force: true,
    );
    expect(calls, 2);

    await service.fetchForecast(latitude: 22.63, longitude: 120.3);
    expect(calls, 3);
  });

  test('a forecast also satisfies the app bar chip', () async {
    var calls = 0;
    final service = WeatherService(
      client: MockClient((request) async {
        calls += 1;
        return _okResponse({
          'utc_offset_seconds': _taipeiOffsetSeconds,
          'current': {'temperature_2m': 28.6, 'weather_code': 2},
        });
      }),
    );

    await service.fetchForecast(latitude: 25.0, longitude: 121.5);
    final snapshot = await service.fetchCurrent(
      latitude: 25.0,
      longitude: 121.5,
    );

    expect(calls, 1);
    expect(snapshot.displayTemperature, 29);
    expect(snapshot.weatherCode, 2);
  });

  test('fetchForecast surfaces failed responses', () async {
    final service = WeatherService(
      client: MockClient((request) async => http.Response('nope', 503)),
    );

    await expectLater(
      service.fetchForecast(latitude: 25.0, longitude: 121.5),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('天氣'),
        ),
      ),
    );
  });

  testWidgets('weather screen shows failures without exception noise', (
    tester,
  ) async {
    final service = WeatherService(
      client: MockClient((request) async => http.Response('nope', 503)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WeatherScreen(
          latitude: 25.0,
          longitude: 121.5,
          serviceOverride: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('天氣資料載入失敗。'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
  });

  test('weather screen labels avoid needing a date formatting package', () {
    expect(clockLabel(null), '--:--');
    expect(clockLabel(DateTime.utc(2026, 9, 6, 7, 5)), '07:05');

    // The first two days read as words; the rest use the weekday.
    expect(dayLabel(DateTime.utc(2026, 9, 6), 0), '今天');
    expect(dayLabel(DateTime.utc(2026, 9, 7), 1), '明天');
    // 2026-09-08 is a Tuesday, 2026-09-13 a Sunday.
    expect(dayLabel(DateTime.utc(2026, 9, 8), 2), '週二');
    expect(dayLabel(DateTime.utc(2026, 9, 13), 6), '週日');
  });

  test('weather chip fit arithmetic', () {
    final chipWidth = weatherChipWidth(40);
    expect(chipWidth, kWeatherChipIconSize + kWeatherChipIconGap + 40 + kWeatherChipHPad * 2);
    // Wider labels need more room.
    expect(weatherChipWidth(60), greaterThan(chipWidth));

    expect(
      weatherChipFits(slotWidth: 968, titleWidth: 68, chipWidth: chipWidth),
      isTrue,
    );
    expect(
      weatherChipFits(slotWidth: 88, titleWidth: 68, chipWidth: chipWidth),
      isFalse,
    );
    // Exactly filling the slot still counts as fitting.
    expect(
      weatherChipFits(
        slotWidth: 68 + kWeatherChipGap + chipWidth,
        titleWidth: 68,
        chipWidth: chipWidth,
      ),
      isTrue,
    );
  });
}
