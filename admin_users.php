<?php
session_start();
// Load .env
$envPath = __DIR__ . '/.env';
$env = [];
if (file_exists($envPath)) {
    $lines = file($envPath, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        if (strpos(trim($line), '#') === 0) continue;
        if (strpos($line, '=') !== false) {
            list($key, $value) = explode('=', $line, 2);
            $env[trim($key)] = trim($value);
        }
    }
}

// Basic Auth
$adminUser = $env['ADMIN_USERNAME'] ?? 'admin';
$adminPass = $env['ADMIN_PASSWORD'] ?? 'password';

if (!isset($_SERVER['PHP_AUTH_USER']) || !isset($_SERVER['PHP_AUTH_PW']) ||
    $_SERVER['PHP_AUTH_USER'] !== $adminUser || $_SERVER['PHP_AUTH_PW'] !== $adminPass) {
    header('WWW-Authenticate: Basic realm="RADIUS Admin Panel"');
    header('HTTP/1.0 401 Unauthorized');
    echo 'Unauthorized Access';
    exit;
}

// DB Connection
$dbHost = $env['DB_HOST'] ?? 'localhost';
$dbUser = $env['DB_USER'] ?? 'root';
$dbPass = $env['DB_PASS'] ?? '';
$dbName = $env['DB_NAME'] ?? 'radius';

try {
    $pdo = new PDO("mysql:host=$dbHost;dbname=$dbName;charset=utf8mb4", $dbUser, $dbPass);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (PDOException $e) {
    die("DB Connection failed: " . $e->getMessage());
}

// API Routes
$action = $_GET['action'] ?? '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    header('Content-Type: application/json');
    $action = $_POST['action'] ?? '';
    
    if ($action === 'add') {
        $username = trim($_POST['username'] ?? '');
        $password = trim($_POST['password'] ?? '');
        if ($username && $password) {
            // Check if exists
            $stmt = $pdo->prepare("SELECT id FROM radcheck WHERE username = ?");
            $stmt->execute([$username]);
            if ($stmt->fetch()) {
                echo json_encode(['success' => false, 'error' => 'Username already exists.']);
                exit;
            }

            $stmt = $pdo->prepare("INSERT INTO radcheck (username, attribute, op, value) VALUES (?, 'Cleartext-Password', '==', ?)");
            $stmt->execute([$username, $password]);
            echo json_encode(['success' => true]);
        } else {
            echo json_encode(['success' => false, 'error' => 'Missing data']);
        }
        exit;
    }
    
    if ($action === 'edit') {
        $id = $_POST['id'] ?? 0;
        $password = trim($_POST['password'] ?? '');
        if ($id && $password) {
            $stmt = $pdo->prepare("UPDATE radcheck SET value = ? WHERE id = ?");
            $stmt->execute([$password, $id]);
            echo json_encode(['success' => true]);
        } else {
            echo json_encode(['success' => false, 'error' => 'Missing data']);
        }
        exit;
    }
    
    if ($action === 'delete') {
        $id = $_POST['id'] ?? 0;
        if ($id) {
            $stmt = $pdo->prepare("DELETE FROM radcheck WHERE id = ?");
            $stmt->execute([$id]);
            echo json_encode(['success' => true]);
        }
        exit;
    }
    
    if ($action === 'toggle_suspend') {
        $id = $_POST['id'] ?? 0;
        $currentAttr = $_POST['attribute'] ?? '';
        if ($id) {
            $newAttr = ($currentAttr === 'Cleartext-Password') ? 'Suspended-Password' : 'Cleartext-Password';
            $stmt = $pdo->prepare("UPDATE radcheck SET attribute = ? WHERE id = ?");
            $stmt->execute([$newAttr, $id]);
            echo json_encode(['success' => true, 'newAttr' => $newAttr]);
        }
        exit;
    }
}

if ($_SERVER['REQUEST_METHOD'] === 'GET' && $action === 'list') {
    header('Content-Type: application/json');
    $stmt = $pdo->query("SELECT * FROM radcheck WHERE attribute IN ('Cleartext-Password', 'Suspended-Password') ORDER BY id DESC");
    $users = $stmt->fetchAll(PDO::FETCH_ASSOC);
    echo json_encode($users);
    exit;
}

?>
<!DOCTYPE html>
<html lang="th">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>RADIUS User Management</title>
    <!-- Fonts -->
    <style>
        :root {
            --bg-color: #0f172a;
            --panel-bg: rgba(30, 41, 59, 0.7);
            --primary: #3b82f6;
            --primary-hover: #2563eb;
            --danger: #ef4444;
            --danger-hover: #dc2626;
            --warning: #f59e0b;
            --success: #10b981;
            --text-main: #f8fafc;
            --text-muted: #94a3b8;
            --border: rgba(255, 255, 255, 0.1);
        }

        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }

        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: var(--bg-color);
            background-image: 
                radial-gradient(at 0% 0%, rgba(59, 130, 246, 0.15) 0px, transparent 50%),
                radial-gradient(at 100% 100%, rgba(16, 185, 129, 0.1) 0px, transparent 50%);
            background-attachment: fixed;
            color: var(--text-main);
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            align-items: center;
            padding: 2rem;
        }

        .container {
            width: 100%;
            max-width: 1000px;
        }

        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 2rem;
            padding-bottom: 1rem;
            border-bottom: 1px solid var(--border);
        }

        .header h1 {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            font-size: 2rem;
            font-weight: 700;
            background: linear-gradient(to right, #60a5fa, #a78bfa);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }

        .btn {
            padding: 0.6rem 1.2rem;
            border: none;
            border-radius: 8px;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            font-weight: 500;
            cursor: pointer;
            transition: all 0.2s ease;
            display: inline-flex;
            align-items: center;
            gap: 0.5rem;
            color: white;
        }

        .btn-primary { background: var(--primary); }
        .btn-primary:hover { background: var(--primary-hover); transform: translateY(-1px); box-shadow: 0 4px 12px rgba(59, 130, 246, 0.3); }
        
        .btn-danger { background: var(--danger); }
        .btn-danger:hover { background: var(--danger-hover); }

        .btn-warning { background: var(--warning); color: #000; }
        .btn-warning:hover { filter: brightness(0.9); }

        .btn-sm {
            padding: 0.4rem 0.8rem;
            font-size: 0.9rem;
        }

        .panel {
            background: var(--panel-bg);
            backdrop-filter: blur(12px);
            -webkit-backdrop-filter: blur(12px);
            border: 1px solid var(--border);
            border-radius: 16px;
            padding: 1.5rem;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.2);
            overflow: hidden;
        }

        .search-bar {
            width: 100%;
            padding: 0.8rem 1rem;
            margin-bottom: 1.5rem;
            background: rgba(15, 23, 42, 0.6);
            border: 1px solid var(--border);
            border-radius: 8px;
            color: white;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            font-size: 1rem;
            outline: none;
            transition: border-color 0.2s;
        }
        .search-bar:focus {
            border-color: var(--primary);
        }

        table {
            width: 100%;
            border-collapse: collapse;
            text-align: left;
        }

        th, td {
            padding: 1rem;
            border-bottom: 1px solid var(--border);
        }

        th {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            font-weight: 600;
            color: var(--text-muted);
            text-transform: uppercase;
            font-size: 0.85rem;
            letter-spacing: 0.05em;
        }

        tbody tr {
            transition: background 0.2s;
        }

        tbody tr:hover {
            background: rgba(255, 255, 255, 0.03);
        }

        .status-badge {
            padding: 0.3rem 0.6rem;
            border-radius: 999px;
            font-size: 0.8rem;
            font-weight: 600;
        }
        .status-active { background: rgba(16, 185, 129, 0.2); color: var(--success); }
        .status-suspended { background: rgba(239, 68, 68, 0.2); color: var(--danger); }

        .actions {
            display: flex;
            gap: 0.5rem;
        }

        /* Modal Styles */
        .modal-backdrop {
            position: fixed;
            top: 0; left: 0; width: 100%; height: 100%;
            background: rgba(0, 0, 0, 0.6);
            backdrop-filter: blur(4px);
            display: flex;
            justify-content: center;
            align-items: center;
            opacity: 0;
            pointer-events: none;
            transition: opacity 0.3s ease;
            z-index: 1000;
        }

        .modal-backdrop.active {
            opacity: 1;
            pointer-events: auto;
        }

        .modal {
            background: #1e293b;
            border: 1px solid var(--border);
            border-radius: 16px;
            width: 100%;
            max-width: 400px;
            padding: 2rem;
            transform: translateY(20px);
            transition: transform 0.3s ease;
            box-shadow: 0 20px 40px rgba(0,0,0,0.4);
        }

        .modal-backdrop.active .modal {
            transform: translateY(0);
        }

        .modal h2 {
            margin-bottom: 1.5rem;
            font-weight: 600;
        }

        .form-group {
            margin-bottom: 1.5rem;
        }

        .form-group label {
            display: block;
            margin-bottom: 0.5rem;
            color: var(--text-muted);
            font-size: 0.9rem;
        }

        .form-group input {
            width: 100%;
            padding: 0.8rem;
            background: rgba(15, 23, 42, 0.8);
            border: 1px solid var(--border);
            border-radius: 8px;
            color: white;
            font-family: inherit;
            outline: none;
        }
        .form-group input:focus { border-color: var(--primary); }

        .modal-actions {
            display: flex;
            justify-content: flex-end;
            gap: 1rem;
        }

        .btn-cancel {
            background: transparent;
            border: 1px solid var(--border);
            color: var(--text-main);
        }
        .btn-cancel:hover { background: rgba(255,255,255,0.05); }

    </style>
</head>
<body>

    <div class="container">
        <div class="header">
            <h1><svg fill="currentColor" viewBox="0 0 20 20" width="1.5em" height="1.5em" style="vertical-align: middle; margin-right: 8px;"><path d="M13 6a3 3 0 11-6 0 3 3 0 016 0zM18 8a2 2 0 11-4 0 2 2 0 014 0zM14 15a4 4 0 00-8 0v3h8v-3zM6 8a2 2 0 11-4 0 2 2 0 014 0zM16 18v-3a5.972 5.972 0 00-.75-2.906A3.005 3.005 0 0119 15v3h-3zM4.75 12.094A5.973 5.973 0 004 15v3H1v-3a3 3 0 013.75-2.906z"/></svg> RADIUS Users</h1>
            <button class="btn btn-primary" onclick="openAddModal()"><svg fill="none" stroke="currentColor" viewBox="0 0 24 24" width="1.2em" height="1.2em" style="vertical-align: middle; margin-right: 4px;" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4"/></svg> เพิ่มผู้ใช้ใหม่</button>
        </div>

        <div class="panel">
            <input type="text" id="searchInput" class="search-bar" placeholder="ค้นหาผู้ใช้งาน (Username)..." onkeyup="filterTable()">
            
            <div style="overflow-x: auto;">
                <table id="usersTable">
                    <thead>
                        <tr>
                            <th>ID</th>
                            <th>Username</th>
                            <th>Password</th>
                            <th>Status</th>
                            <th>Actions</th>
                        </tr>
                    </thead>
                    <tbody id="usersBody">
                        <tr><td colspan="5" style="text-align: center;">Loading...</td></tr>
                    </tbody>
                </table>
            </div>
        </div>
    </div>

    <!-- Modal Form -->
    <div class="modal-backdrop" id="modalBackdrop">
        <div class="modal">
            <h2 id="modalTitle">เพิ่มผู้ใช้ใหม่</h2>
            <input type="hidden" id="userId">
            <div class="form-group">
                <label>Username</label>
                <input type="text" id="username" placeholder="กรอกชื่อผู้ใช้">
            </div>
            <div class="form-group">
                <label>Password</label>
                <input type="text" id="password" placeholder="กรอกรหัสผ่าน">
            </div>
            <div class="modal-actions">
                <button class="btn btn-cancel" onclick="closeModal()">ยกเลิก</button>
                <button class="btn btn-primary" onclick="saveUser()">บันทึก</button>
            </div>
        </div>
    </div>

    <script>
        let allUsers = [];

        async function loadUsers() {
            const res = await fetch('?action=list');
            const data = await res.json();
            allUsers = data;
            renderTable(data);
        }

        function renderTable(users) {
            const tbody = document.getElementById('usersBody');
            tbody.innerHTML = '';
            
            if(users.length === 0) {
                tbody.innerHTML = '<tr><td colspan="5" style="text-align: center; color: #94a3b8;">ไม่พบผู้ใช้งาน</td></tr>';
                return;
            }

            users.forEach(user => {
                const isActive = user.attribute === 'Cleartext-Password';
                const statusHtml = isActive 
                    ? '<span class="status-badge status-active">Active</span>' 
                    : '<span class="status-badge status-suspended">Suspended</span>';
                
                const tr = document.createElement('tr');
                tr.innerHTML = `
                    <td>${user.id}</td>
                    <td style="font-weight: 500;">${escapeHtml(user.username)}</td>
                    <td style="font-family: monospace; color: #94a3b8;">${escapeHtml(user.value)}</td>
                    <td>${statusHtml}</td>
                    <td class="actions">
                        <button class="btn btn-sm btn-primary" onclick="openEditModal(${user.id}, '${escapeHtml(user.value)}')"><svg fill="none" stroke="currentColor" viewBox="0 0 24 24" width="1.2em" height="1.2em" style="vertical-align: middle;" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"/></svg></button>
                        <button class="btn btn-sm btn-warning" onclick="toggleSuspend(${user.id}, '${user.attribute}')">
                            ${isActive ? '<svg fill="none" stroke="currentColor" viewBox="0 0 24 24" width="1.2em" height="1.2em" style="vertical-align: middle;" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636"/></svg>' : '<svg fill="none" stroke="currentColor" viewBox="0 0 24 24" width="1.2em" height="1.2em" style="vertical-align: middle;" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7"/></svg>'}
                        </button>
                        <button class="btn btn-sm btn-danger" onclick="deleteUser(${user.id})"><svg fill="none" stroke="currentColor" viewBox="0 0 24 24" width="1.2em" height="1.2em" style="vertical-align: middle;" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/></svg></button>
                    </td>
                `;
                tbody.appendChild(tr);
            });
        }

        function filterTable() {
            const query = document.getElementById('searchInput').value.toLowerCase();
            const filtered = allUsers.filter(u => u.username.toLowerCase().includes(query));
            renderTable(filtered);
        }

        function escapeHtml(unsafe) {
            return (unsafe||'').replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#039;");
        }

        /* --- Modal Logic --- */
        const modal = document.getElementById('modalBackdrop');
        const mTitle = document.getElementById('modalTitle');
        const mId = document.getElementById('userId');
        const mUser = document.getElementById('username');
        const mPass = document.getElementById('password');

        function openAddModal() {
            mTitle.innerText = "เพิ่มผู้ใช้ใหม่";
            mId.value = "";
            mUser.value = "";
            mUser.disabled = false;
            mPass.value = "";
            modal.classList.add('active');
        }

        function openEditModal(id, currentPass) {
            mTitle.innerText = "แก้ไขรหัสผ่าน";
            mId.value = id;
            const user = allUsers.find(u => parseInt(u.id) === parseInt(id));
            mUser.value = user ? user.username : "";
            mUser.disabled = true;
            mPass.value = currentPass;
            modal.classList.add('active');
        }

        function closeModal() {
            modal.classList.remove('active');
        }

        /* --- API Calls --- */
        async function saveUser() {
            const action = mId.value ? 'edit' : 'add';
            const formData = new FormData();
            formData.append('action', action);
            if(mId.value) formData.append('id', mId.value);
            formData.append('username', mUser.value);
            formData.append('password', mPass.value);

            if(!mPass.value || (!mUser.value && !mId.value)) {
                alert("กรุณากรอกข้อมูลให้ครบถ้วน"); return;
            }

            const res = await fetch('admin_users.php', { method: 'POST', body: formData });
            const data = await res.json();
            if(data.success) {
                closeModal();
                loadUsers();
            } else {
                alert("Error: " + data.error);
            }
        }

        async function deleteUser(id) {
            if(!confirm("ยืนยันการลบผู้ใช้งานนี้?")) return;
            const formData = new FormData();
            formData.append('action', 'delete');
            formData.append('id', id);
            
            await fetch('admin_users.php', { method: 'POST', body: formData });
            loadUsers();
        }

        async function toggleSuspend(id, currentAttr) {
            const actionText = currentAttr === 'Cleartext-Password' ? 'ระงับ' : 'เปิดใช้';
            if(!confirm(`ยืนยันการ${actionText}ผู้ใช้งานนี้?`)) return;
            
            const formData = new FormData();
            formData.append('action', 'toggle_suspend');
            formData.append('id', id);
            formData.append('attribute', currentAttr);
            
            await fetch('admin_users.php', { method: 'POST', body: formData });
            loadUsers();
        }

        // Init
        loadUsers();

    </script>
</body>
</html>
