-- state_mission.lua (整合 EntityController, 戰鬥與 HP 邏輯)

import "CoreLibs/graphics"
import "CoreLibs/animation"
import "CoreLibs/animator"
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
local UI_HEIGHT = 64  -- 操作介面高度
local GAME_HEIGHT = SCREEN_HEIGHT - UI_HEIGHT  -- 實際遊戲畫面高度
local GRAVITY = 0.5
local JUMP_VELOCITY = -10.0
local MOVE_SPEED = 2.0
local MECH_WIDTH = 24
local MECH_HEIGHT = 32

-- 操作介面相關
local UI_GRID_COLS = 3
local UI_GRID_ROWS = 2
local UI_CELL_SIZE = 20
local UI_START_X = 10
local UI_START_Y = GAME_HEIGHT + 5

-- 機甲控制器（零件管理）
local mech_controller = nil

-- 可變的繪製寬高（預設為常數），若合成成功會改成合成尺寸
local mech_draw_w = MECH_WIDTH
local mech_draw_h = MECH_HEIGHT

-- FEET 動畫相關
local feet_imagetable = nil
local feet_current_frame = 1  -- 當前幀 (1-based)
local feet_frame_timer = 0    -- 計時器（毫秒）
local feet_frame_delay = 100  -- 每幀延遲（毫秒）

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
                        local draw_y
                        if pdata.align_image_top then
                            -- 圖片上緣對齊格子上緣（用於 FEET）
                            draw_y = py_top
                        else
                            -- 預設：圖片底部對齊格子底部
                            draw_y = py_top + (mech_grid.cell_size - ih)
                        end
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
            print(string.format("Composite image: w=%s, h=%s, min_x=%s, min_y=%s, max_x=%s, max_y=%s", tostring(comp_w), tostring(comp_h), tostring(min_x), tostring(min_y), tostring(max_x), tostring(max_y)))
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
                        local draw_y
                        if ok and iw and ih then
                            if pdata.align_image_top then
                                -- 圖片上緣對齊格子上緣（用於 FEET）
                                draw_y = py_top
                            else
                                -- 預設：圖片底部對齊格子底部
                                draw_y = py_top + (mech_grid.cell_size - ih)
                            end
                        else
                            draw_y = py_top
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

    -- 初始化 FEET 動畫（如果裝備了 FEET）
    local feet_data = _G.PartsData and _G.PartsData["FEET"]
    if feet_data and feet_data.animation_walk then
        local anim_path = feet_data.animation_walk
        local ok, imagetable = pcall(function() 
            return gfx.imagetable.new(anim_path)
        end)
        if ok and imagetable then
            local length_ok, length = pcall(function() return imagetable:getLength() end)
            if length_ok and length and length > 0 then
                feet_imagetable = imagetable
                feet_current_frame = 1
                feet_frame_timer = 0
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
        entity_controller = EntityController:init(current_scene, enemies, MOVE_SPEED, UI_HEIGHT)
    else
        entity_controller = nil
    end

    if current_scene and current_scene.ground_y then
        mech_x = 50
        -- EntityController 已經將 ground_y 上移 UI_HEIGHT，所以直接使用 entity_controller.ground_y
        local adjusted_ground_y = entity_controller and entity_controller.ground_y or (current_scene.ground_y - UI_HEIGHT)
        mech_y = adjusted_ground_y - mech_draw_h
    else
        mech_x = 50
        mech_y = GAME_HEIGHT - mech_draw_h - 10
    end
    mech_vy = 0
    is_on_ground = true
    mech_y_old = mech_y
    camera_x = 0

    -- 初始化機甲控制器
    mech_controller = MechController:init()

    -- 初始化 HP (從全域 GameState 獲取組裝後的 HP)
    local stats = (_G and _G.GameState and _G.GameState.mech_stats) or {}
    max_hp = stats.total_hp or 100
    current_hp = max_hp
end

function StateMission.update()
    if is_paused then return end

    -- 0. 記錄舊的 Y 座標 (用於 EntityController 碰撞檢查)
    mech_y_old = mech_y
    
    -- 0.1 更新 FEET 動畫
    if feet_imagetable and mech_controller then
        if mech_controller.feet_is_moving then
            -- 移動時播放動畫
            feet_frame_timer = feet_frame_timer + (1000 / 30)  -- 假設 30 FPS，每幀約 33ms
            
            if feet_frame_timer >= feet_frame_delay then
                feet_frame_timer = 0
                
                local frame_count = feet_imagetable:getLength()
                if mech_controller.feet_move_direction < 0 then
                    -- 向左：倒帶播放 (3 -> 2 -> 1 -> 3 ...)
                    feet_current_frame = feet_current_frame - 1
                    if feet_current_frame < 1 then
                        feet_current_frame = frame_count
                    end
                else
                    -- 向右：正常播放 (1 -> 2 -> 3 -> 1 ...)
                    feet_current_frame = feet_current_frame + 1
                    if feet_current_frame > frame_count then
                        feet_current_frame = 1
                    end
                end
            end
        else
            -- 停止時重置動畫
            feet_current_frame = 1
            feet_frame_timer = 0
        end
    end

    -- 1. 處理輸入 (使用 MechController)
    local dx = 0
    local mech_grid = _G.GameState.mech_grid
    
    -- 處理零件選擇和激活
    mech_controller:handleSelection(_G.GameState.mech_stats)
    
    -- 處理零件操作（獲取移動增量）
    dx = mech_controller:handlePartOperation(mech_x, mech_y, mech_grid, entity_controller)
    
    -- 2. 應用物理和碰撞檢測
    
    -- 如果 FEET 激活且有跳躍速度，使用 FEET 的跳躍物理
    if mech_controller.active_part_id == "FEET" and mech_controller.velocity_y ~= 0 then
        mech_vy = mech_controller.velocity_y
    else
        -- 否則應用一般重力
        mech_vy = mech_vy + GRAVITY
    end
    
    -- 計算新的位置
    local new_x = mech_x + dx
    local new_y = mech_y + mech_vy
    
    -- 計算機甲本體碰撞框（3×2 格）
    local mech_grid = _G.GameState.mech_grid
    local body_w = (mech_grid and mech_grid.cols or 3) * (mech_grid and mech_grid.cell_size or 16)
    local body_h = (mech_grid and mech_grid.rows or 2) * (mech_grid and mech_grid.cell_size or 16)
    
    -- 如果裝備 FEET，計算包含 FEET 的總高度
    local total_h = body_h
    local feet_extra_height = 0
    if _G.GameState.mech_stats and _G.GameState.mech_stats.equipped_parts then
        for _, item in ipairs(_G.GameState.mech_stats.equipped_parts) do
            if item.id == "FEET" then
                local feet_data = _G.PartsData and _G.PartsData["FEET"]
                if feet_data and feet_data._img then
                    local ok, iw, ih = pcall(function() return feet_data._img:getSize() end)
                    if ok and iw and ih then
                        feet_extra_height = ih - (mech_grid and mech_grid.cell_size or 16)
                        if feet_extra_height > 0 then
                            total_h = total_h + feet_extra_height
                        end
                    end
                end
                break
            end
        end
    end
    
    local ground_level
    if entity_controller then
        -- 使用 EntityController 的地面（已經上移 UI_HEIGHT）
        ground_level = entity_controller.ground_y - total_h
    else
        ground_level = GAME_HEIGHT - total_h - 10
    end
    
    if entity_controller then
        -- 使用 EntityController 進行精確碰撞（使用包含 FEET 的總高度）
        local horizontal_block, vertical_stop = entity_controller:checkCollision(new_x, new_y, mech_vy, mech_y_old, body_w, total_h)

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
            mech_controller:updateGroundState(true)  -- 通知 MechController 已著地
        elseif new_y >= ground_level then
            -- 撞到地圖的「地面」
            mech_y = ground_level
            mech_vy = 0
            is_on_ground = true
            mech_controller:updateGroundState(true)  -- 通知 MechController 已著地
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
        
        -- 計算機甲本體碰撞框 (3×2 格)
        local mech_grid = _G.GameState.mech_grid
        local body_w = (mech_grid and mech_grid.cols or 3) * (mech_grid and mech_grid.cell_size or 16)
        local body_h = (mech_grid and mech_grid.rows or 2) * (mech_grid and mech_grid.cell_size or 16)
        
        -- 更新敵人和砲彈，使用本體碰撞框檢查受擊
        local damage = entity_controller:updateAll(dt, mech_x, mech_y, body_w, body_h, (_G.GameState and _G.GameState.mech_stats) or {})
        if damage and damage > 0 then
            current_hp = current_hp - damage
            -- 觸發玩家受擊震動效果
            mech_controller:onHit()
        end
        
        -- 更新機甲零件系統（GUN 自動發射、計時器、震動效果等）
        mech_controller:updateParts(dt, mech_x, mech_y, mech_grid, entity_controller)
        
        -- 更新 CLAW 抓取邏輯
        if mech_controller.active_part_id == "CLAW" then
            -- 計算爪子末端位置
            local eq = _G.GameState.mech_stats.equipped_parts or {}
            for _, item in ipairs(eq) do
                if item.id == "CLAW" then
                    local pdata = _G.PartsData and _G.PartsData["CLAW"]
                    if pdata and pdata._img and pdata._arm_img then
                        local cell_size = mech_grid.cell_size
                        local base_x = mech_x + (item.col - 1) * cell_size
                        local base_y_top = mech_y + (mech_grid.rows - item.row) * cell_size
                        local ok, base_w, base_h = pcall(function() return pdata._img:getSize() end)
                        local arm_ok, arm_w, arm_h = pcall(function() return pdata._arm_img:getSize() end)
                        
                        if ok and base_w and base_h and arm_ok and arm_w and arm_h then
                            local base_y = base_y_top + (cell_size - base_h)
                            local pivot_x = base_x + base_w / 2
                            local pivot_y = base_y + base_h / 2
                            
                            -- 計算臂末端（爪子位置）
                            local angle_rad = math.rad(-mech_controller.claw_arm_angle)
                            local cos_a = math.cos(angle_rad)
                            local sin_a = math.sin(angle_rad)
                            local claw_tip_x = pivot_x + arm_w * cos_a
                            local claw_tip_y = pivot_y + arm_w * sin_a
                            
                            -- 如果有抓住石頭，更新石頭位置
                            mech_controller:updateGrabbedStone(claw_tip_x, claw_tip_y)
                            
                            -- 如果按下 A 鍵嘗試抓取
                            if mech_controller.try_grab then
                                mech_controller:tryGrabStone(claw_tip_x, claw_tip_y, entity_controller.stones, 20)
                                mech_controller.try_grab = false
                            end
                        end
                    end
                    break
                end
            end
        end
        
        -- 檢查武器零件碰撞 (攻擊敵人)
        -- SWORD 只在轉動時才攻擊
        local weapon_parts = {}
        if mech_controller.sword_is_attacking then
            local eq = _G.GameState.mech_stats.equipped_parts or {}
            for _, item in ipairs(eq) do
                local pdata = _G.PartsData and _G.PartsData[item.id]
                if pdata and pdata.attack and pdata.attack > 0 then
                    -- 武器只在激活時才有攻擊判定
                    if mech_controller.active_part_id == item.id then
                    -- 計算武器在世界座標的位置
                    local cell_size = mech_grid.cell_size
                    local wx = mech_x + (item.col - 1) * cell_size
                    local wy = mech_y + (mech_grid.rows - item.row) * cell_size
                    local ww = cell_size
                    local wh = cell_size
                    
                    print("    Base weapon position: x=" .. math.floor(wx) .. ", y=" .. math.floor(wy) .. ", w=" .. ww .. ", h=" .. wh)
                    
                    -- 如果是 SWORD 且已激活，根據旋轉角度計算碰撞框
                    if item.id == "SWORD" and pdata._img then
                        local ok, iw, ih = pcall(function() return pdata._img:getSize() end)
                        if ok and iw and ih then
                            -- 計算 SWORD 實際攻擊範圍：以格子中心為軸心，劍的長度為半徑
                            local center_x = wx + cell_size / 2
                            local center_y = wy + cell_size / 2
                            local sword_length = math.max(iw, ih)  -- 劍的長度
                            
                            -- 根據當前角度計算劍尖位置（0度=向右，逆時針旋轉）
                            local angle_rad = math.rad(mech_controller.sword_angle)
                            local tip_x = center_x + math.cos(angle_rad) * sword_length
                            local tip_y = center_y - math.sin(angle_rad) * sword_length
                            
                            -- 碰撞框包含從中心到劍尖的矩形區域
                            local min_x = math.min(center_x, tip_x) - 8  -- 額外增加8px寬度
                            local max_x = math.max(center_x, tip_x) + 8
                            local min_y = math.min(center_y, tip_y) - 8
                            local max_y = math.max(center_y, tip_y) + 8
                            
                            wx = min_x
                            wy = min_y
                            ww = max_x - min_x
                            wh = max_y - min_y
                        end
                    end
                    
                    table.insert(weapon_parts, {
                        x = wx,
                        y = wy,
                        w = ww,
                        h = wh,
                        attack = pdata.attack
                    })
                end
            end
        end
        
        -- 執行武器碰撞檢查
        if #weapon_parts > 0 then
            entity_controller:checkWeaponCollision(weapon_parts)
        end
        end  -- 結束 if sword_is_attacking
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
    local draw_x = mech_x - camera_x + mech_controller.hit_shake_offset  -- 添加震動偏移
    
    -- 計算 FEET 的額外高度（用於碰撞檢測）
    local feet_extra_height = 0
    local mech_grid = _G.GameState.mech_grid
    if _G.GameState.mech_stats and _G.GameState.mech_stats.equipped_parts then
        for _, item in ipairs(_G.GameState.mech_stats.equipped_parts) do
            if item.id == "FEET" then
                local feet_data = _G.PartsData and _G.PartsData["FEET"]
                if feet_data and feet_data._img then
                    local ok, iw, ih = pcall(function() return feet_data._img:getSize() end)
                    if ok and iw and ih then
                        local cell_size = mech_grid and mech_grid.cell_size or 16
                        feet_extra_height = ih - cell_size
                        if feet_extra_height < 0 then feet_extra_height = 0 end
                    end
                end
                break
            end
        end
    end
    
    -- 繪製位置直接使用 mech_y（本體位置），零件座標系統會處理對齊
    local draw_y = mech_y
    local body_draw_y = mech_y  -- 與 draw_y 相同，用於零件座標計算
    local draw_w = mech_draw_w or MECH_WIDTH
    local draw_h = mech_draw_h or MECH_HEIGHT
    
    -- 繪製碰撞框（調試用 - 包含 FEET 的完整高度）
    local body_w = (mech_grid and mech_grid.cols or 3) * (mech_grid and mech_grid.cell_size or 16)
    local body_h = (mech_grid and mech_grid.rows or 2) * (mech_grid and mech_grid.cell_size or 16)
    
    -- 計算包含 FEET 的總高度（用於碰撞檢測）
    local total_h = body_h + feet_extra_height
    
    -- 畫出碰撞框 (用於除錯) - 已關閉
    -- gfx.setColor(gfx.kColorBlack)
    -- gfx.drawRect(draw_x, body_draw_y, body_w, total_h)
    -- print(string.format("Collision box: x=%s, y=%s, w=%s, h=%s (body_h=%s + feet_extra=%s)", tostring(draw_x), tostring(body_draw_y), tostring(body_w), tostring(total_h), tostring(body_h), tostring(feet_extra_height)))
    
    -- 檢查是否需要手動繪製零件（當有特殊零件時，或有任何已裝備的零件時）
    -- 總是使用手動繪製以確保激活零件正確顯示
    local has_special_parts = false
    local eq = _G.GameState.mech_stats.equipped_parts or {}
    if #eq > 0 then
        has_special_parts = true
    end
    
    if has_special_parts then
        -- 手動繪製所有零件（因為有需要特殊處理的零件）
        -- 分兩階段：先繪製下排零件（如 FEET），再繪製上排零件，避免重疊
        local eq = _G.GameState.mech_stats.equipped_parts or {}
        
        -- 第一階段：繪製下排零件（row = 1）
        for _, item in ipairs(eq) do
            -- 有特殊激活繪製邏輯的零件：SWORD, CANON, FEET, CLAW
            local has_special_render = (item.id == "SWORD" or item.id == "CANON" or item.id == "FEET" or item.id == "CLAW")
            local should_skip = has_special_render and (item.id == mech_controller.active_part_id)
            if not should_skip and item.row == 1 then
                local pdata = _G.PartsData and _G.PartsData[item.id]
                if pdata and pdata._img then
                    local cell_size = mech_grid.cell_size
                    local px = draw_x + (item.col - 1) * cell_size
                    local py_top = body_draw_y + (mech_grid.rows - item.row) * cell_size
                    local ok, iw, ih = pcall(function() return pdata._img:getSize() end)
                    if ok and iw and ih then
                        local part_y
                        if pdata.align_image_top then
                            part_y = py_top
                        else
                            local offset_y = pdata.image_offset_y or 0
                            part_y = py_top + (cell_size - ih) + offset_y
                        end
                        
                        -- 特殊處理 FEET 動畫
                        if item.id == "FEET" and feet_imagetable and mech_controller.feet_is_moving then
                            -- 播放動畫（使用當前幀索引）
                            local frame_image = feet_imagetable:getImage(feet_current_frame)
                            if frame_image then
                                pcall(function() frame_image:draw(px, part_y) end)
                            end
                        -- 特殊處理 CLAW（繪製底座 + 臂 + 爪子）
                        elseif item.id == "CLAW" then
                            -- 繪製底座
                            pcall(function() pdata._img:draw(px, part_y) end)
                            -- 計算底座中心點
                            local pivot_x = px + iw / 2
                            local pivot_y = part_y + ih / 2
                            -- 繪製臂和爪子（使用 MechController 的角度）
                            if pdata._arm_img then
                                local arm_ok, arm_w, arm_h = pcall(function() return pdata._arm_img:getSize() end)
                                if arm_ok and arm_w and arm_h then
                                    local angle_rad = math.rad(-mech_controller.claw_arm_angle)
                                    local cos_a = math.cos(angle_rad)
                                    local sin_a = math.sin(angle_rad)
                                    local arm_center_offset_x = arm_w / 2
                                    local rotated_dx = arm_center_offset_x * cos_a
                                    local rotated_dy = arm_center_offset_x * sin_a
                                    local arm_center_x = pivot_x + rotated_dx
                                    local arm_center_y = pivot_y + rotated_dy
                                    pcall(function() pdata._arm_img:drawRotated(arm_center_x, arm_center_y, -mech_controller.claw_arm_angle) end)
                                    -- 計算臂末端位置（爪子軸心）
                                    local arm_end_rotated_dx = arm_w * cos_a
                                    local arm_end_rotated_dy = arm_w * sin_a
                                    local claw_pivot_x = pivot_x + arm_end_rotated_dx
                                    local claw_pivot_y = pivot_y + arm_end_rotated_dy
                                    -- 繪製上爪
                                    if pdata._upper_img then
                                        local total_angle = -mech_controller.claw_arm_angle - mech_controller.claw_grip_angle
                                        pcall(function() pdata._upper_img:drawRotated(claw_pivot_x, claw_pivot_y, total_angle) end)
                                    end
                                    -- 繪製下爪
                                    if pdata._lower_img then
                                        local total_angle = -mech_controller.claw_arm_angle + mech_controller.claw_grip_angle
                                        pcall(function() pdata._lower_img:drawRotated(claw_pivot_x, claw_pivot_y, total_angle) end)
                                    end
                                end
                            end
                        else
                            -- 使用靜態圖片
                            pcall(function() pdata._img:draw(px, part_y) end)
                        end
                    end
                end
            end
        end
        
        -- 第二階段：繪製上排零件（row = 2）
        for _, item in ipairs(eq) do
            -- 有特殊激活繪製邏輯的零件：SWORD, CANON, FEET, CLAW
            local has_special_render = (item.id == "SWORD" or item.id == "CANON" or item.id == "FEET" or item.id == "CLAW")
            local should_skip = has_special_render and (item.id == mech_controller.active_part_id)
            if not should_skip and item.row == 2 then
                local pdata = _G.PartsData and _G.PartsData[item.id]
                if pdata and pdata._img then
                    local cell_size = mech_grid.cell_size
                    local px = draw_x + (item.col - 1) * cell_size
                    local py_top = body_draw_y + (mech_grid.rows - item.row) * cell_size
                    local ok, iw, ih = pcall(function() return pdata._img:getSize() end)
                    if ok and iw and ih then
                        local part_y
                        if pdata.align_image_top then
                            part_y = py_top
                        else
                            local offset_y = pdata.image_offset_y or 0
                            part_y = py_top + (cell_size - ih) + offset_y
                        end
                        -- 特殊處理 CLAW
                        if item.id == "CLAW" then
                            pcall(function() pdata._img:draw(px, part_y) end)
                            local pivot_x = px + iw / 2
                            local pivot_y = part_y + ih / 2
                            if pdata._arm_img then
                                local arm_ok, arm_w, arm_h = pcall(function() return pdata._arm_img:getSize() end)
                                if arm_ok and arm_w and arm_h then
                                    local angle_rad = math.rad(-mech_controller.claw_arm_angle)
                                    local cos_a = math.cos(angle_rad)
                                    local sin_a = math.sin(angle_rad)
                                    local arm_center_offset_x = arm_w / 2
                                    local rotated_dx = arm_center_offset_x * cos_a
                                    local rotated_dy = arm_center_offset_x * sin_a
                                    local arm_center_x = pivot_x + rotated_dx
                                    local arm_center_y = pivot_y + rotated_dy
                                    pcall(function() pdata._arm_img:drawRotated(arm_center_x, arm_center_y, -mech_controller.claw_arm_angle) end)
                                    local arm_end_rotated_dx = arm_w * cos_a
                                    local arm_end_rotated_dy = arm_w * sin_a
                                    local claw_pivot_x = pivot_x + arm_end_rotated_dx
                                    local claw_pivot_y = pivot_y + arm_end_rotated_dy
                                    if pdata._upper_img then
                                        local total_angle = -mech_controller.claw_arm_angle - mech_controller.claw_grip_angle
                                        pcall(function() pdata._upper_img:drawRotated(claw_pivot_x, claw_pivot_y, total_angle) end)
                                    end
                                    if pdata._lower_img then
                                        local total_angle = -mech_controller.claw_arm_angle + mech_controller.claw_grip_angle
                                        pcall(function() pdata._lower_img:drawRotated(claw_pivot_x, claw_pivot_y, total_angle) end)
                                    end
                                end
                            end
                        else
                            pcall(function() pdata._img:draw(px, part_y) end)
                        end
                    end
                end
            end
        end
    else
        -- 正常繪製合成的機甲圖像
        if mech_img then
            pcall(function() mech_img:draw(draw_x, draw_y) end)
        else
            -- 備用: 繪製機甲方塊
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRect(draw_x, draw_y, body_w, body_h)
        end
    end
    
    -- 如果 SWORD 已激活，額外繪製旋轉後的 SWORD
    if mech_controller.active_part_id == "SWORD" and _G.PartsData and _G.PartsData["SWORD"] then
        local sword_data = _G.PartsData["SWORD"]
        if sword_data._img then
            -- 找到 SWORD 在 mech 上的位置
            local eq = _G.GameState.mech_stats.equipped_parts or {}
            for _, item in ipairs(eq) do
                if item.id == "SWORD" then
                    local mech_grid = _G.GameState.mech_grid
                    local cell_size = mech_grid.cell_size
                    -- 計算 SWORD 在 mech image 中的位置 (相對於 mech 左上角)
                    local sx = (item.col - 1) * cell_size
                    local sy = (mech_grid.rows - item.row) * cell_size
                    -- 計算 SWORD 格子的中心點 (在螢幕座標) - 這是旋轉軸心
                    local pivot_x = draw_x + sx + cell_size / 2
                    local pivot_y = draw_y + sy + cell_size / 2
                    
                    gfx.pushContext()
                    local ok, iw, ih = pcall(function() return sword_data._img:getSize() end)
                    if ok and iw and ih then
                        -- 手動計算旋轉後的繪製位置
                        -- SWORD 原本的位置（底部對齊，左對齊）
                        local original_x = draw_x + sx
                        local original_y = draw_y + sy + cell_size - ih
                        
                        -- 計算圖片中心相對於格子中心的向量
                        local img_center_x = original_x + iw / 2
                        local img_center_y = original_y + ih / 2
                        local dx_from_pivot = img_center_x - pivot_x
                        local dy_from_pivot = img_center_y - pivot_y
                        
                        -- 將角度轉換為弧度（注意：往後旋轉是負角度）
                        local angle_rad = math.rad(-mech_controller.sword_angle)
                        
                        -- 旋轉向量
                        local cos_a = math.cos(angle_rad)
                        local sin_a = math.sin(angle_rad)
                        local rotated_dx = dx_from_pivot * cos_a - dy_from_pivot * sin_a
                        local rotated_dy = dx_from_pivot * sin_a + dy_from_pivot * cos_a
                        
                        -- 計算旋轉後圖片中心的新位置
                        local new_center_x = pivot_x + rotated_dx
                        local new_center_y = pivot_y + rotated_dy
                        
                        -- drawRotated 以圖片中心為軸旋轉，所以傳入新的中心位置
                        sword_data._img:drawRotated(new_center_x, new_center_y, -mech_controller.sword_angle)
                    end
                    gfx.popContext()
                    break
                end
            end
        end
    end
    
    -- 如果 CANON 已激活，額外繪製旋轉後的 CANON
    if mech_controller.active_part_id == "CANON" and _G.PartsData and _G.PartsData["CANON"] then
        local canon_data = _G.PartsData["CANON"]
        if canon_data._img then
            -- 找到 CANON 在 mech 上的位置
            local eq = _G.GameState.mech_stats.equipped_parts or {}
            for _, item in ipairs(eq) do
                if item.id == "CANON" then
                    local mech_grid = _G.GameState.mech_grid
                    local cell_size = mech_grid.cell_size
                    -- 計算 CANON 在 mech image 中的位置
                    local cx = (item.col - 1) * cell_size
                    local cy = (mech_grid.rows - item.row) * cell_size
                    -- 計算 CANON 格子的中心點（旋轉軸心）
                    local pivot_x = draw_x + cx + cell_size / 2
                    local pivot_y = draw_y + cy + cell_size / 2
                    
                    gfx.pushContext()
                    local ok, iw, ih = pcall(function() return canon_data._img:getSize() end)
                    if ok and iw and ih then
                        -- 手動計算旋轉後的繪製位置（與 SWORD 相同邏輯）
                        local original_x = draw_x + cx
                        local original_y = draw_y + cy + cell_size - ih
                        
                        local img_center_x = original_x + iw / 2
                        local img_center_y = original_y + ih / 2
                        local dx_from_pivot = img_center_x - pivot_x
                        local dy_from_pivot = img_center_y - pivot_y
                        
                        -- CANON 可以 360 度旋轉，向後旋轉用負角度
                        local angle_rad = math.rad(-mech_controller.canon_angle)
                        
                        local cos_a = math.cos(angle_rad)
                        local sin_a = math.sin(angle_rad)
                        local rotated_dx = dx_from_pivot * cos_a - dy_from_pivot * sin_a
                        local rotated_dy = dx_from_pivot * sin_a + dy_from_pivot * cos_a
                        
                        local new_center_x = pivot_x + rotated_dx
                        local new_center_y = pivot_y + rotated_dy
                        
                        canon_data._img:drawRotated(new_center_x, new_center_y, -mech_controller.canon_angle)
                    end
                    gfx.popContext()
                    break
                end
            end
        end
    end
    
    -- 如果 FEET 已激活，額外繪製 FEET（使用動畫或靜態圖片）
    if mech_controller.active_part_id == "FEET" and _G.PartsData and _G.PartsData["FEET"] then
        local feet_data = _G.PartsData["FEET"]
        if feet_data._img then
            -- 找到 FEET 在 mech 上的位置
            local eq = _G.GameState.mech_stats.equipped_parts or {}
            for _, item in ipairs(eq) do
                if item.id == "FEET" then
                    local mech_grid = _G.GameState.mech_grid
                    local cell_size = mech_grid.cell_size
                    local px = draw_x + (item.col - 1) * cell_size
                    local py_top = body_draw_y + (mech_grid.rows - item.row) * cell_size
                    
                    local ok, iw, ih = pcall(function() return feet_data._img:getSize() end)
                    if ok and iw and ih then
                        local part_y
                        if feet_data.align_image_top then
                            part_y = py_top
                        else
                            local offset_y = feet_data.image_offset_y or 0
                            part_y = py_top + (cell_size - ih) + offset_y
                        end
                        
                        -- 如果移動中且有動畫，使用動畫幀
                        if feet_imagetable and mech_controller.feet_is_moving then
                            local frame_image = feet_imagetable:getImage(feet_current_frame)
                            if frame_image then
                                pcall(function() frame_image:draw(px, part_y) end)
                            end
                        else
                            pcall(function() feet_data._img:draw(px, part_y) end)
                        end
                    end
                    break
                end
            end
        end
    end
    
    -- 如果 CLAW 已激活，額外繪製 CLAW（底座 + 旋轉的臂 + 旋轉的爪子）
    if mech_controller.active_part_id == "CLAW" and _G.PartsData and _G.PartsData["CLAW"] then
        local claw_data = _G.PartsData["CLAW"]
        if claw_data._img then
            -- 找到 CLAW 在 mech 上的位置
            local eq = _G.GameState.mech_stats.equipped_parts or {}
            for _, item in ipairs(eq) do
                if item.id == "CLAW" then
                    local mech_grid = _G.GameState.mech_grid
                    local cell_size = mech_grid.cell_size
                    
                    -- 計算 CLAW 底座的位置
                    local base_x = draw_x + (item.col - 1) * cell_size
                    local base_y_top = body_draw_y + (mech_grid.rows - item.row) * cell_size
                    
                    -- 繪製底座
                    local ok, base_w, base_h = pcall(function() return claw_data._img:getSize() end)
                    if ok and base_w and base_h then
                        local base_y = base_y_top + (cell_size - base_h)
                        pcall(function() claw_data._img:draw(base_x, base_y) end)
                        
                        -- 計算底座中心點（臂的旋轉軸心）
                        local pivot_x = base_x + base_w / 2
                        local pivot_y = base_y + base_h / 2
                        
                        -- 載入臂的圖片
                        if claw_data.arm_image and claw_data._arm_img then
                            local arm_ok, arm_w, arm_h = pcall(function() return claw_data._arm_img:getSize() end)
                            if arm_ok and arm_w and arm_h then
                                -- 臂的左邊緣對齊底座中心，以底座中心為軸旋轉
                                -- 計算臂圖片中心點相對於底座中心的偏移
                                local arm_center_offset_x = arm_w / 2  -- 臂中心在圖片中間
                                local arm_center_offset_y = 0  -- Y 方向無偏移
                                
                                -- 旋轉偏移向量
                                local angle_rad = math.rad(-mech_controller.claw_arm_angle)
                                local cos_a = math.cos(angle_rad)
                                local sin_a = math.sin(angle_rad)
                                local rotated_dx = arm_center_offset_x * cos_a - arm_center_offset_y * sin_a
                                local rotated_dy = arm_center_offset_x * sin_a + arm_center_offset_y * cos_a
                                
                                -- 臂圖片中心的最終位置
                                local arm_center_x = pivot_x + rotated_dx
                                local arm_center_y = pivot_y + rotated_dy
                                
                                -- 繪製旋轉的臂
                                pcall(function() 
                                    claw_data._arm_img:drawRotated(arm_center_x, arm_center_y, -mech_controller.claw_arm_angle)
                                end)
                                
                                -- 計算臂末端位置（爪子的旋轉軸心）
                                local arm_end_offset_x = arm_w  -- 臂的右邊緣
                                local arm_end_offset_y = 0
                                local arm_end_rotated_dx = arm_end_offset_x * cos_a - arm_end_offset_y * sin_a
                                local arm_end_rotated_dy = arm_end_offset_x * sin_a + arm_end_offset_y * cos_a
                                local claw_pivot_x = pivot_x + arm_end_rotated_dx
                                local claw_pivot_y = pivot_y + arm_end_rotated_dy
                                
                                -- 繪製上爪（以臂末端為軸，加上自身旋轉角度）
                                if claw_data.upper_image and claw_data._upper_img then
                                    local upper_ok, upper_w, upper_h = pcall(function() return claw_data._upper_img:getSize() end)
                                    if upper_ok and upper_w and upper_h then
                                        local total_angle = -mech_controller.claw_arm_angle - mech_controller.claw_grip_angle
                                        pcall(function()
                                            claw_data._upper_img:drawRotated(claw_pivot_x, claw_pivot_y, total_angle)
                                        end)
                                    end
                                end
                                
                                -- 繪製下爪（以臂末端為軸，反向旋轉）
                                if claw_data.lower_image and claw_data._lower_img then
                                    local lower_ok, lower_w, lower_h = pcall(function() return claw_data._lower_img:getSize() end)
                                    if lower_ok and lower_w and lower_h then
                                        local total_angle = -mech_controller.claw_arm_angle + mech_controller.claw_grip_angle
                                        pcall(function()
                                            claw_data._lower_img:drawRotated(claw_pivot_x, claw_pivot_y, total_angle)
                                        end)
                                    end
                                end
                            end
                        end
                    end
                    break
                end
            end
        end
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

    -- 4. 繪製控制介面 UI
    -- 繪製 3x2 控制格子
    local eq = _G.GameState.mech_stats.equipped_parts or {}
    
    -- 找出選中格子對應的零件ID（用於高亮所有佔用格子）
    local selected_part_id_for_highlight = nil
    if mech_controller.selected_part_slot then
        for _, item in ipairs(eq) do
            local slot_w = item.w or 1
            local slot_h = item.h or 1
            if mech_controller.selected_part_slot.col >= item.col and mech_controller.selected_part_slot.col < item.col + slot_w and
               mech_controller.selected_part_slot.row >= item.row and mech_controller.selected_part_slot.row < item.row + slot_h then
                selected_part_id_for_highlight = item.id
                break
            end
        end
    end
    
    for r = 1, UI_GRID_ROWS do
        for c = 1, UI_GRID_COLS do
            local cx = UI_START_X + (c - 1) * (UI_CELL_SIZE + 5)
            local cy = UI_START_Y + (UI_GRID_ROWS - r) * (UI_CELL_SIZE + 5)
            
            -- 檢查此格是否有零件以及屬於哪個零件
            local part_id = nil
            local is_in_selected_part = false
            for _, item in ipairs(eq) do
                local slot_w = item.w or 1
                local slot_h = item.h or 1
                if c >= item.col and c < item.col + slot_w and
                   r >= item.row and r < item.row + slot_h then
                    part_id = item.id
                    -- 檢查是否屬於選中的零件
                    if selected_part_id_for_highlight and item.id == selected_part_id_for_highlight then
                        is_in_selected_part = true
                    end
                    break
                end
            end
            
            -- 繪製格子（高亮選中零件的所有格子）
            if is_in_selected_part then
                gfx.setColor(gfx.kColorBlack)
                gfx.fillRect(cx, cy, UI_CELL_SIZE, UI_CELL_SIZE)
                gfx.setColor(gfx.kColorWhite)
            else
                gfx.setColor(gfx.kColorBlack)
            end
            gfx.drawRect(cx, cy, UI_CELL_SIZE, UI_CELL_SIZE)
            
            -- 當前選中格子繪製粗外框
            if mech_controller.selected_part_slot and mech_controller.selected_part_slot.col == c and mech_controller.selected_part_slot.row == r then
                gfx.setLineWidth(3)
                gfx.drawRect(cx, cy, UI_CELL_SIZE, UI_CELL_SIZE)
                gfx.setLineWidth(1)  -- 恢復預設線寬
            end
            
            -- 顯示零件名稱縮寫（只在零件的起始格顯示）
            if part_id then
                for _, item in ipairs(eq) do
                    if item.id == part_id and item.col == c and item.row == r then
                        local label = string.sub(part_id, 1, 1)
                        gfx.drawText(label, cx + 6, cy + 6)
                        break
                    end
                end
            end
        end
    end
    
    -- 顯示當前激活的零件資訊
    local info_x = UI_START_X + UI_GRID_COLS * (UI_CELL_SIZE + 5) + 10
    if mech_controller.active_part_id then
        gfx.drawText("Active: " .. mech_controller.active_part_id, info_x, UI_START_Y)
        if mech_controller.active_part_id == "SWORD" then
            gfx.drawText("Angle: " .. math.floor(mech_controller.sword_angle), info_x, UI_START_Y + 15)
        end
    else
        gfx.drawText("Select part (A)", info_x, UI_START_Y)
    end
    
    -- 5. 繪製調試信息
    gfx.drawText("Mech X: " .. math.floor(mech_x), 10, SCREEN_HEIGHT - 15)
end

return StateMission