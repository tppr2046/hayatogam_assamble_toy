-- state_hq.lua (Version 8.4 - 恢復所有繪圖與操作邏輯)

import "CoreLibs/graphics" 

local gfx = playdate.graphics  
local default_font = gfx.font.systemFont
-- MissionData 現在從 _G.MissionData 獲取（在 main.lua 中載入）

-- 確保字形載入成功
local custom_font_path = 'fonts/Assemble' 
local font = gfx.font.new(custom_font_path) 

if not font then
    font = default_font
    print("WARNING: Failed to load " .. custom_font_path .. ". Using system font.")
end

StateHQ = {}

-- ==========================================
-- 網格組裝常數與狀態
-- ==========================================
local SCREEN_WIDTH = 400
local SCREEN_HEIGHT = 240
local UI_HEIGHT = 64  -- 操作介面高度
local GAME_HEIGHT = SCREEN_HEIGHT - UI_HEIGHT  -- 實際遊戲畫面高度
local GRID_COLS = 3       
local GRID_ROWS = 2       
local GRID_CELL_SIZE = 16 
local GRID_WIDTH = GRID_COLS * GRID_CELL_SIZE

-- ============================================================
-- [[ G2 版型 ]] 組裝介面版型。框線由底圖 images/hq_bg.png 提供，
-- 程式不再畫白底框，只把內容對齊到底圖各框的「內緣」。
-- 下列座標由 hq_bg.png 掃描實測而得（單位：像素，畫面 400x240）。
-- 要微調任何區塊，只改這張表，重新編譯就生效。
-- ============================================================
-- ============================================================
-- [[ 2026-08-13 版面重排 ]] 底圖換成新的 hq_bg.png，操作流程同時改版：
--   * 移除 HQ 的操作面板（那是關卡中的東西，組裝畫面不需要）
--   * 移除 SHOP 方塊 —— 改由 TOP PARTS / BOTTOM PARTS 進入「PARTS 介面」（原商店）
--   * 核心不再畫在組裝 6 格中央，改成右下角的**出擊按鈕**（core1-table-64-64）
-- 框線座標由 `tools/scan_hq_bg.py` 掃描 hq_bg.png 量得（白色連通區域的內緣）。
-- ============================================================
local HQ_LAYOUT = {
    mission  = { x = 20,  y = 19,  w = 360, h = 45 },   -- 頂部框：任務名＋目標（掃描實測）
    menu     = { x = 31,  y = 84,  w = 135, h = 50 },   -- 左中框：TOP/BOTTOM PARTS + REMOVE
    data     = { x = 31,  y = 167, w = 135, h = 46 },   -- 左下框：HP / WEIGHT（框外已有 DATA 標籤）

    mech_scale = 2,      -- 機體放大倍率（組裝格 16px × 2 = 螢幕 32px/格 → 整體 96×64）
    -- ⚠️ 下面兩個是**推測值**：機體要落在右側機艙的空白處，而那是裝飾圖、掃描量不出來。
    --    看畫面後直接改這兩個數字即可（只有這裡在定義機體位置）。
    mech_cx  = 250,      -- 放大後「組裝格中心」的螢幕 x
    mech_cy  = 140,      -- 放大後「組裝格中心」的螢幕 y

    -- [[ 出擊按鈕 ]] core1-table-64-64：1=底座 / 2=按鈕未按 / 3=按鈕按下
    -- ⚠️ 同樣是推測值（右下角），看畫面後改這兩個數字。
    start_x  = 324,
    start_y  = 170,
    start_size = 64,
}

-- [[ 2026-08-13 ]] LIST_VISIBLE 已移除：安裝時左側選單只顯示一筆（正在裝的那個零件），
-- 捲動視窗不再需要。主選單固定 3 項、框高 50px/行高 15 剛好放得下，也不需要捲動。

-- [[ G2 ]] 機甲離屏畫布：機甲先以原生像素畫進此畫布，再 drawScaled 放大置中。
-- GRID_START_X/Y 改為「畫布內的組裝格原點」（四周留邊給砲管/腳/預覽溢出）。
-- 左側留白 = GRID_START_X，需容納「機體左側的未安裝零件預覽」（最寬 3 格=48px
-- ＋間距）；機體在螢幕上的置中不受留白影響（由 mech_cx 決定）。
local MECH_CANVAS_W = 210
local MECH_CANVAS_H = 110
local GRID_START_X = 82
local GRID_START_Y = 52

-- UI 控制介面相關（操作面板繪於 PANEL 盒內）
-- [[ 2026-08-13 ]] UI_GRID_* / UI_START_* 已移除：那是舊操作面板的常數，面板已整段刪掉。

-- [[ 2026-08-13 ]] 零件在清單上要顯示的字串。
-- ★ 以前直接畫 `part_id`，剛好舊零件的 id 都長得像人看的字（GUN / CLAW / FEET…），
--   所以一直沒發現 `parts_data` 的 `name` 欄位其實**從來沒被用過**。
--   加入 BACK_GUN / HIGH_GUN 後就露餡了 —— 畫面上會出現**底線**（`BACK_GUN`）。
-- ★ 順帶修好 GUN2：它的 name 是 "LASER"，以前清單卻顯示 "GUN2"。
local function partLabel(part_id)
    local d = _G.PartsData and _G.PartsData[part_id]
    return (d and d.name) or part_id
end

-- [[ 2026-08-13 ]] 出擊按鈕圖的快取。
-- ⚠️ 必須宣告在 startButtonSheet() **之前** —— Lua 的 local 只對「宣告之後」的程式碼可見，
--    放在後面的話函式裡讀到的是同名**全域變數**（nil），一進 HQ 就 crash。
--    這種錯誤 pdc 不會擋（未宣告的全域是合法語法），開機驗證也抓不到（進不了 HQ）。
local start_sheets = {}      -- [core_id] = imagetable | false(載過但失敗)
local start_sheet_fallback = nil

-- [[ 2026-08-13 ]] 目前核心對應的出擊按鈕圖（3 格 64×64：底座 / 未按 / 按下）。
-- ★ 核心升級 → 這裡自動換圖，state_hq 的繪製端完全不必改。
-- ★ 載不到就退回 CORE1 —— core2/core3 的圖還沒畫，但流程要能照常走完。
local function startButtonSheet()
    local core = _G.CoreData and _G.CoreData.current and _G.CoreData.current() or nil
    local cid  = (core and core.id) or "CORE1"
    if start_sheets[cid] == nil then
        local path = (core and core.button_sprite) or "images/core1"
        local ok, tbl = pcall(function() return gfx.imagetable.new(path) end)
        if ok and tbl then
            start_sheets[cid] = tbl
            print("LOG: start button sheet loaded for " .. cid .. " (" .. path .. ")")
        else
            start_sheets[cid] = false
            print("LOG: no start button sheet for " .. cid .. " (" .. path .. ") -> fallback to CORE1")
        end
    end
    if start_sheets[cid] then return start_sheets[cid] end

    -- fallback：CORE1 的圖（只載一次）
    if start_sheet_fallback == nil then
        local ok, tbl = pcall(function() return gfx.imagetable.new("images/core1") end)
        start_sheet_fallback = (ok and tbl) or false
        if not start_sheet_fallback then
            print("WARNING: failed to load images/core1-table-64-64.png")
        end
    end
    return start_sheet_fallback or nil
end

-- [[ G2 ]] 反白選取：選中＝黑底白字（穩定不閃爍），未選中＝純黑字。
-- 取代舊的「> text <」＋閃爍樣式。
-- [[ 2026-08-13 ]] 選中項的黑底改成**閃爍**（依使用者要求，提示更明顯）。
-- 舊版刻意做成「穩定不閃」，現在改為閃爍：黑底出現時黑底白字、消失時純黑字。
-- ★ 用與其他閃爍元素同一個 250ms 節拍（見 draw 內的 blink_on），整個畫面才不會各閃各的。
local function menuBlinkOn()
    return (math.floor(playdate.getCurrentTimeMilliseconds() / 250) % 2) == 0
end

local function drawSelectableText(text, x, y, selected)
    if selected and menuBlinkOn() then
        local tw, th = gfx.getTextSize(text)
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRect(x - 2, y - 1, tw + 4, th + 2)
        gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        gfx.drawText(text, x, y)
        gfx.setImageDrawMode(gfx.kDrawModeCopy)
    else
        gfx.setColor(gfx.kColorBlack)
        gfx.drawText(text, x, y)
    end
end

-- [[ G2 ]] 白底框線盒已移除：框線改由底圖 hq_bg.png 提供，程式只畫內容。

local GRID_MAP = {}       
local cursor_col = 1      
local cursor_row = 1      
-- [[ P5 重整 ]] 動線規則：左側縱向主選單（上下移動）、START 固定右下、
-- A=進入/確認、B=一律返回上一層（主選單按 B 回任務選擇）、右鍵=跳至 START
local MAIN_MENU = { "TOP PARTS", "BOTTOM PARTS", "REMOVE PART" }  -- SHOP 原型隱藏
local main_menu_index = 1       -- 主選單游標（1..#MAIN_MENU）
local cursor_on_start = false   -- 游標是否在右下角固定 START 鈕上
-- [[ 2026-08-13 ]] cursor_on_shop 已移除：SHOP 鈕不存在了
local is_unequip_mode = false  -- 是否在解除裝備模式（由主選單 REMOVE PART 進入）
local unequip_selected_col = 1  -- 解除模式選中的格子列
local unequip_selected_row = 1  -- 解除模式選中的格子排
local selected_category = nil   -- nil = 主選單層, "TOP" or "BOTTOM" = 零件清單層
local selected_part_index = 1
local hq_mode = "EQUIP"         -- 固定 EQUIP（舊 UNEQUIP 分支為死碼，已移除）

-- [[ P5 ]] 放置回饋：不可放的格子在放置模式中以 dither.png 靜態標示
-- （取代舊「按下才紅閃」——且舊紅閃的 y 映射用 (row-1)，實際畫錯排）
local x_marker_img = nil  -- images/dither.png，於 setup 載入
local hq_bg_img = nil     -- [[ G2 ]] images/hq_bg.png 組裝介面底圖（400x240），於 setup 載入
-- [[ 2026-08-13 ]] HQ 右下角出擊按鈕 ＝ **核心本體**，所以核心升級時整張圖要換掉。
-- 依 core_data 的 `button_sprite` 載入，用 id 當 key 快取（換核心不必重載已載過的）。
-- ⚠️ core2 / core3 的圖還沒畫 → 載不到時退回 CORE1 的圖，功能照常。
local start_press_timer = 0  -- 按下時顯示第 3 格的幀數
-- ★ 出擊要**等按下動畫播完**才切換狀態。舊版在同一幀就 setState，
--   所以「按下」那一格永遠來不及畫出來（畫面直接跳走了）。
local start_launch_pending = false
local cursor_blink_tick = 0  -- 控制粗邊框的閃爍
local overweight_flash = 0   -- [[ CORE ]] 因超過負重上限而擋下安裝時的提示閃爍幀數
local broken_flash = 0       -- [[ 耐久 §8.07 ]] 因零件損壞而擋下安裝時的提示閃爍幀數
local place_error_flash = 0  -- [[ 2026-08-13 ]] 在不可安裝的格子按 A 時，安裝位置粗框的閃爍幀數
-- [[ 2026-08-13 ]] DATA 數字變動時的短暫放大效果（安裝/拆卸後給回饋）
local data_prev_hp, data_prev_wt = nil, nil
local data_pop_hp, data_pop_wt = 0, 0
local DATA_POP_FRAMES = 10   -- 放大持續幀數（30fps → 約 0.33 秒）
-- 播放標題/一般介面 BGM（循環）
function StateHQ.setupBGM()
    if _G.SoundManager and _G.SoundManager.playTitleBGM then
        _G.SoundManager.playTitleBGM()
    end
end

-- [[ P5 ]] READY 彈窗已移除：游標在 START 按 A 直接開始任務

-- ==========================================
-- 輔助函式 (佔位符)
-- ==========================================

-- 佔位符：檢查零件放置是否合適 (避免程式在 draw 函式中崩潰)
local function checkIfFits(part_data, start_col, start_row)
    if not part_data then return false, "No part selected" end
    -- 檢查是否超出網格範圍
    local w = part_data.slot_x or 1
    local h = part_data.slot_y or 1
    if start_col < 1 or start_row < 1 or (start_col + w - 1) > GRID_COLS or (start_row + h - 1) > GRID_ROWS then
        return false, "Out of bounds"
    end

    -- 檢查 placement_row 限制（TOP/BOTTOM/BOTH）
    if part_data.placement_row then
        local pr = part_data.placement_row
        if pr == "TOP" then
            -- TOP placement: the part's topmost occupied row must align with GRID_ROWS
            if (start_row + h - 1) ~= GRID_ROWS then
                return false, "Must place on TOP row"
            end
        elseif pr == "BOTTOM" then
            -- BOTTOM placement: the part's origin must be on the bottom row (row == 1)
            if start_row ~= 1 then
                return false, "Must place on BOTTOM row"
            end
        end
    end



    -- 檢查是否與已佔用格子重疊
    for r = start_row, start_row + h - 1 do
        GRID_MAP[r] = GRID_MAP[r] or {}
        for c = start_col, start_col + w - 1 do
            if GRID_MAP[r][c] then
                return false, "Cell occupied"
            end
        end
    end

    -- [[ 槍口淨空 ]] 直射零件（requires_clear_right，如 GUN）的右側不可有零件，
    -- 否則子彈會視覺上穿過自己的零件。雙向檢查：
    -- 1) 放的是直射零件 → 其右側（同排）不可已有零件
    if part_data.requires_clear_right then
        for c = start_col + w, GRID_COLS do
            if GRID_MAP[start_row] and GRID_MAP[start_row][c] then
                return false, "Muzzle blocked"
            end
        end
    end
    -- 2) 放的是一般零件 → 不可落在已裝直射零件的右側（同排）
    local eq = _G.GameState and _G.GameState.mech_stats and _G.GameState.mech_stats.equipped_parts or {}
    for _, item in ipairs(eq) do
        local ipdata = _G.PartsData and _G.PartsData[item.id]
        if ipdata and ipdata.requires_clear_right and item.row == start_row and start_col > item.col then
            return false, "Muzzle blocked"
        end
    end

    -- [[ §15.9 反向槍 ]] 上面那組的**左側鏡像**（requires_clear_left，如 BACK_GUN）。
    -- ★ 必須兩半都做：只做 1) 的話，之後在反向槍左邊裝別的零件不會被擋下來。
    -- 3) 放的是左射零件 → 其左側（同排）不可已有零件
    if part_data.requires_clear_left then
        for c = 1, start_col - 1 do
            if GRID_MAP[start_row] and GRID_MAP[start_row][c] then
                return false, "Muzzle blocked"
            end
        end
    end
    -- 4) 放的是一般零件 → 不可落在已裝左射零件的左側（同排）
    for _, item in ipairs(eq) do
        local ipdata = _G.PartsData and _G.PartsData[item.id]
        if ipdata and ipdata.requires_clear_left and item.row == start_row and start_col < item.col then
            return false, "Muzzle blocked"
        end
    end

    return true, ""
end

-- [[ 零件限制 ]] 檢查目前任務要求的零件「類別」是否已全部裝備。
-- 回傳缺少的類別清單（nil = 無限制或已滿足）。任務以 required_parts = {"CLAW", ...} 宣告。
local function getMissingRequiredParts()
    local mission_id = _G.GameState and _G.GameState.current_mission
    local mission = mission_id and _G.MissionData and _G.MissionData[mission_id]
    local required = mission and mission.required_parts
    if not required or #required == 0 then return nil end

    local missing = {}
    local eq = (_G.GameState.mech_stats and _G.GameState.mech_stats.equipped_parts) or {}
    for _, req_type in ipairs(required) do
        local found = false
        for _, item in ipairs(eq) do
            local pdata = _G.PartsData and _G.PartsData[item.id]
            if pdata and pdata.part_type == req_type then
                found = true
                break
            end
        end
        if not found then
            missing[#missing + 1] = req_type
        end
    end
    if #missing == 0 then return nil end
    return missing
end

-- 在已裝備清單中尋找覆蓋指定格子的零件，回傳索引與該項
local function findEquippedPartAt(col, row)
    local eq = _G.GameState and _G.GameState.mech_stats and _G.GameState.mech_stats.equipped_parts
    if not eq then return nil end
    for i, item in ipairs(eq) do
        local c1 = item.col
        local r1 = item.row
        local w = item.w or 1
        local h = item.h or 1
        if col >= c1 and col < c1 + w and row >= r1 and row < r1 + h then
            return i, item
        end
    end
    return nil
end

-- 尋找第一個空的格子（適合放置零件）
local function findFirstEmptyCell(part_data)
    local w = (part_data and part_data.slot_x) or 1
    local h = (part_data and part_data.slot_y) or 1
    
    -- 優先從左上角開始尋找
    for r = GRID_ROWS, 1, -1 do  -- 從上到下（row 2, 1）
        for c = 1, GRID_COLS do  -- 從左到右
            local can_fit, reason = checkIfFits(part_data, c, r)
            if can_fit then
                return c, r
            end
        end
    end
    -- 沒有空位，返回中間位置
    return 2, 2
end

-- [[ G2 ]] 依零件的 placement_row 決定安裝列（TOP→上排、BOTTOM→下排）。
-- 玩家只用左右鍵選「欄」，列由零件類別自動決定。
local function rowForPart(part_data)
    if not part_data then return 1 end
    local h = part_data.slot_y or 1
    if part_data.placement_row == "TOP" then
        return GRID_ROWS - h + 1
    end
    return 1
end

-- [[ G2 ]] 零件寬 slot_x 的合法原點欄上限（避免寬零件把原點選到超出邊界）
local function maxOriginCol(part_data)
    local w = (part_data and part_data.slot_x) or 1
    return math.max(1, GRID_COLS - w + 1)
end

-- [[ G2 ]] 實際安裝零件到指定格：填 GRID_MAP、加入 equipped_parts、累加數值、自動存檔
local function installPart(part_id, part_data, col, row)
    local w = part_data.slot_x or 1
    local h = part_data.slot_y or 1
    for r = row, row + h - 1 do
        GRID_MAP[r] = GRID_MAP[r] or {}
        for c = col, col + w - 1 do
            GRID_MAP[r][c] = part_id
        end
    end
    table.insert(_G.GameState.mech_stats.equipped_parts, { id = part_id, col = col, row = row, w = w, h = h })
    -- [[ CORE ]] 改由 recalcMechStats() 統一重算（含核心基礎 HP），不再各自累加
    recalcMechStats()
    if _G.SaveManager and _G.SaveManager.saveCurrent then
        _G.SaveManager.saveCurrent()
        print("LOG: Mech configuration auto-saved.")
    end
end

-- [[ G2 ]] 從 from_index 之後找下一個「未裝備」的零件索引（找不到就繞回頭找）
local function nextUnequippedIndex(parts_list, from_index)
    local count = parts_list and #parts_list or 0
    local eq = _G.GameState.mech_stats.equipped_parts or {}
    local function equipped(pid)
        for _, item in ipairs(eq) do
            if item.id == pid then return true end
        end
        return false
    end
    for i = from_index + 1, count do
        if not equipped(parts_list[i]) then return i end
    end
    for i = 1, from_index - 1 do
        if not equipped(parts_list[i]) then return i end
    end
    return from_index
end

-- 從 equipped_parts 刪除指定索引的零件，並把 GRID_MAP 與 mech_stats 更新
local function removeEquippedPart(index)
    local eq = _G.GameState and _G.GameState.mech_stats and _G.GameState.mech_stats.equipped_parts
    if not eq or not eq[index] then return false end
    local item = eq[index]
    -- 清除 GRID_MAP 的格子
    for r = item.row, item.row + (item.h or 1) - 1 do
        for c = item.col, item.col + (item.w or 1) - 1 do
            if GRID_MAP[r] then GRID_MAP[r][c] = nil end
        end
    end
    table.remove(eq, index)

    -- 將零件重新加入可用清單（TOP/BOTTOM/BOTH）
    local parts_by_category = _G.GameState and _G.GameState.parts_by_category
    local pdata = _G.PartsData and _G.PartsData[item.id]
    if parts_by_category and pdata then
        local pr = pdata.placement_row or "BOTH"
        local function insert_if_missing(cat)
            local list = parts_by_category[cat]
            if list then
                local exists = false
                for _, pid in ipairs(list) do
                    if pid == item.id then exists = true break end
                end
                if not exists then table.insert(list, item.id) end
            end
        end
        if pr == "TOP" or pr == "BOTH" then insert_if_missing("TOP") end
        if pr == "BOTTOM" or pr == "BOTH" then insert_if_missing("BOTTOM") end
    end
    print("LOG: Removed part", item.id, "from", item.col, item.row)
    -- 重算 mech_stats 以避免累加/重複扣除造成誤差
    if _G and _G.GameState and _G.GameState.mech_stats then
        recalcMechStats()
    end
    return true
end

-- 根據 equipped_parts 重新計算 mech_stats（total_hp, total_weight）
-- [[ CORE ]] GDD §8.05:**HP = 核心基礎 HP + 已裝零件 hp 總和**（負重不含核心）。
-- 本函式是 mech_stats 的**唯一真相來源**——安裝/拆卸都改成呼叫它重算，
-- 不再各自做 +/- 累加（舊做法會累積誤差，且無法帶入核心基礎值）。
function recalcMechStats()
    if not (_G and _G.GameState and _G.GameState.mech_stats) then return end
    local total_hp = 0
    local total_weight = 0
    local eq = _G.GameState.mech_stats.equipped_parts or {}
    for _, item in ipairs(eq) do
        local pdata = _G.PartsData and _G.PartsData[item.id]
        if pdata then
            total_hp = total_hp + (pdata.hp or 0)
            total_weight = total_weight + (pdata.weight or 0)
        end
    end
    local core = _G.CoreData and _G.CoreData.current and _G.CoreData.current() or nil
    _G.GameState.mech_stats.total_hp = (core and core.base_hp or 0) + total_hp
    _G.GameState.mech_stats.total_weight = total_weight
    -- 供 UI 顯示與安裝檢查使用（不寫進存檔，每次都由核心推導）
    _G.GameState.mech_stats.weight_cap = (core and core.weight_cap) or 999
end

-- [[ CORE ]] 安裝檢查:裝上這個零件後會不會超過核心的負重上限。
-- 回傳 fits(boolean), 裝上後的總重, 上限
local function weightAfterInstall(part_data)
    local cap = (_G.GameState and _G.GameState.mech_stats and _G.GameState.mech_stats.weight_cap) or 999
    local cur = (_G.GameState and _G.GameState.mech_stats and _G.GameState.mech_stats.total_weight) or 0
    local after = cur + ((part_data and part_data.weight) or 0)
    return (after <= cap), after, cap
end


-- ==========================================
-- 狀態機接口
-- ==========================================

function StateHQ.setup()
    gfx.setFont(font) 
    -- 播放標題/一般介面 BGM（循環）
    if _G.SoundManager and _G.SoundManager.playTitleBGM then
        _G.SoundManager.playTitleBGM()
    end
    
    -- [[ 2026-08-13 ]] 舊版在這裡 `mech_controller = MechController:init()`，
    -- 用途只有「畫操作面板的零件圖示」—— 面板已隨版面重排整段移除，
    -- 這個變數變成**只寫不讀的死碼**（而且沒宣告 local，是個全域）。整段刪除。

    -- 確保 MissionData 已在 main.lua 中載入
    if not _G.MissionData then
        print("ERROR HQ: _G.MissionData not found! Loading fallback...")
        local md = import "mission_data"
        _G.MissionData = md or {}
    end
    
    -- 確保必要的全域變數存在
    _G.GameState = _G.GameState or {}
    _G.GameState.owned_parts = _G.GameState.owned_parts or {}
    
    -- 組織零件為分類（TOP 和 BOTTOM），只顯示已擁有的零件
    local top_parts = {}
    local bottom_parts = {}
    if _G.PartsData and next(_G.PartsData) then
        for pid, pdata in pairs(_G.PartsData) do
            -- 只添加已擁有且未裝備的零件
            if _G.GameState.owned_parts[pid] then
                -- 檢查是否已裝備
                local is_equipped = false
                for _, item in ipairs(_G.GameState.mech_stats.equipped_parts or {}) do
                    if item.id == pid then
                        is_equipped = true
                        break
                    end
                end
                
                -- 只有未裝備的零件才添加到列表
                if not is_equipped then
                    if pdata.placement_row == "TOP" or pdata.placement_row == "BOTH" then
                        table.insert(top_parts, pid)
                    end
                    if pdata.placement_row == "BOTTOM" or pdata.placement_row == "BOTH" then
                        table.insert(bottom_parts, pid)
                    end
                end
            end
        end
    end
    _G.GameState.parts_by_category = {
        TOP = top_parts,
        BOTTOM = bottom_parts
    }
    print("LOG: Available parts - TOP:", #top_parts, "BOTTOM:", #bottom_parts)

    _G.GameState.mech_stats = _G.GameState.mech_stats or { total_hp = 100, total_weight = 0, equipped_parts = {} }
    _G.GameState.mech_stats.equipped_parts = _G.GameState.mech_stats.equipped_parts or {}
    
    hq_mode = "EQUIP" -- 確保從組裝模式開始
    selected_category = nil  -- 重置分類選擇
    main_menu_index = 1
    cursor_on_start = false

    -- [[ 2026-08-13 INSTALL 流程 ]] 從 PARTS 介面按 INSTALL 回來時：直接進入「選位置」狀態。
    -- ★ 沿用既有的 selected_category + selected_part_index 機制（游標粗框、左右移欄、
    --   按 A 安裝、X 標記全部現成），不另做一套放置模式 —— 兩套一定會走鐘。
    local pend = _G.GameState.pending_install
    _G.GameState.pending_install = nil
    if pend then
        local pdata = _G.PartsData and _G.PartsData[pend]
        local cat = (pdata and pdata.placement_row == "BOTTOM") and "BOTTOM" or "TOP"
        local list = _G.GameState.parts_by_category[cat] or {}
        for i, pid in ipairs(list) do
            if pid == pend then
                selected_category = cat
                selected_part_index = i
                cursor_col = findFirstEmptyCell(pdata) or 1
                cursor_row = rowForPart(pdata)
                print("LOG: pending install -> " .. pend .. " (" .. cat .. ")")
                break
            end
        end
    end
    -- [[ S8 ]] 前端設定選單（Menu 鍵）：BGM / SFX 音量
    if _G.MenuItems and _G.MenuItems.installForFrontend then
        _G.MenuItems.installForFrontend()
    end
    -- [[ S10 ]] 首次進入組裝介面：播放教學
    if _G.Tutorial and _G.Tutorial.maybeStart then
        _G.Tutorial.maybeStart("hq")
    end

    -- 初始化 GRID_MAP（row-major），nil 表示空
    GRID_MAP = {}
    for r = 1, GRID_ROWS do
        GRID_MAP[r] = {}
        for c = 1, GRID_COLS do
            GRID_MAP[r][c] = nil
        end
    end

    -- [[ BUGFIX ]] 把「已裝備零件」填回 GRID_MAP。
    -- 舊版漏了這步：帶裝備回到 HQ 時格子看似全空，checkIfFits 放行，
    -- 導致可以把第二顆輪子疊裝在同一排（實測出現 WHEEL1+WHEEL2 重疊）。
    -- 同時自動清理既有存檔中已重疊的零件：後裝的移除、歸還零件清單、扣回數值。
    do
        local eq = _G.GameState.mech_stats.equipped_parts or {}
        local removed_any = false
        local i = 1
        while i <= #eq do
            local item = eq[i]
            local w = item.w or 1
            local h = item.h or 1
            local overlap = false
            for r = item.row, item.row + h - 1 do
                for c = item.col, item.col + w - 1 do
                    if GRID_MAP[r] and GRID_MAP[r][c] then overlap = true end
                end
            end
            if overlap then
                -- 移除重疊零件、扣回數值、歸還到零件清單
                local pdata = _G.PartsData and _G.PartsData[item.id]
                if pdata then
                    -- [[ CORE ]] 數值統一在迴圈結束後 recalcMechStats() 重算
                    local category = (pdata.placement_row == "TOP") and "TOP" or "BOTTOM"
                    local list = _G.GameState.parts_by_category and _G.GameState.parts_by_category[category]
                    if list then
                        local in_list = false
                        for _, pid in ipairs(list) do
                            if pid == item.id then in_list = true break end
                        end
                        if not in_list then table.insert(list, item.id) end
                    end
                end
                print("WARNING: removed overlapping equipped part: " .. tostring(item.id))
                table.remove(eq, i)
                removed_any = true
            else
                for r = item.row, item.row + h - 1 do
                    for c = item.col, item.col + w - 1 do
                        if GRID_MAP[r] then GRID_MAP[r][c] = item.id end
                    end
                end
                i = i + 1
            end
        end
        -- 清理過就存檔，修復既有存檔資料
        if removed_any and _G.SaveManager and _G.SaveManager.saveCurrent then
            recalcMechStats()   -- [[ CORE ]] 移除重疊零件後重算（含核心基礎 HP）
            _G.SaveManager.saveCurrent()
        end
    end
    -- [[ CORE ]] 進 HQ 時一律重算一次：舊存檔的 total_hp 不含核心基礎值，這裡補正
    recalcMechStats()

    -- 保存網格設定到全域，供任務關卡使用（用於合成機體影像）
    _G.GameState.mech_grid = { cell_size = GRID_CELL_SIZE, cols = GRID_COLS, rows = GRID_ROWS }

    -- [[ P5 ]] 載入「不可放置」標示圖（16x16，放置模式蓋在不可放的格子上）
    if not x_marker_img then
        x_marker_img = gfx.image.new("images/dither")
        if not x_marker_img then
            print("WARNING: failed to load images/dither.png, fallback to text X")
        end
    end

    -- [[ G2 ]] 載入組裝介面底圖（400x240）
    if not hq_bg_img then
        hq_bg_img = gfx.image.new("images/hq_bg")
        if not hq_bg_img then
            print("WARNING: failed to load images/hq_bg.png")
        end
    end

    -- [[ 2026-08-13 ]] 舊的「核心小圖」載入器已移除：核心自從搬出組裝格中央之後就沒有讀取端了，
    -- 只留下每次進 HQ 印一行 "failed to load images/core-table-32-16.png" 的假警告。
    -- 出擊按鈕用的是 startButtonSheet()（依 core_data 的 button_sprite 載入）。
    -- 沒有 core_id 的舊存檔（或還沒讀檔就進 HQ）→ 補上預設核心
    _G.GameState = _G.GameState or {}
    if not _G.GameState.core_id then
        _G.GameState.core_id = (_G.CoreData and _G.CoreData.default_id) or "CORE1"
    end

    -- Preload part images into parts data (store as _img)
    if _G and _G.PartsData then
        for pid, pdata in pairs(_G.PartsData) do
            if pdata.image then
                local img, err = gfx.image.new(pdata.image)
                if img then
                    pdata._img = img
                else
                    print("WARN: failed to load image for part", pid, pdata.image, err)
                end
            end
            -- 載入 CLAW 的額外圖片
            if pid == "CLAW" then
                if pdata.arm_image then
                    local arm_img = gfx.image.new(pdata.arm_image)
                    if arm_img then
                        pdata._arm_img = arm_img
                    else
                        print("ERROR: Failed to load arm_image:", pdata.arm_image)
                    end
                end
                if pdata.upper_image then
                    local upper_img = gfx.image.new(pdata.upper_image)
                    if upper_img then
                        pdata._upper_img = upper_img
                    else
                        print("ERROR: Failed to load upper_image:", pdata.upper_image)
                    end
                end
                if pdata.lower_image then
                    local lower_img = gfx.image.new(pdata.lower_image)
                    if lower_img then
                        pdata._lower_img = lower_img
                    else
                        print("ERROR: Failed to load lower_image:", pdata.lower_image)
                    end
                end
            end
            
            -- 載入 CANON 的底座圖片
            if pdata.base_image then
                local base_img = gfx.image.new(pdata.base_image)
                if base_img then
                    pdata._base_img = base_img
                else
                    print("ERROR: Failed to load base_image for", pid, pdata.base_image)
                end
            end
        end
    end
    -- Pre-render scaled images that match grid cell sizes so a part that is w x h
    -- cells can be drawn once spanning those cells. This creates pdata._img_scaled.
    if _G and _G.PartsData then
        for pid, pdata in pairs(_G.PartsData) do
            if pdata._img then
                local gotSize, iw, ih = pcall(function() return pdata._img:getSize() end)
                -- ensure buffer is at least the image size so larger-than-slot images (e.g., 32x16 SWORD) are fully visible
                local sw = math.max((pdata.slot_x or 1) * GRID_CELL_SIZE, (gotSize and iw) or 0)
                local sh = math.max((pdata.slot_y or 1) * GRID_CELL_SIZE, (gotSize and ih) or 0)

                -- [[ CANON 2026-08-08 ]] 砲台要合成「底座 + 上移的砲管」。
                -- ★ 這裡才是組裝格實際走的路徑（下方 draw 是 `if _img_scaled then ... elseif _img then`，
                --   而 _img_scaled 一定存在），所以底座與 barrel_offset_y 必須在這裡處理，
                --   只改 elseif 分支是沒有作用的。
                -- 用 part_type 判斷,不要列舉 id —— 新增 CANON3 之類的砲不必再回來改這裡
                local is_canon = (pdata.part_type == "CANON") and pdata._base_img
                local b_off, bw, bh = 0, 0, 0
                if is_canon then
                    b_off = pdata.barrel_offset_y or 0          -- 負值＝往上
                    local okb, w2, h2 = pcall(function() return pdata._base_img:getSize() end)
                    bw = (okb and w2) or 0
                    bh = (okb and h2) or 0
                    sw = math.max(sw, bw)
                    sh = math.max(sh, bh, (ih or 0) - b_off)    -- 砲管上移後多出來的高度
                end

                -- [[ CLAW 2026-08-08 ]] 組裝介面要與關卡內長得一樣：
                -- 臂裝在底座右齒輪、爪裝在臂末端圓盤（角度 0）。座標與 drawClaw 同一組。
                -- 舊版是把臂與爪都畫在 (0,0)（而且用了永遠為 nil 的 dx/dy），所以全部疊在底座上。
                local is_claw = (pdata.part_type == "CLAW") and pdata._arm_img
                local claw_pos = nil
                if is_claw and gotSize and iw and ih then
                    local okA, aw, ah = pcall(function() return pdata._arm_img:getSize() end)
                    local okJ, jw, jh = pcall(function() return pdata._upper_img:getSize() end)
                    if okA and aw and ah and okJ and jw and jh then
                        local mx  = pdata.arm_mount_x  or (iw / 2)
                        local my  = pdata.arm_mount_y  or (ih / 2)
                        local apx = pdata.arm_pivot_x  or 0
                        local apy = pdata.arm_pivot_y  or (ah / 2)
                        local arm_x, arm_y = mx - apx, my - apy
                        local axle_x = mx + ((pdata.claw_pivot_x or aw) - apx)
                        local axle_y = my + ((pdata.claw_pivot_y or (ah / 2)) - apy)
                        -- 上爪鉸鏈在左下角、下爪在左上角 → 兩爪各自往上/往下長
                        local up_x = axle_x - (pdata.upper_pivot_x or 0)
                        local up_y = axle_y - (pdata.upper_pivot_y or jh)
                        local lo_x = axle_x - (pdata.lower_pivot_x or 0)
                        local lo_y = axle_y - (pdata.lower_pivot_y or 0)

                        -- 以「底座左上角」為原點算出整組的外框
                        local min_y = math.min(0, arm_y, up_y, lo_y)
                        local max_x = math.max(iw, arm_x + aw, up_x + jw, lo_x + jw)
                        local max_y = math.max(ih, arm_y + ah, up_y + jh, lo_y + jh)
                        local top_extra = math.ceil(math.max(0, -min_y))

                        claw_pos = {
                            arm_x = arm_x, arm_y = arm_y,
                            up_x = up_x, up_y = up_y, lo_x = lo_x, lo_y = lo_y,
                            base_y = top_extra,          -- 底座在緩衝區內的 y
                        }
                        sw = math.max(sw, math.ceil(max_x))
                        sh = math.max(sh, math.ceil(max_y) + top_extra)
                        -- ★ 底座不再貼齊緩衝區底部（爪子往下也伸出去了），
                        --   所以要告訴繪製端「這張圖要往下移多少才對得回格子」。
                        --   繪製端的公式是 draw_y = py_top + (格高 − 圖高)，
                        --   補上這個位移後 → 底座正好落在 py_top。
                        pdata._scaled_offset_y = sh - GRID_CELL_SIZE - top_extra
                    end
                end

                if sw > 0 and sh > 0 then
                    local ok, buf = pcall(function() return gfx.image.new(sw, sh) end)
                    if ok and buf then
                        gfx.pushContext(buf)
                        gfx.clear(gfx.kColorClear)
                        if is_canon and gotSize and iw and ih then
                            -- 底座貼緩衝區底部；砲管貼底後再上移 b_off（左緣對齊，與機體上一致）
                            pcall(function() pdata._base_img:draw(0, sh - bh) end)
                            pcall(function() pdata._img:draw(0, sh - ih + b_off) end)
                        elseif claw_pos and gotSize and iw and ih then
                            -- CLAW 底座左緣對齊、y 由 claw_pos.base_y 決定（上方要留給上爪）
                            pcall(function() pdata._img:draw(0, claw_pos.base_y) end)
                        elseif gotSize and iw and ih then
                            local dx = math.floor((sw - iw) / 2)
                            local dy = math.floor((sh - ih) / 2)
                            pcall(function() pdata._img:draw(math.max(0, dx), math.max(0, dy)) end)
                        else
                            pcall(function() pdata._img:draw(0, 0) end)
                        end
                        -- CLAW：臂與爪依支點擺位（角度 0），與關卡內的 drawClaw 一致
                        if claw_pos then
                            local by = claw_pos.base_y   -- 其餘部件都相對底座左上角
                            pcall(function() pdata._arm_img:draw(claw_pos.arm_x, by + claw_pos.arm_y) end)
                            if pdata._upper_img then
                                pcall(function() pdata._upper_img:draw(claw_pos.up_x, by + claw_pos.up_y) end)
                            end
                            if pdata._lower_img then
                                pcall(function() pdata._lower_img:draw(claw_pos.lo_x, by + claw_pos.lo_y) end)
                            end
                        end
                        gfx.popContext()
                        pdata._img_scaled = buf
                    end
                end
            end
        end
    end
end

function StateHQ.update()
    -- [[ 2026-08-13 出擊鈕 ]] 按下動畫倒數；播完才真的進關卡。
    -- ★ 倒數放在 update（不是 draw）—— draw 有可能因狀態切換而不執行，
    --   計時器留在 draw 裡會變成「有時候播、有時候不播」。
    -- ★ 動畫期間吃掉所有輸入，避免連按造成重複切換。
    if start_press_timer > 0 then
        start_press_timer = start_press_timer - 1
        if start_press_timer <= 0 and start_launch_pending then
            start_launch_pending = false
            setState(_G.StateMission)
        end
        return
    end

    -- [[ S10 ]] 教學覆蓋層作用中：吃掉輸入
    if _G.Tutorial and _G.Tutorial.isActive and _G.Tutorial.isActive() then
        _G.Tutorial.update()
        return
    end

    if is_unequip_mode then
        -- 解除裝備模式
        local eq = _G.GameState.mech_stats.equipped_parts or {}
        
        if playdate.buttonJustPressed(playdate.kButtonLeft) then
            -- [[ P5 ]] 左鍵只移動游標；離開拆卸一律按 B（返回鍵語義統一）
            unequip_selected_col = math.max(1, unequip_selected_col - 1)
            -- 播放游標移動音效
            if _G.SoundManager and _G.SoundManager.playCursorMove then
                _G.SoundManager.playCursorMove()
            end
        elseif playdate.buttonJustPressed(playdate.kButtonRight) then
            unequip_selected_col = math.min(GRID_COLS, unequip_selected_col + 1)
            -- 播放游標移動音效
            if _G.SoundManager and _G.SoundManager.playCursorMove then
                _G.SoundManager.playCursorMove()
            end
        elseif playdate.buttonJustPressed(playdate.kButtonUp) then
            -- 從下排跳到上排的零件
            for _, item in ipairs(eq) do
                if item.row == 2 then
                    unequip_selected_col = item.col
                    unequip_selected_row = item.row
                    break
                end
            end
            -- 播放游標移動音效
            if _G.SoundManager and _G.SoundManager.playCursorMove then
                _G.SoundManager.playCursorMove()
            end
        elseif playdate.buttonJustPressed(playdate.kButtonDown) then
            -- 從上排跳到下排的零件
            for _, item in ipairs(eq) do
                if item.row == 1 then
                    unequip_selected_col = item.col
                    unequip_selected_row = item.row
                    break
                end
            end
            -- 播放游標移動音效
            if _G.SoundManager and _G.SoundManager.playCursorMove then
                _G.SoundManager.playCursorMove()
            end
        elseif playdate.buttonJustPressed(playdate.kButtonA) then
            -- 解除選中格子上的零件
            for i = #eq, 1, -1 do
                local item = eq[i]
                local slot_w = item.w or 1
                local slot_h = item.h or 1
                -- 檢查選中的格子是否在零件範圍內
                if unequip_selected_col >= item.col and unequip_selected_col < item.col + slot_w and
                   unequip_selected_row >= item.row and unequip_selected_row < item.row + slot_h then
                    -- 從 equipped_parts 移除
                    table.remove(eq, i)
                    
                    -- 將零件重新添加到左側清單
                    local part_data = _G.PartsData and _G.PartsData[item.id]
                    if part_data then
                        local placement_row = part_data.placement_row
                        local category = (placement_row == "TOP") and "TOP" or "BOTTOM"
                        
                        -- 檢查該零件是否已在清單中（避免重複）
                        local parts_list = _G.GameState.parts_by_category[category] or {}
                        local already_in_list = false
                        for _, pid in ipairs(parts_list) do
                            if pid == item.id then
                                already_in_list = true
                                break
                            end
                        end
                        
                        -- 如果不在清單中，加入
                        if not already_in_list then
                            table.insert(_G.GameState.parts_by_category[category], item.id)
                        end
                    end
                    
                    -- 從 GRID_MAP 清除
                    for r = item.row, item.row + slot_h - 1 do
                        for c = item.col, item.col + slot_w - 1 do
                            GRID_MAP[r][c] = nil
                        end
                    end
                    
                    -- [[ CORE ]] 統一重算（含核心基礎 HP），不再各自扣除
                    recalcMechStats()


                    print("Unequipped part: " .. item.id)
                    -- 播放選擇音效
                    if _G.SoundManager and _G.SoundManager.playSelect then
                        _G.SoundManager.playSelect()
                    end
                    break
                end
            end
        elseif playdate.buttonJustPressed(playdate.kButtonB) then
            -- 按 B 返回零件清單
            is_unequip_mode = false
        end
        return
    end
    
    if hq_mode == "EQUIP" then
        if cursor_on_start then
            -- [[ P5 ]] 游標在右下角固定 START 鈕：A 直接開始任務（READY 彈窗已移除），
            -- 左鍵/B 回主選單
            if playdate.buttonJustPressed(playdate.kButtonA) then
                -- [[ 零件限制 ]] 任務要求的零件類別未裝備時擋下（START 鈕旁有 NEED 提示）
                if getMissingRequiredParts() then
                    if _G.SoundManager and _G.SoundManager.playCancel then
                        _G.SoundManager.playCancel()
                    end
                    return
                end
                -- [[ 耐久 §8.07 ]] 機體上有壞掉的零件 → 擋下出擊。
                -- ★ 為什麼需要這一道（安裝已經擋過了）：零件是**在結算時**才歸零的，
                --   歸零當下它還裝在機體上。不擋的話玩家會帶著壞零件出擊。
                -- ★ 不自動卸下 —— 那太粗暴（可能進關卡才發現沒腿）；讓玩家自己決定修或換。
                if _G.Durability and _G.Durability.brokenEquipped then
                    local broken = _G.Durability.brokenEquipped()
                    if #broken > 0 then
                        broken_flash = 24
                        print("LOG: launch blocked, broken parts equipped: " .. table.concat(broken, ", "))
                        if _G.SoundManager and _G.SoundManager.playCancel then
                            _G.SoundManager.playCancel()
                        end
                        return
                    end
                end
                if _G.SoundManager and _G.SoundManager.playSelect then
                    _G.SoundManager.playSelect()
                end
                _G.GameState = _G.GameState or {}
                if not _G.GameState.current_mission then
                    _G.GameState.current_mission = "M001"
                    print("WARNING: No current_mission set, using M001 as fallback")
                end
                -- [[ 2026-08-13 ]] 先播「按下」那一格，動畫播完才進關卡（見 update 開頭）
                start_press_timer = 8
                start_launch_pending = true
                print("Starting mission:", _G.GameState.current_mission)
            elseif playdate.buttonJustPressed(playdate.kButtonLeft) or playdate.buttonJustPressed(playdate.kButtonB) then
                cursor_on_start = false
                selected_category = nil
                if _G.SoundManager and _G.SoundManager.playCursorMove then
                    _G.SoundManager.playCursorMove()
                end
            end
        elseif not selected_category then
            -- [[ P5 ]] 主選單層：上下移動、A 進入、右鍵跳 START、B 回任務選擇
            -- （SHOP 原型隱藏；拆卸改為明示選項 REMOVE PART）
            if playdate.buttonJustPressed(playdate.kButtonUp) then
                main_menu_index = math.max(1, main_menu_index - 1)
                -- 播放游標移動音效
                if _G.SoundManager and _G.SoundManager.playCursorMove then
                    _G.SoundManager.playCursorMove()
                end
            elseif playdate.buttonJustPressed(playdate.kButtonDown) then
                main_menu_index = math.min(#MAIN_MENU, main_menu_index + 1)
                -- 播放游標移動音效
                if _G.SoundManager and _G.SoundManager.playCursorMove then
                    _G.SoundManager.playCursorMove()
                end
            elseif playdate.buttonJustPressed(playdate.kButtonRight) then
                cursor_on_start = true
                -- 播放游標移動音效
                if _G.SoundManager and _G.SoundManager.playCursorMove then
                    _G.SoundManager.playCursorMove()
                end
            elseif playdate.buttonJustPressed(playdate.kButtonA) then
                -- 播放選擇音效
                if _G.SoundManager and _G.SoundManager.playSelect then
                    _G.SoundManager.playSelect()
                end
                if main_menu_index == 1 or main_menu_index == 2 then
                    -- [[ 2026-08-13 ]] TOP PARTS / BOTTOM PARTS 不再於 HQ 內展開清單，
                    -- 改為**進入 PARTS 介面**（原商店），並把要顯示的排別帶過去。
                    -- 購買、修理、安裝都在那邊完成 —— SHOP 鈕因此不再需要。
                    _G.GameState.parts_filter_row = (main_menu_index == 1) and "TOP" or "BOTTOM"
                    if _G.SoundManager and _G.SoundManager.playSelect then
                        _G.SoundManager.playSelect()
                    end
                    setState(_G.StateShop)
                else
                    -- REMOVE PART：進入拆卸模式
                    is_unequip_mode = true
                    local eq = _G.GameState.mech_stats.equipped_parts or {}
                    if #eq > 0 then
                        unequip_selected_col = eq[1].col
                        unequip_selected_row = eq[1].row
                    end
                end
            elseif playdate.buttonJustPressed(playdate.kButtonB) then
                -- B=返回上一層：主選單層返回任務選擇畫面（取代舊 BACK 選項）
                setState(_G.StateMissionSelect)
            end
        else
            -- 已選分類，選擇零件或移動到 READY
            local parts_list = _G.GameState.parts_by_category[selected_category]
            local parts_count = #parts_list
            -- [[ G2 ]] 依目前零件寬度夾住安裝欄（切換到不同寬度的零件時同步）
            do
                local pd_cur = _G.PartsData and _G.PartsData[parts_list[selected_part_index]]
                cursor_col = math.max(1, math.min(cursor_col, maxOriginCol(pd_cur)))
            end

            if playdate.buttonJustPressed(playdate.kButtonUp) then
                -- 向上移動，跳過已安裝的零件
                local new_index = selected_part_index - 1
                while new_index >= 1 do
                    local check_part_id = parts_list[new_index]
                    local is_equipped = false
                    local eq = _G.GameState.mech_stats.equipped_parts or {}
                    for _, item in ipairs(eq) do
                        if item.id == check_part_id then
                            is_equipped = true
                            break
                        end
                    end
                    if not is_equipped then
                        selected_part_index = new_index
                        break
                    end
                    new_index = new_index - 1
                end
                -- 播放游標移動音效
                if _G.SoundManager and _G.SoundManager.playCursorMove then
                    _G.SoundManager.playCursorMove()
                end
            elseif playdate.buttonJustPressed(playdate.kButtonDown) then
                -- 向下移動，跳過已安裝的零件
                local new_index = selected_part_index + 1
                while new_index <= parts_count do
                    local check_part_id = parts_list[new_index]
                    local is_equipped = false
                    local eq = _G.GameState.mech_stats.equipped_parts or {}
                    for _, item in ipairs(eq) do
                        if item.id == check_part_id then
                            is_equipped = true
                            break
                        end
                    end
                    if not is_equipped then
                        selected_part_index = new_index
                        break
                    end
                    new_index = new_index + 1
                end
                -- 播放游標移動音效
                if _G.SoundManager and _G.SoundManager.playCursorMove then
                    _G.SoundManager.playCursorMove()
                end
            elseif playdate.buttonJustPressed(playdate.kButtonLeft) then
                -- [[ G2 ]] 左右鍵＝選擇安裝位置（欄），夾在合法原點範圍（寬零件不可超出）
                local pd = _G.PartsData and _G.PartsData[parts_list[selected_part_index]]
                cursor_col = math.max(1, cursor_col - 1)
                cursor_col = math.min(cursor_col, maxOriginCol(pd))
                if _G.SoundManager and _G.SoundManager.playCursorMove then
                    _G.SoundManager.playCursorMove()
                end
            elseif playdate.buttonJustPressed(playdate.kButtonRight) then
                local pd = _G.PartsData and _G.PartsData[parts_list[selected_part_index]]
                cursor_col = math.min(maxOriginCol(pd), cursor_col + 1)
                if _G.SoundManager and _G.SoundManager.playCursorMove then
                    _G.SoundManager.playCursorMove()
                end
            elseif playdate.buttonJustPressed(playdate.kButtonA) then
                -- [[ G2 ]] A＝直接安裝在目前選定的位置（放置模式已合併掉）
                local parts_list2 = _G.GameState.parts_by_category[selected_category]
                local part_id = parts_list2 and parts_list2[selected_part_index]
                local part_data = part_id and _G.PartsData and _G.PartsData[part_id]

                -- 已安裝的零件不能再選
                local is_equipped = false
                for _, item in ipairs(_G.GameState.mech_stats.equipped_parts or {}) do
                    if item.id == part_id then is_equipped = true break end
                end

                if part_data and not is_equipped then
                    cursor_row = rowForPart(part_data)
                    local can_fit = checkIfFits(part_data, cursor_col, cursor_row)
                    -- [[ 耐久 §8.07 ]] 耐久歸零 → **不能裝備**（零件還在，修好即可用）。
                    -- ★ 擋在這裡而不是 checkIfFits 裡面，理由與 OVERWEIGHT 完全相同：
                    --   checkIfFits 另外兩個呼叫點是「找空位」與「畫 X 標記」的預覽用途，
                    --   它們沒有 part_id；而且這是**零件本身的狀態**，不是「這格放不放得下」。
                    -- ★ 不做「效能下降」—— 那會把戰鬥數值拉回來，違背「耐久只影響經濟」的設計。
                    local is_broken = _G.Durability and _G.Durability.isBroken
                                      and _G.Durability.isBroken(part_id)
                    -- [[ CORE ]] GDD §8.05:超過核心負重上限 → 擋在安裝階段（不做「可裝但變慢」）
                    local within_weight, after_w, cap_w = weightAfterInstall(part_data)
                    if can_fit and is_broken then
                        broken_flash = 24   -- 顯示 BROKEN 提示的幀數（與 OVERWEIGHT 同一套）
                        print("LOG: install blocked, part broken: " .. tostring(part_id))
                        if _G.SoundManager and _G.SoundManager.playCancel then
                            _G.SoundManager.playCancel()
                        end
                    elseif can_fit and not within_weight then
                        overweight_flash = 24   -- 顯示 OVERWEIGHT 提示的幀數
                        print(string.format("LOG: install blocked, weight %d > cap %d (%s)",
                                            after_w, cap_w, tostring(part_id)))
                        if _G.SoundManager and _G.SoundManager.playCancel then
                            _G.SoundManager.playCancel()
                        end
                    elseif can_fit then
                        installPart(part_id, part_data, cursor_col, cursor_row)
                        if _G.SoundManager and _G.SoundManager.playSelect then
                            _G.SoundManager.playSelect()
                        end
                        -- 安裝後：該排已滿就回主選單，否則自動選下一個未裝備零件
                        local has_top, has_bottom = false, false
                        for _, item in ipairs(_G.GameState.mech_stats.equipped_parts or {}) do
                            for r = item.row, item.row + (item.h or 1) - 1 do
                                if r == 2 then has_top = true end
                                if r == 1 then has_bottom = true end
                            end
                        end
                        if (selected_category == "TOP" and has_top) or (selected_category == "BOTTOM" and has_bottom) then
                            selected_category = nil
                            selected_part_index = 1
                        else
                            selected_part_index = nextUnequippedIndex(parts_list2, selected_part_index)
                        end
                    else
                        -- 不可放（該格已有零件／排限制／槍口淨空）
                        -- [[ 2026-08-13 ]] 除了錯誤音，**高亮外框也要閃**——
                        -- 原本只有音效 + 事前的 X 標示，按下去當下沒有任何「就是這一格不行」的回饋。
                        place_error_flash = 18
                        if _G.SoundManager and _G.SoundManager.playCancel then
                            _G.SoundManager.playCancel()
                        end
                    end
                end
            elseif playdate.buttonJustPressed(playdate.kButtonB) then
                selected_category = nil
                selected_part_index = 1
            end
        end
    
    end
    -- [[ P5 ]] 舊 hq_mode == "UNEQUIP" 分支為死碼（實際拆卸走 is_unequip_mode），已刪除
    
    -- 更新粗邊框閃爍計時
    cursor_blink_tick = (cursor_blink_tick + 1) % 20
end


function StateHQ.draw()
    
    -- [[ G2 ]] 底圖：有 hq_bg 就鋪滿全螢幕，否則退回白底
    if hq_bg_img then
        pcall(function() hq_bg_img:draw(0, 0) end)
    else
        gfx.clear(gfx.kColorWhite)
    end
    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(font)
    -- 使用時間為基準的閃爍，避免某些情況下 tick 未更新導致不閃爍
    local blink_on = (math.floor(playdate.getCurrentTimeMilliseconds() / 250) % 2) == 0

    -- [[ G2 ]] 不再畫白底框：DATA / PANEL / MISSION 的框線由底圖 hq_bg.png 提供

    -- [[ G2 機甲 2 倍放大 ]] 機甲（格線／零件／爪臂／游標）先以原生像素畫進離屏
    -- 畫布，本區段結束後再 drawScaled 置中放大。期間座標皆為畫布內座標。
    local mech_canvas = gfx.image.new(MECH_CANVAS_W, MECH_CANVAS_H)
    gfx.pushContext(mech_canvas)
    gfx.clear(gfx.kColorClear)
    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(font)

    -- 1. 繪製組裝網格背景

    -- 2. 繪製機甲網格邊框 (作為機甲本體的佔位符)
    local mech_image_x = GRID_START_X
    local mech_image_y = GRID_START_Y
    local mech_width = GRID_CELL_SIZE * GRID_COLS
    local mech_height = GRID_CELL_SIZE * GRID_ROWS
    
    gfx.drawRect(mech_image_x, mech_image_y, mech_width, mech_height)
--    gfx.drawText("MECH ASSEMBLY GRID", mech_image_x + 5, mech_image_y + 5)

    -- [[ CORE ]] 核心的繪製在下方「繪製格子格線」之後（要蓋過格線），見該處。

    -- Grid and parts rendering handled below (draw grid lines, then draw each equipped part once)
    
    -- [[ 2026-08-13 ]] 3. 「左側零件預覽框」整段已移除。
    -- 新版 hq_bg 沒有那個框了 —— 零件的外觀/數值/價格改在 PARTS 介面看，
    -- HQ 只負責「機體長怎樣 + 這個零件要放哪一格」（游標粗框已足夠指示）。

    -- 如果在解除裝備模式，繪製選中框
    if is_unequip_mode and blink_on then
        local cursor_x = GRID_START_X + (unequip_selected_col - 1) * GRID_CELL_SIZE
        local cursor_y = GRID_START_Y + (GRID_ROWS - unequip_selected_row) * GRID_CELL_SIZE
        
        -- 繪製粗框標示選取的零件
        gfx.setColor(gfx.kColorBlack)
        gfx.setLineWidth(2)
        
        -- 找出選中格子所屬的零件並繪製完整範圍的框
        local eq = _G.GameState.mech_stats.equipped_parts or {}
        for _, item in ipairs(eq) do
            local slot_w = item.w or 1
            local slot_h = item.h or 1
            if unequip_selected_col >= item.col and unequip_selected_col < item.col + slot_w and
               unequip_selected_row >= item.row and unequip_selected_row < item.row + slot_h then
                local fx = GRID_START_X + (item.col - 1) * GRID_CELL_SIZE
                local fy = GRID_START_Y + (GRID_ROWS - item.row) * GRID_CELL_SIZE - (slot_h - 1) * GRID_CELL_SIZE
                local fw = slot_w * GRID_CELL_SIZE
                local fh = slot_h * GRID_CELL_SIZE
                gfx.drawRect(fx, fy, fw, fh)
                break
            end
        end
        
        gfx.setLineWidth(1)
    end
    
    -- [[ G2 ]] 標示「不可放置」的格子（圖：images/dither.png，2026-08-06 由 X.png 改為 dither）。
    -- 這是**唯一**的不可放置標示——舊的「整排鋪 dither」預覽已於同日移除，避免兩層疊在一起。
    -- 規則（修正舊的 per-origin 誤判）：
    --   1. 不屬於此零件安裝排的整排 → 標示（例：CLAW/CANON 是上排零件，下排整排標）
    --   2. 安裝排上、在合法原點範圍內、但該欄放不下（已佔用／槍口淨空）→ 標示
    --   3. 安裝排上、超出原點範圍的欄（會被寬零件覆蓋，非可選原點）→ 不標示
    -- 這樣就不會出現「上排 col3 因 2 格寬超界而標記、卻仍能安裝覆蓋該格」的矛盾。
    if selected_category and selected_part_index and not is_unequip_mode then
        local parts_list = _G.GameState.parts_by_category[selected_category]
        local part_id = parts_list and parts_list[selected_part_index]
        local pdata = _G.PartsData and _G.PartsData[part_id]
        if pdata then
            local vrow = rowForPart(pdata)
            local max_origin = maxOriginCol(pdata)
            for r = 1, GRID_ROWS do
                for c = 1, GRID_COLS do
                    local blocked
                    if r ~= vrow then
                        blocked = true                       -- 規則 1
                    elseif c <= max_origin then
                        blocked = not checkIfFits(pdata, c, r) -- 規則 2
                    else
                        blocked = false                      -- 規則 3
                    end
                    if blocked then
                        local cx = GRID_START_X + (c - 1) * GRID_CELL_SIZE
                        local cy = GRID_START_Y + (GRID_ROWS - r) * GRID_CELL_SIZE
                        if x_marker_img then
                            pcall(function() x_marker_img:draw(cx, cy) end)
                        else
                            gfx.drawText("X", cx + math.floor(GRID_CELL_SIZE/2) - 3, cy + math.floor(GRID_CELL_SIZE/2) - 6)
                        end
                    end
                end
            end
        end
    end
    
    -- （4. 零件選單／清單已移至機甲離屏區之後，避免被畫進畫布）

    -- 5. [[ G2 ]] DATA 框內容座標（HP / WEIGHT）；框線由底圖提供
    local detail_x = HQ_LAYOUT.data.x + 6
    local detail_y = HQ_LAYOUT.data.y + 8
    
    -- 繪製格子格線（上下兩排都顯示）
    for r = 1, GRID_ROWS do
        for c = 1, GRID_COLS do
            local cell_x = GRID_START_X + (c - 1) * GRID_CELL_SIZE
            local cell_y = GRID_START_Y + (r - 1) * GRID_CELL_SIZE
            gfx.setColor(gfx.kColorBlack)
            gfx.drawRect(cell_x, cell_y, GRID_CELL_SIZE, GRID_CELL_SIZE)
        end
    end

    -- [[ 2026-08-13 ]] 核心不再畫在組裝格中央 —— 依使用者拍板，核心改成右下角的**出擊按鈕**
    -- （core1-table-64-64），不佔用也不遮擋 6 格組裝區。原本畫在格中央的那段已移除。



    -- [[ 2026-08-06 移除 ]] 舊的「整排鋪 dither」預覽已刪除：
    --   不可安裝的標示改用 dither 之後，它與上方「不可放置格」那段畫的是同一張圖，
    --   兩者疊在一起。上方那段用 checkIfFits 逐格判定（涵蓋不同排、已佔用、槍口淨空），
    --   舊的這段只依 placement_row 把「另一排」整排鋪滿，是它的子集且較不精確，故整段移除。
    --   （行為差異：游標停在 START 鈕時，舊段不畫、新段仍會畫標示。）


    -- 繪製已放置的零件，每個零件只繪製一次，佔據 w x h 格
    -- 分兩階段繪製：先下排(row=1)再上排(row=2)
                local eq = _G.GameState and _G.GameState.mech_stats and _G.GameState.mech_stats.equipped_parts or {}
                
                -- 第一階段：繪製下排零件（row=1）和對應的上排格子 dither
                for _, item in ipairs(eq) do
                    if item.row == 1 then
                        local pid = item.id
                        local pdata = (_G.PartsData and _G.PartsData[pid]) or nil
                        local px = GRID_START_X + (item.col - 1) * GRID_CELL_SIZE
                        -- convert item.row (bottom-left origin) to top-based y
                        local py_top = GRID_START_Y + (GRID_ROWS - item.row) * GRID_CELL_SIZE
                        local pw = (item.w or 1) * GRID_CELL_SIZE
                        local ph = (item.h or 1) * GRID_CELL_SIZE
                        
                        -- 繪製零件圖片
                        if pdata and pdata._img_scaled then
                            -- draw pre-rendered image; anchor bottom-left so full image visible
                            local ok, iw, ih = pcall(function() return pdata._img_scaled:getSize() end)
                            if ok and iw and ih then
                                -- ★ image_offset_x/y ＝零件相對格子的位移（反向槍 −8 讓槍口朝左伸出、
                                --   高位槍 y −8 抬高半格）。共 4 個繪製點都要套用，
                                --   漏一處就會變成「機體上正確、組裝格裡偏 8px」（HANDOFF §3-5）。
                                local draw_x = px + (pdata.image_offset_x or 0)
                                local draw_y
                                if pdata.align_image_top then
                                    -- 圖片上緣對齊格子上緣（用於 FEET）
                                    draw_y = py_top + (pdata.image_offset_y or 0)
                                else
                                    -- 預設：圖片底部對齊格子底部
                                    draw_y = py_top + (GRID_CELL_SIZE - ih) + (pdata.image_offset_y or 0)
                                end
                                -- [[ CLAW ]] 合成圖上下都超出格子時，底座不在圖的最底部，
                                -- 用預先算好的位移把底座對回格子（其他零件為 0，不受影響）
                                draw_y = draw_y + (pdata._scaled_offset_y or 0)
                                pcall(function() pdata._img_scaled:draw(draw_x, draw_y) end)
                            else
                                pcall(function() pdata._img_scaled:draw(px, py_top) end)
                            end
                            
                            -- [[ 2026-08-08 移除 ]] 這裡原本又畫一次臂與爪（畫在 px,py_top ＝底座左上角），
                            -- 但 _img_scaled 合成圖**已經含臂與爪**了 → 畫面上會多出一組疊在底座左邊。
                        elseif pdata and pdata._img then
                            -- fallback: draw original with bottom-left anchoring (no scaling)
                            local iw, ih
                            local ok, a, b = pcall(function() return pdata._img:getSize() end)
                            if ok then iw, ih = a, b end
                            local draw_x = px
                            local draw_y
                            if pdata.align_image_top then
                                -- 圖片上緣對齊格子上緣（用於 FEET 等超出格子的零件）
                                draw_y = py_top
                            else
                                -- 預設：圖片底部對齊格子底部
                                draw_y = py_top + (GRID_CELL_SIZE - (ih or GRID_CELL_SIZE))
                            end
                            -- [[ BUGFIX 2026-08-08 ]] CANON 底座必須先畫，砲管才會在上層。
                            -- 舊版把底座畫在最後 → 32px 寬的底座把 40px 砲管蓋掉一大半
                            -- （砲管早期是 64×8 細長條，露在外面所以看不出來；改成 40×16 後就明顯了）。
                            if pdata.part_type == "CANON" and pdata._base_img then
                                pcall(function() pdata._base_img:draw(draw_x, draw_y) end)
                            end
                            -- barrel_offset_y：砲管上移，底座留在原位（與機體上的畫法一致）
                            -- 這個欄位只有 CANON 系列會設，其他零件取到 0，不必判斷 part_type
                            local body_y = draw_y + (pdata.barrel_offset_y or 0)
                            pcall(function() pdata._img:draw(draw_x, body_y) end)
                            
                            -- 繪製 CLAW 的額外部件
                            if pid == "CLAW" then
                                if pdata._arm_img then
                                    pcall(function() pdata._arm_img:draw(draw_x, draw_y) end)
                                end
                                if pdata._upper_img then
                                    pcall(function() pdata._upper_img:draw(draw_x, draw_y) end)
                                end
                                if pdata._lower_img then
                                    pcall(function() pdata._lower_img:draw(draw_x, draw_y) end)
                                end
                            end
                        else
                            -- no image: draw text label at the origin cell
                            gfx.setColor(gfx.kColorBlack)
                            gfx.drawText(pid or "?", px + 2, py_top + 2)
                        end
                    end
                end
                
                -- 第二階段：繪製上排零件（row=2）和對應的下排格子 dither
                for _, item in ipairs(eq) do
                    if item.row == 2 then
                        local pid = item.id
                        local pdata = (_G.PartsData and _G.PartsData[pid]) or nil
                        local px = GRID_START_X + (item.col - 1) * GRID_CELL_SIZE
                        -- convert item.row (bottom-left origin) to top-based y
                        local py_top = GRID_START_Y + (GRID_ROWS - item.row) * GRID_CELL_SIZE
                        local pw = (item.w or 1) * GRID_CELL_SIZE
                        local ph = (item.h or 1) * GRID_CELL_SIZE
                        
                        -- 繪製零件圖片
                        if pdata and pdata._img_scaled then
                            -- draw pre-rendered image; anchor bottom-left so full image visible
                            local ok, iw, ih = pcall(function() return pdata._img_scaled:getSize() end)
                            if ok and iw and ih then
                                -- ★ image_offset_x/y ＝零件相對格子的位移（反向槍 −8 讓槍口朝左伸出、
                                --   高位槍 y −8 抬高半格）。共 4 個繪製點都要套用，
                                --   漏一處就會變成「機體上正確、組裝格裡偏 8px」（HANDOFF §3-5）。
                                local draw_x = px + (pdata.image_offset_x or 0)
                                local draw_y
                                if pdata.align_image_top then
                                    -- 圖片上緣對齊格子上緣（用於 FEET）
                                    draw_y = py_top + (pdata.image_offset_y or 0)
                                else
                                    -- 預設：圖片底部對齊格子底部
                                    draw_y = py_top + (GRID_CELL_SIZE - ih) + (pdata.image_offset_y or 0)
                                end
                                -- [[ CLAW ]] 合成圖上下都超出格子時，底座不在圖的最底部，
                                -- 用預先算好的位移把底座對回格子（其他零件為 0，不受影響）
                                draw_y = draw_y + (pdata._scaled_offset_y or 0)
                                pcall(function() pdata._img_scaled:draw(draw_x, draw_y) end)
                            else
                                pcall(function() pdata._img_scaled:draw(px, py_top) end)
                            end
                            
                            -- [[ 2026-08-08 移除 ]] 這裡原本又畫一次臂與爪（畫在 px,py_top ＝底座左上角），
                            -- 但 _img_scaled 合成圖**已經含臂與爪**了 → 畫面上會多出一組疊在底座左邊。
                        elseif pdata and pdata._img then
                            -- fallback: draw original with bottom-left anchoring (no scaling)
                            local iw, ih
                            local ok, a, b = pcall(function() return pdata._img:getSize() end)
                            if ok then iw, ih = a, b end
                            local draw_x = px
                            local draw_y
                            if pdata.align_image_top then
                                -- 圖片上緣對齊格子上緣（用於 FEET 等超出格子的零件）
                                draw_y = py_top
                            else
                                -- 預設：圖片底部對齊格子底部
                                draw_y = py_top + (GRID_CELL_SIZE - (ih or GRID_CELL_SIZE))
                            end
                            -- [[ BUGFIX 2026-08-08 ]] CANON 底座必須先畫，砲管才會在上層。
                            -- 舊版把底座畫在最後 → 32px 寬的底座把 40px 砲管蓋掉一大半
                            -- （砲管早期是 64×8 細長條，露在外面所以看不出來；改成 40×16 後就明顯了）。
                            if pdata.part_type == "CANON" and pdata._base_img then
                                pcall(function() pdata._base_img:draw(draw_x, draw_y) end)
                            end
                            -- barrel_offset_y：砲管上移，底座留在原位（與機體上的畫法一致）
                            -- 這個欄位只有 CANON 系列會設，其他零件取到 0，不必判斷 part_type
                            local body_y = draw_y + (pdata.barrel_offset_y or 0)
                            pcall(function() pdata._img:draw(draw_x, body_y) end)
                            -- CLAW 特殊處理：繪製額外部件
                            if pid == "CLAW" then
                                if pdata._arm_img then pcall(function() pdata._arm_img:draw(draw_x, draw_y) end) end
                                if pdata._upper_img then pcall(function() pdata._upper_img:draw(draw_x, draw_y) end) end
                                if pdata._lower_img then pcall(function() pdata._lower_img:draw(draw_x, draw_y) end) end
                            end
                        else
                            -- no image: draw text label at the origin cell
                            gfx.setColor(gfx.kColorBlack)
                            gfx.drawText(pid or "?", px + 2, py_top + 2)
                        end
                    end
                end

    -- ============================================================
    -- [[ 耐久 §8.07 ]] 組裝格角落的耐久標記
    -- ★ 獨立成**一個 pass**，不塞進上面那兩個階段（下排/上排）——
    --   塞進去要寫兩次，日後改一邊忘另一邊就會「上排有標記、下排沒有」（HANDOFF §3-5）。
    -- ★ 畫在零件圖之**後**，否則會被零件蓋掉。
    -- ★ 顯示規則（GDD §8.05b）：滿~30% 不顯示（版面乾淨）／29~1% 預警／0% 損壞。
    -- ⚠️ 目前是**程式繪製的佔位**：損壞＝實心方塊、預警＝空心方塊，都有白底
    --   （零件圖本身有黑有白，沒白底會糊在線條裡 —— §3-4）。
    --   美術到位後改成讀圖即可，位置與尺寸都在下面這一區。
    -- ============================================================
    do
        local D = _G.Durability
        if D and D.isBroken then
            local MARK = 8      -- 標記邊長（組裝格 16px，畫在右上角）
            local eqd = _G.GameState and _G.GameState.mech_stats
                        and _G.GameState.mech_stats.equipped_parts or {}
            for _, item in ipairs(eqd) do
                local broken = D.isBroken(item.id)
                local low    = D.isLow and D.isLow(item.id)
                if broken or low then
                    -- 對齊零件**佔用格子**的右上角（不吃 image_offset —— 標記屬於格子，不屬於圖）
                    local cw = (item.w or 1) * GRID_CELL_SIZE
                    local mx = GRID_START_X + (item.col - 1) * GRID_CELL_SIZE + cw - MARK
                    local my = GRID_START_Y + (GRID_ROWS - item.row) * GRID_CELL_SIZE
                    gfx.setColor(gfx.kColorWhite)
                    gfx.fillRect(mx, my, MARK, MARK)
                    gfx.setColor(gfx.kColorBlack)
                    if broken then
                        gfx.fillRect(mx + 1, my + 1, MARK - 2, MARK - 2)   -- 實心＝已損壞
                    else
                        gfx.drawRect(mx, my, MARK, MARK)                   -- 空心＝快壞了
                    end
                end
            end
        end
    end

    -- [[ 2026-08-13 ]] 安裝失敗回饋：在不可安裝的格子按了 A → 安裝位置的粗框**快速閃爍**。
    -- ★ 獨立於下面的 `blink_on` 區塊：那是 250ms 的慢節拍，用來做「這裡是目前位置」的常態提示；
    --   錯誤回饋要更急促才分得出來，所以自己用 3 幀一換的快節拍，且更粗（4px）。
    if place_error_flash > 0 then
        place_error_flash = place_error_flash - 1
        if (place_error_flash // 3) % 2 == 0
           and hq_mode == "EQUIP" and selected_category and selected_part_index and not is_unequip_mode then
            local plist_e = _G.GameState.parts_by_category[selected_category]
            local pid_e = plist_e and plist_e[selected_part_index]
            local pd_e = _G.PartsData and _G.PartsData[pid_e]
            if pd_e then
                local w = pd_e.slot_x or 1
                local h = pd_e.slot_y or 1
                local prow = rowForPart(pd_e)
                local fx = GRID_START_X + (cursor_col - 1) * GRID_CELL_SIZE
                local fy = GRID_START_Y + (GRID_ROWS - prow) * GRID_CELL_SIZE - (h - 1) * GRID_CELL_SIZE
                -- 白外框 + 黑內框：格子裡可能已有零件（黑白都有），單一顏色會被吃掉（§3-4）
                gfx.setColor(gfx.kColorWhite); gfx.setLineWidth(6)
                gfx.drawRect(fx, fy, w * GRID_CELL_SIZE, h * GRID_CELL_SIZE)
                gfx.setColor(gfx.kColorBlack); gfx.setLineWidth(4)
                gfx.drawRect(fx, fy, w * GRID_CELL_SIZE, h * GRID_CELL_SIZE)
                gfx.setLineWidth(1)
            end
        end
    end

    -- 繪製置中的粗框（選位置／拆卸模式），在零件圖上層
    if blink_on then
        -- [[ G2 ]] 瀏覽清單時即顯示「目前選定安裝位置」的粗框
        if hq_mode == "EQUIP" and selected_category and selected_part_index and not is_unequip_mode then
            local parts_list = _G.GameState.parts_by_category[selected_category]
            local part_id = parts_list and parts_list[selected_part_index]
            local pdata = _G.PartsData and _G.PartsData[part_id]
            if pdata then
                local w = pdata.slot_x or 1
                local h = pdata.slot_y or 1
                local prow = rowForPart(pdata)
                local fx = GRID_START_X + (cursor_col - 1) * GRID_CELL_SIZE
                local fy = GRID_START_Y + (GRID_ROWS - prow) * GRID_CELL_SIZE - (h - 1) * GRID_CELL_SIZE
                local fw = w * GRID_CELL_SIZE
                local fh = h * GRID_CELL_SIZE
                gfx.setColor(gfx.kColorBlack)
                gfx.setLineWidth(2)
                gfx.drawRect(fx, fy, fw, fh)
                gfx.setLineWidth(1)
            end
        end

        -- 拆卸模式：在選中的零件上繪製粗邊框
        if is_unequip_mode then
            local eq2 = _G.GameState.mech_stats.equipped_parts or {}
            for _, item in ipairs(eq2) do
                local slot_w = item.w or 1
                local slot_h = item.h or 1
                if unequip_selected_col >= item.col and unequip_selected_col < item.col + slot_w and
                   unequip_selected_row >= item.row and unequip_selected_row < item.row + slot_h then
                    local fx = GRID_START_X + (item.col - 1) * GRID_CELL_SIZE
                    local fy = GRID_START_Y + (GRID_ROWS - item.row) * GRID_CELL_SIZE - (slot_h - 1) * GRID_CELL_SIZE
                    local fw = slot_w * GRID_CELL_SIZE
                    local fh = slot_h * GRID_CELL_SIZE
                    gfx.setColor(gfx.kColorBlack)
                    gfx.setLineWidth(2)
                    gfx.drawRect(fx, fy, fw, fh)
                    gfx.setLineWidth(1)
                    break
                end
            end
        end
    end
    
    -- [[ G2 機甲 2 倍放大 ]] 關閉離屏、放大置中畫到畫面。
    -- 定位：讓「組裝格中心」（畫布內座標）放大後落在 HQ_LAYOUT.mech_cx/cy。
    gfx.popContext()
    do
        local scale = HQ_LAYOUT.mech_scale or 2
        local grid_cx_local = GRID_START_X + (GRID_COLS * GRID_CELL_SIZE) / 2
        local grid_cy_local = GRID_START_Y + (GRID_ROWS * GRID_CELL_SIZE) / 2
        local draw_x = HQ_LAYOUT.mech_cx - grid_cx_local * scale
        local draw_y = HQ_LAYOUT.mech_cy - grid_cy_local * scale
        pcall(function() mech_canvas:drawScaled(draw_x, draw_y, scale) end)
    end

    -- 4. [[ G2 ]] 零件選單 / 零件清單（底部中央；移至機甲離屏區之後繪製）
    -- [[ 2026-08-13 ]] 選單改用新底圖的左中框（menu）。內縮 6px 當 padding。
    local list_x = HQ_LAYOUT.menu.x + 6
    local list_y = HQ_LAYOUT.menu.y + 4
    local line_height = 15
    if not selected_category and not is_unequip_mode then
        -- 主選單：反白選取
        for i = 1, #MAIN_MENU do
            local selected = (i == main_menu_index and not cursor_on_start)
            drawSelectableText(MAIN_MENU[i], list_x, list_y + (i - 1) * line_height, selected)
        end
    elseif selected_category then
        -- [[ 2026-08-13 ]] **只顯示目前要安裝的那一個零件**（依使用者要求；舊版是 3 筆捲動視窗）。
        -- ★ 這在新流程下才說得通：TOP/BOTTOM PARTS 現在是進 PARTS 介面挑零件，
        --   回到 HQ 時已經確定要裝哪一個，左側選單的任務只剩「告訴你正在放的是什麼」。
        --   捲動視窗與 ▲▼ 指示因此一併移除（沒有第二筆可捲）。
        local parts_list = _G.GameState.parts_by_category[selected_category] or {}
        local part_id = parts_list[selected_part_index]
        if part_id then
            local is_equipped = false
            for _, item in ipairs(_G.GameState.mech_stats.equipped_parts or {}) do
                if item.id == part_id then is_equipped = true break end
            end
            local selected = (not cursor_on_start and not is_unequip_mode)
            local label = partLabel(part_id)
            drawSelectableText(label, list_x, list_y, selected)
            if is_equipped then
                -- ★ 底線寬度與顯示字串必須用同一個值，否則長度對不上
                local text_width = gfx.getTextSize(label)
                gfx.setColor(selected and gfx.kColorWhite or gfx.kColorBlack)
                gfx.drawLine(list_x, list_y + 7, list_x + text_width, list_y + 7)
                gfx.setColor(gfx.kColorBlack)
            end
            -- 操作提示：這個畫面現在只做「選位置」這件事
            gfx.setColor(gfx.kColorBlack)
            gfx.drawText("A:INSTALL", list_x, list_y + line_height)
        end
    elseif is_unequip_mode then
        -- [[ G2 ]] 移除模式：底中框顯示目前選中的零件與操作提示（原本是空的）
        local _, item = findEquippedPartAt(unequip_selected_col, unequip_selected_row)
        gfx.setColor(gfx.kColorBlack)
        if item then
            gfx.drawText(item.id, list_x, list_y)
            gfx.drawText("A:REMOVE", list_x, list_y + line_height)
        else
            gfx.drawText("(EMPTY)", list_x, list_y)
        end
        gfx.drawText("B:BACK", list_x, list_y + line_height * 2)
    end

    -- [[ 零件限制 ]] 缺必要零件的提示改畫在「零件預覽框」內（原本在 START 上方）。
    -- 畫在框頂端的白底條上，避免蓋住框中央的零件預覽圖。
    do
        local missing = getMissingRequiredParts()
        if missing then
            -- [[ 2026-08-13 ]] 原本畫在「零件預覽框」內，那個框已隨版面重排移除。
            -- 改畫在 MISSION 框正下方（白底黑字，§3-4）—— 出擊前一定看得到。
            local mb = HQ_LAYOUT.mission
            local need_text = "NEED: " .. table.concat(missing, ",")
            local ntw, nth = gfx.getTextSize(need_text)
            local nx = mb.x + mb.w - ntw - 4
            local ny = mb.y + mb.h + 3
            gfx.setColor(gfx.kColorWhite)
            gfx.fillRect(nx - 3, ny - 2, ntw + 6, nth + 4)
            gfx.setColor(gfx.kColorBlack)
            gfx.drawText(need_text, nx, ny)
        end
    end

    -- 6. [[ G2 ]] 機甲狀態（畫在底圖的 DATA 框內）
    local stats = _G.GameState and _G.GameState.mech_stats or { total_hp = 0, total_weight = 0 }
    gfx.setColor(gfx.kColorBlack)
    -- [[ 2026-08-13 ]] 數值一變就觸發放大 —— 安裝/拆卸/修理後才知道「剛剛改到了什麼」。
    -- ★ 用 drawTextScaled 直接放大，並讓文字**以左下角為錨點**外擴，
    --   避免放大時撞到上一行或跑出 DATA 框（框只有 135x46，兩行就滿了）。
    local hp_text = "HP: " .. stats.total_hp
    if data_prev_hp ~= nil and data_prev_hp ~= stats.total_hp then data_pop_hp = DATA_POP_FRAMES end
    if data_prev_wt ~= nil and data_prev_wt ~= stats.total_weight then data_pop_wt = DATA_POP_FRAMES end
    data_prev_hp, data_prev_wt = stats.total_hp, stats.total_weight

    -- ★ Playdate **沒有** drawTextScaled（查過 SDK stub）。
    --   用 `imageWithText` 先把文字算成一張圖，再 `drawScaled` 放大 —— 兩個 API 都是既有可用的
    --   （drawScaled 本專案到處在用）。整段包 pcall，萬一失敗就退回一般文字，不會讓 HQ 掛掉。
    local function drawPopText(text, x, y, pop)
        if pop > 0 then
            local k = 1 + 0.5 * (pop / DATA_POP_FRAMES)   -- 1.5x 起，衰減回 1.0
            local tw, th = gfx.getTextSize(text)
            local ok = pcall(function()
                local img = gfx.imageWithText(text, tw + 4, th + 4)
                if not img then error("no image") end
                -- 以**左下角**為錨點往上長：不會壓到下一行，也不會衝出 DATA 框（135x46 只夠兩行）
                img:drawScaled(x, y - th * (k - 1), k)
            end)
            if not ok then gfx.drawText(text, x, y) end
        else
            gfx.drawText(text, x, y)
        end
    end

    drawPopText(hp_text, detail_x, detail_y, data_pop_hp)
    if data_pop_hp > 0 then data_pop_hp = data_pop_hp - 1 end
    -- [[ CORE ]] 負重顯示成「目前/上限」，上限來自核心（GDD §8.05）
    -- ★ 用 WT 不用 WEIGHT：DATA 框可用寬度只有 88px，
    --   "WEIGHT: 34/34" 要 117px 會爆框；"WT: 34/34" 是 82px（最寬情況，CORE3 滿載）。
    local cap = stats.weight_cap
    local w_text = "WT: " .. tostring(stats.total_weight) .. (cap and ("/" .. cap) or "")
    drawPopText(w_text, detail_x, detail_y + 16, data_pop_wt)
    if data_pop_wt > 0 then data_pop_wt = data_pop_wt - 1 end

    -- [[ CORE ]] 因超重被擋下時：WEIGHT 那行反白閃爍幾幀，讓玩家知道為什麼裝不上去
    if overweight_flash > 0 then
        overweight_flash = overweight_flash - 1
        if (overweight_flash // 4) % 2 == 0 then
            local tw, th = gfx.getTextSize(w_text)
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRect(detail_x - 2, detail_y + 16 - 2, tw + 4, (th or 14) + 4)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
            gfx.drawText(w_text, detail_x, detail_y + 16)
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        end
    end

    -- [[ 耐久 §8.07 ]] 因零件損壞被擋下時：在 DATA 框下方閃 BROKEN。
    -- ★ 目前是「另外畫一行」而不是佔用 DATA 框 —— DATA 框 97x49 只有 3 行且已被
    --   CORE/HP/WT 佔滿（見 GDD §8.05b）。HQ 版面重排完成後這一段要搬進正式位置。
    if broken_flash > 0 then
        broken_flash = broken_flash - 1
        if (broken_flash // 4) % 2 == 0 then
            local b_text = "BROKEN"
            local tw, th = gfx.getTextSize(b_text)
            local bx, by = detail_x, detail_y + 32
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRect(bx - 2, by - 2, tw + 4, (th or 14) + 4)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
            gfx.drawText(b_text, bx, by)
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        end
    end


    -- [[ 2026-08-13 ]] 7. 出擊按鈕：core1-table-64-64（取代舊的 START 文字方塊）
    --   第 1 格＝底座（一直畫）／第 2 格＝按鈕未按／第 3 格＝按鈕按下
    --   游標在按鈕上時畫第 2 格；按下的瞬間短暫顯示第 3 格。
    do
        local bx, by = HQ_LAYOUT.start_x, HQ_LAYOUT.start_y
        local sheet = startButtonSheet()
        if sheet then
            -- [[ 2026-08-13 ]] 底座與按鈕**一律顯示**（離開焦點也看得到）。
            --   格號：1 = 底座（常駐）／2 = 未按／3 = 按下／**4 = 選中（選配）**
            --
            -- ★ 焦點**不畫外框**（依使用者要求，稍後由圖本身表現）。
            --   已預留第 4 格：imagetable 有 4 格以上時，焦點狀態自動改用第 4 格；
            --   還沒補圖（只有 3 格）就退回第 2 格 —— 與 core2/core3 的處理方式一致，
            --   你把圖放進去就自動生效，不必回來改程式。
            local base = sheet:getImage(1)
            if base then pcall(function() base:draw(bx, by) end) end

            local idx
            if start_press_timer > 0 then
                idx = 3                                  -- 按下
            elseif cursor_on_start then
                local n = (sheet.getLength and sheet:getLength()) or 3
                idx = (n >= 4) and 4 or 2                -- 選中（有第 4 格才用）
            else
                idx = 2                                  -- 未選中
            end
            local btn = sheet:getImage(idx)
            if btn then pcall(function() btn:draw(bx, by) end) end
        else
            -- 圖沒載到時的保險：畫個方框，至少知道按鈕在哪
            gfx.setColor(gfx.kColorBlack)
            gfx.drawRect(bx, by, HQ_LAYOUT.start_size, HQ_LAYOUT.start_size)
        end
    end

    -- [[ 2026-08-13 ]] 7b. SHOP 鈕已移除 —— 改由 TOP PARTS / BOTTOM PARTS 進入 PARTS 介面。

    -- [[ G2 ]] 操作提示列已移除（依使用者要求）

    -- [[ 2026-08-13 ]] 8. 操作面板已整段移除。
    -- 那是**關卡中**的東西（3x2 對應機體零件的操作圖示），組裝畫面用不到，
    -- 新版 hq_bg 也不再有它的位置。關卡內的面板不受影響（在 state_mission）。

    -- 9. [[ G2 ]] 頂部任務資訊（框線由底圖提供，這裡只畫文字）
    local mission_id = (_G and _G.GameState and _G.GameState.current_mission) or "M001"
    if MissionData and MissionData[mission_id] then
        local mission = MissionData[mission_id]
        local mbox = HQ_LAYOUT.mission
        -- [[ G2b ]] 上方黑色標籤：程式畫「寬度隨標題文字長度」的黑底＋白字。
        -- （底圖左上原本的固定黑塊請移除，改由此處動態繪製以自動適應長度。）
        local title = mission.name or "MISSION"
        local ttw, tth = gfx.getTextSize(title)
        local TAB_PAD_X = 8   -- 文字左右內距
        -- [[ 2026-08-13 ]] 依使用者指示：往右 12、往上 2（配合新的 hq_bg 標題位置）
        local tab = { x = 16, y = -1, h = 18 }
        tab.w = ttw + TAB_PAD_X * 2
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRect(tab.x, tab.y, tab.w, tab.h)
        gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        gfx.drawText(title, tab.x + TAB_PAD_X, tab.y + 2 + math.floor((tab.h - tth) / 2))
        gfx.setImageDrawMode(gfx.kDrawModeCopy)
        -- [[ G2b ]] 說明框：說明文字（標題已移到黑色標籤）
        -- [[ 2026-08-11 ]] 下一行加上**本關可獲得的資源**——出擊前就該看得到報酬，
        -- 才有「這關值不值得帶這套裝備去打」的判斷依據（與結算畫面顯示的是同一組數字）。
        gfx.setColor(gfx.kColorBlack)
        local req_text = nil
        if mission.required_parts and #mission.required_parts > 0 then
            req_text = "REQ: " .. table.concat(mission.required_parts, ",")
        end
        if mission.objective then
            local desc = mission.objective.description or ""
            local rs = mission.reward_steel or 0
            local rc = mission.reward_copper or 0
            local rr = mission.reward_rubber or 0
            local reward_text = nil
            if rs > 0 or rc > 0 or rr > 0 then
                reward_text = string.format("REWARD  S:%d  C:%d  R:%d", rs, rc, rr)
            end
            local _, dth = gfx.getTextSize(desc)
            dth = dth or 14
            if reward_text then
                -- 兩行一起垂直置中（行距 4px），不要各自置中
                local gap = 4
                local top = mbox.y + math.floor((mbox.h - (dth * 2 + gap)) / 2)
                gfx.drawText(desc, mbox.x + 6, top)
                local line2_y = top + dth + gap
                gfx.drawText(reward_text, mbox.x + 6, line2_y)
                -- ★ REQ 改畫在**第 2 行右側**（原本在第 1 行右側）。
                --   說明文字最長 353px（"Deliver the stone to the target zone"），右緣到 365，
                --   而 REQ 左緣在 301 —— 同一行會直接疊字（M002/M003/M005 三關就是這個組合）。
                --   REWARD 只有 225px、右緣 237，放同一行才不會撞。
                if req_text then
                    local rtw = gfx.getTextSize(req_text)
                    gfx.drawText(req_text, mbox.x + mbox.w - rtw - 6, line2_y)
                    req_text = nil   -- 已畫，不要再走下面的單行後備
                end
            else
                gfx.drawText(desc, mbox.x + 6, mbox.y + math.floor((mbox.h - dth) / 2))
            end
        end
        -- [[ 零件限制 ]] 沒有 REWARD 那行時（理論上不會發生），REQ 退回原本的右上角
        if req_text then
            local rtw = gfx.getTextSize(req_text)
            gfx.drawText(req_text, mbox.x + mbox.w - rtw - 6, mbox.y + 4)
        end
    end

    -- [[ S10 ]] 教學覆蓋層（畫在最上層）
    if _G.Tutorial and _G.Tutorial.draw then _G.Tutorial.draw() end
end

return StateHQ