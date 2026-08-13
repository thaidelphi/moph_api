#!/bin/bash

# =============================================================================
# สคริปต์ติดตั้งระบบ fpsso และ fp-radius อัตโนมัติ
# Script สำหรับช่วยติดตั้งระบบทีละขั้นตอนบน Ubuntu 20.04 / 22.04 LTS
# =============================================================================

# --- สีสำหรับแสดงผลใน Terminal ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- ตัวแปร Default ---
INSTALL_DIR="/var/www/api/freepascal"
REPO_URL="https://github.com/thaidelphi/internet-authen.git"
DB_NAME="radius"
DB_USER="radius_user"
DB_PASS=""
SKIP_DB_INSTALL=0
SKIP_FPC_INSTALL=0
SKIP_COMPILE=0

# =============================================================================
# ฟังก์ชันแสดงผลข้อความ
# =============================================================================
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }

print_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║        ระบบติดตั้ง fpsso + fp-radius อัตโนมัติ       ║"
    echo "║             Installation Script v1.0                 ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# =============================================================================
# ตรวจสอบ Root Privilege
# =============================================================================
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "สคริปต์นี้ต้องรันด้วยสิทธิ์ root (sudo ./setup.sh)"
        exit 1
    fi
}

# =============================================================================
# ขั้นตอนที่ 1: ติดตั้ง Dependencies
# =============================================================================
step1_install_dependencies() {
    echo ""
    echo -e "${YELLOW}════ ขั้นตอนที่ 1: ติดตั้งโปรแกรมที่จำเป็น ════${NC}"

    info "กำลังอัปเดต package list..."
    apt-get update -q
    if [ $? -ne 0 ]; then
        error "ไม่สามารถอัปเดต package list ได้"
        exit 1
    fi

    info "กำลังติดตั้ง build tools และ dependencies..."
    apt-get install -y -q build-essential libmariadb-dev libssl-dev git curl wget upx-ucl
    if [ $? -ne 0 ]; then
        error "ไม่สามารถติดตั้ง dependencies ได้"
        exit 1
    fi
    success "ติดตั้ง dependencies สำเร็จ"

    # ตรวจสอบและติดตั้ง FPC
    if [ "$SKIP_FPC_INSTALL" -eq 0 ]; then
        if command -v fpc &> /dev/null; then
            FPC_VER=$(fpc -iV 2>/dev/null)
            success "พบ Free Pascal Compiler เวอร์ชัน: $FPC_VER (ข้ามการติดตั้ง)"
        else
            info "กำลังติดตั้ง Free Pascal Compiler (FPC)..."
            apt-get install -y -q fpc
            if [ $? -ne 0 ]; then
                error "ไม่สามารถติดตั้ง FPC ได้"
                exit 1
            fi
            success "ติดตั้ง FPC สำเร็จ ($(fpc -iV))"
        fi
    fi
}

# =============================================================================
# ขั้นตอนที่ 2: ติดตั้งและตั้งค่า MariaDB
# =============================================================================
step2_setup_database() {
    echo ""
    echo -e "${YELLOW}════ ขั้นตอนที่ 2: ตั้งค่าฐานข้อมูล MariaDB ════${NC}"

    if [ "$SKIP_DB_INSTALL" -eq 1 ]; then
        warn "ข้ามการติดตั้ง MariaDB (--skip-db ถูกระบุ)"
        return
    fi

    # ตรวจสอบว่า MariaDB ติดตั้งอยู่แล้วหรือไม่
    if ! command -v mysqld &> /dev/null && ! command -v mariadbd &> /dev/null; then
        info "กำลังติดตั้ง MariaDB Server..."
        apt-get install -y -q mariadb-server
        if [ $? -ne 0 ]; then
            error "ไม่สามารถติดตั้ง MariaDB ได้"
            exit 1
        fi
        systemctl start mariadb
        systemctl enable mariadb
        success "ติดตั้งและเปิดใช้งาน MariaDB สำเร็จ"
    else
        success "พบ MariaDB/MySQL ติดตั้งอยู่แล้ว (ข้ามการติดตั้ง)"
    fi

    # รับรหัสผ่านฐานข้อมูล
    if [ -z "$DB_PASS" ]; then
        echo ""
        echo -e "${CYAN}กรุณากำหนดรหัสผ่านสำหรับ Database User '${DB_USER}':${NC}"
        read -s -p "รหัสผ่าน: " DB_PASS
        echo ""
        read -s -p "ยืนยันรหัสผ่าน: " DB_PASS_CONFIRM
        echo ""
        if [ "$DB_PASS" != "$DB_PASS_CONFIRM" ]; then
            error "รหัสผ่านไม่ตรงกัน กรุณาลองใหม่อีกครั้ง"
            exit 1
        fi
    fi

    # สร้าง Database และ User
    info "กำลังสร้างฐานข้อมูลและผู้ใช้..."
    mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
    if [ $? -ne 0 ]; then
        error "ไม่สามารถสร้างฐานข้อมูลได้ กรุณาตรวจสอบสิทธิ์ root ของ MariaDB"
        exit 1
    fi
    success "สร้างฐานข้อมูล '${DB_NAME}' และผู้ใช้ '${DB_USER}' สำเร็จ"
}

# =============================================================================
# ขั้นตอนที่ 3: ดึง Package ติดตั้งจาก Repository
# =============================================================================
step3_clone_package() {
    echo ""
    echo -e "${YELLOW}════ ขั้นตอนที่ 3: ดึงไฟล์ติดตั้งจาก Repository ════${NC}"

    PACKAGE_DIR="/tmp/internet-authen"

    if [ -d "$PACKAGE_DIR" ]; then
        info "พบโฟลเดอร์เก่า กำลังลบและดึงใหม่..."
        rm -rf "$PACKAGE_DIR"
    fi

    info "กำลังดึงไฟล์จาก $REPO_URL ..."
    git clone "$REPO_URL" "$PACKAGE_DIR"
    if [ $? -ne 0 ]; then
        error "ไม่สามารถดึงไฟล์จาก Repository ได้ กรุณาตรวจสอบการเชื่อมต่อ Internet"
        exit 1
    fi
    success "ดึงไฟล์สำเร็จ"

    # คัดลอกไฟล์ไปยัง /var/www/api/freepascal
    mkdir -p "$INSTALL_DIR"
    info "กำลังคัดลอกไฟล์ไปยัง $INSTALL_DIR ..."

    if [ -d "$PACKAGE_DIR/fp-radius" ]; then
        cp -r "$PACKAGE_DIR/fp-radius" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/fp-radius/fpradius"
        success "คัดลอก fp-radius สำเร็จ"
    fi

    if [ -d "$PACKAGE_DIR/fpsso" ]; then
        cp -r "$PACKAGE_DIR/fpsso" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/fpsso/fpsso"
        success "คัดลอก fpsso สำเร็จ"
    fi

    if [ -f "$PACKAGE_DIR/INSTALL.md" ]; then
        cp "$PACKAGE_DIR/INSTALL.md" "$INSTALL_DIR/"
    fi

    rm -rf "$PACKAGE_DIR"
}

# =============================================================================
# ขั้นตอนที่ 4: ตั้งค่า .env Files
# =============================================================================
step4_configure_env() {
    echo ""
    echo -e "${YELLOW}════ ขั้นตอนที่ 4: ตั้งค่า Environment Variables ════${NC}"

    # --- ตั้งค่า fp-radius ---
    FP_RADIUS_DIR="$INSTALL_DIR/fp-radius"
    if [ -d "$FP_RADIUS_DIR" ] && [ ! -f "$FP_RADIUS_DIR/.env" ]; then
        if [ -f "$FP_RADIUS_DIR/.env.example" ]; then
            cp "$FP_RADIUS_DIR/.env.example" "$FP_RADIUS_DIR/.env"
            info "สร้างไฟล์ .env สำหรับ fp-radius จาก .env.example"
        fi
    fi

    if [ -f "$FP_RADIUS_DIR/.env" ] && [ -n "$DB_PASS" ]; then
        # แทนที่ค่า Database ใน .env โดยอัตโนมัติ
        sed -i "s/^DB_HOST=.*/DB_HOST=localhost/" "$FP_RADIUS_DIR/.env"
        sed -i "s/^DB_NAME=.*/DB_NAME=${DB_NAME}/" "$FP_RADIUS_DIR/.env"
        sed -i "s/^DB_USER=.*/DB_USER=${DB_USER}/" "$FP_RADIUS_DIR/.env"
        sed -i "s/^DB_PASS=.*/DB_PASS=${DB_PASS}/" "$FP_RADIUS_DIR/.env"
        success "อัปเดต fp-radius .env เรียบร้อย"
    else
        warn "กรุณาแก้ไขไฟล์ $FP_RADIUS_DIR/.env ด้วยตัวเอง"
    fi

    # --- ตั้งค่า fpsso ---
    FPSSO_DIR="$INSTALL_DIR/fpsso"
    if [ -d "$FPSSO_DIR" ] && [ ! -f "$FPSSO_DIR/.env" ]; then
        if [ -f "$FPSSO_DIR/.env.example" ]; then
            cp "$FPSSO_DIR/.env.example" "$FPSSO_DIR/.env"
            info "สร้างไฟล์ .env สำหรับ fpsso จาก .env.example"
        fi
    fi

    if [ -f "$FPSSO_DIR/.env" ] && [ -n "$DB_PASS" ]; then
        sed -i "s/^DB_HOST=.*/DB_HOST=localhost/" "$FPSSO_DIR/.env"
        sed -i "s/^DB_NAME=.*/DB_NAME=${DB_NAME}/" "$FPSSO_DIR/.env"
        sed -i "s/^DB_USER=.*/DB_USER=${DB_USER}/" "$FPSSO_DIR/.env"
        sed -i "s/^DB_PASS=.*/DB_PASS=${DB_PASS}/" "$FPSSO_DIR/.env"
        success "อัปเดต fpsso .env เรียบร้อย"
    else
        warn "กรุณาแก้ไขไฟล์ $FPSSO_DIR/.env ด้วยตัวเอง"
    fi
}

# =============================================================================
# ขั้นตอนที่ 5: ติดตั้ง Systemd Services
# =============================================================================
step5_install_services() {
    echo ""
    echo -e "${YELLOW}════ ขั้นตอนที่ 5: ติดตั้ง Systemd Service ════${NC}"

    # --- fp-radius Service ---
    if [ -f "$INSTALL_DIR/fp-radius/fpradius.service" ]; then
        cp "$INSTALL_DIR/fp-radius/fpradius.service" /etc/systemd/system/
        success "คัดลอก fpradius.service ไปยัง systemd"
    elif [ -f "$INSTALL_DIR/fp-radius/fpradius" ]; then
        # สร้าง service file อัตโนมัติถ้าไม่มี
        cat > /etc/systemd/system/fpradius.service <<EOF
[Unit]
Description=fp-radius RADIUS Proxy Service
After=network.target mariadb.service

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}/fp-radius
ExecStart=${INSTALL_DIR}/fp-radius/fpradius
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        success "สร้าง fpradius.service สำเร็จ"
    fi

    # --- fpsso Service ---
    if [ -f "$INSTALL_DIR/fpsso/fpsso.service" ]; then
        cp "$INSTALL_DIR/fpsso/fpsso.service" /etc/systemd/system/
        success "คัดลอก fpsso.service ไปยัง systemd"
    elif [ -f "$INSTALL_DIR/fpsso/fpsso" ]; then
        cat > /etc/systemd/system/fpsso.service <<EOF
[Unit]
Description=fpsso SSO Service
After=network.target mariadb.service fpradius.service

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}/fpsso
ExecStart=${INSTALL_DIR}/fpsso/fpsso
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        success "สร้าง fpsso.service สำเร็จ"
    fi

    info "กำลัง Reload systemd daemon..."
    systemctl daemon-reload

    info "กำลังเปิดใช้งาน Services..."
    systemctl enable fpradius 2>/dev/null && success "เปิดใช้งาน fpradius service สำเร็จ" || warn "ไม่พบ fpradius service"
    systemctl enable fpsso    2>/dev/null && success "เปิดใช้งาน fpsso service สำเร็จ"    || warn "ไม่พบ fpsso service"

    info "กำลังเริ่ม Services..."
    systemctl start fpradius 2>/dev/null && success "เริ่ม fpradius สำเร็จ" || warn "ไม่สามารถเริ่ม fpradius ได้ (กรุณาตรวจสอบ .env)"
    systemctl start fpsso    2>/dev/null && success "เริ่ม fpsso สำเร็จ"    || warn "ไม่สามารถเริ่ม fpsso ได้ (กรุณาตรวจสอบ .env)"
}

# =============================================================================
# สรุปผลการติดตั้ง
# =============================================================================
print_summary() {
    echo ""
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║              ✅ การติดตั้งเสร็จสิ้น!                 ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    SERVER_IP=$(hostname -I | awk '{print $1}')
    echo -e "  ${CYAN}ตรวจสอบสถานะ Service:${NC}"
    echo "    sudo systemctl status fpsso"
    echo "    sudo systemctl status fpradius"
    echo ""
    echo -e "  ${CYAN}ดู Log:${NC}"
    echo "    sudo journalctl -u fpsso -f"
    echo "    sudo journalctl -u fpradius -f"
    echo ""
    echo -e "  ${CYAN}ทดสอบระบบ:${NC}"
    echo "    http://${SERVER_IP}:8080/sso/"
    echo ""
    echo -e "  ${CYAN}ไฟล์ .env อยู่ที่:${NC}"
    echo "    $INSTALL_DIR/fpsso/.env     (สำหรับ SSO)"
    echo "    $INSTALL_DIR/fp-radius/.env (สำหรับ RADIUS)"
    echo ""
    warn "⚠️  อย่าลืมแก้ไขค่า API Keys ใน $INSTALL_DIR/fpsso/.env (THAID, PROVIDERID, GOOGLE)"
}

# =============================================================================
# ฟังก์ชัน Help
# =============================================================================
print_help() {
    echo "การใช้งาน: sudo ./setup.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --skip-db       ข้ามการติดตั้ง MariaDB (ใช้ external DB)"
    echo "  --skip-fpc      ข้ามการติดตั้ง FPC (มีแล้วในระบบ)"
    echo "  --db-pass=PASS  กำหนดรหัสผ่าน Database โดยตรง (ไม่ต้อง Interactive)"
    echo "  --db-user=USER  กำหนดชื่อ Database User (ค่าเริ่มต้น: radius_user)"
    echo "  --db-name=NAME  กำหนดชื่อ Database (ค่าเริ่มต้น: radius)"
    echo "  --help          แสดง Help นี้"
    echo ""
    echo "ตัวอย่าง:"
    echo "  sudo ./setup.sh"
    echo "  sudo ./setup.sh --skip-db --db-pass=MySecretPassword"
}

# =============================================================================
# รับ Arguments จาก Command Line
# =============================================================================
for arg in "$@"; do
    case $arg in
        --skip-db)        SKIP_DB_INSTALL=1 ;;
        --skip-fpc)       SKIP_FPC_INSTALL=1 ;;
        --db-pass=*)      DB_PASS="${arg#*=}" ;;
        --db-user=*)      DB_USER="${arg#*=}" ;;
        --db-name=*)      DB_NAME="${arg#*=}" ;;
        --help|-h)        print_help; exit 0 ;;
        *)                warn "ไม่รู้จัก argument: $arg" ;;
    esac
done

# =============================================================================
# เริ่มต้นการทำงาน
# =============================================================================
print_banner
check_root

echo -e "${CYAN}การตั้งค่าที่จะใช้:${NC}"
echo "  Install Dir : $INSTALL_DIR"
echo "  DB Name     : $DB_NAME"
echo "  DB User     : $DB_USER"
echo "  Skip MariaDB: $( [ $SKIP_DB_INSTALL -eq 1 ] && echo 'ใช่' || echo 'ไม่' )"
echo ""
read -p "ต้องการดำเนินการต่อหรือไม่? (y/n): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "ยกเลิกการติดตั้ง"
    exit 0
fi

step1_install_dependencies
step2_setup_database
step3_clone_package
step4_configure_env
step5_install_services
print_summary
