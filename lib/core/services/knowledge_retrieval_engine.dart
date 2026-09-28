import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

typedef KnowledgeSemanticSearch = Future<Map<String, double>> Function(
  String query,
  List<KnowledgeDocument> documents,
);

class KnowledgeSource {
  final String id;
  final String code;
  final String name;
  final int priority;
  final bool active;
  final bool exactEnabled;
  final bool fuzzyEnabled;
  final bool semanticEnabled;
  final double sufficiencyThreshold;

  const KnowledgeSource({
    required this.id,
    required this.code,
    required this.name,
    required this.priority,
    this.active = true,
    this.exactEnabled = true,
    this.fuzzyEnabled = true,
    this.semanticEnabled = false,
    this.sufficiencyThreshold = 0.42,
  });

  factory KnowledgeSource.fromMap(Map<String, dynamic> row) {
    return KnowledgeSource(
      id: row['id']?.toString() ?? '',
      code: row['codigo']?.toString() ?? '',
      name: row['nombre']?.toString() ?? row['codigo']?.toString() ?? '',
      priority: (row['prioridad'] as num?)?.toInt() ?? 100,
      active: _bool(row['activa'], fallback: true),
      exactEnabled: _bool(row['permite_exacta'], fallback: true),
      fuzzyEnabled: _bool(row['permite_difusa'], fallback: true),
      semanticEnabled: _bool(row['permite_semantica']),
      sufficiencyThreshold:
          (row['umbral_suficiencia'] as num?)?.toDouble() ?? 0.42,
    );
  }

  static bool _bool(dynamic value, {bool fallback = false}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    return const {'TRUE', 'T', '1', 'SI', 'SÍ', 'YES'}
        .contains(value.toString().trim().toUpperCase());
  }
}

/// Conexión dirigida entre dos entradas de la base de conocimiento.
///
/// [destinationDocumentId] puede ser nulo cuando la IA solo reconoció un
/// concepto. Cuando contiene un UUID, el motor puede recuperar y leer el
/// documento de destino, manteniendo el tipo y la fuerza de la relación.
class KnowledgeRelation {
  final String? destinationDocumentId;
  final String destinationConcept;
  final String type;
  final double weight;

  const KnowledgeRelation({
    this.destinationDocumentId,
    required this.destinationConcept,
    this.type = 'RELACIONADO_CON',
    this.weight = 0.70,
  });

  factory KnowledgeRelation.fromMap(Map<dynamic, dynamic> row) {
    final destinationId = row['documento_destino_id']?.toString().trim();
    return KnowledgeRelation(
      destinationDocumentId:
          destinationId == null || destinationId.isEmpty ? null : destinationId,
      destinationConcept:
          (row['concepto_destino'] ?? row['concepto'] ?? '').toString().trim(),
      type: (row['tipo_relacion'] ?? 'RELACIONADO_CON').toString().trim(),
      weight: ((row['peso'] as num?)?.toDouble() ?? 0.70).clamp(0, 1),
    );
  }
}

class KnowledgeDocument {
  final String id;
  final String sourceCode;
  final String sourceName;
  final int sourcePriority;
  final String title;
  final String entityType;
  final String status;
  final Map<String, dynamic> content;
  final Map<String, dynamic> metadata;
  final List<KnowledgeRelation> relations;
  final List<String> relatedConcepts;
  final String searchText;

  const KnowledgeDocument({
    required this.id,
    required this.sourceCode,
    required this.sourceName,
    required this.sourcePriority,
    required this.title,
    required this.entityType,
    required this.status,
    required this.content,
    this.metadata = const <String, dynamic>{},
    this.relations = const <KnowledgeRelation>[],
    this.relatedConcepts = const <String>[],
    this.searchText = '',
  });

  factory KnowledgeDocument.fromMap(
    Map<String, dynamic> row,
    KnowledgeSource source,
  ) {
    final content = _map(row['contenido_estructurado']);
    final metadata = _map(row['metadata']);
    final relationRows = row['relaciones'] is Iterable
        ? (row['relaciones'] as Iterable)
            .whereType<Map>()
            .map(KnowledgeRelation.fromMap)
            .toList(growable: false)
        : const <KnowledgeRelation>[];
    final relatedConcepts = <String>{
      ..._strings(content['conceptos_relacionados']),
      ...relationRows.map((relation) => relation.destinationConcept),
    };
    return KnowledgeDocument(
      id: row['id']?.toString() ?? '',
      sourceCode: source.code,
      sourceName: source.name,
      sourcePriority: source.priority,
      title: row['titulo']?.toString() ?? '',
      entityType: row['entidad_tipo']?.toString() ?? 'DOCUMENTO',
      status: row['estado']?.toString() ?? 'GENERADA_IA',
      content: content,
      metadata: metadata,
      relations: relationRows,
      relatedConcepts:
          relatedConcepts.where((value) => value.isNotEmpty).toList(),
      searchText: row['contenido_busqueda']?.toString() ?? '',
    );
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  static List<String> _strings(dynamic value) {
    if (value is! Iterable) return const <String>[];
    return value
        .map((item) {
          if (item is Map) {
            return (item['concepto_destino'] ?? item['concepto'] ?? '')
                .toString()
                .trim();
          }
          return item.toString().trim();
        })
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  String get searchableText {
    if (searchText.trim().isNotEmpty) return searchText;
    return '$title ${content.values.join(' ')} ${metadata.values.join(' ')} '
        '${relatedConcepts.join(' ')}';
  }
}

class KnowledgeCitation {
  final String documentId;
  final String title;
  final String sourceCode;
  final String sourceName;
  final String status;
  final double score;
  final List<String> matchModes;

  const KnowledgeCitation({
    required this.documentId,
    required this.title,
    required this.sourceCode,
    required this.sourceName,
    required this.status,
    required this.score,
    required this.matchModes,
  });

  Map<String, dynamic> toJson() => {
        'documento_id': documentId,
        'titulo': title,
        'fuente_codigo': sourceCode,
        'fuente': sourceName,
        'estado': status,
        'puntaje': score,
        'coincidencias': matchModes,
      };
}

class KnowledgeAnswer {
  final String question;
  final String contextualQuestion;
  final String answer;
  final bool sufficient;
  final List<KnowledgeCitation> citations;
  final List<String> relatedConcepts;
  final List<String> inspectedSources;

  const KnowledgeAnswer({
    required this.question,
    required this.contextualQuestion,
    required this.answer,
    required this.sufficient,
    required this.citations,
    required this.relatedConcepts,
    required this.inspectedSources,
  });
}

abstract class KnowledgeRepository {
  Future<List<KnowledgeSource>> loadSources();

  Future<List<KnowledgeDocument>> loadDocuments(
    KnowledgeSource source, {
    required String query,
    int limit = 300,
  });

  /// Recupera por UUID los documentos conectados. Esta operación no guarda
  /// conversación: solo expande la evidencia disponible para la respuesta.
  Future<List<KnowledgeDocument>> loadDocumentsByIds(
    Iterable<String> documentIds, {
    int limit = 12,
  });
}

class SupabaseKnowledgeRepository implements KnowledgeRepository {
  static const _cacheTtl = Duration(minutes: 5);
  static const _requestTimeout = Duration(seconds: 7);

  final SupabaseClient? _providedClient;
  final Map<String, KnowledgeSource> _sourcesByCode = {};
  List<KnowledgeSource>? _cachedSources;
  DateTime? _sourcesCachedAt;
  final Map<String, _KnowledgeDocumentsCache> _documentCache = {};
  final Map<String, _KnowledgeSearchCache> _searchCache = {};

  SupabaseKnowledgeRepository({SupabaseClient? client})
      : _providedClient = client;

  SupabaseClient get client => _providedClient ?? Supabase.instance.client;

  @override
  Future<List<KnowledgeSource>> loadSources() async {
    final now = DateTime.now();
    if (_cachedSources != null &&
        _sourcesCachedAt != null &&
        now.difference(_sourcesCachedAt!) < _cacheTtl) {
      return _cachedSources!;
    }
    try {
      final rows = await client
          .from('FUENTES_CONOCIMIENTO_APPGT')
          .select()
          .eq('activa', true)
          .order('prioridad')
          .timeout(_requestTimeout);
      final sources = List<Map<String, dynamic>>.from(rows)
          .map(KnowledgeSource.fromMap)
          .where((source) => source.code.isNotEmpty)
          .toList(growable: false);
      _sourcesByCode
        ..clear()
        ..addEntries(sources.map((source) => MapEntry(source.code, source)));
      _cachedSources = sources;
      _sourcesCachedAt = now;
      return sources;
    } catch (_) {
      return const <KnowledgeSource>[];
    }
  }

  @override
  Future<List<KnowledgeDocument>> loadDocuments(
    KnowledgeSource source, {
    required String query,
    int limit = 300,
  }) async {
    final serverSearch = await _loadServerSearch(query, limit: limit);
    if (serverSearch != null) {
      return (serverSearch[source.code] ?? const <KnowledgeDocument>[])
          .take(limit)
          .toList(growable: false);
    }

    // Compatibilidad con bases que todavía no tienen desplegada la función de
    // búsqueda. Esta ruta carga una fuente completa, pero conserva una caché
    // corta para no repetir la descarga en cada pregunta de la conversación.
    final cached = _documentCache[source.code];
    if (cached != null &&
        DateTime.now().difference(cached.createdAt) < _cacheTtl) {
      return cached.documents.take(limit).toList(growable: false);
    }
    try {
      final response = await client
          .from('BASE_CONOCIMIENTO_APPGT')
          .select()
          .eq('fuente_codigo', source.code)
          .eq('estado', 'APROBADA')
          .limit(limit)
          .timeout(_requestTimeout);
      final rows = List<Map<String, dynamic>>.from(response)
          .map(Map<String, dynamic>.from)
          .toList(growable: false);
      await _attachRelations(rows);
      final documents = rows
          .map((row) => KnowledgeDocument.fromMap(row, source))
          .toList(growable: false);
      _documentCache[source.code] = _KnowledgeDocumentsCache(
        createdAt: DateTime.now(),
        documents: documents,
      );
      return documents;
    } catch (_) {
      return const <KnowledgeDocument>[];
    }
  }

  /// Usa la búsqueda textual/fuzzy del servidor y devuelve únicamente
  /// conocimiento revisado. `null` significa que el RPC no está disponible y
  /// habilita el fallback compatible; un mapa vacío es una búsqueda válida sin
  /// resultados.
  Future<Map<String, List<KnowledgeDocument>>?> _loadServerSearch(
    String query, {
    required int limit,
  }) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const {};
    final cached = _searchCache[normalized];
    if (cached != null &&
        DateTime.now().difference(cached.createdAt) < _cacheTtl) {
      return cached.documentsBySource;
    }

    try {
      final raw = await client.rpc(
        'appgt_buscar_conocimiento_v1',
        params: {
          'p_consulta': query.trim(),
          'p_limite': math.min(limit, 120),
          'p_incluir_generada_ia': false,
        },
      ).timeout(_requestTimeout);
      final rows = raw is List
          ? List<Map<String, dynamic>>.from(raw)
          : const <Map<String, dynamic>>[];
      final grouped = <String, List<KnowledgeDocument>>{};
      for (final result in rows) {
        final documentRaw = result['documento'];
        final sourceRaw = result['fuente'];
        if (documentRaw is! Map || sourceRaw is! Map) continue;
        final sourceMap = Map<String, dynamic>.from(sourceRaw);
        final resolvedSource = KnowledgeSource.fromMap(sourceMap);
        if (!resolvedSource.active || resolvedSource.code.isEmpty) continue;
        _sourcesByCode[resolvedSource.code] = resolvedSource;

        final documentMap = Map<String, dynamic>.from(documentRaw);
        final rawRelations = result['relaciones'];
        if (rawRelations is List) {
          documentMap['relaciones'] = rawRelations
              .whereType<Map>()
              .map(Map<String, dynamic>.from)
              .where((relation) => relation['estado'] == 'APROBADA')
              .toList(growable: false);
        }
        final document = KnowledgeDocument.fromMap(
          documentMap,
          resolvedSource,
        );
        grouped.putIfAbsent(resolvedSource.code, () => []).add(document);
      }
      _searchCache[normalized] = _KnowledgeSearchCache(
        createdAt: DateTime.now(),
        documentsBySource: grouped,
      );
      return grouped;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<KnowledgeDocument>> loadDocumentsByIds(
    Iterable<String> documentIds, {
    int limit = 12,
  }) async {
    final ids = documentIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .take(limit)
        .toList(growable: false);
    if (ids.isEmpty) return const <KnowledgeDocument>[];
    try {
      final response = await client
          .from('BASE_CONOCIMIENTO_APPGT')
          .select()
          .inFilter('id', ids)
          .eq('estado', 'APROBADA')
          .timeout(_requestTimeout);
      final rows = List<Map<String, dynamic>>.from(response)
          .map(Map<String, dynamic>.from)
          .toList(growable: false);
      await _attachRelations(rows);
      return rows.map((row) {
        final code = row['fuente_codigo']?.toString() ?? '';
        final source = _sourcesByCode[code] ??
            KnowledgeSource(
              id: row['fuente_id']?.toString() ?? '',
              code: code,
              name: code.isEmpty ? 'Base de conocimiento' : code,
              priority: 999,
            );
        return KnowledgeDocument.fromMap(row, source);
      }).toList(growable: false);
    } catch (_) {
      return const <KnowledgeDocument>[];
    }
  }

  Future<void> _attachRelations(List<Map<String, dynamic>> rows) async {
    final relationsByDocument = <String, List<Map<String, dynamic>>>{};
    final ids = rows
        .map((row) => row['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    const batchSize = 80;
    for (var start = 0; start < ids.length; start += batchSize) {
      final end = math.min(start + batchSize, ids.length);
      try {
        final relationResponse = await client
            .from('RELACIONES_CONOCIMIENTO_APPGT')
            .select(
              'documento_origen_id, documento_destino_id, concepto_destino, '
              'tipo_relacion, peso',
            )
            .inFilter('documento_origen_id', ids.sublist(start, end))
            .eq('estado', 'APROBADA')
            .order('peso', ascending: false)
            .timeout(_requestTimeout);
        for (final relation
            in List<Map<String, dynamic>>.from(relationResponse)) {
          final documentId = relation['documento_origen_id']?.toString() ?? '';
          relationsByDocument.putIfAbsent(documentId, () => []).add(relation);
        }
      } catch (_) {
        // Los conceptos embebidos en el documento siguen siendo utilizables.
      }
    }
    for (final row in rows) {
      row['relaciones'] = relationsByDocument[row['id']?.toString()] ?? [];
    }
  }
}

class _KnowledgeDocumentsCache {
  const _KnowledgeDocumentsCache({
    required this.createdAt,
    required this.documents,
  });

  final DateTime createdAt;
  final List<KnowledgeDocument> documents;
}

class _KnowledgeSearchCache {
  const _KnowledgeSearchCache({
    required this.createdAt,
    required this.documentsBySource,
  });

  final DateTime createdAt;
  final Map<String, List<KnowledgeDocument>> documentsBySource;
}

class InMemoryKnowledgeRepository implements KnowledgeRepository {
  final List<KnowledgeSource> sources;
  final List<KnowledgeDocument> documents;

  InMemoryKnowledgeRepository({
    required this.sources,
    required this.documents,
  });

  @override
  Future<List<KnowledgeSource>> loadSources() async => sources;

  @override
  Future<List<KnowledgeDocument>> loadDocuments(
    KnowledgeSource source, {
    required String query,
    int limit = 300,
  }) async {
    return documents
        .where((document) => document.sourceCode == source.code)
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<List<KnowledgeDocument>> loadDocumentsByIds(
    Iterable<String> documentIds, {
    int limit = 12,
  }) async {
    final ids = documentIds.toSet();
    return documents
        .where((document) => ids.contains(document.id))
        .take(limit)
        .toList(growable: false);
  }
}

class _KnowledgeTurn {
  final String question;
  final List<String> topics;

  const _KnowledgeTurn(this.question, this.topics);
}

class KnowledgeConversationMemory {
  final int maxTurns;
  final Map<String, List<_KnowledgeTurn>> _turns = {};

  KnowledgeConversationMemory({this.maxTurns = 8});

  bool hasContext(String conversationId) =>
      _turns[conversationId]?.isNotEmpty == true;

  String contextualize(String conversationId, String question) {
    final history = _turns[conversationId];
    if (history == null || history.isEmpty || !_isFollowUp(question)) {
      return question;
    }
    final topics = history.reversed
        .expand((turn) => turn.topics)
        .where((topic) => topic.trim().isNotEmpty)
        .toSet()
        .take(6)
        .join(', ');
    return topics.isEmpty ? question : '$question. Contexto anterior: $topics';
  }

  void remember(
    String conversationId,
    String question,
    Iterable<String> topics,
  ) {
    final turns = _turns.putIfAbsent(conversationId, () => []);
    turns.add(_KnowledgeTurn(question, topics.toSet().take(10).toList()));
    if (turns.length > maxTurns) {
      turns.removeRange(0, turns.length - maxTurns);
    }
  }

  void clear(String conversationId) => _turns.remove(conversationId);

  bool _isFollowUp(String question) {
    final normalized = KnowledgeText.normalize(question);
    final tokens = KnowledgeText.tokens(question);
    if (tokens.length <= 4) return true;
    return RegExp(
      r'(^| )(Y|ESO|ESA|ESTE|ESTA|ELLOS|ELLAS|TAMBIEN|ADEMAS|ENTONCES|RIESGOS|ERRORES|CUANDO|QUIEN|FRECUENCIA)( |$)',
    ).hasMatch(normalized);
  }
}

class _ScoredDocument {
  final KnowledgeDocument document;
  final double score;
  final List<String> modes;

  const _ScoredDocument(this.document, this.score, this.modes);
}

class KnowledgeRetrievalEngine {
  static const String notFoundAnswer =
      'No encontré información suficiente en la base de conocimiento de la empresa.';

  final KnowledgeRepository repository;
  final KnowledgeSemanticSearch? semanticSearch;
  final KnowledgeConversationMemory memory;
  final int maxDocumentsPerSource;
  final int maxConnectedDocuments;
  final int maxRelationDepth;

  KnowledgeRetrievalEngine({
    required this.repository,
    this.semanticSearch,
    KnowledgeConversationMemory? memory,
    this.maxDocumentsPerSource = 300,
    this.maxConnectedDocuments = 6,
    this.maxRelationDepth = 2,
  }) : memory = memory ?? KnowledgeConversationMemory();

  factory KnowledgeRetrievalEngine.supabase({SupabaseClient? client}) {
    return KnowledgeRetrievalEngine(
      repository: SupabaseKnowledgeRepository(client: client),
    );
  }

  bool hasConversationContext(String conversationId) =>
      memory.hasContext(conversationId);

  void clearConversation(String conversationId) => memory.clear(conversationId);

  Future<KnowledgeAnswer> ask(
    String rawQuestion, {
    String conversationId = 'default',
  }) async {
    final question = rawQuestion.trim();
    if (question.isEmpty) {
      return const KnowledgeAnswer(
        question: '',
        contextualQuestion: '',
        answer: notFoundAnswer,
        sufficient: false,
        citations: <KnowledgeCitation>[],
        relatedConcepts: <String>[],
        inspectedSources: <String>[],
      );
    }

    final contextualQuestion = memory.contextualize(conversationId, question);
    final sources = (await repository.loadSources())
        .where((source) => source.active)
        .toList()
      ..sort((a, b) {
        final priority = a.priority.compareTo(b.priority);
        return priority == 0 ? a.code.compareTo(b.code) : priority;
      });
    final sourcesByCode = <String, KnowledgeSource>{
      for (final source in sources) source.code: source,
    };
    final inspectedSources = <String>[];
    final selected = <_ScoredDocument>[];

    for (final source in sources) {
      inspectedSources.add(source.name);
      final documents = await repository.loadDocuments(
        source,
        query: contextualQuestion,
        limit: maxDocumentsPerSource,
      );
      if (documents.isEmpty) continue;

      Map<String, double> semanticScores = const {};
      if (source.semanticEnabled && semanticSearch != null) {
        try {
          semanticScores = await semanticSearch!(contextualQuestion, documents);
        } catch (_) {
          semanticScores = const {};
        }
      }
      final scored = documents
          .map(
            (document) => _score(
              contextualQuestion,
              document,
              source,
              semanticScores[document.id] ?? 0,
            ),
          )
          .where((item) => item.score >= 0.16)
          .toList()
        ..sort((a, b) => b.score.compareTo(a.score));
      if (scored.isEmpty) continue;

      final best = scored.first.score;
      selected.addAll(scored.where(
        (item) => item.score >= math.max(0.24, best - 0.16),
      ));
      if (best >= source.sufficiencyThreshold) break;
    }

    selected.sort((a, b) {
      final priority =
          a.document.sourcePriority.compareTo(b.document.sourcePriority);
      return priority == 0 ? b.score.compareTo(a.score) : priority;
    });
    final unique = <_ScoredDocument>[];
    final seen = <String>{};
    for (final item in selected) {
      if (seen.add(item.document.id)) unique.add(item);
      if (unique.length == 4) break;
    }

    // Los resultados directos son el punto de entrada. A partir de ellos se
    // leen los UUID de destino y se recupera contenido conectado hasta una
    // profundidad acotada. Esto evita ciclos y explosiones de resultados.
    if (unique.isNotEmpty && maxConnectedDocuments > 0) {
      final connected = await _expandConnectedDocuments(
        contextualQuestion,
        unique,
        sourcesByCode,
      );
      for (final item in connected) {
        if (seen.add(item.document.id)) unique.add(item);
        if (unique.length >= 4 + maxConnectedDocuments) break;
      }
    }

    final sufficient = unique.isNotEmpty && unique.first.score >= 0.34;
    final related = sufficient
        ? unique
            .expand((item) => <String>[
                  item.document.title,
                  ...item.document.relatedConcepts,
                ])
            .where((item) => item.trim().isNotEmpty)
            .toSet()
            .take(12)
            .toList(growable: false)
        : const <String>[];
    final citations = sufficient
        ? unique
            .map(
              (item) => KnowledgeCitation(
                documentId: item.document.id,
                title: item.document.title,
                sourceCode: item.document.sourceCode,
                sourceName: item.document.sourceName,
                status: item.document.status,
                score: item.score,
                matchModes: item.modes,
              ),
            )
            .toList(growable: false)
        : const <KnowledgeCitation>[];
    final answer = KnowledgeAnswer(
      question: question,
      contextualQuestion: contextualQuestion,
      answer: sufficient
          ? _composeGroundedAnswer(question, unique)
          : notFoundAnswer,
      sufficient: sufficient,
      citations: citations,
      relatedConcepts: related,
      inspectedSources: inspectedSources,
    );

    if (sufficient) {
      memory.remember(conversationId, question, related);
    }
    return answer;
  }

  Future<List<_ScoredDocument>> _expandConnectedDocuments(
    String query,
    List<_ScoredDocument> seeds,
    Map<String, KnowledgeSource> sourcesByCode,
  ) async {
    final relationQuestion = RegExp(
      r'\b(RELACION|CONECTA|DEPENDE|COMPLEMENTA|VINCULA|GRAFO)\b',
    ).hasMatch(KnowledgeText.normalize(query));
    final visited = seeds.map((item) => item.document.id).toSet();
    var frontier = List<_ScoredDocument>.from(seeds);
    final expanded = <_ScoredDocument>[];

    for (var depth = 0;
        depth < maxRelationDepth && frontier.isNotEmpty;
        depth++) {
      final relationByDestination =
          <String, (_ScoredDocument, KnowledgeRelation)>{};
      for (final origin in frontier) {
        for (final relation in origin.document.relations) {
          final destinationId = relation.destinationDocumentId;
          if (destinationId == null ||
              visited.contains(destinationId) ||
              relation.weight < 0.35) {
            continue;
          }
          final current = relationByDestination[destinationId];
          if (current == null || current.$2.weight < relation.weight) {
            relationByDestination[destinationId] = (origin, relation);
          }
        }
      }
      if (relationByDestination.isEmpty) break;

      final documents = await repository.loadDocumentsByIds(
        relationByDestination.keys,
        limit: maxConnectedDocuments * 2,
      );
      final nextFrontier = <_ScoredDocument>[];
      for (final document in documents) {
        final connection = relationByDestination[document.id];
        if (connection == null) continue;
        final source = sourcesByCode[document.sourceCode] ??
            KnowledgeSource(
              id: '',
              code: document.sourceCode,
              name: document.sourceName,
              priority: document.sourcePriority,
            );
        final directScore = _score(query, document, source, 0);
        final relationScore = connection.$1.score *
            connection.$2.weight *
            (depth == 0 ? 0.90 : 0.72);
        final score = math.max(directScore.score, relationScore);
        final explicitlyRelevant =
            directScore.score >= (depth == 0 ? 0.20 : 0.30);

        // En preguntas de relaciones se leen todos los destinos directos. En
        // consultas normales solo se agrega su contenido si también coincide
        // con la pregunta, para no contaminar la respuesta con ramas lejanas.
        if (!(explicitlyRelevant || (relationQuestion && depth == 0))) continue;
        final modes = <String>{
          ...directScore.modes,
          'relación:${connection.$2.type}',
        }.toList(growable: false);
        final candidate = _ScoredDocument(document, score, modes);
        visited.add(document.id);
        expanded.add(candidate);
        nextFrontier.add(candidate);
      }
      frontier = nextFrontier;
      if (expanded.length >= maxConnectedDocuments) break;
    }

    expanded.sort((a, b) => b.score.compareTo(a.score));
    return expanded.take(maxConnectedDocuments).toList(growable: false);
  }

  _ScoredDocument _score(
    String query,
    KnowledgeDocument document,
    KnowledgeSource source,
    double semantic,
  ) {
    final normalizedQuery = KnowledgeText.normalize(query);
    final normalizedTitle = KnowledgeText.normalize(document.title);
    final normalizedDocument = KnowledgeText.normalize(document.searchableText);
    final queryTokens = KnowledgeText.tokens(query);
    final documentTokens =
        KnowledgeText.tokens(document.searchableText).toSet();
    final titleTokens = KnowledgeText.tokens(document.title).toSet();
    final modes = <String>[];
    var exact = 0.0;
    if (source.exactEnabled) {
      if (normalizedQuery == normalizedTitle) {
        exact = 1;
      } else if (normalizedTitle.length >= 3 &&
          normalizedQuery.contains(normalizedTitle)) {
        exact = 0.96;
      } else if (normalizedQuery.length >= 4 &&
          normalizedDocument.contains(normalizedQuery)) {
        exact = 0.90;
      } else if (queryTokens.isNotEmpty) {
        final matched = queryTokens.where(documentTokens.contains).length;
        final recall = matched / queryTokens.length;
        final titleMatched = queryTokens.where(titleTokens.contains).length;
        exact = (recall * 0.68 + (titleMatched / queryTokens.length) * 0.24)
            .clamp(0, 0.88);
      }
      if (exact >= 0.25) modes.add('exacta');
    }

    var fuzzy = 0.0;
    if (source.fuzzyEnabled && queryTokens.isNotEmpty) {
      final candidateTokens = <String>{...titleTokens, ...documentTokens};
      var sum = 0.0;
      for (final token in queryTokens) {
        var best = 0.0;
        for (final candidate in candidateTokens) {
          if ((token.length - candidate.length).abs() > 3) continue;
          best = math.max(best, KnowledgeText.similarity(token, candidate));
          if (best == 1) break;
        }
        sum += best;
      }
      final average = sum / queryTokens.length;
      var strongestTitleMatch = 0.0;
      for (final token in queryTokens) {
        for (final candidate in titleTokens) {
          strongestTitleMatch = math.max(
            strongestTitleMatch,
            KnowledgeText.similarity(token, candidate),
          );
        }
      }
      final titleBoost = strongestTitleMatch >= 0.70;
      fuzzy = (average * 0.60 + (titleBoost ? 0.20 : 0)).clamp(0, 0.82);
      if (titleBoost) {
        fuzzy = math.max(fuzzy, strongestTitleMatch * 0.84);
      }
      if (fuzzy >= 0.35) modes.add('difusa');
    }

    final semanticScore =
        source.semanticEnabled ? semantic.clamp(0.0, 1.0).toDouble() : 0.0;
    if (semanticScore >= 0.25) modes.add('semántica');
    final score = math.max(exact, math.max(fuzzy, semanticScore));
    return _ScoredDocument(document, score, modes);
  }

  String _composeGroundedAnswer(
    String question,
    List<_ScoredDocument> documents,
  ) {
    final wantedKeys = _requestedSections(question);
    final paragraphs = <String>[];
    for (var index = 0; index < documents.length; index++) {
      final document = documents[index].document;
      final values = <String>[];
      for (final key in wantedKeys) {
        final rendered = _renderValue(document.content[key]);
        if (rendered.isNotEmpty) values.add(rendered);
      }
      if (values.isEmpty) {
        for (final key in const [
          'descripcion_general',
          'objetivo',
          'para_que_sirve',
        ]) {
          final rendered = _renderValue(document.content[key]);
          if (rendered.isNotEmpty) values.add(rendered);
        }
      }
      if (values.isEmpty) continue;
      final prefix =
          documents.length == 1 ? '' : '${document.title} [${index + 1}]: ';
      paragraphs.add('$prefix${values.join('\n')}');
    }
    if (paragraphs.isEmpty) return notFoundAnswer;
    if (documents.length == 1) {
      return '${paragraphs.join('\n\n')}\n\nFuente: [1] ${documents.first.document.sourceName}.';
    }
    final sources = <String>[];
    for (var index = 0; index < documents.length; index++) {
      sources.add('[${index + 1}] ${documents[index].document.sourceName} — '
          '${documents[index].document.title}');
    }
    return '${paragraphs.join('\n\n')}\n\nFuentes: ${sources.join('; ')}.';
  }

  List<String> _requestedSections(String question) {
    final normalized = KnowledgeText.normalize(question);
    final keys = <String>[];
    void addIf(RegExp pattern, String key) {
      if (pattern.hasMatch(normalized)) keys.add(key);
    }

    addIf(RegExp(r'DESCRIP|QUE ES|DE QUE TRATA'), 'descripcion_general');
    addIf(RegExp(r'OBJETIV'), 'objetivo');
    addIf(RegExp(r'PARA QUE|SIRVE|UTILIDAD'), 'para_que_sirve');
    addIf(RegExp(r'QUIEN|RESPONSABL|UTILIZA'), 'quien_lo_utiliza');
    addIf(RegExp(r'CUANDO|MOMENTO'), 'cuando_se_utiliza');
    addIf(RegExp(r'FRECUEN|CADA CUANTO'), 'frecuencia_uso');
    addIf(RegExp(r'EJEMPLO|CASO'), 'ejemplo_utilizacion');
    addIf(RegExp(r'RELACION|CONECTA|GRAFO'), 'conceptos_relacionados');
    addIf(RegExp(r'ERROR|FALLA'), 'errores_comunes');
    addIf(RegExp(r'BUENA.*PRACT|RECOMEND'), 'buenas_practicas');
    addIf(RegExp(r'INDICADOR|KPI|METRICA'), 'indicadores_relacionados');
    addIf(RegExp(r'RIESG|NO.*REGISTR'), 'riesgos_no_registrar');
    addIf(RegExp(r'PREGUNTA.*FRECUENT|FAQ'), 'preguntas_frecuentes');
    return keys;
  }

  String _renderValue(dynamic value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is Iterable) {
      final items = value.map((item) {
        if (item is Map) {
          final question = item['pregunta']?.toString().trim() ?? '';
          final answer = item['respuesta']?.toString().trim() ?? '';
          if (question.isNotEmpty && answer.isNotEmpty) {
            return '• $question $answer';
          }
        }
        final text = item.toString().trim();
        return text.isEmpty ? '' : '• $text';
      }).where((item) => item.isNotEmpty);
      return items.join('\n');
    }
    if (value is Map) {
      return value.entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join('\n');
    }
    return value.toString();
  }
}

class KnowledgeText {
  static const Set<String> _stopWords = {
    'A',
    'AL',
    'COMO',
    'CON',
    'CUAL',
    'CUALES',
    'DE',
    'DEL',
    'EL',
    'EN',
    'ES',
    'ESTAN',
    'ESTA',
    'FORMATO',
    'FORMATOS',
    'LA',
    'LAS',
    'LO',
    'LOS',
    'ME',
    'PARA',
    'POR',
    'QUE',
    'REGISTRO',
    'REGISTROS',
    'SE',
    'SU',
    'SUS',
    'UN',
    'UNA',
    'Y',
  };

  static String normalize(String value) {
    var result = value.trim().toUpperCase();
    const replacements = {
      'Á': 'A',
      'É': 'E',
      'Í': 'I',
      'Ó': 'O',
      'Ú': 'U',
      'Ü': 'U',
      'Ñ': 'N',
    };
    replacements.forEach((key, replacement) {
      result = result.replaceAll(key, replacement);
    });
    return result
        .replaceAll(RegExp(r'[^A-Z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static List<String> tokens(String value) {
    return normalize(value)
        .split(' ')
        .where((token) =>
            token.length >= 2 &&
            !_stopWords.contains(token) &&
            !RegExp(r'^\d+$').hasMatch(token))
        .toSet()
        .toList(growable: false);
  }

  static double similarity(String left, String right) {
    if (left == right) return 1;
    if (left.isEmpty || right.isEmpty) return 0;
    final distance = _levenshtein(left, right);
    return (1 - distance / math.max(left.length, right.length)).clamp(0, 1);
  }

  static int _levenshtein(String left, String right) {
    var previous = List<int>.generate(right.length + 1, (index) => index);
    for (var i = 0; i < left.length; i++) {
      final current = List<int>.filled(right.length + 1, 0);
      current[0] = i + 1;
      for (var j = 0; j < right.length; j++) {
        final insertion = current[j] + 1;
        final deletion = previous[j + 1] + 1;
        final substitution = previous[j] + (left[i] == right[j] ? 0 : 1);
        current[j + 1] = math.min(insertion, math.min(deletion, substitution));
      }
      previous = current;
    }
    return previous.last;
  }
}
