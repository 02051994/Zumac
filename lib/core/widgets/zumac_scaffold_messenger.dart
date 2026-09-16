import 'dart:async';

import 'package:flutter/material.dart' as material;

/// Compatibilidad central para los mensajes existentes del sistema.
///
/// Conserva la llamada `ScaffoldMessenger.of(...).showSnackBar(...)`, pero
/// presenta un dialogo accesible y obligatorio en lugar de una franja fugaz.
class ScaffoldMessenger {
  static final _ZumacMessageQueue _queue = _ZumacMessageQueue();

  static ZumacMessageDispatcher of(material.BuildContext context) {
    return ZumacMessageDispatcher._(context, _queue);
  }
}

class ZumacMessageDispatcher {
  final material.BuildContext context;
  final _ZumacMessageQueue queue;

  const ZumacMessageDispatcher._(this.context, this.queue);

  Future<void> showSnackBar(material.SnackBar snackBar) {
    final raw = _extractText(snackBar.content);
    return queue.show(context, naturalizeZumacMessage(raw));
  }
}

class _ZumacMessageQueue {
  Future<void> _pending = Future<void>.value();

  Future<void> show(material.BuildContext context, String message) {
    _pending = _pending.then((_) async {
      if (!context.mounted) return;
      await material.showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => _ZumacMessageDialog(message: message),
      );
    });
    return _pending;
  }
}

class _ZumacMessageDialog extends material.StatelessWidget {
  final String message;

  const _ZumacMessageDialog({required this.message});

  @override
  material.Widget build(material.BuildContext context) {
    final colors = material.Theme.of(context).colorScheme;
    final lower = message.toLowerCase();
    final isError = lower.contains('no se pudo') ||
        lower.contains('error') ||
        lower.contains('vencid') ||
        lower.contains('debe ');
    final accent = isError ? colors.error : const material.Color(0xFF087F8C);
    final icon = isError
        ? material.Icons.error_outline_rounded
        : material.Icons.info_outline_rounded;

    return material.Dialog(
      insetPadding: const material.EdgeInsets.symmetric(horizontal: 24),
      shape: material.RoundedRectangleBorder(
        borderRadius: material.BorderRadius.circular(22),
      ),
      child: material.ConstrainedBox(
        constraints: const material.BoxConstraints(maxWidth: 440),
        child: material.Padding(
          padding: const material.EdgeInsets.fromLTRB(28, 26, 28, 22),
          child: material.Column(
            mainAxisSize: material.MainAxisSize.min,
            children: [
              material.Container(
                width: 58,
                height: 58,
                decoration: material.BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: material.BoxShape.circle,
                ),
                child: material.Icon(icon, color: accent, size: 32),
              ),
              const material.SizedBox(height: 18),
              material.Text(
                isError ? 'No pudimos completar la accion' : 'Mensaje',
                textAlign: material.TextAlign.center,
                style: material.Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: material.FontWeight.w700),
              ),
              const material.SizedBox(height: 10),
              material.Text(
                message,
                textAlign: material.TextAlign.center,
                style: material.Theme.of(context).textTheme.bodyLarge?.copyWith(
                      height: 1.4,
                      color: colors.onSurfaceVariant,
                    ),
              ),
              const material.SizedBox(height: 24),
              material.SizedBox(
                width: double.infinity,
                child: material.FilledButton(
                  onPressed: () => material.Navigator.of(context).pop(),
                  style: material.FilledButton.styleFrom(
                    backgroundColor: accent,
                    padding: const material.EdgeInsets.symmetric(vertical: 14),
                    shape: material.RoundedRectangleBorder(
                      borderRadius: material.BorderRadius.circular(12),
                    ),
                  ),
                  child: const material.Text('Aceptar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _extractText(material.Widget widget) {
  if (widget is material.Text) {
    return widget.data ?? widget.textSpan?.toPlainText() ?? '';
  }
  return '';
}

String naturalizeZumacMessage(String raw) {
  var message = raw.trim();
  if (message.isEmpty) return 'La operacion no pudo completarse.';
  final postgrestMessage = RegExp(
    r'message:\s*(.*?)(?:,\s*(?:code|details|hint):|\)$)',
    caseSensitive: false,
  ).firstMatch(message)?.group(1)?.trim();
  if (postgrestMessage != null && postgrestMessage.isNotEmpty) {
    message = postgrestMessage;
  }
  final lower = message.toLowerCase();

  if (lower.contains('platform._version') ||
      lower.contains('unsupported operation')) {
    return 'No se pudo preparar el archivo en este navegador. '
        'Actualice la pagina e intentelo nuevamente.';
  }
  if (lower.contains('failed host lookup') ||
      lower.contains('socketexception') ||
      lower.contains('network') ||
      lower.contains('clientexception')) {
    return 'No se pudo conectar con el servidor. Revise su conexion a internet '
        'e intentelo nuevamente.';
  }
  if (lower.contains('jwt') || lower.contains('token has expired')) {
    return 'Su sesion ha vencido. Ingrese nuevamente para continuar.';
  }
  if (lower.contains('administrator permission required') ||
      lower.contains('code: 42501')) {
    return 'Esta accion requiere una cuenta administradora de la empresa activa.';
  }
  if (lower.contains('authentication required') ||
      lower.contains('active company')) {
    return 'El usuario no tiene una empresa activa asociada. Un administrador '
        'debe completar su membresia.';
  }
  if ((lower.contains('could not find the') && lower.contains('column')) ||
      lower.contains('pgrst204') ||
      lower.contains('schema cache')) {
    final match = RegExp(
      r'''could not find the ['"]([^'"]+)['"] column''',
      caseSensitive: false,
    ).firstMatch(message);
    final field = match?.group(1)?.trim();
    return field == null || field.isEmpty
        ? 'La configuracion del formulario no coincide con las columnas de la tabla.'
        : 'La tabla no tiene el campo «$field» que el formulario intenta guardar.';
  }
  if (lower.contains('row-level security') ||
      lower.contains('permission denied') ||
      lower.contains('not authorized')) {
    return 'No tiene permisos para realizar esta operacion.';
  }
  if (lower.contains('duplicate key') || lower.contains('23505')) {
    return 'Ya existe un registro con esos datos. Revise la informacion e '
        'intentelo nuevamente.';
  }
  if (lower.contains('postgrestexception') ||
      lower.contains('storageexception') ||
      lower.contains('sqlstate') ||
      lower.contains('stack trace') ||
      lower.contains('code:')) {
    return 'La operacion no pudo completarse. Revise los datos ingresados e '
        'intentelo nuevamente.';
  }

  message = message
      .replaceFirst(RegExp(r'^exception:\s*', caseSensitive: false), '')
      .replaceFirst(
          RegExp(r'^postgrestexception\([^:]*:?\s*', caseSensitive: false), '')
      .replaceFirst(
          RegExp(r'^storageexception\([^:]*:?\s*', caseSensitive: false), '')
      .trim();
  if (message.length > 360) {
    return 'La operacion no pudo completarse. Revise los datos ingresados e '
        'intentelo nuevamente.';
  }
  return message;
}
