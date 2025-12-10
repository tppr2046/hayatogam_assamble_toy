-- state_mission.lua (整合 EntityController, 戰鬥與 HP 邏輯)

import "CoreLibs/graphics"
import "module_scene_data" 
import "module_entities" 
-- 載入任務資料，用於獲取敵人列表
local MissionData = import "mission_data" 
local StateHQ = _G.StateHQ -- 假設 StateHQ 已在 main.lua 中設定為全域

local gfx = playdate.graphics

-- 載入 Charlie Ninja 字體，如果失敗則使用系統字體
local custom_font = gfx.font.new('fonts/Charlie Ninja')
local font = custom_font or gfx.font.systemFont

StateMission = {}

-- ==========================================
-- 常數與設定
-- ==========================================
local SCREEN_WIDTH = 400
local SCREEN_HEIGHT = 240
local GRAVITY = 0.5
local JUMP_VELOCITY = -10.0
local MOVE_SPEED = 2.0
local MECH_WIDTH = 24
local MECH_HEIGHT = 32

-- 可變的繪製寬高（預設為常數），若合成成功會改成合成尺寸
local mech_draw_w = MECH_WIDTH
local mech_draw_h = MECH_HEIGHT

-- 任務狀態的局部變數
local is_paused = false
local timer = 0
local current_scene = nil 
local mech_x, mech_y, mech_vy = 0, 0, 0
local is_on_ground = true
local camera_x = 0       
local last_input = "None" 
local mech_y_old = 0    -- 用於垂直碰撞檢查
local Assets = {} 
local entity_controller = nil 

local current_hp = 0 -- 追蹤機甲當前 HP
local max_hp = 1     -- 機甲最大 HP (在 setup 中獲取)


-- ==========================================
-- 狀態機接口
-- ==========================================

function StateMission.setup()
    -- 初始化字體與狀態
    gfx.setFont(font)
    is_paused = false
    timer = 0

    -- 嘗試使用先前快取的 mech image
    if _G and _G.GameState and _G.GameState.mech_image then
        Assets.mech_image = _G.GameState.mech_image
        mech_draw_w = _G.GameState.mech_draw_w or mech_draw_w
        mech_draw_h = _G.GameState.mech_draw_h or mech_draw_h
    else
        -- 嘗試從 mech_grid 與已裝備零件合成一張圖
        local mech_grid = _G and _G.GameState and _G.GameState.mech_grid
        local eq = _G and _G.GameState and _G.GameState.mech_stats and _G.GameState.mech_stats.equipped_parts
        if mech_grid and eq and _G.PartsData and (#eq > 0) then
            -- Compute actual bounding box by checking all part images
            local min_x, min_y, max_x, max_y = 0, 0, mech_grid.cols * mech_grid.cell_size, mech_grid.rows * mech_grid.cell_size
            for _, item in ipairs(eq) do
                local pid = item.id
                local pdata = (_G.PartsData and _G.PartsData[pid]) or nil
                if pdata and pdata._img then
                    local px = (item.col - 1) * mech_grid.cell_size
                    local py_top = (mech_grid.rows - item.row) * mech_grid.cell_size
                    local ok, iw, ih = pcall(function() return pdata._img:getSize() end)
                    if ok and iw and ih then
                        local draw_y = py_top + (mech_grid.cell_size - ih)
                        -- Expand bounding box to include full image
                        if px < min_x then min_x = px end
                        if draw_y < min_y then min_y = draw_y end
                        if px + iw > max_x then max_x = px + iw end
                        if draw_y + ih > max_y then max_y = draw_y + ih end
                    end
                end
            end
            local comp_w = math.max(1, max_x - min_x)
            local comp_h = math.max(1, max_y - min_y)
            local okcomp, comp = pcall(function() return gfx.image.new(comp_w, comp_h) end)
            if okcomp and comp then
                gfx.pushContext(comp)
                gfx.clear(gfx.kColorClear)
                -- draw each equipped part into comp; adjust coordinates by min offsets
                for _, item in ipairs(eq) do
                    local pid = item.id
                    local pdata = (_G.PartsData and _G.PartsData[pid]) or nil
                    if pdata and pdata._img then
                        local px = (item.col - 1) * mech_grid.cell_size - min_x
                        local py_top = (mech_grid.rows - item.row) * mech_grid.cell_size - min_y
                        local ok, iw, ih = pcall(function() return pdata._img:getSize() end)
                        local draw_x = px
                        local draw_y = py_top
                        if ok and iw and ih then
                            draw_y = py_top + (mech_grid.cell_size - ih)
                        end
                        pcall(function() pdata._img:draw(draw_x, draw_y) end)
                    end
                end
                gfx.popContext()
                _G.GameState.mech_image = comp
                _G.GameState.mech_draw_w = comp_w
                _G.GameState.mech_draw_h = comp_h
                Assets.mech_image = comp
                mech_draw_w = comp_w
                mech_draw_h = comp_h
            end
        end
    end

    -- 初始化機甲位置：如果場景有 ground 資訊則放在地面，否則靠畫面底部
    -- determine current scene: prefer selected mission in GameState, otherwise first mission in MissionData
    local mission_id = (_G and _G.GameState and _G.GameState.current_mission) or nil
    if not mission_id then
        for k, v in pairs(MissionData) do
            mission_id = k
            break
        end
    end
    if mission_id and MissionData[mission_id] and MissionData[mission_id].scene then
        current_scene = MissionData[mission_id].scene
    end

    -- Initialize entity controller for the current scene (so ground/obstacles/enemies draw)
    if current_scene and EntityController then
        local enemies = (current_scene.enemies) or {}
        entity_controller = EntityController:init(current_scene, enemies, MOVE_SPEED)
    else
        entity_controller = nil
    end

    if current_scene and current_scene.ground_y then
        mech_x = 50
        mech_y = current_scene.ground_y - mech_draw_h
    else
        mech_x = 50
        mech_y = SCREEN_HEIGHT - mech_draw_h - 10
    end
    mech_vy = 0
    is_on_ground = true
    mech_y_old = mech_y
    camera_x = 0

    -- 初始化 HP (從全域 GameState 獲取組裝後的 HP)
    local stats = (_G and _G.GameState and _G.GameState.mech_stats) or {}
    max_hp = stats.total_hp or 100
    current_hp = max_hp
end

function StateMission.update()
    if is_paused then return end

    -- 0. 記錄舊的 Y 座標 (用於 EntityController 碰撞檢查)
    mech_y_old = mech_y

    -- 1. 處理輸入 (移動與跳躍)
    local dx = 0
    
    if playdate.buttonIsPressed(playdate.kButtonLeft) then
        dx = dx - MOVE_SPEED
        last_input = "Left"
    end
    
    if playdate.buttonIsPressed(playdate.kButtonRight) then
        dx = dx + MOVE_SPEED
        last_input = "Right"
    end
    
    if is_on_ground and playdate.buttonJustPressed(playdate.kButtonA) then
        mech_vy = JUMP_VELOCITY -- 跳躍
        is_on_ground = false
    end
    
    -- 2. 應用物理和碰撞檢測
    
    -- 應用重力
    mech_vy = mech_vy + GRAVITY
    
    -- 計算新的位置
    local new_x = mech_x + dx
    local new_y = mech_y + mech_vy
    
    local ground_level
    if current_scene and current_scene.ground_y then
        ground_level = current_scene.ground_y - mech_draw_h
    else
        ground_level = SCREEN_HEIGHT - mech_draw_h - 10
    end
    
    if entity_controller then
        -- 使用 EntityController 進行精確碰撞
        -- 注意：EntityController.checkCollision(self, target_x, target_y, mech_vy_current, mech_y_old, mech_width, mech_height)
        local horizontal_block, vertical_stop = entity_controller:checkCollision(new_x, new_y, mech_vy, mech_y_old, mech_draw_w or MECH_WIDTH, mech_draw_h or MECH_HEIGHT)

        -- 如果沒有水平阻擋，採用計算後的新 X；否則保留原地（阻擋水平移動）
        if not horizontal_block then
            mech_x = new_x
        else
            -- 保持原本的 mech_x（或你可以在此加入推回量）
            -- mech_x = mech_x -- 明確保留
        end

        if vertical_stop then
            mech_y = vertical_stop
            mech_vy = 0
            is_on_ground = true
        elseif new_y >= ground_level then
            -- 撞到地圖的「地面」
            mech_y = ground_level
            mech_vy = 0
            is_on_ground = true
        else
            mech_y = new_y
            is_on_ground = false
        end
    else
        -- 備用/簡單地面碰撞邏輯
        -- apply horizontal movement (no entity controller)
        mech_x = new_x
        if new_y >= ground_level then
            mech_y = ground_level
            mech_vy = 0
            is_on_ground = true
        else
            mech_y = new_y
            is_on_ground = false
        end
    end
    
    -- 3. 相機邏輯
    local target_camera_x = mech_x - 150 
    if target_camera_x < 0 then target_camera_x = 0 end
    local max_camera_x = ((current_scene and current_scene.width) or 400) - SCREEN_WIDTH
    if target_camera_x > max_camera_x then target_camera_x = max_camera_x end
    camera_x = target_camera_x

    -- 4. 更新實體控制器 (敵人、砲彈)，並套用造成的傷害
    if entity_controller then
        local dt = 1 / 30 -- approximate delta time per frame
        local damage = entity_controller:updateAll(dt, mech_x, mech_y, mech_draw_w or MECH_WIDTH, mech_draw_h or MECH_HEIGHT, (_G.GameState and _G.GameState.mech_stats) or {})
        if damage and damage > 0 then
            current_hp = current_hp - damage
        end
    end
    
    -- 5. 更新計時器
    if timer > 0 then
        timer = timer - 1 
    end
    
    -- 6. 遊戲結束/勝利條件檢查 (簡化：HP <= 0 則遊戲結束)
    if current_hp <= 0 then
        print("GAME OVER: Mech destroyed!")
        setState(StateHQ) -- 返回 HQ
    end

    -- 7. 返回 HQ
    if playdate.buttonJustPressed(playdate.kButtonB) then
        setState(StateHQ) 
    end
end

function StateMission.draw()
    gfx.clear(gfx.kColorWhite) 
    
    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(font)
    
    local mech_img = Assets.mech_image
    
    -- 1. 繪製實體 (地面、障礙物等)
    if entity_controller then
        entity_controller:draw(camera_x) 
    end

    -- 2. 繪製機甲（使用預先組合的 mech image，確保碰撞框與視覺一致）
    local draw_x = mech_x - camera_x
    local draw_y = mech_y
    local draw_w = mech_draw_w or MECH_WIDTH
    local draw_h = mech_draw_h or MECH_HEIGHT
    
    -- 繪製碰撞框（調試用）
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(draw_x, draw_y, draw_w, draw_h)
    
    -- 繪製組合後的機甲圖像
    if mech_img then
        pcall(function() mech_img:draw(draw_x, draw_y) end)
    else
        -- 備用: 繪製機甲方塊
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRect(draw_x, draw_y, draw_w, draw_h)
    end
    
    -- 3. 繪製 HUD (HP 條)
    local hp_bar_x = 10
    local hp_bar_y = 10
    local hp_bar_width = 100
    local hp_bar_height = 10
    local hp_percent = current_hp / max_hp
    
    -- 繪製 HP 文字
    gfx.drawText("HP: " .. math.floor(current_hp) .. "/" .. max_hp, hp_bar_x, hp_bar_y - 15)
    
    -- 繪製外框
    gfx.drawRect(hp_bar_x, hp_bar_y, hp_bar_width, hp_bar_height)
    
    -- 繪製血條填充 (Playdate 只有黑白，用黑色表示填充)
    if current_hp > 0 then
        gfx.setColor(gfx.kColorBlack) 
        -- 計算填充寬度
        gfx.fillRect(hp_bar_x + 1, hp_bar_y + 1, (hp_bar_width - 2) * hp_percent, hp_bar_height - 2)
    end

    -- 4. 繪製調試信息
    gfx.drawText("Mech X: " .. math.floor(mech_x), 10, SCREEN_HEIGHT - 30)
    gfx.drawText("Input: " .. last_input, 10, SCREEN_HEIGHT - 15)
end

return StateMission