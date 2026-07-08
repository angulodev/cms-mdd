-- =====================================================================
-- 010 - a) La app solo muestra listas donde eres miembro o creador
--          (el platform admin ya no ve todo desde la app)
--       b) fam_item.not_found: artículo no encontrado, sigue pendiente
-- Aplicada: 2026-07-07 en mseiqleparjnchmgnwwa
-- Nota: también persiste el fix 009 (created_by = auth.uid() en select,
-- por el RETURNING previo al trigger de owner) que se aplicó en caliente.
-- =====================================================================

drop policy if exists fam_list_select on fam_list;
create policy fam_list_select on fam_list
  for select using (
    fn_fam_is_member_any(id)
    or created_by = auth.uid()
  );

alter table fam_item
  add column if not exists not_found boolean not null default false;

comment on column fam_item.not_found is 'true = se buscó pero no se encontró en la tienda; el ítem sigue pendiente (is_done=false).';

insert into sys_dictionary
  (db_object_id, column_name, label, field_type, is_mandatory, is_visible_in_list, is_visible_in_form, display_order, help_text)
select dbo.id, 'not_found', 'No encontrado', 'boolean', false, true, true, 11, 'Se buscó pero no estaba disponible'
from sys_db_object dbo
where dbo.name = 'fam_item'
  and not exists (
    select 1 from sys_dictionary d
    where d.db_object_id = dbo.id and d.column_name = 'not_found'
  );
