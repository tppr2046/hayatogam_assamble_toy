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
local HQ_LAYOUT = {
    mission  = { x = 6,   y = 19,  w = 387, h = 49 },   -- 頂部框：任務名＋目標
    data     = { x = 7,   y = 95,  w = 97,  h = 49 },   -- 左上框：HP / WEIGHT
    -- 左下「無白框」的空位：放 3x2 操作面板（96x64）
    panel    = { x = 2,   y = 150, w = 108, h = 68 },
    -- 中右框 x131 y83 w262 h74：機體 2 倍放大置中於此
    mech_scale = 2,      -- 機體放大倍率
    mech_cx  = 262,      -- 放大後機體「組裝格中心」落點 x（＝中右框水平中心）
    mech_cy  = 120,      -- 放大後機體「組裝格中心」落點 y（＝中右框垂直中心）
    menu_x   = 138,      -- 底中框 x131 w157：零件選單 / 零件清單
    menu_y   = 180,
    start_size = 55,     -- 底右框 x300 y173 55x55（正方形）
    start_x  = 300,
    start_y  = 173,
}

-- [[ G2 ]] 零件清單一次顯示幾筆（底中框 y173~228 高 55px，起點 y180、行高 15
-- → 放得下 3 筆）。超過時捲動並顯示 ▲▼。改行高或框高時記得一起調。
local LIST_VISIBLE = 3

-- [[ G2 ]] 機甲離屏畫布：機甲先以原生像素畫進此畫布，再 drawScaled 放大置中。
-- GRID_START_X/Y 改為「畫布內的組裝格原點」（四周留邊給砲管/腳/預覽溢出）。
local MECH_CANVAS_W = 170
local MECH_CANVAS_H = 110
local GRID_START_X = 40
local GRID_START_Y = 52

-- UI 控制介面相關（操作面板繪於 PANEL 盒內）
local UI_GRID_COLS = 3
local UI_GRID_ROWS = 2
local UI_CELL_SIZE = 32
local UI_START_X = HQ_LAYOUT.panel.x + 6
local UI_START_Y = HQ_LAYOUT.panel.y + 16

-- [[ G2 ]] 反白選取：選中＝黑底白字（穩定不閃爍），未選中＝純黑字。
-- 取代舊的「> text <」＋閃爍樣式。
local function drawSelectableText(text, x, y, selected)
    if selected then
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
local is_unequip_mode = false  -- 是否在解除裝備模式（由主選單 REMOVE PART 進入）
local unequip_selected_col = 1  -- 解除模式選中的格子列
local unequip_selected_row = 1  -- 解除模式選中的格子排
local selected_category = nil   -- nil = 主選單層, "TOP" or "BOTTOM" = 零件清單層
local selected_part_index = 1
local hq_mode = "EQUIP"         -- 固定 EQUIP（舊 UNEQUIP 分支為死碼，已移除）

-- [[ P5 ]] 放置回饋：不可放的格子在放置模式中以 X.png 靜態標示
-- （取代舊「按下才紅閃」——且舊紅閃的 y 映射用 (row-1)，實際畫錯排）
local x_marker_img = nil  -- images/X.png，於 setup 載入
local hq_bg_img = nil     -- [[ G2 ]] images/hq_bg.png 組裝介面底圖（400x240），於 setup 載入
local cursor_blink_tick = 0  -- 控制粗邊框的閃爍
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
    if part_data.hp then
        _G.GameState.mech_stats.total_hp = (_G.GameState.mech_stats.total_hp or 0) + part_data.hp
    end
    if part_data.weight then
        _G.GameState.mech_stats.total_weight = (_G.GameState.mech_stats.total_weight or 0) + part_data.weight
    end
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
    -- 確保即便沒有裝備也有基礎值（例如 0 或先前設定的 base）
    _G.GameState.mech_stats.total_hp = total_hp
    _G.GameState.mech_stats.total_weight = total_weight
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
    
    -- 初始化 MechController（用於繪製介面圖）
    if MechController and MechController.init then
        mech_controller = MechController:init()
    else
        print("WARNING: MechController not found in state_hq")
    end
    
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
                    if pdata.hp then
                        _G.GameState.mech_stats.total_hp = (_G.GameState.mech_stats.total_hp or 0) - pdata.hp
                    end
                    if pdata.weight then
                        _G.GameState.mech_stats.total_weight = (_G.GameState.mech_stats.total_weight or 0) - pdata.weight
                    end
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
            _G.SaveManager.saveCurrent()
        end
    end

    -- 保存網格設定到全域，供任務關卡使用（用於合成機體影像）
    _G.GameState.mech_grid = { cell_size = GRID_CELL_SIZE, cols = GRID_COLS, rows = GRID_ROWS }

    -- [[ P5 ]] 載入「不可放置」標示圖（16x16，放置模式蓋在不可放的格子上）
    if not x_marker_img then
        x_marker_img = gfx.image.new("images/X")
        if not x_marker_img then
            print("WARNING: failed to load images/X.png, fallback to text X")
        end
    end

    -- [[ G2 ]] 載入組裝介面底圖（400x240）
    if not hq_bg_img then
        hq_bg_img = gfx.image.new("images/hq_bg")
        if not hq_bg_img then
            print("WARNING: failed to load images/hq_bg.png")
        end
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
                if sw > 0 and sh > 0 then
                    local ok, buf = pcall(function() return gfx.image.new(sw, sh) end)
                    if ok and buf then
                        gfx.pushContext(buf)
                        gfx.clear(gfx.kColorClear)
                        if gotSize and iw and ih then
                            local dx = math.floor((sw - iw) / 2)
                            local dy = math.floor((sh - ih) / 2)
                            pcall(function() pdata._img:draw(math.max(0, dx), math.max(0, dy)) end)
                        else
                            pcall(function() pdata._img:draw(0, 0) end)
                        end
                        -- 繪製 CLAW 的額外部件到 scaled image
                        if pid == "CLAW" then
                            if pdata._arm_img then pcall(function() pdata._arm_img:draw(math.max(0, dx or 0), math.max(0, dy or 0)) end) end
                            if pdata._upper_img then pcall(function() pdata._upper_img:draw(math.max(0, dx or 0), math.max(0, dy or 0)) end) end
                            if pdata._lower_img then pcall(function() pdata._lower_img:draw(math.max(0, dx or 0), math.max(0, dy or 0)) end) end
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
                    
                    -- 扣除 HP 和 Weight
                    if part_data then
                        if part_data.hp then
                            _G.GameState.mech_stats.total_hp = (_G.GameState.mech_stats.total_hp or 0) - part_data.hp
                        end
                        if part_data.weight then
                            _G.GameState.mech_stats.total_weight = (_G.GameState.mech_stats.total_weight or 0) - part_data.weight
                        end
                    end
                    
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
                if _G.SoundManager and _G.SoundManager.playSelect then
                    _G.SoundManager.playSelect()
                end
                _G.GameState = _G.GameState or {}
                if not _G.GameState.current_mission then
                    _G.GameState.current_mission = "M001"
                    print("WARNING: No current_mission set, using M001 as fallback")
                end
                print("Starting mission:", _G.GameState.current_mission)
                setState(_G.StateMission)
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
                    selected_category = (main_menu_index == 1) and "TOP" or "BOTTOM"
                    selected_part_index = 1
                    -- [[ G2 ]] 進入清單時，安裝位置預設為第一個可放的格（之後用左右鍵調整）
                    local plist = _G.GameState.parts_by_category[selected_category]
                    local pdata0 = plist and plist[1] and _G.PartsData and _G.PartsData[plist[1]]
                    if pdata0 then
                        local c0 = findFirstEmptyCell(pdata0)
                        cursor_col = c0 or 1
                        cursor_row = rowForPart(pdata0)
                    else
                        cursor_col, cursor_row = 1, 1
                    end
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
                -- [[ G2 ]] 左右鍵＝選擇安裝位置（欄），不再跳 START
                cursor_col = math.max(1, cursor_col - 1)
                if _G.SoundManager and _G.SoundManager.playCursorMove then
                    _G.SoundManager.playCursorMove()
                end
            elseif playdate.buttonJustPressed(playdate.kButtonRight) then
                cursor_col = math.min(GRID_COLS, cursor_col + 1)
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
                    if can_fit then
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
                        -- 不可放（該格已有零件／排限制／槍口淨空）：X 標示已事前顯示
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
    
    -- Grid and parts rendering handled below (draw grid lines, then draw each equipped part once)
    
    -- 3. 繪製零件預覽 (選中零件後，即使沒進入放置模式也顯示預覽；解除模式時不顯示)
    if hq_mode == "EQUIP" and selected_category and selected_part_index and not cursor_on_start and not is_unequip_mode then
        local parts_list = _G.GameState.parts_by_category[selected_category]
        local part_id = parts_list and parts_list[selected_part_index]
        local pdata = (_G.PartsData and _G.PartsData[part_id]) or nil
        
        if pdata then
            local preview_x, preview_y
            
            -- [[ G2 ]] 預覽畫在玩家用左右鍵選定的那一格（列由零件類別決定）。
            -- 取代舊的「機體上方浮動預覽」——那個在 2 倍放大後會超出機甲框上緣；
            -- 現在受格子邊界約束不可能溢出，且直接看到零件會裝在哪。
            local prow = rowForPart(pdata)
            preview_x = GRID_START_X + (cursor_col - 1) * GRID_CELL_SIZE
            preview_y = GRID_START_Y + (GRID_ROWS - prow) * GRID_CELL_SIZE
            
            -- 繪製預覽圖片
            if pdata._img_scaled then
                local sw = (pdata.slot_x or 1) * GRID_CELL_SIZE
                local sh = (pdata.slot_y or 1) * GRID_CELL_SIZE
                local draw_y = preview_y + (GRID_CELL_SIZE - sh)
                pcall(function() pdata._img_scaled:draw(preview_x, draw_y) end)
                -- CLAW 特殊處理：繪製額外部件
                if part_id == "CLAW" then
                    if pdata._arm_img then pcall(function() pdata._arm_img:draw(preview_x, draw_y) end) end
                    if pdata._upper_img then pcall(function() pdata._upper_img:draw(preview_x, draw_y) end) end
                    if pdata._lower_img then pcall(function() pdata._lower_img:draw(preview_x, draw_y) end) end
                end
                -- CANON 特殊處理：繪製底座
                if part_id == "CANON1" or part_id == "CANON2" then
                    if pdata._base_img then
                        pcall(function() pdata._base_img:draw(preview_x, draw_y) end)
                    end
                end
                gfx.setColor(gfx.kColorBlack)
                gfx.drawRect(preview_x, draw_y, sw, sh)
                -- 在選擇時繪製閃爍邊框
                if blink_on then
                    gfx.setLineWidth(3)
                    gfx.drawRect(preview_x - 2, draw_y - 2, sw + 4, sh + 4)
                    gfx.setLineWidth(1)
                end
            elseif pdata._img then
                local iw, ih
                local ok, a, b = pcall(function() return pdata._img:getSize() end)
                if ok then iw, ih = a, b end
                local draw_x = preview_x
                local draw_y = preview_y
                if iw and ih then
                    draw_x = preview_x + math.floor((GRID_CELL_SIZE - iw) / 2)
                    draw_y = preview_y + math.floor((GRID_CELL_SIZE - ih) / 2)
                end
                pcall(function() pdata._img:draw(draw_x, draw_y) end)
                -- CLAW 特殊處理：繪製額外部件
                if part_id == "CLAW" then
                    if pdata._arm_img then pcall(function() pdata._arm_img:draw(draw_x, draw_y) end) end
                    if pdata._upper_img then pcall(function() pdata._upper_img:draw(draw_x, draw_y) end) end
                    if pdata._lower_img then pcall(function() pdata._lower_img:draw(draw_x, draw_y) end) end
                end
                -- CANON 特殊處理：繪製底座（在砲管後繪製，這樣底座會顯示在上面）
                if part_id == "CANON1" or part_id == "CANON2" then
                    if pdata._base_img then
                        local ok_base, base_width, base_height = pcall(function() return pdata._base_img:getSize() end)
                        if ok_base and base_width and base_height then
                            local base_draw_x = preview_x + math.floor((GRID_CELL_SIZE - base_width) / 2)
                            local base_draw_y = preview_y + math.floor((GRID_CELL_SIZE - base_height) / 2)
                            pcall(function() pdata._base_img:draw(base_draw_x, base_draw_y) end)
                        else
                            pcall(function() pdata._base_img:draw(draw_x, draw_y) end)
                        end
                    end
                end
                gfx.setColor(gfx.kColorBlack)
                gfx.drawRect(preview_x, preview_y, GRID_CELL_SIZE, GRID_CELL_SIZE)
                -- 在選擇時繪製閃爍邊框
                if blink_on then
                    gfx.setLineWidth(3)
                    gfx.drawRect(preview_x - 2, preview_y - 2, GRID_CELL_SIZE + 4, GRID_CELL_SIZE + 4)
                    gfx.setLineWidth(1)
                end
            end
        end
    end

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
    
    -- [[ P5/G2 ]] 瀏覽零件清單時即以 X 靜態標示不可放置的格子（取代舊紅閃）。
    -- 排限制 / 已佔用 / 槍口淨空全部走同一個 checkIfFits 判定，事前可見。
    if selected_category and selected_part_index and not is_unequip_mode then
        local parts_list = _G.GameState.parts_by_category[selected_category]
        local part_id = parts_list and parts_list[selected_part_index]
        local pdata = _G.PartsData and _G.PartsData[part_id]
        if pdata then
            for r = 1, GRID_ROWS do
                for c = 1, GRID_COLS do
                    if not checkIfFits(pdata, c, r) then
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
    
    -- 預覽模式：在組裝格子上顯示 dither.png（解除模式時不顯示預覽）
    if selected_category and selected_part_index and not cursor_on_start and not is_unequip_mode then
        local parts_list = _G.GameState.parts_by_category[selected_category]
        local part_id = parts_list and parts_list[selected_part_index]
        local pdata = _G.PartsData and _G.PartsData[part_id]
        
        if pdata and mech_controller and mech_controller.ui_images and mech_controller.ui_images.dither then
            local placement_row = pdata.placement_row
            
            -- 找出第一個空格子（預覽位置）
            local check_col, check_row = findFirstEmptyCell(pdata)
            
            if check_col and check_row then
                -- 根據 placement_row 決定 dither 顯示在哪一排
                local dither_row = nil
                if placement_row == "TOP" or (check_row == 2) then
                    -- TOP 零件安裝在上排，在下排（row=1）顯示 dither
                    dither_row = 1
                elseif placement_row == "BOTTOM" or (check_row == 1) then
                    -- BOTTOM 零件安裝在下排，在上排（row=2）顯示 dither
                    dither_row = 2
                end
                
                -- 繪製 dither.png 在對應的排上（整排 3 格）
                if dither_row then
                    for c = 1, GRID_COLS do
                        local dither_x = GRID_START_X + (c - 1) * GRID_CELL_SIZE
                        local dither_y = GRID_START_Y + (GRID_ROWS - dither_row) * GRID_CELL_SIZE
                        pcall(function() mech_controller.ui_images.dither:draw(dither_x, dither_y) end)
                    end
                end
            end
        end
    end
    
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
                                local draw_x = px
                                local draw_y
                                if pdata.align_image_top then
                                    -- 圖片上緣對齊格子上緣（用於 FEET）
                                    draw_y = py_top
                                else
                                    -- 預設：圖片底部對齊格子底部
                                    draw_y = py_top + (GRID_CELL_SIZE - ih)
                                end
                                pcall(function() pdata._img_scaled:draw(draw_x, draw_y) end)
                            else
                                pcall(function() pdata._img_scaled:draw(px, py_top) end)
                            end
                            
                            -- 繪製 CLAW 的額外部件
                            if pid == "CLAW" then
                                if pdata._arm_img then
                                    pcall(function() pdata._arm_img:draw(px, py_top) end)
                                end
                                if pdata._upper_img then
                                    pcall(function() pdata._upper_img:draw(px, py_top) end)
                                end
                                if pdata._lower_img then
                                    pcall(function() pdata._lower_img:draw(px, py_top) end)
                                end
                            end
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
                            pcall(function() pdata._img:draw(draw_x, draw_y) end)
                            
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
                            -- 繪製 CANON 的底座
                            if pid == "CANON1" or pid == "CANON2" then
                                if pdata._base_img then
                                    pcall(function() pdata._base_img:draw(draw_x, draw_y) end)
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
                                local draw_x = px
                                local draw_y
                                if pdata.align_image_top then
                                    -- 圖片上緣對齊格子上緣（用於 FEET）
                                    draw_y = py_top
                                else
                                    -- 預設：圖片底部對齊格子底部
                                    draw_y = py_top + (GRID_CELL_SIZE - ih)
                                end
                                pcall(function() pdata._img_scaled:draw(draw_x, draw_y) end)
                            else
                                pcall(function() pdata._img_scaled:draw(px, py_top) end)
                            end
                            
                            -- 繪製 CLAW 的額外部件
                            if pid == "CLAW" then
                                if pdata._arm_img then
                                    pcall(function() pdata._arm_img:draw(px, py_top) end)
                                end
                                if pdata._upper_img then
                                    pcall(function() pdata._upper_img:draw(px, py_top) end)
                                end
                                if pdata._lower_img then
                                    pcall(function() pdata._lower_img:draw(px, py_top) end)
                                end
                            end
                            -- 繪製 CANON 的底座
                            if pid == "CANON1" or pid == "CANON2" then
                                if pdata._base_img then
                                    pcall(function() pdata._base_img:draw(px, py_top) end)
                                end
                            end
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
                            pcall(function() pdata._img:draw(draw_x, draw_y) end)
                            -- CLAW 特殊處理：繪製額外部件
                            if pid == "CLAW" then
                                if pdata._arm_img then pcall(function() pdata._arm_img:draw(draw_x, draw_y) end) end
                                if pdata._upper_img then pcall(function() pdata._upper_img:draw(draw_x, draw_y) end) end
                                if pdata._lower_img then pcall(function() pdata._lower_img:draw(draw_x, draw_y) end) end
                            end
                            -- CANON 特殊處理：繪製底座
                            if pid == "CANON1" or pid == "CANON2" then
                                if pdata._base_img then
                                    pcall(function() pdata._base_img:draw(draw_x, draw_y) end)
                                end
                            end
                        else
                            -- no image: draw text label at the origin cell
                            gfx.setColor(gfx.kColorBlack)
                            gfx.drawText(pid or "?", px + 2, py_top + 2)
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
    local list_x = HQ_LAYOUT.menu_x
    local list_y = HQ_LAYOUT.menu_y
    local line_height = 15
    if not selected_category and not is_unequip_mode then
        -- 主選單：反白選取
        for i = 1, #MAIN_MENU do
            local selected = (i == main_menu_index and not cursor_on_start)
            drawSelectableText(MAIN_MENU[i], list_x, list_y + (i - 1) * line_height, selected)
        end
    elseif selected_category then
        -- [[ G2 ]] 捲動視窗：底中框只放得下 LIST_VISIBLE 筆，超過時隨游標捲動，
        -- 右側以 ▲▼ 指示上下還有項目。（分類標題已移除——反白選取已足夠指示）
        local parts_list = _G.GameState.parts_by_category[selected_category] or {}
        local total = #parts_list
        local first = 1
        if total > LIST_VISIBLE then
            first = selected_part_index - math.floor(LIST_VISIBLE / 2)
            first = math.max(1, math.min(first, total - LIST_VISIBLE + 1))
        end

        for slot = 1, math.min(LIST_VISIBLE, total) do
            local i = first + slot - 1
            local part_id = parts_list[i]
            local is_equipped = false
            local eq3 = _G.GameState.mech_stats.equipped_parts or {}
            for _, item in ipairs(eq3) do
                if item.id == part_id then is_equipped = true break end
            end
            local selected = (i == selected_part_index and not cursor_on_start and not is_unequip_mode)
            local text_x = list_x
            local text_y = list_y + (slot - 1) * line_height
            drawSelectableText(part_id, text_x, text_y, selected)
            if is_equipped then
                local text_width = gfx.getTextSize(part_id)
                gfx.setColor(selected and gfx.kColorWhite or gfx.kColorBlack)
                gfx.drawLine(text_x, text_y + 7, text_x + text_width, text_y + 7)
                gfx.setColor(gfx.kColorBlack)
            end
        end

        -- ▲▼ 捲動指示（畫在框右側內緣）
        local arrow_x = HQ_LAYOUT.menu_x + 130
        gfx.setColor(gfx.kColorBlack)
        if first > 1 then
            gfx.fillTriangle(arrow_x, list_y + 5, arrow_x + 8, list_y + 5, arrow_x + 4, list_y)
        end
        if first + LIST_VISIBLE - 1 < total then
            local by = list_y + (LIST_VISIBLE - 1) * line_height + 8
            gfx.fillTriangle(arrow_x, by, arrow_x + 8, by, arrow_x + 4, by + 5)
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

    -- 6. [[ G2 ]] 機甲狀態（畫在底圖的 DATA 框內）
    local stats = _G.GameState and _G.GameState.mech_stats or { total_hp = 0, total_weight = 0 }
    gfx.setColor(gfx.kColorBlack)
    gfx.drawText("HP: " .. stats.total_hp, detail_x, detail_y)
    gfx.drawText("WEIGHT: " .. stats.total_weight, detail_x, detail_y + 16)
    
    -- [[ P5/G2 ]] 7. START 正方形鈕（依 mockup；位置/邊長由 HQ_LAYOUT 控制）
    do
        local start_text = "START"
        local tw, th = gfx.getTextSize(start_text)
        local box_w = HQ_LAYOUT.start_size
        local box_h = HQ_LAYOUT.start_size
        local box_x = HQ_LAYOUT.start_x
        local box_y = HQ_LAYOUT.start_y
        local text_x = box_x + math.floor((box_w - tw) / 2)  -- 文字置中
        local text_y = box_y + math.floor((box_h - th) / 2)

        -- [[ 零件限制 ]] 缺必要零件：START 上方顯示 NEED 提示，按下會被擋
        local missing = getMissingRequiredParts()
        if missing then
            local need_text = "NEED: " .. table.concat(missing, ",")
            local ntw = gfx.getTextSize(need_text)
            gfx.setColor(gfx.kColorBlack)
            gfx.drawText(need_text, box_x + box_w - ntw, box_y - 14)
        end

        -- [[ G2 ]] 方框由底圖提供：選中＝整格反白（黑底白字），未選中＝只畫黑字
        if cursor_on_start then
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRect(box_x, box_y, box_w, box_h)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
            gfx.drawText(start_text, text_x, text_y)
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        else
            gfx.setColor(gfx.kColorBlack)
            gfx.drawText(start_text, text_x, text_y)
        end
    end

    -- [[ G2 ]] 操作提示列已移除（依使用者要求）

    -- 8. 繪製控制介面 UI（下半部）
    -- 繪製 3x2 控制格子
    local eq = _G.GameState and _G.GameState.mech_stats and _G.GameState.mech_stats.equipped_parts or {}
    
    -- 找出選中格子對應的零件ID（用於高亮所有佔用格子）
    local selected_part_id_for_highlight = nil
    local preview_part_data = nil
    if selected_category and selected_part_index and not cursor_on_start then
        local parts_list = _G.GameState.parts_by_category[selected_category]
        local part_id = parts_list and parts_list[selected_part_index]
        selected_part_id_for_highlight = part_id
        preview_part_data = _G.PartsData and _G.PartsData[part_id]
    end
    
    for r = 1, UI_GRID_ROWS do
        for c = 1, UI_GRID_COLS do
            local cx = UI_START_X + (c - 1) * UI_CELL_SIZE
            local cy = UI_START_Y + (UI_GRID_ROWS - r) * UI_CELL_SIZE
            
            -- 查找是否有零件在這個列和對應的排
            -- r=2 對應組裝格 row=2（上排），r=1 對應組裝格 row=1（下排）
            local found_part = nil
            for _, item in ipairs(eq) do
                local slot_w = item.w or 1
                -- 檢查此列是否在零件範圍內，且零件的 row 與控制介面的 r 對應
                if item.row == r and c >= item.col and c < item.col + slot_w then
                    found_part = item
                    break
                end
            end
            
            if found_part then
                -- 只在起始格繪製介面圖
                if c == found_part.col then
                    if mech_controller then
                        mech_controller:drawPartUI(found_part.id, cx, cy, UI_CELL_SIZE)
                    end
                end
                -- 零件佔用的其他格子保持空白（不繪製任何東西）
            else
                -- 沒有零件，繪製空格邊框（不使用 empty.png）
                gfx.setColor(gfx.kColorBlack)
                gfx.setLineWidth(1)
                gfx.drawRect(cx, cy, UI_CELL_SIZE, UI_CELL_SIZE)
            end
        end
    end
    
    -- 繪製選中零件的粗外框（根據零件的 row 顯示在對應的控制介面排）
    if selected_part_id_for_highlight then
        for _, item in ipairs(eq) do
            if item.id == selected_part_id_for_highlight then
                local slot_w = item.w or 1
                local fx = UI_START_X + (item.col - 1) * UI_CELL_SIZE
                -- 根據零件的 row 決定 y 座標：row=2 在上方，row=1 在下方
                local fy = UI_START_Y + (UI_GRID_ROWS - item.row) * UI_CELL_SIZE
                local fw = slot_w * UI_CELL_SIZE
                local fh = UI_CELL_SIZE
                
                -- 繪製白色外框（確保在任何背景上都可見）
                gfx.setColor(gfx.kColorWhite)
                gfx.setLineWidth(5)
                gfx.drawRect(fx, fy, fw, fh)
                
                -- 繪製黑色內框
                gfx.setColor(gfx.kColorBlack)
                gfx.setLineWidth(3)
                gfx.drawRect(fx, fy, fw, fh)
                gfx.setLineWidth(1)
                break
            end
        end
    end
    
    -- 顯示當前選中的零件資訊
--    local info_x = UI_START_X + UI_GRID_COLS * UI_CELL_SIZE + 10
--    if selected_category and selected_part_index and not cursor_on_start then
--        local parts_list = _G.GameState.parts_by_category[selected_category]
--        local part_id = parts_list and parts_list[selected_part_index]
--        if part_id then
--            gfx.setColor(gfx.kColorBlack)
--            gfx.drawText("Selected: " .. part_id, info_x, UI_START_Y)
--        end
--    else
--        gfx.setColor(gfx.kColorBlack)
--       gfx.drawText("Select category", info_x, UI_START_Y)
--    end
    
    -- 9. [[ G2 ]] 頂部任務資訊（框線由底圖提供，這裡只畫文字）
    local mission_id = (_G and _G.GameState and _G.GameState.current_mission) or "M001"
    if MissionData and MissionData[mission_id] then
        local mission = MissionData[mission_id]
        local mbox = HQ_LAYOUT.mission
        gfx.setColor(gfx.kColorBlack)
        gfx.drawText(mission.name or "MISSION", mbox.x + 6, mbox.y + 4)
        if mission.objective then
            gfx.drawText(mission.objective.description or "", mbox.x + 6, mbox.y + 24)
        end
        -- [[ 零件限制 ]] 任務需求零件顯示在面板右側（有宣告 required_parts 才顯示）
        if mission.required_parts and #mission.required_parts > 0 then
            local req_text = "REQ: " .. table.concat(mission.required_parts, ",")
            local rtw = gfx.getTextSize(req_text)
            gfx.drawText(req_text, mbox.x + mbox.w - rtw - 6, mbox.y + 4)
        end
    end
end

return StateHQ