String friendlyLoginError(Object error) {
  final raw = error.toString();
  final msg = raw.toLowerCase();
  if (msg.contains('invalid login') ||
      msg.contains('invalid credentials') ||
      msg.contains('password')) {
    return 'Usuario o contraseña incorrectos.';
  }
  if (msg.contains('over_email_send_rate_limit') ||
      msg.contains('email rate limit') ||
      msg.contains('429')) {
    return 'El servicio bloqueó temporalmente el envío de correos por muchos intentos. Espera unos minutos y vuelve a probar.';
  }
  if (msg.contains('socketexception') ||
      msg.contains('failed host lookup') ||
      msg.contains('clientexception') ||
      msg.contains('connection refused') ||
      msg.contains('network is unreachable') ||
      msg.contains('timeout')) {
    final detail = raw.replaceFirst('Exception: ', '').trim();
    return 'El teléfono tiene red, pero no pudo contactar al servicio en línea. Detalle: $detail';
  }
  if (msg.contains('no existe un usuario activo')) {
    return raw.replaceFirst('Exception: ', '');
  }
  if (msg.contains('not authorized') ||
      msg.contains('unauthorized') ||
      msg.contains('permission denied') ||
      msg.contains('jwt')) {
    return 'No autorizado. Revisa que el usuario esté activo y tenga permisos asignados.';
  }
  return raw.replaceFirst('Exception: ', '').trim().isEmpty
      ? 'No se pudo completar la operación.'
      : raw.replaceFirst('Exception: ', '').trim();
}
