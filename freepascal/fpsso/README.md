# คู่มือการใช้งาน fpsso (FreePascal Single Sign-On Server)

**`fpsso`** คือระบบ Single Sign-On (SSO) Web Application ที่เขียนด้วยภาษา **FreePascal** ทำหน้าที่เป็น Captive Portal รับการเชื่อมต่อจากผู้ใช้งาน Wi-Fi ผ่าน **FortiGate Firewall** เพื่อพิสูจน์ตัวตนผ่านช่องทางต่างๆ (เช่น ThaID, MOPH Provider ID, Google OAuth2 หรือระบบบัญชีภายใน) ก่อนอนุญาตให้เข้าใช้งานอินเทอร์เน็ต

---

## 1. ภาพรวมการทำงาน (Architecture & Flow)

```
[ ผู้ใช้งาน Wi-Fi ] 
       │ 1. เชื่อมต่อ Wi-Fi
       ▼
[ FortiGate Firewall ] ─── 2. Redirect พร้อม magic token ───► [ fpsso Server (Port 8080) ]
                                                                      │ 3. ล็อกอินผ่าน
                                                                      │    ThaID / Provider ID /
                                                                      │    Google / Local
                                                                      ▼
                                                              [ สร้าง tmp_passwd ลง MySQL ]
                                                                      │
[ FortiGate Firewall ] ◄── 4. Auto POST (Username/tmp_passwd) ───────┘
       │ 5. ส่ง Access-Request (Port 1812)
       ▼
[ fp-radius Server ] ───── 6. ตรวจสอบ MySQL ───► Access-Accept (ผ่าน) ──► เปิด Internet ให้ผู้ใช้
```

---

## 2. การเตรียมความพร้อมก่อนใช้งาน (Prerequisites)

1. **ติดตั้ง FreePascal Compiler (กรณีต้องการ Compile เอง):**
   ```bash
   sudo apt-get update
   sudo apt-get install fpc
   ```

2. **ติดตั้งฐานข้อมูล MySQL / MariaDB** และสร้างฐานข้อมูลสำหรับเก็บข้อมูลสิทธิ์ยึดตามโครงสร้างของ RADIUS (`radcheck_mirror` และ `users`)

---

## 3. ตัวเลือกและคำสั่งย่อย (CLI Options & Subcommands)

โปรแกรม `fpsso` มาพร้อมคำสั่งช่วยจัดการระบบผ่าน Command Line ดังนี้:

### 3.1 คำสั่งช่วยเหลือ (Help)
```bash
./fpsso --help
# หรือ
./fpsso -h
```

### 3.2 Setup Wizard (ตัวช่วยตั้งค่าแบบโต้ตอบ)
เปิดระบบช่วยตั้งค่าไฟล์ `.env`, ติดตั้ง Systemd Service และคอนฟิก Apache Reverse Proxy ในขั้นตอนเดียว
```bash
sudo ./fpsso --setup-wizard
```

### 3.3 การติดตั้ง Systemd Service อัตโนมัติ (--installservice)
สร้างไฟล์ Service `/etc/systemd/system/fpsso.service` และเปิดให้โปรแกรมเริ่มทำงานอัตโนมัติเมื่อเปิดเครื่อง
```bash
sudo ./fpsso --installservice
```

### 3.4 การถอนติดตั้ง Systemd Service (--uninstallservice)
หยุดการทำงานและลบไฟล์ Service ออกจากระบบ
```bash
sudo ./fpsso --uninstallservice
```

---

## 4. การคอมไพล์โปรแกรม (Build)

หากมีการแก้ไข Source Code ในโฟลเดอร์ `src/` หรือไฟล์ `fpsso.lpr` สามารถทำการ Compile ใหม่ได้ด้วยคำสั่ง:

```bash
cd /var/www/api/freepascal/fpsso/

fpc -O3 -Xs -XX -CX \
    -Fu./src \
    -Fi./src \
    fpsso.lpr \
    -o fpsso
```

---

## 5. การรันโปรแกรม

### 5.1 การรันแบบปกติผ่าน Terminal (สำหรับทดสอบ)
```bash
cd /var/www/api/freepascal/fpsso/
./fpsso
```
* โปรแกรมจะเริ่มทำงานที่พอร์ต **`8080`** (หรือตามค่า `APP_PORT` ในไฟล์ `.env`)
* เข้าทดสอบผ่าน Browser: `http://localhost:8080/`

> **หมายเหตุ:** หากพบ Error `Server error: Binding of socket failed: 8080` แสดงว่าพอร์ต 8080 ถูกใช้งานอยู่แล้ว (อาจมี Service ของ `fpsso` รันอยู่เบื้องหลัง ให้ใช้คำสั่ง `sudo systemctl stop fpsso` ก่อน)

### 5.2 การรันเป็น Background Service (สำหรับ Production)

#### ขั้นตอนการตั้งค่า Systemd ด้วยตนเอง
1. คัดลอกไฟล์ Service เข้าสู่ระบบ:
   ```bash
   sudo cp /var/www/api/freepascal/fpsso/fpsso.service /etc/systemd/system/
   ```

2. โหลด Service ใหม่และเปิดใช้งาน:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable fpsso
   sudo systemctl start fpsso
   ```

#### การตรวจสอบและการจัดการ (Systemctl)
* **เช็คสถานะการทำงาน:**
  ```bash
  sudo systemctl status fpsso
  ```
* **เริ่มต้นระบบใหม่ (Restart):**
  ```bash
  sudo systemctl restart fpsso
  ```
* **หยุดการทำงาน (Stop):**
  ```bash
  sudo systemctl stop fpsso
  ```
* **ดู Log แบบ Real-time:**
  ```bash
  sudo journalctl -u fpsso -f
  ```

---

## 6. รายการ HTTP Routes / Endpoints

| Method | Path | คำอธิบาย |
| :--- | :--- | :--- |
| `GET` | `/` | หน้า Captive Portal Loginหลัก |
| `GET` | `/howto` | หน้าคู่มือการใช้งานระบบ |
| `GET` | `/status` | ตรวจสอบสถานะ Session / การเข้าใช้งาน |
| `POST` | `/auth/login` | ล็อกอินด้วย Username / Password (Local) |
| `GET` | `/auth/thaid` | เริ่มต้นกระบวนการ OAuth2 ของ ThaID |
| `GET` | `/auth/thaid/callback` | Callback URL รับข้อมูลรับรองจาก ThaID |
| `GET` | `/auth/providerid` | เริ่มต้นกระบวนการ OAuth2 ของ MOPH Provider ID |
| `GET` | `/auth/providerid/callback` | Callback URL รับข้อมูลรับรองจาก Provider ID |
| `GET` | `/auth/google` | เริ่มต้นกระบวนการ OAuth2 ของ Google |
| `GET` | `/auth/google/callback` | Callback URL รับข้อมูลรับรองจาก Google |
| `GET` | `/auth/logout` | ล็อกเอาต์และแจ้งเตือนไปยัง FortiGate |
| `GET` | `/fortigate/handshake` | Auto-submit POST ยืนยันตัวตนกลับไปที่ FortiGate |
| `GET` | `/admin` | หน้าผู้ดูแลระบบ (Admin Dashboard) |
| `GET/POST` | `/api/users` | REST API สำหรับจัดการข้อมูลผู้ใช้งาน |

---

## 7. การตั้งค่าคอนฟิก (.env)

สร้างไฟล์ `.env` ไว้ที่โฟลเดอร์เดียวกับโปรแกรม:

```ini
# การเชื่อมต่อฐานข้อมูล MySQL
DB_HOST=127.0.0.1
DB_USER=root
DB_PASS=your_password
DB_NAME=radius

# ThaID OAuth2 Configuration
THAID_CLIENT_ID=your_thaid_client_id
THAID_SECRET_ID=your_thaid_secret
THAID_REDIRECT_URI=https://yourdomain.com/sso/auth/thaid/callback

# MOPH Provider ID Configuration
PROVIDER_ID_CLIENT_ID=your_provider_id_client_id
PROVIDER_ID_SECRET_KEY=your_provider_id_secret
PROVIDER_ID_REDIRECT_URI=https://yourdomain.com/sso/auth/providerid/callback

# System & FortiGate Configuration
FORTIGATE_LOGOUT_URL=
LOGIN_TEMPLATE_PATH=templates/login.html
ADMIN_USERNAME=admin
ADMIN_PASSWORD=your_admin_password
SSO_AUTO_APPROVE=true
APP_PORT=8080
```
