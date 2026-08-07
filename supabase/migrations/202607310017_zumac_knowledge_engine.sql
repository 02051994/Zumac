begin;

-- Fuentes configurables: el motor nunca depende de una lista codificada.
create table if not exists public."FUENTES_CONOCIMIENTO_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  codigo text not null,
  nombre text not null,
  tipo text not null default 'DOCUMENTO'
    check (tipo in ('MATRIZ_FORMATOS', 'TABLA', 'DOCUMENTO', 'API', 'PIPELINE')),
  prioridad integer not null default 100 check (prioridad >= 0),
  activa boolean not null default true,
  permite_exacta boolean not null default true,
  permite_difusa boolean not null default true,
  permite_semantica boolean not null default false,
  umbral_suficiencia numeric(5,4) not null default 0.42
    check (umbral_suficiencia between 0 and 1),
  configuracion jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (empresa_id, codigo)
);

create table if not exists public."BASE_CONOCIMIENTO_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  fuente_id uuid not null references public."FUENTES_CONOCIMIENTO_APPGT"(id),
  fuente_codigo text not null,
  registro_origen_id text not null,
  entidad_tipo text not null
    check (entidad_tipo in ('FORMATO', 'MODULO', 'SECCION', 'CONCEPTO', 'DOCUMENTO')),
  titulo text not null,
  contenido_estructurado jsonb not null default '{}'::jsonb,
  contenido_busqueda text not null default '',
  estado text not null default 'GENERADA_IA'
    check (estado in ('GENERADA_IA', 'APROBADA', 'RECHAZADA', 'ARCHIVADA')),
  es_sugerencia_ia boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  embedding jsonb,
  version integer not null default 1 check (version > 0),
  revisado_por uuid references auth.users(id),
  revisado_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (empresa_id, fuente_codigo, entidad_tipo, registro_origen_id)
);

create table if not exists public."RELACIONES_CONOCIMIENTO_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  documento_origen_id uuid not null
    references public."BASE_CONOCIMIENTO_APPGT"(id) on delete cascade,
  documento_destino_id uuid
    references public."BASE_CONOCIMIENTO_APPGT"(id) on delete cascade,
  concepto_destino text not null,
  tipo_relacion text not null default 'RELACIONADO_CON',
  peso numeric(5,4) not null default 0.70 check (peso between 0 and 1),
  estado text not null default 'GENERADA_IA'
    check (estado in ('GENERADA_IA', 'APROBADA', 'RECHAZADA')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (documento_origen_id, concepto_destino, tipo_relacion)
);

create table if not exists public."CONVERSACIONES_CONSULTOR_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  cliente_conversacion_id text not null,
  resumen_contexto text,
  conceptos_activos jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (empresa_id, user_id, cliente_conversacion_id)
);

create table if not exists public."MENSAJES_CONSULTOR_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  conversacion_id uuid not null
    references public."CONVERSACIONES_CONSULTOR_APPGT"(id) on delete cascade,
  rol text not null check (rol in ('USUARIO', 'ASISTENTE')),
  contenido text not null,
  citas jsonb not null default '[]'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Contrato del pipeline futuro para PDF, Word, Excel y otros archivos.
create table if not exists public."TRABAJOS_INDEXACION_CONOCIMIENTO_APPGT" (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public."EMPRESAS_APPGT"(id) on delete cascade,
  fuente_id uuid not null references public."FUENTES_CONOCIMIENTO_APPGT"(id),
  archivo_nombre text not null,
  archivo_uri text not null,
  mime_type text,
  checksum text,
  estado text not null default 'PENDIENTE'
    check (estado in ('PENDIENTE', 'ANALIZANDO', 'SEGMENTANDO', 'INDEXANDO', 'COMPLETADO', 'ERROR')),
  extractor text,
  total_segmentos integer not null default 0,
  segmentos_indexados integer not null default 0,
  error_mensaje text,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_fuentes_conocimiento_prioridad
  on public."FUENTES_CONOCIMIENTO_APPGT" (empresa_id, activa, prioridad);
create index if not exists idx_base_conocimiento_fuente_estado
  on public."BASE_CONOCIMIENTO_APPGT"
  (empresa_id, fuente_codigo, estado, entidad_tipo);
create index if not exists idx_relaciones_conocimiento_origen
  on public."RELACIONES_CONOCIMIENTO_APPGT" (empresa_id, documento_origen_id);
create index if not exists idx_mensajes_consultor_conversacion
  on public."MENSAJES_CONSULTOR_APPGT" (conversacion_id, created_at);
create index if not exists idx_trabajos_indexacion_estado
  on public."TRABAJOS_INDEXACION_CONOCIMIENTO_APPGT"
  (empresa_id, estado, created_at);

do $$
begin
  begin
    create extension if not exists pg_trgm with schema extensions;
  exception when others then
    raise notice 'pg_trgm no disponible; la búsqueda difusa continuará en el cliente';
  end;
end
$$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_trgm') then
    execute 'create index if not exists idx_base_conocimiento_busqueda_trgm '
      || 'on public."BASE_CONOCIMIENTO_APPGT" using gin '
      || '(contenido_busqueda extensions.gin_trgm_ops)';
  end if;
end
$$;

create index if not exists idx_base_conocimiento_busqueda_fts
  on public."BASE_CONOCIMIENTO_APPGT" using gin
  (to_tsvector('spanish', contenido_busqueda));

create or replace function public.appgt_preparar_documento_conocimiento()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.contenido_busqueda := concat_ws(
    ' ', new.titulo, new.entidad_tipo, new.fuente_codigo,
    new.contenido_estructurado::text,
    coalesce(new.metadata ->> 'modulo', ''),
    coalesce(new.metadata ->> 'seccion', ''),
    coalesce(new.metadata ->> 'tabla_destino', '')
  );
  new.updated_at := now();
  return new;
end
$$;

drop trigger if exists appgt_preparar_documento_conocimiento_trigger
  on public."BASE_CONOCIMIENTO_APPGT";
create trigger appgt_preparar_documento_conocimiento_trigger
before insert or update of titulo, contenido_estructurado, metadata
on public."BASE_CONOCIMIENTO_APPGT"
for each row execute function public.appgt_preparar_documento_conocimiento();

create or replace function public.appgt_perfil_tecnico_agro_v1(p_texto text)
returns jsonb
language plpgsql
immutable
set search_path = public, pg_temp
as $$
declare
  v text := upper(translate(coalesce(p_texto, ''),
    'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNAEIOUUN'));
begin
  if v ~ 'DRENA|RIEGO|FERTIRR|LAVADO.*SAL|CALIDAD.*AGUA' then
    return jsonb_build_object(
      'familia', 'Riego y nutrición',
      'objetivo', 'Controlar la entrega, distribución y salida de agua y nutrientes para sostener uniformidad, disponibilidad radicular y balance de sales.',
      'usuarios', 'Jefe de riego, fertirrigador, supervisor de campo, agrónomo y responsable de calidad.',
      'momento', 'Durante la programación, ejecución y verificación de cada turno de riego, y ante desviaciones de humedad, pH, CE o drenaje.',
      'frecuencia', 'Por turno o evento de riego; consolidación diaria y análisis semanal por sector o variedad.',
      'ejemplo', 'Comparar volumen aplicado y drenado por sector, junto con pH y CE de entrada y drenaje, para decidir duración del siguiente pulso o un lavado de sales.',
      'errores', jsonb_build_array('Registrar sin identificar sector, variedad o turno', 'Mezclar unidades de volumen o conductividad', 'Tomar muestras no representativas', 'Analizar un valor aislado sin tendencia'),
      'practicas', jsonb_build_array('Usar equipos calibrados', 'Mantener unidades y puntos de muestreo consistentes', 'Relacionar aplicación, drenaje, pH y CE', 'Revisar tendencias por sector y variedad'),
      'indicadores', jsonb_build_array('Porcentaje de drenaje', 'Uniformidad de riego', 'pH', 'Conductividad eléctrica', 'Volumen aplicado', 'Acumulación de sales'),
      'riesgos', jsonb_build_array('Estrés hídrico', 'Asfixia radicular', 'Salinidad', 'Pérdida de fertilizante', 'Desuniformidad productiva', 'Menor calidad de fruta'),
      'relaciones', jsonb_build_array('Riego', 'Fertirriego', 'pH', 'CE', 'Drenaje', 'Lavado de sales', 'Calidad del agua', 'Variedades', 'Sectores', 'Macetas')
    );
  elsif v ~ 'PH|CONDUCTIV|(^|[^A-Z])CE([^A-Z]|$)|NUTRI|FERTILI' then
    return jsonb_build_object(
      'familia', 'Nutrición y solución de riego',
      'objetivo', 'Verificar que la solución nutritiva se mantenga dentro de los criterios agronómicos definidos para cultivo, etapa y sistema productivo.',
      'usuarios', 'Responsable de fertirriego, agrónomo, supervisor de campo y laboratorio o calidad.',
      'momento', 'Antes, durante y después del riego, especialmente al preparar soluciones o investigar desviaciones.',
      'frecuencia', 'Por preparación y por turno; análisis de tendencia diario o semanal.',
      'ejemplo', 'Contrastar pH y CE de la solución de entrada con el drenaje para ajustar inyección, acidificación o lavado.',
      'errores', jsonb_build_array('Equipo sin calibrar', 'Muestra contaminada', 'Unidad no indicada', 'No registrar temperatura ni punto de muestreo'),
      'practicas', jsonb_build_array('Calibrar con patrones vigentes', 'Enjuagar el sensor entre muestras', 'Registrar hora y sector', 'Evaluar tendencia y no solo límites'),
      'indicadores', jsonb_build_array('pH', 'CE', 'Diferencial entrada-drenaje', 'Consumo de fertilizante', 'Estabilidad de la solución'),
      'riesgos', jsonb_build_array('Bloqueo de nutrientes', 'Toxicidad', 'Salinidad', 'Precipitados', 'Menor rendimiento'),
      'relaciones', jsonb_build_array('Fertirriego', 'pH', 'CE', 'Drenaje', 'Calidad del agua', 'Programa de riego')
    );
  elsif v ~ 'PLAGA|ENFERMED|FITOSAN|APLICACION|MONITOREO' then
    return jsonb_build_object(
      'familia', 'Manejo fitosanitario',
      'objetivo', 'Detectar, cuantificar y gestionar oportunamente plagas, enfermedades y medidas de control con trazabilidad.',
      'usuarios', 'Evaluador fitosanitario, agrónomo, jefe de sanidad, aplicador y responsable de calidad.',
      'momento', 'En monitoreos programados, antes y después de una aplicación, y ante síntomas o alertas.',
      'frecuencia', 'Según el plan de monitoreo y nivel de riesgo; normalmente diaria o semanal por lote.',
      'ejemplo', 'Registrar incidencia de una plaga por lote y variedad, relacionarla con fenología y verificar el producto autorizado y disponible.',
      'errores', jsonb_build_array('Confundir daño con agente causal', 'No georreferenciar el foco', 'Omitir unidad de evaluación', 'No registrar condición climática'),
      'practicas', jsonb_build_array('Usar metodología de muestreo definida', 'Adjuntar evidencia', 'Confirmar diagnóstico', 'Vincular monitoreo, decisión y aplicación'),
      'indicadores', jsonb_build_array('Incidencia', 'Severidad', 'Individuos por unidad', 'Área afectada', 'Eficacia de control'),
      'riesgos', jsonb_build_array('Pérdida de producción', 'Residuos no conformes', 'Resistencia', 'Rechazo de mercado', 'Diseminación'),
      'relaciones', jsonb_build_array('Plagas', 'Enfermedades', 'Lotes', 'Variedades', 'Fenología', 'Aplicaciones', 'Productos fitosanitarios', 'Clima')
    );
  elsif v ~ 'COSECHA|RECEPCION|CALIDAD|PACKING|EMPAQUE|FRUTA|BATCH|LOTE' then
    return jsonb_build_object(
      'familia', 'Cosecha, calidad y trazabilidad',
      'objetivo', 'Asegurar identificación, condición, calidad y trazabilidad del producto desde campo hasta despacho.',
      'usuarios', 'Supervisor de cosecha, control de calidad, recepción, packing, trazabilidad y operaciones.',
      'momento', 'En cosecha, recepción, inspección, proceso, liberación y despacho.',
      'frecuencia', 'Por lote, turno, recepción o inspección, con consolidación diaria.',
      'ejemplo', 'Relacionar lote de campo, variedad, fecha de cosecha, condición de recepción y resultado de calidad.',
      'errores', jsonb_build_array('Lote incompleto o duplicado', 'Muestra no representativa', 'Criterios de calidad ambiguos', 'Pérdida de vínculo entre campo y packing'),
      'practicas', jsonb_build_array('Usar identificadores únicos', 'Aplicar planes de muestreo', 'Registrar unidad y tolerancia', 'Mantener cadena de custodia'),
      'indicadores', jsonb_build_array('Rendimiento', 'Descarte', 'Defectos', 'Condición', 'Productividad', 'Trazabilidad completa'),
      'riesgos', jsonb_build_array('Mezcla de lotes', 'Reclamos', 'Rechazo de exportación', 'Retiro de producto', 'Pérdida de evidencia'),
      'relaciones', jsonb_build_array('Lotes', 'Variedades', 'Cosecha', 'Calidad', 'Packing', 'Trazabilidad', 'Despacho')
    );
  elsif v ~ 'ASISTEN|TAREO|PERSONAL|SEGURIDAD|CAPACIT' then
    return jsonb_build_object(
      'familia', 'Personas y seguridad',
      'objetivo', 'Mantener evidencia confiable de presencia, labor, competencia y condiciones seguras de trabajo.',
      'usuarios', 'Supervisor, recursos humanos, seguridad y salud, jefe de área y administración.',
      'momento', 'Al inicio y cierre de jornada, durante la asignación de labores y ante eventos o capacitaciones.',
      'frecuencia', 'Diaria por persona y por evento cuando corresponda.',
      'ejemplo', 'Cruzar asistencia con tareo y labor asignada para detectar personas sin registro o diferencias de jornada.',
      'errores', jsonb_build_array('Duplicar personas', 'Registrar horas incompletas', 'No identificar labor o cuadrilla', 'Corregir sin trazabilidad'),
      'practicas', jsonb_build_array('Validar identidad', 'Registrar en el momento', 'Conciliar asistencia y tareo', 'Conservar historial de cambios'),
      'indicadores', jsonb_build_array('Asistencia', 'Horas trabajadas', 'Productividad', 'Ausentismo', 'Cumplimiento de capacitación'),
      'riesgos', jsonb_build_array('Pago incorrecto', 'Falta de trazabilidad laboral', 'Incumplimiento legal', 'Datos de productividad erróneos'),
      'relaciones', jsonb_build_array('Asistencia', 'Tareo', 'Labores', 'Cuadrillas', 'Capacitación', 'Seguridad')
    );
  else
    return jsonb_build_object(
      'familia', 'Gestión agroexportadora',
      'objetivo', 'Estandarizar la captura de información operativa y conservar evidencia trazable para control, análisis y toma de decisiones.',
      'usuarios', 'Responsable del proceso, supervisor, jefatura del área y personal de calidad o administración.',
      'momento', 'Cuando ocurre la actividad o control que el formato representa y durante su revisión posterior.',
      'frecuencia', 'Según el procedimiento de la empresa; registrar cada evento y consolidar con la periodicidad del proceso.',
      'ejemplo', 'Registrar fecha, responsable, ubicación y valores del control; luego comparar el resultado con el plan y otros registros relacionados.',
      'errores', jsonb_build_array('Registrar tarde', 'Dejar campos clave vacíos', 'Usar nombres o unidades inconsistentes', 'Duplicar el evento'),
      'practicas', jsonb_build_array('Registrar en el punto de origen', 'Usar catálogos y unidades estándar', 'Validar antes de cerrar', 'Revisar tendencias y excepciones'),
      'indicadores', jsonb_build_array('Cumplimiento de registros', 'Oportunidad del dato', 'Completitud', 'Desviaciones', 'Acciones cerradas'),
      'riesgos', jsonb_build_array('Decisiones sin evidencia', 'Pérdida de trazabilidad', 'Incumplimiento', 'Reproceso', 'Desviaciones no detectadas'),
      'relaciones', jsonb_build_array('Planificación', 'Ejecución', 'Supervisión', 'Calidad', 'Trazabilidad', 'Acciones correctivas')
    );
  end if;
end
$$;

create or replace function public.appgt_documentacion_formato_v1(
  p_nombre text,
  p_modulo text,
  p_seccion text,
  p_tabla text,
  p_campos jsonb
)
returns jsonb
language plpgsql
immutable
set search_path = public, pg_temp
as $$
declare
  v jsonb := public.appgt_perfil_tecnico_agro_v1(
    concat_ws(' ', p_nombre, p_modulo, p_seccion, p_tabla)
  );
  v_contexto text := concat_ws(' › ', nullif(p_seccion, ''), nullif(p_modulo, ''));
begin
  return jsonb_build_object(
    'descripcion_general', concat(
      p_nombre, ' es un formato de ', lower(v ->> 'familia'),
      ' dentro de ', coalesce(nullif(v_contexto, ''), 'la operación de la empresa'),
      '. Estructura y conserva los datos necesarios para que el proceso pueda revisarse y relacionarse con otros controles.'
    ),
    'objetivo', v ->> 'objetivo',
    'para_que_sirve', concat(
      'Sirve para documentar ', lower(p_nombre),
      ', comparar lo ejecutado con lo planificado, detectar desviaciones y mantener trazabilidad para decisiones y auditorías.'
    ),
    'quien_lo_utiliza', v ->> 'usuarios',
    'cuando_se_utiliza', v ->> 'momento',
    'frecuencia_uso', v ->> 'frecuencia',
    'ejemplo_utilizacion', v ->> 'ejemplo',
    'conceptos_relacionados', v -> 'relaciones',
    'errores_comunes', v -> 'errores',
    'buenas_practicas', v -> 'practicas',
    'indicadores_relacionados', v -> 'indicadores',
    'riesgos_no_registrar', v -> 'riesgos',
    'preguntas_frecuentes', jsonb_build_array(
      jsonb_build_object('pregunta', concat('¿Para qué sirve ', p_nombre, '?'),
        'respuesta', concat('Sirve para ', lower(v ->> 'objetivo'))),
      jsonb_build_object('pregunta', concat('¿Cuándo debo completar ', p_nombre, '?'),
        'respuesta', v ->> 'momento'),
      jsonb_build_object('pregunta', concat('¿Quién revisa ', p_nombre, '?'),
        'respuesta', v ->> 'usuarios'),
      jsonb_build_object('pregunta', '¿Qué debo hacer si encuentro una desviación?',
        'respuesta', 'Confirmar el dato, registrar evidencia, informar al responsable del proceso y vincular la acción correctiva correspondiente.'),
      jsonb_build_object('pregunta', '¿Puedo corregir un registro?',
        'respuesta', 'Sí, mediante el flujo autorizado y conservando la trazabilidad del dato original, el motivo y el responsable del cambio.')
    ),
    'campos_identificados', coalesce(p_campos, '[]'::jsonb),
    'tabla_destino', p_tabla,
    'familia_tecnica', v ->> 'familia',
    'nota_revision', 'Contenido técnico general sugerido por IA. Debe ser revisado y adaptado al procedimiento, cultivo, certificación y límites internos de la empresa.'
  );
end
$$;

create or replace function public.appgt_generar_base_conocimiento_empresa_v1(
  p_empresa_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_fuente_id uuid;
  v_formatos integer := 0;
  v_modulos integer := 0;
  v_secciones integer := 0;
  v_relaciones integer := 0;
begin
  if p_empresa_id is null then
    raise exception 'empresa requerida';
  end if;
  if auth.uid() is not null
     and not public.appgt_puede_gestionar_configuracion(p_empresa_id) then
    raise exception 'sin permiso para generar conocimiento' using errcode = '42501';
  end if;

  insert into public."FUENTES_CONOCIMIENTO_APPGT" (
    empresa_id, codigo, nombre, tipo, prioridad, activa,
    permite_exacta, permite_difusa, permite_semantica, umbral_suficiencia
  ) values (
    p_empresa_id, 'MATRIZ_FORMATOS_APPGT', 'Matriz de formatos Zumac',
    'MATRIZ_FORMATOS', 10, true, true, true, false, 0.40
  ) on conflict (empresa_id, codigo) do nothing;

  insert into public."FUENTES_CONOCIMIENTO_APPGT" (
    empresa_id, codigo, nombre, tipo, prioridad, activa,
    permite_exacta, permite_difusa, permite_semantica, umbral_suficiencia,
    configuracion
  ) values (
    p_empresa_id, 'DOCUMENTOS_EMPRESA', 'Documentos y procedimientos',
    'PIPELINE', 100, true, true, true, true, 0.45,
    jsonb_build_object('formatos_soportados', jsonb_build_array(
      'application/pdf',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'text/plain'
    ))
  ) on conflict (empresa_id, codigo) do nothing;

  select id into v_fuente_id
  from public."FUENTES_CONOCIMIENTO_APPGT"
  where empresa_id = p_empresa_id and codigo = 'MATRIZ_FORMATOS_APPGT';

  with inserted as (
    insert into public."BASE_CONOCIMIENTO_APPGT" (
      empresa_id, fuente_id, fuente_codigo, registro_origen_id,
      entidad_tipo, titulo, contenido_estructurado, estado,
      es_sugerencia_ia, metadata
    )
    select
      f.empresa_id, v_fuente_id, 'MATRIZ_FORMATOS_APPGT', f.id::text,
      'FORMATO', f.nombre,
      public.appgt_documentacion_formato_v1(
        f.nombre,
        coalesce(m.nombre, ''),
        coalesce(nullif(s.nombre, ''), s.id, ''),
        coalesce(nullif(f.tabla_destino, ''), ft.tabla_destino, ''),
        coalesce((
          select jsonb_agg(jsonb_build_object(
            'campo', c.campo,
            'etiqueta', coalesce(nullif(c.etiqueta, ''), c.campo),
            'tipo', coalesce(c.tipo_ui, c.tipo, 'texto')
          ) order by coalesce(c.orden, 0), c.campo)
          from public."MATRIZ_CAMPOS_FORMATO_APPGT" c
          where c.empresa_id = f.empresa_id
            and c.tabla_destino = coalesce(nullif(f.tabla_destino, ''), ft.tabla_destino)
            and coalesce(c.activo, true)
        ), '[]'::jsonb)
      ),
      'GENERADA_IA', true,
      jsonb_build_object(
        'modulo_id', f.modulo_id,
        'modulo', coalesce(m.nombre, ''),
        'seccion', coalesce(nullif(s.nombre, ''), s.id, ''),
        'tabla_destino', coalesce(nullif(f.tabla_destino, ''), ft.tabla_destino, ''),
        'origen', 'GENERADOR_TECNICO_AGROEXPORTACION_V1'
      )
    from public."MATRIZ_FORMATOS_APPGT" f
    left join public."MATRIZ_MODULOS_APPGT" m
      on m.empresa_id = f.empresa_id and m.id = f.modulo_id
    left join lateral (
      select x.tabla_destino
      from public."MATRIZ_FORMATO_TABLAS_APPGT" x
      where x.empresa_id = f.empresa_id and x.formato_id = f.id
        and coalesce(x.activo, true) and x.deleted_at is null
      order by coalesce(x.orden, 0), x.id
      limit 1
    ) ft on true
    left join public."MATRIZ_SECCIONES_APPGT" s
      on s.empresa_id = f.empresa_id
     and s.id = m.seccion
    where f.empresa_id = p_empresa_id
      and coalesce(f.activo, true)
      and f.deleted_at is null
    on conflict (empresa_id, fuente_codigo, entidad_tipo, registro_origen_id)
      do nothing
    returning 1
  ) select count(*) into v_formatos from inserted;

  with inserted as (
    insert into public."BASE_CONOCIMIENTO_APPGT" (
      empresa_id, fuente_id, fuente_codigo, registro_origen_id,
      entidad_tipo, titulo, contenido_estructurado, metadata
    )
    select m.empresa_id, v_fuente_id, 'MATRIZ_FORMATOS_APPGT', m.id::text,
      'MODULO', m.nombre,
      jsonb_build_object(
        'descripcion_general', concat(m.nombre, ' agrupa los formatos y controles del proceso dentro de la estructura operativa de la empresa.'),
        'objetivo', concat('Organizar y conectar la información de ', lower(m.nombre), ' para facilitar captura, supervisión, análisis y trazabilidad.'),
        'formatos_relacionados', coalesce((
          select jsonb_agg(f.nombre order by coalesce(f.orden, 0), f.nombre)
          from public."MATRIZ_FORMATOS_APPGT" f
          where f.empresa_id = m.empresa_id and f.modulo_id = m.id
            and coalesce(f.activo, true) and f.deleted_at is null
        ), '[]'::jsonb),
        'buenas_practicas', jsonb_build_array('Definir responsables', 'Evitar formatos duplicados', 'Relacionar registros que comparten lote, fecha, sector o persona', 'Revisar indicadores del proceso'),
        'nota_revision', 'Contenido sugerido por IA pendiente de revisión administrativa.'
      ),
      jsonb_build_object(
        'seccion', coalesce(nullif(s.nombre, ''), s.id, ''),
        'origen', 'GENERADOR_TECNICO_AGROEXPORTACION_V1'
      )
    from public."MATRIZ_MODULOS_APPGT" m
    left join public."MATRIZ_SECCIONES_APPGT" s
      on s.empresa_id = m.empresa_id
     and s.id = m.seccion
    where m.empresa_id = p_empresa_id and coalesce(m.activo, true)
      and m.deleted_at is null
    on conflict (empresa_id, fuente_codigo, entidad_tipo, registro_origen_id)
      do nothing
    returning 1
  ) select count(*) into v_modulos from inserted;

  with inserted as (
    insert into public."BASE_CONOCIMIENTO_APPGT" (
      empresa_id, fuente_id, fuente_codigo, registro_origen_id,
      entidad_tipo, titulo, contenido_estructurado, metadata
    )
    select s.empresa_id, v_fuente_id, 'MATRIZ_FORMATOS_APPGT', s.id::text,
      'SECCION', coalesce(nullif(s.nombre, ''), s.id),
      jsonb_build_object(
        'descripcion_general', concat(coalesce(nullif(s.nombre, ''), s.id), ' es una sección de conocimiento que reúne procesos y módulos relacionados de la empresa.'),
        'objetivo', 'Facilitar navegación, comprensión del proceso y recuperación contextual de sus formatos.',
        'modulos_relacionados', coalesce((
          select jsonb_agg(m.nombre order by coalesce(m.orden, 0), m.nombre)
          from public."MATRIZ_MODULOS_APPGT" m
          where m.empresa_id = s.empresa_id
            and m.seccion = s.id
            and coalesce(m.activo, true) and m.deleted_at is null
        ), '[]'::jsonb),
        'nota_revision', 'Contenido sugerido por IA pendiente de revisión administrativa.'
      ),
      jsonb_build_object('origen', 'GENERADOR_TECNICO_AGROEXPORTACION_V1')
    from public."MATRIZ_SECCIONES_APPGT" s
    where s.empresa_id = p_empresa_id and coalesce(s.activo, true)
      and s.deleted_at is null
    on conflict (empresa_id, fuente_codigo, entidad_tipo, registro_origen_id)
      do nothing
    returning 1
  ) select count(*) into v_secciones from inserted;

  with edges as (
    select d.id as documento_id, rel.concepto
    from public."BASE_CONOCIMIENTO_APPGT" d
    cross join lateral jsonb_array_elements_text(
      coalesce(d.contenido_estructurado -> 'conceptos_relacionados', '[]'::jsonb)
    ) rel(concepto)
    where d.empresa_id = p_empresa_id and d.entidad_tipo = 'FORMATO'
  ), inserted as (
    insert into public."RELACIONES_CONOCIMIENTO_APPGT" (
      empresa_id, documento_origen_id, concepto_destino,
      tipo_relacion, peso, estado, metadata
    )
    select p_empresa_id, e.documento_id, e.concepto,
      'RELACIONADO_CON', 0.75, 'GENERADA_IA',
      jsonb_build_object('origen', 'INFERENCIA_TECNICA_V1')
    from edges e
    on conflict (documento_origen_id, concepto_destino, tipo_relacion)
      do nothing
    returning 1
  ) select count(*) into v_relaciones from inserted;

  return jsonb_build_object(
    'formatos_generados', v_formatos,
    'modulos_generados', v_modulos,
    'secciones_generadas', v_secciones,
    'relaciones_generadas', v_relaciones,
    'estado', 'GENERADA_IA'
  );
end
$$;

create or replace function public.appgt_generar_base_conocimiento_inicial_v1()
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $$
  select public.appgt_generar_base_conocimiento_empresa_v1(
    public.appgt_empresa_actual_id()
  );
$$;

create or replace function public.appgt_regenerar_conocimiento_al_cambiar_config()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.appgt_generar_base_conocimiento_empresa_v1(new.empresa_id);
  return new;
end
$$;

drop trigger if exists appgt_generar_conocimiento_formato_trigger
  on public."MATRIZ_FORMATOS_APPGT";
create trigger appgt_generar_conocimiento_formato_trigger
after insert on public."MATRIZ_FORMATOS_APPGT"
for each row execute function public.appgt_regenerar_conocimiento_al_cambiar_config();

drop trigger if exists appgt_generar_conocimiento_modulo_trigger
  on public."MATRIZ_MODULOS_APPGT";
create trigger appgt_generar_conocimiento_modulo_trigger
after insert on public."MATRIZ_MODULOS_APPGT"
for each row execute function public.appgt_regenerar_conocimiento_al_cambiar_config();

drop trigger if exists appgt_generar_conocimiento_seccion_trigger
  on public."MATRIZ_SECCIONES_APPGT";
create trigger appgt_generar_conocimiento_seccion_trigger
after insert on public."MATRIZ_SECCIONES_APPGT"
for each row execute function public.appgt_regenerar_conocimiento_al_cambiar_config();

create or replace function public.appgt_revisar_conocimiento_v1(
  p_documento_id uuid,
  p_estado text,
  p_contenido_estructurado jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_doc public."BASE_CONOCIMIENTO_APPGT";
begin
  if not public.appgt_puede_gestionar_configuracion(v_empresa_id) then
    raise exception 'sin permiso para revisar conocimiento' using errcode = '42501';
  end if;
  if p_estado not in ('APROBADA', 'RECHAZADA', 'ARCHIVADA', 'GENERADA_IA') then
    raise exception 'estado inválido';
  end if;

  update public."BASE_CONOCIMIENTO_APPGT" d
  set estado = p_estado,
      contenido_estructurado = coalesce(p_contenido_estructurado, d.contenido_estructurado),
      es_sugerencia_ia = p_estado <> 'APROBADA',
      version = d.version + 1,
      revisado_por = auth.uid(),
      revisado_at = now(),
      updated_at = now()
  where d.id = p_documento_id and d.empresa_id = v_empresa_id
  returning * into v_doc;

  if v_doc.id is null then raise exception 'documento no encontrado'; end if;
  return to_jsonb(v_doc);
end
$$;

-- Búsqueda RPC para clientes delgados. El motor Flutter vuelve a puntuar y
-- aplica memoria; esta función reduce candidatos manteniendo la prioridad.
create or replace function public.appgt_buscar_conocimiento_v1(
  p_consulta text,
  p_limite integer default 80,
  p_incluir_generada_ia boolean default true
)
returns table (
  documento jsonb,
  fuente jsonb,
  puntaje_exacto numeric,
  puntaje_difuso numeric,
  puntaje_fts numeric,
  relaciones jsonb
)
language plpgsql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_query text := btrim(coalesce(p_consulta, ''));
  v_has_trgm boolean := exists (
    select 1 from pg_extension where extname = 'pg_trgm'
  );
begin
  if v_empresa_id is null or v_query = '' then return; end if;

  return query
  select
    to_jsonb(d),
    to_jsonb(f),
    case
      when lower(d.titulo) = lower(v_query) then 1.0
      when d.contenido_busqueda ilike '%' || v_query || '%' then 0.85
      else 0.0
    end::numeric,
    case when v_has_trgm
      then extensions.similarity(d.contenido_busqueda, v_query)
      else 0.0
    end::numeric,
    ts_rank_cd(
      to_tsvector('spanish', d.contenido_busqueda),
      websearch_to_tsquery('spanish', v_query)
    )::numeric,
    coalesce((
      select jsonb_agg(to_jsonb(r) order by r.peso desc)
      from public."RELACIONES_CONOCIMIENTO_APPGT" r
      where r.documento_origen_id = d.id
        and r.estado in ('APROBADA', 'GENERADA_IA')
    ), '[]'::jsonb)
  from public."BASE_CONOCIMIENTO_APPGT" d
  join public."FUENTES_CONOCIMIENTO_APPGT" f on f.id = d.fuente_id
  where d.empresa_id = v_empresa_id
    and f.activa
    and d.estado in ('APROBADA', case when p_incluir_generada_ia then 'GENERADA_IA' else 'APROBADA' end)
    and (
      d.contenido_busqueda ilike '%' || v_query || '%'
      or to_tsvector('spanish', d.contenido_busqueda)
        @@ websearch_to_tsquery('spanish', v_query)
      or (v_has_trgm and extensions.similarity(d.contenido_busqueda, v_query) >= 0.08)
    )
  order by f.prioridad,
    greatest(
      case when lower(d.titulo) = lower(v_query) then 1.0 else 0.0 end,
      ts_rank_cd(
        to_tsvector('spanish', d.contenido_busqueda),
        websearch_to_tsquery('spanish', v_query)
      ),
      case when v_has_trgm then extensions.similarity(d.contenido_busqueda, v_query) else 0.0 end
    ) desc,
    d.updated_at desc
  limit greatest(1, least(coalesce(p_limite, 80), 300));
end
$$;

-- Memoria persistente. El cliente también mantiene una ventana inmediata para
-- responder sin bloquearse si la red no está disponible.
create or replace function public.appgt_guardar_turno_consultor_v1(
  p_cliente_conversacion_id text,
  p_pregunta text,
  p_respuesta text,
  p_citas jsonb default '[]'::jsonb,
  p_conceptos jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid := public.appgt_empresa_actual_id();
  v_conversacion_id uuid;
begin
  if auth.uid() is null or v_empresa_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  insert into public."CONVERSACIONES_CONSULTOR_APPGT" (
    empresa_id, user_id, cliente_conversacion_id, conceptos_activos, updated_at
  ) values (
    v_empresa_id, auth.uid(), p_cliente_conversacion_id,
    coalesce(p_conceptos, '[]'::jsonb), now()
  ) on conflict (empresa_id, user_id, cliente_conversacion_id) do update
    set conceptos_activos = excluded.conceptos_activos, updated_at = now()
  returning id into v_conversacion_id;

  insert into public."MENSAJES_CONSULTOR_APPGT" (
    empresa_id, conversacion_id, rol, contenido
  ) values (v_empresa_id, v_conversacion_id, 'USUARIO', p_pregunta);
  insert into public."MENSAJES_CONSULTOR_APPGT" (
    empresa_id, conversacion_id, rol, contenido, citas
  ) values (v_empresa_id, v_conversacion_id, 'ASISTENTE', p_respuesta, coalesce(p_citas, '[]'::jsonb));
  return v_conversacion_id;
end
$$;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'FUENTES_CONOCIMIENTO_APPGT',
    'BASE_CONOCIMIENTO_APPGT',
    'RELACIONES_CONOCIMIENTO_APPGT',
    'CONVERSACIONES_CONSULTOR_APPGT',
    'MENSAJES_CONSULTOR_APPGT',
    'TRABAJOS_INDEXACION_CONOCIMIENTO_APPGT'
  ] loop
    execute format('alter table public.%I enable row level security', v_table);
    execute format('drop policy if exists tenant_scope on public.%I', v_table);
    execute format(
      'create policy tenant_scope on public.%I for select to authenticated using (public.appgt_puede_acceder_empresa(empresa_id))',
      v_table
    );
  end loop;
end
$$;

-- El historial conversacional es privado por usuario, no solo por empresa.
drop policy if exists tenant_scope
  on public."CONVERSACIONES_CONSULTOR_APPGT";
drop policy if exists tenant_scope
  on public."MENSAJES_CONSULTOR_APPGT";

create policy fuentes_conocimiento_admin_write
on public."FUENTES_CONOCIMIENTO_APPGT" for all to authenticated
using (public.appgt_puede_gestionar_configuracion(empresa_id))
with check (public.appgt_puede_gestionar_configuracion(empresa_id));

create policy base_conocimiento_admin_write
on public."BASE_CONOCIMIENTO_APPGT" for all to authenticated
using (public.appgt_puede_gestionar_configuracion(empresa_id))
with check (public.appgt_puede_gestionar_configuracion(empresa_id));

create policy relaciones_conocimiento_admin_write
on public."RELACIONES_CONOCIMIENTO_APPGT" for all to authenticated
using (public.appgt_puede_gestionar_configuracion(empresa_id))
with check (public.appgt_puede_gestionar_configuracion(empresa_id));

create policy conversaciones_consultor_own_write
on public."CONVERSACIONES_CONSULTOR_APPGT" for all to authenticated
using (user_id = auth.uid() and public.appgt_puede_acceder_empresa(empresa_id))
with check (user_id = auth.uid() and public.appgt_puede_acceder_empresa(empresa_id));

create policy mensajes_consultor_own_write
on public."MENSAJES_CONSULTOR_APPGT" for all to authenticated
using (exists (
  select 1 from public."CONVERSACIONES_CONSULTOR_APPGT" c
  where c.id = conversacion_id and c.user_id = auth.uid()
))
with check (exists (
  select 1 from public."CONVERSACIONES_CONSULTOR_APPGT" c
  where c.id = conversacion_id and c.user_id = auth.uid()
));

create policy trabajos_indexacion_admin_write
on public."TRABAJOS_INDEXACION_CONOCIMIENTO_APPGT" for all to authenticated
using (public.appgt_puede_gestionar_configuracion(empresa_id))
with check (public.appgt_puede_gestionar_configuracion(empresa_id));

revoke all on function public.appgt_generar_base_conocimiento_inicial_v1()
  from public, anon;
revoke all on function public.appgt_generar_base_conocimiento_empresa_v1(uuid)
  from public, anon, authenticated;
revoke all on function public.appgt_revisar_conocimiento_v1(uuid,text,jsonb)
  from public, anon;
revoke all on function public.appgt_buscar_conocimiento_v1(text,integer,boolean)
  from public, anon;
revoke all on function public.appgt_guardar_turno_consultor_v1(text,text,text,jsonb,jsonb)
  from public, anon;
grant execute on function public.appgt_generar_base_conocimiento_inicial_v1()
  to authenticated;
grant execute on function public.appgt_revisar_conocimiento_v1(uuid,text,jsonb)
  to authenticated;
grant execute on function public.appgt_buscar_conocimiento_v1(text,integer,boolean)
  to authenticated;
grant execute on function public.appgt_guardar_turno_consultor_v1(text,text,text,jsonb,jsonb)
  to authenticated;

-- Carga inicial idempotente para todas las empresas existentes. ON CONFLICT
-- DO NOTHING garantiza que ningún contenido previo sea sobrescrito.
do $$
declare
  v_empresa record;
begin
  for v_empresa in select id from public."EMPRESAS_APPGT" loop
    perform public.appgt_generar_base_conocimiento_empresa_v1(v_empresa.id);
  end loop;
end
$$;

notify pgrst, 'reload schema';
commit;
