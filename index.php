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
$redirect_uri = $_ENV['THAID_REDIRECT_URI'] ?? '';
$url_auth = $_ENV['THAID_URL_AUTH'] ?? '';
$default_scope = $_ENV['THAID_SCOPE'] ?? 'pid name address';

// Split the scope string from .env to see which ones are checked by default
$active_scopes = explode(' ', $default_scope);
$has_pid = in_array('pid', $active_scopes);
$has_name = in_array('name', $active_scopes);
$has_address = in_array('address', $active_scopes);

$link = $url_auth . '?response_type=code&client_id=' . urlencode($client_id) . '&redirect_uri=' . urlencode($redirect_uri) . '&scope=' . urlencode($default_scope) . '&state=authen';
?>
<!DOCTYPE html>
<html lang="th">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Scan ThaID</title>
    <link href="https://fonts.googleapis.com/css2?family=Sarabun:wght@300;400;500;600;700&display=swap" rel="stylesheet">
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
        .scope-selector {
            text-align: left;
            margin-bottom: 25px;
            background: #f8fafc;
            padding: 15px;
            border-radius: 8px;
            border: 1px solid #e2e8f0;
        }
        .scope-title {
            font-weight: 600;
            font-size: 14px;
            color: #4a5568;
            display: block;
            margin-bottom: 10px;
        }
        .scope-label {
            display: block;
            margin-bottom: 6px;
            font-size: 14px;
            cursor: pointer;
            color: #4a5568;
        }
        .thaid-link {
            display: inline-block;
            transition: transform 0.2s ease;
            margin-top: 10px;
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
        
        <div class="scope-selector">
            <span class="scope-title">เลือกขอบเขตข้อมูล (Scope):</span>
            <label class="scope-label">
                <input type="checkbox" id="scope-pid" value="pid" <?= $has_pid ? 'checked' : '' ?> disabled style="margin-right: 8px;"> pid (เลขบัตรประชาชน)
            </label>
            <label class="scope-label">
                <input type="checkbox" class="scope-opt" id="scope-name" value="name" <?= $has_name ? 'checked' : '' ?> style="margin-right: 8px;"> name (ชื่อ-นามสกุล)
            </label>
            <label class="scope-label">
                <input type="checkbox" class="scope-opt" id="scope-address" value="address" <?= $has_address ? 'checked' : '' ?> style="margin-right: 8px;"> address (ที่อยู่)
            </label>
        </div>

        <a href="<?= htmlspecialchars($link) ?>" id="thaid-btn-link" class="thaid-link">
            <img src="./images/thaid.png" alt="Scan with ThaID" onerror="this.src='https://imauthsbx.bora.dopa.go.th/api/v2/oauth2/auth/favicon.ico';">
        </a>
    </div>

    <script>
        const urlAuth = '<?= $url_auth ?>';
        const clientId = '<?= urlencode($client_id) ?>';
        const redirectUri = '<?= urlencode($redirect_uri) ?>';

        function updateLink() {
            let scopes = ['pid']; // pid is always required
            if (document.getElementById('scope-name').checked) scopes.push('name');
            if (document.getElementById('scope-address').checked) scopes.push('address');
            
            const scopeStr = encodeURIComponent(scopes.join(' '));
            const newLink = `${urlAuth}?response_type=code&client_id=${clientId}&redirect_uri=${redirectUri}&scope=${scopeStr}&state=authen`;
            document.getElementById('thaid-btn-link').href = newLink;
        }

        document.querySelectorAll('.scope-opt').forEach(checkbox => {
            checkbox.addEventListener('change', updateLink);
        });
        
        // Initial run
        updateLink();
    </script>
</body>
</html>
