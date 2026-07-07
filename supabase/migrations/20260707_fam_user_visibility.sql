-- =====================================================================
-- 005 - Visibilidad de sys_user entre co-miembros de listas fam
-- Problema: sys_user_select solo permite ver usuarios de tu compañía.
-- Los miembros de una lista familiar no comparten tenant, pero la PWA
-- necesita resolver sus nombres/avatares ("Estefani completó Pan").
-- Aplicada: 2026-07-07 en mseiqleparjnchmgnwwa
-- =====================================================================

create or replace function fn_fam_shares_list_with(p_user_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from fam_list_member a
    join fam_list_member b on a.list_id = b.list_id
    where a.user_id = auth.uid()
      and b.user_id = p_user_id
  );
$$;

create policy sys_user_select_fam on sys_user
  for select
  using (fn_fam_shares_list_with(id));
