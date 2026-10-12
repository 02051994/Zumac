class ErpPurchaseTotals {
  final double importeBruto;
  final double descuento;
  final double subtotal;
  final double? impuesto;
  final double total;

  const ErpPurchaseTotals({
    required this.importeBruto,
    required this.descuento,
    required this.subtotal,
    required this.impuesto,
    required this.total,
  });

  factory ErpPurchaseTotals.calculate({
    required double itemAmount,
    required double discount,
    required bool includesIgv,
    double igvPercentage = 18,
  }) {
    final safeAmount = itemAmount.clamp(0, double.infinity).toDouble();
    final safeDiscount = discount.clamp(0, safeAmount).toDouble();
    final safeIgv = igvPercentage.clamp(0, 100).toDouble();
    final subtotal = safeAmount - safeDiscount;
    final tax = includesIgv ? null : subtotal * safeIgv / 100;
    return ErpPurchaseTotals(
      importeBruto: safeAmount,
      descuento: safeDiscount,
      subtotal: subtotal,
      impuesto: tax,
      total: subtotal + (tax ?? 0),
    );
  }
}
