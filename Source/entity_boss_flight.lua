-- entity_boss_flight.lua
-- [[ §15.5b 高速飛行 BOSS ]] `move_mode = "FLIGHT"`。2026-08-19
--
-- ★★★ 本檔最重要的設計前提（使用者拍板）：
--   **「快」的感覺來自背景捲動，不是來自 BOSS 自己的移動速度。**
--   BOSS 在畫面上永遠是「看得到、瞄得到」的速度 —— 因為它若真的飛很快，
--   玩家的武器裡只有追蹤飛彈打得到，這一關就變成「不裝飛彈就過不了」，
--   違反「零件是取捨不是鑰匙」。
--   → 速度感交給 `scene.sky_scroll`（天空層自動捲動），BOSS 只負責戰鬥。
--
-- ★★ 結構完全沿用**序列制**（與 OVERSEER 同一套 `boss_parts` / `boss_phase`）：
--   每階段露出一個弱點零件，打爆進下一階段。
--   本檔只新增一樣東西：**移動與出招的狀態機**。命中框、繪製、血條、
--   死亡爆炸、BOSS_KILL 判定全部是既有的，一行都沒動。
--
-- ★ 座標：BOSS 用**螢幕相對**座標飛（`flight_sx/sy`），每幀換算回世界座標
--   （`boss_x = camera_x + flight_sx`）。相機被 `scene.arena` 鎖住，所以
--   camera_x 是常數 —— 這樣既有的世界座標繪製與命中判定**全部不用改**。
--
-- ==========================================================================
-- 硬直（RECOVER）——這場戰鬥的核心節奏
-- ==========================================================================
-- ★ 每一次攻擊的**最後一段**都是硬直：停在畫面內、不移動、不攻擊、可被打。
-- ★ **窗口外不設無敵**（拍板）。理由：
--     (1) 全遊戲目前只有 PHANTOM 有「打不到」的狀態，再加一個會讓規則變複雜
--     (2) 設無敵會讓追蹤飛彈變廢物 —— 它唯一的優勢就是能打會動的東西
--   → 窗口是**位置性**的（它停下來、又在畫面中央，所以好打），不是規則性的。
-- ★ 窗口長度用**玩家的武器冷卻**定，不是憑感覺：`GUN` 冷卻 1.0 秒且**現在是手動**，
--   窗口短於 1.0 秒＝只帶手動槍的配裝一發都打不到。所以第一階段給 1.5 秒。
-- ⚠️⚠️ **硬直不能發生在畫面外** —— 那樣玩家看不到也打不到，窗口等於不存在。
--   所以順序固定是：出畫 → 衝回來 → 攻擊 → **在畫面內硬直**。

local gfx = playdate.graphics

local SCREEN_W = 400

-- 取得本階段的飛行設定（每個 part 可以自帶 flight_phase 覆寫）
local function phaseCfg(self)
    local part = self.boss_parts[self.boss_phase]
    return (part and part.flight_phase) or {}
end

-- ==========================================================================
-- 初始化
-- ==========================================================================

function Enemy:bossInitFlight(bd, ground_y)
    self.move_mode = "FLIGHT"
    local f = bd.flight or {}
    self.flight = {
        cruise_speed   = f.cruise_speed or 70,    -- ★ 螢幕上的水平速度：看得到、瞄得到
        bob_amp        = f.bob_amp or 10,
        bob_speed      = f.bob_speed or 1.6,
        margin         = f.margin or 30,          -- 巡航時距畫面左右緣
        base_y         = f.base_y or 40,
        exit_speed     = f.exit_speed or 260,
        offscreen_time = f.offscreen_time or 1.0, -- 空白期（拍板 0.8~1.2）
        warn_before    = f.warn_before or 0.5,    -- 入畫預告箭頭提前多久
        dash_speed     = f.dash_speed or 300,
        dash_damage    = f.dash_damage or 8,
        dash_push      = f.dash_push or 44,
        spawn_type     = f.spawn_type or "DRONE",
        spawn_max      = f.spawn_max or 3,        -- ⚠️ 上限：沒有的話玩家不清就會滾雪球
    }
    self.flight_sx = 260          -- 螢幕座標（相機鎖定，所以這就是畫面上的位置）
    self.flight_sy = self.flight.base_y
    self.flight_dir = -1          -- 巡航方向（-1 = 往左，朝玩家）
    self.fstate = "CRUISE"
    self.fstate_t = 0
    self.flight_t = 0
    self.spawned_minions = 0
end

-- 把螢幕座標換算回世界座標，並對齊命中框。**每幀都要叫。**
-- ★ 這是位置的唯一計算點；繪製端讀的是 boss_x/boss_y，不要另外算一份。
function Enemy:bossSyncFlight(controller)
    local cam = (controller and controller.camera_x) or 0
    self.boss_x = cam + self.flight_sx
    self.boss_y = self.flight_sy
    self:bossPositionHitbox()
end

-- ==========================================================================
-- 狀態機
-- ==========================================================================

function Enemy:bossPickFlightAttack()
    local cfg = phaseCfg(self)
    local list = cfg.attacks or { "BOMB" }
    return list[math.random(1, #list)]
end

function Enemy:bossUpdateFlight(dt, mech_x, mech_y, mech_width, mech_height, controller)
    local F = self.flight
    self.flight_t = self.flight_t + dt
    self.fstate_t = self.fstate_t + dt
    local cfg = phaseCfg(self)

    local mech_cx = mech_x and (mech_x + (mech_width or 48) / 2) or nil
    local cam = (controller and controller.camera_x) or 0

    -- ------------------------------------------------------------------
    if self.fstate == "CRUISE" then
        -- 橫向掠過。★ 速度刻意慢到「瞄得準」—— 見檔頭的設計前提。
        self.flight_sx = self.flight_sx + self.flight_dir * F.cruise_speed * dt
        if self.flight_sx < F.margin then
            self.flight_sx = F.margin; self.flight_dir = 1
        elseif self.flight_sx + (self.boss_body_w or 64) > SCREEN_W - F.margin then
            self.flight_sx = SCREEN_W - F.margin - (self.boss_body_w or 64); self.flight_dir = -1
        end
        self.flight_sy = F.base_y + math.sin(self.flight_t * F.bob_speed) * F.bob_amp

        if self.fstate_t >= (cfg.cruise_time or 2.0) then
            local pick = self:bossPickFlightAttack()
            self.fatk = pick
            if pick == "DASH" then
                -- 俯衝要先出畫（拍板：飛出去再衝回來）
                self.fstate = "EXIT"; self.fstate_t = 0
                -- 從離玩家較遠的那一側出去，衝回來才有距離感
                self.exit_dir = (mech_cx and (mech_cx - cam) < SCREEN_W / 2) and 1 or -1
            else
                self.fstate = "TELEGRAPH"; self.fstate_t = 0
            end
        end

    -- ------------------------------------------------------------------
    elseif self.fstate == "EXIT" then
        self.flight_sx = self.flight_sx + (self.exit_dir or 1) * F.exit_speed * dt
        local w = self.boss_body_w or 64
        if self.flight_sx > SCREEN_W + 10 or self.flight_sx + w < -10 then
            self.fstate = "OFFSCREEN"; self.fstate_t = 0
            -- 回來的那一側與出去的相反；瞄準玩家目前的高度
            self.dash_from = -(self.exit_dir or 1)
            self.dash_y = mech_y and math.max(8, mech_y - 10) or F.base_y
        end

    -- ------------------------------------------------------------------
    elseif self.fstate == "OFFSCREEN" then
        -- 空白期。★ 期間畫面邊緣有預告箭頭（見 bossDrawFlightOverlay）——
        --   沒有預告的話「畫面外衝進來」就是偷襲，不是難度。
        if self.fstate_t >= F.offscreen_time then
            self.fstate = "DASH_IN"; self.fstate_t = 0
            local w = self.boss_body_w or 64
            self.flight_sx = (self.dash_from > 0) and (-w - 4) or (SCREEN_W + 4)
            self.flight_sy = self.dash_y or F.base_y
            self.dash_hit = false
        end

    -- ------------------------------------------------------------------
    elseif self.fstate == "DASH_IN" then
        self.flight_sx = self.flight_sx + (self.dash_from or 1) * F.dash_speed * dt

        -- 撞到機體：一次性擊退 + 傷害。★ **沿用 RAMMER 已經做好的 mech_push_x 管線**，
        --   位移仍由 state_mission 夾邊界後才套上（唯一計算點）。
        if (not self.dash_hit) and mech_x and controller then
            local bx = self.boss_x
            local by = self.boss_y
            local bw, bh = (self.boss_body_w or 64), (self.boss_body_h or 40)
            if bx < mech_x + (mech_width or 48) and bx + bw > mech_x
               and by < mech_y + (mech_height or 32) and by + bh > mech_y then
                self.dash_hit = true
                self.pending_mech_damage = (self.pending_mech_damage or 0) + F.dash_damage
                local dir = ((mech_x + (mech_width or 48) / 2) < (bx + bw / 2)) and -1 or 1
                controller.mech_push_x = (controller.mech_push_x or 0) + dir * F.dash_push
                print("LOG: flight boss dash hit")
            end
        end

        -- 穿過畫面 → 減速停在畫面內進硬直（⚠️ 硬直必須在畫面內，見檔頭）
        local w = self.boss_body_w or 64
        local past = (self.dash_from > 0) and (self.flight_sx > SCREEN_W * 0.55)
                                          or (self.flight_sx + w < SCREEN_W * 0.45)
        if past then
            self.fstate = "RECOVER"; self.fstate_t = 0
        end

    -- ------------------------------------------------------------------
    elseif self.fstate == "TELEGRAPH" then
        -- 出手前先停下來一小段：讓玩家看懂「要來了」
        if self.fstate_t >= (cfg.telegraph or 0.6) then
            self:bossFlightStrike(mech_x, mech_y, mech_width, controller)
            self.fstate = "RECOVER"; self.fstate_t = 0
        end

    -- ------------------------------------------------------------------
    else -- RECOVER（硬直）
        -- 停住、不攻擊、可被打。窗口長度依階段縮短（難度曲線就在這個數字上）。
        if self.fstate_t >= (cfg.recover or 1.5) then
            self.fstate = "CRUISE"; self.fstate_t = 0
            -- 回巡航時把高度拉回基準，避免俯衝後卡在很低的位置
            self.flight_sy = F.base_y
            -- 巡航方向朝玩家，免得它一直背對玩家跑
            if mech_cx then
                self.flight_dir = ((mech_cx - cam) < self.flight_sx) and -1 or 1
            end
        end
    end

    self:bossSyncFlight(controller)
end

-- 攻擊生效的那一瞬間
function Enemy:bossFlightStrike(mech_x, mech_y, mech_width, controller)
    local part = self.boss_parts[self.boss_phase]
    local atk = (part and part.attack) or {}
    local F = self.flight
    local target_x = (mech_x or self.boss_x) + (mech_width or 48) / 2

    if self.fatk == "BOMB" then
        -- 掠過投彈：往下拋的弧線彈（高 grav_mult）。沿用 Enemy:fire 的彈道解算。
        self.attack = atk.damage or 6
        self.projectile_speed_mult = atk.speed_mult or 24
        self.projectile_grav_mult = atk.bomb_grav_mult or 14
        local n = atk.bomb_n or 2
        for i = 1, n do
            local off = (i - (n + 1) / 2) * 40
            self:fire(target_x + off, controller)
        end

    elseif self.fatk == "VOLLEY" then
        -- 定點齊射：與序列制 BOSS 的 VOLLEY 同一條管線
        self.attack = atk.damage or 6
        self.projectile_speed_mult = atk.speed_mult or 30
        self.projectile_grav_mult = atk.grav_mult or 18
        local n = atk.n or 3
        for i = 1, n do
            local off = (i - (n + 1) / 2) * 50
            self:fire(target_x + off, controller)
        end

    elseif self.fatk == "SPAWN" then
        -- 放小兵。⚠️ 有上限 —— 沒有的話玩家不清就會滾雪球，戰鬥從單挑變成清場地獄。
        if controller and Enemy.init and self.spawned_minions < F.spawn_max then
            local gy = self.boss_ground_y or (self.boss_y + 100)
            local e = Enemy:init(self.boss_x + (self.boss_body_w or 64) / 2, 0, F.spawn_type, gy)
            if e then
                table.insert(controller.enemies, e)
                self.spawned_minions = self.spawned_minions + 1
                print("LOG: flight boss spawned " .. tostring(F.spawn_type)
                      .. " (" .. self.spawned_minions .. "/" .. F.spawn_max .. ")")
            end
        end
    end
end

-- ==========================================================================
-- 疊在 BOSS 之上的演出（由 drawBoss 在序列制繪製之後呼叫）
-- ==========================================================================
function Enemy:bossDrawFlightOverlay(camera_x)
    local g = gfx
    local F = self.flight
    if not F then return end

    -- [[ 空白期 ]] 入畫預告：它會從哪一側衝回來，畫面邊緣就閃哪一側。
    -- ★ 沒有這個的話「畫面外衝進來」是偷襲不是難度。
    if self.fstate == "OFFSCREEN" then
        local left = F.offscreen_time - self.fstate_t
        if left <= (F.warn_before or 0.5)
           and (math.floor(playdate.getCurrentTimeMilliseconds() / 70) % 2) == 0 then
            local y = (self.dash_y or F.base_y) + (self.boss_body_h or 40) / 2
            local from_left = (self.dash_from or 1) > 0
            local x = from_left and 14 or (400 - 14)
            local s = from_left and 1 or -1
            g.setColor(g.kColorWhite)
            g.fillTriangle(x - 12 * s, y - 13, x - 12 * s, y + 13, x + 13 * s, y)
            g.setColor(g.kColorBlack)
            g.fillTriangle(x - 10 * s, y - 10, x - 10 * s, y + 10, x + 10 * s, y)
        end
    end

    -- [[ 硬直 ]] 弱點提示：沿用 OVERSEER 的「向下箭頭 + 上下浮動」語彙。
    -- ★ 硬直必須**看得出來是機會**，否則玩家學不會這場戰鬥的節奏。
    if self.fstate == "RECOVER" then
        local part = self.boss_parts[self.boss_phase]
        if part then
            local ax = self.boss_x - camera_x + (part.dx or 0) + (part.w or 20) / 2
            local bob = math.sin(playdate.getCurrentTimeMilliseconds() / 180) * 3
            local ay = self.boss_y + (part.dy or 0) - 12 + bob
            g.setColor(g.kColorWhite)
            g.fillTriangle(ax - 8, ay - 10, ax + 8, ay - 10, ax, ay + 2)
            g.setColor(g.kColorBlack)
            g.fillTriangle(ax - 6, ay - 8, ax + 6, ay - 8, ax, ay)
        end
    end
end
