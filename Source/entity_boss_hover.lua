-- entity_boss_hover.lua
-- [[ §15.5c 懸停轟炸機 ]] BOSS 的**懸停制**（`part_mode = "HOVER"`）。2026-09-25
--
-- ★★ 一句話說清楚它與另外兩套的差別：
--   序列制（OVERSEER／COMET）＝一次只有一個零件，打爆換下一個。
--   平行制（COLOSSUS）＝頭與雙臂同時活著，各有 HP，全爆會狂暴。
--   懸停制（本檔）＝**本體一條血**，外掛一個**打得壞、但 60 秒後自己修好**的機槍。
--     機槍不是過關進度 —— 打壞它換到的是一段安靜期，所以它是**取捨**：
--     花彈藥拆槍，還是把火力全押在本體上。
--
-- ★★ 沿用既有管線的地方（都不必改 controller）：
--   本體 → `enemy.x/y/width/height` 與 `enemy.hp` 直接對齊機身命中框，
--          既有的傷害、死亡爆炸、BOSS_KILL 過關判定原樣沿用。
--   機槍 → 一個掛在 `controller.enemies` 裡的代理實體（欄位名沿用 `arm_proxies`，
--          spawn 端已經會把它塞進清單 —— 見 entity_controller 的建立迴圈）。
--   炸彈的爆風 → `controller:triggerEnemyBlast`（敵人專用，只打玩家）。
--   畫面震動 → `controller:requestScreenShake`。
--   投擲方塊落地 → 直接塞進 `controller.obstacles`（那套本來就每幀重讀，會擋路也打得破）。

local gfx = playdate.graphics

-- ==========================================================================
-- 機槍代理實體（讓 6 條命中路徑原樣打得到它）
-- ==========================================================================
-- ★ 與平行制的手臂代理同一套做法。`is_boss` 刻意不設 —— 設了的話沒拆槍就過不了關。
local function makeGunProxy(boss)
    local proxy = {
        is_boss_part = true,
        type_id = "BOSS_GUN",
        parent_boss = boss,
        x = 0, y = 0, width = 1, height = 1,
        hp = boss.gun_hp_max,
        is_alive = true,
        is_exploding = false,
        hit_shake_timer = 0, hit_shake_offset_x = 0,
        face_dir = -1,
        -- ★ 必填：controller 的接觸傷害分支會讀 attack，沒有就是 nil 做算術整個崩潰。
        --   0＝碰到機槍不扣血（它是靠子彈打人的）。
        attack = 0,
    }
    proxy.update = function() end
    proxy.draw = function() end
    proxy.startExplosion = function() end
    proxy.takeDamage = function(self, amount)
        if not amount or amount <= 0 then return false end
        if not self.is_alive then return false end
        return self.parent_boss:hoverGunDamage(amount)
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
    local gp = bd.gun_part or {}

    self.hover = hv
    self.hover_rig = rig
    self.hover_gun = gp

    -- 本體：一條血，命中框＝機身實際範圍（不是整張 120×120 的畫布）
    self.hp = bd.hp or 200
    self.hp_max = self.hp
    self.body_box = bd.body_box or { dx = 0, dy = 0, w = bd.body_w or 64, h = bd.body_h or 64 }

    -- 懸停：以出生點為中心左右飄移；base_y＝機體頂端距畫面上緣
    self.boss_y = hv.base_y or 10
    self.hover_dir = -1
    self.hover_t = 0
    self.hover_origin_x = self.boss_x

    -- 機槍
    self.gun_hp_max = gp.hp or 60
    self.gun_hp = self.gun_hp_max
    self.gun_alive = true
    self.gun_repair_t = 0
    self.gun_angle = 0          -- 相對「水平朝左」的角度，正=順時針（往上）
    self.gun_proxy = makeGunProxy(self)
    self.arm_proxies = { self.gun_proxy }   -- ★ 欄位名沿用 → spawn 端不必改

    -- 出招排程
    self.atk_timer = 0
    self.atk_wait = self:hoverNextWait()
    self.atk = nil              -- 進行中的招式
    self.last_atk = nil         -- 上一招（炸彈不連續要看它）

    -- 飛行中的炸彈與方塊（本檔自己更新與繪製）
    self.bombs = {}
    self.blocks = {}

    -- 旋轉件的緩衝圖（軸心置中）
    local m = rig.mount or {}
    self.gun_img = pivotCell(self.boss_sheet, (rig.gun or {}).cell or 3,
                             m.pivot_x or 50, m.pivot_y or 82, 120)

    self:hoverSyncBoxes()
end

-- 下一次出招的等待秒數（2~4 秒隨機）
function Enemy:hoverNextWait()
    local a = (self.boss_data.attacks or {})
    local lo, hi = a.interval_min or 2.0, a.interval_max or 4.0
    return lo + math.random() * (hi - lo)
end

-- 本體與機槍的世界座標／命中框。**每幀都要叫**（機體會飄、機槍會轉）。
-- ★ 這是位置的唯一計算點：繪製端讀同一組值。
function Enemy:hoverSyncBoxes()
    local b = self.body_box
    self.x = self.boss_x + b.dx
    self.y = self.boss_y + b.dy
    self.width = b.w
    self.height = b.h

    local gp = self.hover_gun or {}
    local p = self.gun_proxy
    if p then
        p.x = self.boss_x + (gp.dx or 18)
        p.y = self.boss_y + (gp.dy or 79)
        p.width = gp.w or 42
        p.height = gp.h or 15
        p.is_alive = self.gun_alive
        p.hp = self.gun_hp
    end
end

-- ==========================================================================
-- 機槍：受傷 / 打壞 / 修好
-- ==========================================================================
function Enemy:hoverGunDamage(amount)
    if not self.gun_alive then return false end
    if self.boss_invuln and self.boss_invuln > 0 then return false end
    self.gun_hp = self.gun_hp - amount
    self.gun_hit_flash = 0.25
    if self.gun_hp <= 0 then
        self.gun_hp = 0
        self.gun_alive = false
        self.gun_repair_t = 0
        self.gun_break_fx = 0.6          -- 打壞瞬間的爆點特效時間
        -- 正在連射就中斷（槍都壞了還在射會很怪）
        if self.atk and self.atk.kind == "GUN" then self.atk = nil end
        print("LOG: BOSS4 gun destroyed")
    end
    return true
end

-- ==========================================================================
-- 更新
-- ==========================================================================
function Enemy:bossUpdateHover(dt, mech_x, mech_y, mech_width, mech_height, controller)
    local bd = self.boss_data
    local hv = self.hover or {}

    -- [[ 懸停 ]] 緩慢左右飄移 ＋ 上下浮動。★ 不套重力（它是飛的）
    self.hover_t = (self.hover_t or 0) + dt
    local nx = self.boss_x + self.hover_dir * (hv.speed or 14) * dt
    if math.abs(nx - self.hover_origin_x) > (hv.range or 110) then
        self.hover_dir = -self.hover_dir
    else
        self.boss_x = nx
    end
    self.boss_y = (hv.base_y or 10) + math.sin(self.hover_t * (hv.bob_speed or 0.5) * math.pi * 2) * (hv.bob_amp or 5)

    -- [[ 機槍 ]] 以底座為軸瞄準玩家，夾在 ±max_angle 內
    local rig = self.hover_rig or {}
    local m = rig.mount or {}
    local gunr = rig.gun or {}
    local pvx = self.boss_x + (m.pivot_x or 50)
    local pvy = self.boss_y + (m.pivot_y or 82)
    if mech_x then
        local tx = mech_x + (mech_width or 48) / 2
        local ty = mech_y and (mech_y + (mech_height or 32) / 2) or pvy
        -- ★ 靜止姿勢＝水平朝左（第 3 格的槍管就是朝左）。
        --   螢幕座標下 atan2 增加＝順時針，所以「相對朝左的角度」＝ a − 180。
        local a = math.deg(math.atan(ty - pvy, tx - pvx))
        local rel = a - 180
        while rel > 180 do rel = rel - 360 end
        while rel < -180 do rel = rel + 360 end
        local mx = gunr.max_angle or 45
        if rel > mx then rel = mx elseif rel < -mx then rel = -mx end
        self.gun_angle = rel
    end

    -- [[ 機槍損壞 ]] 60 秒後自己修好
    if not self.gun_alive then
        self.gun_repair_t = (self.gun_repair_t or 0) + dt
        if self.gun_break_fx and self.gun_break_fx > 0 then
            self.gun_break_fx = self.gun_break_fx - dt
        end
        if self.gun_repair_t >= (self.hover_gun.repair_time or 60) then
            self.gun_alive = true
            self.gun_hp = self.gun_hp_max
            self.gun_repair_flash = 0.8
            print("LOG: BOSS4 gun repaired")
        end
    elseif self.gun_repair_flash and self.gun_repair_flash > 0 then
        self.gun_repair_flash = self.gun_repair_flash - dt
    end
    if self.gun_hit_flash and self.gun_hit_flash > 0 then
        self.gun_hit_flash = self.gun_hit_flash - dt
    end

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

    -- 飛行中的炸彈與方塊
    self:hoverUpdateBombs(dt, mech_x, mech_y, mech_width, mech_height, controller)
    self:hoverUpdateBlocks(dt, mech_x, mech_y, mech_width, mech_height, controller)

    self:hoverSyncBoxes()
end

-- 挑一招。★ 兩段：血量 50% 以上只有機槍＋投擲；50% 以下三種都來。
function Enemy:hoverPickAttack(controller)
    local A = (self.boss_data.attacks or {})
    local ratio = (self.hp or 0) / math.max(1, self.hp_max or 1)
    local pool = {}
    if self.gun_alive then table.insert(pool, "GUN") end
    table.insert(pool, "BLOCK")
    -- ★ 炸彈：第二階段才解禁，而且**不連續投擲**
    if ratio <= (A.phase2_at or 0.5) and self.last_atk ~= "BOMB" then
        table.insert(pool, "BOMB")
    end
    if #pool == 0 then return end
    local kind = pool[math.random(1, #pool)]
    self.last_atk = kind
    if kind == "GUN" then
        self.atk = { kind = "GUN", t = 0, burst = 1, fired = 0, gap_t = nil }
    elseif kind == "BOMB" then
        self.atk = { kind = "BOMB", t = 0, done = false }
    else
        self.atk = { kind = "BLOCK", t = 0, done = false }
    end
end

function Enemy:hoverAdvanceAttack(dt, mech_x, mech_y, mech_width, mech_height, controller)
    local A = (self.boss_data.attacks or {})
    local a = self.atk
    a.t = a.t + dt

    if a.kind == "GUN" then
        local g = A.GUN or {}
        -- 機槍壞掉就中斷（hoverGunDamage 也會清，這裡是保險）
        if not self.gun_alive then self.atk = nil; return end
        local shots = g.shots or 5
        local btime = g.burst_time or 1.0
        if a.gap_t then
            -- 兩輪之間的短暫停頓
            a.gap_t = a.gap_t - dt
            if a.gap_t <= 0 then a.gap_t = nil; a.t = 0; a.fired = 0 end
            return
        end
        -- 這一輪應該已經射出幾發（1 秒 5 發＝每 0.2 秒一發）
        local want = math.min(shots, math.floor(a.t / (btime / shots)) + 1)
        while a.fired < want do
            a.fired = a.fired + 1
            self:hoverFireGun(controller)
        end
        if a.fired >= shots and a.t >= btime then
            if a.burst >= (g.bursts or 3) then
                self.atk = nil                      -- 打完 3 輪 → 回到隨機挑招
            else
                a.burst = a.burst + 1
                a.gap_t = g.burst_gap or 0.45
            end
        end

    elseif a.kind == "BOMB" then
        -- 投彈：一次性
        if not a.done then
            a.done = true
            self:hoverDropBomb(controller)
        end
        if a.t >= 0.4 then self.atk = nil end

    elseif a.kind == "BLOCK" then
        if not a.done then
            a.done = true
            self:hoverThrowBlock(controller)
        end
        if a.t >= 0.5 then self.atk = nil end
    end
end

-- ==========================================================================
-- 三種攻擊
-- ==========================================================================

-- 機槍的槍口（世界座標）與方向。★ 唯一計算點：發射與繪製都讀這裡。
function Enemy:hoverGunAim()
    local rig = self.hover_rig or {}
    local m = rig.mount or {}
    local g = rig.gun or {}
    local pvx = self.boss_x + (m.pivot_x or 50)
    local pvy = self.boss_y + (m.pivot_y or 82)
    -- 槍長＝槍口到軸心的距離（量自圖）
    local ox = (g.muzzle_x or 18) - (m.pivot_x or 50)
    local oy = (g.muzzle_y or 86) - (m.pivot_y or 82)
    local len = math.sqrt(ox * ox + oy * oy)
    local rad = math.rad(180 + (self.gun_angle or 0))
    local dx, dy = math.cos(rad), math.sin(rad)
    return pvx + dx * len, pvy + dy * len, dx, dy, pvx, pvy
end

function Enemy:hoverFireGun(controller)
    if not controller then return end
    local g = (self.boss_data.attacks or {}).GUN or {}
    local mx, my, dx, dy = self:hoverGunAim()
    local spd = g.speed or 360
    local p = Projectile:init(mx, my, dx * spd, dy * spd, g.damage or 3, false, self.boss_ground_y)
    p.gravity = 0        -- ★ 機槍是直射：不吃重力，飛得快又直
    table.insert(controller.projectiles, p)
end

function Enemy:hoverDropBomb(controller)
    local B = (self.boss_data.attacks or {}).BOMB or {}
    local rig = self.hover_rig or {}
    local bm = rig.bomb or {}
    local push = B.push or 26
    -- ★ 往前（機鼻方向＝左）的**很弱**推力，之後就是單純的拋物線
    table.insert(self.bombs, {
        x = self.boss_x + (bm.drop_x or 85),
        y = self.boss_y + (bm.drop_y or 87),
        vx = -push, vy = 0,
    })
    self.bomb_reload = 1.2      -- 機腹的炸彈圖先消失，之後再出現（看得出來「丟出去了」）
end

function Enemy:hoverThrowBlock(controller)
    local BK = (self.boss_data.attacks or {}).BLOCK or {}
    local rig = self.hover_rig or {}
    local th = rig.throw or {}
    table.insert(self.blocks, {
        x = self.boss_x + (th.x or 26),
        y = self.boss_y + (th.y or 60),
        vx = -(BK.speed or 90), vy = 0,
        w = BK.width or 26, h = BK.height or 26,
        t = 0,
    })
end

-- ==========================================================================
-- 飛行中的炸彈 / 方塊
-- ==========================================================================
function Enemy:hoverUpdateBombs(dt, mech_x, mech_y, mech_w, mech_h, controller)
    local B = (self.boss_data.attacks or {}).BOMB or {}
    local G = (controller and controller.GRAVITY or 0.5) * 60 * (B.gravity_mult or 2.2)
    local ground = self.boss_ground_y or 156
    if self.bomb_reload and self.bomb_reload > 0 then self.bomb_reload = self.bomb_reload - dt end

    for i = #self.bombs, 1, -1 do
        local b = self.bombs[i]
        b.vy = b.vy + G * dt
        b.x = b.x + b.vx * dt
        b.y = b.y + b.vy * dt
        local hit_mech = mech_x and b.x >= mech_x and b.x <= mech_x + (mech_w or 48)
                         and b.y >= (mech_y or 0) and b.y <= (mech_y or 0) + (mech_h or 32)
        if b.y >= ground or hit_mech then
            local bx, by = b.x, math.min(b.y, ground)
            table.remove(self.bombs, i)
            -- 直擊：直擊傷害；沒直擊：只有爆風
            if hit_mech then
                self.pending_mech_damage = (self.pending_mech_damage or 0) + (B.damage or 16)
            end
            if controller and controller.triggerEnemyBlast then
                self.pending_mech_damage = (self.pending_mech_damage or 0) +
                    controller:triggerEnemyBlast(bx, by, B.blast_radius or 44, B.blast_damage or 12,
                                                 mech_x, mech_y, mech_w, mech_h)
            end
            -- ★ 爆炸要有畫面震動（使用者拍板）
            if controller and controller.requestScreenShake then
                controller:requestScreenShake(B.shake_intensity or 8, B.shake_duration or 0.5)
            end
        end
    end
end

function Enemy:hoverUpdateBlocks(dt, mech_x, mech_y, mech_w, mech_h, controller)
    local BK = (self.boss_data.attacks or {}).BLOCK or {}
    local G = (controller and controller.GRAVITY or 0.5) * 60 * (BK.gravity_mult or 1.6)
    local ground = self.boss_ground_y or 156

    for i = #self.blocks, 1, -1 do
        local k = self.blocks[i]
        k.t = k.t + dt
        k.vy = k.vy + G * dt
        k.x = k.x + k.vx * dt
        k.y = k.y + k.vy * dt
        local hit_mech = mech_x and (k.x + k.w) >= mech_x and k.x <= mech_x + (mech_w or 48)
                         and (k.y + k.h) >= (mech_y or 0) and k.y <= (mech_y or 0) + (mech_h or 32)
        if hit_mech then
            self.pending_mech_damage = (self.pending_mech_damage or 0) + (BK.damage or 10)
            table.remove(self.blocks, i)
        elseif k.y + k.h >= ground then
            table.remove(self.blocks, i)
            -- ★★ 落地後**留在場上**：直接塞進 controller.obstacles（使用者拍板）。
            --   那一套本來就每幀重讀清單 → 會擋路、打得破、破了自動消失，
            --   完全不必為了「BOSS 丟出來的方塊」另做一種實體。
            if controller and controller.obstacles then
                table.insert(controller.obstacles, {
                    x = math.floor(k.x), y = 0,
                    width = k.w, height = k.h,
                    hp = BK.hp or 20, max_hp = BK.hp or 20,
                })
            end
        end
    end
end

-- ==========================================================================
-- 繪製
-- ==========================================================================
-- 疊圖順序：本體 → 底座 → 機槍 → 機腹炸彈 → 投擲中的方塊 → 機鼻遮罩。
-- ★ 遮罩畫在方塊**之後** —— 它的用途就是把「還在機鼻裡」的方塊擋住，
--   讓方塊看起來是從機鼻黑色處被丟出來的（使用者提供的第 5 格）。
function Enemy:bossDrawHover(camera_x)
    local g = gfx
    local bd = self.boss_data
    local rig = self.hover_rig or {}
    local bx = self.boss_x - camera_x + (self.hit_shake_offset_x or 0)
    local by = self.boss_y
    local sheet = self.boss_sheet

    -- 飛行中的炸彈（畫在機體之前：它已經離開機腹）
    g.setColor(g.kColorBlack)
    for _, b in ipairs(self.bombs or {}) do
        g.fillRect(b.x - camera_x - 4, b.y - 4, 8, 8)
    end

    if sheet then
        -- 本體
        local img = sheet:getImage(bd.cell_body or 4)
        if img then pcall(function() img:draw(bx, by) end) end
        -- 機槍底座
        local m = rig.mount or {}
        local mi = sheet:getImage(m.cell or 2)
        if mi then pcall(function() mi:draw(bx, by) end) end
    else
        -- 沒圖時的佔位：一個機身方框
        local b = self.body_box
        g.setColor(g.kColorWhite); g.fillRect(bx + b.dx, by + b.dy, b.w, b.h)
        g.setColor(g.kColorBlack); g.drawRect(bx + b.dx, by + b.dy, b.w, b.h)
    end

    -- 機槍（繞底座旋轉）
    local m = rig.mount or {}
    local pvx = bx + (m.pivot_x or 50)
    local pvy = by + (m.pivot_y or 82)
    local ang = self.gun_angle or 0
    if not self.gun_alive then
        -- [[ 損壞 ]] 垂下來、閃爍、冒火花。★ 這是先做一版，數值好調（使用者要自己修）
        ang = (rig.gun and rig.gun.max_angle or 45)      -- 垂到最下面
    end
    if self.gun_img then
        local blink = (not self.gun_alive)
            and ((math.floor(playdate.getCurrentTimeMilliseconds() / 160) % 2) == 0)
        if not blink then
            local a = ang
            pcall(function() self.gun_img:drawRotated(pvx, pvy, a) end)
        end
    end

    -- [[ 損壞特效 ]] 打壞的瞬間放幾個爆點，之後持續冒火花
    if not self.gun_alive then
        local mx, my = self:hoverGunAim()
        mx = mx - camera_x
        local t = playdate.getCurrentTimeMilliseconds()
        if (math.floor(t / 90) % 2) == 0 then
            g.setColor(g.kColorWhite)
            g.fillRect(mx - 3, my - 3 + (t % 5), 6, 6)
            g.setColor(g.kColorBlack)
            g.fillRect(mx - 2, my - 2 + (t % 5), 4, 4)
        end
        -- 修好前的倒數條（讓玩家知道安靜期還有多久）
        local left = (self.hover_gun.repair_time or 60) - (self.gun_repair_t or 0)
        local ratio = 1 - math.max(0, math.min(1, left / (self.hover_gun.repair_time or 60)))
        g.setColor(g.kColorWhite); g.fillRect(pvx - 16, pvy + 12, 32, 5)
        g.setColor(g.kColorBlack); g.drawRect(pvx - 16, pvy + 12, 32, 5)
        g.fillRect(pvx - 16, pvy + 12, math.floor(32 * ratio), 5)
    elseif self.gun_repair_flash and self.gun_repair_flash > 0 then
        -- 修好的瞬間閃一下外框
        if (math.floor(playdate.getCurrentTimeMilliseconds() / 80) % 2) == 0 then
            g.setColor(g.kColorBlack); g.setLineWidth(2)
            local p = self.gun_proxy
            if p then g.drawRect(p.x - camera_x - 2, p.y - 2, p.width + 4, p.height + 4) end
            g.setLineWidth(1)
        end
    end

    -- 機腹的炸彈（丟出去之後短暫消失＝看得出來剛剛投了彈）
    if sheet and not (self.bomb_reload and self.bomb_reload > 0) then
        local bmc = (rig.bomb or {}).cell or 1
        local bi = sheet:getImage(bmc)
        if bi then pcall(function() bi:draw(bx, by) end) end
    end

    -- 投擲中的方塊（畫在遮罩之前）
    g.setColor(g.kColorWhite)
    for _, k in ipairs(self.blocks or {}) do
        g.fillRect(k.x - camera_x, k.y, k.w, k.h)
        g.setColor(g.kColorBlack)
        g.drawRect(k.x - camera_x, k.y, k.w, k.h)
        g.drawRect(k.x - camera_x + 3, k.y + 3, k.w - 6, k.h - 6)
        g.setColor(g.kColorWhite)
    end
    g.setColor(g.kColorBlack)

    -- 機鼻遮罩（最上層：把還在機鼻裡的方塊擋住）
    if sheet then
        local nm = (rig.nose_mask or {}).cell or 5
        local ni = sheet:getImage(nm)
        if ni then pcall(function() ni:draw(bx, by) end) end
    end
end

-- 血條：本體一條血；標題後面附機槍狀態（壞掉時顯示剩餘修復秒數）
function Enemy:drawBossHpBarHover()
    local g = gfx
    local ratio = math.max(0, math.min(1, (self.hp or 0) / (self.hp_max or 1)))
    local bw, bh = 220, 8
    local bx = (400 - bw) / 2
    local by = 22
    local title = (self.boss_data.name or "BOSS")
    if self.gun_alive then
        title = title .. "  GUN " .. math.max(0, math.floor(self.gun_hp)) .. "/" .. self.gun_hp_max
    else
        local left = math.ceil((self.hover_gun.repair_time or 60) - (self.gun_repair_t or 0))
        title = title .. "  GUN DOWN " .. left .. "s"
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
