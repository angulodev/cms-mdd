-- =====================================================================
-- 007 - Aprobación de miembros: quien se une por código queda 'pending'
-- hasta que el owner lo apruebe. Aplicada: 2026-07-07
--
-- Cambios:
--   - fam_list_member.status ('pending'/'approved', default approved)
--   - fn_fam_is_member / fn_fam_has_role ahora exigen approved
--   - fn_fam_is_member_any: membresía en cualquier estado (para que el
--     solicitante vea el nombre de la lista mientras espera)
--   - fam_list_select usa fn_fam_is_member_any
--   - fam_member_select permite ver siempre la propia fila
--   - fn_fam_join_by_code inserta en pending
--   - Trigger de owner inserta approved explícito
--   - MDD: campo status + choices
-- =====================================================================

alter table fam_list_member
  add column if not exists status text not null default 'approved'
  check (status in ('pending', 'approved'));

comment on column fam_list_member.status is 'pending = solicitó unirse por código, espera aprobación del owner. approved = miembro activo.';

create or replace function fn_fam_is_member(p_list_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from fam_list_member
    where list_id = p_list_id and user_id = auth.uid() and status = 'approved'
  );
$$;

create or replace function fn_fam_has_role(p_list_id uuid, p_roles text[])
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from fam_list_member
    where list_id = p_list_id
      and user_id = auth.uid()
      and member_role = any(p_roles)
      and status = 'approved'
  );
$$;

create or replace function fn_fam_is_member_any(p_list_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from fam_list_member
    where list_id = p_list_id and user_id = auth.uid()
  );
$$;

drop policy if exists fam_list_select on fam_list;
create policy fam_list_select on fam_list
  for select using (fn_fam_is_member_any(id) or fn_is_platform_admin());

drop policy if exists fam_member_select on fam_list_member;
create policy fam_member_select on fam_list_member
  for select using (
    fn_fam_is_member(list_id)
    or user_id = auth.uid()
    or fn_is_platform_admin()
  );

create or replace function fn_fam_join_by_code(p_code text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_list_id uuid;
begin
  select id into v_list_id
  from fam_list
  where share_code = upper(trim(p_code))
    and is_archived = false;

  if v_list_id is null then
    raise exception 'Código de lista inválido o lista archivada';
  end if;

  insert into fam_list_member (list_id, user_id, member_role, status)
  values (v_list_id, auth.uid(), 'editor', 'pending')
  on conflict (list_id, user_id) do nothing;

  return v_list_id;
end;
$$;

create or replace function fn_fam_list_add_owner()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into fam_list_member (list_id, user_id, member_role, status)
  values (new.id, new.created_by, 'owner', 'approved')
  on conflict (list_id, user_id) do nothing;
  return new;
end;
$$;

insert into sys_dictionary
  (db_object_id, column_name, label, field_type, is_mandatory, is_visible_in_list, is_visible_in_form, display_order)
select dbo.id, 'status', 'Estado', 'choice', true, true, true, 3
from sys_db_object dbo
where dbo.name = 'fam_list_member'
  and not exists (
    select 1 from sys_dictionary d
    where d.db_object_id = dbo.id and d.column_name = 'status'
  );

insert into sys_choice (dictionary_id, value, label, display_order, is_default)
select d.id, c.value, c.label, c.ord, c.is_default
from sys_dictionary d
join sys_db_object dbo on dbo.id = d.db_object_id and dbo.name = 'fam_list_member'
join (values
  ('pending',  'Pendiente', 1, false),
  ('approved', 'Aprobado',  2, true)
) as c(value, label, ord, is_default) on true
where d.column_name = 'status'
  and not exists (
    select 1 from sys_choice sc
    where sc.dictionary_id = d.id and sc.value = c.value and sc.company_id is null
  );
