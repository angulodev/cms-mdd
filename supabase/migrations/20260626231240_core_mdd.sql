-- =====================================================================
-- CORE MDD - Estilo ServiceNow
-- Proyecto: [nuevo Supabase - definir nombre]
-- Autor: Francisco Angulo (angulodev) + Claude (socio técnico)
-- Fecha: 2026-06-26
-- Orden de ejecución: este archivo es secuencial, no reordenar bloques.
-- =====================================================================

-- ---------------------------------------------------------------------
-- EXTENSIONES NECESARIAS
-- ---------------------------------------------------------------------
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
-- 1. SYS_COMPANY (Tenant)
-- ---------------------------------------------------------------------
create table sys_company (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  legal_name text,
  tax_id text,                      -- RUT / identificador fiscal
  is_active boolean not null default true,
  settings jsonb not null default '{}'::jsonb,  -- config flexible por tenant
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,                  -- referencia diferida a sys_user (se agrega FK después)
  updated_by uuid
);

comment on table sys_company is 'Tenant raíz. Cada compañía es un cliente del SaaS.';

-- ---------------------------------------------------------------------
-- 2. SYS_USER (extiende auth.users de Supabase)
-- ---------------------------------------------------------------------
create table sys_user (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  first_name text,
  last_name text,
  display_name text generated always as (
    coalesce(first_name, '') || ' ' || coalesce(last_name, '')
  ) stored,
  avatar_url text,
  phone text,
  locale text not null default 'es-CL',
  is_active boolean not null default true,
  is_platform_admin boolean not null default false,  -- Francisco = true
  last_login_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table sys_user is 'Perfil extendido de auth.users. is_platform_admin = super-admin global (solo Francisco).';

-- Ahora sí, cerramos las FK diferidas de sys_company
alter table sys_company
  add constraint fk_company_created_by foreign key (created_by) references sys_user(id),
  add constraint fk_company_updated_by foreign key (updated_by) references sys_user(id);

-- ---------------------------------------------------------------------
-- 3. SYS_USER_COMPANY (puente N:N — un usuario puede pertenecer a varias compañías)
-- ---------------------------------------------------------------------
create table sys_user_company (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references sys_user(id) on delete cascade,
  company_id uuid not null references sys_company(id) on delete cascade,
  is_default boolean not null default false,  -- compañía activa al iniciar sesión
  created_at timestamptz not null default now(),
  unique (user_id, company_id)
);

comment on table sys_user_company is 'Relación multi-tenant: a qué compañías pertenece cada usuario.';

-- ---------------------------------------------------------------------
-- 4. SYS_ROLE (catálogo de roles)
-- ---------------------------------------------------------------------
create table sys_role (
  id uuid primary key default uuid_generate_v4(),
  name text not null unique,         -- ej: 'admin', 'app_admin', 'itil', 'reader'
  description text,
  is_system_role boolean not null default false,  -- roles que vienen de fábrica, no editables
  company_id uuid references sys_company(id),     -- null = rol global de plataforma
  created_at timestamptz not null default now()
);

comment on table sys_role is 'Catálogo de roles. company_id null = rol de plataforma disponible para todos los tenants.';

-- ---------------------------------------------------------------------
-- 5. SYS_USER_ROLE (puente N:N — usuario↔rol, contextualizado por compañía)
-- ---------------------------------------------------------------------
create table sys_user_role (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references sys_user(id) on delete cascade,
  role_id uuid not null references sys_role(id) on delete cascade,
  company_id uuid not null references sys_company(id) on delete cascade,
  granted_at timestamptz not null default now(),
  granted_by uuid references sys_user(id),
  unique (user_id, role_id, company_id)
);

comment on table sys_user_role is 'Qué rol tiene cada usuario, dentro de qué compañía. Es la base de todo el RBAC.';

-- ---------------------------------------------------------------------
-- 6. SYS_APPLICATION (agrupador de alto nivel — ej "CMS", "AuditaCGE")
-- ---------------------------------------------------------------------
create table sys_application (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  scope_prefix text not null unique,   -- ej: 'cms', 'audita', 'leader' — usado para nombrar tablas
  description text,
  icon text,                            -- nombre de icono (lucide-react)
  color text,                           -- hex para UI
  is_active boolean not null default true,
  display_order integer not null default 0,
  company_id uuid references sys_company(id),  -- null = disponible para todos los tenants
  created_at timestamptz not null default now()
);

comment on table sys_application is 'Aplicación de alto nivel dentro del navegador (Application Navigator). Agrupa módulos.';

-- ---------------------------------------------------------------------
-- 7. SYS_MODULE (submenú dentro de una aplicación — ej "Companies", "Users")
-- ---------------------------------------------------------------------
create table sys_module (
  id uuid primary key default uuid_generate_v4(),
  application_id uuid not null references sys_application(id) on delete cascade,
  name text not null,
  table_name text,                      -- a qué tabla apunta este módulo (si aplica)
  module_type text not null default 'list'
    check (module_type in ('list', 'new_record', 'separator', 'url', 'dashboard')),
  url text,                             -- si module_type = 'url'
  icon text,
  display_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

comment on table sys_module is 'Ítem de menú dentro de una aplicación. Apunta a una tabla (lista) o a una URL/dashboard.';

-- ---------------------------------------------------------------------
-- 8. SYS_DB_OBJECT (catálogo maestro de TABLAS — tu "Tabla" del MDD)
-- ---------------------------------------------------------------------
create table sys_db_object (
  id uuid primary key default uuid_generate_v4(),
  name text not null unique,            -- nombre real de la tabla en Postgres, ej: 'incident'
  label text not null,                  -- nombre visible, ej: 'Incidente'
  label_plural text not null,           -- ej: 'Incidentes'
  application_id uuid references sys_application(id),
  extends_table_id uuid references sys_db_object(id),  -- herencia tipo ServiceNow (task -> incident)
  is_extendable boolean not null default false,
  description text,
  icon text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references sys_user(id)
);

comment on table sys_db_object is 'Registro maestro de cada tabla de negocio del sistema. Es el "diccionario de tablas" del MDD.';

-- ---------------------------------------------------------------------
-- 9. SYS_DICTIONARY (catálogo de CAMPOS por tabla — el corazón del MDD)
-- ---------------------------------------------------------------------
create table sys_dictionary (
  id uuid primary key default uuid_generate_v4(),
  db_object_id uuid not null references sys_db_object(id) on delete cascade,
  column_name text not null,            -- nombre real de la columna en Postgres
  label text not null,                  -- nombre visible
  field_type text not null check (field_type in (
    'string', 'integer', 'decimal', 'boolean', 'date', 'datetime',
    'reference', 'choice', 'email', 'phone', 'url', 'text', 'json'
  )),
  reference_table_id uuid references sys_db_object(id),  -- solo si field_type = 'reference'
  max_length integer,
  is_mandatory boolean not null default false,
  is_unique boolean not null default false,
  is_read_only boolean not null default false,
  is_visible_in_list boolean not null default true,
  is_visible_in_form boolean not null default true,
  default_value text,
  display_order integer not null default 0,
  help_text text,
  created_at timestamptz not null default now(),
  unique (db_object_id, column_name)
);

comment on table sys_dictionary is 'Define cada campo de cada tabla de negocio. La UI dinámica lee esta tabla para renderizar formularios y listas.';

-- ---------------------------------------------------------------------
-- 10. SYS_CHOICE (valores de listas desplegables, ligadas a un campo dictionary)
-- ---------------------------------------------------------------------
create table sys_choice (
  id uuid primary key default uuid_generate_v4(),
  dictionary_id uuid not null references sys_dictionary(id) on delete cascade,
  value text not null,                  -- valor almacenado en BD
  label text not null,                  -- valor visible al usuario
  display_order integer not null default 0,
  is_default boolean not null default false,
  is_inactive boolean not null default false,
  company_id uuid references sys_company(id),  -- null = choice global
  unique (dictionary_id, value, company_id)
);

comment on table sys_choice is 'Valores posibles para campos tipo choice. Editable desde la UI sin tocar código.';

-- ---------------------------------------------------------------------
-- 11. SYS_ACL (seguridad por tabla/campo/rol — metadata + puente a RLS)
-- ---------------------------------------------------------------------
create table sys_acl (
  id uuid primary key default uuid_generate_v4(),
  db_object_id uuid not null references sys_db_object(id) on delete cascade,
  dictionary_id uuid references sys_dictionary(id),  -- null = regla a nivel de tabla completa
  operation text not null check (operation in ('create', 'read', 'write', 'delete')),
  role_id uuid references sys_role(id),              -- null = aplica a "todos los autenticados"
  condition_type text not null default 'role_only'
    check (condition_type in ('role_only', 'owner_only', 'same_company', 'custom_function')),
  custom_function_name text,            -- nombre de función SECURITY DEFINER si condition_type = 'custom_function'
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

comment on table sys_acl is 'Reglas de acceso. Alimenta tanto la UI (qué mostrar) como las políticas RLS reales en Postgres.';

-- ---------------------------------------------------------------------
-- 12. SYS_AUDIT (bitácora general a nivel core)
-- ---------------------------------------------------------------------
create table sys_audit (
  id uuid primary key default uuid_generate_v4(),
  db_object_id uuid references sys_db_object(id),
  record_id uuid not null,              -- id del registro afectado (en su tabla original)
  operation text not null check (operation in ('insert', 'update', 'delete')),
  changed_by uuid references sys_user(id),
  old_values jsonb,
  new_values jsonb,
  created_at timestamptz not null default now()
);

comment on table sys_audit is 'Bitácora genérica de cambios sobre cualquier tabla de negocio registrada en sys_db_object.';

-- =====================================================================
-- ÍNDICES (rendimiento — multi-tenant + lecturas frecuentes del MDD)
-- =====================================================================
create index idx_user_company_user on sys_user_company(user_id);
create index idx_user_company_company on sys_user_company(company_id);
create index idx_user_role_user on sys_user_role(user_id);
create index idx_user_role_company on sys_user_role(company_id);
create index idx_module_application on sys_module(application_id);
create index idx_db_object_application on sys_db_object(application_id);
create index idx_dictionary_db_object on sys_dictionary(db_object_id);
create index idx_choice_dictionary on sys_choice(dictionary_id);
create index idx_acl_db_object on sys_acl(db_object_id);
create index idx_audit_db_object_record on sys_audit(db_object_id, record_id);

-- =====================================================================
-- FIN DEL ARCHIVO 001 — Core MDD
-- Siguiente archivo: 002_rls_functions.sql (funciones de seguridad + RLS)
-- =====================================================================
