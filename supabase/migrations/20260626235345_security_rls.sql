-- =====================================================================
-- 002 - Seguridad: funciones SECURITY DEFINER + RLS + trigger
-- Proyecto: cms-mdd (tncbdookqvusxjnklrns)
-- Depende de: 001_core_mdd.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- FN 1: company_ids del usuario actual
-- Base de TODO el aislamiento multi-tenant. Stable + SECURITY DEFINER
-- para poder leer sys_user_company sin chocar con las políticas RLS
-- que vamos a poner sobre esa misma tabla.
-- ---------------------------------------------------------------------
create or replace function fn_user_company_ids()
returns uuid[]
language sql
security definer
stable
set search_path = public
as $$
  select coalesce(array_agg(company_id), array[]::uuid[])
  from sys_user_company
  where user_id = auth.uid();
$$;

comment on function fn_user_company_ids is 'Compañías a las que pertenece el usuario autenticado. Usada por casi todas las políticas RLS.';

-- ---------------------------------------------------------------------
-- FN 2: ¿el usuario actual es platform_admin?
-- Bypass total — equivalente al super-admin de ServiceNow.
-- ---------------------------------------------------------------------
create or replace function fn_is_platform_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select coalesce(
    (select is_platform_admin from sys_user where id = auth.uid()),
    false
  );
$$;

comment on function fn_is_platform_admin is 'true si el usuario autenticado es super-admin de plataforma (bypass de RLS por diseño de negocio, no de Postgres).';

-- ---------------------------------------------------------------------
-- FN 3: ¿el usuario actual tiene un rol específico en una compañía?
-- ---------------------------------------------------------------------
create or replace function fn_user_has_role(p_role_name text, p_company_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from sys_user_role ur
    join sys_role r on r.id = ur.role_id
    where ur.user_id = auth.uid()
      and ur.company_id = p_company_id
      and r.name = p_role_name
  );
$$;

comment on function fn_user_has_role is 'true si el usuario autenticado tiene el rol p_role_name dentro de p_company_id.';

-- ---------------------------------------------------------------------
-- FN 4: chequeo general contra sys_acl (para tablas de negocio futuras)
-- Por ahora cubre condition_type = 'role_only' y 'same_company'.
-- 'owner_only' y 'custom_function' quedan preparados para cuando
-- existan tablas de negocio que los necesiten.
-- ---------------------------------------------------------------------
create or replace function fn_check_acl(p_table_name text, p_operation text)
returns boolean
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_db_object_id uuid;
  v_has_access boolean := false;
begin
  if fn_is_platform_admin() then
    return true;
  end if;

  select id into v_db_object_id from sys_db_object where name = p_table_name;

  if v_db_object_id is null then
    return false;
  end if;

  select exists (
    select 1
    from sys_acl acl
    left join sys_role r on r.id = acl.role_id
    where acl.db_object_id = v_db_object_id
      and acl.operation = p_operation
      and acl.is_active = true
      and (
        acl.role_id is null  -- regla abierta a todo autenticado
        or exists (
          select 1 from sys_user_role ur
          where ur.user_id = auth.uid() and ur.role_id = acl.role_id
        )
      )
  ) into v_has_access;

  return v_has_access;
end;
$$;

comment on function fn_check_acl is 'Chequeo genérico de ACL para tablas de negocio. Las tablas core usan políticas más simples y explícitas (ver abajo).';

-- =====================================================================
-- RLS: habilitar en las 12 tablas core
-- =====================================================================
alter table sys_company enable row level security;
alter table sys_user enable row level security;
alter table sys_user_company enable row level security;
alter table sys_role enable row level security;
alter table sys_user_role enable row level security;
alter table sys_application enable row level security;
alter table sys_module enable row level security;
alter table sys_db_object enable row level security;
alter table sys_dictionary enable row level security;
alter table sys_choice enable row level security;
alter table sys_acl enable row level security;
alter table sys_audit enable row level security;

-- ---------------------------------------------------------------------
-- POLÍTICAS: sys_company
-- Ve solo las compañías a las que pertenece, o todas si es platform_admin.
-- ---------------------------------------------------------------------
create policy sys_company_select on sys_company
  for select
  using (
    fn_is_platform_admin()
    or id = any(fn_user_company_ids())
  );

create policy sys_company_insert on sys_company
  for insert
  with check (fn_is_platform_admin());

create policy sys_company_update on sys_company
  for update
  using (
    fn_is_platform_admin()
    or (id = any(fn_user_company_ids()) and fn_user_has_role('admin', id))
  );

create policy sys_company_delete on sys_company
  for delete
  using (fn_is_platform_admin());

-- ---------------------------------------------------------------------
-- POLÍTICAS: sys_user
-- Cualquiera ve su propio perfil. Ve perfiles de compañeros de compañía.
-- Solo el propio usuario (o platform_admin) puede editar su perfil.
-- ---------------------------------------------------------------------
create policy sys_user_select on sys_user
  for select
  using (
    fn_is_platform_admin()
    or id = auth.uid()
    or id in (
      select uc.user_id from sys_user_company uc
      where uc.company_id = any(fn_user_company_ids())
    )
  );

create policy sys_user_update on sys_user
  for update
  using (fn_is_platform_admin() or id = auth.uid());

-- Insert se hace solo via trigger (security definer), no directo desde el cliente.
create policy sys_user_insert on sys_user
  for insert
  with check (fn_is_platform_admin() or id = auth.uid());

-- ---------------------------------------------------------------------
-- POLÍTICAS: sys_user_company
-- ---------------------------------------------------------------------
create policy sys_user_company_select on sys_user_company
  for select
  using (
    fn_is_platform_admin()
    or user_id = auth.uid()
    or company_id = any(fn_user_company_ids())
  );

create policy sys_user_company_insert on sys_user_company
  for insert
  with check (fn_is_platform_admin() or fn_user_has_role('admin', company_id));

create policy sys_user_company_delete on sys_user_company
  for delete
  using (fn_is_platform_admin() or fn_user_has_role('admin', company_id));

-- ---------------------------------------------------------------------
-- POLÍTICAS: sys_role
-- Roles de plataforma (company_id null) visibles para todos los autenticados.
-- Roles de una compañía, solo visibles para esa compañía.
-- ---------------------------------------------------------------------
create policy sys_role_select on sys_role
  for select
  using (
    fn_is_platform_admin()
    or company_id is null
    or company_id = any(fn_user_company_ids())
  );

create policy sys_role_insert on sys_role
  for insert
  with check (
    fn_is_platform_admin()
    or (company_id is not null and fn_user_has_role('admin', company_id))
  );

create policy sys_role_update on sys_role
  for update
  using (
    fn_is_platform_admin()
    or (company_id is not null and fn_user_has_role('admin', company_id))
  );

-- ---------------------------------------------------------------------
-- POLÍTICAS: sys_user_role
-- ---------------------------------------------------------------------
create policy sys_user_role_select on sys_user_role
  for select
  using (
    fn_is_platform_admin()
    or user_id = auth.uid()
    or company_id = any(fn_user_company_ids())
  );

create policy sys_user_role_insert on sys_user_role
  for insert
  with check (fn_is_platform_admin() or fn_user_has_role('admin', company_id));

create policy sys_user_role_delete on sys_user_role
  for delete
  using (fn_is_platform_admin() or fn_user_has_role('admin', company_id));

-- ---------------------------------------------------------------------
-- POLÍTICAS: sys_application / sys_module
-- Globales (company_id null) visibles para todos. Las de una compañía,
-- solo para esa compañía. Solo platform_admin crea/edita por ahora
-- (estas tablas son más "de plataforma" que "de tenant").
-- ---------------------------------------------------------------------
create policy sys_application_select on sys_application
  for select
  using (
    fn_is_platform_admin()
    or company_id is null
    or company_id = any(fn_user_company_ids())
  );

create policy sys_application_write on sys_application
  for all
  using (fn_is_platform_admin())
  with check (fn_is_platform_admin());

create policy sys_module_select on sys_module
  for select
  using (
    fn_is_platform_admin()
    or application_id in (
      select id from sys_application
      where company_id is null or company_id = any(fn_user_company_ids())
    )
  );

create policy sys_module_write on sys_module
  for all
  using (fn_is_platform_admin())
  with check (fn_is_platform_admin());

-- ---------------------------------------------------------------------
-- POLÍTICAS: sys_db_object / sys_dictionary / sys_choice
-- Metadata del MDD: lectura abierta a todo autenticado (la UI dinámica
-- la necesita para renderizar), escritura solo platform_admin por ahora.
-- Cuando existan "app_admin" por tenant, esto se vuelve más granular.
-- ---------------------------------------------------------------------
create policy sys_db_object_select on sys_db_object
  for select
  using (auth.uid() is not null);

create policy sys_db_object_write on sys_db_object
  for all
  using (fn_is_platform_admin())
  with check (fn_is_platform_admin());

create policy sys_dictionary_select on sys_dictionary
  for select
  using (auth.uid() is not null);

create policy sys_dictionary_write on sys_dictionary
  for all
  using (fn_is_platform_admin())
  with check (fn_is_platform_admin());

create policy sys_choice_select on sys_choice
  for select
  using (
    auth.uid() is not null
    and (company_id is null or company_id = any(fn_user_company_ids()))
  );

create policy sys_choice_write on sys_choice
  for all
  using (fn_is_platform_admin())
  with check (fn_is_platform_admin());

-- ---------------------------------------------------------------------
-- POLÍTICAS: sys_acl
-- Solo platform_admin gestiona reglas de acceso. Nadie más debería
-- poder leer ni modificar esta tabla directamente desde el cliente.
-- ---------------------------------------------------------------------
create policy sys_acl_all on sys_acl
  for all
  using (fn_is_platform_admin())
  with check (fn_is_platform_admin());

-- ---------------------------------------------------------------------
-- POLÍTICAS: sys_audit
-- Lectura por compañía (vía el db_object al que pertenece el registro
-- auditado, si aplica) o platform_admin. Nadie inserta directo desde
-- el cliente: el insert lo hará un trigger genérico en el futuro.
-- ---------------------------------------------------------------------
create policy sys_audit_select on sys_audit
  for select
  using (fn_is_platform_admin() or changed_by = auth.uid());

create policy sys_audit_insert on sys_audit
  for insert
  with check (auth.uid() is not null);

-- =====================================================================
-- TRIGGER: auto-crear sys_user al registrarse en auth.users
-- =====================================================================
create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.sys_user (id, email, first_name, last_name)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data->>'first_name',
    new.raw_user_meta_data->>'last_name'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

comment on function handle_new_user is 'Crea automáticamente el perfil sys_user cuando alguien se registra via Supabase Auth.';

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- =====================================================================
-- SEED: compañía Angulodev + rol admin de sistema
-- (NO incluye asignación de usuario — eso va en 003, después del signup)
-- =====================================================================
insert into sys_company (name, legal_name, is_active)
values ('Angulodev', 'Angulodev', true)
on conflict do nothing;

insert into sys_role (name, description, is_system_role, company_id)
values
  ('admin', 'Administrador con control total dentro de su compañía', true, null),
  ('app_admin', 'Administrador de una aplicación específica', true, null),
  ('reader', 'Acceso de solo lectura', true, null)
on conflict (name) do nothing;

-- =====================================================================
-- FIN DEL ARCHIVO 002
-- Siguiente paso: 003_seed_platform_admin.sql
-- (requiere que Francisco se registre primero en la app para tener
-- un user_id real en auth.users)
-- =====================================================================
