# การนำ fpsso ไปใช้งานร่วมกับ FortiGate Captive Portal

เอกสารนี้อธิบายถึงหลักการทำงานและขั้นตอนการตั้งค่า FortiGate เพื่อใช้งานร่วมกับระบบ **fpsso** และ **fp-radius** สำหรับการตรวจสอบสิทธิ์ก่อนเข้าใช้งานอินเทอร์เน็ต

## 🔄 หลักการทำงาน (Authentication Flow)

1. ผู้ใช้เชื่อมต่อ WiFi ที่ถูกล็อกด้วย Captive Portal
2. FortiGate จะ Redirect ผู้ใช้มายังหน้าเว็บ **fpsso** พร้อมแนบพารามิเตอร์ `?magic=...` มาด้วย
3. ผู้ใช้กด Login (ด้วย ThaID, ProviderID หรือกรอกฟอร์มด้วย Local User)
4. เมื่อ **fpsso** ยืนยันตัวตนสำเร็จ จะทำการบันทึกรหัสผ่านลงฐานข้อมูล (สำหรับให้ RADIUS ใช้ตรวจสอบในขั้นตอนถัดไป)
5. **fpsso** พาผู้ใช้ไปที่หน้า Handshake และทำการยิงฟอร์ม (Auto-Submit) ส่ง `username`, `password` และ `magic` token กลับไปหา FortiGate
6. FortiGate นำข้อมูลไปถาม **fp-radius** (RADIUS Server)
7. **fp-radius** ตรวจสอบกับฐานข้อมูล MySQL และตอบกลับ FortiGate ว่าผ่าน (Accept)
8. FortiGate ปลดล็อกสิทธิ์ให้ผู้ใช้ออกอินเทอร์เน็ตได้สำเร็จ 🎉

---

## ⚙️ ขั้นตอนการตั้งค่าที่ฝั่ง FortiGate

### 1. ตั้งค่า RADIUS Server
ไปที่เมนู **User & Authentication** > **RADIUS Servers** แล้วกด **Create New**
- **Name**: `fpsso-radius` (หรือชื่ออะไรก็ได้ตามต้องการ)
- **Primary Server IP/Name**: ไอพีของเซิร์ฟเวอร์ที่รัน `fp-radius` (เช่น `172.16.62.30`)
- **Secret**: รหัสผ่าน RADIUS Secret (ต้องตรงกับค่า `RADIUS_SECRET` ในไฟล์ `.env` ของ fp-radius เช่น `0004800048`)
- กด **Test Connectivity** เพื่อตรวจสอบว่าเชื่อมต่อผ่าน

### 2. สร้าง User Group สำหรับใช้งาน
ไปที่เมนู **User & Authentication** > **User Groups** แล้วกด **Create New**
- **Name**: `WiFi-SSO-Group`
- **Type**: Firewall
- **Remote Groups**: เพิ่ม RADIUS Server `fpsso-radius` ที่เพิ่งสร้างขึ้นมาเข้าไป

### 3. ตั้งค่า Interface ให้เปิด Captive Portal
ไปที่เมนู **Network** > **Interfaces** (หรือหากใช้ FortiAP ให้เข้าไปแก้ที่ SSID ของ WiFi)
- แก้ไข Interface ที่ต้องการให้ผู้ใช้ล็อกอิน
- เลื่อนลงมาที่ตัวเลือก **Security mode**
- **Security mode**: กดเปิดสวิตช์ให้เป็นสีเขียว (ON) แล้วเลือกเป็น `Captive Portal`
- **Authentication Portal**: เลือก `External` (สำคัญมาก)
- **URL**: ระบุ URL ของระบบ fpsso เช่น `https://172.16.62.30:8080/` หรือถ้าตั้ง Apache Reverse Proxy ไว้แล้วให้ใส่ `https://172.16.62.30/sso/`
- **User Groups**: เลือก `WiFi-SSO-Group`

**การตั้งค่าข้อยกเว้น (Exempt Destinations) สำหรับหน้าเว็บ SSO**
1. **สร้าง Address Object:** ไปที่เมนู **Policy & Objects** > **Addresses** > สร้าง Address Object สำหรับเซิร์ฟเวอร์ (เช่น ตั้งชื่อว่า `SSO-Server` โดยกำหนดค่า IP เป็น `172.16.62.30/32`)
2. **เพิ่มข้อยกเว้น:** กลับมาที่หน้าตั้งค่า Captive Portal ของ Interface เมื่อสักครู่ ตรงหัวข้อ **Exempt destinations/services** ให้กดปุ่ม `+` แล้วเลือก Address Object `SSO-Server` ที่เพิ่งสร้างเข้าไป 
   > ⚠️ **คำเตือนที่สำคัญมาก:** ในช่อง Exempt destinations/services **ห้ามใส่ Service `HTTP`, `HTTPS` หรือ `ALL` ลงไปเด็ดขาด!** ให้ใส่แค่เฉพาะ Address/IP ปลายทางเท่านั้น หากคุณเผลอใส่ Service HTTP/HTTPS ลงไป FortiGate จะเข้าใจว่า "อนุญาตให้เข้าเว็บได้ทุกเว็บโดยไม่ต้องล็อกอิน" และหน้า Captive Portal จะไม่ยอมเด้งขึ้นมาเลย!
3. กด **Apply / OK** เพื่อบันทึก

*(หมายเหตุ: การตั้งค่าส่วนนี้จะบังคับให้ FortiGate อนุญาตให้ผู้ใช้งานที่เพิ่งเกาะ WiFi สามารถเข้าถึงหน้าเว็บ Authentication ที่ 172.16.62.30 ได้แม้จะยังไม่ได้ล็อกอินก็ตาม)*

### 4. ตั้งค่า Firewall Policies (สำคัญมาก)
คุณต้องสร้าง Policy อย่างน้อย 2 ตัว เพื่อให้ระบบทำงานได้:

**Policy 1: ข้อยกเว้นก่อน Login (Pre-Auth / Walled Garden)**
ต้องอนุญาตให้ผู้ใช้ที่ยังไม่ได้ Login สามารถเข้าถึงหน้าเว็บ SSO และ API ภายนอกได้
- **Source**: `all` (จากวง WiFi)
- **Destination**: IP ของเซิร์ฟเวอร์ที่รัน fpsso (พอร์ต 80, 443, 8080), รวมถึง IP/Domain ของ ThaID, ProviderID และ Google
- **Service**: HTTP, HTTPS
- **Action**: ACCEPT

**Policy 2: อนุญาตออกอินเทอร์เน็ตหลัง Login สำเร็จ**
- **Source**: `all` (จากวง WiFi)
- **User**: `WiFi-SSO-Group` (จับกลุ่มคนที่ล็อกอินผ่านแล้ว)
- **Destination**: `all`
- **Service**: `ALL`
- **Action**: ACCEPT
- **NAT**: เปิดใช้งาน

---

## ⚙️ ตรวจสอบไฟล์ `.env` ฝั่ง fpsso

คุณต้องมั่นใจว่าตัวแปร `FORTIGATE_AUTH_URL` ในไฟล์ `.env` ของระบบ `fpsso` ชี้กลับไปหาขาใน (Gateway IP) ของ FortiGate ถูกต้อง เพื่อให้ตอน Handshake ระบบสามารถส่งข้อมูลผู้ใช้กลับไปให้ FortiGate ตรวจสอบได้

```env
# ตัวอย่าง: ตั้งเป็น IP ของ FortiGate วงใน และพอร์ตที่รับ Auth (ค่ามาตรฐานคือ 1000 หรือ 11443)
FORTIGATE_AUTH_URL=http://192.168.5.1:1000/fgtauth

# หรือถ้า FortiGate มีการบังคับใช้ HTTPS ให้ตั้งเป็น:
# FORTIGATE_AUTH_URL=https://192.168.5.1:1000/fgtauth
```

เมื่อตั้งค่าครบถ้วนตามนี้ เมื่อผู้ใช้เชื่อมต่อ WiFi ระบบจะเด้งหน้าจอของ fpsso ขึ้นมาโดยอัตโนมัติ (Captive Portal) และเมื่อทำการล็อกอินเสร็จสิ้น ระบบจะพาเข้าสู่อินเทอร์เน็ตได้ทันที
