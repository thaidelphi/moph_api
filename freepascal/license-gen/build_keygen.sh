#!/bin/bash

echo "==========================================="
echo " Building fpsso License Key Generator"
echo "==========================================="

echo "[1/2] Compiling source code..."
fpc -O3 -XX -Xs -Fu"../fpsso/src" keygen.lpr

if [ $? -ne 0 ]; then
    echo "Error: Compilation failed!"
    exit 1
fi

echo "[2/2] Done! You can now run ./keygen"
