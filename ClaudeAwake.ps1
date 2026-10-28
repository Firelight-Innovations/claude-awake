# Claude Awake: while its tray icon is showing, closing the lid won't put the PC to sleep,
# so Claude Code sessions keep running. Launch it again (or double-click the tray icon) to turn it off.
#   -Install  writes the icon and the Desktop / Start Menu shortcuts
#   -Cleanup  restores the lid setting if a previous run never got to (e.g. after a crash or power loss)
param([switch]$Install, [switch]$Cleanup)

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Namespace Win32 -Name Power -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);'

$backupPath = Join-Path $PSScriptRoot 'lid-backup.json'
$iconPath = Join-Path $PSScriptRoot 'ClaudeAwake.ico'
$mutexName = 'Local\ClaudeAwake'

function Get-LidAction {
    # LIDACTION is a hidden setting on many laptops, so /query skips it; /qh shows it.
    $out = powercfg /qh SCHEME_CURRENT SUB_BUTTONS LIDACTION | Out-String
    $m = [regex]::Matches($out, ':\s*0x([0-9a-fA-F]{8})')
    if ($m.Count -ne 2) { throw "Couldn't read the lid close setting from powercfg." }
    @{ AC = [Convert]::ToInt32($m[0].Groups[1].Value, 16); DC = [Convert]::ToInt32($m[1].Groups[1].Value, 16) }
}

function Set-LidAction([int]$ac, [int]$dc) {
    powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION $ac | Out-Null
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION $dc | Out-Null
    powercfg /setactive SCHEME_CURRENT | Out-Null
}

function Restore-LidAction {
    if (-not (Test-Path $backupPath)) { return }
    $b = Get-Content $backupPath -Raw | ConvertFrom-Json
    Set-LidAction $b.AC $b.DC
    Remove-Item $backupPath
}

function New-AwakeBitmap([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(217, 119, 87))), 0, 0, $size - 1, $size - 1)
    $d = $size * 0.36
    $g.FillEllipse([System.Drawing.Brushes]::White, ($size - $d) / 2, ($size - $d) / 2, $d, $d)
    $g.Dispose()
    $bmp
}

if ($Cleanup) {
    $running = $null
    if (-not [System.Threading.Mutex]::TryOpenExisting($mutexName, [ref]$running)) { Restore-LidAction }
    return
}

if ($Install) {
    # Single 256px PNG-in-ICO; Explorer scales it down for the shortcuts.
    $png = New-Object System.IO.MemoryStream
    (New-AwakeBitmap 256).Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
    $bytes = $png.ToArray()
    $w = New-Object System.IO.BinaryWriter ([System.IO.File]::Create($iconPath))
    $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]1)                       # ICONDIR: reserved, type, count
    $w.Write([byte]0); $w.Write([byte]0); $w.Write([byte]0); $w.Write([byte]0)         # 256x256, no palette, reserved
    $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$bytes.Length); $w.Write([uint32]22)
    $w.Write($bytes)
    $w.Close()

    $ws = New-Object -ComObject WScript.Shell
    $shortcuts = @(
        @{ Path = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Claude Awake.lnk'; Args = '' }
        @{ Path = Join-Path ([Environment]::GetFolderPath('Programs')) 'Claude Awake.lnk'; Args = '' }
    )
    foreach ($s in $shortcuts) {
        $lnk = $ws.CreateShortcut($s.Path)
        $lnk.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $lnk.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"$($s.Args)"
        $lnk.IconLocation = $iconPath
        $lnk.WindowStyle = 7
        $lnk.Description = 'Keep the PC awake with the lid closed (toggle)'
        $lnk.Save()
        $s.Path
    }
    return
}

# A second launch while it's on means "turn off": signal the running instance and quit.
$isFirst = $false
$mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$isFirst)
$stopEvent = New-Object System.Threading.EventWaitHandle($false, 'AutoReset', 'Local\ClaudeAwake_Stop')
if (-not $isFirst) { [void]$stopEvent.Set(); return }

try {
    # Back up only when there's no backup yet, so a run that died early never overwrites the real originals with "Do nothing".
    if (-not (Test-Path $backupPath)) { Get-LidAction | ConvertTo-Json | Set-Content $backupPath }
    Set-LidAction 0 0
    $now = Get-LidAction
    if ($now.AC -ne 0 -or $now.DC -ne 0) { throw "Windows didn't accept the new lid close setting." }
} catch {
    Restore-LidAction
    [void][System.Windows.Forms.MessageBox]::Show("Couldn't turn Claude Awake on:`n$_", 'Claude Awake', 'OK', 'Error')
    return
}
# ES_CONTINUOUS | ES_SYSTEM_REQUIRED: no idle sleep while this runs; the screen can still turn off.
[void][Win32.Power]::SetThreadExecutionState(0x80000001)

$form = New-Object System.Windows.Forms.Form -Property @{ ShowInTaskbar = $false; WindowState = 'Minimized'; FormBorderStyle = 'FixedToolWindow'; Opacity = 0 }
$tray = New-Object System.Windows.Forms.NotifyIcon -Property @{
    Icon = [System.Drawing.Icon]::FromHandle((New-AwakeBitmap 32).GetHicon())
    Text = "Claude Awake: ON (closing the lid won't sleep)"
    Visible = $true
}
$menu = New-Object System.Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add('Turn off', $null, { Stop-Awake })
$tray.ContextMenuStrip = $menu

$turningOff = $false
function Stop-Awake {
    if ($script:turningOff) { return }
    $script:turningOff = $true
    Restore-LidAction
    $tray.ShowBalloonTip(2000, 'Claude Awake: OFF', 'Closing the lid will put the PC to sleep again.', 'Info')
    $closer = New-Object System.Windows.Forms.Timer -Property @{ Interval = 2500 }
    $closer.add_Tick({ $form.Close() })
    $closer.Start()
}

$poll = New-Object System.Windows.Forms.Timer -Property @{ Interval = 500 }
$poll.add_Tick({ if ($stopEvent.WaitOne(0)) { Stop-Awake } })
$poll.Start()
$tray.add_DoubleClick({ Stop-Awake })
$form.add_Shown({
    $form.Hide()
    $tray.ShowBalloonTip(4000, 'Claude Awake: ON', 'Safe to close the lid. Double-click this icon or launch Claude Awake again to turn off.', 'Info')
})
# Also fires on shutdown, restart and sign-out, so the lid setting doesn't stay changed by accident.
$form.add_FormClosing({ Restore-LidAction })

try { [System.Windows.Forms.Application]::Run($form) }
finally {
    Restore-LidAction
    $tray.Dispose()
    $mutex.ReleaseMutex()
}
