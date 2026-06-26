# CMS MDD — Core (estilo ServiceNow)

Motor de metadatos (MDD) multi-tenant para generar UI dinámica, inspirado en la arquitectura de ServiceNow.

## Proyecto Supabase
- **Nombre:** `cms-mdd`
- **Project ref:** `tncbdookqvusxjnklrns`
- **Región:** `us-east-1`
- **Org:** angulodev's Org (free tier)

## Estado actual
- ✅ Migración `001_core_mdd` aplicada — 12 tablas core creadas
- ✅ Migración `002_security_rls` aplicada:
  - Funciones `SECURITY DEFINER`: `fn_user_company_ids()`, `fn_is_platform_admin()`, `fn_user_has_role()`, `fn_check_acl()`
  - RLS habilitado y con políticas en las 12 tablas core
  - Trigger `on_auth_user_created` → auto-crea `sys_user` al hacer signup
  - Seed: compañía **Angulodev**, roles de sistema `admin` / `app_admin` / `reader`
- ⏳ Pendiente (003): registrar a Francisco en `auth.users` (signup) y luego marcarlo `is_platform_admin = true` + asignarlo a Angulodev con rol `admin`
- ⏳ Pendiente: motor de UI dinámica que lea `sys_dictionary`

## Decisiones de arquitectura (no reabrir sin discutirlas)

1. **Tablas de negocio = SQL real**, no JSONB genérico. Cada entidad de negocio (incidente, proyecto, etc.) tiene su propia tabla Postgres con columnas dedicadas.
2. **`sys_acl` es híbrido**: metadata editable desde la UI + puente a funciones `SECURITY DEFINER` que las políticas RLS invocan. La metadata sola NO es seguridad — el enforcement real vive en RLS de Postgres.
3. **Multi-tenant vía `sys_user_company` + `sys_user_role`**: un usuario puede pertenecer a varias compañías y tener roles distintos en cada una. No hay "un rol global" salvo `is_platform_admin` (reservado para Francisco).
4. **Herencia tipo ServiceNow** disponible vía `sys_db_object.extends_table_id`, pero no se ha usado aún en ninguna tabla de negocio.
5. **El motor de UI dinámica lee `sys_dictionary` en runtime** — cualquier cambio a esa tabla afecta directamente lo que se renderiza, sin deploy.

## Orden de las 12 tablas core (no reordenar al migrar)

| # | Tabla | Rol |
|---|-------|-----|
| 1 | `sys_company` | Tenant raíz |
| 2 | `sys_user` | Extiende `auth.users` |
| 3 | `sys_user_company` | Puente N:N usuario↔compañía |
| 4 | `sys_role` | Catálogo de roles |
| 5 | `sys_user_role` | Puente N:N usuario↔rol↔compañía |
| 6 | `sys_application` | Agrupador de alto nivel (Application Navigator) |
| 7 | `sys_module` | Ítem de menú dentro de una aplicación |
| 8 | `sys_db_object` | Catálogo maestro de tablas (Tabla del MDD) |
| 9 | `sys_dictionary` | Catálogo de campos por tabla (corazón del MDD) |
| 10 | `sys_choice` | Valores de listas desplegables |
| 11 | `sys_acl` | Reglas de acceso (metadata + puente a RLS) |
| 12 | `sys_audit` | Bitácora de cambios |

## Siguiente paso (archivo 002)

- `fn_check_acl()`, `fn_user_has_role()` — funciones `SECURITY DEFINER`
- Políticas RLS sobre las 12 tablas core
- Trigger en `auth.users` → auto-crear `sys_user`
- Seed: usuario platform_admin (Francisco), rol `admin` de sistema, primera `sys_company`

## Convención de nombres

- Todo lo core lleva prefijo `sys_*`.
- Tablas de aplicaciones específicas usan el `scope_prefix` definido en `sys_application` (ej: `cms_*`, `audita_*`).
