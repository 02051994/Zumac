import 'package:flutter/material.dart';

class OnboardingPage extends StatefulWidget {
  final bool replay;

  const OnboardingPage({super.key, this.replay = false});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final controller = PageController();
  int page = 0;

  static const pages = <_OnboardingStep>[
    _OnboardingStep(
      icon: Icons.hub_outlined,
      eyebrow: 'ORDEN, TRAZABILIDAD Y CONEXIÓN',
      title: 'Toda su operación, conectada y trazable',
      description:
          'Zumac organiza la información de campo, supervisión y gestión para responder con agilidad. Además, puede integrarse con otros sistemas mediante APIs y alimentar reportes automáticos.',
      color: Color(0xFF31552F),
      features: [
        'Orden y trazabilidad desde el campo hasta la gestión',
        'Respuesta ágil con información centralizada',
        'Preparado para APIs, integraciones y reportes en Power BI',
      ],
    ),
    _OnboardingStep(
      icon: Icons.signal_wifi_off_outlined,
      eyebrow: 'TRABAJO EN CAMPO',
      title: 'Capture datos incluso sin señal',
      description:
          'El equipo puede seguir registrando su trabajo cuando la cobertura es limitada y enviar la información cuando regresa la conexión.',
      color: Color(0xFF0D5F78),
      features: [
        'La jornada no se detiene por falta de internet',
        'Los pendientes quedan claramente identificados',
        'La sincronización se realiza al recuperar la señal',
      ],
    ),
    _OnboardingStep(
      icon: Icons.dashboard_customize_outlined,
      eyebrow: 'SE ADAPTA A TU OPERACIÓN',
      title: '+100 Formatos listos y editables',
      description:
          'Encuentra plantillas para todas las áreas de la operación y adáptalas a la manera real en que trabaja tu empresa.',
      color: Color(0xFFFABF00),
      accentColor: Color(0xFF765900),
      features: [
        'Formatos para campo, calidad, producción, riego y más',
        'Edita el contenido de las plantillas según tu proceso',
        'Reorganiza formatos y módulos para reflejar tu operación',
      ],
    ),
    _OnboardingStep(
      icon: Icons.auto_awesome_outlined,
      eyebrow: 'CONFIGURACIÓN ÁGIL',
      title: 'Constructor de Formatos Inteligente',
      description:
          'Zumac Creator permite adaptar la estructura de la plataforma a medida que cambian tus procesos.',
      color: Color(0xFF0FA69D),
      accentColor: Color(0xFF08756E),
      features: [
        'Agrega nuevas secciones, módulos y formatos',
        'Edita y reorganiza la estructura sin perder el orden',
        'Previsualiza los cambios antes de publicarlos',
      ],
    ),
    _OnboardingStep(
      icon: Icons.verified_user_outlined,
      eyebrow: 'DATOS CONFIABLES',
      title: 'Más control y menos errores',
      description:
          'Las reglas de captura y los permisos ayudan a que cada persona registre lo correcto y acceda solo a lo que necesita.',
      color: Color(0xFF615170),
      features: [
        'Validaciones que previenen datos incompletos',
        'Permisos configurables por usuario y proceso',
        'Trazabilidad para revisar el avance de la operación',
      ],
    ),
    _OnboardingStep(
      icon: Icons.notification_important_outlined,
      eyebrow: 'ALERTAS INTELIGENTES',
      title: 'Anticípate a las inconsistencias',
      description:
          'Zumac está preparado para incorporar alertas con inteligencia artificial que comparen la información y avisen cuando algo no coincide.',
      color: Color(0xFFEA726D),
      accentColor: Color(0xFFA23F3B),
      features: [
        'Detectar tareos de personal sin asistencia registrada',
        'Señalar datos atípicos antes de que se conviertan en problemas',
        'Notificar a tiempo a los responsables del proceso',
      ],
    ),
    _OnboardingStep(
      icon: Icons.groups_2_outlined,
      eyebrow: 'MÁS USUARIOS, EL MISMO IMPULSO',
      title: 'Una integración que crece contigo',
      description:
          'Amplía el acceso de tu equipo sin convertir cada nuevo usuario en una licencia individual.',
      color: Color(0xFF0D5F78),
      features: [
        'Más de 1,000 usuarios disponibles, según la integración',
        'Precio por integración, no por cada usuario',
        'Escala equipos y áreas desde una sola plataforma',
      ],
    ),
  ];

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _next() {
    if (page == pages.length - 1) {
      Navigator.pop(context, true);
      return;
    }
    controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8F7),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(
                children: [
                  ClipRRect(
                    key: const ValueKey('onboarding-logo'),
                    borderRadius: BorderRadius.circular(9),
                    child: Image.asset(
                      'assets/images/logo_app.png',
                      width: 38,
                      height: 38,
                      cacheWidth: 152,
                      cacheHeight: 152,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      isAntiAlias: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'ZUMAC',
                      style: TextStyle(
                        color: Color(0xFF17324D),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(widget.replay ? 'Cerrar' : 'Omitir'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: controller,
                itemCount: pages.length,
                onPageChanged: (value) => setState(() => page = value),
                itemBuilder: (context, index) => _StepView(
                  step: pages[index],
                  compact: compact,
                  number: index + 1,
                  total: pages.length,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 20 : 44,
                8,
                compact ? 20 : 44,
                22,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 7,
                      children: List.generate(
                        pages.length,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          width: index == page ? 28 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: index == page
                                ? const Color(0xFF0D5F78)
                                : const Color(0xFFC8D8DC),
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (page > 0)
                    TextButton(
                      onPressed: () => controller.previousPage(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                      ),
                      child: const Text('Atrás'),
                    ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _next,
                    icon: Icon(page == pages.length - 1
                        ? Icons.check
                        : Icons.arrow_forward),
                    label: Text(
                        page == pages.length - 1 ? 'Comenzar' : 'Siguiente'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepView extends StatelessWidget {
  final _OnboardingStep step;
  final bool compact;
  final int number;
  final int total;

  const _StepView({
    required this.step,
    required this.compact,
    required this.number,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = step.accentColor ?? step.color;
    final illustration = Container(
      key: ValueKey('onboarding-illustration-$number'),
      constraints: BoxConstraints(maxWidth: compact ? 286 : 420),
      padding: EdgeInsets.all(compact ? 20 : 30),
      decoration: BoxDecoration(
        color: step.color,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: step.color.withValues(alpha: 0.22),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: AspectRatio(
        aspectRatio: compact ? 1.95 : 1.45,
        child: Stack(
          children: [
            Positioned(
              right: -20,
              top: -24,
              child: Icon(
                Icons.blur_on,
                size: compact ? 150 : 210,
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: Container(
                width: compact ? 88 : 130,
                height: compact ? 88 : 130,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.30),
                    width: 2,
                  ),
                ),
                child: Icon(
                  step.icon,
                  size: compact ? 48 : 70,
                  color: Colors.white,
                ),
              ),
            ),
            Positioned(
              left: 0,
              bottom: 0,
              child: Text(
                '$number/$total',
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final copy = Column(
      crossAxisAlignment:
          compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          step.eyebrow,
          textAlign: compact ? TextAlign.center : TextAlign.left,
          style: TextStyle(
            color: accentColor,
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          step.title,
          textAlign: compact ? TextAlign.center : TextAlign.left,
          style: const TextStyle(
            color: Color(0xFF17324D),
            fontSize: 29,
            height: 1.08,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          step.description,
          textAlign: compact ? TextAlign.center : TextAlign.left,
          style: const TextStyle(
            color: Color(0xFF536B7D),
            fontSize: 15,
            height: 1.42,
          ),
        ),
        const SizedBox(height: 18),
        for (final feature in step.features)
          Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle, color: accentColor, size: 21),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    feature,
                    style: const TextStyle(
                      color: Color(0xFF315064),
                      fontSize: 16,
                      height: 1.30,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 24 : 56,
        vertical: compact ? 18 : 34,
      ),
      child: compact
          ? Column(
              children: [
                illustration,
                const SizedBox(height: 22),
                copy,
              ],
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 500),
              child: Row(
                children: [
                  Expanded(child: illustration),
                  const SizedBox(width: 54),
                  Expanded(child: copy),
                ],
              ),
            ),
    );
  }
}

class _OnboardingStep {
  final IconData icon;
  final String eyebrow;
  final String title;
  final String description;
  final Color color;
  final Color? accentColor;
  final List<String> features;

  const _OnboardingStep({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.color,
    this.accentColor,
    required this.features,
  });
}
