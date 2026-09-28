import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool get isDesktopRuntime {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

/// La web guarda directamente en Supabase. Escritorio y móvil mantienen su
/// cola local para poder seguir trabajando ante cortes de red.
bool get isOnlineFirstRuntime => kIsWeb;

bool get isMobileCaptureRuntime {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

bool isWideDesktopLayout(BuildContext context) {
  // La versión web conserva siempre la navegación y las tablas de escritorio,
  // incluso si el navegador reduce su ancho. El contenido tabular se desplaza
  // horizontalmente en lugar de convertirse en formularios/listas móviles.
  if (kIsWeb) return true;

  // Las aplicaciones de escritorio sí pueden adoptar el diseño compacto en
  // ventanas muy angostas. Android/iOS mantienen su experiencia táctil.
  return isDesktopRuntime && MediaQuery.sizeOf(context).width >= 900;
}
