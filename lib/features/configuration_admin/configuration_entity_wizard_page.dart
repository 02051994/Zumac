import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../../core/services/app_experience_service.dart';
import '../../core/widgets/configuration_icon_catalog.dart';
import 'configuration_admin_repository.dart';
import 'configuration_entity_spec.dart';

class ConfigurationEntityWizardPage extends StatefulWidget {
  final String entityType;
  final Map<String, dynamic> contextData;
  final Map<String, dynamic>? initialDraft;
  final String? initialRubroId;
  final ConfigurationAdminRepository? repository;

  const ConfigurationEntityWizardPage({
    super.key,
    required this.entityType,
    required this.contextData,
    this.initialDraft,
    this.initialRubroId,
    this.repository,
  });

  @override
  State<ConfigurationEntityWizardPage> createState() =>
      _ConfigurationEntityWizardPageState();
}

class _ConfigurationEntityWizardPageState
    extends State<ConfigurationEntityWizardPage> {
  late final ConfigurationAdminRepository repository;
  late final ConfigurationEntitySpec spec;
  final experience = AppExperienceService();

  final nameController = TextEditingController();
  final codeController = TextEditingController();
  final descriptionController = TextEditingController();
  final orderController = TextEditingController(text: '0');
  final routeController = TextEditingController();
  final colorController = TextEditingController();

  int currentStep = 0;
  bool loading = true;
  bool saving = false;
  bool active = true;
  bool iconPickerExpanded = false;
  String? error;
  String? selectedTemplateId;
  String? selectedRubroId;
  String? selectedSectionId;
  String selectedIcon = 'apps';
  String selectedContentType = 'FORMATOS';
  String? draftId;
  String? publishedTargetId;
  int? lockVersion;
  Map<String, dynamic>? validation;
  List<Map<String, dynamic>> templates = [];
  List<Map<String, dynamic>> sectionTemplates = [];
  Timer? autosaveTimer;
  DateTime? lastAutosaveAt;
  String? lastAutosaveFingerprint;
  bool restoredAutosave = false;

  bool get isRubro => spec.type == 'RUBRO';
  bool get isSection => spec.type == 'SECCION';
  bool get isModule => spec.type == 'MODULO';
  bool get canPublish => widget.contextData['puede_publicar'] == true;
  bool get isValid => validation?['valido'] == true;
  bool get editingPublished => publishedTargetId != null;

  List<Map<String, dynamic>> get rubros {
    final raw = widget.contextData['rubros'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    repository = widget.repository ?? ConfigurationAdminRepository();
    spec = ConfigurationEntitySpec.forType(widget.entityType);
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
    routeController.dispose();
    colorController.dispose();
    super.dispose();
  }

  String get _autosaveKey {
    final contextKey = widget.initialDraft?['id']?.toString() ??
        widget.initialRubroId ??
        'nuevo';
    return 'entidad_${spec.type}_$contextKey';
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
    if (loading || saving) return;
    final savedAt = DateTime.now();
    final value = <String, dynamic>{
      'payload': _payload(),
      'selected_template_id': selectedTemplateId,
      'current_step': currentStep,
      'saved_at': savedAt.toIso8601String(),
    };
    final fingerprint = jsonEncode(value..remove('saved_at'));
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
    final definition = draft['definicion'] is Map
        ? Map<String, dynamic>.from(draft['definicion'] as Map)
        : <String, dynamic>{};
    draftId = draft['id']?.toString();
    publishedTargetId = definition['_modo_edicion'] == 'NUEVA_VERSION'
        ? definition['_entidad_objetivo_id']?.toString()
        : null;
    lockVersion = int.tryParse('${draft['lock_version'] ?? ''}');
    selectedTemplateId = draft['plantilla_origen_id']?.toString();
    nameController.text = draft['nombre']?.toString() ?? '';
    codeController.text = draft['codigo']?.toString() ?? '';
    descriptionController.text = definition['descripcion']?.toString() ?? '';
    orderController.text = definition['orden']?.toString() ?? '0';
    routeController.text = definition['ruta_flutter']?.toString() ?? '';
    colorController.text = definition['color']?.toString() ?? '';
    selectedRubroId =
        definition['rubro_id']?.toString() ?? draft['rubro_id']?.toString();
    selectedSectionId =
        (definition['seccion_id'] ?? definition['seccion'])?.toString();
    selectedIcon = definition['icono']?.toString() ?? 'apps';
    selectedContentType =
        definition['tipo_contenido']?.toString() ?? 'FORMATOS';
    active = definition['activo'] != false;
    if (draft['_requested_action'] == 'DEACTIVATE' ||
        draft['_requested_action'] == 'ACTIVATE') {
      currentStep = 4;
    }
    validation = draft['validacion'] is Map
        ? Map<String, dynamic>.from(draft['validacion'] as Map)
        : null;
  }

  Future<void> _loadOptions() async {
    try {
      final results = await Future.wait([
        repository.listTemplates(entityType: spec.type, limit: 150),
        if (isModule)
          repository.listTemplates(entityType: 'SECCION', limit: 150),
      ]);
      if (!mounted) return;
      setState(() {
        templates = _items(results.first);
        if (isModule) sectionTemplates = _items(results.last);
        if (!isRubro) {
          selectedRubroId ??=
              rubros.isEmpty ? null : rubros.first['id']?.toString();
        }
        if (isModule &&
            !_availableSectionTemplates.any(
              (row) =>
                  row['entidad_origen_id']?.toString() == selectedSectionId,
            )) {
          selectedSectionId = _availableSectionTemplates.isEmpty
              ? null
              : _availableSectionTemplates.first['entidad_origen_id']
                  ?.toString();
        }
        _suggestNextOrder();
        loading = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        error = 'No se pudieron cargar las opciones: $exception';
        loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _items(Map<String, dynamic> result) {
    final raw = result['items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  List<Map<String, dynamic>> get _availableSectionTemplates {
    if (!isModule || selectedRubroId == null) return sectionTemplates;
    return sectionTemplates.where((row) {
      final definition = _definition(row);
      return (row['rubro_id'] ?? definition['rubro_id'])?.toString() ==
          selectedRubroId;
    }).toList(growable: false);
  }

  List<Map<String, dynamic>> get _availableTemplates {
    if (isRubro || selectedRubroId == null) return templates;
    return templates.where((row) {
      final definition = _definition(row);
      return (row['rubro_id'] ?? definition['rubro_id'])?.toString() ==
          selectedRubroId;
    }).toList(growable: false);
  }

  void _selectTemplate(String? templateId) {
    setState(() {
      final hadTemplate = selectedTemplateId != null;
      selectedTemplateId = templateId;
      validation = null;
      if (templateId == null) {
        if (hadTemplate && !editingPublished) {
          nameController.clear();
          codeController.text = generatedEntityCode(spec.type, '');
          descriptionController.clear();
          orderController.text = '0';
          routeController.clear();
          colorController.clear();
          selectedIcon = 'apps';
          selectedContentType = 'FORMATOS';
          active = true;
          _suggestNextOrder(force: true);
        }
        return;
      }
      final template = templates.cast<Map<String, dynamic>?>().firstWhere(
            (row) => row?['id']?.toString() == templateId,
            orElse: () => null,
          );
      if (template == null) return;
      final definition = template['definicion'] is Map
          ? Map<String, dynamic>.from(template['definicion'] as Map)
          : <String, dynamic>{};
      nameController.text = 'Copia de ${template['nombre'] ?? ''}'.trim();
      codeController.text = generatedEntityCode(spec.type, nameController.text);
      descriptionController.text = definition['descripcion']?.toString() ?? '';
      orderController.text = definition['orden']?.toString() ?? '0';
      routeController.text = definition['ruta_flutter']?.toString() ?? '';
      colorController.text = definition['color']?.toString() ?? '';
      selectedRubroId = definition['rubro_id']?.toString() ??
          template['rubro_id']?.toString() ??
          selectedRubroId;
      selectedSectionId =
          (definition['seccion_id'] ?? definition['seccion'])?.toString();
      selectedIcon = definition['icono']?.toString() ?? selectedIcon;
      selectedContentType =
          definition['tipo_contenido']?.toString() ?? selectedContentType;
      active = definition['activo'] != false;
      _suggestNextOrder(force: true);
    });
  }

  Map<String, dynamic> _payload() {
    if (!editingPublished) {
      codeController.text = generatedEntityCode(spec.type, nameController.text);
    }
    final payload = <String, dynamic>{
      'codigo': codeController.text.trim(),
      'nombre': nameController.text.trim(),
      'descripcion': descriptionController.text.trim(),
      'icono': selectedIcon,
      'color': colorController.text.trim(),
      'orden': int.tryParse(orderController.text.trim()) ??
          orderController.text.trim(),
      'activo': active,
    };
    if (editingPublished) {
      payload.addAll({
        '_modo_edicion': 'NUEVA_VERSION',
        '_entidad_objetivo_id': publishedTargetId,
      });
    }
    if (isRubro) {
      // El código del rubro se convierte en su identificador técnico.
    } else if (isSection) {
      payload.addAll({
        'rubro_id': selectedRubroId,
        'tipo_contenido': selectedContentType,
        'ruta_flutter': routeController.text.trim(),
      });
    } else {
      final section = sectionTemplates.cast<Map<String, dynamic>?>().firstWhere(
            (row) => row?['entidad_origen_id']?.toString() == selectedSectionId,
            orElse: () => null,
          );
      payload.addAll({
        'seccion_id': selectedSectionId,
        'rubro_id': section?['rubro_id']?.toString() ?? selectedRubroId,
      });
    }
    return payload;
  }

  Future<void> _saveAndValidate() async {
    final payload = _payload();
    final localErrors = validateSectionOrModulePayload(spec.type, payload);
    if (localErrors.isNotEmpty) {
      setState(() {
        validation = {
          'valido': false,
          'errores': localErrors
              .map((message) => {'campo': 'formulario', 'mensaje': message})
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
      final draft = await repository.saveDraft(
        entityType: spec.type,
        payload: payload,
        draftId: draftId,
        templateId: selectedTemplateId,
        lockVersion: lockVersion,
      );
      draftId = draft['id']?.toString();
      lockVersion = int.tryParse('${draft['lock_version'] ?? ''}');
      if (draftId == null) {
        throw StateError('El servidor no devolvió el borrador.');
      }
      final result = await repository.validateDraft(draftId!);
      if (!mounted) return;
      setState(() {
        validation = result;
        saving = false;
        currentStep = 4;
        // La validación incrementa el bloqueo en el servidor. La siguiente
        // edición vuelve a guardar sin una versión obsoleta.
        lockVersion = null;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        error = 'No se pudo guardar el borrador: $exception';
        saving = false;
      });
    }
  }

  Future<void> _publish() async {
    if (draftId == null || !isValid || !canPublish) return;
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
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
        title: Text('Publicar ${spec.singularName}'),
        content: const Text(
          'La configuración validada quedará disponible para los usuarios y generará una nueva versión. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Publicar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => saving = true);
    try {
      final result = await repository.publishDraft(
        draftId!,
        notes: 'Publicación desde el asistente de ${spec.singularName}.',
      );
      if (!mounted) return;
      if (result['publicado'] == true) {
        await experience.clearBuilderDraft(_autosaveKey);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${spec.singularName[0].toUpperCase()}${spec.singularName.substring(1)} publicada correctamente.',
            ),
          ),
        );
        Navigator.pop(context, true);
        return;
      }
      setState(() {
        error = result['error']?.toString() ??
            'El servidor rechazó la publicación.';
        saving = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        error = 'No se pudo publicar: $exception';
        saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FA),
      appBar: AppBar(
        title: Text(
          editingPublished
              ? 'Editar ${spec.singularName}'
              : 'Creador de ${spec.singularName}',
        ),
        bottom: _autosaveBar(),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null && templates.isEmpty
              ? _errorPanel()
              : LayoutBuilder(
                  builder: (context, constraints) => Stepper(
                    type: constraints.maxWidth >= 900
                        ? StepperType.horizontal
                        : StepperType.vertical,
                    currentStep: currentStep,
                    onStepTapped: saving
                        ? null
                        : (step) => setState(() => currentStep = step),
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
                    controlsBuilder: (context, details) =>
                        _stepControls(details),
                    steps: [
                      Step(
                        title: const Text('Origen'),
                        isActive: currentStep >= 0,
                        content: _templateStep(),
                      ),
                      Step(
                        title: const Text('Identidad'),
                        isActive: currentStep >= 1,
                        content: _identityStep(),
                      ),
                      Step(
                        title: const Text('Ubicación'),
                        isActive: currentStep >= 2,
                        content: _placementStep(),
                      ),
                      Step(
                        title: const Text('Comportamiento'),
                        isActive: currentStep >= 3,
                        content: _behaviorStep(),
                      ),
                      Step(
                        title: const Text('Revisar'),
                        isActive: currentStep >= 4,
                        state: isValid ? StepState.complete : StepState.indexed,
                        content: _reviewStep(),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _stepControls(ControlsDetails details) {
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
              label: Text(
                  draftId == null ? 'Guardar y validar' : 'Validar cambios'),
            ),
          if (currentStep == 4 && isValid && canPublish)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0C7A5B),
              ),
              onPressed: saving ? null : _publish,
              icon: const Icon(Icons.publish_outlined),
              label: const Text('Publicar'),
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

  Widget _templateStep() {
    return _questionCard(
      question: spec.questions.first,
      child: Column(
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
            onSelectionChanged: (selection) {
              final useTemplate = selection.first;
              if (!useTemplate) {
                _selectTemplate(null);
              } else if (_availableTemplates.isNotEmpty) {
                _selectTemplate(_availableTemplates.first['id']?.toString());
              }
            },
          ),
          const SizedBox(height: 8),
          Text(
            selectedTemplateId == null
                ? 'Comienza con una definición vacía.'
                : '${templates.length} plantilla(s) disponible(s).',
            style: const TextStyle(color: Color(0xFF60758A)),
          ),
          if (_availableTemplates.isNotEmpty) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey('template-$selectedTemplateId'),
              initialValue: _availableTemplates.any(
                (row) => row['id']?.toString() == selectedTemplateId,
              )
                  ? selectedTemplateId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Plantilla base',
                border: OutlineInputBorder(),
              ),
              items: _availableTemplates
                  .map(
                    (template) => DropdownMenuItem(
                      value: template['id']?.toString(),
                      child: Text(
                        template['nombre']?.toString() ?? 'Sin nombre',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _selectTemplate,
            ),
          ],
        ],
      ),
    );
  }

  Widget _identityStep() {
    return Column(
      children: [
        _questionField(
          questionId: 'nombre',
          controller: nameController,
          hint: isRubro
              ? 'Ej. Producción agrícola'
              : isSection
                  ? 'Ej. Operaciones agrícolas'
                  : 'Ej. Cosecha',
          onChanged: (_) => setState(() {
            if (!editingPublished) {
              codeController.text = generatedEntityCode(
                spec.type,
                nameController.text,
              );
            }
            validation = null;
          }),
        ),
        if (_nameSuggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Align(
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
                  children: _nameSuggestions
                      .map(
                        (value) => ActionChip(
                          label: Text(value),
                          onPressed: () => setState(() {
                            nameController.text = value;
                            if (!editingPublished) {
                              codeController.text =
                                  generatedEntityCode(spec.type, value);
                            }
                            validation = null;
                          }),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        _questionField(
          questionId: 'descripcion',
          controller: descriptionController,
          hint: isRubro
              ? 'Ej. Producción, empaque, almacenamiento y despacho.'
              : isSection
                  ? 'Ej. Reúne las operaciones de campo y planta.'
                  : 'Ej. Agrupa los formatos del proceso de almacén.',
          minLines: 3,
          maxLines: 5,
        ),
      ],
    );
  }

  List<ConfigurationIconChoice> get _availableIconChoices {
    if (configurationIconChoices
        .any((choice) => choice.value == selectedIcon)) {
      return configurationIconChoices;
    }
    return [
      ...configurationIconChoices,
      ConfigurationIconChoice(
        selectedIcon,
        'Icono actual ($selectedIcon)',
        configurationIconForName(selectedIcon),
      ),
    ];
  }

  Map<String, dynamic> _definition(Map<String, dynamic> row) {
    final value = row['definicion'];
    return value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
  }

  List<Map<String, dynamic>> get _siblingsForOrder {
    final rows = templates.where((row) {
      if (isRubro) return true;
      final definition = _definition(row);
      if (isSection) {
        return (definition['rubro_id'] ?? row['rubro_id'])?.toString() ==
            selectedRubroId;
      }
      final parent = definition['seccion_id'] ??
          definition['seccion'] ??
          row['padre_origen_id'];
      return parent?.toString() == selectedSectionId;
    }).toList();
    rows.sort((a, b) {
      final aOrder = int.tryParse('${_definition(a)['orden'] ?? 0}') ?? 0;
      final bOrder = int.tryParse('${_definition(b)['orden'] ?? 0}') ?? 0;
      return aOrder.compareTo(bOrder);
    });
    return rows;
  }

  void _suggestNextOrder({bool force = false}) {
    if (editingPublished) return;
    if (!force && !{'', '0'}.contains(orderController.text.trim())) return;
    final orders = _siblingsForOrder
        .map((row) => int.tryParse('${_definition(row)['orden'] ?? 0}') ?? 0)
        .toList();
    final next = orders.isEmpty
        ? 1
        : orders.reduce((left, right) => left > right ? left : right) + 1;
    orderController.text = '$next';
  }

  Future<void> _showCurrentOrder() async {
    final rows = _siblingsForOrder;
    final location = isRubro
        ? 'rubros'
        : isSection
            ? 'secciones del rubro'
            : 'módulos de la sección';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Orden actual de $location'),
        content: SizedBox(
          width: 480,
          child: rows.isEmpty
              ? Text('Todavía no hay $location publicados.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final order =
                        _definition(row)['orden']?.toString() ?? '${index + 1}';
                    return ListTile(
                      leading: CircleAvatar(child: Text(order)),
                      title: Text(row['nombre']?.toString() ?? 'Sin nombre'),
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

  Widget _colorField() {
    return TextField(
      controller: colorController,
      onChanged: (_) => setState(() => validation = null),
      decoration: InputDecoration(
        labelText: 'Color opcional',
        hintText: '#176B87 o rgb(23, 107, 135)',
        helperText:
            'Coloca hexadecimal o rgb, por ejemplo #176B87 o rgb(23, 107, 135).',
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: 'Abrir paleta de colores',
          onPressed: _chooseColor,
          icon: const Icon(Icons.palette_outlined),
        ),
      ),
    );
  }

  Future<void> _chooseColor() async {
    const colors = <String>[
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
      '#2196F3',
      '#4CAF50',
      '#8BC34A',
      '#FFC107',
      '#FF9800',
      '#E91E63',
      '#795548',
      '#455A64',
      '#D9EAF0',
      '#E8F6F1',
      '#FFF1F0',
      '#F4F8F7',
      '#FFFFFF',
      '#000000',
    ];
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Elegir color'),
        content: SizedBox(
          width: 360,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: colors.map((value) {
              final color = Color(
                int.parse('FF${value.substring(1)}', radix: 16),
              );
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
    if (selected == null || !mounted) return;
    setState(() {
      colorController.text = selected;
      validation = null;
    });
  }

  Widget _placementStep() {
    return Column(
      children: [
        if (!isRubro) ...[
          _questionCard(
            question: _question(isSection ? 'rubro_id' : 'seccion_id'),
            child: DropdownButtonFormField<String>(
              key: ValueKey(
                'parent-${isSection ? selectedRubroId : selectedSectionId}',
              ),
              initialValue: isSection ? selectedRubroId : selectedSectionId,
              decoration: InputDecoration(
                labelText: isSection ? 'Rubro' : 'Sección',
                border: const OutlineInputBorder(),
              ),
              items: (isSection ? rubros : _availableSectionTemplates)
                  .map(
                    (row) => DropdownMenuItem(
                      value: isSection
                          ? row['id']?.toString()
                          : row['entidad_origen_id']?.toString(),
                      child: Text(row['nombre']?.toString() ?? 'Sin nombre'),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() {
                if (isSection) {
                  selectedRubroId = value;
                } else {
                  selectedSectionId = value;
                }
                _suggestNextOrder(force: true);
                validation = null;
              }),
            ),
          ),
          const SizedBox(height: 14),
        ],
        _questionCard(
          question: _question('icono'),
          child: _iconSelector(),
        ),
        const SizedBox(height: 14),
        _questionField(
          questionId: 'orden',
          controller: orderController,
          keyboardType: TextInputType.number,
          hint: '0',
          suffix: IconButton(
            tooltip: 'Ver el orden actual',
            onPressed: _showCurrentOrder,
            icon: const Icon(Icons.format_list_numbered),
          ),
        ),
      ],
    );
  }

  Widget _behaviorStep() {
    return Column(
      children: [
        if (isSection) ...[
          _questionCard(
            question: _question('tipo_contenido'),
            child: DropdownButtonFormField<String>(
              key: ValueKey('content-$selectedContentType'),
              initialValue: selectedContentType,
              decoration: const InputDecoration(
                labelText: 'Tipo de contenido',
                border: OutlineInputBorder(),
              ),
              items: const {
                'FORMATOS': 'Módulos y formatos',
                'REPORTES': 'Reportes',
                'VISTAS_DINAMICAS': 'Vistas dinámicas',
                'REGISTROS_LOCALES': 'Registros locales',
                'INICIO': 'Inicio',
                'GENERICO': 'Contenido genérico',
              }
                  .entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => selectedContentType = value ?? 'FORMATOS'),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: routeController,
            decoration: const InputDecoration(
              labelText: 'Ruta Flutter (solo pantallas especiales)',
              helperText:
                  'Déjelo vacío en una sección normal. Solo se usa si un desarrollador registró una pantalla especial.',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (isRubro || isSection || isModule) ...[
          _colorField(),
          const SizedBox(height: 14),
        ],
        _questionCard(
          question: _question('activo'),
          child: SwitchListTile(
            value: active,
            contentPadding: EdgeInsets.zero,
            title: Text(active ? 'Visible al publicar' : 'Publicar oculta'),
            subtitle: Text(
              active
                  ? 'Los usuarios con permiso podrán verla después de actualizar datos.'
                  : 'La configuración se publicará inactiva.',
            ),
            onChanged: (value) => setState(() => active = value),
          ),
        ),
      ],
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
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _reviewSummary(),
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
            child: Row(
              children: [
                Icon(
                  isValid ? Icons.check_circle_outline : Icons.error_outline,
                  color: isValid
                      ? const Color(0xFF0C7A5B)
                      : const Color(0xFFB33B32),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isValid
                        ? 'Borrador válido y listo para publicar.'
                        : 'Corrija ${errors.length} error(es) antes de publicar.',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
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
            'El borrador está validado. Un administrador debe publicarlo.',
            style: TextStyle(color: Color(0xFF60758A)),
          ),
        ],
      ],
    );
  }

  Widget _iconGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 390 ? 4 : 3;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: columns,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.25,
          children: _availableIconChoices.map((choice) {
            final selected = choice.value == selectedIcon;
            return Tooltip(
              message: choice.label,
              child: Semantics(
                button: true,
                selected: selected,
                label: choice.label,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() {
                    selectedIcon = choice.value;
                    iconPickerExpanded = false;
                    validation = null;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFFE5F2F5)
                          : const Color(0xFFF8FAFB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF176B87)
                            : const Color(0xFFDCE6EC),
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          choice.icon,
                          size: 29,
                          color: selected
                              ? const Color(0xFF176B87)
                              : const Color(0xFF435866),
                        ),
                        if (selected)
                          const Positioned(
                            right: 6,
                            top: 6,
                            child: Icon(
                              Icons.check_circle,
                              size: 16,
                              color: Color(0xFF0C7A5B),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _iconSelector() {
    final selectedChoice = _availableIconChoices.firstWhere(
      (choice) => choice.value == selectedIcon,
      orElse: () => _availableIconChoices.first,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(
            () => iconPickerExpanded = !iconPickerExpanded,
          ),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Seleccione icono',
              prefixIcon: Icon(
                selectedChoice.icon,
                color: const Color(0xFF176B87),
              ),
              suffixIcon: AnimatedRotation(
                duration: const Duration(milliseconds: 180),
                turns: iconPickerExpanded ? .5 : 0,
                child: const Icon(Icons.expand_more),
              ),
              border: const OutlineInputBorder(),
            ),
            child: Text(
              selectedChoice.label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        AnimatedCrossFade(
          key: const ValueKey('configuration-icon-picker-panel'),
          duration: const Duration(milliseconds: 190),
          firstCurve: Curves.easeOut,
          secondCurve: Curves.easeOut,
          sizeCurve: Curves.easeOut,
          crossFadeState: iconPickerExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _iconGrid(),
          ),
        ),
      ],
    );
  }

  Widget _reviewSummary() {
    final icon = configurationIconForName(selectedIcon);
    final rows = <Widget>[
      _reviewLine('Nombre', Text(nameController.text.trim())),
    ];
    if (isSection) {
      rows.add(_reviewLine('Rubro', Text(_selectedRubroName())));
    } else if (isModule) {
      rows.add(_reviewLine('Sección', Text(_selectedSectionName())));
    }
    rows.add(_reviewLine(
      'Icono',
      DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFFE5F2F5),
          shape: BoxShape.circle,
        ),
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(icon, color: const Color(0xFF176B87)),
        ),
      ),
    ));
    if (isSection) {
      rows.add(_reviewLine(
        'Tipo de contenido',
        Text(_contentTypeName(selectedContentType)),
      ));
    }
    if (isSection || isModule) {
      rows.add(_reviewLine('Color', _colorPreview(colorController.text)));
    }
    return Column(children: rows);
  }

  Widget _reviewLine(String label, Widget value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF60758A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: value),
        ],
      ),
    );
  }

  String _selectedRubroName() {
    for (final row in rubros) {
      if (row['id']?.toString() == selectedRubroId) {
        if (selectedRubroId == 'rubro_general_zumac') {
          return 'Agroexportación';
        }
        return row['nombre']?.toString() ?? 'Rubro';
      }
    }
    return 'Sin rubro';
  }

  String _selectedSectionName() {
    for (final row in sectionTemplates) {
      if (row['entidad_origen_id']?.toString() == selectedSectionId) {
        return row['nombre']?.toString() ?? 'Sección';
      }
    }
    return 'Sin sección';
  }

  String _contentTypeName(String value) =>
      const {
        'FORMATOS': 'Módulos y formatos',
        'REPORTES': 'Reportes',
        'VISTAS_DINAMICAS': 'Vistas dinámicas',
        'REGISTROS_LOCALES': 'Registros locales',
        'INICIO': 'Inicio',
        'GENERICO': 'Contenido genérico',
      }[value] ??
      value;

  Widget _colorPreview(String rawValue) {
    final value = rawValue.trim();
    final color = _parseColor(value);
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color ?? Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0xFFB8C5CC)),
          ),
          child: color == null
              ? const Icon(Icons.block, size: 18, color: Color(0xFF60758A))
              : null,
        ),
        const SizedBox(width: 9),
        Expanded(
            child: Text(value.isEmpty ? 'Sin color personalizado' : value)),
      ],
    );
  }

  Color? _parseColor(String rawValue) {
    var value = rawValue.trim();
    if (value.startsWith('#')) {
      value = value.substring(1);
      if (value.length == 3) {
        value = value.split('').map((part) => '$part$part').join();
      }
      if (value.length == 6) value = 'FF$value';
      final parsed = int.tryParse(value, radix: 16);
      return parsed == null ? null : Color(parsed);
    }
    final match = RegExp(
      r'^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return null;
    final red = int.tryParse(match.group(1) ?? '');
    final green = int.tryParse(match.group(2) ?? '');
    final blue = int.tryParse(match.group(3) ?? '');
    if (red == null ||
        green == null ||
        blue == null ||
        red > 255 ||
        green > 255 ||
        blue > 255) {
      return null;
    }
    return Color.fromARGB(255, red, green, blue);
  }

  Widget _validationItem(dynamic item, Color color) {
    final map =
        item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{};
    final field = map['campo']?.toString() ?? '';
    final suggestions = map['sugerencias'] is List
        ? List<dynamic>.from(map['sugerencias'] as List)
            .map((value) => value.toString())
            .toList()
        : const <String>[];
    return ListTile(
      dense: true,
      leading: Icon(Icons.circle, size: 8, color: color),
      title: Text(map['mensaje']?.toString() ?? '$item'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (field.isNotEmpty) const Text('Toque aquí para corregirlo.'),
          if (suggestions.isNotEmpty)
            Text('Sugerencias: ${suggestions.join(' · ')}'),
        ],
      ),
      trailing: field.isEmpty ? null : const Icon(Icons.edit_outlined),
      onTap: field.isEmpty
          ? null
          : () => setState(() {
                currentStep = const {
                      'nombre': 1,
                      'codigo': 1,
                      'descripcion': 1,
                      'rubro_id': 2,
                      'seccion_id': 2,
                      'orden': 2,
                      'icono': 2,
                      'tipo_contenido': 3,
                    }[field] ??
                    1;
              }),
    );
  }

  List<String> get _nameSuggestions {
    final rawErrors = validation?['errores'];
    if (rawErrors is! List) return const [];
    final values = <String>{};
    var conflict = false;
    for (final raw in rawErrors) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final field = item['campo']?.toString() ?? '';
      if (field != 'nombre' && field != 'codigo') continue;
      conflict = conflict ||
          (item['mensaje']?.toString().toLowerCase().contains('ya existe') ??
              false);
      if (item['sugerencias'] is List) {
        values.addAll(
          List<dynamic>.from(item['sugerencias'] as List)
              .map((value) => value.toString()),
        );
      }
    }
    if (values.isEmpty && conflict) {
      final base = nameController.text.trim();
      values.addAll(['$base 2', '$base nuevo', '$base ${DateTime.now().year}']);
    }
    return values.toList();
  }

  Widget _questionField({
    required String questionId,
    required TextEditingController controller,
    String? hint,
    Widget? suffix,
    TextInputType? keyboardType,
    int minLines = 1,
    int maxLines = 1,
    bool readOnly = false,
    ValueChanged<String>? onChanged,
  }) {
    final question = _question(questionId);
    return _questionCard(
      question: question,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        minLines: minLines,
        maxLines: maxLines,
        readOnly: readOnly,
        onChanged: onChanged ?? (_) => validation = null,
        decoration: InputDecoration(
          labelText: question.required ? '${question.label} *' : question.label,
          hintText: hint,
          suffixIcon: suffix,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _questionCard({
    required ConfigurationQuestion question,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          question.label,
          style: const TextStyle(
            color: Color(0xFF17324D),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          question.reason,
          style: const TextStyle(color: Color(0xFF60758A), fontSize: 12),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }

  ConfigurationQuestion _question(String id) =>
      spec.questions.firstWhere((question) => question.id == id);

  Widget _errorPanel() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 12),
            Text(error ?? 'No se pudo abrir el asistente.'),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: _loadOptions, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
