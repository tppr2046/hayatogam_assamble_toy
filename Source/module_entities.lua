-- module_entities.lua (最終穩定版 - 修正 'continue' 為 'goto'，新增 Enemy/Projectile 基礎)

import "CoreLibs/graphics"
import "module_scene_data" 

local gfx = playdate.graphics
local EnemyData = import "enemy_data" -- 確保載入敵人數據

EntityController = {}

-- [[ ========================================== ]]
-- [[  Projectile 類別 (砲彈) ]]
-- [[ ========================================== ]]

Projectile = {}

-- 砲彈初始化
function Projectile:init(x, y, vx, vy, damage, is_player_bullet, ground_y)
    local p = {
        x = x,
        y = y,
        vx = vx,
        vy = vy,
        damage = damage,
        is_player_bullet = is_player_bullet,
        width = 4,    -- 砲彈寬度
        height = 4,   -- 砲彈高度
        active = true,
        ground_y = ground_y -- 引用地面高度來處理碰撞
    }
    setmetatable(p, { __index = Projectile })
    return p
end

-- 砲彈更新
function Projectile:update(dt, GRAVITY)
    if not self.active then return end
    
    -- 應用物理
    self.x = self.x + self.vx * dt
    -- 使用砲彈自帶的 gravity（若未設定則使用世界重力）
    local g = self.gravity or GRAVITY or 0.5
    self.vy = self.vy + g * dt
    self.y = self.y + self.vy * dt
    
    -- 檢查是否碰到地面
    if self.y + self.height >= self.ground_y then
        self.y = self.ground_y - self.height
        self.active = false
    end
end

-- 砲彈繪製
function Projectile:draw(camera_x)
    if not self.active then return end
    local screen_x = self.x - camera_x
    gfx.setColor(self.is_player_bullet and gfx.kColorRed or gfx.kColorBlack)
    gfx.fillRect(screen_x, self.y, self.width, self.height)
end

-- [[ ========================================== ]]
-- [[  Enemy 類別 (敵人) ]]
-- [[ ========================================== ]]

Enemy = {}

function Enemy:init(x, y, type_id, ground_y)
    local data = EnemyData[type_id]
    local e = {
        x = x,
        y = y,
        type_id = type_id,
        hp = data.hp,
        attack = data.attack,
        width = 24,  -- 敵人模型寬度
        height = 32, -- 敵人模型高度
        ground_y = ground_y,
        vx = 1.0, -- 基礎水平速度
        move_dir = 1, -- 1 for right, -1 for left
        is_alive = true,
        move_timer = 0,
        fire_timer = 0,
        fire_cooldown = 2.0 -- 每 2 秒發射一次
    }
    -- 確保敵人站在地面上
    e.y = ground_y - e.height 
    setmetatable(e, { __index = Enemy })
    print("LOG: Created Enemy " .. type_id .. " at " .. x)
    -- 從敵人資料讀取砲彈 multiplier（可在 enemy_data.lua 調整）
    e.projectile_speed_mult = (data and data.projectile_speed_mult) or 1.0
    e.projectile_grav_mult = (data and data.projectile_grav_mult) or 1.0
    return e
end

function Enemy:update(dt, mech_x, controller)
    if not self.is_alive then return end
    
    self.move_timer = self.move_timer + dt
    self.fire_timer = self.fire_timer + dt

    -- 左右移動邏輯 (BASIC_ENEMY)
    if self.type_id == "BASIC_ENEMY" then
        if self.move_timer > 2.0 then -- 每 2 秒換一次方向
            self.move_dir = self.move_dir * -1
            self.move_timer = 0
        end
        self.x = self.x + self.move_dir * self.vx * dt
    end

    -- 射擊邏輯
    if self.fire_timer >= self.fire_cooldown then
        self:fire(mech_x, controller)
        self.fire_timer = 0
    end
end

-- 發射拋物線砲彈 (擊向機甲)
function Enemy:fire(target_x, controller)
    local start_x = self.x + self.width / 2
    local start_y = self.y + self.height / 2
    local target_dist = target_x - start_x
    -- 使砲彈水平方向速度接近玩家的移動速度（尊重敵人定義的 multiplier）
    local base_vx = (controller and controller.player_move_speed) or 2.0
    local speed_multiplier = self.projectile_speed_mult or 1.0
    local vx_sign = 1
    if target_dist < 0 then vx_sign = -1 end
    local vx = vx_sign * base_vx * speed_multiplier

    -- 以水平速度估算到達時間（避免除以 0）
    local time_to_target = math.max(1.0, math.abs(target_dist) / math.max(math.abs(vx), 0.1))

    -- 使用與玩家相同的重力感覺（controller.GRAVITY），並乘上敵人定義的 grav multiplier
    local grav_multiplier = self.projectile_grav_mult or 1.0
    local projectileGravity = (controller and controller.GRAVITY) and (controller.GRAVITY * grav_multiplier) or 0.5

    -- 計算垂直初速度，使砲彈在 time_to_target 時抵達 target_y
    local target_y = self.ground_y - 32 -- 假定機甲高度
    local delta_y = target_y - start_y
    local GRAVITY = projectileGravity
    local vy = (delta_y - 0.5 * GRAVITY * time_to_target^2) / time_to_target

    -- 建立砲彈並給予自定重力
    local projectile = Projectile:init(start_x, start_y, vx, vy, self.attack, false, self.ground_y)
    projectile.gravity = projectileGravity
    table.insert(controller.projectiles, projectile)
end

function Enemy:draw(camera_x)
    if not self.is_alive then return end
    local screen_x = self.x - camera_x
    gfx.setColor(gfx.kColorBlack)
    -- 繪製敵人模型
    gfx.fillRect(screen_x, self.y, self.width, self.height) 
    -- 繪製 HP 條
    local hp_max = EnemyData[self.type_id].hp
    local hp_percent = self.hp / hp_max
    gfx.fillRect(screen_x, self.y - 5, self.width * hp_percent, 3) 
end

-- [[ ========================================== ]]
-- [[  EntityController 類別 (實體總控制器) ]]
-- [[ ========================================== ]]

function EntityController:init(scene_data, enemies_data, player_move_speed)
    local safe_ground_y = (scene_data and scene_data.ground_y) or 240 
    
    local controller = {
        obstacles = (scene_data and scene_data.obstacles) or {},
        ground_y = safe_ground_y,
        enemies = {}, -- 新增敵人列表
        projectiles = {}, -- 新增砲彈列表
        GRAVITY = 0.5, -- 將重力常數傳入
        player_move_speed = player_move_speed or 2.0 -- 供敵人計算砲彈速度
    }
    setmetatable(controller, { __index = EntityController })
    
    -- 初始化敵人
    for _, edata in ipairs(enemies_data or {}) do
        local enemy = Enemy:init(edata.x, edata.y, edata.type, safe_ground_y)
        table.insert(controller.enemies, enemy)
    end
    
    print("LOG: EntityController initialized with " .. #controller.obstacles .. " obstacles and " .. #controller.enemies .. " enemies.")
    return controller
end

function EntityController:updateAll(dt, mech_x, mech_y, mech_width, mech_height, mech_stats)
    local mech_damage_taken = 0

    -- 1. 更新敵人 (讓敵人移動和射擊)
    for i, enemy in ipairs(self.enemies) do
        if enemy.is_alive then
            enemy:update(dt, mech_x, self)
            
            -- 檢查敵人與機甲碰撞 (扣 HP 邏輯)
            if self:checkMechCollision(mech_x, mech_y, mech_width, mech_height, enemy.x, enemy.y, enemy.width, enemy.height) then
                 mech_damage_taken = mech_damage_taken + enemy.attack * dt -- 持續傷害
            end
        end
    end

    -- 2. 更新砲彈 (處理物理與碰撞)
    for i = #self.projectiles, 1, -1 do
        local p = self.projectiles[i]
        if p.active then
            p:update(dt, self.GRAVITY)
            
            -- 檢查砲彈是否擊中機甲
            if not p.is_player_bullet and self:checkMechCollision(mech_x, mech_y, mech_width, mech_height, p.x, p.y, p.width, p.height) then
                mech_damage_taken = mech_damage_taken + p.damage
                p.active = false -- 擊中後銷毀
            end
            
            -- TODO: 檢查砲彈是否擊中敵人
            
        else
            table.remove(self.projectiles, i) -- 移除不活躍的砲彈
        end
    end
    
    return mech_damage_taken
end

-- 簡易 AABB 碰撞檢查 (通用)
function EntityController:checkMechCollision(mech_x, mech_y, mech_w, mech_h, entity_x, entity_y, entity_w, entity_h)
    return mech_x < entity_x + entity_w and
           mech_x + mech_w > entity_x and
           mech_y < entity_y + entity_h and
           mech_y + mech_h > entity_y
end


function EntityController:draw(camera_x)
    local ground_y = self.ground_y
    gfx.setColor(gfx.kColorBlack)
    
    -- 繪製地面
    gfx.fillRect(0, ground_y, 400, 240 - ground_y) 

    -- 繪製障礙物 (原有的邏輯保持不變)
    for i, obs in ipairs(self.obstacles) do
        
        if not obs then goto next_obstacle end 
        
        local obs_width = obs.width or 0 
        local obs_height = obs.height or 0
        local obs_x = obs.x or 0

        local obs_screen_x = obs_x - camera_x
        local obs_y = ground_y - obs_height

        if obs_screen_x < 400 and obs_screen_x + obs_width > 0 then
            gfx.fillRect(obs_screen_x, obs_y, obs_width, obs_height)
        end
        
        ::next_obstacle::
    end
    
    -- 繪製敵人
    for _, enemy in ipairs(self.enemies) do
        enemy:draw(camera_x)
    end
    
    -- 繪製砲彈
    for _, projectile in ipairs(self.projectiles) do
        projectile:draw(camera_x)
    end
end

-- checkCollision 函式保持不變 (用於機甲與場景的垂直/水平碰撞檢查)
-- ... (您的 checkCollision 函式內容) ...
local function checkCollision(self, target_x, target_y, mech_vy_current, mech_y_old, mech_width, mech_height)
    local mech_left = target_x
    local mech_right = target_x + mech_width
    local mech_top = target_y
    local mech_bottom = target_y + mech_height
    
    local horizontal_block = false
    local final_y_stop = nil
    
    local safe_ground_y = self.ground_y or 240 

    for i, obs in ipairs(self.obstacles) do
        
        if not obs then goto next_collision_check end 
        
        local obs_width = obs.width or 0 
        local obs_height = obs.height or 0
        local obs_x = obs.x or 0

        local obs_left = obs_x
        local obs_right = obs_left + obs_width
        local obs_top = safe_ground_y - obs_height 
        local obs_bottom = safe_ground_y          

        -- 1. 廣義重疊檢查 (AABB 碰撞)
        if mech_right > obs_left and mech_left < obs_right and
           mech_bottom > obs_top and mech_top < obs_bottom then
            
            -- 2. 細分碰撞類型
            
            -- **A. 垂直碰撞 (從上方落下)**
            if mech_vy_current >= 0 and mech_y_old + mech_height <= obs_top + 1 and mech_bottom > obs_top then
                
                local potential_y_stop = obs_top - mech_height
                
                if not final_y_stop or potential_y_stop < final_y_stop then 
                    final_y_stop = potential_y_stop
                end
            
            -- **B. 水平碰撞 (移動時撞到)**
            elseif mech_top < obs_bottom and mech_bottom > obs_top + 5 then -- 避免與腳下的物體判斷為水平碰撞
                horizontal_block = true
            end
        end

        ::next_collision_check::
    end
    
    return horizontal_block, final_y_stop
end
EntityController.checkCollision = checkCollision

return EntityController