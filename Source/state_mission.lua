-- state_mission.lua (整合 EntityController, 戰鬥與 HP 邏輯)

import "CoreLibs/graphics"
import "CoreLibs/animation"
import "CoreLibs/animator"
import "module_entities" 
-- 任務資料從 _G.MissionData 獲取（在 main.lua 中載入）
local StateHQ = _G.StateHQ -- 假設 StateHQ 已在 main.lua 中設定為全域

local gfx = playdate.graphics

-- 載入 Assemble 字體，如果失敗則使用系統字體
local custom_font = gfx.font.new('fonts/Assemble')
local font = custom_font or gfx.font.systemFont

StateMission = {}

-- ==========================================
-- 常數與設定
-- ==========================================
local SCREEN_WIDTH = 400
local SCREEN_HEIGHT = 240
local UI_HEIGHT = 64  -- 操作介面高度

-- [[ S3 ]] 接管砲台時，機體站到砲台左側這麼遠的地方（機體中心 ↔ 砲台中心，px）。
-- 目的:讓機體不要壓在砲台上，擋住上方的 B:exit 提示。
-- ★ 必須 < weaponNear 的 range(44)，否則按 B 解除後機體會落在可接管範圍外、按不回 A。
local TURRET_STAND_OFFSET = 40

-- [[ 版面 ]] 場景對話框上緣。以上＝插圖可視區（400 × 163），以下＝滿版白底文字框。
-- 三處必須一致：state_intro / state_outro / 本檔的場景對話。
local DIALOG_Y = 163
local GAME_HEIGHT = SCREEN_HEIGHT - UI_HEIGHT  -- 實際遊戲畫面高度
local GRAVITY = 0.5
-- [[ 2026-08-07 移除 ]] 原本這裡有 `JUMP_VELOCITY = -10.0`，但**從來沒有被使用**
-- （實際跳躍在 entity_mech.lua，由零件 jump_height × 核心 jump_mult 反推初速度）。
-- 留著會讓人誤以為跳躍高度是 100px，實際上不是。已刪除。
local MOVE_SPEED = 2.0
local MECH_WIDTH = 24
local MECH_HEIGHT = 32

-- 操作介面相關
local UI_GRID_COLS = 3
local UI_GRID_ROWS = 2
local UI_CELL_SIZE = 32
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
local feet_frame_timer = 0    -- 位移累加器（像素；舊版是毫秒計時器）
-- [[ 手感 ]] 機體每水平移動這麼多像素，走路動畫換一幀。
-- 越小＝步頻越快。要對準腳的「跨步距離」才不會有滑步感：
-- 4 幀 × 8px = 一個完整循環走 32px，約等於 FEET 圖寬（48px）的 2/3。
local FEET_STRIDE_PX = 8

-- 任務狀態的局部變數
local is_paused = false
local timer = 0
-- [[ S3 場景武器接管 ]]
local controlling_weapon = nil     -- 目前接管中的場景武器（nil=控制機體）
local weapon_fire_timer = 0
-- 砲台仰角的 crank 靈敏度：改用與機體零件相同的表示法「crank 轉 1 圈 → 幾度」
-- （機體 CANON 為 15；此處預設 30，可在關卡 JSON 的該砲台以 crank_degrees_per_rotation 覆寫）
local WEAPON_CRANK_DEG_PER_ROTATION = 30
-- [[ 美術 ]] 接管砲台時的操作面板：turret_control（隨 crank 旋轉）、canon_button（A 發射）、
-- 其餘格子用 empty。與機體零件面板同為 3x2、每格 32x32。
local turret_ui = { tried = false, control = nil, button = nil, empty = nil }
local turret_fire_pressed = false   -- A 是否按著（面板按鈕顯示按下幀）
local tutorial_pending = false     -- [[ S10 ]] 待對話結束後啟動關卡內教學
local current_scene = nil
-- [[ S1 多場景 ]] 一關可含多個場景，經傳送點/達標載入下一場景
local current_scenes = nil        -- 場景陣列（單場景時 = { mission.scene }）
local current_scene_index = 1      -- 目前第幾個場景
local carry_npc_hp = nil           -- [[ S5 護送 ]] 跨場景帶過去的 NPC 血量
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
local mission_time_limit = -1  -- 任務時間限制（秒），-1 表示無時間限制
local mission_elapsed_time = 0 -- 任務經過時間（秒）
local dialog_active = false
local dialog_lines = nil
local dialog_index = 1
local dialog_image = nil
local typewriter_progress = 0
local typewriter_speed = 40 -- 每秒顯示的字符數

-- 爆炸狀態相關
local mech_exploding = false
local mech_explode_timer = 0
local mech_explode_duration = 1.0  -- 爆炸動畫時間
local mech_explode_image_table = nil
local mech_explode_frame_index = 0
local mech_explode_frame_timer = 0
local mech_explode_frame_duration = 0.05  -- 每幀 0.05 秒

-- 畫面震動相關
local camera_shake_timer = 999  -- 初始化為大於 duration 的值，避免開始時震動
local camera_shake_duration = 0.2  -- 震動時間（秒）
local camera_shake_intensity = 3  -- 震動幅度（像素）


-- ==========================================
-- 狀態機接口
-- ==========================================

-- [[ S1 多場景 ]] 載入一個場景：建立實體控制器、放置機甲、重置鏡頭、啟用該場景對話。
-- setup（第一場景）與 completeCurrentScene（傳送到下一場景）共用此函式。
local function loadScene(scene)
    current_scene = scene
    if current_scene and EntityController then
        local enemies = (current_scene.enemies) or {}
        entity_controller = EntityController:init(current_scene, enemies, MOVE_SPEED, UI_HEIGHT)
        -- [[ S5 護送 ]] 沿用上一場景帶過來的 NPC 血量（受過的傷不會因換場景而回復）
        if carry_npc_hp and entity_controller.npc then
            entity_controller.npc.hp = math.min(carry_npc_hp, entity_controller.npc.max_hp or carry_npc_hp)
        end
        carry_npc_hp = nil
    else
        entity_controller = nil
    end

    -- 機甲起始位置（每個場景從左側地面重新開始）
    if current_scene and current_scene.ground_y then
        mech_x = 50
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
    controlling_weapon = nil       -- [[ S3 ]] 進新場景時解除任何武器接管
    weapon_fire_timer = 0

    -- 場景對話（打字機）
    dialog_active = false
    dialog_lines = nil
    dialog_index = 1
    dialog_image = nil
    typewriter_progress = 0
    if current_scene and current_scene.dialog and current_scene.dialog.lines then
        dialog_lines = current_scene.dialog.lines
        dialog_active = true
        typewriter_progress = 0
        if current_scene.dialog.image then
            local ok, img = pcall(function() return playdate.graphics.image.new(current_scene.dialog.image) end)
            if ok and img then dialog_image = img end
        end
    end
end

-- [[ §8.08 掉落寬限 ]] 過關判定成立後，如果場上還有沒撿的掉落物，先不結束，
-- 給玩家一段時間走過去撿。
--
-- ★ 為什麼需要：掉落物是在敵人 `is_alive` 轉 false 的那一刻生成的，而
--   ELIMINATE_ALL / BOSS_KILL 的過關判定**也是**等最後一隻敵人爆完 —— 兩件事同一瞬間，
--   所以最後一擊的掉落**永遠來不及撿**。那不是玩家技術問題，是規則本身的漏洞。
--
-- ★ 為什麼放在 completeCurrentScene 裡：過關的呼叫點有 6 處（傳送點／ELIMINATE_ALL／
--   REACH／PROTECT／DELIVER…），逐處加寬限一定會漏（HANDOFF §3-5）。集中在這一個出口。
--
-- 寬限期間關卡照常運作（敵人已清空，所以只是讓玩家跑去撿）。
-- 撿完了就不必等滿 —— 下一幀 #drops == 0 就直接過關。
local CLEAR_GRACE_TIME = 3.0   -- 秒
local clear_grace_timer = nil

-- [[ S1 多場景 ]] 目前場景達標：非最後一場景→載入下一場景（保留機甲 HP/組裝）；最後一場景→通關結算。
local function completeCurrentScene()
    -- 還有掉落物沒撿 → 起算寬限期，先不結束
    if entity_controller and entity_controller.drops and #entity_controller.drops > 0 then
        if clear_grace_timer == nil then
            clear_grace_timer = CLEAR_GRACE_TIME
            print("LOG: clear grace started - " .. #entity_controller.drops .. " drops left")
        end
        if clear_grace_timer > 0 then return end
    end
    clear_grace_timer = nil

    if current_scenes and current_scene_index < #current_scenes then
        -- [[ S5 護送 ]] 把 NPC 目前血量帶到下一場景（跨場景護送才有連續性）
        if entity_controller and entity_controller.npc and not entity_controller.npc.is_dead then
            carry_npc_hp = entity_controller.npc.hp
        else
            carry_npc_hp = nil
        end
        current_scene_index = current_scene_index + 1
        print("LOG: Advancing to scene " .. current_scene_index .. "/" .. #current_scenes)
        loadScene(current_scenes[current_scene_index])
    else
        print("LOG: Final scene complete -> mission success")

        -- [[ 耐久 §8.07 ]] 過關才結算耗損（失敗不扣 —— 重試永遠免費，推進才有成本）。
        -- ★ 這裡是唯一的成功出口，所以耗損只會算一次。
        -- ★ current_hp 跨場景保留（loadScene 不會重設），所以這個比例是**整關**的累計掉血。
        -- ★ 重打已通關的關卡**一樣會耗損** —— 否則重打＝零成本收掉落，經濟直接破掉。
        if _G.Durability and _G.Durability.applyMissionWear then
            local ratio = 0
            if max_hp and max_hp > 0 then
                ratio = (max_hp - current_hp) / max_hp
            end
            local changes = _G.Durability.applyMissionWear(ratio)
            if #changes > 0 then
                print(string.format("LOG: durability wear (dmg %.0f%%): %d part(s)",
                                    ratio * 100, #changes))
                for _, c in ipairs(changes) do
                    print(string.format("     %s %d -> %d", c.id, c.before, c.after))
                end
            end
        end

        setState(_G.StateResult, true, "Mission Complete!", current_mission_id)
    end
end

function StateMission.setup()
    -- 初始化字體與狀態
    gfx.setFont(font)
    is_paused = false
    timer = 0
    clear_grace_timer = nil   -- [[ §8.08 ]] 重試/重打時要歸零，否則沿用上一場的殘值

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
                    -- ★ 外框計算也要吃 image_offset_x/y —— 反向槍往左伸出格外，
                    --   這裡漏掉的話合成圖會**把槍口切掉**（min_x 沒往左擴）。
                    local px = (item.col - 1) * mech_grid.cell_size + (pdata.image_offset_x or 0)
                    local py_top = (mech_grid.rows - item.row) * mech_grid.cell_size
                    local ok, iw, ih = pcall(function() return pdata._img:getSize() end)
                    if ok and iw and ih then
                        local draw_y
                        if pdata.align_image_top then
                            -- 圖片上緣對齊格子上緣（用於 FEET）
                            draw_y = py_top + (pdata.image_offset_y or 0)
                        else
                            -- 預設：圖片底部對齊格子底部
                            draw_y = py_top + (mech_grid.cell_size - ih) + (pdata.image_offset_y or 0)
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
                        -- ★ 與上面的外框計算用同一套位移，兩邊不一致就會畫歪
                        local px = (item.col - 1) * mech_grid.cell_size + (pdata.image_offset_x or 0) - min_x
                        local py_top = (mech_grid.rows - item.row) * mech_grid.cell_size - min_y
                        local ok, iw, ih = pcall(function() return pdata._img:getSize() end)
                        local draw_x = px
                        local draw_y
                        if ok and iw and ih then
                            if pdata.align_image_top then
                                -- 圖片上緣對齊格子上緣（用於 FEET）
                                draw_y = py_top + (pdata.image_offset_y or 0)
                            else
                                -- 預設：圖片底部對齊格子底部
                                draw_y = py_top + (mech_grid.cell_size - ih) + (pdata.image_offset_y or 0)
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
    
    if not mission_id and MissionDataToUse then
        for k, v in pairs(MissionDataToUse) do
            mission_id = k
            break
        end
    end
    
    -- [[ S1 多場景 ]] 解析場景清單：優先 mission.scenes[]（多場景），否則 { mission.scene }（單場景，向後相容）
    current_scenes = nil
    current_scene_index = 1
    local mdata = mission_id and MissionDataToUse and MissionDataToUse[mission_id]
    if mdata then
        if mdata.scenes and #mdata.scenes > 0 then
            current_scenes = mdata.scenes
        elseif mdata.scene then
            current_scenes = { mdata.scene }
        end
    end

    -- Initialize entity controller for the current scene (so ground/obstacles/enemies draw)
    -- 儲存當前任務 ID 用於目標檢查
    current_mission_id = mission_id
    
    -- 初始化任務時間限制
    mission_elapsed_time = 0
    if mission_id and MissionDataToUse and MissionDataToUse[mission_id] then
        mission_time_limit = MissionDataToUse[mission_id].time_limit or -1
    else
        mission_time_limit = -1
    end
    
    -- [[ S1 ]] 場景相依初始化（控制器/機甲位置/鏡頭/對話）改由 loadScene 統一處理，於本函式末尾呼叫

    -- 初始化機甲控制器
    mech_controller = MechController:init()

    -- 初始化 HP (從全域 GameState 獲取組裝後的 HP)
    local stats = (_G and _G.GameState and _G.GameState.mech_stats) or {}
    max_hp = stats.total_hp or 100
    current_hp = max_hp
    
    -- 重置爆炸狀態
    mech_exploding = false
    mech_explode_timer = 0
    mech_explode_duration = 1.0
    
    -- 重置畫面震動（初始化為大於 duration 的值）
    camera_shake_timer = 999

    -- 播放任務關卡 BGM（循環）
    if _G.SoundManager and _G.SoundManager.playMissionBGM then
        _G.SoundManager.playMissionBGM()
    end

    -- [[ S1 多場景 ]] 載入第一個場景（建立控制器/機甲位置/鏡頭/對話）
    loadScene(current_scenes and current_scenes[current_scene_index] or nil)

    -- [[ S8 ]] 安裝暫停選單（Menu 鍵）：Retry / Mission Select / BGM
    if _G.MenuItems and _G.MenuItems.installForMission then
        _G.MenuItems.installForMission()
    end

    -- [[ S10 ]] 首次遊玩：待關前對話結束後啟動關卡內操作教學
    tutorial_pending = (_G.Tutorial and _G.Tutorial.shouldShow and _G.Tutorial.shouldShow("mission")) or false
end

-- [[ S8 ]] 離開任務時清除系統選單項目
function StateMission.tearDown()
    if _G.MenuItems and _G.MenuItems.clear then _G.MenuItems.clear() end
end

function StateMission.update()
    if is_paused then return end

    -- [[ S10 ]] 教學覆蓋層作用中：吃掉輸入、暫停任務
    if _G.Tutorial and _G.Tutorial.isActive and _G.Tutorial.isActive() then
        _G.Tutorial.update()
        return
    end
    -- [[ S10 ]] 關前對話播完後，首次遊玩才啟動關卡內操作教學（避免與對話框重疊）
    if tutorial_pending and not dialog_active then
        tutorial_pending = false
        if _G.Tutorial and _G.Tutorial.maybeStart and _G.Tutorial.maybeStart("mission") then
            return
        end
    end

    -- 如果對話中，處理打字機效果和按鍵前進
    if dialog_active then
        typewriter_progress = typewriter_progress + typewriter_speed * (1/30) -- 假設約 30FPS
        local current_text = dialog_lines[dialog_index]
        -- 監聽 A 鍵（正確用法：呼叫 API 並傳入按鍵常數）
        if playdate.buttonJustPressed and playdate.buttonJustPressed(playdate.kButtonA) then
            if typewriter_progress < #current_text then
                -- 尚未完整顯示，直接顯示完整本句
                typewriter_progress = #current_text
            else
                -- 完整顯示後，切到下一句或結束
                if dialog_index < #dialog_lines then
                    dialog_index = dialog_index + 1
                    typewriter_progress = 0
                else
                    dialog_active = false
                end
            end
        end
        return -- 對話中暫停遊戲更新
    end
    
    -- 更新畫面震動計時器
    if camera_shake_timer < camera_shake_duration then
        camera_shake_timer = camera_shake_timer + (1/30)
    end

    -- 0. 記錄舊的 Y 座標 (用於 EntityController 碰撞檢查)
    mech_y_old = mech_y
    
    -- 0.1 更新 FEET 動畫
    -- [[ 手感 ]] 2026-08-07：改為「依實際移動距離換幀」，不再用固定計時。
    -- 原本每 100ms 換一幀，與機體實際位移無關 → 速度一改就對不上，產生滑步感
    -- （腳在踏、地面卻沒跟著跑相同距離）。現在每移動 FEET_STRIDE_PX 換一幀，
    -- 之後不論調 move_speed 或換幀數，腳步都會自動同步。
    if feet_imagetable and mech_controller then
        if mech_controller.feet_is_moving then
            -- 累加本幀的實際水平位移（像素）
            feet_frame_timer = feet_frame_timer + math.abs(mech_controller.move_velocity or 0)

            if feet_frame_timer >= FEET_STRIDE_PX then
                feet_frame_timer = feet_frame_timer - FEET_STRIDE_PX   -- 保留餘數，避免累積誤差

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

    -- [[ S3 場景武器接管 ]] 靠近武器按 A 接管；接管期間機體暫停，crank 瞄準、A 發射、B 解除
    if controlling_weapon then
        local cc = (playdate.getCrankChange and playdate.getCrankChange()) or 0
        local w = controlling_weapon
        -- crank 轉動量（度）→ 圈數 → 仰角變化
        local per_rot = w.crank_degrees_per_rotation or WEAPON_CRANK_DEG_PER_ROTATION
        local delta = (cc / 360.0) * per_rot
        w.angle = math.max(w.angle_min or 0, math.min(w.angle_max or 80, w.angle + delta))
        weapon_fire_timer = weapon_fire_timer + (1/30)
        turret_fire_pressed = playdate.buttonIsPressed(playdate.kButtonA)   -- 面板按鈕的按下狀態
        if playdate.buttonJustPressed(playdate.kButtonA) and weapon_fire_timer >= (w.cooldown or 0.5) then
            weapon_fire_timer = 0
            if entity_controller then entity_controller:fireSceneWeapon(w) end
            if _G.SoundManager and _G.SoundManager.playCanonFire then _G.SoundManager.playCanonFire() end
        end
        if playdate.buttonJustPressed(playdate.kButtonB) then
            controlling_weapon = nil
            turret_fire_pressed = false
            if _G.SoundManager and _G.SoundManager.playCursorMove then _G.SoundManager.playCursorMove() end
        end
    else
        local near = entity_controller and entity_controller:weaponNear(mech_x + 24, 44)
        if near and playdate.buttonJustPressed(playdate.kButtonA) then
            controlling_weapon = near
            weapon_fire_timer = 0
            -- [[ S3 ]] 接管時把機體挪到砲台左側的固定位置，避免擋住上方的 B:exit 提示。
            -- 以「機體中心」對齊 w.x - TURRET_STAND_OFFSET（中心＝mech_x + 24，與 weaponNear 同慣例）。
            -- ★ 40 必須 < weaponNear 的 range(44)，否則按 B 解除後會立刻掉出可接管範圍、按不回 A。
            mech_x = near.x - TURRET_STAND_OFFSET - 24
            if _G.SoundManager and _G.SoundManager.playSelect then _G.SoundManager.playSelect() end
        end
    end

    -- 1. 處理輸入 (使用 MechController)。接管武器時機體暫停（跳過選擇/操作）
    local dx = 0
    local mech_grid = _G.GameState.mech_grid

    if not controlling_weapon then
        -- 處理零件選擇和激活
        mech_controller:handleSelection(_G.GameState.mech_stats)
        -- 處理零件操作（獲取移動增量）
        dx = mech_controller:handlePartOperation(mech_x, mech_y, mech_grid, entity_controller)
    end
    
    -- [[ §15.3 移動平台 ]] 推進平台，並把「站在上面的玩家」一起帶走。
    -- ★★ 必須在**物理之前** —— entity_controller:updateAll 在本函式很後面才呼叫，
    --   把平台移動放在那裡會慢一幀，玩家看起來會在平台上滑動。
    -- ★ 直接改 mech_x/mech_y（不是加進 dx）：被平台載走**不是玩家的移動輸入**，
    --   混進 dx 會被滑行衰減與索道邊緣判定當成「玩家自己走過去」。
    if entity_controller and entity_controller.updatePlatformMotion then
        local body_w0 = (mech_grid and mech_grid.cols or 3) * (mech_grid and mech_grid.cell_size or 16)
        local body_h0 = (mech_grid and mech_grid.rows or 2) * (mech_grid and mech_grid.cell_size or 16)
        local cdx, cdy = entity_controller:updatePlatformMotion(1/30, mech_x, mech_y, body_w0, body_h0)
        mech_x = mech_x + cdx
        mech_y = mech_y + cdy
    end

    -- 2. 應用物理和碰撞檢測
    
    -- [[ P4 跳躍物理統一（決策 #2）]]
    -- 跳躍初速一次性交給 mech_vy，之後不論焦點在誰身上一律走一般重力。
    -- （舊制在 FEET 焦點與否之間切換兩套物理：半空切走會變軌、
    --   切回來還會因殘留的 velocity_y 在空中再彈一次）
    if mech_controller.velocity_y ~= 0 then
        mech_vy = mech_controller.velocity_y
        mech_controller.velocity_y = 0
    end
    -- [[ §15.3 吊索鉤 ]] 掛在索道上時**不套用重力**，機體吊在索道下方。
    -- ★ 這是唯一一個「暫停重力」的地方 —— 掛/放的判斷在 MechController，
    --   物理只在這裡處理，兩邊不重複。
    local hooked_rope = mech_controller.hookedRope and mech_controller:hookedRope() or nil
    if hooked_rope then
        mech_vy = 0
    else
        mech_vy = mech_vy + GRAVITY
    end

    -- 計算新的位置
    local new_x = mech_x + dx
    -- ★ 吊住時的高度 = 索道 y + **鉤索長度**（crank 收放），不是貼齊索道。
    local new_y = hooked_rope
        and (hooked_rope.y + (mech_controller.hook_len or 32))
        or (mech_y + mech_vy)
    
    -- 邊界檢查：限制玩家不能超出關卡寬度
    local scene_width = (current_scene and current_scene.width) or 400
    local mech_width = (mech_grid and mech_grid.cols or 3) * (mech_grid and mech_grid.cell_size or 16)
    if new_x < 0 then
        new_x = 0
    elseif new_x + mech_width > scene_width then
        new_x = scene_width - mech_width
    end
    
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

    -- [[ S2 懸崖 ]] 機甲水平中心是否在 pit（空洞）上方；是則不套用基準地面夾制，任其下墜
    local over_pit = false
    if entity_controller and entity_controller.getTerrainType then
        over_pit = (entity_controller:getTerrainType(new_x + body_w / 2) == "pit")
    end

    -- [[ §15.3 吊索鉤 ]] 放索不能穿過地面。
    -- ★ 夾的是 **hook_len 本身**（而不是只夾最後的 y）—— 只夾 y 的話 crank 會繼續
    --   累積看不見的鬆弛量，玩家得往回轉很久才看得到機體上升，像是失靈。
    -- ★ 在 pit 上方不夾 —— 那裡本來就沒有地面，正好是「放長索垂到坑裡」的用法。
    if hooked_rope and not over_pit then
        local max_len = ground_level - hooked_rope.y
        if max_len < 0 then max_len = 0 end
        if (mech_controller.hook_len or 0) > max_len then
            mech_controller.hook_len = max_len
            new_y = hooked_rope.y + max_len
        end
    end

    -- [[ §15.3 吊索鉤 ]] 移動到索道邊緣 → **脫鉤掉下去**。
    -- ★ 判定放在這裡（而不是 HOOK 的操作分支）：焦點切走之後 dx 來自別的零件，
    --   夾在那邊的話一離開 HOOK 焦點就失效了。這裡是所有移動的共同出口。
    if hooked_rope then
        local cx = new_x + body_w / 2
        if cx < hooked_rope.x1 or cx > hooked_rope.x2 then
            mech_controller.hook_rope = nil
            hooked_rope = nil
            print("LOG: hook released at rope edge")
        end
    end

    if hooked_rope then
        -- [[ §15.3 吊索鉤 ]] 掛住時：只吃水平移動與場景邊界，**不做地面/障礙的垂直夾制**。
        -- ★ 不走 checkCollision —— 那個函式的職責是「把機體壓回地面」，
        --   在索道上呼叫它會被立刻拉下去。
        mech_x = new_x
        mech_y = new_y
        is_on_ground = false
    elseif entity_controller then
        -- 使用 EntityController 進行精確碰撞（使用包含 FEET 的總高度）
        local horizontal_block, vertical_stop = entity_controller:checkCollision(new_x, new_y, mech_vy, mech_y_old, body_w, total_h)

        -- 如果沒有水平阻擋，採用計算後的新 X；否則保留原地（阻擋水平移動）
        if not horizontal_block then
            mech_x = new_x
        else
            -- 保持原本的 mech_x（或你可以在此加入推回量）
            -- mech_x = mech_x -- 明確保留
        end

        -- [[ §15.3 空中平台 ]] 先看有沒有踩到平台頂面（單向：只有下墜時算）。
        -- ★ 用「腳底這一幀從平台上方跨到下方」判定，不是「重疊」——
        --   重疊判定會讓從下往上跳時被平台頂住，那就不是單向平台了。
        local plat_y = nil
        if entity_controller.platformLanding then
            plat_y = entity_controller:platformLanding(new_x, body_w,
                        mech_y + total_h, new_y + total_h, mech_vy)
        end

        if plat_y then
            mech_x = new_x
            mech_y = plat_y - total_h
            mech_vy = 0
            is_on_ground = true
            mech_controller:updateGroundState(true)
        elseif vertical_stop then
            mech_y = vertical_stop
            mech_vy = 0
            is_on_ground = true
            mech_controller:updateGroundState(true)  -- 通知 MechController 已著地
        elseif (not over_pit) and new_y >= ground_level then
            -- 撞到地圖的「地面」（pit 上方不夾制→下墜）
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

    -- [[ S2 懸崖 ]] 掉出畫面底部 → 關卡失敗
    if mech_y > SCREEN_HEIGHT + 40 then
        print("MISSION FAILED: fell off a cliff")
        setState(_G.StateResult, false, "Fell off the cliff!")
        return
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

        -- [[ §8.08 掉落寬限 ]] 倒數。歸零後下一次過關判定就會真的結束關卡。
        if clear_grace_timer and clear_grace_timer > 0 then
            clear_grace_timer = clear_grace_timer - dt
        end

        -- 計算機甲本體碰撞框 (3×2 格)
        local mech_grid = _G.GameState.mech_grid
        local body_w = (mech_grid and mech_grid.cols or 3) * (mech_grid and mech_grid.cell_size or 16)
        local body_h = (mech_grid and mech_grid.rows or 2) * (mech_grid and mech_grid.cell_size or 16)
        
        -- 更新敵人和砲彈，使用本體碰撞框檢查受擊
        local damage = entity_controller:updateAll(dt, mech_x, mech_y, body_w, body_h, (_G.GameState and _G.GameState.mech_stats) or {})
        -- [[ §15.2 防護罩 ]] 傷害套用**之前**先讓防護罩攔一次（擋下就變 0,並起冷卻）。
        -- ★ 攔在這裡而不是改傷害計算 —— 共享血量池與所有命中判定維持原狀。
        -- ★ 這是**唯一**的傷害入口（entity_controller 把所有來源加總後回傳），所以只要攔這一處。
        if mech_controller and mech_controller.absorbDamage then
            damage = mech_controller:absorbDamage(damage)
        end
        if damage and damage > 0 then
            current_hp = current_hp - damage
            -- 觸發玩家受擊震動效果和音效
            mech_controller:onHit()
            SoundManager.playHit()
        end
        
        -- 檢查敵人爆炸標志，立即觸發畫面震動（無延遲）
        if entity_controller and entity_controller.enemy_explosion_triggered then
            camera_shake_timer = 0  -- 立即開始震動
            entity_controller.enemy_explosion_triggered = false  -- 重置標志
        end
        
        -- 更新機甲零件系統（GUN 自動發射、計時器、震動效果等）
        -- [[ S3 ]] 接管場景武器期間機體暫停：停止零件更新（含 GUN 自動發射）
        if not controlling_weapon then
            mech_controller:updateParts(dt, mech_x, mech_y, mech_grid, entity_controller)
        end
        
        -- 更新 CLAW 抓取邏輯（不論是否激活 CLAW 都要更新石頭位置）
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
                        -- [[ 支點 2026-08-08 ]] 與繪製端（drawClaw）用同一組座標：
                        -- 旋轉中心＝底座右齒輪圓心、爪尖＝臂右端圓盤圓心。
                        -- ★ 這裡是「抓取判定」的爪尖，必須跟畫面上的爪子同一點，
                        --   否則會出現「看起來夾到了卻抓不到」。
                        local pivot_x = base_x + (pdata.arm_mount_x or base_w / 2)
                        local pivot_y = base_y + (pdata.arm_mount_y or base_h / 2)

                        local angle_rad = math.rad(-mech_controller.claw_arm_angle)
                        local cos_a = math.cos(angle_rad)
                        local sin_a = math.sin(angle_rad)
                        -- ★ 再沿臂的方向往前 grip_hold_dist，落在**兩片爪的夾持凹口**上。
                        --   只算到鉸鏈軸的話，石頭會黏在關節上，看起來像卡住而不是夾住。
                        local cpx = (pdata.claw_pivot_x or arm_w) - (pdata.arm_pivot_x or 0)
                                    + (pdata.grip_hold_dist or 0)
                        local cpy = (pdata.claw_pivot_y or arm_h / 2) - (pdata.arm_pivot_y or arm_h / 2)
                        local claw_tip_x = pivot_x + cpx * cos_a - cpy * sin_a
                        local claw_tip_y = pivot_y + cpx * sin_a + cpy * cos_a

                        -- [[ 斜坡跟隨 ]] 繪製端（drawMechTilted）把整台機體繞
                        -- 「底部中心」旋轉 terrain_angle；爪尖的邏輯座標必須做
                        -- 同一個旋轉，否則斜坡上石頭不會跟著爪子走
                        local terrain_angle = entity_controller and entity_controller:getTerrainAngle(mech_x + cell_size * 1.5) or 0
                        if terrain_angle ~= 0 then
                            local tilt_pivot_x = mech_x + body_w / 2
                            local tilt_pivot_y = mech_y + total_h
                            local t_rad = math.rad(terrain_angle)
                            local t_cos = math.cos(t_rad)
                            local t_sin = math.sin(t_rad)
                            local rel_x = claw_tip_x - tilt_pivot_x
                            local rel_y = claw_tip_y - tilt_pivot_y
                            claw_tip_x = tilt_pivot_x + (rel_x * t_cos - rel_y * t_sin)
                            claw_tip_y = tilt_pivot_y + (rel_x * t_sin + rel_y * t_cos)
                        end

                        -- 如果有抓住石頭，更新石頭位置（不論是否激活 CLAW）
                        mech_controller:updateGrabbedStone(claw_tip_x, claw_tip_y)
                        
                        -- 如果 CLAW 激活且按下 A 鍵嘗試抓取
                        if mech_controller.active_part_id == "CLAW" and mech_controller.try_grab then
                            mech_controller:tryGrabStone(claw_tip_x, claw_tip_y, entity_controller.stones, 20)
                            mech_controller.try_grab = false
                        end
                    end
                end
                break
            end
        end
        
        -- 檢查武器零件碰撞 (攻擊敵人)
        -- SWORD 和 CLAW 只在轉動時才攻擊
        local weapon_parts = {}
        if mech_controller.sword_is_attacking or mech_controller.claw_is_attacking then
            local eq = _G.GameState.mech_stats.equipped_parts or {}
            for _, item in ipairs(eq) do
                local pdata = _G.PartsData and _G.PartsData[item.id]
                if pdata and pdata.attack and pdata.attack > 0 then
                    -- 檢查該武器是否處於攻擊狀態
                    local is_weapon_attacking = false
                    if item.id == "SWORD" and mech_controller.sword_is_attacking and mech_controller.active_part_id == item.id then
                        is_weapon_attacking = true
                    elseif item.id == "CLAW" and mech_controller.claw_is_attacking and mech_controller.active_part_id == item.id then
                        is_weapon_attacking = true
                    end
                    
                    if is_weapon_attacking then
                    -- 計算武器在世界座標的位置
                    local cell_size = mech_grid.cell_size
                    local wx = mech_x + (item.col - 1) * cell_size
                    local wy = mech_y + (mech_grid.rows - item.row) * cell_size
                    local ww = cell_size
                    local wh = cell_size
                    
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
                    -- 如果是 CLAW 且已激活，根據爪臂角度計算碰撞框
                    elseif item.id == "CLAW" and pdata._arm_img then
                        local ok, arm_w, arm_h = pcall(function() return pdata._arm_img:getSize() end)
                        if ok and arm_w and arm_h then
                            -- 計算 CLAW 實際攻擊範圍：以格子中心為軸心，臂的長度為半徑
                            local center_x = wx + cell_size / 2
                            local center_y = wy + cell_size / 2
                            local arm_length = arm_w  -- 臂的長度
                            
                            -- 根據當前角度計算爪尖位置
                            local angle_rad = math.rad(-mech_controller.claw_arm_angle)
                            local tip_x = center_x + math.cos(angle_rad) * arm_length
                            local tip_y = center_y + math.sin(angle_rad) * arm_length
                            
                            -- 碰撞框包含從中心到爪尖的矩形區域
                            local min_x = math.min(center_x, tip_x) - 12
                            local max_x = math.max(center_x, tip_x) + 12
                            local min_y = math.min(center_y, tip_y) - 12
                            local max_y = math.max(center_y, tip_y) + 12
                            
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
        end  -- 結束 if sword_is_attacking or claw_is_attacking
    end
    
    -- 5. 更新計時器
    if timer > 0 then
        timer = timer - 1 
    end
    
    -- 5.1 更新任務計時器
    if mission_time_limit > 0 then
        mission_elapsed_time = mission_elapsed_time + (1 / 30)  -- 假設 30 FPS
        
        -- 檢查是否超時
        if mission_elapsed_time >= mission_time_limit then
            print("MISSION FAILED: Time limit exceeded!")
            setState(_G.StateResult, false, "Time limit exceeded!")
            return
        end
    end
    
    -- 6. 遊戲結束/勝利條件檢查
    if current_hp <= 0 then
        print("GAME OVER: Mech destroyed!")
        -- 觸發機甲爆炸動畫
        if not mech_exploding then
            mech_exploding = true
            mech_explode_timer = 0
            
            -- 啟動畫面震動
            camera_shake_timer = 0
            
            -- 播放爆炸音效
            if _G.SoundManager and _G.SoundManager.playExplode then
                _G.SoundManager.playExplode()
            end
            print("LOG: Starting mech explosion animation")
        end
        
        -- 等待爆炸動畫完成
        mech_explode_timer = mech_explode_timer + (1/30)
        if mech_explode_timer >= mech_explode_duration then
            setState(_G.StateResult, false, "Mech destroyed!")
        end
        return
    end
    
    -- [[ S1 傳送點 ]] 場景設有傳送點：機甲到達且敵人已清空 → 完成本場景（載入下一場景或通關）
    if current_scene and current_scene.teleport then
        local tx = current_scene.teleport.x or 0
        local enemies_clear = true
        if entity_controller and entity_controller.enemies then
            for _, e in ipairs(entity_controller.enemies) do
                if (e.hp and e.hp > 0) or e.is_exploding then enemies_clear = false break end
            end
        end
        if enemies_clear and mech_x >= tx then
            print("LOG: Reached teleport at scene " .. current_scene_index)
            completeCurrentScene()
            return
        end
    end

    -- 7. 檢查關卡目標是否完成
    local MissionDataToUse = _G.MissionData or MissionData
    if MissionDataToUse and current_mission_id then
        local mission = MissionDataToUse[current_mission_id]
        -- [[ S1 ]] 允許場景自帶 objective 覆寫任務 objective（多場景可各有目標）
        local obj = (current_scene and current_scene.objective) or (mission and mission.objective)
        if mission and obj then
            
            -- 目標類型：打倒所有敵人
            if obj.type == "ELIMINATE_ALL" then
                if entity_controller and entity_controller.enemies then
                    local all_defeated = true
                    for _, enemy in ipairs(entity_controller.enemies) do
                        -- 仍存活、或爆炸動畫還在播（is_exploding），都不算完成——
                        -- 讓最後一個敵人的爆炸特效播完（約 1 秒）再進結算畫面
                        if (enemy.hp and enemy.hp > 0) or enemy.is_exploding then
                            all_defeated = false
                            break
                        end
                    end
                    
                    if all_defeated and #entity_controller.enemies > 0 then
                        print("MISSION SUCCESS: All enemies defeated!")
                        completeCurrentScene()
                        return
                    end
                end
            
            -- 目標類型：把石頭放到指定地點
            elseif obj.type == "DELIVER_STONE" then
                if entity_controller and entity_controller.delivery_targets and entity_controller.stones then
                    -- 檢查石頭與目標的碰撞
                    for _, stone in ipairs(entity_controller.stones) do
                        if not stone.is_placed and stone.target_id then
                            -- 找到該石頭對應的目標
                            for _, target in ipairs(entity_controller.delivery_targets) do
                                -- 排除「已飛走」與「飛行中」的目標，後者不能再接箱子
                                if target.id == stone.target_id
                                   and not target.is_completed and not target.fly_timer then
                                    -- 檢查石頭是否與目標物件碰撞
                                    if stone.x and stone.y and target.x and target.y then
                                        local stone_right = stone.x + stone.width
                                        local stone_bottom = stone.y + stone.height
                                        local target_right = target.x + target.width
                                        local target_bottom = target.y + target.height
                                        
                                        -- AABB 碰撞檢測
                                        if stone.x < target_right and stone_right > target.x and
                                           stone.y < target_bottom and stone_bottom > target.y then
                                            -- 石頭放置到目標上
                                            stone.is_placed = true
                                            table.insert(target.placed_stones, stone)
                                            print("LOG: Stone placed on target " .. target.id .. " (" .. #target.placed_stones .. "/" .. target.required_count .. ")")
                                            
                                            -- 播放目標完成音效
                                            if _G.SoundManager and _G.SoundManager.playTarget then
                                                _G.SoundManager.playTarget()
                                            end

                                            -- 釋放爪子的引用
                                            if mech_controller and mech_controller.claw_grabbed_stone == stone then
                                                mech_controller.claw_grabbed_stone = nil
                                                print("LOG: Released claw grip on placed stone")
                                            end

                                            -- [[ 2026-08-09 ]] 收滿箱子 → **帶著箱子往左上飛走**
                                            -- （取代舊的擴散圓環）。飛行與消失在
                                            -- entity_controller:updateAll 處理。
                                            -- ★ is_completed 由「飛完」時才設 —— 這裡不能設，
                                            --   繪製迴圈會跳過 is_completed 的目標，
                                            --   當幀設下去就等於目標與箱子瞬間消失、看不到飛走。
                                            if #target.placed_stones >= target.required_count then
                                                -- 先把所有箱子擺到平台上（與飛行途中同一個算法）
                                                for _, s in ipairs(target.placed_stones) do
                                                    s.x, s.y = entity_controller:stoneRestPos(target, s)
                                                end
                                                target.fly_timer = 0
                                                print("LOG: Target " .. target.id .. " full -> flying away")
                                            end
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end
                    
                    -- 檢查是否所有石頭都已放置到指定目標
                    local all_placed = true
                    for _, stone in ipairs(entity_controller.stones) do
                        if stone.target_id and not stone.is_placed then
                            all_placed = false
                            break
                        end
                    end

                    -- [[ 2026-08-09 ]] 目標還在往左上飛就先不過關（與 BOSS 爆炸同一模式：演出播完才結束）
                    local effect_playing = false
                    for _, target in ipairs(entity_controller.delivery_targets or {}) do
                        if target.fly_timer then
                            effect_playing = true
                            break
                        end
                    end

                    if all_placed and not effect_playing and #entity_controller.stones > 0 then
                        print("MISSION SUCCESS: All stones delivered to targets!")
                        completeCurrentScene()
                        return
                    end
                end

            -- [[ S5/S6 ]] 目標類型：打倒 BOSS
            elseif obj.type == "BOSS_KILL" then
                local had_boss, boss_alive = false, false
                if entity_controller and entity_controller.enemies then
                    for _, e in ipairs(entity_controller.enemies) do
                        if e.is_boss then
                            had_boss = true
                            if e.is_alive or e.is_exploding then boss_alive = true end
                        end
                    end
                end
                if had_boss and not boss_alive then
                    print("MISSION SUCCESS: Boss defeated!")
                    completeCurrentScene()
                    return
                end

            -- [[ S5 ]] 目標類型：走到定點
            elseif obj.type == "REACH" then
                local gx = current_scene and current_scene.reach and current_scene.reach.x
                if gx and (mech_x + 24) >= gx then
                    print("MISSION SUCCESS: reached the goal")
                    completeCurrentScene()
                    return
                end

            -- [[ S5 ]] 目標類型：護送/保護 NPC（MOVE 走到目標 / HOLD 撐時間；NPC 死亡=失敗）
            elseif obj.type == "PROTECT" then
                local npc = entity_controller and entity_controller.npc
                if npc then
                    if npc.is_dead or (npc.hp or 1) <= 0 then
                        print("MISSION FAILED: NPC destroyed")
                        setState(_G.StateResult, false, "The escort was destroyed!")
                        return
                    elseif npc.reached_goal or npc.protect_done then
                        print("MISSION SUCCESS: escort protected")
                        completeCurrentScene()
                        return
                    end
                end
            end
        end
    end
end

-- [[ 可讀性 ]] 畫在遊戲世界之上的黑字（提示、HUD）一律先鋪白底，
-- 否則會被深色背景（尤其天空層的黑雲、黑色地面）吃掉。
local function drawTextOnWhite(text, x, y, pad)
    pad = pad or 3
    local tw, th = gfx.getTextSize(text)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(x - pad, y - pad, tw + pad * 2, (th or 14) + pad * 2)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawText(text, x, y)
end

function StateMission.draw()
    gfx.clear(gfx.kColorWhite)
    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(font)
    
    -- 計算畫面震動偏移
    local shake_offset = 0
    if camera_shake_timer < camera_shake_duration then
        -- 正弦波震動：產生左右搖晃（增加頻率到20以加快震動）
        shake_offset = math.sin(camera_shake_timer * math.pi * 20) * camera_shake_intensity
    end
    
    -- 若對話中，先繪製對話畫面
    if dialog_active then
        print("Drawing dialog...")
        -- 上方圖片
        if dialog_image then
            pcall(function() dialog_image:draw(0, 0) end)
        end
        -- 下方對話框
        -- 滿版文字框；插圖可視區＝y < DIALOG_Y（版面理由見 state_intro.lua）
        local box_x, box_y, box_w, box_h = 0, DIALOG_Y, SCREEN_WIDTH, SCREEN_HEIGHT - DIALOG_Y
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRect(box_x, box_y, box_w, box_h)
        gfx.setColor(gfx.kColorBlack)
        gfx.drawRect(box_x, box_y, box_w, box_h)
        -- 打字機文字
        local text = dialog_lines[dialog_index] or ""
        local shown = string.sub(text, 1, math.min(#text, math.floor(typewriter_progress)))
        -- 自動斷行：在對話框矩形內換行並向下排版
        pcall(function()
            gfx.drawTextInRect(shown, box_x + 8, box_y + 6, box_w - 16, box_h - 12)
        end)
        return
    end

    -- 1. 繪製實體 (地面、障礙物、敵人) - 應用震動偏移
    if entity_controller then
        entity_controller:draw(camera_x + shake_offset) 
    end

    -- 2. 繪製機甲（使用 MechController）或爆炸動畫
    if mech_exploding then
        -- 播放爆炸動畫
        if not mech_explode_image_table then
            local ok, table_img = pcall(function()
                return playdate.graphics.imagetable.new("images/mine_explode")
            end)
            if ok and table_img then
                mech_explode_image_table = table_img
                mech_explode_frame_index = 0
                mech_explode_frame_timer = 0
                print("LOG: Loaded mech explosion animation")
            end
        end
        
        if mech_explode_image_table then
            local frame = mech_explode_image_table:getImage(mech_explode_frame_index + 1)
                          or mech_explode_image_table:getImage(1)
            if frame then
                -- ★ [[ BUGFIX 2026-08-08 ]] 原本是 frame:draw(mech_x - 25, mech_y - 25)，
                --   **漏扣 camera_x**。mech_x 是世界座標，這裡要的是螢幕座標
                --   （drawMech 會在內部扣掉，見 entity_mech_render.lua:23）。
                --   結果是鏡頭捲得越遠、爆炸偏得越遠；關卡開頭 camera_x=0 時才剛好正確，
                --   所以症狀是「有時候差很遠」。
                -- 順帶把錨點從「機體左上角」改成「機體中心」，並用實際幀尺寸算，不寫死 25。
                local ok, fw, fh = pcall(function() return frame:getSize() end)
                fw = (ok and fw) or 50
                fh = (ok and fh) or 50
                local cx = mech_x + mech_draw_w / 2 - camera_x + shake_offset
                local cy = mech_y + mech_draw_h / 2
                pcall(function() frame:draw(cx - fw / 2, cy - fh / 2) end)
            end
        end
    elseif mech_controller then
        mech_controller:drawMech(mech_x + shake_offset, mech_y, camera_x, _G.GameState.mech_grid, _G.GameState, feet_imagetable, feet_current_frame, entity_controller)
    end

    -- 2.5 [[ 前景層 ]] 畫在機體之上、HUD/操作面板之下（會擋住玩家，不會擋住 UI）
    if entity_controller and entity_controller.drawForeground then
        entity_controller:drawForeground(camera_x + shake_offset)
    end

    -- 3. [[ 版面 ]] 玩家血條已移到下方操作面板右側，成為面板的一部分
    --    （見「4. 繪製控制介面 UI」）。原本在左上角，會與 BOSS 血條的白底重疊
    --    （BOSS 那塊是 x=87~368、y=3~33）。這裡只算比例，繪製全部在第 4 段。
    local hp_percent = current_hp / max_hp

    -- [[ S3 場景武器接管 ]] 提示 / 操作指示
    -- 位置：砲台**正下方的地面**（原本在砲台上方，會被機體擋住）。
    -- 地面是純黑填充，黑字本來會看不見（見 HANDOFF §3-4），但 drawTextOnWhite 會鋪白底，
    -- 反而在黑地面上對比最強。
    -- 垂直空間：ground_y(156) ~ UI 上緣(176) 共 20px。
    -- gy+3 讓白底剛好是 156~176：上緣貼齊地面線、下緣貼齊 UI，一格不多一格不少。
    local function drawWeaponPrompt(text, world_x)
        local gy = (entity_controller and entity_controller.ground_y) or 156
        local tw = gfx.getTextSize(text)
        drawTextOnWhite(text, world_x - camera_x - tw / 2, gy + 3)
    end
    if controlling_weapon then
        drawWeaponPrompt("B:exit", controlling_weapon.x)
    elseif entity_controller then
        local near = entity_controller:weaponNear(mech_x + 24, 44)
        if near then
            drawWeaponPrompt("Press A", near.x)
        end
    end
    
    -- 3.1 繪製計時器（如果有時間限制）
    if mission_time_limit > 0 then
        local remaining_time = math.max(0, mission_time_limit - mission_elapsed_time)
        local seconds = math.floor(remaining_time)
        local time_text = string.format("TIME: %d", seconds)
        local time_text_width = gfx.getTextSize(time_text)
        local time_x = (SCREEN_WIDTH - time_text_width) / 2
        local time_y = 5
        
        -- [[ 可讀性 ]] 一律鋪底（否則黑字會被天空的黑雲吃掉）；
        -- 剩 10 秒內改為「黑底白字 ↔ 白底黑字」反相閃爍。
        -- （舊版閃爍在白底時仍用 FillWhite 畫字＝白字白底，有一半的幀文字整個消失。）
        local warn = (remaining_time <= 10)
        local invert = warn and (math.floor(mission_elapsed_time * 2) % 2 == 0)
        gfx.setColor(invert and gfx.kColorBlack or gfx.kColorWhite)
        gfx.fillRect(time_x - 5, time_y - 2, time_text_width + 10, 15)
        gfx.setColor(gfx.kColorBlack)
        if invert then
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
            gfx.drawText(time_text, time_x, time_y)
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        else
            gfx.drawText(time_text, time_x, time_y)
        end
    end
    
    -- 4. 繪製控制介面 UI（使用 MechController）
    if mech_controller then
        -- 在操作介面下方畫白色背景方塊（略大於介面）
        local ui_w = UI_GRID_COLS * UI_CELL_SIZE
        local ui_h = UI_GRID_ROWS * UI_CELL_SIZE
        local bg_margin = 6

        -- [[ 版面 ]] 玩家血條：面板右側，與面板共用同一塊白底＝視覺上是面板的一部分。
        -- 移到這裡是因為左上角會被 BOSS 血條的白底蓋住（BOSS 塊 x=87~368）。
        local hp_text = "HP" .. math.floor(current_hp) .. "/" .. max_hp
        local hp_text_w = gfx.getTextSize(hp_text)
        local hp_bar_width, hp_bar_height = 70, 10
        local hp_gap = 10                                   -- 面板與血條之間的留白
        local hp_right_pad = 3                              -- 白底右緣的留白（比左側 bg_margin 窄）
        local hp_x = UI_START_X + ui_w + hp_gap
        local hp_text_y = UI_START_Y + 4
        local hp_bar_y = hp_text_y + 18
        -- 白底右緣由「文字」決定：最長是 HP285/285＝82px，仍比血條 70px 寬
        local hp_block_w = math.max(hp_text_w, hp_bar_width)

        -- 白底一次畫完（面板 + 血條），中間不留縫
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRect(UI_START_X - bg_margin, UI_START_Y - bg_margin,
                     (hp_x + hp_block_w + hp_right_pad) - (UI_START_X - bg_margin),
                     ui_h + bg_margin * 2)
        gfx.setColor(gfx.kColorBlack)

        gfx.drawText(hp_text, hp_x, hp_text_y)
        gfx.drawRect(hp_x, hp_bar_y, hp_bar_width, hp_bar_height)
        if current_hp > 0 then
            gfx.fillRect(hp_x + 1, hp_bar_y + 1, (hp_bar_width - 2) * hp_percent, hp_bar_height - 2)
        end
        if controlling_weapon then
            -- [[ S3/美術 ]] 接管砲台的操作面板：其餘格 empty、左上 turret_control（隨 crank 轉）、
            -- 其右 canon_button（A 發射的按下/放開兩幀）。與機體面板同為 3x2、每格 32x32。
            if not turret_ui.tried then
                turret_ui.tried = true
                local function loadImg(p)
                    local ok, img = pcall(function() return playdate.graphics.image.new(p) end)
                    return ok and img or nil
                end
                turret_ui.control = loadImg("images/turret_control")
                turret_ui.empty   = loadImg("images/empty")
                local okt, tbl = pcall(function() return playdate.graphics.imagetable.new("images/canon_button") end)
                if okt and tbl then turret_ui.button = tbl end
            end
            -- 底：所有格子鋪 empty
            if turret_ui.empty then
                for r = 0, UI_GRID_ROWS - 1 do
                    for c = 0, UI_GRID_COLS - 1 do
                        pcall(function()
                            turret_ui.empty:draw(UI_START_X + c * UI_CELL_SIZE, UI_START_Y + r * UI_CELL_SIZE)
                        end)
                    end
                end
            end
            -- 左上格：旋轉控制（依 crank 絕對位置旋轉）
            if turret_ui.control then
                local rotated = turret_ui.control:rotatedImage(playdate.getCrankPosition())
                if rotated then
                    local rw, rh = rotated:getSize()
                    pcall(function()
                        rotated:draw(UI_START_X + (UI_CELL_SIZE - rw) / 2, UI_START_Y + (UI_CELL_SIZE - rh) / 2)
                    end)
                end
            end
            -- 右鄰格：A 發射按鈕（1=未按下、2=按下）
            if turret_ui.button then
                local img = turret_ui.button:getImage(turret_fire_pressed and 2 or 1)
                if img then
                    pcall(function() img:draw(UI_START_X + UI_CELL_SIZE, UI_START_Y) end)
                end
            end
        else
            -- 繪製零件操作面板（白色操作說明文字已移除）
            mech_controller:drawUI(_G.GameState.mech_stats, UI_START_X, UI_START_Y, UI_CELL_SIZE, UI_GRID_COLS, UI_GRID_ROWS)
        end
    end
    
    -- 5. 繪製調試信息
--    gfx.drawText("Mech X: " .. math.floor(mech_x), 10, SCREEN_HEIGHT - 15)

    -- [[ S10 ]] 教學覆蓋層（畫在最上層）
    if _G.Tutorial and _G.Tutorial.draw then _G.Tutorial.draw() end
end

-- 立即觸發畫面震動（用於敵人爆炸）
function StateMission.triggerScreenShake()
    camera_shake_timer = 0
end

return StateMission