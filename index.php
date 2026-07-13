<?php
// โหลด Security Configuration และเริ่มต้น Session
require_once __DIR__ . '/security_config.php';

// บันทึกค่า magic และ redirurl ลงใน Session เมื่อมีการส่งต่อมาจาก FortiGate
if (isset($_GET['magic'])) {
    $_SESSION['fortigate_magic'] = $_GET['magic'];
}
if (isset($_GET['redirurl'])) {
    $_SESSION['fortigate_redirurl'] = $_GET['redirurl'];
} elseif (isset($_GET['redir'])) {
    $_SESSION['fortigate_redirurl'] = $_GET['redir'];
}

// Load environment variables
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

// Helper to decode Base64 key
function remove_non_text($text) {
    return base64_decode($text);
}

/*
 * Available Scope options for ThaID API:
 * - pid            : เลขประจำตัวประชาชน 13 หลัก (Citizen ID)
 * - name           : ชื่อและนามสกุลภาษาไทย (Thai full name)
 * - name_en        : ชื่อและนามสกุลภาษาอังกฤษ (English full name)
 * - given_name     : ชื่อตัวภาษาไทย (Thai first name)
 * - family_name    : ชื่อสกุลภาษาไทย (Thai last name)
 * - given_name_en  : ชื่อตัวภาษาอังกฤษ (English first name)
 * - family_name_en : ชื่อสกุลภาษาอังกฤษ (English last name)
 * - birthdate      : วันเดือนปีเกิด (Birthdate)
 * - gender         : เพศ (Gender)
 * - address        : ที่อยู่ตามทะเบียนบ้าน (Formatted Address)
 * - title          : คำนำหน้าชื่อภาษาไทย (Thai Title)
 * - title_en       : คำนำหน้าชื่อภาษาอังกฤษ (English Title)
 */
$client_id = getenv('THAID_CLIENT_ID') ?: ($_ENV['THAID_CLIENT_ID'] ?? '');
$redirect_uri = getenv('THAID_REDIRECT_URI') ?: ($_ENV['THAID_REDIRECT_URI'] ?? '');
$url_auth = getenv('THAID_URL_AUTH') ?: ($_ENV['THAID_URL_AUTH'] ?? '');
$default_scope = getenv('THAID_SCOPE') ?: ($_ENV['THAID_SCOPE'] ?? 'pid name address');

$link = $url_auth . '?response_type=code&client_id=' . urlencode($client_id) . '&redirect_uri=' . urlencode($redirect_uri) . '&scope=' . urlencode($default_scope) . '&state=authen';

// ProviderID Configuration
$moph_id_url = getenv('MOPH_ID_URL') ?: ($_ENV['MOPH_ID_URL'] ?? 'https://moph.id.th');
$moph_id_Client_ID = getenv('MOPH_ID_CLIENT_ID') ?: ($_ENV['MOPH_ID_CLIENT_ID'] ?? '');
$provider_redirect_uri = getenv('PROVIDER_ID_REDIRECT_URI') ?: ($_ENV['PROVIDER_ID_REDIRECT_URI'] ?? '');
$provider_link = "{$moph_id_url}/oauth/redirect?client_id={$moph_id_Client_ID}&redirect_uri=" . urlencode($provider_redirect_uri) . "&response_type=code";

// กำหนดการเชื่อมต่อและดึงลิงก์สำหรับการเข้าสู่ระบบด้วย Google
$google_client_id = getenv('GOOGLE_CLIENT_ID') ?: ($_ENV['GOOGLE_CLIENT_ID'] ?? '');
$google_redirect_uri = getenv('GOOGLE_REDIRECT_URI') ?: ($_ENV['GOOGLE_REDIRECT_URI'] ?? '');
$google_url_auth = getenv('GOOGLE_URL_AUTH') ?: ($_ENV['GOOGLE_URL_AUTH'] ?? 'https://accounts.google.com/o/oauth2/v2/auth');
$google_scope = 'openid email profile';
// สร้าง URL สำหรับการยืนยันตัวตนผ่านระบบ Google OAuth 2.0
$google_link = $google_url_auth . '?response_type=code' .
               '&client_id=' . urlencode($google_client_id) .
               '&redirect_uri=' . urlencode($google_redirect_uri) .
               '&scope=' . urlencode($google_scope) .
               '&state=google_auth';
?>

<!DOCTYPE html>
<html lang="th">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>เลือกช่องทางเข้าสู่ระบบ - MOPH API</title>
    <link href="assets/css/fonts.css" rel="stylesheet">
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
        .container {
            text-align: center;
            background: white;
            padding: 40px;
            border-radius: 12px;
            box-shadow: 0 4px 15px rgba(0,0,0,0.05);
            max-width: 420px;
            width: 100%;
        }
        .login-section {
            margin-top: 20px;
        }
        .login-btn {
            display: inline-block;
            transition: transform 0.2s ease;
            margin: 10px 0;
        }
        .login-btn:hover {
            transform: scale(1.04);
        }
        img {
            max-width: 180px;
            height: auto;
            cursor: pointer;
            border-radius: 8px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.08);
        }
        .divider {
            margin: 15px 0;
            font-size: 14px;
            color: #aaa;
            position: relative;
        }
        .divider::before, .divider::after {
            content: "";
            position: absolute;
            top: 50%;
            width: 40%;
            height: 1px;
            background: #e2e8f0;
        }
        .divider::before { left: 0; }
        .divider::after { right: 0; }
        h2 {
            color: #333;
            margin-bottom: 10px;
            font-size: 20px;
        }
        p {
            color: #666;
            font-size: 14px;
            margin-bottom: 25px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h2>ลงทะเบียนเข้าใช้งานอินเตอร์เน็ต</h2>
        <p>กรุณาเลือกช่องทางยืนยันตัวตนเพื่อเข้าใช้งาน</p>

        <div class="login-section">
            <!-- ThaID Login Option -->
            <a href="<?= htmlspecialchars($link) ?>" class="login-btn">
                <img src="./images/thaid.png" alt="Login with ThaID" onerror="this.src='https://imauthsbx.bora.dopa.go.th/api/v2/oauth2/auth/favicon.ico';">
            </a>

            <div class="divider">หรือ</div>

            <!-- ProviderID Login Option -->
            <a href="<?= htmlspecialchars($provider_link) ?>" class="login-btn">
                <img src="./images/providerid.png" alt="Login with ProviderID" onerror="this.src='https://moph.id.th/favicon.ico';">
            </a>

            <div class="divider">หรือ</div>

            <!-- Google Login Option (ทางเลือกการเข้าสู่ระบบผ่าน Google) -->
            <a href="<?= htmlspecialchars($google_link) ?>" class="login-btn">
                <img src="./images/google.png" alt="Login with Google" onerror="this.src='https://www.google.com/favicon.ico';">
            </a>

        </div>
    </div>
</body>
</html>
