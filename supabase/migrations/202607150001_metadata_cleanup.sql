begin;

-- Impedir que una normalizacion de espacios fusione dos claves distintas.
do $$
begin
  if exists (
    select 1
    from public."MATRIZ_FORMATO_TABLAS_APPGT"
    group by btrim(id, E' \t\n\r')
    having count(*) > 1
  ) then
    raise exception 'No se pueden normalizar MATRIZ_FORMATO_TABLAS_APPGT: existen ids duplicados despues de trim';
  end if;
end
$$;

update public."MATRIZ_FORMATO_TABLAS_APPGT"
set
  id = btrim(id, E' \t\n\r'),
  formato_id = btrim(formato_id, E' \t\n\r'),
  tabla_destino = btrim(tabla_destino, E' \t\n\r'),
  updated_at = now()
where id is distinct from btrim(id, E' \t\n\r')
   or formato_id is distinct from btrim(formato_id, E' \t\n\r')
   or tabla_destino is distinct from btrim(tabla_destino, E' \t\n\r');

-- La definicion con prefijo perdido duplica el campo ID canonico; se despublica.
update public."MATRIZ_CAMPOS_FORMATO_APPGT"
set
  activo = false,
  eliminado = true,
  updated_at = now()
where id::text = '93381ae4-ccd0-4d64-a2d2-aa6f979455d2'
  and tabla_destino = '-REGISTRO_LIMPIEZA_TANQUES_DEPOSITOS_AGUA'
  and campo = 'ID';

-- Existe una definicion canonica activa para la misma matriz; se despublica el duplicado huerfano.
update public."MATRIZ_FORMATOS_APPGT"
set
  activo = false,
  eliminado = true,
  updated_at = now()
where id = 'matriz_estacion_de_roedores'
  and modulo_id is null
  and exists (
    select 1
    from public."MATRIZ_FORMATOS_APPGT" canonical
    where canonical.id = 'id_matrices_estacion_roedores_zumac'
      and canonical.activo is true
      and canonical.tabla_destino = 'MATRIZ_ESTACIONES_DE_ROEDORES'
  );

-- Estos dos permisos no representan ni un formato ni una tabla destino vigente.
update public."PERMISOS_DE_USUARIOS_APPGT"
set
  activo = false,
  eliminado = true,
  updated_at = now()
where (id::text, formato) in (
  ('6037c0ba-2d6a-40a5-9811-395a8ff67ecb', 'detalle_evaluacion_materia_prima'),
  ('622c5a6b-6cf1-4279-a7ab-a36913be8954', 'control_fugas')
)
and not exists (
  select 1
  from public."MATRIZ_FORMATOS_APPGT" f
  where f.activo is true
    and (f.id = "PERMISOS_DE_USUARIOS_APPGT".formato
      or f.tabla_destino = "PERMISOS_DE_USUARIOS_APPGT".formato)
)
and not exists (
  select 1
  from public."MATRIZ_FORMATO_TABLAS_APPGT" ft
  where ft.activo is true
    and ft.tabla_destino = "PERMISOS_DE_USUARIOS_APPGT".formato
);

-- Permisos de secciones retiradas de la navegacion vigente.
update public."PERMISOS_SECCIONES_APPGT" p
set
  activo = false,
  eliminado = true,
  updated_at = now()
where coalesce(nullif(btrim(p.seccion), ''), btrim(p.seccion_id)) in (
  'areas_gt',
  'centro_costos_gt',
  'inicio_gt',
  'reportes',
  'usuarios',
  'variedades_gt'
)
and not exists (
  select 1
  from public."MATRIZ_SECCIONES_APPGT" s
  where s.id = coalesce(nullif(btrim(p.seccion), ''), btrim(p.seccion_id))
    and s.activo is true
);

do $$
begin
  if exists (
    select 1
    from public."MATRIZ_FORMATO_TABLAS_APPGT"
    where id is distinct from btrim(id, E' \t\n\r')
       or formato_id is distinct from btrim(formato_id, E' \t\n\r')
       or tabla_destino is distinct from btrim(tabla_destino, E' \t\n\r')
  ) then
    raise exception 'La normalizacion de MATRIZ_FORMATO_TABLAS_APPGT no quedo completa';
  end if;

  if exists (
    select 1
    from public."MATRIZ_FORMATOS_APPGT"
    where id = 'matriz_estacion_de_roedores'
      and activo is true
  ) then
    raise exception 'El formato huerfano de estaciones de roedores continua activo';
  end if;
end
$$;

commit;
