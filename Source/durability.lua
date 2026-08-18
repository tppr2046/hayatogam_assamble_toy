-- durability.lua
-- [[ 零件耐久 / 損壞 ]] GDD §8.07（設計）＋ §8.08（經濟配套）　2026-08-13 實作
--
-- ★ 設計目的是「讓商店與資源產生取捨壓力」，**不是**增加戰鬥變數。
--   所以完全不碰傷害模型：共享血量池維持現狀，耗損只在**關卡外**發生。
--
-- ★★ 這個檔案是耐久規則的**唯一來源**。調參只改下面 WEAR_K / REPAIR_RATE 兩個數字，
--    不要把公式複製到 state_result / state_shop 去 —— 那正是本專案最常出事的模式
--    （HANDOFF §3-5：同一個值有多個計算點）。

local Durability = {}

-- ============================================================
-- ★ 調參區（只有這兩個數字）
-- ============================================================
Durability.MAX = 100

-- K：耗損速度＝「差點死掉那一場要扣多少耐久」。
--    耗損 = round(K × 掉血比例²)。平方 → 打得好幾乎不耗。
--    K=40 對照表：掉血 10% 以內 → 0（免費）／25% → 2（撐 50 關）／
--                 50% → 10（撐 10 關）／75% → 22（撐 5 關）／差點死 → 40（撐 2.5 關）
Durability.WEAR_K = 40

-- R：修理費率＝「從全毀修到全滿，要花新品價的幾成」。
--    高階零件維護貴是這條自動帶出來的，不必另外寫規則
--    （FEET 新品 265 → 全毀修 80；GUN 新品 25 → 全毀修 8）。
Durability.REPAIR_RATE = 0.3

-- ============================================================
-- 基本存取
-- ============================================================
local function store()
    _G.GameState = _G.GameState or {}
    _G.GameState.part_durability = _G.GameState.part_durability or {}
    return _G.GameState.part_durability
end

-- ★ 初始零件（GUN / WHEEL1）宣告 indestructible ＝ 永不損壞。
--   理由是**死鎖**：「耐久 0 擋出擊」＋「重打不給關卡獎勵」會合成永久卡關
--   （零件全壞 → 不能出擊 → 賺不到資源 → 修不好）。GDD §8.08。
--   用資料欄位而不是寫死 id 清單，日後換保底零件只要改 parts_data。
function Durability.isIndestructible(part_id)
    local p = _G.PartsData and _G.PartsData[part_id]
    return (p and p.indestructible) and true or false
end

function Durability.get(part_id)
    if Durability.isIndestructible(part_id) then return Durability.MAX end
    local v = store()[part_id]
    if v == nil then return Durability.MAX end   -- 沒紀錄＝全新
    return v
end

function Durability.set(part_id, value)
    if Durability.isIndestructible(part_id) then return end
    value = math.max(0, math.min(Durability.MAX, math.floor(value + 0.5)))
    store()[part_id] = value
end

function Durability.isBroken(part_id)
    return Durability.get(part_id) <= 0
end

-- 耐久見底但還沒壞 → UI 要給預警（門檻見 GDD §8.05b 的顯示規則）
Durability.WARN_THRESHOLD = 30
function Durability.isLow(part_id)
    if Durability.isIndestructible(part_id) then return false end
    local v = Durability.get(part_id)
    return v > 0 and v < Durability.WARN_THRESHOLD
end

-- ============================================================
-- 過關時的耗損
-- ============================================================
-- damage_ratio = 這場總掉血 ÷ 最大 HP（0~1）
-- ★ 只在**過關**時呼叫。失敗不扣 —— 否則玩得差的人「又輸又花錢」，只會加速卡關；
--   重試永遠免費，推進才有成本（GDD §8.07）。
-- ★ 重打已通關的關卡**仍然會耗損** —— 不然重打就是零成本收掉落，經濟直接破掉。
-- 回傳 { {id=, before=, after=}, ... } 供結算畫面顯示（目前未用，留給日後演出）
function Durability.applyMissionWear(damage_ratio)
    damage_ratio = math.max(0, math.min(1, damage_ratio or 0))
    local wear = math.floor(Durability.WEAR_K * damage_ratio * damage_ratio + 0.5)
    local changes = {}
    if wear <= 0 then return changes end

    local eq = _G.GameState and _G.GameState.mech_stats
                and _G.GameState.mech_stats.equipped_parts or {}
    for _, item in ipairs(eq) do
        local pid = item.id
        if not Durability.isIndestructible(pid) then
            local before = Durability.get(pid)
            if before > 0 then
                local after = math.max(0, before - wear)
                Durability.set(pid, after)
                table.insert(changes, { id = pid, before = before, after = after })
            end
        end
    end
    return changes
end

-- ============================================================
-- 修理
-- ============================================================
-- 修到全滿要花的資源。回傳 { steel=, copper=, rubber=, total= }
-- ★ 每種資源各自 ceil —— 所以極小額的修理仍會各花 1 點，
--   這會讓「每關都回去補一下」不划算，是刻意的。
function Durability.repairCost(part_id)
    local p = _G.PartsData and _G.PartsData[part_id]
    local zero = { steel = 0, copper = 0, rubber = 0, total = 0 }
    if not p or Durability.isIndestructible(part_id) then return zero end

    local missing = (Durability.MAX - Durability.get(part_id)) / Durability.MAX
    if missing <= 0 then return zero end

    local function part_cost(base)
        if not base or base <= 0 then return 0 end
        return math.ceil(base * missing * Durability.REPAIR_RATE)
    end
    local s = part_cost(p.cost_steel)
    local c = part_cost(p.cost_copper)
    local r = part_cost(p.cost_rubber)
    return { steel = s, copper = c, rubber = r, total = s + c + r }
end

function Durability.canAfford(part_id)
    local cost = Durability.repairCost(part_id)
    if cost.total <= 0 then return false end
    local res = (_G.GameState and _G.GameState.resources) or {}
    return (res.steel or 0) >= cost.steel
       and (res.copper or 0) >= cost.copper
       and (res.rubber or 0) >= cost.rubber
end

-- 修好一個零件（扣資源、耐久回滿）。成功回傳 true
function Durability.repair(part_id)
    if not Durability.canAfford(part_id) then return false end
    local cost = Durability.repairCost(part_id)
    local res = _G.GameState.resources
    res.steel  = (res.steel  or 0) - cost.steel
    res.copper = (res.copper or 0) - cost.copper
    res.rubber = (res.rubber or 0) - cost.rubber
    Durability.set(part_id, Durability.MAX)
    return true
end

-- 需要修理的零件清單（給商店 REPAIR 分頁用）：已擁有、非不壞、耐久未滿
function Durability.repairableParts()
    local owned = (_G.GameState and _G.GameState.owned_parts) or {}
    local out = {}
    for pid, has in pairs(owned) do
        if has and not Durability.isIndestructible(pid)
           and Durability.get(pid) < Durability.MAX then
            table.insert(out, pid)
        end
    end
    table.sort(out)
    return out
end

-- 目前機體上有沒有壞掉的零件（出擊前擋下來用）
-- 回傳壞掉的 id 清單（空表＝可以出擊）
function Durability.brokenEquipped()
    local eq = _G.GameState and _G.GameState.mech_stats
                and _G.GameState.mech_stats.equipped_parts or {}
    local out = {}
    for _, item in ipairs(eq) do
        if Durability.isBroken(item.id) then table.insert(out, item.id) end
    end
    return out
end

return Durability