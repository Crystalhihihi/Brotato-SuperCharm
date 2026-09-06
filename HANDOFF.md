# RomanceCharm 交接文档（2026-09-05）

## 项目是什么

Brotato（土豆兄弟，含深海魔怪 DLC）的本地 mod「RomanceCharm」，增强魅惑机制。
源码：`D:\BrotatoMods\RomanceCharm\mods-unpacked\LocalMods-RomanceCharm\`
打包安装：项目根目录 `bash pack.sh`（**游戏必须先关闭**，否则 zip 被占用写入失败），
会生成 zip 到 `D:\SteamLibrary\steamapps\workshop\content\1942280\3790215220\RomanceCharm.zip`。

**重要**：这个游戏只扫描「已订阅工坊条目」的文件夹里的 zip（加载器逻辑见
`load_steam_workshop_zips`，只认 `int(文件夹名) in 已订阅列表`）。

**已发布**：自己的工坊条目 ID = **3796234584**（2026-09-06 用 GodotWorkshopUtility 上传，
标题超级魅惑 SuperCharm）。zip 已迁移到自己条目文件夹，UnlockAll 寄生 zip 已删除。
更新 mod 流程：改代码 → pack.sh（游戏需关闭）→ GodotWorkshopUtility 填 ID 3796234584
点 Upload。注意：自己条目更新后 Steam 会重新下载覆盖本地 zip → 本地改动后重新跑 pack.sh。
另：发布前在游戏目录建了 `steam_appid.txt`（内容 1942280），是工具初始化的前提。

## mod 当前功能（v21 / manifest 1.0.21，已打包安装，zip 输出到自己工坊条目 3796234584）

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
    `cl.load_data_by_dictionary({"items": [item]}, "LocalMods-RomanceCharm")`。
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
16. **魅惑大军占刷怪名额**：每波有 `max_enemies` 上限（wave_data，随波数放大），新刷组
    触发时若 `enemies.size() > max_enemies` 会**随机处死超额怪（不掉落）**——魅惑怪在
    enemies 列表里照样占名额、照样可能被处死。boss 在 bosses 列表不占此名额。
    这是"魅惑海大了小怪变少"的原因，原版机制，不改。
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
