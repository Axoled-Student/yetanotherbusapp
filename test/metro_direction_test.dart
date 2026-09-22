import 'package:flutter_test/flutter_test.dart';
import 'package:taiwanbus_flutter/core/metro_direction.dart';
import 'package:taiwanbus_flutter/core/transit_repository.dart';

MetroStationSequence _sequence(String id, int sequence) =>
    MetroStationSequence(
      stationId: id,
      name: id,
      nameEn: id,
      sequence: sequence,
    );

void main() {
  test('synthesizes the missing opposite metro direction', () {
    final directions = buildMetroDirections(
      lineId: 'G',
      stationOfLine: [
        MetroStationOfLine(
          lineId: 'G',
          direction: 0,
          stations: [
            _sequence('G01', 1),
            _sequence('G02', 2),
            _sequence('G03', 3),
          ],
        ),
      ],
    );

    expect(directions.map((direction) => direction.direction), [0, 1]);
    expect(
      directions[1].stations.map((station) => station.stationId),
      ['G03', 'G02', 'G01'],
    );
    expect(
      directions[1].stations.map((station) => station.sequence),
      [1, 2, 3],
    );
  });

  test('does not duplicate directions already supplied by the API', () {
    final input = [
      MetroStationOfLine(
        lineId: 'BL',
        direction: 0,
        stations: [_sequence('BL01', 1), _sequence('BL02', 2)],
      ),
      MetroStationOfLine(
        lineId: 'BL',
        direction: 1,
        stations: [_sequence('BL02', 1), _sequence('BL01', 2)],
      ),
    ];

    final directions = buildMetroDirections(
      lineId: 'BL',
      stationOfLine: input,
    );
    expect(directions.length, 2);
    expect(directions[0].stations.first.stationId, 'BL01');
    expect(directions[1].stations.first.stationId, 'BL02');
  });

  test('looks up coordinates by station membership, not empty line_id', () {
    final lookup = buildMetroStationLookup(
      stations: const [
        MetroStation(
          stationId: 'G01',
          name: '新店',
          nameEn: 'Xindian',
          lineId: '',
          lat: 24.95,
          lon: 121.54,
        ),
        MetroStation(
          stationId: 'R01',
          name: '淡水',
          nameEn: 'Tamsui',
          lineId: '',
          lat: 25.16,
          lon: 121.45,
        ),
      ],
      lineStations: [_sequence('G01', 1)],
    );

    expect(lookup.keys, ['G01']);
    expect(lookup['G01']!.lat, 24.95);
  });
}
