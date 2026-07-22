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
-- [[ G2 版型 ]] 組裝介面版型（依使用者 mockup：帶標題列的框線盒）。
-- 要移動任何區塊，只改這張表的座標即可，重新編譯就生效。
--   單位：像素，畫面 400x240。box = {x, y, w, h}。
-- ============================================================
local HQ_LAYOUT = {
    mission = { x = 4,   y = 2,   w = 392, h = 40 },   -- 頂部：任務面板（標題列＋目標）
    data    = { x = 6,   y = 86,  w = 104, h = 52 },   -- 左上：DATA（HP / WEIGHT）
    panel   = { x = 6,   y = 150, w = 104, h = 78 },   -- 左下：PANEL（操作面板預覽）
    mech_x  = 216,   -- 機體組裝格左上 x（畫面中右）
    mech_y  = 92,    -- 機體組裝格左上 y
    menu_x  = 176,   -- 底部：零件選單 / 零件清單 x
    menu_y  = 168,   -- 底部：零件選單 / 零件清單 y
    start_y = 210,   -- START 鈕 y（底部；x 依文字寬右對齊）
}

local GRID_START_X = HQ_LAYOUT.mech_x
local GRID_START_Y = HQ_LAYOUT.mech_y

-- UI 控制介面相關（操作面板繪於 PANEL 盒內）
local UI_GRID_COLS = 3
local UI_GRID_ROWS = 2
local UI_CELL_SIZE = 32
local UI_START_X = HQ_LAYOUT.panel.x + 4
local UI_START_Y = HQ_LAYOUT.panel.y + 14

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

-- [[ G2 ]] 繪製「帶黑底標題列的白底框線盒」（DATA / PANEL / MISSION 共用）
local function drawTitledBox(box, title)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(box.x, box.y, box.w, box.h)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(box.x, box.y, box.w, box.h)
    gfx.fillRect(box.x, box.y, box.w, 13)  -- 標題列
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    gfx.drawText(title, box.x + 3, box.y + 1)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

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
local is_placing_part = false

-- [[ P5 ]] 放置回饋：不可放的格子在放置模式中以 X.png 靜態標示
-- （取代舊「按下才紅閃」——且舊紅閃的 y 映射用 (row-1)，實際畫錯排）
local x_marker_img = nil  -- images/X.png，於 setup 載入
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
        if is_placing_part then
            -- 零件放置中：移動網格游標
            if playdate.buttonJustPressed(playdate.kButtonLeft) then
                cursor_col = math.max(1, cursor_col - 1)
                -- 播放游標移動音效
                if _G.SoundManager and _G.SoundManager.playCursorMove then
                    _G.SoundManager.playCursorMove()
                end
            elseif playdate.buttonJustPressed(playdate.kButtonRight) then
                cursor_col = math.min(GRID_COLS, cursor_col + 1)
                -- 播放游標移動音效
                if _G.SoundManager and _G.SoundManager.playCursorMove then
                    _G.SoundManager.playCursorMove()
                end
            elseif playdate.buttonJustPressed(playdate.kButtonUp) then
                cursor_row = math.min(GRID_ROWS, cursor_row + 1)
                -- 播放游標移動音效
                if _G.SoundManager and _G.SoundManager.playCursorMove then
                    _G.SoundManager.playCursorMove()
                end
            elseif playdate.buttonJustPressed(playdate.kButtonDown) then
                cursor_row = math.max(1, cursor_row - 1)
                -- 播放游標移動音效
                if _G.SoundManager and _G.SoundManager.playCursorMove then
                    _G.SoundManager.playCursorMove()
                end
            elseif playdate.buttonJustPressed(playdate.kButtonB) then
                -- 取消放置，返回零件清單
                is_placing_part = false
                if _G.SoundManager and _G.SoundManager.playCancel then
                    _G.SoundManager.playCancel()
                end
            elseif playdate.buttonJustPressed(playdate.kButtonA) then
                -- 嘗試放置
                if selected_category then
                    local parts_list = _G.GameState.parts_by_category[selected_category]
                    local part_id = parts_list[selected_part_index]
                    local part_data = _G.PartsData and _G.PartsData[part_id]
                    local can_fit, reason = checkIfFits(part_data, cursor_col, cursor_row)
                    
                    if can_fit then
                        local w = part_data.slot_x or 1
                        local h = part_data.slot_y or 1
                        for r = cursor_row, cursor_row + h - 1 do
                            for c = cursor_col, cursor_col + w - 1 do
                                GRID_MAP[r][c] = part_id
                            end
                        end
                        table.insert(_G.GameState.mech_stats.equipped_parts, { id = part_id, col = cursor_col, row = cursor_row, w = w, h = h })
                        if part_data.hp then
                            _G.GameState.mech_stats.total_hp = (_G.GameState.mech_stats.total_hp or 0) + part_data.hp
                        end
                        if part_data.weight then
                            _G.GameState.mech_stats.total_weight = (_G.GameState.mech_stats.total_weight or 0) + part_data.weight
                        end
                        
                        -- 自動儲存機甲配置
                        if _G.SaveManager and _G.SaveManager.saveCurrent then
                            _G.SaveManager.saveCurrent()
                            print("LOG: Mech configuration auto-saved.")
                        end
                        -- 播放選擇音效
                        if _G.SoundManager and _G.SoundManager.playSelect then
                            _G.SoundManager.playSelect()
                        end
                        
                        is_placing_part = false
                        
                        -- 檢查該分類（TOP/BOTTOM）是否已滿，如果滿了就返回分類選擇
                        local eq = _G.GameState.mech_stats.equipped_parts or {}
                        local has_top_part = false
                        local has_bottom_part = false
                        
                        for _, item in ipairs(eq) do
                            for r = item.row, item.row + (item.h or 1) - 1 do
                                if r == 2 then has_top_part = true end
                                if r == 1 then has_bottom_part = true end
                            end
                        end
                        
                        -- 如果當前分類是 TOP 且已有上半部零件，或是 BOTTOM 且已有下半部零件，則返回分類選擇
                        if (selected_category == "TOP" and has_top_part) or (selected_category == "BOTTOM" and has_bottom_part) then
                            selected_category = nil
                            selected_part_index = 1
                        else
                            -- 否則，自動選取下一個未裝備的零件
                            local parts_list = _G.GameState.parts_by_category[selected_category]
                            local parts_count = parts_list and #parts_list or 0
                            local found_next = false
                            
                            -- 從當前位置的下一個開始尋找未裝備的零件
                            for i = selected_part_index + 1, parts_count do
                                local check_part_id = parts_list[i]
                                local is_equipped = false
                                local eq = _G.GameState.mech_stats.equipped_parts or {}
                                for _, item in ipairs(eq) do
                                    if item.id == check_part_id then
                                        is_equipped = true
                                        break
                                    end
                                end
                                if not is_equipped then
                                    selected_part_index = i
                                    found_next = true
                                    break
                                end
                            end
                            
                            -- 如果後面沒有未裝備的零件，從頭開始找
                            if not found_next then
                                for i = 1, selected_part_index - 1 do
                                    local check_part_id = parts_list[i]
                                    local is_equipped = false
                                    local eq = _G.GameState.mech_stats.equipped_parts or {}
                                    for _, item in ipairs(eq) do
                                        if item.id == check_part_id then
                                            is_equipped = true
                                            break
                                        end
                                    end
                                    if not is_equipped then
                                        selected_part_index = i
                                        found_next = true
                                        break
                                    end
                                end
                            end
                            
                            -- [[ P5 ]] 如果所有零件都已裝備，游標跳到 START
                            if not found_next then
                                cursor_on_start = true
                                last_part_index = selected_part_index
                            end
                        end
                    else
                        -- [[ P5 ]] 放置失敗不再紅閃：不可放的格子已在放置模式中以 X 靜態標示
                        if _G.SoundManager and _G.SoundManager.playCancel then
                            _G.SoundManager.playCancel()
                        end
                    end
                end
            elseif playdate.buttonJustPressed(playdate.kButtonB) then
                is_placing_part = false
            end
        elseif cursor_on_start then
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
                if main_menu_index == 1 then
                    selected_category = "TOP"
                    selected_part_index = 1
                elseif main_menu_index == 2 then
                    selected_category = "BOTTOM"
                    selected_part_index = 1
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
                -- [[ P5 ]] 清單底部再往下：游標跳到 START
                if new_index > parts_count then
                    cursor_on_start = true
                    last_part_index = selected_part_index
                end
                -- 播放游標移動音效
                if _G.SoundManager and _G.SoundManager.playCursorMove then
                    _G.SoundManager.playCursorMove()
                end
            elseif playdate.buttonJustPressed(playdate.kButtonRight) then
                -- [[ P5 ]] 右鍵跳到 START（拆卸入口移至主選單 REMOVE PART）
                cursor_on_start = true
                -- 播放游標移動音效
                if _G.SoundManager and _G.SoundManager.playCursorMove then
                    _G.SoundManager.playCursorMove()
                end
            elseif playdate.buttonJustPressed(playdate.kButtonA) then
                -- 選中零件，檢查是否已安裝
                local parts_list = _G.GameState.parts_by_category[selected_category]
                local part_id = parts_list[selected_part_index]
                
                -- 檢查是否已安裝
                local is_equipped = false
                local eq = _G.GameState.mech_stats.equipped_parts or {}
                for _, item in ipairs(eq) do
                    if item.id == part_id then
                        is_equipped = true
                        break
                    end
                end
                
                -- 如果已安裝，不做任何事（無法選取）
                if is_equipped then
                    print("Part already equipped: " .. part_id)
                    return
                end
                
                local part_data = _G.PartsData and _G.PartsData[part_id]
                
                if part_data then
                    -- 找到第一個空格子
                    local empty_col, empty_row = findFirstEmptyCell(part_data)
                    cursor_col = empty_col
                    cursor_row = empty_row
                    is_placing_part = true
                    -- 播放選擇音效
                    if _G.SoundManager and _G.SoundManager.playSelect then
                        _G.SoundManager.playSelect()
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
    
    gfx.clear(gfx.kColorWhite)
    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(font) 
    -- 使用時間為基準的閃爍，避免某些情況下 tick 未更新導致不閃爍
    local blink_on = (math.floor(playdate.getCurrentTimeMilliseconds() / 250) % 2) == 0

    -- [[ G2 版型 ]] 先鋪三個框線盒（內容於後續各區段繪於盒內）
    if not is_unequip_mode then
        drawTitledBox(HQ_LAYOUT.data, "DATA")
        drawTitledBox(HQ_LAYOUT.panel, "PANEL")
    end

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
            
            if is_placing_part then
                -- 放置模式：預覽在游標位置
                preview_x = GRID_START_X + (cursor_col - 1) * GRID_CELL_SIZE
                preview_y = GRID_START_Y + (GRID_ROWS - cursor_row) * GRID_CELL_SIZE
            else
                -- 非放置模式：預覽顯示在組裝格上方（置中）
                local sw = (pdata.slot_x or 1) * GRID_CELL_SIZE
                local sh = (pdata.slot_y or 1) * GRID_CELL_SIZE
                local grid_width = GRID_COLS * GRID_CELL_SIZE
                preview_x = GRID_START_X + (grid_width - sw) / 2
                preview_y = GRID_START_Y - sh - 10  -- 組裝格上方，留40像素間距
            end
            
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
    
    -- [[ P5 ]] 放置模式：不可作為放置位置的格子以 X 靜態標示（取代舊紅閃）。
    -- 排限制 / 已佔用 / 槍口淨空全部走同一個 checkIfFits 判定，事前可見。
    if is_placing_part and selected_category and selected_part_index then
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
    
    -- 4. [[ G2 ]] 零件選單 / 零件清單（底部中央）
    local list_x = HQ_LAYOUT.menu_x
    local list_y = HQ_LAYOUT.menu_y
    local line_height = 15

    if not selected_category and not is_unequip_mode then
        -- [[ P5 ]] 主選單：TOP PARTS / BOTTOM PARTS / REMOVE PART（SHOP 原型隱藏）
        -- [[ G2 ]] 選中＝反白（黑底白字），不再用「> <」＋閃爍
        for i = 1, #MAIN_MENU do
            local selected = (i == main_menu_index and not cursor_on_start)
            drawSelectableText(MAIN_MENU[i], list_x, list_y + (i - 1) * line_height, selected)
        end
    elseif selected_category then
        -- 顯示選中分類的零件
            gfx.drawText(selected_category .. " PARTS:", list_x, list_y - 15)
            local parts_list = _G.GameState.parts_by_category[selected_category]
            for i, part_id in ipairs(parts_list) do
                -- 檢查是否已安裝
                local is_equipped = false
                local eq = _G.GameState.mech_stats.equipped_parts or {}
                for _, item in ipairs(eq) do
                    if item.id == part_id then
                        is_equipped = true
                        break
                    end
                end
                
                local text = part_id
                local selected = (i == selected_part_index and not cursor_on_start and not is_unequip_mode)
                local text_x = list_x
                local text_y = list_y + (i - 1) * line_height
                -- [[ G2 ]] 選中＝反白（黑底白字）
                drawSelectableText(text, text_x, text_y, selected)

                -- 如果已安裝，繪製刪除線（反白時用白線，否則黑線）
                if is_equipped then
                    local text_width = gfx.getTextSize(text)
                    gfx.setColor(selected and gfx.kColorWhite or gfx.kColorBlack)
                    gfx.drawLine(text_x, text_y + 7, text_x + text_width, text_y + 7)
                    gfx.setColor(gfx.kColorBlack)
                end
            end
    end
    
    -- 5. [[ G2 ]] DATA 盒內容座標（HP / WEIGHT），盒本身於畫面開頭已鋪
    local detail_x = HQ_LAYOUT.data.x + 5
    local detail_y = HQ_LAYOUT.data.y + 15
    
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
    if selected_category and selected_part_index and not cursor_on_start and not is_placing_part and not is_unequip_mode then
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

    -- 繪製置中的粗框（放置模式／拆卸模式），在零件圖上層
    if blink_on then
        -- 放置模式：在組裝格中繪製粗邊框
        if hq_mode == "EQUIP" and is_placing_part and selected_category and selected_part_index then
            local parts_list = _G.GameState.parts_by_category[selected_category]
            local part_id = parts_list and parts_list[selected_part_index]
            local pdata = _G.PartsData and _G.PartsData[part_id]
            if pdata then
                local w = pdata.slot_x or 1
                local h = pdata.slot_y or 1
                local fx = GRID_START_X + (cursor_col - 1) * GRID_CELL_SIZE
                local fy = GRID_START_Y + (GRID_ROWS - cursor_row) * GRID_CELL_SIZE - (h - 1) * GRID_CELL_SIZE
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
    
    -- 6. [[ G2 ]] 機甲狀態（DATA 盒內；標題由 drawTitledBox 畫）
    local stats = _G.GameState and _G.GameState.mech_stats or { total_hp = 0, total_weight = 0 }
    gfx.setColor(gfx.kColorBlack)
    gfx.drawText("HP: " .. stats.total_hp, detail_x, detail_y)
    gfx.drawText("WEIGHT: " .. stats.total_weight, detail_x, detail_y + 16)
    
    -- [[ P5 ]] 7. 固定右下角 START 鈕（取代 READY/BACK 選項與 READY 彈窗）
    do
        local start_text = "START"
        local tw, th = gfx.getTextSize(start_text)
        local pad_x, pad_y = 8, 4
        local box_w = tw + pad_x * 2
        local box_h = th + pad_y * 2
        local box_x = SCREEN_WIDTH - box_w - 8
        local box_y = HQ_LAYOUT.start_y  -- [[ G2 ]] 底部（版型表控制）

        -- [[ 零件限制 ]] 缺必要零件：START 上方顯示 NEED 提示，按下會被擋
        local missing = getMissingRequiredParts()
        if missing then
            local need_text = "NEED: " .. table.concat(missing, ",")
            local ntw = gfx.getTextSize(need_text)
            gfx.setColor(gfx.kColorBlack)
            gfx.drawText(need_text, SCREEN_WIDTH - ntw - 8, box_y - 16)
        end

        if cursor_on_start then
            -- [[ G2 ]] 選中：反白（黑底白字，穩定不閃爍）
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRect(box_x, box_y, box_w, box_h)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
            gfx.drawText(start_text, box_x + pad_x, box_y + pad_y)
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        else
            -- 未選中：白底黑字黑框
            gfx.setColor(gfx.kColorWhite)
            gfx.fillRect(box_x, box_y, box_w, box_h)
            gfx.setColor(gfx.kColorBlack)
            gfx.drawRect(box_x, box_y, box_w, box_h)
            gfx.drawText(start_text, box_x + pad_x, box_y + pad_y)
        end
    end

    -- [[ P5 ]] 每層操作提示列（遊戲區底部一行，明示下一步）
    do
        local hint
        if is_unequip_mode then
            hint = "A:REMOVE  B:BACK"
        elseif is_placing_part then
            hint = "A:PLACE  B:CANCEL"
        elseif cursor_on_start then
            hint = "A:START MISSION  <(B):BACK"
        elseif selected_category then
            hint = "A:PICK  B:BACK  >:START"
        else
            hint = "A:OK  B:MISSION LIST  >:START"
        end
        gfx.drawText(hint, 5, GAME_HEIGHT - 16)
    end

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
    
    -- 9. [[ G2 ]] 頂部任務面板（標題列＝任務名，內文＝目標）
    local mission_id = (_G and _G.GameState and _G.GameState.current_mission) or "M001"
    if MissionData and MissionData[mission_id] then
        local mission = MissionData[mission_id]
        local mbox = HQ_LAYOUT.mission
        drawTitledBox(mbox, mission.name or "MISSION")
        gfx.setColor(gfx.kColorBlack)
        if mission.objective then
            gfx.drawText(mission.objective.description or "", mbox.x + 5, mbox.y + 18)
        end
        -- [[ 零件限制 ]] 任務需求零件顯示在面板右側（有宣告 required_parts 才顯示）
        if mission.required_parts and #mission.required_parts > 0 then
            local req_text = "REQ: " .. table.concat(mission.required_parts, ",")
            local rtw = gfx.getTextSize(req_text)
            gfx.drawText(req_text, mbox.x + mbox.w - rtw - 6, mbox.y + 18)
        end
    end
end

return StateHQ