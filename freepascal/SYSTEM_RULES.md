# เอกสารสรุปกฎสถาปัตยกรรมและบทเรียนสำคัญ (System Architecture Rules & Lessons Learned)

เอกสารนี้รวบรวมข้อกำหนดและบทเรียนสำคัญจากการพัฒนาและแก้ปัญหาระบบ **FreePascal SSO (`fpsso`)** และ **FreePascal RADIUS (`fp-radius`)** เพื่อใช้เป็นแนวทางมาตรฐานและป้องกันไม่ให้เกิดปัญหาเดิมซ้ำซ้อน

---

## 📌 สารบัญกฎเหล็ก (Critical Architecture Rules)

### 1. ระบบยืนยันตัวตนกับไฟร์วอลล์ FortiGate (FortiGate Captive Portal Handshake)
* **การส่งฟอร์ม Handshake (`/fgtauth`):**
  * **ต้องส่งบนหน้าต่างหลักของเบราว์เซอร์ (Top-level Form Submit) เท่านั้น**
  * **❌ ห้ามใช้ hidden `<iframe>` หรือ `fetch()`/AJAX เด็ดขาด:** เพราะ Port 1003 (`https://192.168.200.1:1003`) เป็น Self-Signed SSL Certificate ตัวเบราว์เซอร์ Chrome จะบล็อกการยิงคำขอใน `<iframe>` เงียบๆ ส่งผลให้ FortiGate ไม่ได้รับข้อมูลล็อกอิน และไม่อนุญาตให้ออกอินเทอร์เน็ต
* **พารามิเตอร์ของฟอร์ม Handshake:**
  * ฟิลด์ที่ต้องส่ง:
    1. `username` : บัญชีผู้ใช้ (Username ปกติ หรือ เลขประจำตัวประชาชน 13 หลักจาก ThaID)
    2. `password` : รหัสผ่านชั่วคราว/รหัสผ่านจริง (`tmp_passwd`)
    3. `magic`    : Magic Token ที่ส่งมาจาก FortiGate
    4. `4Tredir`  : URL ปลายทางหลังล็อกอินสำเร็จ (เช่น `https://auth.kpo.go.th/sso/status?sid=...`)
    5. `redir`    : URL ปลายทางหลังล็อกอินสำเร็จ (เช่น `https://auth.kpo.go.th/sso/status?sid=...`)
  * **❌ ห้ามส่ง `answer=1`:** การส่ง `answer=1` จะทำให้ FortiOS แสดงหน้าต่าง Keepalive Portal สีขาวของไฟร์วอลล์เองแทนที่จะทำการ Redirect
* **การรักษา Session ข้ามโดเมน (`sid` Parameter):**
  * ในค่า `redir` และ `4Tredir` จะต้องแนบ `?sid=<SessionID>` ต่อท้ายไปด้วยเสมอ
  * **เหตุผล:** เมื่อ FortiGate ทำการ 302 Redirect ข้ามโดเมนจาก `https://192.168.200.1:1003` กลับมายัง `https://auth.kpo.go.th/sso/status` เบราว์เซอร์จะตัด Cross-Site Cookies ออก การมี `?sid=` ทำให้หน้า `/sso/status` กู้คืน Session ได้ทันทีและไม่เด้งกลับไปหน้า Login

---

### 2. การซิงค์รหัสผ่านกับฐานข้อมูล RADIUS (`radcheck` Table)
* **ต้องบันทึกทั้ง Cleartext และ MD5 ลงในตาราง `radcheck` เสมอ:**
  * สำหรับทุกช่องทาง (Local, ThaID, Provider ID, Google) โค้ดใน `RadiusDB.pas` จะต้องล้างเรคคอร์ดเก่าที่ซ้ำซ้อน และ Insert ทั้ง 2 แถวดังนี้:
    ```sql
    DELETE FROM radcheck WHERE username = :u AND attribute IN ('Cleartext-Password', 'MD5-Password');
    INSERT INTO radcheck (username, attribute, op, value) VALUES (:u, 'Cleartext-Password', ':=', :v_plain);
    INSERT INTO radcheck (username, attribute, op, value) VALUES (:u, 'MD5-Password', ':=', :v_md5);
    ```
  * **เหตุผล:** ตัว FreeRADIUS และ `fp-radius` ใช้ `Cleartext-Password` ในการตรวจสอบแพ็กเก็ต Access-Request จาก FortiGate หากในตารางมีเฉพาะ `MD5-Password` ตัวไฟร์วอลล์จะยืนยันตัวตนไม่ผ่าน ทำให้ผู้ใช้ล็อกอินผ่านเว็บได้ แต่ไฟร์วอลล์บล็อกไม่ให้ออกเน็ต

---

### 3. การแยกขาดจาก PHP (Pure FreePascal Native Standalone)
* ระบบ **`fpsso`** และ **`fp-radius`** เป็น Standalone Native Linux Binary (ELF 64-bit) 100%
* **ห้ามพึ่งพา หรือเรียกใช้ PHP ภายนอกเด็ดขาด** (การประมวลผล HTTP, Router, Session, DB, RADIUS UDP จัดการด้วย Pascal ทั้งหมด)

---

### 4. การจัดการ Session (`SessionMgr.pas` และ `Router.pas`)
* **ลำดับการค้นหา Session ในทุกหน้า (`HandleFortiGateHandshake`, `HandleStatusPage`):**
  1. ค้นหาจาก Cookie `SSOSESSID`
  2. ค้นหาจาก Query Parameter `sid` (ความสำคัญสูงสุดเมื่อ redirect ข้ามโดเมน)
  3. ค้นหาจาก IP ของเครื่องลูกข่าย (`FindSessionByIP`)
* **การอ่าน Client IP (`GetClientIP`):**
  * ต้องตัดเอาเฉพาะ IP ตัวแรกใน Header `X-Forwarded-For` เสมอ (คั่นด้วย comma) เพื่อป้องกันปัญหาเมื่อมีหลาย Proxy

---

### 5. กฎกระบวนการหลังการล็อกอินที่เป็นมาตรฐานเดียวกัน 100% (Unified Post-Login Pipeline)
* **ทุกระบบล็อกอิน (Local User, ThaID, Provider ID, Google) ต้องใช้กระบวนการเดียวกัน โดยยึด Local User เป็นหลัก:**
  1. **ขั้นตอนที่ 1: ตรวจสอบและบันทึกผู้ใช้ (Verify & Sync)**
     * ตรวจสอบสิทธิ์สำเร็จ ➡️ ซิงค์รหัสผ่าน (Cleartext+MD5) ลงตาราง `radcheck` ➡️ สร้าง/อัปเดต Session ➡️ Set Cookie `SSOSESSID`
  2. **ขั้นตอนที่ 2: ส่งต่อเข้า Handshake (Handshake Forwarding)**
     * ทุกระบบต้อง Redirect ต่อไปยัง `/sso/fortigate/handshake?sid=<SessionID>` เสมอ
  3. **ขั้นตอนที่ 3: ยืนยันสิทธิ์กับไฟร์วอลล์ (FortiGate Auto-Submit)**
     * หน้า Handshake ส่งฟอร์ม 4 ฟิลด์มาตรฐาน (`username`, `password`, `magic`, `redir`) ไปยัง `TargetUrl` บนหน้าต่างหลัก
  4. **ขั้นตอนที่ 4: เปิดหน้าสถานะสำเร็จ (Status Page Presentation)**
     * นำผู้ใช้เข้าสู่หน้า `/sso/status?sid=<SessionID>` แสดงกล่องสถานะเชื่อมต่อสำเร็จ, ชื่อ-นามสกุล, ปุ่มแก้ไขโปรไฟล์ และปุ่ม Logout

