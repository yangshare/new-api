@echo off
setlocal enabledelayedexpansion

echo ====================================
echo new-api - Release Script
echo ====================================
echo.

set /p version="Please enter version number (e.g., 1.0.0): "

if "%version%"=="" (
    echo Error: Version number cannot be empty
    pause
    exit /b 1
)

echo.
echo Preparing to release version: v%version%
echo.

git tag v%version%
if errorlevel 1 (
    echo Error: Failed to create Git Tag
    pause
    exit /b 1
)

echo Git Tag v%version% created successfully
echo.

git push origin v%version%
if errorlevel 1 (
    echo Error: Failed to push Tag to remote repository
    pause
    exit /b 1
)

echo.
echo ====================================
echo Release successful! Version v%version% has been pushed to remote repository
echo GitHub Actions will automatically build and publish to Releases
echo ====================================
pause
