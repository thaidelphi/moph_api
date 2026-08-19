# Agent Rules & Architecture Principles

## 1. Git & Deployment
- **Git Commit and Push**: Every time code files are modified, added, or deleted, stage the changes (`git add`), commit them with a descriptive message, and push them to the remote git repository (`git push`) to both `main` and `work1` branches before completing the turn. Do not wait for the user to request a push.
- **Package Deployment**: Whenever the user explicitly instructs to "push package" or similar, ONLY push the pre-compiled deployment packages (binaries, .env.example, templates, service files) and NOT the source code (`.pas` files) to the repository `https://github.com/thaidelphi/internet-authen`.
  - **Process**: Copy the necessary package files into `/var/www/api/package_send`, then `git add`, `git commit`, and `git push` from inside that directory.

## 2. Secure and Robust Coding
- **No Hardcoded Secrets**: Never hardcode credentials, client IDs, client secrets, database passwords, or private URLs in the source code. Always read them from `.env` or system environment variables.
- **Input Sanitization and Validation**: Sanitize all incoming user data (GET/POST/COOKIE parameters). Prevent SQL Injection by using parameterized queries and XSS by escaping output with HTML encoding.
- **Secure Error Handling**: Disable display of raw errors to end users in production. Log errors securely to systemd journal / server error log instead of displaying system paths, database schemas, or raw stack traces.
- **Code Commenting in Thai**: ทุกครั้งที่มีการเขียนหรือแก้ไขโค้ด จะต้องเขียน Comment เพื่ออธิบายการทำงานของ Source code ตัวแปร และ Logic ทุกครั้งเป็นภาษาไทย (Always write code comments in Thai to explain the source code, variables, and logic).
- **Pure FreePascal Standalone**: ระบบ FreePascal (`fpsso` และ `fp-radius`) เป็นระบบ Native Binary แยกเด็ดขาด 100% โดยไม่พึ่งพาและไม่เรียกใช้ PHP ใดๆ ทั้งสิ้น

## 3. FortiGate Handshake & Redirection Rules (กฎสถาปัตยกรรม Handshake ที่ถูกต้อง)
- **Background Target Submission**: ฟอร์ม Handshake ส่งข้อมูลยืนยันตัวตนไปยัง FortiGate Target URL ในเบื้องหลังผ่าน `<iframe name="fgt_target">` พร้อมสั่งให้ JavaScript นำหน้าต่างหลักเปิดเข้าสู่หน้าสถานะ `window.location.href = nextUrl` (`/sso/status?sid=<SessionID>`) ใน 800ms โดยผู้ใช้จะไม่เห็นหน้า Portal สีขาวของ FortiGate
- **Standard 4 Form Fields**: ฟอร์มที่ส่งไป FortiGate ต้องส่ง 4 ฟิลด์มาตรฐานเท่านั้น: `username`, `password`, `magic`, `redir` (ห้ามส่งฟิลด์แปลกปลอม หรือใส่ query ยาวเกินไปที่ทำให้ socket หลุด)
- **Target URL Integrity**: ยิงเข้า URL และพอร์ตตามที่ FortiGate ส่งมาในพารามิเตอร์ `post` เสมอ (เช่น `https://192.168.200.1:1003/fgtauth`)
- **Session Propagation in Redirection**: ใน `nextUrl` จะต้องแนบ `?sid=<SessionID>` ต่อท้ายไปด้วยเสมอ เพื่อให้หน้าสถานะ `/sso/status?sid=...` กู้คืน Session ได้ 100% ทันที
- **Logout URL Integrity**: เมื่อ Logout ต้องชี้ไปที่ `https://192.168.200.1:1003/logout?<magic>` ตามพอร์ต HTTPS ของ FortiGate เสมอ

## 4. RADIUS & Password Synchronization Rules (กฎเหล็ก RADIUS)
- **Dual Password Sync (Cleartext + MD5)**: สำหรับทุกช่องทางการล็อกอิน (Local, ThaID, ProviderID, Google) ฟังก์ชันการสร้าง/อัปเดตผู้ใช้ใน `RadiusDB.pas` จะต้องล้างข้อมูลเดิมที่ซ้ำซ้อน และบันทึกรหัสผ่านลงตาราง `radcheck` **ทั้งแบบ `Cleartext-Password` และ `MD5-Password`** เสมอ เพราะ FortiGate ตรวจสอบสิทธิ์ผ่าน FreeRADIUS / `fpradius` ด้วย `Cleartext-Password` หากมีเฉพาะ MD5 จะทำให้ผู้ใช้ ThaID ล็อกอินผ่านแต่ไฟร์วอลล์ไม่อนุญาตให้ออกเน็ต
- **radcheck_cleartext Sync**: ต้องซิงค์รหัสผ่านลงตาราง `radcheck_cleartext` ควบคู่กันเสมอ
- **Transaction & Connection Lifecycle**: ใน `fp-radius` (เช่น `RadiusDB.pas`), ทุกฟังก์ชันที่ Query (`CheckUserPassword`, `LogAccessAttempt`, `LogAccounting`) จะต้องมีคำสั่ง `Query.Close` และ `Commit`/`Rollback` Transaction เสมอ พร้อมทั้งมีระบบ Auto-reconnect หาก Connection กับ MySQL ขาดหาย เพื่อป้องกันไม่ให้ Transaction ค้างจนกระทบต่อการตรวจสิทธิ์และทำให้ FortiGate ได้รับ `Auth=Failed`

## 5. Database & Configuration Changes
- **Database Migrations**: ทุกครั้งที่มีการแก้ไขหรือเพิ่มตารางฐานข้อมูล ให้ทำระบบ Auto-migration (`CREATE TABLE IF NOT EXISTS` หรือ ALTER) ในโค้ดแอปพลิเคชันเสมอ
- **CLI Documentation**: ทุกครั้งที่เพิ่ม flag หรือ command-line parameter ให้ปรับปรุงเอกสาร `--help` ทันที
