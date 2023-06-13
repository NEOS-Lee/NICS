#Remove HP bloatware / crapware
#-- source : https://gist.github.com/mark05e/a79221b4245962a477a49eb281d97388

#Remove HP Documentation
if (Test-Path "${Env:ProgramFiles}\HP\Documentation\Doc_uninstall.cmd" -PathType Leaf) {
    try {
        Invoke-Item "${Env:ProgramFiles}\HP\Documentation\Doc_uninstall.cmd"
        Write-Host "Successfully removed provisioned package: HP Documentation"
    }
    catch {
        Write-Host "Error Remvoving HP Documentation $($_.Exception.Message)"
    }
}
else {
    Write-Host "HP Documentation is not installed"
}

#Remove HP Support Assistant silently
$HPSAuninstall = "${Env:ProgramFiles(x86)}\HP\HP Support Framework\UninstallHPSA.exe"

if (Test-Path -Path "HKLM:\Software\WOW6432Node\Hewlett-Packard\HPActiveSupport") {
    try {
        Remove-Item -Path "HKLM:\Software\WOW6432Node\Hewlett-Packard\HPActiveSupport"
        Write-Host "HP Support Assistant regkey deleted $($_.Exception.Message)"
    }
    catch {
        Write-Host "Error retreiving registry key for HP Support Assistant: $($_.Exception.Message)"
    }
}
else {
    Write-Host "HP Support Assistant regkey not found"
}

if (Test-Path $HPSAuninstall -PathType Leaf) {
    try {
        & $HPSAuninstall /s /v/qn UninstallKeepPreferences=FALSE
        Write-Host "Successfully removed provisioned package: HP Support Assistant silently"
    }
    catch {
        Write-Host "Error uninstalling HP Support Assistant: $($_.Exception.Message)"
    }
}
else {
    Write-Host "HP Support Assistant Uninstaller not found"
}

#Remove HP Connection Optimizer
$HPCOuninstall = "${Env:ProgramFiles(x86)}\InstallShield Installation Information\{6468C4A5-E47E-405F-B675-A70A70983EA6}\setup.exe"
if (Test-Path $HPCOuninstall -PathType Leaf) {
    Try {
        # Generating uninstall file
        "[InstallShield Silent]
        Version=v7.00
        File=Response File
        [File Transfer]
        OverwrittenReadOnly=NoToAll
        [{6468C4A5-E47E-405F-B675-A70A70983EA6}-DlgOrder]
        Dlg0={6468C4A5-E47E-405F-B675-A70A70983EA6}-MessageBox-0
        Count=2
        Dlg1={6468C4A5-E47E-405F-B675-A70A70983EA6}-SdFinish-0
        [{6468C4A5-E47E-405F-B675-A70A70983EA6}-MessageBox-0]
        Result=6
        [Application]
        Name=HP Connection Optimizer
        Version=2.0.19.0
        Company=HP
        Lang=0413
        [{6468C4A5-E47E-405F-B675-A70A70983EA6}-SdFinish-0]
        Result=1
        bOpt1=0
        bOpt2=0" | Out-File -FilePath "${Env:Temp}\uninstallHPCO.iss" -Encoding UTF8 -Force:$true -Confirm:$false

        Write-Host "Successfully created uninstall file ${Env:Temp}\uninstallHPCO.iss"

        & $HPCOuninstall -runfromtemp -l0x0413 -removeonly -s -f1${Env:Temp}\uninstallHPCO.iss
        Write-Host "Successfully removed HP Connection Optimizer"
    }
    Catch {
        Write-Host "Error uninstalling HP Connection Optimizer: $($_.Exception.Message)"
    }
}
Else {
    Write-Host "HP Connection Optimizer not found"
}

#List of built-in apps to remove
$UninstallPackages = @(
    "AD2F1837.HPJumpStarts"
    "AD2F1837.HPPCHardwareDiagnosticsWindows"
    "AD2F1837.HPPowerManager"
    "AD2F1837.HPPrivacySettings"
    "AD2F1837.HPSupportAssistant"
    "AD2F1837.HPSureShieldAI"
    "AD2F1837.HPSystemInformation"
    "AD2F1837.HPQuickDrop"
    "AD2F1837.HPWorkWell"
    "AD2F1837.myHP"
    "AD2F1837.HPDesktopSupportUtilities"
    "AD2F1837.HPQuickTouch"
    "AD2F1837.HPEasyClean"
    "AD2F1837.HPSystemInformation"
)

#List of programs to uninstall
$UninstallPrograms = @(
    "HP Client Security Manager"
    "HP Connection Optimizer"
    "HP Documentation"
    "HP MAC Address Manager"
    "HP Notifications"
    "HP Security Update Service"
    "HP System Default Settings"
    "HP Sure Click"
    "HP Sure Click Security Browser"
    "HP Sure Run"
    "HP Sure Recover"
    "HP Sure Sense"
    "HP Sure Sense Installer"
)

$HPidentifier = "AD2F1837"

$InstalledPackages = Get-AppxPackage -AllUsers `
| Where-Object { ($UninstallPackages -contains $_.Name) -or ($_.Name -match "^$HPidentifier") }

$ProvisionedPackages = Get-AppxProvisionedPackage -Online `
| Where-Object { ($UninstallPackages -contains $_.DisplayName) -or ($_.DisplayName -match "^$HPidentifier") }

$InstalledPrograms = Get-Package | Where-Object { $UninstallPrograms -contains $_.Name } | Sort-Object Name -Descending

#Remove appx provisioned packages - AppxProvisionedPackage
ForEach ($ProvPackage in $ProvisionedPackages) {
    Write-Host -Object "Attempting to remove provisioned package: [$($ProvPackage.DisplayName)]..."
    try {
        $Null = Remove-AppxProvisionedPackage -PackageName $ProvPackage.PackageName -Online -ErrorAction Stop
        Write-Host -Object "Successfully removed provisioned package: [$($ProvPackage.DisplayName)]"
    }
    catch { Write-Warning -Message "Failed to remove provisioned package: [$($ProvPackage.DisplayName)]" }
}

#Remove appx packages - AppxPackage
ForEach ($AppxPackage in $InstalledPackages) {                                        
    Write-Host -Object "Attempting to remove Appx package: [$($AppxPackage.Name)]..."
    try {
        $Null = Remove-AppxPackage -Package $AppxPackage.PackageFullName -AllUsers -ErrorAction Stop
        Write-Host -Object "Successfully removed Appx package: [$($AppxPackage.Name)]"
    }
    catch { Write-Warning -Message "Failed to remove Appx package: [$($AppxPackage.Name)]" }
}

#Remove installed programs
ForEach ($InstalledProgram in $InstalledPrograms) {
    Write-Host -Object "Attempting to uninstall: [$($InstalledProgram.Name)]..."
    try {
        $Null = $InstalledProgram | Uninstall-Package -AllVersions -Force -ErrorAction Stop
        Write-Host -Object "Successfully uninstalled: [$($InstalledProgram.Name)]"
    }
    catch {
        Write-Warning -Message "Failed to uninstall: [$($InstalledProgram.Name)]"
        Write-Host -Object "Attempting to uninstall as MSI package: [$($InstalledProgram.Name)]..."
        try {
            $MSIApp = Get-WmiObject Win32_Product | Where-Object { $_.name -like "$($InstalledProgram.Name)" }
            if ($null -ne $MSIApp.IdentifyingNumber) {
                Start-Process -FilePath msiexec.exe -ArgumentList @("/x $($MSIApp.IdentifyingNumber)", "/quiet", "/noreboot") -Wait
            }
            else { Write-Warning -Message "Can't find MSI package: [$($InstalledProgram.Name)]" }
        }
        catch { Write-Warning -Message "Failed to uninstall MSI package: [$($InstalledProgram.Name)]" }
    }
}

#Try to remove all HP Wolf Security apps using msiexec
$InstalledWolfSecurityPrograms = Get-WmiObject Win32_Product | Where-Object { $_.name -like "HP Wolf Security*" }
ForEach ($InstalledWolfSecurityProgram in $InstalledWolfSecurityPrograms) {
    try {
        if ($null -ne $InstalledWolfSecurityProgram.IdentifyingNumber) {
            Start-Process -FilePath msiexec.exe -ArgumentList @("/x $($InstalledWolfSecurityProgram.IdentifyingNumber)", "/quiet", "/noreboot") -Wait
            Write-Host "Attempting to uninstall as MSI package: [$($InstalledWolfSecurityProgram.Name)]..."
        }
        else { Write-Warning -Message "Can't find MSI package: [$($InstalledWolfSecurityProgram.Name)]" }
    }
    catch {
        Write-Warning -Message "Failed to uninstall MSI package: [$($InstalledWolfSecurityProgram.Name)]"
    }
}