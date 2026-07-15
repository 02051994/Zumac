-- Columnas opcionales para ampliar el motor de reportes/gráficos dinámicos.
-- Ejecutar en Supabase solo si quieres parametrizar más comportamiento desde SQL.

alter table if exists public."MATRIZ_GRAFICOS_DINAMICOS"
  add column if not exists subtipo_grafico text,
  add column if not exists orientacion text,
  add column if not exists apilado boolean default false,
  add column if not exists porcentaje boolean default false,
  add column if not exists suavizado boolean default false,
  add column if not exists mostrar_puntos boolean default true,
  add column if not exists mostrar_valores boolean default false,
  add column if not exists mostrar_ejes boolean default true,
  add column if not exists mostrar_grilla boolean default true,
  add column if not exists formato_numero text,
  add column if not exists formato_fecha text,
  add column if not exists color_serie_1 text,
  add column if not exists color_serie_2 text,
  add column if not exists color_serie_3 text,
  add column if not exists eje_y_min numeric,
  add column if not exists eje_y_max numeric,
  add column if not exists eje_y_intervalo numeric,
  add column if not exists alto_grafico integer default 280,
  add column if not exists ancho_minimo integer,
  add column if not exists orden_x text,
  add column if not exists limite_categorias integer,
  add column if not exists agrupacion_fecha text,
  add column if not exists configuracion_json jsonb default '{}'::jsonb;

comment on column public."MATRIZ_GRAFICOS_DINAMICOS".tipo_grafico is
'Tipos soportados por el motor Flutter: linea, area, barra, barra_horizontal, columna, dispersion/scatter, circular/pie/pastel, dona/donut, indicador/kpi/tarjeta, tabla, step/escalon, lollipop. Otros tipos avanzados pueden mapearse mediante configuracion_json.';

alter table if exists public."MATRIZ_FILTROS_DINAMICOS"
  add column if not exists placeholder text,
  add column if not exists ayuda text,
  add column if not exists multiple boolean default false,
  add column if not exists visible boolean default true,
  add column if not exists ancho integer,
  add column if not exists valor_min numeric,
  add column if not exists valor_max numeric,
  add column if not exists fecha_min date,
  add column if not exists fecha_max date,
  add column if not exists depende_de text,
  add column if not exists campo_etiqueta text,
  add column if not exists campo_valor text,
  add column if not exists orden_valores text,
  add column if not exists configuracion_json jsonb default '{}'::jsonb;

comment on column public."MATRIZ_FILTROS_DINAMICOS".disenio is
'Diseños sugeridos: text, number, fecha/date, rango_fecha, dropdown/lista_desplegable, multi_dropdown, checkbox, switch, slider, buscador.';
