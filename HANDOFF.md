# RomanceCharm 交接文档（2026-09-05）

## 项目是什么

Brotato（土豆兄弟，含深海魔怪 DLC）的本地 mod「SuperCharm」（旧名 RomanceCharm，v45 改名），增强魅惑机制。
源码：`D:\BrotatoMods\RomanceCharm\`（**仓库根目录即 mod 源码**：manifest.json/mod_main.gd/icon.png/content/effects；pack.sh 打包时用临时目录拼出 `mods-unpacked/Crystalhihihi-SuperCharm/` 结构。项目根目录名仍是 RomanceCharm，懒得动）
打包安装：项目根目录 `bash pack.sh`（**游戏必须先关闭**，否则 zip 被占用写入失败），
会生成 zip 到 `D:\SteamLibrary\steamapps\workshop\content\1942280\3796234584\RomanceCharm.zip`。

**重要**：这个游戏只扫描「已订阅工坊条目」的文件夹里的 zip（加载器逻辑见
`load_steam_workshop_zips`，只认 `int(文件夹名) in 已订阅列表`）。

**已发布**：工坊条目现状（2026-09-06 晚，上传时 ID 栏留空导致新建了两个条目）：
- **3796762706 = 当前正式条目**，内容 = v32（1.0.32，md5 076e2b33bd9d9b7b65b6032a0133d22f，
  已与本地 zip 逐字节核对一致），本地工坊文件夹已同步，游戏实际加载的就是它
- 3796234584 = 最初条目（旧内容，本地已不在订阅文件夹里）
- 3796761447 = 重复创建的条目（没订阅没下载）
- **待办：上 Steam 工坊页把 3796234584 和 3796761447 删除/隐藏，只留 3796762706**
- 也可反向操作：想用回旧 ID 就往 3796234584 传 v32（**ID 栏必须填**，留空 = 新建条目），
  删掉两个新条目，重新订阅旧条目
更新 mod 流程：改代码 → 打包（`bash pack.sh`，游戏需关闭）→
GodotWorkshopUtility 内容选 publish/ 里的 zip + preview.png，**ID 栏填 3796762706** 点 Upload。
注意：条目更新后 Steam 会重新下载覆盖工坊文件夹的 zip。
另：发布前在游戏目录建了 `steam_appid.txt`（内容 1942280），是工具初始化的前提。
描述文案在 `publish/description.txt`（中英双语，含双币）。
**已开源**：GitHub `Crystalhihihi/Brotato-SuperCharm`（main 分支，MIT；README 中英双语，
截图在 screenshots/）。本地 git 为 github.com 配了仓库级代理 `127.0.0.1:7897`（直连不通；
代理没开时 push 失败就 `git config --unset http.proxy && git config --unset https.proxy`）。
**commit message 用短句**（如 `v46：修简中标签`）：GitHub 文件列表每行都显示该文件最后
一次提交的信息，长消息被截断成一排省略号，很乱。
**上传 zip 的文件名会成为条目标题**（3796762706 的标题就是 22:37 传
"超级魅惑 SuperCharm.zip" 时变的；详情页标题渲染有服务端缓存，改后要等几小时才刷新）。
标题想保持「超级魅惑 SuperCharm」就上传 `publish/超级魅惑 SuperCharm.zip`。
**本地实测捷径**（跳过上传）：把新 zip 覆盖到
`D:\SteamLibrary\steamapps\workshop\content\1942280\3796762706\` 即可直接开游戏测——
注意该文件夹里**同时只能存在一个 zip**（加载器 `load_zips_in_folder` 会加载文件夹里
所有 zip，两个 zip 会重复加载/按序覆盖，结果不可控）。**且 Steam 会按上次上传的
文件名重新下载该条目内容**（上次传的是"超级魅惑 SuperCharm.zip"，Steam 就按这个名
存盘）→ 本地覆盖时用**同名文件**覆盖，别用别的名字塞进去，否则 Steam 校验后会把自己
那份再下回来，变成两个 zip。

## mod 当前功能（v50 / manifest 1.0.50，已打包并覆盖本地工坊文件夹 3796762706（文件名"超级魅惑 SuperCharm.zip"）；**尚未推 Steam**，推送用 GodotWorkshopUtility + ID 3796762706 + publish/超级魅惑 SuperCharm.zip）

**⚠ 最新状态（2026-09-15 深夜，用户已睡，下次从这继续）**：
魅惑 boss 死亡调查**未结**。已确认的事实：
- 复活 boss 不再被 area 路径瞬秒（一帧窗修复有效），但战斗中仍被**玩家归因的
  不明伤害**打死：死因日志 `killed_by_player_index` 出现 **0 和 1 两种**（单人局！
  player_index 合法取值只有 敌=-1 / 玩家=0 / DUMMY=123，**1 来源不明**），
  blow 从 81（波 23）到 617k（波 48+）都有；by_player=123（敌方集火）是正常死法。
- 已部署**探针包**（21:01 打包，zip 已覆盖工坊文件夹）：`effects/rc_boss_probe.gd`
  挂在魅惑 boss 的 effect_behaviors 上，on_taken_damage 抓**所有** take_damage
  路径（含绕过 hurtbox 的直伤），日志前缀 "BOSS PROBE"（记 hitbox 层/from/
  from_player_index）。**但用户当前对局（21:01:02 启动）和写包撞车，日志里
  BOSS PROBE=0 条 → 探针没加载。下次必须让用户完全退出游戏再启动，打到
  45+ 波死几个魅惑 boss，读日志里的 BOSS PROBE 行即可定位凶手。**
- 同包改动：复活 boss 死亡点离玩家 <500px 时改地图边缘生成（与磁石一致）。
- **发布 Steam 前清理调试件**：`effects/rc_boss_probe.gd`（探针）、
  `_scan` 的 hurtbox 自愈日志（"hurtbox reverted, repairing"）、
  hurtbox area_entered 诊断（"ALLY HIT BY PLAYER-SIDE"）、
  "charmed boss died" 死因日志 —— 视情况删/留（纯日志无副作用，但刷屏）。
- vanilla 全部 take_damage 调用点已穷举：hurtbox 路径、player.gd:457 闪避反击
  （hitbox.from.take_damage，唯一绕过 hurtbox 的玩家归因路径，但魅惑怪 1024
  撞不到玩家、理论上触发不了）、替罪羊自残。QMtato/Brotils/FishHook/UnlockAll
  已排查无相关直伤（QMtato 直伤都是其自定义角色专属）。
- 探针方法论（重要）：`Brotato.exe -s user://xxx.gd --headless` 可跑
  extends SceneTree 的探针脚本，结果写 user:// 文件；物理帧用 `_iteration`
  计数（SceneTree 没有 _physics_process）；编译检查用 GDScript.new()+reload()。
- /tmp/gdre（游戏反编译）和 /tmp/qmtato（QMtato 解包）本次已重解，重启会丢。

**⚠ 2026-09-16 会话增量（压缩前最新）**：
- **v50（1.0.50）DLC 环弹 boss 修复已打包，用户实测"看起来没问题"**。细节在下方
  -4.9 节的 v50 补洞段：DLC 三个环弹 boss = 水母×4 环 / 巨人×2 环（_ready 注册，
  v48 已覆盖）/ **鳗鱼 Eel（on_state_changed(1) 才 instance 环弹，晚注册漏转，
  是真凶）**；修法 = 幂等 `_convert_additional_projectiles` + boss `state_changed`
  信号 deferred 重转 + 0.1s 巡逻兜底。另确认：魅惑机制本身是 DLC 内容
  （charm_enemy_effect_behavior.gd），其 on_hurt 里 `_parent is Boss` 直接 return
  → boss 只能走 mod 的复活魅惑路径。
- **GitHub 已推送**（Crystalhihihi/Brotato-SuperCharm main）：`6e5dd33` = v48~v50
  三版代码（含 effects/rc_boss_probe.gd 探针）；`2e21803` = 工坊描述反馈邀请。
- **工坊描述加了反馈邀请**（"觉得超标/需要削弱/有 bug 请留言"），10 语言节全覆盖
  （description.txt 简中+英文有独立「▌反馈 / Feedback」区；i18n 的繁/俄/西/葡/德/
  法/日/韩各节末尾一句）。**尚未贴到 Steam 页**——推 v50 时一并贴。
  西语是中性版，Steam 西班牙/拉美两分区贴同一份即可。
- **平衡结论（存档备查）**：原版无尽 boss 数量恒定不涨（每 10 波固定 3 精英
  [main.gd:973 init_elites_spawn(current_wave+10)，无尽里 horde_chance=0 必精英型]
  + 每 20 波复读一次 wave20 boss 波 [zone_service.get_wave_data 循环 wave11~20]），
  增长的只有数值（endless factor 三次方）和小怪群。mod 磁石上限线性随波长
  （alive_cap +1/4 波、wave_cap +1/2 波）→ 数量上 mod 快。但魅惑 boss 数值冻结
  在捕获波 → 大后期数量对冲不了数值膨胀。**用户拍板：维持现状不调平衡，
  等玩家反馈**；要调就动 mod_main.gd 开头常量区（BOSS_CHARM_CHANCE /
  BOSS_MAGNET_* / BOSS_REVIVE_HP_RATIO / BOSS_WAVE_HEAL_RATIO）。
- **推 Steam 仍待办**：GodotWorkshopUtility + ID 3796762706 +
  publish/超级魅惑 SuperCharm.zip（v50）+ preview.png + 更新后的描述文案。

-5. **魅惑币无尽衰减用最大生命抵消（v49，用户拍板的方向）**：原版无尽把魅惑总概率
   ÷max(1, get_endless_factor()/2)（34 波起 ÷1.05、38÷2.2、40÷3.15、50÷11.6、
   80÷100.7、100÷243，三次方衰减）。魅惑币固定 1%/2% 会归零。v49：
   `_reconcile_charm_compensation`（`_scan` 里每 0.5s 跑）给每枚币注入补偿窗口——
   抵消倍率 m = 1 + 最大生命/100，封顶到稀释倍率本身（只恢复标称概率，永不超出，
   "玩家自己凑血量，凑不齐是自己的事"）。**实现要点**：原版 on_hurt 的
   max(1, value/100×stat) 地板把 structure_range（恒 0）条目锁死在固定 1%，
   调 value 无效；补偿条目必须挂 `stat_max_hp` 反解 value（value = extra_pct×100/maxHP）。
   签名 = [stat_max_hp_hash, 任意值, 30/60]，每次扫描先清后加；浪漫之人自己的
   [stat_max_hp, 50, 25] 阈值不同不会误删。10 语言物品描述同步加了一句
   "每 100 最大生命抵消 1 倍衰减"。**boss 数值冻结维持不变**（用户明确：
   不冻结太离谱）。浪漫之人自身魅惑不做补偿（实测血量成长在 100 波前都能扛住）。

-4.9. **猎杀者环绕子弹魅惑后不再敌对（v48）**：vanilla charm() 只转换
   ShootingAttackBehavior 射出的子弹（custom_collision_layer→PET_PROJECTILES_BIT
   + hue_shift 灰蓝色 shader），对 `register_additional_projectile` 注册的
   "additional" 子弹（Predator 的 $Pivot 环绕弹环，enemy_projectile_rotating.gd，
   场景预置子节点）完全不处理 → 魅惑后弹环保持 layer16 红色敌对、照打玩家
   （本体只有 Predator 用这个机制；**DLC 还有三个：水母 Jellyfish×4 环、
   巨人 Giant×2 环（都在 _ready 注册，同 Predator 路径）、鳗鱼 Eel**）。
   修复：`_setup_charmed_ally` 里遍历
   `enemy._all_additional_projectiles`，逐个 `set_collision_layer(PET_PROJECTILES_BIT)`
   + 套用 vanilla 同款 hue_shift shader（hue=Utils.CHARM_COLOR.h）→ 变灰蓝、
   转打敌人（敌方 hurtbox mask 含 1024）。**无需死亡还原**：boss 永不进池
   （Boss.respawn() 直接 assert false），且 Predator die() 会 queue_free 整个
   Pivot，不存在池化泄漏。
   **v50 补洞（用户实测 DLC 环弹 boss 魅惑后仍是红弹可打人）**：鳗鱼 Eel 的
   环弹不在 _ready 注册——`on_state_changed(1)` 时才 instance pivots_scene
   再 register_additional_projectile，晚于魅惑 setup → 转换漏网。修复：
   ① 转换抽成幂等函数 `_convert_additional_projectiles`（以 hitbox 层
   ==PET_PROJECTILES_BIT 判已转跳过，避免 shader dup 抖动）；② 魅惑 setup 时
   对 boss 连 `state_changed` 信号 → `_on_charmed_boss_state_changed` →
   `call_deferred(_convert_additional_projectiles_deferred)`（必须 deferred：
   Boss.on_state_changed 里 emit 在子类注册之前）；③ `_police_charmed_targets`
   0.1s 巡逻里对每个 ally 兜底重转（普通怪列表为空近零开销，池化弹被还原
   层也能自愈）。另外注意：魅惑机制本身就是 DLC 内容，vanilla 实现在
   dlcs/dlc_1/effect_behaviors/enemy/charm_enemy_effect_behavior.gd，且
   on_hurt 里 `_parent is Boss` 直接 return——boss 永远只能走 mod 的复活魅惑。
   **同次排查结论（用户报"26-30 波后魅惑/币失效"，实跑存档到 38 波）**：
   ① 无尽没有换代码，是原版魅惑稀释：`charm_chance / max(1, get_endless_factor()/2)`，
   factor = (ew×(ew+1)/2)/100 × (2+max(0,(wave-35)×0.2))，ew=wave-20。
   **≤33 波稀释恒为 1（无影响）**；34 波 ÷1.05、38 ÷2.2、40 ÷3.15、45 ÷6.5、
   50 ÷11.6。魅惑币固定 1%/2%（structure_range 恒 0）→ 38 波后实效 0.3~0.9%，
   体感=失效；浪漫之人自身 0.5%×最大生命 基数大，稀释后仍可用（日志里 100
   上限裁员持续到最后一波为证）。② "魅惑 boss 吃我方爆炸"：静态分析（玩家爆炸
   hitbox 层=8，魅惑怪 hurtbox mask=4|16 → 打不到）被用户实测推翻（辣酱吃水果
   爆炸当面炸死魅惑 boss）。**-s 物理探针（真引擎）确认 mask=4|16 的魅惑怪对
   layer=8 确实不可见** → 唯一可能是 hurtbox 状态被还原/未生效。**v49 实测抓到
   真凶：一帧真空窗**——魅惑瞬间 charm() 的 hurtbox disable 是 set_deferred、
   mod 的 setup 是 call_deferred，都要等下一帧，当帧怪还是 vanilla hurtbox
   （enabled + mask 1032 含玩家子弹/爆炸）→ 复活 boss 25% 血落进弹火密集区，
   一帧内十几个命中同时结算直接秒（日志：5/5 复活 boss 0~1s 内被 by_player=0
   的 116k~264k blow 打死；魅惑小怪被 layer=8 命中时 hb layer=0 mask=1032）。
   修复：`_on_enemy_charmed` 里**同步**调 `_protect_ally_hurtbox`（layer/mask
   立刻改 + `_collision.disabled = true` 直接落，不走 deferred；魅惑入口全是
   idle 时机，直接写碰撞安全）。on_hurt 中途魅惑的"当帧排队命中"无法取消
   （hurt_area_entered_deferred 无魅惑判定且不能动 unit.gd），小怪满血兜底
   可承受。另保留：` _scan` hurtbox 状态自愈+日志、hurtbox area_entered 诊断
   （"ALLY HIT BY PLAYER-SIDE"）、魅惑 boss 死因日志（"charmed boss died"）。
   魅惑 boss 后期被敌方集火融化仍是主要死因（数值冻结在被魅惑波次 vs 敌人按
   当前波缩放，38 波 ≈ ×5.5）。
   **一帧窗修复后仍被秒（v49 二轮排查）**：玩家侧 area 命中归零（hurtbox 防护
   生效），但复活 boss 依旧 0~1s 死、by_player=0、blow 15~62 万 → 伤害完全
   绕过 hurtbox。vanilla 全库 take_damage 调用点只有 hurtbox 路径 +
   闪避反击（player.gd:457 hitbox.from.take_damage）+ 替罪羊自残；
   QMtato 直伤全是其自定义角色专属（用户玩浪漫之人不涉及）。待查。
   已部署：① 复活 boss 死亡点离玩家 <500 时改地图边缘生成（与磁石一致，
   脱离秒杀火力区）；② `effects/rc_boss_probe.gd` 探针挂到魅惑 boss 的
   effect_behaviors（鸭式接口，on_taken_damage 能抓到所有 take_damage 路径，
   记 hitbox 层/from/from_player_index）→ 日志 "BOSS PROBE"。
   ③ 复活币后期仍正常绑定（日志：25 波商店买的两个币当场绑定 tentacle 并
   生成）；后期币小弟出生即被高波怪群秒，观感差但不是失效。
   ④ vanilla 魅惑并发上限其实是 **999**（charm tscn 覆盖 export 的 5），
   计数器每波 `_reset_per_wave_properties` 清零，不是问题来源。
   **后续处理（v49）**：稀释抵消已实现（见 -5，绑定最大生命）；boss 数值
   冻结维持（用户决定）。另：本次排查的反编译产物 /tmp/gdre 是 2026-09-15
   重新解的（重启会丢，GDRE Tools v2.6.4 直接 GitHub 下载可用）。

**v45 改名**：mod ID `LocalMods-RomanceCharm` → `Crystalhihihi-SuperCharm`（manifest name/namespace、
zip 内文件夹、mod_main.gd 的 RC_LOG/MOD_DIR/ContentLoader 注册名、3 处 tres ext_resource
路径全部同步）。**配置目录随之变为 `configs/Crystalhihihi-SuperCharm/`，旧配置孤儿化即
重置默认（玩家同意不迁移）**。物品 my_id 不变，存档/解锁不受影响；Steam 标题与物品
翻译 msgid 均不动。游戏内 mod 列表现在显示 `Crystalhihihi-SuperCharm`。

-4.8. **无 DLC 弹窗警告（v46/v47）**：魅惑机制整个是 DLC 内容（charm_enemy_effect_behavior
   在 dlcs/dlc_1、浪漫之人是 DLC 角色），没买/没启用 DLC 时 mod 全程 null 兜底静默
   无效（巴西玩家留言 "pq n esta funcionando?" 的来源）。`_process` 里等
   `_translations_ready`（0.5s 延迟注册完成后）且 current_scene 是标题界面时，
   查 `ProgressData.available_dlcs.size() == 0`（游戏自己的 DLC 判定，
   check_for_available_dlcs 里 Steam 非机主直接 return）→ AcceptDialog 弹一次。
   **踩坑（v46 不弹，v47 修）：这游戏没有独立的 main menu 场景**——标题界面
   title_screen.tscn 内嵌 %MainMenu，current_scene 永远不会叫 "MainMenu"；
   现在用标题界面的 `_menus` 成员鸭式判定（`scene.get("_menus") != null`）。
   **弹窗 add_child 到标题场景继承游戏主题**（Godot 默认主题没 CJK 字体，裸弹窗
   中文变方块）。msgid 直接用英文原文：覆盖不了的 locale 自然回退英文（探针验证
   pl 回退正常），10 语言翻译照旧在 `_add_translations`。每启动至多弹一次。

- 游戏内翻译（v43）：en/zh_Hans 原有，新增 zh_Hant/ru/es/pt_BR/de/fr/ja/ko 共 10 语言
  （物品名、物品描述、2 个配置 tooltip）。**配置键中文标签的本地化技巧**：ModOptions
  菜单显示的是 `config_key.to_upper()`（中文键名不受大小写影响），给 Godot 注册
  msgid=中文键名 的翻译即可让其他语言玩家看到本地化标签——键名不动，存档配置零迁移。
  Godot 3 控件文本默认自动 tr()。多语言工坊文案在 publish/description_i18n.txt。
  **v44 修正（踩坑：简中显示繁体）**："中文玩家匹配不到翻译、回退显示键名原文"是
  **错的**——Godot 3 在最佳匹配翻译里找不到 msgid 时会继续翻**同语言的其他翻译**，
  zh_TW 块的映射会赢，简中玩家看到繁体。必须给 zh 三个 locale 的块注册
  **键名→键名的恒等映射**占位（mod_main.gd `_add_translations`）。

-4.7. **无尽性能治本（v35/v36）**：v34 的返还 cap 只挡住崩溃，没减 mod 自身开销。砍三块：
   ① **钉死魅惑单位的 vanilla 重索敌**：魅惑行为 `update_target` 每 0.25s 为每个魅惑
   怪全表扫描一次敌人列表（60 魅惑 × 160 敌 × 4/s ≈ 4 万次距离计算/秒纯 GDScript，
   无尽二次方税）。`_setup_charmed_ally` 把 `enemy.update_target_timer` 钉成 -99999
   （vanilla `_physics_process` 的 0.25s 节拍永远攒不到），0.1s 纠察队成为唯一索敌
   来源——开销消失，且 0.25s"叛变窗口"从机制上消失（不再是赛跑，vanilla 压根不重选）。
   **死亡时必须还原为 0**（`_on_charmed_ally_died` 第一行）：entity_spawner 池化复用
   死节点，钉死的定时器被带回去的敌对怪会永远不换目标（AI 废掉）。
   ② **魅惑小怪上限 + 确定性裁军（v36 起玩家可配）**：超过上限的魅惑怪本来是被
   vanilla 在每次刷怪时点**随机处死**（entity_spawner.gd on_group_spawn_timing_
   reached：enemies.size() > max_enemies 就从整个敌人列表随机抽杀，魅惑怪在名单里，
   can_drop_loot=false 不掉落）——"魅惑怪莫名消失"观感的真凶。改成 mod 自己杀：
   **最大生命最低优先、同血杀离玩家最远的**、复活币绑定怪豁免、同样不掉落。
   上限同时是 max_enemies 返还 cap，二者恒等对齐。
   ③ **魅惑怪之间取消身体碰撞**（v36）：charm() 把 body mask 设成 PETS+OBSTACLES，
   `_setup_charmed_ally` 改回只留 OBSTACLES_BIT——密集大军每帧省一大片
   move_and_slide 配对结算。敌我判定走 hitbox/hurtbox 不走身体，无战斗影响；
   死亡时 uncharm() 自动还原原 mask。代价纯视觉：大军会叠着站。
   **玩家配置（v36）**：manifest config_schema + ModLoaderConfig（照抄 QMtato 模式，
   config 名固定 `config_created_by_mod_options`），两个键：`RC_SWARM_CAP`
   （integer 默认 100，mod 侧 clamp 0~1000）、`RC_SWARM_UNLIMITED`（bool 默认 false，
   无上限 = 回到 v33 崩溃风险区，玩家自选）。装了 dami-ModOptions 可在游戏内 mod
   列表直接改（setting_changed 实时生效）；没装也能手编
   `user://configs/Crystalhihihi-SuperCharm/config_created_by_mod_options.json`（v45 改名后
   的路径；改名前为 configs/LocalMods-RomanceCharm/）。
   另：**复活币绑定改加权随机**（v36）——`_bindable_species` 的值从 true 改成该物种
   见过的最大生命，`_pick_weighted_species` 按 max HP 加权，血厚物种优先被绑。
   底层改不了的部分：单实体物理/碰撞成本（move_and_slide 原生）、原版无尽自己
   max_enemies=100 + 每波 2 boss（wave_data.gd:5）、敌对怪扫 targetable_pets 的
   原版索敌、波末全场同时 die() + 自动存档的卡一下（main.gd:946/998，vanilla 行为）

-4.5. **魅惑单位索敌纠察（v34 修"集体叛变"）**：vanilla `Enemy.update_target` 每 0.25s
   先选最近玩家/宠物，魅惑行为的 `update_target`（charm_enemy_effect_behavior.gd:139）
   **只在场上存在 ENEMIES_BIT 单位时**才把目标覆盖成敌人 → 波次开头小怪还在出生
   动画、或无尽刷怪组间隙全场零敌对时，所有魅惑单位（含跨波 boss）目标 fallback
   到玩家，集体冲向玩家几秒钟，观感=叛变（实际打不到玩家：hitbox 忽略列表挡着）。
   修复：`_police_charmed_targets` 以 0.1s 节拍跑（vanilla 0.25s 重选，稳赢；
   每帧跑在无尽几百实体下自身就是负载），魅惑单位（collision_layer==PETS_BIT
   快速区分）当前目标不是敌对怪时改指最近敌对怪；零敌对时指**离玩家最远的
   友军**让大军散去场上集结；孤身一怪则不动（跟着玩家没事，反正零伤害）。
   目标失效安全：follow_target_movement_behavior.gd:18 对 invalid target
   有判空。不改 vanilla 文件，纯运行时覆写 current_target
   **注意后续修正（v34 实测反馈）**：用户开局能把"叛变"boss 打死 → 那些其实是
   **真敌对 boss**（魅惑怪 hurtbox 在 PETS_BIT，玩家武器物理上打不到）。来源 =
   无尽波初 vanilla 自刷 boss/精英 + 磁石刷的 boss（磁石 boss 设计上先敌对，
   死后 10% 复活才变自己人——秒杀后 0.6s 蓝色归来，观感="叛变几秒又反正"）。
   且魅惑 boss 在无尽常被敌方集火战死，携带链断属正常（日志 01:02 后无 carrying）
-4.6. **无尽实体过载崩溃（v34 缓解）**：闪退局日志 = 01:17:40 磁石刷 boss 后几千条
   `Can't change this state while flushing queries`（area_set_shape_disabled）刷屏
   中断，无正常退出记录 = 引擎层硬崩。根因 = 实体过载：max_enemies 返还（v25）原来
   是"基础值+魅惑数"无上限，无尽魅惑大军几百只 → 同屏上限同步爆炸 + 磁石 boss +
   币小弟 → 物理服务器压垮。修复：返还加 cap `MAX_ENEMIES_REFUND_CAP = 60`；
   顺手补 `_spawn_charmed_enemy` 缺的 `_cleaning_up` 守卫（踩坑 13 家族最后一个
   敞口）。无尽崩溃若再复现，下一步看实体总数和 curse 刷怪频率

-4. **魅惑币（红装 tier=3，100 块，max_nb=5，红底紫心图标）**：CharmEffect
   （key=stat_max_hp, custom_key=charm_on_hit, value=1, value2=30, KEY_VALUE）→
   任何角色约 1% 魅惑率（<30% 血，原版公式 max(1,...) 保底）。**诅咒**：原版通用诅咒把
   value 1→2（2%@30%），mod 运行时给每个被诅咒魅惑币注入 [stat_max_hp,1,60] 窗口
   （`_reconcile_charm_coins`，实时清点防读档不同步）→ 合计约 2%@30% + 1%@60%。
   **浪漫之人专属**：持魅惑币时 boss 复活率 10%→15%（`_boss_charm_chance`，
   角色判定 `RunData.get_player_character(0).my_id == "character_romantic"`）。
   注意：买币后只有**新刷出**的敌人带魅惑行为（原版限制，behavior 只在 spawn 时挂）

-3. **魅惑磁石刷 boss**（v11 重写 → v12 DeepSeek 评审 → v13 调松 → v14 动态压力）：
   按战力占比（小怪 Σ(max血×max伤害)，boss 两边都不算）每 4s 判定。
   **v14 起上限随比值动态缩放**：比值 r（clamp 到 3），在场上限 = 2+floor(r)（最多 5），
   每波上限 = 3+floor(r×1.5)（最多 7）；概率 = min(70%, r×0.8)；r≥1.5 时一次刷 2 只。
   **全魅惑（敌方清零）按 r=3 顶格处理**——100% 魅惑（浪漫之人 200 血）不再白给，
   魅惑全场 = boss 大乱斗。弱怪海（r<0.1）依然不刷。
   **v15 起无尽加成**：20 波后 endless_bonus = (wave-20)/4，在场上限 +bonus、每波上限
   +2×bonus（原版后期一波几十只 boss，固定上限会沦为摆设）。上限只约束磁石自己刷的
   boss（`_magnet_bosses` 单独追踪），不碰原版刷怪。
   boss 从当前 zone 的 elites+bosses 池随机选，EntityType.BOSS spawn 自带波次缩放。
   spawn 时 `set_meta("rc_scene_path", scene.resource_path)` 兜底。
   日志：`charm swarm attracted a boss (charm power ratio ...)`
   **v22 起加波次闸门**：第 8 波前磁石不启动（BOSS_MAGNET_MIN_WAVE，v33 起改为 10 波）——原版第一个精英
   第 10 波左右才露面，前期魅惑凑 3 只很费劲，boss 落地瞬清场 = 纯惩罚死循环。
   **v23 起**：磁石 boss 改**地图边缘**生成（`get_spawn_pos_in_area(..., true)`，不再
   刷脸上）。**v33 调难度**：启动闸门 8→10 波（与上限表对齐）；在场上限按波次表
   `clamp(1+(wave-10)/5, 1, 3)` = 10/15/20 波 → 1/2/3 只（旧表 8/12/16/20 →
   1/2/3/4），且上限改为**数全场存活的敌对 boss/精英**（原版波次开局刷的占名额，
   魅惑 boss 友军不占；不再只数磁石自己刷的——`_magnet_bosses` 字典删除，清点合并
   进磁石每 4s 的全场扫描循环）。无尽加成照旧。非魅惑构筑（无浪漫之人/长笛）下 mod 完全惰性：魅惑不触发 → 磁石不达标、
   币空槽、boss 复活跳过。币对非魅惑局是白板，备选未做：无魅惑来源时币不进商店池。
   注：`_charmed_alive_species` 只统计普通怪（复活币不绑 boss，boss 跨波有
   专门的 `_boss_records` 通道）
-2.5. **跨波携带修复**：波末 cleanup 会对所有 boss 调 die()，此前 `_on_boss_died` 把它当
   真死删了记录 → 携带功能其实一直是坏的。现在 `_args.cleaning_up == true` 时保留记录
-2.2. **波末崩溃（v16 已修，待实测确认）**：根因 = 清场死亡触发复活判定、0.6s 后才
   spawn → 拆毁中的场景被塞入新 boss → 引擎硬崩。详见踩坑记录 13。诊断日志
   （`wave end: carrying` / `revive-boss begin`）先留着，复发再看
-2. **魅惑怪击退**（解决"量子纠缠"）：接触伤害只在 hitbox **进入** hurtbox 瞬间触发，
   魅惑怪和敌人互锁后走到一起重叠 → 双方都再也不会触发伤害 → 原地摇摆死锁。
   解法（用户提的）：魅惑怪 `_hitbox.knockback_amount` = `max(0, 8 + 玩家击退属性)`，
   方向每 0.5s 扫描时更新为指向 current_target（`_apply_ally_knockback`）。
   击退→再冲→再触发，循环打破。**击退值绝不允许为负**：take_damage 负击退分支会用
   players_ref[123]（DUMMY）越界崩。击退原值同样存 meta(rc_kb)、死亡时恢复
-1. **魅惑时清除点燃**（原版 bug 顺手修了）：魅惑那次命中在 charm() 里 stop_burning 之后
   又 apply_burning（hurt_area_entered_deferred 里 on_hurt 先于 apply_burning 跑），
   且燃烧是计时器扣血、不受 hurtbox 禁用影响 → 魅惑怪带着点燃继续掉血。
   `_setup_charmed_ally` 里 deferred 再 `enemy.stop_burning()` 一次
0. **魅惑瞬间满血**（小怪）：魅惑 <25% 血才触发，不满血一碰就死；`_setup_charmed_ally`
   里 `current_stats.health = max_stats.health`。**boss 排除**（is_elite 判定）——
   boss 复活 25% 血是刻意的
1. 永久魅惑：停掉 CharmTimer（原版 8 秒后魅惑怪自动死亡）
2. 魅惑怪可被敌方攻击：charm() 会禁用 hurtbox，本 mod 在魅惑 1.5 秒**宽限期**后
   （`ALLY_GRACE_PERIOD`，`_enable_ally_hurtbox`）才恢复——v2 是魅惑瞬间立即 enable，
   结果魅惑判定在 <25% 血触发、怪又通常被围在怪堆里，enable 一刻所有重叠的敌方
   hitbox 同时 area_entered 集火 → 魅惑即暴毙。宽限期配合魅惑自带 +100 移速让它走出怪堆。
   hurtbox layer 改 PETS_BIT(512)，**mask 直接覆写为 ENEMIES_BIT|ENEMY_PROJECTILES_BIT**
   （=4|16，不再保留原 mask → 玩家武器绝对打不到它）；
   同时推入 `spawner.targetable_pets`，敌人索敌 = 最近的玩家/宠物/魅惑怪
3. boss/精英死亡 10% 概率魅惑复活（25% 血，血量伤害冻结在死亡波次），活着就带入下一波
   （本质是每波重建），每波回 20% 血。需玩家有魅惑来源（浪漫之人/长笛）
4. 魅惑单位每秒回复 = 玩家「生命恢复」属性的血量
5. 复活币（蓝装 tier=1，基础价 60，+3 生命恢复，猪储钱罐… 不，已是自绘金币爱心图标）：
   ~~波次结束时~~ **v18 起：战斗中有空槽且有存活魅惑小怪就立即绑定并立即生成**
   （买完的下一波就能用，不用等两波）；波末绑定保留为兜底；之后每波开始满血魅惑参战、
   数值随波次自动缩放（原版 spawn 自带缩放）；死了下波满血归来；币永不爆；
   诅咒版绑两只。图标是自己用 PIL 画的像素金币爱心（revival_coin_icon.png）。
   v18 加了诊断日志：`coin binding created/erased`、`coin respawn check N/M`、
   `coin ally spawned/failed`
   **v33 修复"有 2 个复活币但每波只复活 1 只"**：绑定槽从按物品 instance_id 键控
   （`_coin_bindings` 字典）改成按数量计数（`_coin_slots` 数组）——原版商店买非诅咒
   道具不 duplicate，两个币是同一共享实例 → 同 id → 只建了一个绑定（见踩坑 23）。
   槽位数 = 币数 + 诅咒币额外数；卖币/丢币时优先丢空槽，全满才丢最新绑定
   **v33 还改了绑定候选**：币小弟不再做新币的绑定候选（新增 `_bindable_species`
   = 魅惑物种集合减去 `_coin_allies`）——旧逻辑下买第二个币，下一波开局场上唯一
   的魅惑怪就是第一个币的小弟 → 新币直接克隆同款（用户实测以为是 bug）。现在新币
   要等魅惑到"真怪"才绑定（魅惑构筑开波几秒内就会绑上），不再开局克隆。
   注意 `_charmed_alive_species` 仍含币小弟（max_enemies 返还按它计数），两个字典
   用途不同，别合并

## 关键架构

- **零脚本扩展**（全部运行时：信号 + 0.5s 轮询）。原因见下面「踩坑记录」
- mod_main.gd 挂在 ModLoader 节点下常驻；Main 场景每波重建 → 用 `main != _last_main`
  检测新场景/新局，`RunData.wave_in_progress` 判战斗中
- 关键 API（均已验证）：
  - `spawner = Utils.get_scene_node()._entity_spawner`，`spawner.get_all_enemies(true)`，
    `spawner.spawn_entity(scene, EntitySpawner.SpawnEntityArgs.new(pos, EntityType.ENEMY/BOSS), null, null, charmed_by)`
  - 注意 BOSS 类型 spawn 不自动魅惑，要手动 `enemy.set_charmed(0)`
  - `enemy.set_charmed(idx)` → 遍历 effect_behaviors 找带 "charmed" 属性的 behavior 调 charm()
  - charm behavior 场景：`res://dlcs/dlc_1/effect_behaviors/enemy/charm_enemy_effect_behavior.tscn`
    （敌人没有时可用 `_attach_charm_behavior` 手动挂，load tscn 是可靠的）
  - 魅惑信号：`RunData.enemy_charmed`；死亡信号：`entity.died(entity, die_args)`
  - boss 判定：`enemy.get("is_elite") != null`（Boss 类标志）；数值冻结 = 覆盖
    max_stats/current_stats 的 health+damage + `_hitbox.damage`
  - ContentLoader 注册自定义道具（v6 起改运行时路线）：_ready 时
    `get_node_or_null("/root/ModLoader/Darkly77-ContentLoader/ContentLoader")` ← **注意是
    两层**：mod 节点下还有个名叫 ContentLoader 的子节点（QMtato mod_main.gd:107 同款）。
    v2~v5 只写了第一层 → "ContentLoader node not found"，复活币静默不可用。
    然后 `load(res://...tres)` 拿道具资源 → `item.icon = 运行时 ImageTexture` →
    `cl.load_data_by_dictionary({"items": [item]}, "Crystalhihihi-SuperCharm")`（v45 前为 "LocalMods-RomanceCharm"）。
    **不要**用 tres 里 ext_resource 直接引用 png：导出版没有导入器，需要 .import/.stex
    元数据（QMtato 的 zip 里带了一堆 .stex 才行），裸 png → "No loader found for resource"
    → 整条资源链 parse 失败 → mod_data=null → ContentLoader 崩（1.0.4 闪退事故）。
    运行时 Image.load + ImageTexture.create_from_image(img, 0) 是正道。
    content_data/ 目录已删，不再使用。
  - 道具池解锁：ContentLoader 自动处理（unlocked_by_default → ProgressData.items_unlocked）
- 多语言：运行时 `Translation.new()` + `TranslationServer.add_translation`，
  locale 用 zh_Hans_CN / zh_CN / zh / en 各注册一份

## 踩坑记录（别再踩）

1. **BossRush 0.9.8 是万恶之源，用户已弃用**：它的 7 个扩展（main/item_service/weapon/
   wave_manager/player/boss/closest_enemy_target_behavior）有静态类型引用循环依赖，
   Godot 编译顺序随机 → 约 50% 启动失败（扩展装成 Null 父类 → take_over_path(null) → 闪退）。
   用户已取消订阅。BossRush 后来更了 0.9.9 但是否修复未知。
2. **mod_main 里不能直接写全局类名 `ContentLoader`**：mod 编译时其他 mod 注册的全局类
   可能还没进类表 → 整个 mod 编译失败、静默全灭（本次 v1 的事故）。要用节点路径获取。
3. **不能 extends DLC 的 .gd 路径**（如 charm_enemy_effect_behavior.gd）：导出版没有 .gd
   源码，extends 不走 .remap → 编译失败。但 QMtato extends `res://dlcs/dlc_1/dlc_1_data.gd`
   可以——因为那是 DLC 数据单例，启动时已在缓存里。规则：extends 前先在 _init 里
   `load()` 预热目标脚本（本 mod 对 effect.gd/item_data.gd 就这么干的）。
4. **不要再给 unit.gd 叠扩展**（曾导致 boss.gdc 重载失败连锁闪退）。
5. 魅惑原版机制（反编译自 DLC pck）：判定在 charm_enemy_effect_behavior.on_hurt，
   敌人受击时、take_damage 之前；门槛 `is Boss / is_loot / can_be_charmed / dead /
   攻击方是Enemy / cap(999)`；概率 `max(1, value/100 × Utils.get_stat(key))%`，
   浪漫之人效果 = [stat_max_hp, 50, 25]（敌人血<25% 时，概率=0.5%×玩家最大生命）；
   无尽模式 24 波后概率开始被 `get_endless_factor()/2` 稀释。
   魅惑成功那次命中伤害被完全吸收。
6. 原版魅惑后 hurtbox 被禁用+不进索敌列表 = 魅惑怪 8 秒内无敌、不被打，纯靠计时器死亡。
   **魅惑瞬间 enable hurtbox = 自杀**：魅惑 <25% 血触发且怪在怪堆中心，enable 时所有重叠
   敌方 hitbox 同时触发 area_entered 集火秒杀（v2 实测事故）。必须宽限期。
   另：魅惑后 hitbox 层被 charm() 改成 PET_PROJECTILES_BIT(1024)，所以魅惑怪能反过来
   撞伤敌人（敌方 hurtbox mask 含 1024）；敌人 contact hitbox 层是 ENEMIES_BIT(4)、
   敌方弹是 ENEMY_PROJECTILES_BIT(16)。hitbox.from=敌人自己、player_index=-1 →
   hurt_area_entered_deferred 走 DUMMY_PLAYER_INDEX(123) 路径，RunData 各 API 对 123
   有特判，安全。
7. 波次结束：Main 场景整个换掉，敌人随之消失；`RunData.current_charmed_enemies` 每波重置。
   「波末存活名单」要在 wave_in_progress 翻 false 的瞬间读（此时场景还在）。
8. 读档直接信任存档数值（resume_from_state 不重算）→ 坏会话产出的档会带着错数据。
   用户此前"魅惑特别少"就是因为一个老毒档把 max_hp 存成了 ~20。
9. **"Mods are currently disabled" 事故（2026-09-05）**：用户某次测试看到的"异常"
   其实是 mod 全被禁用（最新 modloader.log 只有 4 行：`Mods are currently disabled` +
   `No mod_ids inside mod_list`）→ 纯原版行为。遇到"mod 没效果"先看最新 modloader.log。
   重新启用：游戏内 Mods 菜单/ModLoader 选项打开开关。
10. modloader.log 轮转命名：旧文件时间戳是**下一次启动**的时间，看时间线别被文件名骗。
12. **对象池回收泄漏（v8/1.0.7 修复）**：EntitySpawner 会回收死掉的敌人节点
    （`main.get_node_from_pool` + `entity.respawn()`），respawn 会 `_hurtbox.enable()` 但
    **不会重置我们改过的 collision_layer/mask** → 被魅惑过的怪死后节点被复用成普通敌人，
    带着 PETS_BIT+4|16 的 mask → 玩家子弹直接穿过、打不中，但它照常打玩家（v7 实测事故：
    "没魅惑特效、打不中、还会打人"的怪就是这么来的）。修复：`_setup_charmed_ally` 改 mask
    前把原始 layer/mask 存进 `enemy meta(rc_hb_layer/rc_hb_mask)`，`_on_charmed_ally_died`
    恢复并删 meta。**教训：改实体任何碰撞属性都必须考虑池子复用，死亡时还原。**
    另：魅惑怪和敌人视觉重叠是原版行为（charm 把 body mask 改成不含 ENEMIES_BIT），无害。
13. **波末清场 spawn 崩溃（v16/1.0.15 修复）**：`clean_up_room` 清场杀光所有 boss，此时
    某个 boss 之死若触发 10% 复活判定，0.6s 定时器在**清场完成后**才 spawn → boss 在
    波末结算画面"诈尸"（用户观察到"所有怪消失、魅惑 boss 还在"），且 spawn 发生在场景
    拆毁过程中 → 引擎硬崩、日志无脚本错误。原版自己的 spawn 路径都有 `_cleaning_up`
    守卫，但 `spawn_entity` 没有！修复三处：`_on_boss_died` 对 `args.cleaning_up` 的死亡
    不 roll 复活；`_revive_boss` 和 `_boss_magnet_roll` 开头检查 `spawner.get("_cleaning_up")`。
    **教训：任何往场景 spawn 实体的代码必须先查 `_cleaning_up`。**
14. **boss 跨波携带曾被 scan 清理误杀（v17/1.0.16 修复）**：`_scan` 的 cull 循环把
    "实体已死"的记录删掉——波末清场杀死的魅惑 boss 恰好是 dead → 记录被删 → 携带失效。
    真正的死亡已由 `_on_boss_died`（区分 cleaning_up）负责删除，cull 循环整个移除。
15. **ContentLoader 解锁 bug（v17 绕过）**：`_add_unlocked_by_default_without_leak` 推的是
    `item.my_id`（字符串），但商店池 `init_unlocked_pool` 查 `my_id_hash`（int）→
    所有 ContentLoader 自定义道具**永远进不了商店池**。修复：注册时自己把
    `Keys.generate_hash(COIN_ID)` 推进 `ProgressData.items_unlocked`（时机在
    _install_data 建池之前）。（QMtato 的自定义道具应该也全军覆没，没人发现而已）
16. **魅惑大军占刷怪名额（v25/1.0.25 缓解）**：每波有 `max_enemies` 上限，新刷组触发时
    若 `enemies.size() > max_enemies` 会随机处死超额怪（不掉落）。魅惑怪在 enemies 列表里
    占名额 → 魅惑海一大，系统不停处死小怪，中期小怪不够用（boss 在 bosses 列表不占名额，
    "boss 顶掉小怪"其实是魅惑大军占的）。修复：_scan 里把上限实时改为
    `base + 存活魅惑小怪数`（base 按 wave_data 实例 id 捕获，防资源复用串波）。
21. **魅惑币血量加成去除（v25）**：魅惑公式 `max(1, value/100 × get_stat(key))`，原来
    key=stat_max_hp → 大后期几千血×5币=100%。改成 `structure_range`（实战中恒 0，
    init_stats 里有、hash_to_string 里有）→ 固定 1%/币。诅咒注入窗口同步改
    [structure_range,1,60]。**注意：换占位属性时必须确认它在 init_stats 和
    Keys.hash_to_string 里都存在，否则 get_stat/get_stat_gain 会 null 崩。**
22. **道具描述显示 "Null"（v32/1.0.32 根治，已实测确认）**：
    **真正的根因：在 ModLoader 初始化的同一帧里用 `Translation.new() +
    TranslationServer.add_translation` 注册运行时翻译，长文本会被这个定制引擎写坏**
    ——en 环境读出 "2"、zh 环境读出 "Null"；短文本（物品名）不受影响。用
    `Brotato.exe -s 脚本.gd`（无窗口跑引擎，脚本 extends SceneTree，结果写
    user:// 文件）做了对照实验：同样的文本同样的键名，禁用本 mod 后注册 = 干净；
    本 mod 在 _ready 里注册 = 乱码。与效果类、ContentLoader、QMtato、超市界面全部无关。
    **修复 = 把 `_add_translations` 推迟 0.5s**（`create_timer(0.5).connect("timeout",
    self, "_add_translations")`），避开初始化帧。
    v28~v30 的弯路记录（别再走）：覆写 get_text / 覆写 get_args 返回 [] / 注册
    ItemService.effects 都不治标。顺带做的正确改动保留：① 效果 tres 挂**原版类**
    （魅惑币 = vanilla `charm_effect.gd`，marker = vanilla `effect.gd` 配
    `key=stat_luck, value=0` 纯描述行，key 不能留空——基类 get_args 会跑 tr("")）；
    ② 自定义效果类仍注册在 ItemService.effects，仅为兼容 v25~v29 旧存档。
    **教训：① 运行时注册翻译不要在 mod _ready 里做，延迟 0.5s；② 排查显示问题先写
    探针/用 -s 无界面实测，别空想。**
17. **空场期误刷 boss（v19/1.0.19 修复）**：磁石的"敌方清零=顶格"分支没排除
    `charmed_power == 0`——开局怪还没刷、或怪死光的空档期，双方都是 0 → 比值顶格 →
    70% 狂刷 boss（"前期没魅惑也出 boss"）。修复：`charmed_power <= 0` 直接 return。
18. **携带 boss 刷在玩家脸上（v19 缓解）**：跨波记录没有死亡位置（只有复活的 record 有
    pos），复活落点 = 玩家坐标 → boss 在脸上生成且开局索敌只有玩家 → 立刻朝玩家冲锋，
    观感=攻击玩家。修复：无 pos 时改用 `get_spawn_pos_in_area(玩家, -1, 100)` 随机落点。
20. **磁石只有相对值没有绝对门槛（v21/1.0.21 修复）**：1 只魅惑小怪（或币小弟）+
    敌怪稀少/死光 → 分母趋近 0 → 比值顶格 → 70%/4s 下 boss 雨（第 4 波实测事故）。
    修复：双门槛——魅惑小怪 <3 只磁石完全不启动；清场顶格压力需要 ≥5 只真人海。
    **教训：比例类机制必须配绝对值门槛，否则小样本爆炸。**
19. **魅惑 boss 打死玩家（v20/1.0.20 双保险）**：用户实锤被魅惑 boss 开局撞死。两种可能：
    `cb.charmed`，失败直接 die 移除**并记 error 日志（`boss revive charm FAILED`）；
    (b) 层机制的边界情况——所有魅惑单位的 `_hitbox.ignored_objects` 里推入玩家
    （`hurt_area_entered_deferred` 先查 ignored_objects 再谈伤害），原数组存 meta
    (rc_ignored) 死亡恢复（池子防护同款）。若 v20 之后仍被魅惑 boss 伤血，剩余嫌疑 =
    boss 特殊技能生成的 hazard/AOE（不走 custom_collision_layer），届时再处理。
11. **"有时有mod有时没mod"的真相（2026-09-05 查明）**：不是两个存档，是 Brotato 自带的
    崩溃保护 `crash_reporter.gd`——启动时扫描上一次 godot.log，只要有含 "mods-unpacked"
    的 ERROR（闪退必留下），就把 options profile 的 `enable_mods` 置 false → 下一次启动
    全局禁用 mod。被禁用的那次启动不会产生 mod 错误日志，所以再下次启动又自动恢复。
    表现出来就是闪退后隔一次启动 mod 消失。和存档（save_v3_0.json）无关；mod 解锁状态在
    `mod_user_profiles.json`。只要 mod 不报错不闪退，开关就一直在。
24. **魅惑怪"叛变"是索敌 fallback 不是状态翻转（v34/1.0.34）**：vanilla 没有任何
    临时解除魅惑的路径（uncharm 只在死亡时调，CharmTimer 已停），魅惑 boss 集体
    冲玩家 = `Enemy.update_target` 每 0.25s 重选最近玩家/宠物，而魅惑行为只在
    场上存在敌对单位时才覆盖目标（charm_enemy_effect_behavior.gd:139）。零敌对
    窗口（波初出生动画期、无尽刷怪组间隙）= 全员索敌玩家。排查"状态异常"先分清
    是状态真变了还是行为/观感变了——后者便宜得多。修复见功能 -4.5（每帧索敌纠察）。
25. **钉死 vanilla 实例变量做运行时接管，死亡时必须还原（v35/1.0.35）**：为了掐掉
    魅惑行为每 0.25s 全表扫描的二次方税，把魅惑怪的 `update_target_timer` 钉成
    -99999 让 vanilla 永不重选（mod_main.gd `_setup_charmed_ally` 末尾）。坑在
    entity_spawner **池化复用死节点**：不还原的话，这个被钉死的定时器跟着节点回到
    池里，下次作为普通敌对怪复活 = 永远不换目标、AI 废掉。所以
    `_on_charmed_ally_died` 第一行必须 `update_target_timer = 0.0`。同类教训和
    踩坑里 hurtbox/hitbox/knockback 的 meta 存还原一脉相承：**所有写进 vanilla
    实例的运行时覆写，死时都要清点还原**。
    另：vanilla 自己的"性能裁军"是随机抽杀（on_group_spawn_timing_reached 里
    enemies.size() > max_enemies 就 `Utils.get_rand_element(enemies)` 处死，
    魅惑怪也在名单里）——魅惑军团超额时别指望它"自然调节"，那是随机蒸发，
    要自己确定性裁（功能 -4.7②）。
26. **dami-ModOptions 只渲染四种 schema 类型，"integer"会被静默丢弃（v37/1.0.37）**：
    它的 `mods_config_interface.gd flatten_properties` 只认 `"number"`（滑条，支持
    minimum/maximum/multipleOf/format）、`"boolean"`（勾选框）、string+`enum`
    （下拉框）、string+`format:"color"`（取色器）。数值配置写 `"type":"integer"`
    不报错也不渲染，界面上直接消失。数值项必须写 `"number"`，并且**显式给
    `"format":"%.0f"`**——默认 format 是 percent，100 会显示成百分比。mod 侧读取
    用 `int()` 转换即可（滑条给的是 float）。另：配置键的 title/tooltip 写翻译键
    （如 RC_CONFIG_CAP_TITLE）能被正常翻译显示（mod 里 TranslationServer 注册）。
    **配置键本身就是 UI 显示文本**（滑条 `_label` 和 CheckButton 都是
    `config_key.to_upper()`），想要漂亮标签就直接用中文键名（v38 起 =
    "魅惑大军上限"/"无上限模式"），schema 里就别再放 title 了（否则标签重复）。
    改键名是破坏性变更：老配置文件里还是旧键，读取要做旧键兜底迁移，并且
    迁移后的值要在 `_init_config` 里写回 `config.data` 再 update_config 存盘——
    ModOptions flatten 时遇到 null 值会直接不渲染该控件。配合 manifest
    `load_before: ["dami-ModOptions"]` 保证迁移跑在 ModOptions 建界面之前。
27. **ModOptions 显示/持久化全链路（v39~v42 三连坑，最终形态）**：
    ① **ModOptions 只改内存不落盘**：`mods_config_interface.gd
    on_setting_changed` 只更新内存 `mod_configs` 再转发信号，存盘是 mod 的活
    （源码注释明写 "TODO, something with this"）→ 处理器里必须写
    `config.data` + `update_config`（v39）。
    ② **"default" 配置是 schema 私产，永不持久**：`ModData.load_configs` 每次
    启动按 manifest config_schema 重建 default 配置（实证：手改 default.json
    为 329，启动游戏后文件被重写回 100），`update_config` 也直接拒绝存
    "default"。ModOptions 显示的恰是 `get_current_config` = default
    （用户档案 current_config 恒为 "default"）→ **界面永远显示 schema 默认值，
    与玩家实际存储无关**（QMtato 同款隐患，它的开关全是默认 true 才没人发现）。
    ③ **存储必须用独立命名配置**（"config_created_by_mod_options"，QMtato 模式），
    并在 `_init_config` 里**直接戳 ModOptions 内存缓存**：
    `ModsConfigInterface.mod_configs[mod名][键] = 值`（ModOptions 比我们先加载，
    其 _ready 已从 default 建好缓存，不戳就永远显示默认值）。
    ④ **写入值必须是 float 不能是 int**：`mod_options_tab.gd:61` 渲染滑条的条件是
    `config_value is float`，int 导致整行被移除（界面里选项直接消失）。JSON 文件
    往返是 float，但 GDScript 里 `_swarm_cap` 是 int → 写 cache/config.data 必须
    `float()` 包一层（v41 的"选项消失"就是这么来的）。
    另：manifest 里同一 mod 同时列 `optional_dependencies` 和 `load_before` 会
    报 duplicate 错误，只留 optional_dependencies。
23. **同名商店道具共享池实例（v33/1.0.33 修"2 币只活 1 只"）**：购买链
    `base_shop.buy_item` → `ItemService.get_rand_item_from_wave` →
    `apply_item_effect_modifications` → DLC1 `update_item_effects`，**非诅咒道具全程
    不 duplicate，直接把 ItemService 池里的共享 .tres 实例推进 RunData.items**
    （只有 curse_item 才 duplicate；读档恢复是逐个 duplicate 的，安全）。
    买两个相同非诅咒道具 = items 数组里同一对象两次 → `get_instance_id()` 相同 →
    **任何按 instance_id 键控玩家道具的逻辑都会塌成一份**。修法：按 my_id 数条目
    （`_reconcile_charm_coins` 天生免疫就是因为它只数数）。原地改 is_cursed 的只有
    debug 菜单，正常流程不用担心共享实例被诅咒污染。
    **教训：玩家道具没有身份，只有数量。要按实例区分同名道具，先自己 duplicate。**

## 环境

- 游戏：`D:\SteamLibrary\steamapps\common\Brotato\`（Brotato.pck + BrotatoAbyssalTerrors.pck，
  定制 Godot 3.7 + 内置 ModLoader 6.x）
- 日志：`%APPDATA%\Brotato\logs\modloader.log` / `godot.log`（每次启动轮转，
  旧文件带时间戳但只留最近几个）；存档：`%APPDATA%\Brotato\76561199083278376\run_v3_0.json`
- 用户当前 mod：Brotils、ContentLoader、QMtato、BoxMatrix、EasyToGetFishHook、
  UnlockAll、RomanceCharm（BossRush、Damage Show 已删）
- 反编译产物（重启电脑会丢，需重跑）：`/tmp/gdre/base` 和 `/tmp/gdre/dlc` 是 GDRE Tools
  v2.6.4 解出的全量游戏源码（只读参考，非常有用）；`/tmp/brotato_mods` 是各 mod 解包的源码
  （重新解：`unzip workshop/content/1942280/<id>/<zip> -d 目录`）
- 用户的 Steam 社区网页打不开（hosts 劫持到 127.0.0.1），别用 FetchURL 拉 steamcommunity

## 待办/可能要做

- v8（1.0.7）已装好，**用户还没实测**。验证点：魅惑瞬间满血、宽限期后会被敌人
  追打死、玩家武器不误伤魅惑怪、**不再有"打不中的隐形怪"**（池子复用修复）；复活币
  （日志 `revival coin registered` / 波末 `revival coin bound to ...`）；boss 10% 复活
  （`boss revive-charm`）；点燃不再跟着魅惑怪
- 若魅惑怪还是太脆/太强：调 `ALLY_GRACE_PERIOD`，或满血改成回固定比例
- 平衡备选：币小弟太强 → 血量打折/死后隔一波回归；boss 太强 → 降概率/不带入下一波；
  boss 磁石太强/弱 → 调 BOSS_MAGNET_* 常量（间隔、系数、上限、数量）；魅惑复活 10% 想提
  就改 BOSS_CHARM_CHANCE
- 用户网络环境中文交流，回复用中文
