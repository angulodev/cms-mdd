-- =====================================================================
-- 008 - fam_item.assigned_to (quién debe comprarlo/hacerlo) y
--       fam_list.custom_type (etiqueta libre cuando el tipo es 'otra')
-- Aplicada: 2026-07-07 en mseiqleparjnchmgnwwa
-- =====================================================================

alter table fam_item
  add column if not exists assigned_to uuid references sys_user(id);

alter table fam_list
  add column if not exists custom_type text;

comment on column fam_item.assigned_to is 'Miembro responsable de comprar/hacer el ítem (opcional).';
comment on column fam_list.custom_type is 'Etiqueta libre del tipo cuando list_type = otra (ej: Regalos, Mascotas).';

insert into sys_dictionary
  (db_object_id, column_name, label, field_type, is_mandatory, is_visible_in_list, is_visible_in_form, display_order, help_text)
select dbo.id, f.column_name, f.label, f.field_type, false, f.in_list, true, f.ord, f.help_text
from sys_db_object dbo
join (values
  ('fam_item', 'assigned_to', 'Asignado a', 'reference', true, 10, 'Responsable del ítem'),
  ('fam_list', 'custom_type', 'Tipo personalizado', 'string', false, 7, 'Etiqueta libre cuando el tipo es otra')
) as f(table_name, column_name, label, field_type, in_list, ord, help_text)
  on dbo.name = f.table_name
where not exists (
  select 1 from sys_dictionary d
  where d.db_object_id = dbo.id and d.column_name = f.column_name
);

update sys_dictionary d
set reference_table_id = (select id from sys_db_object where name = 'sys_user')
where d.column_name = 'assigned_to'
  and d.db_object_id = (select id from sys_db_object where name = 'fam_item')
  and d.reference_table_id is null;
