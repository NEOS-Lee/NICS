#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Detects or removes factory-installed application bloatware from HP, Lenovo,
    and Dell computers.

.DESCRIPTION
    This script is intended for newly staged computers. It removes OEM-branded
    desktop applications, OEM Store applications, provisioned OEM packages, and
    common factory trialware. It does not use Win32_Product.

    Removal order is intentional:
      1. Installed Store applications
      2. Provisioned Store applications
      3. Add-ons and dependent components
      4. Main OEM applications
      5. Agents, remediation components, and updaters
      6. Services, frameworks, foundations, and core components

    The script protects entries that identify themselves as hardware drivers,
    firmware, BIOS updates, chipsets, or other device packages. It does not
    maintain an application exclusion list. This means OEM update utilities,
    support tools, security suites, power-management applications, hotkey
    applications, and similar OEM software are removal targets.

    Exit codes:
      Detect mode:
        0 = No targeted software detected
        1 = Targeted software detected
        2 = Detection failed

      Remove mode:
        0    = Removal completed and verification is clean
        1    = One or more targeted items remain
        2    = Fatal script error
        3010 = Removal completed and a restart is required

.PARAMETER Mode
    Detect inventories targeted software without changing the computer.
    Remove uninstalls targeted software and verifies the result.

.PARAMETER Target
    Auto targets the detected computer manufacturer. HP, Lenovo, or Dell limits
    removal to that vendor. All targets applications from all three vendors.

.PARAMETER IncludeCommonTrialware
    When true, also removes common OEM preload trialware such as McAfee, Norton,
    WildTangent, ExpressVPN, Dropbox promotions, and similar packages.

.PARAMETER UninstallPasses
    Number of classic-application uninstall passes. A second pass helps when a
    framework can only be removed after a dependent application is gone.

.EXAMPLE
    .\Remove-OEMFactoryBloatware.ps1 -Mode Detect

.EXAMPLE
    .\Remove-OEMFactoryBloatware.ps1 -Mode Remove -Target Auto -Confirm:$false

.EXAMPLE
    .\Remove-OEMFactoryBloatware.ps1 -Mode Remove -Target All -WhatIf
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [ValidateSet('Detect', 'Remove')]
    [string]$Mode = 'Remove',

    [ValidateSet('Auto', 'HP', 'Lenovo', 'Dell', 'All')]
    [string]$Target = 'Auto',

    [bool]$IncludeCommonTrialware = $true,

    [ValidateRange(1, 3)]
    [int]$UninstallPasses = 2,

    [string]$LogDirectory = (Join-Path $env:ProgramData 'NEOS\DevicePreparation\Logs')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:ScriptVersion = '1.0.0'
$script:RebootRequired = $false
$script:RemovedCount = 0
$script:CompletedClassic = @{}
$script:FailureMessages = @{}
$script:WhatIfMode = [bool]$WhatIfPreference

try {
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
}
catch {
    Write-Host "Unable to create the log directory '$LogDirectory': $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

$script:LogFile = Join-Path $LogDirectory (
    'OEMBloatware-{0}-{1}.log' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmmss')
)

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )

    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8

    switch ($Level) {
        'WARN'    { Write-Host $line -ForegroundColor Yellow }
        'ERROR'   { Write-Host $line -ForegroundColor Red }
        'SUCCESS' { Write-Host $line -ForegroundColor Green }
        default   { Write-Host $line }
    }
}

function Get-PropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

$script:OemDefinitions = @{
    HP = [pscustomobject]@{
        ManufacturerPattern = '(?i)(^|\s)(HP|Hewlett[- ]Packard)(\s|$)'
        PublisherPattern    = '(?i)^(HP( Inc\.?| Development Company| Software)?|Hewlett[- ]Packard|Bromium)(\b|$)'
        ProgramNamePattern  = '(?i)(^HP\b|^Hewlett[- ]Packard\b|^myHP\b|^OMEN\b|^Wolf Security\b|^Sure Click\b|^Sure Sense\b|^Bromium\b|^Poly (Camera Pro|Lens)\b)'
        AppxNamePattern     = '(?i)(^(AD2F1837|HPInc|HewlettPackard)(\.|$)|HP(JumpStarts|SupportAssistant|SystemInformation|QuickDrop|WorkWell|EasyClean|PrivacySettings|PowerManager|DesktopSupportUtilities)|myHP|OMEN)'
    }
    Lenovo = [pscustomobject]@{
        ManufacturerPattern = '(?i)Lenovo'
        PublisherPattern    = '(?i)^(Lenovo|Motorola Mobility)(\b|$)'
        ProgramNamePattern  = '(?i)(^Lenovo\b|^ThinkVantage\b|^ThinkPad .*?(Utility|Experience|Welcome)\b|^Legion\b|^Yoga .*?(App|Utility)\b|^App Explorer\b|^Moto Smart Assistant\b)'
        AppxNamePattern     = '(?i)(^(E046963F|E0469640|LenovoCorporation|LENOVOCO)(\.|$)|Lenovo|ThinkVantage|Legion|AppExplorer)'
    }
    Dell = [pscustomobject]@{
        ManufacturerPattern = '(?i)Dell'
        PublisherPattern    = '(?i)^(Dell|Alienware)(\b|$)'
        ProgramNamePattern  = '(?i)(^Dell\b|^SupportAssist\b|^MyDell\b|^Alienware\b|^SmartByte\b|^Cinema(Color|Sound|Stream)\b|^Waves MaxxAudio Pro for Dell\b)'
        AppxNamePattern     = '(?i)(^DellInc\.|^DellTechnologies\.|Dell(SupportAssist|Command|Optimizer|DigitalDelivery|MobileConnect|PowerManager|Pair)|MyDell|Alienware|Power2GoforDell|PowerMediaPlayer.*Dell)'
    }
}

$script:ProtectedDriverPattern = '(?i)\b(driver( package)?|firmware( update)?|BIOS update|chipset|serial IO|management engine|rapid storage|Bluetooth driver|wireless driver|WLAN driver|Ethernet driver|network adapter|graphics driver|display driver|audio driver|touchpad driver|trackpad driver|card reader driver|Thunderbolt driver|USB driver|camera driver|sensor driver|ControlVault)\b'
$script:ProtectedCommandPattern = '(?i)(DriverStore|pnputil(?:\.exe)?|dpinst(?:64)?(?:\.exe)?|setupapi\.dll)'

$script:CommonTrialwareProgramPattern = '(?i)^(McAfee|Norton|WildTangent|ExpressVPN|Dropbox Promotion|Dropbox 25 GB|Booking\.com|Amazon Assistant|Evernote|Spotify|CyberLink (PowerDirector|PhotoDirector|Power Media Player).*(for (HP|Lenovo|Dell)|OEM))\b'
$script:CommonTrialwareAppxPattern = '(?i)(McAfee|Norton|WildTangent|ExpressVPN|DropboxInc\.Dropbox|Booking\.com|AmazonAssistant|SpotifyAB\.SpotifyMusic|CyberLink.*(HP|Lenovo|Dell))'

function Get-DetectedManufacturer {
    [CmdletBinding()]
    param()

    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    return [string]$computerSystem.Manufacturer
}

function Resolve-SelectedTargets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequestedTarget,

        [Parameter(Mandatory = $true)]
        [string]$Manufacturer
    )

    if ($RequestedTarget -eq 'All') {
        return @('HP', 'Lenovo', 'Dell')
    }

    if ($RequestedTarget -ne 'Auto') {
        return @($RequestedTarget)
    }

    foreach ($vendorName in @('HP', 'Lenovo', 'Dell')) {
        $definition = $script:OemDefinitions[$vendorName]
        if ($Manufacturer -match $definition.ManufacturerPattern) {
            return @($vendorName)
        }
    }

    return @()
}

function Test-IsProtectedDriverComponent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Application
    )

    if ($Application.DisplayName -match $script:ProtectedDriverPattern) {
        return $true
    }

    if ($Application.ReleaseType -match '(?i)^(Driver|Firmware)$') {
        return $true
    }

    $combinedCommand = '{0} {1}' -f $Application.QuietUninstallString, $Application.UninstallString
    if ($combinedCommand -match $script:ProtectedCommandPattern) {
        return $true
    }

    return $false
}

function Test-IsTargetedClassicApplication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Application
    )

    if (Test-IsProtectedDriverComponent -Application $Application) {
        return $false
    }

    foreach ($vendorName in $script:SelectedTargets) {
        $definition = $script:OemDefinitions[$vendorName]
        if (($Application.DisplayName -match $definition.ProgramNamePattern) -or
            ($Application.Publisher -match $definition.PublisherPattern)) {
            return $true
        }
    }

    if ($IncludeCommonTrialware -and
        $script:SelectedTargets.Count -gt 0 -and
        $Application.DisplayName -match $script:CommonTrialwareProgramPattern) {
        return $true
    }

    return $false
}

function Test-IsTargetedAppxName {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }

    foreach ($vendorName in $script:SelectedTargets) {
        if ($Name -match $script:OemDefinitions[$vendorName].AppxNamePattern) {
            return $true
        }
    }

    if ($IncludeCommonTrialware -and
        $script:SelectedTargets.Count -gt 0 -and
        $Name -match $script:CommonTrialwareAppxPattern) {
        return $true
    }

    return $false
}

function Get-ClassicApplications {
    [CmdletBinding()]
    param()

    $locations = @(
        [pscustomobject]@{
            Path  = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
            Scope = 'Machine64'
        }
        [pscustomobject]@{
            Path  = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
            Scope = 'Machine32'
        }
        [pscustomobject]@{
            Path  = 'Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
            Scope = 'CurrentUser'
        }
    )

    $applications = New-Object System.Collections.Generic.List[object]

    foreach ($location in $locations) {
        $items = @(Get-ItemProperty -Path $location.Path -ErrorAction SilentlyContinue)
        foreach ($item in $items) {
            $displayName = [string](Get-PropertyValue -InputObject $item -Name 'DisplayName')
            if ([string]::IsNullOrWhiteSpace($displayName)) {
                continue
            }

            $keyName = [string](Get-PropertyValue -InputObject $item -Name 'PSChildName')
            $productCode = $null
            if ($keyName -match '^\{[0-9A-Fa-f-]{36}\}$') {
                $productCode = $keyName
            }

            $application = [pscustomobject]@{
                DisplayName          = $displayName.Trim()
                DisplayVersion       = [string](Get-PropertyValue -InputObject $item -Name 'DisplayVersion')
                Publisher            = [string](Get-PropertyValue -InputObject $item -Name 'Publisher')
                QuietUninstallString = [string](Get-PropertyValue -InputObject $item -Name 'QuietUninstallString')
                UninstallString      = [string](Get-PropertyValue -InputObject $item -Name 'UninstallString')
                InstallLocation      = [string](Get-PropertyValue -InputObject $item -Name 'InstallLocation')
                ReleaseType          = [string](Get-PropertyValue -InputObject $item -Name 'ReleaseType')
                WindowsInstaller     = Get-PropertyValue -InputObject $item -Name 'WindowsInstaller'
                SystemComponent      = Get-PropertyValue -InputObject $item -Name 'SystemComponent'
                RegistryPath         = [string](Get-PropertyValue -InputObject $item -Name 'PSPath')
                RegistryKeyName      = $keyName
                ProductCode          = $productCode
                Scope                = $location.Scope
            }

            if (Test-IsTargetedClassicApplication -Application $application) {
                $applications.Add($application)
            }
        }
    }

    return @(
        $applications |
            Sort-Object RegistryPath -Unique
    )
}

function Get-OemInventory {
    [CmdletBinding()]
    param()

    $installedAppx = @(
        Get-AppxPackage -AllUsers -ErrorAction Stop |
            Where-Object { Test-IsTargetedAppxName -Name $_.Name } |
            Sort-Object PackageFullName -Unique
    )

    $provisionedAppx = @(
        Get-AppxProvisionedPackage -Online -ErrorAction Stop |
            Where-Object { Test-IsTargetedAppxName -Name $_.DisplayName } |
            Sort-Object PackageName -Unique
    )

    $classicApplications = @(Get-ClassicApplications)

    return [pscustomobject]@{
        InstalledAppx       = $installedAppx
        ProvisionedAppx     = $provisionedAppx
        ClassicApplications = $classicApplications
        TotalCount          = $installedAppx.Count + $provisionedAppx.Count + $classicApplications.Count
    }
}

function Show-OemInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Inventory,

        [string]$Heading = 'Detected targets'
    )

    Write-Log -Message $Heading

    foreach ($package in $Inventory.InstalledAppx) {
        Write-Log -Message ("  Installed Appx: {0}" -f $package.Name)
    }

    foreach ($package in $Inventory.ProvisionedAppx) {
        Write-Log -Message ("  Provisioned Appx: {0}" -f $package.DisplayName)
    }

    foreach ($application in $Inventory.ClassicApplications) {
        Write-Log -Message ("  Classic application: {0} {1}" -f $application.DisplayName, $application.DisplayVersion)
    }

    if ($Inventory.TotalCount -eq 0) {
        Write-Log -Message '  None'
    }
}

function Get-ClassicIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Application
    )

    if (-not [string]::IsNullOrWhiteSpace($Application.ProductCode)) {
        return ('MSI:{0}' -f $Application.ProductCode.ToUpperInvariant())
    }

    return ('REG:{0}' -f $Application.RegistryPath.ToLowerInvariant())
}

function Get-UninstallPriority {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Application
    )

    $name = $Application.DisplayName

    if ($name -match '(?i)(Application Support|Add[- ]?on|Plug[- ]?in|Plugin|Extension|Module|Companion)') {
        return 10
    }

    if ($name -match '(?i)(Core|Framework|Foundation|System Interface|ImController|TechHub|Data Vault|Client Management Service|Support Solutions Framework|Vantage Service|Optimizer Service)') {
        return 50
    }

    if ($name -match '(?i)(Service|Agent|Remediation|Analytics|Telemetry|Update Service|Service Bridge|Digital Delivery)') {
        return 40
    }

    if ($name -match '(?i)(SupportAssist|Optimizer|Vantage|myHP|Wolf Security|Sure Click|Sure Sense|Power Manager|System Update|Command Update|Customer Connect)') {
        return 20
    }

    return 30
}

function Split-UninstallCommandLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandLine
    )

    $expanded = [Environment]::ExpandEnvironmentVariables($CommandLine.Trim())
    if ([string]::IsNullOrWhiteSpace($expanded)) {
        throw 'The uninstall command is empty.'
    }

    if ($expanded.StartsWith('"')) {
        $closingQuote = $expanded.IndexOf('"', 1)
        if ($closingQuote -lt 2) {
            throw "The quoted uninstall command is malformed: $expanded"
        }

        return [pscustomobject]@{
            FilePath  = $expanded.Substring(1, $closingQuote - 1)
            Arguments = $expanded.Substring($closingQuote + 1).Trim()
        }
    }

    $exeMatch = [regex]::Match(
        $expanded,
        '^(?<Executable>.+?\.exe)(?:\s+(?<Arguments>.*))?$',
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if ($exeMatch.Success) {
        return [pscustomobject]@{
            FilePath  = $exeMatch.Groups['Executable'].Value.Trim()
            Arguments = $exeMatch.Groups['Arguments'].Value.Trim()
        }
    }

    $firstSpace = $expanded.IndexOf(' ')
    if ($firstSpace -lt 1) {
        return [pscustomobject]@{
            FilePath  = $expanded
            Arguments = ''
        }
    }

    return [pscustomobject]@{
        FilePath  = $expanded.Substring(0, $firstSpace).Trim()
        Arguments = $expanded.Substring($firstSpace + 1).Trim()
    }
}

function Add-Arguments {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$ExistingArguments,

        [Parameter(Mandatory = $true)]
        [string]$AdditionalArguments
    )

    if ([string]::IsNullOrWhiteSpace($ExistingArguments)) {
        return $AdditionalArguments.Trim()
    }

    return ('{0} {1}' -f $ExistingArguments.Trim(), $AdditionalArguments.Trim())
}

function Get-UninstallCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Application
    )

    $allUninstallText = '{0} {1} {2}' -f $Application.ProductCode, $Application.QuietUninstallString, $Application.UninstallString
    $guidMatch = [regex]::Match($allUninstallText, '\{[0-9A-Fa-f-]{36}\}')
    $isMsi = (($null -ne $Application.WindowsInstaller) -and ([int]$Application.WindowsInstaller -eq 1)) -or
        ($allUninstallText -match '(?i)\bmsiexec(?:\.exe)?\b')

    if ($isMsi -and $guidMatch.Success) {
        return [pscustomobject]@{
            FilePath  = (Join-Path $env:SystemRoot 'System32\msiexec.exe')
            Arguments = ('/x {0} /qn /norestart REBOOT=ReallySuppress' -f $guidMatch.Value)
            Method    = 'MSI product code'
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Application.QuietUninstallString)) {
        $quietCommand = Split-UninstallCommandLine -CommandLine $Application.QuietUninstallString
        return [pscustomobject]@{
            FilePath  = $quietCommand.FilePath
            Arguments = $quietCommand.Arguments
            Method    = 'QuietUninstallString'
        }
    }

    if ([string]::IsNullOrWhiteSpace($Application.UninstallString)) {
        throw 'No uninstall command is registered.'
    }

    $command = Split-UninstallCommandLine -CommandLine $Application.UninstallString
    $executableName = [IO.Path]::GetFileName($command.FilePath)
    $arguments = $command.Arguments
    $method = 'Generated silent command'

    switch -Regex ($executableName) {
        '(?i)^UninstallHPSA\.exe$' {
            $arguments = '/s /v/qn UninstallKeepPreferences=FALSE'
            break
        }
        '(?i)^unins\d*\.exe$' {
            $arguments = Add-Arguments -ExistingArguments $arguments -AdditionalArguments '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART'
            break
        }
        '(?i)^setup\.exe$' {
            $arguments = Add-Arguments -ExistingArguments $arguments -AdditionalArguments '-s -v"/qn REBOOT=ReallySuppress"'
            break
        }
        '(?i)^(uninstall|uninstaller)\.exe$' {
            $arguments = Add-Arguments -ExistingArguments $arguments -AdditionalArguments '/S /norestart'
            break
        }
        '(?i)^maintenancetool\.exe$' {
            $arguments = Add-Arguments -ExistingArguments $arguments -AdditionalArguments '--silent'
            break
        }
        default {
            if ($arguments -notmatch '(?i)(/quiet|/silent|/verysilent|/qn|/s(?:\s|$)|-silent|-s(?:\s|$))') {
                $arguments = Add-Arguments -ExistingArguments $arguments -AdditionalArguments '/quiet /norestart'
            }
        }
    }

    return [pscustomobject]@{
        FilePath  = $command.FilePath
        Arguments = $arguments
        Method    = $method
    }
}

function Invoke-UninstallCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Application,

        [Parameter(Mandatory = $true)]
        [object]$Command
    )

    Write-Log -Message ("Uninstalling '{0}' using {1}." -f $Application.DisplayName, $Command.Method)
    Write-Log -Message ("Command: {0} {1}" -f $Command.FilePath, $Command.Arguments)

    $startParameters = @{
        FilePath    = $Command.FilePath
        Wait        = $true
        PassThru    = $true
        ErrorAction = 'Stop'
        WindowStyle = 'Hidden'
    }

    if (-not [string]::IsNullOrWhiteSpace($Command.Arguments)) {
        $startParameters.ArgumentList = $Command.Arguments
    }

    $process = Start-Process @startParameters
    $exitCode = [int]$process.ExitCode

    $successCodes = @(0, 1605, 1614, 1641, 3010)
    if ($successCodes -notcontains $exitCode) {
        throw "The uninstaller returned exit code $exitCode."
    }

    if ($exitCode -in @(1641, 3010)) {
        $script:RebootRequired = $true
    }

    return $exitCode
}

function Set-Failure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Identity,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $script:FailureMessages[$Identity] = $Message
    Write-Log -Message $Message -Level 'WARN'
}

function Clear-Failure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Identity
    )

    if ($script:FailureMessages.ContainsKey($Identity)) {
        $script:FailureMessages.Remove($Identity)
    }
}

try {
    Write-Log -Message ("Remove-OEMFactoryBloatware version {0} started." -f $script:ScriptVersion)
    Write-Log -Message ("Mode={0}; Target={1}; IncludeCommonTrialware={2}; WhatIf={3}" -f $Mode, $Target, $IncludeCommonTrialware, $script:WhatIfMode)

    $manufacturer = Get-DetectedManufacturer
    $script:SelectedTargets = @(Resolve-SelectedTargets -RequestedTarget $Target -Manufacturer $manufacturer)

    Write-Log -Message ("Computer manufacturer: {0}" -f $manufacturer)

    if ($script:SelectedTargets.Count -eq 0) {
        Write-Log -Message 'No supported OEM was detected. Use -Target All or select a vendor explicitly.' -Level 'WARN'
        exit 0
    }

    Write-Log -Message ("Selected OEM targets: {0}" -f ($script:SelectedTargets -join ', '))

    $initialInventory = Get-OemInventory
    Show-OemInventory -Inventory $initialInventory -Heading 'Initial targeted-software inventory:'

    if ($Mode -eq 'Detect') {
        if ($initialInventory.TotalCount -gt 0) {
            Write-Log -Message ("Detection completed. {0} targeted entries were found." -f $initialInventory.TotalCount) -Level 'WARN'
            exit 1
        }

        Write-Log -Message 'Detection completed. No targeted software was found.' -Level 'SUCCESS'
        exit 0
    }

    if ($initialInventory.TotalCount -eq 0) {
        Write-Log -Message 'The computer is already clean for the selected policy.' -Level 'SUCCESS'
        exit 0
    }

    $installedAppxOrder = @(
        $initialInventory.InstalledAppx |
            Sort-Object @{ Expression = { if ($_.IsFramework) { 1 } else { 0 } }; Ascending = $true }, Name
    )

    foreach ($package in $installedAppxOrder) {
        $identity = 'APPX:{0}' -f $package.PackageFullName
        if ($PSCmdlet.ShouldProcess($package.Name, 'Remove installed Appx package for all users')) {
            try {
                Write-Log -Message ("Removing installed Appx package '{0}'." -f $package.PackageFullName)
                Remove-AppxPackage -Package $package.PackageFullName -AllUsers -Confirm:$false -ErrorAction Stop
                $script:RemovedCount++
                Clear-Failure -Identity $identity
            }
            catch {
                Set-Failure -Identity $identity -Message ("Failed to remove installed Appx package '{0}': {1}" -f $package.Name, $_.Exception.Message)
            }
        }
    }

    foreach ($package in $initialInventory.ProvisionedAppx) {
        $identity = 'PROVISIONED:{0}' -f $package.PackageName
        if ($PSCmdlet.ShouldProcess($package.DisplayName, 'Remove provisioned Appx package for all users')) {
            try {
                Write-Log -Message ("Removing provisioned Appx package '{0}'." -f $package.PackageName)
                Remove-AppxProvisionedPackage -Online -AllUsers -PackageName $package.PackageName -ErrorAction Stop | Out-Null
                $script:RemovedCount++
                Clear-Failure -Identity $identity
            }
            catch {
                Set-Failure -Identity $identity -Message ("Failed to remove provisioned Appx package '{0}': {1}" -f $package.DisplayName, $_.Exception.Message)
            }
        }
    }

    $passesToRun = if ($script:WhatIfMode) { 1 } else { $UninstallPasses }

    for ($pass = 1; $pass -le $passesToRun; $pass++) {
        $applications = @(
            Get-ClassicApplications |
                Sort-Object @{ Expression = { Get-UninstallPriority -Application $_ }; Ascending = $true }, DisplayName
        )

        $pendingApplications = @(
            $applications |
                Where-Object { -not $script:CompletedClassic.ContainsKey((Get-ClassicIdentity -Application $_)) }
        )

        if ($pendingApplications.Count -eq 0) {
            break
        }

        Write-Log -Message ("Starting classic-application uninstall pass {0} of {1}." -f $pass, $passesToRun)

        foreach ($application in $pendingApplications) {
            $identity = Get-ClassicIdentity -Application $application
            $priority = Get-UninstallPriority -Application $application

            if ($PSCmdlet.ShouldProcess($application.DisplayName, "Uninstall classic application at dependency priority $priority")) {
                try {
                    $command = Get-UninstallCommand -Application $application
                    $exitCode = Invoke-UninstallCommand -Application $application -Command $command
                    $script:CompletedClassic[$identity] = $true
                    $script:RemovedCount++
                    Clear-Failure -Identity $identity
                    Write-Log -Message ("Uninstaller for '{0}' completed with exit code {1}." -f $application.DisplayName, $exitCode) -Level 'SUCCESS'
                }
                catch {
                    Set-Failure -Identity $identity -Message ("Failed to uninstall '{0}': {1}" -f $application.DisplayName, $_.Exception.Message)
                }
            }
        }

        if (($pass -lt $passesToRun) -and (-not $script:WhatIfMode)) {
            Start-Sleep -Seconds 3
        }
    }

    if ($script:WhatIfMode) {
        Write-Log -Message 'WhatIf preview completed. No applications were removed.' -Level 'SUCCESS'
        exit 0
    }

    Start-Sleep -Seconds 3
    $finalInventory = Get-OemInventory
    Show-OemInventory -Inventory $finalInventory -Heading 'Post-removal verification inventory:'

    if ($finalInventory.TotalCount -gt 0) {
        foreach ($application in $finalInventory.ClassicApplications) {
            $identity = Get-ClassicIdentity -Application $application
            if (-not $script:CompletedClassic.ContainsKey($identity)) {
                Set-Failure -Identity $identity -Message ("Application remains installed after cleanup: {0}" -f $application.DisplayName)
            }
        }

        foreach ($package in $finalInventory.InstalledAppx) {
            $identity = 'APPX:{0}' -f $package.PackageFullName
            Set-Failure -Identity $identity -Message ("Installed Appx package remains after cleanup: {0}" -f $package.Name)
        }

        foreach ($package in $finalInventory.ProvisionedAppx) {
            $identity = 'PROVISIONED:{0}' -f $package.PackageName
            Set-Failure -Identity $identity -Message ("Provisioned Appx package remains after cleanup: {0}" -f $package.DisplayName)
        }

        $pendingRestartOnly = $script:RebootRequired -and
            ($finalInventory.InstalledAppx.Count -eq 0) -and
            ($finalInventory.ProvisionedAppx.Count -eq 0) -and
            (@($finalInventory.ClassicApplications | Where-Object {
                -not $script:CompletedClassic.ContainsKey((Get-ClassicIdentity -Application $_))
            }).Count -eq 0)

        if ($pendingRestartOnly) {
            Write-Log -Message ("Removal actions completed. {0} registry entries are pending restart cleanup." -f $finalInventory.ClassicApplications.Count) -Level 'WARN'
            Write-Log -Message ("Log file: {0}" -f $script:LogFile)
            exit 3010
        }

        Write-Log -Message ("Cleanup is incomplete. {0} targeted entries remain." -f $finalInventory.TotalCount) -Level 'ERROR'
        Write-Log -Message ("Log file: {0}" -f $script:LogFile)
        exit 1
    }

    Write-Log -Message ("Cleanup completed successfully. {0} removal actions succeeded." -f $script:RemovedCount) -Level 'SUCCESS'
    Write-Log -Message ("Log file: {0}" -f $script:LogFile)

    if ($script:RebootRequired) {
        Write-Log -Message 'A restart is required to complete one or more uninstall operations.' -Level 'WARN'
        exit 3010
    }

    exit 0
}
catch {
    try {
        Write-Log -Message ("Fatal cleanup error: {0}" -f $_.Exception.Message) -Level 'ERROR'
        Write-Log -Message ("Log file: {0}" -f $script:LogFile)
    }
    catch {
        Write-Host ("Fatal cleanup error: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }

    exit 2
}
