@echo off
echo ====================================
echo Inventory Pro Version Control
echo ====================================

:: Get current version from pubspec.yaml
for /f "tokens=2 delims=: " %%a in ('findstr "version:" pubspec.yaml') do set CURRENT_VERSION=%%a
echo Current version: %CURRENT_VERSION%

:: Ask for new version
set /p NEW_VERSION="Enter new version (or press Enter to skip): "

if not "%NEW_VERSION%"=="" (
    :: Update version in pubspec.yaml
    powershell -Command "(gc pubspec.yaml) -replace 'version: %CURRENT_VERSION%', 'version: %NEW_VERSION%' | Out-File -encoding ASCII pubspec.yaml"
    echo Version updated to %NEW_VERSION%
)

:: Git operations
echo.
echo Checking git status...
git status

echo.
set /p COMMIT_MSG="Enter commit message: "

if "%COMMIT_MSG%"=="" (
    echo Error: Commit message cannot be empty
    exit /b 1
)

:: Add all changes
git add .

:: Commit changes
git commit -m "%COMMIT_MSG%"

:: Push to remote
echo.
echo Pushing to remote...
git push origin main

echo.
echo ====================================
echo Changes committed and pushed!
echo ====================================
pause