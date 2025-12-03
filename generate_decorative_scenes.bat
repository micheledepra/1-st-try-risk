@echo off
REM Batch script to run the decorative scene generator
REM This will create PantherDecorative.tscn and t34Decorative.tscn

echo ========================================
echo Decorative Scene Generator
echo ========================================
echo.

REM Find Godot executable (common installation paths)
set "GODOT_PATH="

if exist "C:\Program Files\Godot\Godot.exe" (
    set "GODOT_PATH=C:\Program Files\Godot\Godot.exe"
    goto :found
)
if exist "C:\Program Files (x86)\Godot\Godot.exe" (
    set "GODOT_PATH=C:\Program Files (x86)\Godot\Godot.exe"
    goto :found
)
if exist "C:\Godot\Godot.exe" (
    set "GODOT_PATH=C:\Godot\Godot.exe"
    goto :found
)
if exist "%LOCALAPPDATA%\Godot\Godot.exe" (
    set "GODOT_PATH=%LOCALAPPDATA%\Godot\Godot.exe"
    goto :found
)

REM Try to find in Downloads folder
for /f "delims=" %%i in ('dir /b /s "%USERPROFILE%\Downloads\Godot*.exe" 2^>nul') do (
    echo %%i | findstr /v "console" >nul
    if not errorlevel 1 (
        set "GODOT_PATH=%%i"
        goto :found
    )
)

:found
if not defined GODOT_PATH (
    echo ERROR: Godot executable not found in common locations!
    echo.
    echo Please enter the full path to your Godot executable:
    echo Example: C:\Path\To\Godot_v4.3_win64.exe
    echo.
    set /p GODOT_PATH="Godot path: "
)

if not exist "%GODOT_PATH%" (
    echo ERROR: Godot executable not found at: %GODOT_PATH%
    echo.
    pause
    exit /b 1
)

echo Using Godot: %GODOT_PATH%
echo.

REM Run the generator script
"%GODOT_PATH%" --headless --script create_decorative_scenes.gd

echo.
if %ERRORLEVEL% EQU 0 (
    echo ========================================
    echo SUCCESS! Decorative scenes created.
    echo ========================================
    echo.
    echo Files created:
    echo   - Scenes/Units/Import/Panther/PantherDecorative.tscn
    echo   - Scenes/Units/Import/t34/t34Decorative.tscn
    echo.
    echo Next steps:
    echo   1. Open Godot editor
    echo   2. Verify scenes in FileSystem
    echo   3. Run game - should have ZERO deprecation warnings
    echo.
) else (
    echo ========================================
    echo FAILED! See errors above.
    echo ========================================
    echo.
)

pause
