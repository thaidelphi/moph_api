# คู่มือการรัน fp-radius (FreePascal RADIUS Server)

ก่อนรันโปรแกรม หรือตั้งค่า Service **จำเป็นต้องติดตั้ง MySQL Client Library** เพื่อให้ FreePascal สามารถเชื่อมต่อกับฐานข้อมูล MySQL ได้ โดยรันคำสั่ง:
```bash
sudo apt-get update
sudo apt-get install libmysqlclient-dev
```

---

## 1. การรันแบบปกติผ่าน Command Line (เพื่อทดสอบ)
เหมาะสำหรับการรันเพื่อดู Log แบบสดๆ ว่ามีการส่งข้อมูลเข้ามาและสามารถเชื่อมต่อฐานข้อมูลได้ถูกต้องหรือไม่

```bash
cd /var/www/api/freepascal/fp-radius/

# รันโดยให้โปรแกรมไปอ่านค่าคอนฟิกจาก /var/www/api/.env
./fpradius /var/www/api/.env
```
*(ถ้าคุณไม่ระบุพาธไฟล์ `.env` ต่อท้าย โปรแกรมจะตั้งค่าเริ่มต้นไปอ่านที่ `/var/www/api/.env` อยู่แล้ว)*

---

## 2. การรันเป็น Background Service (สำหรับ Production)
การตั้งค่าแบบนี้จะทำให้เซิร์ฟเวอร์รันอยู่เบื้องหลังตลอดเวลา และเปิดตัวเองอัตโนมัติหากมีการรีสตาร์ทเครื่อง

### ขั้นตอนการตั้งค่า Systemd
1. คัดลอกไฟล์เซอร์วิส (ถ้ามีไฟล์ `fpradius.service` เตรียมไว้) ไปยังระบบ
```bash
sudo cp /var/www/api/freepascal/fp-radius/fpradius.service /etc/systemd/system/
```

2. โหลด Service ใหม่และตั้งค่าให้ทำงานอัตโนมัติ
```bash
sudo systemctl daemon-reload
sudo systemctl enable fpradius
sudo systemctl start fpradius
```

### การตรวจสอบและการจัดการ (Systemctl)
เช็คว่าเซอร์วิสทำงานปกติหรือไม่ (ดูสถานะ Active)
```bash
sudo systemctl status fpradius
```

หากมีการแก้ไขโค้ดหรือต้องการเริ่มต้นระบบใหม่ ให้ใช้คำสั่ง Restart
```bash
sudo systemctl restart fpradius
```

คำสั่งสำหรับหยุดการทำงานของระบบ (Stop)
```bash
sudo systemctl stop fpradius
```

ดู Log ย้อนหลังและแบบ Real-time ของ RADIUS
sudo journalctl -u fpradius -f
```

---

## 3. การตั้งค่า Firewall (UFW / iptables)
ระบบ `fp-radius` ใช้พอร์ตมาตรฐานของ RADIUS แบบ **UDP** ดังนั้นหากเครื่องเซิร์ฟเวอร์มีการเปิดใช้งาน Firewall ไว้ (เช่น UFW) จำเป็นต้องอนุญาตการเข้าถึงพอร์ตดังต่อไปนี้ เพื่อให้ FortiGate หรืออุปกรณ์ Network สามารถส่งข้อมูลเข้ามาได้ครับ:

- **Port 1812 (UDP)**: สำหรับ Authentication (ตรวจสอบสิทธิ์เข้าใช้งาน)
- **Port 1813 (UDP)**: สำหรับ Accounting (เก็บประวัติและเวลาการใช้งาน)

**คำสั่งสำหรับตั้งค่า UFW (Ubuntu/Debian):**
```bash
sudo ufw allow 1812/udp
sudo ufw allow 1813/udp
sudo ufw reload
```
