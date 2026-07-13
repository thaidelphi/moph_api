# ขั้นตอนและวิธีการเขียนระบบล็อกอินผ่าน API ไปยัง FortiGate (External Captive Portal)

เอกสารฉบับนี้อธิบายแนวทาง วิธีการ และโค้ดตัวอย่างสำหรับการพัฒนาระบบ Captive Portal ภายนอกเพื่อล็อกอินและส่งผลยืนยันตัวตนต่อไปยังอุปกรณ์ FortiGate

---

## ข้อจำกัดทางเทคนิคที่สำคัญ (Crucial Limitation)

> [!WARNING]
> **เซิร์ฟเวอร์หลังบ้าน (เช่น PHP, Node.js) ไม่สามารถส่งคำขอล็อกอินแทนเครื่องผู้ใช้งานได้**
> เนื่องจากการตรวจสอบสิทธิ์ของ FortiGate จะอิงตาม **IP Address ของเครื่องที่ทำคำขอ (Requesting IP)** หากส่งคำขอออกจากเซิร์ฟเวอร์หลังบ้านโดยตรง จะทำให้เซิร์ฟเวอร์หลังบ้านได้รับสิทธิ์อินเทอร์เน็ตแทนเครื่องของผู้ใช้ 
> **ดังนั้น การส่งข้อมูลการล็อกอินขั้นสุดท้ายจะต้องทำงานผ่านเบราว์เซอร์ของตัวผู้ใช้งานเองเสมอ**

---

## ขั้นตอนการทำงานโดยรวม (SSO Flow)

1. **การเปลี่ยนทิศทางเริ่มต้น (Redirection):** เมื่อผู้ใช้เชื่อมต่อสัญญาณ Wi-Fi อุปกรณ์ FortiGate จะเปลี่ยนเส้นทางหน้าเว็บ (Redirect) ไปยังหน้าล็อกอินภายนอกที่คุณกำหนด พร้อมส่งพารามิเตอร์ที่จำเป็นผ่าน Query string เช่น:
   `https://yourportal.com/index.php?magic=xxxxxxxx&redirurl=http://www.google.com`
2. **การรักษาข้อมูลพารามิเตอร์:** หน้าเว็บระบบของคุณจะต้องจัดเก็บค่า `magic` และ `redirurl` (หรือ `redir`) เอาไว้ (เช่น บันทึกลงใน Session หรือส่งต่อไปยังฟอร์มแต่ละหน้า)
3. **การพิสูจน์ตัวตน:** ผู้ใช้ทำการล็อกอินบนหน้าเว็บของคุณ เช่น ผ่าน Google Login, ThaID, MOPH ID หรือบัญชีทั่วไปจนเสร็จสิ้นกระบวนการตรวจสอบสิทธิ์ฝั่งคุณ
4. **การเปิดสิทธิ์อินเทอร์เน็ต (Authentication Handshake):** เมื่อยืนยันฝั่งระบบคุณสำเร็จแล้ว เบราว์เซอร์ของผู้ใช้จะต้องส่งคำขอ HTTP POST (ที่มีค่า `username`, `password`, `magic`, และ `redir`) ไปยัง URL ของอุปกรณ์ FortiGate โดยตรงผ่านหนึ่งใน 2 วิธีด้านล่าง

---

## วิธีที่ 1: การใช้ HTML Form ซ่อนตัวและส่งอัตโนมัติ (Auto-Submit Form) - แนะนำและเสถียรที่สุด

วิธีนี้เป็นวิธีมาตรฐาน โดยเมื่อผู้ใช้ยืนยันตัวตนบนระบบคุณเรียบร้อยแล้ว ให้แสดงผลหน้าเว็บที่มี Form ซ่อนและสั่งให้ JavaScript รันคำสั่ง `submit()` อัตโนมัติไปยังอุปกรณ์ FortiGate

### ตัวอย่างโค้ด HTML/PHP (`fortigate_handshake.php`):

```html
<!DOCTYPE html>
<html lang="th">
<head>
    <meta charset="UTF-8">
    <title>กำลังเชื่อมต่อเครือข่าย...</title>
</head>
<body>
    <!-- ข้อความแสดงสถานะให้ผู้ใช้ทราบระหว่างกระบวนการเปลี่ยนหน้า -->
    <p style="text-align: center; margin-top: 50px; font-family: sans-serif;">
        กำลังเชื่อมต่ออินเทอร์เน็ต กรุณารอสักครู่...
    </p>

    <!-- ฟอร์มส่งข้อมูลไปยัง FortiGate (ซ่อนไว้ไม่ให้ผู้ใช้เห็น) -->
    <!-- หมายเหตุ: URL ใน action ปกติจะรับค่ามาจากตัวแปรที่ FortiGate ส่งมาตอนแรก หรือระบุไอพีของเกตเวย์ตรงๆ -->
    <form id="fortigate_form" action="http://192.168.1.1:1000/fgtauth" method="post" style="display:none;">
        <!-- บัญชีผู้ใช้งานและรหัสผ่านสำหรับลงทะเบียนในระบบ FortiGate -->
        <input type="hidden" name="username" value="user_sso_account">
        <input type="hidden" name="password" value="user_sso_password">
        
        <!-- magic และ redir ที่ดึงมาจากพารามิเตอร์ดั้งเดิมที่ได้จาก FortiGate -->
        <input type="hidden" name="magic" value="<?php echo htmlspecialchars($_GET['magic'] ?? ''); ?>">
        <input type="hidden" name="redir" value="<?php echo htmlspecialchars($_GET['redirurl'] ?? ''); ?>">
    </form>

    <script>
        // ทำการเรียกให้ฟอร์มทำงานส่งข้อมูล (Submit) ไปยัง FortiGate ทันทีที่หน้าจอโหลดเสร็จสิ้น
        document.getElementById('fortigate_form').submit();
    </script>
</body>
</html>
```

---

## วิธีที่ 2: การใช้ JavaScript Fetch API / AJAX ยิงในเบื้องหลัง (Behind-the-scenes AJAX)

หากคุณกำลังทำแอปพลิเคชันรูปแบบ Single Page Application (SPA) หรือไม่ต้องการให้เบราว์เซอร์รีเฟรชหน้าจอทั้งหมด คุณสามารถใช้ JavaScript เพื่อยิงข้อมูลไปหา FortiGate โดยตรงในเบื้องหลังได้

### ตัวอย่างโค้ด JavaScript:

```javascript
/**
 * ฟังก์ชันสำหรับการยิงยืนยันสิทธิ์ไปยัง FortiGate ด้วย Fetch API
 * @param {string} username - ชื่อบัญชีสำหรับเข้าใช้งาน
 * @param {string} password - รหัสผ่านสำหรับเข้าใช้งาน
 * @param {string} magic - รหัส magic session ที่ FortiGate ให้มา
 * @param {string} redirUrl - ลิงก์ที่ต้องการให้เปลี่ยนไปหลังจากเข้าสู่ระบบสำเร็จ
 */
function loginToFortiGate(username, password, magic, redirUrl) {
    // กำหนด URL สำหรับการ Authentication ของ FortiGate
    const fortigateUrl = "http://192.168.1.1:1000/fgtauth";
    
    // จัดเตรียม Body parameters ในรูปแบบ URL encoded
    const formData = new URLSearchParams();
    formData.append('username', username);
    formData.append('password', password);
    formData.append('magic', magic);
    formData.append('redir', redirUrl);

    // ยิงคำขอ POST ไปยัง FortiGate
    fetch(fortigateUrl, {
        method: 'POST',
        body: formData,
        mode: 'no-cors' // *จำเป็นอย่างยิ่ง* เนื่องจาก FortiGate ไม่ได้ส่ง CORS Header ตอบกลับมา
    })
    .then(() => {
        console.log("ลงทะเบียนเปิดใช้งานสำเร็จ!");
        // นำผู้ใช้ไปยังหน้าเว็บปลายทางที่ต้องการท่องอินเทอร์เน็ต
        window.location.href = redirUrl;
    })
    .catch((error) => {
        console.error("เกิดข้อผิดพลาดในการเชื่อมต่อกับ FortiGate:", error);
        alert("ไม่สามารถเปิดสิทธิ์ใช้งานอินเทอร์เน็ตได้ กรุณาติดต่อผู้ดูแลระบบ");
    });
}
```
