-- =====================================================================
-- 003 - Seed: Francisco como platform admin + membresía Angulodev
-- Proyecto: cms-mdd (mseiqleparjnchmgnwwa) · Aplicada: 2026-07-06
-- Depende de: 002_security_rls.sql y del signup de Francisco
-- Sin IDs hardcodeados: todo se resuelve por email / nombre.
-- =====================================================================

update sys_user
set is_platform_admin = true,
    first_name = coalesce(first_name, 'Francisco'),
    last_name  = coalesce(last_name, 'Angulo'),
    updated_at = now()
where email = 'francisco.angulo1992@gmail.com';

insert into sys_user_company (user_id, company_id, is_default)
select u.id, c.id, true
from sys_user u, sys_company c
where u.email = 'francisco.angulo1992@gmail.com'
  and c.name = 'Angulodev'
on conflict (user_id, company_id) do nothing;

insert into sys_user_role (user_id, role_id, company_id, granted_by)
select u.id, r.id, c.id, u.id
from sys_user u, sys_role r, sys_company c
where u.email = 'francisco.angulo1992@gmail.com'
  and r.name = 'admin'
  and c.name = 'Angulodev'
on conflict (user_id, role_id, company_id) do nothing;

update sys_company
set created_by = (select id from sys_user where email = 'francisco.angulo1992@gmail.com'),
    updated_by = (select id from sys_user where email = 'francisco.angulo1992@gmail.com'),
    updated_at = now()
where name = 'Angulodev' and created_by is null;
