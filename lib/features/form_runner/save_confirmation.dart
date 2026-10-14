import 'package:flutter/material.dart';

/// Shared confirmation used by the generic form runner and every specialized
/// ERP editor before any write is sent to local storage or Supabase.
Future<bool> confirmRecordSave(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      shape: const RoundedRectangleBorder(),
      title: const Text('Confirmar guardado'),
      content: const Text('¿Seguro de guardar?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
  return confirmed == true;
}
