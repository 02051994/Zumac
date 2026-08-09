import 'package:appgt_offline_subtables/core/widgets/configuration_icon_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('acepta nombres de iconos persistidos con sufijo outlined', () {
    expect(
      configurationIconForName('precision_manufacturing_outlined'),
      Icons.precision_manufacturing_outlined,
    );
    expect(
      configurationIconForName('warehouse_outlined'),
      Icons.warehouse_outlined,
    );
    expect(
      configurationIconForName('groups_outlined'),
      Icons.groups_outlined,
    );
  });

  test('usa iconos semánticos para aliases ERP', () {
    expect(
      configurationIconForName('account_balance_outlined'),
      Icons.account_balance_outlined,
    );
    expect(
      configurationIconForName('inventory_2_outlined'),
      Icons.inventory_2_outlined,
    );
    expect(
      configurationIconForName('public_outlined'),
      Icons.public_outlined,
    );
  });

  test('un icono desconocido nunca vuelve al circulo generico', () {
    expect(
      configurationIconForName('icono_personalizado'),
      Icons.category_outlined,
    );
  });
}
