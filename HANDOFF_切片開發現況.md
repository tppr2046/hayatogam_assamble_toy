# 交接文件 — 垂直切片開發現況

> 更新日:2026-08-01　分支:`feat/g2-hq-layout`　最後 commit:`3e1663a 第一階段功能完成，待製作美術`
> **目前有 36 個未提交變更**(切片全部系統 + 新美術),尚未 commit。

---

## 1. 一句話現況

**正式版垂直切片的「系統項(WBS A 區 S1–S10)全部完成並驗證**;目前停在**內容製作階段**——使用者正在依 [ArtAssets 清單](ArtAssets_切片_組裝玩具任務.md) 產出美術,每完成一項就交給我接線與調整。

---

## 2. 已完成(全部編譯 exit 0、開機無錯誤)

| 項目 | 內容 |
|------|------|
| **S1 多場景** | `mission.scenes[]` + 傳送點;`loadScene()` 逐場景載入(保留機甲 HP) |
| **S2 懸崖** | `pit` 地形類型(視覺缺口、無地面),掉出畫面 → 關卡失敗 |
| **S3 場景砲台** | 靠近按 A 接管(機體暫停、GUN 停火)、crank 瞄準、A 發射、B 解除;砲管繞軸心轉、子彈自槍口射出走拋物線 |
| **S4 敵人重生器** | `scene.respawns[]`(型別/座標/間隔/上限) |
| **S5 REACH / PROTECT** | REACH 走到定點;PROTECT 兩模式 **HOLD**(定點撐時間)/**MOVE**(護送到 bunker);**敵人會主動攻擊 NPC**;NPC 血量**跨場景延續** |
| **S6 BOSS** | 組裝式 BOSS:依序拆武器 → 最終露出內部雷射槍;武器旋轉瞄準(發射前先轉、有預告)、受擊震動、零件爆炸特效、雷射充能→光束、雙方同框才開打 |
| **S7 進程/選關** | 選關 CLEAR 標記 + 進度、結算 **NEXT/RETRY/MISSION SELECT** |
| **S8 暫停** | Playdate 系統選單(Menu 鍵):Retry / Mission Select(音量交給系統) |
| **S9 開場過場** | 新遊戲播 3 頁(圖+打字機文字),可跳過 |
| **S10 操作教學** | 覆蓋層,首次進入組裝/商店/關卡各播一次,存檔記錄 |
| **關卡架構重構** | **一關一檔 JSON**(`Source/levels/*.json`)+ `level_loader.lua` 啟動掃描 |
| **前景層** | `scene.foregrounds[]` 4 幀動畫,畫在**機體之上、UI 之下** |

---

## 3. 關鍵慣例(接手前必讀)

### 3-1. 關卡 = 一關一檔 JSON
- 每關 = `Source/levels/<id>.json`,`level_loader.lua` 啟動時掃描組成 `_G.MissionData`
- **新增關卡 = 丟 JSON 進資料夾 + 重新編譯**(Playdate 無法熱載入,編譯這步省不掉)
- `mission_data.lua` 已清空成 `return {}`(僅作 fallback)
- 現有:M001–M006(原型關)、**M007**(多場景/懸崖/砲台/重生/BOSS 測試)、**M008**(護送測試:HOLD → MOVE到傳送點 → MOVE到 bunker)

### 3-2. ★ Sprite sheet 檔名必須是 `名稱-table-寬-高.png`
Playdate 的 imagetable 硬性規定。**使用者曾兩次存錯檔名導致改圖沒生效**:
- `boss1-table-72-72.png`(7 格:身體/上身/後輪/前輪/武器1/武器2/雷射槍)
- `turret-table-32-32.png`(2 格:底座/砲管)
- `forground-table-32-32.png`(4 格前景動畫,注意是使用者的拼法 forground)
- `npc_walk-table-24-28.png`、`arrow-table-32-32.png`
- 單張圖則正常命名:`bunker.png`、`turret_control.png`

### 3-3. 驗證流程(唯一可自動化的部分)
```bash
"E:/PlaydateSDK/bin/pdc.exe" Source Builds/hayatogam_assamble_toy.pdx   # 必須 EXIT 0
# 開機驗證(抓載入期錯誤):啟動模擬器導向 log,grep "LEVEL loaded"(應為 8)與 error/attempt/traceback
```
- **可自動驗證**:編譯錯誤、載入期崩潰、關卡載入數
- **必須人工**:畫面、手感、通關流程(我無法驅動輸入或看畫面)

### 3-4. ★ 地面線以下不要畫黑字
地面填色是黑的,`ground_y`(約 156)以下的黑字會**看不見**;但在 `pit`(懸崖缺口)處會露出來。已因此修過兩次 bug(除錯資訊文字、砲台提示文字)。

---

## 4. 進行中 / 下一步

### 4-1. 立即接續:美術接線(使用者主導)
使用者依 [ArtAssets_切片_組裝玩具任務.md](ArtAssets_切片_組裝玩具任務.md) 產圖,每交一批就:
1. 確認檔名(尤其 `-table-` 慣例)
2. 用 Python/PIL 量測 bbox 定出**命中框、旋轉軸心、槍口座標**(BOSS/砲台都是這樣做的)
3. 接線 → 編譯 → 開機驗證 → 請使用者實測

**已完成美術**:BOSS(boss1)、砲台(turret + turret_control 面板)、NPC 走路、傳送點箭頭、bunker、前景裝飾
**待製作**:見清單 —— UI 四畫面底圖(存檔/選任務/結算)、開場 3 頁、新零件、新敵人、場景背景組、CANON 砲管改短、FEET 改矮、爆炸特效、DRONE 專屬圖

### 4-2. 之後:C 內容 + QA 量測
- **C1** 新功能零件、**C4** BOSS roster、**C5** 3–4 關正式關卡
- **QA2 單位成本量測** ← 這是 **M2 規模拍板**的依據(25 關/5 王/20 零件要不要下修)
- **請使用者記錄「畫每一項花的實際時間」**,那就是量測原始資料

### 4-3. 仍待使用者拍板
- 20 零件分類(純變體 vs 新功能型)
- +3 敵人行為型別、+5 BOSS 的具體規劃
- 進程結構:線性解鎖 vs 分支選關

---

## 5. 常用調參位置(使用者常要求微調)

| 想調什麼 | 位置 |
|---|---|
| 地面表面層厚度/濃度 | `entity_controller.lua` 的 `SURFACE_T`(6)、`self.surface_dither`(0.5, Bayer8x8) |
| BOSS 各階段武器 | `boss_data.lua`:`aim_time`/`aim_speed`/`cooldown`/`speed_mult`/`grav_mult`、雷射 `charge`/`beam_time`/`thickness` |
| BOSS 命中框/軸心/槍口 | `boss_data.lua` 各 part 的 `dx,dy,w,h` / `pivot_x,pivot_y` / `muzzle_x,muzzle_y` |
| 砲台 | `entity_controller.lua` 砲台初始化:`pivot_x/y`(10,10)、`barrel_len`(21)、`grav_mult`(40)、`speed_mult`(30);crank 靈敏度在 `state_mission.lua` 的 `WEAPON_CRANK_DEG_PER_ROTATION`(30) |
| 機體零件 | `parts_data.lua`(CANON 角度改為**每零件獨立** `canon_angles[id]`,離開焦點維持角度、非焦點面板不動) |
| HQ 版面 | `state_hq.lua` 的 `HQ_LAYOUT`(含 `preview_box`) |
| 商店版面 | `state_shop.lua` 的 `SHOP_LAYOUT` |

---

## 6. 關卡編輯器(網頁工具)

**https://claude.ai/code/artifact/b9dcff9f-7b4f-41b1-97d9-1cb075bad0a2**

- **同一個網址持續更新**——下次要改編輯器,用 `Artifact` 工具帶 `url` 參數republish,不要開新的
- 原始檔在 scratchpad:`level_editor.html`(session 換了會消失 → **若要再改,需先用 WebFetch 抓回內容**)
- 功能:新增/載入本機 JSON(可拖放)、多場景分頁、每場景目標、地形(含 pit)、敵人/BOSS/石頭/目標/背景/傳送點/重生點/REACH旗/NPC/bunker/砲台/前景
- **已移除**內嵌的預設關卡選單(使用者反映與本機檔案不同步造成混淆)
- **沙盒限制**:下載常被擋、`navigator.clipboard` 無效 → 複製改用 `document.execCommand('copy')`;**無法即時讀取本機資料夾**(已確認做不到)
- 改完務必:抽出 `<script>` 內容跑 `node --check` 驗證語法

---

## 7. 使用者偏好(從本次協作觀察)

- 動作/平面設計為專長,程式靠 AI;**版面與手感由他主導**,我負責實作與量測對齊
- 偏好**先討論設計再實作**(BOSS、護送戰都是先確認方向才動工)
- 大量的**小幅視覺微調**(位置差幾 px、文字要不要留、動畫速度),要快速迭代
- 回報問題時常只給現象(如「文字沒顯示」),**要主動找根因**(通常是座標/圖層/檔名)
- 文件一律**繁體中文 Markdown**

---

## 8. 未提交狀態提醒

36 個變更未 commit,包含所有切片系統與新美術。使用者尚未要求 commit/PR——**動 git 前務必先問**。
