import 'transit_repository.dart';

/// Returns the station directions that should be shown for a metro line.
///
/// Some versions of the API return only one ordered station list.  The list
/// is still enough to render the opposite platform, so synthesize that view
/// by reversing the sequence.  When the API already provides both directions
/// its data is kept unchanged.
List<MetroStationOfLine> buildMetroDirections({
  required String lineId,
  required List<MetroStationOfLine> stationOfLine,
}) {
  final directions = stationOfLine
      .where((entry) => entry.lineId == lineId && entry.stations.isNotEmpty)
      .toList(growable: true)
    ..sort((left, right) => left.direction.compareTo(right.direction));

  if (directions.length != 1 || directions.first.stations.length < 2) {
    return directions;
  }

  final source = directions.first;
  final reverseDirection = source.direction == 0 ? 1 : 0;
  final reversedStations = source.stations.reversed
      .toList(growable: false)
      .asMap()
      .entries
      .map(
        (entry) => MetroStationSequence(
          stationId: entry.value.stationId,
          name: entry.value.name,
          nameEn: entry.value.nameEn,
          sequence: entry.key + 1,
        ),
      )
      .toList(growable: false);

  directions.add(
    MetroStationOfLine(
      lineId: source.lineId,
      direction: reverseDirection,
      stations: reversedStations,
    ),
  );
  directions.sort((left, right) => left.direction.compareTo(right.direction));
  return directions;
}

/// Builds a station lookup for a selected line from its ordered station list.
///
/// The station endpoint currently returns an empty `line_id` for metro
/// stations.  Restricting this lookup by that field therefore drops every
/// coordinate.  The station IDs in `stationOfLine` are the authoritative
/// membership relation, so use those IDs instead.
Map<String, MetroStation> buildMetroStationLookup({
  required List<MetroStation> stations,
  required List<MetroStationSequence> lineStations,
}) {
  final stationIds = lineStations.map((station) => station.stationId).toSet();
  final lookup = <String, MetroStation>{};
  for (final station in stations) {
    if (stationIds.contains(station.stationId)) {
      lookup.putIfAbsent(station.stationId, () => station);
    }
  }
  return lookup;
}
