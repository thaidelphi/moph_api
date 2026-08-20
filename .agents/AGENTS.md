# Agent Rules & Architecture Principles

## 1. Git & Deployment
- **Automatic Git Commit and Push**: ทุกครั้งที่มีการอัปเดต/แก้ไข/เพิ่ม/ลบโค้ด และทดสอบเสร็จสิ้นแล้ว จะต้องรัน `git add .`, `git commit -m "..."`, และ `git push origin HEAD` (รวมถึง push ไปยังทั้ง `main` และ `work1` branches) โดยอัตโนมัติทันที ห้ามรอให้ผู้ใช้สั่ง
- **Commit Message Convention**: ใช้ข้อความ Commit เป็นภาษาไทย หรือภาษาอังกฤษแบบสื่อความหมายชัดเจน อธิบายการเปลี่ยนแปลงที่เกิดขึ้นอย่างตรงไปตรงมา
- **Git Log Tracking (`git_log.md`)**: หลังจากการ Push เรียบร้อยแล้วทุกครั้ง จะต้องบันทึกประวัติ Commit ลงในไฟล์ [git_log.md](file:///var/www/api/git_log.md) เสมอ โดยต้องมีรายละเอียดครบถ้วน:
  1. วันที่-เวลา (Timestamp)
  2. Commit Hash (ทั้งแบบสั้นและแบบเต็ม)
  3. ข้อความ Commit (Commit Message)
  4. แนวทางการย้อนกลับ/กู้คืนระบบ (Rollback / Recovery Command เช่น `git checkout <hash>` หรือ `git revert <hash>`)
  เพื่อให้สามารถติดตามประวัติและใช้กู้คืนระบบได้อย่างรวดเร็วในกรณีฉุกเฉิน
- **Package Deployment**: เมื่อผู้ใช้สั่งให้ "push package" หรือคล้ายคลึงกัน ให้ push เฉพาะ binary และไฟล์ deploy ใน `/var/www/api/package_send` ไปยัง `https://github.com/thaidelphi/internet-authen` เท่านั้น (ห้าม push ไฟล์ `.pas`)

## 2. Secure and Robust Coding
- **No Hardcoded Secrets**: Never hardcode credentials, client IDs, client secrets, database passwords, or private URLs in the source code. Always read them from `.env` or system environment variables.
- **Input Sanitization and Validation**: Sanitize all incoming user data (GET/POST/COOKIE parameters). Prevent SQL Injection by using parameterized queries and XSS by escaping output with HTML encoding.
- **Secure Error Handling**: Disable display of raw errors to end users in production. Log errors securely to systemd journal / server error log instead of displaying system paths, database schemas, or raw stack traces.
- **Code Commenting in Thai**: ทุกครั้งที่มีการเขียนหรือแก้ไขโค้ด จะต้องเขียน Comment เพื่ออธิบายการทำงานของ Source code ตัวแปร และ Logic ทุกครั้งเป็นภาษาไทย (Always write code comments in Thai to explain the source code, variables, and logic).
- **Pure FreePascal Standalone**: ระบบ FreePascal (`fpsso` และ `fp-radius`) เป็นระบบ Native Binary แยกเด็ดขาด 100% โดยไม่พึ่งพาและไม่เรียกใช้ PHP ใดๆ ทั้งสิ้น

## 3. Unified Post-Login Pipeline Rules (กฎกระบวนการหลังล็อกอินมาตรฐานเดียวกัน 100%)
- **Standard Authentication Pipeline**: ทุกช่องทางการล็อกอิน (**Local User, ThaID, Provider ID, Google OAuth**) จะต้องส่งผ่านกระบวนการเดียวกันทั้งหมด โดยยึดพฤติกรรมการทำงานของ **Local User** เป็นแม่แบบหลัก:
  1. **User Sync & Session Creation**: ตรวจสอบสิทธิ์, บันทึกรหัสผ่านทั้ง Cleartext+MD5 ลงตาราง `radcheck`, สร้าง Session ที่มี `Username`, `PlainPass`, `Magic`, `PostUrl`, `UserMac`, `ClientIP` และ Set Cookie `SSOSESSID`
  2. **Handshake Forwarding**: Redirect ต่อไปยัง `/sso/fortigate/handshake?sid=<SessionID>` (แนบ `sid` ใน query เสมอ)
  3. **Auto-Submit Handshake Form**: หน้า Handshake ส่งฟอร์ม 4 ฟิลด์มาตรฐาน (`username`, `password`, `magic`, `redir`) ไปยัง `https://192.168.200.1:1003/fgtauth` โดยตรง
  4. **Post-Login Landing**: เมื่อ FortiGate ตอบรับ จะนำพาผู้ใช้เข้าสู่หน้าสถานะ `/sso/status?sid=<SessionID>` แสดงชื่อ-นามสกุล และปุ่ม Logout
- **Target URL Integrity**: ยิงเข้า URL และพอร์ตตามที่ FortiGate ส่งมาในพารามิเตอร์ `post` เสมอ (เช่น `https://192.168.200.1:1003/fgtauth`)
- **Session Propagation**: แนบ `?sid=<SessionID>` ในทุกจุดเชื่อมต่อ (OAuth Callback ➡️ Handshake ➡️ RedirUrl ➡️ Status) เพื่อให้ Session ต่อเนื่อง 100% แม้เบราว์เซอร์จะไม่ส่ง Cookie
- **Logout URL Integrity**: เมื่อ Logout ต้องชี้ไปที่ `https://192.168.200.1:1003/logout?<magic>` ตามพอร์ต HTTPS ของ FortiGate เสมอ

## 4. RADIUS & Password Synchronization Rules (กฎเหล็ก RADIUS)
- **Dual Password Sync (Cleartext + MD5)**: สำหรับทุกช่องทางการล็อกอิน (Local, ThaID, ProviderID, Google) ฟังก์ชันการสร้าง/อัปเดตผู้ใช้ใน `RadiusDB.pas` จะต้องล้างข้อมูลเดิมที่ซ้ำซ้อน และบันทึกรหัสผ่านลงตาราง `radcheck` **ทั้งแบบ `Cleartext-Password` และ `MD5-Password`** เสมอ เพราะ FortiGate ตรวจสอบสิทธิ์ผ่าน FreeRADIUS / `fpradius` ด้วย `Cleartext-Password` หากมีเฉพาะ MD5 จะทำให้ผู้ใช้ ThaID ล็อกอินผ่านแต่ไฟร์วอลล์ไม่อนุญาตให้ออกเน็ต
- **radcheck_cleartext Sync**: ต้องซิงค์รหัสผ่านลงตาราง `radcheck_cleartext` ควบคู่กันเสมอ
- **Transaction & Connection Lifecycle**: ใน `fp-radius` (เช่น `RadiusDB.pas`), ทุกฟังก์ชันที่ Query (`CheckUserPassword`, `LogAccessAttempt`, `LogAccounting`) จะต้องมีคำสั่ง `Query.Close` และ `Commit`/`Rollback` Transaction เสมอ พร้อมทั้งมีระบบ Auto-reconnect หาก Connection กับ MySQL ขาดหาย เพื่อป้องกันไม่ให้ Transaction ค้างจนกระทบต่อการตรวจสิทธิ์และทำให้ FortiGate ได้รับ `Auth=Failed`

## 5. Database & Configuration Changes
- **Database Migrations**: ทุกครั้งที่มีการแก้ไขหรือเพิ่มตารางฐานข้อมูล ให้ทำระบบ Auto-migration (`CREATE TABLE IF NOT EXISTS` หรือ ALTER) ในโค้ดแอปพลิเคชันเสมอ
- **CLI Documentation**: ทุกครั้งที่เพิ่ม flag หรือ command-line parameter ให้ปรับปรุงเอกสาร `--help` ทันที
