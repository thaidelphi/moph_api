# คู่มือการติดตั้งระบบและเตรียมความพร้อมเซิร์ฟเวอร์ (Installation Guide)

เอกสารนี้จะอธิบายขั้นตอนการติดตั้ง **สภาพแวดล้อม (Environment)** ที่จำเป็นทั้งหมด ตั้งแต่เซิร์ฟเวอร์เปล่าๆ จนถึงพร้อมรันระบบ `fpsso` และ `fp-radius`

---

## 1. ความต้องการของระบบ (System Requirements)
- **OS:** Ubuntu 20.04 LTS หรือ 22.04 LTS (แนะนำ)
- **CPU:** 2 Cores ขึ้นไป
- **RAM:** 2 GB ขึ้นไป
- **Database:** MySQL 8.0 หรือ MariaDB (ติดตั้งในตัว หรือใช้ External DB ก็ได้)

---

## 2. การติดตั้งโปรแกรมที่จำเป็น (Prerequisites)

อัปเดตระบบและติดตั้งไลบรารีที่จำเป็น:
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y build-essential libmysqlclient-dev libssl-dev git curl wget
```

### การติดตั้ง Free Pascal Compiler (FPC)
ระบบถูกพัฒนาด้วยภาษา Pascal จำเป็นต้องมีคอมไพเลอร์ในการบิวด์:
```bash
sudo apt install -y fpc
```
ตรวจสอบการติดตั้ง:
```bash
fpc -iV
# ควรแสดงเวอร์ชัน 3.2.2 หรือใหม่กว่า
```

---

## 3. การติดตั้งฐานข้อมูล (Database Setup)

หากคุณใช้เซิร์ฟเวอร์ฐานข้อมูลแยกต่างหาก สามารถข้ามขั้นตอนนี้ได้
```bash
sudo apt install -y mysql-server
sudo systemctl start mysql
sudo systemctl enable mysql
```

**สร้างผู้ใช้และฐานข้อมูลสำหรับ RADIUS:**
```bash
sudo mysql
```
รันคำสั่ง SQL ต่อไปนี้ (เปลี่ยน `YOUR_PASSWORD` เป็นรหัสผ่านที่ต้องการ):
```sql
CREATE DATABASE radius CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'radius_user'@'localhost' IDENTIFIED BY 'YOUR_PASSWORD';
GRANT ALL PRIVILEGES ON radius.* TO 'radius_user'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```
*(หมายเหตุ: โครงสร้างตารางต่างๆ เช่น `radcheck_mirror` และ `login_history` ระบบ `fpsso` และ `fp-radius` จะเป็นคนสร้างให้อัตโนมัติเมื่อสั่งรันโปรแกรมครั้งแรก)*

---

## 4. การดึงโค้ดจาก Git (Clone Repository)

```bash
cd /var/www/
sudo git clone https://github.com/thaidelphi/moph_api.git api
cd api/freepascal
```

---

## 5. การตั้งค่าระบบ (Configuration)

### 5.1 ระบบ RADIUS Proxy (`fp-radius`)
```bash
cd /var/www/api/freepascal/fp-radius
cp .env.example .env
nano .env
```
ตั้งค่าที่สำคัญ:
- `DB_HOST`, `DB_USER`, `DB_PASS`, `DB_NAME`
- `RADIUS_AUTH_PORT=1812` (พอร์ตที่รับข้อมูลจาก FortiGate)
- `RADIUS_SECRET=testing123` (ตั้งค่าให้ตรงกับฝั่ง FortiGate)

### 5.2 ระบบ SSO (`fpsso`)
```bash
cd /var/www/api/freepascal/fpsso
cp .env.example .env
nano .env
```
ตั้งค่าที่สำคัญใน `.env`:
- `DB_HOST`, `DB_USER`, `DB_PASS`, `DB_NAME` (ให้ตรงกับฐานข้อมูลที่สร้างไว้)
- การตั้งค่า `PROVIDERID_*` และ `THAID_*` (API Keys ต่างๆ)
- `TEMPLATE_FOLDER=templates/login_template`

---

## 6. การ Compile และติดตั้งเป็น Service

### 6.1 Compile ระบบ
เพื่อให้ระบบทำงานได้เร็วที่สุด ต้อง Compile เป็นโหมด Release
**fp-radius:**
```bash
cd /var/www/api/freepascal/fp-radius
fpc -O3 -XX -Xs -Fu"src" fpradius.lpr
```
**fpsso:**
```bash
cd /var/www/api/freepascal/fpsso
fpc -O3 -XX -Xs -Fu"src" fpsso.lpr
```

### 6.2 ติดตั้ง Service (Systemd)
เพื่อให้โปรแกรมทำงานแบบ Background และรันอัตโนมัติเมื่อเปิดเครื่อง

**ติดตั้ง fpradius:**
โปรแกรม `fp-radius` มีคำสั่งช่วยติดตั้ง Service และ Database ในตัว คุณสามารถใช้คำสั่งต่อไปนี้ได้เลย:
```bash
cd /var/www/api/freepascal/fp-radius
# สั่งติดตั้ง Systemd Service อัตโนมัติ
sudo ./fpradius --installservice

# (แถม) หากต้องการสร้าง Database และตารางอัตโนมัติ ให้ใช้:
# ./fpradius --init-database

# (แถม) หากต้องการรันวิซาร์ดตั้งค่าทีละขั้นตอน:
# ./fpradius --setup-wizard
```
หลังจากติดตั้ง Service เสร็จ ให้สั่งให้ทำงาน:
```bash
sudo systemctl daemon-reload
sudo systemctl enable fpradius
sudo systemctl start fpradius
```

**ติดตั้ง fpsso:**
```bash
sudo cp /var/www/api/freepascal/fpsso/fpsso.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable fpsso
sudo systemctl start fpsso
```

---

## 7. ตรวจสอบการทำงาน

เช็คว่า Service ทั้งสองทำงานปกติหรือไม่:
```bash
sudo systemctl status fpsso
sudo systemctl status fpradius
```

ดู Log สด (Real-time logs) กรณีเกิดข้อผิดพลาด:
```bash
sudo journalctl -u fpsso -f
sudo journalctl -u fpradius -f
```

**เสร็จสิ้นการติดตั้ง!** ตอนนี้คุณสามารถทดลองเข้าหน้าเว็บ `http://YOUR_SERVER_IP:8080/sso/` เพื่อทดสอบระบบหน้าล็อกอินได้เลย
