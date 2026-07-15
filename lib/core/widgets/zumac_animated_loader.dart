import 'dart:math' as math;

import 'package:flutter/material.dart';

// Paleta visual de Zumac: azul petróleo, azul, celeste y plomo azulado.
const _zumacNavy = Color(0xFF0D3E5A);
const _zumacBlue = Color(0xFF0D5F78);
const _zumacSky = Color(0xFF35B7D3);
const _zumacIce = Color(0xFF9ED9E6);
const _zumacSlate = Color(0xFF738391);

class ZumacShapeLoader extends StatefulWidget {
  final double size;

  const ZumacShapeLoader({super.key, this.size = 108});

  @override
  State<ZumacShapeLoader> createState() => _ZumacShapeLoaderState();
}

class _ZumacShapeLoaderState extends State<ZumacShapeLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Un ciclo deliberadamente pausado: cada figura permanece legible y la
    // transición no se percibe como un parpadeo.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Procesando',
      child: RepaintBoundary(
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (_, __) => CustomPaint(
              isComplex: true,
              willChange: true,
              painter: _ShapeSequencePainter(_controller.value),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShapeSequencePainter extends CustomPainter {
  final double progress;

  _ShapeSequencePainter(this.progress);

  static const _count = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final cycle = (progress % 1.0) * _count;
    final index = cycle.floor().clamp(0, _count - 1);
    final rawLocal = cycle - cycle.floor();

    // Entrada y salida suaves, con una meseta central. De esta forma cada
    // figura se observa con claridad y nunca parece detenerse bruscamente.
    final enter = Curves.easeOutCubic.transform((rawLocal / 0.28).clamp(0.0, 1.0));
    final exit = Curves.easeInCubic.transform(((1.0 - rawLocal) / 0.28).clamp(0.0, 1.0));
    final visibility = math.min(enter, exit).clamp(0.0, 1.0).toDouble();
    final breathe = 0.96 + 0.045 * math.sin(rawLocal * math.pi);
    final scale = (0.76 + 0.24 * visibility) * breathe;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate((rawLocal - 0.5) * 0.22 + index * 0.035);
    canvas.scale(scale);

    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: size.width * 0.56,
      height: size.height * 0.56,
    );
    final shaderRect = rect.inflate(size.width * 0.12);
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_zumacNavy, _zumacBlue, _zumacSky, _zumacIce, _zumacSlate],
        stops: [0.0, 0.25, 0.52, 0.76, 1.0],
      ).createShader(shaderRect)
      ..color = Colors.white.withOpacity(visibility)
      ..filterQuality = FilterQuality.high;

    final path = _shapePath(index, rect);
    canvas.drawShadow(path, _zumacNavy.withOpacity(0.24 * visibility), 16, true);
    canvas.drawPath(path, paint);

    // Brillo interno sutil, dentro de la misma paleta corporativa.
    final highlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, size.width * 0.012)
      ..color = _zumacIce.withOpacity(0.34 * visibility);
    canvas.drawPath(path, highlight);
    canvas.restore();
  }

  Path _shapePath(int index, Rect rect) {
    switch (index) {
      case 0:
        return Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(18)));
      case 1:
        final diamond = Path()
          ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(18)));
        return diamond.transform(Matrix4.rotationZ(math.pi / 4).storage);
      case 2:
        return Path()..addOval(rect);
      case 3:
        return _regularPolygon(rect, 3, -math.pi / 2, cornerRadius: 12);
      default:
        return _regularPolygon(rect, 8, -math.pi / 8, cornerRadius: 8);
    }
  }

  Path _regularPolygon(Rect rect, int sides, double rotation,
      {double cornerRadius = 0}) {
    final center = rect.center;
    final radius = math.min(rect.width, rect.height) / 2;
    final points = List<Offset>.generate(sides, (i) {
      final angle = rotation + (math.pi * 2 * i / sides);
      return center + Offset(math.cos(angle), math.sin(angle)) * radius;
    });

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final prev = points[(i - 1 + points.length) % points.length];
      final current = points[i];
      final next = points[(i + 1) % points.length];
      final amount = (cornerRadius / radius).clamp(0.0, 0.35);
      final a = Offset.lerp(current, prev, amount)!;
      final b = Offset.lerp(current, next, amount)!;
      if (i == 0) {
        path.moveTo(a.dx, a.dy);
      } else {
        path.lineTo(a.dx, a.dy);
      }
      path.quadraticBezierTo(current.dx, current.dy, b.dx, b.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant _ShapeSequencePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class ZumacStartupSplash extends StatefulWidget {
  final VoidCallback onFinished;

  const ZumacStartupSplash({super.key, required this.onFinished});

  @override
  State<ZumacStartupSplash> createState() => _ZumacStartupSplashState();
}

class _ZumacStartupSplashState extends State<ZumacStartupSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 7800),
    )
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onFinished();
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _interval(double start, double end, {Curve curve = Curves.easeInOutCubic}) =>
      CurvedAnimation(parent: _controller, curve: Interval(start, end, curve: curve)).value;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FA),
      body: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, __) {
            // 61% del tiempo para las cinco figuras: aprox. 950 ms por figura.
            final shapePhase = _interval(0.00, 0.61, curve: Curves.linear);
            final namePhase = _interval(0.57, 0.74);
            final sweepPhase = _interval(0.70, 1.00, curve: Curves.easeInOutCubic);
            final shapeOpacity = (1.0 - _interval(0.56, 0.65)).clamp(0.0, 1.0).toDouble();

            return Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  isComplex: true,
                  willChange: true,
                  painter: _StartupBackgroundPainter(sweepPhase),
                ),
                Center(
                  child: Opacity(
                    opacity: shapeOpacity,
                    child: SizedBox(
                      width: 124,
                      height: 124,
                      child: CustomPaint(
                        isComplex: true,
                        willChange: true,
                        painter: _ShapeSequencePainter(shapePhase),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Opacity(
                    opacity: namePhase,
                    child: Transform.scale(
                      scale: 0.91 + (0.09 * namePhase),
                      child: const Text(
                        'Zumac',
                        style: TextStyle(
                          color: _zumacNavy,
                          fontSize: 38,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.15,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StartupBackgroundPainter extends CustomPainter {
  final double progress;

  _StartupBackgroundPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_zumacNavy, _zumacBlue, _zumacSky, _zumacIce, _zumacSlate],
        stops: [0.0, 0.24, 0.50, 0.76, 1.0],
      ).createShader(Offset.zero & size)
      ..filterQuality = FilterQuality.high;

    final travel = size.height * 1.62;
    final y = -size.height * 0.82 + travel * progress;
    final path = Path()
      ..moveTo(-size.width * 0.30, y)
      ..lineTo(size.width * 1.24, y - size.height * 0.27)
      ..lineTo(size.width * 1.10, y + size.height * 0.53)
      ..lineTo(-size.width * 0.22, y + size.height * 0.76)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _StartupBackgroundPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
