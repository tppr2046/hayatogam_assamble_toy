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
    -- 設置字體
    gfx.setFont(font)
    is_paused = false
    timer = 0
    
    -- 1. 載入 Assets
    -- ❗ 假設您有 images/mech_24x32.png 圖片
    -- 如果在 HQ 已經合成了機體影像，使用它；否則組合當前 equipped_parts
    if _G and _G.GameState and _G.GameState.mech_image then
        Assets.mech_image = _G.GameState.mech_image
    else
        -- 嘗試從 HQ 儲存的網格設定與 equipped_parts 合成影像
        local mech_grid = _G and _G.GameState and _G.GameState.mech_grid
        local eq = _G and _G.GameState and _G.GameState.mech_stats and _G.GameState.mech_stats.equipped_parts
        if mech_grid and eq and _G.PartsData then
            local comp_w = mech_grid.cols * mech_grid.cell_size
            local comp_h = mech_grid.rows * mech_grid.cell_size
            local final_w, final_h = MECH_WIDTH, MECH_HEIGHT

                    -- Compose into a grid-sized composition (comp_w x comp_h) so layout matches HQ exactly
                    local okcomp, comp = pcall(function() return gfx.image.new(comp_w, comp_h) end)
                    if okcomp and comp then
                        gfx.pushContext(comp)
                        gfx.clear(gfx.kColorClear)
                        for i, item in ipairs(eq) do
                            local pid = item.id
                            local pdata = _G.PartsData and _G.PartsData[pid]
                            if not pdata then
                                -- missing part data
                            else
                                local px = (item.col - 1) * mech_grid.cell_size
                                local py = (item.row - 1) * mech_grid.cell_size
                                local pw = (item.w or 1) * mech_grid.cell_size
                                local ph = (item.h or 1) * mech_grid.cell_size
                                if pdata._img_scaled then
                                    -- If pre-rendered scaled image matches cell area, draw it; otherwise center it
                                    local ok, sw, sh = pcall(function() return pdata._img_scaled:getSize() end)
                                    if ok and sw and sh and sw == pw and sh == ph then
                                        pcall(function() pdata._img_scaled:draw(px, py) end)
                                    else
                                        local ok2, iw, ih = pcall(function() return pdata._img_scaled:getSize() end)
                                        if ok2 and iw and ih then
                                            local dx = math.floor((pw - iw) / 2)
                                            local dy = math.floor((ph - ih) / 2)
                                            pcall(function() pdata._img_scaled:draw(px + math.max(0, dx), py + math.max(0, dy)) end)
                                        else
                                            pcall(function() pdata._img_scaled:draw(px, py) end)
                                        end
                                    end
                                elseif pdata._img then
                                    local ok, iw, ih = pcall(function() return pdata._img:getSize() end)
                                    if ok and iw and ih then
                                        local dx = math.floor((pw - iw) / 2)
                                        local dy = math.floor((ph - ih) / 2)
                                        pcall(function() pdata._img:draw(px + math.max(0, dx), py + math.max(0, dy)) end)
                                    else
                                        pcall(function() pdata._img:draw(px, py) end)
                                    end
                                else
                                    -- no image for this part
                                end
                            end
                        end
                        gfx.popContext()

                        -- Use the grid-sized comp as the mech image so mission draws match HQ layout
                        Assets.mech_image = comp
                        _G.GameState.mech_image = comp
                        mech_draw_w = comp_w
                        mech_draw_h = comp_h
                        -- composed and cached as mech_image
                    else
                        print("WARN: Failed to create comp buffer; using default mech image")
                        Assets.mech_image = gfx.image.new("images/mech_24x32.png") or gfx.image.new("images/mech_24x32")
                    end
            -- mech_grid or equipped_parts missing; using default image
        end
    end

    -- Diagnostic: print whether mech image is available and its size
    if Assets.mech_image then
        local ok, iw, ih = pcall(function() return Assets.mech_image:getSize() end)
        -- Assets.mech_image size check (silent)
        if not ok then
            -- getSize failed; keep silent
        end
    else
        -- Assets.mech_image is nil after setup
    end
    
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
    
    -- StateMission initialized
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

    -- 2. 繪製機甲（使用容器方式直接繪製零件）
    local draw_x = mech_x - camera_x
    local draw_y = mech_y
    -- 使用實際的繪製尺寸（若合成或 fallback 設定過會使用 mech_draw_w/mech_draw_h）
    local draw_w = mech_draw_w or MECH_WIDTH
    local draw_h = mech_draw_h or MECH_HEIGHT
    -- 先清空機甲區域為白色背景，確保零件黑色像素可見
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(draw_x, draw_y, draw_w, draw_h)
    -- 外框（黑色）
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(draw_x, draw_y, draw_w, draw_h)

    -- 使用容器方式繪製：直接在畫面上逐一繪製每個已裝備的零件（不嘗試合成至單一 image）
    local mech_grid = _G and _G.GameState and _G.GameState.mech_grid
    local eq = _G and _G.GameState and _G.GameState.mech_stats and _G.GameState.mech_stats.equipped_parts or {}
    if mech_grid and eq and (#eq > 0) and _G.PartsData then
        local comp_w = mech_grid.cols * mech_grid.cell_size
        local comp_h = mech_grid.rows * mech_grid.cell_size
        local sx = (mech_draw_w or MECH_WIDTH) / comp_w
        local sy = (mech_draw_h or MECH_HEIGHT) / comp_h
        for _, item in ipairs(eq) do
            local pid = item.id
            local pdata = _G.PartsData and _G.PartsData[pid]
                if pdata then
                    local px = draw_x + math.floor((item.col - 1) * mech_grid.cell_size * sx)
                local py = draw_y + math.floor((item.row - 1) * mech_grid.cell_size * sy)
                local pw = math.max(1, math.floor((item.w or 1) * mech_grid.cell_size * sx))
                local ph = math.max(1, math.floor((item.h or 1) * mech_grid.cell_size * sy))
                local drew = false
                local info = {}
                    local src = pdata._img_scaled or pdata._img
                if pdata._img_scaled then
                    local oksize, sw, sh = pcall(function() return pdata._img_scaled:getSize() end)
                    table.insert(info, string.format("_img_scaled size=%s,%s", tostring(sw), tostring(sh)))
                    if oksize and sw and sh then
                        local dx = math.floor((pw - sw) / 2)
                        local dy = math.floor((ph - sh) / 2)
                        local draw_x = px + math.max(0, dx)
                        local draw_y = py + math.max(0, dy)
                        local ok, err = pcall(function() pdata._img_scaled:draw(draw_x, draw_y) end)
                        -- if drawing failed, we'll fallback silently
                        drew = ok
                        table.insert(info, string.format("draw_centered=%s", tostring(drew)))
                    end
                elseif pdata._img then
                    local oksize, iw, ih = pcall(function() return pdata._img:getSize() end)
                    table.insert(info, string.format("_img size=%s,%s", tostring(iw), tostring(ih)))
                    if oksize and iw and ih then
                        local dx = math.floor((pw - iw) / 2)
                        local dy = math.floor((ph - ih) / 2)
                        local draw_x = px + math.max(0, dx)
                        local draw_y = py + math.max(0, dy)
                        local ok, err = pcall(function() pdata._img:draw(draw_x, draw_y) end)
                        -- if drawing failed, we'll fallback silently
                        drew = ok
                        table.insert(info, string.format("draw_centered=%s", tostring(drew)))
                    end
                else
                    table.insert(info, "no_img")
                end
                if not drew then
                    -- 尝试更强的 fallback：建立临时缓冲区并在其上绘制，再把缓冲区 draw 回屏幕
                    local buf_ok, buf = pcall(function() return gfx.image.new(pw, ph) end)
                    if buf_ok and buf then
                        local drew_buf = false
                        local okpush, perr = pcall(function()
                            gfx.pushContext(buf)
                            gfx.clear(gfx.kColorClear)
                            -- 在緩衝中以原始尺寸繪製（不縮放），並置中到緩衝內
                            local gotSize, sw, sh = pcall(function() return src:getSize() end)
                            if gotSize and sw and sh then
                                local dx = math.floor((pw - sw) / 2)
                                local dy = math.floor((ph - sh) / 2)
                                pcall(function() src:draw(math.max(0, dx), math.max(0, dy)) end)
                            else
                                pcall(function() src:draw(0, 0) end)
                            end
                            gfx.popContext()
                        end)
                        if not okpush then
                            -- failed to push/pop context for temp buffer; silent fallback
                        else
                            local okdrawbuf, derrbuf = pcall(function() buf:draw(px, py) end)
                            if okdrawbuf then
                                drew = true
                            end
                        end
                    end
                end
                if not drew then
                    -- 最後回退到文字標籤
                    gfx.drawText(pid or "?", px, py)
                end
                -- debug info suppressed
            else
                gfx.drawText(pid or "?", draw_x, draw_y)
            end
        end
    else
        -- 若沒有格子資訊，嘗試繪製已快取的 mech image
        if mech_img then
            pcall(function() mech_img:draw(draw_x, draw_y) end)
        else
            -- 備用: 繪製機甲方塊
            gfx.fillRect(draw_x, draw_y, MECH_WIDTH, MECH_HEIGHT)
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

    -- 4. 繪製調試信息
    gfx.drawText("Mech X: " .. math.floor(mech_x), 10, SCREEN_HEIGHT - 30)
    gfx.drawText("Input: " .. last_input, 10, SCREEN_HEIGHT - 15)
end

return StateMission