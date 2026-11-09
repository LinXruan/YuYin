param (

    [Parameter(Position = 0)]

    [string]$Action = "status",



    [Parameter(Position = 1)]

    [string]$Arg1 = "",



    [string]$Serial = "",

    [int]$Port = 9527

)



$ErrorActionPreference = "Stop"



function Get-TargetDevice {

    if ($Serial) { return $Serial }

    $devs = @(adb devices | Select-String -Pattern "(\S+)\s+device$" | ForEach-Object { $_.Matches.Groups[1].Value })

    if ($devs.Count -eq 0) {

        throw "未检测到已连接的 Android 设备或模拟器"

    }

    $emu = $devs | Where-Object { $_ -like "emulator-*" } | Select-Object -First 1

    if ($emu) { return $emu }

    return $devs[0]

}



$device = Get-TargetDevice

$baseUrl = "http://127.0.0.1:$Port"



switch ($Action.ToLower()) {

    "setup" {

        Write-Host "[AgentBridge] 正在为设备 $device 建立端口映射: tcp:$Port -> tcp:$Port..."

        adb -s $device forward tcp:$Port tcp:$Port

        Write-Host "[AgentBridge] [成功] 端口映射完成。正在测试连通性..."

        try {

            $resp = Invoke-RestMethod -Uri "$baseUrl/api/status" -Method Get -TimeoutSec 3

            Write-Host "[AgentBridge] [在线] 应用控制台已连接: $($resp.app) v$($resp.version)"

        } catch {

            Write-Host "[AgentBridge] [提示] 端口已映射，但尚未收到应用响应。请确保 Debug 版 YuYin 已在设备上启动运行。"

        }

    }



    "status" {

        $resp = Invoke-RestMethod -Uri "$baseUrl/api/status" -Method Get

        $resp | ConvertTo-Json -Depth 5

    }



    "quality" {

        $enabled = if ($Arg1 -eq "off" -or $Arg1 -eq "false" -or $Arg1 -eq "0") { $false } else { $true }

        $body = @{ onlyHighestQualityPerResolution = $enabled } | ConvertTo-Json

        $resp = Invoke-RestMethod -Uri "$baseUrl/api/settings/quality" -Method Post -Body $body -ContentType "application/json; charset=utf-8"

        Write-Host "[AgentBridge] [成功] 仅显示同分辨率最高画质: $($resp.onlyHighestQualityPerResolution)"

    }



    "parse" {

        if (-not $Arg1) {

            throw "请提供要解析的抖音作品链接或分享文本，例如: .\tool\agent_cmd.bat parse 'https://v.douyin.com/...'"

        }

        Write-Host "[AgentBridge] 正在请求解析: $Arg1 ..."

        $body = @{ text = $Arg1 } | ConvertTo-Json

        $resp = Invoke-RestMethod -Uri "$baseUrl/api/parse" -Method Post -Body $body -ContentType "application/json; charset=utf-8"

        if ($resp.type -eq "user_home") {

            Write-Host "=== 主页作品解析成功 ==="

            Write-Host "作者: $($resp.result.nickname)"

            Write-Host "作品总数: $($resp.result.count) 条"

            Write-Host "标注总数: $($resp.result.tabCount) 个"

            Write-Host "封面总数: $($resp.result.coversCount) 条"

        } else {

            Write-Host "=== 解析成功 ==="

            Write-Host "标题: $($resp.title)"

            Write-Host "文案: $($resp.desc)"

            $typeLabel = if ($resp.isImagePost) { "图文/实况图集" } else { "普通视频" }

            Write-Host "类型: $typeLabel"

            Write-Host "资源总数: $($resp.totalItems)"

            $resp.items | Format-Table -Property index, type, resolutionLabel, formattedSize, formattedBitRate, gearName -AutoSize

        }

    }



    "download" {

        $indices = if (-not $Arg1 -or $Arg1 -eq "all") { "all" } else { ($Arg1 -split "," | ForEach-Object { [int]$_.Trim() }) }

        Write-Host "[AgentBridge] 正在请求下载资源 (indices=$Arg1)..."

        $body = @{ indices = $indices } | ConvertTo-Json

        $resp = Invoke-RestMethod -Uri "$baseUrl/api/download" -Method Post -Body $body -ContentType "application/json; charset=utf-8"

        Write-Host "=== 下载完成 ==="

        Write-Host "成功保存数量: $($resp.downloadedCount)"

        $types = $resp.savedTypes -join ', '

        Write-Host "保存资源类型: $types"

        Write-Host "生成文件名称:"

        $resp.expectedFiles | ForEach-Object { Write-Host "  - $_" }

    }



    "logs" {

        $tail = if ($Arg1) { "?tail=$Arg1" } else { "" }

        $resp = Invoke-RestMethod -Uri "$baseUrl/api/logs$tail" -Method Get

        Write-Host "=== 应用运行日志 (共 $($resp.count) 条) ==="

        $resp.logs | ForEach-Object { Write-Host $_ }

    }



    "clear-logs" {

        $resp = Invoke-RestMethod -Uri "$baseUrl/api/logs/clear" -Method Post

        Write-Host "[AgentBridge] [成功] 日志已清空"

    }



    "history" {

        $q = if ($Arg1) { "?q=$([System.Uri]::EscapeDataString($Arg1))" } else { "" }

        $resp = Invoke-RestMethod -Uri "$baseUrl/api/history$q" -Method Get

        Write-Host "=== 历史记录 (共 $($resp.count) 条) ==="

        if ($resp.records.Count -gt 0) {

            $resp.records | Format-Table -Property id, title, mediaSummary, formattedTime, itemCount -AutoSize

        } else {

            Write-Host "暂无历史记录"

        }

    }



    "clear-history" {

        $resp = Invoke-RestMethod -Uri "$baseUrl/api/history/clear" -Method Post

        Write-Host "[AgentBridge] [成功] 历史记录已清空"

    }



    "display" {

        $resp = Invoke-RestMethod -Uri "$baseUrl/api/display" -Method Get

        Write-Host "=== 屏幕刷新率检测信息 ==="

        Write-Host "当前激活刷新率: $($resp.activeRefreshRate) Hz"

        Write-Host "硬件最高支持: $($resp.maxRefreshRate) Hz"

        $status = if ($resp.isHighRefreshRate) { "已启用 (>60Hz 高刷模式)" } else { "标准 60Hz 模式" }

        Write-Host "高刷跟随状态: $status"

        if ($resp.width -gt 0) {

            Write-Host "屏幕物理分辨率: $($resp.width) x $($resp.height)"

        }

    }



    "thumbnails" {

        $resp = Invoke-RestMethod -Uri "$baseUrl/api/thumbnails" -Method Get

        Write-Host "=== 缩略图离线缓存状态 ==="

        Write-Host "本地已缓存缩略图: $($resp.stats.cachedFilesCount) 个文件"

        Write-Host "磁盘占用大小: $([math]::Round($resp.stats.totalBytes / 1KB, 2)) KB"

        Write-Host "内存索引记录数: $($resp.stats.inMemoryEntries) 条"

        Write-Host "正在下载任务数: $($resp.stats.inFlightDownloadsCount) 个"

    }



    "clear-thumbnails" {

        $resp = Invoke-RestMethod -Uri "$baseUrl/api/thumbnails/clear" -Method Post

        Write-Host "[AgentBridge] [成功] 本地缩略图离线缓存已完全清空"

    }



    "preload-thumbnails" {

        $resp = Invoke-RestMethod -Uri "$baseUrl/api/thumbnails/preload" -Method Post

        Write-Host "[AgentBridge] [成功] 触发离线缓存预热: $($resp.triggeredCount) / $($resp.totalRecords) 条记录"

    }



    "verify-covers" {

        $resp = Invoke-RestMethod -Uri "$baseUrl/api/verify/home-covers" -Method Post

        Write-Host "=== 主页作品封面图抓取校验比对报告 ==="

        Write-Host "基准期望作品数: $($resp.totalExpected)"

        Write-Host "本次捕获作品数: $($resp.capturedCount)"

        Write-Host "成功关联封面数: $($resp.coversCount)"

        Write-Host "样本精确匹配数: $($resp.matchedCount)"

        $pct = [math]::Round($resp.matchRate * 100, 1)

        Write-Host "封面匹配成功率: $pct %"

        $resp.details | Format-Table -Property index, matched, hasCover, referenceImage, url -AutoSize

    }



    "mock-login" {

        $enabled = if ($Arg1 -eq "off" -or $Arg1 -eq "false" -or $Arg1 -eq "0") { $false } else { $true }

        $body = @{ loggedIn = $enabled } | ConvertTo-Json

        $resp = Invoke-RestMethod -Uri "$baseUrl/api/login/mock" -Method Post -Body $body -ContentType "application/json; charset=utf-8"

        Write-Host "[AgentBridge] [成功] 模拟登录状态: $($resp.loggedIn)"

    }



    "cancel" {

        $resp = Invoke-RestMethod -Uri "$baseUrl/api/cancel" -Method Post

        Write-Host "[AgentBridge] [成功] 已取消当前任务"

    }



    "eval" {

        if (-not $Arg1) {

            throw "请提供要执行的 JS 脚本，例如: .\tool\agent_cmd.bat eval 'location.href'"

        }

        $body = @{ script = $Arg1 } | ConvertTo-Json

        $resp = Invoke-RestMethod -Uri "$baseUrl/api/eval" -Method Post -Body $body -ContentType "application/json; charset=utf-8"

        Write-Host $resp.result

    }



    default {

        Write-Host "未知指令: $Action"

        Write-Host "支持的指令: setup, status, display, quality [on|off], mock-login [on|off], parse, download, logs, clear-logs, history [query], clear-history, thumbnails, clear-thumbnails, preload-thumbnails, verify-covers, cancel, eval"

    }

}

