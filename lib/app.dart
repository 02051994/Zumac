import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/auth/login_page.dart';
import 'features/auth/reset_password_page.dart';
import 'features/modules/modules_page.dart';

class AppGT extends StatefulWidget {
  const AppGT({super.key});

  @override
  State<AppGT> createState() => _AppGTState();
}

class _AppGTState extends State<AppGT> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        _navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const ResetPasswordPage()),
        );
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Zumac',
      builder: (context, child) {
        final width = MediaQuery.sizeOf(context).width;
        final scale = (width / 1440).clamp(1.0, 1.12).toDouble();
        final controlHeight = (44 * scale).clamp(44.0, 50.0).toDouble();
        final base = Theme.of(context);
        final radius = RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        );
        return Theme(
          data: base.copyWith(
            textTheme: base.textTheme.apply(fontSizeFactor: scale),
            inputDecorationTheme: base.inputDecorationTheme.copyWith(
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12 * scale,
                vertical: 11 * scale,
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0D5F78),
                foregroundColor: Colors.white,
                minimumSize: Size(0, controlHeight),
                shape: radius,
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                minimumSize: Size(0, controlHeight),
                shape: radius,
              ),
            ),
            iconButtonTheme: IconButtonThemeData(
              style: IconButton.styleFrom(
                minimumSize: Size.square(width < 600 ? 44 : 46),
              ),
            ),
          ),
          child: _AppInteractionScope(
            child: SelectionArea(
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0D5F78),
        scaffoldBackgroundColor: const Color(0xFFF4F8F7),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF4F8F7),
          foregroundColor: Color(0xFF1D2B24),
          elevation: 0,
          centerTitle: false,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF0D5F78),
          foregroundColor: Colors.white,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0D5F78),
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          isDense: true,
          filled: true,
          fillColor: const Color(0xFFFCFEFE),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF6FA6B4), width: 1.2),
          ),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF0D5F78), width: 2)),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFC9D9DE)),
          ),
          labelStyle: const TextStyle(color: Color(0xFF496977)),
          floatingLabelStyle: const TextStyle(
            color: Color(0xFF0D5F78),
            fontWeight: FontWeight.w700,
          ),
          prefixIconColor: const Color(0xFF176B87),
          suffixIconColor: const Color(0xFF176B87),
        ),
      ),
      home: session == null
          ? const LoginPage()
          : const ModulesPage(refreshOnEntry: false),
    );
  }
}

/// Interacciones globales comunes a web, Windows, macOS y Linux.
///
/// Ctrl + rueda modifica el lienzo completo (no solo el texto o el control bajo
/// el puntero). El mismo tope se aplica a Ctrl +/- para que el comportamiento
/// sea predecible cuando no hay rueda disponible.
class _AppInteractionScope extends StatefulWidget {
  const _AppInteractionScope({required this.child});

  final Widget child;

  @override
  State<_AppInteractionScope> createState() => _AppInteractionScopeState();
}

class _AppInteractionScopeState extends State<_AppInteractionScope> {
  static const double _minimumZoom = .80;
  static const double _maximumZoom = 1.40;
  static const double _zoomStep = .10;

  double _zoom = 1;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    // La ruta global recibe la rueda antes que los Scrollable internos. Asi
    // Ctrl/Cmd + rueda funciona incluso sobre tablas, graficos y paneles.
    GestureBinding.instance.pointerRouter.addGlobalRoute(_handlePointerEvent);
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter
        .removeGlobalRoute(_handlePointerEvent);
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool get _modifierPressed =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  void _changeZoom(double delta) {
    final next = (_zoom + delta).clamp(_minimumZoom, _maximumZoom).toDouble();
    if ((next - _zoom).abs() < .001 || !mounted) return;
    setState(() => _zoom = next);
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent || !_modifierPressed) return false;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      _changeZoom(_zoomStep);
      return true;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      _changeZoom(-_zoomStep);
      return true;
    }
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      if ((_zoom - 1).abs() >= .001 && mounted) {
        setState(() => _zoom = 1);
      }
      return true;
    }
    return false;
  }

  void _handlePointerEvent(PointerEvent event) {
    if (event is! PointerScrollEvent || !_modifierPressed) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (signal) {
      final scroll = signal as PointerScrollEvent;
      _changeZoom(scroll.scrollDelta.dy < 0 ? _zoomStep : -_zoomStep);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          return widget.child;
        }
        final logicalSize = Size(
          constraints.maxWidth / _zoom,
          constraints.maxHeight / _zoom,
        );
        return ClipRect(
          child: Transform.scale(
            scale: _zoom,
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(
              size: logicalSize,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(size: logicalSize),
                child: widget.child,
              ),
            ),
          ),
        );
      },
    );
  }
}
