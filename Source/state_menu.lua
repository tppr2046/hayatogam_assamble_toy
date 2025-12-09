-- state_menu.lua (最終穩定版 - 使用 Charlie Ninja 字體)

import "CoreLibs/graphics"

local gfx = playdate.graphics

-- 載入 Charlie Ninja 字體，如果失敗則使用系統字體
local custom_font = gfx.font.new('fonts/Charlie Ninja')
local font = custom_font or gfx.font.systemFont

StateMenu = {}

local menu_options = {"START ASSEMBLY", "OPTIONS", "EXIT"}
local selected_index = 1
local menu_x = 100
local menu_y_start = 100
local line_height = 20

function StateMenu.setup()
    -- 設置字體
    gfx.setFont(font)
    selected_index = 1
    print("LOG: StateMenu initialized.")
end

function StateMenu.update()
    
    -- 處理方向鍵上下移動選單
    if playdate.buttonJustPressed(playdate.kButtonUp) then
        selected_index = selected_index - 1
        if selected_index < 1 then
            selected_index = #menu_options
        end
    elseif playdate.buttonJustPressed(playdate.kButtonDown) then
        selected_index = selected_index + 1
        if selected_index > #menu_options then
            selected_index = 1
        end
    end
    
    -- 處理 A 鍵確認
    if playdate.buttonJustPressed(playdate.kButtonA) then
        local selection = menu_options[selected_index]
        if selection == "START ASSEMBLY" then
            -- 確保呼叫全域函式 setState
            setState(StateHQ) 
        elseif selection == "OPTIONS" then
            print("Action: Go to Options (Not implemented)")
        elseif selection == "EXIT" then
            playdate.stop() -- 結束模擬器
        end
    end
end

function StateMenu.draw()
    
    gfx.clear(gfx.kColorWhite) 
    
    gfx.setColor(gfx.kColorBlack)
    -- 確保在 draw 週期中字體仍被設定 (雖然 setup 已經設過，但保留是好習慣)
    gfx.setFont(font)

    -- 繪製標題
    gfx.drawText("MECH ASSEMBLY GAME", menu_x, 50)
    
    -- 繪製選單選項
    for i, option in ipairs(menu_options) do
        local y = menu_y_start + (i - 1) * line_height
        
        if i == selected_index then
            gfx.drawText(">" .. option .. "<", menu_x, y)
        else
            gfx.drawText(option, menu_x, y)
        end
    end
end

return StateMenu