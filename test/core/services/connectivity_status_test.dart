import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:appgt_offline_subtables/core/services/sync_service.dart';

void main() {
  test('acepta datos moviles aunque Android tambien reporte none', () {
    expect(
      SyncService.connectivityIndicatesNetwork(const [
        ConnectivityResult.mobile,
        ConnectivityResult.none,
      ]),
      isTrue,
    );
  });

  test('rechaza una lista que contiene solamente none', () {
    expect(
      SyncService.connectivityIndicatesNetwork(
        const [ConnectivityResult.none],
      ),
      isFalse,
    );
  });

  test('acepta wifi, ethernet y vpn', () {
    for (final result in const [
      ConnectivityResult.wifi,
      ConnectivityResult.ethernet,
      ConnectivityResult.vpn,
    ]) {
      expect(
        SyncService.connectivityIndicatesNetwork([result]),
        isTrue,
      );
    }
  });
}
