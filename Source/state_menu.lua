-- state_menu.lua (最終穩定版 - 使用 Charlie Ninja 字體)

import "CoreLibs/graphics"

local gfx = playdate.graphics

-- 載入 Charlie Ninja 字體，如果失敗則使用系統字體
local custom_font = gfx.font.new('fonts/Charlie Ninja')
local font = custom_font or gfx.font.systemFont

StateMenu = {}

local menu_options = {"START GAME", "CREDITS"}
local selected_index = 1
local menu_x = 150
local menu_y_start = 150
local line_height = 20

function StateMenu.setup()
    -- 設置字體
    gfx.setFont(font)
    selected_index = 1
    print("LOG: StateMenu initialized.")
    -- 播放標題/一般介面 BGM（循環）
    if _G.SoundManager and _G.SoundManager.playTitleBGM then
        _G.SoundManager.playTitleBGM()
    end
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
        if selection == "START GAME" then
            -- START GAME: 進入存檔選擇畫面
            if _G.StateSaveSelect then
                setState(_G.StateSaveSelect)
            else
                print("ERROR: StateSaveSelect not found")
            end
        elseif selection == "CREDITS" then
            if _G.StateCredits then
                setState(_G.StateCredits)
            else
                print("Action: Show Credits (StateCredits not found)")
            end
        end
    end
end

function StateMenu.draw()
    
    gfx.clear(gfx.kColorWhite) 
    
    gfx.setColor(gfx.kColorBlack)
    -- 確保在 draw 週期中字體仍被設定 (雖然 setup 已經設過，但保留是好習慣)
    gfx.setFont(font)
    

    
    -- 繪製選單選項
    for i, option in ipairs(menu_options) do
        local y = menu_y_start + (i - 1) * line_height
            local text_width, text_height = gfx.getTextSize(option)
            local option_x = (400 - text_width) / 2  -- 水平置中
            if i == selected_index then
                -- 選中時使用黑底白字突出顯示（與任務選擇風格一致）
                local padding_x = 6
                local padding_y = 2
                gfx.setColor(gfx.kColorBlack)
                gfx.fillRect(option_x - padding_x, y - padding_y, text_width + padding_x * 2, text_height + padding_y * 2)
                gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
                gfx.drawText(option, option_x, y)
                gfx.setImageDrawMode(gfx.kDrawModeCopy)
                gfx.setColor(gfx.kColorBlack)
            else
                gfx.drawText(option, option_x, y)
        end
    end
end

return StateMenu