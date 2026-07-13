# แผนการแปลงระบบ SSO จาก PHP เป็น FreePascal

## ภาพรวมของระบบปัจจุบัน (Current PHP System)

ระบบปัจจุบันเป็น Web Application ที่ทำงานบน Apache + PHP มีหน้าที่รับผิดชอบดังนี้:

```
                ┌──────────────────────────────┐
                │   index.php / login.php       │  ← หน้า Login หลัก (HTML/CSS)
                └────────────┬─────────────────┘
                             │
          ┌──────────────────┼──────────────────┐
          ▼                  ▼                  ▼
   thaid_api.php      providerid_api.php    google_api.php
   (ThaID SSO)        (MOPH ID / ProviderID) (Google OAuth)
          │                  │                  │
          └──────────────────┼──────────────────┘
                             ▼
                      radius_auth.php  ← ตรวจสอบ/สร้างรหัสผ่านใน Radius
                             │
                             ▼
                  fortigate_handshake.php  ← ส่ง Credentials ให้ FortiGate
```

---

## ทำไมถึงแปลงเป็น FreePascal?

| ข้อดี | รายละเอียด |
|---|---|
| **ประสิทธิภาพสูงกว่า** | Pascal Compile เป็น Native Binary ทำงานเร็วกว่า PHP มาก |
| **ใช้ RAM น้อยกว่า** | ไม่ต้องการ PHP Runtime ลด Overhead บน Server |
| **ควบคุมได้ละเอียดกว่า** | จัดการ HTTP Request/Response, Socket, และ Threads ได้โดยตรง |
| **Build เป็น Service/Daemon ได้** | รันเป็น Background Service โดยไม่พึ่ง Apache |

---

## สถาปัตยกรรมใหม่ที่เสนอ (FreePascal Architecture)

ระบบใหม่จะแบ่งออกเป็น **2 ส่วนหลัก**:

### ส่วนที่ 1: FreePascal HTTP Server (Backend)

โปรแกรม Pascal ที่คอมไพล์เป็น Binary ทำงานเป็น HTTP Server รับ Request จาก Browser และตอบกลับด้วย JSON หรือ HTML

```
Port 8080 (FreePascal HTTP Server)
├── GET  /                         → หน้า Login HTML
├── POST /auth/login               → ตรวจสอบ Username/Password กับ Radius
├── GET  /auth/thaid               → Redirect ไปยัง ThaID OAuth
├── GET  /auth/thaid/callback      → รับ Token จาก ThaID
├── GET  /auth/providerid          → Redirect ไปยัง MOPH ID OAuth
├── GET  /auth/providerid/callback → รับ Token จาก ProviderID
├── GET  /auth/google              → Redirect ไปยัง Google OAuth
├── GET  /auth/google/callback     → รับ Token จาก Google
└── GET  /fortigate/handshake      → ส่ง Credentials ให้ FortiGate
```

### ส่วนที่ 2: Static HTML Frontend

หน้า Login ยังคงใช้ HTML/CSS/JavaScript ที่มีอยู่แล้วโดยไม่ต้องเปลี่ยนแปลง เปลี่ยนแค่ปลายทางของ Form Action ให้ชี้ไปยัง FreePascal Server แทน

---

## โครงสร้างโปรเจกต์ (Project Structure)

```
/var/www/fpsso/
├── fpsso.lpr              ← Main Program (Entry Point)
├── fpsso.lpi              ← Lazarus Project File
├── src/
│   ├── HttpServer.pas     ← HTTP Server (ใช้ fphttpserver unit)
│   ├── Router.pas         ← URL Routing
│   ├── Config.pas         ← อ่านค่าจาก .env
│   ├── RadiusDB.pas       ← เชื่อมต่อ MySQL (Radius Database)
│   ├── SessionMgr.pas     ← จัดการ Session (ผ่าน Cookie)
│   ├── AuthLocal.pas      ← ตรวจสอบ Username/Password
│   ├── AuthThaiD.pas      ← ThaID OAuth Flow
│   ├── AuthProviderID.pas ← ProviderID/MOPH ID OAuth Flow
│   ├── AuthGoogle.pas     ← Google OAuth 2.0 Flow (สำรองไว้ก่อน)
│   └── FortiGate.pas      ← FortiGate Handshake Logic
└── templates/
    ├── login.html         ← หน้า Login (ย้ายมาจากเดิม)
    └── fortigate.html     ← หน้า FortiGate Handshake (ย้ายมาจากเดิม)
```

---

## เทคโนโลยีที่จะใช้ใน FreePascal

| ฟีเจอร์ | Unit / Library |
|---|---|
| HTTP Server | `fphttpserver` (มาพร้อมกับ FPC) |
| HTTP Client (เรียก API ภายนอก) | `fphttpclient` (มาพร้อมกับ FPC) |
| JSON Parsing | `fpjson` + `jsonparser` |
| MySQL Connection | `sqldb` + `mysql8conn` |
| SSL/HTTPS (สำหรับ HTTP Client) | `openssl` |
| อ่าน .env / ini File | Custom Key=Value Parser |
| Base64 Encoding | `base64` |
| URL Encoding | `uriparser` |

---

## แผนการพัฒนาแบบ Phase (Development Plan)

### Phase 1: Core Infrastructure

ตั้งค่าโครงสร้างโปรเจกต์และสร้างส่วนหลักที่ทุก Module ต้องใช้

**ไฟล์ที่จะสร้าง:**
- **`Config.pas`** — อ่านไฟล์ `.env` (Key=Value Parser) เก็บค่าใน Record/Global Variable
- **`HttpServer.pas`** — สร้าง HTTP Server ด้วย `TFPHttpServer` กำหนด Handler หลัก
- **`Router.pas`** — จับคู่ URL Path + Method กับ Handler Function
- **`SessionMgr.pas`** — จัดการ Session ผ่าน Cookie (สร้าง/อ่าน/ลบ Session Token จาก Memory หรือไฟล์)
- **`fpsso.lpr`** — Entry Point โหลด Config และเริ่มต้น Server

---

### Phase 2: Database และ Local Authentication

เชื่อมต่อฐานข้อมูล Radius MySQL และสร้างระบบตรวจสอบ User/Password

**ไฟล์ที่จะสร้าง:**
- **`RadiusDB.pas`** — เชื่อมต่อ MySQL ด้วย `sqldb` + `mysql8conn` มีฟังก์ชัน:
  - `CheckUserPassword(username, password)` — ตรวจสอบกับตาราง `radcheck`
  - `GetOrCreateRadiusUser(username)` — ดึงหรือสร้าง tmp_passwd จาก `radcheck_mirror`
- **`AuthLocal.pas`** — Handler สำหรับ `POST /auth/login` ตรวจสอบ Credentials แล้วสร้าง Session

**Logic เดียวกับ `radius_auth.php` เดิม:**
```
CheckUserPassword → ถ้าตรง → GetOrCreateRadiusUser → สร้าง Session → Redirect FortiGate
```

---

### Phase 3: OAuth Modules

สร้าง OAuth 2.0 Flow ครบสำหรับแต่ละ Provider

**ไฟล์ที่จะสร้าง:**

#### `AuthThaiD.pas` (ThaID OAuth)
- `HandleThaiDLogin` — สร้าง Redirect URL ไปยัง ThaID พร้อม state parameter
- `HandleThaiDCallback` — รับ code → แลก Token → ดึงข้อมูล cid, ชื่อ, ที่อยู่ → Radius Auth → Session

#### `AuthProviderID.pas` (MOPH ID / ProviderID)
- `HandleProviderIDLogin` — สร้าง Redirect URL ไปยัง MOPH ID
- `HandleProviderIDCallback` — รับ code → แลก MOPH Token → ใช้แลก ProviderID Token → ดึง Profile → Radius Auth → Session

#### `AuthGoogle.pas` (Google OAuth — สำรองไว้)
- เขียน Skeleton ไว้ก่อน ยังไม่เปิดใช้งาน

---

### Phase 4: FortiGate Integration

สร้างหน้า Handshake ที่ส่ง Credentials จากระบบไปยัง FortiGate Captive Portal

**ไฟล์ที่จะสร้าง:**
- **`FortiGate.pas`** — Handler สำหรับ `GET /fortigate/handshake` ดึงข้อมูล username/password จาก Session แล้วเรนเดอร์ HTML Form ที่ Auto-Submit ไปยัง FortiGate URL

---

### Phase 5: Testing และ Deploy

- Compile เป็น Binary และทดสอบการทำงานในแต่ละ Endpoint
- สร้าง Systemd Service (`fpsso.service`) ให้รันอัตโนมัติเมื่อเปิดเครื่อง
- ตั้งค่า Apache Reverse Proxy ให้ Forward Traffic ไปยัง FreePascal Server (Port 8080)

---

## การตั้งค่า Apache Reverse Proxy (Apache Proxy Configuration)

ระบบนี้ใช้ Apache 2.4.58 บน Ubuntu และมี Virtual Host สำหรับ `api1.kpo.go.th` อยู่แล้วที่ไฟล์:
`/etc/apache2/sites-available/api1-kpo.conf`

### โครงสร้างการทำงานที่ต้องการ

```
                   ┌───────────────────────────────────────┐
 Browser           │           Apache 2.4 (Port 443 HTTPS) │
 ──────────────►   │   ServerName: api1.kpo.go.th          │
                   │   SSL: /var/www/ssl-cert/ssl.cer       │
                   └──────────────────┬────────────────────┘
                                      │
                        ┌─────────────┴──────────────┐
                        │                            │
                        ▼                            ▼
             Path: /sso/*                  Path: /php/* (เดิม)
          ┌──────────────────┐          ┌──────────────────┐
          │  FreePascal App  │          │  /var/www/api/   │
          │  localhost:8080  │          │  (PHP Files)     │
          └──────────────────┘          └──────────────────┘
```

### ขั้นตอนการตั้งค่า

#### ขั้นตอนที่ 1: เปิดใช้งาน Apache Modules ที่จำเป็น

```bash
# เปิด Proxy modules
sudo a2enmod proxy
sudo a2enmod proxy_http
sudo a2enmod proxy_wstunnel  # สำหรับ WebSocket (ถ้าจำเป็น)
sudo a2enmod headers          # สำหรับ Forward Headers

# Restart Apache
sudo systemctl restart apache2
```

#### ขั้นตอนที่ 2: แก้ไขไฟล์ Apache VirtualHost

แก้ไขไฟล์ `/etc/apache2/sites-available/api1-kpo.conf` โดยเพิ่มส่วน Proxy ใน VirtualHost port 443 (HTTPS):

```apache
<VirtualHost *:80>
    ServerName api1.kpo.go.th
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/api

    # Redirect HTTP to HTTPS
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)$ https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]

    <Directory /var/www/api>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/api1-kpo_error.log
    CustomLog ${APACHE_LOG_DIR}/api1-kpo_access.log combined
</VirtualHost>

<VirtualHost *:443>
    ServerName api1.kpo.go.th
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/api

    <Directory /var/www/api>
        AllowOverride All
        Require all granted
    </Directory>

    # === Reverse Proxy สำหรับ FreePascal SSO Server ===
    # Forward ทุก Request ที่เริ่มต้นด้วย /sso/ ไปยัง FreePascal (Port 8080)
    ProxyPreserveHost On

    # Forward Headers จริงของผู้ใช้ไปให้ FreePascal ด้วย
    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Forwarded-Host "api1.kpo.go.th"

    # Route: /sso/* → FreePascal HTTP Server
    ProxyPass        /sso/  http://127.0.0.1:8080/  timeout=60
    ProxyPassReverse /sso/  http://127.0.0.1:8080/

    # ไม่ให้ส่ง Request ที่เป็น PHP ไปยัง FreePascal
    ProxyPassMatch ^/(?!sso/) !

    # SSL Configuration
    SSLEngine on
    SSLCertificateFile      /var/www/ssl-cert/ssl.cer
    SSLCertificateKeyFile   /var/www/ssl-cert/ssl.key
    SSLCertificateChainFile /var/www/ssl-cert/ssl.ca

    ErrorLog  ${APACHE_LOG_DIR}/api1-kpo_error.log
    CustomLog ${APACHE_LOG_DIR}/api1-kpo_access.log combined
</VirtualHost>
```

#### ขั้นตอนที่ 3: สร้าง Systemd Service สำหรับ FreePascal

สร้างไฟล์ `/etc/systemd/system/fpsso.service`:

```ini
[Unit]
Description=FreePascal SSO HTTP Server
After=network.target mysql.service

[Service]
Type=simple
User=www-data
WorkingDirectory=/var/www/fpsso
ExecStart=/var/www/fpsso/fpsso
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

คำสั่งเปิดใช้งาน Service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable fpsso
sudo systemctl start fpsso
sudo systemctl status fpsso
```

#### ขั้นตอนที่ 4: ทดสอบและ Reload Apache

```bash
# ตรวจสอบ Config ว่าถูกต้อง
sudo apache2ctl configtest

# Reload Apache (ไม่ต้อง Restart)
sudo systemctl reload apache2
```

---

### URL Mapping หลังจาก Deploy

| URL (HTTPS) | ปลายทาง | หมายเหตุ |
|---|---|---|
| `https://api1.kpo.go.th/sso/` | FreePascal Port 8080 | หน้า Login ใหม่ |
| `https://api1.kpo.go.th/sso/auth/login` | FreePascal Port 8080 | POST Login |
| `https://api1.kpo.go.th/sso/auth/thaid` | FreePascal Port 8080 | ThaID OAuth |
| `https://api1.kpo.go.th/sso/auth/thaid/callback` | FreePascal Port 8080 | ThaID Callback |
| `https://api1.kpo.go.th/sso/auth/providerid` | FreePascal Port 8080 | ProviderID OAuth |
| `https://api1.kpo.go.th/sso/fortigate/handshake` | FreePascal Port 8080 | FortiGate Submit |
| `https://api1.kpo.go.th/login.php` | PHP `/var/www/api/` | ระบบเดิม (ยังใช้ได้) |

---

### ข้อดีของการใช้ Apache เป็น Reverse Proxy

| ด้าน | รายละเอียด |
|---|---|
| **SSL จัดการที่ Apache** | FreePascal ไม่ต้องจัดการ HTTPS เอง ทำงานได้บน HTTP ธรรมดา (localhost) |
| **ใช้ Certificate เดิมได้เลย** | ไฟล์ ssl.cer / ssl.key / ssl.ca ที่มีอยู่แล้วยังใช้ได้ทันที |
| **ระบบเดิม PHP ยังทำงานได้** | PHP Files ใน `/var/www/api/` ยังเข้าถึงได้ตามปกติ ไม่ถูกรบกวน |
| **Session Cookie Secure** | Apache ส่งผ่าน HTTPS ทำให้ Session Cookie ของ FreePascal มี Secure Flag อัตโนมัติ |
| **Log รวมที่เดียว** | Apache Access Log บันทึก Request ทั้ง PHP และ FreePascal ไว้ที่ไฟล์เดียวกัน |

---

## ตารางเปรียบเทียบไฟล์เดิม vs ไฟล์ใหม่

| ไฟล์ PHP เดิม | Unit FreePascal ใหม่ |
|---|---|
| `security_config.php` | `HttpServer.pas` + `SessionMgr.pas` |
| `login.php` | `AuthLocal.pas` + `templates/login.html` |
| `radius_auth.php` | `RadiusDB.pas` |
| `thaid_api.php` | `AuthThaiD.pas` |
| `providerid_api.php` | `AuthProviderID.pas` |
| `google_api.php` | `AuthGoogle.pas` (สำรอง) |
| `fortigate_handshake.php` | `FortiGate.pas` |
| `index.php` | `Router.pas` + `templates/login.html` |
| `.env` | ยังคงใช้ไฟล์เดิม (Config.pas อ่านเอง) |

---

## ข้อควรพิจารณา

> **HTTPS**: FreePascal HTTP Server ไม่ต้องจัดการ SSL เอง เพราะ Apache รับ HTTPS ด้านหน้าแล้วส่งต่อเป็น HTTP ธรรมดาไปยัง FreePascal บน localhost:8080

> **Session Management**: PHP มี Session ในตัว ส่วน Pascal ต้องเขียน Custom Session Store (แนะนำใช้ In-Memory Dictionary + Cookie Token)

> **OAuth Redirect URI**: ตัวแปร `THAID_REDIRECT_URI`, `PROVIDER_ID_REDIRECT_URI` ใน `.env` จะต้องเปลี่ยนเป็น URL ที่ชี้ไปยัง FreePascal Endpoint เช่น `https://api1.kpo.go.th/sso/auth/thaid/callback`

> **OAuth State Parameter**: ต้องจัดการ CSRF State Token สำหรับทุก OAuth Flow เพื่อป้องกัน CSRF Attack

> **FortiGate**: หน้า Handshake ยังต้องการการส่ง HTTP POST จากฝั่ง Browser (Client-side) เหมือนเดิม เพียงแค่เปลี่ยนหน้าที่เรนเดอร์ HTML

---

## ลำดับการทำงานแนะนำ

```
Phase 1  →  Core (HttpServer + Router + Config + Session)
Phase 2  →  Database (RadiusDB + AuthLocal)
Phase 3  →  OAuth Modules (ThaID → ProviderID)
Phase 4  →  FortiGate Integration
Phase 5  →  Testing + Deploy (a2enmod proxy + แก้ api1-kpo.conf + Systemd)
```
