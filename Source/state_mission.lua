-- state_mission.lua (整合 EntityController, 戰鬥與 HP 邏輯)

import "CoreLibs/graphics"
import "CoreLibs/animation"
import "CoreLibs/animator"
import "module_entities" 
-- 任務資料從 _G.MissionData 獲取（在 main.lua 中載入）
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
local current_mission_id = nil -- 當前任務 ID（用於檢查目標）


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
    -- 使用全域的 MissionData
    local MissionDataToUse = _G.MissionData
    local mission_id = (_G and _G.GameState and _G.GameState.current_mission) or nil
    print("DEBUG: mission_id from GameState = " .. tostring(mission_id))
    print("DEBUG: Using global MissionData? " .. tostring(_G.MissionData ~= nil))
    print("DEBUG: Local MissionData? " .. tostring(MissionData ~= nil))
    print("DEBUG: MissionDataToUse exists? " .. tostring(MissionDataToUse ~= nil))
    if MissionDataToUse then
        local keys = {}
        for k, v in pairs(MissionDataToUse) do
            table.insert(keys, tostring(k))
            print("DEBUG: Found mission key:", k, "scene exists?", v.scene ~= nil)
        end
        print("DEBUG: MissionDataToUse keys = " .. table.concat(keys, ", "))
    end
    if not mission_id and MissionDataToUse then
        for k, v in pairs(MissionDataToUse) do
            mission_id = k
            print("DEBUG: Using fallback mission_id = " .. tostring(mission_id))
            break
        end
    end
    print("DEBUG: Final mission_id = " .. tostring(mission_id))
    if mission_id and MissionDataToUse and MissionDataToUse[mission_id] and MissionDataToUse[mission_id].scene then
        current_scene = MissionDataToUse[mission_id].scene
        print("DEBUG: Scene loaded: width=" .. tostring(current_scene.width) .. ", ground_y=" .. tostring(current_scene.ground_y))
    else
        print("DEBUG: WARNING - No scene loaded!")
    end

    -- Initialize entity controller for the current scene (so ground/obstacles/enemies draw)
    -- 儲存當前任務 ID 用於目標檢查
    current_mission_id = mission_id
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
    
    -- 6. 遊戲結束/勝利條件檢查
    if current_hp <= 0 then
        print("GAME OVER: Mech destroyed!")
        setState(_G.StateResult, false, "Mech destroyed!") -- 失敗，顯示結果畫面
        return
    end
    
    -- 7. 檢查關卡目標是否完成
    local MissionDataToUse = _G.MissionData or MissionData
    if MissionDataToUse and current_mission_id then
        local mission = MissionDataToUse[current_mission_id]
        if mission and mission.objective then
            local obj = mission.objective
            
            -- 目標類型：打倒所有敵人
            if obj.type == "ELIMINATE_ALL" then
                if entity_controller and entity_controller.enemies then
                    local all_defeated = true
                    for _, enemy in ipairs(entity_controller.enemies) do
                        if enemy.hp and enemy.hp > 0 then
                            all_defeated = false
                            break
                        end
                    end
                    
                    if all_defeated and #entity_controller.enemies > 0 then
                        print("MISSION SUCCESS: All enemies defeated!")
                        setState(_G.StateResult, true, obj.description or "Mission Complete!", current_mission_id)
                        return
                    end
                end
            
            -- 目標類型：把石頭放到指定地點
            elseif obj.type == "DELIVER_STONE" then
                if mission.delivery_zone and entity_controller and entity_controller.stones then
                    local zone = mission.delivery_zone
                    for _, stone in ipairs(entity_controller.stones) do
                        -- 檢查石頭是否在目標區域內
                        if stone.x and stone.y then
                            if stone.x >= zone.x and stone.x < zone.x + zone.width and
                               stone.y >= zone.y and stone.y < zone.y + zone.height then
                                print("MISSION SUCCESS: Stone delivered to target zone!")
                                setState(_G.StateResult, true, obj.description or "Mission Complete!", current_mission_id)
                                return
                            end
                        end
                    end
                end
            end
        end
    end
end

function StateMission.draw()
    gfx.clear(gfx.kColorWhite) 
    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(font)
    
    -- 1. 繪製實體 (地面、障礙物、敵人)
    if entity_controller then
        entity_controller:draw(camera_x) 
    end

    -- 2. 繪製機甲（使用 MechController）
    if mech_controller then
        mech_controller:drawMech(mech_x, mech_y, camera_x, _G.GameState.mech_grid, _G.GameState, feet_imagetable, feet_current_frame)
    end
    
    -- 3. 繪製 HUD (HP 條)
    local hp_bar_x = 10
    local hp_bar_y = 10
    local hp_bar_width = 100
    local hp_bar_height = 10
    local hp_percent = current_hp / max_hp
    
    gfx.drawText("HP: " .. math.floor(current_hp) .. "/" .. max_hp, hp_bar_x, hp_bar_y - 15)
    gfx.drawRect(hp_bar_x, hp_bar_y, hp_bar_width, hp_bar_height)
    
    if current_hp > 0 then
        gfx.setColor(gfx.kColorBlack) 
        gfx.fillRect(hp_bar_x + 1, hp_bar_y + 1, (hp_bar_width - 2) * hp_percent, hp_bar_height - 2)
    end

    -- 4. 繪製控制介面 UI（使用 MechController）
    if mech_controller then
        mech_controller:drawUI(_G.GameState.mech_stats, UI_START_X, UI_START_Y, UI_CELL_SIZE, UI_GRID_COLS, UI_GRID_ROWS)
    end
    
    -- 5. 繪製調試信息
    gfx.drawText("Mech X: " .. math.floor(mech_x), 10, SCREEN_HEIGHT - 15)
end

return StateMission