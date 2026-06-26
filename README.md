# cms-mdd

SaaS MDD multi-tenant, estilo ServiceNow. Motor de metadatos que alimenta una UI dinámica (formularios y listas auto-generados).

**Stack:** Supabase (Postgres + RLS) · React + TypeScript (UI dinámica, próximamente)

**Proyecto Supabase:** `cms-mdd` (`tncbdookqvusxjnklrns`) — región `us-east-1`

Ver documentación completa de arquitectura en [`docs/README_core_mdd.md`](docs/README_core_mdd.md).

## Estado
- [x] Core MDD (12 tablas `sys_*`) — migración aplicada
- [ ] RLS + funciones de seguridad
- [ ] Seed inicial (platform admin, primera compañía)
- [ ] Motor de UI dinámica (lee `sys_dictionary` en runtime)
