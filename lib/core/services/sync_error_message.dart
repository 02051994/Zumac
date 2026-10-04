String friendlySyncError(Object error) {
  final raw = error.toString();
  final msg = raw.toLowerCase();

  if (msg.contains('no hay sesión online activa') ||
      msg.contains('no hay sesion online activa') ||
      msg.contains('sin credenciales') ||
      msg.contains('sesión online venció') ||
      msg.contains('sesion online vencio') ||
      msg.contains('auth session missing') ||
      msg.contains('refresh token')) {
    return 'La sesión en línea venció. Vuelve a ingresar para actualizar los datos.';
  }
  if (msg.contains('sin conexión') ||
      msg.contains('sin conexion') ||
      msg.contains('socketexception') ||
      msg.contains('failed host') ||
      msg.contains('connection refused') ||
      msg.contains('network') ||
      msg.contains('network is unreachable') ||
      msg.contains('timeout')) {
    return 'No hay conexión a internet. El registro quedó pendiente; vuelve a sincronizar cuando tengas señal.';
  }
  if (msg.contains('invalid login') ||
      msg.contains('invalid credentials') ||
      msg.contains('invalid password') ||
      msg.contains('wrong password')) {
    return 'Usuario o contraseña incorrectos.';
  }
  if (msg.contains('jwt') ||
      msg.contains('not authorized') ||
      msg.contains('unauthorized') ||
      msg.contains('permission denied') ||
      msg.contains('row-level security') ||
      msg.contains('rls')) {
    return 'No autorizado. La sesión online venció o el usuario no tiene permiso para enviar este registro.';
  }
  if (msg.contains('administrator permission required') ||
      msg.contains('code: 42501')) {
    return 'Esta acción requiere una cuenta administradora de la empresa activa.';
  }
  if (msg.contains('authentication required') ||
      msg.contains('active company') ||
      msg.contains('empresa actual')) {
    return 'El usuario no tiene una empresa activa asociada. Un administrador debe completar su membresía.';
  }
  if (msg.contains('could not find the') && msg.contains('column') ||
      msg.contains('pgrst204') ||
      msg.contains('schema cache')) {
    final match = RegExp(
      r'''could not find the ['"]([^'"]+)['"] column''',
      caseSensitive: false,
    ).firstMatch(raw);
    final field = match?.group(1)?.trim();
    return field == null || field.isEmpty
        ? 'La configuración del formulario no coincide con las columnas de la tabla. Actualice o publique nuevamente la configuración.'
        : 'La tabla no tiene el campo «$field» que el formulario intenta guardar. Actualice o publique nuevamente la configuración.';
  }
  if (msg.contains('storage') ||
      msg.contains('bucket') ||
      msg.contains('upload')) {
    return 'No se pudo subir la foto o firma. Revisa internet y permisos del almacenamiento.';
  }
  if (msg.contains('duplicate key') || msg.contains('unique constraint')) {
    return 'El registro ya existe en la base de datos. Revisa si fue sincronizado antes.';
  }
  if (msg.contains('violates not-null') || msg.contains('null value')) {
    return 'Falta completar un campo obligatorio para poder enviar el registro.';
  }
  if (msg.contains('invalid input syntax') ||
      msg.contains('data type') ||
      msg.contains('cannot cast') ||
      msg.contains('cast error')) {
    return 'Un campo tiene un tipo de dato incorrecto. Revisa números, fechas y textos antes de sincronizar.';
  }
  return raw.replaceFirst('Exception: ', '').trim().isEmpty
      ? 'Ocurrió un problema al procesar la operación.'
      : raw.replaceFirst('Exception: ', '').trim();
}
