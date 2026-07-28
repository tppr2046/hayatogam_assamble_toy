-- mission_data.lua
-- [[ 已遷移 ]] 關卡資料改為「一關一檔」：每關是 Source/levels/<id>.json，由 level_loader.lua 於啟動時掃描載入。
-- 新增關卡＝把關卡編輯工具匯出的 .json 丟進 Source/levels/ 後重新編譯即可，不需再編輯本檔。
-- 本檔僅保留為 level_loader 找不到任何關卡時的安全網（回傳空表）。原本的關卡內容已完整轉為 JSON（見 git 歷史）。

return {}