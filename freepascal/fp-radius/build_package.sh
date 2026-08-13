#!/bin/bash

echo "==========================================="
echo " Building fpradius Release Package"
echo "==========================================="

# 1. Compile in Release Mode (Optimize for speed, strip debug symbols)
echo "[1/4] Compiling source code (Release mode)..."
fpc -O3 -XX -Xs -Fu"src" fpradius.lpr

if [ $? -ne 0 ]; then
    echo "Error: Compilation failed!"
    exit 1
fi

# 2. Create staging directory
echo "[2/4] Preparing deployment folder..."
DEPLOY_DIR="fpradius_release"
rm -rf $DEPLOY_DIR
mkdir -p $DEPLOY_DIR

# 3. Copy necessary files (EXCLUDING SOURCE CODE)
echo "[3/4] Copying files..."
cp fpradius $DEPLOY_DIR/              # The compiled binary
cp .env.example $DEPLOY_DIR/          # Example config
cp fpradius.service $DEPLOY_DIR/      # Systemd service file
cp README.md $DEPLOY_DIR/ 2>/dev/null # Documentation (if exists)

# 4. Compress to tar.gz
echo "[4/4] Creating archive..."
tar -czvf fpradius_package.tar.gz $DEPLOY_DIR/

# Cleanup staging folder
rm -rf $DEPLOY_DIR

echo "==========================================="
echo " DONE! Release package created: fpradius_package.tar.gz"
echo "==========================================="
