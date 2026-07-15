class ConfigurationQuestion {
  final String id;
  final String label;
  final bool required;
  final String reason;

  const ConfigurationQuestion({
    required this.id,
    required this.label,
    required this.required,
    required this.reason,
  });
}

class ConfigurationEntitySpec {
  final String type;
  final String singularName;
  final List<ConfigurationQuestion> questions;

  const ConfigurationEntitySpec({
    required this.type,
    required this.singularName,
    required this.questions,
  });

  static const rubro = ConfigurationEntitySpec(
    type: 'RUBRO',
    singularName: 'rubro',
    questions: [
      ConfigurationQuestion(
        id: 'plantilla',
        label: '¿Desea partir de una plantilla?',
        required: false,
        reason:
            'Permite reutilizar una organización ya probada sin modificarla.',
      ),
      ConfigurationQuestion(
        id: 'nombre',
        label: '¿Qué nombre verá el usuario?',
        required: true,
        reason: 'Identifica la línea de negocio o ámbito principal.',
      ),
      ConfigurationQuestion(
        id: 'codigo',
        label: '¿Cuál será su código técnico único?',
        required: true,
        reason:
            'Relaciona toda la jerarquía y no cambia con el nombre visible.',
      ),
      ConfigurationQuestion(
        id: 'descripcion',
        label: '¿Qué procesos comprende este rubro?',
        required: false,
        reason: 'Documenta su alcance para los administradores.',
      ),
      ConfigurationQuestion(
        id: 'icono',
        label: '¿Qué icono lo representa?',
        required: true,
        reason: 'Ayuda a distinguirlo en la navegación.',
      ),
      ConfigurationQuestion(
        id: 'orden',
        label: '¿En qué orden debe aparecer?',
        required: true,
        reason: 'Controla su posición frente a otros rubros.',
      ),
      ConfigurationQuestion(
        id: 'activo',
        label: '¿Quedará visible al publicarse?',
        required: true,
        reason: 'Permite preparar el rubro antes de habilitarlo.',
      ),
    ],
  );

  static const section = ConfigurationEntitySpec(
    type: 'SECCION',
    singularName: 'sección',
    questions: [
      ConfigurationQuestion(
        id: 'plantilla',
        label: '¿Desea partir de una plantilla?',
        required: false,
        reason: 'Permite reutilizar una estructura sin modificar la original.',
      ),
      ConfigurationQuestion(
        id: 'nombre',
        label: '¿Qué nombre verá el usuario?',
        required: true,
        reason: 'Identifica la sección en la navegación.',
      ),
      ConfigurationQuestion(
        id: 'codigo',
        label: '¿Cuál será su código técnico único?',
        required: true,
        reason: 'Relaciona módulos, permisos y sincronización.',
      ),
      ConfigurationQuestion(
        id: 'descripcion',
        label: '¿Cuál es el propósito de la sección?',
        required: false,
        reason: 'Documenta el alcance para otros administradores.',
      ),
      ConfigurationQuestion(
        id: 'rubro_id',
        label: '¿A qué rubro pertenece?',
        required: true,
        reason: 'Ubica la sección dentro de la jerarquía empresarial.',
      ),
      ConfigurationQuestion(
        id: 'icono',
        label: '¿Qué icono la representa?',
        required: true,
        reason: 'Facilita reconocerla en móvil y escritorio.',
      ),
      ConfigurationQuestion(
        id: 'orden',
        label: '¿En qué orden debe aparecer?',
        required: true,
        reason: 'Controla su posición en la navegación.',
      ),
      ConfigurationQuestion(
        id: 'tipo_contenido',
        label: '¿Qué contenido mostrará?',
        required: true,
        reason: 'Determina qué vista dinámica abrirá Flutter.',
      ),
      ConfigurationQuestion(
        id: 'activo',
        label: '¿Quedará visible al publicarse?',
        required: true,
        reason: 'Permite publicar sin exponer contenido incompleto.',
      ),
    ],
  );

  static const module = ConfigurationEntitySpec(
    type: 'MODULO',
    singularName: 'módulo',
    questions: [
      ConfigurationQuestion(
        id: 'plantilla',
        label: '¿Desea partir de una plantilla?',
        required: false,
        reason: 'Reutiliza una configuración publicada como punto de partida.',
      ),
      ConfigurationQuestion(
        id: 'nombre',
        label: '¿Qué nombre verá el usuario?',
        required: true,
        reason: 'Identifica el módulo dentro de su sección.',
      ),
      ConfigurationQuestion(
        id: 'codigo',
        label: '¿Cuál será su código técnico único?',
        required: true,
        reason:
            'Relaciona formatos y permisos sin depender del nombre visible.',
      ),
      ConfigurationQuestion(
        id: 'descripcion',
        label: '¿Cuál es el propósito del módulo?',
        required: false,
        reason: 'Documenta qué procesos agrupa.',
      ),
      ConfigurationQuestion(
        id: 'seccion_id',
        label: '¿En qué sección se mostrará?',
        required: true,
        reason: 'Define su padre en la navegación.',
      ),
      ConfigurationQuestion(
        id: 'icono',
        label: '¿Qué icono lo representa?',
        required: false,
        reason: 'Queda disponible para vistas que muestren iconos de módulo.',
      ),
      ConfigurationQuestion(
        id: 'orden',
        label: '¿En qué orden debe aparecer?',
        required: true,
        reason: 'Controla su posición dentro de la sección.',
      ),
      ConfigurationQuestion(
        id: 'activo',
        label: '¿Quedará visible al publicarse?',
        required: true,
        reason: 'Permite mantener oculto un módulo todavía incompleto.',
      ),
    ],
  );

  static ConfigurationEntitySpec forType(String type) {
    switch (type.trim().toUpperCase()) {
      case 'RUBRO':
        return rubro;
      case 'SECCION':
        return section;
      case 'MODULO':
        return module;
      default:
        throw ArgumentError.value(
            type, 'type', 'Tipo de asistente no soportado');
    }
  }
}

List<String> validateSectionOrModulePayload(
  String type,
  Map<String, dynamic> payload,
) {
  final spec = ConfigurationEntitySpec.forType(type);
  final errors = <String>[];
  String text(String key) => payload[key]?.toString().trim() ?? '';

  for (final question
      in spec.questions.where((question) => question.required)) {
    if (question.id == 'activo' || question.id == 'plantilla') continue;
    if (text(question.id).isEmpty) {
      errors.add('${question.label} es obligatorio.');
    }
  }

  final code = text('codigo');
  if (code.isNotEmpty &&
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{1,62}$').hasMatch(code)) {
    errors.add(
        'El código debe tener 2 a 63 letras, números, guiones o guiones bajos.');
  }
  final order = text('orden');
  if (order.isNotEmpty && int.tryParse(order) == null) {
    errors.add('El orden debe ser un número entero.');
  }

  return errors;
}

String normalizeConfigurationCode(String value) {
  var normalized = value.trim().toUpperCase();
  normalized = normalized.replaceAll(RegExp(r'[^A-Z0-9_-]+'), '_');
  normalized = normalized.replaceAll(RegExp(r'_+'), '_');
  return normalized.replaceAll(RegExp(r'^_+|_+$'), '');
}
