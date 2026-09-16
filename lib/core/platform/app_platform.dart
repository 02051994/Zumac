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
  // En pantallas angostas se conserva la navegación táctil/responsive.
  // Solo la web usa guardado online-first; escritorio conserva su cola local.
  return (kIsWeb || isDesktopRuntime) &&
      MediaQuery.sizeOf(context).width >= 900;
}
