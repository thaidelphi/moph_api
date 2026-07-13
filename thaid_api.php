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

function HTTP_POST($url, $token, $data) {
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query($data));
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        'Authorization: ' . $token,
        'Content-Type: application/x-www-form-urlencoded'
    ]);
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
    return HTTP_POST($url_token, $token, $data);
}

function _PARAM($key, $default = "") {
    return $_REQUEST[$key] ?? $default;
}

function randomTextSP($length, $letters = true, $numbers = true, $special = false, $dummy = false) {
    $chars = '';
    if ($letters) $chars .= 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    if ($numbers) $chars .= '0123456789';
    if ($special) $chars .= '!@#$%^&*()';
    if (empty($chars)) $chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    
    $str = '';
    for ($i = 0; $i < $length; $i++) {
        $str .= $chars[rand(0, strlen($chars) - 1)];
    }
    return $str;
}

function kill_injection($text) {
    return addslashes(trim($text));
}

// Database Connection Helper using MySQLi
class mysql_connect {
    private $conn;

    public function __construct($server, $database, $username, $password, $port = 3306) {
        $this->conn = new mysqli($server, $username, $password, $database, $port);
        if ($this->conn->connect_error) {
            die("Connection failed: " . $this->conn->connect_error);
        }
        $this->conn->set_charset("utf8");
    }

    public function getsqlstringdata($sql) {
        $result = $this->conn->query($sql);
        if ($result && $result->num_rows > 0) {
            $row = $result->fetch_row();
            return $row[0];
        }
        return '';
    }

    public function execsql($sql) {
        return $this->conn->query($sql) === TRUE;
    }

    public function close() {
        if ($this->conn) {
            $this->conn->close();
        }
    }
}

// Initialize Default Variables for View
$title = "ลงทะเบียนเข้าใช้งานอินเตอร์เน็ต";
$fullname = "";
$address = "";
$cid = "";
$passwd_rnd = "";

// Database config from Environment Variables
$server = $_ENV['DB_HOST'] ?? 'localhost';
$username = $_ENV['DB_USER'] ?? 'root';
$password = $_ENV['DB_PASS'] ?? '';
$database = $_ENV['DB_NAME'] ?? 'moph_db';

// Connect to Database
$db = new mysql_connect($server, $database, $username, $password, 3306);

$client_id = remove_non_text($_ENV['THAID_CLIENT_ID'] ?? '');
$secret_id = remove_non_text($_ENV['THAID_SECRET_ID'] ?? '');
$redirect_uri = $_ENV['THAID_REDIRECT_URI'] ?? '';
$url_token = $_ENV['THAID_URL_TOKEN'] ?? '';
$url_auth = $_ENV['THAID_URL_AUTH'] ?? '';

// POST handling
if ($_SERVER["REQUEST_METHOD"] == "POST") {
    $newPassword = kill_injection($_POST['newPassword']);
    $pid_ = kill_injection($_POST['pid']);    
    $hashedPassword = $newPassword;
    exit;
}

// GET parameters from login
$code_thaid = _PARAM("code", "");
$state_thaid = _PARAM("state", "");

if (($code_thaid == "") or ($state_thaid == "")) {
    $link = $url_auth.'?response_type=code&client_id='.$client_id.'&redirect_uri='.$redirect_uri.'&scope=pid name address&state=authen';  
    echo "<a href='$link'><img src='./images/thaid.png' width='100' height='100'></a>";
    exit;
} elseif ($state_thaid == "authen") {
    $thaid_data = ThaID_GETDATA($code_thaid, $client_id, $secret_id, $redirect_uri);
    $cid = getjsonvalue($thaid_data, "pid");
    $username = $cid;
    $fullname = getjsonvalue($thaid_data, "name");
    
    $data = json_decode($thaid_data, true);
    $address = $data['address']['formatted'] ?? '';
    
    $old_pass = $db->getsqlstringdata('SELECT passwd FROM person_radius WHERE cid = "'.$cid.'" LIMIT 1;');
    
    $passwd_rnd = randomTextSP(7, true, false, false, false);
    $passwd_rnd = randomTextSP(1, false, false, true, false).$passwd_rnd;   

    if (strlen($old_pass) > 0) {
        $passwd_rnd = $old_pass; 
    }

    $passwd_rnd_base64 = base64_encode($passwd_rnd);
    $username_base64 = base64_encode($username);
    $tmp1 = randomTextSP(225, true, true, true, false);
    $tmp2 = randomTextSP(99, true, true, true, false);
    
    $attribute = "MD5-Password";
    $op = ":=";
    $value = "md5('".$passwd_rnd."')";
    $active = "Y";
    $date_register = "NOW()";
    $date_expire = "DATE_FORMAT(NOW(), '%Y-%m-%d 23:59:59')";
    $note = "Login by thaID";
    
    $asql = "INSERT INTO radcheck_mirror (username, attribute, op, `value`, `tmp_passwd`, `address`, active, date_register, date_expire, note) 
        VALUES ('$username', '$attribute', '$op', $value, '$passwd_rnd', '$address', '$active', $date_register, $date_expire, '$note')";    
    $db->execsql($asql);

    $ccount = $db->getsqlstringdata('SELECT COUNT(*) FROM radcheck WHERE username = "'.$username.'" ');
    if ($ccount <= 0) {
        $asql = "INSERT INTO radcheck (username, attribute, op, `value`) VALUES ('$username', '$attribute', '$op', $value)";         
        $db->execsql($asql);
    } else {
        $asql = "UPDATE radcheck SET attribute = '$attribute', `value` = $value WHERE `username` = '$cid' ";   
        $db->execsql($asql); 
    } 
    
    $db->close();
    header("Location: http://192.168.199.1:8000/state=$tmp1&c0=$username_base64&c1=$passwd_rnd_base64&c3=$tmp2");
    exit();
}

$db->close();
?>
<!DOCTYPE html>
<html lang="th">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link href='https://fonts.googleapis.com/css?family=Sarabun' rel='stylesheet'>
    <title>INTERNET REGISTER</title>
    <style>
        body {
            font-family: 'Sarabun';
            font-size: 15px;
            background-color: #f4f4f4;
            margin: 0;
            padding: 0;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
        }
        .container {
            background-color: #fff;
            padding: 20px;
            box-shadow: 0 0 10px rgba(0, 0, 0, 0.1);
            width: 400px;
            border-radius: 8px;
        }
        h2 {
            text-align: center;
        }
        .user-info {
            text-align: center;
            margin-bottom: 20px;
            font-size: 16px;
            color: #555;
        }
        input[type="password"] {
            font-family: 'Sarabun';
            font-size: 15px;
            width: calc(100% - 20px);
            padding: 10px;
            margin: 10px auto;
            border: 1px solid #ccc;
            border-radius: 4px;
            display: block;
            text-align: center;
        }        
        input[type="submit"] {
            font-family: 'Sarabun';
            font-size: 15px;
            width: 100%;
            padding: 10px;
            margin: 20px auto;
            border: 1px solid #ccc;
            border-radius: 4px;
            background-color: #28a745;
            color: white;
            cursor: pointer;
            display: block;
        }
        input[type="submit"]:hover {
            font-family: 'Sarabun';
            font-size: 15px;
            background-color: #218838;
        }
        .error {
            color: red;
            text-align: center;
            margin-bottom: 10px;
        }
    </style>
</head>
<body>

    <div class="container">
        <h2><?=$title?></h2>
        <div class="user-info">
            <p><strong><?=$fullname?></strong></p>
            <p><strong><?=$address?></strong></p>
        </div>        
        <form id="passwordForm" action="" method="POST" onsubmit="return validatePassword()">                 
            <div class="error" id="error"></div>
            <center>
                <p><strong>AccountName : <?=$cid?></strong></p>
                <p><strong>Password : <?=$passwd_rnd?></strong></p>
                <p><strong>expire : 2024-10-10 23:59</strong></p>
            </center>
            <input type="hidden" id="pid" name="pid" value="<?=$cid?>">
            <input type="submit" value="ตกลง">
        </form>
    </div>

    <script>
        function validatePassword() {
            var newPassword = document.getElementById('newPassword').value;
            var confirmPassword = document.getElementById('confirmPassword').value;
            var errorDiv = document.getElementById('error');

            if (newPassword !== confirmPassword) {
                errorDiv.textContent = "รหัสผ่านใหม่ไม่ตรงกัน";
                return false;
            }

            if (newPassword.length < 8) {
                errorDiv.textContent = "รหัสผ่านใหม่ต้องมีความยาวอย่างน้อย 8 ตัวอักษร";
                return false;
            }

            var hasLetter = /[a-zA-Z]/.test(newPassword);
            var hasNumber = /[0-9]/.test(newPassword);
            if (!hasLetter || !hasNumber) {
                errorDiv.textContent = "รหัสผ่านใหม่ต้องมีทั้งตัวอักษรและตัวเลข";
                return false;
            }

            errorDiv.textContent = "";
            return true;
        }
    </script>
</body>
</html>
