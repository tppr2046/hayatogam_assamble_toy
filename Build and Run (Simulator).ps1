 param (
    [string]$build = ".\Builds",
    [string]$source = ".\Source",
    [string]$name = (Get-Item -Path .).BaseName,
    [switch]$dontbuild = $false
 )

# Close Simulator
# ★ 2026-08-13 修正：舊版寫成
#       $sim = Get-Process ...; while (!$sim.HasExited) { ... }
#   在「同時有 2 個以上模擬器行程」時會失效 —— $sim 是集合時 $sim.HasExited
#   回傳的是**布林陣列**，而 PowerShell 把非空陣列視為 $true，
#   於是 !$sim.HasExited 永遠是 $false → 迴圈跑 0 圈（實測）、
#   底下的 Stop-Process -Force 永遠不會執行。
#   結果是「送出關閉要求後完全不等」就往下跑去刪除 Builds，
#   模擬器有沒有來得及放掉 .pdx 的檔案鎖純看時序 —— 是個 race condition。
#   改成逐一 WaitForExit，race 就消失了。
$sims = @(Get-Process "PlaydateSimulator" -ErrorAction SilentlyContinue)

if ($sims.Count -gt 0)
{
    $sims | Stop-Process -ErrorAction SilentlyContinue

    # 逐一等待，不能靠集合的屬性判斷
    foreach ($s in $sims)
    {
        if (-not $s.WaitForExit(3000))
        {
            $s | Stop-Process -Force -ErrorAction SilentlyContinue
            $null = $s.WaitForExit(3000)
        }
    }
}

$pdx = Join-Path -Path "$build" -ChildPath "$name.pdx"

# Create build folder if not present
if (!$dontbuild)
{
    New-Item -ItemType Directory -Force -Path "$build" | Out-Null
}

# Clean build folder
if (!$dontbuild)
{
    try
    {
        Remove-Item "$build\*" -Recurse -Force -Confirm:$false -ErrorAction Stop
    }
    catch
    {
        # 失敗時說明「為什麼」，不要只丟一行紅字 —— 九成是還有模擬器鎖著 .pdx
        Write-Host "清除 $build 失敗：$($_.Exception.Message)" -ForegroundColor Red
        $still = @(Get-Process "PlaydateSimulator" -ErrorAction SilentlyContinue)
        if ($still.Count -gt 0)
        {
            Write-Host "→ 還有 $($still.Count) 個 PlaydateSimulator 行程沒關掉（PID: $($still.Id -join ', ')），它鎖住了 .pdx。" -ForegroundColor Yellow
        }
        exit 1
    }
}

# Build
if (!$dontbuild)
{
    pdc -sdkpath "$Env:PLAYDATE_SDK_PATH" "$source" "$pdx"

    # ★ 編譯失敗就不要啟動模擬器 —— 否則會跑到**上一版的 pdx**，
    #   看起來像「改了卻沒生效」，最浪費除錯時間。
    if ($LASTEXITCODE -ne 0)
    {
        Write-Host "pdc 編譯失敗（exit $LASTEXITCODE），不啟動模擬器。" -ForegroundColor Red
        exit 1
    }
}

# Run (Simulator)
& "$Env:PLAYDATE_SDK_PATH\bin\PlaydateSimulator.exe" "$pdx"
