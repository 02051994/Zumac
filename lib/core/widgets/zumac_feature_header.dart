import 'package:flutter/material.dart';

/// Encabezado común para las herramientas premium de Zumac.
///
/// Mantiene el mismo lenguaje visual en Consultor, Creator, Metrics,
/// Alerts y Actions sin obligar a cada pantalla a repetir estilos.
class ZumacFeatureHeader extends StatelessWidget {
  const ZumacFeatureHeader({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    this.compact = false,
  });

  final String title;
  final IconData icon;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 12,
        vertical: compact ? 5 : 7,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color.lerp(color, Colors.white, .84)!,
            Color.lerp(color, const Color(0xFFF7F4FC), .91)!,
          ],
        ),
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
        border: Border.all(color: color.withValues(alpha: .20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 28 : 32,
            height: compact ? 28 : 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: compact ? 17 : 19),
          ),
          SizedBox(width: compact ? 7 : 9),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFF17324D),
                fontSize: compact ? 16 : 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
