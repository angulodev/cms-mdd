-- =====================================================================
-- 006 - fam_item: precio, foto y link + bucket de Storage para fotos
-- Aplicada: 2026-07-07 en mseiqleparjnchmgnwwa
-- =====================================================================

alter table fam_item
  add column price numeric(12,2),
  add column photo_url text,
  add column link_url text;

comment on column fam_item.price is 'Precio en CLP (se registra normalmente al marcar como comprado).';

insert into storage.buckets (id, name, public)
values ('fam-photos', 'fam-photos', true)
on conflict (id) do nothing;

create policy fam_photos_read on storage.objects
  for select using (bucket_id = 'fam-photos');

create policy fam_photos_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'fam-photos');

create policy fam_photos_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'fam-photos' and owner = auth.uid());

insert into sys_dictionary
  (db_object_id, column_name, label, field_type, is_mandatory, is_visible_in_list, is_visible_in_form, display_order, help_text)
select dbo.id, f.column_name, f.label, f.field_type, false, f.in_list, f.in_form, f.ord, f.help_text
from sys_db_object dbo
join (values
  ('fam_item', 'price',     'Precio',  'decimal', true,  true, 7, 'Precio en CLP'),
  ('fam_item', 'photo_url', 'Foto',    'url',     false, true, 8, 'Foto del producto (Storage fam-photos)'),
  ('fam_item', 'link_url',  'Link',    'url',     false, true, 9, 'Enlace de referencia del producto')
) as f(table_name, column_name, label, field_type, in_list, in_form, ord, help_text)
  on dbo.name = f.table_name
where not exists (
  select 1 from sys_dictionary d
  where d.db_object_id = dbo.id and d.column_name = f.column_name
);
