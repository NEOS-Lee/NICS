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
set /p removebloatware=Remove Bloatware? Y/N 
if %removebloatware% ==y goto removebloatwarescript
if %removebloatware% ==n goto skipbloatwareremove

:removebloatwarescript

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Detect-HPBloatware.ps1" -Verb RunAs
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Remove-HPBloatwareNew.ps1" -Verb RunAs

pause
:skipbloatwareremove

echo STAGE 2: Set And Activate Local Admin
set /p localadminchoice= Activate and Set Local Admin Password? Y/N 
if %localadminchoice% ==y goto setuplocaladmin
if %localadminchoice% ==n goto skiplocaladmin

:setuplocaladmin

set /p LocalAdministratorPassword=Enter Desired Local Admin Password 
net user Administrator /active:yes "%LocalAdministratorPassword%"
echo Local Administrator Activated with password: %LocalAdministratorPassword%


pause
:skiplocaladmin

echo STAGE 3: Install Applications
set /p InstallApplications=Install Applications? Y/N 
if %InstallApplications% ==y goto appinstallyes
if %InstallApplications% ==Y goto appinstallyes
if %InstallApplications% ==N goto appinstallno
if %InstallApplications% ==n goto appinstallno

:appinstallyes

color 0a
echo.
echo Choose Application Option Below
echo 1. Install Google Chrome
echo 2. Install Adobe PDF
echo 3. Install Java JRE
echo 4. Install ALL OF THE ABOVE
echo 5. Done
echo.
set /p a=
IF %a%==1 "%~dp0ChromeSetup.exe"
IF %a%==2 "%~dp0readerdc64_en_xa_mdr_install.exe"
IF %a%==3 "%~dp0JavaSetup8u371.exe"
IF %a%==4 goto fullappinstall
IF %a%==5 goto appinstallno
goto appinstallyes

:fullappinstall

"%~dp0ChromeSetup.exe"
"%~dp0readerdc64_en_xa_mdr_install.exe"
"%~dp0JavaSetup8u371.exe"
goto appinstallyes

:appinstallno

echo STAGE4: Rename or Domain Join Device
set /p renameyes=Would You Like To Rename Device / Join To Domain? Y/N 
if %renameyes% ==y sysdm.cpl else 
pause
echo Thanks For Using NEOS Device Preparation!
echo Don't Forget To Remove This User Account If Needed!
pause
