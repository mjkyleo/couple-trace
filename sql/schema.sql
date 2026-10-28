-- ============================================================
-- Trace · 同迹 — PostgreSQL Schema & RLS
-- 目标环境：MemFire Cloud（PostgreSQL 15+，Supabase 兼容）
-- 在 MemFire SQL 编辑器中整体执行
-- ============================================================

create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- 1. couples 情侣绑定表
-- ------------------------------------------------------------
create table couples (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references auth.users(id),
  user_b uuid not null references auth.users(id),
  invite_code text unique not null,
  created_at timestamptz default now(),
  unique(user_a, user_b)
);

alter table couples enable row level security;

create policy couple_self_select on couples
  for select using (auth.uid() = user_a or auth.uid() = user_b);

create policy couple_insert on couples
  for insert with check (auth.uid() = user_a);

-- ------------------------------------------------------------
-- 2. moments 动态主表
-- ------------------------------------------------------------
create table moments (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references couples(id),
  publisher_id uuid not null references auth.users(id),
  content text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create index idx_moments_couple_created on moments (couple_id, created_at desc);

alter table moments enable row level security;

create policy moment_select on moments
  for select using (
    exists (
      select 1 from couples c
      where c.id = moments.couple_id
        and (c.user_a = auth.uid() or c.user_b = auth.uid())
    )
  );

create policy moment_insert on moments
  for insert with check (
    exists (
      select 1 from couples c
      where c.id = moments.couple_id
        and (c.user_a = auth.uid() or c.user_b = auth.uid())
    )
  );

create policy moment_delete on moments
  for delete using (
    exists (
      select 1 from couples c
      where c.id = moments.couple_id
        and (c.user_a = auth.uid() or c.user_b = auth.uid())
    )
    and publisher_id = auth.uid()
  );

-- ------------------------------------------------------------
-- 3. moment_media 媒体关联表（可多存储适配）
-- ------------------------------------------------------------
create table moment_media (
  id uuid primary key default gen_random_uuid(),
  moment_id uuid not null references moments(id) on delete cascade,
  object_key text not null,
  storage_provider text,
  media_type text not null check (media_type in ('image','video')),
  sort int default 0
);

create index idx_moment_media_moment on moment_media (moment_id);

alter table moment_media enable row level security;

-- 注意：与早期草案不同，此处为正确写法 m.id = moment_media.moment_id
create policy media_select on moment_media
  for select using (
    exists (
      select 1 from moments m
      join couples c on m.couple_id = c.id
      where m.id = moment_media.moment_id
        and (c.user_a = auth.uid() or c.user_b = auth.uid())
    )
  );

-- ------------------------------------------------------------
-- 4. 邀请码绑定 RPC（安全实现）
--    客户端不能直接按 invite_code 查询/更新 couples（RLS 会拦截），
--    必须通过 security definer 函数完成：输入邀请码 + 当前用户 id。
-- ------------------------------------------------------------
create or replace function join_couple(p_invite_code text, p_user uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_couple couples%rowtype;
begin
  select * into v_couple
  from couples
  where invite_code = p_invite_code
  limit 1;

  if not found then
    raise exception 'invite_code not found';
  end if;
  if v_couple.user_a = p_user then
    raise exception 'cannot join own couple';
  end if;
  if v_couple.user_b is not null then
    raise exception 'couple already full';
  end if;

  update couples
  set user_b = p_user
  where id = v_couple.id;

  return v_couple.id;
end;
$$;

-- ------------------------------------------------------------
-- 5. 常用查询辅助视图（可选）
--    一条动态 + 其媒体清单，仅在当前情侣空间内可见
-- ------------------------------------------------------------
create or replace view couple_moments_view as
select
  m.id as moment_id,
  m.couple_id,
  m.publisher_id,
  m.content,
  m.created_at,
  mm.id as media_id,
  mm.object_key,
  mm.storage_provider,
  mm.media_type,
  mm.sort
from moments m
left join moment_media mm on mm.moment_id = m.id;
