#!/bin/bash

echo "==========================================="
echo " Building fpsso Release Package"
echo "==========================================="

# 1. Compile in Release Mode (Optimize for speed, strip debug symbols)
echo "[1/4] Compiling source code (Release mode)..."
fpc -O3 -XX -Xs -Fu"src" fpsso.lpr

if [ $? -ne 0 ]; then
    echo "Error: Compilation failed!"
    exit 1
fi

# 1.5 Pack the executable with UPX to prevent decompilation
echo "[1.5/4] Packing executable with UPX..."
if command -v upx &> /dev/null; then
    upx --best --lzma fpsso
else
    echo "Warning: UPX not found. Skipping binary packing. To enable anti-decompilation, install UPX (sudo apt install upx-ucl)."
fi

# 2. Create staging directory
echo "[2/4] Preparing deployment folder..."
DEPLOY_DIR="fpsso_release"
rm -rf $DEPLOY_DIR
mkdir -p $DEPLOY_DIR

# 3. Copy necessary files (EXCLUDING SOURCE CODE)
echo "[3/4] Copying files..."
cp fpsso $DEPLOY_DIR/                 # The compiled binary
cp -r templates $DEPLOY_DIR/          # HTML templates and images
cp .env $DEPLOY_DIR/.env.example      # Example config (Rename actual .env to .env.example to strip secrets later if needed, or just copy as template)
cp fpsso.service $DEPLOY_DIR/         # Systemd service file
cp LOGIN_FLOW.md $DEPLOY_DIR/         # Documentation

# 4. Compress to tar.gz
echo "[4/4] Creating archive..."
tar -czvf fpsso_package.tar.gz $DEPLOY_DIR/

# Cleanup staging folder
rm -rf $DEPLOY_DIR

echo "==========================================="
echo " DONE! Release package created: fpsso_package.tar.gz"
echo "==========================================="
