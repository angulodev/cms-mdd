# cms-mdd

SaaS **MDD (Metadata-Driven Development)** multi-tenant, estilo ServiceNow. Un motor de metadatos en Postgres que describe tablas, campos, roles y reglas de acceso — y que alimentará una UI dinámica capaz de renderizar formularios y listas sin código por entidad.

**Stack:** Supabase (Postgres 17 + RLS + Auth) · React + TypeScript (UI dinámica, próximamente)

**Proyecto Supabase:** `cms-mdd` (ref `mseiqleparjnchmgnwwa`) — región `us-east-1`

> ⚠️ **Historia:** el proyecto Supabase original (`tncbdookqvusxjnklrns`) fue eliminado por accidente el 2026-07-05. Se recreó en minutos re-aplicando las migraciones de este repo. **Moraleja: toda alteración del schema pasa por una migración versionada aquí. Sin excepciones.**

---

## Estado actual (2026-07-06)

- [x] **001** — Core MDD: 12 tablas `sys_*` + índices
- [x] **002** — Seguridad: 4 funciones `SECURITY DEFINER`, RLS en las 12 tablas (29 políticas), trigger de signup, seed base
- [x] **003** — Seed: Francisco como platform admin, membresía y rol admin en Angulodev
- [ ] Módulo `fam_*` — listas compartidas familiares (compras/tareas/pendientes) con Google OAuth + Realtime
- [ ] Motor de UI dinámica (lee `sys_dictionary` en runtime)
- [ ] Generador de políticas RLS desde `sys_acl`

---

## Arquitectura del backend

### Modelo multi-tenant

`sys_company` es el tenant raíz. Un usuario puede pertenecer a N compañías (`sys_user_company`) y sus roles se otorgan **por compañía** (`sys_user_role`), no globalmente. La compañía con `is_default = true` es la activa al iniciar sesión.

### Las 12 tablas core

**Identidad y tenancy**
| Tabla | Propósito |
|---|---|
| `sys_company` | Tenant raíz. Cada compañía es un cliente del SaaS. |
| `sys_user` | Perfil extendido de `auth.users`. Incluye `is_platform_admin` (super-admin global). |
| `sys_user_company` | Puente N:N usuario↔compañía, con compañía default. |

**RBAC**
| Tabla | Propósito |
|---|---|
| `sys_role` | Catálogo de roles. `company_id null` = rol de plataforma disponible para todos los tenants. |
| `sys_user_role` | Qué rol tiene cada usuario **dentro de qué compañía**. Base de todo el control de acceso. |

**Navegación (Application Navigator)**
| Tabla | Propósito |
|---|---|
| `sys_application` | Aplicación de alto nivel (ej: "CMS", "Listas Familiares"). Agrupa módulos. |
| `sys_module` | Ítem de menú: lista de una tabla, formulario nuevo, URL o dashboard. |

**Motor MDD (el corazón)**
| Tabla | Propósito |
|---|---|
| `sys_db_object` | Diccionario de **tablas** de negocio. Soporta herencia (`extends_table_id`, estilo task→incident). |
| `sys_dictionary` | Diccionario de **campos**: tipo, obligatoriedad, visibilidad en lista/form, orden. La UI dinámica lee esta tabla para renderizar. |
| `sys_choice` | Valores de campos tipo choice, editables sin tocar código. Soporta overrides por tenant. |

**Seguridad y auditoría**
| Tabla | Propósito |
|---|---|
| `sys_acl` | Reglas de acceso por tabla/campo/rol/operación. Alimenta la UI y (a futuro) genera políticas RLS. |
| `sys_audit` | Bitácora genérica de insert/update/delete sobre cualquier tabla de negocio registrada. |

### Funciones de seguridad (`SECURITY DEFINER`)

Todas con `set search_path = public` y `stable`:

| Función | Rol |
|---|---|
| `fn_user_company_ids()` | Devuelve las compañías del usuario autenticado. Base del aislamiento multi-tenant en casi todas las políticas. |
| `fn_is_platform_admin()` | `true` si el usuario es super-admin. Bypass de negocio (no de Postgres). |
| `fn_user_has_role(rol, company)` | Chequeo de rol contextualizado por compañía. |
| `fn_check_acl(tabla, operación)` | Chequeo genérico contra `sys_acl` para futuras tablas de negocio. |

Se usan `SECURITY DEFINER` para que las políticas puedan consultar `sys_user_company` / `sys_user_role` sin recursión infinita de RLS sobre esas mismas tablas.

### RLS: filosofía

RLS habilitado en **las 12 tablas** con 29 políticas explícitas:

- **Aislamiento por tenant:** solo ves datos de compañías a las que perteneces.
- **Platform admin** ve y gestiona todo (vía `fn_is_platform_admin()`).
- **Metadata del MDD** (`sys_db_object`, `sys_dictionary`): lectura abierta a autenticados (la UI la necesita para renderizar), escritura solo platform admin.
- **`sys_acl`**: invisible e intocable salvo para platform admin.
- **Gestión de miembros y roles**: requiere rol `admin` en esa compañía.

### Trigger de signup

`on_auth_user_created` → `handle_new_user()`: al registrarse alguien en Supabase Auth, se crea automáticamente su fila en `sys_user` (idempotente con `on conflict do nothing`).

### Seed actual

- Compañía **Angulodev**
- Roles de plataforma: `admin`, `app_admin`, `reader`
- **Francisco** (`francisco.angulo1992@gmail.com`): `is_platform_admin = true`, miembro default de Angulodev con rol `admin`

---

## Migraciones

| Archivo | Contenido | Estado |
|---|---|---|
| `20260626231240_core_mdd.sql` | 12 tablas + índices | ✅ Aplicada |
| `20260626235345_security_rls.sql` | Funciones + RLS + trigger + seed base | ✅ Aplicada |
| `20260706_seed_platform_admin.sql` | Platform admin + membresía (sin IDs hardcodeados) | ✅ Aplicada |

### Recrear el proyecto desde cero

1. Crear proyecto Supabase (free tier)
2. Aplicar las migraciones de `supabase/migrations/` **en orden**
3. Registrar al usuario admin vía Supabase Auth (el trigger crea su `sys_user`)
4. Re-aplicar la 003 (resuelve por email, no por UUID)
5. Actualizar el ref del proyecto en este README

---

## Convenciones

- **Prefijos por dominio:** `sys_*` = core de plataforma · `fam_*` = listas familiares (próximo módulo). Un solo proyecto Supabase hospeda varios dominios con RLS independiente.
- **Nada de IDs hardcodeados en seeds** — siempre resolver por claves naturales (email, nombre).
- **Todo cambio de schema es una migración en este repo.** El proyecto Supabase es desechable; este repo es la fuente de verdad.

---

## Documentación adicional

Arquitectura extendida y decisiones de diseño: [`docs/README_core_mdd.md`](docs/README_core_mdd.md)

**Autores:** Francisco Angulo (angulodev) + Claude (socio técnico)
