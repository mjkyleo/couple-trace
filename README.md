# Trace · 同迹

> 双人私密时光记录 App ｜ 完整开源方案（极简 · 稳定 · 可扩展 · 多存储厂商适配）

<p align="center">
  <b>记录两个人的专属轨迹</b>
</p>

## 一、项目简介

**Trace（同迹）** 是一款专为情侣设计的 **私密双人时光记录 App**。

核心定位：

- 仅 **两人可见** 的私密朋友圈
- 支持每日文字日记、图片、短视频记录
- 极简干净、无社交、无陌生人
- **无自建后端服务器**
- **对象存储可插拔**：支持腾讯 COS / 阿里云 OSS / AWS S3 / MinIO 自由切换
- 本地缓存 + 云端双同步，支持离线浏览
- 完全开源、轻量、可自用、可二次开发

设计理念：

> 基础足够简单，架构足够灵活，不过度设计，预留全部扩展空间。

## 二、整体架构

```
Flutter 客户端（全平台）
        ↓  统一固定 API（不绑定任何厂商）
MemFire 云函数（鉴权 + 适配层）
        ↓  可插拔存储适配器
对象存储（COS / OSS / S3 / MinIO 任选其一）

MemFire PostgreSQL（唯一权威数据源）
本地 SQLite Drift（离线缓存）
```

架构优势：

1. **无后端服务器**，零运维、零压力
2. **数据库稳定不变**，长期可用
3. **存储层完全抽象**，随时切换云厂商
4. **客户端完全无感知存储厂商**，业务代码无需改动
5. **权限在数据库层锁死**，绝对私密
6. **所有密钥托管云端**，客户端无任何密钥泄露风险

## 三、功能 MVP

### 基础核心功能

已实现（代码可跑通，接口与缓存链路完整）：

- 用户注册/登录（邮箱）
- 情侣专属空间绑定（邀请码机制 + 数据库 RPC 安全绑定）
- 每日文字动态记录、动态删除（云端与本地同步移除）
- 时间轴时光流展示 + 下拉刷新同步（双端各自刷新后一致，非 Realtime 推送）
- 离线浏览（断网时读取 Drift 本地缓存）
- 云函数签名 URL 换取 + 直传/直下封装（`StorageService`）
- 本地媒体缓存目录与手动清理缓存

待接入（MVP 骨架已留好，UI 尚未接真机能力）：

- 图片/视频选择与上传（需 `image_picker`，当前发布页为文字专用）
- 上传前自动压缩（`flutter_image_compress` / `video_compress` 已在依赖中，未调用）
- 视频播放（`video_player` 已在依赖中，预览页仅占位）
- 时间轴加载媒体清单（`moment_media` 查询与展示）
- 预览优先读本地缓存（当前直接走签名 URL）
- 删除动态时一并清理云端媒体文件

### 安全特性

- 全局私有存储桶，文件不可公开访问
- 所有文件采用 **限时签名 URL** 访问
- 数据库 RLS 行级权限隔离，外人 0 权限读取
- 服务端统一鉴权，防止越权操作
- 防路径穿越、防恶意上传

## 四、技术栈

| 分层 | 选型 | 说明 |
|---|---|---|
| 客户端 | Flutter | 跨端 Android / iOS |
| 本地缓存 | Drift (SQLite) | 强类型本地缓存 |
| 状态管理 | Riverpod | 轻量、易维护 |
| 网络 | Dio | 统一 HTTP 客户端 |
| 媒体压缩 | flutter_image_compress / video_compress | 上传前压缩 |
| BaaS | MemFire Cloud | PostgreSQL + Auth + 云函数，国内可访问 |
| 对象存储 | COS / OSS / S3 / MinIO | 可插拔，自由切换 |

## 五、数据流设计

1. **登录绑定流程**
   - 用户邮箱登录
   - A 生成邀请码 → B 输入邀请码
   - 绑定成功生成唯一 `couple_id`
2. **发布动态流程**
   - 本地压缩图片/视频
   - 云函数获取上传预签名 URL
   - 直传文件到对象存储
   - 写入 PostgreSQL 动态、媒体记录
3. **浏览流程**
   - 联网：从云端拉取最新数据 → 覆盖本地缓存
   - 离线：直接读取本地缓存
4. **媒体加载流程**
   - 预览页当前直接请求签名下载 URL 加载（本地缓存优先读取待接入）
   - `CacheService.resolve()` 已实现「有缓存则本地读取、无缓存则签名下载并落盘」，目前 UI 仅接入手动清理缓存，预览还未调用它
5. **删除流程**
   - 删除云端数据库记录（`moment_media` 由外键级联删除）
   - 删除本地缓存记录
   - 云端媒体文件删除尚未接入 UI（云函数 `delete_object` 接口已就绪）

## 六、数据库设计

> 完整可执行脚本见 [`sql/schema.sql`](sql/schema.sql)，在 MemFire SQL 编辑器直接执行。
> 复用 MemFire 自带 `auth.users`，不重复造登录表。

### 1. `couples` 情侣绑定表

```sql
create table couples (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references auth.users(id),
  user_b uuid not null references auth.users(id),
  invite_code text unique not null,
  created_at timestamptz default now(),
  unique(user_a, user_b)
);

alter table couples enable row level security;
create policy couple_self_select on couples for select using (auth.uid() = user_a or auth.uid() = user_b);
create policy couple_insert on couples for insert with check (auth.uid() = user_a);
```

### 2. `moments` 动态主表

```sql
create table moments (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references couples(id),
  publisher_id uuid not null references auth.users(id),
  content text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table moments enable row level security;
create policy moment_select on moments for select using (
  exists (select 1 from couples c where c.id = moments.couple_id and (c.user_a = auth.uid() or c.user_b = auth.uid()))
);
create policy moment_insert on moments for insert with check (
  exists (select 1 from couples c where c.id = moments.couple_id and (c.user_a = auth.uid() or c.user_b = auth.uid()))
);
create policy moment_delete on moments for delete using (
  exists (select 1 from couples c where c.id = moments.couple_id and (c.user_a = auth.uid() or c.user_b = auth.uid()))
  and publisher_id = auth.uid()
);
```

### 3. `moment_media` 媒体关联表（可多存储适配）

```sql
create table moment_media (
  id uuid primary key default gen_random_uuid(),
  moment_id uuid not null references moments(id) on delete cascade,
  object_key text not null,
  storage_provider text,
  media_type text not null check (media_type in ('image','video')),
  sort int default 0
);

alter table moment_media enable row level security;
create policy media_select on moment_media for select using (
  exists (
    select 1 from moments m join couples c on m.couple_id = c.id
    where m.id = moment_media.moment_id
    and (c.user_a = auth.uid() or c.user_b = auth.uid())
  )
);
-- 只允许给自己发布的动态挂媒体；删除限本人情侣空间
create policy media_insert on moment_media for insert with check (
  exists (
    select 1 from moments m join couples c on m.couple_id = c.id
    where m.id = moment_media.moment_id
      and m.publisher_id = auth.uid()
      and (c.user_a = auth.uid() or c.user_b = auth.uid())
  )
);
create policy media_delete on moment_media for delete using (
  exists (
    select 1 from moments m join couples c on m.couple_id = c.id
    where m.id = moment_media.moment_id
      and (c.user_a = auth.uid() or c.user_b = auth.uid())
  )
);
```

> 客户端 `MomentService.addMedia` 会向 `moment_media` 写入，因此该表必须有 insert 策略；
> 只有 select 策略时，写媒体记录会被 RLS 直接拒绝。

### 4. 绑定 RPC 与辅助视图的权限约束

```sql
-- join_couple 是 security definer（需要绕过 RLS 更新 user_b），
-- 因此必须自校验调用者，否则任何人都能替任意 uuid 完成绑定：
if p_user is distinct from auth.uid() then
  raise exception 'forbidden: can only join couple for the authenticated user';
end if;

revoke execute on function join_couple(text, uuid) from public, anon;
grant execute on function join_couple(text, uuid) to authenticated;

-- 视图必须以调用者身份执行，否则会以 owner（BYPASSRLS）权限读取全表
create or replace view couple_moments_view
with (security_invoker = true) as
select ...;
```

## 七、云函数多存储适配架构

### 统一对外接口（永久不变）

客户端只调用 3 个通用接口，**完全不感知云厂商**：

```
POST /storage/get_upload_sign
POST /storage/get_download_sign
POST /storage/delete_object
```

统一入参：

```json
{ "objectKey": "couple-uuid/xxx.jpg" }
```

统一返回：

```json
{ "url": "签名链接" }
```

### 存储适配器抽象接口

```ts
export interface StorageProvider {
  getUploadUrl(key: string, expireSeconds: number): Promise<string>;
  getDownloadUrl(key: string, expireSeconds: number): Promise<string>;
  delete(key: string): Promise<void>;
}
```

### 支持厂商列表

| 厂商 | 实现文件 | 说明 |
|---|---|---|
| 腾讯 COS | `storage-functions/src/cos.ts` | 国内首选 |
| 阿里云 OSS | `storage-functions/src/oss.ts` | 国内备选 |
| AWS S3 | `storage-functions/src/s3.ts` | 全球区域 |
| MinIO | `storage-functions/src/s3.ts` | 本地开发 / 私有化，S3 协议兼容 |

### 切换方式

**仅修改环境变量 `STORAGE_PROVIDER`**，无需改代码、无需改前端、无需改数据库：

```env
STORAGE_PROVIDER=cos   # 可选：cos / oss / s3 / minio
```

### 鉴权相关环境变量（必填，缺失即拒绝服务）

| 变量 | 作用 | 缺失时的行为 |
|---|---|---|
| `TRACE_JWT_SECRET` | 用 MemFire/Supabase 项目 JWT 密钥对 Bearer token **验签**（HS256），取 `sub` 作为用户 id | 所有请求 401；不会退化成「只解码不验签」 |
| `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` | 校验 `objectKey` 前缀的 coupleId 确实属于当前用户 | 请求以 500 `auth_check_failed` 拒绝 |
| `TRACE_ALLOW_INSECURE_DEV_AUTH=1` | 本地开发开关：允许无签名 token 与 `X-Trace-User-Id` 头 | 默认关闭；**生产开启等于任何人都能冒充任意用户** |

完整模板见 [`storage-functions/.env.example`](storage-functions/.env.example)。

## 八、客户端架构

### 核心模块

1. `AuthService` 登录认证
2. `CoupleService` 情侣绑定管理
3. `MomentService` 动态数据管理
4. `StorageService` 统一存储接口（无厂商依赖）
5. `LocalCache` Drift 本地离线缓存

### StorageService 核心封装

真实实现见 [`app/lib/services/storage_service.dart`](app/lib/services/storage_service.dart)，
签名请求统一走 `ApiClient`（负责注入 JWT 与云函数地址）：

```dart
class StorageService {
  StorageService(this._api);
  final ApiClient _api;

  Future<String> getUploadSign(String objectKey) async {
    final res = await _api.storageCall(
      '/storage/get_upload_sign', {'objectKey': objectKey});
    return res['url'] as String;
  }

  Future<void> upload(String objectKey, List<int> bytes) async {
    final url = await getUploadSign(objectKey);
    await _api.uploadToSignedUrl(url, bytes);
  }

  // getDownloadSign / download / deleteObject / buildObjectKey 同理
}
```

> 写库接口 `ApiClient.dbInsert` 带 `Prefer: return=representation`：
> PostgREST 默认返回空响应体，缺这个头会让创建类流程在解析返回值时直接抛异常。

### 页面结构（MVP 极简）

- 登录页
- 情侣绑定页
- 时光轴主页
- 发布动态页
- 媒体预览页
- 设置页

## 九、缓存策略

1. 所有媒体文件缓存至 App 沙盒目录
2. 已缓存文件优先本地读取，节省流量、提升速度
3. 数据库数据优先云端，本地仅做缓存
4. MVP 仅提供**手动清理缓存**
5. 不做过度自动清理，保证稳定性

## 十、安全体系

1. 全部存储桶私有，禁止公开访问
2. AK/SK 全部存放云函数环境变量
3. 客户端**无任何密钥**
4. 所有文件访问均为**限时签名 URL**（上传 15 分钟 / 下载 30 分钟）
5. 数据库 RLS 严格双人隔离；辅助视图带 `security_invoker`，绑定 RPC 校验 `auth.uid()`
6. 云函数对 Bearer token **验签**后才认领身份，密钥缺失或签名不符一律 401；
   情侣空间归属校验依赖的 Supabase 环境变量缺失时报错拒绝，而非默认放行
7. 服务端校验 `objectKey` 字符集与路径合法性（拦 `..`、拦首尾斜杠、限长度）；
   文件大小与 MIME 类型校验依赖桶策略/预签名约束，**尚未在云函数内实现**

## 十一、成本测算

| 阶段 | 项目 | 费用 |
|---|---|---|
| 开发阶段 | MemFire 免费额度 + MinIO 本地 | 0 元 |
| 正式使用（双人） | 数据库（免费/小额） | 0 ~ 十几元/月 |
| 正式使用（双人） | 对象存储 | 50 ~ 200 元/年 |
| **全年总成本** | | **200 ~ 300 元封顶** |

## 十二、测试

```bash
# 云函数类型检查 + 单元测试（Node >= 18）
cd storage-functions
npm install
npm run build
npm test

# Flutter 客户端静态检查 + 单元测试
cd ../app
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # 生成 Drift 的 .g.dart，缺了 test 编译不过
flutter analyze
flutter test
```

上述四项（云函数 build/test + Flutter analyze/test）已作为 CI 门禁跑在
[`verify` job](.github/workflows/build-apk.yml) 中：任一项失败都不会继续构建 APK。

## 十三、开发步骤

1. 注册 MemFire Cloud，开启邮箱登录
2. 执行 [`sql/schema.sql`](sql/schema.sql)，验证 RLS 权限
3. 部署云函数多存储适配器（`storage-functions/`）
4. 配置对应存储厂商环境变量（参考 `.env.example`）
5. Flutter 初始化项目、依赖引入（`app/`）
6. 完成登录、情侣绑定逻辑
7. 完成动态文字 CRUD
8. 接入存储上传、下载、缓存
9. 双人真机联调、断网测试、权限测试
10. 美化 UI、发布开源版本

## 十四、二期可扩展功能

- 实时 Realtime 自动刷新
- 动态点赞、评论
- 纪念日倒计时
- 心情打卡
- 自动 LRU 缓存清理
- 图片缩略图自动生成
- 大视频断点续传
- 数据一键导出备份
- 桌面小组件

## 十五、开源适配说明

> **仓库内容说明**：本仓库包含全部源码、数据库脚本与文档；不包含 Flutter 平台二进制资源（Android/iOS 应用图标、`gradle-wrapper.jar`）与锁文件。
> Fork 后按以下步骤补齐即可构建：
>
> ```bash
> # 1) 补齐 Flutter 平台目录（自动生成图标占位与 gradle wrapper）
> cd app && flutter create . --platforms android,ios
> # 2) 安装依赖
> flutter pub get
> # 3) 生成 Drift 本地缓存代码（.g.dart）
> dart run build_runner build
> # 4) 云函数依赖
> cd ../storage-functions && npm install
> ```

任何人 Fork 本项目后仅需：

1. 自己注册 MemFire
2. 自己注册对象存储（自选厂商）
3. 修改云函数环境变量

即可**一键部署属于自己的双人私密记录 App**。

## License

[MIT](LICENSE) © Trace Contributors
