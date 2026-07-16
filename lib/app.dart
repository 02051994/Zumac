import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/auth/login_page.dart';
import 'features/auth/reset_password_page.dart';
import 'features/modules/modules_page.dart';
import 'core/widgets/zumac_animated_loader.dart';

class AppGT extends StatefulWidget {
  const AppGT({super.key});

  @override
  State<AppGT> createState() => _AppGTState();
}

class _AppGTState extends State<AppGT> {
  bool _showStartupSplash = true;
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
      home: _showStartupSplash
          ? ZumacStartupSplash(
              onFinished: () {
                if (mounted) setState(() => _showStartupSplash = false);
              },
            )
          : session == null
              ? const LoginPage()
              : const ModulesPage(),
    );
  }
}
