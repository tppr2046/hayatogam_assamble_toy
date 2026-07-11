-- module_entities.lua — 聚合器
-- [[ P1 拆檔（2026-07-11）]] 原 115KB 巨檔依「生命週期與職責」拆為五檔：
--   entity_projectile.lua  Projectile（彈道，雙方共用）
--   entity_enemy.lua       Enemy（敵人 AI；載入 EnemyData 並掛 _G 中繼）
--   entity_stone.lua       Stone（可搬運物件）
--   entity_mech.lua        MechController（玩家機體：輸入/操作/切換/繪製）
--   entity_controller.lua  EntityController（關卡總控：地形/實體/碰撞）
-- 本檔保留原名與回傳值，main.lua / state_mission.lua 的 import 不需更動。
-- 載入順序注意：entity_enemy 必須在 entity_controller 之前（_G.EnemyData 中繼）。

import "entity_projectile"
import "entity_enemy"
import "entity_stone"
import "entity_mech"
import "entity_controller"

return EntityController
