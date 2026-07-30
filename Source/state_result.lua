-- state_result.lua - 關卡結果畫面

import "CoreLibs/graphics"

local gfx = playdate.graphics
local font = gfx.font.new('fonts/Assemble') or gfx.font.systemFont

StateResult = {}

local result_success = false
local result_message = ""
local reward_steel = 0
local reward_copper = 0
local reward_rubber = 0
-- [[ S7 ]] 結算選項：成功＝NEXT/SELECT（有下一關時）；失敗＝RETRY/SELECT
local result_options = {}
local result_option_index = 1
local result_mission_id = nil

-- 找出下一個「已解鎖且未完成」的任務（依 id 排序）
local function findNextMission()
    local completed = (_G.GameState and _G.GameState.completed_missions) or {}
    local ids = {}
    for id, _ in pairs(_G.MissionData or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        if not completed[id] then
            local m = _G.MissionData[id]
            local pre = m and m.prerequisite
            local unlocked = (pre == 0) or (type(pre) == "string" and completed[pre])
            if unlocked then return id end
        end
    end
    return nil
end

function StateResult.setup(success, message, mission_id)
    gfx.setFont(font)
    -- 播放標題/一般介面 BGM（循環）
    if _G.SoundManager and _G.SoundManager.playTitleBGM then
        _G.SoundManager.playTitleBGM()
    end
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
            
            -- 標記任務為已完成
            _G.GameState.completed_missions = _G.GameState.completed_missions or {}
            _G.GameState.completed_missions[mission_id] = true
            
            -- 自動儲存遊戲進度
            if _G.SaveManager and _G.SaveManager.saveCurrent then
                _G.SaveManager.saveCurrent()
                print("LOG: Game progress auto-saved.")
            end
            
            print("LOG: Mission " .. mission_id .. " completed!")
            print("LOG: Obtained resources - Steel:" .. reward_steel .. " Copper:" .. reward_copper .. " Rubber:" .. reward_rubber)
        end
    end

    -- [[ S7 ]] 組出結算選項
    result_mission_id = mission_id or (_G.GameState and _G.GameState.current_mission)
    result_options = {}
    if result_success then
        local nxt = findNextMission()
        if nxt then result_options[#result_options + 1] = { label = "NEXT", mission = nxt } end
    else
        if result_mission_id then
            result_options[#result_options + 1] = { label = "RETRY", mission = result_mission_id }
        end
    end
    result_options[#result_options + 1] = { label = "MISSION SELECT" }
    result_option_index = 1
end

function StateResult.update()
    -- [[ S7 ]] 左右選擇、A 確認
    if playdate.buttonJustPressed(playdate.kButtonLeft) or playdate.buttonJustPressed(playdate.kButtonRight) then
        if #result_options > 1 then
            result_option_index = (result_option_index % #result_options) + 1
            if _G.SoundManager and _G.SoundManager.playCursorMove then _G.SoundManager.playCursorMove() end
        end
    elseif playdate.buttonJustPressed(playdate.kButtonA) then
        if _G.SoundManager and _G.SoundManager.playSelect then _G.SoundManager.playSelect() end
        local opt = result_options[result_option_index]
        if opt and opt.mission then
            _G.GameState = _G.GameState or {}
            _G.GameState.current_mission = opt.mission
            setState(_G.StateHQ)          -- 下一關/重試：先進 HQ 組裝
        else
            setState(_G.StateMissionSelect)
        end
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
    
    -- [[ S7 ]] 結算選項列（NEXT / RETRY / MISSION SELECT）：選中＝黑底白字並閃爍
    local pad_x, pad_y, gap = 12, 6, 14
    local by = 180
    local blink_on = (playdate.getCurrentTimeMilliseconds() // 300) % 2 == 0
    -- 先算總寬以置中
    local total_w, widths = 0, {}
    for i, opt in ipairs(result_options) do
        local tw = gfx.getTextSize(opt.label)
        widths[i] = tw + pad_x * 2
        total_w = total_w + widths[i] + (i > 1 and gap or 0)
    end
    local bx = (400 - total_w) // 2
    local _, th = gfx.getTextSize("A")
    local bh = th + pad_y * 2
    for i, opt in ipairs(result_options) do
        local w = widths[i]
        local selected = (i == result_option_index)
        if selected and blink_on then
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRect(bx, by, w, bh)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
            gfx.drawText(opt.label, bx + pad_x, by + pad_y)
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        else
            gfx.setColor(gfx.kColorBlack)
            gfx.drawRect(bx, by, w, bh)
            gfx.drawText(opt.label, bx + pad_x, by + pad_y)
        end
        bx = bx + w + gap
    end
    -- 多個選項時提示左右切換
    if #result_options > 1 then
        local hint = "left/right: choose   A: confirm"
        local htw = gfx.getTextSize(hint)
        gfx.drawText(hint, (400 - htw) // 2, by + bh + 6)
    end
end

return StateResult
