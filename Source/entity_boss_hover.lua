-- entity_boss_hover.lua
-- [[ §15.5c 懸停制 BOSS ]] `part_mode = "HOVER"`。2026-09-25
--
-- ★★ 一句話說清楚它與另外兩套的差別：
--   序列制（OVERSEER）＝一次只有一個零件，打爆換下一個。
--   平行制（COLOSSUS）＝頭與雙臂同時活著，各有 HP，全爆會狂暴。
--   懸停制（本檔）＝**本體一條血**，外掛數個**打得壞、但過一段時間自己修好**的「砲塔」。
--     砲塔不是過關進度 —— 打壞它換到的是一段安靜期，所以它是**取捨**：
--     花彈藥拆砲塔，還是把火力全押在本體上。
--
-- ★★ 本檔是**兩隻 BOSS 共用**的（2026-09-25 從 BOSS4 專用改成資料驅動）：
--     BOSS4 GUNSHIP：機槍＋炸彈＋投擲 crate。
--     BOSS3 COMET  ：機槍＋小型炸彈＋追蹤火箭，另外有「出畫→衝回來」的飛行。
--   「機槍的行為兩隻相同」是使用者的要求 → 所以**不複製一份程式**，
--   而是把可打壞部件抽成 `bd.turrets` 清單，兩邊填資料就好。
--
-- ★★ 沿用既有管線的地方（都不必改 controller）：
--   本體 → `enemy.x/y/width/height` 與 `enemy.hp` 對齊機身命中框，
--          既有的傷害、死亡爆炸、BOSS_KILL 過關判定原樣沿用。
--   砲塔 → 各自一個掛在 `controller.enemies` 裡的代理實體（欄位名沿用 `arm_proxies`）。
--   爆風 → `controller:triggerEnemyBlast`（敵人專用，只打玩家）。
--   震動 → `controller:requestScreenShake`。
--   擊退 → `controller.mech_push_x`（RAMMER 已做好的管線）。
--   crate → `controller.stones`（Stone），落地後轉中性給玩家撿。

local gfx = playdate.graphics

-- ==========================================================================
-- 砲塔代理實體（讓 6 條命中路徑原樣打得到它）
-- ==========================================================================
-- ★ 與平行制的手臂代理同一套做法。`is_boss` 刻意不設 —— 設了的話沒拆砲塔就過不了關。
local function makeTurretProxy(boss, turret)
    local proxy = {
        is_boss_part = true,
        type_id = "BOSS_TURRET",
        parent_boss = boss,
        turret = turret,
        x = 0, y = 0, width = 1, height = 1,
        hp = turret.hp_max,
        is_alive = true,
        is_exploding = false,
        hit_shake_timer = 0, hit_shake_offset_x = 0,
        face_dir = -1,
        -- ★ 必填：controller 的接觸傷害分支會讀 attack，沒有就是 nil 做算術整個崩潰。
        --   0＝碰到砲塔不扣血（它是靠子彈打人的）。
        attack = 0,
    }
    proxy.update = function() end
    proxy.draw = function() end
    proxy.startExplosion = function() end
    proxy.takeDamage = function(self, amount)
        if not amount or amount <= 0 then return false end
        if not self.is_alive then return false end
        return self.parent_boss:hoverTurretDamage(self.turret, amount)
    end
    return proxy
end

-- 把某一格裁成「軸心置中」的方形小圖，供 drawRotated 繞軸心旋轉。
-- ★ 與 COLOSSUS 的做法相同（見 entity_boss_parallel 的 rigPivotCell）。
local function pivotCell(sheet, cell, px, py, size)
    local src = sheet and sheet:getImage(cell)
    if not src then return nil end
    local ok, buf = pcall(function() return gfx.image.new(size, size) end)
    if not (ok and buf) then return nil end
    gfx.pushContext(buf)
    gfx.clear(gfx.kColorClear)
    src:draw(-(px - size / 2), -(py - size / 2))
    gfx.popContext()
    return buf
end

-- ==========================================================================
-- 初始化
-- ==========================================================================
function Enemy:bossInitHover(bd, ground_y)
    self.part_mode = "HOVER"
    local hv = bd.hover or {}
    local rig = bd.rig or {}

    self.hover = hv
    self.hover_rig = rig

    -- 本體：一條血，命中框＝機身實際範圍（不是整張畫布）
    self.hp = bd.hp or 200
    self.hp_max = self.hp
    self.body_box = bd.body_box or { dx = 0, dy = 0, w = bd.body_w or 64, h = bd.body_h or 64 }

    -- 懸停：以出生點為中心左右飄移；base_y＝機體頂端距畫面上緣
    self.boss_y = hv.base_y or 10
    self.hover_dir = -1
    self.hover_t = 0
    self.hover_origin_x = self.boss_x
    self.alt_off = 0

    -- [[ 砲塔 ]] 資料驅動：每一項都是「可打壞、會自己修好」的部件
    self.turrets = {}
    self.turret_by_id = {}
    self.arm_proxies = {}            -- ★ 欄位名沿用 → spawn 端不必改
    local size = math.max(bd.body_w or 120, bd.body_h or 120)
    for _, td in ipairs(bd.turrets or {}) do
        local t = {
            id = td.id, label = td.label or td.id,
            data = td,
            hp_max = td.hp or 60, hp = td.hp or 60,
            alive = true, repair_t = 0,
            angle = td.rest_angle or 0,   -- 相對「水平朝左」，正=順時針(往上)
        }
        t.img = pivotCell(self.boss_sheet, td.cell, td.pivot_x or 0, td.pivot_y or 0, size)
        t.proxy = makeTurretProxy(self, t)
        table.insert(self.turrets, t)
        self.turret_by_id[t.id] = t
        table.insert(self.arm_proxies, t.proxy)
    end

    -- 出招排程
    self.atk_timer = 0
    self.atk_wait = self:hoverNextWait()
    self.atk = nil              -- 進行中的招式
    self.last_atk = nil         -- 上一招（不連續的招式要看它）

    -- 自己管理的飛行物（crate 走 controller 的 stones 管線）
    self.bombs = {}             -- 大炸彈（BOSS4）
    self.sbombs = {}            -- 小型炸彈（BOSS3）
    self.rockets = {}           -- 追蹤火箭（BOSS3）

    -- [[ 推進器煙霧 ]] 純程式特效，不需要圖
    self.smoke = {}
    self.smoke_t = 0

    -- [[ 飛行 ]] 出畫→衝回來（BOSS3 保留 COMET 的飛行感；沒填 hover.dash 就不會發生）
    self.fly_state = "CRUISE"
    self.fly_t = 0
    self.fly_wait = self:hoverNextDashWait()

    -- 機腹炸彈那一格（BOSS4）：投下去的彈體就是裁這一塊來畫
    local bmb = rig.bomb
    if bmb then
        local bcx = ((bmb.x0 or 0) + (bmb.x1 or 0)) / 2
        local bcy = ((bmb.y0 or 0) + (bmb.y1 or 0)) / 2
        self.bomb_img = pivotCell(self.boss_sheet, bmb.cell, bcx, bcy, 64)
    end

    self:hoverSyncBoxes()
end

-- 下一次出招的等待秒數
function Enemy:hoverNextWait()
    local a = (self.boss_data.attacks or {})
    local lo, hi = a.interval_min or 2.0, a.interval_max or 4.0
    return lo + math.random() * (hi - lo)
end

-- 下一次「出畫→衝回來」的等待秒數
function Enemy:hoverNextDashWait()
    local d = (self.hover or {}).dash
    if not d then return math.huge end
    local lo, hi = d.interval_min or 9, d.interval_max or 15
    return lo + math.random() * (hi - lo)
end

-- 本體與砲塔的世界座標／命中框。**每幀都要叫**（機體會飄、砲塔會轉）。
-- ★ 這是位置的唯一計算點：繪製端讀同一組值。
function Enemy:hoverSyncBoxes()
    local b = self.body_box
    self.x = self.boss_x + b.dx
    self.y = self.boss_y + b.dy
    self.width = b.w
    self.height = b.h

    for _, t in ipairs(self.turrets or {}) do
        local bx = t.data.box or {}
        local p = t.proxy
        if p then
            p.x = self.boss_x + (bx.dx or 0)
            p.y = self.boss_y + (bx.dy or 0)
            p.width = bx.w or 16
            p.height = bx.h or 16
            p.is_alive = t.alive
            p.hp = t.hp
        end
    end
end

-- ==========================================================================
-- 砲塔：受傷 / 打壞 / 修好
-- ==========================================================================
function Enemy:hoverTurretDamage(t, amount)
    if not t.alive then return false end
    if self.boss_invuln and self.boss_invuln > 0 then return false end
    t.hp = t.hp - amount
    t.hit_flash = 0.25
    if t.hp <= 0 then
        t.hp = 0
        t.alive = false
        t.repair_t = 0
        t.break_fx = 0.6                 -- 打壞瞬間的爆點特效時間
        -- 正在用這座砲塔出招就中斷（都壞了還在射會很怪）
        local A = (self.boss_data.attacks or {})
        if self.atk and (A[self.atk.kind] or {}).needs == t.id then self.atk = nil end
        print("LOG: BOSS turret destroyed: " .. tostring(t.id))
    end
    return true
end

function Enemy:hoverUpdateTurrets(dt, mech_x, mech_y, mech_width, mech_height)
    for _, t in ipairs(self.turrets or {}) do
        local td = t.data
        -- 瞄準：以軸心為中心朝玩家轉，夾在資料給的角度範圍內
        -- ★ 靜止姿勢＝水平朝左。螢幕座標下 atan2 增加＝順時針，所以「相對朝左的角度」＝ a − 180。
        if td.aim and mech_x then
            local pvx = self.boss_x + (td.pivot_x or 0)
            local pvy = self.boss_y + (td.pivot_y or 0)
            local tx = mech_x + (mech_width or 48) / 2
            local ty = mech_y and (mech_y + (mech_height or 32) / 2) or pvy
            local a = math.deg(math.atan(ty - pvy, tx - pvx))
            local rel = a - 180
            while rel > 180 do rel = rel - 360 end
            while rel < -180 do rel = rel + 360 end
            local lo = td.aim.min or -45
            local hi = td.aim.max or 45
            if rel < lo then rel = lo elseif rel > hi then rel = hi end
            t.angle = rel
        end

        -- 損壞後的自動修復
        if not t.alive then
            t.repair_t = (t.repair_t or 0) + dt
            if t.break_fx and t.break_fx > 0 then t.break_fx = t.break_fx - dt end
            if t.repair_t >= (td.repair_time or 60) then
                t.alive = true
                t.hp = t.hp_max
                t.repair_flash = 0.8
                print("LOG: BOSS turret repaired: " .. tostring(t.id))
            end
        elseif t.repair_flash and t.repair_flash > 0 then
            t.repair_flash = t.repair_flash - dt
        end
        if t.hit_flash and t.hit_flash > 0 then t.hit_flash = t.hit_flash - dt end
    end
end

-- 砲塔的槍口（世界座標）與方向。★ 唯一計算點：發射與繪製都讀這裡。
function Enemy:hoverTurretAim(t)
    local td = t.data
    local pvx = self.boss_x + (td.pivot_x or 0)
    local pvy = self.boss_y + (td.pivot_y or 0)
    local ox = (td.muzzle_x or 0) - (td.pivot_x or 0)
    local oy = (td.muzzle_y or 0) - (td.pivot_y or 0)
    local len = math.sqrt(ox * ox + oy * oy)
    local rad = math.rad(180 + (t.angle or 0))
    local dx, dy = math.cos(rad), math.sin(rad)
    return pvx + dx * len, pvy + dy * len, dx, dy, pvx, pvy
end

-- ==========================================================================
-- 更新
-- ==========================================================================
function Enemy:bossUpdateHover(dt, mech_x, mech_y, mech_width, mech_height, controller)
    local bd = self.boss_data
    local hv = self.hover or {}

    self.hover_t = (self.hover_t or 0) + dt

    -- [[ 飛行：出畫 → 衝回來 ]]（BOSS3；沒填 hover.dash 的 BOSS 完全不會進來）
    if self:hoverUpdateDash(dt, mech_x, mech_y, mech_width, mech_height, controller) then
        self:hoverUpdateTurrets(dt, mech_x, mech_y, mech_width, mech_height)
        self:hoverUpdateSmoke(dt)
        self:hoverUpdateShots(dt, mech_x, mech_y, mech_width, mech_height, controller)
        self:hoverSyncBoxes()
        return                           -- 衝刺中不做巡邏與出招
    end

    -- [[ 懸停 ]] 緩慢左右飄移。★ 不套重力（它是飛的）
    -- ★★ 投彈時不巡邏，改成朝投彈點靠過去（見 BOMB 分支）
    local seek = nil
    if self.atk and self.atk.kind == "BOMB" and not self.atk.done then
        seek = self:hoverBombSeekX(controller)
    end
    if seek then
        local B = (bd.attacks or {}).BOMB or {}
        local d = seek - self.boss_x
        local step = (B.approach_speed or 60) * dt
        if math.abs(d) <= step then self.boss_x = seek
        else self.boss_x = self.boss_x + (d > 0 and step or -step) end
    else
        local nx = self.boss_x + self.hover_dir * (hv.speed or 14) * dt
        if math.abs(nx - self.hover_origin_x) > (hv.range or 110) then
            self.hover_dir = -self.hover_dir
        else
            self.boss_x = nx
        end
    end

    -- [[ 高度 ]] 待機浮動 ＋ 出招前的爬升（漸進，不是瞬移）
    local want_alt = 0
    if self.atk and self.atk.kind == "BOMB" and not self.atk.done then
        want_alt = -(hv.bomb_climb or 34)
    elseif #(self.bombs or {}) > 0 then
        -- ★ 炸彈還在空中就維持高度：爆炸圖是 50×50 以爆心置中，低空會整個疊在機體上，
        --   看起來像「炸到自己」（實測血量沒掉 —— 是畫面問題，不是判定問題）。
        want_alt = -(hv.bomb_climb or 34)
    elseif self.atk and self.atk.kind == "BLOCK" and not self.atk.done then
        want_alt = -(hv.crate_climb or 26)
    end
    local cur = self.alt_off or 0
    local step = (hv.climb_speed or 60) * dt
    if math.abs(want_alt - cur) <= step then cur = want_alt
    else cur = cur + ((want_alt > cur) and step or -step) end
    self.alt_off = cur
    self.boss_y = (hv.base_y or 10) + cur
        + math.sin(self.hover_t * (hv.bob_speed or 0.5) * math.pi * 2) * (hv.bob_amp or 5)

    -- ★★ 玩家還沒進到 BOSS 場景前不出手：與序列制／平行制同一條規則，
    --   雙方都在畫面上才動作，畫面外不偷打。只擋出招，飄移照常。
    -- ⚠️ 夾畫面**一定要放在這道閘之後**：放前面的話，還沒交戰就會被夾進相機視野，
    --   等於 BOSS 一開場就自己飛到玩家面前（2026-09-25 實測踩到）。
    do
        local cam = (controller and controller.camera_x) or 0
        local bb = self.body_box
        local boss_on = (self.boss_x + bb.dx + bb.w > cam) and (self.boss_x + bb.dx < cam + 400)
        local mech_on = mech_x and (mech_x + (mech_width or 48) > cam) and (mech_x < cam + 400)
        if not (boss_on and mech_on) then
            self.atk = nil
            self.atk_timer = 0          -- 入畫後從完整的間隔重新數（不會一進場就被打）
            self:hoverUpdateTurrets(dt, mech_x, mech_y, mech_width, mech_height)
            self:hoverUpdateSmoke(dt)
            self:hoverUpdateCrate(dt, controller)
            self:hoverUpdateShots(dt, mech_x, mech_y, mech_width, mech_height, controller)
            self:hoverSyncBoxes()
            return
        end
    end

    -- 交戰中才夾在畫面內（相機停捲時飄出去＝看不見的東西在打你）
    do
        local cam = (controller and controller.camera_x) or 0
        local b = self.body_box
        local margin = hv.screen_margin or 8
        local lo = cam + margin - b.dx
        local hi = cam + 400 - margin - b.dx - b.w
        if self.boss_x < lo then self.boss_x = lo; self.hover_dir = 1 end
        if self.boss_x > hi then self.boss_x = hi; self.hover_dir = -1 end
    end

    self:hoverUpdateTurrets(dt, mech_x, mech_y, mech_width, mech_height)
    self:hoverUpdateSmoke(dt)

    -- [[ 出招 ]] 進行中的招式優先推進，沒有才數冷卻挑下一招
    if self.atk then
        self:hoverAdvanceAttack(dt, mech_x, mech_y, mech_width, mech_height, controller)
    else
        self.atk_timer = (self.atk_timer or 0) + dt
        if self.atk_timer >= (self.atk_wait or 3) then
            self.atk_timer = 0
            self.atk_wait = self:hoverNextWait()
            self:hoverPickAttack(controller)
        end
    end

    self:hoverUpdateCrate(dt, controller)
    self:hoverUpdateShots(dt, mech_x, mech_y, mech_width, mech_height, controller)
    self:hoverSyncBoxes()
end

-- [[ 飛行 ]] 出畫 → 停一下 → 高速衝回來。回傳 true＝這一幀由飛行接管。
-- ★ 這是 COMET 舊版「飛行感」的保留（使用者拍板）：它平常只是慢慢飄的空中砲台，
--   偶爾來一次橫貫畫面的衝刺，戰鬥節奏才不會從頭到尾一個樣。
function Enemy:hoverUpdateDash(dt, mech_x, mech_y, mech_w, mech_h, controller)
    local D = (self.hover or {}).dash
    if not D then return false end
    local cam = (controller and controller.camera_x) or 0
    local b = self.body_box

    if self.fly_state == "CRUISE" then
        self.fly_t = (self.fly_t or 0) + dt
        if self.fly_t >= (self.fly_wait or math.huge) then
            self.fly_t = 0
            self.fly_state = "EXIT"
            self.atk = nil
        end
        return false

    elseif self.fly_state == "EXIT" then
        -- 往右飛出畫面
        self.boss_x = self.boss_x + (D.exit_speed or 220) * dt
        if self.boss_x + b.dx > cam + 400 + 10 then
            self.fly_state = "WAIT"
            self.fly_t = 0
        end
        return true

    elseif self.fly_state == "WAIT" then
        self.fly_t = (self.fly_t or 0) + dt
        if self.fly_t >= (D.offscreen or 0.9) then
            self.fly_state = "DASH"
            self.fly_t = 0
            self.dash_hit = false
            -- 衝刺高度：對齊玩家（要閃就得跳開，不能站著不動）
            self.boss_y = math.max(4, (mech_y or 100) - (b.dy + b.h) + (D.aim_bias or 18))
        end
        return true

    elseif self.fly_state == "DASH" then
        self.boss_x = self.boss_x - (D.speed or 300) * dt
        -- 撞到機體：一次性擊退＋傷害。★ 沿用 RAMMER 已做好的 mech_push_x 管線
        if not self.dash_hit and mech_x and controller then
            local L, R = self.boss_x + b.dx, self.boss_x + b.dx + b.w
            local T, B = self.boss_y + b.dy, self.boss_y + b.dy + b.h
            if R >= mech_x and L <= mech_x + (mech_w or 48)
               and B >= (mech_y or 0) and T <= (mech_y or 0) + (mech_h or 32) then
                self.dash_hit = true
                self.pending_mech_damage = (self.pending_mech_damage or 0) + (D.damage or 8)
                controller.mech_push_x = (controller.mech_push_x or 0) - (D.push or 44)
            end
        end
        if self.boss_x + b.dx + b.w < cam - 10 then
            self.fly_state = "RETURN"
        end
        return true

    elseif self.fly_state == "RETURN" then
        -- 從左邊繞回巡邏區（在畫面外用較快的速度，玩家不會看到它慢慢走回來）
        self.boss_x = self.boss_x + (D.return_speed or 260) * dt
        self.boss_y = (self.hover or {}).base_y or 10
        if self.boss_x >= self.hover_origin_x then
            self.boss_x = self.hover_origin_x
            self.fly_state = "CRUISE"
            self.fly_t = 0
            self.fly_wait = self:hoverNextDashWait()
        end
        return true
    end
    return false
end

-- ==========================================================================
-- 出招：挑選與推進
-- ==========================================================================
-- ★★ 加權抽選：權重寫在 boss_data 的 attacks.weights，不在程式裡寫死。
-- ★ 每一招可以標：
--     needs   = "<砲塔 id>"  砲塔壞了就不會被抽到
--     phase2  = true         血量低於 phase2_at 才解禁
--     no_repeat = true       不會連續兩次
function Enemy:hoverPickAttack(controller)
    local A = (self.boss_data.attacks or {})
    local ratio = (self.hp or 0) / math.max(1, self.hp_max or 1)
    local W = A.weights or {}
    local pool, total = {}, 0
    for _, kind in ipairs(A.order or {}) do
        local def = A[kind] or {}
        local ok = true
        if def.needs then
            local t = self.turret_by_id[def.needs]
            if not (t and t.alive) then ok = false end
        end
        if def.phase2 and ratio > (A.phase2_at or 0.5) then ok = false end
        if def.no_repeat and self.last_atk == kind then ok = false end
        local w = W[kind] or 1
        if ok and w > 0 then
            total = total + w
            table.insert(pool, { kind = kind, acc = total })
        end
    end
    if #pool == 0 or total <= 0 then return end
    local r = math.random() * total
    local kind = pool[#pool].kind
    for _, e in ipairs(pool) do
        if r <= e.acc then kind = e.kind; break end
    end
    self.last_atk = kind
    self.atk = { kind = kind, t = 0, n = 0, burst = 1, fired = 0 }
end

function Enemy:hoverAdvanceAttack(dt, mech_x, mech_y, mech_width, mech_height, controller)
    local A = (self.boss_data.attacks or {})
    local a = self.atk
    a.t = a.t + dt
    local def = A[a.kind] or {}

    if a.kind == "GUN" then
        local t = self.turret_by_id[def.needs or "GUN"]
        if not (t and t.alive) then self.atk = nil; return end
        local shots = def.shots or 5
        local btime = def.burst_time or 1.0
        if a.gap_t then
            a.gap_t = a.gap_t - dt
            if a.gap_t <= 0 then a.gap_t = nil; a.t = 0; a.fired = 0 end
            return
        end
        -- 這一輪應該已經射出幾發（1 秒 5 發＝每 0.2 秒一發）
        local want = math.min(shots, math.floor(a.t / (btime / shots)) + 1)
        while a.fired < want do
            a.fired = a.fired + 1
            self:hoverFireTurret(t, def, controller)
        end
        if a.fired >= shots and a.t >= btime then
            if a.burst >= (def.bursts or 3) then
                self.atk = nil                      -- 打完幾輪 → 回到隨機挑招
            else
                a.burst = a.burst + 1
                a.gap_t = def.burst_gap or 0.45
            end
        end

    elseif a.kind == "BOMB" then
        -- 投彈：先靠近並爬高（移動在 bossUpdateHover 裡做），到位或逾時才投
        local hv2 = self.hover or {}
        if not a.done then
            local seek = self:hoverBombSeekX(controller)
            local high = math.abs((self.alt_off or 0) + (hv2.bomb_climb or 34)) <= 2
            local near = ((not seek) or math.abs(seek - self.boss_x) <= (def.approach_tol or 8)) and high
            -- ★ 逾時保險：玩家一直往外跑時不能無限追，否則這一招會卡住排程
            if near or a.t >= (def.approach_max or 4.5) then
                a.done = true
                self:hoverDropBomb(controller)
                a.t = 0
            end
        elseif a.t >= 0.4 then
            self.atk = nil
        end

    elseif a.kind == "BLOCK" then
        local hv2 = self.hover or {}
        if not a.done then
            local high = math.abs((self.alt_off or 0) + (hv2.crate_climb or 26)) <= 2
            if high or a.t >= (def.climb_max or 2.5) then
                a.done = true
                self:hoverThrowBlock(controller)
                a.t = 0
            end
        elseif a.t >= 0.5 then
            self.atk = nil
        end

    elseif a.kind == "SBOMB" then
        -- 小型炸彈：連續丟幾顆，每顆之間隔 gap
        -- ★ 2026-09-25：顆數改成**每次隨機 n_min~n_max**（使用者拍板 1~2 顆）。
        --   在這裡抽而不是在挑招時抽 —— 挑招那支不認識各招式的欄位，
        --   放進去就變成「每加一招就要改挑招」。
        if not a.n_target then
            local lo = def.n_min or def.n or 3
            local hi = def.n_max or def.n or 3
            a.n_target = math.random(lo, hi)
        end
        local n = a.n_target
        local gap = def.gap or 0.25
        local want = math.min(n, math.floor(a.t / gap) + 1)
        while a.n < want do
            a.n = a.n + 1
            self:hoverFireSmallBomb(def, controller)
        end
        if a.n >= n and a.t >= n * gap then self.atk = nil end

    elseif a.kind == "ROCKET" then
        local t = self.turret_by_id[def.needs or "ROCKET"]
        if not (t and t.alive) then self.atk = nil; return end
        local n = def.n or 2
        local gap = def.gap or 0.5
        local want = math.min(n, math.floor(a.t / gap) + 1)
        while a.n < want do
            a.n = a.n + 1
            self:hoverFireRocket(t, def, controller)
        end
        if a.n >= n and a.t >= n * gap then self.atk = nil end

    else
        self.atk = nil
    end
end

-- ==========================================================================
-- 各種發射
-- ==========================================================================

-- 砲塔直射（機槍）
function Enemy:hoverFireTurret(t, def, controller)
    if not controller then return end
    local mx, my, dx, dy = self:hoverTurretAim(t)
    local spd = def.speed or 360
    local p = Projectile:init(mx, my, dx * spd, dy * spd, def.damage or 3, false, self.boss_ground_y)
    p.gravity = 0        -- ★ 機槍是直射：不吃重力，飛得快又直
    table.insert(controller.projectiles, p)
end

-- [[ BOSS3 ]] 小型炸彈：往前（機鼻方向）發射，之後純落下。★ 直徑 4 的方形（使用者拍板）
-- ★ 2026-09-25：往前的力道改成**每顆隨機**（speed_min~speed_max）。
--   固定力道時每顆的落點都一樣，一整串看起來像複製貼上；隨機才像手動投彈。
function Enemy:hoverFireSmallBomb(def, controller)
    local m = (self.hover_rig or {}).sbomb or {}
    local lo = def.speed_min or def.speed or 110
    local hi = def.speed_max or def.speed or 110
    table.insert(self.sbombs, {
        x = self.boss_x + (m.x or 0),
        y = self.boss_y + (m.y or 0),
        vx = -(lo + math.random() * (hi - lo)),
        vy = 0,
        size = def.size or 4,
    })
end

-- [[ BOSS3 ]] 追蹤火箭：往左上發射，之後轉向追玩家
function Enemy:hoverFireRocket(t, def, controller)
    local mx, my, dx, dy = self:hoverTurretAim(t)
    local spd = def.speed or 90
    table.insert(self.rockets, {
        x = mx, y = my,
        vx = dx * spd, vy = dy * spd,
        t = 0,
    })
end

-- [[ BOSS4 ]] 大炸彈：往前一點點推力 → 拋物線落下 → 大範圍爆炸＋畫面震動
function Enemy:hoverDropBomb(controller)
    local B = (self.boss_data.attacks or {}).BOMB or {}
    local bm = (self.hover_rig or {}).bomb or {}
    table.insert(self.bombs, {
        x = self.boss_x + (bm.drop_x or 85),
        y = self.boss_y + (bm.drop_y or 87),
        vx = -(B.push or 26), vy = 0,
    })
    self.bomb_reload = 1.2      -- 機腹的炸彈圖先消失，之後再出現（看得出來「丟出去了」）
end

-- [[ BOSS4 ]] 投擲 crate：丟的就是既有的 crate 物件（Stone）。
-- ★ 產生後**先在機鼻停留 hold 秒再掉落**：借用 Stone 既有的 `is_grabbed`
--   （那個狀態本來就會凍結物理、也不跑消失倒數），不必為了「停一下」多開一種狀態。
function Enemy:hoverThrowBlock(controller)
    if not (controller and Stone) then return end
    local BK = (self.boss_data.attacks or {}).BLOCK or {}
    local th = (self.hover_rig or {}).throw or {}
    local stone = Stone:init(self.boss_x + (th.x or 26), self.boss_y + (th.y or 60),
                             self.boss_ground_y or 156)
    stone.mech_damage = BK.damage or 10
    stone.despawn_time = BK.despawn
    stone.is_grabbed = true
    table.insert(controller.stones, stone)
    self.pending_crate = { stone = stone, t = 0 }
end

-- 停留中的 crate：黏在機鼻上，時間到就放手。
-- ★ 彈道在**放手那一刻**才算 —— 停留期間 BOSS 還在飄，提前算好會偏。
function Enemy:hoverUpdateCrate(dt, controller)
    local pc = self.pending_crate
    if not pc then return end
    local BK = (self.boss_data.attacks or {}).BLOCK or {}
    local th = (self.hover_rig or {}).throw or {}
    local sx = self.boss_x + (th.x or 26)
    local sy = self.boss_y + (th.y or 60)
    pc.stone.x, pc.stone.y = sx, sy
    pc.t = pc.t + dt
    if pc.t < (BK.hold or 0.3) then return end
    self.pending_crate = nil

    -- ★★ crate **不帶往上的推力**：只有往前的速度，垂直純自由落下（vy 從 0 開始）。
    -- ⚠️ Stone 的物理是**逐幀**的，落地幀數要解離散式：g·T·(T+1)/2 = h
    local tx = self.aim_mx or (self.boss_x - 120)
    do
        local lo = BK.dist_scale_min or 0.6
        local hi = BK.dist_scale_max or 1.35
        tx = sx + (tx - sx) * (lo + math.random() * (hi - lo))
    end
    local g = (controller and controller.GRAVITY) or 0.5
    local h = math.max(1, (self.boss_ground_y or 156) - sy)
    local T = (math.sqrt(1 + 8 * h / g) - 1) / 2
    local vx = (tx - sx) / math.max(1, T)
    vx = vx + (math.random() * 2 - 1) * (BK.spread or 0.5)
    local vmax = BK.speed_max or 5
    if vx > vmax then vx = vmax elseif vx < -vmax then vx = -vmax end
    pc.stone:launch(vx, 0, "BOSS")
end

-- ==========================================================================
-- 推進器煙霧（純程式特效，不需要圖）
-- ==========================================================================
-- ★★ 做法：從噴口定時吐出一顆，往機尾慢慢飄、邊飄邊變大，
--   接近壽命尾聲就只剩外框（1-bit 沒有半透明，「變淡」只能靠**變空心 → 變虛線**）。
-- ★ 粒子存的是**世界座標**：吐出來之後就與機體脫鉤，機體飄走時煙留在原地。
function Enemy:hoverUpdateSmoke(dt)
    local sm = (self.boss_data.smoke)
    if not sm then return end
    local th = (self.hover_rig or {}).thruster or {}
    self.smoke = self.smoke or {}
    self.smoke_t = (self.smoke_t or 0) + dt

    local interval = sm.interval or 0.22
    while self.smoke_t >= interval do
        self.smoke_t = self.smoke_t - interval
        if #self.smoke < (sm.max or 24) then
            local jx = (math.random() * 2 - 1) * (sm.spawn_jitter or 2)
            local jy = (math.random() * 2 - 1) * (sm.spawn_jitter or 2)
            table.insert(self.smoke, {
                x = self.boss_x + (th.x or 0) + jx,
                y = self.boss_y + (th.y or 0) + jy,
                vx = (sm.vx_min or 10) + math.random() * ((sm.vx_max or 18) - (sm.vx_min or 10)),
                vy = -((sm.rise_min or 2) + math.random() * ((sm.rise_max or 7) - (sm.rise_min or 2))),
                t = 0,
                life = (sm.life_min or 1.2) + math.random() * ((sm.life_max or 1.9) - (sm.life_min or 1.2)),
            })
        end
    end

    for i = #self.smoke, 1, -1 do
        local s = self.smoke[i]
        s.t = s.t + dt
        if s.t >= s.life then
            table.remove(self.smoke, i)
        else
            s.x = s.x + s.vx * dt
            s.y = s.y + s.vy * dt
            s.vx = s.vx * (1 - (sm.drag or 0.6) * dt)
        end
    end
end

function Enemy:hoverDrawSmoke(camera_x)
    local g = gfx
    local sm = (self.boss_data.smoke)
    if not sm then return end
    local r0, r1 = sm.r0 or 2, sm.r1 or 7
    for _, s in ipairs(self.smoke or {}) do
        local k = s.t / s.life                 -- 0＝剛吐出來、1＝快消失
        local r = r0 + (r1 - r0) * k
        local sx, sy = s.x - camera_x, s.y
        if k < 0.45 then
            g.setColor(g.kColorWhite); g.fillCircleAtPoint(sx, sy, r)
            g.setColor(g.kColorBlack); g.drawCircleAtPoint(sx, sy, r)
        elseif k < 0.75 then
            g.setColor(g.kColorBlack); g.drawCircleAtPoint(sx, sy, r)
        else
            g.setColor(g.kColorBlack)
            local n = 6
            for i = 0, n - 1 do
                local a = (i / n) * math.pi * 2 + s.t * 2
                g.drawPixel(sx + math.cos(a) * r, sy + math.sin(a) * r)
            end
        end
    end
    g.setColor(g.kColorBlack)
end

-- ==========================================================================
-- 飛行物（大炸彈 / 小型炸彈 / 火箭）
-- ==========================================================================

-- 炸彈圖的實際大小（量自 rig 的 x0~y1）。
-- ★★ 唯一計算點：繪製、落地判定、打到玩家的判定全部讀這支 ——
--   判定用「一個點」而圖是 40×23 的話，會出現「圖都埋進地裡了才爆」。
function Enemy:hoverBombSize()
    local bm = (self.hover_rig or {}).bomb or {}
    local w = (bm.x1 or 0) - (bm.x0 or 0) + 1
    local h = (bm.y1 or 0) - (bm.y0 or 0) + 1
    return w, h
end

function Enemy:hoverBombGravity(controller)
    local B = (self.boss_data.attacks or {}).BOMB or {}
    return (controller and controller.GRAVITY or 0.5) * 60 * (B.gravity_mult or 2.2)
end

-- 投彈前要飛到的 boss_x：讓炸彈**落在玩家身上**。
-- ★ 不是「飛到玩家正上方」那麼簡單 —— 炸彈離機時帶著往前的推力，
--   落下期間會往前飄 push × 落下時間，所以投彈點要往後偏那麼多。
function Enemy:hoverBombSeekX(controller)
    if not self.aim_mx then return nil end
    local B = (self.boss_data.attacks or {}).BOMB or {}
    local bm = (self.hover_rig or {}).bomb or {}
    local drop_x = bm.drop_x or 85
    local drop_y = bm.drop_y or 87
    local _, bh = self:hoverBombSize()
    local h = math.max(1, (self.boss_ground_y or 156) - (self.boss_y + drop_y) - bh / 2)
    local G = self:hoverBombGravity(controller)
    local tfall = math.sqrt(2 * h / G)
    return self.aim_mx + (B.push or 26) * tfall - drop_x
end

-- 三種飛行物一起更新
function Enemy:hoverUpdateShots(dt, mech_x, mech_y, mech_w, mech_h, controller)
    local A = (self.boss_data.attacks or {})
    local ground = self.boss_ground_y or 156
    local function hitMech(l, t, r, b)
        return mech_x and r >= mech_x and l <= mech_x + (mech_w or 48)
               and b >= (mech_y or 0) and t <= (mech_y or 0) + (mech_h or 32)
    end

    -- 大炸彈（BOSS4）
    local B = A.BOMB or {}
    local G = self:hoverBombGravity(controller)
    if self.bomb_reload and self.bomb_reload > 0 then self.bomb_reload = self.bomb_reload - dt end
    for i = #(self.bombs or {}), 1, -1 do
        local b = self.bombs[i]
        b.vy = b.vy + G * dt
        b.x = b.x + b.vx * dt
        b.y = b.y + b.vy * dt
        -- ★ 用**彈體矩形**判定（圖是 40×23，用中心點判會變成圖埋進地裡才爆）
        local bw, bh = self:hoverBombSize()
        local bl, br = b.x - bw / 2, b.x + bw / 2
        local bt, bb = b.y - bh / 2, b.y + bh / 2
        local hm = hitMech(bl, bt, br, bb)
        if bb >= ground or hm then
            local bx, by = b.x, math.min(bb, ground)
            table.remove(self.bombs, i)
            if hm then
                self.pending_mech_damage = (self.pending_mech_damage or 0) + (B.damage or 16)
            end
            if controller and controller.triggerEnemyBlast then
                self.pending_mech_damage = (self.pending_mech_damage or 0) +
                    controller:triggerEnemyBlast(bx, by, B.blast_radius or 44, B.blast_damage or 12,
                                                 mech_x, mech_y, mech_w, mech_h)
            end
            if controller and controller.requestScreenShake then
                controller:requestScreenShake(B.shake_intensity or 8, B.shake_duration or 0.5)
            end
        end
    end

    -- 小型炸彈（BOSS3）：往前飛 → 落下 → 碰到地面或玩家就消失
    local SB = A.SBOMB or {}
    local SG = (controller and controller.GRAVITY or 0.5) * 60 * (SB.gravity_mult or 1.6)
    for i = #(self.sbombs or {}), 1, -1 do
        local s = self.sbombs[i]
        s.vy = s.vy + SG * dt
        s.x = s.x + s.vx * dt
        s.y = s.y + s.vy * dt
        local half = (s.size or 4) / 2
        local hm = hitMech(s.x - half, s.y - half, s.x + half, s.y + half)
        if hm or (s.y + half) >= ground then
            if hm then
                self.pending_mech_damage = (self.pending_mech_damage or 0) + (SB.damage or 6)
            end
            if controller and controller.addHitSpark then
                controller:addHitSpark(s.x, math.min(s.y, ground))
            end
            table.remove(self.sbombs, i)
        end
    end

    -- 追蹤火箭（BOSS3）：飛出去之後轉向追玩家
    local R = A.ROCKET or {}
    for i = #(self.rockets or {}), 1, -1 do
        local r = self.rockets[i]
        r.t = r.t + dt
        -- ★ 轉向有**上限**（turn 度/秒）：無限轉＝必中，玩家只能硬吃。
        --   有上限的話繞一圈甩開它就是有效解法。
        if self.aim_mx and r.t >= (R.home_delay or 0.25) then
            local tx = self.aim_mx
            local ty = self.aim_my or r.y
            local want = math.atan(ty - r.y, tx - r.x)
            local cur = math.atan(r.vy, r.vx)
            local d = want - cur
            while d > math.pi do d = d - math.pi * 2 end
            while d < -math.pi do d = d + math.pi * 2 end
            local maxd = math.rad(R.turn or 110) * dt
            if d > maxd then d = maxd elseif d < -maxd then d = -maxd end
            local a = cur + d
            local spd = math.sqrt(r.vx * r.vx + r.vy * r.vy)
            r.vx, r.vy = math.cos(a) * spd, math.sin(a) * spd
        end
        r.x = r.x + r.vx * dt
        r.y = r.y + r.vy * dt
        local half = (R.size or 5) / 2
        local hm = hitMech(r.x - half, r.y - half, r.x + half, r.y + half)
        if hm or r.y >= ground or r.t >= (R.life or 4.0) then
            if hm then
                self.pending_mech_damage = (self.pending_mech_damage or 0) + (R.damage or 12)
            end
            if (hm or r.y >= ground) and controller and controller.addBlastVisual then
                controller:addBlastVisual(r.x, math.min(r.y, ground))
            end
            table.remove(self.rockets, i)
        end
    end
end

-- ==========================================================================
-- 繪製
-- ==========================================================================
function Enemy:bossDrawHover(camera_x)
    local g = gfx
    local bd = self.boss_data
    local rig = self.hover_rig or {}
    local bx = self.boss_x - camera_x + (self.hit_shake_offset_x or 0)
    local by = self.boss_y
    local sheet = self.boss_sheet

    -- 飛行中的大炸彈（畫在機體之前：它已經離開機腹）
    for _, b in ipairs(self.bombs or {}) do
        if self.bomb_img then
            local sx, sy = b.x - camera_x, b.y
            pcall(function() self.bomb_img:drawCentered(sx, sy) end)
        else
            g.setColor(g.kColorBlack)
            g.fillRect(b.x - camera_x - 4, b.y - 4, 8, 8)
        end
    end
    g.setColor(g.kColorBlack)

    -- 推進器煙霧：畫在本體**之前**（機體會壓在煙上＝煙從機身後方冒出）
    self:hoverDrawSmoke(camera_x)

    if sheet then
        local img = sheet:getImage(bd.cell_body or 1)
        if img then pcall(function() img:draw(bx, by) end) end
        -- 靜態件（砲塔底座、不會轉的發射器…）
        for _, c in ipairs(rig.mounts or {}) do
            local mi = sheet:getImage(c)
            if mi then pcall(function() mi:draw(bx, by) end) end
        end
    else
        local b = self.body_box
        g.setColor(g.kColorWhite); g.fillRect(bx + b.dx, by + b.dy, b.w, b.h)
        g.setColor(g.kColorBlack); g.drawRect(bx + b.dx, by + b.dy, b.w, b.h)
    end

    -- 砲塔（繞各自的軸心旋轉；壞掉時垂下＋閃爍＋火花＋修復倒數條）
    for _, t in ipairs(self.turrets or {}) do
        local td = t.data
        local pvx = bx + (td.pivot_x or 0)
        local pvy = by + (td.pivot_y or 0)
        local ang = t.angle or 0
        if not t.alive then ang = td.droop or (td.aim and td.aim.min) or 0 end
        if t.img then
            local blink = (not t.alive)
                and ((math.floor(playdate.getCurrentTimeMilliseconds() / 160) % 2) == 0)
            if not blink then
                pcall(function() t.img:drawRotated(pvx, pvy, ang) end)
            end
        end
        if not t.alive then
            -- 火花
            local mx, my = self:hoverTurretAim(t)
            mx = mx - camera_x
            local ms = playdate.getCurrentTimeMilliseconds()
            if (math.floor(ms / 90) % 2) == 0 then
                g.setColor(g.kColorWhite); g.fillRect(mx - 3, my - 3 + (ms % 5), 6, 6)
                g.setColor(g.kColorBlack); g.fillRect(mx - 2, my - 2 + (ms % 5), 4, 4)
            end
            -- 修復倒數條（讓玩家知道安靜期還有多久）
            local left = (td.repair_time or 60) - (t.repair_t or 0)
            local ratio = 1 - math.max(0, math.min(1, left / (td.repair_time or 60)))
            local byy = pvy + (td.bar_dy or 12)
            g.setColor(g.kColorWhite); g.fillRect(pvx - 16, byy, 32, 5)
            g.setColor(g.kColorBlack); g.drawRect(pvx - 16, byy, 32, 5)
            g.fillRect(pvx - 16, byy, math.floor(32 * ratio), 5)
        elseif t.repair_flash and t.repair_flash > 0 then
            if (math.floor(playdate.getCurrentTimeMilliseconds() / 80) % 2) == 0 then
                g.setColor(g.kColorBlack); g.setLineWidth(2)
                local p = t.proxy
                if p then g.drawRect(p.x - camera_x - 2, p.y - 2, p.width + 4, p.height + 4) end
                g.setLineWidth(1)
            end
        end
    end

    -- 機腹的炸彈（丟出去之後短暫消失＝看得出來剛剛投了彈）
    if sheet and rig.bomb and not (self.bomb_reload and self.bomb_reload > 0) then
        local bi = sheet:getImage(rig.bomb.cell)
        if bi then pcall(function() bi:draw(bx, by) end) end
    end

    -- 小型炸彈（直徑 4 的方形）
    g.setColor(g.kColorBlack)
    for _, s in ipairs(self.sbombs or {}) do
        local half = (s.size or 4) / 2
        g.fillRect(s.x - camera_x - half, s.y - half, s.size or 4, s.size or 4)
    end

    -- 追蹤火箭：黑色本體＋白色尾焰（1-bit 上要有對比才看得出方向）
    for _, r in ipairs(self.rockets or {}) do
        local sx, sy = r.x - camera_x, r.y
        local spd = math.max(1, math.sqrt(r.vx * r.vx + r.vy * r.vy))
        local ux, uy = r.vx / spd, r.vy / spd
        g.setColor(g.kColorWhite)
        g.fillRect(sx - ux * 7 - 2, sy - uy * 7 - 2, 4, 4)
        g.setColor(g.kColorBlack)
        g.setLineWidth(3)
        g.drawLine(sx - ux * 5, sy - uy * 5, sx + ux * 3, sy + uy * 3)
        g.setLineWidth(1)
    end

    -- ★ 機鼻遮罩不在這裡畫 —— 它要疊在剛丟出來的 crate 之上，
    --   而 crate（石頭管線）是畫在敵人之後的。見 drawAfterStones。
end

-- [[ §15.5c ]] 要疊在平台之上的 BOSS（COMET）：由 controller 在**畫完平台之後**呼叫。
-- ★ 這支掛在 Enemy 上，所有敵人都有 → 第一行先擋掉不需要的。
function Enemy:drawAfterPlatforms(camera_x)
    if self.part_mode ~= "HOVER" then return end
    if not self.boss_data.draw_above_platforms then return end
    self:bossDrawHover(camera_x)
end

-- [[ §15.5c ]] 機鼻遮罩：由 controller 在**畫完石頭之後**呼叫。
-- ★★ 它的用途就是「擋住正從機鼻出來的 crate」，所以繪製順序一定要在 crate 之後。
-- ★ 這支掛在 Enemy 上，所有敵人都有 → 第一行先擋掉非懸停制的。
function Enemy:drawAfterStones(camera_x)
    if self.part_mode ~= "HOVER" then return end
    local sheet = self.boss_sheet
    if not sheet then return end
    local nm = (self.hover_rig or {}).nose_mask
    if not nm then return end
    local ni = sheet:getImage(nm.cell)
    if not ni then return end
    local bx = self.boss_x - camera_x + (self.hit_shake_offset_x or 0)
    pcall(function() ni:draw(bx, self.boss_y) end)
end

-- 血條：本體一條血；標題後面附各砲塔狀態（壞掉時顯示剩餘修復秒數）
function Enemy:drawBossHpBarHover()
    local g = gfx
    local ratio = math.max(0, math.min(1, (self.hp or 0) / (self.hp_max or 1)))
    local bw, bh = 220, 8
    local bx = (400 - bw) / 2
    local by = 22
    local title = (self.boss_data.name or "BOSS")
    for _, t in ipairs(self.turrets or {}) do
        if t.alive then
            title = title .. "  " .. t.label .. " " .. math.max(0, math.floor(t.hp))
        else
            local left = math.ceil((t.data.repair_time or 60) - (t.repair_t or 0))
            title = title .. "  " .. t.label .. " DOWN " .. left .. "s"
        end
    end

    -- [[ 可讀性 ]] 先鋪白底（與其他血條同一套處理）
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
