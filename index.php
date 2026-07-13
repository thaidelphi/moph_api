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
    <title>เข้าสู่ระบบด้วย ThaID - MOPH API</title>
    <link href="https://fonts.googleapis.com/css2?family=Sarabun:wght@300;400;500;600;700&family=Outfit:wght@300;400;600;800&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg-gradient: linear-gradient(135deg, #0f172a 0%, #1e1b4b 50%, #020617 100%);
            --panel-bg: rgba(30, 41, 59, 0.45);
            --panel-border: rgba(255, 255, 255, 0.08);
            --primary: #6366f1;
            --primary-hover: #4f46e5;
            --text-light: #f8fafc;
            --text-muted: #94a3b8;
            --accent: #14b8a6;
        }

        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }

        body {
            font-family: 'Sarabun', 'Outfit', sans-serif;
            background: var(--bg-gradient);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            color: var(--text-light);
            overflow: hidden;
            position: relative;
        }

        /* Ambient light effects */
        body::before {
            content: '';
            position: absolute;
            width: 300px;
            height: 300px;
            background: radial-gradient(circle, rgba(99, 102, 241, 0.15) 0%, transparent 70%);
            top: 20%;
            left: 25%;
            z-index: 0;
        }

        body::after {
            content: '';
            position: absolute;
            width: 350px;
            height: 350px;
            background: radial-gradient(circle, rgba(20, 184, 166, 0.15) 0%, transparent 70%);
            bottom: 15%;
            right: 20%;
            z-index: 0;
        }

        .login-card {
            background: var(--panel-bg);
            backdrop-filter: blur(20px);
            -webkit-backdrop-filter: blur(20px);
            border: 1px solid var(--panel-border);
            border-radius: 24px;
            padding: 40px 30px;
            width: 100%;
            max-width: 440px;
            text-align: center;
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.1);
            z-index: 10;
            position: relative;
            animation: fadeIn 0.8s cubic-bezier(0.16, 1, 0.3, 1);
        }

        @keyframes fadeIn {
            from {
                opacity: 0;
                transform: translateY(20px);
            }
            to {
                opacity: 1;
                transform: translateY(0);
            }
        }

        .logo-container {
            margin-bottom: 24px;
            position: relative;
            display: inline-block;
        }

        .logo-ring {
            position: absolute;
            top: -10px;
            left: -10px;
            right: -10px;
            bottom: -10px;
            border: 2px dashed rgba(99, 102, 241, 0.3);
            border-radius: 50%;
            animation: rotate 20s linear infinite;
        }

        @keyframes rotate {
            from { transform: rotate(0deg); }
            to { transform: rotate(360deg); }
        }

        .moph-logo {
            width: 90px;
            height: 90px;
            background: rgba(15, 23, 42, 0.6);
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            border: 1px solid rgba(255, 255, 255, 0.1);
            padding: 10px;
        }

        .moph-logo svg {
            width: 100%;
            height: 100%;
            fill: var(--accent);
        }

        h1 {
            font-size: 22px;
            font-weight: 600;
            margin-bottom: 12px;
            letter-spacing: -0.5px;
            background: linear-gradient(120deg, #f8fafc 0%, #cbd5e1 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }

        .subtitle {
            font-size: 14px;
            color: var(--text-muted);
            line-height: 1.6;
            margin-bottom: 35px;
        }

        .thaid-btn {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 12px;
            background: linear-gradient(135deg, #1e293b 0%, #0f172a 100%);
            border: 1px solid rgba(255, 255, 255, 0.12);
            color: var(--text-light);
            text-decoration: none;
            padding: 16px 28px;
            border-radius: 16px;
            font-size: 16px;
            font-weight: 500;
            cursor: pointer;
            transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
            position: relative;
            overflow: hidden;
        }

        .thaid-btn::before {
            content: '';
            position: absolute;
            top: 0;
            left: -100%;
            width: 100%;
            height: 100%;
            background: linear-gradient(
                90deg,
                transparent,
                rgba(255, 255, 255, 0.08),
                transparent
            );
            transition: 0.5s;
        }

        .thaid-btn:hover::before {
            left: 100%;
        }

        .thaid-btn:hover {
            transform: translateY(-2px);
            border-color: var(--primary);
            box-shadow: 0 8px 20px rgba(99, 102, 241, 0.25);
            background: linear-gradient(135deg, #273549 0%, #131d2e 100%);
        }

        .thaid-btn:active {
            transform: translateY(1px);
        }

        .thaid-icon {
            width: 32px;
            height: 32px;
            border-radius: 8px;
            object-fit: contain;
            transition: transform 0.3s ease;
        }

        .thaid-btn:hover .thaid-icon {
            transform: scale(1.1);
        }

        .footer {
            margin-top: 35px;
            font-size: 11px;
            color: var(--text-muted);
            border-top: 1px solid rgba(255, 255, 255, 0.05);
            padding-top: 20px;
        }

        .footer a {
            color: var(--accent);
            text-decoration: none;
            transition: color 0.2s ease;
        }

        .footer a:hover {
            color: var(--primary);
            text-decoration: underline;
        }
    </style>
</head>
<body>

    <div class="login-card">
        <div class="logo-container">
            <div class="logo-ring"></div>
            <div class="moph-logo">
                <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
                    <path d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-2 10h-4v4h-2v-4H7v-2h4V7h2v4h4v2z"/>
                </svg>
            </div>
        </div>
        
        <h1>เข้าสู่ระบบด้วย Digital ID</h1>
        <p class="subtitle">ระบบยืนยันตัวตนสำหรับลงทะเบียนเข้าใช้งานอินเตอร์เน็ต<br>สำนักงานสาธารณสุขจังหวัดกำแพงเพชร</p>
        
        <a href="<?= htmlspecialchars($link) ?>" class="thaid-btn">
            <img class="thaid-icon" src="./images/thaid1.png" alt="ThaID Logo" onerror="this.src='https://imauthsbx.bora.dopa.go.th/api/v2/oauth2/auth/favicon.ico';">
            <span>เข้าสู่ระบบด้วย ThaID</span>
        </a>
        
        <div class="footer">
            <p>ความปลอดภัยระดับมาตรฐานภาครัฐตามพระราชบัญญัติคุ้มครองข้อมูลส่วนบุคคล (PDPA)</p>
            <p style="margin-top: 6px;">พัฒนาโดย <a href="https://kpo.moph.go.th" target="_blank">สสจ.กำแพงเพชร</a></p>
        </div>
    </div>

</body>
</html>
