import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool get isDesktopRuntime {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

bool isWideDesktopLayout(BuildContext context) {
  return isDesktopRuntime && MediaQuery.sizeOf(context).width >= 900;
}
