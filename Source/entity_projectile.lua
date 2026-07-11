-- entity_projectile.lua — Projectile 類別（砲彈/子彈，玩家與敵人共用）
-- [[ P1 拆檔 ]] 自 module_entities.lua 拆出；由 module_entities.lua（聚合器）載入

import "CoreLibs/graphics"

local gfx = playdate.graphics

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
function Projectile:update(dt, GRAVITY, entity_controller)
    if not self.active then return end
    
    -- 應用物理
    self.x = self.x + self.vx * dt
    -- 使用砲彈自帶的 gravity（若未設定則使用世界重力）
    local g = self.gravity or GRAVITY or 0.5
    self.vy = self.vy + g * dt
    self.y = self.y + self.vy * dt
    
    -- 檢查是否碰到地形
    local ground_height = entity_controller and entity_controller:getGroundHeight(self.x) or self.ground_y
    if self.y + self.height >= ground_height then
        self.y = ground_height - self.height
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

