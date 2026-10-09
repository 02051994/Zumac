class ErpPurchaseTotals {
  final double importeBruto;
  final double descuento;
  final double subtotal;
  final double impuesto;
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
  }) {
    final safeAmount = itemAmount.clamp(0, double.infinity).toDouble();
    final safeDiscount = discount.clamp(0, safeAmount).toDouble();
    if (includesIgv) {
      final total = safeAmount - safeDiscount;
      final subtotal = total == 0 ? 0.0 : total / 1.18;
      final tax = total - subtotal;
      return ErpPurchaseTotals(
        importeBruto: subtotal + safeDiscount,
        descuento: safeDiscount,
        subtotal: subtotal,
        impuesto: tax,
        total: total,
      );
    }
    final gross = safeAmount;
    final subtotal = gross - safeDiscount;
    final tax = subtotal * .18;
    return ErpPurchaseTotals(
      importeBruto: gross,
      descuento: safeDiscount,
      subtotal: subtotal,
      impuesto: tax,
      total: subtotal + tax,
    );
  }
}
