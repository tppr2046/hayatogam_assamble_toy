-- enemy_data.lua
-- 導出所有敵人類型的詳細屬性 (已移除中文字符)

return {
    ["BASIC_ENEMY"] = {
        name = "BASIC TRAINER UNIT", hp = 30, attack = 5, 
        move_type = "MOVE FORWARD/BACK", attack_type = "FIRE BULLET",
        -- 砲彈屬性 multiplier：水平速度相對於玩家移動速度、以及重力的倍率
           projectile_speed_mult = 30, -- 30 = 水平速度接近玩家感覺
           projectile_grav_mult = 20   -- 20 = 重力感接近玩家
    },
    
    ["HEAVY_ENEMY"] = {
        name = "HEAVY ARMOR UNIT", hp = 80, attack = 10, 
        move_type = "IMMOBILE", attack_type = "SWING ATTACK"
    }
}