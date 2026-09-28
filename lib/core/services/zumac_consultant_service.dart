import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'knowledge_retrieval_engine.dart';
import 'local_db.dart';
import 'soft_delete.dart';

enum ZumacConsultantIntent {
  knowledge,
  phThreshold,
  absences,
  attendance,
  crossTable,
  generalSearch,
}

class ZumacConsultantReportColumn {
  final String key;
  final String label;

  const ZumacConsultantReportColumn({
    required this.key,
    required this.label,
  });
}

class ZumacConsultantReportTable {
  final String title;
  final String tableName;
  final List<ZumacConsultantReportColumn> columns;
  final List<Map<String, String>> rows;
  final int totalRows;
  final String? moduleId;
  final String? formatId;

  const ZumacConsultantReportTable({
    required this.title,
    required this.tableName,
    required this.columns,
    required this.rows,
    required this.totalRows,
    this.moduleId,
    this.formatId,
  });

  bool get canOpen =>
      moduleId?.isNotEmpty == true && formatId?.isNotEmpty == true;
}

class ZumacConsultantFinding {
  final String title;
  final String detail;
  final String tableName;
  final String? moduleId;
  final String? formatId;
  final String? recordField;
  final String? recordValue;
  final Map<String, dynamic> values;

  const ZumacConsultantFinding({
    required this.title,
    required this.detail,
    required this.tableName,
    this.moduleId,
    this.formatId,
    this.recordField,
    this.recordValue,
    this.values = const <String, dynamic>{},
  });

  bool get canReview =>
      moduleId?.isNotEmpty == true && formatId?.isNotEmpty == true;
}

/// Formato de referencia relacionado con la consulta, pero que no representa
/// un resultado operativo. Se muestra como acceso opcional "Quizá te interesa".
class ZumacConsultantRelatedTable {
  final String title;
  final String tableName;
  final String? moduleId;
  final String? formatId;

  const ZumacConsultantRelatedTable({
    required this.title,
    required this.tableName,
    this.moduleId,
    this.formatId,
  });

  bool get canOpen =>
      moduleId?.isNotEmpty == true && formatId?.isNotEmpty == true;
}

enum ZumacConsultantOptionKind { source, period, followUp }

/// Opción contextual que permite precisar una consulta sin convertir el chat
/// en un formulario. [sourceTable] se utiliza internamente y nunca se muestra
/// como identificador técnico al usuario.
class ZumacConsultantOption {
  const ZumacConsultantOption({
    required this.label,
    required this.query,
    required this.kind,
    this.sourceTable,
  });

  final String label;
  final String query;
  final ZumacConsultantOptionKind kind;
  final String? sourceTable;
}

class ZumacConsultantResult {
  final String question;
  final String answer;
  final ZumacConsultantIntent intent;
  final List<ZumacConsultantFinding> findings;
  final List<ZumacConsultantReportTable> reportTables;
  final List<ZumacConsultantRelatedTable> relatedTables;
  final int inspectedRecords;
  final List<KnowledgeCitation> citations;
  final List<String> relatedConcepts;
  final List<String> inspectedKnowledgeSources;
  final List<ZumacConsultantOption> options;
  final List<String> detailLines;
  final String? followUpPrompt;

  const ZumacConsultantResult({
    required this.question,
    required this.answer,
    required this.intent,
    required this.findings,
    this.reportTables = const <ZumacConsultantReportTable>[],
    this.relatedTables = const <ZumacConsultantRelatedTable>[],
    required this.inspectedRecords,
    this.citations = const <KnowledgeCitation>[],
    this.relatedConcepts = const <String>[],
    this.inspectedKnowledgeSources = const <String>[],
    this.options = const <ZumacConsultantOption>[],
    this.detailLines = const <String>[],
    this.followUpPrompt,
  });

  bool get needsClarification => options.isNotEmpty;
}

class _OperationalConversationContext {
  String? baseQuestion;
  String? selectedTable;
  String? selectedLabel;
}

class _ConsultantPeriod {
  final DateTime start;
  final DateTime endExclusive;
  final String label;
  final bool isToday;

  const _ConsultantPeriod({
    required this.start,
    required this.endExclusive,
    required this.label,
    this.isToday = false,
  });
}

class _CrossTableResult {
  final ZumacConsultantIntent intent;
  final List<ZumacConsultantFinding> findings;
  final String kind;
  final int? attendanceCount;
  final int? workLogCount;
  final int? unmatchedCount;
  final bool workLogWithoutAttendance;

  const _CrossTableResult({
    required this.intent,
    required this.findings,
    required this.kind,
    this.attendanceCount,
    this.workLogCount,
    this.unmatchedCount,
    this.workLogWithoutAttendance = false,
  });
}

/// Consultor empresarial híbrido para conocimiento y datos operativos.
///
/// Las preguntas conceptuales se delegan al motor de recuperación con citas.
/// Las preguntas operativas se resuelven sobre formatos configurados, memoria
/// de conversación y periodos detectados; nunca dependen de respuestas fijas.
class ZumacConsultantService {
  static const Duration _remoteTableTimeout = Duration(seconds: 7);
  static const int _defaultRemoteCandidateLimit = 4;

  final LocalDb local;
  final Future<List<Map<String, dynamic>>> Function(String table) remoteLoader;
  final KnowledgeRetrievalEngine knowledgeEngine;
  final bool _usesDefaultRemoteLoader;
  final Map<String, String> _lastOperationalQuestion = {};
  final Map<String, _OperationalConversationContext> _operationalContexts = {};

  ZumacConsultantService({
    LocalDb? localDb,
    Future<List<Map<String, dynamic>>> Function(String table)? remoteLoader,
    KnowledgeRetrievalEngine? knowledgeRetrievalEngine,
  })  : local = localDb ?? LocalDb.instance,
        remoteLoader = remoteLoader ?? _loadRemoteTable,
        _usesDefaultRemoteLoader = remoteLoader == null,
        knowledgeEngine =
            knowledgeRetrievalEngine ?? KnowledgeRetrievalEngine.supabase();

  static Future<List<Map<String, dynamic>>> _loadRemoteTable(
    String table,
  ) async {
    final client = Supabase.instance.client;
    const pageSize = 500;
    const maxRows = 2000;
    final rows = <Map<String, dynamic>>[];
    for (var from = 0; from < maxRows; from += pageSize) {
      final page = await client
          .from(table)
          .select()
          .range(from, from + pageSize - 1)
          .timeout(_remoteTableTimeout);
      final mapped = List<Map<String, dynamic>>.from(page);
      rows.addAll(mapped.where((row) => !isSoftDeletedAppgtRow(row)));
      if (mapped.length < pageSize) break;
    }
    return rows;
  }

  /// Responde una pregunta y conserva el contexto asociado a [conversationId].
  ///
  /// La consulta remota usa un número acotado de tablas, filtros de periodo y
  /// tiempos máximos para impedir que una fuente lenta deje la interfaz cargando.
  Future<ZumacConsultantResult> ask(
    String rawQuestion, {
    String conversationId = 'default',
    String? selectedSourceTable,
  }) async {
    final question = rawQuestion.trim();
    if (question.isEmpty) {
      return const ZumacConsultantResult(
        question: '',
        answer: 'Escribe una pregunta para consultar los datos de Zumac.',
        intent: ZumacConsultantIntent.generalSearch,
        findings: <ZumacConsultantFinding>[],
        inspectedRecords: 0,
      );
    }

    if (selectedSourceTable == null &&
        _looksLikeKnowledgeQuestion(question, conversationId)) {
      final knowledge = await knowledgeEngine.ask(
        question,
        conversationId: conversationId,
      );
      return ZumacConsultantResult(
        question: question,
        answer: knowledge.answer,
        intent: ZumacConsultantIntent.knowledge,
        findings: const <ZumacConsultantFinding>[],
        inspectedRecords: 0,
        citations: knowledge.citations,
        relatedConcepts: knowledge.relatedConcepts,
        inspectedKnowledgeSources: knowledge.inspectedSources,
        followUpPrompt:
            '¿Quieres que lo relacione con otro proceso o formato de la empresa?',
      );
    }

    final conversation = _operationalContexts.putIfAbsent(
      conversationId,
      _OperationalConversationContext.new,
    );
    if (selectedSourceTable != null && selectedSourceTable.trim().isNotEmpty) {
      conversation.selectedTable = selectedSourceTable.trim();
    }
    var contextualQuestion = _contextualizeOperationalQuestion(
      conversationId,
      question,
    );
    if (selectedSourceTable != null &&
        (conversation.baseQuestion ?? '').isNotEmpty) {
      contextualQuestion = conversation.baseQuestion!;
    }
    final normalized = _normalize(contextualQuestion);
    var intent = _intentFor(normalized);
    final threshold = _numericThreshold(normalized);
    final period = _periodFor(normalized);
    final requestedLots = _requestedLots(normalized);

    // Estas lecturas son independientes. En móvil, abrir SQLite siete veces en
    // serie hacía perceptible la espera antes de iniciar siquiera la consulta.
    final localData = await Future.wait<dynamic>([
      _safeLocalRows('local_form_fields'),
      _safeLocalRows('local_formats'),
      _safeLocalRows('local_format_tables'),
      _safeLocalRows('local_modules'),
      _safeLocalRows('local_sections'),
      local.matrixSourceTables(),
      local.allRecords(),
    ]);
    final fields = localData[0] as List<Map<String, dynamic>>;
    final formats = localData[1] as List<Map<String, dynamic>>;
    final formatTables = localData[2] as List<Map<String, dynamic>>;
    final modules = localData[3] as List<Map<String, dynamic>>;
    final sections = localData[4] as List<Map<String, dynamic>>;
    final sourceTables = localData[5] as List<String>;
    final pendingRecords = localData[6] as List<Map<String, dynamic>>;

    final metadataByTable = <String, List<Map<String, dynamic>>>{};
    for (final field in fields) {
      final table = field['tabla_destino']?.toString().trim() ?? '';
      if (table.isEmpty) continue;
      metadataByTable.putIfAbsent(table, () => []).add(field);
    }
    _augmentSearchMetadata(
      metadataByTable: metadataByTable,
      formats: formats,
      formatTables: formatTables,
      modules: modules,
      sections: sections,
    );

    final formatByTable = _formatMetadataByTable(
      formats: formats,
      formatTables: formatTables,
      modules: modules,
    );
    final allCandidates = _candidateTables(
      question: normalized,
      intent: intent,
      sourceTables: sourceTables,
      metadataByTable: metadataByTable,
      pendingRecords: pendingRecords,
    );
    final separatesReferenceCatalogs =
        _isAttendanceDomainQuestion(normalized, intent);
    final relatedTables = separatesReferenceCatalogs
        ? _relatedReferenceTables(
            question: normalized,
            formatByTable: formatByTable,
          )
        : const <ZumacConsultantRelatedTable>[];
    var candidates = separatesReferenceCatalogs
        ? allCandidates
            .where(
              (table) => !_isReferenceCatalogTable(table, formatByTable),
            )
            .toList(growable: false)
        : allCandidates;
    final explicitSource = _explicitCandidateSource(
      normalized,
      candidates,
      formatByTable,
    );
    if (explicitSource != null) {
      conversation.selectedTable = explicitSource;
    }
    if ((conversation.selectedTable ?? '').isNotEmpty) {
      conversation.selectedLabel =
          _sourceLabel(conversation.selectedTable, formatByTable);
    }
    if ((conversation.selectedTable ?? '').isNotEmpty &&
        candidates.contains(conversation.selectedTable)) {
      candidates = <String>[conversation.selectedTable!];
    }

    if (intent == ZumacConsultantIntent.phThreshold) {
      final sourceOptions = _sourceClarificationOptions(
        allCandidates,
        formatByTable,
      );
      if ((conversation.selectedTable ?? '').isEmpty &&
          sourceOptions.length > 1) {
        conversation.baseQuestion = contextualQuestion;
        _lastOperationalQuestion[conversationId] = contextualQuestion;
        return ZumacConsultantResult(
          question: question,
          answer: '¿A qué registro te refieres?',
          intent: intent,
          findings: const <ZumacConsultantFinding>[],
          inspectedRecords: 0,
          options: sourceOptions,
          followUpPrompt:
              'Selecciona un registro para que Zumac consulte solo esa fuente.',
        );
      }
      if ((conversation.selectedTable ?? '').isEmpty &&
          sourceOptions.length == 1) {
        conversation
          ..selectedTable = sourceOptions.first.sourceTable
          ..selectedLabel = sourceOptions.first.label;
        candidates = <String>[sourceOptions.first.sourceTable!];
      }
      if (period == null) {
        conversation.baseQuestion ??= contextualQuestion;
        _lastOperationalQuestion[conversationId] = conversation.baseQuestion!;
        final sourceName = conversation.selectedLabel ??
            _sourceLabel(conversation.selectedTable, formatByTable);
        return ZumacConsultantResult(
          question: question,
          answer: sourceName.isEmpty
              ? '¿En qué fecha o rango de fechas quieres consultar?'
              : 'Revisaré $sourceName. ¿En qué fecha o rango de fechas?',
          intent: intent,
          findings: const <ZumacConsultantFinding>[],
          inspectedRecords: 0,
          options: _periodClarificationOptions(),
          followUpPrompt:
              'También puedes escribir un día, un mes o un rango específico.',
        );
      }
    }
    final remoteCandidateLimit = intent == ZumacConsultantIntent.crossTable
        ? 8
        : _defaultRemoteCandidateLimit;
    final remoteByTable = await _loadRemoteCandidates(
      candidates.take(remoteCandidateLimit).toList(growable: false),
      period: period,
      metadataByTable: metadataByTable,
    );

    var findings = <ZumacConsultantFinding>[];
    final allRows = <Map<String, dynamic>>[];
    final periodRowsByTable = <String, List<Map<String, dynamic>>>{};
    var inspected = 0;
    for (final table in candidates.take(24)) {
      final periodRows =
          periodRowsByTable.putIfAbsent(table, () => <Map<String, dynamic>>[]);
      final remoteRows = remoteByTable[table] ?? const <Map<String, dynamic>>[];
      if (remoteRows.isNotEmpty) {
        try {
          await local.applyMatrixRowsFromPayloads(
            {table: remoteRows},
            replaceSources: false,
          );
        } catch (_) {}
      }
      final rows = await local.matrixPayloads(table);
      final combined = <Map<String, dynamic>>[
        ...remoteRows,
        ...rows,
        ..._pendingPayloadsForTable(pendingRecords, table),
      ];
      final seen = <String>{};
      for (final row in combined) {
        if (isSoftDeletedAppgtRow(row)) continue;
        final fingerprint = _rowFingerprint(row);
        if (!seen.add(fingerprint)) continue;
        allRows.add(row);
        inspected++;
        if (period != null && !_isInPeriod(row, period)) {
          final context = _tableContext(
            table,
            metadataByTable[table] ?? const <Map<String, dynamic>>[],
          );
          final isUndatedCrossReference =
              intent == ZumacConsultantIntent.crossTable &&
                  !_hasUsableDate(row) &&
                  RegExp(
                    r'PRODUCT|INSUMO|FITOSANIT|LOTE|CATALOG|MATRIZ|MAESTR',
                  ).hasMatch(context);
          if (!isUndatedCrossReference) continue;
        }
        if (requestedLots.isNotEmpty &&
            !_matchesRequestedLot(row, requestedLots)) {
          continue;
        }
        periodRows.add(row);

        final match = switch (intent) {
          ZumacConsultantIntent.phThreshold => _phMatch(
              row,
              metadataByTable[table] ?? const <Map<String, dynamic>>[],
              threshold,
            ),
          ZumacConsultantIntent.absences => _absenceMatch(row),
          ZumacConsultantIntent.attendance => _attendanceMatch(
              row,
              table,
              metadataByTable[table] ?? const <Map<String, dynamic>>[],
            ),
          ZumacConsultantIntent.knowledge ||
          ZumacConsultantIntent.crossTable ||
          ZumacConsultantIntent.generalSearch =>
            _generalMatch(
              row,
              normalized,
              table,
              metadataByTable[table] ?? const <Map<String, dynamic>>[],
              threshold,
            ),
        };
        if (match == null) continue;

        final navigation = formatByTable[table];
        final recordIdentity = _recordIdentity(row);
        findings.add(
          ZumacConsultantFinding(
            title: match.$1,
            detail: match.$2,
            tableName: table,
            moduleId: navigation?['module_id']?.toString(),
            formatId: navigation?['format_id']?.toString(),
            recordField: recordIdentity?.$1,
            recordValue: recordIdentity?.$2,
            values: Map<String, dynamic>.from(row),
          ),
        );
      }
    }

    final inspectedTables = candidates.take(24).map(_normalize).toSet();
    for (final table in sourceTables
        .where((table) => !inspectedTables.contains(_normalize(table)))
        .take(60)) {
      try {
        allRows.addAll(await local.matrixPayloads(table));
        allRows.addAll(_pendingPayloadsForTable(pendingRecords, table));
      } catch (_) {
        // Una tabla auxiliar dañada no debe impedir responder con las demás.
      }
    }

    final crossResult = intent == ZumacConsultantIntent.crossTable
        ? _applyCrossTableReasoning(
            question: normalized,
            findings: findings,
            metadataByTable: metadataByTable,
            rowsByTable: periodRowsByTable,
            formatByTable: formatByTable,
          )
        : null;
    if (crossResult != null) {
      intent = crossResult.intent;
      findings = crossResult.findings;
    }
    final reportTables = _buildReportTables(
      findings: findings,
      metadataByTable: metadataByTable,
      formatByTable: formatByTable,
      allRows: allRows,
      period: period,
    );

    final result = ZumacConsultantResult(
      question: question,
      answer: _smartAnswerFor(
        question: normalized,
        intent: intent,
        findings: findings,
        inspected: inspected,
        threshold: threshold,
        period: period,
        formatByTable: formatByTable,
        crossResult: crossResult,
      ),
      intent: intent,
      findings: findings,
      reportTables: reportTables,
      relatedTables: relatedTables,
      inspectedRecords: inspected,
      detailLines: intent == ZumacConsultantIntent.phThreshold
          ? _phDetailLines(findings)
          : const <String>[],
      followUpPrompt: _followUpPromptFor(intent, findings),
    );
    _lastOperationalQuestion[conversationId] = contextualQuestion;
    return result;
  }

  void clearConversation(String conversationId) {
    knowledgeEngine.clearConversation(conversationId);
    _lastOperationalQuestion.remove(conversationId);
    _operationalContexts.remove(conversationId);
  }

  String _contextualizeOperationalQuestion(
    String conversationId,
    String question,
  ) {
    final previous = _lastOperationalQuestion[conversationId];
    if (previous == null) return question;
    final normalized = KnowledgeText.normalize(question);
    final isFollowUp = KnowledgeText.tokens(question).length <= 5 ||
        RegExp(r'^(Y|TAMBIEN|ADEMAS|ENTONCES|DE ELLOS|DE ELLAS)\b')
            .hasMatch(normalized);
    if (!isFollowUp) return question;
    final subject = previous
        .replaceAll(
          RegExp(
            r'\b(hoy|ayer|anteayer|esta semana|este mes|el mes pasado|mañana)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return '$subject. $question';
  }

  bool _looksLikeKnowledgeQuestion(
    String question,
    String conversationId,
  ) {
    final normalized = KnowledgeText.normalize(question);
    final isOperational = RegExp(
      r'\b(HAY|CUANTOS|CUANTAS|HOY|AYER|SEMANA|MES|FECHA|MAYOR|MENOR|STOCK|ASISTENCIA|TAREO)\b',
    ).hasMatch(normalized);
    if (isOperational &&
        !RegExp(r'\b(QUE ES|PARA QUE|RELACION|RIESGO|ERROR|BUENA PRACTICA)\b')
            .hasMatch(normalized)) {
      return false;
    }
    if (RegExp(
      r'\b(QUE ES|DESCRIB|EXPLICA|OBJETIVO|PARA QUE|SIRVE|UTILIZA|QUIEN|CUANDO|FRECUENCIA|EJEMPLO|RELACION|CONECTA|GRAFO|ERROR|BUENA PRACTICA|RECOMEND|INDICADOR|KPI|RIESGO|FAQ|PREGUNTA FRECUENTE)\b',
    ).hasMatch(normalized)) {
      return true;
    }
    return knowledgeEngine.hasConversationContext(conversationId) &&
        KnowledgeText.tokens(question).length <= 5;
  }

  Future<List<Map<String, dynamic>>> _safeLocalRows(String table) async {
    try {
      return await local.getAll(table);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> _safeRemoteRows(
    String table, {
    _ConsultantPeriod? period,
    List<Map<String, dynamic>> metadata = const <Map<String, dynamic>>[],
  }) async {
    try {
      if (_usesDefaultRemoteLoader && period != null) {
        final dateColumn = _remoteDateColumn(metadata);
        if (dateColumn != null) {
          return await _loadRemoteTableForPeriod(table, dateColumn, period);
        }
      }
      return await remoteLoader(table).timeout(_remoteTableTimeout);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  String? _remoteDateColumn(List<Map<String, dynamic>> metadata) {
    for (final field in metadata) {
      if (field['__consultant_context'] == true) continue;
      final name = field['campo']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      final type = _normalize(field['tipo_ui']?.toString() ?? '');
      final normalizedName = _normalize(name);
      if (RegExp(r'DATE|FECHA|DIA|TIMESTAMP').hasMatch(type) ||
          RegExp(r'(^|_)FECHA($|_)|(^|_)DATE($|_)|(^|_)DIA($|_)')
              .hasMatch(normalizedName.replaceAll(' ', '_'))) {
        return name;
      }
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> _loadRemoteTableForPeriod(
    String table,
    String dateColumn,
    _ConsultantPeriod period,
  ) async {
    final client = Supabase.instance.client;
    const pageSize = 500;
    const maxRows = 10000;
    final rows = <Map<String, dynamic>>[];
    final start = _dateForRemoteFilter(period.start);
    final end = _dateForRemoteFilter(period.endExclusive);
    for (var from = 0; from < maxRows; from += pageSize) {
      final page = await client
          .from(table)
          .select()
          .gte(dateColumn, start)
          .lt(dateColumn, end)
          .range(from, from + pageSize - 1)
          .timeout(_remoteTableTimeout);
      final mapped = List<Map<String, dynamic>>.from(page);
      rows.addAll(mapped);
      if (mapped.length < pageSize) break;
    }
    return rows;
  }

  String _dateForRemoteFilter(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<Map<String, List<Map<String, dynamic>>>> _loadRemoteCandidates(
    List<String> tables, {
    _ConsultantPeriod? period,
    Map<String, List<Map<String, dynamic>>> metadataByTable =
        const <String, List<Map<String, dynamic>>>{},
  }) async {
    final loaded = <String, List<Map<String, dynamic>>>{};
    const batchSize = 4;
    for (var start = 0; start < tables.length; start += batchSize) {
      final end = (start + batchSize < tables.length)
          ? start + batchSize
          : tables.length;
      final batch = tables.sublist(start, end);
      final rows = await Future.wait(
        batch.map(
          (table) => _safeRemoteRows(
            table,
            period: period,
            metadata: metadataByTable[table] ?? const <Map<String, dynamic>>[],
          ),
        ),
      );
      for (var index = 0; index < batch.length; index++) {
        loaded[batch[index]] = rows[index];
      }
    }
    return loaded;
  }

  ZumacConsultantIntent _intentFor(String question) {
    if (question.contains('PERO NO') ||
        question.contains(' SIN ') ||
        ((question.contains('PLAGA') || question.contains('ENFERMEDAD')) &&
            question.contains('PRODUCT'))) {
      return ZumacConsultantIntent.crossTable;
    }
    if (RegExp(r'(^|[^A-Z])PHS?([^A-Z]|$)').hasMatch(question)) {
      return ZumacConsultantIntent.phThreshold;
    }
    if (question.contains('INASIST') ||
        question.contains('AUSEN') ||
        question.contains('FALTO') ||
        question.contains('FALTA')) {
      return ZumacConsultantIntent.absences;
    }
    if (question.contains('ASIST') ||
        question.contains('INGRESO') ||
        question.contains('SALIDA')) {
      return ZumacConsultantIntent.attendance;
    }
    return ZumacConsultantIntent.generalSearch;
  }

  num? _numericThreshold(String question) => _comparisonFor(question)?.$2;

  /// Extrae entidades solo de la clausula que sigue a "lote(s)"; evita tomar
  /// el limite de pH o los componentes de la fecha como identificadores.
  Set<String> _requestedLots(String question) {
    final clause = RegExp(
      r'\bLOTES?\s+(.+?)(?=\s+(?:TUVO|TUVIERON|TIENE|TIENEN|ESTUVO|ESTUVIERON|FUERON|CON|CUYO|CUYOS|QUE|MAYOR|MENOR|EL\s+DIA|EN\s+LA\s+FECHA|DEL?\s+\d)|[?.,;]|$)',
    ).firstMatch(question)?.group(1);
    if (clause == null || clause.trim().isEmpty) return const <String>{};
    final values = RegExp(r'[A-Z0-9][A-Z0-9_-]*')
        .allMatches(clause)
        .map((match) => match.group(0)!)
        .where((value) => !const {'Y', 'E', 'O', 'U'}.contains(value))
        .map(_normalizeLotValue)
        .where((value) => value.isNotEmpty)
        .toSet();
    return values.length <= 20 ? values : const <String>{};
  }

  bool _matchesRequestedLot(
    Map<String, dynamic> row,
    Set<String> requestedLots,
  ) {
    for (final entry in row.entries) {
      final field = _normalize(entry.key).replaceAll(' ', '_');
      if (!RegExp(r'(^LOTE$|^LOTE_|_LOTE$|LOTE_ID|ID_LOTE)').hasMatch(field)) {
        continue;
      }
      final value = _normalizeLotValue(entry.value?.toString() ?? '');
      if (value.isNotEmpty && requestedLots.contains(value)) return true;
    }
    return false;
  }

  String _normalizeLotValue(String value) => _normalize(value)
      .replaceFirst(RegExp(r'^LOTE[\s_-]*'), '')
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '');

  (String, num)? _comparisonFor(String question) {
    final patterns = <(String, RegExp)>[
      (
        '>',
        RegExp(
          r'(?:MAYOR(?:ES)?(?:\s+(?:A|QUE))?|\>)\s*(\d+(?:[\.,]\d+)?)',
        ),
      ),
      (
        '<',
        RegExp(
          r'(?:MENOR(?:ES)?(?:\s+(?:A|QUE))?|\<)\s*(\d+(?:[\.,]\d+)?)',
        ),
      ),
      (
        '=',
        RegExp(
          r'(?:IGUAL(?:ES)?(?:\s+(?:A|QUE))?|=)\s*(\d+(?:[\.,]\d+)?)',
        ),
      ),
    ];
    for (final pattern in patterns) {
      final match = pattern.$2.firstMatch(question);
      final value = match == null
          ? null
          : num.tryParse(match.group(1)!.replaceAll(',', '.'));
      if (value != null) return (pattern.$1, value);
    }
    return null;
  }

  List<String> _candidateTables({
    required String question,
    required ZumacConsultantIntent intent,
    required List<String> sourceTables,
    required Map<String, List<Map<String, dynamic>>> metadataByTable,
    required List<Map<String, dynamic>> pendingRecords,
  }) {
    final available = <String>{
      ...sourceTables,
      ...metadataByTable.keys,
      ...pendingRecords
          .map((row) => row['tabla_destino']?.toString().trim() ?? '')
          .where((value) => value.isNotEmpty),
    };
    final tokens = _tokens(question);
    final scored = <(String, int)>[];
    for (final table in available) {
      var score = 0;
      final tableText = _normalize(table);
      final fields = metadataByTable[table] ?? const <Map<String, dynamic>>[];
      final fieldText = fields
          .map((field) =>
              '${field['campo'] ?? ''} ${field['etiqueta'] ?? ''} ${field['tipo_ui'] ?? ''}')
          .map(_normalize)
          .join(' ');

      if (intent == ZumacConsultantIntent.phThreshold &&
          RegExp(r'(^|_)PH($|_)|POTENCIAL.*HIDROGEN').hasMatch(
            '$tableText $fieldText'.replaceAll(' ', '_'),
          )) {
        score += 100;
      }
      if (intent == ZumacConsultantIntent.absences &&
          RegExp(r'INASIST|AUSEN|ASISTEN|FALTA|PRESENTE|TAREO')
              .hasMatch('$tableText $fieldText')) {
        score += 100;
      }
      if (intent == ZumacConsultantIntent.attendance &&
          RegExp(r'ASISTEN|INGRESO|SALIDA|PRESENTE')
              .hasMatch('$tableText $fieldText')) {
        score += 100;
      }
      if (question.contains('TAREO') &&
          RegExp(r'TAREO|JORNAL|LABOR').hasMatch('$tableText $fieldText')) {
        score += 100;
      }
      if (RegExp(r'ASISTEN|PRESENTE|INGRESO').hasMatch(question) &&
          RegExp(r'ASISTEN|PRESENTE|HORA.?INGRESO')
              .hasMatch('$tableText $fieldText')) {
        score += 100;
      }
      if (RegExp(r'PLAGA|ENFERMEDAD').hasMatch(question) &&
          RegExp(r'PLAGA|ENFERMEDAD').hasMatch('$tableText $fieldText')) {
        score += 100;
      }
      if (RegExp(r'PRODUCT|INSUMO|FITOSANIT').hasMatch(question) &&
          RegExp(r'PRODUCT|INSUMO|FITOSANIT')
              .hasMatch('$tableText $fieldText')) {
        score += 100;
      }
      for (final token in tokens) {
        if (_textContainsToken(tableText, token)) score += 8;
        if (_textContainsToken(fieldText, token)) score += 12;
      }
      if (score > 0) scored.add((table, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    if (scored.isNotEmpty) {
      final bestScore = scored.first.$2;
      final relevanceFloor = (bestScore * 0.60).ceil();
      return scored
          .where((entry) => entry.$2 >= relevanceFloor)
          .map((entry) => entry.$1)
          .toList();
    }
    return available.take(24).toList();
  }

  String? _explicitCandidateSource(
    String normalizedQuestion,
    List<String> candidates,
    Map<String, Map<String, String>> formatByTable,
  ) {
    final matches = <String>[];
    for (final table in candidates) {
      final metadata = formatByTable[table];
      final names = <String>[
        table,
        metadata?['format_name'] ?? '',
      ].map(_normalize).where((value) => value.length >= 4);
      if (names.any(normalizedQuestion.contains)) matches.add(table);
    }
    return matches.length == 1 ? matches.single : null;
  }

  List<ZumacConsultantOption> _sourceClarificationOptions(
    List<String> candidates,
    Map<String, Map<String, String>> formatByTable,
  ) {
    final seenLabels = <String>{};
    final options = <ZumacConsultantOption>[];
    for (final table in candidates) {
      final label = _sourceLabel(table, formatByTable);
      if (label.isEmpty || !seenLabels.add(_normalize(label))) continue;
      options.add(
        ZumacConsultantOption(
          label: label,
          query: 'Consultar $label',
          kind: ZumacConsultantOptionKind.source,
          sourceTable: table,
        ),
      );
      if (options.length == 8) break;
    }
    return options;
  }

  String _sourceLabel(
    String? table,
    Map<String, Map<String, String>> formatByTable,
  ) {
    if (table == null || table.isEmpty) return '';
    final configured = formatByTable[table]?['format_name']?.trim() ?? '';
    return configured.isNotEmpty ? configured : _humanizeIdentifier(table);
  }

  List<ZumacConsultantOption> _periodClarificationOptions() => const [
        ZumacConsultantOption(
          label: 'Hoy',
          query: 'Hoy',
          kind: ZumacConsultantOptionKind.period,
        ),
        ZumacConsultantOption(
          label: 'Ayer',
          query: 'Ayer',
          kind: ZumacConsultantOptionKind.period,
        ),
        ZumacConsultantOption(
          label: 'Esta semana',
          query: 'Esta semana',
          kind: ZumacConsultantOptionKind.period,
        ),
        ZumacConsultantOption(
          label: 'Este mes',
          query: 'Este mes',
          kind: ZumacConsultantOptionKind.period,
        ),
      ];

  List<String> _phDetailLines(List<ZumacConsultantFinding> findings) {
    final lotsByDate = <String, Set<String>>{};
    for (final finding in findings) {
      final date = _displayDate(finding.values);
      final lot = _firstValue(finding.values, const [
        'LOTE',
        'LOTE_ID',
        'ID_LOTE',
        'CAMPO',
        'SECTOR',
        'UBICACION',
        'TURNO',
      ]);
      final key = date.isEmpty ? 'Sin fecha registrada' : date;
      if (lot.isNotEmpty && !_looksOpaqueIdentifier(lot)) {
        lotsByDate.putIfAbsent(key, () => <String>{}).add(lot);
      }
    }
    final dates = lotsByDate.keys.toList()
      ..sort((a, b) {
        final parsedA = _parseDate(a);
        final parsedB = _parseDate(b);
        if (parsedA == null || parsedB == null) return a.compareTo(b);
        return parsedA.compareTo(parsedB);
      });
    return dates.take(31).map((date) {
      final lots = lotsByDate[date]!.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return '$date — ${lots.length == 1 ? 'Lote' : 'Lotes'} ${lots.join(', ')}';
    }).toList(growable: false);
  }

  String _followUpPromptFor(
    ZumacConsultantIntent intent,
    List<ZumacConsultantFinding> findings,
  ) {
    if (findings.isEmpty) {
      return '¿Quieres probar otra fecha, otro registro o una condición diferente?';
    }
    return switch (intent) {
      ZumacConsultantIntent.phThreshold =>
        '¿Quieres comparar otro periodo, cambiar el límite de pH o abrir los registros?',
      ZumacConsultantIntent.attendance ||
      ZumacConsultantIntent.absences =>
        '¿Quieres revisar el detalle, otro periodo o compararlo con tareos?',
      _ =>
        '¿Quieres precisar otra condición o revisar los registros encontrados?',
    };
  }

  bool _isAttendanceDomainQuestion(
    String question,
    ZumacConsultantIntent intent,
  ) {
    if (intent == ZumacConsultantIntent.attendance ||
        intent == ZumacConsultantIntent.absences) {
      return true;
    }
    return RegExp(r'ASISTEN|AUSEN|INASIST|TAREO|PERSONAL|TRABAJADOR')
        .hasMatch(question);
  }

  bool _isReferenceCatalogTable(
    String table,
    Map<String, Map<String, String>> formatByTable,
  ) {
    final metadata = formatByTable[table];
    final context = _normalize(
      '$table ${metadata?['format_name'] ?? ''} '
      '${metadata?['module_name'] ?? ''}',
    );
    return RegExp(r'(^|\s|_)(MATRIZ|CATALOGO|MAESTRO|MAESTRA)(\s|_|$)')
        .hasMatch(context);
  }

  List<ZumacConsultantRelatedTable> _relatedReferenceTables({
    required String question,
    required Map<String, Map<String, String>> formatByTable,
  }) {
    final questionTokens = _tokens(question);
    final scored = <(ZumacConsultantRelatedTable, int)>[];
    final seen = <String>{};
    for (final entry in formatByTable.entries) {
      if (!_isReferenceCatalogTable(entry.key, formatByTable)) continue;
      final metadata = entry.value;
      final title = metadata['format_name']?.trim().isNotEmpty == true
          ? metadata['format_name']!.trim()
          : _humanizeIdentifier(entry.key);
      final normalizedContext = _normalize(
        '$title ${entry.key} ${metadata['module_name'] ?? ''}',
      );
      var score = 0;
      if (RegExp(r'ASISTEN|AUSEN|INASIST|TAREO|PERSONAL|TRABAJADOR')
              .hasMatch(question) &&
          RegExp(r'ASISTEN|AUSEN|INASIST|TAREO|PERSONAL|TRABAJADOR')
              .hasMatch(normalizedContext)) {
        score += 100;
      }
      for (final token in questionTokens) {
        if (_textContainsToken(normalizedContext, token)) score += 8;
      }
      if (score <= 0 || !seen.add(_normalize(title))) continue;
      scored.add((
        ZumacConsultantRelatedTable(
          title: title,
          tableName: entry.key,
          moduleId: metadata['module_id'],
          formatId: metadata['format_id'],
        ),
        score,
      ));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(8).map((entry) => entry.$1).toList(growable: false);
  }

  void _augmentSearchMetadata({
    required Map<String, List<Map<String, dynamic>>> metadataByTable,
    required List<Map<String, dynamic>> formats,
    required List<Map<String, dynamic>> formatTables,
    required List<Map<String, dynamic>> modules,
    required List<Map<String, dynamic>> sections,
  }) {
    final formatsById = <String, Map<String, dynamic>>{
      for (final format in formats)
        if ((format['id']?.toString() ?? '').isNotEmpty)
          format['id'].toString(): format,
    };
    final modulesById = <String, Map<String, dynamic>>{
      for (final module in modules)
        if ((module['id']?.toString() ?? '').isNotEmpty)
          module['id'].toString(): module,
    };
    final sectionsByKey = <String, Map<String, dynamic>>{};
    for (final section in sections) {
      for (final rawKey in [
        section['id'],
        section['seccion'],
        section['nombre'],
      ]) {
        final key = _normalize(rawKey?.toString() ?? '');
        if (key.isNotEmpty) sectionsByKey.putIfAbsent(key, () => section);
      }
    }

    void add(
      String rawTable,
      Map<String, dynamic>? format, {
      String extraContext = '',
    }) {
      final table = rawTable.trim();
      if (table.isEmpty || format == null) return;
      final module = modulesById[format['modulo_id']?.toString() ?? ''];
      final section =
          sectionsByKey[_normalize(module?['seccion']?.toString() ?? '')];
      metadataByTable.putIfAbsent(table, () => []).add({
        'campo': format['nombre'] ?? format['id'],
        'etiqueta': '${format['nombre'] ?? ''} ${module?['nombre'] ?? ''} '
                '${section?['nombre'] ?? section?['seccion'] ?? ''} '
                '$extraContext'
            .trim(),
        '__consultant_context': true,
      });
    }

    for (final format in formats) {
      add(format['tabla_destino']?.toString() ?? '', format);
    }
    for (final table in formatTables) {
      add(
        table['tabla_destino']?.toString() ?? '',
        formatsById[table['formato_id']?.toString() ?? ''],
        extraContext: table['nombre']?.toString() ?? '',
      );
    }
  }

  Map<String, Map<String, String>> _formatMetadataByTable({
    required List<Map<String, dynamic>> formats,
    required List<Map<String, dynamic>> formatTables,
    required List<Map<String, dynamic>> modules,
  }) {
    final formatById = <String, Map<String, dynamic>>{
      for (final row in formats)
        if ((row['id']?.toString() ?? '').isNotEmpty) row['id'].toString(): row,
    };
    final modulesById = <String, Map<String, dynamic>>{
      for (final row in modules)
        if ((row['id']?.toString() ?? '').isNotEmpty) row['id'].toString(): row,
    };
    final out = <String, Map<String, String>>{};

    void add(String table, Map<String, dynamic>? format) {
      final cleanTable = table.trim();
      if (cleanTable.isEmpty || format == null) return;
      final formatId = format['id']?.toString() ?? '';
      final moduleId = format['modulo_id']?.toString() ?? '';
      if (formatId.isEmpty || !modulesById.containsKey(moduleId)) return;
      out[cleanTable] = {
        'format_id': formatId,
        'module_id': moduleId,
        'format_name': format['nombre']?.toString().trim() ?? '',
        'module_name':
            modulesById[moduleId]?['nombre']?.toString().trim() ?? '',
      };
    }

    for (final format in formats) {
      add(format['tabla_destino']?.toString() ?? '', format);
    }
    for (final row in formatTables) {
      add(
        row['tabla_destino']?.toString() ?? '',
        formatById[row['formato_id']?.toString() ?? ''],
      );
    }
    return out;
  }

  List<Map<String, dynamic>> _pendingPayloadsForTable(
    List<Map<String, dynamic>> records,
    String table,
  ) {
    final out = <Map<String, dynamic>>[];
    for (final record in records) {
      if (_normalize(record['tabla_destino']?.toString() ?? '') !=
          _normalize(table)) {
        continue;
      }
      try {
        final payload = Map<String, dynamic>.from(
          jsonDecode(record['payload_json']?.toString() ?? '{}') as Map,
        );
        payload.putIfAbsent(
          '__consultant_date',
          () => record['created_at'] ?? record['updated_at_local'],
        );
        out.add(payload);
      } catch (_) {}
    }
    return out;
  }

  (String, String)? _phMatch(
    Map<String, dynamic> row,
    List<Map<String, dynamic>> fieldMetadata,
    num? threshold,
  ) {
    final configuredFields = fieldMetadata
        .where((field) {
          final text =
              _normalize('${field['campo'] ?? ''} ${field['etiqueta'] ?? ''}');
          return RegExp(r'(^|_)PH($|_)|POTENCIAL_HIDROGEN')
              .hasMatch(text.replaceAll(' ', '_'));
        })
        .map((field) => _normalize(field['campo']?.toString() ?? ''))
        .where((value) => value.isNotEmpty)
        .toSet();
    for (final entry in row.entries) {
      final key = _normalize(entry.key);
      final isPh = configuredFields.contains(key) ||
          RegExp(r'(^|_)PH($|_)|POTENCIAL_HIDROGEN')
              .hasMatch(key.replaceAll(' ', '_'));
      if (!isPh) continue;
      final value =
          num.tryParse(entry.value?.toString().replaceAll(',', '.') ?? '');
      if (value == null || (threshold != null && value <= threshold)) continue;
      final location = _firstValue(row, const [
        'LOTE',
        'UBICACION',
        'FUNDO',
        'CAMPO',
        'TURNO',
        'SECTOR',
      ]);
      final date = _displayDate(row);
      final context = <String>[
        if (location.isNotEmpty) location,
        if (date.isNotEmpty) date,
      ].join(' · ');
      return (
        'pH ${_cleanNumber(value)}',
        context.isEmpty
            ? 'Registro con pH fuera del límite consultado.'
            : context
      );
    }
    return null;
  }

  (String, String)? _absenceMatch(Map<String, dynamic> row) {
    var absent = false;
    for (final entry in row.entries) {
      final key = _normalize(entry.key);
      final value = _normalize(entry.value?.toString() ?? '');
      if (RegExp(r'INASIST|AUSEN|FALTA').hasMatch(key) &&
          (_truthy(entry.value) ||
              RegExp(r'INASIST|AUSEN|FALTO|FALTA').hasMatch(value))) {
        absent = true;
      }
      if (RegExp(r'ASISTEN|PRESENTE').hasMatch(key) &&
          (_falsey(entry.value) ||
              RegExp(r'NO|INASIST|AUSEN|FALTO').hasMatch(value))) {
        absent = true;
      }
      if (RegExp(r'ESTADO|CONDICION').hasMatch(key) &&
          RegExp(r'INASIST|AUSEN|FALTO|FALTA').hasMatch(value)) {
        absent = true;
      }
    }
    if (!absent) return null;
    final person = _firstValue(row, const [
      'NOMBRE_COMPLETO',
      'NOMBRES_Y_APELLIDOS',
      'TRABAJADOR',
      'COLABORADOR',
      'PERSONAL',
      'NOMBRE',
      'APELLIDOS',
      'DNI',
    ]);
    final detail = <String>[
      if (_displayDate(row).isNotEmpty) _displayDate(row),
      if (_firstValue(row, const ['MOTIVO', 'OBSERVACION']).isNotEmpty)
        _firstValue(row, const ['MOTIVO', 'OBSERVACION']),
    ].join(' · ');
    return (
      person.isEmpty ? 'Inasistencia registrada' : person,
      detail.isEmpty ? 'Marcado como ausente o inasistente.' : detail,
    );
  }

  (String, String)? _attendanceMatch(
    Map<String, dynamic> row,
    String table,
    List<Map<String, dynamic>> fieldMetadata,
  ) {
    final context = _normalize(
      '$table ${fieldMetadata.map((field) => '${field['campo'] ?? ''} ${field['etiqueta'] ?? ''}').join(' ')}',
    );
    if (!RegExp(r'ASISTEN|HORA.?INGRESO|HORA.?SALIDA|PRESENTE')
        .hasMatch(context)) {
      return null;
    }
    if (_absenceMatch(row) != null) return null;
    final hasAttendanceValue = row.entries.any((entry) {
      final key = _normalize(entry.key);
      final value = entry.value?.toString().trim() ?? '';
      if (value.isEmpty) return false;
      return RegExp(r'ASISTEN|INGRESO|PRESENTE').hasMatch(key);
    });
    if (!hasAttendanceValue &&
        !RegExp(r'ASISTEN').hasMatch(_normalize(table))) {
      return null;
    }
    final person = _personDisplay(row);
    final detail = <String>[
      if (_displayDate(row).isNotEmpty) _displayDate(row),
      if (_firstValue(row, const ['HORA_INGRESO', 'INGRESO']).isNotEmpty)
        'Ingreso: ${_firstValue(row, const ['HORA_INGRESO', 'INGRESO'])}',
      if (_firstValue(row, const ['HORA_SALIDA', 'SALIDA']).isNotEmpty)
        'Salida: ${_firstValue(row, const ['HORA_SALIDA', 'SALIDA'])}',
    ].join(' · ');
    return (
      person.isEmpty ? 'Asistencia registrada' : person,
      detail.isEmpty ? 'Cuenta con asistencia registrada.' : detail,
    );
  }

  (String, String)? _generalMatch(
    Map<String, dynamic> row,
    String question,
    String table,
    List<Map<String, dynamic>> fieldMetadata,
    num? threshold,
  ) {
    final tokens = _tokens(question);
    if (tokens.isEmpty) return null;
    final rowText = _normalize(
      row.entries
          .where((entry) => !entry.key.startsWith('__'))
          .map((entry) => '${entry.key} ${entry.value ?? ''}')
          .join(' '),
    );
    final contextText = _normalize(
      '$table ${fieldMetadata.map((field) => '${field['campo'] ?? ''} ${field['etiqueta'] ?? ''}').join(' ')}',
    );
    final contextTokens =
        tokens.where((token) => _textContainsToken(contextText, token)).toSet();
    final rowTokens =
        tokens.where((token) => _textContainsToken(rowText, token)).toSet();

    if (contextTokens.isEmpty && rowTokens.isEmpty) return null;
    final comparison = _comparisonFor(question);
    final quotedValues = RegExp(r'["“”]([^"“”]+)["“”]')
        .allMatches(question)
        .map((match) => _normalize(match.group(1) ?? ''))
        .where((value) => value.isNotEmpty);
    if (quotedValues.isNotEmpty &&
        !quotedValues.every((value) => rowText.contains(value))) {
      return null;
    }
    if (question.contains('STOCK') &&
        RegExp(r'PRODUCT|INSUMO|FITOSANIT|ALMACEN').hasMatch(contextText) &&
        !_hasPositiveStock(row)) {
      return null;
    }

    if (comparison != null &&
        !_rowMatchesComparison(
          row: row,
          metadata: fieldMetadata,
          tokens: tokens,
          operator: comparison.$1,
          threshold: threshold ?? comparison.$2,
        )) {
      return null;
    }

    final title = _firstValue(row, const [
      'NOMBRE_COMPLETO',
      'NOMBRES_Y_APELLIDOS',
      'APELLIDOS_Y_NOMBRES',
      'APELLIDOS Y NOMBRES',
      'TRABAJADOR',
      'COLABORADOR',
      'PERSONAL',
      'PRODUCTO',
      'NOMBRE_PRODUCTO',
      'PLAGA',
      'ENFERMEDAD',
      'NOMBRE',
      'DESCRIPCION',
      'LOTE',
    ]);
    final detailParts = <String>{
      if (_displayDate(row).isNotEmpty) _displayDate(row),
      ..._relatedValues(row, fieldMetadata, tokens).take(3),
    }.toList();
    return (
      title.isNotEmpty ? title : 'Registro relacionado',
      detailParts.isEmpty
          ? 'Coincide con la consulta en $table.'
          : detailParts.join(' · '),
    );
  }

  bool _rowMatchesComparison({
    required Map<String, dynamic> row,
    required List<Map<String, dynamic>> metadata,
    required List<String> tokens,
    required String operator,
    required num threshold,
  }) {
    final relatedFields = metadata
        .where((field) => field['__consultant_context'] != true)
        .where((field) {
          final description =
              '${field['campo'] ?? ''} ${field['etiqueta'] ?? ''}';
          return tokens.any(
            (token) => _textContainsToken(description, token),
          );
        })
        .map((field) => _normalize(field['campo']?.toString() ?? ''))
        .where((field) => field.isNotEmpty)
        .toSet();
    for (final entry in row.entries) {
      if (relatedFields.isNotEmpty &&
          !relatedFields.contains(_normalize(entry.key))) {
        continue;
      }
      final value =
          num.tryParse(entry.value?.toString().replaceAll(',', '.') ?? '');
      if (value == null) continue;
      if (operator == '>' && value > threshold) return true;
      if (operator == '<' && value < threshold) return true;
      if (operator == '=' && value == threshold) return true;
    }
    return false;
  }

  Iterable<String> _relatedValues(
    Map<String, dynamic> row,
    List<Map<String, dynamic>> metadata,
    List<String> tokens,
  ) sync* {
    final labelByField = <String, String>{};
    for (final field in metadata) {
      if (field['__consultant_context'] == true) continue;
      final name = field['campo']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      labelByField[_normalize(name)] =
          field['etiqueta']?.toString().trim().isNotEmpty == true
              ? field['etiqueta'].toString().trim()
              : name;
    }
    for (final entry in row.entries) {
      final value = entry.value?.toString().trim() ?? '';
      if (value.isEmpty || entry.key.startsWith('__')) continue;
      final label = labelByField[_normalize(entry.key)] ?? entry.key;
      final related = tokens.any(
        (token) =>
            _textContainsToken(label, token) ||
            _textContainsToken(value, token),
      );
      if (related) yield '$label: $value';
    }
  }

  _CrossTableResult _applyCrossTableReasoning({
    required String question,
    required List<ZumacConsultantFinding> findings,
    required Map<String, List<Map<String, dynamic>>> metadataByTable,
    required Map<String, List<Map<String, dynamic>>> rowsByTable,
    required Map<String, Map<String, String>> formatByTable,
  }) {
    final connector = RegExp(r'\bPERO NO\b|\bSIN\b').firstMatch(question);
    if (connector != null) {
      final positiveClause = question.substring(0, connector.start);
      final negativeClause = question.substring(connector.end);
      final asksWorkLogAttendance =
          RegExp(r'TAREO|JORNAL|LABOR').hasMatch(question) &&
              RegExp(r'ASISTEN|PRESENTE|INGRESO').hasMatch(question);
      if (asksWorkLogAttendance) {
        final availableTables = rowsByTable.keys.toSet();
        final workLogTables = availableTables.where((table) {
          final context = _tableContext(
            table,
            metadataByTable[table] ?? const <Map<String, dynamic>>[],
          );
          return RegExp(r'TAREO|JORNAL|LABOR').hasMatch(context);
        }).toSet();
        final attendanceTables = availableTables.where((table) {
          final context = _tableContext(
            table,
            metadataByTable[table] ?? const <Map<String, dynamic>>[],
          );
          return !RegExp(r'TAREO|JORNAL').hasMatch(context) &&
              RegExp(r'ASISTEN|PRESENTE|HORA.?INGRESO').hasMatch(context);
        }).toSet();

        if (workLogTables.isNotEmpty && attendanceTables.isNotEmpty) {
          final workLogs = _uniquePersonRows(
            tables: workLogTables,
            rowsByTable: rowsByTable,
          );
          final attendances = _uniquePersonRows(
            tables: attendanceTables,
            rowsByTable: rowsByTable,
          );
          final workLogPeople =
              workLogs.expand((entry) => _personKeys(entry.$2)).toSet();
          final attendancePeople =
              attendances.expand((entry) => _personKeys(entry.$2)).toSet();
          final primaryIsWorkLog =
              RegExp(r'TAREO|JORNAL|LABOR').hasMatch(positiveClause);
          final sourceRows = primaryIsWorkLog ? workLogs : attendances;
          final otherPeople =
              primaryIsWorkLog ? attendancePeople : workLogPeople;
          final missingRows = sourceRows.where((entry) {
            final people = _personKeys(entry.$2);
            return people.isNotEmpty &&
                people.intersection(otherPeople).isEmpty;
          }).toList(growable: false);
          final crossFindings = missingRows
              .map(
                (entry) => _findingFromRow(
                  table: entry.$1,
                  row: entry.$2,
                  formatByTable: formatByTable,
                  detail: primaryIsWorkLog
                      ? 'Tiene tareo, pero no asistencia registrada.'
                      : 'Tiene asistencia, pero no tareo registrado.',
                ),
              )
              .toList(growable: false);
          return _CrossTableResult(
            intent: ZumacConsultantIntent.crossTable,
            findings: crossFindings,
            kind: 'attendance_worklog',
            attendanceCount: attendances.length,
            workLogCount: workLogs.length,
            unmatchedCount: crossFindings.length,
            workLogWithoutAttendance: primaryIsWorkLog,
          );
        }
      }

      final tables = <String>{
        ...rowsByTable.keys,
        ...findings.map((finding) => finding.tableName),
      };
      final primary = _bestTablesForClause(
        positiveClause,
        tables,
        metadataByTable,
      );
      final excluded = _bestTablesForClause(
        negativeClause,
        tables,
        metadataByTable,
      );
      if (primary.isNotEmpty && excluded.isNotEmpty) {
        final excludedPeople = <String>{};
        for (final finding in findings) {
          if (!excluded.contains(finding.tableName)) continue;
          excludedPeople.addAll(_personKeys(finding.values));
        }
        final filtered = findings.where((finding) {
          if (!primary.contains(finding.tableName)) return false;
          final personKeys = _personKeys(finding.values);
          return personKeys.isNotEmpty &&
              personKeys.intersection(excludedPeople).isEmpty;
        }).toList(growable: false);
        return _CrossTableResult(
          intent: ZumacConsultantIntent.crossTable,
          findings: filtered,
          kind: 'missing_relation',
        );
      }
    }

    final asksPestProducts =
        (question.contains('PLAGA') || question.contains('ENFERMEDAD')) &&
            question.contains('PRODUCT');
    if (asksPestProducts) {
      bool isPestTable(String table) => RegExp(r'PLAGA|ENFERMEDAD').hasMatch(
            _tableContext(table, metadataByTable[table] ?? const []),
          );
      bool isProductTable(String table) =>
          RegExp(r'PRODUCT|INSUMO|FITOSANIT').hasMatch(
            _tableContext(table, metadataByTable[table] ?? const []),
          );

      final pestFindings = findings
          .where((finding) => isPestTable(finding.tableName))
          .toList(growable: false);
      final targets = <String>{};
      for (final finding in pestFindings) {
        for (final entry in finding.values.entries) {
          final key = _normalize(entry.key);
          final value = entry.value?.toString().trim() ?? '';
          if (!RegExp(r'PLAGA|ENFERMEDAD|DESCRIPCION|CONCEPTO').hasMatch(key) ||
              value.isEmpty ||
              num.tryParse(value.replaceAll(',', '.')) != null ||
              _looksOpaqueIdentifier(value)) {
            continue;
          }
          targets.add(_normalize(value));
        }
      }
      final productFindings = findings.where((finding) {
        if (!isProductTable(finding.tableName)) return false;
        if (question.contains('STOCK') && !_hasPositiveStock(finding.values)) {
          return false;
        }
        final objectives = finding.values.entries
            .where(
              (entry) => RegExp(
                r'OBJETIVO|COMBATE|PLAGA|ENFERMEDAD|USO|APLICACION',
              ).hasMatch(_normalize(entry.key)),
            )
            .map((entry) => _normalize(entry.value?.toString() ?? ''))
            .where((value) => value.isNotEmpty)
            .toList(growable: false);
        if (targets.isEmpty || objectives.isEmpty) return false;
        return targets.any(
          (target) => objectives.any(
            (objective) =>
                objective.contains(target) || target.contains(objective),
          ),
        );
      }).toList(growable: false);
      return _CrossTableResult(
        intent: ZumacConsultantIntent.crossTable,
        findings: <ZumacConsultantFinding>[
          ...pestFindings,
          ...productFindings,
        ],
        kind: 'pest_products',
      );
    }
    return _CrossTableResult(
      intent: ZumacConsultantIntent.crossTable,
      findings: findings,
      kind: 'related_tables',
    );
  }

  List<(String, Map<String, dynamic>)> _uniquePersonRows({
    required Set<String> tables,
    required Map<String, List<Map<String, dynamic>>> rowsByTable,
  }) {
    final unique = <(String, Map<String, dynamic>)>[];
    final knownPeople = <String>{};
    for (final table in tables) {
      for (final row in rowsByTable[table] ?? const <Map<String, dynamic>>[]) {
        final people = _personKeys(row);
        if (people.isEmpty || people.intersection(knownPeople).isNotEmpty) {
          continue;
        }
        knownPeople.addAll(people);
        unique.add((table, row));
      }
    }
    return unique;
  }

  ZumacConsultantFinding _findingFromRow({
    required String table,
    required Map<String, dynamic> row,
    required Map<String, Map<String, String>> formatByTable,
    required String detail,
  }) {
    final navigation = formatByTable[table];
    final identity = _recordIdentity(row);
    final person = _personDisplay(row);
    return ZumacConsultantFinding(
      title: person.isEmpty ? 'Persona relacionada' : person,
      detail: detail,
      tableName: table,
      moduleId: navigation?['module_id'],
      formatId: navigation?['format_id'],
      recordField: identity?.$1,
      recordValue: identity?.$2,
      values: Map<String, dynamic>.from(row),
    );
  }

  Set<String> _bestTablesForClause(
    String clause,
    Set<String> tables,
    Map<String, List<Map<String, dynamic>>> metadataByTable,
  ) {
    final tokens = _tokens(clause);
    final scored = <String, int>{};
    for (final table in tables) {
      final context = _tableContext(table, metadataByTable[table] ?? const []);
      var score = 0;
      for (final token in tokens) {
        if (_textContainsToken(_normalize(table), token)) score += 10;
        if (_textContainsToken(context, token)) score += 6;
      }
      if (score > 0) scored[table] = score;
    }
    if (scored.isEmpty) return const <String>{};
    final best = scored.values.reduce((a, b) => a > b ? a : b);
    return scored.entries
        .where((entry) => entry.value == best)
        .map((entry) => entry.key)
        .toSet();
  }

  String _tableContext(
    String table,
    List<Map<String, dynamic>> metadata,
  ) {
    return _normalize(
      '$table ${metadata.map((field) => '${field['campo'] ?? ''} ${field['etiqueta'] ?? ''}').join(' ')}',
    );
  }

  List<ZumacConsultantReportTable> _buildReportTables({
    required List<ZumacConsultantFinding> findings,
    required Map<String, List<Map<String, dynamic>>> metadataByTable,
    required Map<String, Map<String, String>> formatByTable,
    required List<Map<String, dynamic>> allRows,
    required _ConsultantPeriod? period,
  }) {
    final grouped = <String, List<ZumacConsultantFinding>>{};
    for (final finding in findings) {
      grouped.putIfAbsent(finding.tableName, () => []).add(finding);
    }
    final referenceLabels = _referenceLabels(allRows);
    final reports = <ZumacConsultantReportTable>[];
    for (final entry in grouped.entries) {
      final table = entry.key;
      final tableFindings = entry.value;
      final metadata = metadataByTable[table] ?? const <Map<String, dynamic>>[];
      final rows = tableFindings
          .map((finding) => finding.values)
          .where((row) => row.isNotEmpty)
          .toList(growable: false);
      if (rows.isEmpty) continue;

      final metadataByField = <String, Map<String, dynamic>>{};
      for (final field in metadata) {
        if (field['__consultant_context'] == true) continue;
        final key = _normalize(field['campo']?.toString() ?? '');
        if (key.isNotEmpty) metadataByField[key] = field;
      }
      final actualKeys = <String>[];
      final seenKeys = <String>{};
      for (final row in rows) {
        for (final key in row.keys) {
          final normalizedKey = _normalize(key);
          if (!_isReportableField(normalizedKey) ||
              !seenKeys.add(normalizedKey)) {
            continue;
          }
          final configuration = metadataByField[normalizedKey];
          if (configuration != null &&
              _isExplicitlyFalse(configuration['visible_tabla'])) {
            continue;
          }
          actualKeys.add(key);
        }
      }
      actualKeys.sort((a, b) {
        final aOrder = _fieldOrder(metadataByField[_normalize(a)]);
        final bOrder = _fieldOrder(metadataByField[_normalize(b)]);
        final compared = aOrder.compareTo(bOrder);
        return compared != 0 ? compared : a.compareTo(b);
      });
      final columns = actualKeys
          .map(
            (key) => ZumacConsultantReportColumn(
              key: key,
              label: _fieldLabel(key, metadataByField[_normalize(key)]),
            ),
          )
          .toList(growable: false);
      final displayRows = rows.take(100).map((row) {
        return <String, String>{
          for (final column in columns)
            column.key: _displayCellValue(
              _valueByNormalizedKey(row, column.key),
              column.key,
              referenceLabels,
            ),
        };
      }).toList(growable: false);
      final navigation = formatByTable[table];
      final baseTitle = navigation?['format_name']?.trim().isNotEmpty == true
          ? navigation!['format_name']!.trim()
          : _humanizeIdentifier(table);
      reports.add(
        ZumacConsultantReportTable(
          title: period == null ? baseTitle : '$baseTitle · ${period.label}',
          tableName: table,
          columns: columns,
          rows: displayRows,
          totalRows: rows.length,
          moduleId: navigation?['module_id'],
          formatId: navigation?['format_id'],
        ),
      );
    }
    return reports;
  }

  Map<String, String> _referenceLabels(List<Map<String, dynamic>> rows) {
    final labels = <String, String>{};
    for (final row in rows) {
      final label = _preferredRowDisplay(row);
      if (label.isEmpty) continue;
      for (final entry in row.entries) {
        final key = _normalize(entry.key);
        final value = entry.value?.toString().trim() ?? '';
        if (value.isEmpty ||
            !RegExp(
              r'^(ID|ID_LOCAL|ID_REGISTRO|CODIGO|DNI|DOCUMENTO)$',
            ).hasMatch(key)) {
          continue;
        }
        labels.putIfAbsent(value, () => label);
      }
    }
    return labels;
  }

  bool _isReportableField(String key) {
    if (key.isEmpty || key.startsWith('__')) return false;
    return !const {
      'ID',
      'ID_LOCAL',
      'ID_REGISTRO',
      'EMPRESA_ID',
      'USER_ID',
      'USUARIO_ID',
      'FORMATO_ID',
      'MODULO_ID',
      'RUBRO_ID',
      'VERSION',
      'VERSION_LOCAL',
      'VERSION_REMOTA',
      'PAYLOAD_JSON',
      'CONFLICT_JSON',
    }.contains(key);
  }

  bool _isExplicitlyFalse(dynamic value) {
    if (value == false || value == 0) return true;
    return const {'FALSE', 'NO', '0', 'N'}
        .contains(_normalize(value?.toString() ?? ''));
  }

  int _fieldOrder(Map<String, dynamic>? field) {
    if (field == null) return 100000;
    return int.tryParse(field['orden']?.toString() ?? '') ?? 100000;
  }

  String _fieldLabel(String key, Map<String, dynamic>? field) {
    final configured = field?['etiqueta']?.toString().trim() ?? '';
    return configured.isNotEmpty ? configured : _humanizeIdentifier(key);
  }

  dynamic _valueByNormalizedKey(Map<String, dynamic> row, String key) {
    final wanted = _normalize(key);
    for (final entry in row.entries) {
      if (_normalize(entry.key) == wanted) return entry.value;
    }
    return null;
  }

  String _displayCellValue(
    dynamic raw,
    String field,
    Map<String, String> referenceLabels,
  ) {
    if (raw == null) return '—';
    if (raw is bool) return raw ? 'Sí' : 'No';
    if (raw is Map || raw is List) return jsonEncode(raw);
    final value = raw.toString().trim();
    if (value.isEmpty || value.toLowerCase() == 'null') return '—';
    final normalizedField = _normalize(field);
    final referenced = referenceLabels[value];
    if (referenced != null &&
        (RegExp(r'(^ID$|^ID_|_ID$|CODIGO)').hasMatch(normalizedField) ||
            _looksOpaqueIdentifier(value))) {
      return referenced;
    }
    if (RegExp(r'FECHA|DATE|DIA|CREATED|UPDATED').hasMatch(normalizedField)) {
      final date = _parseDate(value);
      if (date != null) {
        final formatted =
            '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
        final hasTime = RegExp(r'[T ]\d{1,2}:\d{2}').hasMatch(value);
        if (hasTime) {
          return '$formatted ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
        }
        return formatted;
      }
    }
    return value;
  }

  String _smartAnswerFor({
    required String question,
    required ZumacConsultantIntent intent,
    required List<ZumacConsultantFinding> findings,
    required int inspected,
    required num? threshold,
    required _ConsultantPeriod? period,
    required Map<String, Map<String, String>> formatByTable,
    required _CrossTableResult? crossResult,
  }) {
    final periodSuffix = period == null ? '' : ' ${period.label}';
    final crossKind = crossResult?.kind;
    if (crossKind == 'attendance_worklog') {
      final attended = crossResult?.attendanceCount ?? 0;
      final worked = crossResult?.workLogCount ?? 0;
      final unmatched = crossResult?.unmatchedCount ?? 0;
      if (worked == 0 && attended > 0) {
        return 'Ninguno de los $attended asistidos tiene tareo$periodSuffix.';
      }
      final summary = 'Asistidos $attended, tareados $worked.';
      if (unmatched == 0) return summary;
      if (crossResult?.workLogWithoutAttendance == true) {
        return '$summary Encontré $unmatched '
            '${unmatched == 1 ? 'persona con tareo sin asistencia' : 'personas con tareo sin asistencia'}'
            '$periodSuffix.';
      }
      return '$summary Encontré $unmatched '
          '${unmatched == 1 ? 'persona con asistencia sin tareo' : 'personas con asistencia sin tareo'}'
          '$periodSuffix.';
    }
    if (findings.isEmpty) {
      if (inspected == 0) {
        return 'Todavía no hay datos sincronizados que pueda consultar. Actualiza los datos cuando tengas conexión y vuelve a intentarlo.';
      }
      if (crossKind == 'missing_relation') {
        return 'No encontré personas que cumplan la relación solicitada$periodSuffix.';
      }
      if (crossKind == 'pest_products') {
        return 'No encontré productos con stock cuyo campo Objetivo coincida con las plagas o enfermedades registradas$periodSuffix.';
      }
      return switch (intent) {
        ZumacConsultantIntent.phThreshold =>
          'No encontré valores de pH${threshold == null ? '' : ' mayores a ${_cleanNumber(threshold)}'}$periodSuffix.',
        ZumacConsultantIntent.absences =>
          'No encontré inasistencias registradas$periodSuffix.',
        ZumacConsultantIntent.attendance =>
          'No encontré asistencias registradas$periodSuffix.',
        ZumacConsultantIntent.knowledge ||
        ZumacConsultantIntent.crossTable ||
        ZumacConsultantIntent.generalSearch =>
          'No encontré registros que coincidan con esa pregunta$periodSuffix.',
      };
    }

    if (intent == ZumacConsultantIntent.attendance) {
      final unique = _uniquePeople(findings);
      final total = unique.length;
      final hasExitFields = unique.any(
        (finding) => finding.values.keys.any(
          (key) => RegExp(r'HORA.?SALIDA|FECHA.?SALIDA|^SALIDA$')
              .hasMatch(_normalize(key)),
        ),
      );
      if (hasExitFields) {
        final exited =
            unique.where((finding) => _hasRecordedExit(finding.values)).length;
        final pendingExit = total - exited;
        return 'Sí,${period == null ? '' : ' ${period.label}'} hay $total '
            '${total == 1 ? 'persona con asistencia' : 'personas con asistencia'}; '
            '$exited ${exited == 1 ? 'ya registró su salida' : 'ya registraron su salida'} '
            'y $pendingExit ${pendingExit == 1 ? 'aún no tiene salida' : 'aún no tienen salida'}.';
      }
      return 'Sí. Encontré $total '
          '${total == 1 ? 'persona con asistencia' : 'personas con asistencia'}$periodSuffix.';
    }
    if (intent == ZumacConsultantIntent.phThreshold) {
      final lots = findings
          .map((finding) => _firstValue(finding.values, const [
                'LOTE',
                'LOTE_ID',
                'ID_LOTE',
                'CAMPO',
                'SECTOR',
                'UBICACION',
                'TURNO',
              ]))
          .where((value) => value.isNotEmpty && !_looksOpaqueIdentifier(value))
          .toSet()
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      final limit =
          threshold == null ? 'el límite consultado' : _cleanNumber(threshold);
      if (lots.isNotEmpty) {
        return '${_capitalize(period?.label ?? 'En el periodo consultado')}, '
            '${lots.length == 1 ? 'el lote con pH mayor a $limit fue' : 'los lotes con pH mayor a $limit fueron'}: '
            '${lots.join(', ')}.';
      }
      return '${_capitalize(period?.label ?? 'En el periodo consultado')}, '
          'se encontraron ${findings.length} '
          '${findings.length == 1 ? 'medición de pH mayor' : 'mediciones de pH mayores'} a $limit, '
          'pero la fuente no contiene un lote legible para resumirlas.';
    }
    if (intent == ZumacConsultantIntent.absences) {
      return 'Sí. Encontré ${findings.length} '
          '${findings.length == 1 ? 'inasistencia registrada' : 'inasistencias registradas'}$periodSuffix.';
    }
    if (crossKind == 'missing_relation') {
      final people = _uniquePeople(findings).length;
      return 'Encontré $people '
          '${people == 1 ? 'persona con tareo que no tiene' : 'personas con tareo que no tienen'} '
          'asistencia registrada$periodSuffix.';
    }
    if (crossKind == 'pest_products') {
      final pestCount = findings
          .where(
            (finding) => RegExp(r'PLAGA|ENFERMEDAD').hasMatch(
              _normalize(finding.tableName),
            ),
          )
          .length;
      final productCount = findings.length - pestCount;
      final lots = findings
          .map((finding) => _firstValue(
                finding.values,
                const ['LOTE', 'LOTE_ID', 'ID_LOTE', 'UBICACION'],
              ))
          .where((value) => value.isNotEmpty)
          .toSet()
          .length;
      return 'Encontré $pestCount '
          '${pestCount == 1 ? 'hallazgo de plaga o enfermedad' : 'hallazgos de plagas o enfermedades'}'
          '${lots == 0 ? '' : ' en $lots ${lots == 1 ? 'lote' : 'lotes'}'}, '
          'y $productCount ${productCount == 1 ? 'producto con stock y objetivo coincidente' : 'productos con stock y objetivo coincidente'}$periodSuffix.';
    }

    if (question.contains('DONDE')) {
      final places = findings
          .map(
            (finding) => _firstValue(
              finding.values,
              const [
                'LOTE',
                'UBICACION',
                'FUNDO',
                'CAMPO',
                'SECTOR',
                'TURNO',
              ],
            ),
          )
          .where(
            (value) => value.isNotEmpty && !_looksOpaqueIdentifier(value),
          )
          .toSet();
      if (places.isNotEmpty) {
        return 'Encontré ${findings.length} '
            '${findings.length == 1 ? 'registro' : 'registros'}$periodSuffix en: '
            '${places.join(', ')}.';
      }
    }
    if (question.contains('QUIEN')) {
      final people = findings
          .map((finding) => _personDisplay(finding.values))
          .where(
            (value) => value.isNotEmpty && !_looksOpaqueIdentifier(value),
          )
          .toSet();
      if (people.isNotEmpty) {
        return 'Encontré ${findings.length} '
            '${findings.length == 1 ? 'registro relacionado con' : 'registros relacionados con'} '
            '${people.join(', ')}$periodSuffix.';
      }
    }
    if (question.contains('COMO') ||
        question.contains('ESTADO') ||
        question.contains('RESULTADO')) {
      final distribution = _categoricalDistribution(findings);
      if (distribution.isNotEmpty) {
        return 'Encontré ${findings.length} '
            '${findings.length == 1 ? 'registro' : 'registros'}$periodSuffix. '
            '${distribution.join('; ')}.';
      }
    }

    final tables = findings.map((finding) => finding.tableName).toSet();
    if (tables.length == 1) {
      final table = tables.single;
      final name =
          formatByTable[table]?['format_name']?.trim().isNotEmpty == true
              ? formatByTable[table]!['format_name']!.trim()
              : _humanizeIdentifier(table);
      final verb = question.contains('HUBO') ? 'hubo' : 'encontré';
      final periodLead = period == null ? '' : '${_capitalize(period.label)} ';
      return 'Sí. $periodLead$verb ${findings.length} '
          '${findings.length == 1 ? 'registro' : 'registros'} en $name.';
    }
    final sourceNames = tables
        .map(
          (table) =>
              formatByTable[table]?['format_name']?.trim().isNotEmpty == true
                  ? formatByTable[table]!['format_name']!.trim()
                  : _humanizeIdentifier(table),
        )
        .join(', ');
    return 'Encontré ${findings.length} registros relacionados en '
        '${tables.length} fuentes: $sourceNames$periodSuffix.';
  }

  List<String> _categoricalDistribution(
    List<ZumacConsultantFinding> findings,
  ) {
    final countsByField = <String, Map<String, int>>{};
    for (final finding in findings) {
      for (final entry in finding.values.entries) {
        final key = _normalize(entry.key);
        final value = entry.value?.toString().trim() ?? '';
        if (!RegExp(r'ESTADO|RESULTADO|CONDICION|TIPO|CLASIFICACION')
                .hasMatch(key) ||
            value.isEmpty ||
            _looksOpaqueIdentifier(value)) {
          continue;
        }
        countsByField
            .putIfAbsent(entry.key, () => <String, int>{})
            .update(value, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    return countsByField.entries.take(3).map((entry) {
      final values = entry.value.entries
          .map((value) => '${value.key}: ${value.value}')
          .join(', ');
      return '${_humanizeIdentifier(entry.key)} — $values';
    }).toList(growable: false);
  }

  List<ZumacConsultantFinding> _uniquePeople(
    List<ZumacConsultantFinding> findings,
  ) {
    final seen = <String>{};
    final unique = <ZumacConsultantFinding>[];
    for (final finding in findings) {
      final keys = _personKeys(finding.values);
      final identity = keys.isEmpty
          ? _rowFingerprint(finding.values)
          : (keys.toList()..sort()).first;
      if (seen.add(identity)) unique.add(finding);
    }
    return unique;
  }

  (String, String)? _recordIdentity(Map<String, dynamic> row) {
    const candidates = [
      'ID_LOCAL',
      'ID',
      'ID_REGISTRO',
      'CODIGO',
      'DNI',
    ];
    for (final candidate in candidates) {
      for (final entry in row.entries) {
        if (_normalize(entry.key) != candidate) continue;
        final value = entry.value?.toString().trim() ?? '';
        if (value.isNotEmpty) return (entry.key, value);
      }
    }
    return null;
  }

  _ConsultantPeriod? _periodFor(String question) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _ConsultantPeriod day(DateTime value, String label,
        {bool isToday = false}) {
      final start = DateTime(value.year, value.month, value.day);
      return _ConsultantPeriod(
        start: start,
        endExclusive: start.add(const Duration(days: 1)),
        label: label,
        isToday: isToday,
      );
    }

    final numericRange = RegExp(
      r'\b(?:DEL?\s+)?(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})\s+(?:AL?|HASTA)\s+(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})\b',
    ).firstMatch(question);
    if (numericRange != null) {
      final start = _validDate(
        int.parse(numericRange.group(3)!),
        int.parse(numericRange.group(2)!),
        int.parse(numericRange.group(1)!),
      );
      final end = _validDate(
        int.parse(numericRange.group(6)!),
        int.parse(numericRange.group(5)!),
        int.parse(numericRange.group(4)!),
      );
      if (start != null && end != null && !end.isBefore(start)) {
        return _ConsultantPeriod(
          start: start,
          endExclusive: end.add(const Duration(days: 1)),
          label: 'del ${_formatDate(start)} al ${_formatDate(end)}',
        );
      }
    }

    final numericDate = RegExp(r'\b(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})\b')
        .firstMatch(question);
    if (numericDate != null) {
      final date = _validDate(
        int.parse(numericDate.group(3)!),
        int.parse(numericDate.group(2)!),
        int.parse(numericDate.group(1)!),
      );
      if (date != null) return day(date, 'el ${_formatDate(date)}');
    }
    final isoDate = RegExp(r'\b(\d{4})[\/\-](\d{1,2})[\/\-](\d{1,2})\b')
        .firstMatch(question);
    if (isoDate != null) {
      final date = _validDate(
        int.parse(isoDate.group(1)!),
        int.parse(isoDate.group(2)!),
        int.parse(isoDate.group(3)!),
      );
      if (date != null) return day(date, 'el ${_formatDate(date)}');
    }
    final writtenDate = RegExp(
      r'\b(\d{1,2})\s+DE\s+(ENERO|FEBRERO|MARZO|ABRIL|MAYO|JUNIO|JULIO|AGOSTO|SEPTIEMBRE|OCTUBRE|NOVIEMBRE|DICIEMBRE)\s+(?:DE\s+)?(\d{4})\b',
    ).firstMatch(question);
    if (writtenDate != null) {
      const months = {
        'ENERO': 1,
        'FEBRERO': 2,
        'MARZO': 3,
        'ABRIL': 4,
        'MAYO': 5,
        'JUNIO': 6,
        'JULIO': 7,
        'AGOSTO': 8,
        'SEPTIEMBRE': 9,
        'OCTUBRE': 10,
        'NOVIEMBRE': 11,
        'DICIEMBRE': 12,
      };
      final date = _validDate(
        int.parse(writtenDate.group(3)!),
        months[writtenDate.group(2)!]!,
        int.parse(writtenDate.group(1)!),
      );
      if (date != null) return day(date, 'el ${_formatDate(date)}');
    }

    // Preguntas agregadas como "en julio" o "el mes de julio de 2025"
    // representan el mes completo. Si no se indica año se usa el actual,
    // que es el comportamiento esperado en una consulta operativa cotidiana.
    const monthNumbers = {
      'ENERO': 1,
      'FEBRERO': 2,
      'MARZO': 3,
      'ABRIL': 4,
      'MAYO': 5,
      'JUNIO': 6,
      'JULIO': 7,
      'AGOSTO': 8,
      'SEPTIEMBRE': 9,
      'OCTUBRE': 10,
      'NOVIEMBRE': 11,
      'DICIEMBRE': 12,
    };
    final writtenMonth = RegExp(
      r'\b(?:MES\s+DE\s+|EN\s+)?(ENERO|FEBRERO|MARZO|ABRIL|MAYO|JUNIO|JULIO|AGOSTO|SEPTIEMBRE|OCTUBRE|NOVIEMBRE|DICIEMBRE)(?:\s+(?:DE\s+)?(\d{4}))?\b',
    ).firstMatch(question);
    if (writtenMonth != null) {
      final monthName = writtenMonth.group(1)!;
      final year = int.tryParse(writtenMonth.group(2) ?? '') ?? today.year;
      final month = monthNumbers[monthName]!;
      return _ConsultantPeriod(
        start: DateTime(year, month),
        endExclusive: DateTime(year, month + 1),
        label: 'en ${monthName.toLowerCase()} de $year',
      );
    }
    if (question.contains('ANTEAYER')) {
      return day(
        today.subtract(const Duration(days: 2)),
        'anteayer',
      );
    }
    if (question.contains('AYER')) {
      return day(today.subtract(const Duration(days: 1)), 'ayer');
    }
    if (question.contains('HOY')) return day(today, 'hoy', isToday: true);

    final recentDays =
        RegExp(r'ULTIM(?:O|OS|A|AS)\s+(\d+)\s+DIAS?').firstMatch(question);
    if (recentDays != null) {
      final count = int.tryParse(recentDays.group(1)!) ?? 0;
      if (count > 0) {
        return _ConsultantPeriod(
          start: today.subtract(Duration(days: count - 1)),
          endExclusive: today.add(const Duration(days: 1)),
          label: 'en los últimos $count días',
        );
      }
    }
    if (question.contains('ESTA SEMANA')) {
      final start = today.subtract(Duration(days: today.weekday - 1));
      return _ConsultantPeriod(
        start: start,
        endExclusive: start.add(const Duration(days: 7)),
        label: 'esta semana',
      );
    }
    if (question.contains('ESTE MES')) {
      return _ConsultantPeriod(
        start: DateTime(today.year, today.month),
        endExclusive: DateTime(today.year, today.month + 1),
        label: 'este mes',
      );
    }
    if (question.contains('ESTE ANO')) {
      return _ConsultantPeriod(
        start: DateTime(today.year),
        endExclusive: DateTime(today.year + 1),
        label: 'este año',
      );
    }
    return null;
  }

  DateTime? _validDate(int year, int month, int day) {
    final value = DateTime(year, month, day);
    if (value.year != year || value.month != month || value.day != day) {
      return null;
    }
    return value;
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  bool _isInPeriod(Map<String, dynamic> row, _ConsultantPeriod period) {
    final businessDates = <DateTime>[];
    final fallbackDates = <DateTime>[];
    for (final entry in row.entries) {
      final key = _normalize(entry.key);
      final parsed = _parseDate(entry.value);
      if (parsed == null) continue;
      if (RegExp(r'FECHA|(^|_)DATE($|_)|(^|_)DIA($|_)').hasMatch(key) &&
          !RegExp(r'CREATED|UPDATED|CONSULTANT').hasMatch(key)) {
        businessDates.add(parsed);
      } else if (RegExp(r'CREATED|UPDATED|CONSULTANT_DATE').hasMatch(key)) {
        fallbackDates.add(parsed);
      }
    }
    final candidates = businessDates.isNotEmpty ? businessDates : fallbackDates;
    return candidates.any(
      (date) =>
          !date.isBefore(period.start) && date.isBefore(period.endExclusive),
    );
  }

  bool _hasUsableDate(Map<String, dynamic> row) {
    for (final entry in row.entries) {
      final key = _normalize(entry.key);
      if (RegExp(
        r'FECHA|(^|_)DATE($|_)|(^|_)DIA($|_)|CREATED|UPDATED|CONSULTANT_DATE',
      ).hasMatch(key)) {
        if (_parseDate(entry.value) != null) return true;
      }
    }
    return false;
  }

  Set<String> _personKeys(Map<String, dynamic> row) {
    final keys = <String>{};
    for (final entry in row.entries) {
      final field = _normalize(entry.key).replaceAll(' ', '_');
      final value = entry.value?.toString().trim() ?? '';
      if (value.isEmpty) continue;
      if (RegExp(
        r'(^DNI$|DOCUMENTO|ID_PERSONAL|PERSONAL_ID|ID_TRABAJADOR|TRABAJADOR_ID|ID_COLABORADOR|COLABORADOR_ID)',
      ).hasMatch(field)) {
        keys.add('PERSON:${_normalize(value)}');
      }
      if (RegExp(
        r'NOMBRE_COMPLETO|NOMBRES_Y_APELLIDOS|APELLIDOS_Y_NOMBRES|TRABAJADOR|COLABORADOR',
      ).hasMatch(field)) {
        keys.add('NAME:${_normalize(value)}');
      }
    }
    return keys;
  }

  String _personDisplay(Map<String, dynamic> row) => _firstValue(row, const [
        'NOMBRE_COMPLETO',
        'NOMBRES_Y_APELLIDOS',
        'APELLIDOS_Y_NOMBRES',
        'APELLIDOS Y NOMBRES',
        'TRABAJADOR',
        'COLABORADOR',
        'PERSONAL',
        'NOMBRE',
        'DNI',
      ]);

  String _preferredRowDisplay(Map<String, dynamic> row) {
    return _firstValue(row, const [
      'NOMBRE_COMPLETO',
      'NOMBRES_Y_APELLIDOS',
      'APELLIDOS_Y_NOMBRES',
      'APELLIDOS Y NOMBRES',
      'NOMBRE_PRODUCTO',
      'PRODUCTO',
      'TRABAJADOR',
      'COLABORADOR',
      'PLAGA',
      'ENFERMEDAD',
      'NOMBRE',
      'DESCRIPCION',
      'LOTE',
      'VARIEDAD',
    ]);
  }

  bool _hasRecordedExit(Map<String, dynamic> row) {
    for (final entry in row.entries) {
      if (!RegExp(r'HORA.?SALIDA|FECHA.?SALIDA|^SALIDA$')
          .hasMatch(_normalize(entry.key))) {
        continue;
      }
      final value = entry.value?.toString().trim() ?? '';
      if (value.isNotEmpty &&
          value.toLowerCase() != 'null' &&
          !_falsey(entry.value)) {
        return true;
      }
    }
    return false;
  }

  bool _hasPositiveStock(Map<String, dynamic> row) {
    for (final entry in row.entries) {
      if (!RegExp(r'STOCK|EXISTENCIA|DISPONIBLE|SALDO')
          .hasMatch(_normalize(entry.key))) {
        continue;
      }
      final numeric =
          num.tryParse(entry.value?.toString().replaceAll(',', '.') ?? '');
      if (numeric != null && numeric > 0) return true;
      if (numeric == null && _truthy(entry.value)) return true;
    }
    return false;
  }

  bool _looksOpaqueIdentifier(String value) {
    final clean = value.trim();
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F-]{20,}$|^[A-Za-z]+-[A-Za-z0-9-]*\d[A-Za-z0-9-]*$',
    ).hasMatch(clean);
  }

  String _humanizeIdentifier(String value) {
    var clean = value
        .trim()
        .replaceFirst(RegExp(r'^(GT|SN)[-_]'), '')
        .replaceAll(RegExp(r'[_\-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    if (clean.isEmpty) return value;
    clean = '${clean[0].toUpperCase()}${clean.substring(1)}';
    return clean;
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  String _displayDate(Map<String, dynamic> row) {
    for (final entry in row.entries) {
      if (!RegExp(r'FECHA|DATE|DIA|CREATED|CONSULTANT_DATE')
          .hasMatch(_normalize(entry.key))) {
        continue;
      }
      final date = _parseDate(entry.value);
      if (date != null) {
        return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
      }
    }
    return '';
  }

  DateTime? _parseDate(dynamic raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return null;
    final iso = DateTime.tryParse(value);
    if (iso != null) return iso.toLocal();
    final match =
        RegExp(r'^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})').firstMatch(value);
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(3)!),
      int.parse(match.group(2)!),
      int.parse(match.group(1)!),
    );
  }

  String _firstValue(Map<String, dynamic> row, List<String> candidates) {
    for (final candidate in candidates.map(_normalize)) {
      for (final entry in row.entries) {
        if (_normalize(entry.key) != candidate) continue;
        final value = entry.value?.toString().trim() ?? '';
        if (value.isNotEmpty) return value;
      }
    }
    return '';
  }

  String _rowFingerprint(Map<String, dynamic> row) {
    final identity = _recordIdentity(row);
    if (identity != null) return '${identity.$1}:${identity.$2}';
    return jsonEncode(row);
  }

  List<String> _tokens(String value) {
    const ignored = {
      'HAY',
      'LOS',
      'LAS',
      'UNA',
      'UNOS',
      'UNAS',
      'QUE',
      'DEL',
      'POR',
      'PARA',
      'CON',
      'HOY',
      'AYER',
      'ANTEAYER',
      'PERO',
      'SIN',
      'DONDE',
      'COMO',
      'QUIEN',
      'QUIENES',
      'HUBO',
      'AMBOS',
      'AUN',
      'MAYOR',
      'MAYORES',
      'CUALES',
      'CUAL',
      'CUANTOS',
      'CUANTO',
      'ESTAN',
      'ESTA',
      'EXISTE',
      'EXISTEN',
      'TIENE',
      'TIENEN',
      'ALGUN',
      'ALGUNA',
      'REGISTRO',
      'REGISTROS',
      'DATO',
      'DATOS',
      'INFORMACION',
    };
    return _normalize(value)
        .split(RegExp(r'[^A-Z0-9]+'))
        .where(
          (token) =>
              (token.length >= 3 || num.tryParse(token) != null) &&
              !ignored.contains(token),
        )
        .map(_stemToken)
        .where((token) => token.isNotEmpty)
        .toSet()
        .toList();
  }

  bool _textContainsToken(String text, String token) {
    final wanted = _stemToken(token);
    if (wanted.isEmpty) return false;
    final words = _normalize(text)
        .split(RegExp(r'[^A-Z0-9]+'))
        .map(_stemToken)
        .where((word) => word.isNotEmpty);
    for (final word in words) {
      if (word == wanted) return true;
      if (wanted.length >= 4 &&
          (word.contains(wanted) || wanted.contains(word))) {
        return true;
      }
    }
    return false;
  }

  String _stemToken(String raw) {
    var token = _normalize(raw).replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (token.length <= 3 || num.tryParse(token) != null) return token;
    if (token.endsWith('ES') &&
        token.length > 5 &&
        !const {'A', 'E', 'I', 'O', 'U'}.contains(token[token.length - 3])) {
      token = token.substring(0, token.length - 2);
    } else if (token.endsWith('S')) {
      token = token.substring(0, token.length - 1);
    }
    if (token == 'MATRIC') return 'MATRIZ';
    return token;
  }

  bool _truthy(dynamic value) {
    if (value == true) return true;
    if (value is num) return value != 0;
    return const {'SI', 'TRUE', '1', 'S', 'YES'}
        .contains(_normalize(value?.toString() ?? ''));
  }

  bool _falsey(dynamic value) {
    if (value == false) return true;
    if (value is num) return value == 0;
    return const {'NO', 'FALSE', '0', 'N'}
        .contains(_normalize(value?.toString() ?? ''));
  }

  String _cleanNumber(num value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toString();

  String _normalize(String value) {
    var output = value.trim().toUpperCase();
    const replacements = {
      'Á': 'A',
      'É': 'E',
      'Í': 'I',
      'Ó': 'O',
      'Ú': 'U',
      'Ü': 'U',
      'Ñ': 'N',
    };
    replacements.forEach((source, target) {
      output = output.replaceAll(source, target);
    });
    return output;
  }
}
