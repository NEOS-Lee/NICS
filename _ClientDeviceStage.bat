@echo off
echo NEOS Device Preparation
pause

:: BatchGotAdmin
:-------------------------------------
REM  --> Check for permissions
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"

REM --> If error flag set, we do not have admin.
if '%errorlevel%' NEQ '0' (
    echo Requesting administrative privileges...
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    set params = %*:"=""
    echo UAC.ShellExecute "cmd.exe", "/c %~s0 %params%", "", "runas", 1 >> "%temp%\getadmin.vbs"

    "%temp%\getadmin.vbs"
    del "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
    pushd "%CD%"
    CD /D "%~dp0"
:--------------------------------------

echo STAGE 1: Remove Bloatware
choice /C YN /N /M "Remove Bloatware? [Y/N]"

rem errorlevel is 1 for Y, 2 for N
if errorlevel 2 goto skipbloatwareremove
goto removebloatwarescript

:removebloatwarescript

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Detect-HPBloatware.ps1" -Verb RunAs
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Remove-HPBloatwareNew.ps1" -Verb RunAs
pause

:skipbloatwareremove

echo STAGE 2: Set And Activate Local Admin
choice /C YN /N /M "Activate and Set Local Admin Password? [Y/N]"

rem errorlevel is 1 for Y, 2 for N
if errorlevel 2 goto skiplocaladmin
goto setuplocaladmin

:setuplocaladmin

set /p LocalAdministratorPassword=Enter Desired Local Admin Password 
net user Administrator /active:yes "%LocalAdministratorPassword%"
echo Local Administrator activated with password: %LocalAdministratorPassword%
pause

:skiplocaladmin

echo STAGE 3: Install Applications
choice /C YN /N /M "Install Applications? [Y/N]"
rem   Y=1   N=2
if errorlevel 2 goto appinstallno
goto appinstallyes

:appinstallyes

color 0a
echo.
echo Choose Application Option Below:
echo   1. Install Google Chrome
echo   2. Install Adobe PDF
echo   3. Install Microsoft JDK
echo   4. Install ALL OF THE ABOVE
echo   5. Done
echo.

rem only allow keys 1–5
choice /C 12345 /N /M "Enter selection [1-5]:"

rem errorlevel is 1 for “1”, 2 for “2”, … 5 for “5”
if errorlevel 5 goto appinstallno
if errorlevel 4 goto fullappinstall
if errorlevel 3 goto javaInstall
if errorlevel 2 goto adobeInstall
if errorlevel 1 goto chromeInstall

rem (just in case—should never happen)
goto appinstallyes

:adobeInstall

set "readerStub=%~dp0AcroRdrDCsetup.exe"

rem Only download if the stub isn’t already present
if not exist "%readerStub%" (
    echo Downloading Adobe Acrobat Reader stub installer…
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-BitsTransfer -Source 'https://ardownload2.adobe.com/pub/adobe/reader/win/AcrobatDC/2500120531/AcroRdrDC2500120531_en_US.exe' -Destination '%readerStub%'"
) else (
    echo Found existing AcroRdrDCsetup.exe, skipping download.
)

rem give BITS a moment to finalize the file
TIMEOUT /T 1 >nul

echo Installing Adobe Acrobat Reader...
"%readerStub%" /sAll /rs

goto appinstallyes

:javaInstall

echo Installing Java JDK…

rem 1) only download if we don’t already have winJava.msi
if not exist "%~dp0winJava.msi" (
    echo Downloading Microsoft Java JDK…
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "Start-BitsTransfer -Source 'https://aka.ms/download-jdk/microsoft-jdk-21.0.3-windows-x64.msi' -Destination '%~dp0winJava.msi'"
) else (
    echo Found existing winJava.msi, skipping download.
)

rem 2) give a tiny pause so BITS flushes to disk
TIMEOUT /T 1 >nul

rem 3) install (quiet, no restart)
msiexec /i "%~dp0winJava.msi" /qn /norestart ADDLOCAL=ALL

echo Java Installation Complete!
goto appinstallyes

:chromeInstall

rem Install Chrome
rem 1) Only download if the MSI isn’t already present
if not exist "%~dp0GoogleChromeStandalone.msi" (
    echo Downloading Chrome offline MSI…
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "Start-BitsTransfer -Source 'https://dl.google.com/chrome/install/GoogleChromeStandaloneEnterprise64.msi' -Destination '%~dp0GoogleChromeStandalone.msi'"
) else (
    echo Found existing GoogleChromeStandalone.msi, skipping download.
)

rem 2) Tiny pause to ensure BITS has flushed the file to disk
TIMEOUT /T 1 >nul

rem 3) Install (quiet, no restart)
echo Installing Chrome…
msiexec /i "%~dp0GoogleChromeStandalone.msi" /qn /norestart
echo Chrome Install Complete!

goto appinstallyes

:fullappinstall

rem Install Chrome
rem 1) Only download if the MSI isn’t already present
if not exist "%~dp0GoogleChromeStandalone.msi" (
    echo Downloading Chrome offline MSI…
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "Start-BitsTransfer -Source 'https://dl.google.com/chrome/install/GoogleChromeStandaloneEnterprise64.msi' -Destination '%~dp0GoogleChromeStandalone.msi'"
) else (
    echo Found existing GoogleChromeStandalone.msi, skipping download.
)

rem 2) Tiny pause to ensure BITS has flushed the file to disk
TIMEOUT /T 1 >nul

rem 3) Install (quiet, no restart)
echo Installing Chrome…
msiexec /i "%~dp0GoogleChromeStandalone.msi" /qn /norestart
echo Chrome Install Complete!

rem install Adobe Reader PDF
set "readerStub=%~dp0AcroRdrDCsetup.exe"

rem Only download if the stub isn’t already present
if not exist "%readerStub%" (
    echo Downloading Adobe Acrobat Reader stub installer…
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-BitsTransfer -Source 'https://ardownload2.adobe.com/pub/adobe/reader/win/AcrobatDC/2500120531/AcroRdrDC2500120531_en_US.exe' -Destination '%readerStub%'"
) else (
    echo Found existing AcroRdrDCsetup.exe, skipping download.
)

rem give BITS a moment to finalize the file
TIMEOUT /T 1 >nul

echo Installing Adobe Acrobat Reader…
"%readerStub%" /sAll /rs
echo Adobe Install Complete!

rem Install Microsoft Java JDK
echo Installing Java JDK…

rem 1) only download if we don’t already have winJava.msi
if not exist "%~dp0winJava.msi" (
    echo Downloading Microsoft Java JDK…
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "Start-BitsTransfer -Source 'https://aka.ms/download-jdk/microsoft-jdk-21.0.3-windows-x64.msi' -Destination '%~dp0winJava.msi'"
) else (
    echo Found existing winJava.msi, skipping download.
)

rem 2) give a tiny pause so BITS flushes to disk
TIMEOUT /T 1 >nul

rem 3) install (quiet, no restart)
msiexec /i "%~dp0winJava.msi" /qn /norestart ADDLOCAL=ALL

echo Java Installation Complete!

:appinstallno

echo STAGE4: Rename or Domain Join Device
choice /C YN /N /M "Would you like to Rename Device / Join Domain? [Y/N]"
rem %errorlevel% is 1 for the first choice (Y), 2 for the second (N)
if errorlevel 2 goto updatePrompt
rem -- errorlevel is 1 here, so it was “Y” --
sysdm.cpl

:updatePrompt

echo STAGE 5: Begin Windows Update Process
choice /C YN /N /M "Begin Windows Update process? [Y/N]"

rem errorlevel is 1 for Y, 2 for N
if errorlevel 2 goto updateno
goto updateyes

:updateyes

echo Checking for PSWindowsUpdate module…
powershell -NoProfile -ExecutionPolicy Bypass -Command "if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) { Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers } ; Import-Module PSWindowsUpdate ; Write-Host 'Starting Windows Update...' ; Get-WindowsUpdate -AcceptAll -Install -AutoReboot ; Write-Host '' ; Write-Host 'Windows Update process has started. Updates will continue in the background.'"
pause

:updateno

echo Thanks For Using NEOS Device Preparation!
echo Don't Forget To Remove This User Account If Needed!
pause
