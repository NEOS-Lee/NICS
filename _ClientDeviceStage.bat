@echo off
setlocal EnableExtensions DisableDelayedExpansion
title NEOS Device Preparation

set "_ScriptVersion=2.1.0"
set "_PowerShell=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if defined PROCESSOR_ARCHITEW6432 set "_PowerShell=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%_PowerShell%" (
    echo ERROR: Windows PowerShell could not be found.
    pause
    exit /b 1
)

:: ============================================
:: Administrative privilege check
:: ============================================
"%_PowerShell%" -NoProfile -ExecutionPolicy Bypass -Command "$identity=[Security.Principal.WindowsIdentity]::GetCurrent(); $principal=[Security.Principal.WindowsPrincipal]::new($identity); if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }"

if not errorlevel 1 goto gotAdmin

echo Requesting administrative privileges...
set "_ElevateTarget=%~f0"
"%_PowerShell%" -NoProfile -ExecutionPolicy Bypass -Command "try { Start-Process -FilePath $env:_ElevateTarget -Verb RunAs -ErrorAction Stop } catch { exit 1 }"

if errorlevel 1 goto ElevationFailed
exit /b 0

:ElevationFailed
echo.
echo ERROR: Administrative elevation was canceled or failed.
pause
exit /b 1

:gotAdmin
pushd "%~dp0"
if errorlevel 1 goto StartupDirectoryError

:: ============================================
:: Working folders, logging, and package sources
:: ============================================
set "_WorkRoot=%ProgramData%\NEOS\DevicePreparation"
set "_CacheDir=%_WorkRoot%\Cache"
set "_LogDir=%_WorkRoot%\Logs"

if not exist "%_CacheDir%" md "%_CacheDir%" >nul 2>&1
if not exist "%_LogDir%" md "%_LogDir%" >nul 2>&1

if not exist "%_CacheDir%" goto WorkingFolderError
if not exist "%_LogDir%" goto WorkingFolderError

set "_LogFile=%_LogDir%\DevicePreparation-%COMPUTERNAME%-%RANDOM%-%RANDOM%.log"
set "_RebootRequired=0"

set "_ChromeUrl=https://dl.google.com/chrome/install/GoogleChromeStandaloneEnterprise64.msi"
set "_ChromeInstaller=%_CacheDir%\GoogleChromeStandaloneEnterprise64.msi"

:: Adobe publishes version-specific enterprise installer URLs.
:: Refresh these two values when adopting a newer tested Adobe release.
set "_AdobeVersion=2600121745"
set "_AdobeUrl=https://ardownload2.adobe.com/pub/adobe/acrobat/win/AcrobatDC/%_AdobeVersion%/AcroRdrDCx64%_AdobeVersion%_MUI.exe"
set "_AdobeInstaller=%_CacheDir%\AcroRdrDCx64%_AdobeVersion%_MUI.exe"

:: These Microsoft URLs always target the latest OpenJDK 21 LTS MSI.
set "_JdkUrl=https://aka.ms/download-jdk/microsoft-jdk-21-windows-x64.msi"
set "_JdkInstaller=%_CacheDir%\MicrosoftOpenJDK21-x64.msi"
if /I "%PROCESSOR_ARCHITECTURE%"=="ARM64" (
    set "_JdkUrl=https://aka.ms/download-jdk/microsoft-jdk-21-windows-aarch64.msi"
    set "_JdkInstaller=%_CacheDir%\MicrosoftOpenJDK21-arm64.msi"
)
if /I "%PROCESSOR_ARCHITEW6432%"=="ARM64" (
    set "_JdkUrl=https://aka.ms/download-jdk/microsoft-jdk-21-windows-aarch64.msi"
    set "_JdkInstaller=%_CacheDir%\MicrosoftOpenJDK21-arm64.msi"
)

:: BGInfo is downloaded from the official Microsoft Sysinternals site.
:: Place an optional NEOS-BGInfo.bgi file beside this batch file to deploy
:: a customized layout. Otherwise, BGInfo uses its default per-user layout.
set "_BGInfoUrl=https://download.sysinternals.com/files/BGInfo.zip"
set "_BGInfoPackage=%_CacheDir%\BGInfo.zip"
set "_BGInfoRoot=%ProgramData%\NEOS\BGInfo"
set "_BGInfoExe=%_BGInfoRoot%\BGInfo.exe"
set "_BGInfoConfigSource=%~dp0NEOS-BGInfo.bgi"
set "_BGInfoConfig=%_BGInfoRoot%\NEOS-BGInfo.bgi"

call :Log "NEOS Device Preparation version %_ScriptVersion% started."
call :Log "Running as %USERDOMAIN%\%USERNAME% on %COMPUTERNAME%."

:: ============================================
:: Main Menu
:: ============================================
:mainmenu
cls
echo ======================================
echo      NEOS Device Preparation Tool
echo             Version %_ScriptVersion%
echo ======================================
echo 1. Remove HP Bloatware
echo 2. Set and Activate Local Admin
echo 3. Install Applications
echo 4. Rename or Domain Join Device
echo 5. Repair and Sync Computer Time
echo 6. Install and Configure BGInfo
echo 7. Run Windows Update
echo 8. Exit
echo ======================================
if "%_RebootRequired%"=="1" echo NOTE: One or more completed tasks require a restart.
choice /C 12345678 /N /M "Select an option [1-8]:"
set "_MenuChoice=%errorlevel%"

if "%_MenuChoice%"=="1" goto removebloatwarescript
if "%_MenuChoice%"=="2" goto setuplocaladmin
if "%_MenuChoice%"=="3" goto appmenu
if "%_MenuChoice%"=="4" goto renamejoin
if "%_MenuChoice%"=="5" goto repairtime
if "%_MenuChoice%"=="6" goto setupbginfo
if "%_MenuChoice%"=="7" goto updateyes
if "%_MenuChoice%"=="8" goto end
goto mainmenu

:: ============================================
:: Task 1 - Remove HP Bloatware
:: ============================================
:removebloatwarescript
cls
echo ======================================
echo Remove HP Bloatware
echo ======================================
echo.

if not exist "%~dp0Detect-HPBloatware.ps1" (
    echo ERROR: Detect-HPBloatware.ps1 was not found beside this batch file.
    call :Log "HP bloatware task failed: detection script missing."
    pause
    goto mainmenu
)

if not exist "%~dp0Remove-HPBloatwareNew.ps1" (
    echo ERROR: Remove-HPBloatwareNew.ps1 was not found beside this batch file.
    call :Log "HP bloatware task failed: removal script missing."
    pause
    goto mainmenu
)

echo Running HP bloatware detection...
call :Log "Starting HP bloatware detection."
call :RunPowerShellScript "%~dp0Detect-HPBloatware.ps1"
if errorlevel 1 (
    echo.
    echo WARNING: HP bloatware detection returned an error.
    call :Log "HP bloatware detection returned an error."
    choice /C YN /N /M "Run the removal script anyway? [Y/N]:"
    if errorlevel 2 goto mainmenu
)

echo.
echo Running HP bloatware removal...
call :Log "Starting HP bloatware removal."
call :RunPowerShellScript "%~dp0Remove-HPBloatwareNew.ps1"
if errorlevel 1 (
    echo.
    echo ERROR: HP bloatware removal failed. Review the script output above.
    call :Log "HP bloatware removal failed."
    pause
    goto mainmenu
)

echo.
echo Bloatware task completed successfully.
call :Log "HP bloatware task completed successfully."
pause
goto mainmenu

:: ============================================
:: Task 2 - Local Administrator
:: ============================================
:setuplocaladmin
cls
echo ======================================
echo Local Administrator Setup
echo ======================================
echo.
echo The password will not be displayed.
echo The built-in Administrator account is located by its SID,
echo so this also works if the account was renamed or localized.
echo.

call :Log "Starting local Administrator configuration."
"%_PowerShell%" -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $b1=[IntPtr]::Zero; $b2=[IntPtr]::Zero; try { $admin=Get-LocalUser | Where-Object { $_.SID.Value -match '-500$' } | Select-Object -First 1; if (-not $admin) { throw 'The built-in Administrator account could not be found.' }; Write-Host ('Account: ' + $admin.Name); $p1=Read-Host 'Enter desired local Administrator password' -AsSecureString; $p2=Read-Host 'Confirm the password' -AsSecureString; $b1=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($p1); $b2=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($p2); $s1=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($b1); $s2=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($b2); if ([string]::IsNullOrWhiteSpace($s1)) { throw 'The password cannot be blank.' }; if ($s1 -cne $s2) { throw 'The passwords do not match.' }; Set-LocalUser -InputObject $admin -Password $p1; Enable-LocalUser -InputObject $admin; Write-Host 'The built-in Administrator account was updated and enabled.' } catch { Write-Error $_.Exception.Message; exit 1 } finally { if ($b1 -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b1) }; if ($b2 -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b2) } }"
set "_TaskRC=%errorlevel%"

if "%_TaskRC%"=="0" (
    echo.
    echo Local Administrator configuration completed successfully.
    call :Log "Local Administrator configuration completed successfully."
) else (
    echo.
    echo ERROR: Local Administrator configuration failed.
    call :Log "Local Administrator configuration failed with exit code %_TaskRC%."
)

pause
goto mainmenu

:: ============================================
:: Task 3 - Application Installation Menu
:: ============================================
:appmenu
cls
echo ======================================
echo Application Installation
echo ======================================
echo 1. Install Google Chrome
echo 2. Install Adobe Acrobat Reader
echo 3. Install Microsoft OpenJDK 21
echo 4. Install All Applications
echo 5. Return to Main Menu
echo ======================================
choice /C 12345 /N /M "Select an option [1-5]:"
set "_AppChoice=%errorlevel%"

if "%_AppChoice%"=="1" goto chromeInstall
if "%_AppChoice%"=="2" goto adobeInstall
if "%_AppChoice%"=="3" goto javaInstall
if "%_AppChoice%"=="4" goto fullappinstall
if "%_AppChoice%"=="5" goto mainmenu
goto appmenu

:chromeInstall
cls
echo ======================================
echo Google Chrome Installation
echo ======================================
echo.
call :InstallChrome
pause
goto appmenu

:adobeInstall
cls
echo ======================================
echo Adobe Acrobat Reader Installation
echo ======================================
echo.
call :InstallAdobe
pause
goto appmenu

:javaInstall
cls
echo ======================================
echo Microsoft OpenJDK 21 Installation
echo ======================================
echo.
call :InstallJdk
pause
goto appmenu

:fullappinstall
cls
echo ======================================
echo Install All Applications
echo ======================================
echo.

set /a "_AppFailures=0"

echo [1/3] Google Chrome
call :InstallChrome
if errorlevel 1 set /a "_AppFailures+=1"
echo.

echo [2/3] Adobe Acrobat Reader
call :InstallAdobe
if errorlevel 1 set /a "_AppFailures+=1"
echo.

echo [3/3] Microsoft OpenJDK 21
call :InstallJdk
if errorlevel 1 set /a "_AppFailures+=1"
echo.

if "%_AppFailures%"=="0" (
    echo All application installations completed successfully.
    call :Log "Install All completed successfully."
) else (
    echo WARNING: %_AppFailures% application installation tasks failed.
    echo Review the messages above and the logs in:
    echo %_LogDir%
    call :Log "Install All completed with %_AppFailures% failure(s)."
)

pause
goto appmenu

:: ============================================
:: Task 4 - Rename / Domain Join
:: ============================================
:renamejoin
cls
echo ======================================
echo Rename or Domain Join Device
echo ======================================
echo.
echo Opening System Properties...
call :Log "Opening System Properties for rename or domain join."
start "" "%SystemRoot%\System32\control.exe" sysdm.cpl
if errorlevel 1 (
    echo ERROR: System Properties could not be opened.
    call :Log "System Properties failed to open."
) else (
    echo.
    echo Complete the rename or domain join, then return to this window.
)
pause
goto mainmenu

:: ============================================
:: Task 5 - Repair and Sync Computer Time
:: ============================================
:repairtime
cls
echo ======================================
echo Repair and Sync Computer Time
echo ======================================
echo.
echo Domain-joined computers will use the domain time hierarchy.
echo Workgroup computers will use time.windows.com and time.nist.gov.
echo The configured time zone will be displayed but will not be changed.
echo.

call :Log "Starting Windows Time repair and synchronization."
"%_PowerShell%" -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $w32tm=Join-Path $env:SystemRoot 'System32\w32tm.exe'; try { Set-Service -Name W32Time -StartupType Automatic; if ((Get-Service -Name W32Time).Status -ne 'Running') { Start-Service -Name W32Time }; $domain=[bool](Get-CimInstance -ClassName Win32_ComputerSystem).PartOfDomain; if ($domain) { Write-Host 'Domain membership detected. Configuring domain hierarchy time.'; & $w32tm /config /syncfromflags:domhier /update | Out-Host } else { Write-Host 'Workgroup computer detected. Configuring public NTP sources.'; & $w32tm /config '/manualpeerlist:time.windows.com,0x9 time.nist.gov,0x9' /syncfromflags:manual /update | Out-Host }; if ($LASTEXITCODE -ne 0) { throw ('w32tm configuration failed with exit code ' + $LASTEXITCODE) }; Restart-Service -Name W32Time -Force; Start-Sleep -Seconds 3; & $w32tm /resync /rediscover | Out-Host; if ($LASTEXITCODE -ne 0) { Start-Sleep -Seconds 3; & $w32tm /resync /force | Out-Host }; if ($LASTEXITCODE -ne 0) { throw ('Time synchronization failed with exit code ' + $LASTEXITCODE) }; Write-Host ''; Write-Host 'Current time source:'; & $w32tm /query /source | Out-Host; Write-Host ''; & $w32tm /query /status | Out-Host; Write-Host ''; Write-Host ('Current time zone: ' + (Get-TimeZone).DisplayName) } catch { Write-Error $_.Exception.Message; exit 1 }"
set "_TimeRC=%errorlevel%"

if "%_TimeRC%"=="0" (
    echo.
    echo Computer time synchronized successfully.
    call :Log "Windows Time repair and synchronization completed successfully."
) else (
    echo.
    echo ERROR: Computer time synchronization failed.
    echo Confirm that the network permits NTP traffic and review the output above.
    call :Log "Windows Time repair failed with exit code %_TimeRC%."
)

pause
goto mainmenu

:: ============================================
:: Task 6 - Install and Configure BGInfo
:: ============================================
:setupbginfo
cls
echo ======================================
echo Install and Configure BGInfo
echo ======================================
echo.
echo BGInfo will be installed for this computer and will refresh the
echo desktop information whenever a user signs in.
echo.
if exist "%_BGInfoConfigSource%" (
    echo Custom configuration found:
    echo "%_BGInfoConfigSource%"
) else if exist "%_BGInfoConfig%" (
    echo No new NEOS-BGInfo.bgi file was found beside this batch file.
    echo The previously installed custom configuration will be kept.
) else (
    echo No NEOS-BGInfo.bgi file was found beside this batch file.
    echo The standard BGInfo layout will be used.
)
echo.

call :InstallBGInfo
set "_BGInfoRC=%errorlevel%"

if "%_BGInfoRC%"=="0" (
    echo.
    echo BGInfo setup completed successfully.
    echo It will run automatically for every user at sign-in.
    call :Log "BGInfo setup completed successfully."
) else (
    echo.
    echo ERROR: BGInfo setup failed.
    echo Review the messages above and the log file for details.
    call :Log "BGInfo setup failed with exit code %_BGInfoRC%."
)

pause
goto mainmenu

:: ============================================
:: Task 7 - Windows Update
:: ============================================
:updateyes
cls
echo ======================================
echo Windows Update
echo ======================================
echo.
echo Installing available updates without automatically restarting...
echo This can take a considerable amount of time.
echo.

call :Log "Starting Windows Update."
"%_PowerShell%" -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $required=[version]'2.2.1.5'; $repoCreated=$false; $repo=Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue; if (-not $repo) { Register-PSRepository -Default; $repoCreated=$true; $repo=Get-PSRepository -Name PSGallery -ErrorAction Stop }; $oldPolicy=$repo.InstallationPolicy; $needsReboot=$false; try { if ($oldPolicy -ne 'Trusted') { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted }; if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null }; if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate | Where-Object { $_.Version -eq $required })) { Install-Module -Name PSWindowsUpdate -RequiredVersion $required -Force -AllowClobber -Scope AllUsers -Confirm:$false }; Import-Module PSWindowsUpdate -RequiredVersion $required -Force; Get-WindowsUpdate -AcceptAll -Install -IgnoreReboot -Verbose; $sessionRename=Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue; $needsReboot=(Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or ($null -ne $sessionRename) } finally { if ($repoCreated) { Unregister-PSRepository -Name PSGallery } elseif ($oldPolicy -ne 'Trusted') { Set-PSRepository -Name PSGallery -InstallationPolicy $oldPolicy } }; if ($needsReboot) { exit 3010 }"
set "_UpdateRC=%errorlevel%"

if "%_UpdateRC%"=="0" goto UpdateSuccess
if "%_UpdateRC%"=="3010" goto UpdateRebootRequired

echo.
echo ERROR: Windows Update failed with exit code %_UpdateRC%.
call :Log "Windows Update failed with exit code %_UpdateRC%."
pause
goto mainmenu

:UpdateSuccess
echo.
echo Windows Update completed successfully. No restart was detected.
call :Log "Windows Update completed successfully without a detected restart requirement."
pause
goto mainmenu

:UpdateRebootRequired
set "_RebootRequired=1"
echo.
echo Windows Update completed successfully and a restart is required.
call :Log "Windows Update completed successfully and requires a restart."
choice /C YN /N /M "Restart the computer in 30 seconds? [Y/N]:"
set "_RestartChoice=%errorlevel%"

if not "%_RestartChoice%"=="1" goto mainmenu

shutdown.exe /r /t 30 /c "NEOS device preparation completed Windows Update."
if errorlevel 1 (
    echo ERROR: The restart could not be scheduled.
    call :Log "Failed to schedule the Windows restart."
    pause
    goto mainmenu
)

echo Restart scheduled. Run shutdown /a within 30 seconds to cancel.
call :Log "Computer restart scheduled for 30 seconds."
goto EndNoPause

:: ============================================
:: Application helper routines
:: ============================================
:InstallChrome
echo Preparing Google Chrome...
call :Log "Preparing Google Chrome installation."
call :DownloadVerified "%_ChromeUrl%" "%_ChromeInstaller%" "Google LLC" "14" "Google Chrome"
if errorlevel 1 exit /b 1

echo Installing Google Chrome...
msiexec.exe /i "%_ChromeInstaller%" /qn /norestart /L*v "%_LogDir%\GoogleChrome-install.log"
set "_InstallRC=%errorlevel%"
call :HandleInstallerResult "%_InstallRC%" "Google Chrome"
exit /b %errorlevel%

:InstallAdobe
echo Preparing Adobe Acrobat Reader...
call :Log "Preparing Adobe Acrobat Reader installation."
call :DownloadVerified "%_AdobeUrl%" "%_AdobeInstaller%" "Adobe Inc" "90" "Adobe Acrobat Reader"
if errorlevel 1 exit /b 1

echo Installing Adobe Acrobat Reader...
"%_AdobeInstaller%" -sfx_nu /sAll /rs /msi /log "%_LogDir%\AdobeReader-install.log"
set "_InstallRC=%errorlevel%"
call :HandleInstallerResult "%_InstallRC%" "Adobe Acrobat Reader"
exit /b %errorlevel%

:InstallJdk
echo Preparing Microsoft OpenJDK 21...
call :Log "Preparing Microsoft OpenJDK 21 installation."
call :DownloadVerified "%_JdkUrl%" "%_JdkInstaller%" "Microsoft Corporation" "14" "Microsoft OpenJDK 21"
if errorlevel 1 exit /b 1

echo Installing Microsoft OpenJDK 21...
msiexec.exe /i "%_JdkInstaller%" /qn /norestart ADDLOCAL=ALL /L*v "%_LogDir%\MicrosoftOpenJDK21-install.log"
set "_InstallRC=%errorlevel%"
call :HandleInstallerResult "%_InstallRC%" "Microsoft OpenJDK 21"
exit /b %errorlevel%

:InstallBGInfo
echo Preparing Microsoft Sysinternals BGInfo...
call :Log "Preparing Microsoft Sysinternals BGInfo setup."
"%_PowerShell%" -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; function Save-BgInfoPackage { $temp=$env:_BGInfoPackage+'.download'; try { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }; try { Start-BitsTransfer -Source $env:_BGInfoUrl -Destination $temp -ErrorAction Stop } catch { Invoke-WebRequest -Uri $env:_BGInfoUrl -OutFile $temp -UseBasicParsing }; $item=Get-Item -LiteralPath $temp -ErrorAction Stop; if ($item.Length -lt 1MB) { throw 'The downloaded BGInfo package is unexpectedly small.' }; Move-Item -LiteralPath $temp -Destination $env:_BGInfoPackage -Force; (Get-Item -LiteralPath $env:_BGInfoPackage).LastWriteTimeUtc=[DateTime]::UtcNow } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue } } }; function Install-BgInfoPackage { param([string]$Archive); $stage=Join-Path ([IO.Path]::GetTempPath()) ('NEOS-BGInfo-'+[guid]::NewGuid().ToString('N')); try { Expand-Archive -LiteralPath $Archive -DestinationPath $stage -Force; $isX64=($env:PROCESSOR_ARCHITECTURE -eq 'AMD64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'AMD64'); $sourceName=if ($isX64) { 'Bginfo64.exe' } else { 'Bginfo.exe' }; $sourceExe=Join-Path $stage $sourceName; if (-not (Test-Path -LiteralPath $sourceExe -PathType Leaf)) { throw ('The BGInfo package does not contain '+$sourceName+'.') }; $sig=Get-AuthenticodeSignature -LiteralPath $sourceExe; if ($sig.Status -ne 'Valid' -or $null -eq $sig.SignerCertificate -or $sig.SignerCertificate.Subject -notmatch 'Microsoft Corporation') { throw ('BGInfo signature validation failed. Status: '+$sig.Status) }; New-Item -ItemType Directory -Path $env:_BGInfoRoot -Force | Out-Null; Copy-Item -LiteralPath $sourceExe -Destination $env:_BGInfoExe -Force; Unblock-File -LiteralPath $env:_BGInfoExe -ErrorAction SilentlyContinue; $eula=Join-Path $stage 'Eula.txt'; if (Test-Path -LiteralPath $eula) { Copy-Item -LiteralPath $eula -Destination (Join-Path $env:_BGInfoRoot 'Eula.txt') -Force } } finally { if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue } } }; $refresh=$true; if (Test-Path -LiteralPath $env:_BGInfoPackage -PathType Leaf) { $cached=Get-Item -LiteralPath $env:_BGInfoPackage; if ($cached.Length -ge 1MB -and ((Get-Date)-$cached.LastWriteTime).TotalDays -le 30) { $refresh=$false; Write-Host 'Using the cached BGInfo package.' } }; if ($refresh) { Write-Host 'Downloading BGInfo from Microsoft Sysinternals...'; Save-BgInfoPackage }; try { Install-BgInfoPackage -Archive $env:_BGInfoPackage } catch { if ($refresh) { throw }; Write-Host 'The cached package is invalid. Downloading a fresh copy...'; Save-BgInfoPackage; Install-BgInfoPackage -Archive $env:_BGInfoPackage }; $config=$null; if (Test-Path -LiteralPath $env:_BGInfoConfigSource -PathType Leaf) { Copy-Item -LiteralPath $env:_BGInfoConfigSource -Destination $env:_BGInfoConfig -Force; $config=$env:_BGInfoConfig; Write-Host 'Installed the custom NEOS-BGInfo.bgi configuration.' } elseif (Test-Path -LiteralPath $env:_BGInfoConfig -PathType Leaf) { $config=$env:_BGInfoConfig; Write-Host 'Keeping the previously installed NEOS-BGInfo.bgi configuration.' } else { Write-Host 'Using the standard BGInfo layout.' }; $startup=[Environment]::GetFolderPath([Environment+SpecialFolder]::CommonStartup); if ([string]::IsNullOrWhiteSpace($startup)) { throw 'The common Startup folder could not be resolved.' }; $quote=[char]34; $configArgument=if ($config) { $quote+$config+$quote+' ' } else { '' }; $startupArguments=$configArgument+'/timer:0 /silent /accepteula'; $shortcutPath=Join-Path $startup 'NEOS BGInfo.lnk'; $shell=New-Object -ComObject WScript.Shell; $shortcut=$shell.CreateShortcut($shortcutPath); $shortcut.TargetPath=$env:_BGInfoExe; $shortcut.Arguments=$startupArguments; $shortcut.WorkingDirectory=$env:_BGInfoRoot; $shortcut.Description='Refresh the desktop with Microsoft Sysinternals BGInfo'; $shortcut.IconLocation=$env:_BGInfoExe+',0'; $shortcut.Save(); if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) { throw 'The all-users BGInfo Startup shortcut was not created.' }; try { $currentArguments=$configArgument+'/timer:0 /accepteula'; $process=Start-Process -FilePath $env:_BGInfoExe -ArgumentList $currentArguments -PassThru -Wait -ErrorAction Stop; if ($process.ExitCode -ne 0) { Write-Warning ('BGInfo was installed, but the immediate desktop refresh returned exit code '+$process.ExitCode+'.') } } catch { Write-Warning ('BGInfo was installed, but the current desktop could not be refreshed: '+$_.Exception.Message) }; $version=(Get-Item -LiteralPath $env:_BGInfoExe).VersionInfo.FileVersion; Write-Host ('BGInfo '+$version+' installed at '+$env:_BGInfoExe); Write-Host ('All-users Startup shortcut: '+$shortcutPath)"
set "_BGInfoInstallRC=%errorlevel%"

if not "%_BGInfoInstallRC%"=="0" (
    echo ERROR: BGInfo could not be downloaded, verified, or configured.
    call :Log "Microsoft Sysinternals BGInfo setup failed with exit code %_BGInfoInstallRC%."
    exit /b 1
)

call :Log "Microsoft Sysinternals BGInfo was installed and configured for all-user sign-in."
exit /b 0

:HandleInstallerResult
setlocal EnableExtensions DisableDelayedExpansion
set "_ResultCode=%~1"
set "_ResultName=%~2"

if "%_ResultCode%"=="0" goto HIRSuccess
if "%_ResultCode%"=="1641" goto HIRReboot
if "%_ResultCode%"=="3010" goto HIRReboot
goto HIRFailure

:HIRSuccess
echo %_ResultName% installation completed successfully.
call :Log "%_ResultName% installation completed successfully."
endlocal & exit /b 0

:HIRReboot
echo %_ResultName% installation completed successfully. A restart is required.
call :Log "%_ResultName% installation completed with success code %_ResultCode%; restart required."
endlocal & set "_RebootRequired=1" & exit /b 0

:HIRFailure
echo ERROR: %_ResultName% installation failed with exit code %_ResultCode%.
call :Log "%_ResultName% installation failed with exit code %_ResultCode%."
endlocal & exit /b 1

:DownloadVerified
setlocal EnableExtensions DisableDelayedExpansion
set "_InstallerUrl=%~1"
set "_InstallerPath=%~2"
set "_ExpectedSigner=%~3"
set "_MaxCacheAgeDays=%~4"
set "_DisplayName=%~5"

if exist "%_InstallerPath%" (
    "%_PowerShell%" -NoProfile -ExecutionPolicy Bypass -Command "$p=$env:_InstallerPath; try { $item=Get-Item -LiteralPath $p -ErrorAction Stop; if ($item.Length -lt 1MB) { exit 1 }; $sig=Get-AuthenticodeSignature -LiteralPath $p; if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch $env:_ExpectedSigner) { exit 1 }; if (((Get-Date)-$item.LastWriteTime).TotalDays -gt [double]$env:_MaxCacheAgeDays) { exit 2 }; exit 0 } catch { exit 1 }"
    if not errorlevel 1 (
        echo Using verified cached %_DisplayName% installer.
        call :Log "Using verified cached %_DisplayName% installer."
        endlocal & exit /b 0
    )
    echo The cached %_DisplayName% installer is expired or invalid. Refreshing it...
)

for %%F in ("%_InstallerPath%") do set "_DownloadTemp=%%~dpF%%~nF.download%%~xF"
echo Downloading %_DisplayName% from the publisher...
"%_PowerShell%" -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $temp=$env:_DownloadTemp; try { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }; try { Start-BitsTransfer -Source $env:_InstallerUrl -Destination $temp -ErrorAction Stop } catch { Invoke-WebRequest -Uri $env:_InstallerUrl -OutFile $temp -UseBasicParsing }; $item=Get-Item -LiteralPath $temp -ErrorAction Stop; if ($item.Length -lt 1MB) { throw 'The downloaded file is unexpectedly small.' }; $sig=Get-AuthenticodeSignature -LiteralPath $temp; if ($sig.Status -ne 'Valid') { throw ('Authenticode status is ' + $sig.Status) }; if ($sig.SignerCertificate.Subject -notmatch $env:_ExpectedSigner) { throw ('Unexpected signer: ' + $sig.SignerCertificate.Subject) }; Unblock-File -LiteralPath $temp; Move-Item -LiteralPath $temp -Destination $env:_InstallerPath -Force; (Get-Item -LiteralPath $env:_InstallerPath).LastWriteTimeUtc=[DateTime]::UtcNow } catch { Write-Error $_.Exception.Message; if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }; exit 1 }"

if errorlevel 1 goto DVFailure
if not exist "%_InstallerPath%" goto DVFailure

echo Download and signature verification completed.
call :Log "%_DisplayName% download and signature verification completed."
endlocal & exit /b 0

:DVFailure
echo ERROR: %_DisplayName% could not be downloaded and verified.
call :Log "%_DisplayName% download or verification failed."
endlocal & exit /b 1

:RunPowerShellScript
setlocal EnableExtensions DisableDelayedExpansion
set "_PsScript=%~1"

if not exist "%_PsScript%" (
    echo ERROR: PowerShell script not found: %_PsScript%
    endlocal & exit /b 1
)

"%_PowerShell%" -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { & $env:_PsScript; exit 0 } catch { Write-Error $_.Exception.Message; exit 1 }"
set "_PsScriptRC=%errorlevel%"
endlocal & exit /b %_PsScriptRC%

:Log
setlocal DisableDelayedExpansion
set "_LogMessage=%~1"
set "_LogDate=%date%"
set "_LogTime=%time%"
setlocal EnableDelayedExpansion
>>"%_LogFile%" echo([!_LogDate! !_LogTime!] !_LogMessage!
endlocal
endlocal & exit /b 0

:: ============================================
:: Startup and exit handling
:: ============================================
:StartupDirectoryError
echo.
echo ERROR: Unable to access the batch file directory:
echo %~dp0
echo If this was launched from a mapped drive, use a local path or UNC path.
pause
exit /b 1

:WorkingFolderError
echo.
echo ERROR: Unable to create the working folders under:
echo %ProgramData%\NEOS\DevicePreparation
pause
popd
exit /b 1

:end
cls
echo ======================================
echo      NEOS Device Preparation Tool
echo ======================================
echo.
echo Thanks for using NEOS Device Preparation.
echo Do not forget to remove the staging user account if needed.
if "%_RebootRequired%"=="1" echo NOTE: One or more completed tasks require a restart.
echo.
echo Log folder:
echo %_LogDir%
echo.
call :Log "NEOS Device Preparation closed."
pause

:EndNoPause
popd
endlocal
exit /b 0
