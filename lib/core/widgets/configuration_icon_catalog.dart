import 'package:flutter/material.dart';

class ConfigurationIconChoice {
  final String value;
  final String label;
  final IconData icon;

  const ConfigurationIconChoice(this.value, this.label, this.icon);
}

const configurationIconChoices = <ConfigurationIconChoice>[
  ConfigurationIconChoice('apps', 'Aplicaciones', Icons.apps_outlined),
  ConfigurationIconChoice('assignment', 'Formatos', Icons.assignment_outlined),
  ConfigurationIconChoice(
      'agriculture', 'Agricultura', Icons.agriculture_outlined),
  ConfigurationIconChoice(
      'phytosanitary', 'Aplicación fitosanitaria', Icons.sanitizer_outlined),
  ConfigurationIconChoice(
      'pest_control', 'Plagas', Icons.pest_control_outlined),
  ConfigurationIconChoice('eco', 'Cultivos y ambiente', Icons.eco_outlined),
  ConfigurationIconChoice(
      'fertilizer', 'Fertilizantes', Icons.compost_outlined),
  ConfigurationIconChoice(
      'fruit_quality', 'Calidad de fruta', Icons.workspace_premium_outlined),
  ConfigurationIconChoice('harvest', 'Cosecha', Icons.grass_outlined),
  ConfigurationIconChoice(
      'temperature', 'Temperatura', Icons.thermostat_outlined),
  ConfigurationIconChoice('packing', 'Empaque', Icons.inventory_outlined),
  ConfigurationIconChoice(
      'inventory', 'Inventario', Icons.inventory_2_outlined),
  ConfigurationIconChoice('people', 'Personal', Icons.people_alt_outlined),
  ConfigurationIconChoice('analytics', 'Indicadores', Icons.analytics_outlined),
  ConfigurationIconChoice('settings', 'Configuración', Icons.settings_outlined),
  ConfigurationIconChoice('home', 'Inicio', Icons.home_outlined),
  ConfigurationIconChoice('storage', 'Base de datos', Icons.storage_outlined),
  ConfigurationIconChoice('bar_chart', 'Reportes', Icons.bar_chart_outlined),
  ConfigurationIconChoice('checklist', 'Lista de control', Icons.checklist),
  ConfigurationIconChoice(
      'fact_check', 'Verificación', Icons.fact_check_outlined),
  ConfigurationIconChoice('verified', 'Aprobaciones', Icons.verified_outlined),
  ConfigurationIconChoice('security', 'Seguridad', Icons.security_outlined),
  ConfigurationIconChoice('water', 'Riego y agua', Icons.water_drop_outlined),
  ConfigurationIconChoice(
      'water_consumption', 'Consumo de agua', Icons.water_outlined),
  ConfigurationIconChoice('map', 'Mapas y lotes', Icons.map_outlined),
  ConfigurationIconChoice(
      'account_tree', 'Procesos', Icons.account_tree_outlined),
  ConfigurationIconChoice('grid_view', 'Módulos', Icons.grid_view_outlined),
  ConfigurationIconChoice('category', 'Categorías', Icons.category_outlined),
  ConfigurationIconChoice('warehouse', 'Almacén', Icons.warehouse_outlined),
  ConfigurationIconChoice(
      'local_shipping', 'Transporte', Icons.local_shipping_outlined),
  ConfigurationIconChoice('precision_manufacturing', 'Producción',
      Icons.precision_manufacturing_outlined),
  ConfigurationIconChoice('science', 'Laboratorio', Icons.science_outlined),
  ConfigurationIconChoice('health_and_safety', 'Salud y seguridad',
      Icons.health_and_safety_outlined),
  ConfigurationIconChoice(
      'engineering', 'Mantenimiento', Icons.engineering_outlined),
  ConfigurationIconChoice(
      'shopping_cart', 'Compras', Icons.shopping_cart_outlined),
  ConfigurationIconChoice('sell', 'Ventas', Icons.sell_outlined),
  ConfigurationIconChoice('payments', 'Finanzas', Icons.payments_outlined),
  ConfigurationIconChoice('groups', 'Equipos', Icons.groups_outlined),
  ConfigurationIconChoice('schedule', 'Programación', Icons.schedule_outlined),
  ConfigurationIconChoice(
      'notifications', 'Alertas', Icons.notifications_outlined),
  ConfigurationIconChoice('folder', 'Documentos', Icons.folder_outlined),
  ConfigurationIconChoice(
      'photo_camera', 'Evidencias', Icons.photo_camera_outlined),
  ConfigurationIconChoice('qr_code', 'Código QR', Icons.qr_code_2_outlined),
];

IconData configurationIconForName(String? name) {
  final normalized = (name ?? '').trim().toLowerCase();
  const aliases = <String, String>{
    'app': 'apps',
    'modulos': 'apps',
    'database': 'storage',
    'registros_locales': 'storage',
    'reportes': 'bar_chart',
    'users': 'people',
    'usuarios': 'people',
    'pending': 'notifications',
    'pending_actions': 'notifications',
    'warning': 'notifications',
    'alert': 'notifications',
    'registros_pendientes': 'notifications',
    'inicio': 'home',
    'inicio_gt': 'home',
    'form': 'assignment',
    'formatos': 'assignment',
    'tractor': 'agriculture',
    'aplicacion_fitosanitaria': 'phytosanitary',
    'plagas': 'pest_control',
    'fertilizante': 'fertilizer',
    'calidad_fruta': 'fruit_quality',
    'cosecha': 'harvest',
    'empaque': 'packing',
    'riego': 'water',
    'lotes': 'map',
    'variedades': 'eco',
    'centro_costo': 'account_tree',
  };
  final canonical = aliases[normalized] ?? normalized;
  for (final choice in configurationIconChoices) {
    if (choice.value == canonical) return choice.icon;
  }
  return Icons.circle_outlined;
}
