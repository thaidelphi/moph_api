@echo off
echo ===========================================
echo  Building fpsso License Key Generator (Windows)
echo ===========================================

echo [1/2] Compiling source code...
fpc -O3 -XX -Xs -Fu"..\fpsso\src" keygen.lpr

if %ERRORLEVEL% NEQ 0 (
    echo Error: Compilation failed!
    exit /b 1
)

echo [2/2] Done! You can now run keygen.exe
pause
