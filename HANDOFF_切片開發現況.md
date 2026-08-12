# 交接文件 — 垂直切片開發現況

> 更新日:**2026-08-09**　分支:`feat/g2-hq-layout`　最後 commit:`f1da39b 忽略模擬器與編譯產生的雜訊檔`
> **未提交變更 112 個**(74 修改 / 30 新增 / 8 刪除)——包含所有切片系統與新美術。
> ⚠️ 使用者尚未要求 commit/PR,**動 git 前務必先問**。

---

## 1. 一句話現況

**系統面已超出原訂的 S1–S10**,目前是**「使用者交圖 → 我接線與量測對齊 → 使用者實測回饋 → 微調」**的高頻循環。
美術完成度見 [ArtAssets §0.5 完成進度總覽](ArtAssets_切片_組裝玩具任務.md)(該節持續更新,**以它為準**,本文件不重複列)。

---

## 2. 已完成(全部編譯 exit 0、開機無錯誤)

### 2-1. 原訂系統項 S1–S11

| 項目 | 內容 |
|------|------|
| **S1 多場景** | `mission.scenes[]` + 傳送點;`loadScene()` 逐場景載入(保留機甲 HP) |
| **S2 懸崖** | `pit` 地形類型(視覺缺口、無地面),掉出畫面 → 關卡失敗 |
| **S3 場景砲台** | 靠近按 A 接管(機體暫停、GUN 停火)、crank 瞄準、A 發射、B 解除;**接管時機體自動挪到砲台左側 40px**;提示文字在**砲台正下方的地面**(白底黑字) |
| **S4 敵人重生器** | `scene.respawns[]`(型別/座標/間隔/上限) |
| **S5 REACH / PROTECT** | **REACH＝只看玩家**走到定點;**PROTECT＝只看 NPC**(玩家位置不影響過關):**HOLD** 定點撐時間 / **MOVE** 自走到 `goal_x`;NPC 死亡＝失敗;敵人會主動攻擊 NPC;NPC 血量跨場景延續;**MOVE 時 NPC 領先玩家超過 140px 會停下來等**,頭上顯示 `PROTECT` |
| **S6 BOSS** | 組裝式 BOSS「OVERSEER」:依序拆 **GUN → CANON → CORE**(2026-08-11 隨新圖改名,舊為 ARM→GUN→CORE);武器旋轉瞄準、受擊震動、雷射充能→光束、雙方同框才開打。**死亡演出 3 秒連環爆**(爆完才過關) |
| **S7 進程/選關** | 選關 CLEAR 標記 + 進度、結算 NEXT/RETRY/MISSION SELECT;**焦點預設落在最新未完成關卡**、**crank 可捲動** |
| **S8 暫停** | Playdate 系統選單(Menu 鍵):Retry / Mission Select |
| **S9 開場過場** | **4 頁**(核爆 / 廢墟 / 核心特寫 / 規格對峙),圖與文案皆已定稿 |
| **S10 操作教學** | 覆蓋層,首次進入組裝/商店/關卡各播一次,存檔記錄 |
| **S11 結局過場** | 全破 → 結算出現 `CONTINUE` → 播 3 頁結局 → CREDITS 標題變 **THE END**;存檔記 `tutorial.game_cleared` |

### 2-2. 後續追加的系統

| 項目 | 內容 |
|------|------|
| **關卡架構重構** | **一關一檔 JSON**(`Source/levels/*.json`)+ `level_loader.lua` 啟動掃描 |
| **前景層** | `scene.foregrounds[]` 4 幀動畫,畫在**機體之上、UI 之下** |
| **天空層** | `scene.sky` 最遠層,**橫向平鋪**、視差 0.1;與 `backgrounds` 是**不同系統**(後者只畫一次、視差 0.3/0.6)。<br>⚠️ 2026-08-11 才發現 **M001 一直漏掉**(舊版本文件誤寫「12 個場景全部接上」),已補;檢查指令見 §6-3 |
| **CORE**（[GDD §8.05/§8.05a](GDD_正式版_組裝玩具任務.md)） | `core_data.lua` + `GameState.core_id` + 存檔 + HQ 顯示。**HP ＝核心基礎+零件**、**超重擋安裝**、**跳躍高度倍率**、關卡 `reward_core` 給予,結算後插入**專屬升級畫面** `state_core_upgrade.lua`。⬜ 未做:核心更換介面 |
| **跳躍改制**（[GDD §8.06](GDD_正式版_組裝玩具任務.md)） | 不再是 FEET 專屬 —— **任何有 `jump_height` 的下層零件都能跳**,高度 × 核心 `jump_mult`(CORE1=0 完全不能跳)。**仍綁在焦點上**(焦點在 CANON 時 A 是發射),切換壓力不變 |
| **CANON3 迫擊砲** | 高拋物線 + **落點/命中範圍爆炸**。範圍爆炸是通用機制:任何零件設 `blast_radius` 就有 |
| **命中火花** | 子彈打到敵人/機甲/地形/被盾擋下都有小特效。**目前程式繪製**,放圖即自動改用圖 |
| **運送任務改版** | `stone`→**`crate`**、目標→**`target` 4 幀動畫**;目標**浮空 5px 上下飄**,箱子**踩在平台上表面**;箱子放滿後目標**帶著箱子往左上加速飛出畫面上緣**才過關(舊的擴散圓環已移除) |

---

## 3. 關鍵慣例(接手前必讀)

### 3-1. 關卡 = 一關一檔 JSON
- 每關 = `Source/levels/<id>.json`,`level_loader.lua` 啟動時掃描組成 `_G.MissionData`
- **新增關卡 = 丟 JSON 進資料夾 + 重新編譯**(Playdate 無法熱載入)
- `mission_data.lua` 已清空成 `return {}`(僅作 fallback)
- 現有:M001–M006(原型關)、**M007**(多場景/懸崖/砲台/重生/BOSS)、**M008**(護送:HOLD → MOVE到傳送點 → MOVE到 bunker)

### 3-2. ★★ Sprite sheet 檔名必須是 `名稱-table-寬-高.png`
Playdate 的 imagetable 硬性規定,**這是本專案最常踩的坑**(已發生四次:core、target、feet_walk、以及使用者早期兩次)。
症狀是「改了圖卻沒生效」或「整張圖被當成一格」。

現有:`boss1-table-72-72`(**6格**,2026-08-11 由 7 格改版)、`turret-table-32-32`(2格)、`forground-table-32-32`(4格,注意拼法)、
`npc_walk-table-36-36`(2格)、`arrow-table-32-32`(3格)、`feet_walk-table-48-20`(4格)、
`core-table-24-24`(3格)、`target-table-32-32`(4格)、`enemy_drone-table-32-32`(6格)、
`canon_button-table-32-32`(2格)、`mine_explode-table-50-50`(3格)、
`mine-table-32-16`(3格,2026-08-10 由單張 `mine.png` 改制)、
`claw-button-table-32-32`(2格,2026-08-10 取代佔位的 `claw_control_v`)

⚠️ **換圖時舊檔一定要刪**，`Source/images/` 與 `Builds/.../images/` **兩邊都要**
（pdc 不會清掉來源已消失的 `.pdi`/`.pdt`，會一路留在 pdx 裡）。
2026-08-10 已這樣清掉 `mine.png`（改 `mine-table-32-16`）與 `claw_control_v-table-32-32.png`（改 `claw-button-table-32-32`）。
`.pdi` 與 `.pdt` 同名可以並存、不會編譯失敗,所以**不刪也不會報錯**——這正是它危險的地方:
pdx 裡會留一張永遠用不到的舊圖,而載圖順序是**先試 imagetable、失敗才退回單張**(`entity_enemy.lua`)。

⚠️ **同名不同尺寸的兩張表不能並存**(如 `core-table-16-16` 與 `core-table-32-16`),
pdc 會用它們產生同一個 `.pdt` → 衝突。換圖時**舊的要刪掉**。

### 3-3. 驗證流程(唯一可自動化的部分)
```powershell
# 1) 編譯：必須 EXIT 0
& "E:/PlaydateSDK/bin/pdc.exe" Source Builds/hayatogam_assamble_toy.pdx

# 2) 開機驗證：★必須用 CloseMainWindow() 收尾，不能 taskkill /F
$p = Start-Process "E:\PlaydateSDK\bin\PlaydateSimulator.exe" `
     -ArgumentList "Builds\hayatogam_assamble_toy.pdx" `
     -RedirectStandardOutput boot.log -PassThru `
     -WorkingDirectory "<專案根目錄>"
Start-Sleep 10; $null = $p.CloseMainWindow(); $null = $p.WaitForExit(8000)
# 然後 grep "LEVEL loaded"（應為 8）與 error / attempt / traceback
```
⚠️ **2026-08-10 踩到的坑**:模擬器的 stdout 是**帶緩衝**的,開機 log 只有約 1KB、填不滿緩衝區,
**被 `taskkill /F` 強殺就整份遺失(log 完全空白)**。以前之所以抓得到,是因為 `state_menu` 有每幀 print
把緩衝區灌爆——那兩行已在 2026-08-10 移除(每幀 print 在實機有成本),所以**收尾方式從此必須是關視窗**。
- **可自動驗證**:編譯錯誤、載入期崩潰、關卡載入數
- **必須人工**:畫面、手感、通關流程(無法驅動輸入或看畫面)
- ⚠️ 開機驗證**跑不到**需要輸入才會進入的路徑(HQ、關卡內、商店),那些只能請使用者實測

### 3-4. ★ 1-bit 可讀性:黑字要有白底
地面是純黑填充、天空層上半 45~68% 是黑的 —— **任何黑色文字/線條疊在上面都會消失**。
已因此修過多次。現有的白底處理:HUD 血條、BOSS 血條、砲台提示、NPC 的 `PROTECT`、命中火花(黑線白描邊)。
`state_mission.lua` 有共用的 `drawTextOnWhite()`。

### 3-5. ★ 接美術的標準流程
1. **先確認檔名**(尤其 `-table-` 慣例)與尺寸
2. **用 Python/PIL 把圖的像素攤開**量測命中框、旋轉軸心、槍口、齒輪圓心
   —— BOSS、砲台、CANON、CLAW、DRONE 全都是這樣定位的,**不要用猜的**
3. 量到的座標寫進 `parts_data` / `enemy_data` / `boss_data` 當**資料欄位**,不要寫死在繪製程式裡
4. 接線 → 編譯 → 開機驗證 → 請使用者實測
5. ⚠️ **同一個座標常常有兩個以上的使用者**(繪製端 / 判定端 / 發射端),改一個要全部一起改
   - ★ **關卡編輯器也是使用者之一**,而且最容易被忘記——它不在 `Source/` 底下,grep 搜不到。
     **動到任何「寫進關卡 JSON 的座標語意」時,一定要回頭確認編輯器那邊怎麼算。**
   - ★★ **先把「一共有幾個計算點」列完再動手,不要修一個算一個。**
     背景的 `y` 就是這樣一天內爆兩次(§6-2):第一次修了編輯器語意,漏掉 `ui_offset`;
     第二次才發現**地面線是 `ground_y − 64`**。三個計算點,前兩次都只修兩個。
     已發生的案例:劍的 `sword_length`(繪製 vs 判定)、背景 `y`(遊戲 vs 編輯器 vs `ui_offset`)。

---

## 4. 進行中 / 下一步

### 4-1. ✅ 切片美術已結案（2026-08-12）

**必做素材剩餘 0 張**（逐項見 [ArtAssets §0.5](ArtAssets_切片_組裝玩具任務.md)）。
最後一張是走路敵人 `enemy04-table-40-32.png`。

收尾的四個拍板：
- **新零件 C1 結案** —— 就雷射槍 `GUN2` 一個
- **新敵人 C3 結案** —— 就 `WALKER_ENEMY` 一種（移動快、走走停停、**停下才開火**）
- **選關／結算底圖** —— 沿用 `save_bg` 暫代，不另畫
- **障礙物、結局專屬圖** —— 延後至下階段

**關卡 M001–M003 已完成**（資源數值待調）。

→ **下一步：實機測試 → 檢討 → QA2 工時評估**（見 §4-2）。

⚠️ **尚未實機驗證的項目**（開機驗證都跑不到）：
BOSS 三階段新圖、雷射斜射打盾牌機器人、WALKER 的走停與開火節奏、
結算三段式動畫、標題畫面零件捶動。

### 4-2. 之後:C 內容 + QA 量測
- **C1** 新功能零件、**C4** BOSS roster、**C5** 3–4 關正式關卡
- **QA2 單位成本量測** ← **M2 規模拍板**的依據(25 關/5 王/20 零件要不要下修)
- **請使用者記錄「畫每一項花的實際時間」**,那就是量測原始資料

### 4-2b. ⚠️ 暫時性測試用的東西(記得清掉)

**1. `"final": true` @ [M008.json](Source/levels/M008.json)**
為了測 S11 結局過場——打完 M008 就跳結局。
正式版最終關是 **COMMAND CORE**(尚未製作),那關做好後把 `final` 移過去。

**2. `CORE(test)` 系統選單項 @ [menu_items.lua](Source/menu_items.lua)**
Menu 鍵可切 CORE1/2/3。存在理由:核心取得與更換介面還沒做,而 **CORE1 的 `jump_mult = 0` 代表預設完全不能跳**,不切就沒東西可測。
移除方式:刪 `addCoreSwitcher()` 與兩處呼叫。
⚠️ Playdate 系統選單**上限 3 個自訂項目**,關卡中已用滿。

### 4-2c. ⏸ 已討論但暫緩(切片期間不要動手)
- **零件耐久 / 損壞**(2026-08-08 討論):目的是「讓商店與資源有取捨」,**不是**增加戰鬥變數,
  因此**不必碰傷害模型**。設計共識已寫入 [GDD §8.07](GDD_正式版_組裝玩具任務.md)
  ——含「失敗不扣耐久」「依掉血比例耗損」「高階零件維護費高」「商店加 REPAIR 分頁」與最大風險。
  要重啟時直接照那份走,**不用重新討論**。

### 4-2d. 📋 下一階段構想池(2026-08-10 登記,尚未排程)

使用者一次丟了一整批下個階段的想法,**已整理進 [GDD §15](GDD_正式版_組裝玩具任務.md)**——
上層多零件 + 7 種輔助零件、5 種場景物件、4 種敵人、2 隻 BOSS、CLAW 攻擊力改制。
切片期間**不要動手**,但其中兩項會**改動已驗證的手感**,排程時要特別注意:

- **GUN 改成手動發射**(目前 `operable = false` 全自動;改了它會進入焦點循環,加重切換壓力)
- **CLAW 揮動不再有攻擊力**(改成抓取時才有,會改變 DELIVER 類關卡的節奏)

★ 另外 §15.3 那批場景物件**都要同步補進關卡編輯器**,而編輯器已經落後於程式(見本文件 §6)。

### 4-2e. 🔒 跨平台移植(上架 Catalog 之後才啟動)

Android/iOS(crank 改虛擬 UI)的可行性評估已做完並封存在 **[GDD §16](GDD_正式版_組裝玩具任務.md)**。
**啟動條件是「Playdate 版已上架 Catalog」,在那之前不做任何移植工作,也不為了移植而改架構。**

三行速讀:技術可行度高(`playdate.*` 只用到約 25 個呼叫,Lua 邏輯幾乎全可留);
crank 只有 8 個呼叫點、換觸控不成問題;**真正的風險是焦點切換模型會被觸控溶解掉**。
結論:**要離開 Playdate 的話第一站應該是 PC 而不是手機。**

### 4-3. 仍待使用者拍板
- 20 零件分類(純變體 vs 新功能型)
- +3 敵人行為型別、+5 BOSS 的具體規劃
- 進程結構:線性解鎖 vs 分支選關
- 產品名稱(定名前查 Playdate Catalog 與商標)

---

## 5. 常用調參位置(使用者常要求微調)

### 5-1. 手感 / 數值

| 想調什麼 | 位置 |
|---|---|
| **移動手感** | `parts_data` 的 `move_speed`(FEET 2.0);滑行慣性 `coast_friction`(FEET 0.55、預設 `MechController.COAST_FRICTION` 0.85);走路步頻 `state_mission.lua` 的 `FEET_STRIDE_PX`(8,**每移動這麼多像素換一幀**,不是計時) |
| **跳躍高度** | `parts_data` 的 `jump_height`(WHEEL1 30/WHEEL2 42/FEET 64)× `core_data` 的 `jump_mult`(0/1.0/1.3)。**調的是高度不是初速**,初速由 `entity_mech.lua` 的 `MECH_GRAVITY` 反推(★必須與 `state_mission.lua` 的 `GRAVITY` 一致) |
| **核心 HP / 負重上限** | `core_data.lua` 的 `base_hp`(30/60/100)、`weight_cap`(16/24/34)、`jump_mult`、`jump_label`。零件重量在 `parts_data` 的 `weight`。★改任一邊都直接改變可用 build |
| **懸崖落地容錯** | `entity_controller.lua` 的 `FOOT_INSET_RATIO`(0.25)與 `STEP_UP_MAX`(12)。★`STEP_UP_MAX` **必須 > 最快跳躍的落地速度**(CORE3+FEET ≈ 9.1),否則跳不上去 |
| **護送 NPC 等待距離** | `entity_controller.lua` 的 `NPC_WAIT_DISTANCE`(140);單一 NPC 可用 `scene.npc.wait_distance` 覆寫 |
| **砲台** | `entity_controller.lua` 砲台初始化:`pivot_x/y`(10,10)、`barrel_len`(21)、`grav_mult`(40)、`speed_mult`(30);crank 靈敏度 `WEAPON_CRANK_DEG_PER_ROTATION`(30);**接管站位** `TURRET_STAND_OFFSET`(40,★必須 < `weaponNear` 的 range 44) |
| **CANON3 迫擊砲** | `parts_data` 的 `blast_radius`(44)/`blast_damage`(18)＋`projectile_speed_mult`(24)/`projectile_grav_mult`(40)。範圍爆炸實作在 `entity_controller.lua` 的 `triggerBlast()`,**任何零件設 `blast_radius` 就有** |
| ★ **雷射槍 GUN2** | `parts_data` 的 `GUN2`:`fire_cooldown`(2.2,比 GUN 的 1.0 長)、`laser_speed_mult`(150,GUN 砲彈是 40)、`laser_length`(40,線段長度)、`laser_thickness`(3)、`laser_range`(420)、`projectile_damage`(12)。<br>★ **手動**(`operable = true`)→ 進焦點循環、按 A 發射,面板右格是共用的 `canon_button`。<br>★ **貫穿**:每道光束記著自己打過誰(`L.hit` 集合),沿路每隻各扣一次、不重複。實作在 `entity_controller:updatePlayerLasers()`。<br>⚠️ 冷卻計時器在 `updateParts` **所有槍都會累加**,只有「自動開火」那段跳過 `operable` 的——否則手動槍打完第一發後計時器不動,再也打不出來 |
| ★ **交戰範圍** | `entity_controller.lua` 的 `ENGAGE_MARGIN`(96，約 2 個機身)。敵人只在「畫面內 + 這段餘裕」內**才攻擊，也才會被打到**。<br>★ 判定集中在 `EntityController:isEngageable()`，**敵人開火／砲彈命中／雷射命中三處共用** —— 只做一半會變成「看不到卻被打」或「明明在打卻扣不到血」。<br>移動不受限，離開範圍時重置開火節奏。BOSS 維持自己更嚴格的「雙方同框才開打」，未套用這個餘裕 |
| ★ **雷射槍 GUN2** | `parts_data` 的 `GUN2`：`fire_cooldown`(2.2)、`laser_speed_mult`(150)、`laser_length`(40)、`laser_thickness`(3)、`laser_range`(420)、`projectile_damage`(12)。<br>★ **手動**(`operable = true`) → 進焦點循環、按 A 發射，面板右格是共用的 `canon_button`。<br>★ **貫穿**：每道光束記著自己打過誰(`L.hit`)，沿路每隻各扣一次。<br>★ **光束方向跟著槍口**：發射時記下單位方向 `dx/dy`（速度已由 `applyMechTilt` 依地形角度旋轉），**繪製與命中都用它**。命中用線段-矩形（slab method），不能再用水平帶。<br>⚠️ 冷卻計時器在 `updateParts` **所有槍都會累加**，只有「自動開火」那段跳過 `operable` 的——否則手動槍打完第一發就再也打不出來 |
| ★ **WALKER 敵人** | `enemy_data` 的 `WALKER_ENEMY`：`move_speed`(55，BASIC 是 20)、`move_duration`(1.6)、`pause_duration`(1.4)、`walk_fps`(8)、`fire_only_when_stopped`(true)。<br>★ 走路動畫由 `MOVE_PAUSE` 分支自己控制（第1格＝站立、第2~3格＝走路），**不要設 `anim_fps`**（那是無條件循環，停著也會走）。<br>★ `flip_x = true`：原圖面向右，但本作敵人一律面向左。這是通用欄位，以後任何畫反方向的敵人都可用 |
| **BOSS 各階段武器** | `boss_data.lua`:`aim_time`/`aim_speed`/`cooldown`/`speed_mult`/`grav_mult`、雷射 `charge`/`beam_time`/`thickness`。<br>★ 血條標題「name  [label  n/3]」總寬 **≤ 220px**。2026-08-11 重量:最長標籤變成 `CANON`(5字)→後綴 135px,**name 上限只剩 85px**(OVERSEER=76,餘 9px)。<br>⚠️ 標籤寫成 `CANNON`(雙 N)會變 221px **超 1px 就折行**——改標籤前先用 §5-4 的字寬腳本量 |
| **BOSS 死亡演出** | `entity_enemy.lua` 的 `BOSS_DEATH_DURATION`(3.0)與 `BOSS_DEATH_BURST_INTERVAL`(0.22)。★`BOSS_KILL` 判定本來就等 `is_exploding` 結束,**改長度＝改「爆炸播完才過關」** |
| **運送目標** | `entity_controller.lua` 開頭一整組:浮空 `TARGET_FLOAT_H`(5)、飄動 `TARGET_BOB_AMP`(3)/`TARGET_BOB_SPEED`(2.2)、換幀 `TARGET_FRAME_TIME`(0.12)、**平台上表面** `TARGET_PLATFORM_TOP`(8,箱底對齊這條線)、飛走 `TARGET_FLY_VX`(-70)/`TARGET_FLY_VY`(-110)/`TARGET_FLY_ACC`(220,加速起飛)/`TARGET_FLY_MAX_T`(3.0,保險)。<br>★**飛到完全離開畫面上緣才消失**,不是固定秒數;箱子位置統一由 `stoneRestPos()` 算 |
| **選關捲動** | `state_mission_select.lua` 的 `CRANK_DEG_PER_STEP`(30)、`VISIBLE_ROWS`(4,★與 draw 共用,改版面兩邊一起看) |

### 5-2. 圖片座標(全部量自像素,寫成資料欄位)

| 項目 | 位置與注意 |
|---|---|
| **CANON 砲管** | `parts_data` 的 `barrel_offset_y`(**現為 −2**,負值＝往上)。由「砲管左端圓心 y=7.5 vs 底座樞紐 y=6.0」推得。★**旋轉軸心與砲彈發射點會一起移**,共 6 處讀它 |
| **CLAW 支點** | `parts_data` 五組:`arm_mount_x/y`(21.5,7.5＝底座**右**齒輪圓心)、`arm_pivot_x/y`(0,7)、`claw_pivot_x/y`(35.5,7.5＝臂右端圓盤圓心)、`upper_pivot_x/y`(0,12＝上爪**左下角**)、`lower_pivot_x/y`(0,0＝下爪**左上角**)、`grip_hold_dist`(12＝夾持點,石頭放這裡)。<br>★**繪製端與抓取判定端共用同一組**,改一邊沒改另一邊＝「看起來夾到卻抓不到」 |
| **DRONE 槍口** | `enemy_data` 的 `bullet_offset_x/y`(16,24＝下方槍管出口)。★發射點有加 `drone_vertical_offset`,否則子彈會偏離浮動中的機身 |
| **地雷 MINE 警示燈** | `mine-table-32-16.png` 3 格共用同一張 32×16 畫布:**第 1 格本體在 y=9~15、第 2/3 格警示燈在 y=2~9**,所以疊畫時**用和本體完全相同的座標**,不要另外加偏移。閃爍參數在 `enemy_data` 的 `warn_frame_a/b`、`warn_blink_speed`(10)。<br>★ 本體由 `Enemy:draw()` 一般路徑畫(`self.image` ＝第 1 格),燈由 `drawMineExplosion()` 疊在後面,**順序不能反** |
| **SWORD 敵人的劍** | `enemy_data` 的 `SWORD_ENEMY` 四欄:身上掛點 `sword_pivot_offset_x/y`(0,0＝敵人圖中心)、劍圖內軸心 `sword_image_pivot_offset_x/y`(**−17**,0＝握把圓環中心 (7.0,8.0) 相對圖中心 (24,8))、劍長 `sword_length`(**41**＝圓環中心 x=7 → 劍尖 x=48)。<br>★**繪製端**(`entity_enemy.lua` drawSword)**與命中判定端**(`entity_controller.lua` 的 `SWING SWORD` 區塊)**共用這四欄** —— 2026-08-10 之前判定端是寫死的 `sword_length = 30` 且不讀 pivot,是「看起來砍到卻沒扣血」的來源 |
| **BOSS 命中框/軸心/槍口** | `boss_data.lua` 各 part 的 `dx,dy,w,h` / `pivot_x,pivot_y` / `muzzle_x,muzzle_y`,全部是 **72×72 內的座標**(各格原位對齊)。<br>★ 2026-08-11 隨 6 格新圖全部重量過,數值旁有註明量法。<br>★ 非武器的三格在 boss 層級:`cell_body`(1)/`cell_pipe`(2)/`cell_track`(3);武器格號寫在各 part 的 `cell`,**不要另外再列一份**(舊版的 `cell_weapon1/2/laser` 從來沒被讀,已刪) |
| **BOSS 履帶 / 管子 / 最終階段** | `cell_track` 是整條 72×16,**不旋轉**(舊版兩顆小輪的 `drawRotated` 與 `wheel_angle` 已移除)。<br>管子上下移動幅度 `pipe_vibrate`(−2)。<br>`hide_body_on_final = true` ＝**最終階段隱藏本體**,畫面只剩履帶＋雷射槍 |

### 5-3. 版面

| 項目 | 位置與注意 |
|---|---|
| **過場圖 / 對話框** | 圖 **400×163**;文字框滿版、上緣 `DIALOG_Y = 163`,**三處必須一致**(`state_intro`/`state_outro`/`state_mission`) |
| **關卡 HUD** | `state_mission.lua` 第 4 段:玩家血條在**操作面板右側、與面板共用同一塊白底**。★不要移回左上角——會被 BOSS 血條的白底(x=87~368、y=3~33)蓋住 |
| ★ **零件圖比格子高時** | `parts_data` 的 `align_image_top`。`true`＝**上緣對齊格子上緣**、多出來的往下超出格子(**FEET 48×20**、**WHEEL2 48×20** 都是);`false`(預設)＝底部對齊格子底部,可再用 `image_offset_y` 微調。<br>★ 機體上、HQ 組裝格、HQ 預覽、商店、關卡預覽**共 7 處都讀這一個欄位**,所以換圖變高時**只要改這個布林**,不必逐處改繪製程式 |
| **移動零件面板** | `wheel_panel.png` **2 格(64px)** 滑軌 + **第 3 格**跳躍鈕(能跳)或 `empty.png`。滑塊行程 `STICK_MAX_OFFSET`(23)＝(軌道64−滑塊18)/2,**換面板圖要一併改** |
| **CLAW 開合開關** | 面板左格,`claw-button-table-32-32`(2 格)的**第 1 格＝開、第 2 格＝夾起**。<br>★ 2026-08-10 由佔位圖 `claw_control_v`(3 格)換來,**兩張圖的順序剛好相反**(舊圖 1=關/2=開)——換圖時 [entity_mech_render.lua](Source/entity_mech_render.lua) 那一行沒跟著改的話,按鈕會顯示**相反**的狀態。舊圖與 fallback 分支都已刪除 |
| ★ **結算畫面** | [state_result.lua](Source/state_result.lua) 開頭一區。**成功只有 `MISSION COMPLETE` 一行**(2026-08-11 移除了第二行訊息與 CORE UPGRADED 橫幅——核心升級有專屬畫面 `state_core_upgrade` 接在後面,重複了)。<br>★ **失敗仍保留第二行**＝失敗原因(掉下懸崖／時間到／機體損毀／NPC 陣亡),那是唯一的失敗回饋,不要一起砍。<br>**資源三段式演出**:現有數字 → 閃爍 `+N` → 最終數字。`ANIM_HOLD_F`(18幀≈0.6s)／`ANIM_FLASH_F`(36幀≈1.2s)／`ANIM_BLINK_F`(4,與 `state_shop` 的 `res_flash_timer` 同一套)。<br>版面 `RES_LABEL_X`(118)／`RES_VALUE_R`(248,數字**右**對齊)／`RES_PLUS_X`(260)／`RES_Y0`(100)／`RES_LINE_H`(22)。<br>★ 加獎勵**之前**的存量在 setup 就先記進 `before_steel/copper/rubber`,不能事後反推 |
| ★ **HQ 任務框(兩行)** | `HQ_LAYOUT.mission`(x=6,y=19,w=387,h=49)。第 1 行＝目標說明、第 2 行＝`REWARD S:n C:n R:n`(2026-08-11 新增,出擊前就看得到報酬),兩行**一起**垂直置中、行距 4px。<br>⚠️ **`REQ:` 必須畫在第 2 行右側,不能放第 1 行** —— 說明最長 353px(`Deliver the stone to the target zone`)右緣到 **365**,而 `REQ: CLAW` 左緣在 **301**,同一行會疊字(**M002/M003/M005 三關就是這個組合**)。REWARD 只有 225px、右緣 237,放同一行才不會撞 |
| **HQ / 商店版面** | `state_hq.lua` 的 `HQ_LAYOUT`、`state_shop.lua` 的 `SHOP_LAYOUT` |
| ★ **標題畫面背景** | [state_menu.lua](Source/state_menu.lua) 開頭一整區:排數 `ROWS`(4)、每排每幀位移 `ROW_SPEEDS`(`{0.7,-0.5,0.9,-0.6}`,**正=右／負=左**)、一段寬度 `STRIP_W`(480)、零件間距 `ROW_GAP_MIN/MAX`(14/46,越大越稀疏)、排內上下抖動 `ROW_JITTER`(6)、減淡 `BG_DIM`(0.5)。<br>★ `cover.png` 是**透明底**,只剩標題字 —— 先畫零件層、再疊 cover,**順序不能反**。<br>★ 每排在 setup 合成成一張 `STRIP_W` 長條圖,畫兩段循環;**超出右緣的零件會補畫在 `x − STRIP_W`**,否則接縫會斷。<br>⚠️ `BG_DIM` 存在的理由:零件圖 60~83% 是黑的,不減淡會把黑色標題字吃掉(§3-4)。設 0 = 零件清晰但標題糊。<br>捲動推進在 `update()` 用**每幀像素數**(refresh rate 固定 30fps),不算 dt |
| **存檔 / 選關畫面底圖** | 兩個畫面都吃 `images/save_bg`(選關是**暫用**,專屬 `mission_select_bg` 未做)。<br>⚠️ `save_bg.png` 是**滿版細點陣場景圖**,不是 `hq_bg` 那種留白框線底圖 —— 所以兩個檔各自有一份局部的 `drawTextOnWhite()`,文字一律鋪白底、清單列未選中先填白再描框(選中則沿用黑底白字)。<br>★ 這是 §3-4 的直接應用。**日後換成留白式底圖時,把那些白底拿掉即可,版面座標沒動過** |
| ⚠️ **HQ 組裝格畫的是 `_img_scaled`** | 預先合成圖,在 `state_hq` setup 內產生(CANON＝底座+上移砲管;CLAW＝底座+臂+爪)。**改組裝格外觀要改那段**,改下方的 `elseif _img` 分支沒有作用(那是走不到的 fallback)。CLAW 的合成圖上下各超出格子 4px,靠 `pdata._scaled_offset_y` 對回格子 |
| 地面表面層 | `entity_controller.lua` 的 `SURFACE_T`(6)、`self.surface_dither`(0.5, Bayer8x8) |
| 過場/對話文案 | `intro_data.lua` / `outro_data.lua` / 關卡 JSON 的 `scene.dialog` |

### 5-4. ★ 過場文字寬度:量 px,不要只數字元

文字框可用寬度 = **384px**(滿版 `box_w` 400 − 左右 padding 16)。字寬在 `fonts/Assemble.fnt`,`tracking=1`。
**40 個字元就可能超過**(實測 `The weak toys are torn apart by weapons.` = 40 字元 / 400px → 折行)。折行會讓打字機節奏斷掉。

```bash
python -c "
import io,re
w={};t=0
for ln in io.open('Source/fonts/Assemble.fnt',encoding='utf-8',errors='replace'):
    ln=ln.rstrip('\n')
    if ln.startswith('tracking='): t=int(ln.split('=')[1]); continue
    if ln.startswith('--') or not ln.strip(): continue
    p=ln.split('\t')
    if len(p)==2 and p[1].strip().isdigit(): w[' ' if p[0]=='space' else p[0]]=int(p[1])
px=lambda s: sum(w.get(c,9)+t for c in s)-t if s else 0
for s in re.findall(r'\"([^\"]*)\"\s*,', io.open('Source/intro_data.lua',encoding='utf-8').read()):
    if s.startswith('images/'): continue
    print('%4dpx %s %s' % (px(s),'WRAP!' if px(s)>384 else 'ok   ',s))
"
```

---

## 6. 關卡編輯器(網頁工具)

**https://claude.ai/code/artifact/b9dcff9f-7b4f-41b1-97d9-1cb075bad0a2**

- **同一個網址持續更新**——要改用 `Artifact` 工具帶 `url` 參數 republish,不要開新的
- 原始檔在 scratchpad:`level_editor.html`(session 換了會消失 → **要再改需先用 WebFetch 抓回內容**)
  - ★ WebFetch 抓回來的是**已發佈版**,開頭被塞了 `<!doctype html>…<head>…<body>` 的 frame-runtime 前綴。
    republish 前**必須從 `<title>` 砍到 `</body></html>` 之前**,只留原始內容,否則會被重複包一層
- 功能:新增/載入本機 JSON(可拖放)、多場景分頁、每場景目標、地形(含 pit)、敵人/BOSS/石頭/目標/背景/**天空層**/傳送點/重生點/REACH旗/NPC/bunker/砲台/前景
- ⚠️ **編輯器仍未支援的欄位**:`sky_parallax`、`sky_y`、`reward_core`、`final`、`npc.wait_distance`
  —— 這些目前得手動編 JSON。**用編輯器重存既有關卡時,這些欄位會整個消失**,記得補回去
  - `scene.sky` **已於 2026-08-11 補上**(頂端「☁ 天空層」勾選框),新場景預設帶天空層
- **沙盒限制**:下載常被擋、`navigator.clipboard` 無效 → 用 `document.execCommand('copy')`
- 改完務必:抽出 `<script>` 內容跑 `node --check`

### ★ 6-1. 背景圖庫:連結 `Source/images` 資料夾(2026-08-11 新增)

> 舊版這裡寫「無法讀取本機資料夾」——**那條限制已解除**。沙盒不能主動掃硬碟,
> 但可以由使用者**授權一次**(`<input type="file" webkitdirectory>` 或拖放),這在 iframe 裡是允許的。

頂端「🖼 連結 images」按鈕 → 挑一次 `Source/images` 資料夾,編輯器會:

1. 自動抓出所有 `bg_buildingN.png`(`BG_NAME_RE`),**清單不必再手動維護** —— 新增 `bg_building8` 直接就出現
2. 讀 `naturalWidth/Height` 當**真實尺寸**,預覽框與拖曳命中框都跟著走
3. 在畫布上**畫真圖**(`imageSmoothingEnabled = false`,1-bit 不會被插值糊掉)
4. 存進 `localStorage`(key `assembleToy.bgLib.v1`,存 dataURL),**下次開頁面自動帶回**;**改了圖要重連一次**

也可以**直接把 png 拖進頁面**——拖放處理已分流:`.json` → 載入關卡、`bg_buildingN.png` → 併入圖庫。
狀態字在按鈕右邊,**右鍵可清除圖庫**改回內建清單。
沒連結時退回 `BG_FALLBACK`(寫死的 7 張 + 尺寸),所以換台電腦開也不會壞。

### ★ 6-2. ★★ 背景的 `y` ——「畫面上的地面線 ≠ `scene.ground_y`」

`entity_controller.lua` 的背景繪製:`screen_x = bg.x - camera_x * parallax`、**`screen_y = bg.y`**(不吃垂直位移)。
所以 `y` ＝**圖片左上角的螢幕 y**,底邊 = `y + 圖高`。

#### ⚠️⚠️⚠️ 最重要的一條:地面線是 `ground_y − 64`

[state_mission.lua](Source/state_mission.lua) 呼叫
`EntityController:init(current_scene, enemies, MOVE_SPEED, UI_HEIGHT)`,
把 **`UI_HEIGHT = 64`** 當 `ui_offset` 傳進去,而 [entity_controller.lua](Source/entity_controller.lua) 內部做了:

```lua
safe_ground_y = safe_ground_y - ui_offset   -- 220 - 64 = 156
```

| 東西 | 畫在哪 |
|---|---|
| 地形／敵人／NPC／砲台／石頭…(一切 **ground-relative**) | **`ground_y − 64`**(M001 = **156**) |
| **背景 `backgrounds`** | 原始 `bg.y`,**不減這 64** |
| 天空層 `sky` | `sky_y`(預設 0)＝螢幕最上緣,也**不減** |

→ **「背景踩在地面線上」＝ 底邊 = `ground_y − 64`,不是 `ground_y`。**
`state_mission.lua` 那句 `local gy = ... or 156` 的註解其實早就寫著 156,查的時候記得看它。

#### 這個坑 2026-08-11 一天內連爆兩次

**這是「同一個值有多個計算點」(§3-5 第 5 條)最貴的一次,共有三個計算點,我前兩次都只修了兩個。**

| 次 | 症狀 | 原因 |
|---|---|---|
| 第 1 次 | 編輯器排好的背景進遊戲**整批飄到畫面上方** | 編輯器用自創語意 `250 − 圖高 − y`,與遊戲的 `screen_y = bg.y` 無關 |
| 第 2 次 | 改成遊戲語意後**仍差 64px** | 漏掉 `ui_offset` —— 誤以為地面線是 `ground_y`(220),其實是 156 |

**現行修法**(編輯器):
```js
const UI_HEIGHT = 64;                     // 必須與 state_mission.lua 一致
function effGround(){ return level.ground_y - UI_HEIGHT; }   // 畫面上真正的地面線
function bgYToCanvas(y){ return y + V_BASE - effGround(); }
function canvasToBgY(cy){ return Math.round(cy - V_BASE + effGround()); }
```
- 放置/拖曳時**游標對齊圖的底邊**(`y = canvasToBgY(游標) − 圖高`)
- 屬性面板即時顯示「地面線是 156(= ground_y − UI_HEIGHT)」與目前**沉入/浮空幾 px**
- ★ **畫布上畫出遊戲畫面範圍**:螢幕上緣 `y=0`、**UI 面板上緣 `y=176`**(以下淡化標「看不到」)
  —— 這才是根本解。之前編輯器完全沒有畫面邊界的參照,只能憑感覺放

#### 沉入是正常的,浮空才是問題

背景在地平線後方,底邊沉到地面線以下**本來就會被地面填色蓋住**,是對的。
盤點指令(換背景圖或改完關卡後跑一次):

```bash
python -c "
import json,glob,os
H={'bg_building1.png':128,'bg_building2.png':128,'bg_building3.png':128,
   'bg_building4.png':64,'bg_building5.png':64,'bg_building6.png':64,'bg_building7.png':32}
UI=64
for f in sorted(glob.glob('Source/levels/*.json')):
    d=json.load(open(f,encoding='utf-8'))
    sc=d.get('scenes') or ([d['scene']] if 'scene' in d else [])
    for i,s in enumerate(sc):
        for b in s.get('backgrounds') or []:
            nm=b['image'].split('/')[-1]; bot=b['y']+H[nm]; dd=bot-(s['ground_y']-UI)
            print('%-10s s%d %-20s %s'%(os.path.basename(f),i,nm,
                  '貼齊' if dd==0 else ('沉入 %d'%dd if dd>0 else '★浮空 %d'%(-dd))))
"
```

**2026-08-11 盤點結果**:M001 已由使用者手動排好(貼齊~沉入 20);
M002–M006 的 `bg_building4` 仍**浮空 27~37px**、M007 s2 浮空 1px —— 尚未處理,要不要修由使用者決定。

#### 換圖高度時的座標重算規則

⚠️ **換背景圖的高度,關卡 JSON 的 `y` 一定要重算**,否則建物會浮空或沉到地下。
2026-08-11 背景由 4 張改 7 張、尺寸全變時,M007/M008 共 6 個場景是這樣重算的:

- **x：保留中心**(不是保留左緣 —— 寬度變化會讓構圖整個偏掉)
- **y：保留底邊**(`new_y = 舊底邊 − 新圖高`),維持原本「離地面線多高」的關係
- 例外:`bg_building2` 舊圖 250 高、底邊 310,照公式算只剩 38px 露出 → 改成貼齊

### ★ 6-3. 天空層:M001 曾是唯一沒有 `sky` 的關

2026-08-11 發現 **M001 從頭到尾就沒有 `scene.sky`**(不是編輯器弄丟的,git HEAD 的舊版也沒有)。
本文件舊版寫的「12 個場景全部接上」是錯的,已補上。

**檢查全部關卡有沒有天空層**:
```bash
python -c "
import json,glob,os
for f in sorted(glob.glob('Source/levels/*.json')):
    d=json.load(open(f,encoding='utf-8'))
    sc = d.get('scenes') or ([d['scene']] if 'scene' in d else [])
    print('%-10s %s' % (os.path.basename(f), [('sky' in s) for s in sc]))
"
```
★ 新增關卡後跑一次 —— **少了天空層畫面不會報錯,只是變空,很容易漏掉**。


### ★ 6-4. 目標(objective)是唯一來源,`category` 已不再手動選(2026-08-12)

編輯器原本有「類型」與「本場景目標」**兩個**下拉,已移除「類型」。

**為什麼不能只是拔掉選單**:`category` 雖然**遊戲完全沒讀**
(`grep -rn category Source/*.lua` 只會命中 `state_hq` 的 `parts_by_category`,那是零件分類、無關),
但它原本**驅動著頂層 `objective`** —— 而頂層 objective 遊戲**有讀三處**:

| 讀取點 | 用途 |
|---|---|
| `state_mission_select.lua` | 選關列表顯示的目標文字 |
| `state_hq.lua` | 出擊前的任務說明 |
| `state_mission.lua` | **場景沒帶 objective 時的後備**(`scene.objective or mission.objective`) |

**現行規則**:
- 「本場景目標」不再有空值,一律有值(預設 `ELIMINATE_ALL`)
- **頂層 `objective` ＝ 第 1 個場景的目標**
- ★ **`category` 已完全移除**(2026-08-12):8 個關卡檔都拿掉了,編輯器也不再輸出。
  確認方式:`grep -rn "\.category" Source/ --include=*.lua` 只會命中 `state_hq` 的
  `parts_by_category` / `selected_category`(那是**零件**的 TOP/BOTTOM 分類,與任務無關)
- 目標描述表抽成共用的 `OBJECTIVE_DESC`,`sceneToJSON` 與 `buildMissionObject` 共用一份

⚠️ **載入舊檔的陷阱**:場景沒有自己的 objective 時,預設值**必須取「整關的 objective」**,
不能寫死 `ELIMINATE_ALL` —— 否則 DELIVER 類的關卡會被讀成清敵。
(已用真實的 8 個關卡檔模擬「載入 → 匯出」對照過,7 關完全一致。)

★ **新增關卡時的自我檢查**:目標與場景物件要對得起來 ——
`REACH` 需要 `reach`、`PROTECT` 需要 `npc`、`DELIVER_STONE` 需要 `delivery_targets`、
`BOSS_KILL` 需要 `enemies` 裡有 `type: "BOSS"`。缺了不會報錯,但那關**永遠過不了**。

### ★ 6-5. 頂層 objective 與場景 objective 要對得起來

2026-08-12 因為上面那項而發現:**M008 的頂層 objective 是錯的** ——
三個場景都是 `PROTECT`,頂層卻寫 `ELIMINATE_ALL` + `description: "demo"`,
所以選關列表與 HQ 把那關的說明顯示成 `demo`。玩法不受影響(場景各自有 objective 會覆寫),純粹是顯示錯。已修正。

**盤點指令**(改完關卡跑一次):
```bash
python -c "
import json,glob
for f in sorted(glob.glob('Source/levels/*.json')):
    m=json.load(open(f,encoding='utf-8'))
    top=(m.get('objective') or {}).get('type')
    sc=m.get('scenes') or ([m['scene']] if 'scene' in m else [])
    types=[(s.get('objective') or {}).get('type') for s in sc]
    first=types[0] if types else None
    print('%-5s 頂層=%-14s 場景=%s%s'%(m['id'],top,types,
          '' if (first is None or first==top) else '  ★不一致'))
"
```
★ 場景是 `None` 代表它沿用頂層,那是正常的;**只有「場景 1 有值且與頂層不同」才要修**。

---

## 7. 使用者偏好(從協作觀察)

- 動作/平面設計為專長,程式靠 AI;**版面與手感由他主導**,我負責實作與量測對齊
- 偏好**先討論設計再實作**(BOSS、護送戰、跳躍歸屬、零件耐久都是先確認方向)
- 大量的**小幅視覺微調**(位置差幾 px、動畫速度),要快速迭代
- 回報問題常只給現象(「文字沒顯示」「位置不對」),**要主動找根因**——
  九成是**座標系不一致**(世界/螢幕)、**圖層順序**、**檔名慣例**、或**同一個值有兩個計算點**
- 會**推翻自己前一個決定**(如砲管 −10 → −5 → −2),照做即可,但若量測結果與指示不符要**講出數字**讓他判斷
- 文件一律**繁體中文 Markdown**

---

## 8. 給下一個 session 的最短路徑

1. 讀本文件 §3(慣例)與 §5(調參位置)
2. 美術進度看 [ArtAssets §0.5](ArtAssets_切片_組裝玩具任務.md);設計決策看 [GDD §1.5 / §8.05–8.07](GDD_正式版_組裝玩具任務.md)
3. 使用者丟圖過來時 → 走 §3-5 的五步流程
4. 使用者回報「位置不對」時 → **先用 PIL 量像素再動手**,不要猜
5. 每次改完:`pdc` 編譯 + 開機驗證 + **明確告知哪些部分只能人工實測**
