-- parts_data.lua 

local parts_data = {
    -- 這是您機甲零件的實際資料。請確保這些 ID 和結構是正確的。
    
    WHEEL_2X1 = {
        name = "Wheel", 
        hp = 20, 
        weight = 5, 
        slot_x = 2, 
        slot_y = 1,
        color = gfx.kColorBlack},
    ARMOR_1X1 = {
        name = "Armor", 
        hp = 10, 
        weight = 2, 
        slot_x = 1, 
        slot_y = 1,
        color = gfx.kColorBlack},
    
    FRAME_3X1 = {
        name = "Light Frame", 
        hp = 15, 
        weight = 3, 
        slot_x = 3, 
        slot_y = 1,
        color = gfx.kColorBlack
    },
    
    -- ... 其他零件數據 ...
}

-- 關鍵：必須使用 return 將 parts_data 表傳出
return my_parts_table