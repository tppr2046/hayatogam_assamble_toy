-- state_result.lua - 關卡結果畫面

import "CoreLibs/graphics"

local gfx = playdate.graphics
local font = gfx.font.new('fonts/Charlie Ninja') or gfx.font.systemFont

StateResult = {}

local result_success = false
local result_message = ""
local reward_steel = 0
local reward_copper = 0
local reward_rubber = 0

function StateResult.setup(success, message, mission_id)
    gfx.setFont(font)
    result_success = success or false
    result_message = message or ""
    reward_steel = 0
    reward_copper = 0
    reward_rubber = 0
    
    -- 如果任務成功，檢查任務獎勵
    if result_success and mission_id then
        local MissionData = _G.MissionData or {}
        local mission = MissionData and MissionData[mission_id]
        if mission then
            reward_steel = mission.reward_steel or 0
            reward_copper = mission.reward_copper or 0
            reward_rubber = mission.reward_rubber or 0
            
            -- 添加資源到玩家
            _G.GameState = _G.GameState or {}
            _G.GameState.resources = _G.GameState.resources or {steel = 0, copper = 0, rubber = 0}
            _G.GameState.resources.steel = _G.GameState.resources.steel + reward_steel
            _G.GameState.resources.copper = _G.GameState.resources.copper + reward_copper
            _G.GameState.resources.rubber = _G.GameState.resources.rubber + reward_rubber
            
            print("LOG: Obtained resources - Steel:" .. reward_steel .. " Copper:" .. reward_copper .. " Rubber:" .. reward_rubber)
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
        
        -- 顯示資源獎勵
        if reward_steel > 0 or reward_copper > 0 or reward_rubber > 0 then
            gfx.drawText("REWARDS:", (400 - gfx.getTextSize("REWARDS:")) / 2, y_offset)
            y_offset = y_offset + 20
            
            if reward_steel > 0 then
                local text = "Steel: +" .. reward_steel
                gfx.drawText(text, (400 - gfx.getTextSize(text)) / 2, y_offset)
                y_offset = y_offset + 15
            end
            
            if reward_copper > 0 then
                local text = "Copper: +" .. reward_copper
                gfx.drawText(text, (400 - gfx.getTextSize(text)) / 2, y_offset)
                y_offset = y_offset + 15
            end
            
            if reward_rubber > 0 then
                local text = "Rubber: +" .. reward_rubber
                gfx.drawText(text, (400 - gfx.getTextSize(text)) / 2, y_offset)
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
