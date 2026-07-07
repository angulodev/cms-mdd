-- =====================================================================
-- 006 - fam_item: precio, foto y link + bucket de Storage para fotos
-- Aplicada: 2026-07-07 en mseiqleparjnchmgnwwa (con fix idempotente
-- posterior por aplicación parcial del tool: columna link + su MDD)
-- =====================================================================

alter table fam_item
  add column if not exists price numeric(12,2) check (price is null or price >= 0),
  add column if not exists photo_url text,
  add column if not exists link text;

comment on column fam_item.price is 'Precio en CLP (o moneda local). Alimenta el gasto del mes en la PWA.';
comment on column fam_item.photo_url is 'URL pública en el bucket fam-photos.';

-- Bucket público para fotos de ítems (rutas: {list_id}/{uuid}.jpg)
insert into storage.buckets (id, name, public)
values ('fam-photos', 'fam-photos', true)
on conflict (id) do nothing;

-- Políticas: lectura pública; escritura/borrado solo miembros de la lista
-- (el primer segmento de la ruta es el list_id)
do $$ begin
  create policy fam_photos_read on storage.objects
    for select using (bucket_id = 'fam-photos');
exception when duplicate_object then null; end $$;

do $$ begin
  create policy fam_photos_insert on storage.objects
    for insert to authenticated
    with check (
      bucket_id = 'fam-photos'
      and fn_fam_is_member(((storage.foldername(name))[1])::uuid)
    );
exception when duplicate_object then null; end $$;

do $$ begin
  create policy fam_photos_delete on storage.objects
    for delete to authenticated
    using (
      bucket_id = 'fam-photos'
      and fn_fam_is_member(((storage.foldername(name))[1])::uuid)
    );
exception when duplicate_object then null; end $$;

-- Registro MDD de los campos nuevos
insert into sys_dictionary
  (db_object_id, column_name, label, field_type, is_mandatory, is_visible_in_list, is_visible_in_form, display_order, help_text)
select dbo.id, f.column_name, f.label, f.field_type, false, f.in_list, true, f.ord, f.help_text
from sys_db_object dbo
join (values
  ('fam_item', 'price',     'Precio', 'decimal', true,  7, 'Precio en moneda local'),
  ('fam_item', 'photo_url', 'Foto',   'url',     false, 8, 'Foto del producto'),
  ('fam_item', 'link',      'Link',   'url',     false, 9, 'Enlace al producto')
) as f(table_name, column_name, label, field_type, in_list, ord, help_text)
  on dbo.name = f.table_name
where not exists (
  select 1 from sys_dictionary d
  where d.db_object_id = dbo.id and d.column_name = f.column_name
);
