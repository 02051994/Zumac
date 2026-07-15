import 'package:flutter_test/flutter_test.dart';

import 'package:appgt_offline_subtables/config/app_version.dart';

void main() {
  test('la etiqueta de version corresponde a la version de la app', () {
    expect(appVersion, isNotEmpty);
    expect(appVersionLabel, 'Version $appVersion');
  });
}
