<?php
// โหลด Security Configuration และเริ่มต้น Session
require_once __DIR__ . '/security_config.php';

// โหลดค่าตัวแปรสภาพแวดล้อมจากไฟล์ .env
function load_env($filePath) {
    if (!file_exists($filePath)) {
        return;
    }
    // อ่านไฟล์ .env ทีละบรรทัด
    $lines = file($filePath, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        // ข้ามบรรทัดที่เป็น Comment
        if (strpos(trim($line), '#') === 0) {
            continue;
        }
        // แยกตัวแปรด้วยเครื่องหมาย =
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

// นำเข้าไฟล์สำหรับ Radius Authentication
require_once __DIR__ . '/radius_auth.php';

// ฟังก์ชันรับค่าพารามิเตอร์ GET/POST อย่างปลอดภัย
function _PARAM($key, $default = "") {
    return $_REQUEST[$key] ?? $default;
}

// ฟังก์ชันส่ง HTTP POST ด้วย cURL ไปยัง API ของ Google เพื่อแลกเปลี่ยน Access Token
function Google_Exchange_Token($url, $data) {
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query($data));
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    
    // ตั้งค่า Header สำหรับการรับส่งข้อมูลในรูปแบบ URL encoded
    $headers = [
        'Content-Type: application/x-www-form-urlencoded'
    ];
    curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
    
    $response = curl_exec($ch);
    curl_close($ch);
    return $response;
}

// ฟังก์ชันส่ง HTTP GET ด้วย cURL โดยใช้ Bearer Token เพื่อดึงข้อมูลผู้ใช้งานจาก Google
function Google_Get_User_Info($url, $accessToken) {
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    
    // แนบ Access Token เข้าไปใน Authorization Header
    $headers = [
        'Authorization: Bearer ' . $accessToken
    ];
    curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
    
    $response = curl_exec($ch);
    curl_close($ch);
    return $response;
}

// ดึงการตั้งค่า Google OAuth จากไฟล์ .env
$client_id = getenv('GOOGLE_CLIENT_ID') ?: ($_ENV['GOOGLE_CLIENT_ID'] ?? '');
$client_secret = getenv('GOOGLE_CLIENT_SECRET') ?: ($_ENV['GOOGLE_CLIENT_SECRET'] ?? '');
$redirect_uri = getenv('GOOGLE_REDIRECT_URI') ?: ($_ENV['GOOGLE_REDIRECT_URI'] ?? '');
$url_auth = getenv('GOOGLE_URL_AUTH') ?: ($_ENV['GOOGLE_URL_AUTH'] ?? 'https://accounts.google.com/o/oauth2/v2/auth');
$url_token = getenv('GOOGLE_URL_TOKEN') ?: ($_ENV['GOOGLE_URL_TOKEN'] ?? 'https://oauth2.googleapis.com/token');
$url_userinfo = getenv('GOOGLE_URL_USERINFO') ?: ($_ENV['GOOGLE_URL_USERINFO'] ?? 'https://www.googleapis.com/oauth2/v3/userinfo');

$error_msg = "";

// ดึงรหัส code และ state หลังจาก redirect กลับมาจาก Google
$code_google = _PARAM("code", "");
$state_google = _PARAM("state", "");

// กำหนดขอบเขตข้อมูล (Scope) ที่ต้องการขอเข้าถึงจาก Google (ขอข้อมูลโปรไฟล์พื้นฐานและอีเมล)
$scope = "openid email profile";

// ตรวจสอบว่ามี Code ส่งมาหรือไม่ หากไม่มีจะเปลี่ยนทิศทางไปยังหน้าล็อกอิน Google
if (($code_google == "") or ($state_google == "")) {
    // สร้าง Google Authorization Link สำหรับล็อกอิน
    $link = $url_auth . '?response_type=code' .
            '&client_id=' . urlencode($client_id) .
            '&redirect_uri=' . urlencode($redirect_uri) .
            '&scope=' . urlencode($scope) .
            '&state=google_auth';
    
    // เปลี่ยนทิศทางไปยังหน้าล็อกอินของ Google ทันที
    header("Location: " . $link);
    exit;
} elseif ($state_google == "google_auth") {
    // กำหนดข้อมูลในการขอแลกเปลี่ยน token
    $token_data = [
        'code' => $code_google,
        'client_id' => $client_id,
        'client_secret' => $client_secret,
        'redirect_uri' => $redirect_uri,
        'grant_type' => 'authorization_code'
    ];
    
    // ดึง Token Response จาก Google
    $token_response = Google_Exchange_Token($url_token, $token_data);
    $token_json = json_decode($token_response, true);
    
    // ดึง Access Token ออกมาเพื่อนำไปเรียก API ข้อมูลผู้ใช้
    $access_token = $token_json['access_token'] ?? '';
    
    $raw_json = "";
    $email = "";
    $fullname = "";
    $picture = "";
    $google_id = "";
    
    if (!empty($access_token)) {
        // ดึงข้อมูลโปรไฟล์ผู้ใช้งานด้วย Access Token
        $user_info_response = Google_Get_User_Info($url_userinfo, $access_token);
        $user_info = json_decode($user_info_response, true);
        
        $google_id = $user_info['sub'] ?? '';
        $fullname = $user_info['name'] ?? '';
        $email = $user_info['email'] ?? '';
        $picture = $user_info['picture'] ?? '';
        $raw_json = $user_info_response;

        // ป้องกัน Session Fixation
        session_regenerate_id(true);

        // 1. เชื่อมต่อฐานข้อมูลเพื่อตรวจสอบความสัมพันธ์ของ Gmail กับบัญชีในระบบ
        $db_host = getenv('DB_HOST') ?: ($_ENV['DB_HOST'] ?? '168.148.62.15');
        $db_user = getenv('DB_USER') ?: ($_ENV['DB_USER'] ?? 'root');
        $db_pass = getenv('DB_PASS') ?: ($_ENV['DB_PASS'] ?? '');
        $db_name = getenv('DB_NAME') ?: ($_ENV['DB_NAME'] ?? 'radius');
        
        $conn = @new mysqli($db_host, $db_user, $db_pass, $db_name);
        if ($conn->connect_error) {
            error_log("Database connection failed: " . $conn->connect_error);
            $error_msg = "ระบบเชื่อมต่อฐานข้อมูลล้มเหลว กรุณาติดต่อผู้ดูแลระบบ";
        } else {
            $conn->set_charset("utf8");
            
            // 2. ค้นหาบัญชีผู้ใช้เดิมที่ผูกกับ Gmail นี้ไว้
            $stmt = $conn->prepare("SELECT username, tmp_passwd, active FROM radcheck_mirror WHERE email = ? LIMIT 1");
            $stmt->bind_param("s", $email);
            $stmt->execute();
            $result = $stmt->get_result();
            
            if ($result && $result->num_rows > 0) {
                $row = $result->fetch_assoc();
                
                // ตรวจสอบว่าบัญชีถูกบล็อกหรือปิดการใช้งานหรือไม่
                if ($row['active'] === 'N') {
                    $error_msg = "บัญชีของท่านถูกระงับการใช้งานชั่วคราว กรุณาติดต่อผู้ดูแลระบบ";
                } else {
                    $username_found = $row['username'];
                    $password_found = $row['tmp_passwd'];
                    
                    // หากยังไม่มีรหัสผ่าน ให้สร้างใหม่
                    if (empty($password_found)) {
                        $password_found = sso_radius_auth($username_found, $email, $fullname);
                    }
                    
                    // บันทึกข้อมูลเข้าระบบ Session
                    $_SESSION['user_sso_email'] = $email;
                    $_SESSION['user_sso_name'] = $fullname;
                    $_SESSION['user_sso_account'] = $username_found;
                    $_SESSION['user_sso_password'] = $password_found;
                    
                    // หากมาด้วย FortiGate magic ให้นำทางเข้าเชื่อมต่อเน็ตทันที
                    if (!empty($_SESSION['fortigate_magic'])) {
                        $conn->close();
                        header("Location: fortigate_handshake.php");
                        exit;
                    }
                }
            } else {
                // 3. กรณีไม่มี Gmail นี้ในระบบ: ให้บันทึกข้อมูลแต่กำหนด active = 'N' (ไม่สร้างบัญชีใน radcheck)
                $stmt_check = $conn->prepare("SELECT COUNT(*) as count FROM radcheck_mirror WHERE username = ?");
                $username_temp = $email;
                $stmt_check->bind_param("s", $username_temp);
                $stmt_check->execute();
                $result_check = $stmt_check->get_result();
                $row_check = $result_check->fetch_assoc();
                
                if ($row_check['count'] == 0) {
                    $date_register = date('Y-m-d H:i:s');
                    $note = "ลงทะเบียนผ่าน Google (ยังไม่อนุมัติ)";
                    $active = "N";
                    
                    $stmt_insert = $conn->prepare("INSERT INTO radcheck_mirror (username, email, fullname, date_register, active, note) VALUES (?, ?, ?, ?, ?, ?)");
                    $stmt_insert->bind_param("ssssss", $username_temp, $email, $fullname, $date_register, $active, $note);
                    $stmt_insert->execute();
                }
                
                $error_msg = "อีเมลนี้ยังไม่มีสิทธิ์เข้าใช้งานระบบ แต่อุปกรณ์ได้บันทึกข้อมูลของท่านเรียบร้อยแล้ว กรุณาติดต่อผู้ดูแลระบบเพื่อเปิดสิทธิ์การใช้งาน";
            }
            $conn->close();
        }
    } else {
        $raw_json = $token_response;
    }
}
?>
<!DOCTYPE html>
<html lang="th">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link href="assets/css/fonts.css" rel="stylesheet">
    <title>ข้อมูลที่ได้รับจากระบบ Google</title>
    <style>
        body {
            font-family: 'Sarabun', sans-serif;
            background-color: #f4f7f6;
            margin: 0;
            padding: 20px;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
        }
        .container {
            background-color: #fff;
            padding: 30px;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.08);
            max-width: 600px;
            width: 100%;
            border-radius: 12px;
        }
        h2 {
            text-align: center;
            color: #333;
            margin-bottom: 20px;
        }
        .profile-box {
            text-align: center;
            margin-bottom: 20px;
        }
        .profile-img {
            width: 100px;
            height: 100px;
            border-radius: 50%;
            box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
            object-fit: cover;
        }
        .data-row {
            display: flex;
            margin-bottom: 12px;
            border-bottom: 1px solid #eee;
            padding-bottom: 8px;
        }
        .data-label {
            font-weight: 600;
            width: 180px;
            color: #555;
        }
        .data-value {
            flex: 1;
            color: #111;
        }
        pre {
            background: #2d3748;
            color: #a0aec0;
            padding: 15px;
            border-radius: 8px;
            overflow-x: auto;
            font-family: monospace;
            font-size: 13px;
            max-height: 300px;
        }
        .back-btn {
            display: block;
            text-align: center;
            margin-top: 25px;
            background-color: #4285F4;
            color: white;
            text-decoration: none;
            padding: 10px 20px;
            border-radius: 6px;
            font-weight: 500;
            transition: background 0.2s;
        }
        .back-btn:hover {
            background-color: #357ae8;
        }
    </style>
</head>
<body>

    <?php if (!empty($error_msg)): ?>
        <!-- แสดงกล่องแจ้งเตือนเมื่อเกิดข้อผิดพลาดในการตรวจสอบสิทธิ์การใช้งาน (เช่น อีเมลไม่มีในระบบ หรือโดนแบน) -->
        <div class="container" style="border-top: 4px solid #ef4444; text-align: center;">
            <h2 style="color: #ef4444;">ไม่สามารถเข้าใช้งานระบบได้</h2>
            <div style="margin: 30px 0; color: #4a5568; line-height: 1.6;">
                <!-- ไอคอนแสดงข้อผิดพลาดขนาดใหญ่เพื่อให้ผู้ใช้สังเกตเห็นได้ง่าย -->
                <svg width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="#ef4444" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="margin: 0 auto 20px auto; display: block;">
                    <circle cx="12" cy="12" r="10"></circle>
                    <line x1="15" y1="9" x2="9" y2="15"></line>
                    <line x1="9" y1="9" x2="15" y2="15"></line>
                </svg>
                <p style="font-size: 16px; margin: 0; padding: 0 10px;"><?= htmlspecialchars($error_msg) ?></p>
            </div>
            <a href="index.php" class="back-btn" style="background-color: #718096; max-width: 150px; margin: 20px auto 0 auto;">กลับหน้าหลัก</a>
        </div>
    <?php else: ?>
        <!-- แสดงกล่องข้อมูลโปรไฟล์ของผู้ใช้งานเมื่อยืนยันตัวตนสำเร็จ -->
        <div class="container">
            <h2>ข้อมูลที่ได้รับจากระบบ Google</h2>
            
            <?php if (!empty($picture)): ?>
            <div class="profile-box">
                <img src="<?=htmlspecialchars($picture)?>" alt="Google Profile" class="profile-img">
            </div>
            <?php endif; ?>
            
            <div class="data-row">
                <div class="data-label">Google ID (sub):</div>
                <div class="data-value"><?=htmlspecialchars($google_id)?></div>
            </div>
            
            <div class="data-row">
                <div class="data-label">ชื่อ-นามสกุล:</div>
                <div class="data-value"><?=htmlspecialchars($fullname)?></div>
            </div>
            
            <div class="data-row">
                <div class="data-label">อีเมล (Email):</div>
                <div class="data-value"><?=htmlspecialchars($email)?></div>
            </div>
            
            <h3 style="margin-top: 25px; font-size: 16px; color: #333;">ข้อมูลดิบจาก Google (Raw JSON):</h3>
            <pre><?=htmlspecialchars(json_encode(json_decode($raw_json, true), JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE))?></pre>
            
            <a href="index.php" class="back-btn">กลับหน้าหลัก</a>
        </div>
    <?php endif; ?>

</body>
</html>
