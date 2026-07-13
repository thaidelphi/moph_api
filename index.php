<?php
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
            if (!array_key_exists($name, $_SERVER) && !array_key_exists($name, $_ENV)) {
                putenv("{$name}={$value}");
                $_ENV[$name] = $value;
                $_SERVER[$name] = $value;
            }
        }
    }
}
load_env(__DIR__ . '/.env');

// Helper to decode Base64 key
function remove_non_text($text) {
    return base64_decode($text);
}

$dev_sand_box = filter_var($_ENV['DEV_SANDBOX'] ?? 'true', FILTER_VALIDATE_BOOLEAN);

if (isset($_ENV['THAID_CLIENT_ID']) && $_ENV['THAID_CLIENT_ID'] !== '') {
    $client_id = remove_non_text($_ENV['THAID_CLIENT_ID']);
    $redirect_uri = $_ENV['THAID_REDIRECT_URI'] ?? '';
    $url_auth = $_ENV['THAID_URL_AUTH'] ?? '';
} else {
    if ($dev_sand_box == true) {
        $client_id = remove_non_text('MlBDd0dKVjBJN2gwNDlQRXZYN0pxdGozZzBjb3VCWWQ');
        $redirect_uri = "https://mis.kpo.go.th/systemapi/internet_authen_snb.php";  
        $url_auth = 'https://imauthsbx.bora.dopa.go.th/api/v2/oauth2/auth/';
    } else {
        $client_id = remove_non_text('Z0ZiTXJoaHhwUWRtUnhoNVVtREliZUNFMUpWT1c2TjY');
        $redirect_uri = "https://mis.kpo.go.th/systemapi/internet_authen_snb.php";  
        $url_auth = 'https://imauth.bora.dopa.go.th/api/v2/oauth2/auth/';    
    }
}

$link = $url_auth . '?response_type=code&client_id=' . urlencode($client_id) . '&redirect_uri=' . urlencode($redirect_uri) . '&scope=pid%20name%20address&state=authen';
?>
<!DOCTYPE html>
<html lang="th">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Scan ThaID</title>
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
            max-width: 400px;
            width: 100%;
        }
        .thaid-link {
            display: inline-block;
            transition: transform 0.2s ease;
            margin-top: 20px;
        }
        .thaid-link:hover {
            transform: scale(1.05);
        }
        img {
            width: 150px;
            height: auto;
            cursor: pointer;
        }
        h2 {
            color: #333;
            margin-bottom: 10px;
            font-size: 20px;
        }
        p {
            color: #666;
            font-size: 14px;
            margin-bottom: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h2>ลงทะเบียนเข้าใช้งานอินเตอร์เน็ต</h2>
        <p>คลิกรูปภาพด้านล่างเพื่อยืนยันตัวตนด้วย ThaID</p>
        <a href="<?= htmlspecialchars($link) ?>" class="thaid-link">
            <img src="./images/thaid.png" alt="Scan with ThaID" onerror="this.src='https://imauthsbx.bora.dopa.go.th/api/v2/oauth2/auth/favicon.ico';">
        </a>
    </div>
</body>
</html>
