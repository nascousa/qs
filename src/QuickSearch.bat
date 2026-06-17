@echo off
setlocal
set "QUICKSEARCH_LAUNCHER=%~dp0QuickSearch.vbs"
set "QUICKSEARCH_SCRIPT=%~dp0QuickSearch.ps1"

if not exist "%QUICKSEARCH_LAUNCHER%" (
	echo QuickSearch.vbs was not found next to this launcher.
	echo Expected: "%QUICKSEARCH_LAUNCHER%"
	pause
	exit /b 1
)

if not exist "%QUICKSEARCH_SCRIPT%" (
	echo QuickSearch.ps1 was not found next to this launcher.
	echo Expected: "%QUICKSEARCH_SCRIPT%"
	pause
	exit /b 1
)

start "" wscript.exe "%QUICKSEARCH_LAUNCHER%"
endlocal
exit /b 0