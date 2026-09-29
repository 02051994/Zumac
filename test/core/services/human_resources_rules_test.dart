import 'package:appgt_offline_subtables/core/services/human_resources_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('permissionRequiresSupportingDocument', () {
    test('exige sustento solo para los cuatro tipos autorizados', () {
      expect(permissionRequiresSupportingDocument('DESCANSO MEDICO'), isTrue);
      expect(
        permissionRequiresSupportingDocument('LICENCIA DE MATERNIDAD'),
        isTrue,
      );
      expect(
        permissionRequiresSupportingDocument('LICENCIA DE PATERNIDAD'),
        isTrue,
      );
      expect(
        permissionRequiresSupportingDocument('LICENCIA POR FALLECIMIENTO'),
        isTrue,
      );
      expect(permissionRequiresSupportingDocument('PERMISO SIN GOCE'), isFalse);
      expect(
        permissionRequiresSupportingDocument('COMISION DE SERVICIO'),
        isFalse,
      );
      expect(permissionRequiresSupportingDocument('VACACIONES'), isFalse);
      expect(permissionRequiresSupportingDocument('OTRO'), isFalse);
    });

    test('normaliza mayusculas, espacios y tildes', () {
      expect(permissionRequiresSupportingDocument(' descanso médico '), isTrue);
      expect(
        permissionRequiresSupportingDocument('Licencia de maternidad'),
        isTrue,
      );
    });
  });

  group('mobilityIsAuthorized', () {
    final day = DateTime(2026, 9, 29);

    test('autoriza cuando SOAT y revision estan vigentes inclusive', () {
      expect(
        mobilityIsAuthorized(
          soatExpiration: '2026-09-29',
          technicalReviewExpiration: '30/09/2026',
          onDate: day,
        ),
        isTrue,
      );
    });

    test('no autoriza si falta o vencio cualquiera de los dos', () {
      expect(
        mobilityIsAuthorized(
          soatExpiration: '2026-09-28',
          technicalReviewExpiration: '2026-10-01',
          onDate: day,
        ),
        isFalse,
      );
      expect(
        mobilityIsAuthorized(
          soatExpiration: '2026-10-01',
          technicalReviewExpiration: null,
          onDate: day,
        ),
        isFalse,
      );
    });
  });

  test('reconoce tablas y aprobacion de Gestion Humana', () {
    expect(
      isHumanResourcesApprovalTable('GH_PERMISOS_LICENCIAS_APPGT'),
      isTrue,
    );
    expect(
      isHumanResourcesApprovalTable('GH_SANCIONES_PERSONAL_APPGT'),
      isTrue,
    );
    expect(
      isApprovedHumanResourcesRecord({'ESTADO_APROBACION': 'APROBADO'}),
      isTrue,
    );
    expect(
      isApprovedHumanResourcesRecord({'estado_aprobacion': 'PENDIENTE'}),
      isFalse,
    );
  });
}
