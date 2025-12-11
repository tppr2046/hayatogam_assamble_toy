-- state_result.lua - 關卡結果畫面

import "CoreLibs/graphics"

local gfx = playdate.graphics
local font = gfx.font.new('fonts/Charlie Ninja') or gfx.font.systemFont

StateResult = {}

local result_success = false
local result_message = ""

function StateResult.setup(success, message)
    gfx.setFont(font)
    result_success = success or false
    result_message = message or ""
end

function StateResult.update()
    if playdate.buttonJustPressed(playdate.kButtonA) then
        -- 返回 HQ
        setState(_G.StateHQ)
    end
end

function StateResult.draw()
    gfx.clear(gfx.kColorWhite)
    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(font)
    
    -- 顯示結果
    local result_text = result_success and "MISSION SUCCESS" or "MISSION FAILED"
    local result_width = gfx.getTextSize(result_text)
    gfx.drawText(result_text, (400 - result_width) / 2, 80)
    
    -- 顯示訊息
    if result_message and result_message ~= "" then
        local msg_width = gfx.getTextSize(result_message)
        gfx.drawText(result_message, (400 - msg_width) / 2, 110)
    end
    
    -- 顯示 OK 選項
    local ok_text = "> OK <"
    local ok_width = gfx.getTextSize(ok_text)
    gfx.drawText(ok_text, (400 - ok_width) / 2, 180)
    
    -- 提示文字
    gfx.drawText("Press A to continue", 10, 220)
end

return StateResult
