# คู่มือการติดตั้งระบบ FreePascal SSO (fpsso) สำหรับเซิร์ฟเวอร์ใหม่

คู่มือนี้สรุปขั้นตอนตั้งแต่เริ่มต้นจนจบ สำหรับนำระบบ Web Application SSO ที่เขียนด้วย FreePascal ไปติดตั้งและรันบนเซิร์ฟเวอร์ Linux (Ubuntu/Debian) เครื่องอื่นด้วยตัวเองครับ

---

## 1. การเตรียมความพร้อมของ Server (Prerequisites)

ติดตั้งแพ็กเกจที่จำเป็นสำหรับการคอมไพล์และรันระบบ:

```bash
sudo apt-get update
# ติดตั้ง FreePascal Compiler
sudo apt-get install fpc

# ติดตั้งไลบรารี MySQL/MariaDB เพื่อให้ Pascal คุยกับ Database ได้
sudo apt-get install libmysqlclient-dev

# ติดตั้ง Apache2 (หากยังไม่มี)
sudo apt-get install apache2
```

## 2. การคัดลอกไฟล์และตั้งค่าโปรเจกต์

นำโฟลเดอร์โปรเจกต์ไปวางไว้ใน Server แนะนำให้วางไว้ที่ `/var/www/api/freepascal/fpsso/` หรือ path ที่คุณต้องการ (หากเปลี่ยน path จะต้องไปแก้พาทในไฟล์อื่นๆ ด้วย)

โครงสร้างโฟลเดอร์ที่จำเป็นต้องมี:
```
/var/www/api/freepascal/fpsso/
├── fpsso.lpr          # Main Source Code
├── src/               # Source Modules (Config, SessionMgr, Router, HttpServer, Auth*, etc.)
└── templates/         # HTML Templates (login.html)
```

สร้างไฟล์ตั้งค่า `.env` (ตัวอย่างเก็บไว้ที่ `/var/www/api/.env`):
```env
DB_HOST=127.0.0.1
DB_USER=root
DB_PASS=your_password
DB_NAME=radius

THAID_CLIENT_ID=your_client_id
THAID_SECRET_ID=your_secret
THAID_REDIRECT_URI=https://yourdomain.com/sso/auth/thaid/callback
THAID_URL_TOKEN=https://imauth.bora.dopa.go.th/api/v2/oauth2/token/
THAID_URL_AUTH=https://imauth.bora.dopa.go.th/api/v2/oauth2/auth/
THAID_SCOPE=pid name address

PROVIDER_ID_CLIENT_ID=your_client_id
PROVIDER_ID_SECRET_KEY=your_secret
PROVIDER_ID_REDIRECT_URI=https://yourdomain.com/sso/auth/providerid/callback
PROVIDER_ID_URL=https://provider.id.th

FORTIGATE_AUTH_URL=http://192.168.1.1:1000/fgtauth
```

## 3. การคอมไพล์โปรแกรม (Compile)

เข้าไปยังโฟลเดอร์โปรเจกต์ และสั่งคอมไพล์โค้ดให้เป็น Binary (`fpsso`):

```bash
cd /var/www/api/freepascal/fpsso/
fpc -O3 -Xs -XX -CX -Fu./src -Fi./src fpsso.lpr
```
*หลังจากรันคำสั่งนี้ คุณจะได้ไฟล์ `fpsso` (Executable Binary) สีเขียวๆ โผล่ขึ้นมา*

## 4. ตั้งค่าให้ทำงานเป็น Background Service (Systemd)

เพื่อให้โปรแกรมทำงานตลอดเวลา และเปิดตัวเองทุกครั้งที่บูตเครื่อง ให้สร้างไฟล์ Service:

```bash
sudo nano /etc/systemd/system/fpsso.service
```

นำโค้ดนี้ไปใส่ (ถ้าเปลี่ยนพาทโปรเจกต์ อย่าลืมแก้ `WorkingDirectory` และ `ExecStart`):
```ini
[Unit]
Description=FreePascal SSO HTTP Server
After=network.target mysql.service

[Service]
Type=simple
User=root
WorkingDirectory=/var/www/api/freepascal/fpsso
ExecStart=/var/www/api/freepascal/fpsso/fpsso
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

เปิดใช้งาน Service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable fpsso
sudo systemctl start fpsso
sudo systemctl status fpsso  # เช็คว่าขึ้น Active (running) หรือไม่
```

## 5. การตั้งค่า Apache Reverse Proxy

เปิดการใช้งาน Proxy Modules ของ Apache:
```bash
sudo a2enmod proxy proxy_http headers
```

ไปแก้ไขไฟล์ VirtualHost ของคุณ (เช่น `/etc/apache2/sites-available/your-domain.conf`)
แทรกการตั้งค่านี้เข้าไปใน `<VirtualHost *:443>` ก่อนบรรทัด `SSLEngine on`:

```apache
    # === Reverse Proxy สำหรับ FreePascal SSO Server ===
    ProxyPreserveHost On
    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Forwarded-Host "yourdomain.com"
    
    # ส่งทราฟฟิก /sso/ ทั้งหมดไปให้ FreePascal ที่รันอยู่พอร์ต 8080
    ProxyPass /sso/ http://127.0.0.1:8080/ timeout=60
    ProxyPassReverse /sso/ http://127.0.0.1:8080/
```

บันทึกไฟล์และ Reload Apache:
```bash
sudo apache2ctl configtest   # เช็ค Syntax ว่าถูกต้องไหม (ต้องขึ้น Syntax OK)
sudo systemctl reload apache2
```

---

> [!TIP]
> **การตรวจสอบและการแก้ปัญหา (Troubleshooting)**
> - ดู Log ของโปรแกรม fpsso แบบเรียลไทม์: `sudo journalctl -u fpsso -f`
> - ตรวจสอบว่าพอร์ต 8080 ถูกเปิดใช้งานอยู่หรือไม่: `sudo netstat -tlnp | grep 8080`
> - หากคอมไพล์แล้วติด Error ไลบรารี มักเกิดจาก OS นั้นๆ หา `libmysqlclient` ไม่เจอ ให้เช็คการเชื่อมต่อ Symlink ใน `/usr/lib/`
