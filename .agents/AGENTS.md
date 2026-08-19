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

## 3. FortiGate Handshake & Redirection Rules (กฎเหล็กห้ามทำผิดซ้ำ)
- **Top-Level Direct Submission**: ฟอร์ม Handshake ที่ส่งข้อมูลยืนยันตัวตนไปยัง FortiGate (`/fgtauth`) จะต้อง Submit บนหน้าต่างหลักของเบราว์เซอร์โดยตรง **ห้ามใช้ hidden `<iframe>` หรือ AJAX เด็ดขาด** เพราะเบราว์เซอร์ (Chrome) จะบล็อกการส่งข้อมูลไปยัง Self-Signed SSL Certificate ของ FortiGate ทำให้เครื่องลูกข่ายไม่ได้รับสิทธิ์ออกเน็ต
- **Target URL Integrity**: ห้ามแปลงพอร์ต `1003` เป็น `1000` เองโดยพลการ ให้ยิงเข้า URL และพอร์ตตามที่ FortiGate ส่งมาในพารามิเตอร์ `post` เสมอ
- **Session Propagation in Redirection**: ในพารามิเตอร์ `redir` และ `4Tredir` จะต้องแนบ `?sid=<SessionID>` ต่อท้ายไปด้วยเสมอ เพื่อให้เมื่อ FortiGate ทำการ 302 Redirect กลับมาที่ `POST_LOGIN_REDIRECT_URL` (`/sso/status?sid=...`) หน้าสถานะจะสามารถกู้คืน Session ได้ 100% แม้เบราว์เซอร์จะตัด Cross-Site Cookies ออกก็ตาม
- **Standard Form Fields**: ฟอร์มที่ส่งไป FortiGate ต้องส่ง 5 ฟิลด์มาตรฐาน: `username`, `password`, `magic`, `4Tredir`, `redir` (ห้ามส่ง `answer=1` เพราะจะทำให้ FortiGate แสดงหน้า keepalive portal แทนที่จะ Redirect)

## 4. RADIUS & Password Synchronization Rules (กฎเหล็ก RADIUS)
- **Dual Password Sync (Cleartext + MD5)**: สำหรับทุกช่องทางการล็อกอิน (Local, ThaID, ProviderID, Google) ฟังก์ชันการสร้าง/อัปเดตผู้ใช้ใน `RadiusDB.pas` จะต้องล้างข้อมูลเดิมที่ซ้ำซ้อน และบันทึกรหัสผ่านลงตาราง `radcheck` **ทั้งแบบ `Cleartext-Password` และ `MD5-Password`** เสมอ เพราะ FortiGate ตรวจสอบสิทธิ์ผ่าน FreeRADIUS / `fpradius` ด้วย `Cleartext-Password` หากมีเฉพาะ MD5 จะทำให้ผู้ใช้ ThaID ล็อกอินผ่านแต่ไฟร์วอลล์ไม่อนุญาตให้ออกเน็ต
- **radcheck_cleartext Sync**: ต้องซิงค์รหัสผ่านลงตาราง `radcheck_cleartext` ควบคู่กันเสมอ

## 5. Database & Configuration Changes
- **Database Migrations**: ทุกครั้งที่มีการแก้ไขหรือเพิ่มตารางฐานข้อมูล ให้ทำระบบ Auto-migration (`CREATE TABLE IF NOT EXISTS` หรือ ALTER) ในโค้ดแอปพลิเคชันเสมอ
- **CLI Documentation**: ทุกครั้งที่เพิ่ม flag หรือ command-line parameter ให้ปรับปรุงเอกสาร `--help` ทันที
