-- entity_controller.lua — EntityController 類別（關卡總控：地形/實體管理/碰撞裁判）
-- [[ P1 拆檔 ]] 自 module_entities.lua 拆出；由 module_entities.lua（聚合器）載入

import "CoreLibs/graphics"

local gfx = playdate.graphics
-- EnemyData 由 entity_enemy.lua 載入並掛於 _G（Playdate import 同檔僅載一次，
-- 二次 import 拿不到回傳值，故經 _G 中繼；聚合器保證 entity_enemy 先載入）
local EnemyData = _G.EnemyData or {}

EntityController = {}

-- [[ ========================================== ]]
-- [[  EntityController 類別 (實體總控制器) ]]
-- [[ ========================================== ]]

function EntityController:init(scene_data, enemies_data, player_move_speed, ui_offset)
    local ui_offset = ui_offset or 0  -- UI 區域偏移量
    local safe_ground_y = (scene_data and scene_data.ground_y) or 240
    -- 將地面往上移動 ui_offset
    safe_ground_y = safe_ground_y - ui_offset
    
    local controller = {
        obstacles = {},  -- 先初始化為空，稍後處理
        ground_y = safe_ground_y,
        terrain = {},  -- 地形數據
        backgrounds = {}, -- 背景層列表
        enemies = {}, -- 新增敵人列表
        projectiles = {}, -- 新增砲彈列表
        stones = {},  -- 新增石頭列表
        delivery_target = nil,  -- 交付目標物件
        GRAVITY = 0.5, -- 將重力常數傳入
        player_move_speed = player_move_speed or 2.0, -- 供敵人計算砲彈速度
        enemy_explosion_triggered = false  -- 標記是否有敵人爆炸被觸發
    }
    setmetatable(controller, { __index = EntityController })
    
    -- 初始化地形（64px單位）
    local terrain_data = (scene_data and scene_data.terrain) or {}
    for i, tdata in ipairs(terrain_data) do
        local terrain_type = tdata.type or "flat"
        local height_offset = tdata.height_offset or 0  -- 相對於 ground_y 的高度偏移
        table.insert(controller.terrain, {
            type = terrain_type,
            x = (i - 1) * 64,  -- 每單位64px寬
            width = 64,
            height_offset = height_offset
        })
    end
    
    -- 初始化背景層（兩層視差捲動）
    local bgs_data = (scene_data and scene_data.backgrounds) or {}
    for _, b in ipairs(bgs_data) do
        local bg = {
            layer = (b.layer or 0),
            x = b.x or 0,
            y = b.y or 0,
            image = nil,
            width = 0,
            height = 0
        }
        if b.image then
            local ok, img = pcall(function()
                return playdate.graphics.image.new(b.image)
            end)
            if ok and img then
                bg.image = img
                local ok_size, w, h = pcall(function() return img:getSize() end)
                if ok_size and w and h then
                    bg.width = w
                    bg.height = h
                end
            end
        end
        table.insert(controller.backgrounds, bg)
    end

    -- 初始化障礙物（加載圖片和計算尺寸）
    local obstacles_data = (scene_data and scene_data.obstacles) or {}
    for _, odata in ipairs(obstacles_data) do
        local obs = {
            x = odata.x,
            y = odata.y,
            width = 0,
            height = 0,
            image = nil
        }
        
        -- 加載圖片並獲取尺寸
        if odata.image then
            local ok, img = pcall(function()
                return playdate.graphics.image.new(odata.image)
            end)
            if ok and img then
                obs.image = img
                local ok_size, w, h = pcall(function() return img:getSize() end)
                if ok_size and w and h then
                    obs.width = w
                    obs.height = h
                end
            end
        else
            -- 如果沒有圖片，使用指定的寬高或預設值
            obs.width = odata.width or 40
            obs.height = odata.height or 40
        end
        
        table.insert(controller.obstacles, obs)
    end
    
    -- 初始化敵人
    for _, edata in ipairs(enemies_data or {}) do
        local enemy = Enemy:init(edata.x, edata.y, edata.type, safe_ground_y)
        table.insert(controller.enemies, enemy)
    end
    
    -- 初始化石頭
    local stones_data = (scene_data and scene_data.stones) or {}
    for _, sdata in ipairs(stones_data) do
        local stone_y = sdata.y == 0 and (safe_ground_y - 16) or sdata.y
        local stone = Stone:init(sdata.x, stone_y, safe_ground_y, sdata.target_id, sdata.image)
        table.insert(controller.stones, stone)
    end
    
    -- 初始化交付目標物件
    controller.delivery_targets = {}
    -- 支援單個目標（delivery_target）或多個目標（delivery_targets）
    local single_target = scene_data and scene_data.delivery_target
    local targets_data = (scene_data and scene_data.delivery_targets) or {}
    
    if single_target then
        local target_img = nil
        local target_width = 32
        local target_height = 32
        
        -- 加載圖片並獲取尺寸
        if single_target.image then
            local ok, img = pcall(function()
                return playdate.graphics.image.new(single_target.image)
            end)
            if ok and img then
                target_img = img
                local ok_size, w, h = pcall(function() return img:getSize() end)
                if ok_size and w and h then
                    target_width = w
                    target_height = h
                end
            end
        else
            -- 使用指定的寬高
            target_width = single_target.width or 32
            target_height = single_target.height or 32
        end
        
        local target_y = single_target.y == 0 and (safe_ground_y - target_height) or single_target.y
        local target = {
            id = single_target.id or "default",
            x = single_target.x,
            y = target_y,
            width = target_width,
            height = target_height,
            image = target_img,
            placed_stones = {},  -- 已放置的石頭列表
            is_completed = false  -- 是否已完成
        }
        table.insert(controller.delivery_targets, target)
    end
    
    for _, tdata in ipairs(targets_data) do
        local target_img = nil
        local target_width = 32
        local target_height = 32
        
        -- 加載圖片並獲取尺寸
        if tdata.image then
            local ok, img = pcall(function()
                return playdate.graphics.image.new(tdata.image)
            end)
            if ok and img then
                target_img = img
                local ok_size, w, h = pcall(function() return img:getSize() end)
                if ok_size and w and h then
                    target_width = w
                    target_height = h
                end
            end
        else
            -- 使用指定的寬高
            target_width = tdata.width or 32
            target_height = tdata.height or 32
        end
        
        local target_y = tdata.y == 0 and (safe_ground_y - target_height) or tdata.y
        local target = {
            id = tdata.id or "target" .. #controller.delivery_targets + 1,
            x = tdata.x,
            y = target_y,
            width = target_width,
            height = target_height,
            image = target_img,
            placed_stones = {},  -- 已放置的石頭列表
            is_completed = false  -- 是否已完成
        }
        table.insert(controller.delivery_targets, target)
    end
    
    -- 計算每個目標需要的石頭數量
    for _, target in ipairs(controller.delivery_targets) do
        target.required_count = 0
        for _, stone in ipairs(controller.stones) do
            if stone.target_id == target.id then
                target.required_count = target.required_count + 1
            end
        end
    end
    
    print("LOG: EntityController initialized with " .. #controller.obstacles .. " obstacles and " .. #controller.enemies .. " enemies.")
    return controller
end

-- 添加玩家砲彈
function EntityController:addPlayerProjectile(x, y, vx, vy, damage, grav_mult)
    grav_mult = grav_mult or 1.0
    
    local projectile = Projectile:init(x, y, vx, vy, damage, true, self.ground_y)
    -- 設定重力（基準重力 * 重力倍率）
    projectile.gravity = (self.GRAVITY or 0.5) * grav_mult
    table.insert(self.projectiles, projectile)
    print("LOG: Player fired projectile at (" .. math.floor(x) .. ", " .. math.floor(y) .. ") vx=" .. math.floor(vx) .. " grav_mult=" .. grav_mult)
end

function EntityController:updateAll(dt, mech_x, mech_y, mech_width, mech_height, mech_stats)
    local mech_damage_taken = 0

    -- [[ 放置成功特效 ]] 倒數計時（特效由 draw 繪製，播完才允許過關）
    for _, target in ipairs(self.delivery_targets or {}) do
        if target.success_effect_timer and target.success_effect_timer > 0 then
            target.success_effect_timer = target.success_effect_timer - dt
        end
    end

    -- 1. 更新敵人 (讓敵人移動和射擊)
    for i, enemy in ipairs(self.enemies) do
        if enemy.is_alive then
            enemy:update(dt, mech_x, mech_y, mech_width, mech_height, self)
            
            -- 檢查敵人與機甲碰撞 (扣 HP 邏輯)
            if self:checkMechCollision(mech_x, mech_y, mech_width, mech_height, enemy.x, enemy.y, enemy.width, enemy.height) then
                -- 特殊處理：地雷被玩家踩到時觸發
                if enemy.attack_type == "EXPLODE" and not enemy.is_triggered then
                    enemy.is_triggered = true
                    enemy.explode_timer = 0
                    print("LOG: Mine triggered by player!")
                end
                
                if enemy.attack_type == "CONTACT" then
                    -- 接觸傷害（一次性）
                    if not enemy.has_hit_player then
                        mech_damage_taken = mech_damage_taken + enemy.attack
                        enemy.has_hit_player = true
                    end
                elseif enemy.attack_type == "EXPLODE" then
                    -- 爆炸型敵人：只在爆炸時造成傷害
                    if enemy.is_exploded and not enemy.has_applied_explode_damage then
                        local distance = math.sqrt((mech_x - enemy.x)^2 + (mech_y - enemy.y)^2)
                        if distance < enemy.explode_radius then
                            mech_damage_taken = mech_damage_taken + enemy.explode_damage
                        end
                        enemy.has_applied_explode_damage = true
                    end
                else
                    -- 持續傷害
                    mech_damage_taken = mech_damage_taken + enemy.attack * dt
                end
            else
                enemy.has_hit_player = false  -- 離開碰撞範圍後重置
            end
            
            -- 檢查 sword 敵人的劍揮擊
            if enemy.attack_type == "SWING SWORD" and enemy.sword_swinging then
                -- 計算劍的位置（簡化為矩形區域）
                local sword_length = 30
                local sword_x = enemy.x + enemy.width / 2
                local sword_y = enemy.y + enemy.height / 2
                
                -- 劍的角度決定攻擊範圍
                local angle_rad = math.rad(enemy.sword_angle)
                local sword_end_x = sword_x + math.cos(angle_rad) * sword_length
                local sword_end_y = sword_y + math.sin(angle_rad) * sword_length
                
                -- 簡化碰撞：檢查劍尖是否在機甲範圍內
                if sword_end_x >= mech_x and sword_end_x <= mech_x + mech_width and
                   sword_end_y >= mech_y and sword_end_y <= mech_y + mech_height then
                    if not enemy.sword_has_hit then
                        mech_damage_taken = mech_damage_taken + enemy.attack
                        enemy.sword_has_hit = true
                    end
                else
                    enemy.sword_has_hit = false
                end
            end
            
            -- 檢查地雷爆炸
            if enemy.attack_type == "EXPLODE" and enemy.is_exploded and not enemy.has_applied_explode_damage then
                local distance = math.sqrt((mech_x - enemy.x)^2 + (mech_y - enemy.y)^2)
                if distance < enemy.explode_radius then
                    mech_damage_taken = mech_damage_taken + enemy.explode_damage
                end
                enemy.has_applied_explode_damage = true  -- 只應用一次傷害
                -- 不要立即設置 is_alive = false，讓動畫播放完畢
            end
        end
    end

    -- 2. 更新砲彈 (處理物理與碰撞)
    for i = #self.projectiles, 1, -1 do
        local p = self.projectiles[i]
        if p.active then
            p:update(dt, self.GRAVITY, self)  -- 傳入 entity_controller
            
            -- 檢查敵人砲彈是否擊中機甲
            if not p.is_player_bullet and self:checkMechCollision(mech_x, mech_y, mech_width, mech_height, p.x, p.y, p.width, p.height) then
                mech_damage_taken = mech_damage_taken + p.damage
                p.active = false -- 擊中後銷毀
            end
            
            -- 檢查玩家砲彈是否擊中敵人
            if p.is_player_bullet then
                for _, enemy in ipairs(self.enemies) do
                    if enemy.is_alive and self:checkMechCollision(enemy.x, enemy.y, enemy.width, enemy.height, p.x, p.y, p.width, p.height) then
                        -- 特殊處理：地雷被砲彈擊中時觸發
                        if enemy.attack_type == "EXPLODE" and not enemy.is_triggered then
                            enemy.is_triggered = true
                            enemy.explode_timer = 0  -- 重置計時器開始計數
                            p.active = false
                            print("LOG: Mine triggered by projectile!")
                            break
                        end
                        
                        -- 盾牌機器人的特殊邏輯
                        local shield_blocked = false
                        if enemy.type_id == "SHIELD_ROBOT" and enemy.shield_raised then
                            -- 盾牌在敵人左邊，阻擋從左邊來的子彈
                            local shield_x = enemy.x + enemy.shield_offset_x
                            local shield_right = shield_x + enemy.shield_width
                            local shield_top = enemy.y + enemy.shield_offset_y
                            local shield_bottom = shield_top + enemy.shield_height
                            
                            -- 判斷子彈是否在盾牌範圍內
                            if p.x >= shield_x and p.x <= shield_right and
                               p.y >= shield_top and p.y <= shield_bottom then
                                -- 子彈在盾牌範圍內，檢查擊中位置
                                -- 從左邊擊中時被擋（子彈向右移動 vx > 0）
                                if p.vx > 0 then
                                    p.active = false  -- 盾牌吸收子彈，不造成傷害
                                    shield_blocked = true
                                    print("LOG: Shield blocks projectile from left!")
                                end
                                -- 從其他方向（右邊、上方、下方）擊中時造成傷害，繼續進行
                            end
                        end
                        
                        -- 若盾牌未阻擋，則造成傷害
                        if not shield_blocked then
                            -- 擊中敵人
                            enemy.hp = enemy.hp - p.damage
                            p.active = false -- 砲彈銷毀
                            
                            -- 播放擊中音效
                            if _G.SoundManager and _G.SoundManager.playHit then
                                _G.SoundManager.playHit()
                            end
                            
                            -- 敵人受擊震動
                            enemy.hit_shake_timer = 0.3
                            enemy.hit_shake_offset_x = 0
                            
                            print("LOG: Player projectile hit enemy! HP=" .. math.floor(enemy.hp))
                            
                            if enemy.hp <= 0 and not enemy.is_exploding then
                                enemy.is_exploding = true
                                enemy.exploding_frame_index = 0
                                enemy.exploding_frame_timer = 0
                                if _G.SoundManager and _G.SoundManager.playExplode then
                                    _G.SoundManager.playExplode()
                                end
                                -- 設置敵人爆炸標志
                                self.enemy_explosion_triggered = true
                                print("LOG: Enemy killed by player projectile, starting explosion animation")
                            end
                        end
                        break
                    end
                end
            end
            
        else
            table.remove(self.projectiles, i) -- 移除不活躍的砲彈
        end
    end
    
    -- 3. 更新石頭
    for i = #self.stones, 1, -1 do
        local stone = self.stones[i]
        stone:update(dt, self.GRAVITY, self)  -- 傳入 entity_controller
        
        -- 檢查石頭是否與敵人碰撞（造成傷害）
        if not stone.is_grabbed and (stone.vx ~= 0 or stone.vy ~= 0) then
            for _, enemy in ipairs(self.enemies) do
                if enemy.is_alive and self:checkMechCollision(enemy.x, enemy.y, enemy.width, enemy.height, stone.x, stone.y, stone.width, stone.height) then
                    -- 特殊處理：地雷被石頭擊中時觸發
                    if enemy.attack_type == "EXPLODE" and not enemy.is_triggered then
                        enemy.is_triggered = true
                        enemy.explode_timer = 0  -- 重置計時器開始計數
                        print("LOG: Mine triggered by stone!")
                        break
                    end
                    
                    -- 石頭砸到敵人
                    enemy.hp = enemy.hp - stone.damage
                    enemy.hit_shake_timer = 0.3
                    enemy.hit_shake_offset_x = 0
                    
                    -- 播放擊中音效
                    if _G.SoundManager and _G.SoundManager.playHit then
                        _G.SoundManager.playHit()
                    end
                    
                    print("LOG: Stone hit enemy! HP=" .. math.floor(enemy.hp))
                    
                    if enemy.hp <= 0 and not enemy.is_exploding then
                        enemy.is_exploding = true
                        enemy.exploding_frame_index = 0
                        enemy.exploding_frame_timer = 0
                        if _G.SoundManager and _G.SoundManager.playExplode then
                            _G.SoundManager.playExplode()
                        end
                        -- 設置敵人爆炸標志
                        if self then
                            self.enemy_explosion_triggered = true
                        end
                        print("LOG: Enemy killed by stone, starting explosion animation")
                    end
                    
                    -- 石頭減速但繼續受重力影響
                    stone.vx = stone.vx * 0.5  -- 減少水平速度
                    -- 不強制設定 vy = 0，讓石頭繼續受重力影響
                    break
                end
            end
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

-- 檢查武器零件是否擊中敵人，並造成傷害
-- weapon_parts: 陣列，每個元素包含 {x, y, w, h, attack}
function EntityController:checkWeaponCollision(weapon_parts)
    local damage_dealt = 0
    
    for _, weapon in ipairs(weapon_parts or {}) do
        if not weapon.x or not weapon.y or not weapon.w or not weapon.h then
            goto next_weapon
        end
        
        for i, enemy in ipairs(self.enemies) do
            if enemy.is_alive and not enemy.is_exploding then
                -- AABB 碰撞檢查
                local collision = weapon.x < enemy.x + enemy.width and
                                 weapon.x + weapon.w > enemy.x and
                                 weapon.y < enemy.y + enemy.height and
                                 weapon.y + weapon.h > enemy.y
                
                if collision then
                    -- 擊中敵人，扣除 HP
                    local attack = weapon.attack or 0
                    enemy.hp = enemy.hp - attack
                    damage_dealt = damage_dealt + attack
                    
                    -- 播放擊中音效
                    if _G.SoundManager and _G.SoundManager.playHit then
                        _G.SoundManager.playHit()
                    end
                    
                    -- 調試輸出：顯示被攻擊敵人的 HP
                    print("LOG: Enemy hit! Type=" .. (enemy.type_id or "unknown") .. ", HP=" .. math.floor(enemy.hp) .. "/" .. (EnemyData[enemy.type_id] and EnemyData[enemy.type_id].hp or "?") .. ", Damage=" .. attack)
                    
                    -- 受擊效果：震動
                    enemy.hit_shake_timer = 0.3  -- 0.3 秒震動（增加持續時間）
                    enemy.hit_shake_offset_x = 0
                    
                    if enemy.hp <= 0 and not enemy.is_exploding then
                        -- [[ FIX ]] 近戰擊殺也要走爆炸狀態機（與砲彈擊殺一致），
                        -- 而非立即 is_alive=false——否則沒有爆炸特效，
                        -- 且最後一敵被近戰擊殺時會瞬間跳結算
                        enemy.is_exploding = true
                        enemy.exploding_frame_index = 0
                        enemy.exploding_frame_timer = 0
                        if _G.SoundManager and _G.SoundManager.playExplode then
                            _G.SoundManager.playExplode()
                        end
                        self.enemy_explosion_triggered = true
                        print("LOG: Enemy killed by melee weapon, starting explosion animation")
                    end
                end
            end
        end
        
        ::next_weapon::
    end
    
    return damage_dealt
end


function EntityController:draw(camera_x)
    local ground_y = self.ground_y
    gfx.setColor(gfx.kColorBlack)
    
    -- 繪製背景（先後景，再前景），背景隨畫面反向捲動；不重複平鋪
    if self.backgrounds and #self.backgrounds > 0 then
        local sorted = { }
        for _, bg in ipairs(self.backgrounds) do table.insert(sorted, bg) end
        table.sort(sorted, function(a, b) return (a.layer or 0) < (b.layer or 0) end)
        for _, bg in ipairs(sorted) do
            local parallax = (bg.layer == 1) and 0.6 or 0.3  -- 前景較快，後景較慢
            local screen_x = bg.x - (camera_x * parallax)
            local screen_y = bg.y
            if bg.image then
                -- 單次繪製，不進行重複平鋪
                pcall(function() bg.image:draw(screen_x, screen_y) end)
            end
        end
    end
    
    -- 繪製地形
    for _, terrain in ipairs(self.terrain) do
        local screen_x = terrain.x - camera_x
        
        -- 只繪製在畫面內的地形
        if screen_x < 400 and screen_x + 64 > 0 then
            local x1, y1, x2, y2 = self:getTerrainPoints(terrain.type, screen_x, ground_y, terrain.height_offset)
            
            -- 繪製地形線
            gfx.drawLine(x1, y1, x2, y2)
            
            -- 使用填充遮擋背景：將地形線下方填滿至畫面底部，以遮住背景
            gfx.fillTriangle(x1, y1, x2, y2, x2, 240)
            gfx.fillTriangle(x1, y1, x1, 240, x2, 240)
        end
    end 

    -- 繪製障礙物
    for i, obs in ipairs(self.obstacles) do
        
        if not obs then goto next_obstacle end 
        
        local obs_width = obs.width or 0 
        local obs_height = obs.height or 0
        local obs_x = obs.x or 0

        local obs_screen_x = obs_x - camera_x
        local obs_y = ground_y - obs_height

        if obs_screen_x < 400 and obs_screen_x + obs_width > 0 then
            if obs.image then
                -- 繪製圖片
                pcall(function() obs.image:draw(obs_screen_x, obs_y) end)
            else
                -- 備用：繪製方塊
                gfx.setColor(gfx.kColorBlack)
                gfx.fillRect(obs_screen_x, obs_y, obs_width, obs_height)
            end
        end
        
        ::next_obstacle::
    end
    
    -- 繪製敵人
    for _, enemy in ipairs(self.enemies) do
        enemy:draw(camera_x)
    end
    
    -- 繪製石頭
    for _, stone in ipairs(self.stones) do
        stone:draw(camera_x)
    end
    
    -- 繪製目標物件
    for _, target in ipairs(self.delivery_targets) do
        -- [[ 放置成功特效 ]] 石頭成功放上目標：從目標中心向外擴散的雙圓環（約 0.8 秒）
        if target.success_effect_timer and target.success_effect_timer > 0 then
            local duration = target.success_effect_duration or 0.8
            local p = 1 - (target.success_effect_timer / duration)  -- 0→1 進度
            local cx = target.x - camera_x + target.width / 2
            local cy = target.y + target.height / 2
            if cx >= -40 and cx <= 440 then
                gfx.setColor(gfx.kColorBlack)
                gfx.setLineWidth(2)
                gfx.drawCircleAtPoint(cx, cy, 6 + p * 24)
                if p > 0.3 then
                    gfx.drawCircleAtPoint(cx, cy, (p - 0.3) * 24)
                end
                gfx.setLineWidth(1)
            end
        end

        if not target.is_completed then  -- 只繪製未完成的目標
            local screen_x = target.x - camera_x
            if screen_x >= -target.width and screen_x <= 400 then
                if target.image then
                    -- 繪製圖片
                    pcall(function() target.image:draw(screen_x, target.y) end)
                else
                    -- 備用：繪製黑色方塊
                    gfx.setColor(gfx.kColorBlack)
                    gfx.fillRect(screen_x, target.y, target.width, target.height)
                end
                
                -- 在目標上方10px處繪製閃爍的"TARGET"文字
                local text = "TARGET"
                local text_width = gfx.getTextSize(text)
                local text_x = screen_x + (target.width - text_width) / 2
                local text_y = target.y - 10 - 8  -- 10px + 文字高度
                
                -- 實現閃爍效果（基於全局時間）
                local blink_time = playdate.getElapsedTime and playdate.getElapsedTime() or 0
                if math.floor(blink_time * 2) % 2 == 0 then
                    gfx.setColor(gfx.kColorBlack)
                    gfx.drawText(text, text_x, text_y)
                end
            end
        end
    end
    
    -- 繪製砲彈
    for _, projectile in ipairs(self.projectiles) do
        projectile:draw(camera_x)
    end
end

-- 獲取地形兩端點坐標
function EntityController:getTerrainPoints(terrain_type, screen_x, base_y, height_offset)
    local y_start = base_y + (height_offset or 0)
    local x1, y1, x2, y2 = screen_x, y_start, screen_x + 64, y_start
    
    if terrain_type == "up15" then
        y2 = y_start - 17  -- tan(15°) ≈ 0.27, 64 * 0.27 ≈ 17
    elseif terrain_type == "up30" then
        y2 = y_start - 37  -- tan(30°) ≈ 0.58, 64 * 0.58 ≈ 37
    elseif terrain_type == "up45" then
        y2 = y_start - 64  -- tan(45°) = 1, 64 * 1 = 64
    elseif terrain_type == "down15" then
        y2 = y_start + 17
    elseif terrain_type == "down30" then
        y2 = y_start + 37
    elseif terrain_type == "down45" then
        y2 = y_start + 64
    end
    
    return x1, y1, x2, y2
end

-- 獲取指定X位置的地面高度
function EntityController:getGroundHeight(world_x)
    -- 找到對應的地形單位
    for _, terrain in ipairs(self.terrain) do
        if world_x >= terrain.x and world_x < terrain.x + 64 then
            local base_y = self.ground_y + (terrain.height_offset or 0)
            local relative_x = world_x - terrain.x  -- 在地形單位內的相對位置
            local progress = relative_x / 64  -- 0到1的進度
            
            if terrain.type == "flat" then
                return base_y
            elseif terrain.type == "up15" then
                return base_y - (17 * progress)
            elseif terrain.type == "up30" then
                return base_y - (37 * progress)
            elseif terrain.type == "up45" then
                return base_y - (64 * progress)
            elseif terrain.type == "down15" then
                return base_y + (17 * progress)
            elseif terrain.type == "down30" then
                return base_y + (37 * progress)
            elseif terrain.type == "down45" then
                return base_y + (64 * progress)
            end
        end
    end
    
    -- 預設返回基準地面高度
    return self.ground_y
end

-- 獲取指定X位置的地形類型
function EntityController:getTerrainType(world_x)
    for _, terrain in ipairs(self.terrain) do
        if world_x >= terrain.x and world_x < terrain.x + 64 then
            return terrain.type
        end
    end
    return "flat"
end

-- 獲取指定X位置的地形角度（度數）
function EntityController:getTerrainAngle(world_x)
    local terrain_type = self:getTerrainType(world_x)
    
    if terrain_type == "up15" then
        return -15
    elseif terrain_type == "up30" then
        return -30
    elseif terrain_type == "up45" then
        return -45
    elseif terrain_type == "down15" then
        return 15
    elseif terrain_type == "down30" then
        return 30
    elseif terrain_type == "down45" then
        return 45
    else
        return 0
    end
end

-- 檢查移動方向是否能爬上斜坡
-- direction: 1=向右, -1=向左
function EntityController:canClimbSlope(world_x, direction, climb_power)
    local terrain_type = self:getTerrainType(world_x)
    
    -- 向右移動時檢查向上斜坡
    if direction > 0 then
        if terrain_type == "up15" and climb_power >= 1 then
            return true
        elseif terrain_type == "up30" and climb_power >= 2 then
            return true
        elseif terrain_type == "up45" and climb_power >= 3 then
            return true
        elseif terrain_type:sub(1, 4) == "down" then
            return true  -- 下坡總是可以走
        elseif terrain_type == "flat" then
            return true
        end
    -- 向左移動時檢查向下斜坡（從左看是上坡）
    elseif direction < 0 then
        if terrain_type == "down15" and climb_power >= 1 then
            return true
        elseif terrain_type == "down30" and climb_power >= 2 then
            return true
        elseif terrain_type == "down45" and climb_power >= 3 then
            return true
        elseif terrain_type:sub(1, 2) == "up" then
            return true  -- 從左往右看的下坡
        elseif terrain_type == "flat" then
            return true
        end
    end
    
    return false
end

-- checkCollision 函式 (用於機甲與場景的垂直/水平碰撞檢查，包含地形)
local function checkCollision(self, target_x, target_y, mech_vy_current, mech_y_old, mech_width, mech_height)
    local mech_left = target_x
    local mech_right = target_x + mech_width
    local mech_top = target_y
    local mech_bottom = target_y + mech_height
    
    local horizontal_block = false
    local final_y_stop = nil
    
    local safe_ground_y = self.ground_y or 240 
    
    -- 1. 檢查地形碰撞
    -- 使用機甲中心點的地面高度，因為機甲會旋轉以匹配斜坡角度
    local center_x = target_x + mech_width / 2
    local terrain_y = self:getGroundHeight(center_x)
    
    -- 只要機甲底部觸碰或低於地面，就設置停靠點
    if mech_bottom >= terrain_y then
        final_y_stop = terrain_y - mech_height
    end
    
    -- 2. 合併障礙物和石頭為檢查列表
    local all_obstacles = {}
    for _, obs in ipairs(self.obstacles) do
        table.insert(all_obstacles, {x = obs.x, width = obs.width, height = obs.height})
    end
    -- 添加石頭作為障礙物（未被抓住且在地面上）
    for _, stone in ipairs(self.stones or {}) do
        if not stone.is_grabbed and stone.is_grounded then
            local stone_height = stone.height
            table.insert(all_obstacles, {x = stone.x, width = stone.width, height = stone_height})
        end
    end

    -- 3. 檢查障礙物碰撞
    for i, obs in ipairs(all_obstacles) do
        
        if not obs then goto next_collision_check end 
        
        local obs_width = obs.width or 0 
        local obs_height = obs.height or 0
        local obs_x = obs.x or 0

        local obs_left = obs_x
        local obs_right = obs_left + obs_width
        local obs_top = safe_ground_y - obs_height 
        local obs_bottom = safe_ground_y          

        -- 廣義重疊檢查 (AABB 碰撞)
        if mech_right > obs_left and mech_left < obs_right and
           mech_bottom > obs_top and mech_top < obs_bottom then
            
            -- 細分碰撞類型
            
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
