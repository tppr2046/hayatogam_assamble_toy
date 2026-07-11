-- entity_stone.lua — Stone 類別（可抓取/搬運/放置的物件）
-- [[ P1 拆檔 ]] 自 module_entities.lua 拆出；由 module_entities.lua（聚合器）載入

import "CoreLibs/graphics"

local gfx = playdate.graphics

-- [[ ========================================== ]]
-- [[  Stone 类別 (可互動石頭) ]]
-- [[ ========================================== ]]

Stone = {}

function Stone:init(x, y, ground_y, target_id, image_path)
    local stone_img = nil
    local img_width = 16
    local img_height = 16
    
    -- 加載圖片並獲取尺寸
    if image_path then
        local ok, img = pcall(function()
            return playdate.graphics.image.new(image_path)
        end)
        if ok and img then
            stone_img = img
            local ok_size, w, h = pcall(function() return img:getSize() end)
            if ok_size and w and h then
                img_width = w
                img_height = h
            end
        end
    else
        -- 預設圖片
        pcall(function()
            stone_img = playdate.graphics.image.new("images/stone")
        end)
    end
    
    local stone = {
        x = x,
        y = y,
        width = img_width,
        height = img_height,
        vx = 0,
        vy = 0,
        is_grounded = (y >= ground_y - img_height),
        is_grabbed = false,  -- 是否被爪子抓住
        ground_y = ground_y,
        image = stone_img,
        damage = 15,  -- 砸到敵人的傷害
        target_id = target_id,  -- 指定要放到哪個目標
        is_placed = false  -- 是否已經放到指定目標
    }
    setmetatable(stone, { __index = Stone })
    return stone
end

function Stone:update(dt, gravity, entity_controller)
    if self.is_grabbed or self.is_placed then
        -- 被抓住或已放置時不更新物理
        return
    end
    
    -- 應用重力
    if not self.is_grounded then
        self.vy = self.vy + gravity
        self.y = self.y + self.vy
        
        -- 地形碰撞
        local ground_height = entity_controller and entity_controller:getGroundHeight(self.x) or self.ground_y
        if self.y >= ground_height - self.height then
            self.y = ground_height - self.height
            self.vy = 0
            self.vx = 0  -- 落地後停止
            self.is_grounded = true
        end
    end
    
    -- 水平移動
    self.x = self.x + self.vx
end

function Stone:draw(camera_x)
    if self.is_placed then
        return  -- 已放置的石頭不顯示
    end
    
    local screen_x = self.x - camera_x
    if self.image then
        pcall(function() self.image:draw(screen_x, self.y) end)
    else
        -- 備用：繪製方塊
        playdate.graphics.setColor(playdate.graphics.kColorBlack)
        playdate.graphics.fillRect(screen_x, self.y, self.width, self.height)
    end
end

function Stone:launch(vx, vy)
    -- 被拋出時設定速度
    self.vx = vx
    self.vy = vy
    self.is_grounded = false
    self.is_grabbed = false
end

