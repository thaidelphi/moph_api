<?php
// Load Environment Variables from .env file
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
            if (!array_key_exists($name, $_SERVER) && !array_key_exists($name, $_ENV)) {
                putenv("{$name}={$value}");
                $_ENV[$name] = $value;
                $_SERVER[$name] = $value;
            }
        }
    }
}
load_env(__DIR__ . '/.env');

// Helper Functions
function remove_non_text($text) {
    return base64_decode($text);
}

function HTTP_POST($url, $token, $data, $apiKey = null) {
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query($data));
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    
    $headers = [
        'Authorization: ' . $token,
        'Content-Type: application/x-www-form-urlencoded'
    ];
    if ($apiKey) {
        $headers[] = 'x-api-key: ' . $apiKey;
    }
    
    curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
    $response = curl_exec($ch);
    curl_close($ch);
    return $response;
}

function getjsonvalue($json, $key) {    
    $data = json_decode($json, true);    
    if (is_array($data) && array_key_exists($key, $data)) {
        return $data[$key];
    } else {
        return null;
    }
}

function ThaID_GETDATA($code, $client_id, $secret_id, $redirect_uri) {
    global $url_token;
    $token = 'Basic '.base64_encode($client_id.':'.$secret_id);
    $data = [
        'grant_type' => 'authorization_code',
        'code' => $code,
        'redirect_uri'=> $redirect_uri,
    ];
    $apiKey = $_ENV['API_KEY'] ?? null;
    return HTTP_POST($url_token, $token, $data, $apiKey);
}

function _PARAM($key, $default = "") {
    return $_REQUEST[$key] ?? $default;
}

// Variables for display
$title = "ข้อมูลที่ได้รับจากระบบ ThaID";
$fullname = "";
$address = "";
$cid = "";
$raw_json = "";

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
$client_id = $_ENV['THAID_CLIENT_ID'] ?? '';
$secret_id = $_ENV['THAID_SECRET_ID'] ?? '';
$redirect_uri = $_ENV['THAID_REDIRECT_URI'] ?? '';
$url_token = $_ENV['THAID_URL_TOKEN'] ?? '';
$url_auth = $_ENV['THAID_URL_AUTH'] ?? '';

// GET parameters from login
$code_thaid = _PARAM("code", "");
$state_thaid = _PARAM("state", "");

$scope = $_ENV['THAID_SCOPE'] ?? 'pid name address';
if (($code_thaid == "") or ($state_thaid == "")) {
    $link = $url_auth.'?response_type=code&client_id='.$client_id.'&redirect_uri='.$redirect_uri.'&scope='.urlencode($scope).'&state=authen';  
    echo "<a href='$link'><img src='./images/thaid.png' width='100' height='100'></a>";
    exit;
} elseif ($state_thaid == "authen") {
    $thaid_data = ThaID_GETDATA($code_thaid, $client_id, $secret_id, $redirect_uri);
    $cid = getjsonvalue($thaid_data, "pid");
    $fullname = getjsonvalue($thaid_data, "name");
    
    $data = json_decode($thaid_data, true);
    $address = $data['address']['formatted'] ?? '';
    $raw_json = $thaid_data;
}
?>
<!DOCTYPE html>
<html lang="th">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link href="https://fonts.googleapis.com/css2?family=Sarabun:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    <title>ThaID Data Viewer</title>
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
            background-color: #007bff;
            color: white;
            text-decoration: none;
            padding: 10px 20px;
            border-radius: 6px;
            font-weight: 500;
            transition: background 0.2s;
        }
        .back-btn:hover {
            background-color: #0056b3;
        }
    </style>
</head>
<body>

    <div class="container">
        <h2><?=$title?></h2>
        
        <div class="data-row">
            <div class="data-label">เลขบัตรประชาชน (CID):</div>
            <div class="data-value"><?=htmlspecialchars($cid)?></div>
        </div>
        
        <div class="data-row">
            <div class="data-label">ชื่อ-นามสกุล:</div>
            <div class="data-value"><?=htmlspecialchars($fullname)?></div>
        </div>
        
        <div class="data-row">
            <div class="data-label">ที่อยู่ (Address):</div>
            <div class="data-value"><?=htmlspecialchars($address)?></div>
        </div>
        
        <h3 style="margin-top: 25px; font-size: 16px; color: #333;">ข้อมูลดิบจาก ThaID (Raw JSON):</h3>
        <pre><?=htmlspecialchars(json_encode(json_decode($raw_json, true), JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE))?></pre>
        
        <a href="index.php" class="back-btn">กลับหน้าหลัก</a>
    </div>

</body>
</html>
