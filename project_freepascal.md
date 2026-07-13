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

```apache
# ตัวอย่าง Apache Reverse Proxy Config
ProxyPass /fpsso/ http://localhost:8080/
ProxyPassReverse /fpsso/ http://localhost:8080/
```

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

> **HTTPS**: FreePascal HTTP Server ต้องการการตั้งค่า SSL Certificate เอง การใช้ Apache เป็น Reverse Proxy เพื่อจัดการ TLS ด้านหน้าจะง่ายและปลอดภัยกว่า

> **Session Management**: PHP มี Session ในตัว ส่วน Pascal ต้องเขียน Custom Session Store (แนะนำใช้ In-Memory Dictionary + Cookie Token)

> **OAuth State Parameter**: ต้องจัดการ CSRF State Token สำหรับทุก OAuth Flow เพื่อป้องกัน CSRF Attack

> **FortiGate**: หน้า Handshake ยังต้องการการส่ง HTTP POST จากฝั่ง Browser (Client-side) เหมือนเดิม เพียงแค่เปลี่ยนหน้าที่เรนเดอร์ HTML

---

## ลำดับการทำงานแนะนำ

```
Phase 1  →  Core (HttpServer + Router + Config + Session)
Phase 2  →  Database (RadiusDB + AuthLocal)
Phase 3  →  OAuth Modules (ThaID → ProviderID)
Phase 4  →  FortiGate Integration
Phase 5  →  Testing + Deploy
```
