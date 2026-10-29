# UI / UX 开发指南

> 适用对象：后续接手界面的人（包括未来的自己）。
> 现状前提：**UI 只做到"基本可用"**，风格尚未定稿，交互细节没打磨。
> 本文的目标不是描述"现在长什么样"，而是把「怎么加页面、怎么换风格、怎么不踩坑」写清楚，让 UI 优化能小步快跑。

---

## 1. 代码地图

```
app/lib/
├── main.dart                 // 建库、读本地字号偏好、override 两个 provider
├── models/models.dart        // Couple / Moment / MomentMedia / MomentComment，只做解析
├── core/api_client.dart      // PostgREST 封装（dbGet/dbInsert/dbUpdate/dbRpc）
├── services/                 // 业务与网络：auth / couple / moment / media / cache / storage
├── db/                       // Drift 本地缓存（moments / comments / media / prefs）
└── ui/
    ├── theme.dart            // 唯一的设计令牌来源
    ├── app.dart              // MaterialApp + 路由表 + onGenerateRoute
    ├── providers.dart        // 依赖注入（改服务层只动这里）
    └── pages/
        ├── login_page.dart
        ├── bind_page.dart
        ├── timeline_page.dart      // 门禁 + 列表 + 媒体网格（组件也在这里）
        ├── publish_page.dart       // 发布 / 编辑共用
        ├── moment_detail_page.dart // 详情 + 评论 + 回复
        ├── preview_page.dart       // 图片全屏 / 视频内嵌播放
        └── settings_page.dart      // 情侣空间、在一起第一天、字号、清缓存
```

约定：

- **services 不认识 Widget，pages 不直接拼 URL / 不直接读 token。** 页面只调 provider 里的 service。
- 所有颜色从 `theme.dart` 取，页面里不写十六进制。（现存例外：`preview_page` 的黑底、`_Thumb` 的 `Colors.white` 播放角标，属于媒体语义色，可以保留）
- 一个页面的状态就用 `ConsumerStatefulWidget` 自管，不额外造全局 store；跨页面才需要共享的东西才进 provider。

---

## 2. 设计令牌

全部定义在 [`app/lib/ui/theme.dart`](../app/lib/ui/theme.dart)，改风格只改这一个文件。

| 令牌 | 值 | 用途 | 不要用在哪 |
| --- | --- | --- | --- |
| `paper` | `#F7F8F6` | 页面底色、AppBar 底色 | 卡片内部 |
| `surface` | `#FFFFFF` | 卡片 / 弹层表面 | 页面底色 |
| `ink` | `#1B1F1D` | 正文、标题、主按钮底色 | 次要说明文字 |
| `inkSoft` | `#6E7873` | 时间戳、地点、空态说明 | 正文（对比度不够） |
| `hairline` | `#DCE1DC` | 1px 描边、分割线、图片占位 | 强调 |
| `me` | `#C08A18` 琥珀 | "我"的作者点、作者名 | 大面积色块 |
| `partner` | `#2F5D8C` 靛蓝 | "TA"的作者点、链接、聚焦态 | 大面积色块 |
| `alert` | `#9E2B25` 砖红 | 删除等破坏性动作、错误文案 | 装饰 |

`TraceColors` 之外，`buildTraceTheme()` 还统一了这些组件的形态，页面里直接用默认样式即可：

| 组件 | 形态 |
| --- | --- |
| AppBar | 无阴影、纸色底、左对齐、墨色字 |
| Card | 白底、1px `hairline` 描边、**圆角 6**、无阴影、零外边距（间距由调用方 `margin` 给） |
| FilledButton | 墨底纸字、圆角 4 |
| OutlinedButton | 墨色描边 + 墨色字、圆角 4 |
| 输入框 | 1px `hairline` 描边、圆角 4、聚焦变 `partner` |
| Chip | 圆角 3 |

**间距没有做成令牌，用的是约定值**：页面左右 12，卡片内边距 14，卡片间距 12，元素间距 8/6/4，列表底部留 88（给 FAB 让位）。

---

## 3. 字号与三档缩放

- 正文 14 / 行高 1.55；时间戳与辅助信息 11–12；大数字（在一起天数）30、`FontWeight.w300`。
- 不要写死 `fontSize` 来表达层级，层级用 `Theme.of(context).textTheme.*`；只有"辅助信息"这类固定小字才用 `TextStyle(fontSize: 11|12)`，因为它们不随档位变化也更稳定。
- 三档 `TextScaleLevel`（small 0.9 / normal 1.0 / large 1.15）通过 `base.textTheme.apply(fontSizeFactor:)` 生效，设置在设置页写进本地 `prefs` 表，冷启动时由 `main.dart` 读出来。
- **注意**：写死的 `fontSize` 不会跟随档位缩放。新增写死字号时，问自己"这行字在大字号下需不需要变大"，需要就走 `textTheme`。

---

## 4. 页面现状

| 页面 | 路由 | 现状 |
| --- | --- | --- |
| 登录 | `/login` | 邮箱 + 密码，注册/登录两个按钮，错误信息内联显示 |
| 绑定 | `/bind` | 创建空间拿邀请码 / 输入邀请码加入 |
| 时光轴 | `/timeline` | 门禁（未建空间 / 等对方 / 载入失败 / 空态）→ 在一起天数 → 动态列表 |
| 发布 | `/publish` | 新建与编辑共用，`editing != null` 即编辑态（编辑态不能增删媒体） |
| 详情 | `/moment` | 文字 + 媒体 + 评论列表（parentId 分组显示楼中楼）+ 回复栏 |
| 预览 | `/preview` | 图片可缩放；视频用 `video_player` 内嵌播放（含播放/暂停、进度条、失败重试），**未在真机验证** |
| 设置 | `/settings` | 情侣空间信息、在一起第一天、字号、清缓存、退出登录 |

---

## 5. 组件清单（可复用件）

现有组件都是页面内私有类（`_` 前缀），复用时**先提升到 `ui/widgets/` 再改**，不要跨文件引用私有类。

| 组件 | 位置 | 职责 | 扩展点 |
| --- | --- | --- | --- |
| `_Gate` | timeline | 居中提示块：标题 + 说明 + 可选大号邀请码 + 主按钮 | 加次级按钮、加插图 |
| `_DaysHeader` | timeline | "第 N 天"大数字 | 换成倒计时/纪念日卡片 |
| `_MomentCard` | timeline | 作者点 + 时间 + 正文 + 媒体 + 地点 + 评论数 + 已编辑 + 编辑/删除 | 加点赞、加"那年今天"入口 |
| `MediaGrid` | timeline（公开） | 3 列缩略图，视频叠播放角标，点击进预览 | 改成 1/4/9 宫格、加长按保存 |
| `_Thumb` | timeline | 签名 URL → 图片，加载/失败占位 | 换成 `CachedNetworkImage` |
| `_Dot` | moment_detail | 作者色小圆点 | — |
| `_CommentRow` | moment_detail | 单条评论/回复 | 加删除按钮、加 @ |
| `_CommentBar` | moment_detail | 底部输入 + 回复态提示 + 取消回复 | 加表情、加图片评论 |

新增组件放 `ui/widgets/`，命名不带页面前缀，颜色只用 `TraceColors`。

---

## 6. 新增一个页面的 checklist

1. 文件放 `ui/pages/xxx_page.dart`，`ConsumerStatefulWidget`（需要读 provider）或 `StatelessWidget`（纯展示）。
2. 页面里**不建 Dio、不读 token**，需要什么从 `ref.read(xxxServiceProvider)` 取。
3. 路由：静态无参页加进 `app.dart` 的 `routes`；带参数页加进 `onGenerateRoute`，参数用具体类型判断（参考 `/publish` 用 `Moment?`、`/preview` 用 `Map<String,String>`），**不要 `as` 强转**，拿到错类型就返回 `null`。
4. 状态三件套必须齐：加载中（`CircularProgressIndicator`）、空态（`_Gate` 风格）、错误态（可重试）。离线时回退本地 Drift 缓存（参考 `_loadMoments`）。
5. 破坏性操作一律 `AlertDialog` 二次确认，确认按钮用 `FilledButton`，取消用 `TextButton`。
6. 列表页记得底部留 88（FAB 让位），`RefreshIndicator` 包住 `ListView` 且给 `AlwaysScrollableScrollPhysics`。
7. 跑 `flutter analyze --no-fatal-infos` 和 `flutter test`，两者都过再提交。

---

## 7. 换风格：只改 `theme.dart`

当前落地的是 **S1「双轨」的双人配色**（自己琥珀 / 对方靛蓝）+ 中性纸色。双轨版式（中缝刻度、左右分栏）需要 `CustomPaint`，等 UI 优化阶段再评估。

五套风格稿的色板（按原稿顺序，语义以原稿标注为准；S4/S5 稿上没标语义，落地时自己指派）：

| 风格 | 色板（原稿顺序） | 语义 | 备注 |
| --- | --- | --- | --- |
| S1 双轨 | `#EDF0EE` `#16202A` `#2F5D8C` `#C08A18` `#A03A4E` `#C8D2CC` | 纸白 / 墨蓝 / 靛蓝（对方）/ 姜黄（自己）/ 绛红（提醒）/ 细线 | 冷静克制，归属靠左右轨道 + 颜色 |
| S2 夜航 | `#141A24` `#1B2330` `#F2C46B` `#8FB6B0` `#E0A0A8` `#E9ECF2` | 夜底 / 卡片 / 暖光黄（我）/ 雾青（TA）/ 雾粉（纪念日）/ 月白字 | **深色**，正文 12:1 对比度；小字另有 `#A9B6C9` |
| S3 手账 | `#F4F6F5` `#1D1F1E` `#C33A2E` `#D9C9A8` `#BBD4CB` `#6C7A72` | 冷白底 / 墨 / 印章红 / 牛皮纸 / 胶带青 / 铅笔灰 | 纸感，配楷体标题 |
| S4 极简 | `#F7F8F6` `#1B1F1D` `#9E2B25` `#DCE1DC` `#6E7873` `#FFFFFF` | 未标注 | 当前 `theme.dart` 的纸色与墨色来自这套 |
| S5 留白 | `#FFFFFF` `#1B1E1C` `#2F5D8C` `#F4F6F3` `#E3E6E2` `#7A817C` | 未标注 | 大留白，信息密度最低 |

> 当前 `theme.dart` 是混搭：作者色取 S1（琥珀 `#C08A18` / 靛蓝 `#2F5D8C`），纸色墨色取 S4（`#F7F8F6` / `#1B1F1D`）。定稿时统一到一套即可，不影响组件代码。

操作步骤：

1. 改 `TraceColors` 的六个常量（语义名不变，只换值）。
2. 改 `ColorScheme.fromSeed(seedColor: ...)` 的种子色，`brightness` 跟着定。
3. 深色风格（S2）**不能只换颜色**：还要 `brightness: Brightness.dark`、`surfaceTintColor` 全透明、`ink` 变浅色并且用于正文（此时 `ink` 不再是"墨"，而是"前景"），`surface` 要比 `paper` 更亮一档表达层级。建议先把 `TraceColors` 改成语义名（`fg` / `fgSoft` / `bg` / `bgElevated`），再套色板。
4. 换完跑一遍时光轴 + 详情 + 发布三页的真机/模拟器截图，重点看：作者色在深底上的对比度、`hairline` 描边是否还看得见、按钮反色是否成立。

---

## 8. 数据 → 视觉的约定

| 视觉 | 数据来源 | 规则 |
| --- | --- | --- |
| "我 / TA" + 颜色 | `moment.publisherId` vs `auth.currentUserId` | `authorColor()` / `isMine()`，不要在页面里重复写三元 |
| "已编辑" | `Moment.isEdited` | `updatedAt > createdAt + 1s` 才算，容忍时钟抖动 |
| 时间 | `formatMomentTime()` | 今年只显示 `MM-DD HH:mm`，跨年补年份 |
| 第 N 天 | `couple.startedOn` | 含首日（`+1`）；未设置时不显示数字，提示去设置页补 |
| 缩略图 | `CacheService.signedUrl(objectKey)` | 内存缓存签名 URL，**不要**每次 build 直接调 `getDownloadSign` |
| 视频 | `mediaType == 'video'` | 网格里只叠播放角标；播放在预览页 `_VideoView`（`VideoPlayerController.networkUrl`，切后台自动暂停，初始化失败显示重试） |

---

## 9. 常见坑

1. **签名 URL 有有效期。** 页面里直接 `FutureBuilder(getDownloadSign(...))` 会在过期后 403。统一走 `CacheService.signedUrl()`（带内存缓存），过期重建时它自己会刷。
2. **`Image.network` 在断网时是白块。** 必须给 `errorBuilder` 和 `loadingBuilder`（或底色占位），否则看起来像 UI 崩了。
3. **`ListView` 里套 `GridView` 必须 `shrinkWrap: true` + `NeverScrollableScrollPhysics`**，否则滚动冲突或直接报 unbounded height。`MediaGrid` 已经处理。
4. **键盘弹出会顶掉评论输入框。** 详情页目前靠 `Scaffold` 默认 `resizeToAvoidBottomInset`，长列表下定位不准，后续可换 `bottomSheet` + `viewInsets`。
5. **深色模式没有做。** 现在只有 `Brightness.light`，系统切深色时 App 仍是浅色（这是刻意的，不是 bug）。做深色要按第 7 节第 3 步改语义令牌。
6. **写死 `fontSize` 不跟随字号档位**（见第 3 节）。
7. **`Card` 默认有外边距。** 已在 theme 里置零，页面里用 `margin:` 显式给间距，别依赖默认值。
8. **时间显示一律 `toLocal()`。** 服务端返回 UTC，直接格式化会差 8 小时。
9. **不要用 `MediaQuery.textScaleFactor` 覆盖用户设置**，我们已经有自己的三档；混用会双重放大导致布局溢出。

---

## 10. 待做的 UI 工作（按建议顺序）

1. **视频播放的真机验证**：解码、横竖屏、宽高比、大文件缓冲都只能在真机上看；目前只在测试里验证了「初始化失败 → 提示 + 重试」这一条降级路径。离线观看（`CacheService.resolve()` 先落盘再播）也还没接。
2. **空态与首次使用引导**：现在四种空态都是同一个 `_Gate` 样式，可以区分（未建空间给插图、等对方时给"复制邀请码"按钮）。
3. **日历视图 / 心情打卡 / 那年今天**：数据侧 `anniversaries` 表已就绪，`moment_comments` 已在本地缓存；心情打卡与主题偏好属于纯客户端，走本地 `prefs`。
4. **地图 SDK**：`moments.location_lat/lng` 已预留并有 `(lat,lng)` 同空的约束，接入时先做"能选点"再考虑逆地理编码；无 SDK 时降级为现有手动输入。
5. **深色模式 / 风格定稿**：见第 7 节。
6. **真机走查**：媒体上传链路目前只过了单元测试，图片压缩、大视频、弱网重试都没在真机上跑过。

---

## 11. 验收方式

```bash
cd app
flutter analyze --no-fatal-infos     # 只允许既有的 prefer_initializing_formals info
flutter test                         # 改动 UI 后必须全绿
```

UI 改动无法只靠测试保证，提交前至少手动走一遍：登录 → 建空间 → 等对方/绑定 → 发一条带图动态 → 编辑 → 评论 → 回复 → 删除 → 断网看缓存。
