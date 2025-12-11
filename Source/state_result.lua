-- state_result.lua - 關卡結果畫面

import "CoreLibs/graphics"

local gfx = playdate.graphics
local font = gfx.font.new('fonts/Charlie Ninja') or gfx.font.systemFont

StateResult = {}

local result_success = false
local result_message = ""
local reward_part_id = nil
local reward_money = 0
local new_part_obtained = false

function StateResult.setup(success, message, mission_id)
    gfx.setFont(font)
    result_success = success or false
    result_message = message or ""
    reward_part_id = nil
    reward_money = 0
    new_part_obtained = false
    
    -- 如果任務成功，檢查任務獎勵
    if result_success and mission_id then
        local MissionData = _G.MissionData or {}
        local mission = MissionData and MissionData[mission_id]
        if mission then
            reward_money = mission.reward_money or 0
            reward_part_id = mission.reward_part_id
            
            -- 如果有零件獎勵且尚未擁有，標記為新獲得
            if reward_part_id then
                _G.GameState = _G.GameState or {}
                _G.GameState.owned_parts = _G.GameState.owned_parts or {}
                if not _G.GameState.owned_parts[reward_part_id] then
                    _G.GameState.owned_parts[reward_part_id] = true
                    new_part_obtained = true
                    print("LOG: Obtained new part:", reward_part_id)
                end
            end
        end
    end
end

function StateResult.update()
    if playdate.buttonJustPressed(playdate.kButtonA) then
        -- 返回任務選擇畫面
        setState(_G.StateMissionSelect)
    end
end

function StateResult.draw()
    gfx.clear(gfx.kColorWhite)
    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(font)
    
    -- 顯示結果
    local result_text = result_success and "MISSION SUCCESS" or "MISSION FAILED"
    local result_width = gfx.getTextSize(result_text)
    gfx.drawText(result_text, (400 - result_width) / 2, 60)
    
    -- 顯示訊息
    if result_message and result_message ~= "" then
        local msg_width = gfx.getTextSize(result_message)
        gfx.drawText(result_message, (400 - msg_width) / 2, 90)
    end
    
    -- 顯示獎勵
    if result_success then
        local y_offset = 120
        
        -- 顯示金錢獎勵
        if reward_money > 0 then
            local money_text = "REWARD: $" .. reward_money
            local money_width = gfx.getTextSize(money_text)
            gfx.drawText(money_text, (400 - money_width) / 2, y_offset)
            y_offset = y_offset + 25
        end
        
        -- 顯示零件獎勵
        if reward_part_id then
            local part_text = new_part_obtained and "NEW PART: " .. reward_part_id or "PART: " .. reward_part_id .. " (Already owned)"
            local part_width = gfx.getTextSize(part_text)
            gfx.drawText(part_text, (400 - part_width) / 2, y_offset)
            
            -- 如果是新獲得的零件，加上特效
            if new_part_obtained then
                gfx.drawText("*** NEW ***", (400 - gfx.getTextSize("*** NEW ***")) / 2, y_offset + 20)
            end
        end
    end
    
    -- 顯示 OK 選項
    local ok_text = "> OK <"
    local ok_width = gfx.getTextSize(ok_text)
    gfx.drawText(ok_text, (400 - ok_width) / 2, 180)
    
    -- 提示文字
    gfx.drawText("Press A to continue", 10, 220)
end

return StateResult
