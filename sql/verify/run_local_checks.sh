#!/usr/bin/env bash
# ------------------------------------------------------------
# 在本地 PostgreSQL 15+ 上验证 sql/schema.sql + sql/schema_v2.sql
#
# 用途：CHECK 约束 / RLS 策略 / 列级授权 / 触发器 / security_invoker 视图
#       是否按预期生效，含"必须失败"的反向用例。
# 不覆盖：PostgREST 的 HTTP 行为（内嵌 select、Prefer: return=representation）、
#         MemFire 的 JWT 签发，这些只能在真实实例上联调。
#
# 用法（需要一个已启动且可建库的 PG 15+）：
#   PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres \
#     bash sql/verify/run_local_checks.sh
# 可选 PSQL=/path/to/psql 指定客户端（Windows 免安装包常用）
#
# 脚本会 drop/create 名为 trace_verify 的库，勿指向生产实例。
# ------------------------------------------------------------
set -u

PSQL="${PSQL:-psql}"
DB="${VERIFY_DB:-trace_verify}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
export PGCLIENTENCODING=UTF8

PSQL="$PSQL -X -q -tA -v ON_ERROR_STOP=1"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n     -> %s\n' "$1" "$2"; }

# 注意：中文一律走 stdin，不要用 psql -c（Windows 下 argv 会按 ANSI 代码页转换）
su() { printf '%s\n' "$1" | $PSQL -d "$DB" -f - >/dev/null 2>&1 || { echo "seed failed: $1"; exit 1; }; }

as_user() {
  local uid="$1" sql="$2" role="${3:-authenticated}"
  $PSQL -d "$DB" 2>&1 <<SQL
begin;
set local role $role;
set local "request.jwt.claim.sub" = '$uid';
$sql
commit;
SQL
}

expect_value() {
  local desc="$1" uid="$2" sql="$3" want="$4" out rc
  out=$(as_user "$uid" "$sql"); rc=$?
  if [ $rc -ne 0 ]; then bad "$desc" "unexpected error: $(echo "$out" | head -2 | tr '\n' ' ')"; return; fi
  if [ "$out" = "$want" ]; then ok "$desc"; else bad "$desc" "want [$want] got [$(echo "$out" | tr '\n' '|')]"; fi
}

expect_fail() {
  local desc="$1" uid="$2" sql="$3" want="$4" role="${5:-authenticated}" out rc
  out=$(as_user "$uid" "$sql" "$role"); rc=$?
  if [ $rc -eq 0 ]; then bad "$desc" "expected $want but statement succeeded"; return; fi
  if [ -n "$want" ] && ! echo "$out" | grep -qiE "$want"; then
    bad "$desc" "expected [$want] got: $(echo "$out" | head -2 | tr '\n' ' ')"; return
  fi
  ok "$desc"
}

echo "== 建库 + 应用 schema =="
printf 'drop database if exists %s;\ncreate database %s;\n' "$DB" "$DB" | $PSQL -d postgres -f - >/dev/null 2>&1 \
  || { echo "无法创建 $DB，请检查连接参数与权限"; exit 1; }

# 最小 Supabase 兼容层：三个角色 + auth.users + 读 JWT sub 的 auth.uid()
su "do \$\$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin bypassrls; end if;
end \$\$;
create schema if not exists auth;
grant usage on schema auth to anon, authenticated, service_role;
create table if not exists auth.users (id uuid primary key);
create or replace function auth.uid() returns uuid language sql stable
as \$\$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid \$\$;"

$PSQL -d "$DB" -f "$REPO/sql/schema.sql" >/dev/null 2>&1 || { echo "schema.sql 执行失败"; exit 1; }
echo "  schema.sql ok"
$PSQL -d "$DB" -f "$REPO/sql/schema_v2.sql" >/dev/null 2>&1 || { echo "schema_v2.sql 执行失败"; exit 1; }
echo "  schema_v2.sql ok"
$PSQL -d "$DB" -f "$REPO/sql/schema_v2.sql" >/dev/null 2>&1 || { echo "schema_v2.sql 不幂等：第二次执行失败"; exit 1; }
echo "  schema_v2.sql 二次执行 ok（幂等）"

A=11111111-1111-1111-1111-111111111111
B=22222222-2222-2222-2222-222222222222
C=33333333-3333-3333-3333-333333333333
D=44444444-4444-4444-4444-444444444444
E=55555555-5555-5555-5555-555555555555
F=66666666-6666-6666-6666-666666666666
C1=c1000000-0000-0000-0000-000000000001
C2=c2000000-0000-0000-0000-000000000002
M1=a0000000-0000-0000-0000-000000000001
M2=a0000000-0000-0000-0000-000000000002
M3=b0000000-0000-0000-0000-000000000003
CM1=cc000000-0000-0000-0000-000000000001
CM2=cc000000-0000-0000-0000-000000000002
CM3=cc000000-0000-0000-0000-000000000003

echo "== 种子数据（以超级用户写入，绕过 RLS）=="
su "insert into auth.users(id) values ('$A'),('$B'),('$C'),('$D'),('$E'),('$F') on conflict do nothing"
su "insert into couples(id,user_a,user_b,invite_code,started_on) values
      ('$C1','$A','$B','INV00001','2024-02-14'),
      ('$C2','$C','$D','INV00002','2025-01-01') on conflict do nothing"
su "insert into moments(id,couple_id,publisher_id,content,location_text,location_lat,location_lng,created_at) values
      ('$M1','$C1','$A','一周年','西湖',30.24,120.15, now() - interval '2 hour'),
      ('$M2','$C1','$B','今天的晚饭',null,null,null, now() - interval '1 hour'),
      ('$M3','$C2','$C','别人的动态',null,null,null, now()) on conflict do nothing"
su "insert into moment_comments(id,moment_id,author_id,body) values
      ('$CM1','$M1','$A','我先评论'),
      ('$CM2','$M3','$C','别人家的评论'),
      ('$CM3','$M2','$B','晚饭看起来不错') on conflict do nothing"

echo
echo "== 绑定流程（v1 的 user_b not null 会卡死创建空间）=="
expect_value "E 创建空位空间（只写 user_a + invite_code）" "$E" \
  "insert into couples(user_a,invite_code) values ('$E','INV00005') returning invite_code;" "INV00005"
expect_value "F 用邀请码加入 E 的空间" "$F" \
  "select join_couple('INV00005','$F') is not null;" "t"
expect_value "加入后 E 看到伴侣字段已填" "$E" \
  "select user_b = '$F' from couples where invite_code='INV00005';" "t"
expect_fail "join_couple 传别人的 uuid" "$F" "select join_couple('INV00005','$E');" "forbidden"
expect_fail "join_couple 加入自己的空间" "$E" "select join_couple('INV00005','$E');" "cannot join own couple|forbidden"

echo
echo "== 多租户隔离 =="
expect_value "A 只看到自己的空间" "$A" "select count(*) from couples;" "1"
expect_value "A 只看到本空间动态" "$A" "select count(*) from moments;" "2"
expect_value "A 看不到别家动态" "$A" "select count(*) from moments where id='$M3';" "0"
expect_value "A 看不到别家评论" "$A" "select count(*) from moment_comments where id='$CM2';" "0"
expect_value "security_invoker 视图同样受限" "$A" "select count(distinct moment_id) from couple_moments_view;" "2"
expect_fail "anon 读不到 moments" "" "select count(*) from moments;" "permission denied" anon

echo
echo "== 动态编辑：作者可改 / 伴侣不可改 =="
expect_value "A 改自己的动态" "$A" "update moments set content='一周年快乐' where id='$M1' returning 1;" "1"
expect_value "updated_at 晚于 created_at（已编辑标记）" "$A" \
  "select updated_at > created_at + interval '1 second' from moments where id='$M1';" "t"
expect_value "A 同时写经纬度" "$A" "update moments set location_lat=30.25, location_lng=120.16 where id='$M1' returning 1;" "1"
expect_value "A 改不了伴侣的动态（0 行）" "$A" "update moments set content='篡改' where id='$M2' returning 1;" ""
expect_value "B 改自己的动态" "$B" "update moments set content='今晚吃面' where id='$M2' returning 1;" "1"
expect_fail "A 把 publisher_id 改成 B" "$A" "update moments set publisher_id='$B' where id='$M1';" "permission denied"
expect_fail "A 改 created_at" "$A" "update moments set created_at=now() where id='$M1';" "permission denied"
expect_fail "A 把动态挪到别的空间" "$A" "update moments set couple_id='$C2' where id='$M1';" "permission denied"
expect_fail "只写半个坐标" "$A" "update moments set location_lat=30.1, location_lng=null where id='$M1';" "violates check constraint"

echo
echo "== 动态创建：publisher 与空间归属 =="
expect_value "A 正常发一条" "$A" \
  "insert into moments(couple_id,publisher_id,content) values ('$C1','$A','新动态') returning 1;" "1"
expect_fail "A 伪造 publisher_id = B" "$A" \
  "insert into moments(couple_id,publisher_id,content) values ('$C1','$B','冒名');" "row-level security"
expect_fail "A 往别家空间发动态" "$A" \
  "insert into moments(couple_id,publisher_id,content) values ('$C2','$A','越权');" "row-level security"
expect_fail "A 直接写 user_b 完成绑定" "$A" \
  "insert into couples(user_a,user_b,invite_code) values ('$A','$B','HACK0001');" "row-level security"
expect_value "A 删不掉伴侣的动态" "$A" "delete from moments where id='$M2' returning 1;" ""
expect_value "A 删得掉自己的动态" "$A" "delete from moments where content='新动态' returning 1;" "1"

echo
echo "== 评论与回复 =="
expect_value "A 在伴侣动态下评论" "$A" \
  "insert into moment_comments(moment_id,author_id,body) values ('$M2','$A','好吃') returning 1;" "1"
expect_value "B 回复同一条动态下的评论" "$B" \
  "insert into moment_comments(moment_id,author_id,parent_id,body) values ('$M2','$B','$CM3','我也想吃') returning 1;" "1"
expect_fail "A 伪造 author_id = B" "$A" \
  "insert into moment_comments(moment_id,author_id,body) values ('$M1','$B','冒名');" "row-level security"
expect_fail "A 评论到别家动态下" "$A" \
  "insert into moment_comments(moment_id,author_id,body) values ('$M3','$A','越权');" "row-level security"
expect_fail "parent_id 指向别家评论" "$A" \
  "insert into moment_comments(moment_id,author_id,parent_id,body) values ('$M1','$A','$CM2','错挂');" "does not belong to this moment"
expect_fail "parent_id 指向同空间另一条动态的评论" "$A" \
  "insert into moment_comments(moment_id,author_id,parent_id,body) values ('$M2','$A','$CM1','错挂');" "does not belong to this moment"
expect_fail "评论正文超过 500 字" "$A" \
  "insert into moment_comments(moment_id,author_id,body) values ('$M1','$A',repeat('x',501));" "check constraint"
expect_fail "评论不允许编辑" "$A" "update moment_comments set body='改了' where id='$CM1';" "permission denied"
expect_value "动态作者删得掉伴侣的评论" "$B" "delete from moment_comments where body='好吃' returning 1;" "1"
expect_value "A 删不掉别家评论" "$A" "delete from moment_comments where id='$CM2' returning 1;" ""

echo
echo "== 在一起天数 / 纪念日 =="
expect_value "A 设置在一起的第一天" "$A" "update couples set started_on='2023-05-20' where id='$C1' returning 1;" "1"
expect_fail "A 改成员关系 user_a" "$A" "update couples set user_a='$C' where id='$C1';" "permission denied"
expect_fail "A 改邀请码" "$A" "update couples set invite_code='NEWCODE1' where id='$C1';" "permission denied"
expect_value "A 建纪念日" "$A" \
  "insert into anniversaries(couple_id,title,event_date,created_by) values ('$C1','恋爱纪念日','2023-05-20','$A') returning 1;" "1"
expect_value "B 能看到纪念日" "$B" "select count(*) from anniversaries where couple_id='$C1';" "1"
expect_value "A 看不到别家纪念日" "$A" "select count(*) from anniversaries where couple_id='$C2';" "0"
expect_fail "A 给别家建纪念日" "$A" \
  "insert into anniversaries(couple_id,title,event_date) values ('$C2','越权','2025-01-01');" "row-level security"
expect_fail "纪念日标题为空" "$A" \
  "insert into anniversaries(couple_id,title,event_date) values ('$C1','','2025-01-01');" "check constraint"

echo
echo "== 媒体（沿用 v1 策略）=="
expect_value "A 给自己的动态挂图" "$A" \
  "insert into moment_media(moment_id,object_key,media_type) values ('$M1','k/1.jpg','image') returning 1;" "1"
expect_fail "A 给伴侣的动态挂图" "$A" \
  "insert into moment_media(moment_id,object_key,media_type) values ('$M2','k/2.jpg','image');" "row-level security"
expect_fail "media_type 只允许 image/video" "$A" \
  "insert into moment_media(moment_id,object_key,media_type) values ('$M1','k/3.mp4','audio');" "check constraint"

echo
echo "== 汇总：PASS=$PASS FAIL=$FAIL =="
[ $FAIL -eq 0 ]
