<#
Reusable Windows 11 gaming/performance optimizer.

Run examples:

  Audit only:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\w11-optimiser.ps1 -Mode Audit

  Preview planned changes:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\w11-optimiser.ps1 -Mode Preview

  Safe optimisation, no temp/cache cleanup:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\w11-optimiser.ps1 -Mode SafeOptimize -SkipTempCleanup

  Safe optimisation with old temp/cache cleanup:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\w11-optimiser.ps1 -Mode SafeOptimize

  Safe optimisation when System Restore is unavailable:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\w11-optimiser.ps1 -Mode SafeOptimize -SkipRestorePoint

  Undo latest optimization run:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\w11-optimiser.ps1 -Mode UndoLatest

  Check current optimization state:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\w11-optimiser.ps1 -Mode PostCheck

  Open the latest generated report:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\w11-optimiser.ps1 -Mode OpenLastReport

What this script will NOT do:
- It will not disable Windows Defender, firewall, Windows Update, Microsoft Store,
  AMD Software, drivers, VBS/Memory Integrity, HAGS, services, startup apps,
  BIOS/UEFI settings, overclocking, or undervolting.
- It will not remove apps or run remote internet code.

What safe optimisation does:
- Creates a restore point.
- Creates Desktop\W11 Optimiser\Runs\Safe Run <timestamp>.
- Exports registry backups before edits.
- Enables Ultimate Performance if available/creatable, otherwise High Performance.
- Sets AC CPU minimum to 10 percent and maximum to 100 percent.
- Disables PCIe Link State Power Management on AC.
- Disables USB selective suspend on AC.
- Sets wireless adapter AC power saving to maximum performance.
- Disables Windows Game DVR/background capture.
- Keeps Windows Game Mode enabled.
- Applies a conservative visual responsiveness profile.
- Ensures SSD TRIM is enabled.
- Runs a safe SSD ReTrim maintenance pass on fixed NTFS/ReFS volumes.
- Disables physical network adapter sleep permission where Windows exposes it,
  including a registry fallback for adapters/drivers that hide it from the cmdlet.
- Lists startup apps for review, but does not disable them.
- Detects AMD, NVIDIA, Intel, and Microsoft Basic Display Adapter GPUs for
  audit/recommendation purposes without using vendor registry hacks.
- Warns when a battery is detected, because high-performance plans are best
  used while plugged in.

Safety controls:
- SafeOptimize and UndoLatest ask for confirmation unless -Force is passed.
- -SkipRestorePoint is opt-in for systems where Windows System Restore is unavailable.
- -VerboseLog writes a detailed step log into the run folder for troubleshooting.
#>

[CmdletBinding()]
param(
    [ValidateSet("Audit", "Preview", "SafeOptimize", "UndoLatest", "PostCheck", "OpenLastReport")]
    [string] $Mode = "Audit",

    [switch] $SkipTempCleanup,

    [switch] $SkipRestorePoint,

    [switch] $Force,

    [switch] $VerboseLog,

    [switch] $NoSelfElevate,

    [string] $BackupPath
)

$ErrorActionPreference = "Stop"

$PowerGuids = @{
    UltimatePerformance = "e9a42b02-d5df-448d-aa00-03f14749eb61"
    HighPerformance     = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
    Balanced            = "381b4222-f694-41f0-9685-ff5bb260df2e"
    Processor           = "54533251-82be-4824-96c1-47b60b740d00"
    ProcessorMin        = "893dee8e-2bef-41e0-89c6-b55d0929964c"
    ProcessorMax        = "bc5038f7-23e0-4960-96da-33abaf5935ec"
    PciExpress          = "501a4d13-42af-4429-9fd1-a8218c268e20"
    PcieAspm            = "ee12f906-d277-404b-b6da-e5fa1a576df5"
    Usb                 = "2a737441-1930-4402-8d77-b2bebba308a3"
    UsbSelectiveSuspend = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226"
    WirelessAdapter     = "19cbb8fa-5279-450e-9fac-8a3d5fedd0c1"
    WirelessPowerSaving = "12bbebe6-58d6-4636-95bb-3217ef867c1a"
}

$NetworkAdapterClassKeyRoot = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}"
$NetworkAdapterPowerOffDisableMask = 24

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal] $identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DesktopPath {
    $desktop = [Environment]::GetFolderPath("Desktop")
    if ([string]::IsNullOrWhiteSpace($desktop)) {
        $desktop = Join-Path $env:USERPROFILE "Desktop"
    }
    return $desktop
}

function Get-FriendlyTimestamp {
    return Get-Date -Format "yyyy-MM-dd HHmmss"
}

function Get-OptimisationRoot {
    return Join-Path (Get-DesktopPath) "W11 Optimiser"
}

function Get-ReportsFolder {
    return Join-Path (Get-OptimisationRoot) "Reports"
}

function Get-ChangesFolder {
    return Join-Path (Get-OptimisationRoot) "Runs"
}

function Test-HasBattery {
    try {
        return $null -ne (Get-CimInstance Win32_Battery -ErrorAction Stop | Select-Object -First 1)
    }
    catch {
        return $false
    }
}

function Get-GpuVendorSummary {
    $gpus = @()
    try {
        $gpus = Get-CimInstance Win32_VideoController -ErrorAction Stop
    }
    catch {
        return [pscustomobject]@{
            Vendors = "Unknown"
            Names   = "GPU query failed: $($_.Exception.Message)"
        }
    }

    $vendors = foreach ($gpu in $gpus) {
        $text = "$($gpu.Name) $($gpu.AdapterCompatibility)"
        if ($text -match "AMD|Radeon|Advanced Micro Devices") {
            "AMD"
        }
        elseif ($text -match "NVIDIA|GeForce|RTX|GTX|Quadro") {
            "NVIDIA"
        }
        elseif ($text -match "Intel|Arc|Iris|UHD") {
            "Intel"
        }
        elseif ($text -match "Microsoft Basic Display") {
            "Microsoft Basic Display Adapter"
        }
        else {
            "Unknown"
        }
    }

    [pscustomobject]@{
        Vendors = (($vendors | Sort-Object -Unique) -join ", ")
        Names   = (($gpus | Select-Object -ExpandProperty Name) -join "; ")
    }
}

function Invoke-SelfElevateIfNeeded {
    param([Parameter(Mandatory = $true)][string] $TargetMode)

    if ((Test-IsAdmin) -or $NoSelfElevate) {
        return
    }

    $scriptPath = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        Write-Error "Cannot self-elevate because the script path is unknown. Re-run from an elevated PowerShell session."
        exit 1
    }

    $argumentList = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$scriptPath`"",
        "-Mode", $TargetMode
    )

    if ($SkipTempCleanup) {
        $argumentList += "-SkipTempCleanup"
    }
    if ($SkipRestorePoint) {
        $argumentList += "-SkipRestorePoint"
    }
    if ($Force -or $script:ConfirmedRunAction) {
        $argumentList += "-Force"
    }
    if ($VerboseLog) {
        $argumentList += "-VerboseLog"
    }
    if (-not [string]::IsNullOrWhiteSpace($BackupPath)) {
        $argumentList += @("-BackupPath", "`"$BackupPath`"")
    }
    $argumentList += "-NoSelfElevate"

    Write-ConsoleStatus -Tag "ADMIN" -Message "Requesting Administrator elevation for $TargetMode..." -Color Cyan
    try {
        $process = Start-Process -FilePath "powershell.exe" -ArgumentList ($argumentList -join " ") -Verb RunAs -Wait -PassThru -ErrorAction Stop
        if ($null -ne $process.ExitCode) {
            exit $process.ExitCode
        }
        exit 0
    }
    catch {
        Write-ConsoleStatus -Tag "CANCEL" -Message "Elevation was cancelled or failed. No changes were made." -Color Yellow
        Write-Host ("  Reason: {0}" -f $_.Exception.Message) -ForegroundColor DarkGray
        exit 1
    }
}

function Initialize-RunFolder {
    param([string] $Prefix = "Safe Run")

    $root = Get-ChangesFolder
    $timestamp = Get-FriendlyTimestamp
    $script:BackupPath = Join-Path $root "$Prefix $timestamp"
    $null = New-Item -ItemType Directory -Path $script:BackupPath -Force
    $script:LogPath = if ($VerboseLog) { Join-Path $script:BackupPath "Run Log.txt" } else { $null }
    $script:LogWarnings = @()
    $script:LogErrors = @()
    $script:LogStepCount = 0
}

function Write-ConsoleStatus {
    param(
        [Parameter(Mandatory = $true)][string] $Tag,
        [Parameter(Mandatory = $true)][string] $Message,
        [ConsoleColor] $Color = [ConsoleColor]::White
    )

    Write-Host ("  [{0}] {1}" -f $Tag, $Message) -ForegroundColor $Color
}

function Write-Log {
    param([Parameter(Mandatory = $true)][string] $Message)

    $time = Get-Date -Format "HH:mm:ss"
    $line = $null
    $consoleTag = $null
    $consoleMessage = $null
    $consoleColor = [ConsoleColor]::White

    if ($Message -match "^START:\s*(.+)$") {
        $script:LogStepCount++
        $stepName = $Matches[1]
        $line = "`r`n[{0}] START: {1}" -f $time, $stepName
        $consoleTag = ".."
        $consoleMessage = $stepName
        $consoleColor = [ConsoleColor]::Cyan
    }
    elseif ($Message -match "^DONE\s*:\s*(.+)$") {
        $stepName = $Matches[1]
        $line = "[{0}] DONE : {1}" -f $time, $stepName
        $consoleTag = "OK"
        $consoleMessage = $stepName
        $consoleColor = [ConsoleColor]::Green
    }
    elseif ($Message -match "^WARN\s*:\s*(.+)$") {
        $warning = $Matches[1]
        $script:LogWarnings += $warning
        $line = "[{0}] WARN : {1}" -f $time, $warning
        $consoleTag = "WARN"
        $consoleMessage = $warning
        $consoleColor = [ConsoleColor]::Yellow
    }
    elseif ($Message -match "^ERROR:\s*(.+)$") {
        $errorText = $Matches[1]
        $script:LogErrors += $errorText
        $line = "[{0}] ERROR: {1}" -f $time, $errorText
        $consoleTag = "ERROR"
        $consoleMessage = $errorText
        $consoleColor = [ConsoleColor]::Red
    }
    else {
        $line = "[{0}] INFO : {1}" -f $time, $Message
        if ($Message -match "(?i)\bskipped\b|\bskip\b") {
            $consoleTag = "SKIP"
            $consoleMessage = $Message
            $consoleColor = [ConsoleColor]::DarkGray
        }
    }

    if ($consoleTag) {
        Write-ConsoleStatus -Tag $consoleTag -Message $consoleMessage -Color $consoleColor
    }
    if ($script:LogPath) {
        Add-Content -Path $script:LogPath -Value $line -Encoding UTF8
    }
}

function Confirm-RunAction {
    param(
        [Parameter(Mandatory = $true)][string] $Title,
        [Parameter(Mandatory = $true)][string[]] $Lines
    )

    if ($Force) {
        return $true
    }

    Write-Host ""
    Write-Host ("=== {0} ===" -f $Title) -ForegroundColor Cyan
    Write-Host ""
    foreach ($line in $Lines) {
        Write-Host ("  {0}" -f $line)
    }
    Write-Host ""

    $answer = Read-Host "Continue? (Y/N)"
    if ($answer -match "^(?i:y(?:es)?)$") {
        return $true
    }

    Write-ConsoleStatus -Tag "CANCEL" -Message "Cancelled. No changes were made." -Color DarkGray
    return $false
}

function Write-LogHeader {
    param([Parameter(Mandatory = $true)][string] $Title)

    if (-not $script:LogPath) {
        return
    }

    $lines = @(
        $Title,
        ("=" * $Title.Length),
        "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')",
        "Computer: $env:COMPUTERNAME",
        "User: $env:USERNAME",
        "Folder: $script:BackupPath",
        ""
    )
    Set-Content -Path $script:LogPath -Value $lines -Encoding UTF8
}

function Write-LogFooter {
    param([string] $Result = "Completed")

    if (-not $script:LogPath) {
        return
    }

    $footer = [System.Collections.Generic.List[string]]::new()
    $footer.Add("")
    $footer.Add("Run Summary")
    $footer.Add("===========")
    $footer.Add("Finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
    $footer.Add("Result: $Result")

    if ($script:LogWarnings.Count -gt 0) {
        $footer.Add("")
        $footer.Add("Warnings")
        $footer.Add("--------")
        foreach ($warning in $script:LogWarnings) {
            $footer.Add("- $warning")
        }
    }
    else {
        $footer.Add("")
        $footer.Add("Warnings: none")
    }

    if ($script:LogErrors.Count -gt 0) {
        $footer.Add("")
        $footer.Add("Errors")
        $footer.Add("------")
        foreach ($errorText in $script:LogErrors) {
            $footer.Add("- $errorText")
        }
    }
    else {
        $footer.Add("Errors: none")
    }

    Add-Content -Path $script:LogPath -Value $footer -Encoding UTF8
}

function ConvertTo-HtmlText {
    param([AllowNull()][string] $Text)

    if ($null -eq $Text) {
        return ""
    }

    return [System.Net.WebUtility]::HtmlEncode($Text)
}

function New-HtmlReportFromText {
    param(
        [Parameter(Mandatory = $true)][string] $Title,
        [Parameter(Mandatory = $true)][string] $Text,
        [Parameter(Mandatory = $true)][string] $OutputPath
    )

    $encodedTitle = ConvertTo-HtmlText $Title
    $encodedText = ConvertTo-HtmlText $Text
    $generated = ConvertTo-HtmlText (Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz")

    $html = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$encodedTitle</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #000000;
      --panel: #000000;
      --text: #ffffff;
      --muted: #c7c7c7;
      --border: #ffffff;
    }
    body {
      margin: 0;
      font-family: Segoe UI, Arial, sans-serif;
      background: var(--bg);
      color: var(--text);
      line-height: 1.5;
    }
    main {
      max-width: 980px;
      margin: 0 auto;
      padding: 32px 20px 48px;
    }
    header {
      border-bottom: 1px solid var(--border);
      margin-bottom: 22px;
      padding-bottom: 18px;
    }
    h1 {
      margin: 0 0 6px;
      font-size: 28px;
      font-weight: 650;
      letter-spacing: 0;
    }
    .meta {
      color: var(--muted);
      font-size: 14px;
    }
    .panel {
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 0;
      overflow: hidden;
    }
    pre {
      margin: 0;
      padding: 22px;
      white-space: pre;
      overflow-x: auto;
      overflow-wrap: normal;
      font-family: Consolas, Cascadia Mono, monospace;
      font-size: 13px;
    }
  </style>
</head>
<body>
  <main>
    <header>
      <h1>$encodedTitle</h1>
      <div class="meta">Generated $generated</div>
    </header>
    <section class="panel">
      <pre>$encodedText</pre>
    </section>
  </main>
</body>
</html>
"@

    $html | Set-Content -Path $OutputPath -Encoding UTF8
    return $OutputPath
}

function Open-ReportInBrowser {
    param([Parameter(Mandatory = $true)][string] $Path)

    try {
        Start-Process -FilePath $Path
    }
    catch {
        Write-Log "WARN : Could not open report in browser: $($_.Exception.Message)"
    }
}

function Add-PreviewItem {
    param(
        [Parameter(Mandatory = $true)][System.Text.StringBuilder] $Builder,
        [Parameter(Mandatory = $true)][string] $Area,
        [AllowNull()][string] $Current,
        [Parameter(Mandatory = $true)][string] $Planned,
        [AllowNull()][string] $Notes
    )

    [void] $Builder.AppendLine("- $Area")
    [void] $Builder.AppendLine("  Current: $Current")
    [void] $Builder.AppendLine("  Planned: $Planned")
    if (-not [string]::IsNullOrWhiteSpace($Notes)) {
        [void] $Builder.AppendLine("  Notes: $Notes")
    }
    [void] $Builder.AppendLine("")
}

function Get-LatestHtmlReport {
    $candidateFolders = @()
    $reportsFolder = Get-ReportsFolder
    $runsFolder = Get-ChangesFolder

    if (Test-Path $reportsFolder) {
        $candidateFolders += [pscustomobject]@{ Path = $reportsFolder; Recurse = $false }
    }
    if (Test-Path $runsFolder) {
        $candidateFolders += [pscustomobject]@{ Path = $runsFolder; Recurse = $true }
    }

    $reports = foreach ($folder in $candidateFolders) {
        Get-ChildItem -Path $folder.Path -Filter "*.html" -File -Recurse:$folder.Recurse -ErrorAction SilentlyContinue
    }

    $reports |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Invoke-OpenLastReport {
    $latestReport = Get-LatestHtmlReport
    if ($null -eq $latestReport) {
        Write-ConsoleStatus -Tag "WARN" -Message "No W11 Optimiser HTML reports were found under Desktop\W11 Optimiser." -Color Yellow
        exit 1
    }

    Write-Host "Opening latest report: $($latestReport.FullName)" -ForegroundColor Green
    Open-ReportInBrowser -Path $latestReport.FullName
}

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][scriptblock] $Action,
        [switch] $Required
    )

    Write-Log "START: $Name"
    try {
        & $Action
        Write-Log "DONE : $Name"
    }
    catch {
        if ($Required) {
            Write-Log "ERROR: $Name failed: $($_.Exception.Message)"
            throw
        }
        Write-Log "WARN : $Name failed: $($_.Exception.Message)"
    }
}

function Get-RegistryValueSafe {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $Name
    )

    try {
        return Get-ItemPropertyValue -Path $Path -Name $Name -ErrorAction Stop
    }
    catch {
        return "(missing)"
    }
}

function Get-ActivePowerSchemeGuid {
    $text = powercfg /GETACTIVESCHEME | Out-String
    if ($text -match "([0-9a-fA-F-]{36})") {
        return $Matches[1]
    }
    throw "Could not detect active power scheme."
}

function Write-ObjectBlock {
    param(
        [Parameter(ValueFromPipeline = $true)] $InputObject,
        [Parameter(Mandatory = $true)][System.Text.StringBuilder] $Builder
    )

    process {
        if ($null -eq $InputObject) {
            [void] $Builder.AppendLine("(no data)")
            return
        }

        $text = $InputObject | Format-List * | Out-String -Width 220
        foreach ($line in ($text -split "`r?`n")) {
            if ($line.Trim().Length -gt 0) {
                [void] $Builder.AppendLine($line)
            }
        }
    }
}

function Add-ReportSection {
    param(
        [Parameter(Mandatory = $true)][System.Text.StringBuilder] $Builder,
        [Parameter(Mandatory = $true)][string] $Title
    )

    [void] $Builder.AppendLine("")
    [void] $Builder.AppendLine("=" * 80)
    [void] $Builder.AppendLine($Title)
    [void] $Builder.AppendLine("=" * 80)
}

function Add-CommandToReport {
    param(
        [Parameter(Mandatory = $true)][System.Text.StringBuilder] $Builder,
        [Parameter(Mandatory = $true)][string] $Command,
        [string[]] $Arguments = @()
    )

    [void] $Builder.AppendLine("")
    [void] $Builder.AppendLine(("> {0} {1}" -f $Command, ($Arguments -join " ")).Trim())
    try {
        $output = & $Command @Arguments 2>&1 | Out-String -Width 220
        if ([string]::IsNullOrWhiteSpace($output)) {
            [void] $Builder.AppendLine("(no output)")
        }
        else {
            [void] $Builder.AppendLine($output.TrimEnd())
        }
    }
    catch {
        [void] $Builder.AppendLine("Failed: $($_.Exception.Message)")
    }
}

function Add-StorageSpaceReport {
    param([Parameter(Mandatory = $true)][System.Text.StringBuilder] $Builder)

    try {
        Get-Volume |
            Where-Object { $_.DriveLetter -and $_.DriveType -eq "Fixed" } |
            Sort-Object DriveLetter |
            ForEach-Object {
                $sizeGb = if ($_.Size) { [math]::Round($_.Size / 1GB, 1) } else { $null }
                $freeGb = if ($_.SizeRemaining) { [math]::Round($_.SizeRemaining / 1GB, 1) } else { $null }
                $freePercent = if ($_.Size -and $_.SizeRemaining) { [math]::Round(($_.SizeRemaining / $_.Size) * 100, 1) } else { $null }
                [pscustomobject]@{
                    Drive       = "$($_.DriveLetter):"
                    Label       = $_.FileSystemLabel
                    FileSystem  = $_.FileSystem
                    Health      = $_.HealthStatus
                    SizeGB      = $sizeGb
                    FreeGB      = $freeGb
                    FreePercent = $freePercent
                    Note        = if ($freePercent -ne $null -and $freePercent -lt 15) { "Low free space can affect updates/cache/game installs" } else { "" }
                }
            } | Write-ObjectBlock -Builder $Builder
    }
    catch {
        [void] $Builder.AppendLine("Volume free-space query failed: $($_.Exception.Message)")
    }
}

function Get-StartupRunEntries {
    $locations = @(
        @{ Scope = "Current user"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" },
        @{ Scope = "Local machine"; Path = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" },
        @{ Scope = "Local machine WOW6432Node"; Path = "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" }
    )

    foreach ($location in $locations) {
        try {
            $props = Get-ItemProperty -Path $location.Path -ErrorAction Stop
            foreach ($prop in $props.PSObject.Properties) {
                if ($prop.Name -notmatch "^PS") {
                    [pscustomobject]@{
                        Scope = $location.Scope
                        Name  = $prop.Name
                        Value = $prop.Value
                        Path  = $location.Path
                    }
                }
            }
        }
        catch {
            [pscustomobject]@{
                Scope = $location.Scope
                Name  = "(unavailable)"
                Value = $_.Exception.Message
                Path  = $location.Path
            }
        }
    }
}

function Invoke-Audit {
    $reportsFolder = Get-ReportsFolder
    $null = New-Item -ItemType Directory -Path $reportsFolder -Force
    $timestamp = Get-FriendlyTimestamp
    $reportPath = Join-Path $reportsFolder "Audit Report $timestamp.html"
    $builder = [System.Text.StringBuilder]::new()

    [void] $builder.AppendLine("W11 Optimiser Audit")
    [void] $builder.AppendLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
    [void] $builder.AppendLine("Computer: $env:COMPUTERNAME")
    [void] $builder.AppendLine("User: $env:USERNAME")
    [void] $builder.AppendLine("Admin: $(Test-IsAdmin)")
    [void] $builder.AppendLine("Report path: $reportPath")
    $gpuSummary = Get-GpuVendorSummary
    [void] $builder.AppendLine("Detected GPU vendor(s): $($gpuSummary.Vendors)")
    [void] $builder.AppendLine("Detected GPU name(s): $($gpuSummary.Names)")
    [void] $builder.AppendLine("Battery detected: $(Test-HasBattery)")

    Add-ReportSection -Builder $builder -Title "Windows Version / Build"
    try {
        Get-ComputerInfo | Select-Object OsName, OsDisplayVersion, OsVersion, OsBuildNumber, WindowsVersion, BiosFirmwareType, CsSystemType, CsManufacturer, CsModel | Write-ObjectBlock -Builder $builder
    }
    catch {
        [void] $builder.AppendLine("Get-ComputerInfo failed: $($_.Exception.Message)")
    }

    Add-ReportSection -Builder $builder -Title "CPU"
    try {
        Get-CimInstance Win32_Processor | Select-Object Name, Manufacturer, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed, CurrentClockSpeed, L2CacheSize, L3CacheSize, VirtualizationFirmwareEnabled | Write-ObjectBlock -Builder $builder
    }
    catch {
        [void] $builder.AppendLine("CPU query failed: $($_.Exception.Message)")
    }

    Add-ReportSection -Builder $builder -Title "RAM"
    try {
        Get-CimInstance Win32_ComputerSystem | Select-Object TotalPhysicalMemory | Write-ObjectBlock -Builder $builder
        Get-CimInstance Win32_PhysicalMemory | Select-Object BankLabel, Manufacturer, PartNumber, Capacity, Speed, ConfiguredClockSpeed, DeviceLocator | Write-ObjectBlock -Builder $builder
    }
    catch {
        [void] $builder.AppendLine("RAM query failed: $($_.Exception.Message)")
    }

    Add-ReportSection -Builder $builder -Title "GPU / Display Drivers"
    try {
        Get-CimInstance Win32_VideoController | Select-Object Name, AdapterRAM, DriverVersion, DriverDate, VideoModeDescription, CurrentHorizontalResolution, CurrentVerticalResolution, CurrentRefreshRate, Status | Write-ObjectBlock -Builder $builder
        Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceClass -eq "DISPLAY" -or $_.DeviceName -match "AMD|Radeon|NVIDIA|Intel" } | Select-Object DeviceName, Manufacturer, DriverVersion, DriverDate, InfName, IsSigned | Write-ObjectBlock -Builder $builder
    }
    catch {
        [void] $builder.AppendLine("GPU query failed: $($_.Exception.Message)")
    }
    [void] $builder.AppendLine("HAGS: $(Get-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode')")

    Add-ReportSection -Builder $builder -Title "GPU Vendor Software Detection"
    try {
        $gpuSoftware = @()
        $roots = @(
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        foreach ($root in $roots) {
            $gpuSoftware += Get-ItemProperty -Path $root -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -match "AMD|Radeon|Adrenalin|NVIDIA|GeForce|Intel.*Graphics|Intel.*Arc|Intel.*Driver" } |
                Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
        }
        if ($gpuSoftware.Count -eq 0) {
            [void] $builder.AppendLine("(No AMD/NVIDIA/Intel GPU software uninstall entries detected)")
        }
        else {
            $gpuSoftware | Sort-Object DisplayName -Unique | Write-ObjectBlock -Builder $builder
        }
    }
    catch {
        [void] $builder.AppendLine("GPU vendor software query failed: $($_.Exception.Message)")
    }

    Add-ReportSection -Builder $builder -Title "Storage / TRIM"
    try {
        Get-CimInstance Win32_DiskDrive | Select-Object Model, InterfaceType, MediaType, Size, Status, SerialNumber | Write-ObjectBlock -Builder $builder
        Get-PhysicalDisk | Select-Object FriendlyName, MediaType, BusType, HealthStatus, OperationalStatus, Size | Write-ObjectBlock -Builder $builder
    }
    catch {
        [void] $builder.AppendLine("Storage query failed: $($_.Exception.Message)")
    }
    Add-StorageSpaceReport -Builder $builder
    Add-CommandToReport -Builder $builder -Command "fsutil" -Arguments @("behavior", "query", "DisableDeleteNotify")

    Add-ReportSection -Builder $builder -Title "Power Plans / CPU / PCIe / USB Power Settings"
    Add-CommandToReport -Builder $builder -Command "powercfg" -Arguments @("/GETACTIVESCHEME")
    Add-CommandToReport -Builder $builder -Command "powercfg" -Arguments @("/L")
    Add-CommandToReport -Builder $builder -Command "powercfg" -Arguments @("/QUERY", "SCHEME_CURRENT", "SUB_PROCESSOR")
    Add-CommandToReport -Builder $builder -Command "powercfg" -Arguments @("/QUERY", "SCHEME_CURRENT", "SUB_PCIEXPRESS")
    Add-CommandToReport -Builder $builder -Command "powercfg" -Arguments @("/QUERY", "SCHEME_CURRENT", $PowerGuids.Usb, $PowerGuids.UsbSelectiveSuspend)

    Add-ReportSection -Builder $builder -Title "Game Bar / Game DVR / Captures"
    [pscustomobject][ordered]@{
        "HKCU GameBar AutoGameModeEnabled" = Get-RegistryValueSafe -Path "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled"
        "HKCU GameConfigStore GameDVR_Enabled" = Get-RegistryValueSafe -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled"
        "HKCU GameDVR AppCaptureEnabled" = Get-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled"
        "HKCU GameDVR HistoricalCaptureEnabled" = Get-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "HistoricalCaptureEnabled"
        "HKLM AllowGameDVR" = Get-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR"
    } | Write-ObjectBlock -Builder $builder

    Add-ReportSection -Builder $builder -Title "VBS / Memory Integrity / Device Guard"
    [void] $builder.AppendLine("Memory Integrity Enabled: $(Get-RegistryValueSafe -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name 'Enabled')")
    try {
        Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard | Select-Object SecurityServicesConfigured, SecurityServicesRunning, VirtualizationBasedSecurityStatus | Write-ObjectBlock -Builder $builder
    }
    catch {
        [void] $builder.AppendLine("DeviceGuard query failed: $($_.Exception.Message)")
    }

    Add-ReportSection -Builder $builder -Title "Startup Entries"
    Get-StartupRunEntries | Sort-Object Scope, Name | Write-ObjectBlock -Builder $builder
    try {
        Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User | Sort-Object Location, Name | Write-ObjectBlock -Builder $builder
    }
    catch {
        [void] $builder.AppendLine("Win32_StartupCommand failed: $($_.Exception.Message)")
    }

    Add-ReportSection -Builder $builder -Title "Network Adapter Power Management"
    try {
        Get-NetAdapter | Where-Object Status -eq "Up" | Select-Object Name, InterfaceDescription, LinkSpeed, Status, MacAddress | Write-ObjectBlock -Builder $builder
        Get-NetworkAdapterPowerState | Write-ObjectBlock -Builder $builder
    }
    catch {
        [void] $builder.AppendLine("Network adapter power query failed: $($_.Exception.Message)")
    }

    Add-ReportSection -Builder $builder -Title "Recommended Manual Checks"
    [void] $builder.AppendLine("- AMD Adrenalin: FreeSync on if supported, Anti-Lag per-game, Chill off unless needed, Enhanced Sync per-game, shader cache default/on.")
    [void] $builder.AppendLine("- NVIDIA Control Panel/App: G-SYNC on if supported, Reflex per-game where available, Low Latency Mode per-game if Reflex is unavailable, Shader Cache on/default.")
    [void] $builder.AppendLine("- Intel Arc/Graphics Command Center: VRR/adaptive sync where supported, low-latency/game profiles per-game, driver shader/cache defaults.")
    [void] $builder.AppendLine("- Any GPU: prefer official control panels and per-game profiles; avoid random registry hacks.")
    [void] $builder.AppendLine("- BIOS/UEFI: confirm XMP/EXPO stability, Resizable BAR/Above 4G where supported, current BIOS/microcode. Do not auto-overclock/undervolt.")
    [void] $builder.AppendLine("- Startup apps: review manually; do not disable SecurityHealth.")
    [void] $builder.AppendLine("- Laptop/battery systems: use these optimizations while plugged in; check OEM performance mode and cooling profile manually.")

    New-HtmlReportFromText -Title "W11 Optimiser - Audit" -Text $builder.ToString() -OutputPath $reportPath | Out-Null
    Write-Host "Audit report written to: $reportPath" -ForegroundColor Green
    Open-ReportInBrowser -Path $reportPath
}

function Invoke-Preview {
    $reportsFolder = Get-ReportsFolder
    $null = New-Item -ItemType Directory -Path $reportsFolder -Force
    $timestamp = Get-FriendlyTimestamp
    $reportPath = Join-Path $reportsFolder "Preview Report $timestamp.html"
    $builder = [System.Text.StringBuilder]::new()
    $gpuSummary = Get-GpuVendorSummary

    [void] $builder.AppendLine("W11 Optimiser Preview")
    [void] $builder.AppendLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
    [void] $builder.AppendLine("Computer: $env:COMPUTERNAME")
    [void] $builder.AppendLine("User: $env:USERNAME")
    [void] $builder.AppendLine("Admin: $(Test-IsAdmin)")
    [void] $builder.AppendLine("Report path: $reportPath")
    [void] $builder.AppendLine("No changes were made by this preview.")
    [void] $builder.AppendLine("Detected GPU vendor(s): $($gpuSummary.Vendors)")
    [void] $builder.AppendLine("Detected GPU name(s): $($gpuSummary.Names)")
    [void] $builder.AppendLine("Battery detected: $(Test-HasBattery)")

    Add-ReportSection -Builder $builder -Title "Planned Safe Optimisation Changes"

    $activePlan = try { Get-ActivePowerSchemeGuid } catch { "Unavailable: $($_.Exception.Message)" }
    Add-PreviewItem -Builder $builder -Area "System restore point" -Current "Not changed during preview" -Planned "Create or accept a recent W11 Optimiser restore point before changes" -Notes "Can be explicitly skipped with -SkipRestorePoint when System Restore is unavailable."
    Add-PreviewItem -Builder $builder -Area "Backup and undo state" -Current "Not changed during preview" -Planned "Create Desktop\W11 Optimiser\Runs\Safe Run <timestamp> with State.json, registry backups, and power-plan backup" -Notes "Used by UndoLatest."
    Add-PreviewItem -Builder $builder -Area "Active power plan" -Current $activePlan -Planned "Use Ultimate Performance if available or creatable, otherwise High Performance" -Notes "Then apply conservative AC-only processor, PCIe, USB, and wireless settings."
    Add-PreviewItem -Builder $builder -Area "Processor AC minimum" -Current "See Current Power Details below" -Planned "10 percent" -Notes "Keeps the CPU responsive without pinning minimum to 100 percent."
    Add-PreviewItem -Builder $builder -Area "Processor AC maximum" -Current "See Current Power Details below" -Planned "100 percent" -Notes ""
    Add-PreviewItem -Builder $builder -Area "PCIe Link State Power Management on AC" -Current "See Current Power Details below" -Planned "Off" -Notes ""
    Add-PreviewItem -Builder $builder -Area "USB selective suspend on AC" -Current "See Current Power Details below" -Planned "Off" -Notes ""
    Add-PreviewItem -Builder $builder -Area "Wireless adapter power saving on AC" -Current "See Current Power Details below" -Planned "Maximum Performance" -Notes ""

    Add-PreviewItem -Builder $builder -Area "GameDVR_Enabled" -Current (Get-RegistryValueSafe -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled") -Planned "0" -Notes "Disables Game DVR/background capture overhead."
    Add-PreviewItem -Builder $builder -Area "AppCaptureEnabled" -Current (Get-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled") -Planned "0" -Notes ""
    Add-PreviewItem -Builder $builder -Area "HistoricalCaptureEnabled" -Current (Get-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "HistoricalCaptureEnabled") -Planned "0" -Notes ""
    Add-PreviewItem -Builder $builder -Area "AllowGameDVR policy" -Current (Get-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR") -Planned "0" -Notes ""
    Add-PreviewItem -Builder $builder -Area "AutoGameModeEnabled" -Current (Get-RegistryValueSafe -Path "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled") -Planned "1" -Notes "Keeps Windows Game Mode enabled."

    Add-PreviewItem -Builder $builder -Area "VisualFXSetting" -Current (Get-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting") -Planned "3" -Notes "Conservative custom visual responsiveness profile."
    Add-PreviewItem -Builder $builder -Area "MenuShowDelay" -Current (Get-RegistryValueSafe -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay") -Planned "100" -Notes ""
    Add-PreviewItem -Builder $builder -Area "DragFullWindows" -Current (Get-RegistryValueSafe -Path "HKCU:\Control Panel\Desktop" -Name "DragFullWindows") -Planned "1" -Notes ""
    Add-PreviewItem -Builder $builder -Area "MinAnimate" -Current (Get-RegistryValueSafe -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate") -Planned "0" -Notes ""

    $trimStatus = try { (fsutil behavior query DisableDeleteNotify | Out-String).Trim() } catch { "Unavailable: $($_.Exception.Message)" }
    Add-PreviewItem -Builder $builder -Area "TRIM DisableDeleteNotify" -Current $trimStatus -Planned "Set DisableDeleteNotify to 0" -Notes "Enables TRIM for supported filesystems."
    Add-PreviewItem -Builder $builder -Area "SSD ReTrim maintenance" -Current "Not changed during preview" -Planned "Run ReTrim on fixed NTFS/ReFS drive-letter volumes" -Notes ""
    Add-PreviewItem -Builder $builder -Area "Network adapter power saving" -Current "See Physical Network Adapters below" -Planned "Disable 'Allow computer to turn off this device' where supported on active physical adapters" -Notes "Can improve stability/throughput on some USB Wi-Fi adapters; virtual VPN/Hyper-V-style adapters are not targeted."
    Add-PreviewItem -Builder $builder -Area "Temp/cache cleanup" -Current "Not changed during preview" -Planned "Skip cleanup when -SkipTempCleanup is used; otherwise remove old temp files and rebuildable GPU shader caches" -Notes "Launcher recommended path skips cleanup."

    Add-ReportSection -Builder $builder -Title "Current Power Details"
    Add-CommandToReport -Builder $builder -Command "powercfg" -Arguments @("/GETACTIVESCHEME")
    Add-CommandToReport -Builder $builder -Command "powercfg" -Arguments @("/QUERY", "SCHEME_CURRENT", "SUB_PROCESSOR")
    Add-CommandToReport -Builder $builder -Command "powercfg" -Arguments @("/QUERY", "SCHEME_CURRENT", "SUB_PCIEXPRESS")
    Add-CommandToReport -Builder $builder -Command "powercfg" -Arguments @("/QUERY", "SCHEME_CURRENT", $PowerGuids.Usb, $PowerGuids.UsbSelectiveSuspend)
    Add-CommandToReport -Builder $builder -Command "powercfg" -Arguments @("/QUERY", "SCHEME_CURRENT", $PowerGuids.WirelessAdapter, $PowerGuids.WirelessPowerSaving)

    Add-ReportSection -Builder $builder -Title "Physical Network Adapters"
    try {
        Get-NetworkAdapterPowerState |
            Where-Object { $_.Status -eq "Up" } |
            Write-ObjectBlock -Builder $builder
    }
    catch {
        [void] $builder.AppendLine("Physical adapter query failed: $($_.Exception.Message)")
    }

    Add-ReportSection -Builder $builder -Title "What Preview Refuses To Change"
    [void] $builder.AppendLine("- Preview does not create restore points, backups, registry keys, reports outside the Reports folder, or run folders.")
    [void] $builder.AppendLine("- Preview does not change power plans, Game DVR, visual settings, TRIM, network adapters, temp files, Defender, Firewall, Windows Update, drivers, services, BIOS, HAGS, overclocking, undervolting, or startup apps.")

    New-HtmlReportFromText -Title "W11 Optimiser - Preview" -Text $builder.ToString() -OutputPath $reportPath | Out-Null
    Write-Host "Preview report written to: $reportPath" -ForegroundColor Green
    Open-ReportInBrowser -Path $reportPath
}

function Export-RegistryKey {
    param(
        [Parameter(Mandatory = $true)][string] $RegPath,
        [Parameter(Mandatory = $true)][string] $FileName
    )

    $destination = Join-Path $script:BackupPath $FileName
    $markerPath = Join-Path $script:BackupPath ($FileName + ".missing.json")
    $powerShellPath = $RegPath -replace "^HKCU\\", "HKCU:\" -replace "^HKLM\\", "HKLM:\"

    if (-not (Test-Path $powerShellPath)) {
        [ordered]@{
            RegistryPath = $RegPath
            Status       = "MissingBeforeOptimisation"
            Timestamp    = Get-Date -Format "o"
        } | ConvertTo-Json | Set-Content -Path $markerPath -Encoding UTF8
        Write-Log "Registry key missing before optimization, marker written: $RegPath"
        return
    }

    $output = & reg.exe export $RegPath $destination /y 2>&1
    if ($LASTEXITCODE -eq 0 -and (Test-Path $destination)) {
        Write-Log "Exported $RegPath to $destination"
    }
    else {
        [ordered]@{
            RegistryPath = $RegPath
            Status       = "ExportFailedBeforeOptimisation"
            Timestamp    = Get-Date -Format "o"
        } | ConvertTo-Json | Set-Content -Path $markerPath -Encoding UTF8
        Write-Log "Registry key export failed, marker written: $RegPath"
        if (-not [string]::IsNullOrWhiteSpace(($output | Out-String))) {
            Write-Log "reg.exe export output: $(($output | Out-String).Trim())"
        }
    }
}

function Set-RegistryDword {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][int] $Value
    )

    if (-not (Test-Path $Path)) {
        $null = New-Item -Path $Path -Force
    }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
    Write-Log "Set $Path\$Name = $Value"
}

function Set-RegistryString {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $Name,
        [Parameter(Mandatory = $true)][string] $Value
    )

    if (-not (Test-Path $Path)) {
        $null = New-Item -Path $Path -Force
    }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType String -Force | Out-Null
    Write-Log "Set $Path\$Name = $Value"
}

function Normalize-GuidText {
    param($Value)

    if ($null -eq $Value) {
        return ""
    }
    return ([string] $Value).Trim("{}").ToUpperInvariant()
}

function Get-NetworkAdapterClassKeyPath {
    param([Parameter(Mandatory = $true)] $Adapter)

    $targetGuid = Normalize-GuidText -Value $Adapter.InterfaceGuid
    if ([string]::IsNullOrWhiteSpace($targetGuid)) {
        return $null
    }

    foreach ($key in Get-ChildItem -Path $NetworkAdapterClassKeyRoot -ErrorAction Stop) {
        try {
            $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
            if ((Normalize-GuidText -Value $props.NetCfgInstanceId) -eq $targetGuid) {
                return $key.PSPath
            }
        }
        catch {
        }
    }

    return $null
}

function Get-PnPCapabilitiesState {
    param([string] $ClassRegistryPath)

    if ([string]::IsNullOrWhiteSpace($ClassRegistryPath)) {
        return [pscustomobject][ordered]@{
            Exists = $false
            Value  = $null
        }
    }

    try {
        $props = Get-ItemProperty -LiteralPath $ClassRegistryPath -ErrorAction Stop
        $property = $props.PSObject.Properties["PnPCapabilities"]
        if ($null -eq $property) {
            return [pscustomobject][ordered]@{
                Exists = $false
                Value  = $null
            }
        }

        return [pscustomobject][ordered]@{
            Exists = $true
            Value  = [int] $property.Value
        }
    }
    catch {
        return [pscustomobject][ordered]@{
            Exists = $false
            Value  = $null
        }
    }
}

function Get-NetworkAdapterPowerState {
    $adapters = Get-NetAdapter -Physical -ErrorAction Stop

    foreach ($adapter in $adapters) {
        $powerState = $null
        try {
            $powerState = Get-NetAdapterPowerManagement -Name $adapter.Name -ErrorAction Stop
        }
        catch {
        }

        $classKeyPath = $null
        try {
            $classKeyPath = Get-NetworkAdapterClassKeyPath -Adapter $adapter
        }
        catch {
        }
        $pnpState = Get-PnPCapabilitiesState -ClassRegistryPath $classKeyPath

        [pscustomobject][ordered]@{
            Name                           = $adapter.Name
            InterfaceDescription           = $adapter.InterfaceDescription
            Status                         = $adapter.Status
            LinkSpeed                      = $adapter.LinkSpeed
            InterfaceGuid                  = [string] $adapter.InterfaceGuid
            AllowComputerToTurnOffDevice   = if ($powerState) { $powerState.AllowComputerToTurnOffDevice } else { "Unavailable" }
            SelectiveSuspend               = if ($powerState) { $powerState.SelectiveSuspend } else { "Unavailable" }
            DeviceSleepOnDisconnect        = if ($powerState) { $powerState.DeviceSleepOnDisconnect } else { "Unavailable" }
            ClassRegistryPath              = $classKeyPath
            PnPCapabilitiesExists          = $pnpState.Exists
            PnPCapabilities                = $pnpState.Value
        }
    }
}

function Set-AdapterPowerOffPermissionDisabled {
    param([Parameter(Mandatory = $true)] $Adapter)

    $currentPower = $null
    try {
        $currentPower = Get-NetAdapterPowerManagement -Name $Adapter.Name -ErrorAction Stop
        if ($currentPower.AllowComputerToTurnOffDevice -eq "Disabled") {
            Write-Log "Adapter sleep permission already disabled for: $($Adapter.Name)"
            return
        }

        try {
            $currentPower | Set-CimInstance -Property @{ AllowComputerToTurnOffDevice = "Disabled" } -ErrorAction Stop
            Start-Sleep -Milliseconds 250
            $afterPower = Get-NetAdapterPowerManagement -Name $Adapter.Name -ErrorAction Stop
            if ($afterPower.AllowComputerToTurnOffDevice -eq "Disabled") {
                Write-Log "Disabled adapter sleep permission for: $($Adapter.Name)"
                return
            }
            Write-Log "WARN : CIM write did not change adapter sleep permission for $($Adapter.Name); using registry fallback."
        }
        catch {
            Write-Log "WARN : CIM adapter sleep write unsupported for $($Adapter.Name): $($_.Exception.Message)"
        }
    }
    catch {
        Write-Log "WARN : Could not query adapter sleep permission for $($Adapter.Name): $($_.Exception.Message)"
    }

    $classKeyPath = Get-NetworkAdapterClassKeyPath -Adapter $Adapter
    if ([string]::IsNullOrWhiteSpace($classKeyPath)) {
        Write-Log "WARN : Could not find network adapter registry key for $($Adapter.Name)."
        return
    }

    $pnpState = Get-PnPCapabilitiesState -ClassRegistryPath $classKeyPath
    $oldValue = if ($pnpState.Exists) { [int] $pnpState.Value } else { 0 }
    $newValue = $oldValue -bor $NetworkAdapterPowerOffDisableMask

    New-ItemProperty -LiteralPath $classKeyPath -Name "PnPCapabilities" -Value $newValue -PropertyType DWord -Force | Out-Null
    Write-Log "Set adapter sleep registry fallback for $($Adapter.Name): PnPCapabilities $oldValue -> $newValue"
    Write-Log "Adapter $($Adapter.Name) may need reconnect/restart before Windows reports the new sleep permission."
}

function Restore-NetworkAdapterPowerState {
    param([Parameter(Mandatory = $true)] $NetworkState)

    foreach ($adapter in @($NetworkState)) {
        if ($adapter.Name -and $adapter.AllowComputerToTurnOffDevice -and $adapter.AllowComputerToTurnOffDevice -ne "Unavailable") {
            try {
                $currentPower = Get-NetAdapterPowerManagement -Name $adapter.Name -ErrorAction Stop
                $currentPower | Set-CimInstance -Property @{ AllowComputerToTurnOffDevice = $adapter.AllowComputerToTurnOffDevice } -ErrorAction Stop
                Write-Log "Restored CIM adapter sleep permission for $($adapter.Name) to $($adapter.AllowComputerToTurnOffDevice)"
            }
            catch {
                Write-Log "WARN : Could not restore CIM adapter sleep permission for $($adapter.Name): $($_.Exception.Message)"
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($adapter.ClassRegistryPath)) {
            try {
                if ($adapter.PnPCapabilitiesExists -eq $true) {
                    New-ItemProperty -LiteralPath $adapter.ClassRegistryPath -Name "PnPCapabilities" -Value ([int] $adapter.PnPCapabilities) -PropertyType DWord -Force | Out-Null
                    Write-Log "Restored PnPCapabilities for $($adapter.Name) to $($adapter.PnPCapabilities)"
                }
                else {
                    Remove-ItemProperty -LiteralPath $adapter.ClassRegistryPath -Name "PnPCapabilities" -ErrorAction SilentlyContinue
                    Write-Log "Removed PnPCapabilities for $($adapter.Name) because it was absent before the run"
                }
            }
            catch {
                Write-Log "WARN : Could not restore network registry power state for $($adapter.Name): $($_.Exception.Message)"
            }
        }
    }
}

function Save-State {
    $activeScheme = Get-ActivePowerSchemeGuid
    $trimText = fsutil behavior query DisableDeleteNotify | Out-String
    $ntfsTrimValue = $null
    if ($trimText -match "NTFS DisableDeleteNotify =\s*(\d+)") {
        $ntfsTrimValue = [int] $Matches[1]
    }

    [ordered]@{
        Timestamp = Get-Date -Format "o"
        PreviousActivePowerSchemeGuid = $activeScheme
        NtfsDisableDeleteNotify = $ntfsTrimValue
    } | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $script:BackupPath "State.json") -Encoding UTF8

    powercfg /export (Join-Path $script:BackupPath "Previous Active Power Plan.pow") $activeScheme | Out-Null
    Write-Log "Saved current active power scheme: $activeScheme"

    try {
        Get-NetworkAdapterPowerState | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $script:BackupPath "Network Power Management.json") -Encoding UTF8
        Write-Log "Saved network adapter power management state."
    }
    catch {
        Write-Log "WARN : Could not save network adapter power management state: $($_.Exception.Message)"
    }

    Write-Log "Startup entries remain manual review only."
}

function Create-RestorePointOrStop {
    $descriptionPrefix = "Before safe gaming optimizations"
    try {
        Checkpoint-Computer -Description "$descriptionPrefix $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -RestorePointType "MODIFY_SETTINGS"
        return
    }
    catch {
        $checkpointError = $_.Exception.Message
        $recentRestorePoint = $null
        try {
            $recentRestorePoint = Get-ComputerRestorePoint |
                Where-Object {
                    $_.Description -like "$descriptionPrefix*" -and
                    [Management.ManagementDateTimeConverter]::ToDateTime($_.CreationTime) -gt (Get-Date).AddHours(-2)
                } |
                Sort-Object CreationTime -Descending |
                Select-Object -First 1
        }
        catch {
            Write-Log "WARN : Could not query existing restore points: $($_.Exception.Message)"
        }

        if ($null -ne $recentRestorePoint) {
            Write-Log "Using recent restore point after Checkpoint-Computer failed: $($recentRestorePoint.Description)"
            Write-Log "Checkpoint-Computer failure was: $checkpointError"
            return
        }

        throw
    }
}

function Backup-RegistryKeys {
    Export-RegistryKey -RegPath "HKCU\System\GameConfigStore" -FileName "HKCU_System_GameConfigStore.reg"
    Export-RegistryKey -RegPath "HKCU\Software\Microsoft\GameBar" -FileName "HKCU_Microsoft_GameBar.reg"
    Export-RegistryKey -RegPath "HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR" -FileName "HKCU_GameDVR.reg"
    Export-RegistryKey -RegPath "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -FileName "HKLM_Policies_GameDVR.reg"
    Export-RegistryKey -RegPath "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -FileName "HKCU_VisualEffects.reg"
    Export-RegistryKey -RegPath "HKCU\Control Panel\Desktop" -FileName "HKCU_ControlPanel_Desktop.reg"
    Export-RegistryKey -RegPath "HKCU\Control Panel\Desktop\WindowMetrics" -FileName "HKCU_WindowMetrics.reg"
}

function Enable-PerformancePowerPlan {
    $planList = powercfg /L | Out-String
    $targetGuid = $null
    $ultimateLine = ($planList -split "`r?`n") | Where-Object { $_ -match "\(Ultimate Performance\)" } | Select-Object -First 1

    if ($ultimateLine -and $ultimateLine -match "([0-9a-fA-F-]{36})") {
        $targetGuid = $Matches[1]
        Write-Log "Ultimate Performance already exists: $targetGuid"
    }
    else {
        $duplicateOutput = powercfg /DUPLICATESCHEME $PowerGuids.UltimatePerformance 2>&1 | Out-String
        if ($duplicateOutput -match "([0-9a-fA-F-]{36})") {
            $targetGuid = $Matches[1]
            Write-Log "Created Ultimate Performance plan: $targetGuid"
        }
        else {
            $targetGuid = $PowerGuids.HighPerformance
            Write-Log "Ultimate Performance could not be created. Falling back to High Performance."
        }
    }

    powercfg /SETACTIVE $targetGuid | Out-Null
    powercfg /SETACVALUEINDEX $targetGuid $PowerGuids.Processor $PowerGuids.ProcessorMin 10 | Out-Null
    powercfg /SETACVALUEINDEX $targetGuid $PowerGuids.Processor $PowerGuids.ProcessorMax 100 | Out-Null
    powercfg /SETACVALUEINDEX $targetGuid $PowerGuids.PciExpress $PowerGuids.PcieAspm 0 | Out-Null
    powercfg /SETACVALUEINDEX $targetGuid $PowerGuids.Usb $PowerGuids.UsbSelectiveSuspend 0 | Out-Null
    powercfg /SETACVALUEINDEX $targetGuid $PowerGuids.WirelessAdapter $PowerGuids.WirelessPowerSaving 0 | Out-Null
    powercfg /SETACTIVE $targetGuid | Out-Null
    Write-Log "Applied Ultimate/High Performance AC CPU, PCIe, USB, and wireless settings."
}

function Disable-GameCaptureOverhead {
    Set-RegistryDword -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0
    Set-RegistryDword -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 0
    Set-RegistryDword -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "HistoricalCaptureEnabled" -Value 0
    Set-RegistryDword -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Value 0
    Set-RegistryDword -Path "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled" -Value 1
}

function Set-ConservativeVisualPerformance {
    Set-RegistryDword -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 3
    Set-RegistryString -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "100"
    Set-RegistryString -Path "HKCU:\Control Panel\Desktop" -Name "DragFullWindows" -Value "1"
    Set-RegistryString -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "0"
    Write-Log "Visual effects set to a conservative custom performance profile. Sign out or reboot may be needed."
}

function Ensure-TrimEnabled {
    fsutil behavior set DisableDeleteNotify 0 | Out-Null
    Write-Log "TRIM enabled for supported filesystems."
}

function Invoke-StorageReTrim {
    $volumes = @()
    try {
        $volumes = Get-Volume |
            Where-Object {
                $_.DriveLetter -and
                $_.DriveType -eq "Fixed" -and
                $_.FileSystem -in @("NTFS", "ReFS")
            } |
            Sort-Object DriveLetter
    }
    catch {
        Write-Log "WARN : Could not enumerate volumes for ReTrim: $($_.Exception.Message)"
        return
    }

    if ($volumes.Count -eq 0) {
        Write-Log "No fixed NTFS/ReFS drive-letter volumes found for ReTrim."
        return
    }

    foreach ($volume in $volumes) {
        try {
            Optimize-Volume -DriveLetter $volume.DriveLetter -ReTrim -ErrorAction Stop | Out-Null
            Write-Log "ReTrim completed for drive $($volume.DriveLetter):"
        }
        catch {
            Write-Log "WARN : ReTrim skipped or unsupported for drive $($volume.DriveLetter): $($_.Exception.Message)"
        }
    }
}

function Clear-FilesOlderThan {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][int] $Days,
        [Parameter(Mandatory = $true)][string] $Label
    )

    if (-not (Test-Path $Path)) {
        Write-Log "$Label not found: $Path"
        return
    }

    $cutoff = (Get-Date).AddDays(-1 * $Days)
    $removed = 0
    Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        ForEach-Object {
            try {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                $removed++
            }
            catch {
                Write-Log "WARN : Skipped locked file: $($_.FullName)"
            }
        }
    Write-Log "$Label cleanup removed $removed file(s) older than $Days day(s)."
}

function Clear-SafeTempAndCaches {
    Clear-FilesOlderThan -Path $env:TEMP -Days 7 -Label "User temp"
    Clear-FilesOlderThan -Path "$env:WINDIR\Temp" -Days 7 -Label "Windows temp"

    $cachePaths = @(
        (Join-Path $env:LOCALAPPDATA "D3DSCache"),
        (Join-Path $env:LOCALAPPDATA "AMD\DxCache"),
        (Join-Path $env:LOCALAPPDATA "AMD\GLCache"),
        (Join-Path $env:LOCALAPPDATA "AMD\VkCache"),
        (Join-Path $env:LOCALAPPDATA "NVIDIA\DXCache"),
        (Join-Path $env:LOCALAPPDATA "NVIDIA\GLCache")
    )

    foreach ($cachePath in $cachePaths) {
        Clear-FilesOlderThan -Path $cachePath -Days 30 -Label "Rebuildable shader/cache"
    }
}

function Optimize-NetworkPowerSaving {
    try {
        $upAdapters = Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq "Up" }
        foreach ($adapter in $upAdapters) {
            try {
                Set-AdapterPowerOffPermissionDisabled -Adapter $adapter
            }
            catch {
                Write-Log "WARN : Adapter power setting not supported for $($adapter.Name): $($_.Exception.Message)"
            }
        }
    }
    catch {
        Write-Log "WARN : Network adapter optimisation skipped: $($_.Exception.Message)"
    }
}

function Write-ManualReviewFiles {
    Write-Log "Manual review notes are included in the HTML report."
}

function Write-SafeOptimisationRunReport {
    param(
        [Parameter(Mandatory = $true)][string] $CleanupSummary
    )

    $reportPath = Join-Path $script:BackupPath "Run Report.html"
    $restorePointSummary = if ($SkipRestorePoint) {
        "[SKIP] RESTORE POINT: SKIPPED BECAUSE -SKIPRESTOREPOINT WAS PASSED."
    }
    else {
        "[OK] RESTORE POINT: CREATED OR ACCEPTED A RECENT RESTORE POINT."
    }
    $cleanupLine = if ($SkipTempCleanup) {
        "[SKIP] TEMP/CACHE CLEANUP: SKIPPED BY RECOMMENDED MODE."
    }
    else {
        "[OK] TEMP/CACHE CLEANUP: CLEANED OLD SAFE REBUILDABLE FILES."
    }
    $warningText = if ($script:LogWarnings.Count -gt 0) {
        ($script:LogWarnings | ForEach-Object { "- $_" }) -join "`r`n"
    }
    else {
        "None"
    }

    $errorText = if ($script:LogErrors.Count -gt 0) {
        ($script:LogErrors | ForEach-Object { "- $_" }) -join "`r`n"
    }
    else {
        "None"
    }

    $activePlan = "(unknown)"
    try {
        $activePlan = (powercfg /GETACTIVESCHEME | Out-String).Trim()
    }
    catch {
        $activePlan = "Could not query active power plan: $($_.Exception.Message)"
    }

    $trimStatus = "(unknown)"
    try {
        $trimStatus = (fsutil behavior query DisableDeleteNotify | Out-String).Trim()
    }
    catch {
        $trimStatus = "Could not query TRIM: $($_.Exception.Message)"
    }

    $networkPowerStatus = "(unknown)"
    try {
        $networkPowerStatus = Get-NetworkAdapterPowerState |
            Where-Object { $_.Status -eq "Up" } |
            Select-Object Name, InterfaceDescription, AllowComputerToTurnOffDevice, SelectiveSuspend, PnPCapabilities |
            Format-Table -AutoSize |
            Out-String -Width 220
        $networkPowerStatus = $networkPowerStatus.Trim()
    }
    catch {
        $networkPowerStatus = "Could not query network adapter sleep permission: $($_.Exception.Message)"
    }

    $reportText = @"
W11 OPTIMISER - RUN REPORT
================================
GENERATED: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz")
COMPUTER: $env:COMPUTERNAME
USER: $env:USERNAME
FOLDER: $script:BackupPath

RESULT
------
SAFE OPTIMISATION COMPLETED.

QUICK STATUS
------------
$activePlan

GAME DVR/BACKGROUND CAPTURE:
- GameDVR_Enabled: $(Get-RegistryValueSafe -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled")
- AppCaptureEnabled: $(Get-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled")
- HistoricalCaptureEnabled: $(Get-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "HistoricalCaptureEnabled")
- AllowGameDVR: $(Get-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR")

TRIM:
$trimStatus

NETWORK ADAPTER SLEEP PERMISSION:
$networkPowerStatus

WHAT CHANGED
------------
$restorePointSummary
[OK] BACKUPS: SAVED STATE AND REGISTRY BACKUPS IN THIS FOLDER.
[OK] POWER PLAN: ENABLED ULTIMATE PERFORMANCE IF AVAILABLE, OTHERWISE HIGH PERFORMANCE.
[OK] CPU POWER: SET AC MINIMUM TO 10 PERCENT AND MAXIMUM TO 100 PERCENT.
[OK] PCI EXPRESS: DISABLED LINK STATE POWER MANAGEMENT ON AC.
[OK] USB POWER: DISABLED USB SELECTIVE SUSPEND ON AC.
[OK] WI-FI POWER: SET WIRELESS ADAPTER POWER SAVING TO MAXIMUM PERFORMANCE ON AC.
[OK] GAME DVR: DISABLED BACKGROUND CAPTURE REGISTRY SETTINGS.
[OK] GAME MODE: KEPT WINDOWS GAME MODE ENABLED.
[OK] VISUALS: APPLIED A CONSERVATIVE RESPONSIVENESS PROFILE.
[OK] STORAGE: ENSURED TRIM IS ENABLED.
[OK] STORAGE: RAN SSD RETRIM ON SUPPORTED FIXED NTFS/REFS VOLUMES.
[OK] NETWORK: DISABLED ACTIVE PHYSICAL ADAPTER SLEEP PERMISSION WHERE SUPPORTED.
$cleanupLine

WHAT WAS NOT CHANGED
--------------------
[NO CHANGE] STARTUP APPS: LISTED FOR REVIEW ONLY.
[NO CHANGE] VBS/MEMORY INTEGRITY: NOT CHANGED.
[NO CHANGE] DEFENDER/FIREWALL/WINDOWS UPDATE/MICROSOFT STORE: NOT CHANGED.
[NO CHANGE] GPU SOFTWARE/DRIVERS/SERVICES/BIOS/HAGS/OVERCLOCKING/UNDERVOLTING: NOT CHANGED.
[NO CHANGE] GPU VENDOR-SPECIFIC SETTINGS: NOT CHANGED.

WARNINGS
--------
$warningText

ERRORS
------
$errorText

REPORT NOTES
------------
THIS PAGE OPENS FROM A LOCAL FILE. NOTHING IS UPLOADED ONLINE.
ESSENTIAL LOCAL BACKUPS ARE SAVED IN THE RUN FOLDER SO UNDO REMAINS POSSIBLE.

RISKIER TWEAKS
--------------
PROS:
- SOME CAN HELP IN VERY SPECIFIC SYSTEMS OR GAMES.
- STARTUP CLEANUP CAN MAKE LOGIN LIGHTER.
- HAGS OR VBS CHANGES CAN SOMETIMES ALTER PERFORMANCE MEASURABLY.

CONS:
- RESULTS ARE INCONSISTENT ACROSS HARDWARE, DRIVERS, AND GAMES.
- SECURITY-IMPACTING TWEAKS REDUCE PROTECTION.
- DRIVER/REGISTRY HACKS CAN CREATE STUTTER, CRASHES, OR UPDATE PROBLEMS.
- SERVICE AND TIMER TWEAKS ARE OFTEN PLACEBO AND HARD TO TROUBLESHOOT.

RECOMMENDATION:
- KEEP RISKY TWEAKS MANUAL AND MEASURED.
- DO NOT BUNDLE THEM INTO THE SAFE ALL-IN-ONE RUN.

NEXT STEPS
----------
- REBOOT IF YOU HAVE NOT ALREADY.
- RUN POST-CHECK FROM THE LAUNCHER OR COMMAND LINE.
- TEST A REAL GAME AND COMPARE FRAME-TIME SMOOTHNESS/1 PERCENT LOWS.
"@

    New-HtmlReportFromText -Title "W11 Optimiser - Run Report" -Text $reportText -OutputPath $reportPath | Out-Null
    $script:LastHtmlReportPath = $reportPath

    Write-Log "Wrote readable run report to $reportPath"
}

function Invoke-SafeOptimize {
    $restorePointLine = if ($SkipRestorePoint) {
        "- Skip the restore point because -SkipRestorePoint was passed"
    }
    else {
        "+ Create or verify a system restore point"
    }
    if (-not (Confirm-RunAction -Title "Confirm Safe Optimisation" -Lines @(
        "Yes will apply only the safe items below.",
        "No will cancel before any changes are made.",
        $restorePointLine,
        "+ Save local backups before changes",
        "+ Tune safe AC power and gaming responsiveness settings",
        "+ Optimise active physical network adapter power saving",
        "+ Keep Defender, Firewall, Windows Update, drivers, services, BIOS, overclocking, undervolting, HAGS, Memory Integrity, and startup apps untouched",
        "+ Generate a local browser report"
    ))) {
        return
    }

    $script:ConfirmedRunAction = $true
    Invoke-SelfElevateIfNeeded -TargetMode "SafeOptimize"

    Initialize-RunFolder -Prefix "Safe Run"
    Write-LogHeader -Title "Safe W11 Optimiser Run Log"
    $runResult = "Completed"

    try {
        Write-Log "Safe W11 optimisation started."
        Write-Log "Backup path: $script:BackupPath"
        Write-Log "Detected GPU vendor(s): $((Get-GpuVendorSummary).Vendors)"
        if (Test-HasBattery) {
            Write-Log "Battery detected. This script changes AC gaming settings; review battery behavior manually after the run."
        }
        if ($SkipRestorePoint) {
            Write-Log "WARN : Restore point skipped by -SkipRestorePoint. Registry and state backups will still be saved for undo."
        }
        else {
            Invoke-Step -Name "Create system restore point" -Required -Action { Create-RestorePointOrStop }
        }
        Invoke-Step -Name "Save current state" -Required -Action { Save-State }
        Invoke-Step -Name "Export registry backups" -Required -Action { Backup-RegistryKeys }
        Invoke-Step -Name "Enable Ultimate or High Performance power plan" -Action { Enable-PerformancePowerPlan }
        Invoke-Step -Name "Disable Game DVR and background capture" -Action { Disable-GameCaptureOverhead }
        Invoke-Step -Name "Set conservative visual performance profile" -Action { Set-ConservativeVisualPerformance }
        Invoke-Step -Name "Ensure SSD TRIM is enabled" -Action { Ensure-TrimEnabled }
        Invoke-Step -Name "Run SSD ReTrim maintenance" -Action { Invoke-StorageReTrim }
        Invoke-Step -Name "Optimize network adapter power saving for latency" -Action { Optimize-NetworkPowerSaving }

        $cleanupSummary = "Skipped temp/cache cleanup because -SkipTempCleanup was used."
        if (-not $SkipTempCleanup) {
            Invoke-Step -Name "Clean safe temporary and rebuildable cache files" -Action { Clear-SafeTempAndCaches }
            $cleanupSummary = "Cleaned only old temp/cache files from safe, rebuildable locations."
        }
        else {
            Write-Log "Temp/cache cleanup skipped by parameter."
        }

        Invoke-Step -Name "Prepare manual review section" -Action { Write-ManualReviewFiles }
        Invoke-Step -Name "Create browser report" -Action { Write-SafeOptimisationRunReport -CleanupSummary $cleanupSummary }

        Write-Log "Safe W11 optimisation completed."
        Write-Host ""
        Write-Host "Completed. Opening report..." -ForegroundColor Green
        if (-not [string]::IsNullOrWhiteSpace($script:LastHtmlReportPath)) {
            Open-ReportInBrowser -Path $script:LastHtmlReportPath
        }
    }
    catch {
        $runResult = "Failed"
        Write-Log "ERROR: Unexpected failure: $($_.Exception.Message)"
        throw
    }
    finally {
        Write-LogFooter -Result $runResult
    }
}

function Get-LatestBackupPath {
    $newRoot = Get-ChangesFolder
    $legacyPcRoot = Join-Path (Get-DesktopPath) "PC Optimiser"
    $legacyGamingRoot = Join-Path (Get-DesktopPath) "Gaming Optimiser"
    $oldRoot = Join-Path (Get-DesktopPath) "Windows_Optimisation_Backup"
    $candidates = @()

    if (Test-Path $newRoot) {
        $candidates += Get-ChildItem -Path $newRoot -Directory -Filter "Safe Run *" -ErrorAction SilentlyContinue
        $candidates += Get-ChildItem -Path $newRoot -Directory -Filter "Safe Optimisation *" -ErrorAction SilentlyContinue
    }
    if (Test-Path $legacyPcRoot) {
        $candidates += Get-ChildItem -Path $legacyPcRoot -Directory -Filter "Safe Run *" -ErrorAction SilentlyContinue
        $candidates += Get-ChildItem -Path $legacyPcRoot -Directory -Filter "Safe Optimisation *" -ErrorAction SilentlyContinue
    }
    if (Test-Path $legacyGamingRoot) {
        $candidates += Get-ChildItem -Path $legacyGamingRoot -Directory -Filter "Safe Run *" -ErrorAction SilentlyContinue
        $candidates += Get-ChildItem -Path $legacyGamingRoot -Directory -Filter "Safe Optimisation *" -ErrorAction SilentlyContinue
    }
    if (Test-Path $oldRoot) {
        $candidates += Get-ChildItem -Path $oldRoot -Directory -Filter "Run_*" -ErrorAction SilentlyContinue
    }

    $latest = $candidates |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -eq $latest) {
        throw "No optimisation change folders found under $newRoot or $oldRoot"
    }

    return $latest.FullName
}

function Import-RegistryBackup {
    param([Parameter(Mandatory = $true)][string] $FileName)

    $path = Join-Path $script:BackupPath $FileName
    if (-not (Test-Path $path)) {
        Write-Log "WARN : Registry backup not found, skipping: $FileName"
        return
    }

    $null = & reg.exe import $path 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Imported registry backup: $FileName"
    }
    else {
        Write-Log "WARN : Registry import failed for: $FileName"
    }
}

function Remove-RegistryPathIfMissingBeforeRun {
    param(
        [Parameter(Mandatory = $true)][string] $MarkerFileName,
        [Parameter(Mandatory = $true)][string] $RegistryPath
    )

    $markerPath = Join-Path $script:BackupPath ($MarkerFileName + ".missing.json")
    if (-not (Test-Path $markerPath)) {
        $markerPath = Join-Path $script:BackupPath ($MarkerFileName + ".missing.txt")
    }
    if (-not (Test-Path $markerPath)) {
        return
    }

    if (Test-Path $RegistryPath) {
        try {
            Remove-Item -Path $RegistryPath -Recurse -Force -ErrorAction Stop
            Write-Log "Removed registry path created after missing-before-run marker: $RegistryPath"
        }
        catch {
            Write-Log "WARN : Could not remove registry path $RegistryPath`: $($_.Exception.Message)"
        }
    }
}

function Invoke-UndoLatest {
    if (-not (Confirm-RunAction -Title "Confirm Undo" -Lines @(
        "Yes will restore settings from the latest saved W11 Optimiser run.",
        "No will cancel before any changes are made.",
        "It uses local backup files from Desktop\W11 Optimiser.",
        "If no previous safe run exists, nothing will be changed."
    ))) {
        return
    }

    $script:ConfirmedRunAction = $true
    Invoke-SelfElevateIfNeeded -TargetMode "UndoLatest"

    $script:LogWarnings = @()
    $script:LogErrors = @()
    $script:LogStepCount = 0
    $script:LogPath = $null
    $runResult = "Completed"
    $undoFailed = $false

    try {
    if ([string]::IsNullOrWhiteSpace($BackupPath)) {
        $script:BackupPath = Get-LatestBackupPath
    }
    else {
        $script:BackupPath = (Resolve-Path $BackupPath).Path
    }

    $script:LogPath = if ($VerboseLog) { Join-Path $script:BackupPath "Undo Log.txt" } else { $null }
    Write-LogHeader -Title "Undo Log"
    Write-Log "Undo started."
    Write-Log "Using backup path: $script:BackupPath"

    $statePath = Join-Path $script:BackupPath "State.json"
    $state = $null
    if (Test-Path $statePath) {
        try {
            $state = Get-Content -Path $statePath -Raw | ConvertFrom-Json
            Write-Log "Loaded State.json"
        }
        catch {
            Write-Log "WARN : Could not load State.json: $($_.Exception.Message)"
        }
    }

    Import-RegistryBackup -FileName "HKCU_System_GameConfigStore.reg"
    Import-RegistryBackup -FileName "HKCU_Microsoft_GameBar.reg"
    Import-RegistryBackup -FileName "HKCU_GameDVR.reg"
    Import-RegistryBackup -FileName "HKLM_Policies_GameDVR.reg"
    Import-RegistryBackup -FileName "HKCU_VisualEffects.reg"
    Import-RegistryBackup -FileName "HKCU_ControlPanel_Desktop.reg"
    Import-RegistryBackup -FileName "HKCU_WindowMetrics.reg"

    Remove-RegistryPathIfMissingBeforeRun -MarkerFileName "HKCU_System_GameConfigStore.reg" -RegistryPath "HKCU:\System\GameConfigStore"
    Remove-RegistryPathIfMissingBeforeRun -MarkerFileName "HKCU_Microsoft_GameBar.reg" -RegistryPath "HKCU:\Software\Microsoft\GameBar"
    Remove-RegistryPathIfMissingBeforeRun -MarkerFileName "HKCU_GameDVR.reg" -RegistryPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR"
    Remove-RegistryPathIfMissingBeforeRun -MarkerFileName "HKLM_Policies_GameDVR.reg" -RegistryPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
    Remove-RegistryPathIfMissingBeforeRun -MarkerFileName "HKCU_VisualEffects.reg" -RegistryPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    Remove-RegistryPathIfMissingBeforeRun -MarkerFileName "HKCU_ControlPanel_Desktop.reg" -RegistryPath "HKCU:\Control Panel\Desktop"
    Remove-RegistryPathIfMissingBeforeRun -MarkerFileName "HKCU_WindowMetrics.reg" -RegistryPath "HKCU:\Control Panel\Desktop\WindowMetrics"

    if ($null -ne $state -and -not [string]::IsNullOrWhiteSpace($state.PreviousActivePowerSchemeGuid)) {
        try {
            powercfg /SETACTIVE $state.PreviousActivePowerSchemeGuid | Out-Null
            Write-Log "Restored previous active power scheme: $($state.PreviousActivePowerSchemeGuid)"
        }
        catch {
            Write-Log "WARN : Could not restore previous active power scheme: $($_.Exception.Message)"
        }
    }

    if ($null -ne $state -and $null -ne $state.NtfsDisableDeleteNotify) {
        try {
            fsutil behavior set DisableDeleteNotify ([int] $state.NtfsDisableDeleteNotify) | Out-Null
            Write-Log "Restored NTFS DisableDeleteNotify to $($state.NtfsDisableDeleteNotify)"
        }
        catch {
            Write-Log "WARN : Could not restore TRIM setting: $($_.Exception.Message)"
        }
    }

    $networkStatePath = Join-Path $script:BackupPath "Network Power Management.json"
    if (-not (Test-Path $networkStatePath)) {
        $networkStatePath = Join-Path $script:BackupPath "NetworkPowerManagement.json"
    }
    if (Test-Path $networkStatePath) {
        try {
            $networkState = Get-Content -Path $networkStatePath -Raw | ConvertFrom-Json
            Restore-NetworkAdapterPowerState -NetworkState $networkState
        }
        catch {
            Write-Log "WARN : Could not restore network adapter state: $($_.Exception.Message)"
        }
    }

    Write-Log "Undo completed. Restart or sign out may be needed."
    }
    catch {
        $runResult = "Failed"
        Write-Log "ERROR: Undo failed: $($_.Exception.Message)"
        $undoFailed = $true
    }
    finally {
        Write-LogFooter -Result $runResult
    }

    if ($undoFailed) {
        exit 1
    }
}

function Invoke-PostCheck {
    $reportsFolder = Get-ReportsFolder
    $null = New-Item -ItemType Directory -Path $reportsFolder -Force
    $timestamp = Get-FriendlyTimestamp
    $htmlPath = Join-Path $reportsFolder "Post Check Report $timestamp.html"
    $builder = [System.Text.StringBuilder]::new()
    $gpuSummary = Get-GpuVendorSummary

    [void] $builder.AppendLine("W11 Optimiser Post-Check")
    [void] $builder.AppendLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
    [void] $builder.AppendLine("Computer: $env:COMPUTERNAME")
    [void] $builder.AppendLine("User: $env:USERNAME")
    [void] $builder.AppendLine("Admin: $(Test-IsAdmin)")
    [void] $builder.AppendLine("Detected GPU vendor(s): $($gpuSummary.Vendors)")
    [void] $builder.AppendLine("Detected GPU name(s): $($gpuSummary.Names)")
    [void] $builder.AppendLine("Battery detected: $(Test-HasBattery)")

    Add-ReportSection -Builder $builder -Title "Active Power Plan"
    Add-CommandToReport -Builder $builder -Command "powercfg" -Arguments @("/GETACTIVESCHEME")

    Add-ReportSection -Builder $builder -Title "Processor AC Power Settings"
    Add-CommandToReport -Builder $builder -Command "powercfg" -Arguments @("/QUERY", "SCHEME_CURRENT", "SUB_PROCESSOR")

    Add-ReportSection -Builder $builder -Title "PCIe Link State Power Management"
    Add-CommandToReport -Builder $builder -Command "powercfg" -Arguments @("/QUERY", "SCHEME_CURRENT", "SUB_PCIEXPRESS")

    Add-ReportSection -Builder $builder -Title "USB Selective Suspend"
    Add-CommandToReport -Builder $builder -Command "powercfg" -Arguments @("/QUERY", "SCHEME_CURRENT", $PowerGuids.Usb, $PowerGuids.UsbSelectiveSuspend)

    Add-ReportSection -Builder $builder -Title "Wireless Adapter Power Saving"
    Add-CommandToReport -Builder $builder -Command "powercfg" -Arguments @("/QUERY", "SCHEME_CURRENT", $PowerGuids.WirelessAdapter, $PowerGuids.WirelessPowerSaving)

    Add-ReportSection -Builder $builder -Title "Network Adapter Sleep Permission"
    try {
        Get-NetworkAdapterPowerState |
            Where-Object { $_.Status -eq "Up" } |
            Write-ObjectBlock -Builder $builder
    }
    catch {
        [void] $builder.AppendLine("Network adapter sleep permission query failed: $($_.Exception.Message)")
    }

    Add-ReportSection -Builder $builder -Title "Game DVR / Game Mode"
    [pscustomobject][ordered]@{
        "GameDVR_Enabled" = Get-RegistryValueSafe -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled"
        "AppCaptureEnabled" = Get-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled"
        "HistoricalCaptureEnabled" = Get-RegistryValueSafe -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "HistoricalCaptureEnabled"
        "AllowGameDVR" = Get-RegistryValueSafe -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR"
        "AutoGameModeEnabled" = Get-RegistryValueSafe -Path "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled"
    } | Write-ObjectBlock -Builder $builder

    Add-ReportSection -Builder $builder -Title "Security Features Not Touched By SafeOptimize"
    [pscustomobject][ordered]@{
        "HAGS HwSchMode" = Get-RegistryValueSafe -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode"
        "Memory Integrity Enabled" = Get-RegistryValueSafe -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" -Name "Enabled"
    } | Write-ObjectBlock -Builder $builder

    Add-ReportSection -Builder $builder -Title "TRIM"
    Add-StorageSpaceReport -Builder $builder
    Add-CommandToReport -Builder $builder -Command "fsutil" -Arguments @("behavior", "query", "DisableDeleteNotify")

    Add-ReportSection -Builder $builder -Title "Startup Entries Still Manual"
    Get-StartupRunEntries | Sort-Object Scope, Name | Write-ObjectBlock -Builder $builder

    $postCheckText = $builder.ToString()
    New-HtmlReportFromText -Title "W11 Optimiser - Post Check" -Text $postCheckText -OutputPath $htmlPath | Out-Null
    Write-Host "Post-check report written to: $htmlPath" -ForegroundColor Green
    Open-ReportInBrowser -Path $htmlPath
}

switch ($Mode) {
    "Audit" {
        Invoke-Audit
    }
    "Preview" {
        Invoke-Preview
    }
    "SafeOptimize" {
        Invoke-SafeOptimize
    }
    "UndoLatest" {
        Invoke-UndoLatest
    }
    "PostCheck" {
        Invoke-PostCheck
    }
    "OpenLastReport" {
        Invoke-OpenLastReport
    }
}
