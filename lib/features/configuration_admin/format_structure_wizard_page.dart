import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide ScaffoldMessenger;

import '../../core/services/app_experience_service.dart';
import '../../core/widgets/configuration_icon_catalog.dart';
import '../../core/widgets/zumac_scaffold_messenger.dart';
import 'configuration_admin_repository.dart';
import 'format_structure_validator.dart';

class FormatStructureWizardPage extends StatefulWidget {
  final Map<String, dynamic> contextData;
  final Map<String, dynamic>? initialDraft;
  final String? initialRubroId;
  final ConfigurationAdminRepository? repository;

  const FormatStructureWizardPage({
    super.key,
    required this.contextData,
    this.initialDraft,
    this.initialRubroId,
    this.repository,
  });

  @override
  State<FormatStructureWizardPage> createState() =>
      _FormatStructureWizardPageState();
}

class _FormatStructureWizardPageState extends State<FormatStructureWizardPage> {
  static const Map<String, String> _formulaNames = {
    'SUMA': 'Suma',
    'RESTA': 'Resta',
    'MULTIPLICACION': 'Multiplicación',
    'DIVISION': 'División',
    'PROMEDIO': 'Promedio',
    'MAXIMO': 'Valor máximo',
    'MINIMO': 'Valor mínimo',
    'CONTAR': 'Contar valores',
    'CONTARSI': 'Contar si cumple una condición',
    'SUMARSI': 'Sumar si cumple una condición',
    'PROMEDIOSI': 'Promediar si cumple una condición',
    'MEDIANA': 'Mediana',
    'MODA': 'Moda',
    'SI': 'Condicional SI',
    'SI_ANIDADA': 'Condicional SI anidada',
    'SIERROR': 'Valor alternativo si hay error',
    'BUSCAR': 'Buscar un valor',
    'CONCATENAR': 'Concatenar textos',
    'CONCATENAR_SEP': 'Concatenar con separador',
    'EXTRAER': 'Extraer parte de un texto',
    'IZQUIERDA': 'Caracteres desde la izquierda',
    'DERECHA': 'Caracteres desde la derecha',
    'LARGO': 'Longitud del texto',
    'MAYUSCULAS': 'Convertir a mayúsculas',
    'MINUSCULAS': 'Convertir a minúsculas',
    'LIMPIAR': 'Quitar espacios sobrantes',
    'REEMPLAZAR': 'Reemplazar texto',
    'REDONDEAR': 'Redondear número',
    'ABSOLUTO': 'Valor absoluto',
    'ENTERO': 'Parte entera',
    'POTENCIA': 'Potencia',
    'RESIDUO': 'Residuo de una división',
    'RESTA_TIEMPOS': 'Tiempo transcurrido',
    'FECHAS_TRANSCURRIDAS': 'Días entre fechas',
    'SUMAR_DIAS': 'Sumar días a una fecha',
    'FECHA_ACTUAL': 'Fecha actual',
    'HORA_ACTUAL': 'Hora actual',
    'FECHA_HORA_ACTUAL': 'Fecha y hora actual',
    'SEMANA': 'Semana de una fecha',
    'MES': 'Mes de una fecha',
    'ANIO': 'Año de una fecha',
    'DIA': 'Día de una fecha',
    'LISTA': 'Traer una lista de valores',
    'PERSONALIZADA': 'Fórmula personalizada',
  };

  static const Map<String, String> _formulaTemplates = {
    'SUMA': '[CAMPO_A] + [CAMPO_B]',
    'RESTA': 'RESTA([CAMPO_A]; [CAMPO_B])',
    'MULTIPLICACION': 'MULTIPLICACION([CAMPO_A]; [CAMPO_B])',
    'DIVISION': 'DIVISION([DIVIDENDO]; [DIVISOR])',
    'PROMEDIO': 'PROMEDIO([CAMPO_INICIAL]:[CAMPO_FINAL])',
    'MAXIMO': 'MAXIMO([CAMPO_INICIAL]:[CAMPO_FINAL])',
    'MINIMO': 'MINIMO([CAMPO_INICIAL]:[CAMPO_FINAL])',
    'CONTAR': 'CONTAR([CAMPO_INICIAL]:[CAMPO_FINAL])',
    'CONTARSI': 'CONTARSI([CAMPO_INICIAL]:[CAMPO_FINAL]; ">0")',
    'SUMARSI': 'SUMARSI([CAMPO_CONDICION]; ">0"; [CAMPO_A_SUMAR])',
    'PROMEDIOSI': 'PROMEDIOSI([CAMPO_CONDICION]; ">0"; [CAMPO_A_PROMEDIAR])',
    'MEDIANA': 'MEDIANA([CAMPO_INICIAL]:[CAMPO_FINAL])',
    'MODA': 'MODA([CAMPO_INICIAL]:[CAMPO_FINAL])',
    'SI': 'SI([CONDICION] = "valor"; "sí"; "no")',
    'SI_ANIDADA':
        'SI([CONDICION_1] = "valor"; "resultado 1"; SI([CONDICION_2] = "valor"; "resultado 2"; "otro"))',
    'SIERROR': 'SIERROR([FORMULA]; "valor alternativo")',
    'BUSCAR': 'BUSCAR("TABLA"; "CAMPO_CLAVE"; [VALOR]; "CAMPO_RETORNO")',
    'CONCATENAR': 'CONCATENAR([CAMPO_A]; " "; [CAMPO_B])',
    'CONCATENAR_SEP': 'CONCATENAR_SEP(" - "; [CAMPO_A]; [CAMPO_B])',
    'EXTRAER': 'EXTRAER([CAMPO]; 1; 5)',
    'IZQUIERDA': 'IZQUIERDA([CAMPO]; 3)',
    'DERECHA': 'DERECHA([CAMPO]; 3)',
    'LARGO': 'LARGO([CAMPO])',
    'MAYUSCULAS': 'MAYUSCULAS([CAMPO])',
    'MINUSCULAS': 'MINUSCULAS([CAMPO])',
    'LIMPIAR': 'LIMPIAR([CAMPO])',
    'REEMPLAZAR': 'REEMPLAZAR([CAMPO]; "antes"; "después")',
    'REDONDEAR': 'REDONDEAR([CAMPO]; 2)',
    'ABSOLUTO': 'ABSOLUTO([CAMPO])',
    'ENTERO': 'ENTERO([CAMPO])',
    'POTENCIA': 'POTENCIA([CAMPO]; 2)',
    'RESIDUO': 'RESIDUO([CAMPO]; 2)',
    'RESTA_TIEMPOS': 'RESTA_TIEMPOS([HORA_INICIO]; [HORA_FIN])',
    'FECHAS_TRANSCURRIDAS': 'FECHAS_TRANSCURRIDAS([FECHA_INICIO]; [FECHA_FIN])',
    'SUMAR_DIAS': 'SUMAR_DIAS([FECHA]; 7)',
    'FECHA_ACTUAL': 'FECHA_ACTUAL()',
    'HORA_ACTUAL': 'HORA_ACTUAL()',
    'FECHA_HORA_ACTUAL': 'FECHA_HORA_ACTUAL()',
    'SEMANA': 'SEMANA([FECHA])',
    'MES': 'MES([FECHA])',
    'ANIO': 'ANIO([FECHA])',
    'DIA': 'DIA([FECHA])',
    'LISTA':
        'LISTA("TABLA"; "CAMPO_RETORNO"; "CAMPO_CONDICION"; [VALOR_CONDICION])',
  };

  static String _dataTypeForUi(String uiType) {
    switch (uiType) {
      case 'number':
      case 'slider':
      case 'percent':
        return 'number';
      case 'integer':
      case 'rating':
        return 'integer';
      case 'date':
        return 'date';
      case 'time':
        return 'time';
      case 'datetime':
        return 'datetime';
      case 'checkbox':
      case 'switch':
        return 'boolean';
      case 'hidden_id':
        return 'hidden_id';
      case 'photo':
      case 'signature':
      case 'qr_scan':
      case 'barcode_scan':
      case 'dni_scan':
      case 'dropdown':
      case 'multiselect':
      case 'formula':
      case 'lookup':
      default:
        return 'text';
    }
  }

  // Una fórmula describe cómo se obtiene el valor, no el tipo físico que se
  // almacenará. Mantener esta lista separada evita que BUSCAR() se publique
  // siempre como numeric y permite resultados de texto, fecha, hora, etc.
  static const Map<String, String> _formulaResultTypes = <String, String>{
    'text': 'Texto',
    'number': 'Número decimal',
    'integer': 'Número entero',
    'date': 'Fecha',
    'time': 'Hora',
    'datetime': 'Fecha y hora',
    'boolean': 'Sí / No',
    'json': 'JSON',
  };

  static String _formulaResultType(String value) {
    return _formulaResultTypes.containsKey(value) ? value : 'text';
  }

  late final ConfigurationAdminRepository repository;
  final experience = AppExperienceService();

  final nameController = TextEditingController();
  final codeController = TextEditingController();
  final descriptionController = TextEditingController();
  final orderController = TextEditingController(text: '0');

  int currentStep = 0;
  bool loading = true;
  bool saving = false;
  bool active = true;
  bool tableVisible = true;
  bool offline = true;
  bool workflow = false;
  bool photos = false;
  bool signature = false;
  bool geolocation = false;
  bool qr = false;
  bool approvals = false;
  List<String> workflowStates = const [
    'BORRADOR',
    'EN_REVISION',
    'COMPLETADO',
  ];
  String formatType = 'SIMPLE';
  String? selectedTemplateId;
  String? selectedModuleId;
  String? selectedRubroId;
  String? draftId;
  String? publishedTargetId;
  int? requestedTableIndex;
  int? requestedFieldIndex;
  String? requestedFieldCode;
  String? requestedFieldAction;
  bool requestedAddField = false;
  bool focusedFieldMode = false;
  bool focusedNewField = false;
  int? focusedTableIndex;
  int? focusedFieldIndex;
  String? focusedActionMessage;
  int? lockVersion;
  String? error;
  Map<String, dynamic>? validation;
  List<Map<String, dynamic>> templates = [];
  List<Map<String, dynamic>> moduleTemplates = [];
  List<Map<String, dynamic>> tables = [];
  Map<String, dynamic> aiImportMetadata = <String, dynamic>{};
  Timer? autosaveTimer;
  DateTime? lastAutosaveAt;
  String? lastAutosaveFingerprint;
  bool restoredAutosave = false;

  bool get canPublish => widget.contextData['puede_publicar'] == true;
  bool get isValid => validation?['valido'] == true;
  bool get editingPublished => publishedTargetId != null;

  @override
  void initState() {
    super.initState();
    repository = widget.repository ?? ConfigurationAdminRepository();
    selectedRubroId = widget.initialRubroId;
    _hydrateDraft(widget.initialDraft);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    if (widget.initialDraft == null) await _restoreAutosave();
    autosaveTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_saveAutosave()),
    );
    await _loadOptions();
  }

  @override
  void dispose() {
    autosaveTimer?.cancel();
    unawaited(_saveAutosave());
    nameController.dispose();
    codeController.dispose();
    descriptionController.dispose();
    orderController.dispose();
    super.dispose();
  }

  String get _autosaveKey {
    final contextKey = widget.initialDraft?['id']?.toString() ??
        widget.initialRubroId ??
        'nuevo';
    return 'entidad_FORMATO_$contextKey';
  }

  Future<void> _restoreAutosave() async {
    final saved = await experience.loadBuilderDraft(_autosaveKey);
    final payload = saved['payload'];
    if (payload is! Map) return;
    final restoredPayload = Map<String, dynamic>.from(payload);
    _hydrateDraft({
      'nombre': restoredPayload['nombre'],
      'codigo': restoredPayload['codigo'],
      'plantilla_origen_id': saved['selected_template_id'],
      'definicion': restoredPayload,
    });
    currentStep = int.tryParse('${saved['current_step'] ?? 0}') ?? 0;
    restoredAutosave = true;
    lastAutosaveAt = DateTime.tryParse(saved['saved_at']?.toString() ?? '');
  }

  Future<void> _saveAutosave() async {
    if (loading || saving || focusedFieldMode) return;
    final savedAt = DateTime.now();
    final value = <String, dynamic>{
      'payload': _payload(),
      'selected_template_id': selectedTemplateId,
      'current_step': currentStep,
    };
    final fingerprint = jsonEncode(value);
    if (fingerprint == lastAutosaveFingerprint) return;
    lastAutosaveFingerprint = fingerprint;
    value['saved_at'] = savedAt.toIso8601String();
    await experience.saveBuilderDraft(_autosaveKey, value);
    if (mounted) setState(() => lastAutosaveAt = savedAt);
  }

  PreferredSizeWidget _autosaveBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(28),
      child: Container(
        width: double.infinity,
        height: 28,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: const Color(0xFFEAF3F6),
        child: Row(
          children: [
            Icon(
              lastAutosaveAt == null
                  ? Icons.cloud_queue_outlined
                  : Icons.cloud_done_outlined,
              size: 15,
              color: const Color(0xFF31596B),
            ),
            const SizedBox(width: 6),
            Text(
              restoredAutosave
                  ? 'Borrador recuperado · Guardado automáticamente'
                  : lastAutosaveAt == null
                      ? 'Borrador automático activo'
                      : 'Guardado hace unos segundos',
              style: const TextStyle(
                color: Color(0xFF31596B),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _hydrateDraft(Map<String, dynamic>? draft) {
    if (draft == null) return;
    final definition = _map(draft['definicion']);
    aiImportMetadata = _aiMetadataFrom(definition);
    draftId = draft['id']?.toString();
    publishedTargetId = definition['_modo_edicion'] == 'NUEVA_VERSION'
        ? definition['_entidad_objetivo_id']?.toString()
        : null;
    lockVersion = int.tryParse('${draft['lock_version'] ?? ''}');
    requestedTableIndex =
        int.tryParse('${draft['_requested_table_index'] ?? ''}');
    requestedFieldIndex =
        int.tryParse('${draft['_requested_field_index'] ?? ''}');
    requestedFieldCode = draft['_requested_field_code']?.toString();
    requestedFieldAction = draft['_requested_field_action']?.toString();
    requestedAddField = draft['_requested_add_field'] == true;
    focusedFieldMode = requestedTableIndex != null &&
        (requestedAddField ||
            requestedFieldIndex != null ||
            requestedFieldCode?.isNotEmpty == true ||
            requestedFieldAction?.isNotEmpty == true);
    focusedNewField = requestedAddField;
    selectedTemplateId = draft['plantilla_origen_id']?.toString();
    selectedRubroId =
        definition['rubro_id']?.toString() ?? draft['rubro_id']?.toString();
    selectedModuleId = definition['modulo_id']?.toString();
    nameController.text = draft['nombre']?.toString() ?? '';
    codeController.text = draft['codigo']?.toString() ?? '';
    descriptionController.text = definition['descripcion']?.toString() ?? '';
    orderController.text = definition['orden']?.toString() ?? '0';
    formatType = definition['tipo_formato']?.toString() ?? 'SIMPLE';
    active = definition['activo'] != false;
    tableVisible = definition['tabla_visible_app'] != false;
    if (draft['_requested_action'] == 'DEACTIVATE' ||
        draft['_requested_action'] == 'ACTIVATE') {
      currentStep = 4;
    } else if (requestedTableIndex != null) {
      currentStep = 3;
    }
    final capabilities = _map(definition['capacidades']);
    offline = capabilities['offline'] != false;
    workflow = capabilities['workflow'] == true;
    photos = capabilities['fotos'] == true;
    signature = capabilities['firma'] == true;
    geolocation = capabilities['geolocalizacion'] == true;
    qr = capabilities['qr'] == true;
    approvals = capabilities['aprobaciones'] == true;
    final rawWorkflowStates = definition['flujo_estados'];
    if (rawWorkflowStates is List) {
      final parsed = rawWorkflowStates
          .map((value) => value.toString().trim().toUpperCase())
          .where((value) => value.isNotEmpty)
          .toList();
      if (parsed.isNotEmpty) workflowStates = parsed;
    }
    tables = _maps(definition['tablas']);
    validation = draft['validacion'] is Map
        ? Map<String, dynamic>.from(draft['validacion'] as Map)
        : null;
  }

  Future<void> _loadOptions() async {
    try {
      final results = await Future.wait([
        repository.listTemplates(entityType: 'FORMATO', limit: 200),
        repository.listTemplates(entityType: 'MODULO', limit: 200),
      ]);
      if (!mounted) return;
      setState(() {
        templates = _items(results[0]);
        moduleTemplates = _items(results[1]);
        if (!_availableModuleTemplates.any(
          (row) => row['entidad_origen_id']?.toString() == selectedModuleId,
        )) {
          selectedModuleId = _availableModuleTemplates.isEmpty
              ? null
              : _availableModuleTemplates.first['entidad_origen_id']
                  ?.toString();
        }
        _deriveRubro();
        _syncGeneratedFormatCode();
        _suggestNextOrder();
        loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openRequestedStructureEditor();
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'No se pudieron cargar las opciones: $exception';
      });
    }
  }

  Future<void> _openRequestedStructureEditor() async {
    final tableIndex = requestedTableIndex;
    final fieldIndex = requestedFieldIndex;
    final fieldCode = requestedFieldCode;
    final fieldAction = requestedFieldAction?.toUpperCase();
    final addField = requestedAddField;
    requestedTableIndex = null;
    requestedFieldIndex = null;
    requestedFieldCode = null;
    requestedFieldAction = null;
    requestedAddField = false;
    if (tableIndex == null || tableIndex < 0 || tableIndex >= tables.length) {
      if (focusedFieldMode && mounted) {
        setState(
            () => error = 'No se encontró la tabla que contiene el campo.');
      }
      return;
    }
    focusedTableIndex = tableIndex;
    if (addField) {
      final previousLength = _maps(tables[tableIndex]['campos']).length;
      await _editField(tableIndex);
      if (!mounted) return;
      final nextLength = _maps(tables[tableIndex]['campos']).length;
      setState(() {
        focusedFieldIndex = nextLength > previousLength ? nextLength - 1 : null;
        focusedActionMessage = nextLength > previousLength
            ? 'Revise el nuevo campo y guarde los cambios.'
            : 'No se agregó ningún campo.';
      });
      return;
    }
    final fields = _maps(tables[tableIndex]['campos']);
    var resolvedIndex = fieldIndex;
    if (fieldCode?.isNotEmpty == true) {
      final normalized = fieldCode!.trim().toLowerCase();
      final match = fields.indexWhere((field) => {
            field['campo'],
            field['entidad_origen_id'],
            field['codigo'],
          }.any(
              (value) => value?.toString().trim().toLowerCase() == normalized));
      if (match >= 0) resolvedIndex = match;
    }
    if (resolvedIndex != null &&
        resolvedIndex >= 0 &&
        resolvedIndex < fields.length) {
      focusedFieldIndex = resolvedIndex;
      if (fieldAction == 'HIDE' ||
          fieldAction == 'SHOW' ||
          fieldAction == 'DELETE') {
        final field = Map<String, dynamic>.from(fields[resolvedIndex]);
        if (fieldAction == 'SHOW') {
          field['visible'] = true;
          field['visible_tabla'] = true;
          focusedActionMessage = 'El campo se mostrará nuevamente.';
        } else {
          field['visible'] = false;
          field['visible_tabla'] = false;
          if (fieldAction == 'DELETE') {
            field['activo'] = false;
            field['matrices'] = _maps(field['matrices'])
                .map((matrix) => {...matrix, 'activo': false})
                .toList();
            focusedActionMessage =
                'El campo se retirará de la configuración sin borrar los registros existentes.';
          } else {
            focusedActionMessage = 'El campo quedará oculto para los usuarios.';
          }
        }
        fields[resolvedIndex] = field;
        if (mounted) {
          setState(() {
            tables[tableIndex]['campos'] = fields;
            validation = null;
          });
        }
        return;
      }
      await _editField(tableIndex, index: resolvedIndex);
      if (mounted) {
        setState(() => focusedActionMessage =
            'Revise el campo y guarde los cambios cuando esté listo.');
      }
      return;
    }
    if (focusedFieldMode && mounted) {
      setState(() => error = 'No se encontró el campo seleccionado.');
      return;
    }
    await _editTable(index: tableIndex);
  }

  List<Map<String, dynamic>> _items(Map<String, dynamic> result) =>
      _maps(result['items']);

  List<Map<String, dynamic>> get _availableModuleTemplates {
    if (selectedRubroId == null) return moduleTemplates;
    return moduleTemplates.where((row) {
      final definition = _map(row['definicion']);
      return (row['rubro_id'] ?? definition['rubro_id'])?.toString() ==
          selectedRubroId;
    }).toList(growable: false);
  }

  List<Map<String, dynamic>> get _availableFormatTemplates {
    if (selectedRubroId == null) return templates;
    return templates.where((row) {
      final definition = _map(row['definicion']);
      return (row['rubro_id'] ?? definition['rubro_id'])?.toString() ==
          selectedRubroId;
    }).toList(growable: false);
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
      : <Map<String, dynamic>>[];

  int _configuredFieldCount() => tables.fold<int>(
        0,
        (total, table) =>
            total +
            _maps(table['campos'])
                .where((field) => field['activo'] != false)
                .length,
      );

  void _deriveRubro() {
    final module = moduleTemplates.cast<Map<String, dynamic>?>().firstWhere(
          (row) => row?['entidad_origen_id']?.toString() == selectedModuleId,
          orElse: () => null,
        );
    selectedRubroId = module?['rubro_id']?.toString() ?? selectedRubroId;
  }

  String _withoutDiacritics(String value) {
    const replacements = <String, String>{
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
      'Á': 'A',
      'É': 'E',
      'Í': 'I',
      'Ó': 'O',
      'Ú': 'U',
      'Ü': 'U',
      'Ñ': 'N',
    };
    var result = value;
    for (final entry in replacements.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }

  String _slug(String value) {
    var result = _withoutDiacritics(value).trim().toLowerCase();
    result = result.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    result = result.replaceAll(RegExp(r'_+'), '_');
    return result.replaceAll(RegExp(r'^_+|_+$'), '');
  }

  String _bounded(String value, [int max = 63]) =>
      value.length <= max ? value : value.substring(0, max);

  String _modulePrefix() {
    final module = moduleTemplates.cast<Map<String, dynamic>?>().firstWhere(
          (row) => row?['entidad_origen_id']?.toString() == selectedModuleId,
          orElse: () => null,
        );
    final source = _withoutDiacritics(
      module?['entidad_origen_id']?.toString() ??
          module?['codigo']?.toString() ??
          module?['nombre']?.toString() ??
          'fm',
    ).toLowerCase();
    final tokens = source
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.isNotEmpty && token != 'modulo')
        .toList();
    final token = tokens.isEmpty ? 'fm' : tokens.first;
    return token.length >= 2 ? token.substring(0, 2) : '${token}x';
  }

  String _selectedModuleName() {
    final module = moduleTemplates.cast<Map<String, dynamic>?>().firstWhere(
          (row) => row?['entidad_origen_id']?.toString() == selectedModuleId,
          orElse: () => null,
        );
    return module?['nombre']?.toString() ?? 'Módulo seleccionado';
  }

  String _generatedFormatCode() {
    if (editingPublished && codeController.text.trim().isNotEmpty) {
      return codeController.text.trim();
    }
    final name = _slug(nameController.text);
    return _bounded('${_modulePrefix()}_id_${name.isEmpty ? 'formato' : name}');
  }

  void _syncGeneratedFormatCode() {
    if (!editingPublished) codeController.text = _generatedFormatCode();
  }

  String _generatedTableCode(String name) =>
      _bounded('${_modulePrefix()}_tabla_${_slug(name)}');

  String _generatedTableName(String name) =>
      _bounded('${_modulePrefix()}-tabla_${_slug(name)}');

  String _generatedFieldCode(String tableCode, String name) => _bounded(
        '${_slug(tableCode)}_campo_${_slug(name).isEmpty ? 'campo' : _slug(name)}',
      );

  String _generatedPhysicalFieldName(String name) {
    final normalized = _slug(name);
    if (normalized.isEmpty) return 'Campo';
    return _bounded(
      '${normalized[0].toUpperCase()}${normalized.substring(1).toLowerCase()}',
    );
  }

  List<Map<String, dynamic>> get _formatsInSelectedModule {
    final rows = templates.where((row) {
      final definition = _map(row['definicion']);
      final moduleId = definition['modulo_id']?.toString() ??
          row['padre_origen_id']?.toString();
      return moduleId == selectedModuleId;
    }).toList();
    rows.sort((a, b) {
      final aOrder =
          int.tryParse('${_map(a['definicion'])['orden'] ?? 0}') ?? 0;
      final bOrder =
          int.tryParse('${_map(b['definicion'])['orden'] ?? 0}') ?? 0;
      return aOrder.compareTo(bOrder);
    });
    return rows;
  }

  void _suggestNextOrder() {
    if (editingPublished || orderController.text.trim() != '0') return;
    final orders = _formatsInSelectedModule
        .map((row) =>
            int.tryParse('${_map(row['definicion'])['orden'] ?? 0}') ?? 0)
        .toList();
    final next =
        orders.isEmpty ? 1 : orders.reduce((a, b) => a > b ? a : b) + 1;
    orderController.text = '$next';
  }

  Future<void> _showCurrentFormatOrder() async {
    final rows = _formatsInSelectedModule;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Orden actual del módulo'),
        content: SizedBox(
          width: 480,
          child: rows.isEmpty
              ? const Text('Este módulo todavía no tiene formatos publicados.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final order =
                        _map(row['definicion'])['orden']?.toString() ??
                            '${index + 1}';
                    return ListTile(
                      leading: CircleAvatar(child: Text(order)),
                      title: Text(row['nombre']?.toString() ?? 'Formato'),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<bool> _hasInternet() async {
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  Future<void> _selectTemplate(String? id) async {
    if (id == null) {
      setState(() {
        selectedTemplateId = null;
        validation = null;
      });
      return;
    }
    setState(() {
      selectedTemplateId = id;
      saving = true;
      error = null;
      validation = null;
    });
    try {
      final full = await repository.loadFullFormatTemplate(id);
      final structure = formatStructureFromTemplate(full);
      if (!mounted) return;
      setState(() {
        _applyStructure(structure);
        saving = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = 'No se pudo copiar la plantilla: $exception';
      });
    }
  }

  void _applyStructure(Map<String, dynamic> structure) {
    final targetModuleId = selectedModuleId;
    final targetRubroId = selectedRubroId;
    nameController.text = structure['nombre']?.toString() ?? '';
    codeController.text = structure['codigo']?.toString() ?? '';
    descriptionController.text = structure['descripcion']?.toString() ?? '';
    orderController.text = structure['orden']?.toString() ?? '0';
    selectedModuleId = targetModuleId ?? structure['modulo_id']?.toString();
    selectedRubroId = targetRubroId;
    formatType = structure['tipo_formato']?.toString() ?? 'SIMPLE';
    active = structure['activo'] != false;
    tableVisible = structure['tabla_visible_app'] != false;
    aiImportMetadata = _aiMetadataFrom(structure);
    tables = _maps(structure['tablas']);
    _deriveRubro();
  }

  Map<String, dynamic> _payload() {
    _syncGeneratedFormatCode();
    final normalizedTables = tables
        .map((table) => <String, dynamic>{
              ...table,
              'auditable': table['auditable'] == null
                  ? true
                  : table['auditable'] == true || table['auditable'] == 1,
              'icono': table['icono']?.toString().trim().isNotEmpty == true
                  ? table['icono']
                  : 'assignment',
            })
        .toList();
    final firstTable = normalizedTables.isEmpty
        ? const <String, dynamic>{}
        : normalizedTables.first;
    final raw = <String, dynamic>{
      ...aiImportMetadata,
      'codigo': codeController.text.trim(),
      'nombre': nameController.text.trim(),
      'descripcion': descriptionController.text.trim(),
      'rubro_id': selectedRubroId,
      'modulo_id': selectedModuleId,
      'tipo_formato': formatType,
      'tabla_destino': normalizedTables.isEmpty
          ? ''
          : normalizedTables.first['tabla_destino']?.toString() ?? '',
      'tabla_visible_app': tableVisible,
      'auditable': firstTable['auditable'] ?? true,
      'icono': firstTable['icono'] ?? 'assignment',
      'imagen_encabezado': firstTable['imagen_encabezado'],
      'orden': int.tryParse(orderController.text.trim()) ??
          orderController.text.trim(),
      'activo': active,
      'capacidades': {
        'offline': offline,
        'workflow': workflow,
        'fotos': photos,
        'firma': signature,
        'geolocalizacion': geolocation,
        'qr': qr,
        'aprobaciones': approvals,
      },
      'flujo_estados': workflow ? workflowStates : <String>[],
      'tablas': normalizedTables,
    };
    if (editingPublished) {
      raw.addAll({
        '_modo_edicion': 'NUEVA_VERSION',
        '_entidad_objetivo_id': publishedTargetId,
      });
    }
    return rekeyClonedFormatChildren(raw);
  }

  Map<String, dynamic> _aiMetadataFrom(Map<String, dynamic> source) {
    const keys = <String>{
      'estado_revision_ia',
      'layout_formulario',
      'layout_registros',
      'configuracion_layout',
      'origen_creador',
      'relaciones_sugeridas_ia',
    };
    return {
      for (final key in keys)
        if (source.containsKey(key)) key: source[key],
    };
  }

  Future<void> _saveAndValidate() async {
    final payload = _payload();
    final localErrors = validateFormatStructurePayload(payload);
    if (localErrors.isNotEmpty) {
      setState(() {
        validation = {
          'valido': false,
          'errores': localErrors
              .map((message) => {'campo': 'estructura', 'mensaje': message})
              .toList(),
          'advertencias': <dynamic>[],
        };
        currentStep = 4;
      });
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final saved = await repository.saveDraft(
        entityType: 'FORMATO',
        payload: payload,
        draftId: draftId,
        templateId: selectedTemplateId,
        lockVersion: lockVersion,
      );
      draftId = saved['id']?.toString();
      lockVersion = int.tryParse('${saved['lock_version'] ?? ''}');
      if (draftId == null) throw StateError('No se recibió el borrador.');
      final result = await repository.validateFormatStructure(draftId!);
      if (!mounted) return;
      setState(() {
        validation = result;
        saving = false;
        currentStep = 4;
        tables = _maps(payload['tablas']);
        lockVersion = null;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = 'No se pudo guardar y validar: $exception';
      });
    }
  }

  Future<void> _publish() async {
    if (!isValid || !canPublish || draftId == null) return;
    if (!await _hasInternet()) {
      if (!mounted) return;
      setState(() => error = 'Necesitas internet para publicar');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Necesitas internet para publicar')),
      );
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          focusedFieldMode ? 'Publicar cambio del campo' : 'Publicar cambios',
        ),
        content: Text(
          focusedFieldMode
              ? 'Se aplicará el cambio de este campo. Si algo falla, la configuración publicada permanecerá intacta.'
              : 'Se aplicarán los cambios del formato, sus tablas, campos y reglas en una sola operación. Si algo falla, no se modificará la configuración publicada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.publish_outlined),
            label: const Text('Publicar cambios'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final result = await repository.publishFormatStructure(
        draftId!,
        notes: 'Publicación atómica desde el asistente de formato.',
      );
      if (!mounted) return;
      if (result['publicado'] == true) {
        await experience.clearBuilderDraft(_autosaveKey);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Formato publicado: ${result['tablas_publicadas'] ?? 0} tabla(s), ${result['campos_publicados'] ?? 0} campo(s) y ${result['matrices_publicadas'] ?? 0} matriz(ces).',
            ),
          ),
        );
        Navigator.pop(context, true);
        return;
      }
      setState(() {
        saving = false;
        error = result['error']?.toString() ??
            'La estructura fue rechazada durante la publicación.';
        validation = result['validacion'] is Map
            ? Map<String, dynamic>.from(result['validacion'] as Map)
            : validation;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = 'No se pudo publicar: $exception';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FA),
      appBar: AppBar(
        title: Text(
          focusedFieldMode
              ? (focusedNewField ? 'Agregar campo' : 'Editar campo')
              : editingPublished
                  ? 'Editar formato'
                  : 'Creador de formato',
          maxLines: 2,
          overflow: TextOverflow.visible,
        ),
        bottom: focusedFieldMode ? null : _autosaveBar(),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : focusedFieldMode
              ? _focusedFieldPage()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final contentWidth = constraints.maxWidth > 1360
                        ? 1360.0
                        : constraints.maxWidth;
                    return Center(
                      child: SizedBox(
                        width: contentWidth,
                        child: Stepper(
                          type: contentWidth >= 1180
                              ? StepperType.horizontal
                              : StepperType.vertical,
                          currentStep: currentStep,
                          onStepTapped: saving
                              ? null
                              : (value) => setState(() => currentStep = value),
                          onStepContinue: saving
                              ? null
                              : () {
                                  if (currentStep < 4) {
                                    setState(() => currentStep++);
                                  } else {
                                    _saveAndValidate();
                                  }
                                },
                          onStepCancel: saving || currentStep == 0
                              ? null
                              : () => setState(() => currentStep--),
                          controlsBuilder: _controls,
                          steps: [
                            Step(
                              title: const Text('Origen'),
                              isActive: currentStep >= 0,
                              content: _originStep(),
                            ),
                            Step(
                              title: const Text('Identidad'),
                              isActive: currentStep >= 1,
                              content: _identityStep(),
                            ),
                            Step(
                              title: const Text('Capacidades'),
                              isActive: currentStep >= 2,
                              content: _capabilitiesStep(),
                            ),
                            Step(
                              title: const Text('Estructura'),
                              isActive: currentStep >= 3,
                              content: _structureStep(),
                            ),
                            Step(
                              title: const Text('Revisar'),
                              isActive: currentStep >= 4,
                              state: isValid
                                  ? StepState.complete
                                  : StepState.indexed,
                              content: _reviewStep(),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _focusedFieldPage() {
    final tableIndex = focusedTableIndex;
    final fieldIndex = focusedFieldIndex;
    Map<String, dynamic>? field;
    if (tableIndex != null && tableIndex >= 0 && tableIndex < tables.length) {
      final fields = _maps(tables[tableIndex]['campos']);
      if (fieldIndex != null && fieldIndex >= 0 && fieldIndex < fields.length) {
        field = fields[fieldIndex];
      }
    }
    final fieldName = field?['etiqueta']?.toString().trim().isNotEmpty == true
        ? field!['etiqueta'].toString()
        : field?['nombre']?.toString() ??
            (focusedNewField ? 'Nuevo campo' : 'Campo seleccionado');
    final deleted = field?['activo'] == false;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF4F7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Está modificando únicamente este campo. El resto del formato conserva su configuración actual.',
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          child: ListTile(
            leading: CircleAvatar(
              child: Icon(
                deleted ? Icons.delete_outline : Icons.text_fields_outlined,
              ),
            ),
            title: Text(
              fieldName,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              'Formato: ${nameController.text.trim().isEmpty ? 'Sin nombre' : nameController.text.trim()}',
            ),
            trailing: field == null || deleted
                ? null
                : IconButton(
                    tooltip: 'Abrir configuración del campo',
                    onPressed:
                        saving || tableIndex == null || fieldIndex == null
                            ? null
                            : () => _editField(tableIndex, index: fieldIndex),
                    icon: const Icon(Icons.edit_outlined),
                  ),
            onTap: field == null ||
                    deleted ||
                    saving ||
                    tableIndex == null ||
                    fieldIndex == null
                ? null
                : () => _editField(tableIndex, index: fieldIndex),
          ),
        ),
        if (focusedActionMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            focusedActionMessage!,
            style: const TextStyle(color: Color(0xFF60758A)),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!, style: const TextStyle(color: Colors.red)),
        ],
        if (field != null) ...[
          const SizedBox(height: 12),
          _focusedFieldDetails(field),
        ],
        if (validation != null && field != null) ...[
          const SizedBox(height: 14),
          _focusedFieldValidation(),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: saving || field == null ? null : _saveAndValidate,
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Guardar cambios'),
            ),
            if (isValid && canPublish)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0C7A5B),
                ),
                onPressed: saving ? null : _publish,
                icon: const Icon(Icons.publish_outlined),
                label: const Text('Publicar cambios'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _focusedFieldDetails(Map<String, dynamic> field) {
    final uiType = field['tipo_ui']?.toString() ?? 'Campo';
    final dataType = field['tipo']?.toString() ?? 'text';
    final defaultValue = field['valor_default']?.toString().trim() ?? '';
    final formula = field['formula_funcion']?.toString().trim() ?? '';
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _focusedFieldLine('Control', uiType),
            _focusedFieldLine('Tipo de dato', dataType),
            _focusedFieldLine(
              'Obligatorio',
              field['requerido'] == true ? 'Sí' : 'No',
            ),
            _focusedFieldLine(
              'Editable',
              field['editable'] == false ? 'No' : 'Sí',
            ),
            _focusedFieldLine(
              'Visible en formulario',
              field['visible'] == false ? 'No' : 'Sí',
            ),
            _focusedFieldLine(
              'Visible en registros',
              field['visible_tabla'] == false ? 'No' : 'Sí',
            ),
            if (defaultValue.isNotEmpty)
              _focusedFieldLine('Valor predeterminado', defaultValue),
            if (formula.isNotEmpty) _focusedFieldLine('Fórmula', formula),
            _focusedFieldLine(
              'Estado',
              field['activo'] == false ? 'Inactivo' : 'Activo',
            ),
          ],
        ),
      ),
    );
  }

  Widget _focusedFieldLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 145,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF60758A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _focusedFieldValidation() {
    final errors = validation?['errores'] is List
        ? List<dynamic>.from(validation!['errores'] as List)
        : const <dynamic>[];
    final warnings = validation?['advertencias'] is List
        ? List<dynamic>.from(validation!['advertencias'] as List)
        : const <dynamic>[];
    final message = isValid
        ? 'El cambio del campo está validado y listo para publicar.'
        : errors.isEmpty
            ? 'Revise el campo antes de guardar los cambios.'
            : 'Corrija ${errors.length} error(es) antes de publicar.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isValid ? const Color(0xFFE8F6F1) : const Color(0xFFFFF1F0),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color:
                  isValid ? const Color(0xFF79BEA4) : const Color(0xFFE8A39D),
            ),
          ),
          child: Text(message,
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        for (final item in errors) _validationItem(item, Colors.red.shade700),
        for (final item in warnings)
          _validationItem(item, Colors.orange.shade800),
      ],
    );
  }

  Widget _controls(BuildContext context, ControlsDetails details) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          if (currentStep < 4)
            FilledButton.icon(
              onPressed: saving ? null : details.onStepContinue,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Continuar'),
            )
          else
            FilledButton.icon(
              onPressed: saving ? null : _saveAndValidate,
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fact_check_outlined),
              label: const Text('Guardar y validar'),
            ),
          if (currentStep == 4 && isValid && canPublish)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0C7A5B),
              ),
              onPressed: saving ? null : _publish,
              icon: const Icon(Icons.publish_outlined),
              label: const Text('Publicar cambios'),
            ),
          if (currentStep > 0)
            OutlinedButton(
              onPressed: saving ? null : details.onStepCancel,
              child: const Text('Atrás'),
            ),
        ],
      ),
    );
  }

  Widget _originStep() {
    if (editingPublished) {
      return _question(
        'Configuración actual',
        'Estos son los valores existentes. Puede avanzar por cada sección y modificar únicamente lo que necesite.',
        Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.assignment_outlined),
              title: const Text('Nombre del formato'),
              subtitle: Text(nameController.text.trim().isEmpty
                  ? 'Sin nombre'
                  : nameController.text.trim()),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.grid_view_outlined),
              title: const Text('Módulo'),
              subtitle: Text(_selectedModuleName()),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('Estructura'),
              subtitle: Text(
                '${tables.length} ${tables.length == 1 ? 'tabla' : 'tablas'} · ${_configuredFieldCount()} campos',
              ),
            ),
          ],
        ),
      );
    }
    return _question(
      '¿Desea crear desde cero o copiar una plantilla?',
      'La copia conserva tablas, campos y reglas, pero usa nuevos identificadores para no modificar la plantilla original.',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.add_outlined),
                label: Text('Desde cero'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.copy_all_outlined),
                label: Text('Usar plantilla'),
              ),
            ],
            selected: {selectedTemplateId != null},
            onSelectionChanged: saving
                ? null
                : (selection) {
                    if (!selection.first) {
                      _selectTemplate(null);
                    } else if (_availableFormatTemplates.isNotEmpty) {
                      _selectTemplate(
                        _availableFormatTemplates.first['id']?.toString(),
                      );
                    }
                  },
          ),
          if (_availableFormatTemplates.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('format-template-$selectedTemplateId'),
              initialValue: _availableFormatTemplates.any(
                (row) => row['id']?.toString() == selectedTemplateId,
              )
                  ? selectedTemplateId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Plantilla de formato',
                border: OutlineInputBorder(),
              ),
              items: _availableFormatTemplates
                  .map(
                    (row) => DropdownMenuItem(
                      value: row['id']?.toString(),
                      child: Text(
                        row['nombre']?.toString() ?? 'Sin nombre',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: saving ? null : _selectTemplate,
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }

  Widget _identityStep() {
    return Column(
      children: [
        _question(
          editingPublished
              ? '¿Mantener o mover este formato?'
              : '¿En qué módulo se mostrará?',
          editingPublished
              ? 'Selecciona otro módulo para mover el formato con toda su configuración y sus tablas.'
              : 'El módulo determina la ubicación del formato en la navegación.',
          DropdownButtonFormField<String>(
            key: ValueKey('module-$selectedModuleId'),
            initialValue: _availableModuleTemplates.any(
              (row) => row['entidad_origen_id']?.toString() == selectedModuleId,
            )
                ? selectedModuleId
                : null,
            decoration: InputDecoration(
              labelText: editingPublished ? 'Mover al módulo *' : 'Módulo *',
              border: const OutlineInputBorder(),
            ),
            items: _availableModuleTemplates
                .map(
                  (row) => DropdownMenuItem(
                    value: row['entidad_origen_id']?.toString(),
                    child: Text(
                      row['nombre']?.toString() ?? 'Sin nombre',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() {
              selectedModuleId = value;
              _deriveRubro();
              _syncGeneratedFormatCode();
              orderController.text = '0';
              _suggestNextOrder();
              validation = null;
            }),
          ),
        ),
        const SizedBox(height: 14),
        _textQuestion(
          '¿Nombre del formato?',
          'Este es el nombre que verán las personas en la aplicación.',
          nameController,
          label: 'Nombre del formato *',
          hint: 'Ej. Inspección de cultivo',
          onChanged: (_) => setState(() {
            _syncGeneratedFormatCode();
            validation = null;
          }),
        ),
        if (_suggestionsForPath('nombre').isNotEmpty ||
            _suggestionsForPath('codigo').isNotEmpty) ...[
          const SizedBox(height: 8),
          _suggestionChoices(
            nameController,
            {
              ..._suggestionsForPath('nombre'),
              ..._suggestionsForPath('codigo'),
            }.toList(),
            () => setState(() {
              _syncGeneratedFormatCode();
              validation = null;
            }),
          ),
        ],
        const SizedBox(height: 14),
        _textQuestion(
          '¿Cuál es el propósito del formato?',
          'Ayuda a otros administradores a entender su alcance.',
          descriptionController,
          label: 'Descripción',
          minLines: 3,
          maxLines: 5,
        ),
        const SizedBox(height: 14),
        _textQuestion(
          '¿En qué orden debe aparecer?',
          'Controla la posición dentro del módulo.',
          orderController,
          label: 'Orden *',
          keyboardType: TextInputType.number,
          suffix: IconButton(
            tooltip: 'Ver el orden actual del módulo',
            onPressed: _showCurrentFormatOrder,
            icon: const Icon(Icons.format_list_numbered),
          ),
        ),
      ],
    );
  }

  Widget _capabilitiesStep() {
    return Column(
      children: [
        _capability(
          'Trabajo sin conexión',
          'Permite capturar y sincronizar posteriormente.',
          offline,
          (value) => offline = value,
        ),
        _capability(
          'Flujo de estados',
          'Actívelo y configure aquí los estados por los que avanzará el registro.',
          workflow,
          (value) => workflow = value,
        ),
        if (workflow)
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 9),
            child: ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: const Text(
                'Configurar flujo de estados',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(workflowStates.join('  ›  ')),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _editWorkflowStates,
            ),
          ),
        _capability(
          'Evidencias fotográficas',
          'Habilita preguntas y controles asociados a fotos.',
          photos,
          (value) => photos = value,
        ),
        _capability(
          'Firma',
          'Se activa también automáticamente al elegir un campo Firma; no limita su creación.',
          signature,
          (value) => signature = value,
        ),
        _capability(
          'Geolocalización',
          'Crea y llena latitud, longitud, precisión y fecha GPS, incluso sin internet.',
          geolocation,
          (value) => geolocation = value,
        ),
        _capability(
          'Lectura QR',
          'Se activa automáticamente al elegir el Tipo de Campo “Lector QR”.',
          qr,
          (value) => qr = value,
        ),
        _capability(
          'Aprobaciones',
          'Agrega PENDIENTE → REVISADO → APROBADO y habilita permisos Revisa/Aprueba.',
          approvals,
          (value) => approvals = value,
        ),
        _capability(
          'Mostrar tabla de registros',
          'Habilita la vista de consulta, búsqueda y edición de registros.',
          tableVisible,
          (value) => tableVisible = value,
        ),
        _capability(
          'Activo al publicar',
          'Los usuarios podrán verlo después de actualizar datos.',
          active,
          (value) => active = value,
        ),
      ],
    );
  }

  Widget _capability(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> assign,
  ) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 9),
      child: SwitchListTile(
        value: value,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        onChanged: (next) => setState(() {
          assign(next);
          validation = null;
        }),
      ),
    );
  }

  Future<void> _editWorkflowStates() async {
    final states = List<String>.from(workflowStates);
    final controller = TextEditingController();
    final result = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Flujo de estados'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Ordene los estados tal como avanzará el registro.',
                  ),
                ),
                const SizedBox(height: 12),
                for (var index = 0; index < states.length; index++)
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      child: Text('${index + 1}'),
                    ),
                    title: Text(states[index]),
                    trailing: IconButton(
                      tooltip: 'Quitar',
                      onPressed: states.length <= 1
                          ? null
                          : () => setDialogState(() => states.removeAt(index)),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: 'Nuevo estado',
                    hintText: 'Ej. EN_SUPERVISION',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: 'Agregar',
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        final value = controller.text
                            .trim()
                            .toUpperCase()
                            .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
                            .replaceAll(RegExp(r'^_|_$'), '');
                        if (value.isEmpty || states.contains(value)) return;
                        setDialogState(() {
                          states.add(value);
                          controller.clear();
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, states),
              child: const Text('Guardar flujo'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty || !mounted) return;
    setState(() {
      workflowStates = result;
      validation = null;
    });
  }

  Widget _structureStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF4F7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Defina cada tabla, sus campos y las matrices que controlan dropdowns, validaciones, condiciones y fórmulas.',
          ),
        ),
        const SizedBox(height: 12),
        for (var tableIndex = 0; tableIndex < tables.length; tableIndex++)
          _tableCard(tableIndex),
        OutlinedButton.icon(
          onPressed: saving ? null : () => _editTable(),
          icon: const Icon(Icons.add),
          label: const Text('Agregar tabla'),
        ),
      ],
    );
  }

  Widget _tableCard(int tableIndex) {
    final table = tables[tableIndex];
    final fields = _maps(table['campos']);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFD3E2E8)),
      ),
      child: ExpansionTile(
        leading: const CircleAvatar(child: Icon(Icons.table_chart_outlined)),
        title: Text(
          table['nombre']?.toString() ?? 'Tabla ${tableIndex + 1}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${fields.length} campo(s) configurado(s)',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _editTable(index: tableIndex),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Editar tabla'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _editField(tableIndex),
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar campo'),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() {
                        tables.removeAt(tableIndex);
                        validation = null;
                      }),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Quitar'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (fields.isEmpty)
                  const Text('Todavía no hay campos en esta tabla.')
                else
                  for (var fieldIndex = 0;
                      fieldIndex < fields.length;
                      fieldIndex++)
                    _fieldCard(tableIndex, fieldIndex, fields[fieldIndex]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldCard(
    int tableIndex,
    int fieldIndex,
    Map<String, dynamic> field,
  ) {
    final matrices = _maps(field['matrices']);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE0E7EB)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.text_fields_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${field['etiqueta'] ?? field['nombre'] ?? 'Campo'} · ${field['tipo_ui'] ?? 'text'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Editar campo',
                onPressed: () => _editField(
                  tableIndex,
                  index: fieldIndex,
                ),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Quitar campo',
                onPressed: () => setState(() {
                  final fields = _maps(tables[tableIndex]['campos']);
                  fields.removeAt(fieldIndex);
                  tables[tableIndex]['campos'] = fields;
                  validation = null;
                }),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          Text(
            '${matrices.length} regla(s) o matriz(ces)',
            style: const TextStyle(color: Color(0xFF60758A), fontSize: 12),
          ),
          const SizedBox(height: 6),
          for (var matrixIndex = 0;
              matrixIndex < matrices.length;
              matrixIndex++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.account_tree_outlined, size: 20),
              title:
                  Text(matrices[matrixIndex]['nombre']?.toString() ?? 'Matriz'),
              subtitle: Text(
                matrices[matrixIndex]['clase_matriz']?.toString() ?? '',
              ),
              trailing: Wrap(
                spacing: 0,
                children: [
                  IconButton(
                    tooltip: 'Editar matriz',
                    onPressed: () => _editMatrix(
                      tableIndex,
                      fieldIndex,
                      index: matrixIndex,
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 20),
                  ),
                  IconButton(
                    tooltip: 'Quitar matriz',
                    onPressed: () => setState(() {
                      matrices.removeAt(matrixIndex);
                      final fields = _maps(tables[tableIndex]['campos']);
                      fields[fieldIndex]['matrices'] = matrices;
                      tables[tableIndex]['campos'] = fields;
                      validation = null;
                    }),
                    icon: const Icon(Icons.delete_outline, size: 20),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _editMatrix(tableIndex, fieldIndex),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Agregar regla o matriz'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editTable({int? index}) async {
    final initial = index == null ? <String, dynamic>{} : tables[index];
    final name = TextEditingController(text: initial['nombre']?.toString());
    final order = TextEditingController(
        text: initial['orden']?.toString() ?? '${tables.length + 1}');
    final parent =
        TextEditingController(text: initial['tabla_padre']?.toString());
    final parentKey = TextEditingController(
        text: initial['campo_pk_padre']?.toString() ?? 'id_local');
    final foreignKey =
        TextEditingController(text: initial['campo_fk_hijo']?.toString());
    final parentTables = tables.asMap().entries.where((entry) {
      return entry.key != index && entry.value['activo'] != false;
    }).toList()
      ..sort((left, right) {
        final leftHeader = left.value['es_cabecera'] == true ? 0 : 1;
        final rightHeader = right.value['es_cabecera'] == true ? 0 : 1;
        return leftHeader.compareTo(rightHeader);
      });
    String parentValue(Map<String, dynamic> table) =>
        table['tabla_destino']?.toString().trim().isNotEmpty == true
            ? table['tabla_destino'].toString()
            : table['codigo']?.toString() ?? '';
    if (initial['es_detalle'] == true &&
        parent.text.trim().isEmpty &&
        parentTables.isNotEmpty) {
      parent.text = parentValue(parentTables.first.value);
    }
    if (initial['es_detalle'] == true &&
        foreignKey.text.trim().isEmpty &&
        parent.text.trim().isNotEmpty) {
      foreignKey.text = '${_slug(parent.text.trim())}_id';
    }
    var createPhysical = initial['crear_tabla_fisica'] != false;
    var header = initial['es_cabecera'] == true;
    var detail = initial['es_detalle'] == true;
    bool? auditable = initial.containsKey('auditable')
        ? initial['auditable'] == true ||
            initial['auditable'] == 1 ||
            initial['auditable']?.toString().toLowerCase() == 'true'
        : null;
    String? auditableError;
    var selectedIcon = initial['icono']?.toString().trim().isNotEmpty == true
        ? initial['icono'].toString()
        : 'assignment';
    var headerImage = initial['imagen_encabezado']?.toString() ?? '';

    Widget imagePreview() {
      if (!headerImage.startsWith('data:image/') ||
          !headerImage.contains(',')) {
        return Icon(configurationIconForName(selectedIcon), size: 34);
      }
      try {
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(
            base64Decode(headerImage.split(',').last),
            width: 54,
            height: 54,
            fit: BoxFit.cover,
          ),
        );
      } catch (_) {
        return Icon(configurationIconForName(selectedIcon), size: 34);
      }
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(index == null ? 'Nueva tabla' : 'Editar tabla'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dialogField(
                    name,
                    'Nombre de tabla *',
                    helperText:
                        'Nombre visible que identificarán los usuarios.',
                  ),
                  DropdownButtonFormField<bool>(
                    initialValue: auditable,
                    decoration: InputDecoration(
                      labelText: '¿Es auditable? *',
                      helperText:
                          'Sí muestra código; No centra el título sobre todo el encabezado.',
                      errorText: auditableError,
                      border: const OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: true, child: Text('Sí')),
                      DropdownMenuItem(value: false, child: Text('No')),
                    ],
                    onChanged: (value) => setDialogState(() {
                      auditable = value;
                      auditableError = null;
                    }),
                  ),
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    leading: imagePreview(),
                    title: const Text(
                      'Icono o imagen del encabezado',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'Elija un icono agrícola o suba una imagen JPG, PNG o WebP.',
                    ),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: configurationIconChoices
                              .map((choice) => ChoiceChip(
                                    selected: headerImage.isEmpty &&
                                        selectedIcon == choice.value,
                                    avatar: Icon(choice.icon, size: 17),
                                    label: Text(choice.label),
                                    onSelected: (_) => setDialogState(() {
                                      selectedIcon = choice.value;
                                      headerImage = '';
                                    }),
                                  ))
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              final picked =
                                  await FilePicker.platform.pickFiles(
                                type: FileType.image,
                                withData: true,
                                allowMultiple: false,
                              );
                              final file = picked?.files.single;
                              final bytes = file?.bytes;
                              if (bytes == null || !mounted) return;
                              final extension =
                                  (file?.extension ?? 'png').toLowerCase();
                              final mime =
                                  extension == 'jpg' || extension == 'jpeg'
                                      ? 'jpeg'
                                      : extension == 'webp'
                                          ? 'webp'
                                          : 'png';
                              setDialogState(() {
                                headerImage =
                                    'data:image/$mime;base64,${base64Encode(bytes)}';
                              });
                            },
                            icon: const Icon(Icons.upload_file_outlined),
                            label: const Text('Subir imagen'),
                          ),
                          if (headerImage.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: () =>
                                  setDialogState(() => headerImage = ''),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Quitar'),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                  if (index != null &&
                      _suggestionsForPath('tablas[$index]').isNotEmpty)
                    _suggestionChoices(
                      name,
                      _suggestionsForPath('tablas[$index]'),
                      () => setDialogState(() {}),
                    ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.tune_outlined),
                    title: const Text(
                      'Configuración avanzada',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'Orden y relaciones entre cabecera y detalle.',
                    ),
                    children: [
                      _dialogField(
                        order,
                        'Orden *',
                        keyboardType: TextInputType.number,
                        helperText:
                            'Posición de esta tabla dentro del formato.',
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: createPhysical,
                        title: const Text('Crear almacenamiento al publicar'),
                        subtitle: const Text(
                          'Déjelo activo cuando la tabla es nueva.',
                        ),
                        onChanged: (value) =>
                            setDialogState(() => createPhysical = value),
                      ),
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF4F7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Use “Es cabecera” cuando esta tabla guarda los datos principales una sola vez (por ejemplo fecha, lote y responsable) y tendrá otra tabla con varias filas de detalle.',
                          style: TextStyle(
                            color: Color(0xFF31596B),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: header,
                        title: const Text('Es cabecera'),
                        subtitle: const Text('Contiene los datos principales.'),
                        onChanged: (value) => setDialogState(() {
                          header = value == true;
                          if (header) detail = false;
                        }),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: detail,
                        title: const Text('Es detalle'),
                        subtitle:
                            const Text('Repite filas ligadas a una cabecera.'),
                        onChanged: (value) => setDialogState(() {
                          detail = value == true;
                          if (!detail) return;
                          header = false;
                          if (parent.text.trim().isEmpty &&
                              parentTables.isNotEmpty) {
                            parent.text = parentValue(parentTables.first.value);
                          }
                          if (foreignKey.text.trim().isEmpty &&
                              parent.text.trim().isNotEmpty) {
                            foreignKey.text = '${_slug(parent.text.trim())}_id';
                          }
                        }),
                      ),
                      if (detail) ...[
                        if (parentTables.isEmpty)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF6DE),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFE7C96A),
                              ),
                            ),
                            child: const Text(
                              'Primero cree una tabla cabecera. Una tabla detalle necesita seleccionar esa tabla como padre.',
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: DropdownButtonFormField<String>(
                              key: ValueKey('parent-table-${parent.text}'),
                              initialValue: parentTables.any(
                                (entry) =>
                                    parentValue(entry.value) == parent.text,
                              )
                                  ? parent.text
                                  : null,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Tabla padre *',
                                helperText:
                                    'Seleccione la tabla cabecera relacionada.',
                                border: OutlineInputBorder(),
                              ),
                              items: parentTables.map((entry) {
                                final table = entry.value;
                                return DropdownMenuItem(
                                  value: parentValue(table),
                                  child: Text(
                                    table['nombre']?.toString() ??
                                        parentValue(table),
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) => setDialogState(() {
                                parent.text = value ?? '';
                                if (foreignKey.text.trim().isEmpty &&
                                    value?.isNotEmpty == true) {
                                  foreignKey.text = '${_slug(value!)}_id';
                                }
                              }),
                            ),
                          ),
                        _dialogField(
                          parentKey,
                          'Campo principal del padre *',
                          helperText:
                              'Normalmente id_local, identificador estable de la cabecera.',
                        ),
                        _dialogField(
                          foreignKey,
                          'Campo de relación del detalle *',
                          helperText:
                              'Columna que guardará el identificador del padre.',
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (auditable == null) {
                  setDialogState(() => auditableError =
                      'Seleccione Sí o No para crear la tabla.');
                  return;
                }
                final visibleName = name.text.trim();
                final existingCode = initial['codigo']?.toString().trim() ?? '';
                final existingPhysical =
                    initial['tabla_destino']?.toString().trim() ?? '';
                Navigator.pop(dialogContext, {
                  ...initial,
                  'nombre': visibleName,
                  'codigo': existingCode.isEmpty
                      ? _generatedTableCode(visibleName)
                      : existingCode,
                  'tabla_destino': existingPhysical.isEmpty
                      ? _generatedTableName(visibleName)
                      : existingPhysical,
                  'orden': int.tryParse(order.text.trim()) ?? order.text.trim(),
                  'crear_tabla_fisica': createPhysical,
                  'auditable': auditable,
                  'icono': selectedIcon,
                  'imagen_encabezado': headerImage.isEmpty ? null : headerImage,
                  'activo': initial['activo'] != false,
                  'es_cabecera': header,
                  'es_detalle': detail,
                  'tipo_relacion': detail ? 'UNO_MUCHOS' : null,
                  'tabla_padre': detail ? parent.text.trim() : null,
                  'campo_pk_padre': detail ? parentKey.text.trim() : null,
                  'campo_fk_hijo': detail ? foreignKey.text.trim() : null,
                  'modo_captura': initial['modo_captura'] ?? 'FORMULARIO',
                  'campos': _maps(initial['campos']),
                });
              },
              child: const Text('Guardar tabla'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    order.dispose();
    parent.dispose();
    parentKey.dispose();
    foreignKey.dispose();
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        tables.add(result);
      } else {
        tables[index] = result;
      }
      validation = null;
    });
  }

  Future<Map<String, dynamic>?> _pickBuilderFieldReference({
    String? preferredTable,
  }) async {
    final catalog = <Map<String, dynamic>>[];
    for (final table in tables) {
      final tableName = table['tabla_destino']?.toString().trim() ?? '';
      final tableLabel = table['nombre']?.toString().trim() ?? tableName;
      for (final field in _maps(table['campos'])) {
        final campo = field['campo']?.toString().trim() ?? '';
        if (tableName.isEmpty || campo.isEmpty) continue;
        catalog.add({
          'tabla_destino': tableName,
          'tabla_nombre': tableLabel,
          'campo': campo,
          'campo_etiqueta':
              field['etiqueta']?.toString().trim().isNotEmpty == true
                  ? field['etiqueta'].toString().trim()
                  : campo,
          'ruta': 'Este formato › $tableLabel › $campo',
        });
      }
    }
    try {
      catalog.addAll(await repository.searchBuilderFieldCatalog());
    } catch (_) {
      // El catálogo del borrador sigue siendo utilizable sin conexión o antes
      // de aplicar la RPC de catálogo en una instalación existente.
    }
    final unique = <String, Map<String, dynamic>>{};
    for (final item in catalog) {
      final table = item['tabla_destino']?.toString().trim() ?? '';
      final field = item['campo']?.toString().trim() ?? '';
      if (table.isEmpty || field.isEmpty) continue;
      unique['${table.toUpperCase()}|${field.toUpperCase()}'] = item;
    }
    final items = unique.values.toList()
      ..sort((a, b) {
        final aTable = a['tabla_destino']?.toString() ?? '';
        final bTable = b['tabla_destino']?.toString() ?? '';
        final preferredA =
            preferredTable != null && aTable == preferredTable ? 0 : 1;
        final preferredB =
            preferredTable != null && bTable == preferredTable ? 0 : 1;
        if (preferredA != preferredB) return preferredA.compareTo(preferredB);
        final tableOrder = aTable.compareTo(bTable);
        if (tableOrder != 0) return tableOrder;
        return (a['campo']?.toString() ?? '')
            .compareTo(b['campo']?.toString() ?? '');
      });

    if (!mounted) return null;
    final search = TextEditingController();
    try {
      return await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            final query = search.text.trim().toLowerCase();
            final filtered = items
                .where((item) {
                  if (query.isEmpty) return true;
                  final haystack = [
                    item['ruta'],
                    item['modulo_nombre'],
                    item['tabla_nombre'],
                    item['tabla_destino'],
                    item['campo_etiqueta'],
                    item['campo'],
                  ].join(' ').toLowerCase();
                  return haystack.contains(query);
                })
                .take(250)
                .toList();
            return AlertDialog(
              title: const Text('Elegir tabla y campo'),
              content: SizedBox(
                width: 720,
                height: 520,
                child: Column(
                  children: [
                    TextField(
                      controller: search,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Buscar por tabla o campo',
                        hintText: 'Ej. turno, lote, variedad',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text(
                                'No se encontraron campos permitidos.',
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = filtered[index];
                                final table =
                                    item['tabla_destino']?.toString() ?? '';
                                final campo = item['campo']?.toString() ?? '';
                                final path = item['ruta']
                                            ?.toString()
                                            .trim()
                                            .isNotEmpty ==
                                        true
                                    ? item['ruta'].toString()
                                    : '${item['modulo_nombre'] ?? 'Módulo'} › ${item['tabla_nombre'] ?? table} › $campo';
                                return ListTile(
                                  leading: const Icon(
                                    Icons.table_view_outlined,
                                    color: Color(0xFF176B87),
                                  ),
                                  title: Text(
                                    item['campo_etiqueta']?.toString() ?? campo,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(path),
                                  trailing:
                                      const Icon(Icons.check_circle_outline),
                                  onTap: () =>
                                      Navigator.pop(dialogContext, item),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      search.dispose();
    }
  }

  Future<void> _editField(int tableIndex, {int? index}) async {
    final fields = _maps(tables[tableIndex]['campos']);
    final initial = index == null ? <String, dynamic>{} : fields[index];
    bool boolValue(dynamic value, {bool fallback = false}) {
      if (value == null) return fallback;
      if (value is bool) return value;
      if (value is num) return value != 0;
      return const {'true', 't', '1', 'si', 'sí', 'yes'}
          .contains(value.toString().trim().toLowerCase());
    }

    final label = TextEditingController(text: initial['etiqueta']?.toString());
    final code = TextEditingController(text: initial['codigo']?.toString());
    final physical = TextEditingController(text: initial['campo']?.toString());
    final order = TextEditingController(
        text: initial['orden']?.toString() ?? '${fields.length + 1}');
    final defaultValue =
        TextEditingController(text: initial['valor_default']?.toString());
    final formula =
        TextEditingController(text: initial['formula_funcion']?.toString());
    final dropdown =
        TextEditingController(text: initial['id_campo_dropdown']?.toString());
    final idGenerator =
        TextEditingController(text: initial['id_generador']?.toString());
    final decimals =
        TextEditingController(text: initial['numero_decimales']?.toString());
    final gridRow =
        TextEditingController(text: initial['grid_fila']?.toString());
    final gridColumn =
        TextEditingController(text: initial['grid_columna']?.toString());
    final pendingGridRow = TextEditingController(
        text: initial['grid_fila_pendientes']?.toString());
    final pendingGridColumn = TextEditingController(
        text: initial['grid_columna_pendientes']?.toString());
    final valueRange =
        TextEditingController(text: initial['rango_valor']?.toString());
    final maxCharacters =
        TextEditingController(text: initial['num_caracteres']?.toString());
    final photoCount =
        TextEditingController(text: initial['numero_fotos']?.toString());
    final photoDepends =
        TextEditingController(text: initial['photo_depende_de']?.toString());
    final photoList =
        TextEditingController(text: initial['lista_destino_photo']?.toString());
    final photoOrder =
        TextEditingController(text: initial['orden_lista_photo']?.toString());
    final conditionalFormat = TextEditingController(
        text: initial['formato_condicional_campo']?.toString());
    final textColorCondition = TextEditingController(
        text: initial['condicion_color_texto']?.toString() ??
            conditionalFormat.text);
    final backgroundColorCondition = TextEditingController(
        text: initial['condicion_color_fondo']?.toString() ??
            conditionalFormat.text);
    final borderColorCondition = TextEditingController(
        text: initial['condicion_color_borde']?.toString() ??
            conditionalFormat.text);
    final textColor =
        TextEditingController(text: initial['color_texto']?.toString());
    final backgroundColor =
        TextEditingController(text: initial['color_fondo']?.toString());
    final borderColor =
        TextEditingController(text: initial['color_borde']?.toString());
    final fontSize =
        TextEditingController(text: initial['tamanio_letra']?.toString());
    final subtitle =
        TextEditingController(text: initial['sub_titulo']?.toString());
    final subtitleAlignment = TextEditingController(
        text: initial['subtitulo_alineacion']?.toString() ?? 'left');
    final subtitleFontSize = TextEditingController(
        text: initial['subtitulo_tamanio_letra']?.toString());
    final subtitleColor =
        TextEditingController(text: initial['subtitulo_color']?.toString());
    final subtitlePadding = TextEditingController(
        text: initial['subtitulo_padding']?.toString() ?? '12,10,12,10');
    final captureGroup =
        TextEditingController(text: initial['grupo_captura']?.toString());
    final title1 = TextEditingController(text: initial['titulo1']?.toString());
    final title2 = TextEditingController(text: initial['titulo2']?.toString());
    final code1 = TextEditingController(text: initial['codigo1']?.toString());
    final code2 = TextEditingController(text: initial['codigo2']?.toString());
    final title1Alignment = TextEditingController(
        text: initial['titulo1_alineacion']?.toString() ?? 'center');
    final title1FontSize = TextEditingController(
        text: initial['titulo1_tamanio_letra']?.toString());
    final title1Color =
        TextEditingController(text: initial['titulo1_color']?.toString());
    final title1Padding = TextEditingController(
        text: initial['titulo1_padding']?.toString() ?? '8,3,8,3');
    final title2Alignment = TextEditingController(
        text: initial['titulo2_alineacion']?.toString() ?? 'center');
    final title2FontSize = TextEditingController(
        text: initial['titulo2_tamanio_letra']?.toString());
    final title2Color =
        TextEditingController(text: initial['titulo2_color']?.toString());
    final title2Padding = TextEditingController(
        text: initial['titulo2_padding']?.toString() ?? '8,3,8,3');
    final formulaSourceTable = TextEditingController(
        text: initial['formula_tabla_origen']?.toString());
    final formulaValueField =
        TextEditingController(text: initial['formula_campo_valor']?.toString());
    final formulaFilterField = TextEditingController(
        text: initial['formula_campo_condicion']?.toString());
    final formulaFilterValue = TextEditingController(
        text: initial['formula_valor_condicion']?.toString());
    var uiType = initial['tipo_ui']?.toString() ?? 'text';
    if (uiType == 'textarea') uiType = 'multiline';
    if (uiType == 'boolean' || uiType == 'boolean_int') uiType = 'checkbox';
    if (uiType == 'qr') uiType = 'qr_scan';
    var dataType = (uiType == 'formula' || uiType == 'lookup')
        ? _formulaResultType(initial['tipo']?.toString() ?? 'text')
        : _dataTypeForUi(uiType);
    var formulaKind = initial['formula_tipo']?.toString();
    formulaKind ??= _formulaTemplates.entries
        .where((entry) => entry.value == formula.text.trim())
        .map((entry) => entry.key)
        .firstOrNull;
    formulaKind ??= formula.text.trim().isEmpty ? 'SUMA' : 'PERSONALIZADA';
    var required = boolValue(initial['requerido']);
    var editable = boolValue(initial['editable'], fallback: true);
    var visible = boolValue(initial['visible'], fallback: true);
    var visibleTable = boolValue(initial['visible_tabla'], fallback: true);
    var applyConditionalToTable =
        boolValue(initial['aplicar_formato_condicional_tabla']);
    var activeField = boolValue(initial['activo'], fallback: true);
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(index == null ? 'Nuevo campo' : 'Editar campo'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dialogField(
                    label,
                    'Nombre de campo *',
                    helperText: 'Texto breve que verá la persona que registra.',
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: uiType,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de Campo *',
                      helperText:
                          'El tipo de dato de Supabase se asigna automáticamente.',
                      border: OutlineInputBorder(),
                    ),
                    items: <String, String>{
                      'text': 'Texto',
                      'multiline': 'Texto largo',
                      'number': 'Número decimal',
                      'integer': 'Número entero',
                      'date': 'Fecha',
                      'time': 'Hora',
                      'datetime': 'Fecha y hora',
                      'checkbox': 'Casilla de verificación',
                      'switch': 'Interruptor Sí / No',
                      'dropdown': 'Lista desplegable',
                      'multiselect': 'Selección múltiple',
                      'slider': 'Control deslizante',
                      'rating': 'Calificación por estrellas',
                      'formula': 'Fórmula',
                      'lookup': 'Consulta calculada',
                      'photo': 'Foto',
                      'signature': 'Firma',
                      'qr_scan': 'Lector de código QR',
                      'barcode_scan': 'Lector de código de barras',
                      'dni_scan': 'Lector de documento',
                      'email': 'Correo',
                      'phone': 'Teléfono',
                      'url': 'Enlace web',
                      'percent': 'Porcentaje',
                      'hidden_id': 'Identificador oculto',
                    }
                        .entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(() {
                      final previousUiType = uiType;
                      uiType = value ?? 'text';
                      if (uiType == 'formula' || uiType == 'lookup') {
                        // Al convertir un campo existente a fórmula, conservar
                        // su tipo lógico (por ejemplo number) como resultado.
                        dataType = _formulaResultType(dataType);
                      } else if (previousUiType == 'formula' ||
                          previousUiType == 'lookup') {
                        dataType = _dataTypeForUi(uiType);
                      } else {
                        dataType = _dataTypeForUi(uiType);
                      }
                      if (uiType == 'photo') photos = true;
                      if (uiType == 'signature') signature = true;
                      if (uiType == 'qr_scan') qr = true;
                      if (uiType == 'formula' || uiType == 'lookup') {
                        defaultValue.clear();
                      }
                    }),
                  ),
                  const SizedBox(height: 5),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Se guardará como: $dataType',
                      style: const TextStyle(
                        color: Color(0xFF60758A),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (uiType == 'formula' || uiType == 'lookup') ...[
                    DropdownButtonFormField<String>(
                      initialValue: _formulaResultType(dataType),
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Tipo del resultado *',
                        helperText:
                            'La fórmula puede devolver texto, números, fechas, horas u otros tipos.',
                        border: OutlineInputBorder(),
                      ),
                      items: _formulaResultTypes.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setDialogState(
                        () => dataType = _formulaResultType(value ?? 'text'),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _dialogField(
                    order,
                    'Orden *',
                    keyboardType: TextInputType.number,
                    helperText: 'Posición del campo dentro de esta tabla.',
                  ),
                  if (uiType != 'formula' && uiType != 'lookup')
                    _dialogField(
                      defaultValue,
                      'Valor predeterminado',
                      helperText: 'Valor inicial; puede dejarlo vacío.',
                    ),
                  if (uiType == 'formula' || uiType == 'lookup') ...[
                    DropdownButtonFormField<String>(
                      initialValue: formulaKind,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Fórmula a aplicar *',
                        helperText:
                            'Seleccione por nombre la operación que necesita.',
                        helperMaxLines: 1,
                        border: OutlineInputBorder(),
                      ),
                      items: _formulaNames.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setDialogState(() {
                        formulaKind = value ?? 'PERSONALIZADA';
                        final template = _formulaTemplates[formulaKind];
                        if (template != null) formula.text = template;
                      }),
                    ),
                    const SizedBox(height: 12),
                    if (formulaKind == 'LISTA') ...[
                      _dialogField(
                        formulaSourceTable,
                        'Tabla de origen *',
                        readOnly: true,
                        helperText:
                            'Tabla permitida que contiene las opciones.',
                        suffixIcon: IconButton(
                          tooltip: 'Buscar tabla y campo',
                          icon: const Icon(Icons.manage_search),
                          onPressed: () async {
                            final picked = await _pickBuilderFieldReference();
                            if (picked == null) return;
                            setDialogState(() {
                              formulaSourceTable.text =
                                  picked['tabla_destino']?.toString() ?? '';
                              formulaValueField.text =
                                  picked['campo']?.toString() ?? '';
                            });
                          },
                        ),
                      ),
                      _dialogField(
                        formulaValueField,
                        'Campo que devolverá valores únicos *',
                        readOnly: true,
                        suffixIcon: IconButton(
                          tooltip: 'Cambiar campo',
                          icon: const Icon(Icons.table_view_outlined),
                          onPressed: () async {
                            final picked = await _pickBuilderFieldReference(
                              preferredTable: formulaSourceTable.text,
                            );
                            if (picked == null) return;
                            setDialogState(() {
                              formulaSourceTable.text =
                                  picked['tabla_destino']?.toString() ?? '';
                              formulaValueField.text =
                                  picked['campo']?.toString() ?? '';
                            });
                          },
                        ),
                      ),
                      _dialogField(
                        formulaFilterField,
                        'Campo de condición (opcional)',
                        readOnly: true,
                        suffixIcon: IconButton(
                          tooltip: 'Elegir campo de condición',
                          icon: const Icon(Icons.filter_alt_outlined),
                          onPressed: () async {
                            final picked = await _pickBuilderFieldReference(
                              preferredTable: formulaSourceTable.text,
                            );
                            if (picked == null) return;
                            setDialogState(() {
                              formulaSourceTable.text =
                                  picked['tabla_destino']?.toString() ?? '';
                              formulaFilterField.text =
                                  picked['campo']?.toString() ?? '';
                            });
                          },
                        ),
                      ),
                      _dialogField(
                        formulaFilterValue,
                        'Valor o campo que debe cumplir',
                        helperText:
                            'Ej. ALBUS o [VARIEDAD]. Los corchetes usan el valor del formulario.',
                        suffixIcon: IconButton(
                          tooltip: 'Insertar campo del formulario',
                          icon: const Icon(Icons.data_object),
                          onPressed: () async {
                            final picked = await _pickBuilderFieldReference();
                            if (picked == null) return;
                            setDialogState(() {
                              formulaFilterValue.text = '[${picked['campo']}]';
                            });
                          },
                        ),
                      ),
                    ] else
                      _dialogField(
                        formula,
                        'Configuración de la fórmula *',
                        maxLines: 3,
                        helperText:
                            'La sintaxis está preparada: reemplace los campos de ejemplo.',
                        suffixIcon: IconButton(
                          tooltip: 'Insertar referencia de tabla/campo',
                          icon: const Icon(Icons.manage_search),
                          onPressed: () async {
                            final picked = await _pickBuilderFieldReference();
                            if (picked == null) return;
                            final reference = '[${picked['campo']}]';
                            setDialogState(() {
                              final selection = formula.selection;
                              final text = formula.text;
                              if (selection.isValid) {
                                formula.text = text.replaceRange(
                                  selection.start,
                                  selection.end,
                                  reference,
                                );
                              } else {
                                formula.text = '$text$reference';
                              }
                            });
                          },
                        ),
                      ),
                  ],
                  if (uiType == 'dropdown' || uiType == 'multiselect')
                    _dialogField(
                      dropdown,
                      'Tabla-campo de origen *',
                      readOnly: true,
                      helperText:
                          'La lista mostrará valores únicos del campo elegido.',
                      suffixIcon: IconButton(
                        tooltip: 'Buscar tabla y campo',
                        icon: const Icon(Icons.manage_search),
                        onPressed: () async {
                          final picked = await _pickBuilderFieldReference();
                          if (picked == null) return;
                          setDialogState(() {
                            dropdown.text =
                                '${picked['tabla_destino']}.${picked['campo']}';
                          });
                        },
                      ),
                    ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: required,
                    title: const Text('Obligatorio'),
                    subtitle:
                        const Text('Impide guardar el registro si está vacío.'),
                    onChanged: (value) =>
                        setDialogState(() => required = value == true),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: editable,
                    title: const Text('Editable'),
                    subtitle:
                        const Text('Permite que el usuario cambie el valor.'),
                    onChanged: (value) =>
                        setDialogState(() => editable = value == true),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: visible,
                    title: const Text('Visible en formulario'),
                    subtitle:
                        const Text('Muestra el campo durante la captura.'),
                    onChanged: (value) =>
                        setDialogState(() => visible = value == true),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: visibleTable,
                    title: const Text('Visible en tabla de registros'),
                    subtitle:
                        const Text('Muestra el campo en consultas y listados.'),
                    onChanged: (value) =>
                        setDialogState(() => visibleTable = value == true),
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.tune_outlined),
                    title: const Text(
                      'Opciones avanzadas',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      photos
                          ? 'Posición, validación, fotos, estilos y parámetros especiales'
                          : 'Posición, validación, estilos y parámetros especiales',
                    ),
                    children: [
                      if (uiType == 'hidden_id')
                        _dialogField(
                          idGenerator,
                          'Prefijo del identificador automático',
                          helperText:
                              'Es incremental: GT-GB-G genera GT-GB-G1, GT-GB-G2…',
                        ),
                      if (dataType == 'number')
                        _dialogField(
                          decimals,
                          'Número de decimales',
                          keyboardType: TextInputType.number,
                        ),
                      if (dataType == 'number' || dataType == 'integer')
                        _dialogField(
                          valueRange,
                          'Rango permitido',
                          helperText:
                              'Ejemplos: 0..100, >=0 o una regla compatible.',
                        ),
                      _dialogField(
                        maxCharacters,
                        'Máximo de caracteres',
                        keyboardType: TextInputType.number,
                      ),
                      _dialogField(
                        fontSize,
                        'Tamaño de letra del campo',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        helperText:
                            'Se aplica al formulario y, si lo activa, también a la tabla.',
                      ),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Posición en formulario-nuevo',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _dialogField(
                              gridRow,
                              'Fila',
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _dialogField(
                              gridColumn,
                              'Columna',
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Posición en formulario-flujo',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _dialogField(
                              pendingGridRow,
                              'Fila',
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _dialogField(
                              pendingGridColumn,
                              'Columna',
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      _dialogField(subtitle, 'Subtítulo antes del campo'),
                      _textStyleToolbar(
                        alignment: subtitleAlignment,
                        fontSize: subtitleFontSize,
                        color: subtitleColor,
                        padding: subtitlePadding,
                        setDialogState: setDialogState,
                      ),
                      if (uiType == 'photo') ...[
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Text(
                              'Fotos',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        _dialogField(
                          photoCount,
                          'Número de fotos',
                          keyboardType: TextInputType.number,
                          helperText:
                              'Al publicar se crean o reutilizan FOTO1, FOTO2… hasta completar esta cantidad.',
                        ),
                        _dialogField(captureGroup, 'Grupo de captura'),
                        _dialogField(
                          photoDepends,
                          'Campos de los que depende la foto',
                        ),
                        _dialogField(photoList, 'Lista o grupo de destino'),
                        _dialogField(
                          photoOrder,
                          'Orden dentro de la lista de fotos',
                          keyboardType: TextInputType.number,
                        ),
                      ],
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Formato de valores',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      _conditionalColorField(
                        textColor,
                        textColorCondition,
                        'Color del texto',
                        setDialogState: setDialogState,
                        currentField: physical.text.trim().isEmpty
                            ? _generatedPhysicalFieldName(label.text)
                            : physical.text.trim(),
                      ),
                      _conditionalColorField(
                        backgroundColor,
                        backgroundColorCondition,
                        'Color del fondo',
                        setDialogState: setDialogState,
                        currentField: physical.text.trim().isEmpty
                            ? _generatedPhysicalFieldName(label.text)
                            : physical.text.trim(),
                      ),
                      _conditionalColorField(
                        borderColor,
                        borderColorCondition,
                        'Color del borde',
                        setDialogState: setDialogState,
                        currentField: physical.text.trim().isEmpty
                            ? _generatedPhysicalFieldName(label.text)
                            : physical.text.trim(),
                      ),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Encabezados especiales',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      _dialogField(title1, 'Título 1'),
                      _textStyleToolbar(
                        alignment: title1Alignment,
                        fontSize: title1FontSize,
                        color: title1Color,
                        padding: title1Padding,
                        setDialogState: setDialogState,
                      ),
                      _dialogField(code1, 'Código 1'),
                      _dialogField(title2, 'Título 2'),
                      _textStyleToolbar(
                        alignment: title2Alignment,
                        fontSize: title2FontSize,
                        color: title2Color,
                        padding: title2Padding,
                        setDialogState: setDialogState,
                      ),
                      _dialogField(code2, 'Código 2'),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: applyConditionalToTable,
                        title: const Text(
                            'Aplicar también en la tabla de registros'),
                        subtitle: const Text(
                          'Replica posiciones, tamaño y formato de valores en todos los listados permitidos.',
                        ),
                        onChanged: (value) => setDialogState(
                            () => applyConditionalToTable = value == true),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: activeField,
                        title: const Text('Campo activo'),
                        subtitle: const Text(
                            'Puede desactivarse sin borrar la definición.'),
                        onChanged: (value) =>
                            setDialogState(() => activeField = value == true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final visibleName = label.text.trim();
                final existingCode = code.text.trim();
                final existingPhysical = physical.text.trim();
                if (uiType != 'formula' && uiType != 'lookup') {
                  dataType = _dataTypeForUi(uiType);
                } else {
                  dataType = _formulaResultType(dataType);
                }
                if (formulaKind == 'LISTA') {
                  final source = formulaSourceTable.text.trim();
                  final valueField = formulaValueField.text.trim();
                  final filterField = formulaFilterField.text.trim();
                  final rawFilterValue = formulaFilterValue.text.trim();
                  final filterValue = rawFilterValue.startsWith('[') ||
                          rawFilterValue.startsWith('{{') ||
                          rawFilterValue.startsWith('"') ||
                          rawFilterValue.startsWith("'")
                      ? rawFilterValue
                      : '"${rawFilterValue.replaceAll('"', '\\"')}"';
                  formula.text = filterField.isEmpty
                      ? 'LISTA("$source"; "$valueField")'
                      : 'LISTA("$source"; "$valueField"; "$filterField"; $filterValue)';
                }
                Navigator.pop(dialogContext, {
                  ...initial,
                  'nombre': visibleName,
                  'etiqueta': visibleName,
                  'codigo': existingCode.isEmpty
                      ? _generatedFieldCode(
                          tables[tableIndex]['codigo']?.toString() ??
                              _generatedTableCode(
                                tables[tableIndex]['nombre']?.toString() ??
                                    'tabla',
                              ),
                          visibleName,
                        )
                      : existingCode,
                  'campo': existingPhysical.isEmpty
                      ? _generatedPhysicalFieldName(visibleName)
                      : existingPhysical,
                  'tipo': dataType,
                  'tipo_ui': uiType,
                  'formula_tipo': formulaKind,
                  'orden': int.tryParse(order.text.trim()) ?? order.text.trim(),
                  'valor_default': uiType == 'formula' || uiType == 'lookup'
                      ? ''
                      : defaultValue.text.trim(),
                  'formula_funcion': formula.text.trim(),
                  'formula_tabla_origen': formulaSourceTable.text.trim(),
                  'formula_campo_valor': formulaValueField.text.trim(),
                  'formula_campo_condicion': formulaFilterField.text.trim(),
                  'formula_valor_condicion': formulaFilterValue.text.trim(),
                  'id_campo_dropdown': dropdown.text.trim(),
                  'requerido': required,
                  'editable': editable,
                  'visible': visible,
                  'visible_tabla': visibleTable,
                  'id_generador': idGenerator.text.trim(),
                  'numero_decimales': decimals.text.trim(),
                  'grid_fila': gridRow.text.trim(),
                  'grid_columna': gridColumn.text.trim(),
                  'grid_fila_pendientes': pendingGridRow.text.trim(),
                  'grid_columna_pendientes': pendingGridColumn.text.trim(),
                  'rango_valor': valueRange.text.trim(),
                  'num_caracteres': maxCharacters.text.trim(),
                  'numero_fotos':
                      uiType == 'photo' ? photoCount.text.trim() : '',
                  'photo_depende_de':
                      uiType == 'photo' ? photoDepends.text.trim() : '',
                  'lista_destino_photo':
                      uiType == 'photo' ? photoList.text.trim() : '',
                  'orden_lista_photo':
                      uiType == 'photo' ? photoOrder.text.trim() : '',
                  'formato_condicional_campo': '',
                  'condicion_color_texto': textColorCondition.text.trim(),
                  'condicion_color_fondo': backgroundColorCondition.text.trim(),
                  'condicion_color_borde': borderColorCondition.text.trim(),
                  'color_texto': textColor.text.trim(),
                  'color_fondo': backgroundColor.text.trim(),
                  'color_borde': borderColor.text.trim(),
                  'tamanio_letra': fontSize.text.trim(),
                  'aplicar_formato_condicional_tabla': applyConditionalToTable,
                  'sub_titulo': subtitle.text.trim(),
                  'fila_sub_titulo': '',
                  'subtitulo_alineacion': subtitleAlignment.text.trim(),
                  'subtitulo_tamanio_letra': subtitleFontSize.text.trim(),
                  'subtitulo_color': subtitleColor.text.trim(),
                  'subtitulo_padding': subtitlePadding.text.trim(),
                  'grupo_captura':
                      uiType == 'photo' ? captureGroup.text.trim() : '',
                  'titulo1': title1.text.trim(),
                  'titulo2': title2.text.trim(),
                  'codigo1': code1.text.trim(),
                  'codigo2': code2.text.trim(),
                  'titulo1_alineacion': title1Alignment.text.trim(),
                  'titulo1_tamanio_letra': title1FontSize.text.trim(),
                  'titulo1_color': title1Color.text.trim(),
                  'titulo1_padding': title1Padding.text.trim(),
                  'titulo2_alineacion': title2Alignment.text.trim(),
                  'titulo2_tamanio_letra': title2FontSize.text.trim(),
                  'titulo2_color': title2Color.text.trim(),
                  'titulo2_padding': title2Padding.text.trim(),
                  'activo': activeField,
                  'matrices': _maps(initial['matrices']),
                });
              },
              child: const Text('Guardar campo'),
            ),
          ],
        ),
      ),
    );
    label.dispose();
    code.dispose();
    physical.dispose();
    order.dispose();
    defaultValue.dispose();
    formula.dispose();
    dropdown.dispose();
    idGenerator.dispose();
    decimals.dispose();
    gridRow.dispose();
    gridColumn.dispose();
    pendingGridRow.dispose();
    pendingGridColumn.dispose();
    valueRange.dispose();
    maxCharacters.dispose();
    photoCount.dispose();
    photoDepends.dispose();
    photoList.dispose();
    photoOrder.dispose();
    conditionalFormat.dispose();
    textColorCondition.dispose();
    backgroundColorCondition.dispose();
    borderColorCondition.dispose();
    textColor.dispose();
    backgroundColor.dispose();
    borderColor.dispose();
    fontSize.dispose();
    subtitle.dispose();
    subtitleAlignment.dispose();
    subtitleFontSize.dispose();
    subtitleColor.dispose();
    subtitlePadding.dispose();
    captureGroup.dispose();
    title1.dispose();
    title2.dispose();
    code1.dispose();
    code2.dispose();
    title1Alignment.dispose();
    title1FontSize.dispose();
    title1Color.dispose();
    title1Padding.dispose();
    title2Alignment.dispose();
    title2FontSize.dispose();
    title2Color.dispose();
    title2Padding.dispose();
    formulaSourceTable.dispose();
    formulaValueField.dispose();
    formulaFilterField.dispose();
    formulaFilterValue.dispose();
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        fields.add(result);
      } else {
        fields[index] = result;
      }
      tables[tableIndex]['campos'] = fields;
      validation = null;
    });
  }

  Future<void> _editMatrix(
    int tableIndex,
    int fieldIndex, {
    int? index,
  }) async {
    final fields = _maps(tables[tableIndex]['campos']);
    final matrices = _maps(fields[fieldIndex]['matrices']);
    final initial = index == null ? <String, dynamic>{} : matrices[index];
    final name = TextEditingController(text: initial['nombre']?.toString());
    final code = TextEditingController(text: initial['codigo']?.toString());
    final expression =
        TextEditingController(text: initial['expresion']?.toString());
    final sourceTable =
        TextEditingController(text: initial['tabla_origen']?.toString());
    final valueField =
        TextEditingController(text: initial['campo_valor']?.toString());
    final labelField =
        TextEditingController(text: initial['campo_etiqueta']?.toString());
    var matrixClass = initial['clase_matriz']?.toString() ?? 'DROPDOWN';
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(index == null ? 'Nueva matriz' : 'Editar matriz'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dialogField(
                    name,
                    'Nombre de la regla *',
                    helperText:
                        'Nombre con el que se identificará esta configuración.',
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: matrixClass,
                    decoration: const InputDecoration(
                      labelText: 'Clase de matriz *',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'DROPDOWN', child: Text('Dropdown')),
                      DropdownMenuItem(
                          value: 'VALIDACION', child: Text('Validación')),
                      DropdownMenuItem(
                          value: 'CONDICION', child: Text('Condición')),
                      DropdownMenuItem(
                          value: 'FORMULA', child: Text('Fórmula')),
                    ],
                    onChanged: (value) => setDialogState(
                      () => matrixClass = value ?? 'DROPDOWN',
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (matrixClass == 'DROPDOWN') ...[
                    _dialogField(sourceTable, 'Tabla origen'),
                    _dialogField(valueField, 'Campo valor'),
                    _dialogField(labelField, 'Campo etiqueta'),
                  ],
                  if (matrixClass != 'DROPDOWN')
                    _dialogField(
                      expression,
                      matrixClass == 'FORMULA'
                          ? 'Expresión de fórmula *'
                          : 'Expresión o regla',
                      maxLines: 4,
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final visibleName = name.text.trim();
                final existingCode = code.text.trim();
                Navigator.pop(dialogContext, {
                  ...initial,
                  'nombre': visibleName,
                  'codigo': existingCode.isEmpty
                      ? '${_generatedFieldCode(
                          fields[fieldIndex]['codigo']?.toString() ?? 'campo',
                          visibleName,
                        )}_regla'
                      : existingCode,
                  'clase_matriz': matrixClass,
                  'expresion': expression.text.trim(),
                  'tabla_origen': sourceTable.text.trim(),
                  'campo_valor': valueField.text.trim(),
                  'campo_etiqueta': labelField.text.trim(),
                  'activo': initial['activo'] != false,
                });
              },
              child: const Text('Guardar matriz'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    code.dispose();
    expression.dispose();
    sourceTable.dispose();
    valueField.dispose();
    labelField.dispose();
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        matrices.add(result);
      } else {
        matrices[index] = result;
      }
      fields[fieldIndex]['matrices'] = matrices;
      tables[tableIndex]['campos'] = fields;
      validation = null;
    });
  }

  Widget _dialogField(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    int maxLines = 1,
    String? helperText,
    Widget? suffixIcon,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        readOnly: readOnly,
        onTap: onTap,
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText ?? _defaultDialogHelper(label),
          helperMaxLines: 1,
          border: const OutlineInputBorder(),
          suffixIcon: suffixIcon,
        ),
      ),
    );
  }

  String _defaultDialogHelper(String label) {
    final value = label.toLowerCase();
    if (value.contains('decimales')) {
      return 'Cantidad de decimales que se mostrarán.';
    }
    if (value.contains('rango')) {
      return 'Límite mínimo y máximo permitido.';
    }
    if (value.contains('caracteres')) {
      return 'Longitud máxima aceptada.';
    }
    if (value.contains('fila')) {
      return 'Número de fila donde se ubicará.';
    }
    if (value.contains('columna')) {
      return 'Número de columna donde se ubicará.';
    }
    if (value.contains('foto')) {
      return 'Regla aplicada a la captura de evidencias.';
    }
    if (value.contains('subtítulo')) {
      return 'Texto que agrupa o explica los campos siguientes.';
    }
    if (value.contains('grupo')) {
      return 'Nombre del grupo al que pertenece el campo.';
    }
    if (value.contains('condición')) {
      return 'Regla que activa el estilo configurado.';
    }
    if (value.contains('título')) {
      return 'Texto breve para el encabezado.';
    }
    if (value.contains('código')) {
      return 'Referencia interna generada o relacionada.';
    }
    return 'Complete este valor solo cuando la configuración lo requiera.';
  }

  Widget _colorField(
    TextEditingController controller,
    String label, {
    required VoidCallback onPalette,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          helperText:
              'Coloca hexadecimal o rgb, por ejemplo #176B87 o rgb(23, 107, 135).',
          helperMaxLines: 1,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: 'Abrir paleta de colores',
            onPressed: onPalette,
            icon: const Icon(Icons.palette_outlined),
          ),
        ),
      ),
    );
  }

  Widget _conditionalColorField(
    TextEditingController colorController,
    TextEditingController conditionController,
    String label, {
    required StateSetter setDialogState,
    required String currentField,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: colorController,
        decoration: InputDecoration(
          labelText: label,
          helperText: conditionController.text.trim().isEmpty
              ? 'Se aplica siempre. Use fx para agregar una condición.'
              : 'Condición: ${conditionController.text.trim()}',
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Configurar condición',
                onPressed: () async {
                  await _configureValueFormatCondition(
                    conditionController,
                    currentField: currentField,
                  );
                  setDialogState(() {});
                },
                icon: const Icon(Icons.functions),
              ),
              IconButton(
                tooltip: 'Abrir paleta de colores',
                onPressed: () async {
                  final value = await _pickColorValue();
                  if (value != null) {
                    setDialogState(() => colorController.text = value);
                  }
                },
                icon: const Icon(Icons.palette_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _configureValueFormatCondition(
    TextEditingController target, {
    required String currentField,
  }) async {
    final value = TextEditingController();
    final secondValue = TextEditingController();
    final formula = TextEditingController(text: target.text);
    var operator = target.text.trim().isEmpty ? 'always' : 'formula';
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Condición del formato de valores'),
          content: SizedBox(
            width: 540,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: operator,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Aplicar este color cuando',
                    border: OutlineInputBorder(),
                  ),
                  items: const {
                    'always': 'Siempre (sin condición)',
                    '>': 'Es mayor que',
                    '<': 'Es menor que',
                    '=': 'Es igual a',
                    '!=': 'Es diferente de',
                    '>=': 'Es mayor o igual que',
                    '<=': 'Es menor o igual que',
                    'between': 'Está entre',
                    'contains': 'Contiene el texto',
                    'empty': 'Está vacío',
                    'not_empty': 'No está vacío',
                    'formula': 'Usar fórmula o condición personalizada',
                  }
                      .entries
                      .map((entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ))
                      .toList(),
                  onChanged: (next) =>
                      setLocalState(() => operator = next ?? 'always'),
                ),
                const SizedBox(height: 12),
                if (!const {
                  'always',
                  'formula',
                  'empty',
                  'not_empty',
                }.contains(operator))
                  _dialogField(
                    value,
                    'Valor o campo de comparación',
                    helperText:
                        'Escriba un valor o elija otro campo para compararlos.',
                    suffixIcon: IconButton(
                      tooltip: 'Elegir campo',
                      icon: const Icon(Icons.manage_search),
                      onPressed: () async {
                        final picked = await _pickBuilderFieldReference();
                        if (picked == null) return;
                        setLocalState(
                            () => value.text = '[${picked['campo']}]');
                      },
                    ),
                  ),
                if (operator == 'between')
                  _dialogField(
                    secondValue,
                    'Segundo límite',
                    helperText: 'Límite superior del intervalo.',
                    suffixIcon: IconButton(
                      tooltip: 'Elegir campo',
                      icon: const Icon(Icons.manage_search),
                      onPressed: () async {
                        final picked = await _pickBuilderFieldReference();
                        if (picked == null) return;
                        setLocalState(
                            () => secondValue.text = '[${picked['campo']}]');
                      },
                    ),
                  ),
                if (operator == 'formula')
                  _dialogField(
                    formula,
                    'Fórmula o condición',
                    maxLines: 3,
                    helperText:
                        'Ej. [CAMPO1] < [CAMPO2] o SI([VALOR] > 10; true; false).',
                    suffixIcon: IconButton(
                      tooltip: 'Insertar campo',
                      icon: const Icon(Icons.manage_search),
                      onPressed: () async {
                        final picked = await _pickBuilderFieldReference();
                        if (picked == null) return;
                        setLocalState(() {
                          formula.text = '${formula.text}[${picked['campo']}]';
                        });
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final field = currentField.trim().isEmpty
                    ? 'CAMPO_ACTUAL'
                    : currentField.trim();
                final first = value.text.trim();
                final second = secondValue.text.trim();
                final expression = switch (operator) {
                  'always' => '',
                  'empty' => 'ESVACIO([$field])',
                  'not_empty' => 'NOESVACIO([$field])',
                  'contains' => 'CONTIENE([$field]; "$first")',
                  'between' => '([$field] >= $first) Y ([$field] <= $second)',
                  'formula' => formula.text.trim(),
                  _ => '[$field] $operator $first',
                };
                Navigator.pop(dialogContext, expression);
              },
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
    value.dispose();
    secondValue.dispose();
    formula.dispose();
    if (result != null) target.text = result;
  }

  Widget _textStyleToolbar({
    required TextEditingController alignment,
    required TextEditingController fontSize,
    required TextEditingController color,
    required TextEditingController padding,
    required StateSetter setDialogState,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          PopupMenuButton<String>(
            tooltip: 'Alineación',
            icon: Icon(
              alignment.text == 'center'
                  ? Icons.format_align_center
                  : alignment.text == 'right'
                      ? Icons.format_align_right
                      : Icons.format_align_left,
            ),
            onSelected: (value) => setDialogState(() => alignment.text = value),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'left', child: Text('Izquierda')),
              PopupMenuItem(value: 'center', child: Text('Centro')),
              PopupMenuItem(value: 'right', child: Text('Derecha')),
            ],
          ),
          IconButton(
            tooltip: 'Tamaño de letra',
            onPressed: () async {
              final selected = await _pickNumericSetting(
                title: 'Tamaño de letra',
                initialValue: fontSize.text,
                hint: 'Ej. 14',
              );
              if (selected != null) {
                setDialogState(() => fontSize.text = selected);
              }
            },
            icon: const Icon(Icons.format_size),
          ),
          IconButton(
            tooltip: 'Color de letra',
            onPressed: () async {
              final selected = await _pickColorValue();
              if (selected != null) {
                setDialogState(() => color.text = selected);
              }
            },
            icon: const Icon(Icons.palette_outlined),
          ),
          IconButton(
            tooltip: 'Padding',
            onPressed: () async {
              final selected = await _pickNumericSetting(
                title: 'Padding',
                initialValue: padding.text,
                hint: 'izquierda,arriba,derecha,abajo',
              );
              if (selected != null) {
                setDialogState(() => padding.text = selected);
              }
            },
            icon: const Icon(Icons.padding_outlined),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${alignment.text} · ${fontSize.text.isEmpty ? 'tamaño normal' : '${fontSize.text}px'} · ${color.text.isEmpty ? 'color normal' : color.text}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF60758A), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _pickNumericSetting({
    required String title,
    required String initialValue,
    required String hint,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<String?> _pickColorValue() {
    const colors = <String>[
      '#000000',
      '#FFFFFF',
      '#17324D',
      '#0F5265',
      '#176B87',
      '#0C7A5B',
      '#31552F',
      '#60758A',
      '#B06B20',
      '#B33B32',
      '#7A211B',
      '#6F42C1',
      '#D9EAF0',
      '#E8F6F1',
      '#FFF1F0',
      '#F4F8F7',
      '#FFC107',
      '#FF9800',
      '#4CAF50',
      '#2196F3',
    ];
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Elegir color'),
        content: SizedBox(
          width: 360,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: colors.map((value) {
              final color =
                  Color(int.parse('FF${value.substring(1)}', radix: 16));
              return Tooltip(
                message: value,
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => Navigator.pop(dialogContext, value),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFB8C5CC)),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Widget _reviewStep() {
    final errors = validation?['errores'] is List
        ? List<dynamic>.from(validation!['errores'] as List)
        : const <dynamic>[];
    final warnings = validation?['advertencias'] is List
        ? List<dynamic>.from(validation!['advertencias'] as List)
        : const <dynamic>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nameController.text.trim().isEmpty
                      ? 'Formato sin nombre'
                      : nameController.text.trim(),
                  style: const TextStyle(
                    color: Color(0xFF17324D),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Divider(height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.grid_view_outlined),
                  title: const Text('Pertenece al módulo'),
                  subtitle: Text(_selectedModuleName()),
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tablas',
                    style: TextStyle(
                      color: Color(0xFF17324D),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                for (final table in tables)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.table_chart_outlined),
                    title: Text(table['nombre']?.toString() ?? 'Tabla'),
                    subtitle: Text(
                      '${_maps(table['campos']).length} campo(s)',
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (validation != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color:
                  isValid ? const Color(0xFFE8F6F1) : const Color(0xFFFFF1F0),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color:
                    isValid ? const Color(0xFF79BEA4) : const Color(0xFFE8A39D),
              ),
            ),
            child: Text(
              isValid
                  ? 'La estructura completa es válida y está lista para publicar.'
                  : 'Corrija ${errors.length} error(es) antes de publicar.',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          for (final item in errors) _validationItem(item, Colors.red.shade700),
          for (final item in warnings)
            _validationItem(item, Colors.orange.shade800),
        ],
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!, style: const TextStyle(color: Colors.red)),
        ],
        if (isValid && !canPublish) ...[
          const SizedBox(height: 12),
          const Text(
            'La estructura está validada. Un administrador debe publicarla.',
            style: TextStyle(color: Color(0xFF60758A)),
          ),
        ],
      ],
    );
  }

  Widget _validationItem(dynamic item, Color color) {
    final data = _map(item);
    final field = data['campo']?.toString() ?? '';
    final suggestions = data['sugerencias'] is List
        ? List<dynamic>.from(data['sugerencias'] as List)
            .map((value) => value.toString())
            .toList()
        : const <String>[];
    return ListTile(
      dense: true,
      leading: Icon(Icons.circle, size: 8, color: color),
      title: Text(data['mensaje']?.toString() ?? '$item'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (field.isNotEmpty) const Text('Toque aquí para corregirlo.'),
          if (suggestions.isNotEmpty)
            Text('Sugerencias: ${suggestions.join(' · ')}'),
        ],
      ),
      trailing: field.isEmpty ? null : const Icon(Icons.edit_outlined),
      onTap: field.isEmpty ? null : () => _goToValidationField(field),
    );
  }

  List<String> _suggestionsForPath(String path) {
    final rawErrors = validation?['errores'];
    if (rawErrors is! List) return const [];
    final suggestions = <String>{};
    var conflict = false;
    for (final raw in rawErrors) {
      final data = _map(raw);
      final field = data['campo']?.toString() ?? '';
      if (field != path && !field.startsWith('$path.')) continue;
      conflict = conflict ||
          (data['mensaje']?.toString().toLowerCase().contains('ya existe') ??
              false);
      if (data['sugerencias'] is List) {
        suggestions.addAll(
          List<dynamic>.from(data['sugerencias'] as List)
              .map((value) => value.toString()),
        );
      }
    }
    if (suggestions.isEmpty && conflict) {
      final base = path.startsWith('tablas[')
          ? (() {
              final match = RegExp(r'tablas\[(\d+)\]').firstMatch(path);
              final index = int.tryParse(match?.group(1) ?? '');
              return index != null && index < tables.length
                  ? tables[index]['nombre']?.toString() ?? 'Tabla'
                  : 'Tabla';
            })()
          : nameController.text.trim();
      suggestions
          .addAll(['$base 2', '$base nuevo', '$base ${DateTime.now().year}']);
    }
    return suggestions.toList();
  }

  Widget _suggestionChoices(
    TextEditingController controller,
    List<String> suggestions,
    VoidCallback onSelected,
  ) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pruebe uno de estos nombres:',
            style: TextStyle(color: Color(0xFF60758A), fontSize: 12),
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: suggestions
                .map(
                  (value) => ActionChip(
                    label: Text(value),
                    onPressed: () {
                      controller.text = value;
                      onSelected();
                    },
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  void _goToValidationField(String field) {
    final tableMatch = RegExp(r'tablas\[(\d+)\]').firstMatch(field);
    final fieldMatch = RegExp(r'campos\[(\d+)\]').firstMatch(field);
    if (tableMatch == null) {
      setState(() => currentStep = field == 'modulo_id' ? 1 : 1);
      return;
    }
    final tableIndex = int.tryParse(tableMatch.group(1) ?? '');
    final fieldIndex = int.tryParse(fieldMatch?.group(1) ?? '');
    if (tableIndex == null || tableIndex >= tables.length) return;
    setState(() => currentStep = 3);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (fieldIndex != null &&
          fieldIndex < _maps(tables[tableIndex]['campos']).length) {
        _editField(tableIndex, index: fieldIndex);
      } else {
        _editTable(index: tableIndex);
      }
    });
  }

  Widget _textQuestion(
    String title,
    String reason,
    TextEditingController controller, {
    required String label,
    String? hint,
    Widget? suffix,
    TextInputType? keyboardType,
    int minLines = 1,
    int maxLines = 1,
    bool readOnly = false,
    ValueChanged<String>? onChanged,
  }) {
    return _question(
      title,
      reason,
      TextField(
        controller: controller,
        keyboardType: keyboardType,
        minLines: minLines,
        maxLines: maxLines,
        readOnly: readOnly,
        onChanged: onChanged ?? (_) => validation = null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          suffixIcon: suffix,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _question(String title, String reason, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF17324D),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          reason,
          style: const TextStyle(color: Color(0xFF60758A), fontSize: 12),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}
