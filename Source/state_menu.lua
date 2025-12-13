-- state_menu.lua (最終穩定版 - 使用 Charlie Ninja 字體)

import "CoreLibs/graphics"

local gfx = playdate.graphics

-- 載入 Charlie Ninja 字體，如果失敗則使用系統字體
local custom_font = gfx.font.new('fonts/Charlie Ninja')
local font = custom_font or gfx.font.systemFont

StateMenu = {}

local menu_options = {"NEW GAME", "CONTINUE", "CREDITS"}
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
        -- 播放游標移動音效
        if _G.SoundManager and _G.SoundManager.playCursorMove then
            _G.SoundManager.playCursorMove()
        end
    elseif playdate.buttonJustPressed(playdate.kButtonDown) then
        selected_index = selected_index + 1
        if selected_index > #menu_options then
            selected_index = 1
        end
        -- 播放游標移動音效
        if _G.SoundManager and _G.SoundManager.playCursorMove then
            _G.SoundManager.playCursorMove()
        end
    end
    
    -- 處理 A 鍵確認
    if playdate.buttonJustPressed(playdate.kButtonA) then
        -- 播放選擇確認音效
        if _G.SoundManager and _G.SoundManager.playSelect then
            _G.SoundManager.playSelect()
        end
        
        local selection = menu_options[selected_index]
        if selection == "NEW GAME" then
            -- NEW GAME: 進入存檔選擇畫面（模式為創建新遊戲）
            setState(_G.StateSaveSelect, "new_game")
        elseif selection == "CONTINUE" then
            -- CONTINUE: 進入存檔選擇畫面（模式為繼續遊戲）
            setState(_G.StateSaveSelect, "continue")
        elseif selection == "CREDITS" then
            print("Action: Show Credits (Not implemented)")
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