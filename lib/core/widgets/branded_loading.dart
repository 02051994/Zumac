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
    return ZumacShapeLoader(size: size.clamp(84.0, 132.0).toDouble());
  }
}
