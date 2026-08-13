#!/bin/bash

# =============================================================================
# fpsso + fp-radius Automated Installation Script
# รองรับภาษาไทย และ ภาษาอังกฤษ / Supports Thai and English
# Ubuntu 20.04 / 22.04 LTS
# =============================================================================

# --- สีสำหรับแสดงผลใน Terminal / Terminal Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- ตัวแปรภาษา / Language variable ---
LANG_CODE="th"  # ค่าเริ่มต้น: ไทย / Default: Thai

# --- ตัวแปร Default ---
INSTALL_DIR="/var/www/api/freepascal"
REPO_URL="https://github.com/thaidelphi/internet-authen.git"
DB_NAME="radius"
DB_USER="radius_user"
DB_PASS=""
SKIP_DB_INSTALL=0
SKIP_FPC_INSTALL=0

# =============================================================================
# ฟังก์ชัน i18n: แปลข้อความตามภาษาที่เลือก
# i18n function: translate text based on selected language
# =============================================================================
t() {
    local key="$1"
    if [ "$LANG_CODE" = "en" ]; then
        case $key in
            # Banner
            "banner_title")         echo "fpsso + fp-radius Auto Installer" ;;
            "banner_subtitle")      echo "Installation Script v1.0" ;;
            # Root check
            "err_root")             echo "This script must be run as root (sudo ./setup.sh)" ;;
            # Language select
            "lang_prompt")          echo "Please select your language:" ;;
            "lang_thai")            echo "  1) Thai (ภาษาไทย)" ;;
            "lang_english")         echo "  2) English" ;;
            "lang_choice")          echo "Your choice [1/2]: " ;;
            # General
            "confirm_prompt")       echo "Do you want to proceed? (y/n): " ;;
            "cancelled")            echo "Installation cancelled." ;;
            "install_dir")          echo "Install Dir" ;;
            "db_name")              echo "DB Name" ;;
            "db_user")              echo "DB User" ;;
            "skip_mariadb")         echo "Skip MariaDB" ;;
            "yes")                  echo "Yes" ;;
            "no")                   echo "No" ;;
            "config_heading")       echo "Configuration to be used:" ;;
            # Step 1
            "step1_heading")        echo "Step 1: Installing Dependencies" ;;
            "step1_updating")       echo "Updating package list..." ;;
            "step1_err_update")     echo "Failed to update package list." ;;
            "step1_installing_dep") echo "Installing build tools and dependencies..." ;;
            "step1_err_dep")        echo "Failed to install dependencies." ;;
            "step1_dep_ok")         echo "Dependencies installed successfully." ;;
            "step1_fpc_found")      echo "Free Pascal Compiler found: version" ;;
            "step1_fpc_skip")       echo "(skipping install)" ;;
            "step1_installing_fpc") echo "Installing Free Pascal Compiler (FPC)..." ;;
            "step1_err_fpc")        echo "Failed to install FPC." ;;
            # Step 2
            "step2_heading")        echo "Step 2: MariaDB Database Setup" ;;
            "step2_skip")           echo "Skipping MariaDB installation (--skip-db specified)." ;;
            "step2_installing")     echo "Installing MariaDB Server..." ;;
            "step2_err_install")    echo "Failed to install MariaDB." ;;
            "step2_db_found")       echo "MariaDB/MySQL already installed. (skipping)" ;;
            "step2_pass_prompt")    echo "Enter a password for Database User" ;;
            "step2_pass_confirm")   echo "Confirm password: " ;;
            "step2_pass_mismatch")  echo "Passwords do not match. Please try again." ;;
            "step2_creating_db")    echo "Creating database and user..." ;;
            "step2_err_db")         echo "Failed to create database. Check MariaDB root privileges." ;;
            "step2_db_ok")          echo "Database and user created successfully." ;;
            # Step 3
            "step3_heading")        echo "Step 3: Downloading Package from Repository" ;;
            "step3_removing_old")   echo "Removing old directory and re-downloading..." ;;
            "step3_cloning")        echo "Cloning from" ;;
            "step3_err_clone")      echo "Failed to clone repository. Check your internet connection." ;;
            "step3_clone_ok")       echo "Download successful." ;;
            "step3_copying_radius") echo "fp-radius copied successfully." ;;
            "step3_copying_sso")    echo "fpsso copied successfully." ;;
            # Step 4
            "step4_heading")        echo "Step 4: Configuring Environment Variables" ;;
            "step4_created_radius") echo "Created fp-radius .env from .env.example" ;;
            "step4_updated_radius") echo "Updated fp-radius .env" ;;
            "step4_warn_radius")    echo "Please manually edit" ;;
            "step4_created_sso")    echo "Created fpsso .env from .env.example" ;;
            "step4_updated_sso")    echo "Updated fpsso .env" ;;
            # Step 5
            "step5_heading")        echo "Step 5: Installing Systemd Services" ;;
            "step5_copied_radius")  echo "Copied fpradius.service to systemd." ;;
            "step5_created_radius") echo "Created fpradius.service successfully." ;;
            "step5_copied_sso")     echo "Copied fpsso.service to systemd." ;;
            "step5_created_sso")    echo "Created fpsso.service successfully." ;;
            "step5_reloading")      echo "Reloading systemd daemon..." ;;
            "step5_enabling")       echo "Enabling services..." ;;
            "step5_en_radius_ok")   echo "fpradius service enabled." ;;
            "step5_en_radius_fail") echo "fpradius service not found." ;;
            "step5_en_sso_ok")      echo "fpsso service enabled." ;;
            "step5_en_sso_fail")    echo "fpsso service not found." ;;
            "step5_starting")       echo "Starting services..." ;;
            "step5_start_radius_ok")   echo "fpradius started successfully." ;;
            "step5_start_radius_fail") echo "Could not start fpradius (please check .env)." ;;
            "step5_start_sso_ok")      echo "fpsso started successfully." ;;
            "step5_start_sso_fail")    echo "Could not start fpsso (please check .env)." ;;
            # Summary
            "summary_title")        echo "Installation Complete!" ;;
            "summary_status")       echo "Check service status:" ;;
            "summary_logs")         echo "View logs:" ;;
            "summary_test")         echo "Test the system:" ;;
            "summary_env")          echo "Config files (.env) are at:" ;;
            "summary_warn_api")     echo "Don't forget to set API Keys in fpsso/.env (THAID, PROVIDERID, GOOGLE)" ;;
            # Help
            "help_usage")           echo "Usage: sudo ./setup.sh [OPTIONS]" ;;
            "help_options")         echo "Options:" ;;
            "help_skip_db")         echo "  --skip-db       Skip MariaDB installation (use external DB)" ;;
            "help_skip_fpc")        echo "  --skip-fpc      Skip FPC installation (already installed)" ;;
            "help_db_pass")         echo "  --db-pass=PASS  Set database password directly (non-interactive)" ;;
            "help_db_user")         echo "  --db-user=USER  Set database username (default: radius_user)" ;;
            "help_db_name")         echo "  --db-name=NAME  Set database name (default: radius)" ;;
            "help_lang")            echo "  --lang=th|en    Set language (default: th)" ;;
            "help_help")            echo "  --help          Show this help" ;;
            "help_examples")        echo "Examples:" ;;
            *)                      echo "$key" ;;
        esac
    else
        # ภาษาไทย (ค่าเริ่มต้น)
        case $key in
            "banner_title")         echo "ระบบติดตั้ง fpsso + fp-radius อัตโนมัติ" ;;
            "banner_subtitle")      echo "Installation Script v1.0" ;;
            "err_root")             echo "สคริปต์นี้ต้องรันด้วยสิทธิ์ root (sudo ./setup.sh)" ;;
            "lang_prompt")          echo "กรุณาเลือกภาษาที่ต้องการ:" ;;
            "lang_thai")            echo "  1) ไทย (Thai)" ;;
            "lang_english")         echo "  2) English (ภาษาอังกฤษ)" ;;
            "lang_choice")          echo "เลือก [1/2]: " ;;
            "confirm_prompt")       echo "ต้องการดำเนินการต่อหรือไม่? (y/n): " ;;
            "cancelled")            echo "ยกเลิกการติดตั้ง" ;;
            "install_dir")          echo "โฟลเดอร์ติดตั้ง" ;;
            "db_name")              echo "ชื่อ Database" ;;
            "db_user")              echo "ชื่อผู้ใช้ Database" ;;
            "skip_mariadb")         echo "ข้าม MariaDB" ;;
            "yes")                  echo "ใช่" ;;
            "no")                   echo "ไม่" ;;
            "config_heading")       echo "การตั้งค่าที่จะใช้:" ;;
            "step1_heading")        echo "ขั้นตอนที่ 1: ติดตั้งโปรแกรมที่จำเป็น" ;;
            "step1_updating")       echo "กำลังอัปเดต package list..." ;;
            "step1_err_update")     echo "ไม่สามารถอัปเดต package list ได้" ;;
            "step1_installing_dep") echo "กำลังติดตั้ง build tools และ dependencies..." ;;
            "step1_err_dep")        echo "ไม่สามารถติดตั้ง dependencies ได้" ;;
            "step1_dep_ok")         echo "ติดตั้ง dependencies สำเร็จ" ;;
            "step1_fpc_found")      echo "พบ Free Pascal Compiler เวอร์ชัน" ;;
            "step1_fpc_skip")       echo "(ข้ามการติดตั้ง)" ;;
            "step1_installing_fpc") echo "กำลังติดตั้ง Free Pascal Compiler (FPC)..." ;;
            "step1_err_fpc")        echo "ไม่สามารถติดตั้ง FPC ได้" ;;
            "step2_heading")        echo "ขั้นตอนที่ 2: ตั้งค่าฐานข้อมูล MariaDB" ;;
            "step2_skip")           echo "ข้ามการติดตั้ง MariaDB (--skip-db ถูกระบุ)" ;;
            "step2_installing")     echo "กำลังติดตั้ง MariaDB Server..." ;;
            "step2_err_install")    echo "ไม่สามารถติดตั้ง MariaDB ได้" ;;
            "step2_db_found")       echo "พบ MariaDB/MySQL ติดตั้งอยู่แล้ว (ข้ามการติดตั้ง)" ;;
            "step2_pass_prompt")    echo "กรุณากำหนดรหัสผ่านสำหรับ Database User" ;;
            "step2_pass_confirm")   echo "ยืนยันรหัสผ่าน: " ;;
            "step2_pass_mismatch")  echo "รหัสผ่านไม่ตรงกัน กรุณาลองใหม่อีกครั้ง" ;;
            "step2_creating_db")    echo "กำลังสร้างฐานข้อมูลและผู้ใช้..." ;;
            "step2_err_db")         echo "ไม่สามารถสร้างฐานข้อมูลได้ กรุณาตรวจสอบสิทธิ์ root ของ MariaDB" ;;
            "step2_db_ok")          echo "สร้างฐานข้อมูลและผู้ใช้สำเร็จ" ;;
            "step3_heading")        echo "ขั้นตอนที่ 3: ดึงไฟล์ติดตั้งจาก Repository" ;;
            "step3_removing_old")   echo "พบโฟลเดอร์เก่า กำลังลบและดึงใหม่..." ;;
            "step3_cloning")        echo "กำลังดึงไฟล์จาก" ;;
            "step3_err_clone")      echo "ไม่สามารถดึงไฟล์จาก Repository ได้ กรุณาตรวจสอบการเชื่อมต่อ Internet" ;;
            "step3_clone_ok")       echo "ดึงไฟล์สำเร็จ" ;;
            "step3_copying_radius") echo "คัดลอก fp-radius สำเร็จ" ;;
            "step3_copying_sso")    echo "คัดลอก fpsso สำเร็จ" ;;
            "step4_heading")        echo "ขั้นตอนที่ 4: ตั้งค่า Environment Variables" ;;
            "step4_created_radius") echo "สร้างไฟล์ .env สำหรับ fp-radius จาก .env.example" ;;
            "step4_updated_radius") echo "อัปเดต fp-radius .env เรียบร้อย" ;;
            "step4_warn_radius")    echo "กรุณาแก้ไขไฟล์ด้วยตัวเอง:" ;;
            "step4_created_sso")    echo "สร้างไฟล์ .env สำหรับ fpsso จาก .env.example" ;;
            "step4_updated_sso")    echo "อัปเดต fpsso .env เรียบร้อย" ;;
            "step5_heading")        echo "ขั้นตอนที่ 5: ติดตั้ง Systemd Service" ;;
            "step5_copied_radius")  echo "คัดลอก fpradius.service ไปยัง systemd" ;;
            "step5_created_radius") echo "สร้าง fpradius.service สำเร็จ" ;;
            "step5_copied_sso")     echo "คัดลอก fpsso.service ไปยัง systemd" ;;
            "step5_created_sso")    echo "สร้าง fpsso.service สำเร็จ" ;;
            "step5_reloading")      echo "กำลัง Reload systemd daemon..." ;;
            "step5_enabling")       echo "กำลังเปิดใช้งาน Services..." ;;
            "step5_en_radius_ok")   echo "เปิดใช้งาน fpradius service สำเร็จ" ;;
            "step5_en_radius_fail") echo "ไม่พบ fpradius service" ;;
            "step5_en_sso_ok")      echo "เปิดใช้งาน fpsso service สำเร็จ" ;;
            "step5_en_sso_fail")    echo "ไม่พบ fpsso service" ;;
            "step5_starting")       echo "กำลังเริ่ม Services..." ;;
            "step5_start_radius_ok")   echo "เริ่ม fpradius สำเร็จ" ;;
            "step5_start_radius_fail") echo "ไม่สามารถเริ่ม fpradius ได้ (กรุณาตรวจสอบ .env)" ;;
            "step5_start_sso_ok")      echo "เริ่ม fpsso สำเร็จ" ;;
            "step5_start_sso_fail")    echo "ไม่สามารถเริ่ม fpsso ได้ (กรุณาตรวจสอบ .env)" ;;
            "summary_title")        echo "✅ การติดตั้งเสร็จสิ้น!" ;;
            "summary_status")       echo "ตรวจสอบสถานะ Service:" ;;
            "summary_logs")         echo "ดู Log:" ;;
            "summary_test")         echo "ทดสอบระบบ:" ;;
            "summary_env")          echo "ไฟล์ .env อยู่ที่:" ;;
            "summary_warn_api")     echo "⚠️  อย่าลืมแก้ไขค่า API Keys ใน fpsso/.env (THAID, PROVIDERID, GOOGLE)" ;;
            "help_usage")           echo "การใช้งาน: sudo ./setup.sh [OPTIONS]" ;;
            "help_options")         echo "Options:" ;;
            "help_skip_db")         echo "  --skip-db       ข้ามการติดตั้ง MariaDB (ใช้ external DB)" ;;
            "help_skip_fpc")        echo "  --skip-fpc      ข้ามการติดตั้ง FPC (มีแล้วในระบบ)" ;;
            "help_db_pass")         echo "  --db-pass=PASS  กำหนดรหัสผ่าน Database โดยตรง (ไม่ต้อง Interactive)" ;;
            "help_db_user")         echo "  --db-user=USER  กำหนดชื่อ Database User (ค่าเริ่มต้น: radius_user)" ;;
            "help_db_name")         echo "  --db-name=NAME  กำหนดชื่อ Database (ค่าเริ่มต้น: radius)" ;;
            "help_lang")            echo "  --lang=th|en    เลือกภาษา (ค่าเริ่มต้น: th)" ;;
            "help_help")            echo "  --help          แสดง Help นี้" ;;
            "help_examples")        echo "ตัวอย่าง:" ;;
            *)                      echo "$key" ;;
        esac
    fi
}

# =============================================================================
# ฟังก์ชันแสดงผล
# =============================================================================
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }

print_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════╗"
    printf "║  %-52s  ║\n" "$(t banner_title)"
    printf "║  %-52s  ║\n" "$(t banner_subtitle)"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# =============================================================================
# เลือกภาษา / Language Selection
# =============================================================================
select_language() {
    # ถ้าระบุ --lang มาแล้วจาก argument ไม่ต้องถาม
    if [ "$LANG_CODE" != "th" ] && [ "$LANG_CODE" != "en" ]; then
        LANG_CODE="th"
    fi

    # ถ้าได้รับ --lang= จาก argument ข้ามการถามได้เลย
    if [ -n "$LANG_ARG_SET" ]; then
        return
    fi

    echo ""
    echo -e "${CYAN}$(t lang_prompt)${NC}"
    echo "$(t lang_thai)"
    echo "$(t lang_english)"
    echo ""
    read -p "$(t lang_choice)" LANG_CHOICE

    case "$LANG_CHOICE" in
        2|en|EN) LANG_CODE="en" ;;
        *)       LANG_CODE="th" ;;
    esac
    echo ""
}

# =============================================================================
# ตรวจสอบ Root
# =============================================================================
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "$(t err_root)"
        exit 1
    fi
}

# =============================================================================
# ขั้นตอนที่ 1: ติดตั้ง Dependencies
# =============================================================================
step1_install_dependencies() {
    echo ""
    echo -e "${YELLOW}════ $(t step1_heading) ════${NC}"

    info "$(t step1_updating)"
    apt-get update -q
    if [ $? -ne 0 ]; then
        error "$(t step1_err_update)"; exit 1
    fi

    info "$(t step1_installing_dep)"
    apt-get install -y -q build-essential libmariadb-dev libssl-dev git curl wget upx-ucl
    if [ $? -ne 0 ]; then
        error "$(t step1_err_dep)"; exit 1
    fi
    success "$(t step1_dep_ok)"

    if [ "$SKIP_FPC_INSTALL" -eq 0 ]; then
        if command -v fpc &> /dev/null; then
            FPC_VER=$(fpc -iV 2>/dev/null)
            success "$(t step1_fpc_found) $FPC_VER $(t step1_fpc_skip)"
        else
            info "$(t step1_installing_fpc)"
            apt-get install -y -q fpc
            if [ $? -ne 0 ]; then
                error "$(t step1_err_fpc)"; exit 1
            fi
            success "$(t step1_fpc_found) $(fpc -iV)"
        fi
    fi
}

# =============================================================================
# ขั้นตอนที่ 2: ตั้งค่า MariaDB
# =============================================================================
step2_setup_database() {
    echo ""
    echo -e "${YELLOW}════ $(t step2_heading) ════${NC}"

    if [ "$SKIP_DB_INSTALL" -eq 1 ]; then
        warn "$(t step2_skip)"; return
    fi

    if ! command -v mysqld &> /dev/null && ! command -v mariadbd &> /dev/null; then
        info "$(t step2_installing)"
        apt-get install -y -q mariadb-server
        if [ $? -ne 0 ]; then
            error "$(t step2_err_install)"; exit 1
        fi
        systemctl start mariadb
        systemctl enable mariadb
        success "$(t step2_db_found)"
    else
        success "$(t step2_db_found)"
    fi

    if [ -z "$DB_PASS" ]; then
        echo ""
        echo -e "${CYAN}$(t step2_pass_prompt) '${DB_USER}':${NC}"
        read -s -p "Password: " DB_PASS
        echo ""
        read -s -p "$(t step2_pass_confirm)" DB_PASS_CONFIRM
        echo ""
        if [ "$DB_PASS" != "$DB_PASS_CONFIRM" ]; then
            error "$(t step2_pass_mismatch)"; exit 1
        fi
    fi

    info "$(t step2_creating_db)"
    mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
    if [ $? -ne 0 ]; then
        error "$(t step2_err_db)"; exit 1
    fi
    success "$(t step2_db_ok) (DB: '${DB_NAME}', User: '${DB_USER}')"
}

# =============================================================================
# ขั้นตอนที่ 3: ดึง Package จาก Repository
# =============================================================================
step3_clone_package() {
    echo ""
    echo -e "${YELLOW}════ $(t step3_heading) ════${NC}"

    PACKAGE_DIR="/tmp/internet-authen"
    if [ -d "$PACKAGE_DIR" ]; then
        info "$(t step3_removing_old)"
        rm -rf "$PACKAGE_DIR"
    fi

    info "$(t step3_cloning) $REPO_URL ..."
    git clone "$REPO_URL" "$PACKAGE_DIR"
    if [ $? -ne 0 ]; then
        error "$(t step3_err_clone)"; exit 1
    fi
    success "$(t step3_clone_ok)"

    mkdir -p "$INSTALL_DIR"

    if [ -d "$PACKAGE_DIR/fp-radius" ]; then
        cp -r "$PACKAGE_DIR/fp-radius" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/fp-radius/fpradius"
        success "$(t step3_copying_radius)"
    fi

    if [ -d "$PACKAGE_DIR/fpsso" ]; then
        cp -r "$PACKAGE_DIR/fpsso" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/fpsso/fpsso"
        success "$(t step3_copying_sso)"
    fi

    [ -f "$PACKAGE_DIR/INSTALL.md" ] && cp "$PACKAGE_DIR/INSTALL.md" "$INSTALL_DIR/"
    rm -rf "$PACKAGE_DIR"
}

# =============================================================================
# ขั้นตอนที่ 4: ตั้งค่า .env
# =============================================================================
step4_configure_env() {
    echo ""
    echo -e "${YELLOW}════ $(t step4_heading) ════${NC}"

    FP_RADIUS_DIR="$INSTALL_DIR/fp-radius"
    FPSSO_DIR="$INSTALL_DIR/fpsso"

    if [ -d "$FP_RADIUS_DIR" ] && [ ! -f "$FP_RADIUS_DIR/.env" ] && [ -f "$FP_RADIUS_DIR/.env.example" ]; then
        cp "$FP_RADIUS_DIR/.env.example" "$FP_RADIUS_DIR/.env"
        info "$(t step4_created_radius)"
    fi

    if [ -f "$FP_RADIUS_DIR/.env" ] && [ -n "$DB_PASS" ]; then
        sed -i "s/^DB_HOST=.*/DB_HOST=localhost/" "$FP_RADIUS_DIR/.env"
        sed -i "s/^DB_NAME=.*/DB_NAME=${DB_NAME}/" "$FP_RADIUS_DIR/.env"
        sed -i "s/^DB_USER=.*/DB_USER=${DB_USER}/" "$FP_RADIUS_DIR/.env"
        sed -i "s/^DB_PASS=.*/DB_PASS=${DB_PASS}/" "$FP_RADIUS_DIR/.env"
        success "$(t step4_updated_radius)"
    else
        warn "$(t step4_warn_radius) $FP_RADIUS_DIR/.env"
    fi

    if [ -d "$FPSSO_DIR" ] && [ ! -f "$FPSSO_DIR/.env" ] && [ -f "$FPSSO_DIR/.env.example" ]; then
        cp "$FPSSO_DIR/.env.example" "$FPSSO_DIR/.env"
        info "$(t step4_created_sso)"
    fi

    if [ -f "$FPSSO_DIR/.env" ] && [ -n "$DB_PASS" ]; then
        sed -i "s/^DB_HOST=.*/DB_HOST=localhost/" "$FPSSO_DIR/.env"
        sed -i "s/^DB_NAME=.*/DB_NAME=${DB_NAME}/" "$FPSSO_DIR/.env"
        sed -i "s/^DB_USER=.*/DB_USER=${DB_USER}/" "$FPSSO_DIR/.env"
        sed -i "s/^DB_PASS=.*/DB_PASS=${DB_PASS}/" "$FPSSO_DIR/.env"
        success "$(t step4_updated_sso)"
    else
        warn "$(t step4_warn_radius) $FPSSO_DIR/.env"
    fi
}

# =============================================================================
# ขั้นตอนที่ 5: ติดตั้ง Systemd Services
# =============================================================================
step5_install_services() {
    echo ""
    echo -e "${YELLOW}════ $(t step5_heading) ════${NC}"

    if [ -f "$INSTALL_DIR/fp-radius/fpradius.service" ]; then
        cp "$INSTALL_DIR/fp-radius/fpradius.service" /etc/systemd/system/
        success "$(t step5_copied_radius)"
    elif [ -f "$INSTALL_DIR/fp-radius/fpradius" ]; then
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
        success "$(t step5_created_radius)"
    fi

    if [ -f "$INSTALL_DIR/fpsso/fpsso.service" ]; then
        cp "$INSTALL_DIR/fpsso/fpsso.service" /etc/systemd/system/
        success "$(t step5_copied_sso)"
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
        success "$(t step5_created_sso)"
    fi

    info "$(t step5_reloading)"
    systemctl daemon-reload

    info "$(t step5_enabling)"
    systemctl enable fpradius 2>/dev/null && success "$(t step5_en_radius_ok)" || warn "$(t step5_en_radius_fail)"
    systemctl enable fpsso    2>/dev/null && success "$(t step5_en_sso_ok)"    || warn "$(t step5_en_sso_fail)"

    info "$(t step5_starting)"
    systemctl start fpradius 2>/dev/null && success "$(t step5_start_radius_ok)" || warn "$(t step5_start_radius_fail)"
    systemctl start fpsso    2>/dev/null && success "$(t step5_start_sso_ok)"    || warn "$(t step5_start_sso_fail)"
}

# =============================================================================
# สรุปผล / Summary
# =============================================================================
print_summary() {
    echo ""
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════╗"
    printf "║  %-52s  ║\n" "$(t summary_title)"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    SERVER_IP=$(hostname -I | awk '{print $1}')
    echo -e "  ${CYAN}$(t summary_status)${NC}"
    echo "    sudo systemctl status fpsso"
    echo "    sudo systemctl status fpradius"
    echo ""
    echo -e "  ${CYAN}$(t summary_logs)${NC}"
    echo "    sudo journalctl -u fpsso -f"
    echo "    sudo journalctl -u fpradius -f"
    echo ""
    echo -e "  ${CYAN}$(t summary_test)${NC}"
    echo "    http://${SERVER_IP}:8080/sso/"
    echo ""
    echo -e "  ${CYAN}$(t summary_env)${NC}"
    echo "    $INSTALL_DIR/fpsso/.env"
    echo "    $INSTALL_DIR/fp-radius/.env"
    echo ""
    warn "$(t summary_warn_api)"
}

# =============================================================================
# Help
# =============================================================================
print_help() {
    echo "$(t help_usage)"
    echo ""
    echo "$(t help_options)"
    echo "$(t help_skip_db)"
    echo "$(t help_skip_fpc)"
    echo "$(t help_db_pass)"
    echo "$(t help_db_user)"
    echo "$(t help_db_name)"
    echo "$(t help_lang)"
    echo "$(t help_help)"
    echo ""
    echo "$(t help_examples)"
    echo "  sudo ./setup.sh"
    echo "  sudo ./setup.sh --lang=en --skip-db --db-pass=MyPassword"
}

# =============================================================================
# รับ Arguments
# =============================================================================
LANG_ARG_SET=""
for arg in "$@"; do
    case $arg in
        --skip-db)     SKIP_DB_INSTALL=1 ;;
        --skip-fpc)    SKIP_FPC_INSTALL=1 ;;
        --db-pass=*)   DB_PASS="${arg#*=}" ;;
        --db-user=*)   DB_USER="${arg#*=}" ;;
        --db-name=*)   DB_NAME="${arg#*=}" ;;
        --lang=th)     LANG_CODE="th"; LANG_ARG_SET=1 ;;
        --lang=en)     LANG_CODE="en"; LANG_ARG_SET=1 ;;
        --help|-h)     print_help; exit 0 ;;
        *)             warn "Unknown argument: $arg" ;;
    esac
done

# =============================================================================
# เริ่มต้น
# =============================================================================
# เลือกภาษาก่อนทำอะไร (ถ้ายังไม่ได้ระบุ --lang)
select_language

print_banner
check_root

echo -e "${CYAN}$(t config_heading)${NC}"
echo "  $(t install_dir) : $INSTALL_DIR"
echo "  $(t db_name)     : $DB_NAME"
echo "  $(t db_user)     : $DB_USER"
echo "  $(t skip_mariadb): $( [ $SKIP_DB_INSTALL -eq 1 ] && t yes || t no )"
echo ""
read -p "$(t confirm_prompt)" CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "$(t cancelled)"; exit 0
fi

step1_install_dependencies
step2_setup_database
step3_clone_package
step4_configure_env
step5_install_services
print_summary
