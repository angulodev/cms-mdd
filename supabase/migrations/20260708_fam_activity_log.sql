-- =====================================================================
-- 012 - fam_activity: log de actividad real por triggers
-- Captura: agregó, compró/completó, desmarcó, no encontrado, repuesto,
-- editado y ELIMINADO. Con backfill desde fam_item. Realtime habilitado.
-- Aplicada: 2026-07-08 en mseiqleparjnchmgnwwa
-- (SQL completo idéntico al aplicado; ver historial del proyecto)
-- =====================================================================

create table if not exists fam_activity (
  id uuid primary key default uuid_generate_v4(),
  list_id uuid not null references fam_list(id) on delete cascade,
  item_content text not null,
  action text not null check (action in ('added','done','undone','not_found','found','deleted','edited')),
  actor_id uuid references sys_user(id),
  detail jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_fam_activity_list_time on fam_activity(list_id, created_at desc);

alter table fam_activity enable row level security;

do $$ begin
  create policy fam_activity_select on fam_activity
    for select using (fn_fam_is_member(list_id));
exception when duplicate_object then null; end $$;

create or replace function fn_fam_item_log()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
begin
  if tg_op = 'INSERT' then
    insert into fam_activity (list_id, item_content, action, actor_id)
    values (new.list_id, new.content, 'added', coalesce(v_actor, new.created_by));
    return new;
  elsif tg_op = 'DELETE' then
    insert into fam_activity (list_id, item_content, action, actor_id)
    values (old.list_id, old.content, 'deleted', v_actor);
    return old;
  else
    if new.is_done and not old.is_done then
      insert into fam_activity (list_id, item_content, action, actor_id, detail)
      values (new.list_id, new.content, 'done', coalesce(v_actor, new.done_by),
              jsonb_strip_nulls(jsonb_build_object('price', new.price, 'quantity', new.quantity)));
    elsif old.is_done and not new.is_done then
      insert into fam_activity (list_id, item_content, action, actor_id)
      values (new.list_id, new.content, 'undone', v_actor);
    elsif new.not_found and not old.not_found then
      insert into fam_activity (list_id, item_content, action, actor_id)
      values (new.list_id, new.content, 'not_found', v_actor);
    elsif old.not_found and not new.not_found then
      insert into fam_activity (list_id, item_content, action, actor_id)
      values (new.list_id, new.content, 'found', v_actor);
    elsif new.content is distinct from old.content
       or new.quantity is distinct from old.quantity
       or new.price is distinct from old.price
       or new.link is distinct from old.link
       or new.photo_url is distinct from old.photo_url
       or new.assigned_to is distinct from old.assigned_to then
      insert into fam_activity (list_id, item_content, action, actor_id)
      values (new.list_id, new.content, 'edited', v_actor);
    end if;
    return new;
  end if;
end;
$$;

do $$ begin
  create trigger trg_fam_item_log
    after insert or update or delete on fam_item
    for each row execute function fn_fam_item_log();
exception when duplicate_object then null; end $$;

do $$ begin
  alter publication supabase_realtime add table fam_activity;
exception when duplicate_object then null; end $$;
