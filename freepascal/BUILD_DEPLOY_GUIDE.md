# คู่มือการ Build และ Deploy ระบบ SSO (fpsso) และ RADIUS Proxy (fp-radius)

คู่มือนี้จะอธิบายขั้นตอนการสร้างแพ็กเกจการติดตั้ง (Build) เพื่อนำระบบไปติดตั้งและใช้งานบนเครื่องเซิร์ฟเวอร์ปลายทาง โดย**ไม่ต้องนำ Source Code ไปด้วย** (เพื่อความปลอดภัยและง่ายต่อการติดตั้ง)

---

## สรุปภาพรวม
ระบบประกอบด้วย 2 เซอร์วิสหลัก:
1. **fpsso:** ระบบหน้าเว็บ Login และตรวจสอบสิทธิ์ผ่านช่องทางต่างๆ (Local, ThaID, ProviderID, Google)
2. **fp-radius:** ระบบรับส่งและแปลงข้อมูล RADIUS ให้คุยกับ FortiGate

ทั้งสองโฟลเดอร์มีสคริปต์ชื่อ `build_package.sh` เตรียมไว้ให้แล้ว ซึ่งจะทำหน้าที่:
- Compile โค้ดภาษา Pascal ให้เป็นไฟล์ Executable (.exe / binary) ด้วยโหมดรีดประสิทธิภาพสูงสุด (Release mode)
- รวบรวมไฟล์ที่จำเป็นทั้งหมด เช่น ไฟล์รัน, เทมเพลต, ไฟล์ Service และตัวอย่างคอนฟิก
- บีบอัดเป็นไฟล์ `.tar.gz` หนึ่งไฟล์เพื่อให้ง่ายต่อการดาวน์โหลดหรือส่งต่อไปยังเครื่องปลายทาง

---

## ขั้นตอนที่ 1: การสร้างแพ็กเกจ (Build) ที่เครื่องนักพัฒนา

### 1. Build แพ็กเกจของระบบ SSO (`fpsso`)
1. เข้าไปยังโฟลเดอร์ `fpsso`
   ```bash
   cd /var/www/api/freepascal/fpsso
   ```
2. รันสคริปต์สร้างแพ็กเกจ
   ```bash
   ./build_package.sh
   ```
3. เมื่อเสร็จสิ้น คุณจะได้ไฟล์ชื่อ **`fpsso_package.tar.gz`**

### 2. Build แพ็กเกจของระบบ RADIUS (`fp-radius`)
1. เข้าไปยังโฟลเดอร์ `fp-radius`
   ```bash
   cd /var/www/api/freepascal/fp-radius
   ```
2. รันสคริปต์สร้างแพ็กเกจ
   ```bash
   ./build_package.sh
   ```
3. เมื่อเสร็จสิ้น คุณจะได้ไฟล์ชื่อ **`fpradius_package.tar.gz`**

นำไฟล์ `.tar.gz` ทั้งสองไฟล์นี้ ส่งไปยังเครื่องเซิร์ฟเวอร์ปลายทาง (เช่น ผ่าน WinSCP หรือ SFTP)

---

## ขั้นตอนที่ 2: การติดตั้งและใช้งาน (Deploy) ที่เครื่องปลายทาง

เมื่อนำไฟล์ `.tar.gz` ทั้งสองไฟล์มาไว้บนเครื่องเซิร์ฟเวอร์ปลายทางแล้ว ให้ทำตามขั้นตอนต่อไปนี้ (ขอแนะนำให้ติดตั้งไว้ที่โฟลเดอร์ `/opt/` หรือ `/var/www/`)

### 1. ติดตั้งระบบ SSO (`fpsso`)
1. สร้างโฟลเดอร์และแตกไฟล์
   ```bash
   sudo mkdir -p /var/www/fpsso
   sudo tar -xzvf fpsso_package.tar.gz -C /var/www/fpsso/
   cd /var/www/fpsso
   ```
2. คัดลอกและตั้งค่าคอนฟิก (ใส่ค่ารหัสผ่านและ API ภายในบริษัทคุณ)
   ```bash
   cp .env.example .env
   nano .env
   ```
3. ติดตั้ง Systemd Service และสั่งรันระบบ
   ```bash
   sudo cp fpsso.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable fpsso
   sudo systemctl start fpsso
   ```

### 2. ติดตั้งระบบ RADIUS (`fp-radius`)
1. สร้างโฟลเดอร์และแตกไฟล์
   ```bash
   sudo mkdir -p /var/www/fp-radius
   sudo tar -xzvf fpradius_package.tar.gz -C /var/www/fp-radius/
   cd /var/www/fp-radius
   ```
2. คัดลอกและตั้งค่าคอนฟิก
   ```bash
   cp .env.example .env
   nano .env
   ```
3. ติดตั้ง Systemd Service และสั่งรันระบบ
   ```bash
   sudo cp fpradius.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable fpradius
   sudo systemctl start fpradius
   ```

---

## การตรวจสอบสถานะการทำงาน (Troubleshooting)

หากระบบทำงานผิดปกติ สามารถเช็คดู Log การทำงานแบบ Real-time ได้ด้วยคำสั่ง:

- ดู Log ของ fpsso:
  ```bash
  sudo journalctl -u fpsso -f
  ```
- ดู Log ของ fp-radius:
  ```bash
  sudo journalctl -u fpradius -f
  ```

> **ข้อแนะนำ:** หากมีการปรับปรุงโค้ดหรือหน้าตาเว็บ (templates) ให้กลับไปรัน `./build_package.sh` ที่เครื่องพัฒนา และนำไฟล์ `.tar.gz` ใหม่มาเขียนทับที่เครื่องปลายทาง แล้วสั่ง `sudo systemctl restart fpsso` (หรือ `fpradius`) ก็จะเป็นการอัปเดตระบบให้ทันสมัยเรียบร้อยครับ
