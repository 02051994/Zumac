import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide ScaffoldMessenger;

import '../../core/widgets/zumac_scaffold_messenger.dart';
import 'package:image_picker/image_picker.dart';

import 'configuration_admin_repository.dart';
import 'creator_document_models.dart';
import 'creator_document_quality_service.dart';
import 'format_structure_validator.dart';
import 'format_structure_wizard_page.dart';

/// Flujo de Zumac Creator que transforma una foto o PDF en un borrador
/// revisable, sin publicar ni sobrescribir configuración existente.
class CreatorDocumentImportPage extends StatefulWidget {
  const CreatorDocumentImportPage({
    super.key,
    required this.contextData,
    required this.repository,
    this.initialRubroId,
  });

  final Map<String, dynamic> contextData;
  final ConfigurationAdminRepository repository;
  final String? initialRubroId;

  @override
  State<CreatorDocumentImportPage> createState() =>
      _CreatorDocumentImportPageState();
}

class _CreatorDocumentImportPageState extends State<CreatorDocumentImportPage> {
  static const maxFileBytes = 18 * 1024 * 1024;
  static const uiTypes = <String, String>{
    'text': 'Texto',
    'multiline': 'Texto largo',
    'number': 'Número decimal',
    'integer': 'Número entero',
    'date': 'Fecha',
    'time': 'Hora',
    'datetime': 'Fecha y hora',
    'checkbox': 'Casilla Sí / No',
    'switch': 'Interruptor Sí / No',
    'dropdown': 'Lista desplegable',
    'multiselect': 'Selección múltiple',
    'photo': 'Foto',
    'signature': 'Firma',
    'qr_scan': 'Código QR',
    'barcode_scan': 'Código de barras',
    'email': 'Correo',
    'phone': 'Teléfono',
    'url': 'Enlace',
    'percent': 'Porcentaje',
  };

  final picker = ImagePicker();
  final qualityService = const CreatorDocumentQualityService();
  final payloadBuilder = const CreatorFormatPayloadBuilder();
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  final headerRowController = TextEditingController(text: '1');

  int currentStep = 0;
  bool busy = false;
  bool loadingModules = true;
  String? error;
  _CreatorPickedDocument? document;
  CreatorDocumentQuality? quality;
  CreatorDocumentAnalysis? analysis;
  List<CreatorDetectedField> fields = <CreatorDetectedField>[];
  List<Map<String, dynamic>> moduleTemplates = <Map<String, dynamic>>[];
  String? selectedRubroId;
  String? selectedModuleId;
  String? importId;
  String? model;
  String analysisEngine = 'ZUMAC';
  bool advancedAiEnabled = false;
  Map<String, dynamic> aiSubscription = <String, dynamic>{};
  Map<String, dynamic> pendingAiRequest = <String, dynamic>{};
  List<Map<String, dynamic>> aiPlans = <Map<String, dynamic>>[];
  CreatorFormLayout formLayout = CreatorFormLayout.vertical;
  CreatorRecordLayout recordLayout = CreatorRecordLayout.table;
  Map<String, dynamic>? savedDraft;
  Map<String, dynamic>? validation;

  @override
  void initState() {
    super.initState();
    _applyProductContext(widget.contextData);
    selectedRubroId = widget.initialRubroId ??
        (_rubros.isEmpty ? null : _rubros.first['id']?.toString());
    _loadModules();
  }

  void _applyProductContext(Map<String, dynamic> contextData) {
    advancedAiEnabled = contextData['ia_avanzada_habilitada'] == true;
    aiSubscription = _map(contextData['suscripcion_ia']);
    pendingAiRequest = _map(contextData['solicitud_pendiente']);
    aiPlans = _maps(contextData['planes_ia']);
  }

  bool get _hasAdvancedCredits {
    final remaining =
        num.tryParse('${aiSubscription['creditos_restantes'] ?? 0}') ?? 0;
    return advancedAiEnabled &&
        aiSubscription['estado']?.toString() == 'ACTIVA' &&
        remaining > 0;
  }

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    headerRowController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _rubros {
    final value = widget.contextData['rubros'];
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  List<Map<String, dynamic>> get _availableModules {
    if (selectedRubroId == null) return moduleTemplates;
    return moduleTemplates.where((row) {
      final definition = _map(row['definicion']);
      return (row['rubro_id'] ?? definition['rubro_id'])?.toString() ==
          selectedRubroId;
    }).toList(growable: false);
  }

  Future<void> _loadModules() async {
    try {
      final result = await widget.repository.listTemplates(
        entityType: 'MODULO',
        limit: 300,
      );
      if (!mounted) return;
      setState(() {
        moduleTemplates = _maps(result['items']);
        final available = _availableModules;
        selectedModuleId =
            available.isEmpty ? null : _moduleId(available.first);
        loadingModules = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        loadingModules = false;
        error = 'No se pudieron cargar los módulos: $exception';
      });
    }
  }

  Future<void> _pickCamera() async {
    try {
      final file = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
        maxWidth: 3200,
      );
      if (file == null) return;
      await _acceptDocument(
        name: 'captura_${DateTime.now().millisecondsSinceEpoch}.jpg',
        mimeType: _imageMime(file.name),
        bytes: await file.readAsBytes(),
        sourceType: CreatorSourceType.camera,
      );
    } catch (exception) {
      _showError('No se pudo abrir la cámara: $exception');
    }
  }

  Future<void> _pickGallery() async {
    try {
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
        maxWidth: 4000,
      );
      if (file == null) return;
      await _acceptDocument(
        name: file.name,
        mimeType: _imageMime(file.name),
        bytes: await file.readAsBytes(),
        sourceType: CreatorSourceType.gallery,
      );
    } catch (exception) {
      _showError('No se pudo leer la imagen: $exception');
    }
  }

  Future<void> _pickPdf() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        allowMultiple: false,
        withData: true,
      );
      if (result == null) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        _showError('No se pudo cargar el contenido del PDF.');
        return;
      }
      await _acceptDocument(
        name: file.name,
        mimeType: 'application/pdf',
        bytes: bytes,
        sourceType: CreatorSourceType.pdf,
      );
    } catch (exception) {
      _showError('No se pudo leer el PDF: $exception');
    }
  }

  Future<void> _acceptDocument({
    required String name,
    required String mimeType,
    required Uint8List bytes,
    required CreatorSourceType sourceType,
  }) async {
    if (bytes.isEmpty) {
      _showError('El archivo está vacío.');
      return;
    }
    if (bytes.length > maxFileBytes) {
      _showError('El archivo supera el máximo permitido de 18 MB.');
      return;
    }
    final report = sourceType == CreatorSourceType.pdf
        ? qualityService.inspectPdf(bytes)
        : qualityService.inspectImage(bytes);
    if (!mounted) return;
    setState(() {
      document = _CreatorPickedDocument(
        name: name,
        mimeType: mimeType,
        bytes: bytes,
        sourceType: sourceType,
      );
      quality = report;
      analysis = null;
      fields = <CreatorDetectedField>[];
      importId = null;
      model = null;
      savedDraft = null;
      validation = null;
      error = null;
      currentStep = 1;
    });
  }

  Future<void> _analyze() async {
    final selected = document;
    final localQuality = quality;
    if (selected == null || localQuality == null || !localQuality.acceptable) {
      _showError('Seleccione un archivo legible antes de analizarlo.');
      return;
    }
    if (analysisEngine == 'OPENAI' && !_hasAdvancedCredits) {
      await _showAdvancedPlanDialog(
        exhausted: aiSubscription['estado']?.toString() == 'AGOTADA',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final session = await widget.repository.createAiFormatImport(
        sourceName: selected.name,
        mimeType: selected.mimeType,
        sizeBytes: selected.bytes.length,
        sourceHash: sha256.convert(selected.bytes).toString(),
        sourceType: _sourceTypeValue(selected.sourceType),
        localQuality: localQuality.toJson(),
      );
      importId = session['id']?.toString();
      if (importId == null) {
        throw StateError('No se creó la sesión de análisis.');
      }
      await widget.repository.updateAiFormatImport(
        importId: importId!,
        status: 'ANALIZANDO',
      );
      final result = await widget.repository.analyzeFormatDocument(
        sourceName: selected.name,
        mimeType: selected.mimeType,
        bytes: selected.bytes,
        importId: importId!,
        engine: analysisEngine,
      );
      final rawAnalysis = _map(result['analysis']);
      final parsed = CreatorDocumentAnalysis.fromJson(rawAnalysis);
      model = result['model']?.toString();
      final credits = _map(result['credits']);
      if (analysisEngine == 'OPENAI' && credits.isNotEmpty) {
        aiSubscription = {
          ...aiSubscription,
          'creditos_restantes':
              credits['remaining'] ?? aiSubscription['creditos_restantes'] ?? 0,
          if (credits['exhausted'] == true) 'estado': 'AGOTADA',
        };
      }
      if (!parsed.qualityAcceptable) {
        final serverQuality = _map(rawAnalysis['document_quality']);
        final issues = _strings(serverQuality['issues']);
        quality = localQuality.copyWith(
          acceptable: false,
          summary: parsed.qualityMessage.isEmpty
              ? 'El documento no es suficientemente legible.'
              : parsed.qualityMessage,
          reasons: issues.isEmpty
              ? const [
                  'La revisión visual no pudo leer el documento con seguridad.'
                ]
              : issues,
          requiresServerReview: false,
        );
        await widget.repository.updateAiFormatImport(
          importId: importId!,
          status: 'CALIDAD_RECHAZADA',
          serverQuality: serverQuality,
          rawAnalysis: rawAnalysis,
          model: model,
        );
        if (!mounted) return;
        setState(() {
          busy = false;
          currentStep = 1;
        });
        return;
      }
      if (parsed.fields.isEmpty) {
        throw StateError('No se detectaron campos revisables en el documento.');
      }
      await widget.repository.updateAiFormatImport(
        importId: importId!,
        status: 'REQUIERE_REVISION',
        serverQuality: _map(rawAnalysis['document_quality']),
        rawAnalysis: rawAnalysis,
        headerRow: parsed.headerRow,
        model: model,
      );
      if (!mounted) return;
      setState(() {
        analysis = parsed;
        fields = List<CreatorDetectedField>.from(parsed.fields);
        titleController.text = parsed.title;
        descriptionController.text = parsed.description;
        headerRowController.text = '${parsed.headerRow}';
        busy = false;
        currentStep = 2;
      });
    } catch (exception) {
      if (importId != null) {
        try {
          await widget.repository.updateAiFormatImport(
            importId: importId!,
            status: 'ERROR',
            errorMessage: '$exception',
          );
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        busy = false;
        error = 'No se pudo analizar el documento: $exception';
      });
      if (exception is CreatorAnalysisException &&
          (exception.code == 'AI_CREDITS_EXHAUSTED' ||
              exception.code == 'AI_PLAN_REQUIRED')) {
        await _showAdvancedPlanDialog(
          exhausted: exception.code == 'AI_CREDITS_EXHAUSTED',
        );
      }
    }
  }

  Future<void> _reloadAiAccess() async {
    final contextData = await widget.repository.loadProductContext();
    if (!mounted) return;
    setState(() => _applyProductContext(contextData));
  }

  Future<void> _showAdvancedPlanDialog({bool exhausted = false}) async {
    if (!advancedAiEnabled) {
      _showError('La IA avanzada no está habilitada para esta empresa.');
      return;
    }
    final selectedPlan = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          exhausted
              ? '¿Ya consumiste todos los tokens, deseas más?'
              : 'Activar IA avanzada',
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Zumac AI Engine continúa disponible gratuitamente. El plan avanzado utiliza OpenAI solo para este usuario y descuenta el consumo real de entrada y salida.',
                ),
                if (pendingAiRequest.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF6DE),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Existe una solicitud ${pendingAiRequest['estado'] ?? 'PENDIENTE_PAGO'} por US\$${pendingAiRequest['monto_usd'] ?? ''}. Puede cambiar el plan antes de confirmar el pago.',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                for (final plan in aiPlans) ...[
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.auto_awesome_outlined),
                      ),
                      title: Text(
                        plan['nombre']?.toString() ?? 'Plan avanzado',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${plan['creditos_incluidos'] ?? 0} créditos IA · ${plan['periodo'] ?? ''}\n${plan['descripcion'] ?? ''}',
                      ),
                      trailing: Text(
                        'US\$${plan['precio_usd'] ?? ''}',
                        style: const TextStyle(
                          color: Color(0xFF0D5F78),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      onTap: () => Navigator.pop(
                        dialogContext,
                        plan['codigo']?.toString(),
                      ),
                    ),
                  ),
                ],
                const Text(
                  'El precio y los créditos están configurados en Supabase. La suscripción se activa únicamente cuando el pago queda confirmado.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF60758A)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'ZUMAC_FREE'),
            child: const Text('Seguir con Zumac gratis'),
          ),
        ],
      ),
    );
    if (selectedPlan == 'ZUMAC_FREE' && mounted) {
      setState(() => analysisEngine = 'ZUMAC');
      return;
    }
    if (selectedPlan == null || !mounted) return;

    setState(() {
      busy = true;
      error = null;
    });
    try {
      final request =
          await widget.repository.requestAdvancedAiPlan(selectedPlan);
      await _reloadAiAccess();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Pago pendiente'),
          content: Text(
            'Plan: ${request['plan_nombre'] ?? selectedPlan}\n'
            'Importe: ${request['moneda'] ?? 'USD'} ${request['monto_usd'] ?? ''}\n\n'
            '${request['mensaje'] ?? 'El acceso se activará cuando se confirme el pago.'}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    } catch (exception) {
      if (mounted) {
        setState(() => error = 'No se pudo crear la solicitud: $exception');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _applyHeaderRow() {
    final parsed = int.tryParse(headerRowController.text.trim());
    final rows = analysis?.rows ?? const <List<String>>[];
    if (parsed == null || parsed < 1 || parsed > rows.length) {
      _showError('Indique una fila entre 1 y ${rows.length}.');
      return;
    }
    final header = rows[parsed - 1];
    if (header.every((cell) => cell.trim().isEmpty)) {
      _showError('La fila seleccionada no contiene encabezados.');
      return;
    }
    final oldByColumn = <int, CreatorDetectedField>{
      for (final field in fields) field.columnIndex: field,
    };
    final tableName = titleController.text.trim().isEmpty
        ? 'Registros'
        : titleController.text.trim();
    final rebuilt = <CreatorDetectedField>[];
    for (var column = 0; column < header.length; column++) {
      final label = header[column].trim();
      if (label.isEmpty) continue;
      final old = oldByColumn[column];
      rebuilt.add(CreatorDetectedField(
        originalLabel: label,
        correctedLabel: old == null || old.correctedLabel == old.originalLabel
            ? label
            : old.correctedLabel,
        columnIndex: column,
        tableName: old?.tableName ?? tableName,
        section: old?.section ?? 'Datos generales',
        uiType: old?.uiType ?? 'text',
        required: old?.required ?? false,
        visible: old?.visible ?? true,
        visibleInRecords: old?.visibleInRecords ?? true,
        included: old?.included ?? true,
        confidence: old?.confidence ?? .7,
        options: old?.options ?? const <String>[],
        notes:
            old?.notes ?? 'Campo derivado de la fila elegida por el usuario.',
      ));
    }
    setState(() {
      fields = rebuilt;
      error = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Fila $parsed aplicada: ${rebuilt.length} campos.')),
    );
  }

  Future<void> _addField() async {
    final label = TextEditingController();
    final table = TextEditingController(
      text: titleController.text.trim().isEmpty
          ? 'Registros'
          : titleController.text.trim(),
    );
    final section = TextEditingController(text: 'Datos generales');
    var uiType = 'text';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Agregar campo'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: label,
                  decoration: const InputDecoration(
                    labelText: 'Nombre correcto del campo *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: table,
                  decoration: const InputDecoration(
                    labelText: 'Tabla',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: section,
                  decoration: const InputDecoration(
                    labelText: 'Sección',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: uiType,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de campo',
                    border: OutlineInputBorder(),
                  ),
                  items: uiTypes.entries
                      .map((entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ))
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => uiType = value ?? 'text'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && label.text.trim().isNotEmpty && mounted) {
      setState(() {
        fields.add(CreatorDetectedField(
          originalLabel: '',
          correctedLabel: label.text.trim(),
          columnIndex: fields.isEmpty
              ? 0
              : fields.map((field) => field.columnIndex).reduce(
                        (left, right) => left > right ? left : right,
                      ) +
                  1,
          tableName:
              table.text.trim().isEmpty ? 'Registros' : table.text.trim(),
          section: section.text.trim().isEmpty
              ? 'Datos generales'
              : section.text.trim(),
          uiType: uiType,
          confidence: 1,
          notes: 'Campo agregado por el usuario.',
        ));
      });
    }
    label.dispose();
    table.dispose();
    section.dispose();
  }

  String? _metadataError() {
    if (titleController.text.trim().isEmpty) {
      return 'Escriba el nombre correcto del formato.';
    }
    if (selectedRubroId == null) return 'Seleccione un rubro.';
    if (selectedModuleId == null) return 'Seleccione el módulo de destino.';
    final row = int.tryParse(headerRowController.text.trim());
    if (row == null || row < 1 || row > (analysis?.rows.length ?? 0)) {
      return 'Revise el número de la fila de encabezados.';
    }
    return null;
  }

  String? _fieldsError() {
    final included = fields.where((field) => field.included).toList();
    if (included.isEmpty) return 'Mantenga al menos un campo.';
    if (included.any((field) => field.correctedLabel.trim().isEmpty)) {
      return 'Todos los campos incluidos necesitan un nombre correcto.';
    }
    final names = <String>{};
    for (final field in included) {
      final key = '${field.tableName}|${field.correctedLabel}'.toLowerCase();
      if (!names.add(key)) {
        return 'No repita el mismo nombre de campo dentro de una tabla.';
      }
    }
    return null;
  }

  Map<String, dynamic> _buildPayload() {
    return payloadBuilder.build(
      title: titleController.text.trim(),
      description: descriptionController.text.trim(),
      rubroId: selectedRubroId!,
      moduleId: selectedModuleId!,
      fields: fields,
      formLayout: formLayout,
      recordLayout: recordLayout,
      headerRow: int.parse(headerRowController.text.trim()),
      sourceName: document!.name,
      importId: importId,
      relationships: analysis?.relationships ?? const <Map<String, dynamic>>[],
    );
  }

  Future<void> _convertToDraft() async {
    final metadataError = _metadataError();
    final fieldsError = _fieldsError();
    if (metadataError != null || fieldsError != null) {
      _showError(metadataError ?? fieldsError!);
      return;
    }
    final payload = _buildPayload();
    final localErrors = validateFormatStructurePayload(payload);
    if (localErrors.isNotEmpty) {
      _showError(localErrors.join('\n'));
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final saved = await widget.repository.saveDraft(
        entityType: 'FORMATO',
        payload: payload,
      );
      final draftId = saved['id']?.toString();
      if (draftId == null) throw StateError('No se recibió el borrador.');
      final checked = await widget.repository.validateFormatStructure(draftId);
      if (importId != null) {
        await widget.repository.updateAiFormatImport(
          importId: importId!,
          status: 'GENERADA_IA',
          reviewedDefinition: payload,
          headerRow: int.parse(headerRowController.text.trim()),
          formLayout: formLayout.value,
          recordLayout: recordLayout.value,
          draftId: draftId,
          model: model,
        );
      }
      if (!mounted) return;
      setState(() {
        savedDraft = {
          ...saved,
          'definicion': payload,
          'validacion': checked,
        };
        validation = checked;
        busy = false;
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = 'No se pudo crear el borrador: $exception';
      });
    }
  }

  Future<void> _openDraftEditor() async {
    final draft = savedDraft;
    if (draft == null) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FormatStructureWizardPage(
          contextData: widget.contextData,
          initialDraft: draft,
          initialRubroId: selectedRubroId,
          repository: widget.repository,
        ),
      ),
    );
  }

  void _continue() {
    switch (currentStep) {
      case 0:
        if (document == null) {
          _showError('Tome una foto o seleccione un archivo.');
        } else {
          setState(() => currentStep = 1);
        }
      case 1:
        if (analysis == null) {
          _analyze();
        } else {
          setState(() => currentStep = 2);
        }
      case 2:
        final problem = _metadataError();
        if (problem != null) {
          _showError(problem);
        } else {
          setState(() => currentStep = 3);
        }
      case 3:
        final problem = _fieldsError();
        if (problem != null) {
          _showError(problem);
        } else {
          setState(() => currentStep = 4);
        }
      case 4:
        setState(() => currentStep = 5);
      case 5:
        _convertToDraft();
    }
  }

  bool _canTapStep(int step) {
    if (step <= currentStep) return true;
    if (analysis == null) return false;
    return step <= 5;
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => error = message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Documento → App'),
        bottom: busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _statusBanner(),
            Expanded(
              child: Stepper(
                type: StepperType.vertical,
                currentStep: currentStep,
                onStepTapped: busy
                    ? null
                    : (step) {
                        if (_canTapStep(step)) {
                          setState(() => currentStep = step);
                        }
                      },
                controlsBuilder: (context, details) => _controls(),
                steps: [
                  Step(
                    title: const Text('1. Motor, foto, imagen o PDF'),
                    subtitle: const Text(
                      'Elija Básico o Avanzado antes de subir el registro',
                    ),
                    isActive: currentStep >= 0,
                    state: document == null
                        ? StepState.indexed
                        : StepState.complete,
                    content: _sourceStep(),
                  ),
                  Step(
                    title: const Text('2. Calidad y análisis'),
                    subtitle:
                        const Text('Rechaza imágenes borrosas o ilegibles'),
                    isActive: currentStep >= 1,
                    state: quality?.acceptable == false
                        ? StepState.error
                        : analysis == null
                            ? StepState.indexed
                            : StepState.complete,
                    content: _qualityStep(),
                  ),
                  Step(
                    title: const Text('3. Encabezados y destino'),
                    subtitle:
                        const Text('Confirme la fila y los datos correctos'),
                    isActive: currentStep >= 2,
                    state: analysis == null
                        ? StepState.disabled
                        : currentStep > 2
                            ? StepState.complete
                            : StepState.indexed,
                    content: _headerStep(),
                  ),
                  Step(
                    title: const Text('4. Campos detectados'),
                    subtitle:
                        const Text('Corrija, agregue o descarte sugerencias'),
                    isActive: currentStep >= 3,
                    state: currentStep > 3
                        ? StepState.complete
                        : StepState.indexed,
                    content: _fieldsStep(),
                  ),
                  Step(
                    title: const Text('5. Diseño de la app'),
                    subtitle: const Text('Elija captura y vista de registros'),
                    isActive: currentStep >= 4,
                    state: currentStep > 4
                        ? StepState.complete
                        : StepState.indexed,
                    content: _layoutStep(),
                  ),
                  Step(
                    title: const Text('6. Vista previa y borrador'),
                    subtitle: const Text('Revise antes de convertir'),
                    isActive: currentStep >= 5,
                    state: savedDraft == null
                        ? StepState.indexed
                        : StepState.complete,
                    content: _previewStep(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBanner() {
    if (error == null && savedDraft == null) return const SizedBox.shrink();
    final success = savedDraft != null;
    return Container(
      width: double.infinity,
      color: success ? const Color(0xFFE6F5EE) : const Color(0xFFFFECEA),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(
        children: [
          Icon(
            success ? Icons.check_circle_outline : Icons.error_outline,
            color: success ? const Color(0xFF0C7A5B) : const Color(0xFFB3261E),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              success
                  ? 'Borrador GENERADA_IA creado. Todavía requiere revisión y aprobación administrativa.'
                  : error!,
            ),
          ),
          if (!success)
            IconButton(
              tooltip: 'Cerrar',
              onPressed: () => setState(() => error = null),
              icon: const Icon(Icons.close),
            ),
        ],
      ),
    );
  }

  Widget _controls() {
    final isLast = currentStep == 5;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed:
                busy || (isLast && savedDraft != null) ? null : _continue,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(isLast
                    ? Icons.auto_awesome_outlined
                    : currentStep == 1 && analysis == null
                        ? Icons.document_scanner_outlined
                        : Icons.arrow_forward),
            label: Text(isLast
                ? 'Crear borrador en Zumac Creator'
                : currentStep == 1 && analysis == null
                    ? 'Analizar documento'
                    : 'Continuar'),
          ),
          if (currentStep > 0)
            OutlinedButton(
              onPressed: busy ? null : () => setState(() => currentStep--),
              child: const Text('Atrás'),
            ),
          if (savedDraft != null)
            FilledButton.tonalIcon(
              onPressed: _openDraftEditor,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Abrir en el editor'),
            ),
        ],
      ),
    );
  }

  Widget _sourceStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Primero elige cómo quieres analizar el documento.',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        const Text(
          'Puedes usar gratis el motor propio de Zumac o elegir el análisis avanzado cuando el documento sea más complejo.',
          style: TextStyle(color: Color(0xFF60758A), fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        _analysisEngineSelector(),
        const SizedBox(height: 18),
        const Divider(),
        const SizedBox(height: 10),
        const Text(
          'Use buena luz, mantenga el celular paralelo al documento y asegúrese de que ningún borde quede cortado. La iluminación y el enfoque importan más que tener un equipo costoso.',
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.tonalIcon(
              onPressed: busy ? null : _pickCamera,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Tomar foto'),
            ),
            FilledButton.tonalIcon(
              onPressed: busy ? null : _pickGallery,
              icon: const Icon(Icons.image_outlined),
              label: const Text('Subir imagen'),
            ),
            FilledButton.tonalIcon(
              onPressed: busy ? null : _pickPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Subir PDF'),
            ),
          ],
        ),
        if (document != null) ...[
          const SizedBox(height: 16),
          _documentCard(),
        ],
      ],
    );
  }

  Widget _documentCard() {
    final selected = document!;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              height: 110,
              child: selected.sourceType == CreatorSourceType.pdf
                  ? const ColoredBox(
                      color: Color(0xFFFFECEA),
                      child: Icon(Icons.picture_as_pdf, size: 52),
                    )
                  : Image.memory(
                      selected.bytes,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selected.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                      '${selected.mimeType} · ${_fileSize(selected.bytes.length)}'),
                  const SizedBox(height: 6),
                  const Text(
                    'El archivo original se procesa en memoria; Zumac conserva el hash y la revisión, no el binario.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF60758A)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _qualityStep() {
    final report = quality;
    if (report == null) {
      return const Text('Primero seleccione un documento.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: report.acceptable
                ? const Color(0xFFE6F5EE)
                : const Color(0xFFFFECEA),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                report.acceptable
                    ? Icons.check_circle_outline
                    : Icons.blur_on_outlined,
                color: report.acceptable
                    ? const Color(0xFF0C7A5B)
                    : const Color(0xFFB3261E),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.summary,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    for (final reason in report.reasons)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text('• $reason'),
                      ),
                    for (final warning in report.warnings)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text('• $warning'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (report.metrics.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: report.metrics.entries
                .map((entry) => Chip(
                      label: Text(
                        '${entry.key}: ${entry.value.toStringAsFixed(entry.key == 'ancho' || entry.key == 'alto' ? 0 : 1)}',
                      ),
                    ))
                .toList(),
          ),
        ],
        if (!report.acceptable) ...[
          const SizedBox(height: 12),
          const Text(
            'La conversión está bloqueada para evitar crear campos incorrectos. Vuelva al paso 1 y cargue otra imagen.',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
        if (busy) ...[
          const SizedBox(height: 14),
          const Text(
              'Zumac está leyendo filas, encabezados, campos y relaciones…'),
        ],
      ],
    );
  }

  Widget _analysisEngineSelector() {
    final remaining =
        num.tryParse('${aiSubscription['creditos_restantes'] ?? 0}') ?? 0;

    Widget engineCard({
      required String value,
      required IconData icon,
      required String title,
      required String badge,
      required String subtitle,
      required bool enabled,
    }) {
      final selected = analysisEngine == value;
      return Expanded(
        child: Opacity(
          opacity: enabled ? 1 : .55,
          child: Material(
            color: selected ? const Color(0xFFE5F2F5) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: busy || !enabled
                  ? null
                  : () {
                      setState(() {
                        analysisEngine = value;
                        analysis = null;
                        fields = <CreatorDetectedField>[];
                        model = null;
                        error = null;
                      });
                    },
              child: Container(
                constraints: const BoxConstraints(minHeight: 132),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF176B87)
                        : const Color(0xFFD4E3E8),
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, color: const Color(0xFF176B87)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFF176B87)
                                : const Color(0xFFEAF1F4),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              color: selected
                                  ? Colors.white
                                  : const Color(0xFF40576A),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (selected)
                          const Icon(
                            Icons.check_circle,
                            color: Color(0xFF0C7A5B),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF60758A),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Motor de análisis',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final cards = <Widget>[
              engineCard(
                value: 'ZUMAC',
                icon: Icons.psychology_alt_outlined,
                title: 'Básico',
                badge: 'GRATIS',
                subtitle:
                    'Usa Zumac AI Engine, nuestro motor propio. Lee fotos y PDF nítidos, detecta encabezados, campos y estructuras comunes. Es gratuito y no consume créditos; puede requerir más correcciones en documentos complejos, manuscritos o ambiguos.',
                enabled: true,
              ),
              engineCard(
                value: 'OPENAI',
                icon: Icons.auto_awesome_outlined,
                title: 'Avanzado',
                badge: _hasAdvancedCredits ? 'ACTIVO' : 'CON COSTO',
                subtitle: !advancedAiEnabled
                    ? 'La empresa no tiene habilitado este servicio. Un administrador puede autorizarlo desde la configuración de productos.'
                    : _hasAdvancedCredits
                        ? 'Usa OpenAI para interpretar mejor diseños complejos, tablas irregulares, encabezados ambiguos y relaciones entre campos. Tienes $remaining créditos exclusivos para tu usuario.'
                        : 'Obtiene una interpretación visual y contextual más precisa en documentos complejos. Requiere adquirir un plan mensual o anual antes del análisis.',
                enabled: advancedAiEnabled,
              ),
            ];
            if (constraints.maxWidth < 680 || cards.length == 1) {
              return Column(
                children: [
                  for (var index = 0; index < cards.length; index++) ...[
                    if (index > 0) const SizedBox(height: 10),
                    Row(children: [cards[index]]),
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                cards.first,
                const SizedBox(width: 10),
                cards.last,
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _headerStep() {
    final parsed = analysis;
    if (parsed == null) {
      return const Text('Analice el documento para continuar.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (parsed.warnings.isNotEmpty || parsed.questions.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF6DE),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Puntos que requieren revisión',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                for (final item in [...parsed.warnings, ...parsed.questions])
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('• $item'),
                  ),
              ],
            ),
          ),
        TextField(
          controller: titleController,
          decoration: const InputDecoration(
            labelText: 'Nombre correcto del formato *',
            helperText:
                'Puede reemplazar libremente el nombre sugerido por la IA.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: descriptionController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Descripción',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 250,
              child: DropdownButtonFormField<String>(
                initialValue: _rubros.any(
                  (row) => row['id']?.toString() == selectedRubroId,
                )
                    ? selectedRubroId
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Rubro *',
                  border: OutlineInputBorder(),
                ),
                items: _rubros
                    .map((row) => DropdownMenuItem(
                          value: row['id']?.toString(),
                          child: Text(row['nombre']?.toString() ?? 'Rubro'),
                        ))
                    .toList(),
                onChanged: busy
                    ? null
                    : (value) {
                        setState(() {
                          selectedRubroId = value;
                          final modules = _availableModules;
                          selectedModuleId =
                              modules.isEmpty ? null : _moduleId(modules.first);
                        });
                      },
              ),
            ),
            SizedBox(
              width: 290,
              child: DropdownButtonFormField<String>(
                key: ValueKey('module-$selectedRubroId-$selectedModuleId'),
                initialValue: _availableModules
                        .any((row) => _moduleId(row) == selectedModuleId)
                    ? selectedModuleId
                    : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Módulo de destino *',
                  border: const OutlineInputBorder(),
                  suffixIcon: loadingModules
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                ),
                items: _availableModules
                    .map((row) => DropdownMenuItem(
                          value: _moduleId(row),
                          child: Text(row['nombre']?.toString() ?? 'Módulo'),
                        ))
                    .toList(),
                onChanged: loadingModules
                    ? null
                    : (value) => setState(() => selectedModuleId = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Text(
          '¿En qué número de fila están los encabezados?',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 150,
              child: TextField(
                controller: headerRowController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Fila',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.tonal(
              onPressed: _applyHeaderRow,
              child: const Text('Aplicar fila'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _rowsTable(parsed.rows),
      ],
    );
  }

  Widget _rowsTable(List<List<String>> rows) {
    if (rows.isEmpty) return const Text('No hay filas para mostrar.');
    final columns = rows.fold<int>(
      0,
      (maximum, row) => row.length > maximum ? row.length : maximum,
    );
    final selectedHeader = int.tryParse(headerRowController.text.trim());
    return Container(
      constraints: const BoxConstraints(maxHeight: 360),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD7E0E8)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              headingRowHeight: 42,
              columns: [
                const DataColumn(label: Text('Fila')),
                for (var index = 0; index < columns; index++)
                  DataColumn(label: Text('Col. ${index + 1}')),
              ],
              rows: rows.asMap().entries.map((entry) {
                final isHeader = entry.key + 1 == selectedHeader;
                return DataRow(
                  color: isHeader
                      ? WidgetStateProperty.all(const Color(0xFFE6F5EE))
                      : null,
                  cells: [
                    DataCell(Text(
                      '${entry.key + 1}${isHeader ? ' · ENCABEZADOS' : ''}',
                      style: TextStyle(
                        fontWeight:
                            isHeader ? FontWeight.w800 : FontWeight.w500,
                      ),
                    )),
                    for (var column = 0; column < columns; column++)
                      DataCell(Text(
                        column < entry.value.length ? entry.value[column] : '',
                      )),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldsStep() {
    if (fields.isEmpty) return const Text('No hay campos detectados.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Todo sigue siendo sugerido por IA. Confirme especialmente los campos con baja confianza y escriba el nombre correcto cuando sea necesario.',
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < fields.length; index++) _fieldEditor(index),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _addField,
            icon: const Icon(Icons.add),
            label: const Text('Agregar campo faltante'),
          ),
        ),
      ],
    );
  }

  Widget _fieldEditor(int index) {
    final field = fields[index];
    final lowConfidence = field.confidence < .75;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    field.originalLabel.isEmpty
                        ? 'Agregado por el usuario'
                        : 'Detectado: “${field.originalLabel}”',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Chip(
                  backgroundColor: lowConfidence
                      ? const Color(0xFFFFF0CF)
                      : const Color(0xFFE6F5EE),
                  label: Text(
                    '${(field.confidence * 100).round()}% confianza',
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: field.included,
                  onChanged: (value) => setState(() {
                    fields[index] = field.copyWith(included: value);
                  }),
                ),
              ],
            ),
            if (lowConfidence)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  'Revise este nombre: la lectura no fue completamente segura.',
                  style: TextStyle(color: Color(0xFF8A6815)),
                ),
              ),
            if (field.included) ...[
              TextFormField(
                key: ValueKey('label-$index-${field.originalLabel}'),
                initialValue: field.correctedLabel,
                decoration: const InputDecoration(
                  labelText: 'Nombre correcto *',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  fields[index] = fields[index].copyWith(correctedLabel: value);
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: 230,
                    child: TextFormField(
                      initialValue: field.tableName,
                      decoration: const InputDecoration(
                        labelText: 'Tabla',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        fields[index] =
                            fields[index].copyWith(tableName: value);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 230,
                    child: TextFormField(
                      initialValue: field.section,
                      decoration: const InputDecoration(
                        labelText: 'Sección',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        fields[index] = fields[index].copyWith(section: value);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 230,
                    child: DropdownButtonFormField<String>(
                      initialValue: field.uiType,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Tipo',
                        border: OutlineInputBorder(),
                      ),
                      items: uiTypes.entries
                          .map((entry) => DropdownMenuItem(
                                value: entry.key,
                                child: Text(entry.value),
                              ))
                          .toList(),
                      onChanged: (value) => setState(() {
                        fields[index] =
                            fields[index].copyWith(uiType: value ?? 'text');
                      }),
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 4,
                children: [
                  CheckboxMenuButton(
                    value: field.required,
                    onChanged: (value) => setState(() {
                      fields[index] =
                          fields[index].copyWith(required: value == true);
                    }),
                    child: const Text('Obligatorio'),
                  ),
                  CheckboxMenuButton(
                    value: field.visibleInRecords,
                    onChanged: (value) => setState(() {
                      fields[index] = fields[index]
                          .copyWith(visibleInRecords: value == true);
                    }),
                    child: const Text('Mostrar en registros'),
                  ),
                ],
              ),
              if (field.options.isNotEmpty)
                Text(
                  'Opciones detectadas: ${field.options.join(', ')}',
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF60758A)),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _layoutStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Diseño para capturar datos',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: CreatorFormLayout.values
              .map((layout) => _layoutCard(
                    selected: formLayout == layout,
                    icon: switch (layout) {
                      CreatorFormLayout.vertical => Icons.view_agenda_outlined,
                      CreatorFormLayout.twoColumns =>
                        Icons.view_column_outlined,
                      CreatorFormLayout.sections => Icons.segment_outlined,
                      CreatorFormLayout.compact => Icons.density_small_outlined,
                    },
                    label: layout.label,
                    onTap: () => setState(() => formLayout = layout),
                  ))
              .toList(),
        ),
        const SizedBox(height: 20),
        const Text(
          'Diseño para consultar registros',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: CreatorRecordLayout.values
              .map((layout) => _layoutCard(
                    selected: recordLayout == layout,
                    icon: switch (layout) {
                      CreatorRecordLayout.table => Icons.table_rows_outlined,
                      CreatorRecordLayout.cards => Icons.view_module_outlined,
                      CreatorRecordLayout.list => Icons.view_list_outlined,
                    },
                    label: layout.label,
                    onTap: () => setState(() => recordLayout = layout),
                  ))
              .toList(),
        ),
        const SizedBox(height: 18),
        _formPreview(),
      ],
    );
  }

  Widget _layoutCard({
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 180,
      child: Card(
        color: selected ? const Color(0xFFE6F5EE) : null,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: selected ? const Color(0xFF0C7A5B) : const Color(0xFFD7E0E8),
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(icon, size: 34, color: const Color(0xFF176B87)),
                const SizedBox(height: 8),
                Text(label, textAlign: TextAlign.center),
                if (selected)
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(Icons.check_circle, color: Color(0xFF0C7A5B)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _previewStep() {
    if (analysis == null) return const Text('Complete el análisis primero.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF6DE),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Esta vista no publica nada. Al convertir se crea un borrador GENERADA_IA que un administrador debe revisar y aprobar.',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          titleController.text.trim(),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        Text(
          '${_selectedModuleName()} · ${fields.where((field) => field.included).length} campos',
          style: const TextStyle(color: Color(0xFF60758A)),
        ),
        const SizedBox(height: 16),
        DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'Formulario'),
                  Tab(text: 'Registros'),
                ],
              ),
              SizedBox(
                height: 440,
                child: TabBarView(
                  children: [
                    SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: _formPreview(),
                    ),
                    SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: _recordsPreview(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (validation != null) ...[
          const SizedBox(height: 12),
          Text(
            validation!['valido'] == true
                ? 'La estructura pasó la validación técnica.'
                : 'El borrador fue creado, pero todavía tiene observaciones técnicas.',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: validation!['valido'] == true
                  ? const Color(0xFF0C7A5B)
                  : const Color(0xFF8A6815),
            ),
          ),
        ],
      ],
    );
  }

  Widget _formPreview() {
    final included = fields.where((field) => field.included).toList();
    if (included.isEmpty) {
      return const Text('No hay campos para previsualizar.');
    }
    if (formLayout == CreatorFormLayout.sections) {
      final grouped = <String, List<CreatorDetectedField>>{};
      for (final field in included) {
        grouped
            .putIfAbsent(
              field.section.trim().isEmpty ? 'Datos generales' : field.section,
              () => <CreatorDetectedField>[],
            )
            .add(field);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: grouped.entries
            .map((entry) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(entry.key,
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        const Divider(),
                        for (final field in entry.value) _previewField(field),
                      ],
                    ),
                  ),
                ))
            .toList(),
      );
    }
    if (formLayout == CreatorFormLayout.twoColumns) {
      return LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 10,
          runSpacing: 10,
          children: included
              .map((field) => SizedBox(
                    width: constraints.maxWidth < 560
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 10) / 2,
                    child: _previewField(field),
                  ))
              .toList(),
        ),
      );
    }
    if (formLayout == CreatorFormLayout.compact) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: included
            .map((field) => InputChip(
                  avatar: Icon(_fieldIcon(field.uiType), size: 18),
                  label: Text(field.correctedLabel),
                  onPressed: () {},
                ))
            .toList(),
      );
    }
    return Column(children: included.map(_previewField).toList());
  }

  Widget _previewField(CreatorDetectedField field) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: '${field.correctedLabel}${field.required ? ' *' : ''}',
          prefixIcon: Icon(_fieldIcon(field.uiType)),
          border: const OutlineInputBorder(),
        ),
        child: Text(
          uiTypes[field.uiType] ?? 'Texto',
          style: const TextStyle(color: Color(0xFF60758A)),
        ),
      ),
    );
  }

  Widget _recordsPreview() {
    final visible = fields
        .where((field) => field.included && field.visibleInRecords)
        .toList();
    final rowStart = int.tryParse(headerRowController.text.trim()) ?? 1;
    final rows = (analysis?.rows ?? const <List<String>>[])
        .skip(rowStart)
        .take(4)
        .toList();
    if (visible.isEmpty) {
      return const Text('No hay campos visibles en registros.');
    }
    if (recordLayout == CreatorRecordLayout.table) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: visible
              .map((field) => DataColumn(label: Text(field.correctedLabel)))
              .toList(),
          rows: rows.isEmpty
              ? [
                  DataRow(
                    cells:
                        visible.map((_) => const DataCell(Text('—'))).toList(),
                  )
                ]
              : rows
                  .map((row) => DataRow(
                        cells: visible
                            .map((field) => DataCell(Text(
                                  field.columnIndex < row.length
                                      ? row[field.columnIndex]
                                      : '',
                                )))
                            .toList(),
                      ))
                  .toList(),
        ),
      );
    }
    final previewRows = rows.isEmpty ? <List<String>>[const <String>[]] : rows;
    return Column(
      children: previewRows.map((row) {
        if (recordLayout == CreatorRecordLayout.list) {
          return ListTile(
            leading:
                const CircleAvatar(child: Icon(Icons.description_outlined)),
            title: Text(_recordValue(visible.first, row).isEmpty
                ? 'Nuevo registro'
                : _recordValue(visible.first, row)),
            subtitle: Text(visible.skip(1).take(2).map((field) {
              return '${field.correctedLabel}: ${_recordValue(field, row)}';
            }).join(' · ')),
          );
        }
        return Card(
          margin: const EdgeInsets.only(bottom: 9),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: visible
                  .map((field) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${field.correctedLabel}: ${_recordValue(field, row)}',
                        ),
                      ))
                  .toList(),
            ),
          ),
        );
      }).toList(),
    );
  }

  String _recordValue(CreatorDetectedField field, List<String> row) =>
      field.columnIndex < row.length ? row[field.columnIndex] : '';

  IconData _fieldIcon(String type) => switch (type) {
        'number' || 'integer' || 'percent' => Icons.numbers_outlined,
        'date' || 'datetime' => Icons.calendar_today_outlined,
        'time' => Icons.schedule_outlined,
        'checkbox' || 'switch' => Icons.check_box_outlined,
        'dropdown' || 'multiselect' => Icons.arrow_drop_down_circle_outlined,
        'photo' => Icons.photo_camera_outlined,
        'signature' => Icons.draw_outlined,
        'qr_scan' || 'barcode_scan' => Icons.qr_code_scanner_outlined,
        'email' => Icons.email_outlined,
        'phone' => Icons.phone_outlined,
        _ => Icons.short_text,
      };

  String _selectedModuleName() {
    for (final module in moduleTemplates) {
      if (_moduleId(module) == selectedModuleId) {
        return module['nombre']?.toString() ?? 'Módulo';
      }
    }
    return 'Módulo pendiente';
  }

  String? _moduleId(Map<String, dynamic> row) =>
      row['entidad_origen_id']?.toString() ?? row['codigo']?.toString();

  String _sourceTypeValue(CreatorSourceType type) => switch (type) {
        CreatorSourceType.camera => 'CAMARA',
        CreatorSourceType.gallery => 'GALERIA',
        CreatorSourceType.pdf => 'PDF',
      };

  String _imageMime(String name) {
    final extension = name.toLowerCase().split('.').last;
    return switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
  }

  String _fileSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false)
      : const <Map<String, dynamic>>[];

  List<String> _strings(dynamic value) => value is List
      ? value.map((item) => item.toString()).toList(growable: false)
      : const <String>[];
}

class _CreatorPickedDocument {
  const _CreatorPickedDocument({
    required this.name,
    required this.mimeType,
    required this.bytes,
    required this.sourceType,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;
  final CreatorSourceType sourceType;
}
