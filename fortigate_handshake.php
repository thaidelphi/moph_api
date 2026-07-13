<?php
// เริ่มต้นใช้งาน Session เพื่อดึงค่าที่จัดเก็บไว้ก่อนหน้านี้
session_start();

// โหลดค่าตัวแปรสภาพแวดล้อมจากไฟล์ .env
function load_env($filePath) {
    if (!file_exists($filePath)) {
        return;
    }
    $lines = file($filePath, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        if (strpos(trim($line), '#') === 0) {
            continue;
        }
        $parts = explode('=', $line, 2);
        if (count($parts) === 2) {
            $name = trim($parts[0]);
            $value = trim($parts[1]);
            putenv("{$name}={$value}");
            $_ENV[$name] = $value;
            $_SERVER[$name] = $value;
        }
    }
}
load_env(__DIR__ . '/.env');

// ดึงการตั้งค่า URL ปลายทางของ FortiGate และพารามิเตอร์จาก Session
$fortigate_auth_url = getenv('FORTIGATE_AUTH_URL') ?: ($_ENV['FORTIGATE_AUTH_URL'] ?? 'http://192.168.1.1:1000/fgtauth');
$magic = $_SESSION['fortigate_magic'] ?? '';
$redirurl = $_SESSION['fortigate_redirurl'] ?? 'https://www.google.com';

// รับค่า Username และ Password ที่ส่งมาจากหน้าประมวลผลการเข้าสู่ระบบ
$username = $_REQUEST['username'] ?? '';
$password = $_REQUEST['password'] ?? '';

// กรณีทดสอบ หากไม่มีชื่อผู้ใช้ให้ดึงข้อมูลจำลอง
if (empty($username)) {
    $username = $_SESSION['user_sso_email'] ?? $_SESSION['user_sso_name'] ?? 'sso_user';
}
if (empty($password)) {
    $password = 'sso_dummy_password';
}
?>
<!DOCTYPE html>
<html lang="th">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <!-- นำเข้าฟอนต์เพื่อใช้แต่งหน้าจอ Loading ที่เป็นระบบภาษาไทย -->
    <link href="https://fonts.googleapis.com/css2?family=Sarabun:wght@400;500;600&display=swap" rel="stylesheet">
    <title>กำลังเชื่อมต่อระบบเครือข่าย...</title>
    <style>
        body {
            font-family: 'Sarabun', sans-serif;
            background-color: #f4f7f6;
            margin: 0;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
        }
        .loading-box {
            text-align: center;
            background: white;
            padding: 40px;
            border-radius: 12px;
            box-shadow: 0 4px 15px rgba(0, 0, 0, 0.05);
            max-width: 400px;
            width: 100%;
        }
        .spinner {
            border: 4px solid rgba(0, 0, 0, 0.1);
            width: 50px;
            height: 50px;
            border-radius: 50%;
            border-left-color: #007bff;
            animation: spin 1s linear infinite;
            margin: 0 auto 20px auto;
        }
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        h2 {
            color: #333;
            margin-bottom: 10px;
            font-size: 18px;
        }
        p {
            color: #666;
            font-size: 14px;
        }
    </style>
</head>
<body>

    <div class="loading-box">
        <div class="spinner"></div>
        <h2>กำลังอนุญาตสิทธิ์เข้าใช้งานอินเทอร์เน็ต</h2>
        <p>กรุณารอสักครู่ ระบบกำลังลงทะเบียนอุปกรณ์ของท่านกับทาง FortiGate...</p>
    </div>

    <!-- ฟอร์มที่จะทำ Auto-submit ไปยัง FortiGate ผ่านเบราว์เซอร์ผู้ใช้งาน -->
    <form id="fortigate_form" action="<?= htmlspecialchars($fortigate_auth_url) ?>" method="post" style="display: none;">
        <!-- บัญชีผู้ใช้งานที่ผ่าน SSO แล้ว -->
        <input type="hidden" name="username" value="<?= htmlspecialchars($username) ?>">
        <input type="hidden" name="password" value="<?= htmlspecialchars($password) ?>">
        
        <!-- ข้อมูลเซสชันและพารามิเตอร์นำทางของ FortiGate -->
        <input type="hidden" name="magic" value="<?= htmlspecialchars($magic) ?>">
        <input type="hidden" name="redir" value="<?= htmlspecialchars($redirurl) ?>">
    </form>

    <script>
        // ทำการส่งฟอร์มเพื่อยืนยันสิทธิ์กับ FortiGate ทันทีหลังจากที่หน้าโหลดเสร็จสิ้น
        window.addEventListener('load', function() {
            setTimeout(function() {
                document.getElementById('fortigate_form').submit();
            }, 1000); // ดีเลย์สั้นๆ 1 วินาทีเพื่อให้ผู้ใช้เห็นสถานะการโหลด
        });
    </script>

</body>
</html>
