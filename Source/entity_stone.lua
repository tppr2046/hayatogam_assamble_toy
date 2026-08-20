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
        -- [[ 2026-08-09 ]] 運送物由 stone 改為 crate（24×19）。尺寸一律讀圖，改圖不必改程式。
        local ok, img = pcall(function()
            return playdate.graphics.image.new("images/crate")
        end)
        if ok and img then
            stone_img = img
            local ok_size, w, h = pcall(function() return img:getSize() end)
            if ok_size and w and h then
                img_width = w
                img_height = h
            end
        end
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
        -- [[ §15.5a-6 ]] 石頭的歸屬。**只有飛行中才有意義**。
        --   nil / "PLAYER" → 只傷敵人（切片以來的行為，不變）
        --   "BOSS"         → 只傷玩家，且**不傷敵人**（BOSS 砸自己的小兵很難解釋）
        -- ★★ 落地時一律清回 nil（見 update）—— 否則 BOSS 丟過來的石頭停在地上
        --   還掛著傷害判定，玩家走過去撿就會莫名扣血。
        --   清成中性之後它就是玩家的彈藥：BOSS 自己供應消耗品。
        owner = nil,
        mech_damage = 12,  -- 砸到玩家的傷害（只有 owner=="BOSS" 時會用到）
        -- [[ §15.5a-6 ]] **臨時石頭**（BOSS 丟出來的那種）。nil＝永久石頭（既有行為，不變）。
        -- 規則（2026-08-19 使用者拍板）：
        --   1) **落地後** despawn_time 秒消失 —— 計時只在「站在地上」時走
        --   2) 被爪子抓著時不會消失（沒落地就不計時，所以這條是自動成立的，不必特判）
        --   3) 擊中敵人／BOSS 就消失（在 entity_controller 的命中分支移除）
        --   4) 丟出去沒打中 → 落地後**重新計時**（落地那一刻歸零）
        -- ★ 這樣「BOSS 供應彈藥」是有時限的：撿了要馬上用，不能囤一地。
        despawn_time = nil,
        despawn_timer = 0,
        is_gone = false,
        target_id = target_id,  -- 指定要放到哪個目標
        is_placed = false  -- 是否已經放到指定目標
    }
    setmetatable(stone, { __index = Stone })
    return stone
end

function Stone:update(dt, gravity, entity_controller)
    if self.is_grabbed or self.is_placed then
        -- 被抓住或已放置時不更新物理（★ 也因此不計時 → 抓在爪子上不會消失）
        return
    end

    -- [[ §15.5a-6 ]] 臨時石頭：落地後開始倒數，時間到就標記消失
    -- （實際從清單移除是在 entity_controller，那裡才拿得到陣列）
    if self.despawn_time and self.is_grounded then
        self.despawn_timer = (self.despawn_timer or 0) + dt
        if self.despawn_timer >= self.despawn_time then
            self.is_gone = true
        end
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
            self.owner = nil  -- ★ [[ §15.5a-6 ]] 落地即歸零成中性，見 init 的註解
            self.despawn_timer = 0  -- ★ 每次落地都**重新計時**（丟出去沒打中就是這條）
        end
    end
    
    -- 水平移動
    self.x = self.x + self.vx
end

function Stone:draw(camera_x)
    -- [[ 2026-08-09 ]] 判斷改用 is_hidden，不再是 is_placed ——
    -- 放上目標後箱子要**跟著目標一起飛走**，所以那段期間仍需繪製；
    -- 等目標飛完消失時才由 entity_controller 設 is_hidden。
    if self.is_hidden then
        return
    end

    -- [[ §15.5a-6 ]] 臨時石頭：最後 1 秒閃爍。
    -- ★ 不預告就直接消失的話，玩家會以為是 bug（正要去撿，石頭沒了）。
    if self.despawn_time and self.is_grounded then
        local left = self.despawn_time - (self.despawn_timer or 0)
        if left <= 1.0 and (math.floor(playdate.getCurrentTimeMilliseconds() / 90) % 2) == 0 then
            return
        end
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

-- owner：nil/"PLAYER"＝玩家甩投（只傷敵人）、"BOSS"＝BOSS 投擲（只傷玩家）。
-- ★ 只在飛行期間有效，落地時 update 會清回 nil。
function Stone:launch(vx, vy, owner)
    -- 被拋出時設定速度
    self.vx = vx
    self.vy = vy
    self.is_grounded = false
    self.is_grabbed = false
    self.owner = owner
    self.despawn_timer = 0   -- 離地＝重新計時（落地時還會再歸零一次，兩邊都歸零才不會有殘值）
end

