-- =====================================================================
-- 004 - MÓDULO FAM: Listas compartidas familiares
-- Proyecto: cms-mdd (ref mseiqleparjnchmgnwwa)
-- Autor: Francisco Angulo (angulodev) + Claude (socio técnico)
-- Fecha: 2026-07-07
--
-- Contenido:
--   1. Tablas fam_list, fam_list_member, fam_item
--   2. Funciones de seguridad (SECURITY DEFINER) + join por código
--   3. Triggers (owner automático, updated_at)
--   4. RLS (aislamiento por membresía de lista, no por tenant)
--   5. Realtime (publication supabase_realtime)
--   6. Registro en el MDD (sys_application, sys_module, sys_db_object,
--      sys_dictionary, sys_choice) — sin IDs hardcodeados
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. TABLAS
-- ---------------------------------------------------------------------

create table fam_list (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  list_type text not null default 'compras'
    check (list_type in ('compras', 'tareas', 'pendientes', 'otra')),
  icon text,
  color text,
  share_code text not null unique
    default upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6)),
  is_archived boolean not null default false,
  created_by uuid not null references sys_user(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table fam_list is 'Lista compartida familiar (compras, tareas, pendientes). Acceso por membresía, no por tenant.';
comment on column fam_list.share_code is 'Código corto de 6 caracteres para unirse a la lista (fn_fam_join_by_code).';

create table fam_list_member (
  id uuid primary key default uuid_generate_v4(),
  list_id uuid not null references fam_list(id) on delete cascade,
  user_id uuid not null references sys_user(id) on delete cascade,
  member_role text not null default 'editor'
    check (member_role in ('owner', 'editor', 'viewer')),
  joined_at timestamptz not null default now(),
  unique (list_id, user_id)
);

comment on table fam_list_member is 'Miembros de cada lista. owner = control total, editor = CRUD de ítems, viewer = solo lectura.';

create table fam_item (
  id uuid primary key default uuid_generate_v4(),
  list_id uuid not null references fam_list(id) on delete cascade,
  content text not null,
  notes text,
  quantity text,                        -- texto libre: "2 kg", "3 unidades"
  is_done boolean not null default false,
  done_by uuid references sys_user(id),
  done_at timestamptz,
  position integer not null default 0,
  created_by uuid not null references sys_user(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table fam_item is 'Ítem dentro de una lista familiar. is_done + done_by/done_at para saber quién completó qué.';

-- Índices
create index idx_fam_member_user on fam_list_member(user_id);
create index idx_fam_member_list on fam_list_member(list_id);
create index idx_fam_item_list on fam_item(list_id);
create index idx_fam_item_list_pending on fam_item(list_id) where is_done = false;

-- ---------------------------------------------------------------------
-- 2. FUNCIONES DE SEGURIDAD
-- SECURITY DEFINER para evitar recursión de RLS sobre fam_list_member.
-- ---------------------------------------------------------------------

create or replace function fn_fam_is_member(p_list_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from fam_list_member
    where list_id = p_list_id and user_id = auth.uid()
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
  );
$$;

-- Unirse a una lista con el código compartido (bypass controlado del RLS de insert)
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

  insert into fam_list_member (list_id, user_id, member_role)
  values (v_list_id, auth.uid(), 'editor')
  on conflict (list_id, user_id) do nothing;

  return v_list_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. TRIGGERS
-- ---------------------------------------------------------------------

-- Al crear una lista, el creador queda como owner automáticamente
create or replace function fn_fam_list_add_owner()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into fam_list_member (list_id, user_id, member_role)
  values (new.id, new.created_by, 'owner')
  on conflict (list_id, user_id) do nothing;
  return new;
end;
$$;

create trigger trg_fam_list_add_owner
  after insert on fam_list
  for each row execute function fn_fam_list_add_owner();

-- updated_at genérico (reutilizable por futuros módulos)
create or replace function fn_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger trg_fam_list_touch
  before update on fam_list
  for each row execute function fn_touch_updated_at();

create trigger trg_fam_item_touch
  before update on fam_item
  for each row execute function fn_touch_updated_at();

-- ---------------------------------------------------------------------
-- 4. RLS
-- Filosofía fam_*: el aislamiento es POR LISTA (membresía), no por tenant.
-- ---------------------------------------------------------------------

alter table fam_list enable row level security;
alter table fam_list_member enable row level security;
alter table fam_item enable row level security;

-- fam_list
create policy fam_list_select on fam_list
  for select using (fn_fam_is_member(id) or fn_is_platform_admin());

create policy fam_list_insert on fam_list
  for insert with check (created_by = auth.uid());

create policy fam_list_update on fam_list
  for update using (fn_fam_has_role(id, array['owner']) or fn_is_platform_admin());

create policy fam_list_delete on fam_list
  for delete using (fn_fam_has_role(id, array['owner']) or fn_is_platform_admin());

-- fam_list_member
create policy fam_member_select on fam_list_member
  for select using (fn_fam_is_member(list_id) or fn_is_platform_admin());

-- Solo el owner agrega miembros directamente; el auto-join pasa por fn_fam_join_by_code
create policy fam_member_insert on fam_list_member
  for insert with check (fn_fam_has_role(list_id, array['owner']) or fn_is_platform_admin());

create policy fam_member_update on fam_list_member
  for update using (fn_fam_has_role(list_id, array['owner']));

-- El owner puede sacar miembros; cualquiera puede salirse de una lista
create policy fam_member_delete on fam_list_member
  for delete using (
    fn_fam_has_role(list_id, array['owner'])
    or user_id = auth.uid()
  );

-- fam_item
create policy fam_item_select on fam_item
  for select using (fn_fam_is_member(list_id));

create policy fam_item_insert on fam_item
  for insert with check (
    fn_fam_has_role(list_id, array['owner', 'editor'])
    and created_by = auth.uid()
  );

create policy fam_item_update on fam_item
  for update using (fn_fam_has_role(list_id, array['owner', 'editor']));

create policy fam_item_delete on fam_item
  for delete using (fn_fam_has_role(list_id, array['owner', 'editor']));

-- ---------------------------------------------------------------------
-- 5. REALTIME
-- ---------------------------------------------------------------------

alter publication supabase_realtime add table fam_list, fam_list_member, fam_item;

-- Payloads completos en UPDATE/DELETE (necesario para filtros de Realtime)
alter table fam_list replica identity full;
alter table fam_item replica identity full;

-- ---------------------------------------------------------------------
-- 6. REGISTRO EN EL MDD (sin IDs hardcodeados — claves naturales)
-- ---------------------------------------------------------------------

-- 6.1 Aplicación
insert into sys_application (name, scope_prefix, description, icon, color, display_order)
values ('Listas Familiares', 'fam', 'Listas compartidas de compras, tareas y pendientes con Realtime', 'list-checks', '#10B981', 10)
on conflict (scope_prefix) do nothing;

-- 6.2 Módulos de navegación
insert into sys_module (application_id, name, table_name, module_type, icon, display_order)
select a.id, m.name, m.table_name, m.module_type, m.icon, m.display_order
from sys_application a
cross join (values
  ('Mis Listas', 'fam_list', 'list', 'list', 1),
  ('Nueva Lista', 'fam_list', 'new_record', 'plus', 2),
  ('Ítems', 'fam_item', 'list', 'check-square', 3)
) as m(name, table_name, module_type, icon, display_order)
where a.scope_prefix = 'fam'
  and not exists (
    select 1 from sys_module sm
    where sm.application_id = a.id and sm.name = m.name
  );

-- 6.3 Diccionario de tablas
insert into sys_db_object (name, label, label_plural, application_id, description, icon)
select o.name, o.label, o.label_plural, a.id, o.description, o.icon
from sys_application a
cross join (values
  ('fam_list', 'Lista', 'Listas', 'Lista compartida familiar', 'list'),
  ('fam_list_member', 'Miembro de Lista', 'Miembros de Lista', 'Membresía usuario↔lista con rol', 'users'),
  ('fam_item', 'Ítem', 'Ítems', 'Ítem dentro de una lista', 'check-square')
) as o(name, label, label_plural, description, icon)
where a.scope_prefix = 'fam'
on conflict (name) do nothing;

-- 6.4 Diccionario de campos (los que la UI dinámica renderiza)
insert into sys_dictionary
  (db_object_id, column_name, label, field_type, is_mandatory, is_visible_in_list, is_visible_in_form, display_order, help_text)
select dbo.id, f.column_name, f.label, f.field_type, f.is_mandatory, f.in_list, f.in_form, f.ord, f.help_text
from sys_db_object dbo
join (values
  -- fam_list
  ('fam_list', 'name',       'Nombre',       'string',  true,  true,  true,  1, 'Nombre de la lista'),
  ('fam_list', 'list_type',  'Tipo',         'choice',  true,  true,  true,  2, null),
  ('fam_list', 'icon',       'Ícono',        'string',  false, false, true,  3, 'Nombre de ícono lucide-react'),
  ('fam_list', 'color',      'Color',        'string',  false, false, true,  4, 'Hex, ej #10B981'),
  ('fam_list', 'share_code', 'Código',       'string',  false, true,  true,  5, 'Compártelo para que otros se unan'),
  ('fam_list', 'is_archived','Archivada',    'boolean', false, true,  true,  6, null),
  -- fam_item
  ('fam_item', 'content',    'Contenido',    'string',  true,  true,  true,  1, null),
  ('fam_item', 'quantity',   'Cantidad',     'string',  false, true,  true,  2, 'Texto libre: 2 kg, 3 unidades'),
  ('fam_item', 'notes',      'Notas',        'text',    false, false, true,  3, null),
  ('fam_item', 'is_done',    'Completado',   'boolean', false, true,  true,  4, null),
  ('fam_item', 'done_by',    'Completado por','reference', false, true, false, 5, null),
  ('fam_item', 'position',   'Posición',     'integer', false, false, false, 6, null),
  -- fam_list_member
  ('fam_list_member', 'user_id',     'Usuario', 'reference', true, true, true, 1, null),
  ('fam_list_member', 'member_role', 'Rol',     'choice',    true, true, true, 2, null)
) as f(table_name, column_name, label, field_type, is_mandatory, in_list, in_form, ord, help_text)
  on dbo.name = f.table_name
where not exists (
  select 1 from sys_dictionary d
  where d.db_object_id = dbo.id and d.column_name = f.column_name
);

-- Cerrar reference_table_id de los campos reference (apuntan a sys_user)
update sys_dictionary d
set reference_table_id = (select id from sys_db_object where name = 'sys_user')
where d.column_name in ('done_by', 'user_id')
  and d.db_object_id in (select id from sys_db_object where name in ('fam_item', 'fam_list_member'))
  and d.reference_table_id is null
  and exists (select 1 from sys_db_object where name = 'sys_user');

-- 6.5 Choices
insert into sys_choice (dictionary_id, value, label, display_order, is_default)
select d.id, c.value, c.label, c.ord, c.is_default
from sys_dictionary d
join sys_db_object dbo on dbo.id = d.db_object_id
join (values
  ('fam_list', 'list_type', 'compras',    'Compras',    1, true),
  ('fam_list', 'list_type', 'tareas',     'Tareas',     2, false),
  ('fam_list', 'list_type', 'pendientes', 'Pendientes', 3, false),
  ('fam_list', 'list_type', 'otra',       'Otra',       4, false),
  ('fam_list_member', 'member_role', 'owner',  'Dueño',  1, false),
  ('fam_list_member', 'member_role', 'editor', 'Editor', 2, true),
  ('fam_list_member', 'member_role', 'viewer', 'Lector', 3, false)
) as c(table_name, column_name, value, label, ord, is_default)
  on dbo.name = c.table_name and d.column_name = c.column_name
where not exists (
  select 1 from sys_choice sc
  where sc.dictionary_id = d.id and sc.value = c.value and sc.company_id is null
);

-- =====================================================================
-- FIN 004 — Módulo fam_*
-- Pendiente fuera de SQL: habilitar Google OAuth en el dashboard de
-- Supabase (Authentication → Providers → Google).
-- =====================================================================
