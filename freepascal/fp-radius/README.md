# คู่มือการใช้งาน fp-radius (FreePascal RADIUS Server)

ก่อนรันโปรแกรม หรือตั้งค่า Service **จำเป็นต้องติดตั้ง MySQL Client Library** เพื่อให้ FreePascal สามารถเชื่อมต่อกับฐานข้อมูล MySQL ได้ โดยรันคำสั่ง:
```bash
sudo apt-get update
sudo apt-get install libmysqlclient-dev
```

---

## 1. คำสั่งย่อยและตัวเลือกการใช้งาน (CLI Options & Subcommands)

โปรแกรม `fpradius` มาพร้อมคำสั่งย่อย (CLI Flags) สำหรับช่วยตั้งค่าและจัดการระบบ ดังนี้:

### 1.1 คำสั่งช่วยเหลือ (Help)
```bash
./fpradius --help
# หรือ
./fpradius -h
```

### 1.2 Setup Wizard (ตัวช่วยตั้งค่าแบบโต้ตอบ)
ช่วยตั้งค่าไฟล์ `.env`, สร้าง/นำเข้าฐานข้อมูล และติดตั้ง Systemd Service ในขั้นตอนเดียว
```bash
sudo ./fpradius --setup-wizard
```

### 1.3 การเตรียมและสร้างฐานข้อมูล (--init-database)
สร้างฐานข้อมูลและนำเข้า Table Schema อัตโนมัติ (อ่านค่า DB จากไฟล์ `.env`)
```bash
./fpradius --init-database
```

### 1.4 การติดตั้ง Systemd Service อัตโนมัติ (--installservice)
สร้างไฟล์ Service, คัดลอกไป `/etc/systemd/system/fpradius.service`, reload daemon และสั่ง start อัตโนมัติ
```bash
sudo ./fpradius --installservice
```

### 1.5 การถอนติดตั้ง Systemd Service (--uninstallservice)
หยุดการทำงาน Disable Service และลบไฟล์ Service ออกจากระบบ
```bash
sudo ./fpradius --uninstallservice
```

---

## 2. การรันโปรแกรม

### 2.1 การรันแบบปกติผ่าน Command Line (เพื่อทดสอบ)
เหมาะสำหรับการรันเพื่อดู Log แบบสดๆ บนหน้าจอ

```bash
cd /var/www/api/freepascal/fp-radius/

# รันโดยระบุไฟล์ .env
./fpradius /var/www/api/.env

# หรือรันโดยไม่ระบุพาธไฟล์ .env (โปรแกรมจะหา .env ในโฟลเดอร์ปัจจุบัน หรือ /var/www/api/.env อัตโนมัติ)
./fpradius
```

### 2.2 การรันเป็น Background Service (สำหรับ Production)

หากไม่ได้ใช้คำสั่ง `sudo ./fpradius --installservice` สามารถติดตั้ง Service ด้วยตนเองได้ดังนี้:

#### ขั้นตอนการตั้งค่า Systemd ด้วยตนเอง
1. คัดลอกไฟล์เซอร์วิสไปยังระบบ:
```bash
sudo cp /var/www/api/freepascal/fp-radius/fpradius.service /etc/systemd/system/
```

2. โหลด Service ใหม่และเปิดใช้งาน:
```bash
sudo systemctl daemon-reload
sudo systemctl enable fpradius
sudo systemctl start fpradius
```

#### การตรวจสอบและการจัดการ (Systemctl)
* เช็คสถานะการทำงาน:
```bash
sudo systemctl status fpradius
```

* เริ่มระบบใหม่ (Restart):
```bash
sudo systemctl restart fpradius
```

* หยุดการทำงาน (Stop):
```bash
sudo systemctl stop fpradius
```

* ดู Log ย้อนหลังและแบบ Real-time:
```bash
sudo journalctl -u fpradius -f
```

---

## 3. การตั้งค่า Firewall (UFW / iptables)
ระบบ `fp-radius` ใช้พอร์ตมาตรฐานของ RADIUS แบบ **UDP** ดังนั้นหากเครื่องเซิร์ฟเวอร์มีการเปิดใช้งาน Firewall ไว้ (เช่น UFW) จำเป็นต้องอนุญาตการเข้าถึงพอร์ตดังต่อไปนี้ เพื่อให้ FortiGate หรืออุปกรณ์ Network สามารถส่งข้อมูลเข้ามาได้:

- **Port 1812 (UDP)**: สำหรับ Authentication (ตรวจสอบสิทธิ์เข้าใช้งาน)
- **Port 1813 (UDP)**: สำหรับ Accounting (เก็บประวัติและเวลาการใช้งาน)

**คำสั่งสำหรับตั้งค่า UFW (Ubuntu/Debian):**
```bash
sudo ufw allow 1812/udp
sudo ufw allow 1813/udp
sudo ufw reload
```

