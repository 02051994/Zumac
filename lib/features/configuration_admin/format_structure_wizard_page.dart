import 'package:flutter/material.dart';

import 'configuration_admin_repository.dart';
import 'configuration_entity_spec.dart';
import 'format_structure_validator.dart';

class FormatStructureWizardPage extends StatefulWidget {
  final Map<String, dynamic> contextData;
  final Map<String, dynamic>? initialDraft;
  final ConfigurationAdminRepository? repository;

  const FormatStructureWizardPage({
    super.key,
    required this.contextData,
    this.initialDraft,
    this.repository,
  });

  @override
  State<FormatStructureWizardPage> createState() =>
      _FormatStructureWizardPageState();
}

class _FormatStructureWizardPageState extends State<FormatStructureWizardPage> {
  late final ConfigurationAdminRepository repository;

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
  String formatType = 'SIMPLE';
  String? selectedTemplateId;
  String? selectedModuleId;
  String? selectedRubroId;
  String? draftId;
  int? lockVersion;
  String? error;
  Map<String, dynamic>? validation;
  List<Map<String, dynamic>> templates = [];
  List<Map<String, dynamic>> moduleTemplates = [];
  List<Map<String, dynamic>> tables = [];

  bool get canPublish => widget.contextData['puede_publicar'] == true;
  bool get isValid => validation?['valido'] == true;

  @override
  void initState() {
    super.initState();
    repository = widget.repository ?? ConfigurationAdminRepository();
    _hydrateDraft(widget.initialDraft);
    _loadOptions();
  }

  @override
  void dispose() {
    nameController.dispose();
    codeController.dispose();
    descriptionController.dispose();
    orderController.dispose();
    super.dispose();
  }

  void _hydrateDraft(Map<String, dynamic>? draft) {
    if (draft == null) return;
    final definition = _map(draft['definicion']);
    draftId = draft['id']?.toString();
    lockVersion = int.tryParse('${draft['lock_version'] ?? ''}');
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
    final capabilities = _map(definition['capacidades']);
    offline = capabilities['offline'] != false;
    workflow = capabilities['workflow'] == true;
    photos = capabilities['fotos'] == true;
    signature = capabilities['firma'] == true;
    geolocation = capabilities['geolocalizacion'] == true;
    qr = capabilities['qr'] == true;
    approvals = capabilities['aprobaciones'] == true;
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
        selectedModuleId ??= moduleTemplates.isEmpty
            ? null
            : moduleTemplates.first['entidad_origen_id']?.toString();
        _deriveRubro();
        loading = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'No se pudieron cargar las opciones: $exception';
      });
    }
  }

  List<Map<String, dynamic>> _items(Map<String, dynamic> result) =>
      _maps(result['items']);

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
      : <Map<String, dynamic>>[];

  void _deriveRubro() {
    final module = moduleTemplates.cast<Map<String, dynamic>?>().firstWhere(
          (row) => row?['entidad_origen_id']?.toString() == selectedModuleId,
          orElse: () => null,
        );
    selectedRubroId = module?['rubro_id']?.toString() ?? selectedRubroId;
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
    nameController.text = structure['nombre']?.toString() ?? '';
    codeController.text = structure['codigo']?.toString() ?? '';
    descriptionController.text = structure['descripcion']?.toString() ?? '';
    orderController.text = structure['orden']?.toString() ?? '0';
    selectedModuleId = structure['modulo_id']?.toString() ?? selectedModuleId;
    formatType = structure['tipo_formato']?.toString() ?? 'SIMPLE';
    active = structure['activo'] != false;
    tableVisible = structure['tabla_visible_app'] != false;
    tables = _maps(structure['tablas']);
    _deriveRubro();
  }

  Map<String, dynamic> _payload() {
    final raw = <String, dynamic>{
      'codigo': codeController.text.trim(),
      'nombre': nameController.text.trim(),
      'descripcion': descriptionController.text.trim(),
      'rubro_id': selectedRubroId,
      'modulo_id': selectedModuleId,
      'tipo_formato': formatType,
      'tabla_destino':
          tables.isEmpty ? '' : tables.first['tabla_destino']?.toString() ?? '',
      'tabla_visible_app': tableVisible,
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
      'tablas': tables,
    };
    return rekeyClonedFormatChildren(raw);
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Publicar estructura completa'),
        content: Text(
          'Se crearán el formato, ${tables.length} tabla(s), sus campos y matrices en una sola operación. Si algo falla, no se aplicará ningún cambio.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.publish_outlined),
            label: const Text('Publicar todo'),
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
      appBar: AppBar(title: const Text('Asistente de formato dinámico')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) => Stepper(
                type: constraints.maxWidth >= 1050
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
                    state: isValid ? StepState.complete : StepState.indexed,
                    content: _reviewStep(),
                  ),
                ],
              ),
            ),
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
              label: const Text('Guardar y validar todo'),
            ),
          if (currentStep == 4 && isValid && canPublish)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0C7A5B),
              ),
              onPressed: saving ? null : _publish,
              icon: const Icon(Icons.publish_outlined),
              label: const Text('Publicar todo'),
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
                    } else if (templates.isNotEmpty) {
                      _selectTemplate(templates.first['id']?.toString());
                    }
                  },
          ),
          if (templates.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('format-template-$selectedTemplateId'),
              initialValue: templates.any(
                (row) => row['id']?.toString() == selectedTemplateId,
              )
                  ? selectedTemplateId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Plantilla de formato',
                border: OutlineInputBorder(),
              ),
              items: templates
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
          '¿En qué módulo se mostrará?',
          'El módulo determina la ubicación del formato en la navegación.',
          DropdownButtonFormField<String>(
            key: ValueKey('module-$selectedModuleId'),
            initialValue: moduleTemplates.any(
              (row) => row['entidad_origen_id']?.toString() == selectedModuleId,
            )
                ? selectedModuleId
                : null,
            decoration: const InputDecoration(
              labelText: 'Módulo *',
              border: OutlineInputBorder(),
            ),
            items: moduleTemplates
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
              validation = null;
            }),
          ),
        ),
        const SizedBox(height: 14),
        _textQuestion(
          '¿Qué nombre verá el usuario?',
          'Identifica el proceso o captura en la aplicación.',
          nameController,
          label: 'Nombre visible *',
          hint: 'Ej. Inspección de cultivo',
        ),
        const SizedBox(height: 14),
        _textQuestion(
          '¿Cuál será su código técnico único?',
          'Relaciona navegación, permisos, tablas y sincronización.',
          codeController,
          label: 'Código técnico *',
          hint: 'INSPECCION_CULTIVO',
          suffix: IconButton(
            tooltip: 'Generar desde el nombre',
            onPressed: () => setState(() {
              codeController.text =
                  normalizeConfigurationCode(nameController.text);
              validation = null;
            }),
            icon: const Icon(Icons.auto_fix_high),
          ),
        ),
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
        _question(
          '¿Qué patrón de captura necesita?',
          'El tipo orienta las tablas y relaciones que deberá configurar.',
          DropdownButtonFormField<String>(
            initialValue: formatType,
            decoration: const InputDecoration(
              labelText: 'Tipo de formato *',
              border: OutlineInputBorder(),
            ),
            items: supportedFormatTypes
                .map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(value.replaceAll('_', ' ')),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() {
              formatType = value ?? 'SIMPLE';
              validation = null;
            }),
          ),
        ),
        const SizedBox(height: 14),
        _textQuestion(
          '¿En qué orden debe aparecer?',
          'Controla la posición dentro del módulo.',
          orderController,
          label: 'Orden *',
          keyboardType: TextInputType.number,
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
          'El registro podrá avanzar por estados de proceso.',
          workflow,
          (value) => workflow = value,
        ),
        _capability(
          'Evidencias fotográficas',
          'Habilita preguntas y controles asociados a fotos.',
          photos,
          (value) => photos = value,
        ),
        _capability(
          'Firma',
          'Permite agregar controles de conformidad o firma.',
          signature,
          (value) => signature = value,
        ),
        _capability(
          'Geolocalización',
          'Permite capturar coordenadas del registro.',
          geolocation,
          (value) => geolocation = value,
        ),
        _capability(
          'Lectura QR',
          'Permite identificar elementos mediante códigos QR.',
          qr,
          (value) => qr = value,
        ),
        _capability(
          'Aprobaciones',
          'El formato requerirá una o más aprobaciones.',
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
          '${table['tabla_destino'] ?? ''} · ${fields.length} campo(s)',
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
            '${field['campo'] ?? ''} · ${matrices.length} matriz(ces)',
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
    final code = TextEditingController(text: initial['codigo']?.toString());
    final physical =
        TextEditingController(text: initial['tabla_destino']?.toString());
    final order = TextEditingController(
        text: initial['orden']?.toString() ?? '${tables.length + 1}');
    final parent =
        TextEditingController(text: initial['tabla_padre']?.toString());
    final parentKey = TextEditingController(
        text: initial['campo_pk_padre']?.toString() ?? 'id');
    final foreignKey =
        TextEditingController(text: initial['campo_fk_hijo']?.toString());
    var createPhysical = initial['crear_tabla_fisica'] != false;
    var header = initial['es_cabecera'] == true;
    var detail = initial['es_detalle'] == true;
    var captureMode = initial['modo_captura']?.toString() ?? 'FORMULARIO';
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
                  _dialogField(name, 'Nombre visible *'),
                  _dialogField(code, 'Código técnico *'),
                  _dialogField(physical, 'Nombre físico en Supabase *'),
                  _dialogField(order, 'Orden *',
                      keyboardType: TextInputType.number),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: createPhysical,
                    title: const Text('Crear tabla física si no existe'),
                    onChanged: (value) =>
                        setDialogState(() => createPhysical = value),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: header,
                    title: const Text('Es cabecera'),
                    onChanged: (value) =>
                        setDialogState(() => header = value == true),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: detail,
                    title: const Text('Es detalle'),
                    onChanged: (value) =>
                        setDialogState(() => detail = value == true),
                  ),
                  if (detail) ...[
                    _dialogField(parent, 'Tabla padre *'),
                    _dialogField(parentKey, 'Campo PK del padre *'),
                    _dialogField(foreignKey, 'Campo FK del detalle *'),
                  ],
                  DropdownButtonFormField<String>(
                    initialValue: captureMode,
                    decoration: const InputDecoration(
                      labelText: 'Modo de captura',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'FORMULARIO', child: Text('Formulario')),
                      DropdownMenuItem(
                          value: 'TABLA', child: Text('Tabla editable')),
                      DropdownMenuItem(value: 'MIXTO', child: Text('Mixto')),
                    ],
                    onChanged: (value) => setDialogState(
                        () => captureMode = value ?? 'FORMULARIO'),
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
              onPressed: () => Navigator.pop(dialogContext, {
                ...initial,
                'nombre': name.text.trim(),
                'codigo': code.text.trim(),
                'tabla_destino': physical.text.trim(),
                'orden': int.tryParse(order.text.trim()) ?? order.text.trim(),
                'crear_tabla_fisica': createPhysical,
                'activo': initial['activo'] != false,
                'es_cabecera': header,
                'es_detalle': detail,
                'tipo_relacion': detail ? 'UNO_MUCHOS' : null,
                'tabla_padre': detail ? parent.text.trim() : null,
                'campo_pk_padre': detail ? parentKey.text.trim() : null,
                'campo_fk_hijo': detail ? foreignKey.text.trim() : null,
                'modo_captura': captureMode,
                'campos': _maps(initial['campos']),
              }),
              child: const Text('Guardar tabla'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    code.dispose();
    physical.dispose();
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

  Future<void> _editField(int tableIndex, {int? index}) async {
    final fields = _maps(tables[tableIndex]['campos']);
    final initial = index == null ? <String, dynamic>{} : fields[index];
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
    var uiType = initial['tipo_ui']?.toString() ?? 'text';
    var required = '${initial['requerido']}'.toLowerCase() == 'true';
    var editable = initial['editable'] != false;
    var visible = initial['visible'] != false;
    var visibleTable = initial['visible_tabla'] != false;
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
                  _dialogField(label, 'Etiqueta visible *'),
                  _dialogField(code, 'Código técnico *'),
                  _dialogField(physical, 'Nombre físico de columna *'),
                  DropdownButtonFormField<String>(
                    initialValue: uiType,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de control *',
                      border: OutlineInputBorder(),
                    ),
                    items: const {
                      'text': 'Texto',
                      'textarea': 'Texto largo',
                      'number': 'Número decimal',
                      'integer': 'Número entero',
                      'date': 'Fecha',
                      'datetime': 'Fecha y hora',
                      'boolean': 'Sí / No',
                      'dropdown': 'Lista desplegable',
                      'multiselect': 'Selección múltiple',
                      'formula': 'Fórmula',
                      'lookup': 'Consulta calculada',
                      'photo': 'Foto',
                      'signature': 'Firma',
                      'qr': 'Código QR',
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
                        setDialogState(() => uiType = value ?? 'text'),
                  ),
                  const SizedBox(height: 12),
                  _dialogField(order, 'Orden *',
                      keyboardType: TextInputType.number),
                  _dialogField(defaultValue, 'Valor predeterminado'),
                  if (uiType == 'formula' || uiType == 'lookup')
                    _dialogField(formula, 'Fórmula o función *', maxLines: 3),
                  if (uiType == 'dropdown' || uiType == 'multiselect')
                    _dialogField(dropdown, 'Código de fuente dropdown'),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: required,
                    title: const Text('Obligatorio'),
                    onChanged: (value) =>
                        setDialogState(() => required = value == true),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: editable,
                    title: const Text('Editable'),
                    onChanged: (value) =>
                        setDialogState(() => editable = value == true),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: visible,
                    title: const Text('Visible en formulario'),
                    onChanged: (value) =>
                        setDialogState(() => visible = value == true),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: visibleTable,
                    title: const Text('Visible en tabla de registros'),
                    onChanged: (value) =>
                        setDialogState(() => visibleTable = value == true),
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
              onPressed: () => Navigator.pop(dialogContext, {
                ...initial,
                'nombre': label.text.trim(),
                'etiqueta': label.text.trim(),
                'codigo': code.text.trim(),
                'campo': physical.text.trim(),
                'tipo': uiType,
                'tipo_ui': uiType,
                'orden': int.tryParse(order.text.trim()) ?? order.text.trim(),
                'valor_default': defaultValue.text.trim(),
                'formula_funcion': formula.text.trim(),
                'id_campo_dropdown': dropdown.text.trim(),
                'requerido': required,
                'editable': editable,
                'visible': visible,
                'visible_tabla': visibleTable,
                'activo': initial['activo'] != false,
                'matrices': _maps(initial['matrices']),
              }),
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
                  _dialogField(name, 'Nombre visible *'),
                  _dialogField(code, 'Código técnico *'),
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
              onPressed: () => Navigator.pop(dialogContext, {
                ...initial,
                'nombre': name.text.trim(),
                'codigo': code.text.trim(),
                'clase_matriz': matrixClass,
                'expresion': expression.text.trim(),
                'tabla_origen': sourceTable.text.trim(),
                'campo_valor': valueField.text.trim(),
                'campo_etiqueta': labelField.text.trim(),
                'activo': initial['activo'] != false,
              }),
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
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _reviewStep() {
    final fields = tables.fold<int>(
      0,
      (total, table) => total + _maps(table['campos']).length,
    );
    final matrices = tables.fold<int>(0, (total, table) {
      return total +
          _maps(table['campos']).fold<int>(
            0,
            (subtotal, field) => subtotal + _maps(field['matrices']).length,
          );
    });
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
                const SizedBox(height: 5),
                Text('${codeController.text} · $formatType'),
                const Divider(height: 24),
                Text('$selectedModuleId · Rubro $selectedRubroId'),
                const SizedBox(height: 6),
                Text(
                    '$fields campo(s) en ${tables.length} tabla(s) · $matrices matriz(ces)'),
                const SizedBox(height: 12),
                for (final table in tables)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.table_chart_outlined),
                    title: Text(table['nombre']?.toString() ?? 'Tabla'),
                    subtitle: Text(
                      '${table['tabla_destino'] ?? ''} · ${_maps(table['campos']).length} campo(s)',
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
    return ListTile(
      dense: true,
      leading: Icon(Icons.circle, size: 8, color: color),
      title: Text(data['mensaje']?.toString() ?? '$item'),
      subtitle: data['campo'] == null ? null : Text('Campo: ${data['campo']}'),
    );
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
  }) {
    return _question(
      title,
      reason,
      TextField(
        controller: controller,
        keyboardType: keyboardType,
        minLines: minLines,
        maxLines: maxLines,
        onChanged: (_) => validation = null,
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
