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

# (Optional) กำหนด Path ของไฟล์ login.html หากต้องการปรับแต่งหน้าเว็บเอง
LOGIN_TEMPLATE_PATH=/var/www/api/freepascal/fpsso/templates/login.html

# SSO Auto Approve Feature
# set to true: ล็อกอินผ่าน SSO แล้วใช้อินเทอร์เน็ตได้เลยทันที
# set to false: แอดมินต้องเข้าไปอนุมัติบัญชีใหม่ก่อนจึงจะใช้งานได้
SSO_AUTO_APPROVE=false
APP_PORT=8080
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

## 5. การตั้งค่าหน้าเว็บ Login และไฟล์ประกอบ (Static Assets)
โปรแกรมจะมีหน้าตาเว็บ Login สวยงาม (มี Font Sarabun แบบ Offline และรูปภาพ) 
หากคุณนำโปรแกรมไปติดตั้งที่เครื่องใหม่ ให้ทำตามขั้นตอนนี้ด้วยเพื่อให้หน้าเว็บแสดงผลได้สมบูรณ์:

1. หน้าเว็บ `login.html` จะถูกเรียกใช้งานจากโฟลเดอร์ `templates/login_template/` ที่อยู่ภายในโฟลเดอร์โปรแกรม `fpsso` (เช่น `/var/www/api/freepascal/fpsso/templates/login_template/login.html`)
2. โฟลเดอร์ย่อยข้างในอย่าง `assets` และ `images` (ที่มีไฟล์ CSS, Font และรูปภาพ) ให้นำไปวางไว้ที่ **Web Document Root** ของ Web Server (Apache/Nginx) ของคุณ
   เช่น นำไปวางที่ `/var/www/html/assets` และ `/var/www/html/images`
   เพื่อให้เบราว์เซอร์สามารถดาวน์โหลดไฟล์รูปภาพและ Font ผ่านทาง Root URL (`https://your-domain.com/images/...`) ได้โดยตรง

## 6. การตั้งค่า Apache Reverse Proxy

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
</VirtualHost>
```

บันทึกไฟล์และ Reload Apache:
```bash
sudo apache2ctl configtest   # เช็ค Syntax ว่าถูกต้องไหม (ต้องขึ้น Syntax OK)
sudo systemctl reload apache2
```

---

## 7. การตั้งค่าความปลอดภัย SSL (HTTPS)

ระบบ `fpsso` ถูกออกแบบมาให้ทำงานอยู่หลัง Web Server ภายนอก ดังนั้นวิธีที่ดีที่สุดและปลอดภัยที่สุดคือการให้ Apache หรือ Nginx ทำหน้าที่เข้ารหัส SSL แทน (เรียกว่า "SSL Termination") ส่วนตัว `fpsso` จะคอยรับข้อมูลผ่าน HTTP พอร์ตธรรมดาจาก Apache ภายในเครื่องเดียวกันเท่านั้น

คุณสามารถเลือกใช้วิธีใดวิธีหนึ่งตามความเหมาะสมของเซิร์ฟเวอร์คุณ:

### วิธีที่ 1: ใช้ Let's Encrypt (ฟรีและต่ออายุอัตโนมัติ)
หากเซิร์ฟเวอร์ของคุณมี Domain Name ชี้มาเรียบร้อยแล้ว แนะนำให้ใช้ **Let's Encrypt (Certbot)** 

**เงื่อนไขที่ต้องมีก่อนทำ:**
- เซิร์ฟเวอร์ต้องเปิดพอร์ต 80 (HTTP) และ 443 (HTTPS) จากภายนอก
- ต้องจดโดเมนและชี้ A Record มาที่ IP ของเซิร์ฟเวอร์เรียบร้อยแล้ว (ตัวอย่าง: `sso.yourdomain.com`)

**ขั้นตอนการขอ Certificate:**
1. ติดตั้ง Certbot และปลั๊กอินสำหรับ Apache:
   ```bash
   sudo apt update
   sudo apt install certbot python3-certbot-apache -y
   ```

2. สั่งรันคำสั่งขอ Certificate และให้มันตั้งค่า Apache อัตโนมัติ:
   ```bash
   sudo certbot --apache -d sso.yourdomain.com
   ```

3. ระบบจะถามคำถามสั้นๆ ให้ทำตามนี้:
   - **Enter email address:** ใส่อีเมลของคุณเพื่อรับการแจ้งเตือน
   - **Please read the Terms of Service...:** พิมพ์ `Y` เพื่อยอมรับเงื่อนไข
   - **Would you be willing...:** พิมพ์ `N` หรือ `Y` ก็ได้ (เกี่ยวกับการส่งอีเมลโฆษณา)
   - หากสำเร็จ ระบบจะตั้งค่าไฟล์ VirtualHost ให้มี SSL และสั่ง Reload Apache ทันที

4. (ตัวเลือกเสริม) ตรวจสอบว่าระบบตั้งเวลาต่ออายุ Certificate ให้อัตโนมัติแล้วหรือยัง:
   ```bash
   sudo systemctl status certbot.timer
   ```

### วิธีที่ 2: นำใบรับรอง (Certificate) มาติดตั้งเอง
หากคุณซื้อ Certificate จากผู้ให้บริการ หรือหน่วยงานมีไฟล์ `.cer`, `.crt`, `.key` ให้มาอยู่แล้ว ให้แก้ไขไฟล์ VirtualHost ด้วยตัวเองดังนี้:

1. นำไฟล์ใบรับรองไปวางไว้ในโฟลเดอร์ที่ปลอดภัยบนเซิร์ฟเวอร์ เช่น `/var/www/ssl-cert/`
2. สร้างหรือแก้ไขไฟล์ VirtualHost (เช่น `/etc/apache2/sites-available/your-domain-ssl.conf`)
3. เพิ่มบล็อกสำหรับพอร์ต 443 ตามตัวอย่าง:
```apache
<VirtualHost *:443>
    ServerName yourdomain.com
    
    # เปิดใช้งาน SSL และระบุตำแหน่งไฟล์ Certificate
    SSLEngine on
    SSLCertificateFile /var/www/ssl-cert/ssl.cer
    SSLCertificateKeyFile /var/www/ssl-cert/ssl.key
    SSLCertificateChainFile /var/www/ssl-cert/ssl.ca
    
    # === Reverse Proxy สำหรับ FreePascal SSO Server ===
    ProxyPreserveHost On
    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Forwarded-Host "yourdomain.com"
    ProxyPass /sso/ http://127.0.0.1:8080/ timeout=60
    ProxyPassReverse /sso/ http://127.0.0.1:8080/
</VirtualHost>
```
4. เปิดการใช้งานไซต์และโหลด Apache ใหม่:
```bash
sudo a2ensite your-domain-ssl.conf
sudo systemctl reload apache2
```

> **หมายเหตุสำคัญ:** การ Login ผ่านระบบ ThaID และ ProviderID จำเป็นจะต้องให้ URL ที่เรียกเข้ามาเป็น HTTPS เท่านั้น การตั้งค่าด้วยวิธีใดวิธีหนึ่งร่วมกับคำสั่ง `RequestHeader set X-Forwarded-Proto "https"` ใน Apache จะทำให้ระบบส่งค่าให้ fpsso ทราบว่าการเชื่อมต่อมีความปลอดภัยสมบูรณ์

---

## 8. การตั้งค่าระบบที่เครื่อง FortiGate (Captive Portal)

เพื่อให้ผู้ใช้งานที่เชื่อมต่อเครือข่ายถูกส่งมาบังคับล็อกอินที่หน้าเว็บ `fpsso` ของเรา ให้ดำเนินการตั้งค่าที่ FortiGate ดังนี้:

1. ล็อกอินเข้าสู่หน้าแอดมินของ **FortiGate**
2. ไปที่เมนู **Network > Interfaces**
3. เลือกขา Interface ที่ต้องการให้ผู้ใช้งานต้องล็อกอิน (เช่น ขา LAN หรือ Wi-Fi) แล้วกด **Edit**
4. เลื่อนลงมาในส่วนของ Security Mode ให้เปิดสวิตช์ **Captive Portal**
5. เลือก **Authentication Portal** เป็น **External**
6. ในช่อง **URL** ให้กรอกที่อยู่ของระบบ SSO ของเรา เช่น:
   ```text
   https://api1.kpo.go.th/sso/
   ```
7. (ข้อควรระวัง) ตรวจสอบให้แน่ใจว่าเครื่องผู้ใช้งาน (Client) สามารถเข้าถึงโดเมน `api1.kpo.go.th` และ `sso.moph.go.th` (สำหรับ ThaID) ได้ก่อนการล็อกอิน โดยอาจจะต้องตั้งค่า Walled Garden, Exempt Destination หรือเปิด Firewall Policy แบบจำกัดเอาไว้

เมื่อตั้งค่าเสร็จสิ้น เวลามีคนมาต่อ Wi-Fi และเปิดเบราว์เซอร์ เครื่อง FortiGate จะทำการ Redirect ทราฟฟิกส่งมาที่หน้า `/sso/` พร้อมพ่วงค่าพารามิเตอร์ `?magic=...` มาด้วย ซึ่งระบบ `fpsso` ของเราจะจัดการต่อและปลดล็อกเน็ตให้โดยอัตโนมัติเมื่อล็อกอินผ่าน

### การสร้าง Walled Garden ผ่าน Firewall Policy (วิธีที่แนะนำ)

วิธีนี้ปลอดภัยและควบคุมพอร์ตได้ดีกว่าการใช้ Exempt Destination ธรรมดา เพราะเราสามารถจำกัดให้วิ่งไปหาเซิร์ฟเวอร์ SSO ได้เฉพาะพอร์ตที่จำเป็นจริงๆ (เช่น HTTP, HTTPS, DNS) และเป็นการทำ Walled Garden แบบมาตรฐานที่ใช้ได้กับ FortiOS ทุกเวอร์ชั่นครับ

**ขั้นตอนการทำ:**

1. **สร้าง Address Object แบบ FQDN** สำหรับโดเมนที่เกี่ยวข้องกับระบบ SSO และ OAuth ทั้งหมด โดยให้สร้างแยกเป็นแต่ละ Object ดังนี้:
   - `accounts.google.com` (สำหรับ Google SSO)
   - `oauth2.googleapis.com` (สำหรับ Google SSO)
   - `www.googleapis.com` (สำหรับ Google SSO)
   - `imauth.bora.dopa.go.th` (สำหรับ ThaID SSO)
   - `moph.id.th` (โดเมนหลักของระบบ MOPH)
   - `provider.id.th` (สำหรับ MOPH Provider ID)
   - `api1.kpo.go.th` (โดเมนของระบบ fpsso ที่เราติดตั้ง)

2. **สร้าง Address Group** (รวมกลุ่มเพื่อความสะดวก)
   - ไปที่ **Policy & Objects > Addresses**
   - คลิก **Create New > Address Group**
   - **Name:** ตั้งชื่อกลุ่ม เช่น `Walled_Garden_SSO`
   - **Members:** คลิก `+` แล้วเลือก FQDN ทั้งหมดที่สร้างไว้ใส่เข้ามา แล้วกด **OK**

3. **สร้าง Firewall Policy ชุดพิเศษ**
   - ไปที่เมนู **Policy & Objects > Firewall Policy**
   - คลิก **Create New**
   - **Name:** ตั้งชื่อ เช่น `Walled_Garden_Permit`
   - **Incoming Interface:** เลือกขาที่ทำ Captive Portal (เช่น LANSTAFF)
   - **Outgoing Interface:** เลือกขาที่ออกอินเทอร์เน็ต (เช่น wan1)
   - **Source:** เลือก **all** *(ห้ามใส่ User Group ใน Policy นี้เด็ดขาด)*
   - **Destination:** เลือกกลุ่ม `Walled_Garden_SSO` ที่เราสร้างไว้ในข้อ 2
   - **Service:** เลือกบริการที่จำเป็น ได้แก่ **DNS** *(สำคัญที่สุด เพราะถ้าเครื่อง Client resolve IP ของเว็บไม่ได้ จะเข้าหน้าล็อกอินไม่ได้เลย)*, **HTTP**, และ **HTTPS**
   - **Action:** เลือก **ACCEPT**
   - เปิดใช้งาน **NAT**
   - กด **OK**

4. **จัดลำดับ Policy (CRITICAL!)**
   - เมื่อกดบันทึกแล้ว ให้ไปที่หน้า Firewall Policy
   - ทำการลาก (Drag & Drop) ให้ Policy `Walled_Garden_Permit` นี้ ขึ้นไปอยู่ด้านบนสุด (หรืออย่างน้อยต้องอยู่สูงกว่า Policy หลักที่ใช้เล่นอินเทอร์เน็ตตัวที่มีการผูก User Group เอาไว้)

---

## 9. การตั้งค่า FortiGate ให้ส่งรายงานการใช้งาน (RADIUS Accounting / Traffic In-Out)

ระบบมีฐานข้อมูล `radacct` สำหรับเก็บประวัติและปริมาณแบนด์วิดท์ (Traffic) ของผู้ใช้งาน หากต้องการให้ FortiGate อัปเดตข้อมูลปริมาณการดาวน์โหลด/อัปโหลดระหว่างที่ผู้ใช้กำลังเชื่อมต่ออยู่ (Interim-Update) แทนที่จะส่งแค่ตอนเริ่มและตอนจบ สามารถตั้งค่าผ่าน Command Line ของ FortiGate ได้ดังนี้:

```text
config user radius
    edit "ชื่อ_Radius_Server_ของคุณ"
        set radius-port 1812
        set acct-interim-interval 600
    next
end
```
*(ค่า `600` คือ 600 วินาที หมายถึงสั่งให้ FortiGate ส่งรายงาน Traffic อัปเดตมาให้ระบบทราบทุกๆ 10 นาที)*

---

> [!TIP]
> **การตรวจสอบและการแก้ปัญหา (Troubleshooting)**
> - ดู Log ของโปรแกรม fpsso แบบเรียลไทม์: `sudo journalctl -u fpsso -f`
> - ตรวจสอบว่าพอร์ต 8080 ถูกเปิดใช้งานอยู่หรือไม่: `sudo netstat -tlnp | grep 8080`
> - หากคอมไพล์แล้วติด Error ไลบรารี มักเกิดจาก OS นั้นๆ หา `libmysqlclient` ไม่เจอ ให้เช็คการเชื่อมต่อ Symlink ใน `/usr/lib/`
