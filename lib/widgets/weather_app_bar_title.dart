import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../app/bus_app.dart';
import '../core/weather_service.dart';

typedef PassiveLocationResolver = Future<Position?> Function();

/// Called when the chip is tapped, with the fix the chip already resolved so
/// the caller can hand it straight to the weather screen. Either coordinate is
/// null when no fix was available.
typedef WeatherChipTapCallback =
    void Function(double? latitude, double? longitude);

const double kWeatherChipGap = 8;
const double kWeatherChipIconSize = 16;
const double kWeatherChipIconGap = 4;
const double kWeatherChipHPad = 4;

/// Width the weather chip needs for a temperature label of [labelWidth].
double weatherChipWidth(double labelWidth) =>
    kWeatherChipIconSize + kWeatherChipIconGap + labelWidth + kWeatherChipHPad * 2;

/// Whether title plus chip still fit inside the app bar's title slot.
bool weatherChipFits({
  required double slotWidth,
  required double titleWidth,
  required double chipWidth,
}) => titleWidth + kWeatherChipGap + chipWidth <= slotWidth;

/// Icon for a WMO weather interpretation code.
///
/// Ported from the sibling weather app, which maps ranges rather than exact
/// codes so intermediate codes (52, 62, 74, ...) still resolve.
IconData weatherConditionIcon(int? code) {
  if (code == null) {
    return Icons.cloud_outlined;
  }
  if (code == 0) {
    return Icons.wb_sunny;
  }
  if (code == 1 || code == 2) {
    return Icons.wb_cloudy;
  }
  if (code == 3) {
    return Icons.cloud;
  }
  if (code == 45 || code == 48) {
    return Icons.blur_on;
  }
  if (code >= 51 && code <= 57) {
    return Icons.grain;
  }
  if (code >= 61 && code <= 67) {
    return Icons.opacity;
  }
  if (code >= 71 && code <= 77) {
    return Icons.ac_unit;
  }
  if (code >= 80 && code <= 82) {
    return Icons.grain;
  }
  if (code >= 85 && code <= 86) {
    return Icons.ac_unit;
  }
  if (code >= 95) {
    return Icons.flash_on;
  }
  return Icons.wb_cloudy;
}

/// Reads the device location without ever prompting for permission.
///
/// The weather chip is a passive nicety, so it only uses a fix the app is
/// already allowed to read; asking here would hijack the app's own
/// permission flow.
Future<Position?> resolvePassivePosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return null;
    }
  } catch (_) {
    return null;
  }

  LocationPermission permission;
  try {
    permission = await Geolocator.checkPermission();
  } catch (_) {
    return null;
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    return null;
  }

  Position? lastKnown;
  try {
    lastKnown = await Geolocator.getLastKnownPosition();
  } catch (_) {
    lastKnown = null;
  }
  if (lastKnown != null) {
    return lastKnown;
  }

  try {
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 5),
      ),
    );
  } catch (_) {
    return null;
  }
}

/// App bar title that renders `YABus  ☀ 32°C` when weather is available.
///
/// Falls back to the plain title when the setting is off, the location is
/// unavailable, or the title slot is too narrow for both.
class WeatherAppBarTitle extends StatelessWidget {
  const WeatherAppBarTitle({
    required this.title,
    this.onTap,
    this.serviceOverride,
    this.locationOverride,
    super.key,
  });

  final String title;

  /// Tapping the chip opens the full weather page. Null leaves it decorative.
  final WeatherChipTapCallback? onTap;

  @visibleForTesting
  final WeatherService? serviceOverride;

  @visibleForTesting
  final PassiveLocationResolver? locationOverride;

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    if (!controller.settings.showWeatherInAppBar) {
      return Text(title);
    }
    return _WeatherChipHost(
      title: title,
      onTap: onTap,
      serviceOverride: serviceOverride,
      locationOverride: locationOverride,
    );
  }
}

class _WeatherChipHost extends StatefulWidget {
  const _WeatherChipHost({
    required this.title,
    this.onTap,
    this.serviceOverride,
    this.locationOverride,
  });

  final String title;
  final WeatherChipTapCallback? onTap;
  final WeatherService? serviceOverride;
  final PassiveLocationResolver? locationOverride;

  @override
  State<_WeatherChipHost> createState() => _WeatherChipHostState();
}

class _WeatherChipHostState extends State<_WeatherChipHost>
    with WidgetsBindingObserver {
  static const _refreshInterval = Duration(minutes: 15);

  WeatherSnapshot? _snapshot;
  Position? _position;
  Timer? _timer;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
    _timer = Timer.periodic(_refreshInterval, (_) => unawaited(_load()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Timers are frozen while backgrounded, so refresh on resume. The
    // service's TTL keeps this from turning into a request per resume.
    if (state == AppLifecycleState.resumed) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (_loading) {
      return;
    }
    _loading = true;
    try {
      final resolve = widget.locationOverride ?? resolvePassivePosition;
      final position = await resolve();
      if (position == null) {
        return;
      }
      // Handed to the weather screen on tap so it skips its own lookup.
      _position = position;
      final service = widget.serviceOverride ?? WeatherService.shared;
      final snapshot = await service.fetchCurrent(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (!mounted) {
        return;
      }
      setState(() => _snapshot = snapshot);
    } catch (_) {
      // Weather is decorative; keep whatever is already on screen.
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return Text(widget.title);
    }

    final baseStyle = DefaultTextStyle.of(context).style;
    final chipStyle = baseStyle.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    final label = '${snapshot.displayTemperature}°C';

    final titleWidth = _measure(
      widget.title,
      baseStyle,
      textScaler,
      textDirection,
    );
    final chipWidth = weatherChipWidth(
      _measure(label, chipStyle, textScaler, textDirection),
    );

    final onTap = widget.onTap;
    // Padding is part of the tap target, so it stays inside the InkWell and
    // weatherChipWidth keeps accounting for it either way.
    final Widget chipBody = Padding(
      padding: const EdgeInsets.symmetric(horizontal: kWeatherChipHPad),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            weatherConditionIcon(snapshot.weatherCode),
            size: kWeatherChipIconSize,
          ),
          const SizedBox(width: kWeatherChipIconGap),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: chipStyle,
            ),
          ),
        ],
      ),
    );

    final chip = Semantics(
      button: onTap != null,
      label: '目前天氣 ${weatherConditionLabel(snapshot.weatherCode)}'
          ' ${snapshot.displayTemperature} 度',
      child: Tooltip(
        message: onTap == null
            ? weatherConditionLabel(snapshot.weatherCode)
            : '${weatherConditionLabel(snapshot.weatherCode)} · 查看天氣',
        child: onTap == null
            ? chipBody
            : InkWell(
                onTap: () => onTap(_position?.latitude, _position?.longitude),
                borderRadius: BorderRadius.circular(8),
                child: chipBody,
              ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final slotWidth = constraints.maxWidth;
        final fits =
            !slotWidth.isFinite ||
            weatherChipFits(
              slotWidth: slotWidth,
              titleWidth: titleWidth,
              chipWidth: chipWidth,
            );
        if (!fits) {
          return Text(
            widget.title,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                widget.title,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: kWeatherChipGap),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: slotWidth.isFinite ? slotWidth : double.infinity,
              ),
              child: chip,
            ),
          ],
        );
      },
    );
  }

  double _measure(
    String text,
    TextStyle style,
    TextScaler textScaler,
    TextDirection textDirection,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}
