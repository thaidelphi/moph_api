<?php
// โหลด Security Configuration และเริ่มต้น Session
require_once __DIR__ . '/security_config.php';

$env_file = __DIR__ . '/.env';

// ฟังก์ชันสำหรับอ่านตัวแปรทั้งหมดจากไฟล์ .env
function get_env_vars() {
    global $env_file;
    $vars = [];
    if (file_exists($env_file)) {
        $lines = file($env_file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
        foreach ($lines as $line) {
            $line = trim($line);
            if (strpos($line, '#') === 0) continue; // ข้ามบรรทัด Comment
            if (strpos($line, '=') !== false) {
                list($name, $value) = explode('=', $line, 2);
                $vars[trim($name)] = trim($value);
            }
        }
    }
    return $vars;
}

// ฟังก์ชันสำหรับอัปเดตไฟล์ .env โดยรักษา Comment เอาไว้
function update_env($updates) {
    global $env_file;
    if (!is_writable($env_file)) {
        return false;
    }
    $lines = file($env_file);
    $new_lines = [];
    foreach ($lines as $line) {
        $matched = false;
        foreach ($updates as $key => $value) {
            // หากพบคีย์ที่ตรงกัน ให้เปลี่ยนค่า (รองรับบรรทัดที่ไม่มีช่องว่าง)
            if (preg_match("/^" . preg_quote($key, '/') . "=/i", $line)) {
                $new_lines[] = "{$key}={$value}\n";
                $matched = true;
                unset($updates[$key]);
                break;
            }
        }
        if (!$matched) {
            $new_lines[] = $line;
        }
    }
    // เพิ่มคีย์ที่หลงเหลือ (ไม่มีในไฟล์เดิม) ลงท้ายไฟล์
    foreach ($updates as $key => $value) {
        // ให้แน่ใจว่าบรรทัดก่อนหน้ามีการขึ้นบรรทัดใหม่
        if (!empty($new_lines) && substr(end($new_lines), -1) !== "\n") {
            $new_lines[count($new_lines)-1] .= "\n";
        }
        $new_lines[] = "{$key}={$value}\n";
    }
    return file_put_contents($env_file, implode('', $new_lines)) !== false;
}

// โหลดค่า Environment ล่าสุด
$env_vars = get_env_vars();

$error = '';
$success = '';

// ออกจากระบบ
if (isset($_GET['logout'])) {
    unset($_SESSION['admin_logged_in']);
    session_regenerate_id(true);
    header("Location: admin.php");
    exit;
}

// ประมวลผลการเข้าสู่ระบบ
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'login') {
    $username = trim($_POST['username'] ?? '');
    $password = trim($_POST['password'] ?? '');
    
    $admin_user = $env_vars['ADMIN_USERNAME'] ?? 'admin';
    $admin_pass = $env_vars['ADMIN_PASSWORD'] ?? 'password123';
    
    if ($username === $admin_user && $password === $admin_pass) {
        session_regenerate_id(true); // ป้องกัน Session Fixation
        $_SESSION['admin_logged_in'] = true;
        header("Location: admin.php");
        exit;
    } else {
        $error = "ชื่อผู้ใช้งานหรือรหัสผ่านไม่ถูกต้อง";
    }
}

// ตรวจสอบสถานะการเข้าสู่ระบบ
$is_logged_in = !empty($_SESSION['admin_logged_in']);

// ประมวลผลการบันทึกการตั้งค่า
if ($is_logged_in && $_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'save_settings') {
    $updates = [];
    foreach ($_POST as $key => $value) {
        if ($key === 'action') continue;
        $updates[$key] = trim($value);
    }
    
    if (update_env($updates)) {
        $success = "บันทึกการตั้งค่าเรียบร้อยแล้ว";
        $env_vars = get_env_vars(); // โหลดข้อมูลใหม่
    } else {
        $error = "ไม่สามารถบันทึกไฟล์ .env ได้ กรุณาตรวจสอบสิทธิ์ของไฟล์ (chmod 666)";
    }
}
?>
<!DOCTYPE html>
<html lang="th">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>System Administration</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Sarabun:wght@400;500;600&display=swap" rel="stylesheet">
    <style>
        :root {
            --primary: #4f46e5;
            --primary-hover: #4338ca;
            --bg-color: #0f172a;
            --card-bg: rgba(30, 41, 59, 0.7);
            --text-main: #f8fafc;
            --text-muted: #94a3b8;
            --border-color: rgba(255, 255, 255, 0.1);
            --input-bg: rgba(15, 23, 42, 0.6);
            --danger: #ef4444;
            --success: #10b981;
        }

        body {
            font-family: 'Inter', 'Sarabun', sans-serif;
            background: linear-gradient(135deg, #0f172a 0%, #1e1b4b 100%);
            color: var(--text-main);
            margin: 0;
            padding: 0;
            min-height: 100vh;
            display: flex;
            flex-direction: column;
        }

        /* Glassmorphism Classes */
        .glass {
            background: var(--card-bg);
            backdrop-filter: blur(12px);
            -webkit-backdrop-filter: blur(12px);
            border: 1px solid var(--border-color);
            border-radius: 16px;
        }

        /* Container & Layout */
        .container {
            max-width: 1000px;
            margin: 40px auto;
            padding: 0 20px;
            flex-grow: 1;
            width: 100%;
            box-sizing: border-box;
        }

        .login-container {
            max-width: 400px;
            margin: 10vh auto;
            padding: 40px;
            text-align: center;
            box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5);
        }

        /* Typography */
        h1, h2, h3 {
            margin-top: 0;
            font-weight: 600;
        }
        
        .header-title {
            font-size: 1.5rem;
            margin-bottom: 30px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        /* Forms */
        .form-group {
            margin-bottom: 20px;
            text-align: left;
        }

        label {
            display: block;
            margin-bottom: 8px;
            font-size: 0.9rem;
            color: var(--text-muted);
            font-weight: 500;
        }

        input[type="text"], input[type="password"] {
            width: 100%;
            padding: 12px 16px;
            background: var(--input-bg);
            border: 1px solid var(--border-color);
            color: #fff;
            border-radius: 8px;
            font-family: 'Inter', sans-serif;
            font-size: 1rem;
            box-sizing: border-box;
            transition: all 0.3s ease;
        }

        input[type="text"]:focus, input[type="password"]:focus {
            outline: none;
            border-color: var(--primary);
            box-shadow: 0 0 0 3px rgba(79, 70, 229, 0.2);
        }

        /* Buttons */
        .btn {
            background: var(--primary);
            color: #fff;
            border: none;
            padding: 12px 24px;
            border-radius: 8px;
            font-size: 1rem;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s ease;
            text-decoration: none;
            display: inline-block;
        }

        .btn:hover {
            background: var(--primary-hover);
            transform: translateY(-2px);
            box-shadow: 0 10px 15px -3px rgba(79, 70, 229, 0.4);
        }
        
        .btn-outline {
            background: transparent;
            border: 1px solid var(--border-color);
            color: var(--text-main);
        }
        
        .btn-outline:hover {
            background: rgba(255,255,255,0.1);
            box-shadow: none;
        }

        .btn-block {
            width: 100%;
            display: block;
        }

        /* Dashboard Layout */
        .dashboard-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 24px;
        }

        .section-card {
            padding: 24px;
            box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.3);
            transition: transform 0.3s ease;
        }
        
        .section-card:hover {
            transform: translateY(-5px);
        }

        .section-title {
            font-size: 1.1rem;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 1px solid var(--border-color);
            color: var(--primary);
        }

        /* Alerts & Toasts */
        .alert {
            padding: 16px;
            border-radius: 8px;
            margin-bottom: 24px;
            font-weight: 500;
            animation: slideDown 0.5s ease;
        }
        
        .alert-danger {
            background: rgba(239, 68, 68, 0.1);
            border: 1px solid var(--danger);
            color: #fca5a5;
        }
        
        .alert-success {
            background: rgba(16, 185, 129, 0.1);
            border: 1px solid var(--success);
            color: #6ee7b7;
        }

        /* Actions Bar */
        .actions-bar {
            margin-top: 30px;
            padding: 20px;
            text-align: right;
            position: sticky;
            bottom: 20px;
            z-index: 100;
            box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.5);
        }

        @keyframes slideDown {
            from { opacity: 0; transform: translateY(-20px); }
            to { opacity: 1; transform: translateY(0); }
        }
        
        /* Helper functions for rendering inputs */
        <?php
        function renderInput($label, $name, $value, $type = 'text', $is_password = false) {
            $safe_value = htmlspecialchars($value ?? '', ENT_QUOTES, 'UTF-8');
            $input_type = $is_password ? 'password' : $type;
            echo "<div class=\"form-group\">";
            echo "<label for=\"{$name}\">{$label}</label>";
            echo "<input type=\"{$input_type}\" id=\"{$name}\" name=\"{$name}\" value=\"{$safe_value}\" required>";
            echo "</div>";
        }
        ?>
    </style>
</head>
<body>
    <div class="container">
        <?php if (!empty($error)): ?>
            <div class="alert alert-danger"><?= htmlspecialchars($error, ENT_QUOTES, 'UTF-8') ?></div>
        <?php endif; ?>
        
        <?php if (!empty($success)): ?>
            <div class="alert alert-success"><?= htmlspecialchars($success, ENT_QUOTES, 'UTF-8') ?></div>
        <?php endif; ?>

        <?php if (!$is_logged_in): ?>
            <!-- Login Interface -->
            <div class="login-container glass">
                <h2 style="margin-bottom: 30px;">System Admin</h2>
                <form method="post" action="admin.php">
                    <input type="hidden" name="action" value="login">
                    <div class="form-group">
                        <label for="username">Username</label>
                        <input type="text" id="username" name="username" required autofocus>
                    </div>
                    <div class="form-group">
                        <label for="password">Password</label>
                        <input type="password" id="password" name="password" required>
                    </div>
                    <button type="submit" class="btn btn-block" style="margin-top: 30px;">Login securely</button>
                </form>
            </div>
            
        <?php else: ?>
            <!-- Dashboard Interface -->
            <div class="header-title">
                <h2>Configuration Dashboard</h2>
                <a href="admin.php?logout=1" class="btn btn-outline">Logout</a>
            </div>
            
            <form method="post" action="admin.php">
                <input type="hidden" name="action" value="save_settings">
                
                <div class="dashboard-grid">
                    
                    <!-- Admin Credentials -->
                    <div class="section-card glass">
                        <h3 class="section-title">Admin Credentials</h3>
                        <?php 
                        renderInput('Admin Username', 'ADMIN_USERNAME', $env_vars['ADMIN_USERNAME'] ?? ''); 
                        renderInput('Admin Password', 'ADMIN_PASSWORD', $env_vars['ADMIN_PASSWORD'] ?? ''); 
                        ?>
                    </div>

                    <!-- Database -->
                    <div class="section-card glass">
                        <h3 class="section-title">Database Settings</h3>
                        <?php 
                        renderInput('Host', 'DB_HOST', $env_vars['DB_HOST'] ?? ''); 
                        renderInput('User', 'DB_USER', $env_vars['DB_USER'] ?? ''); 
                        renderInput('Password', 'DB_PASS', $env_vars['DB_PASS'] ?? ''); 
                        renderInput('Database Name', 'DB_NAME', $env_vars['DB_NAME'] ?? ''); 
                        ?>
                    </div>
                    
                    <!-- FortiGate -->
                    <div class="section-card glass">
                        <h3 class="section-title">FortiGate Captive Portal</h3>
                        <?php 
                        renderInput('FortiGate Auth URL', 'FORTIGATE_AUTH_URL', $env_vars['FORTIGATE_AUTH_URL'] ?? ''); 
                        ?>
                    </div>

                    <!-- ThaID OAuth -->
                    <div class="section-card glass">
                        <h3 class="section-title">ThaID OAuth</h3>
                        <?php 
                        renderInput('API Key', 'THAID_API_KEY', $env_vars['THAID_API_KEY'] ?? ''); 
                        renderInput('Client ID', 'THAID_CLIENT_ID', $env_vars['THAID_CLIENT_ID'] ?? ''); 
                        renderInput('Secret ID', 'THAID_SECRET_ID', $env_vars['THAID_SECRET_ID'] ?? ''); 
                        renderInput('Redirect URI', 'THAID_REDIRECT_URI', $env_vars['THAID_REDIRECT_URI'] ?? ''); 
                        ?>
                    </div>

                    <!-- ProviderID / MOPH ID -->
                    <div class="section-card glass">
                        <h3 class="section-title">ProviderID / MOPH ID</h3>
                        <?php 
                        renderInput('ProviderID Client ID', 'PROVIDER_ID_CLIENT_ID', $env_vars['PROVIDER_ID_CLIENT_ID'] ?? ''); 
                        renderInput('ProviderID Secret Key', 'PROVIDER_ID_SECRET_KEY', $env_vars['PROVIDER_ID_SECRET_KEY'] ?? ''); 
                        renderInput('Redirect URI', 'PROVIDER_ID_REDIRECT_URI', $env_vars['PROVIDER_ID_REDIRECT_URI'] ?? ''); 
                        ?>
                    </div>
                    
                    <!-- Google OAuth -->
                    <div class="section-card glass">
                        <h3 class="section-title">Google OAuth 2.0</h3>
                        <?php 
                        renderInput('Client ID', 'GOOGLE_CLIENT_ID', $env_vars['GOOGLE_CLIENT_ID'] ?? ''); 
                        renderInput('Client Secret', 'GOOGLE_CLIENT_SECRET', $env_vars['GOOGLE_CLIENT_SECRET'] ?? ''); 
                        renderInput('Redirect URI', 'GOOGLE_REDIRECT_URI', $env_vars['GOOGLE_REDIRECT_URI'] ?? ''); 
                        ?>
                    </div>

                </div>
                
                <!-- Sticky Actions Bar -->
                <div class="actions-bar glass" style="margin-bottom: 40px;">
                    <button type="submit" class="btn">Save Configuration</button>
                </div>
            </form>
        <?php endif; ?>
    </div>
</body>
</html>
