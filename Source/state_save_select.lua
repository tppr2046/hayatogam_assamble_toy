-- state_save_select.lua - 選擇紀錄檔畫面

import "CoreLibs/graphics"

local gfx = playdate.graphics
local font = gfx.font.new('fonts/Charlie Ninja') or gfx.font.systemFont

StateSaveSelect = {}

local SAVE_SLOTS = 3  -- 三個存檔槽
local selected_slot = 1

function StateSaveSelect.setup()
    gfx.setFont(font)
    selected_slot = 1
end

function StateSaveSelect.update()
    -- 上下選擇存檔槽
    if playdate.buttonJustPressed(playdate.kButtonUp) then
        selected_slot = math.max(1, selected_slot - 1)
    elseif playdate.buttonJustPressed(playdate.kButtonDown) then
        selected_slot = math.min(SAVE_SLOTS, selected_slot + 1)
    elseif playdate.buttonJustPressed(playdate.kButtonA) then
        -- 選擇存檔槽，進入任務選擇畫面
        _G.GameState = _G.GameState or {}
        _G.GameState.current_save_slot = selected_slot
        setState(_G.StateMissionSelect)
    elseif playdate.buttonJustPressed(playdate.kButtonB) then
        -- 返回主選單（如果有的話）
        if _G.StateMenu then
            setState(_G.StateMenu)
        end
    end
end

function StateSaveSelect.draw()
    gfx.clear(gfx.kColorWhite)
    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(font)
    
    -- 標題
    local title = "SELECT SAVE FILE"
    local title_width = gfx.getTextSize(title)
    gfx.drawText(title, (400 - title_width) / 2, 30)
    
    -- 繪製存檔槽
    for i = 1, SAVE_SLOTS do
        local y = 80 + (i - 1) * 40
        local text = "SAVE " .. i
        
        -- 這裡以後可以顯示存檔資訊（例如遊戲進度）
        -- 暫時只顯示 "Empty" 或 "New Game"
        local info = "Empty"
        
        if i == selected_slot then
            text = "> " .. text .. " <"
        end
        
        gfx.drawText(text, 100, y)
        gfx.drawText(info, 200, y)
    end
    
    -- 提示文字
    gfx.drawText("A: Select  B: Back", 10, 220)
end

return StateSaveSelect
