-- Register the release packages only after their Storage uploads succeed.
insert into public.appgt_versiones (
  plataforma,
  version,
  storage_path,
  obligatorio,
  notas,
  activo
)
select
  'android',
  '0.0.14',
  'android/app-release_v0.0.14.apk',
  true,
  'Importación Excel flexible, IDs automáticos y mensajes centrados.',
  true
where not exists (
  select 1
  from public.appgt_versiones
  where plataforma = 'android'
    and version = '0.0.14'
);

insert into public.appgt_versiones (
  plataforma,
  version,
  storage_path,
  obligatorio,
  notas,
  activo
)
select
  'windows',
  '0.0.14',
  'windows/Zumac_v0.0.14.zip',
  true,
  'Importación Excel flexible, IDs automáticos y mensajes centrados.',
  true
where not exists (
  select 1
  from public.appgt_versiones
  where plataforma = 'windows'
    and version = '0.0.14'
);
