import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Datos inmutables y renderer de la boleta de pago.
///
/// La fuente preferida es el RPC [appgt_obtener_contexto_boleta_v2]. El
/// constructor también entiende el snapshot de boletas anteriores para que la
/// descarga no falle mientras se regeneran documentos históricos.
class PayrollSlipPdf {
  static const int contextVersion = 2;
  static const int currentVersion = 3;

  static final PdfColor _deepTeal = PdfColor(0.027, 0.231, 0.298);
  static final PdfColor _teal = PdfColor(0.0, 0.54, 0.604);
  static final PdfColor _mint = PdfColor(0.91, 0.969, 0.965);
  static final PdfColor _ink = PdfColor(0.137, 0.192, 0.247);
  static final PdfColor _muted = PdfColor(0.39, 0.46, 0.51);
  static final PdfColor _border = PdfColor(0.76, 0.84, 0.85);

  static int versionOf(dynamic raw) {
    final parsed = _number(raw);
    return parsed?.round() ?? 0;
  }

  static PayrollSlipContext contextFromPayload(
    dynamic payload, {
    Map<String, dynamic>? fallbackSlip,
    dynamic fallbackSnapshot,
    Map<String, dynamic>? fallbackSettlement,
  }) {
    final root = _asMap(payload);
    final snapshot = _asMap(fallbackSnapshot);
    final slip = fallbackSlip ?? const <String, dynamic>{};
    final settlement = fallbackSettlement ?? const <String, dynamic>{};
    final rpcPeriod = _asMap(root['periodo']);
    final periodData = _mergeMaps(slip, rpcPeriod);
    final workerData = _mergeMaps(
      slip,
      snapshot,
      settlement,
      _asMap(root['trabajador']),
    );
    // El RPC V2 conserva el tipo de remuneración dentro de trabajador. Se
    // mezcla antes de liquidación para que esta última mantenga prioridad
    // para los montos, pero el renderer distinga jornales de sueldo.
    final liquidationData = _mergeMaps(
      snapshot,
      settlement,
      _asMap(root['trabajador']),
      _asMap(root['liquidacion']),
    );
    final summaryData = _asMap(root['resumen']);
    final dayValue = _value(root, const ['dias']);
    final hasDailyDetail = _hasKey(root, const ['dias']);
    final days = <PayrollSlipDay>[];
    for (final rawDay in _asList(dayValue)) {
      final day = PayrollSlipDay.fromJson(_asMap(rawDay));
      if (day.date != null) days.add(day);
    }
    days.sort((a, b) => a.date!.compareTo(b.date!));

    final start = _date(_value(periodData, const [
          'fecha_inicio',
          'inicio',
        ])) ??
        _date(_value(root, const ['fecha_inicio'])) ??
        DateTime.now();
    final end = _date(_value(periodData, const [
          'fecha_fin',
          'fin',
        ])) ??
        _date(_value(root, const ['fecha_fin'])) ??
        start;

    final worker = PayrollSlipWorker(
      dni: _text(_value(workerData, const ['dni', 'DNI'])),
      name: _text(_value(workerData, const [
        'nombre',
        'nombres',
        'trabajador',
      ])),
      position: _text(_value(workerData, const ['puesto', 'cargo'])),
      pensionSystem: _text(_value(workerData, const [
        'sistema_pension',
        'sistema_pensionario',
        'regimen_pensionario',
        'regimen_codigo',
        'SISTEMA_PENSION_CODIGO',
      ])),
      familyAllowance: _bool(_value(workerData, const [
        'asignacion_familiar',
        'tiene_asignacion_familiar',
        'ASIGNACION_FAMILIAR',
      ])),
      entryDate: _date(_value(workerData, const [
        'fecha_ingreso',
        'Fecha de Ingreso',
        'FECHA_INGRESO',
      ])),
      monthlySalary: _number(_value(workerData, const [
            'sueldo',
            'Sueldo',
            'SUELDO',
            'sueldo_mensual',
            'SUELDO_MENSUAL',
            'remuneracion_mensual',
          ])) ??
          0,
    );
    final dailySummary = PayrollSlipSummary.fromJson(
      summaryData,
      fallbackDays: days,
      hasDailyDetail: hasDailyDetail,
    );
    final isTestScenario =
        _bool(_value(root, const ['es_prueba', 'modo_prueba'])) ||
            _bool(_value(rpcPeriod, const ['es_prueba', 'modo_prueba'])) ||
            _bool(_value(_asMap(root['trabajador']), const [
              'es_prueba',
              'modo_prueba',
            ]));
    final contextLabel = _text(
      _value(
        _mergeMaps(rpcPeriod, root),
        const ['etiqueta', 'etiqueta_contexto', 'escenario'],
      ),
    );

    return PayrollSlipContext(
      version: versionOf(_value(root, const ['version'])),
      period: PayrollSlipPeriod(
          start: start, end: end.isBefore(start) ? start : end),
      worker: worker,
      summary: dailySummary,
      liquidation: PayrollSlipLiquidation(liquidationData),
      days: days,
      hasDailyDetail: hasDailyDetail,
      usedFallback: root.isEmpty,
      // No se imprime una etiqueta contextual ordinaria en el encabezado. La
      // única etiqueta opcional es la de prueba y requiere una señal explícita
      // del contexto; así se evita duplicar marca o texto de producción.
      headerLabel: (isTestScenario || _isTestLabel(contextLabel))
          ? (contextLabel.isNotEmpty ? contextLabel : 'Escenario de prueba')
          : '',
    );
  }

  /// [compress] se expone para pruebas binarias de codificación. La salida
  /// productiva sigue comprimida por defecto.
  static Future<Uint8List> build(
    PayrollSlipContext context, {
    bool compress = true,
  }) async {
    final pdf = pw.Document(compress: compress);
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 23, 24, 28),
        footer: (pageContext) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Boleta de pago - página ${pageContext.pageNumber}',
            style: pw.TextStyle(fontSize: 6.5, color: _muted),
          ),
        ),
        build: (_) => [
          _header(context),
          pw.SizedBox(height: 7),
          _identity(context),
          pw.SizedBox(height: 10),
          _sectionTitle('Detalle de boleta'),
          pw.SizedBox(height: 4),
          _detailTable(context),
          pw.SizedBox(height: 8),
          _netPay(context),
          pw.NewPage(),
          _dailyHeader(context),
          ..._calendarWidgets(context),
          pw.SizedBox(height: 5),
          _legend(),
          pw.SizedBox(height: 22),
          _signatures(),
        ],
      ),
    );
    return pdf.save();
  }

  static pw.Widget _dailyHeader(PayrollSlipContext context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            color: _deepTeal,
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'ZUMAC',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                if (context.headerLabel.isNotEmpty)
                  pw.Text(
                    context.headerLabel,
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 7.4,
                    ),
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: 13),
          pw.Text(
            'Detalle diario de Horas',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              color: _deepTeal,
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Horas totales o condición de la jornada',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 7.5, color: _muted),
          ),
          pw.SizedBox(height: 6),
        ],
      );

  static pw.Widget _header(PayrollSlipContext context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            color: _deepTeal,
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'ZUMAC',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                if (context.headerLabel.isNotEmpty)
                  pw.Text(
                    context.headerLabel,
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 7.4,
                    ),
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            'Boleta de pago',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              color: _deepTeal,
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Periodo: ${_formatDate(context.period.start)} al ${_formatDate(context.period.end)}',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(color: _muted, fontSize: 8.6),
          ),
        ],
      );

  static pw.Widget _identity(PayrollSlipContext context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Table(
            border: pw.TableBorder.all(color: _border, width: 0.45),
            columnWidths: const {
              0: pw.FlexColumnWidth(0.86),
              1: pw.FlexColumnWidth(1.55),
              2: pw.FlexColumnWidth(1.0),
            },
            children: [
              pw.TableRow(
                children: [
                  _identityCell('DNI', _orDash(context.worker.dni)),
                  _identityCell('Trabajador', _orDash(context.worker.name)),
                  _identityCell('Puesto', _orDash(context.worker.position)),
                ],
              ),
            ],
          ),
          pw.Table(
            border: pw.TableBorder.all(color: _border, width: 0.45),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.12),
              1: pw.FlexColumnWidth(1.05),
              2: pw.FlexColumnWidth(1.0),
              3: pw.FlexColumnWidth(0.9),
            },
            children: [
              pw.TableRow(
                children: [
                  _identityCell(
                    'Sistema pensionario',
                    _orDash(context.worker.pensionSystem),
                  ),
                  _identityCell(
                    'Asignación familiar',
                    context.worker.familyAllowance ? 'Sí' : 'No',
                  ),
                  _identityCell(
                    'Fecha de ingreso',
                    context.worker.entryDate == null
                        ? '-'
                        : _formatDate(context.worker.entryDate!),
                  ),
                  _identityCell(
                    'Sueldo',
                    context.worker.monthlySalary > 0
                        ? _money(context.worker.monthlySalary)
                        : '-',
                  ),
                ],
              ),
            ],
          ),
          pw.Table(
            border: pw.TableBorder.all(color: _border, width: 0.45),
            columnWidths: const {
              0: pw.FlexColumnWidth(),
              1: pw.FlexColumnWidth(),
              2: pw.FlexColumnWidth(),
              3: pw.FlexColumnWidth(),
            },
            children: [
              pw.TableRow(
                children: [
                  _identityCell(
                    'Días trabajados',
                    _formatCount(context.summary.workedDays),
                  ),
                  _identityCell(
                    'Descansos semanales',
                    _formatCount(context.summary.weeklyRestDays),
                  ),
                  _identityCell(
                    'Días permisos',
                    _formatCount(context.summary.permissionDays),
                  ),
                  _identityCell(
                    'Faltas',
                    _formatCount(context.summary.absenceDays),
                  ),
                ],
              ),
            ],
          ),
        ],
      );

  static pw.Widget _identityCell(String label, String value) => pw.Container(
        color: _mint,
        padding: const pw.EdgeInsets.fromLTRB(6, 5, 6, 5),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label.toUpperCase(),
              style: pw.TextStyle(
                color: _muted,
                fontSize: 6.25,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              value,
              style: pw.TextStyle(
                color: _ink,
                fontSize: 8.15,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      );

  static pw.Widget _sectionTitle(String value) => pw.Text(
        value,
        style: pw.TextStyle(
          color: _deepTeal,
          fontSize: 11.3,
          fontWeight: pw.FontWeight.bold,
        ),
      );

  static pw.Widget _detailTable(PayrollSlipContext context) {
    final incomes = context.incomeLines;
    final discounts = context.discountLines;
    final contributions = context.employerContributionLines;
    var rowCount = 1;
    rowCount = math.max(rowCount, incomes.length);
    rowCount = math.max(rowCount, discounts.length);
    rowCount = math.max(rowCount, contributions.length);
    final rows = <pw.TableRow>[
      pw.TableRow(
        children: [
          _detailHeader('Ingresos'),
          _detailHeader('Monto', right: true),
          _detailHeader('Descuentos'),
          _detailHeader('Monto', right: true),
          _detailHeader('Aportes empleador / EsSalud'),
        ],
      ),
    ];
    for (var index = 0; index < rowCount; index++) {
      final income = index < incomes.length ? incomes[index] : null;
      final discount = index < discounts.length ? discounts[index] : null;
      final contribution =
          index < contributions.length ? contributions[index] : null;
      rows.add(
        pw.TableRow(
          children: [
            _detailText(income?.concept ?? ''),
            _detailAmount(income?.amount),
            _detailText(discount?.concept ?? ''),
            _detailAmount(discount?.amount),
            _employerContributionCell(contribution),
          ],
        ),
      );
    }
    rows.add(
      pw.TableRow(
        children: [
          _detailTotal('Total ingresos'),
          _detailTotal(_money(context.totalIncome), right: true),
          _detailTotal('Total descuentos'),
          _detailTotal(_money(context.totalDiscounts), right: true),
          _detailTotal(''),
        ],
      ),
    );
    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: 0.4),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.4),
        1: pw.FlexColumnWidth(0.67),
        2: pw.FlexColumnWidth(1.3),
        3: pw.FlexColumnWidth(0.67),
        4: pw.FlexColumnWidth(1.12),
      },
      children: rows,
    );
  }

  static pw.Widget _detailHeader(String value, {bool right = false}) =>
      pw.Container(
        color: _deepTeal,
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: pw.Text(
          value,
          textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
          style: pw.TextStyle(
            color: PdfColors.white,
            fontSize: 6.8,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      );

  static pw.Widget _detailText(String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: pw.Text(
          value,
          style: pw.TextStyle(color: _ink, fontSize: 6.8),
        ),
      );

  static pw.Widget _detailAmount(double? amount) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: pw.Text(
          amount == null ? '' : _money(amount),
          textAlign: pw.TextAlign.right,
          style: pw.TextStyle(color: _ink, fontSize: 6.8),
        ),
      );

  static pw.Widget _employerContributionCell(PayrollSlipAmountLine? line) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: line == null
            ? pw.SizedBox()
            : pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    line.concept,
                    style: pw.TextStyle(color: _ink, fontSize: 6.7),
                  ),
                  pw.SizedBox(height: 1.5),
                  pw.Text(
                    _money(line.amount),
                    style: pw.TextStyle(
                      color: _muted,
                      fontSize: 6.55,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
      );

  static pw.Widget _detailTotal(String value, {bool right = false}) =>
      pw.Container(
        color: _mint,
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: pw.Text(
          value,
          textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
          style: pw.TextStyle(
            color: _ink,
            fontSize: 6.8,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      );

  static pw.Widget _netPay(PayrollSlipContext context) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: pw.BoxDecoration(
          color: _mint,
          border: pw.Border.all(color: _teal, width: 0.8),
        ),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                'Neto a pagar',
                style: pw.TextStyle(
                  color: _deepTeal,
                  fontSize: 11.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Text(
              _money(context.netPay),
              style: pw.TextStyle(
                color: _deepTeal,
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      );

  static List<pw.Widget> _calendarWidgets(PayrollSlipContext context) {
    final widgets = <pw.Widget>[];
    final weeks = context.calendarWeeks;
    for (final week in weeks) {
      widgets.add(pw.SizedBox(height: 5));
      widgets.add(
        pw.Text(
          'Semana del ${_formatDate(week.start)}',
          style: pw.TextStyle(
            color: _muted,
            fontSize: 7.1,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      );
      widgets.add(pw.SizedBox(height: 2));
      widgets.add(
        pw.Table(
          border: pw.TableBorder.all(color: _border, width: 0.35),
          columnWidths: const {
            0: pw.FlexColumnWidth(),
            1: pw.FlexColumnWidth(),
            2: pw.FlexColumnWidth(),
            3: pw.FlexColumnWidth(),
            4: pw.FlexColumnWidth(),
            5: pw.FlexColumnWidth(),
            6: pw.FlexColumnWidth(),
          },
          children: [
            pw.TableRow(
              children: week.cells
                  .map(
                    (cell) => pw.Container(
                      color: cell.inPeriod ? _deepTeal : PdfColors.grey300,
                      padding: const pw.EdgeInsets.symmetric(vertical: 3),
                      child: pw.Text(
                        cell.inPeriod ? cell.header : '',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          color: cell.inPeriod ? PdfColors.white : _muted,
                          fontSize: 6.4,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            pw.TableRow(
              children: week.cells
                  .map(
                    (cell) => pw.Container(
                      color:
                          cell.inPeriod ? PdfColors.white : PdfColors.grey100,
                      padding: const pw.EdgeInsets.symmetric(vertical: 5),
                      child: pw.Text(
                        cell.inPeriod ? cell.value : '',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          color: _ink,
                          fontSize: 7.1,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      );
    }
    return widgets;
  }

  static pw.Widget _legend() => pw.Container(
        padding: const pw.EdgeInsets.all(5),
        color: PdfColors.grey100,
        child: pw.Text(
          'Leyenda: DS = descanso semanal | F = falta | P = permiso/licencia | C = compensación | FE = feriado',
          style: pw.TextStyle(
            color: _muted,
            fontSize: 7.8,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      );

  static pw.Widget _signatures() => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(child: _signature('Firma del empleador')),
          pw.SizedBox(width: 32),
          pw.Expanded(child: _signature('Firma del trabajador')),
        ],
      );

  static pw.Widget _signature(String label) => pw.Column(
        children: [
          pw.SizedBox(height: 35),
          pw.Container(height: 0.7, color: _ink),
          pw.SizedBox(height: 4),
          pw.Text(
            label,
            style: pw.TextStyle(
              color: _ink,
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      );
}

class PayrollSlipContext {
  const PayrollSlipContext({
    required this.version,
    required this.period,
    required this.worker,
    required this.summary,
    required this.liquidation,
    required this.days,
    required this.hasDailyDetail,
    required this.usedFallback,
    this.headerLabel = '',
  });

  final int version;
  final PayrollSlipPeriod period;
  final PayrollSlipWorker worker;
  final PayrollSlipSummary summary;
  final PayrollSlipLiquidation liquidation;
  final List<PayrollSlipDay> days;
  final bool hasDailyDetail;
  final bool usedFallback;
  final String headerLabel;

  bool get hasLiquidationData => liquidation.values.isNotEmpty;

  List<PayrollSlipAmountLine> get incomeLines {
    final lines = <PayrollSlipAmountLine>[];
    void add(String concept, double value) {
      if (value > 0.004) lines.add(PayrollSlipAmountLine(concept, value));
    }

    final type = _normalize(liquidation.text(const [
      'tipo_remuneracion',
      'TIPO_REMUNERACION',
    ]));
    add(
      type == 'JORNAL'
          ? 'Remuneración básica (jornales trabajados)'
          : 'Remuneración básica',
      _basicJornales(),
    );
    add(
        'Descanso semanal remunerado',
        liquidation.amount(const [
          'descanso_semanal',
          'descanso_semanal_pagado',
        ]));
    add('Licencias y permisos remunerados', _paidLicenses());
    add('Compensación', _compensation());
    add(
      'Trabajo en descanso semanal - sobretasa 100%',
      liquidation.amount(const [
        'sobretasa_descanso_semanal_100',
        'sobretasa_dso_100',
      ]),
    );
    add('Asignación familiar',
        liquidation.amount(const ['asignacion_familiar']));
    add(
        'Horas extra 25%',
        liquidation.amount(const [
          'horas_extra_25_importe',
          'importe_horas_extra_25',
        ]));
    add(
        'Horas extra 35%',
        liquidation.amount(const [
          'horas_extra_35_importe',
          'importe_horas_extra_35',
        ]));
    final nightAmount = liquidation.amount(const [
      'nocturnidad_importe',
      'importe_nocturnidad',
    ]);
    final nightHours = liquidation.amount(const ['horas_nocturnas']);
    add(
      nightHours > 0
          ? 'Horas nocturnas (${_formatHours(nightHours)})'
          : 'Nocturnidad',
      nightAmount,
    );
    final cargo = liquidation.amount(const [
      'bono_cargo_pagado',
      'bono_cargo',
      'bono_cargo_importe',
      'bono_cargo_maestro',
    ]);
    final labor = liquidation.amount(const [
      'bono_labor_pagado',
      'bono_labor',
      'bono_labor_importe',
      'bono_labor_maestro',
    ]);
    final mobility = liquidation.amount(const [
      'bono_movilidad_pagado',
      'bono_movilidad',
      'bono_movilidad_importe',
      'bono_movilidad_maestro',
    ]);
    add('Bono al cargo', cargo);
    add('Bono por labor', labor);
    add('Bono movilidad', mobility);
    if (cargo <= 0.004 && labor <= 0.004 && mobility <= 0.004) {
      add(
          'Bonos al cargo / labor',
          liquidation.amount(const [
            'otros_ingresos_afectos',
          ]));
    } else {
      add(
          'Otros ingresos afectos',
          liquidation.amount(const [
            'otros_ingresos_afectos_no_bonos',
            'otros_bonos_afectos',
          ]));
    }
    // No se infiere un bono desde costos o ingresos genéricos de movilidad:
    // el único bono visible es el campo explícito anterior. Esto evita que un
    // costo corporativo de movilidad llegue a la boleta del trabajador.
    final otherUnaffected = liquidation.maybeAmount(const [
          'otros_ingresos_inafectos_no_movilidad',
        ]) ??
        liquidation.amount(const [
          'otros_ingresos_inafectos',
        ]);
    add('Otros ingresos inafectos', otherUnaffected);
    add('Bono BETA', liquidation.amount(const ['beta_pagado']));
    add('CTS prorrateada', liquidation.amount(const ['cts_pagada']));
    add(
        'Gratificación prorrateada',
        liquidation.amount(const [
          'gratificacion_pagada',
        ]));
    add(
        'Bono extraordinario gratificación',
        liquidation.amount(const [
          'bono_extraordinario_gratificacion',
        ]));
    return lines;
  }

  List<PayrollSlipAmountLine> get discountLines {
    final lines = <PayrollSlipAmountLine>[];
    void add(String concept, double value) {
      if (value > 0.004) lines.add(PayrollSlipAmountLine(concept, value));
    }

    add('ONP', liquidation.amount(const ['onp']));
    add('AFP aporte obligatorio', liquidation.amount(const ['afp_aporte']));
    add('AFP seguro', liquidation.amount(const ['afp_seguro']));
    add('AFP comisión', liquidation.amount(const ['afp_comision']));
    add(
        'Retención de quinta categoría',
        liquidation.amount(const [
          'retencion_quinta',
        ]));
    add('Otros descuentos', liquidation.amount(const ['otros_descuentos']));
    return lines;
  }

  List<PayrollSlipAmountLine> get employerContributionLines {
    final lines = <PayrollSlipAmountLine>[];
    void add(String concept, double value) {
      if (value > 0.004) lines.add(PayrollSlipAmountLine(concept, value));
    }

    add('EsSalud empleador', liquidation.amount(const ['essalud_empleador']));
    add('SCTR Salud', liquidation.amount(const ['sctr_salud']));
    add('SCTR Pensión', liquidation.amount(const ['sctr_pension']));
    return lines;
  }

  double get totalIncome {
    final visibleTotal =
        incomeLines.fold<double>(0, (sum, line) => sum + line.amount);
    // V2 expone cada componente de la boleta. Sumarlos garantiza que el total
    // publicado coincida con el detalle y no incorpore costos del empleador.
    if (version >= PayrollSlipPdf.contextVersion && visibleTotal > 0.004) {
      return visibleTotal;
    }
    final reported = liquidation.amount(const ['remuneracion_bruta']);
    if (reported > 0.004) return reported;
    return visibleTotal;
  }

  double get totalDiscounts {
    final reported = liquidation.amount(const ['total_descuentos']);
    if (reported > 0.004) return reported;
    return discountLines.fold<double>(0, (sum, line) => sum + line.amount);
  }

  double get totalEmployerContributions {
    final reported = liquidation.amount(const ['total_aportes_empleador']);
    if (reported > 0.004) return reported;
    return employerContributionLines.fold<double>(
        0, (sum, line) => sum + line.amount);
  }

  double get netPay {
    final reported = liquidation.amount(const ['neto_pagar', 'total_neto']);
    if (reported > 0.004 || totalIncome <= 0.004) return reported;
    return math.max(0, totalIncome - totalDiscounts).toDouble();
  }

  List<PayrollSlipCalendarWeek> get calendarWeeks {
    final daysByDate = <String, PayrollSlipDay>{
      for (final day in days)
        if (day.date != null) _dateKey(day.date!): day,
    };
    final rows = <PayrollSlipCalendarWeek>[];
    var weekStart =
        period.start.subtract(Duration(days: period.start.weekday - 1));
    final finalWeekStart =
        period.end.subtract(Duration(days: period.end.weekday - 1));
    while (!weekStart.isAfter(finalWeekStart)) {
      final cells = <PayrollSlipCalendarCell>[];
      for (var offset = 0; offset < 7; offset++) {
        final date = weekStart.add(Duration(days: offset));
        final inPeriod =
            !date.isBefore(period.start) && !date.isAfter(period.end);
        PayrollSlipDay? detail;
        if (inPeriod) {
          detail = daysByDate[_dateKey(date)] ??
              PayrollSlipDay(
                date: date,
                hoursTotal: 0,
                code: '',
              );
        }
        cells.add(
          PayrollSlipCalendarCell(
            date: date,
            inPeriod: inPeriod,
            detail: detail,
          ),
        );
      }
      rows.add(PayrollSlipCalendarWeek(start: weekStart, cells: cells));
      weekStart = weekStart.add(const Duration(days: 7));
    }
    return rows;
  }

  double _basicJornales() {
    final explicit = liquidation.maybeAmount(const [
      'remuneracion_basica_jornales',
      'jornales_trabajados_importe',
      'basico_jornales',
      'remuneracion_basica_sin_descanso',
    ]);
    if (explicit != null) return math.max(0, explicit).toDouble();
    final raw = liquidation.amount(const ['remuneracion_basica']);
    // El contrato V2 entrega este monto solo por jornal/tareo efectivo. Los
    // snapshots anteriores lo incluían junto con descanso y licencias.
    if (version >= PayrollSlipPdf.contextVersion) {
      return math.max(0, raw).toDouble();
    }
    final weeklyRest = liquidation.amount(const [
      'descanso_semanal',
      'descanso_semanal_pagado',
    ]);
    final paidLicenses = liquidation.amount(const ['licencias_pagadas']);
    return math.max(0, raw - weeklyRest - paidLicenses).toDouble();
  }

  double _compensation() => liquidation.amount(const [
        'compensacion_pagada',
        'compensacion_importe',
        'compensacion',
      ]);

  double _paidLicenses() {
    final explicit = liquidation.maybeAmount(const [
      'licencias_pagadas_sin_compensacion',
      'licencias_y_permisos_pagados',
    ]);
    if (explicit != null) return math.max(0, explicit).toDouble();
    return math
        .max(
          0,
          liquidation.amount(const ['licencias_pagadas']) - _compensation(),
        )
        .toDouble();
  }
}

class PayrollSlipPeriod {
  const PayrollSlipPeriod({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

class PayrollSlipWorker {
  const PayrollSlipWorker({
    required this.dni,
    required this.name,
    required this.position,
    required this.pensionSystem,
    required this.familyAllowance,
    required this.entryDate,
    required this.monthlySalary,
  });

  final String dni;
  final String name;
  final String position;
  final String pensionSystem;
  final bool familyAllowance;
  final DateTime? entryDate;
  final double monthlySalary;
}

class PayrollSlipSummary {
  const PayrollSlipSummary({
    required this.workedDays,
    required this.weeklyRestDays,
    required this.permissionDays,
    required this.absenceDays,
  });

  final double workedDays;
  final double weeklyRestDays;
  final double permissionDays;
  final double absenceDays;

  factory PayrollSlipSummary.fromJson(
    Map<String, dynamic> data, {
    required List<PayrollSlipDay> fallbackDays,
    required bool hasDailyDetail,
  }) {
    final worked = _number(_value(data, const [
      'dias_trabajados',
      'dias_laborados',
    ]));
    final weeklyRest = _number(_value(data, const [
      'descansos_semanales',
      'dias_descanso_semanal',
    ]));
    final permissions = _number(_value(data, const [
      'dias_permisos',
      'dias_permiso',
      'dias_licencia',
    ]));
    final absences = _number(_value(data, const ['faltas', 'dias_falta']));
    if (!hasDailyDetail) {
      return PayrollSlipSummary(
        workedDays: worked ?? 0,
        weeklyRestDays: weeklyRest ?? 0,
        permissionDays: permissions ?? 0,
        absenceDays: absences ?? 0,
      );
    }
    return PayrollSlipSummary(
      workedDays: worked ??
          fallbackDays.where((day) => day.hoursTotal > 0).length.toDouble(),
      weeklyRestDays: weeklyRest ??
          fallbackDays.where((day) => day.hasCode('DS')).length.toDouble(),
      permissionDays: permissions ??
          fallbackDays
              .where((day) => day.hasCode('P') || day.hasCode('C'))
              .length
              .toDouble(),
      absenceDays: absences ??
          fallbackDays.where((day) => day.hasCode('F')).length.toDouble(),
    );
  }
}

class PayrollSlipLiquidation {
  const PayrollSlipLiquidation(this.values);

  final Map<String, dynamic> values;

  double amount(List<String> names) => maybeAmount(names) ?? 0;

  double? maybeAmount(List<String> names) {
    final raw = _value(values, names);
    return raw == null ? null : (_number(raw) ?? 0);
  }

  String text(List<String> names) => _text(_value(values, names));
}

class PayrollSlipDay {
  const PayrollSlipDay({
    required this.date,
    required this.hoursTotal,
    required this.code,
  });

  factory PayrollSlipDay.fromJson(Map<String, dynamic> data) => PayrollSlipDay(
        date: _date(_value(data, const ['fecha', 'date'])),
        hoursTotal: _number(_value(data, const [
              'horas_totales',
              'horas_total',
            ])) ??
            0,
        code: _dayCodes(_value(data, const [
          'codigos',
          'codigo',
          'estado',
          'codigo_dia',
        ])),
      );

  final DateTime? date;
  final double hoursTotal;
  final String code;

  String get normalizedCode => _normalize(code);

  List<String> get normalizedCodes => _splitDayCodes(code);

  bool hasCode(String expected) =>
      normalizedCodes.contains(_canonicalDayCode(expected));

  String get display {
    final code = normalizedCodes.join(' / ');
    if (hoursTotal > 0.004) {
      return code.isEmpty
          ? _formatHours(hoursTotal)
          : '${_formatHours(hoursTotal)} / $code';
    }
    return code;
  }
}

class PayrollSlipCalendarWeek {
  const PayrollSlipCalendarWeek({required this.start, required this.cells});

  final DateTime start;
  final List<PayrollSlipCalendarCell> cells;
}

class PayrollSlipCalendarCell {
  const PayrollSlipCalendarCell({
    required this.date,
    required this.inPeriod,
    required this.detail,
  });

  final DateTime date;
  final bool inPeriod;
  final PayrollSlipDay? detail;

  String get header =>
      '${_weekdayShort(date)}\n${date.day.toString().padLeft(2, '0')}';

  String get value => detail?.display ?? '';
}

class PayrollSlipAmountLine {
  const PayrollSlipAmountLine(this.concept, this.amount);

  final String concept;
  final double amount;
}

Map<String, dynamic> _asMap(dynamic raw) {
  if (raw is String) {
    final text = raw.trim();
    if (text.isEmpty) return const <String, dynamic>{};
    try {
      return _asMap(jsonDecode(text));
    } catch (_) {
      return const <String, dynamic>{};
    }
  }
  if (raw is List && raw.isNotEmpty) return _asMap(raw.first);
  if (raw is! Map) return const <String, dynamic>{};
  return Map<String, dynamic>.fromEntries(
    raw.entries.map((entry) => MapEntry(entry.key.toString(), entry.value)),
  );
}

List<dynamic> _asList(dynamic raw) {
  if (raw is List) return List<dynamic>.from(raw);
  if (raw is String) {
    try {
      return _asList(jsonDecode(raw));
    } catch (_) {
      return const <dynamic>[];
    }
  }
  return const <dynamic>[];
}

Map<String, dynamic> _mergeMaps(Map<String, dynamic> first,
        [Map<String, dynamic>? second,
        Map<String, dynamic>? third,
        Map<String, dynamic>? fourth]) =>
    <String, dynamic>{
      ...first,
      ...?second,
      ...?third,
      ...?fourth,
    };

dynamic _value(Map<String, dynamic> data, List<String> names) {
  for (final name in names) {
    if (data.containsKey(name)) return data[name];
  }
  for (final entry in data.entries) {
    final key = _normalize(entry.key);
    if (names.any((name) => key == _normalize(name))) return entry.value;
  }
  return null;
}

bool _hasKey(Map<String, dynamic> data, List<String> names) =>
    names.any((name) =>
        data.containsKey(name) ||
        data.keys.any((key) => _normalize(key) == _normalize(name)));

double? _number(dynamic raw) {
  if (raw is num) return raw.toDouble();
  if (raw == null) return null;
  final source = raw.toString().trim();
  if (source.isEmpty) return null;
  var value = source.replaceAll(RegExp(r'[^0-9,.-]'), '');
  final lastComma = value.lastIndexOf(',');
  final lastDot = value.lastIndexOf('.');
  if (lastComma >= 0 && lastDot >= 0) {
    value = lastComma > lastDot
        ? value.replaceAll('.', '').replaceAll(',', '.')
        : value.replaceAll(',', '');
  } else if (lastComma >= 0) {
    value = value.replaceAll(',', '.');
  }
  return double.tryParse(value);
}

bool _bool(dynamic raw) {
  if (raw is bool) return raw;
  if (raw is num) return raw > 0;
  final normalized = _normalize(raw?.toString() ?? '');
  return normalized == 'SI' ||
      normalized == 'SÍ' ||
      normalized == 'TRUE' ||
      normalized == '1';
}

DateTime? _date(dynamic raw) {
  if (raw is DateTime) return DateTime(raw.year, raw.month, raw.day);
  if (raw == null) return null;
  final source = raw.toString().trim();
  if (source.isEmpty) return null;
  final iso = DateTime.tryParse(source);
  if (iso != null) return DateTime(iso.year, iso.month, iso.day);
  final match = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(source);
  if (match == null) return null;
  try {
    return DateTime(
      int.parse(match.group(3)!),
      int.parse(match.group(2)!),
      int.parse(match.group(1)!),
    );
  } catch (_) {
    return null;
  }
}

String _text(dynamic raw) => raw?.toString().trim() ?? '';

String _normalize(String value) => value.trim().toUpperCase();

bool _isTestLabel(String value) {
  final normalized = _normalize(value);
  return normalized.contains('PRUEBA') || normalized.contains('TEST');
}

String _dayCodes(dynamic raw) {
  final values = raw is List ? raw : <dynamic>[raw];
  final codes = <String>[];
  for (final value in values) {
    final source = value is Map
        ? _value(
            Map<String, dynamic>.fromEntries(
              value.entries.map(
                (entry) => MapEntry(entry.key.toString(), entry.value),
              ),
            ),
            const ['codigo', 'code', 'estado'],
          )
        : value;
    for (final part in _text(source).split(RegExp(r'[,/|;]+'))) {
      final code = _canonicalDayCode(part);
      if (code.isNotEmpty && !codes.contains(code)) codes.add(code);
    }
  }
  return codes.join(' / ');
}

List<String> _splitDayCodes(String raw) => _dayCodes(raw)
    .split(' / ')
    .where((code) => code.isNotEmpty)
    .toList(growable: false);

String _canonicalDayCode(String value) {
  final code = _normalize(value).replaceAll(RegExp(r'[_-]+'), ' ');
  if (code == 'DS' || code.contains('DESCANSO SEMANAL')) return 'DS';
  if (code == 'F' || code == 'FALTA' || code == 'FALTAS') return 'F';
  if (code == 'P' || code.contains('PERMISO') || code.contains('LICENCIA')) {
    return 'P';
  }
  if (code == 'C' ||
      code.contains('COMPENSACION') ||
      code.contains('COMPENSACIÓN')) {
    return 'C';
  }
  if (code == 'FE' || code.contains('FERIADO')) return 'FE';
  return code;
}

String _orDash(String value) => value.isEmpty ? '-' : value;

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

String _weekdayShort(DateTime date) => switch (date.weekday) {
      DateTime.monday => 'Lun',
      DateTime.tuesday => 'Mar',
      DateTime.wednesday => 'Mié',
      DateTime.thursday => 'Jue',
      DateTime.friday => 'Vie',
      DateTime.saturday => 'Sáb',
      _ => 'Dom',
    };

String _formatHours(double value) {
  final rounded = value.roundToDouble();
  final text = (value - rounded).abs() < 0.005
      ? rounded.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text h';
}

String _formatCount(double value) {
  final rounded = value.roundToDouble();
  return (value - rounded).abs() < 0.005
      ? rounded.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}

String _money(double value) {
  final sign = value < 0 ? '-' : '';
  final fixed = value.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts.first;
  final grouped = whole.replaceAllMapped(
    RegExp(r'(?<!^)(?=(\d{3})+$)'),
    (_) => ',',
  );
  return '${sign}S/ $grouped.${parts.last}';
}
