-- Allow current signed release packages to be published through the internal
-- updater. Keep the change scoped to the existing application updates bucket.
update storage.buckets
set file_size_limit = 157286400
where id = 'actualizaciones-appgt'
  and coalesce(file_size_limit, 0) < 157286400;
