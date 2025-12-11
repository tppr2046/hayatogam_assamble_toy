-- state_mission_select.lua
-- 任務選擇畫面：顯示所有任務列表，選擇任務進入 HQ

import "CoreLibs/graphics"
import "CoreLibs/ui"

local gfx = playdate.graphics
local MissionData = import "mission_data"

-- 狀態物件
StateMissionSelect = {}
StateMissionSelect.__index = StateMissionSelect

local mission_list = {}  -- 任務列表（排序後的 ID）
local selected_index = 1  -- 當前選擇的任務索引
local scroll_offset = 0   -- 捲動偏移量

local FONT_SMALL = nil
local FONT_LARGE = nil

function StateMissionSelect:setup()
    print("StateMissionSelect setup called")
    
    -- 載入字體
    FONT_SMALL = gfx.getFont("fonts/Exerion")
    FONT_LARGE = gfx.getFont("fonts/Charlie Ninja")
    
    -- 將 MissionData 存到全域以供其他狀態使用
    _G.MissionData = MissionData
    
    -- 建立任務列表（排序）
    mission_list = {}
    for id, _ in pairs(MissionData) do
        table.insert(mission_list, id)
    end
    table.sort(mission_list)
    
    -- 重置選擇
    selected_index = 1
    scroll_offset = 0
    
    print("StateMissionSelect setup complete. Missions: " .. #mission_list)
end

function StateMissionSelect:update()
    -- A 鍵：選擇任務，進入 HQ
    if playdate.buttonJustPressed(playdate.kButtonA) then
        if #mission_list > 0 then
            local selected_mission_id = mission_list[selected_index]
            print("Selected mission: " .. selected_mission_id)
            
            -- 設定當前任務到全域
            _G.GameState = _G.GameState or {}
            _G.GameState.current_mission = selected_mission_id
            
            -- 進入 HQ 畫面
            setState(_G.StateHQ)
        end
    end
    
    -- 上下鍵：選擇任務
    if playdate.buttonJustPressed(playdate.kButtonUp) then
        selected_index = selected_index - 1
        if selected_index < 1 then
            selected_index = #mission_list
        end
        scroll_offset = math.max(0, selected_index - 3)
    end
    
    if playdate.buttonJustPressed(playdate.kButtonDown) then
        selected_index = selected_index + 1
        if selected_index > #mission_list then
            selected_index = 1
        end
        scroll_offset = math.max(0, selected_index - 3)
    end
end

function StateMissionSelect:draw()
    gfx.clear()
    
    -- 繪製標題
    gfx.setFont(FONT_LARGE)
    gfx.drawText("MISSION SELECT", 10, 10)
    
    -- 繪製任務列表
    gfx.setFont(FONT_SMALL)
    local y = 50
    local line_height = 40
    local visible_count = 4  -- 一次顯示 4 個任務
    
    for i = 1, math.min(visible_count, #mission_list) do
        local index = scroll_offset + i
        if index > #mission_list then break end
        
        local mission_id = mission_list[index]
        local mission = MissionData[mission_id]
        
        -- 繪製選擇框
        if index == selected_index then
            gfx.fillRect(5, y - 2, 390, line_height)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        else
            gfx.drawRect(5, y - 2, 390, line_height)
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        end
        
        -- 繪製任務名稱
        gfx.drawText(mission.name or mission_id, 10, y)
        
        -- 繪製任務目標
        local objective_text = ""
        if mission.objective then
            if mission.objective.type == "ELIMINATE_ALL" then
                objective_text = "Eliminate All"
            elseif mission.objective.type == "DELIVER_STONE" then
                objective_text = "Deliver Stone"
            else
                objective_text = mission.objective.description or ""
            end
        end
        gfx.drawText(objective_text, 10, y + 16)
        
        gfx.setImageDrawMode(gfx.kDrawModeCopy)
        y = y + line_height
    end
    
    -- 繪製捲動提示
    if #mission_list > visible_count then
        gfx.drawText("^v: " .. (selected_index) .. "/" .. #mission_list, 10, 210)
    end
    
    -- 繪製控制提示
    gfx.drawText("A: SELECT", 10, 225)
end

function StateMissionSelect:cleanup()
    print("StateMissionSelect cleanup")
end

return StateMissionSelect
