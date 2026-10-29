-- ============================================================
-- Trace · 同迹 — Schema v2 增量迁移
-- 覆盖：动态可编辑 / 评论与回复 / 定位 / 纪念日
-- 前置：已执行 sql/schema.sql
-- 目标环境：MemFire Cloud（PostgreSQL 15+，Supabase 兼容）
-- 本文件幂等，可整体重复执行
-- ============================================================

-- ------------------------------------------------------------
-- 0. 依赖
-- ------------------------------------------------------------
create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- 1. moments 补列：定位
--    location_text 为手动输入（当前唯一必填路径）；
--    location_lat/lng 预留给后续地图 SDK，两者可空、不参与鉴权。
-- ------------------------------------------------------------
alter table moments add column if not exists location_text text;
alter table moments add column if not exists location_lat  double precision;
alter table moments add column if not exists location_lng  double precision;

-- 边界：只允许 (lat 与 lng 同时为空) 或 (同时非空)，避免半个坐标
alter table moments drop constraint if exists moments_location_pair;
alter table moments add constraint moments_location_pair
  check ((location_lat is null and location_lng is null)
      or (location_lat is not null and location_lng is not null));

-- ------------------------------------------------------------
-- 2. updated_at 由触发器维护
--    schema.sql 里只有 default now()，插入后不再变化；
--    加了触发器，"已编辑" 才有依据（updated_at > created_at）。
-- ------------------------------------------------------------
create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists moments_set_updated_at on moments;
create trigger moments_set_updated_at
  before update on moments
  for each row execute function set_updated_at();

-- ------------------------------------------------------------
-- 3. moments：作者可改自己的动态
--    using     校验旧行（只有作者本人能发起 UPDATE）
--    with check 校验新行（改完之后仍必须是「本人发布 + 本人情侣空间」，
--              防止把别人的动态改到自己名下或把动态挪进别的情侣空间）
-- ------------------------------------------------------------
drop policy if exists moment_update on moments;
create policy moment_update on moments
  for update using (
    publisher_id = auth.uid()
    and exists (
      select 1 from couples c
      where c.id = moments.couple_id
        and (c.user_a = auth.uid() or c.user_b = auth.uid())
    )
  ) with check (
    publisher_id = auth.uid()
    and exists (
      select 1 from couples c
      where c.id = moments.couple_id
        and (c.user_a = auth.uid() or c.user_b = auth.uid())
    )
  );

-- ------------------------------------------------------------
-- 4. 收紧 v1 的两处插入策略
--    v1 的 moment_insert 只校验了 couple 归属，没校验 publisher_id，
--    因此 A 可以伪造 publisher_id = B 发一条"是 B 说的"动态；
--    v1 的 couple_insert 没限制 user_b，因此可以跳过邀请码直接把
--    任意 uuid 写成伴侣。两处都补上。
-- ------------------------------------------------------------
drop policy if exists moment_insert on moments;
create policy moment_insert on moments
  for insert with check (
    publisher_id = auth.uid()
    and exists (
      select 1 from couples c
      where c.id = moments.couple_id
        and (c.user_a = auth.uid() or c.user_b = auth.uid())
    )
  );

drop policy if exists couple_insert on couples;
create policy couple_insert on couples
  for insert with check (
    user_a = auth.uid()
    and user_b is null
  );

-- v1 的 user_b 是 not null，但绑定流程是"发起方先建一个空位空间再等对方进来"：
-- 客户端创建时只写 user_a + invite_code，上面的 couple_insert 也要求 user_b 为空。
-- 两者必须同时成立，否则建空间这一步必然失败（null 违反 not null，
-- 或为了满足 not null 而绕过策略凭空写一个伴侣）。
alter table couples alter column user_b drop not null;

-- couples 的"在一起起始日"双方都可改
alter table couples add column if not exists started_on date;

drop policy if exists couple_update on couples;
create policy couple_update on couples
  for update using (
    auth.uid() = user_a or auth.uid() = user_b
  ) with check (
    auth.uid() = user_a or auth.uid() = user_b
  );
-- 成员关系与邀请码的不可篡改由第 8 节的列级授权保证：
-- 只授予 started_on 的 UPDATE 权限，user_a/user_b/invite_code 改不动。
-- （不要在策略里用子查询自比对新旧行：PG 的 WITH CHECK 在新元组已写入之后
--   才求值，自引用子查询读到的就是新值，条件恒真、形同虚设。）

-- ------------------------------------------------------------
-- 5. moment_comments 评论表
--    parent_id 自引用实现"回复评论"；一层自引用足够表达
--    朋友圈那种「评论 + 楼中楼」结构，不必做邻接路径。
-- ------------------------------------------------------------
create table if not exists moment_comments (
  id         uuid primary key default gen_random_uuid(),
  moment_id  uuid not null references moments(id) on delete cascade,
  author_id  uuid not null references auth.users(id),
  parent_id  uuid references moment_comments(id) on delete cascade,
  body       text not null check (char_length(body) between 1 and 500),
  created_at timestamptz default now()
);

create index if not exists idx_comments_moment on moment_comments (moment_id, created_at);
create index if not exists idx_comments_parent on moment_comments (parent_id);

-- parent_id 必须指向同一条动态下的评论，否则可以把评论挂到别人的动态上。
-- 跨行约束 CHECK 表达不了，用触发器。
create or replace function comment_parent_same_moment()
returns trigger
language plpgsql
as $$
begin
  if new.parent_id is not null then
    if not exists (
      select 1 from moment_comments p
      where p.id = new.parent_id
        and p.moment_id = new.moment_id
    ) then
      raise exception 'comment parent does not belong to this moment';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists comments_parent_guard on moment_comments;
create trigger comments_parent_guard
  before insert or update on moment_comments
  for each row execute function comment_parent_same_moment();

alter table moment_comments enable row level security;

-- 同情侣空间可见
drop policy if exists comment_select on moment_comments;
create policy comment_select on moment_comments
  for select using (
    exists (
      select 1 from moments m
      join couples c on c.id = m.couple_id
      where m.id = moment_comments.moment_id
        and (c.user_a = auth.uid() or c.user_b = auth.uid())
    )
  );

-- 只能以本人身份、在自己情侣空间的动态下评论
drop policy if exists comment_insert on moment_comments;
create policy comment_insert on moment_comments
  for insert with check (
    author_id = auth.uid()
    and exists (
      select 1 from moments m
      join couples c on c.id = m.couple_id
      where m.id = moment_comments.moment_id
        and (c.user_a = auth.uid() or c.user_b = auth.uid())
    )
  );

-- 评论作者可删自己的；动态作者可删自己动态下的任意评论
drop policy if exists comment_delete on moment_comments;
create policy comment_delete on moment_comments
  for delete using (
    author_id = auth.uid()
    or exists (
      select 1 from moments m
      where m.id = moment_comments.moment_id
        and m.publisher_id = auth.uid()
    )
  );

-- 评论不提供编辑：改评论会让"回复某条评论"的语义失真，删了重发即可

-- ------------------------------------------------------------
-- 6. anniversaries 纪念日（双方共享，必须放服务端）
--    主题色/字号/背景这类纯客户端观感偏好不放这里，
--    见第 10 节：每对独立部署，偏好走 --dart-define + 本地 Drift。
-- ------------------------------------------------------------
create table if not exists anniversaries (
  id         uuid primary key default gen_random_uuid(),
  couple_id  uuid not null references couples(id) on delete cascade,
  title      text not null check (char_length(title) between 1 and 40),
  event_date date not null,
  created_by uuid references auth.users(id),
  created_at timestamptz default now(),
  unique (couple_id, title, event_date)
);

create index if not exists idx_anniversaries_couple_date
  on anniversaries (couple_id, event_date);

alter table anniversaries enable row level security;

drop policy if exists anniversary_rw on anniversaries;
create policy anniversary_rw on anniversaries
  for all using (
    exists (
      select 1 from couples c
      where c.id = anniversaries.couple_id
        and (c.user_a = auth.uid() or c.user_b = auth.uid())
    )
  ) with check (
    exists (
      select 1 from couples c
      where c.id = anniversaries.couple_id
        and (c.user_a = auth.uid() or c.user_b = auth.uid())
    )
  );

-- ------------------------------------------------------------
-- 7. 辅助视图补齐新列（v1 视图缺 updated_at/location，
--    保留视图是为了给"一次拿动态+媒体"的老调用方兼容）
--    注意：新列插在了中间，列序与 v1 不同，
--    create or replace view 不允许改列序（会报 cannot change name
--    of view column），因此必须 drop + create，并补回授权。
-- ------------------------------------------------------------
drop view if exists couple_moments_view;

create view couple_moments_view
with (security_invoker = true) as
select
  m.id            as moment_id,
  m.couple_id,
  m.publisher_id,
  m.content,
  m.location_text,
  m.created_at,
  m.updated_at,
  mm.id           as media_id,
  mm.object_key,
  mm.storage_provider,
  mm.media_type,
  mm.sort
from moments m
left join moment_media mm on mm.moment_id = m.id;

-- ------------------------------------------------------------
-- 8. 表权限
--    列级 UPDATE 授权：即使策略写漏，客户端也改不了
--    couple_id / publisher_id / created_at 这类身份列。
-- ------------------------------------------------------------
revoke all on table moment_comments, anniversaries from anon;
revoke all on table moment_comments, anniversaries from public;

grant select, insert, delete on table moment_comments to authenticated;
grant select, insert, update, delete on table anniversaries to authenticated;

grant update (content, location_text, location_lat, location_lng)
  on table moments to authenticated;
grant update (started_on) on table couples to authenticated;

-- 视图被重建过，授权要跟着补回（drop view 会一并丢掉 ACL）
revoke all on table couple_moments_view from anon;
grant select on table couple_moments_view to authenticated;

-- ------------------------------------------------------------
-- 9. 自检（在 MemFire 里逐条跑，确认迁移生效）
-- ------------------------------------------------------------
-- 9.1 策略清单
-- select tablename, policyname, cmd from pg_policies
--  where schemaname='public' order by tablename, policyname;
--
-- 9.2 列级 UPDATE 权限
-- select table_name, privilege_type, column_name
--   from information_schema.column_privileges
--  where grantee='authenticated' and privilege_type='UPDATE';
--
-- 9.3 触发器
-- select tgname from pg_trigger where not tgisinternal
--  and tgrelid in ('moments'::regclass, 'moment_comments'::regclass);
--
-- 9.4 反向验证（必须失败才算通过）：
--   a) 以 A 身份 PATCH moments 把 publisher_id 改成 B   -> 42501/403
--   b) 以 A 身份 POST moments 带 publisher_id = B       -> RLS 违规
--   c) 以 A 身份 POST moment_comments 挂到 B 的动态下   -> 触发器报错
--   d) 以 A 身份 POST couples 直接写 user_b = B        -> RLS 违规

-- ------------------------------------------------------------
-- 10. 客户端个性化（不落库）
--     每对情侣独立部署一套实例，因此：
--       · 主题色 / 字号 / 背景图 -> 构建期 --dart-define + 本地 Drift prefs
--       · 纪念日、在一起天数     -> 上面的 anniversaries / couples.started_on
--     这样服务端只多两张表，RLS 面积最小。
-- ------------------------------------------------------------
