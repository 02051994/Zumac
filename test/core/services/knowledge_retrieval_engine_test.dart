import 'package:flutter_test/flutter_test.dart';

import 'package:appgt_offline_subtables/core/services/knowledge_retrieval_engine.dart';

void main() {
  const primary = KnowledgeSource(
    id: 'source-formats',
    code: 'MATRIZ_FORMATOS_APPGT',
    name: 'Matriz de formatos Zumac',
    priority: 10,
    sufficiencyThreshold: 0.40,
  );
  const documents = KnowledgeSource(
    id: 'source-documents',
    code: 'DOCUMENTOS_EMPRESA',
    name: 'Procedimientos internos',
    priority: 100,
    sufficiencyThreshold: 0.40,
  );

  KnowledgeDocument drainage({
    String sourceCode = 'MATRIZ_FORMATOS_APPGT',
    String sourceName = 'Matriz de formatos Zumac',
    int priority = 10,
  }) {
    return KnowledgeDocument(
      id: 'drainage-$sourceCode',
      sourceCode: sourceCode,
      sourceName: sourceName,
      sourcePriority: priority,
      title: 'Registro Drenaje',
      entityType: 'FORMATO',
      status: 'GENERADA_IA',
      content: const {
        'descripcion_general':
            'Registro técnico del volumen drenado después de cada evento de riego.',
        'objetivo':
            'Controlar el balance hídrico y la acumulación de sales por sector.',
        'conceptos_relacionados': [
          'Registro pH',
          'Registro CE',
          'Programa de riego',
          'Fertirriego',
          'Variedades',
          'Sectores',
          'Macetas',
        ],
        'riesgos_no_registrar': [
          'Salinidad no detectada',
          'Asfixia radicular',
        ],
      },
      relatedConcepts: const [
        'Registro pH',
        'Registro CE',
        'Programa de riego',
        'Fertirriego',
        'Variedades',
        'Sectores',
        'Macetas',
      ],
    );
  }

  test('respeta la prioridad y se detiene cuando la primera fuente basta',
      () async {
    final repository = InMemoryKnowledgeRepository(
      sources: const [documents, primary],
      documents: [
        drainage(),
        drainage(
          sourceCode: 'DOCUMENTOS_EMPRESA',
          sourceName: 'Procedimientos internos',
          priority: 100,
        ),
      ],
    );
    final engine = KnowledgeRetrievalEngine(repository: repository);

    final answer = await engine.ask(
      '¿Qué registros están relacionados con drenaje?',
      conversationId: 'priority',
    );

    expect(answer.sufficient, isTrue);
    expect(answer.citations, isNotEmpty);
    expect(answer.citations.first.sourceCode, 'MATRIZ_FORMATOS_APPGT');
    expect(
      answer.citations.every(
        (citation) => citation.sourceCode == 'MATRIZ_FORMATOS_APPGT',
      ),
      isTrue,
    );
    expect(answer.answer, contains('Registro pH'));
    expect(answer.inspectedSources, ['Matriz de formatos Zumac']);
  });

  test('continúa automáticamente con la siguiente fuente si es insuficiente',
      () async {
    final repository = InMemoryKnowledgeRepository(
      sources: const [primary, documents],
      documents: [
        KnowledgeDocument(
          id: 'procedure-harvest',
          sourceCode: 'DOCUMENTOS_EMPRESA',
          sourceName: 'Procedimientos internos',
          sourcePriority: 100,
          title: 'Procedimiento de cosecha',
          entityType: 'DOCUMENTO',
          status: 'APROBADA',
          content: const {
            'buenas_practicas': [
              'Mantener la identificación del lote durante la cosecha.',
            ],
          },
        ),
      ],
    );
    final engine = KnowledgeRetrievalEngine(repository: repository);

    final answer = await engine.ask('Buenas prácticas de cosecha');

    expect(answer.sufficient, isTrue);
    expect(answer.citations.single.sourceCode, 'DOCUMENTOS_EMPRESA');
    expect(
      answer.inspectedSources,
      ['Matriz de formatos Zumac', 'Procedimientos internos'],
    );
  });

  test('la búsqueda difusa corrige Vareidad a Variedad', () async {
    final repository = InMemoryKnowledgeRepository(
      sources: const [primary],
      documents: const [
        KnowledgeDocument(
          id: 'variety',
          sourceCode: 'MATRIZ_FORMATOS_APPGT',
          sourceName: 'Matriz de formatos Zumac',
          sourcePriority: 10,
          title: 'Registro Variedad',
          entityType: 'FORMATO',
          status: 'GENERADA_IA',
          content: {
            'descripcion_general':
                'Catálogo de variedades agrícolas utilizadas por la empresa.',
          },
        ),
      ],
    );
    final engine = KnowledgeRetrievalEngine(repository: repository);

    final answer = await engine.ask('¿Para qué sirve el registro Vareidad?');

    expect(answer.sufficient, isTrue);
    expect(answer.citations.single.matchModes, contains('difusa'));
    expect(answer.answer, contains('variedades agrícolas'));
  });

  test('mantiene el tema para una pregunta de seguimiento', () async {
    final repository = InMemoryKnowledgeRepository(
      sources: const [primary],
      documents: [drainage()],
    );
    final engine = KnowledgeRetrievalEngine(repository: repository);

    await engine.ask('¿Qué es el Registro Drenaje?', conversationId: 'memory');
    final followUp = await engine.ask(
      '¿Y cuáles son los riesgos?',
      conversationId: 'memory',
    );

    expect(followUp.sufficient, isTrue);
    expect(followUp.contextualQuestion, contains('Registro Drenaje'));
    expect(followUp.answer, contains('Salinidad no detectada'));
  });

  test('lee el contenido del documento conectado mediante su UUID', () async {
    final origin = KnowledgeDocument(
      id: 'drainage-linked',
      sourceCode: 'MATRIZ_FORMATOS_APPGT',
      sourceName: 'Matriz de formatos Zumac',
      sourcePriority: 10,
      title: 'Registro Drenaje',
      entityType: 'FORMATO',
      status: 'APROBADA',
      content: const {
        'descripcion_general': 'Control del drenaje del cultivo.',
        'conceptos_relacionados': ['CE'],
      },
      relations: const [
        KnowledgeRelation(
          destinationDocumentId: 'electrical-conductivity',
          destinationConcept: 'CE',
          type: 'SE_MIDE_CON',
          weight: 0.95,
        ),
      ],
      relatedConcepts: const ['CE'],
    );
    const destination = KnowledgeDocument(
      id: 'electrical-conductivity',
      sourceCode: 'DOCUMENTOS_EMPRESA',
      sourceName: 'Procedimientos internos',
      sourcePriority: 100,
      title: 'Registro CE',
      entityType: 'DOCUMENTO',
      status: 'APROBADA',
      content: {
        'descripcion_general':
            'La conductividad eléctrica permite evaluar sales en el drenaje.',
      },
    );
    final engine = KnowledgeRetrievalEngine(
      repository: InMemoryKnowledgeRepository(
        sources: const [primary, documents],
        documents: [origin, destination],
      ),
    );

    final answer = await engine.ask(
      '¿Cómo se relaciona CE con el drenaje?',
      conversationId: 'connected-document',
    );

    expect(answer.sufficient, isTrue);
    expect(answer.answer, contains('conductividad eléctrica'));
    expect(
      answer.citations.any(
        (citation) =>
            citation.documentId == 'electrical-conductivity' &&
            citation.matchModes.contains('relación:SE_MIDE_CON'),
      ),
      isTrue,
    );
  });

  test('solo responde no encontrado cuando ninguna fuente aporta evidencia',
      () async {
    final repository = InMemoryKnowledgeRepository(
      sources: const [primary, documents],
      documents: const [],
    );
    final engine = KnowledgeRetrievalEngine(repository: repository);

    final answer = await engine.ask('Protocolo inexistente');

    expect(answer.sufficient, isFalse);
    expect(answer.citations, isEmpty);
    expect(answer.answer, KnowledgeRetrievalEngine.notFoundAnswer);
  });

  test('combina búsqueda semántica cuando la fuente la habilita', () async {
    const semanticSource = KnowledgeSource(
      id: 'semantic',
      code: 'MANUALES',
      name: 'Manuales',
      priority: 20,
      semanticEnabled: true,
      sufficiencyThreshold: 0.60,
    );
    const document = KnowledgeDocument(
      id: 'water-stress',
      sourceCode: 'MANUALES',
      sourceName: 'Manuales',
      sourcePriority: 20,
      title: 'Balance de humedad',
      entityType: 'DOCUMENTO',
      status: 'APROBADA',
      content: {
        'descripcion_general':
            'Método interno para evaluar disponibilidad hídrica del cultivo.',
      },
    );
    final engine = KnowledgeRetrievalEngine(
      repository: InMemoryKnowledgeRepository(
        sources: const [semanticSource],
        documents: const [document],
      ),
      semanticSearch: (_, __) async => {'water-stress': 0.91},
    );

    final answer =
        await engine.ask('¿Cómo detectamos estrés por falta de agua?');

    expect(answer.sufficient, isTrue);
    expect(answer.citations.single.matchModes, contains('semántica'));
  });
}
