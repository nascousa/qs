@echo off
setlocal

set "PAYLOAD_SCRIPT=%~dp0QuickSearch.Payload.ps1"
for %%I in ("%~dp0..\..") do set "REPO_ROOT=%%~fI"
set "CONFIG_PATH=%REPO_ROOT%\src\settings\config.json"
set "RELEASE_DIR=%REPO_ROOT%\release"
set "TMP_DIR=%REPO_ROOT%\tmp"

if not exist "%PAYLOAD_SCRIPT%" (
	echo QuickSearch.Payload.ps1 was not found next to this launcher.
	echo Expected: "%PAYLOAD_SCRIPT%"
	goto failed
)

where pwsh.exe >nul 2>nul
if errorlevel 1 (
	echo PowerShell 7+ was not found. Install PowerShell 7 and make sure pwsh.exe is on PATH.
	goto failed
)

set "PROJECT_VERSION="
if not exist "%CONFIG_PATH%" (
	echo QuickSearch settings config was not found.
	echo Expected: "%CONFIG_PATH%"
	goto failed
)

set "QS_CONFIG_PATH=%CONFIG_PATH%"
for /f "usebackq delims=" %%A in (`pwsh.exe -NoProfile -NoLogo -Command "$config = Get-Content -LiteralPath $env:QS_CONFIG_PATH -Raw | ConvertFrom-Json; if ($null -ne $config.Version) { [Console]::Out.Write([string]$config.Version) }"`) do (
	set "PROJECT_VERSION=%%~A"
	goto version_found
)

:version_found
if "%PROJECT_VERSION%"=="" (
	echo Version was not found in "%CONFIG_PATH%".
	goto failed
)
set "PROJECT_VERSION=%PROJECT_VERSION:"=%"

if "%QS_PAYLOAD_INPUT_PATH%"=="" (
	set "INPUT_PATH=%RELEASE_DIR%\%PROJECT_VERSION%-payload.txt"
) else (
	set "INPUT_PATH=%QS_PAYLOAD_INPUT_PATH%"
)

if "%QS_PAYLOAD_DECODE_OUTPUT_PATH%"=="" (
	if not exist "%TMP_DIR%" mkdir "%TMP_DIR%"
	set "OUTPUT_PATH=%TMP_DIR%\quicksearch-%PROJECT_VERSION%.decoded.ps1"
) else (
	set "OUTPUT_PATH=%QS_PAYLOAD_DECODE_OUTPUT_PATH%"
)

if not exist "%INPUT_PATH%" (
	echo Payload input file was not found.
	echo Expected: "%INPUT_PATH%"
	goto failed
)

for %%I in ("%OUTPUT_PATH%") do set "OUTPUT_DIR=%%~dpI"
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

echo Decoding QuickSearch Brotli Base64 payload...
echo Input: "%INPUT_PATH%"
echo Output: "%OUTPUT_PATH%"
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%PAYLOAD_SCRIPT%" -Decode -Path "%INPUT_PATH%" -OutputPath "%OUTPUT_PATH%"
if errorlevel 1 goto failed

for %%I in ("%OUTPUT_PATH%") do set "DECODED_CHARACTERS=%%~zI"
echo.
echo Payload decoded successfully.
echo File: "%OUTPUT_PATH%"
echo Characters: %DECODED_CHARACTERS%
goto done

:failed
echo.
echo Payload decode failed.
if /i not "%QS_PAYLOAD_BATCH_NO_PAUSE%"=="1" pause
exit /b 1

:done
if /i not "%QS_PAYLOAD_BATCH_NO_PAUSE%"=="1" pause
exit /b 0