-- entity_boss_parallel.lua
-- [[ §15.5a 巨大 BOSS ]] BOSS 的**平行零件制**（`part_mode = "PARALLEL"`）。2026-08-19
--
-- ★★ 與既有序列制（OVERSEER）的差別，一句話：
--   序列制＝同時只有一個零件存在，打爆才換下一個（`boss_phase` 索引）。
--   平行制＝頭與雙臂**同時活著**，各有 HP，可個別被打爆。
--   ★ 兩者共存：`part_mode` 不是 "PARALLEL" 的 BOSS 完全走舊路徑，OVERSEER 一行都沒動。
--
-- ★★★ 本檔最重要的設計決定：**頭部就是 BOSS 實體本身，手臂才是額外的實體。**
--   頭 → `enemy.x/y/width/height` 與 `enemy.hp` 直接對齊頭部
--        ＝ 既有的傷害管線、死亡爆炸、BOSS_KILL 過關判定**全部原樣沿用，一處都不用改**。
--   手臂 → 各自是一個掛在 `controller.enemies` 裡的**代理實體**（見 makeArmProxy）
--        ＝ 子彈／雷射／爆風／飛彈／石頭／近戰 6 條命中路徑**也全部原樣沿用**。
--   ⚠️ 反過來做（把三個零件都做成 BOSS 內部狀態）就得改那 6 條路徑各自的命中判定，
--      那正是 HANDOFF §3-5 說的「同一件事有多個計算點」——必漏。
--
-- 攻擊排程：BOSS 層級只有**一個 `attack_slot`**，誰的冷卻先到誰出手，
--   出手期間其他零件不動作 → GDD 要求的「雙臂攻擊時頭不發射」是這條的自然結果，
--   不需要寫成特例。

local gfx = playdate.graphics

-- ==========================================================================
-- 手臂代理實體
-- ==========================================================================

-- 手臂在 controller.enemies 裡的樣子。它只負責「被打到」這一件事：
--   update / draw 都是空的（BOSS 自己畫、自己動），傷害轉交給 BOSS。
-- ★ `is_boss` 刻意**不設** —— BOSS_KILL 過關判定是掃 `e.is_boss`，
--   手臂若被算成 BOSS，沒拆手臂就永遠過不了關。
-- ★ `type_id` 不在 EnemyData 裡 → dropTableFor 回傳 nil → 手臂不掉資源。
--   （要讓拆手臂有掉落獎勵的話，改這裡，不要改 spawnDrops。）
local function makeArmProxy(boss, arm)
    local proxy = {
        is_boss_part = true,
        type_id = "BOSS_ARM",
        parent_boss = boss,
        arm = arm,
        x = arm.x, y = arm.y, width = arm.w, height = arm.h,
        hp = arm.hp,
        is_alive = true,
        is_exploding = false,
        hit_shake_timer = 0, hit_shake_offset_x = 0,
        face_dir = -1,
    }
    -- 空實作：這些是 controller 的迴圈會呼叫的介面，不能沒有
    proxy.update = function() end
    proxy.draw = function() end
    proxy.startExplosion = function(self)
        -- 由 BOSS 統一處理（爆炸特效畫在 BOSS 身上），這裡只要不擋住流程
    end
    proxy.takeDamage = function(self, amount)
        if not amount or amount <= 0 then return false end
        if not self.is_alive then return false end
        return self.parent_boss:bossArmDamage(self.arm, amount)
    end
    return proxy
end

-- ==========================================================================
-- 初始化
-- ==========================================================================

-- 由 Enemy:initBoss 在 part_mode=="PARALLEL" 時呼叫。
-- 回傳後，spawn 端要把 e.arm_proxies 一起塞進 controller.enemies（見 entity_controller）。
function Enemy:bossInitParallel(bd, ground_y)
    local head = bd.head or {}
    self.part_mode = "PARALLEL"
    self.boss_head = head
    self.head_hp_max = head.hp or 100

    -- ★ 頭＝BOSS 本體：hp 與命中框直接指向頭部
    self.hp = self.head_hp_max
    self.attack = (head.attack and head.attack.damage) or 5

    -- 攻擊排程器狀態
    self.attack_slot = nil          -- nil＝沒人在出手
    self.slot_timer = 0
    self.actor_timers = {}          -- [actor_id] = 已冷卻秒數
    self.head_drop = 0              -- 頭部下探的當前位移（telegraph）

    -- 手臂
    self.arms = {}
    self.arm_proxies = {}
    local ad = bd.arms
    if ad and ad.mounts then
        for _, m in ipairs(ad.mounts) do
            local arm = {
                id = m.id, label = m.label or m.id,
                dx = m.dx or 0, dy = m.dy or 0,
                mirror = m.mirror and true or false,
                w = ad.w or 40, h = ad.h or 96,
                hp = ad.hp or 80, hp_max = ad.hp or 80,
                alive = true,
                -- 世界座標（每幀由 bossSyncParallelBoxes 更新）
                x = 0, y = 0,
                anim = "IDLE",      -- IDLE / RAISE / SLAM / THROW
                anim_t = 0,
            }
            table.insert(self.arms, arm)
            table.insert(self.arm_proxies, makeArmProxy(self, arm))
        end
    end

    -- 手臂圖（左右共用一套，右臂鏡射 —— §15.5a-7 的主要省圖點）
    if ad and ad.sprite then
        local ok, tbl = pcall(function() return gfx.imagetable.new(ad.sprite) end)
        if ok and tbl then self.arm_sheet = tbl end
    end

    self:bossSyncParallelBoxes()
end

-- 把頭與手臂的世界座標／命中框對齊本體。**每幀都要叫**（頭會下探、手臂會動）。
-- ★ 這是頭與手臂位置的**唯一計算點**：繪製端也讀這裡算好的值，不要各算一次。
function Enemy:bossSyncParallelBoxes()
    local head = self.boss_head or {}
    self.width  = head.w or 40
    self.height = head.h or 40
    self.x = self.boss_x + (head.dx or 0)
    self.y = self.boss_y + (head.dy or 0) + (self.head_drop or 0)
    if head.muzzle_x and head.muzzle_y then
        self.bullet_offset_x = head.muzzle_x - (head.dx or 0)
        self.bullet_offset_y = head.muzzle_y - (head.dy or 0)
    else
        self.bullet_offset_x = self.width / 2
        self.bullet_offset_y = self.height / 2
    end

    for i, arm in ipairs(self.arms or {}) do
        -- track_dx＝舉在上方時左右追著玩家移動的位移（見 bossAdvanceSlot 的 TELEGRAPH）
        arm.x = self.boss_x + arm.dx + (arm.track_dx or 0)
        arm.y = self.boss_y + arm.dy + (arm.swing_dy or 0)
        local p = self.arm_proxies[i]
        if p then p.x, p.y = arm.x, arm.y end
    end
end

-- ==========================================================================
-- 手臂受傷與破壞
-- ==========================================================================

function Enemy:bossArmDamage(arm, amount)
    if not arm.alive then return false end
    if self.boss_invuln and self.boss_invuln > 0 then return false end
    arm.hp = arm.hp - amount
    arm.hit_flash = 0.2
    if arm.hp <= 0 then
        arm.hp = 0
        arm.alive = false
        -- ★ 斷臂**整個消失**，不留殘骸擋子彈（§15.5a-8）：
        --   殘骸若留著當掩體，拆手臂反而有隱藏的壞處，那不是取捨是懲罰。
        for i, a in ipairs(self.arms) do
            if a == arm then
                local p = self.arm_proxies[i]
                if p then p.is_alive = false; p.is_exploding = false end
            end
        end
        -- 沿用既有的零件爆炸特效（mine_explode 動畫表）
        self.part_explode_x = arm.x + arm.w / 2
        self.part_explode_y = arm.y + arm.h / 2
        self.part_explode_timer = 0
        self.part_explode_duration = 0.8
        -- 出手中的那隻手被打爆 → 立刻中止它的動作，否則排程器會卡著等它演完
        if self.attack_slot and self.attack_slot.arm == arm then
            self.attack_slot = nil
        end
        if _G.SoundManager and _G.SoundManager.playExplode then _G.SoundManager.playExplode() end
        print("LOG: Boss arm destroyed: " .. tostring(arm.id))
    end
    return true
end

function Enemy:bossArmsAlive()
    local n = 0
    for _, a in ipairs(self.arms or {}) do if a.alive then n = n + 1 end end
    return n
end

-- 雙臂全爆 → 頭部狂暴（§15.5a-2：「全拆」要有代價，否則拆手臂是無腦最優解）
function Enemy:bossIsRaging()
    return (#(self.arms or {}) > 0) and (self:bossArmsAlive() == 0)
end

-- ==========================================================================
-- 攻擊排程器
-- ==========================================================================

-- 取得某個行動者這次要用的攻擊資料
local function armAttackFor(bd, arm, pick)
    local list = (bd.arms and bd.arms.attacks) or {}
    if #list == 0 then return nil end
    return list[((pick - 1) % #list) + 1]
end

function Enemy:bossUpdateParallel(dt, mech_x, mech_y, mech_width, mech_height, controller)
    local bd = self.boss_data
    local head = self.boss_head or {}

    -- 進行中的動作：推進它的階段
    if self.attack_slot then
        self:bossAdvanceSlot(dt, mech_x, mech_y, controller)
        self:bossSyncParallelBoxes()
        return
    end

    -- 沒人出手：累積各行動者的冷卻，挑一個發動
    local raging = self:bossIsRaging()
    local candidates = {}

    for _, arm in ipairs(self.arms or {}) do
        if arm.alive then
            self.actor_timers[arm.id] = (self.actor_timers[arm.id] or 0) + dt
            local atk = armAttackFor(bd, arm, arm.next_attack or 1)
            if atk and self.actor_timers[arm.id] >= (atk.cooldown or 3.0) then
                table.insert(candidates, { arm = arm, atk = atk })
            end
        end
    end

    self.actor_timers.HEAD = (self.actor_timers.HEAD or 0) + dt
    local hatk = head.attack
    if hatk then
        local cd = hatk.cooldown or 2.5
        if raging and head.rage then cd = cd * (head.rage.cooldown_mult or 0.5) end
        if self.actor_timers.HEAD >= cd then
            table.insert(candidates, { head = true, atk = hatk })
        end
    end

    if #candidates == 0 then
        self:bossSyncParallelBoxes()
        return
    end

    -- ★ 隨機挑一個 —— 不做優先權。手臂與頭用不同的冷卻長度來分配出手比重，
    --   在這裡加優先權只會變成「另一個調節出手頻率的地方」（兩個計算點）。
    local pick = candidates[math.random(1, #candidates)]
    self.attack_slot = {
        arm = pick.arm, is_head = pick.head, atk = pick.atk,
        phase = "TELEGRAPH", t = 0,
    }
    if pick.arm then
        pick.arm.anim = (pick.atk.type == "THROW") and "THROW" or "RAISE"
        pick.arm.anim_t = 0
    end
    self:bossSyncParallelBoxes()
end

-- 動作三段：TELEGRAPH（預告，看得見要來了）→ STRIKE（生效的那一瞬間）→ RECOVER（收手）
function Enemy:bossAdvanceSlot(dt, mech_x, mech_y, controller)
    local slot = self.attack_slot
    local atk = slot.atk
    slot.t = slot.t + dt

    local tele = atk.telegraph or 0.7
    local recover = atk.recover or 0.5

    if slot.phase == "TELEGRAPH" then
        -- 頭部：下探（§15.5a-3 —— 既是開火預告，也讓水平槍打得到）
        if slot.is_head then
            local drop = (self.boss_head.lower_dy or 0)
            self.head_drop = drop * math.min(1, slot.t / math.max(0.01, tele))
        elseif slot.arm then
            local arm = slot.arm
            arm.swing_dy = -(atk.raise or 20) * math.min(1, slot.t / math.max(0.01, tele))
            -- ★★ 舉在上方時**左右追著玩家移動**（2026-08-19 修正）。
            --   固定位置的拳頭只要站在兩拳之間就永遠打不到，那不是難度是失效。
            --   ★ 移動範圍刻意夾在**約一個本體寬**之內（track_range）——
            --     無限追蹤等於必中，玩家就沒有「走出打擊範圍」這個解法了。
            if atk.track then
                local half = (atk.track_range or self.boss_body_w or 130) / 2
                -- ★ aim_mx/aim_my＝玩家中心，由 updateBoss 每幀算一次。
                --   這裡不要自己用 mech_x 再算一次（那是左緣、不是中心）。
                local want = (self.aim_mx or self.boss_x) - self.boss_x - arm.dx - arm.w / 2
                if want > half then want = half elseif want < -half then want = -half end
                local cur = arm.track_dx or 0
                local step = (atk.track_speed or 90) * dt
                local diff = want - cur
                if math.abs(diff) <= step then cur = want
                else cur = cur + (diff > 0 and step or -step) end
                arm.track_dx = cur
            end
        end
        if slot.t >= tele then
            -- 手臂：進入**發招預告**（停止追蹤、地面閃爍落點），之後才砸下來
            if slot.arm and (atk.warn or 0) > 0 then
                slot.phase = "WARN"
            else
                slot.phase = "STRIKE"
                self:bossStrike(slot, mech_x, mech_y, controller)
            end
            slot.t = 0
        end

    elseif slot.phase == "WARN" then
        -- 短暫的發招預告：手臂停在上方不再追蹤，落點在地面閃爍（繪製端讀 attack_slot）。
        -- ★ 這一段就是玩家的反應窗口 —— 追蹤停下來的那一刻才是「可以閃了」。
        if slot.t >= (atk.warn or 0.35) then
            slot.phase = "STRIKE"
            slot.t = 0
            self:bossStrike(slot, mech_x, mech_y, controller)
        end

    elseif slot.phase == "STRIKE" then
        if slot.arm then slot.arm.swing_dy = (atk.follow_through or 10) end
        if slot.t >= (atk.strike_time or 0.15) then
            slot.phase = "RECOVER"
            slot.t = 0
        end

    else -- RECOVER
        local k = 1 - math.min(1, slot.t / math.max(0.01, recover))
        if slot.is_head then
            self.head_drop = (self.boss_head.lower_dy or 0) * k
        elseif slot.arm then
            slot.arm.swing_dy = (atk.follow_through or 10) * k
            -- 收手時手臂滑回肩膀原位（不留在打擊點，否則下一輪的追蹤起點會漂移）
            slot.arm.track_dx = (slot.arm.track_dx or 0) * k
        end
        if slot.t >= recover then
            if slot.is_head then
                self.head_drop = 0
                self.actor_timers.HEAD = 0
            elseif slot.arm then
                slot.arm.swing_dy = 0
                slot.arm.track_dx = 0
                slot.arm.anim = "IDLE"
                self.actor_timers[slot.arm.id] = 0
                -- 下次換另一種攻擊（SLAM ↔ THROW 輪替）
                slot.arm.next_attack = (slot.arm.next_attack or 1) + 1
            end
            self.attack_slot = nil
        end
    end
end

-- 拳擊的傷害半徑。★ **由手臂寬度決定**（2026-08-19 使用者拍板）：
--   打擊範圍就是那隻拳頭的寬度再加一點點，不是一大片區域 ——
--   範圍太大的話「追著你移動」就沒有意義了，站哪裡都一樣被打到。
-- ★ 這是半徑的唯一計算點：命中判定與地面預告特效都讀它。
function Enemy:bossSlamRadius(arm, atk)
    if atk.radius then return atk.radius end          -- 明確指定就照指定
    return (arm.w or 30) / 2 + (atk.radius_pad or 8)
end

-- 攻擊真正生效的那一瞬間
function Enemy:bossStrike(slot, mech_x, mech_y, controller)
    local atk = slot.atk

    if slot.is_head then
        -- 頭部射擊：沿用序列制的 VOLLEY（同一個 Enemy:fire 管線）
        local n = atk.n or 1
        if self:bossIsRaging() and self.boss_head.rage then
            n = self.boss_head.rage.n or n
        end
        self.attack = atk.damage or 5
        self.projectile_speed_mult = atk.speed_mult or 30
        self.projectile_grav_mult = atk.grav_mult or 18
        for i = 1, n do
            local off = 0
            if n > 1 then off = (i - (n + 1) / 2) * 50 end
            self:fire((mech_x or self.boss_x) + off, controller)
        end
        return
    end

    local arm = slot.arm
    if not arm then return end

    if atk.type == "SLAM" then
        -- 拳擊地面：★ **不改變地形**（§15.5a-5 拍板）。
        --   crumble 塌陷不可逆，打久了戰場全是坑，後期是玩家被自己的戰場拖死。
        --   只做「落點周圍的範圍傷害 + 畫面震動」。
        local gx = arm.x + arm.w / 2
        local gy = self.boss_ground_y or (arm.y + arm.h)
        self.pending_slam = { x = gx, y = gy, radius = self:bossSlamRadius(arm, atk),
                              damage = atk.damage or 10, t = 0 }
        if controller and controller.addBlastVisual then
            controller:addBlastVisual(gx, gy - 8)
        end
        if _G.SoundManager and _G.SoundManager.playExplode then _G.SoundManager.playExplode() end

    elseif atk.type == "THROW" then
        -- 投擲石頭：沿用既有的 Stone。owner="BOSS" → 飛行中只傷玩家，
        -- 落地後 Stone:update 會把 owner 清回 nil，就變成玩家可以撿去丟回來的彈藥。
        --
        -- ★★ 2026-08-19 修正：舊版是「固定速度往玩家方向丟」，結果**一律落在玩家前方的地面**，
        --   打不到人。現在改成**算彈道**：解出「T 幀後剛好落在玩家身上」的初速。
        --   ⚠️ Stone 的物理是**逐幀**的（vy += g 之後 y += vy，不是 dt 積分），所以這裡
        --     用的是離散解，不是連續運動公式：
        --         x_T = x0 + T·vx
        --         y_T = y0 + T·vy0 + g·T·(T+1)/2
        --     用連續版的 ½gT² 會系統性丟短（少了 gT/2 那一項）。
        if controller and Stone then
            local sx = arm.x + arm.w / 2
            local sy = arm.y
            local stone = Stone:init(sx, sy, self.boss_ground_y or sy, nil, atk.image)
            stone.mech_damage = atk.damage or 12
            -- ★ 臨時石頭：落地 3 秒後消失（見 Stone 的 despawn_time 註解）
            stone.despawn_time = atk.despawn

            local tx = self.aim_mx or (self.boss_x - 150)
            local ty = self.aim_my or (self.boss_ground_y or sy)
            local dx = tx - sx
            local dy = ty - sy

            -- 飛行幀數：距離越遠飛越久，但夾在上下限之間。
            -- ★ 上限＝丟得太慢會變成「看得到、走開就好」；下限＝太快就成了無法反應的直線。
            local vmax = atk.speed_max or 9
            local T = math.abs(dx) / vmax
            local tmin, tmax = (atk.min_frames or 22), (atk.max_frames or 55)
            if T < tmin then T = tmin elseif T > tmax then T = tmax end

            local g = (controller.GRAVITY or 0.5)
            local vx = dx / T
            local vy = (dy - g * T * (T + 1) / 2) / T
            -- 一點點散布：完全精確＝每一發必中，玩家會覺得只能硬吃
            local spread = atk.spread or 0.6
            vx = vx + (math.random() * 2 - 1) * spread

            stone:launch(vx, vy, "BOSS")
            table.insert(controller.stones, stone)
        end
    end
end

-- 拳擊震波：在 STRIKE 之後由 updateBoss 每幀呼叫一次，回傳這一幀要對玩家造成的傷害。
-- ★ 一次性：命中後（或超時）就清掉，不會持續扣血。
function Enemy:bossConsumeSlam(mech_x, mech_y, mech_w, mech_h)
    local s = self.pending_slam
    if not s then return 0 end
    self.pending_slam = nil
    if not mech_x then return 0 end
    -- 以「玩家腳底中心」到落點的水平距離判定 —— 震波沿地面傳，不是球形爆炸
    local px = mech_x + (mech_w or 48) / 2
    local py = mech_y and (mech_y + (mech_h or 32)) or s.y
    if math.abs(px - s.x) <= s.radius and math.abs(py - s.y) <= 60 then
        return s.damage
    end
    return 0
end

-- ==========================================================================
-- 繪製
-- ==========================================================================

-- 巨大 BOSS 的繪製。**沒有圖也能玩** —— 缺圖時全部走程式繪製佔位，
-- 與 drop / 耐久標記同一個慣例（放圖即自動生效，不必回頭改程式）。
function Enemy:bossDrawParallel(camera_x)
    local g = gfx
    local bd = self.boss_data
    local bx = self.boss_x - camera_x + (self.hit_shake_offset_x or 0)
    local by = self.boss_y
    local head = self.boss_head or {}

    -- 本體（上半身）
    local body_drawn = false
    if self.boss_sheet and bd.cell_body then
        local img = self.boss_sheet:getImage(bd.cell_body)
        if img then pcall(function() img:draw(bx, by) end); body_drawn = true end
    end
    if not body_drawn then
        g.setColor(g.kColorWhite)
        g.fillRect(bx, by, self.boss_body_w, self.boss_body_h)
        g.setColor(g.kColorBlack)
        g.drawRect(bx, by, self.boss_body_w, self.boss_body_h)
    end

    -- 手臂（左右共用一套圖，mirror 的那隻水平鏡射）
    for _, arm in ipairs(self.arms or {}) do
        if arm.alive then
            -- ★★ 讀 arm.x/arm.y（bossSyncParallelBoxes 算好的世界座標），
            --   **不要**在這裡用 arm.dx 重算 —— 那樣會漏掉 track_dx，
            --   結果就是「命中框左右移動、圖卻只上下動」。
            --   （2026-08-19 實際踩過這個 bug；HANDOFF §3-5：同一個值有兩個計算點。）
            local ax = arm.x - camera_x + (self.hit_shake_offset_x or 0)
            local ay = arm.y
            local drawn = false
            if self.arm_sheet then
                local idx = (arm.anim == "IDLE") and 1 or 2
                local img = self.arm_sheet:getImage(idx)
                if img then
                    local flip = arm.mirror and g.kImageFlippedX or g.kImageUnflipped
                    pcall(function() img:draw(ax, ay, flip) end)
                    drawn = true
                end
            end
            if not drawn then
                g.setColor(g.kColorWhite); g.fillRect(ax, ay, arm.w, arm.h)
                g.setColor(g.kColorBlack); g.drawRect(ax, ay, arm.w, arm.h)
                -- 佔位的「拳頭」：下端一個實心塊，讓揮動看得出來
                g.fillRect(ax + 4, ay + arm.h - 18, arm.w - 8, 14)
            end
            -- 受擊閃爍
            if arm.hit_flash and arm.hit_flash > 0 then
                arm.hit_flash = arm.hit_flash - 1 / 30
                if (math.floor(playdate.getCurrentTimeMilliseconds() / 50) % 2) == 0 then
                    g.setColor(g.kColorXOR); g.fillRect(ax, ay, arm.w, arm.h)
                    g.setColor(g.kColorBlack)
                end
            end
        end
    end

    -- [[ 發招預告 ]] 手臂舉在上方、追蹤停止的那一段：地面落點閃爍。
    -- ★ 只用本專案已有先例的原語（fillRect / fillTriangle / drawLine），
    --   1-bit 上先鋪白再畫黑，才不會被深色背景吃掉（§3-4）。
    local slot = self.attack_slot
    if slot and slot.phase == "WARN" and slot.arm then
        local arm = slot.arm
        local gx = arm.x - camera_x + arm.w / 2
        local gy = (self.boss_ground_y or (by + self.boss_body_h))
        local r = self:bossSlamRadius(arm, slot.atk)   -- 與命中判定同一個計算點
        if (math.floor(playdate.getCurrentTimeMilliseconds() / 70) % 2) == 0 then
            -- 震波範圍：地面上的一條粗線
            g.setColor(g.kColorWhite); g.fillRect(gx - r, gy - 5, r * 2, 6)
            g.setColor(g.kColorBlack); g.fillRect(gx - r, gy - 3, r * 2, 2)
            -- 落點：向下的箭頭（與序列制的弱點提示同一種語彙）
            local ay = gy - 30
            g.setColor(g.kColorWhite); g.fillTriangle(gx - 9, ay - 11, gx + 9, ay - 11, gx, ay + 3)
            g.setColor(g.kColorBlack); g.fillTriangle(gx - 7, ay - 9, gx + 7, ay - 9, gx, ay + 1)
        end
    end

    -- 頭（下探時整顆往下移；self.y 已經算進 head_drop，這裡直接用命中框座標畫）
    local hx = bx + (head.dx or 0)
    local hy = by + (head.dy or 0) + (self.head_drop or 0)
    local head_drawn = false
    if self.boss_sheet then
        local cell = head.cell
        if (self.head_drop or 0) > 0 and head.cell_fire then cell = head.cell_fire end
        if cell then
            local img = self.boss_sheet:getImage(cell)
            -- ★★ 頭的格子是**整張本體尺寸的畫布、只畫頭、其餘透明**（與 BOSS1 的
            --   「各格原位對齊」同一個慣例），所以要畫在**本體原點**，不是 head.dx/dy。
            --   下探只加 head_drop —— 整格往下移，等於只有頭往下移。
            --   ⚠️ imagetable 的每一格尺寸都相同，不可能一格 130×150、另一格 40×34；
            --     畫在 (hx,hy) 的話整顆頭會再被推開 head.dx，對不上（2026-08-19 修）。
            --   head.dx/dy/w/h 仍然是**命中框**，那個不變。
            if img then
                pcall(function() img:draw(bx, by + (self.head_drop or 0)) end)
                head_drawn = true
            end
        end
    end
    if not head_drawn then
        g.setColor(g.kColorBlack)
        g.fillRect(hx, hy, head.w or 40, head.h or 40)
        -- 佔位的「眼」：白色橫槓，一眼看得出是頭而且朝左
        g.setColor(g.kColorWhite)
        g.fillRect(hx + 4, hy + (head.h or 40) / 3, (head.w or 40) / 2, 5)
        g.setColor(g.kColorBlack)
    end

    -- 狂暴提示：雙臂全爆後頭部持續閃動外框
    if self:bossIsRaging() and (math.floor(playdate.getCurrentTimeMilliseconds() / 120) % 2) == 0 then
        g.setColor(g.kColorBlack); g.setLineWidth(2)
        g.drawRect(hx - 4, hy - 4, (head.w or 40) + 8, (head.h or 40) + 8)
        g.setLineWidth(1)
    end
end

-- 血條：平行制沒有「n/3」這回事（§15.5a-1）。
-- 主血條＝頭部；手臂**不給血條**，改用外觀受損表現，順便省掉一組 UI。
-- 只在標題後面附一個 ARMS 2/2 的計數，讓「拆手臂是選擇」這件事看得見。
function Enemy:drawBossHpBarParallel()
    local g = gfx
    local ratio = math.max(0, math.min(1, (self.hp or 0) / (self.head_hp_max or 1)))
    local bw, bh = 220, 8
    local bx = (400 - bw) / 2
    local by = 22
    local title = (self.boss_data.name or "BOSS") .. "  [" .. (self.boss_head.label or "HEAD") .. "]"
    local n_arms = #(self.arms or {})
    if n_arms > 0 then
        title = title .. "  ARMS " .. self:bossArmsAlive() .. "/" .. n_arms
    end

    -- [[ 可讀性 ]] 先鋪白底（與序列制血條同一套處理：上方會被天空層的黑雲吃掉）
    local tw = g.getTextSize(title)
    local pad = 3
    local top = by - 16
    local block_w = math.max(tw, bw) + pad * 2
    local block_h = (by + bh) - top + pad * 2
    g.setColor(g.kColorWhite)
    g.fillRect(bx - pad, top - pad, block_w, block_h)

    g.setColor(g.kColorBlack)
    g.drawText(title, bx, top)
    g.drawRect(bx, by, bw, bh)
    g.fillRect(bx, by, math.floor(bw * ratio), bh)
end
