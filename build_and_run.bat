@echo off
:dev_loop
cls
echo =========================================================
echo Copyright (C) 2026 Daniel Halen
echo This program is free software: you can redistribute it and/or modify
echo it under the terms of the GNU General Public License as published by
echo the Free Software Foundation, either version 3 of the License, or
echo (at your option) any later version.
echo =========================================================
echo       FRAQSHIFT OS AUTOMATED BUILD SYSTEM V6.0
echo =========================================================

echo.
echo [1/3] Running Python compiler (builder2.py)...
python builder2.py
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Python compilation failed!
    goto menu
)

echo.
echo [2/3] Assembling kernel.asm via local NASM...
nasm.exe -f bin kernel.asm -o fraqshift_kernel.bin
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] NASM assembly failed!
    goto menu
)

echo.
echo [3/3] Launching Fraqshift OS inside QEMU Bare-Metal Sandbox...
echo ---------------------------------------------------------
"C:\Program Files\qemu\qemu-system-x86_64.exe" -drive format=raw,file=fraqshift_kernel.bin

:menu
echo.
echo =========================================================
echo  [R] Run Script Again (Recompile and Restart)
echo  [X] Exit and Close Terminal
echo =========================================================
echo.

set /p user_choice="Enter your choice (R/X): "

if /i "%user_choice%"=="R" goto dev_loop
if /i "%user_choice%"=="X" exit
goto menu
