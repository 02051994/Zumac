import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool get isDesktopRuntime {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

bool isWideDesktopLayout(BuildContext context) {
  // Web y escritorio comparten la misma experiencia cuando hay espacio.
  // En pantallas angostas se conserva la navegación táctil/responsive.
  return (isDesktopRuntime || kIsWeb) &&
      MediaQuery.sizeOf(context).width >= 900;
}
