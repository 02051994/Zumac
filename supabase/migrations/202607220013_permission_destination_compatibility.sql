-- Compatibilidad entre la matriz histórica de permisos y los formatos
-- publicados desde Zumac Creator. La RPC v3 conserva el identificador
-- canónico en `formato` y la tabla física principal en `tabla_destino`.

alter table public."PERMISOS_DE_USUARIOS_APPGT"
  add column if not exists tabla_destino text;

update public."PERMISOS_DE_USUARIOS_APPGT" p
set tabla_destino = coalesce(
  (
    select ft.tabla_destino
    from public."MATRIZ_FORMATO_TABLAS_APPGT" ft
    where ft.empresa_id = p.empresa_id
      and ft.formato_id = p.formato
      and coalesce(ft.activo, true)
      and ft.deleted_at is null
    order by ft.orden, ft.id
    limit 1
  ),
  (
    select f.tabla_destino
    from public."MATRIZ_FORMATOS_APPGT" f
    where f.empresa_id = p.empresa_id
      and (f.id = p.formato or f.tabla_destino = p.formato)
    order by case when f.id = p.formato then 0 else 1 end, f.orden, f.id
    limit 1
  ),
  p.formato
)
where nullif(btrim(p.tabla_destino), '') is null;

create index if not exists idx_permisos_usuario_tabla_destino
  on public."PERMISOS_DE_USUARIOS_APPGT" (empresa_id, user_id, tabla_destino);

comment on column public."PERMISOS_DE_USUARIOS_APPGT".tabla_destino is
  'Tabla física principal del formato. `formato` conserva el id canónico publicado.';

notify pgrst, 'reload schema';
