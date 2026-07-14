<?php
// โหลด Security Configuration และเริ่มต้น Session
require_once __DIR__ . '/security_config.php';

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
            
            // ลบเครื่องหมายคำพูด (Quote) ถ้ามี
            $value = trim($value, "\"'");
            
            putenv("{$name}={$value}");
            $_ENV[$name] = $value;
            $_SERVER[$name] = $value;
        }
    }
}
load_env(__DIR__ . '/.env');

// ลบข้อมูล Session ฝั่งเซิร์ฟเวอร์ PHP
session_unset();
session_destroy();

// ลบ Cookie ฝั่งเบราว์เซอร์
if (ini_get("session.use_cookies")) {
    $params = session_get_cookie_params();
    setcookie(session_name(), '', time() - 42000,
        $params["path"], $params["domain"],
        $params["secure"], $params["httponly"]
    );
}

// หา URL สำหรับ Logout ของ FortiGate
$fortigate_auth_url = getenv('FORTIGATE_AUTH_URL') ?: ($_ENV['FORTIGATE_AUTH_URL'] ?? 'http://192.168.1.1:1000/fgtauth');
$fortigate_logout_url = getenv('FORTIGATE_LOGOUT_URL') ?: ($_ENV['FORTIGATE_LOGOUT_URL'] ?? str_ireplace('fgtauth', 'logout', $fortigate_auth_url));

// สั่ง Redirect เบราว์เซอร์ไปยัง FortiGate Logout URL
header("Location: " . $fortigate_logout_url);
exit;
