import 'package:flutter/material.dart';

import 'zumac_animated_loader.dart';

class BrandedLoading extends StatelessWidget {
  final double progress;
  final String message;
  final double size;

  const BrandedLoading({
    super.key,
    required this.progress,
    this.message = '',
    this.size = 112,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedProgress = progress.clamp(0.0, 1.0).toDouble();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ZumacShapeLoader(size: size.clamp(84.0, 132.0).toDouble()),
          const SizedBox(height: 18),
          SizedBox(
            width: 240,
            child: LinearProgressIndicator(
              value: normalizedProgress == 0 ? null : normalizedProgress,
              minHeight: 5,
              color: const Color(0xFF032A63),
              backgroundColor: const Color(0xFFD7E7EC),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          if (message.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              message.trim(),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF1D2B24),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
