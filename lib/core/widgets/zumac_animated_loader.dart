import 'dart:async';

import 'package:flutter/material.dart';

const _zumacNavy = Color(0xFF032A63);
const _surfaceColor = Color(0xFFF5FCFF);

/// Indicador de actividad ligero basado en la identidad oficial de Zumac.
///
/// La marca permanece estática; únicamente se anima el indicador nativo de
/// progreso, evitando repintar un lienzo completo durante sincronizaciones.
class ZumacShapeLoader extends StatelessWidget {
  const ZumacShapeLoader({super.key, this.size = 108});

  final double size;

  @override
  Widget build(BuildContext context) {
    final resolvedSize = size.clamp(72.0, 132.0).toDouble();
    return Semantics(
      label: 'Procesando',
      child: SizedBox.square(
        dimension: resolvedSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(resolvedSize * .18),
              child: Image.asset(
                'assets/images/logo_app.png',
                width: resolvedSize,
                height: resolvedSize,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              ),
            ),
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                width: 28,
                height: 28,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: _surfaceColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _zumacNavy, width: 1.5),
                ),
                child: const CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: _zumacNavy,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Splash de compatibilidad para rutas antiguas.
///
/// La aplicación principal ya no lo utiliza: el splash nativo muestra el logo
/// mientras Flutter inicia, sin agregar una espera artificial posterior.
class ZumacStartupSplash extends StatefulWidget {
  const ZumacStartupSplash({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<ZumacStartupSplash> createState() => _ZumacStartupSplashState();
}

class _ZumacStartupSplashState extends State<ZumacStartupSplash> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 250), widget.onFinished);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: _surfaceColor,
      body: Center(child: ZumacShapeLoader(size: 112)),
    );
  }
}
