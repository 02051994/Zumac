import 'package:flutter/material.dart';

import 'configuration_admin_repository.dart';
import 'configuration_entity_spec.dart';

class ConfigurationEntityWizardPage extends StatefulWidget {
  final String entityType;
  final Map<String, dynamic> contextData;
  final Map<String, dynamic>? initialDraft;
  final ConfigurationAdminRepository? repository;

  const ConfigurationEntityWizardPage({
    super.key,
    required this.entityType,
    required this.contextData,
    this.initialDraft,
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
    _hydrateDraft(widget.initialDraft);
    _loadOptions();
  }

  @override
  void dispose() {
    nameController.dispose();
    codeController.dispose();
    descriptionController.dispose();
    orderController.dispose();
    routeController.dispose();
    colorController.dispose();
    super.dispose();
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
    if (draft['_requested_action'] == 'DEACTIVATE') currentStep = 4;
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

  void _selectTemplate(String? templateId) {
    setState(() {
      selectedTemplateId = templateId;
      validation = null;
      if (templateId == null) return;
      final template = templates.cast<Map<String, dynamic>?>().firstWhere(
            (row) => row?['id']?.toString() == templateId,
            orElse: () => null,
          );
      if (template == null) return;
      final definition = template['definicion'] is Map
          ? Map<String, dynamic>.from(template['definicion'] as Map)
          : <String, dynamic>{};
      nameController.text = 'Copia de ${template['nombre'] ?? ''}'.trim();
      codeController.clear();
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
    });
  }

  Map<String, dynamic> _payload() {
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Publicar ${spec.singularName}'),
        content: const Text(
          'La configuración validada quedará disponible en Supabase y generará una nueva versión. ¿Continuar?',
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
              ? 'Nueva versión de ${spec.singularName}'
              : 'Nueva ${spec.singularName}',
        ),
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
              } else if (templates.isNotEmpty) {
                _selectTemplate(templates.first['id']?.toString());
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
          if (templates.isNotEmpty) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey('template-$selectedTemplateId'),
              initialValue: templates.any(
                (row) => row['id']?.toString() == selectedTemplateId,
              )
                  ? selectedTemplateId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Plantilla base',
                border: OutlineInputBorder(),
              ),
              items: templates
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
        ),
        const SizedBox(height: 14),
        _questionField(
          questionId: 'codigo',
          controller: codeController,
          hint: isRubro
              ? 'PRODUCCION_AGRICOLA'
              : isSection
                  ? 'OPERACIONES_AGRICOLAS'
                  : 'COSECHA',
          suffix: IconButton(
            tooltip: 'Generar desde el nombre',
            onPressed: editingPublished
                ? null
                : () {
                    codeController.text =
                        normalizeConfigurationCode(nameController.text);
                    setState(() {});
                  },
            icon: const Icon(Icons.auto_fix_high),
          ),
          readOnly: editingPublished,
        ),
        const SizedBox(height: 14),
        _questionField(
          questionId: 'descripcion',
          controller: descriptionController,
          minLines: 3,
          maxLines: 5,
        ),
      ],
    );
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
              items: (isSection ? rubros : sectionTemplates)
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
              }),
            ),
          ),
          const SizedBox(height: 14),
        ],
        _questionCard(
          question: _question('icono'),
          child: DropdownButtonFormField<String>(
            key: ValueKey('icon-$selectedIcon'),
            initialValue: selectedIcon,
            decoration: const InputDecoration(
              labelText: 'Icono',
              border: OutlineInputBorder(),
            ),
            items: const {
              'apps': 'Aplicaciones',
              'assignment': 'Formatos',
              'agriculture': 'Agricultura',
              'eco': 'Cultivos',
              'inventory': 'Inventario',
              'people': 'Personal',
              'analytics': 'Indicadores',
              'settings': 'Configuración',
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
                setState(() => selectedIcon = value ?? 'apps'),
          ),
        ),
        const SizedBox(height: 14),
        _questionField(
          questionId: 'orden',
          controller: orderController,
          keyboardType: TextInputType.number,
          hint: '0',
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
              labelText: 'Ruta Flutter opcional',
              helperText: 'Solo para una pantalla especial ya registrada.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (isRubro || isSection) ...[
          TextField(
            controller: colorController,
            decoration: const InputDecoration(
              labelText: 'Color opcional',
              hintText: '#176B87',
              border: OutlineInputBorder(),
            ),
          ),
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
    final payload = _payload();
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
            child: Column(
              children: payload.entries
                  .where((entry) => '${entry.value}'.trim().isNotEmpty)
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 145,
                            child: Text(
                              entry.key,
                              style: const TextStyle(
                                color: Color(0xFF60758A),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(child: Text('${entry.value}')),
                        ],
                      ),
                    ),
                  )
                  .toList(),
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

  Widget _validationItem(dynamic item, Color color) {
    final map =
        item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{};
    return ListTile(
      dense: true,
      leading: Icon(Icons.circle, size: 8, color: color),
      title: Text(map['mensaje']?.toString() ?? '$item'),
      subtitle: map['campo'] == null ? null : Text('Campo: ${map['campo']}'),
    );
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
