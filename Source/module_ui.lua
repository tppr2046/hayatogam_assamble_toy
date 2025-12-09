-- module_ui.lua (Version 0.2 - Global Table Pattern)
-- 包含所有通用 UI 渲染和組件輔助函式

import "CoreLibs/graphics" -- 確保 CoreLibs/graphics 存在
local gfx = playdate.graphics

-- **重大修正：定義全域表格 ModuleUI**
ModuleUI = {} 

-- ==========================================
-- 操作介面常數 (下半部網格)
-- ==========================================

-- 螢幕寬度 400
-- 螢幕高度 240
local UI_AREA_HEIGHT = 80  -- 假定 UI 區域佔用底部 80 像素
local UI_AREA_Y_START = 240 - UI_AREA_HEIGHT -- Y 座標起始點 (160)

local GRID_COLS = 3 -- 橫向 3 格
local GRID_ROWS = 2 -- 縱向 2 格

-- 單個格子的大小
local GRID_WIDTH = 400 / GRID_COLS  -- 133.33 像素
local GRID_HEIGHT = UI_AREA_HEIGHT / GRID_ROWS -- 40 像素

-- ==========================================
-- 函式：通用介面渲染
-- (將函式綁定到 ModuleUI)
-- ==========================================

--- 繪製整個操作介面的網格背景
function ModuleUI.drawUIBackground()
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(0, UI_AREA_Y_START, 400, UI_AREA_HEIGHT)
    gfx.setColor(gfx.kColorBlack)
    
    -- 繪製邊框
    gfx.drawRect(0, UI_AREA_Y_START, 400, UI_AREA_HEIGHT)
    
    -- 繪製網格線
    for c = 1, GRID_COLS - 1 do
        -- 垂直線
        local x = c * GRID_WIDTH
        gfx.drawLine(x, UI_AREA_Y_START, x, 240)
    end
    
    for r = 1, GRID_ROWS - 1 do
        -- 水平線
        local y = UI_AREA_Y_START + r * GRID_HEIGHT
        gfx.drawLine(0, y, 400, y)
    end
end

--- 根據零件佔用的格子，繪製該零件的操作 UI 區塊
function ModuleUI.drawPartUI(part_data, is_selected)
    
    -- 根據佔用的格子數計算實際像素大小
    local slot_width_count = part_data.slot_x or 1
    local slot_height_count = part_data.slot_y or 1
    
    -- 這裡暫時假設零件從 (1, 1) 開始佔用，直到 HQ 邏輯完善為止
    local start_col = 1
    local start_row = 1 
    
    local start_x = (start_col - 1) * GRID_WIDTH
    local start_y = UI_AREA_Y_START + (start_row - 1) * GRID_HEIGHT
    
    local width = slot_width_count * GRID_WIDTH
    local height = slot_height_count * GRID_HEIGHT
    
    -- 繪製零件外框
    gfx.drawRect(start_x, start_y, width, height)
    
    if is_selected then
        -- 突出顯示 (例如：虛線框)
        gfx.drawText("SELECTED", start_x + 5, start_y + 5)
    end
end

-- 檔案末尾沒有 return