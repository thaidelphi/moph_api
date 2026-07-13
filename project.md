# รายละเอียดโครงสร้างและการตั้งค่าการใช้งาน APIs

เอกสารนี้อธิบายถึงตัวแปรสภาพแวดล้อมและการใช้งาน API ของบริการพิสูจน์และยืนยันตัวตน (Single Sign-On - SSO) ในโครงการ

---

## 1. การตั้งค่าสิทธิ์เข้าใช้งาน ThaID API

ค่าตัวแปรในส่วนนี้ใช้สำหรับการตรวจสอบและยืนยันตัวตนผ่านบริการ **ThaID** ของกรมการปกครอง

*   **`THAID_API_KEY`**: รหัสสิทธิ์เข้าใช้งาน (API Key) ใช้ส่งร่วมกับ HTTP Header ในรูปแบบ `x-api-key: [API_KEY]` ไปยัง API Endpoint เพื่อตรวจสอบสิทธิ์การใช้งาน
*   **`THAID_CLIENT_ID`**: รหัสประจำตัวแอปพลิเคชัน (Client ID)
*   **`THAID_SECRET_ID`**: รหัสลับของแอปพลิเคชัน (Client Secret)
*   **`THAID_REDIRECT_URI`**: URL ปลายทางที่ต้องการให้ ThaID ส่งผลลัพธ์กลับมาหลังจากยืนยันตัวตนสำเร็จ
*   **`THAID_URL_TOKEN`**: URL Endpoint ของ ThaID สำหรับการขอแลกเปลี่ยน Authorization Code เป็น Access Token
*   **`THAID_URL_AUTH`**: URL Endpoint สำหรับส่งผู้ใช้งานไปหน้า Login/Authorize ของ ThaID
*   **`THAID_SCOPE`**: สิทธิ์ของข้อมูลที่ขอเข้าถึง (เช่น `pid`, `name`, `address`)

---

## 2. การตั้งค่าระบบ ProviderID / MOPH ID Configuration

ตัวแปรสภาพแวดล้อมในส่วนนี้ใช้เพื่อยืนยันตัวตนและดึงข้อมูลของบุคลากรทางการแพทย์และสาธารณสุข กระทรวงสาธารณสุข

### MOPH ID Configuration (ระบบยืนยันตัวตนกลาง)

*   **`MOPH_ID_URL`**
    *   **คำอธิบาย**: URL หลักของระบบยืนยันตัวตน MOPH ID (`https://moph.id.th`)
    *   **ไฟล์ที่ใช้งาน**: 
        *   [`login.php`](file:///var/www/api/login.php): ใช้สร้างลิงก์สำหรับ Redirect ผู้ใช้งานไปยังหน้าล็อกอินของ MOPH ID
        *   [`providerid_api.php`](file:///var/www/api/providerid_api.php) & [`provider.php`](file:///var/www/api/provider.php): ใช้ในการส่ง HTTP POST เพื่อแลกรับ Access Token
*   **`MOPH_ID_CLIENT_ID`**
    *   **คำอธิบาย**: Client ID ของระบบ MOPH ID เพื่อระบุแอปพลิเคชันนี้
    *   **ไฟล์ที่ใช้งาน**:
        *   [`login.php`](file:///var/www/api/login.php): ส่งไปเป็น Query parameter ตอนโยนหน้าไปล็อกอิน
        *   [`providerid_api.php`](file:///var/www/api/providerid_api.php) & [`provider.php`](file:///var/www/api/provider.php): ใช้ส่งไปใน API Payload เพื่อขอแลกเปลี่ยน Token
*   **`MOPH_ID_SECRET_KEY`**
    *   **คำอธิบาย**: Client Secret ของแอปพลิเคชันที่ใช้ยืนยันความปลอดภัยในระบบ MOPH ID
    *   **ไฟล์ที่ใช้งาน**:
        *   [`providerid_api.php`](file:///var/www/api/providerid_api.php) & [`provider.php`](file:///var/www/api/provider.php): แนบใน Request Body ตอนแลกเปลี่ยน Access Token

### Provider ID Configuration (ระบบข้อมูลบุคลากรทางการแพทย์)

*   **`PROVIDER_ID_URL`**
    *   **คำอธิบาย**: URL ของระบบฐานข้อมูลและจัดการรหัสผู้ให้บริการ (Provider ID) (`https://provider.id.th`)
    *   **ไฟล์ที่ใช้งาน**:
        *   [`providerid_api.php`](file:///var/www/api/providerid_api.php) & [`provider.php`](file:///var/www/api/provider.php): ใช้ยิง API เพื่อนำ MOPH ID Access Token ไปแลกรับข้อมูลโปรไฟล์และ Provider ID ของผู้ใช้
*   **`PROVIDER_ID_CLIENT_ID`**
    *   **คำอธิบาย**: Client ID สำหรับการระบุตัวตนแอปพลิเคชันในระบบ Provider ID
    *   **ไฟล์ที่ใช้งาน**: [`providerid_api.php`](file:///var/www/api/providerid_api.php) & [`provider.php`](file:///var/www/api/provider.php)
*   **`PROVIDER_ID_SECRET_KEY`**
    *   **คำอธิบาย**: Client Secret ที่เกี่ยวข้องกับการใช้งานระบบ Provider ID
    *   **ไฟล์ที่ใช้งาน**: [`providerid_api.php`](file:///var/www/api/providerid_api.php) & [`provider.php`](file:///var/www/api/provider.php)
*   **`PROVIDER_ID_REDIRECT_URI`**
    *   **คำอธิบาย**: URL ของหน้า callback บนระบบนี้ (`https://api1.kpo.go.th/providerid_api.php`) เพื่อรับข้อมูลผลลัพธ์หลังจาก Login
    *   **ไฟล์ที่ใช้งาน**:
        *   [`login.php`](file:///var/www/api/login.php): ใช้กำหนดค่า `redirect_uri` ใน SSO Link
        *   [`providerid_api.php`](file:///var/www/api/providerid_api.php): ใช้ส่งเป็นพารามิเตอร์ตรวจสอบตอนแลก Token
