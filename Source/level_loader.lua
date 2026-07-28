-- level_loader.lua
-- [[ 一關一檔 ]] 掃描 Source/levels/ 資料夾內的所有 *.json，組成 MissionData 表（以每檔的 id 為鍵）。
-- 新增關卡＝把關卡編輯工具匯出的 .json 丟進 levels/ 後重新編譯，無需改任何程式或貼進 mission_data。
-- 底線開頭的檔（如 _template.json）會被略過。

local function loadLevels()
    local missions = {}
    local count = 0
    local ok, files = pcall(function() return playdate.file.listFiles("levels/") end)
    if not ok or not files then
        print("LEVELS: listFiles('levels/') 失敗，回傳空表")
        return missions
    end
    for _, fn in ipairs(files) do
        if string.sub(fn, -5) == ".json" and string.sub(fn, 1, 1) ~= "_" then
            local okd, data = pcall(function() return json.decodeFile("levels/" .. fn) end)
            if okd and data and data.id then
                if missions[data.id] then
                    print("LEVELS: 警告—id 重複 '" .. data.id .. "'（" .. fn .. " 覆蓋前一筆）")
                end
                missions[data.id] = data
                count = count + 1
                print("LEVEL loaded: " .. data.id .. " (" .. fn .. ")")
            else
                print("LEVEL load FAILED: " .. fn .. "（json 解析失敗或缺少 id）")
            end
        end
    end
    print("LEVELS: 共載入 " .. count .. " 關")
    return missions
end

return loadLevels