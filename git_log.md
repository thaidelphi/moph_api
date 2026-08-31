# Git Commit History & Recovery Log (`git_log.md`)

ไฟล์นี้ใช้สำหรับบันทึกประวัติการ Commit และคำสั่งในการย้อนกลับ (Rollback/Recovery) ทุกครั้งที่มีการอัปเดตระบบ เพื่อให้สามารถติดตามประวัติและกู้คืนระบบได้อย่างรวดเร็วในกรณีฉุกเฉิน

---

## ตารางประวัติการ Commit

| วันที่-เวลา | Commit Hash | Commit Message | คำสั่งกู้คืน / ย้อนกลับ (Rollback) |
|---|---|---|---|
| 2026-08-31 11:45:00 | `38ed5ba` | fix(fpsso): ยกเลิกการเพิ่มแถว MD5-Password ในตาราง radcheck และปรับ Handshake เป็น Top-level form submit | `git checkout 38ed5ba` |
| 2026-08-20 10:40:35 | `2a2ccbf` | docs: บันทึกกฎการ commit/push อัตโนมัติและสร้างไฟล์ git_log.md สำหรับบันทึกประวัติการกู้คืน | `git checkout 2a2ccbf` |
| 2026-08-19 19:11:09 | `effa8ee` | chore: ignore .key license files | `git checkout effa8ee` |
| 2026-08-19 19:04:39 | `5f62f25` | fix(fpsso): replace target=_blank with hidden iframe in handshake to bypass Chrome popup blocker | `git checkout 5f62f25` |
| 2026-08-19 16:16:44 | `067fc69` | fix(fpsso): form target=_blank so FortiGate auth opens in new tab, main tab setTimeout redirect to /sso/status works for all auth methods | `git checkout 067fc69` |
| 2026-08-19 16:12:51 | `a0505a6` | fix(fpsso): add 2s setTimeout redirect to /sso/status after FortiGate handshake form submit | `git checkout a0505a6` |
| 2026-08-19 16:10:44 | `db85897` | revert(fpsso): restore FortiGate.pas to state at 15:43 (before handshake experiments) | `git checkout db85897` |
| 2026-08-19 16:08:11 | `8a3bf09` | fix(fpsso): add 2s setTimeout redirect to /sso/status after form submit to FortiGate | `git checkout 8a3bf09` |
| 2026-08-19 16:06:20 | `a7c5829` | revert(fpsso): restore FortiGate.pas to original client-side form submit (before handshake experiments) | `git checkout a7c5829` |
| 2026-08-19 16:03:08 | `8f94936` | fix(fpsso): restore client-side form submit + JS timeout redirect to /sso/status to fix browser stuck on handshake page | `git checkout 8f94936` |
| 2026-08-19 15:53:37 | `1babbf0` | fix(fpsso): server-side POST to FortiGate instead of browser form submit to fix self-signed cert hang | `git checkout 1babbf0` |
| 2026-08-19 15:43:59 | `8c30895` | fix: SSO_AUTO_APPROVE=false blocks active=N users across all login methods (Local/ThaID/ProviderID/Google) | `git checkout 8c30895` |

---

## คำแนะนำในการกู้คืนระบบ (Emergency Recovery Guide)

1. **ต้องการดูสถานะโค้ด ณ จุดใดจุดหนึ่ง:**
   ```bash
   git checkout <commit_hash>
   ```
2. **ต้องการยกเลิกการเปลี่ยนแปลงล่าสุดและย้อนกลับไปจุดก่อนหน้า:**
   ```bash
   git revert <commit_hash>
   ```
3. **ต้องการกู้คืนทั้งระบบกลับไปยังจุดที่แน่นอน:**
   ```bash
   git reset --hard <commit_hash>
   ```
4. **หลังกู้คืนโค้ดเสร็จแล้ว ให้คอมไพล์และรีสตาร์ตเซอร์วิส:**
   ```bash
   cd /var/www/api/freepascal/fpsso && fpc -O3 -XX -Xs -Fu"src" fpsso.lpr
   sudo systemctl restart fpsso
   ```
