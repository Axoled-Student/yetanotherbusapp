import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_user_agent.dart';
import 'http_error_utils.dart';

/// A single "current weather" reading for one location.
class WeatherSnapshot {
  const WeatherSnapshot({
    required this.temperatureC,
    required this.weatherCode,
    required this.fetchedAt,
  });

  final double temperatureC;

  /// WMO weather interpretation code, or null when the provider omitted it.
  final int? weatherCode;

  final DateTime fetchedAt;

  /// Temperature rounded for display, e.g. `32` for `32.4`.
  int get displayTemperature => temperatureC.round();
}

/// One hourly forecast slot.
///
/// [time] carries wall clock at the forecast location inside a UTC flagged
/// [DateTime], so `.hour` reads the local hour there and comparisons never
/// pick up the device's own timezone offset.
class WeatherHourly {
  const WeatherHourly({
    required this.time,
    required this.temperatureC,
    required this.weatherCode,
    required this.precipitationProbability,
  });

  final DateTime time;
  final double temperatureC;
  final int? weatherCode;

  /// Chance of precipitation, 0-100.
  final int precipitationProbability;

  int get displayTemperature => temperatureC.round();
}

/// One day of the weekly forecast. [date] follows [WeatherHourly.time].
class WeatherDaily {
  const WeatherDaily({
    required this.date,
    required this.highC,
    required this.lowC,
    required this.weatherCode,
    required this.precipitationProbability,
  });

  final DateTime date;
  final double highC;
  final double lowC;
  final int? weatherCode;

  /// Highest chance of precipitation that day, 0-100.
  final int precipitationProbability;

  int get displayHigh => highC.round();
  int get displayLow => lowC.round();
}

/// Everything the weather screen renders: current conditions plus the hourly
/// and daily forecasts.
class WeatherForecast {
  const WeatherForecast({
    required this.current,
    required this.apparentTemperatureC,
    required this.relativeHumidity,
    required this.windSpeedKph,
    required this.hourly,
    required this.daily,
    required this.sunrise,
    required this.sunset,
  });

  final WeatherSnapshot current;

  /// "Feels like" temperature in Celsius.
  final double? apparentTemperatureC;

  /// Relative humidity in percent.
  final int? relativeHumidity;

  /// Wind speed in km/h, Open-Meteo's default unit.
  final double? windSpeedKph;

  /// Upcoming hours, starting with the hour already in progress.
  final List<WeatherHourly> hourly;

  /// Upcoming days, starting with today.
  final List<WeatherDaily> daily;

  final DateTime? sunrise;
  final DateTime? sunset;

  DateTime get fetchedAt => current.fetchedAt;
}

/// WMO weather interpretation codes used by Open-Meteo.
/// https://open-meteo.com/en/docs#weathervariables
const Map<int, String> _wmoLabels = {
  0: '晴',
  1: '晴時多雲',
  2: '多雲',
  3: '陰',
  45: '霧',
  48: '霧',
  51: '小雨',
  53: '雨',
  55: '大雨',
  56: '凍雨',
  57: '凍雨',
  61: '小雨',
  63: '雨',
  65: '大雨',
  66: '凍雨',
  67: '凍雨',
  71: '小雪',
  73: '雪',
  75: '大雪',
  77: '雪',
  80: '陣雨',
  81: '陣雨',
  82: '大陣雨',
  85: '陣雪',
  86: '大陣雪',
  95: '雷陣雨',
  96: '雷陣雨伴冰雹',
  99: '雷陣雨伴冰雹',
};

/// Human readable condition for a WMO code, falling back to 多雲 like the
/// upstream weather app does for unmapped codes.
String weatherConditionLabel(int? code) => _wmoLabels[code] ?? '多雲';

/// Rounds a coordinate to ~1.1km. Applied before anything leaves the device.
double roundCoordinate(double value) => (value * 100).roundToDouble() / 100;

/// Fetches current conditions and forecasts from Open-Meteo.
///
/// Open-Meteo needs no API key and sends `Access-Control-Allow-Origin: *`,
/// so the same calls work on web without a proxy.
class WeatherService {
  WeatherService({http.Client? client}) : _client = client ?? http.Client();

  /// Shared instance so the cache survives remounts and is reused between the
  /// app bar chip and the weather screen.
  static final WeatherService shared = WeatherService();

  final http.Client _client;

  static const _host = 'api.open-meteo.com';
  static const _path = '/v1/forecast';
  static const _timeout = Duration(seconds: 10);

  /// How long a reading stays fresh before another request is made.
  static const cacheTtl = Duration(minutes: 15);

  /// Hours kept from the hourly forecast.
  static const forecastHourCount = 24;

  /// Days requested from the daily forecast.
  static const forecastDayCount = 7;

  WeatherSnapshot? _cached;
  String? _cachedKey;
  Future<WeatherSnapshot>? _inFlight;
  String? _inFlightKey;

  WeatherForecast? _cachedForecast;
  String? _cachedForecastKey;
  Future<WeatherForecast>? _inFlightForecast;
  String? _inFlightForecastKey;

  /// Current temperature and weather code only — the cheap call behind the
  /// app bar chip.
  Future<WeatherSnapshot> fetchCurrent({
    required double latitude,
    required double longitude,
    bool force = false,
  }) {
    // The rounded pair doubles as the cache key.
    final lat = roundCoordinate(latitude);
    final lon = roundCoordinate(longitude);
    final key = '$lat,$lon';

    final cached = _cached;
    if (!force &&
        cached != null &&
        _cachedKey == key &&
        DateTime.now().difference(cached.fetchedAt) < cacheTtl) {
      return Future.value(cached);
    }

    final inFlight = _inFlight;
    if (inFlight != null && _inFlightKey == key) {
      return inFlight;
    }

    final request = _fetch(lat: lat, lon: lon, key: key);
    _inFlight = request;
    _inFlightKey = key;
    return request.whenComplete(() {
      _inFlight = null;
      _inFlightKey = null;
    });
  }

  /// Current conditions plus hourly and daily forecasts — the heavier call
  /// behind the weather screen.
  Future<WeatherForecast> fetchForecast({
    required double latitude,
    required double longitude,
    bool force = false,
  }) {
    final lat = roundCoordinate(latitude);
    final lon = roundCoordinate(longitude);
    final key = '$lat,$lon';

    final cached = _cachedForecast;
    if (!force &&
        cached != null &&
        _cachedForecastKey == key &&
        DateTime.now().difference(cached.fetchedAt) < cacheTtl) {
      return Future.value(cached);
    }

    final inFlight = _inFlightForecast;
    if (inFlight != null && _inFlightForecastKey == key) {
      return inFlight;
    }

    final request = _fetchForecast(lat: lat, lon: lon, key: key);
    _inFlightForecast = request;
    _inFlightForecastKey = key;
    return request.whenComplete(() {
      _inFlightForecast = null;
      _inFlightForecastKey = null;
    });
  }

  Future<WeatherSnapshot> _fetch({
    required double lat,
    required double lon,
    required String key,
  }) async {
    final decoded = await _getJson(
      Uri.https(_host, _path, {
        'latitude': '$lat',
        'longitude': '$lon',
        'current': 'temperature_2m,weather_code',
      }),
    );

    final snapshot = _currentFrom(decoded);
    _cached = snapshot;
    _cachedKey = key;
    return snapshot;
  }

  Future<WeatherForecast> _fetchForecast({
    required double lat,
    required double lon,
    required String key,
  }) async {
    final decoded = await _getJson(
      Uri.https(_host, _path, {
        'latitude': '$lat',
        'longitude': '$lon',
        'current':
            'temperature_2m,relative_humidity_2m,apparent_temperature,'
            'weather_code,wind_speed_10m',
        'hourly': 'temperature_2m,precipitation_probability,weather_code',
        'daily':
            'temperature_2m_max,temperature_2m_min,weather_code,'
            'precipitation_probability_max,sunrise,sunset',
        'timezone': 'auto',
        'forecast_days': '$forecastDayCount',
      }),
    );

    final snapshot = _currentFrom(decoded);
    // One reading serves both the chip and the screen.
    _cached = snapshot;
    _cachedKey = key;

    final current = decoded['current'];
    final currentMap = current is Map<Object?, Object?>
        ? current
        : const <Object?, Object?>{};

    // With timezone=auto Open-Meteo reports the location's wall clock, so
    // "now" has to be expressed the same way for the comparison below.
    final offsetSeconds = _asInt(decoded['utc_offset_seconds']) ?? 0;
    final locationNow = DateTime.now().toUtc().add(
      Duration(seconds: offsetSeconds),
    );
    // Keep the hour already in progress rather than jumping to the next one.
    final earliest = locationNow.subtract(const Duration(hours: 1));

    final hourly = <WeatherHourly>[];
    final hourlyMap = decoded['hourly'];
    if (hourlyMap is Map<Object?, Object?>) {
      final times = _asList(hourlyMap['time']);
      final temperatures = _asList(hourlyMap['temperature_2m']);
      final codes = _asList(hourlyMap['weather_code']);
      final rain = _asList(hourlyMap['precipitation_probability']);
      for (var i = 0; i < times.length; i++) {
        if (hourly.length >= forecastHourCount) {
          break;
        }
        final time = _parseLocationWallClock(_at(times, i));
        final temperature = _asDouble(_at(temperatures, i));
        if (time == null || temperature == null || time.isBefore(earliest)) {
          continue;
        }
        hourly.add(
          WeatherHourly(
            time: time,
            temperatureC: temperature,
            weatherCode: _asInt(_at(codes, i)),
            precipitationProbability: _asPercent(_at(rain, i)),
          ),
        );
      }
    }

    final daily = <WeatherDaily>[];
    DateTime? sunrise;
    DateTime? sunset;
    final dailyMap = decoded['daily'];
    if (dailyMap is Map<Object?, Object?>) {
      final times = _asList(dailyMap['time']);
      final highs = _asList(dailyMap['temperature_2m_max']);
      final lows = _asList(dailyMap['temperature_2m_min']);
      final codes = _asList(dailyMap['weather_code']);
      final rain = _asList(dailyMap['precipitation_probability_max']);
      for (var i = 0; i < times.length && i < forecastDayCount; i++) {
        final date = _parseLocationWallClock(_at(times, i));
        final high = _asDouble(_at(highs, i));
        final low = _asDouble(_at(lows, i));
        if (date == null || high == null || low == null) {
          continue;
        }
        daily.add(
          WeatherDaily(
            date: date,
            highC: high,
            lowC: low,
            weatherCode: _asInt(_at(codes, i)),
            precipitationProbability: _asPercent(_at(rain, i)),
          ),
        );
      }
      sunrise = _parseLocationWallClock(_at(_asList(dailyMap['sunrise']), 0));
      sunset = _parseLocationWallClock(_at(_asList(dailyMap['sunset']), 0));
    }

    final forecast = WeatherForecast(
      current: snapshot,
      apparentTemperatureC: _asDouble(currentMap['apparent_temperature']),
      relativeHumidity: _asInt(currentMap['relative_humidity_2m']),
      windSpeedKph: _asDouble(currentMap['wind_speed_10m']),
      hourly: List<WeatherHourly>.unmodifiable(hourly),
      daily: List<WeatherDaily>.unmodifiable(daily),
      sunrise: sunrise,
      sunset: sunset,
    );
    _cachedForecast = forecast;
    _cachedForecastKey = key;
    return forecast;
  }

  Future<Map<Object?, Object?>> _getJson(Uri uri) async {
    // Built by hand on purpose: ApiUserAgent.applyTo would attach the signed
    // in user's bearer token, and Open-Meteo is a third party.
    final response = await _client
        .get(
          uri,
          headers: <String, String>{
            'Accept': 'application/json',
            // User-Agent is a forbidden header in browsers.
            if (!kIsWeb) 'User-Agent': ApiUserAgent.value,
          },
        )
        .timeout(_timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        httpStatusMessage(response.statusCode, '天氣資料載入失敗。'),
      );
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException('天氣資料格式錯誤。');
    }
    return decoded;
  }

  WeatherSnapshot _currentFrom(Map<Object?, Object?> decoded) {
    final current = decoded['current'];
    if (current is! Map<Object?, Object?>) {
      throw const FormatException('天氣資料格式錯誤。');
    }

    // Open-Meteo returns 26 (int) or 26.4 (double) depending on the value.
    final temperature = _asDouble(current['temperature_2m']);
    if (temperature == null) {
      throw const FormatException('天氣資料缺少氣溫。');
    }

    return WeatherSnapshot(
      temperatureC: temperature,
      weatherCode: _asInt(current['weather_code']),
      fetchedAt: DateTime.now(),
    );
  }
}

double? _asDouble(Object? value) => value is num ? value.toDouble() : null;

int? _asInt(Object? value) => value is num ? value.toInt() : null;

/// Reads a 0-100 percentage, clamping anything out of range to the ends.
int _asPercent(Object? value) {
  final parsed = _asInt(value);
  if (parsed == null || parsed < 0) {
    return 0;
  }
  return parsed > 100 ? 100 : parsed;
}

List<Object?> _asList(Object? value) =>
    value is List<Object?> ? value : const <Object?>[];

Object? _at(List<Object?> values, int index) =>
    index >= 0 && index < values.length ? values[index] : null;

final RegExp _wallClockPattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2}))?',
);

/// Parses one of Open-Meteo's `timezone=auto` timestamps, which arrive as
/// naive local times such as `2026-09-06T15:00`.
///
/// The digits are read straight into a UTC value so it always reads back as
/// wall clock at the forecast location, whatever the device's timezone is.
/// `DateTime.parse` is deliberately not used: it would build a local time, and
/// a wall clock inside the device's own DST spring-forward gap gets normalised
/// an hour forward, which would print one hour twice and skip another.
DateTime? _parseLocationWallClock(Object? value) {
  if (value is! String) {
    return null;
  }
  final match = _wallClockPattern.firstMatch(value.trim());
  if (match == null) {
    return null;
  }
  return DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4) ?? '0'),
    int.parse(match.group(5) ?? '0'),
  );
}
