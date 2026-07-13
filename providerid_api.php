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
function IFNULL($val, $default) {
    return $val !== null ? $val : $default;
}

function getMophIDToken($code) {
    global $moph_id_url, $redirect_uri, $moph_id_Client_ID, $moph_id_Secret_Key;

    $token_url = rtrim($moph_id_url, '/') . '/api/v1/token';
    $postData = [
        'grant_type'    => 'authorization_code',
        'code'          => $code,
        'redirect_uri'  => $redirect_uri,
        'client_id'     => $moph_id_Client_ID,
        'client_secret' => $moph_id_Secret_Key,
    ];

    $ch = curl_init($token_url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query($postData));
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        'Content-Type: application/x-www-form-urlencoded'
    ]);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);

    $response = curl_exec($ch);
    if (curl_errno($ch)) {
        error_log('MOPH ID Token cURL Error: ' . curl_error($ch));
        curl_close($ch);
        return '';
    }
    curl_close($ch);

    $json = json_decode($response, true);
    if (isset($json['data']['access_token'])) {
        return $json['data']['access_token'];
    } elseif (isset($json['access_token'])) {
        return $json['access_token'];
    }
    return '';
}

function getProviderIDToken($moph_id_access_token) {
    global $provider_id_url, $providerID_Client_ID, $providerID_Secret_Key;

    $token_url = rtrim($provider_id_url, '/') . '/api/v1/services/token';
    $postData = [
        'client_id'  => $providerID_Client_ID,
        'secret_key' => $providerID_Secret_Key,
        'token_by'   => 'Health ID',
        'token'      => $moph_id_access_token,
    ];

    $ch = curl_init($token_url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query($postData));
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        'Content-Type: application/x-www-form-urlencoded'
    ]);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);

    $response = curl_exec($ch);
    if (curl_errno($ch)) {
        error_log('Provider ID Token cURL Error: ' . curl_error($ch));
        curl_close($ch);
        return '';
    }
    curl_close($ch);

    $json = json_decode($response, true);
    if (isset($json['data']['access_token'])) {
        return $json['data']['access_token'];
    }
    return '';
}

function getProviderProfile($access_token) {
    global $providerID_Client_ID, $providerID_Secret_Key;

    $url = 'https://provider.id.th/api/v1/services/profile';
    $url .= '?moph_center_token=1&moph_idp_permission=1&position_type=1';

    $headers = [
        'Content-Type: application/json',
        'Authorization: Bearer ' . $access_token,
        'client-id: ' . $providerID_Client_ID,
        'secret-key: ' . $providerID_Secret_Key,        
    ];

    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);

    $response = curl_exec($ch);
    if (curl_errno($ch)) {
        error_log('Provider Profile cURL Error: ' . curl_error($ch));
        curl_close($ch);
        return '';
    }
    curl_close($ch);

    return $response;
}

// Variables for configuration
$moph_id_url = $_ENV['MOPH_ID_URL'] ?? 'https://moph.id.th';
$provider_id_url = $_ENV['PROVIDER_ID_URL'] ?? 'https://provider.id.th';
$moph_id_Client_ID = $_ENV['MOPH_ID_CLIENT_ID'] ?? '';
$moph_id_Secret_Key = $_ENV['MOPH_ID_SECRET_KEY'] ?? '';
$providerID_Client_ID = $_ENV['PROVIDER_ID_CLIENT_ID'] ?? '';
$providerID_Secret_Key = $_ENV['PROVIDER_ID_SECRET_KEY'] ?? '';
$redirect_uri = $_ENV['PROVIDER_ID_REDIRECT_URI'] ?? '';

// Check for callback parameters
$code = $_GET['code'] ?? '';

$title = "ข้อมูลที่ได้รับจากระบบ Provider ID";
$fullname = "";
$provider_id = "";
$email = "";
$hname_th = "";
$position = "";
$raw_json = "";

if ($code === '') {
    // Generate Auth Link
    $link = "{$moph_id_url}/oauth/redirect?client_id={$moph_id_Client_ID}&redirect_uri=" . urlencode($redirect_uri) . "&response_type=code";
    echo "<a href='$link'><img src='./images/providerid.png' width='200' height='100' alt='Login with ProviderID'></a>";
    exit;
} else {
    $access_token = getMophIDToken($code);
    if ($access_token !== '') {
        $providerID_access_token = getProviderIDToken($access_token);
        if ($providerID_access_token !== '') {
            $raw_json = getProviderProfile($providerID_access_token);
            $data = json_decode($raw_json, true);
            
            if (isset($data['data'])) {
                $profile = $data['data'];
                $fullname = IFNULL($profile['name_th'], '');
                $provider_id = IFNULL($profile['provider_id'], '');
                $email = IFNULL($profile['email'], '');
                
                $org = IFNULL($profile['organization'][0] ?? null, []);
                $hname_th = IFNULL($org['hname_th'] ?? '', '');
                $position = IFNULL($org['position'] ?? '', '');
            }
        } else {
            $title = "เกิดข้อผิดพลาดในการดึง Token ของ Provider ID";
        }
    } else {
        $title = "เกิดข้อผิดพลาดในการดึง Token ของ MOPH ID";
    }
}
?>
<!DOCTYPE html>
<html lang="th">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link href="assets/css/fonts.css" rel="stylesheet">
    <title>Provider ID Data Viewer</title>
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
            <div class="data-label">เลขประจำตัววิชาชีพ:</div>
            <div class="data-value"><?=htmlspecialchars($provider_id)?></div>
        </div>
        
        <div class="data-row">
            <div class="data-label">ชื่อ-นามสกุล:</div>
            <div class="data-value"><?=htmlspecialchars($fullname)?></div>
        </div>
        
        <div class="data-row">
            <div class="data-label">อีเมล (Email):</div>
            <div class="data-value"><?=htmlspecialchars($email)?></div>
        </div>

        <div class="data-row">
            <div class="data-label">ตำแหน่ง:</div>
            <div class="data-value"><?=htmlspecialchars($position)?></div>
        </div>

        <div class="data-row">
            <div class="data-label">หน่วยงาน:</div>
            <div class="data-value"><?=htmlspecialchars($hname_th)?></div>
        </div>
        
        <h3 style="margin-top: 25px; font-size: 16px; color: #333;">ข้อมูลดิบจาก Provider ID (Raw JSON):</h3>
        <pre><?=htmlspecialchars(json_encode(json_decode($raw_json, true), JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE))?></pre>
        
        <a href="index.php" class="back-btn">กลับหน้าหลัก</a>
    </div>

</body>
</html>
