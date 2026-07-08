-- =====================================================================
-- 011 - Listas externas: tipo 'externa' + external_url
-- (carritos de Mercado Libre, SheIn, etc.)
-- Aplicada: 2026-07-08 en mseiqleparjnchmgnwwa
-- =====================================================================

do $$
declare c text;
begin
  select conname into c
  from pg_constraint
  where conrelid = 'fam_list'::regclass
    and pg_get_constraintdef(oid) ilike '%list_type%';
  if c is not null then
    execute format('alter table fam_list drop constraint %I', c);
  end if;
end $$;

alter table fam_list
  add constraint fam_list_list_type_check
  check (list_type in ('compras', 'tareas', 'pendientes', 'otra', 'externa'));

alter table fam_list
  add column if not exists external_url text;

comment on column fam_list.external_url is 'URL del carrito externo (Mercado Libre, SheIn, etc.) cuando list_type = externa.';

insert into sys_choice (dictionary_id, value, label, display_order, is_default)
select d.id, 'externa', 'Externa', 5, false
from sys_dictionary d
join sys_db_object dbo on dbo.id = d.db_object_id and dbo.name = 'fam_list'
where d.column_name = 'list_type'
  and not exists (
    select 1 from sys_choice sc
    where sc.dictionary_id = d.id and sc.value = 'externa' and sc.company_id is null
  );

insert into sys_dictionary
  (db_object_id, column_name, label, field_type, is_mandatory, is_visible_in_list, is_visible_in_form, display_order, help_text)
select dbo.id, 'external_url', 'URL externa', 'url', false, false, true, 8, 'Carrito de tienda externa'
from sys_db_object dbo
where dbo.name = 'fam_list'
  and not exists (
    select 1 from sys_dictionary d
    where d.db_object_id = dbo.id and d.column_name = 'external_url'
  );
