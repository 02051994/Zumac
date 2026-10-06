from __future__ import annotations

import os
from pathlib import Path

from reportlab.graphics.shapes import Drawing, Line, Rect, String
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    HRFlowable,
    Image,
    KeepTogether,
    LongTable,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "output" / "pdf" / "flujo_asistencia_tareo_permisos_sanciones_a_planilla.pdf"
LOGO = ROOT / "assets" / "images" / "logo_app.png"

NAVY = colors.HexColor("#0A2F60")
BLUE = colors.HexColor("#0D75D8")
CYAN = colors.HexColor("#08B9D4")
TEAL = colors.HexColor("#0E6B78")
GREEN = colors.HexColor("#1A8B6A")
AMBER = colors.HexColor("#E7A62B")
RED = colors.HexColor("#C84C4C")
INK = colors.HexColor("#243746")
MUTED = colors.HexColor("#5E7180")
PALE_BLUE = colors.HexColor("#EAF4FC")
PALE_TEAL = colors.HexColor("#E9F6F5")
PALE_AMBER = colors.HexColor("#FFF5DE")
PALE_RED = colors.HexColor("#FDECEC")
GRID = colors.HexColor("#CBD9E2")


def register_fonts() -> tuple[str, str]:
    regular_candidates = [
        Path(r"C:\Windows\Fonts\arial.ttf"),
        Path(r"C:\Windows\Fonts\calibri.ttf"),
    ]
    bold_candidates = [
        Path(r"C:\Windows\Fonts\arialbd.ttf"),
        Path(r"C:\Windows\Fonts\calibrib.ttf"),
    ]
    regular = next((p for p in regular_candidates if p.exists()), None)
    bold = next((p for p in bold_candidates if p.exists()), None)
    if regular and bold:
        pdfmetrics.registerFont(TTFont("ZumacSans", str(regular)))
        pdfmetrics.registerFont(TTFont("ZumacSansBold", str(bold)))
        return "ZumacSans", "ZumacSansBold"
    return "Helvetica", "Helvetica-Bold"


FONT, FONT_BOLD = register_fonts()


styles = getSampleStyleSheet()
styles.add(
    ParagraphStyle(
        name="CoverTitle",
        fontName=FONT_BOLD,
        fontSize=26,
        leading=31,
        textColor=colors.white,
        alignment=TA_LEFT,
        spaceAfter=14,
    )
)
styles.add(
    ParagraphStyle(
        name="CoverSub",
        fontName=FONT,
        fontSize=12,
        leading=17,
        textColor=colors.HexColor("#DCEBFA"),
        spaceAfter=8,
    )
)
styles.add(
    ParagraphStyle(
        name="H1Z",
        fontName=FONT_BOLD,
        fontSize=18,
        leading=22,
        textColor=NAVY,
        spaceBefore=2,
        spaceAfter=10,
        keepWithNext=True,
    )
)
styles.add(
    ParagraphStyle(
        name="H2Z",
        fontName=FONT_BOLD,
        fontSize=12.5,
        leading=16,
        textColor=TEAL,
        spaceBefore=8,
        spaceAfter=5,
        keepWithNext=True,
    )
)
styles.add(
    ParagraphStyle(
        name="BodyZ",
        fontName=FONT,
        fontSize=9.1,
        leading=13.2,
        textColor=INK,
        spaceAfter=6,
    )
)
styles.add(
    ParagraphStyle(
        name="SmallZ",
        fontName=FONT,
        fontSize=7.7,
        leading=10.5,
        textColor=INK,
    )
)
styles.add(
    ParagraphStyle(
        name="SmallBoldZ",
        fontName=FONT_BOLD,
        fontSize=7.8,
        leading=10.5,
        textColor=INK,
    )
)
styles.add(
    ParagraphStyle(
        name="CalloutZ",
        fontName=FONT,
        fontSize=9,
        leading=13,
        textColor=INK,
        leftIndent=8,
        rightIndent=8,
        spaceBefore=4,
        spaceAfter=4,
    )
)
styles.add(
    ParagraphStyle(
        name="CaptionZ",
        fontName=FONT,
        fontSize=7.4,
        leading=9.5,
        textColor=MUTED,
        alignment=TA_CENTER,
        spaceBefore=3,
        spaceAfter=7,
    )
)


def p(text: str, style: str = "BodyZ") -> Paragraph:
    return Paragraph(text, styles[style])


def bullets(items: list[str]) -> list:
    out: list = []
    for item in items:
        out.append(
            Paragraph(
                f"<font color='#0E6B78'>•</font> {item}",
                ParagraphStyle(
                    name=f"Bullet{len(out)}",
                    parent=styles["BodyZ"],
                    leftIndent=10,
                    firstLineIndent=-8,
                    spaceAfter=3,
                ),
            )
        )
    return out


def callout(title: str, text: str, bg=PALE_BLUE, accent=BLUE) -> Table:
    content = [
        Paragraph(f"<b>{title}</b>", styles["BodyZ"]),
        Paragraph(text, styles["CalloutZ"]),
    ]
    table = Table([[content]], colWidths=[170 * mm])
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), bg),
                ("BOX", (0, 0), (-1, -1), 0.7, accent),
                ("LINEBEFORE", (0, 0), (0, -1), 4, accent),
                ("LEFTPADDING", (0, 0), (-1, -1), 10),
                ("RIGHTPADDING", (0, 0), (-1, -1), 10),
                ("TOPPADDING", (0, 0), (-1, -1), 8),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
            ]
        )
    )
    return table


def make_table(
    rows: list[list[str]],
    widths: list[float],
    header_bg=NAVY,
    font_size: float = 7.7,
    repeat_rows: int = 1,
) -> LongTable:
    paragraph_rows = []
    for row_index, row in enumerate(rows):
        style = "SmallBoldZ" if row_index < repeat_rows else "SmallZ"
        paragraph_rows.append([p(value, style) for value in row])
    table = LongTable(
        paragraph_rows,
        colWidths=[value * mm for value in widths],
        repeatRows=repeat_rows,
        hAlign="LEFT",
    )
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, repeat_rows - 1), header_bg),
                ("TEXTCOLOR", (0, 0), (-1, repeat_rows - 1), colors.white),
                ("FONTNAME", (0, 0), (-1, repeat_rows - 1), FONT_BOLD),
                ("FONTSIZE", (0, 0), (-1, -1), font_size),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("GRID", (0, 0), (-1, -1), 0.35, GRID),
                ("ROWBACKGROUNDS", (0, repeat_rows), (-1, -1), [colors.white, colors.HexColor("#F6F9FB")]),
                ("LEFTPADDING", (0, 0), (-1, -1), 5),
                ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]
        )
    )
    return table


def flow_diagram() -> Drawing:
    drawing = Drawing(485, 155)
    nodes = [
        (5, 92, 88, 42, "1. Captura", "Asistencia\nTareo\nRR.HH.", BLUE),
        (102, 92, 88, 42, "2. Control", "Cruces\ny aprobaciones", TEAL),
        (199, 92, 88, 42, "3. Diario", "Horas y costo\npor labor/CC", GREEN),
        (296, 92, 88, 42, "4. Periodo", "Liquidacion\npor trabajador", AMBER),
        (393, 92, 88, 42, "5. Cierre", "Boleta, auditoria\ny bloqueo", NAVY),
    ]
    for x, y, w, h, title, subtitle, color in nodes:
        drawing.add(Rect(x, y, w, h, 8, 8, fillColor=color, strokeColor=color))
        drawing.add(String(x + 8, y + 27, title, fontName=FONT_BOLD, fontSize=8.5, fillColor=colors.white))
        for line_index, line in enumerate(subtitle.split("\n")):
            drawing.add(String(x + 8, y + 15 - line_index * 9, line, fontName=FONT, fontSize=7, fillColor=colors.white))
        if x < 390:
            drawing.add(Line(x + w, y + 21, x + w + 9, y + 21, strokeColor=MUTED, strokeWidth=1.3))
    stage_labels = [
        (49, "Registros fuente"),
        (146, "Sin inconsistencias"),
        (243, "Costo diario"),
        (340, "Liquidacion por trabajador"),
        (437, "Cierre del periodo"),
    ]
    for center_x, label in stage_labels:
        drawing.add(
            String(
                center_x,
                62,
                label,
                fontName=FONT_BOLD,
                fontSize=6.5,
                fillColor=MUTED,
                textAnchor="middle",
            )
        )
    drawing.add(Line(28, 45, 455, 45, strokeColor=GRID, strokeWidth=1))
    drawing.add(String(8, 29, "Regla central:", fontName=FONT_BOLD, fontSize=8, fillColor=NAVY))
    drawing.add(String(75, 29, "la planilla no se llena manualmente; se reconstruye desde las fuentes aprobadas.", fontName=FONT, fontSize=8, fillColor=INK))
    return drawing


def cost_stack_diagram() -> Drawing:
    drawing = Drawing(485, 145)
    colors_list = [BLUE, CYAN, GREEN, AMBER, colors.HexColor("#8E6BBE")]
    labels = [
        ("Horas y ausencias", "ordinarias, HE 25/35, nocturnas, permisos"),
        ("Ingresos", "basico, asignacion, DSO, licencias, BETA, bonos"),
        ("Descuentos", "ONP/AFP, seguro, comision flujo, quinta"),
        ("Empleador", "EsSalud, SCTR, provisiones"),
        ("Movilidad", "costo por asiento o costo/capacidad"),
    ]
    y = 105
    for index, ((title, subtitle), color) in enumerate(zip(labels, colors_list)):
        width = 440 - index * 34
        x = 20 + index * 17
        drawing.add(Rect(x, y - index * 20, width, 18, 4, 4, fillColor=color, strokeColor=color))
        drawing.add(String(x + 7, y + 6 - index * 20, title, fontName=FONT_BOLD, fontSize=7.4, fillColor=colors.white))
        drawing.add(String(x + 92, y + 6 - index * 20, subtitle, fontName=FONT, fontSize=6.8, fillColor=colors.white))
    drawing.add(String(20, 8, "Resultado: costo diario distribuido + liquidacion del periodo + costo total con movilidad.", fontName=FONT_BOLD, fontSize=8, fillColor=NAVY))
    return drawing


def header_footer(canvas, doc):
    canvas.saveState()
    page = canvas.getPageNumber()
    if page > 1:
        canvas.setFillColor(NAVY)
        canvas.rect(0, A4[1] - 17 * mm, A4[0], 17 * mm, fill=1, stroke=0)
        canvas.setFillColor(colors.white)
        canvas.setFont(FONT_BOLD, 8)
        canvas.drawString(20 * mm, A4[1] - 10.5 * mm, "ZUMAC | Flujo operativo hacia planilla")
        canvas.setStrokeColor(CYAN)
        canvas.setLineWidth(1.4)
        canvas.line(20 * mm, 15 * mm, A4[0] - 20 * mm, 15 * mm)
        canvas.setFillColor(MUTED)
        canvas.setFont(FONT, 7.5)
        canvas.drawString(20 * mm, 9.5 * mm, "Documento funcional basado en la implementacion del proyecto - 06/10/2026")
        canvas.drawRightString(A4[0] - 20 * mm, 9.5 * mm, f"Pagina {page}")
    canvas.restoreState()


def build_story() -> list:
    story: list = []

    cover = Table(
        [
            [
                Image(str(LOGO), width=38 * mm, height=38 * mm) if LOGO.exists() else "",
                [
                    p("FLUJO OPERATIVO HACIA PLANILLA", "CoverTitle"),
                    p("Asistencia + Tareo + Permisos y Licencias + Sanciones", "CoverSub"),
                    p("Desde la captura y las aprobaciones hasta el costo diario, la liquidacion y el detalle por trabajador.", "CoverSub"),
                ],
            ]
        ],
        colWidths=[45 * mm, 120 * mm],
        rowHeights=[72 * mm],
    )
    cover.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), NAVY),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LEFTPADDING", (0, 0), (-1, -1), 10),
                ("RIGHTPADDING", (0, 0), (-1, -1), 10),
                ("TOPPADDING", (0, 0), (-1, -1), 10),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 10),
            ]
        )
    )
    story.extend(
        [
            Spacer(1, 36 * mm),
            cover,
            Spacer(1, 15 * mm),
            callout(
                "Objetivo",
                "Explicar que se registra en cada formato, que controles se aplican, que dato downstream modifica y como esos datos terminan en la planilla y en el costo de cada trabajador.",
                bg=PALE_TEAL,
                accent=TEAL,
            ),
            Spacer(1, 8 * mm),
            p("Version funcional: 06 de octubre de 2026", "H2Z"),
            p("Alcance: comportamiento implementado en Flutter y Supabase. No reemplaza la revision laboral, contable o legal de la empresa.", "BodyZ"),
            PageBreak(),
        ]
    )

    story.extend(
        [
            p("1. Mapa completo del flujo", "H1Z"),
            p(
                "El sistema usa una sola cadena de datos. Los formatos operativos no calculan una boleta final: crean evidencias y distribuciones que luego son validadas y consolidadas por el motor de planilla.",
            ),
            flow_diagram(),
            p("Lectura rapida", "H2Z"),
            make_table(
                [
                    ["Etapa", "Entrada", "Control principal", "Salida"],
                    ["Captura", "Asistencia, tareo, permisos/licencias y sanciones", "Identidad, fechas, contrato, duplicados, movilidad y documentos", "Registros fuente"],
                    ["Aprobacion", "Tareos y novedades de RR.HH.", "Permiso de aprobar, horas extra autorizadas, documento cuando aplica", "Fuentes habilitadas para planilla"],
                    ["Costeo diario", "Personal + asistencia + tareo aprobado + permisos aprobados", "Cruce por DNI y fecha", "PLANILLA_TRABAJADORES_ZUMAC"],
                    ["Liquidacion", "Filas diarias del periodo + parametros legales", "Validaciones sin errores", "PLANILLA_LIQUIDACION_TRABAJADOR_APPGT"],
                    ["Ciclo", "Periodo calculado", "Revisar -> Aprobar -> Cerrar", "Totales, boletas preparadas, auditoria y bloqueo"],
                ],
                [25, 46, 58, 41],
            ),
            Spacer(1, 4 * mm),
            callout(
                "Idea clave",
                "Asistencia confirma presencia. Tareo aprobado explica en que se uso el tiempo. Permisos aprobados explican la ausencia o reclasifican horas. Sanciones aprobadas pueden impedir la asistencia, pero no generan automaticamente un descuento monetario.",
                bg=PALE_AMBER,
                accent=AMBER,
            ),
            PageBreak(),
        ]
    )

    story.extend(
        [
            p("2. Matriz solicitada: formato -> que hace -> que afecta -> como se llena", "H1Z"),
            make_table(
                [
                    ["Formato", "Que hace", "Que afecta", "Como se llena"],
                    [
                        "Asistencia",
                        "Marca ingreso y salida por DNI/QR. Conserva fecha, hora, movilidad, reclutador y observacion de la tanda.",
                        "Acredita presencia; habilita el cruce con tareo; aporta placa para costo de movilidad y sirve para validar contrato/sanciones.",
                        "Elegir Ingreso o Salida; completar placa, reclutador y observacion si aplican; abrir el escaner; leer cada QR; cerrar al terminar la movilidad. Al cerrar se limpian solo esos tres datos para evitar arrastrarlos a la siguiente movilidad.",
                    ],
                    [
                        "Tareo",
                        "Distribuye las horas presentes por labor, lote/variedad, area y centro de costo; descuenta refrigerio y detecta horas extra.",
                        "Crea la distribucion diaria de costo. Solo el tareo APROBADO se toma como fuente valida para planilla y descansos.",
                        "Indicar fecha, labor, turno/lote, variedad, area y centro de costo; agregar trabajadores por busqueda o QR; completar inicio/fin; revisar refrigerio de 45 min; agregar observacion; guardar/cerrar y enviar a aprobacion.",
                    ],
                    [
                        "Permisos y licencias",
                        "Justifica ausencia total o parcial, con o sin goce, y clasifica descanso medico, maternidad, paternidad, fallecimiento, comision, vacaciones, teletrabajo o compensacion.",
                        "Reclasifica horas diarias; puede pagar licencias, reducir dias/horas sin goce y alterar DSO, BETA, beneficios y liquidacion.",
                        "Escanear/seleccionar DNI; verificar trabajador, puesto y area; elegir tipo; indicar fechas y horas si es parcial; motivo/observacion; adjuntar PDF solo cuando el tipo lo exige; firmar; en COMPENSACION completar Fecha trabajada a compensar.",
                    ],
                    [
                        "Sanciones",
                        "Registra amonestacion o suspension, su vigencia, motivo y si bloquea asistencia.",
                        "Una sancion aprobada y vigente con bloqueo impide marcar asistencia. No crea por si sola un descuento en la liquidacion.",
                        "Seleccionar DNI; revisar trabajador; elegir tipo; colocar inicio/fin, motivo y Bloquea asistencia. La suspension exige bloqueo. Enviar a aprobacion; solo APROBADA pasa a VIGENTE.",
                    ],
                ],
                [27, 45, 48, 50],
                font_size=7.2,
            ),
            Spacer(1, 5 * mm),
            callout(
                "Dependencia obligatoria",
                "El maestro GH-REGISTRO_PERSONAL_PLANILLA debe tener al trabajador activo, contrato vigente y datos laborales completos. Sin ese maestro, la captura puede bloquearse y el periodo no se calcula.",
                bg=PALE_RED,
                accent=RED,
            ),
            PageBreak(),
        ]
    )

    story.extend(
        [
            p("3. Asistencia: presencia, movilidad y cierre de cada tanda", "H1Z"),
            p("Que se registra", "H2Z"),
            make_table(
                [
                    ["Dato", "Uso", "Regla operativa"],
                    ["Fecha", "Dia de la marcacion", "Se toma del dia operativo."],
                    ["Tipo de movimiento", "INGRESO o SALIDA", "Ingreso crea la marcacion; salida completa la existente."],
                    ["Placa / movilidad", "Vincula transporte y costo de movilidad", "Debe corresponder a movilidad autorizada cuando se utiliza."],
                    ["Reclutador", "Responsable/referencia de la tanda", "Se copia a las personas escaneadas en esa tanda."],
                    ["Observacion", "Contexto de la movilidad o incidencia", "Se conserva con los registros de la tanda."],
                    ["DNI / QR", "Identifica al trabajador", "No admite DNI sin registro laboral valido."],
                    ["Horas de ingreso/salida", "Evidencia temporal", "Se generan al escanear; salida requiere ingreso previo."],
                ],
                [34, 58, 78],
            ),
            p("Controles antes de guardar", "H2Z"),
            *bullets(
                [
                    "El trabajador debe existir en el registro de personal, estar ACTIVO y tener contrato vigente para la fecha.",
                    "Una sancion VIGENTE y aprobada que bloquea asistencia impide la marcacion durante su rango.",
                    "No se permite un segundo ingreso del mismo trabajador para la misma jornada; la salida debe encontrar el ingreso abierto.",
                    "Cuando hay placa, se valida la movilidad y su documentacion/estado segun la configuracion vigente.",
                    "El escaner continuo acepta un QR nuevo despues de 0.6 segundos y conserva una barrera adicional contra la repeticion inmediata del mismo codigo.",
                ]
            ),
            callout(
                "Cambio operativo incluido",
                "Al cerrar la ventana del escaner se restablecen Placa/Movilidad, Reclutador y Observacion tanto en Ingreso como en Salida. Fecha, tipo de movimiento y personas ya marcadas no se borran.",
                bg=PALE_TEAL,
                accent=GREEN,
            ),
            p("Efecto downstream", "H2Z"),
            p("La asistencia no asigna labor ni centro de costo. Su funcion es acreditar la presencia y aportar, cuando existe, la placa usada para calcular el costo de movilidad de ese trabajador y dia."),
            PageBreak(),
        ]
    )

    story.extend(
        [
            p("4. Tareo: horas, labor y centro de costo", "H1Z"),
            p("Que se llena", "H2Z"),
            make_table(
                [
                    ["Bloque", "Campos principales", "Resultado"],
                    ["Cabecera", "Fecha, labor, turno/lote, variedad, area, centro de costo", "Define donde se imputara el trabajo."],
                    ["Trabajadores", "DNI y nombres por busqueda o QR", "Crea una fila por trabajador para la misma cabecera."],
                    ["Horario", "Hora inicio, hora fin", "Calcula horas netas; admite jornada nocturna."],
                    ["Refrigerio", "Inicio 12:00, fin 12:45, 45 minutos", "Se descuenta cuando el tramo abarca todo el refrigerio; se rechaza un tramo parcial dentro del refrigerio."],
                    ["Observacion", "Incidencia o aclaracion", "Queda como evidencia del tareo."],
                ],
                [32, 72, 66],
            ),
            p("Aprobacion y horas extra", "H2Z"),
            *bullets(
                [
                    "El servidor suma las horas del trabajador en el dia. Lo que supera 8 horas solicita horas extra.",
                    "Antes de aprobar un tareo con horas extra, estas deben estar AUTORIZADAS; queda usuario, fecha, hora y observacion de autorizacion.",
                    "Solo ESTADO_APROBACION = APROBADO entra a los cruces de planilla.",
                    "La clave evita duplicar una misma combinacion trabajador + fecha + labor + centro de costo, pero permite distribuir la misma jornada entre centros distintos.",
                ]
            ),
            p("Como llega al costo diario", "H2Z"),
            p("El motor ordena las filas del dia y reparte las primeras horas hasta la jornada ordinaria, luego las dos primeras extras al 25 % y el exceso siguiente al 35 %. Conserva labor, variedad y centro de costo, por lo que el costo diario queda trazable a la operacion que lo origino."),
            callout(
                "Correccion visual incluida",
                "La tabla de Trabajadores reserva una franja inferior exclusiva para el scroll horizontal. La barra ya no cruza la ultima fila.",
                bg=PALE_BLUE,
                accent=BLUE,
            ),
            PageBreak(),
        ]
    )

    story.extend(
        [
            p("5. Permisos y licencias: clasificacion de ausencias", "H1Z"),
            p("Captura", "H2Z"),
            make_table(
                [
                    ["Dato", "Como se usa"],
                    ["DNI / trabajador", "Busca personal y completa nombre, puesto y area."],
                    ["Tipo", "Determina goce, sustento y concepto de planilla."],
                    ["Inicio / fin", "Rango de dias. Para permiso parcial se usan hora inicio/fin."],
                    ["Motivo / observaciones", "Explican la solicitud y dejan trazabilidad."],
                    ["Documento PDF", "Obligatorio solo para descanso medico, maternidad, paternidad y fallecimiento."],
                    ["Firma", "Evidencia del trabajador cuando la captura lo requiere."],
                    ["Fecha trabajada a compensar", "Aparece y se exige solo cuando Tipo = COMPENSACION."],
                ],
                [57, 113],
            ),
            p("Efecto en planilla", "H2Z"),
            make_table(
                [
                    ["Tipo / condicion", "Tratamiento"],
                    ["Con goce", "Cuenta como ausencia pagada; alimenta el concepto correspondiente y puede contar para descanso semanal segun la regla vigente."],
                    ["Sin goce", "Registra horas/dias no pagados; reduce dias computables y bases donde corresponda."],
                    ["Compensacion", "Es ausencia pagada vinculada a un dia trabajado de descanso/feriado; exige asistencia y tareo aprobado en la fecha origen y no se trata como hora extra."],
                    ["Vacaciones", "Reclasifica las horas al concepto vacaciones y alimenta la liquidacion del periodo."],
                    ["Teletrabajo / comision", "Reclasifica el dia u horas segun el tipo aprobado."],
                ],
                [48, 122],
            ),
            p("Aprobacion", "H2Z"),
            p("El registro nace pendiente. Un usuario con permiso de APROBAR lo resuelve. Al aprobar se fijan aprobador, fecha, reincorporacion y datos de la empresa; el periodo solo considera registros con estado y estado de aprobacion en APROBADO."),
            callout(
                "Importante",
                "El formulario oculta Fecha trabajada a compensar en todos los demas tipos y limpia cualquier valor anterior al cambiar de COMPENSACION a otro tipo.",
                bg=PALE_TEAL,
                accent=GREEN,
            ),
            PageBreak(),
        ]
    )

    story.extend(
        [
            p("6. Sanciones: control laboral y efecto indirecto", "H1Z"),
            make_table(
                [
                    ["Campo", "Como se llena", "Efecto"],
                    ["DNI / trabajador", "Seleccionar o escanear al trabajador correcto.", "Identifica a quien se aplica la medida."],
                    ["Tipo", "Amonestacion verbal, escrita, suspension u otra.", "Define la naturaleza de la sancion."],
                    ["Fecha inicio / fin", "Rango de vigencia.", "Delimita cuando el control esta activo."],
                    ["Bloquea asistencia", "Activar cuando la medida impide trabajar; es obligatorio en suspension.", "La asistencia rechaza la marcacion durante el rango."],
                    ["Motivo", "Describir hechos y decision.", "Trazabilidad y documento interno."],
                    ["Aprobacion", "PENDIENTE/REVISADO -> APROBADO.", "Solo APROBADO pasa a VIGENTE."],
                ],
                [34, 75, 61],
            ),
            Spacer(1, 5 * mm),
            callout(
                "Que NO hace",
                "La sancion no inserta un descuento, una multa ni una licencia en la liquidacion. Su efecto directo es bloquear la asistencia cuando corresponde. Si una suspension debe convertirse en ausencia sin goce, debe existir tambien la novedad de permiso/licencia aprobada que clasifique esa ausencia; de lo contrario, la validacion del periodo puede detectar que faltan fuentes.",
                bg=PALE_RED,
                accent=RED,
            ),
            p("Flujo de estados", "H2Z"),
            make_table(
                [
                    ["Estado de aprobacion", "Estado operativo", "Puede bloquear asistencia"],
                    ["PENDIENTE / REVISADO", "BORRADOR", "No"],
                    ["APROBADO", "VIGENTE (o CUMPLIDA si ya concluyo)", "Si, cuando Bloquea asistencia = verdadero y la fecha esta dentro del rango"],
                    ["RECHAZADO", "BORRADOR", "No"],
                    ["ANULADO", "ANULADA", "No"],
                ],
                [48, 48, 74],
            ),
            PageBreak(),
        ]
    )

    story.extend(
        [
            p("7. Puertas de control antes de calcular", "H1Z"),
            p("El boton Validar y calcular no continua si hay errores. Las validaciones comparan las fuentes del periodo y los datos laborales/legales."),
            make_table(
                [
                    ["Control", "Que detecta", "Como se corrige"],
                    ["Personal", "Contrato/estado/datos laborales incompletos, regimen o pension sin configurar", "Corregir GH-REGISTRO_PERSONAL_PLANILLA."],
                    ["Asistencia vs. tareo", "Asistencia sin tareo aprobado o tareo aprobado sin asistencia", "Completar o corregir la fuente del mismo DNI y fecha."],
                    ["Tareo pendiente", "ESTADO_APROBACION distinto de APROBADO dentro del periodo", "Revisar, autorizar horas extra si aplica y aprobar."],
                    ["Permiso pendiente", "Permiso/licencia no resuelto dentro del periodo", "Aprobar, rechazar o anular."],
                    ["Permisos superpuestos", "Dos novedades aprobadas cubren el mismo DNI/fecha", "Corregir rangos o anular el duplicado."],
                    ["Fuentes ausentes", "Trabajador activo sin asistencia, tareo ni permiso aprobado", "Registrar la fuente real; no inventar una fila de planilla."],
                    ["Parametros", "RMV, UIT, AFP, SCTR o vigencias faltantes", "Completar configuracion legal antes del calculo."],
                    ["Cambios posteriores", "Fuentes modificadas despues del calculo", "Volver a Validar y recalcular."],
                ],
                [42, 69, 59],
            ),
            p("Secuencia de aprobaciones", "H2Z"),
            *bullets(
                [
                    "Tareo: cerrar/guardar -> autorizar horas extra si aplica -> aprobar.",
                    "Permiso/licencia: registrar -> adjuntar sustento cuando aplica -> resolver/aprobar.",
                    "Sancion: registrar -> revisar -> aprobar para que pase a VIGENTE.",
                    "Periodo: BORRADOR -> Validar y calcular -> CALCULADA -> REVISAR -> REVISADA -> APROBAR -> APROBADA -> CERRAR -> CERRADA.",
                ]
            ),
            PageBreak(),
        ]
    )

    story.extend(
        [
            p("8. Costeo diario: detalle por trabajador, labor y centro", "H1Z"),
            p("PLANILLA_TRABAJADORES_ZUMAC es una tabla derivada. Puede tener varias filas para un trabajador y dia porque cada fila conserva la distribucion por labor/centro de costo. No es la boleta final."),
            cost_stack_diagram(),
            make_table(
                [
                    ["Grupo de columnas", "Contenido", "Lectura"],
                    ["Trazabilidad", "DNI, fecha, tareo_id, origen_clave, labor, centro_costo, variedad", "Permite regresar a la fuente que genero el costo."],
                    ["Horas", "Ordinarias, HE 25 %, HE 35 %, nocturnas, descanso semanal, licencias, permiso sin goce, vacaciones, compensacion", "Explica la cantidad fisica pagada o descontada."],
                    ["Ingresos/costos", "Basico, asignacion, DSO, HE, nocturnidad, licencias, BETA, bonos", "Costo monetario diario distribuido."],
                    ["Retenciones", "ONP o AFP, seguro, comision de flujo", "Deducciones del trabajador; no se suman otra vez al costo empresa."],
                    ["Empleador", "EsSalud y costos/provisiones derivados", "Componentes adicionales a cargo de la empresa."],
                    ["Movilidad", "costo_boleta_trabajador, costo_movilidad_empresa, costo_total_con_movilidad", "Separa remuneracion/costo y transporte para evitar mezclarlos."],
                ],
                [42, 74, 54],
            ),
            p("Movilidad", "H2Z"),
            p("Para cada DNI y fecha, la placa de asistencia se cruza con la matriz de movilidades. Si existe costo por asiento se usa directamente; si solo hay costo total y capacidad, se calcula costo total / capacidad. En el detalle diario, costo total con movilidad = importe visible del trabajador + movilidad. En la liquidacion del periodo, la movilidad se suma aparte al costo total empresa."),
            PageBreak(),
        ]
    )

    story.extend(
        [
            p("9. Liquidacion por periodo y costo final", "H1Z"),
            p("PLANILLA_LIQUIDACION_TRABAJADOR_APPGT consolida todas las filas diarias de un DNI dentro del periodo y aplica las reglas legales/configuradas."),
            make_table(
                [
                    ["Bloque", "Incluye", "Resultado"],
                    ["Tiempo computable", "Dias base, dias sin goce, horas ordinarias, extra, nocturnas y licencias", "Cantidad que alimenta remuneracion y beneficios."],
                    ["Ingresos", "Basico, asignacion familiar, descanso semanal, HE, nocturnidad, licencias pagadas, compensacion, BETA, CTS/gratificacion segun modalidad", "Remuneracion bruta."],
                    ["Descuentos", "ONP o AFP, prima de seguro, comision de flujo y quinta categoria", "Total descuentos y neto a pagar."],
                    ["Desembolsos", "Neto + deposito CTS cuando corresponde", "Total desembolso al trabajador."],
                    ["Costo empresa", "Remuneracion devengada + EsSalud + SCTR + provisiones, sin duplicar beneficios", "Costo total empresa."],
                    ["Movilidad", "Suma del costo diario de transporte", "Costo total con movilidad."],
                ],
                [38, 82, 50],
            ),
            p("Formulas de lectura", "H2Z"),
            *bullets(
                [
                    "Neto a pagar = remuneracion bruta - descuentos del trabajador.",
                    "Total desembolso = neto a pagar + deposito CTS del periodo, cuando corresponde.",
                    "Costo empresa = remuneracion devengada + aportes patronales + provisiones no pagadas, evitando duplicidades.",
                    "Costo total con movilidad = costo total empresa + movilidad empresa.",
                ]
            ),
            callout(
                "No confundir",
                "El neto que recibe el trabajador, el costo de la empresa y el costo distribuido a un centro de costo son lecturas distintas del mismo periodo. La tabla diaria sirve para distribucion; la liquidacion es la fuente monetaria autoritativa por trabajador.",
                bg=PALE_AMBER,
                accent=AMBER,
            ),
            PageBreak(),
        ]
    )

    story.extend(
        [
            p("10. Que pasa al Revisar, Aprobar y Cerrar", "H1Z"),
            make_table(
                [
                    ["Accion", "Condicion", "Que sucede"],
                    ["Validar y calcular", "Periodo BORRADOR o CALCULADA y cero errores", "Reconstruye costo diario, aplica permisos, genera liquidaciones, actualiza totales y deja CALCULADA."],
                    ["Revisar", "Periodo CALCULADA y sin cambios pendientes", "Deja constancia del revisor y pasa a REVISADA."],
                    ["Aprobar", "Periodo REVISADA", "Registra aprobador y pasa a APROBADA."],
                    ["Cerrar", "Periodo APROBADA", "Recalcula totales, prepara las boletas/snapshots, bloquea fuentes del rango y pasa a CERRADA."],
                    ["Reabrir", "Periodo CERRADA, usuario autorizado y motivo obligatorio", "Vuelve a BORRADOR; toda correccion exige recalcular, revisar y aprobar nuevamente."],
                ],
                [33, 58, 79],
            ),
            p("Despues del cierre", "H2Z"),
            *bullets(
                [
                    "Asistencia, tareo, permisos y filas calculadas del rango quedan protegidos contra cambios accidentales.",
                    "Se preparan registros de boleta con una instantanea de la liquidacion; la generacion/entrega del PDF de boleta sigue su proceso propio.",
                    "Toda transicion y reapertura queda auditada con usuario, fecha, estado anterior/nuevo y motivo.",
                    "El sistema no sustituye PLAME, AFPnet, archivo bancario, asiento contable, liquidacion por cese ni utilidades; esos son procesos separados.",
                ]
            ),
            p("Controles finales recomendados", "H2Z"),
            make_table(
                [
                    ["Responsable", "Revisar antes de avanzar"],
                    ["Operaciones", "Que todas las movilidades/tandas terminaron y que asistencia y salida corresponden al dia."],
                    ["Supervisor de tareo", "Labor, centro de costo, horas, refrigerio, trabajadores y horas extra."],
                    ["Gestion Humana", "Permisos/licencias y sanciones resueltos, documentos y firmas cuando aplican."],
                    ["Planillas", "Cero validaciones, muestra de trabajadores, parametros, totales y diferencias contra control independiente."],
                    ["Aprobador", "Liquidacion, costo empresa, movilidad y evidencia de revision antes del cierre."],
                ],
                [48, 122],
            ),
            PageBreak(),
        ]
    )

    story.extend(
        [
            p("11. Ejemplo trazable de un trabajador", "H1Z"),
            p("Ejemplo conceptual (sin fijar tasas legales):"),
            make_table(
                [
                    ["Paso", "Registro", "Efecto"],
                    ["1", "Asistencia: DNI 12345678, ingreso y salida, placa ABC-123", "Confirma presencia y habilita movilidad del dia."],
                    ["2", "Tareo aprobado: 8 h en labor COSECHA, centro de costo LOTE-01", "Crea distribucion diaria de 8 h para LOTE-01."],
                    ["3", "Permiso aprobado de 2 h con goce", "El motor reclasifica 2 h al concepto pagado y conserva la trazabilidad diaria."],
                    ["4", "Costo diario", "Calcula basico/conceptos, retenciones y costo de movilidad por la placa."],
                    ["5", "Liquidacion del periodo", "Suma todas las fechas y calcula neto, aportes, provisiones y costo empresa."],
                    ["6", "Cierre", "Prepara boleta, bloquea fuentes y conserva auditoria."],
                ],
                [18, 82, 70],
            ),
            Spacer(1, 7 * mm),
            callout(
                "Si existe una suspension",
                "Una sancion aprobada puede impedir el paso 1. Para que el periodo explique correctamente ese dia, Gestion Humana debe registrar la novedad laboral que corresponda (por ejemplo, una ausencia sin goce aprobada). La sancion sola no inventa una linea de descuento.",
                bg=PALE_RED,
                accent=RED,
            ),
            p("Checklist de cierre operativo", "H2Z"),
            *bullets(
                [
                    "Cruce asistencia/tareo sin diferencias.",
                    "Tareos APROBADOS y horas extra AUTORIZADAS.",
                    "Permisos/licencias y sanciones resueltos.",
                    "Periodo validado sin errores y recalculado despues del ultimo cambio.",
                    "Detalle diario revisado por labor/centro de costo.",
                    "Liquidacion y costo total con movilidad revisados por trabajador.",
                    "Aprobacion y cierre ejecutados por usuarios autorizados.",
                ]
            ),
            Spacer(1, 6 * mm),
            HRFlowable(width="100%", color=CYAN, thickness=1.5),
            Spacer(1, 4 * mm),
            p("Fuentes internas revisadas", "H2Z"),
            p("Implementacion Flutter de Asistencia/Tareo/Form Runner; migraciones del ciclo de planilla, motor legal peruano, aprobaciones de RR.HH., control de movilidad, compensacion y refrigerio; y docs/GUIA_PLANILLA_ZUMAC.md.", "SmallZ"),
        ]
    )
    return story


def main() -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    doc = SimpleDocTemplate(
        str(OUTPUT),
        pagesize=A4,
        rightMargin=20 * mm,
        leftMargin=20 * mm,
        topMargin=23 * mm,
        bottomMargin=20 * mm,
        title="Flujo de asistencia, tareo, permisos, sanciones y planilla",
        author="Zumac",
        subject="Guia operativa y detalle de costos por trabajador",
    )
    doc.build(build_story(), onFirstPage=header_footer, onLaterPages=header_footer)
    print(OUTPUT)


if __name__ == "__main__":
    main()
