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
    -- 設置字體
    gfx.setFont(font)
    is_paused = false
    timer = 0
    
    -- 1. 載入 Assets
    -- ❗ 假設您有 images/mech_24x32.png 圖片
    Assets.mech_image = gfx.image.new("images/mech_24x32") 
    
    -- 2. 獲取關卡數據 (假設我們總是載入 Level1)
    local scene_data = _G.SceneData.Level1
    current_scene = scene_data

    -- 3. 初始化 EntityController (處理障礙物、敵人等)，並傳入關卡內的敵人資料與玩家移動速度
    entity_controller = EntityController:init(scene_data, scene_data.enemies, MOVE_SPEED)

    -- 4. 初始化機甲位置和 HP
    local ground_level = current_scene.ground_y - MECH_HEIGHT
    mech_x, mech_y, mech_vy = 50, ground_level, 0
    is_on_ground = true
    mech_y_old = mech_y
    camera_x = 0
    
    -- 5. 初始化 HP (從全域 GameState 獲取組裝後的 HP)
    local stats = _G.GameState.mech_stats or {}
    max_hp = stats.total_hp or 100 
    current_hp = max_hp
    
    print("LOG: StateMission initialized. Max HP: " .. max_hp)
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
    
    local ground_level = current_scene.ground_y - MECH_HEIGHT
    
    if entity_controller then
        -- 使用 EntityController 進行精確碰撞
        -- 注意：EntityController.checkCollision(self, target_x, target_y, mech_vy_current, mech_y_old, mech_width, mech_height)
        local horizontal_block, vertical_stop = entity_controller:checkCollision(new_x, new_y, mech_vy, mech_y_old, MECH_WIDTH, MECH_HEIGHT)

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
    local max_camera_x = (current_scene.width or 400) - SCREEN_WIDTH
    if target_camera_x > max_camera_x then target_camera_x = max_camera_x end
    camera_x = target_camera_x

    -- 4. 更新實體控制器 (敵人、砲彈)，並套用造成的傷害
    -- 使用近似幀時間 dt（playdate 刷新率預設 30 FPS）
    local dt = 1.0 / 30.0
    if entity_controller then
        local damage = entity_controller:updateAll(dt, mech_x, mech_y, MECH_WIDTH, MECH_HEIGHT, _G.GameState.mech_stats)
        if damage and damage > 0 then
            current_hp = current_hp - damage
            print("LOG: Mech took " .. damage .. " damage from entities. Current HP: " .. current_hp)
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

    -- 2. 繪製機甲
    if mech_img then
        mech_img:draw(mech_x - camera_x, mech_y)
    else
        -- 備用: 繪製機甲方塊
        gfx.fillRect(mech_x - camera_x, mech_y, MECH_WIDTH, MECH_HEIGHT)
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