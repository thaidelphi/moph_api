<?php
  // https://mis.kpo.go.th/systemapi/internet_authen_by_providerid.php
ini_set('display_errors', 1); // เปิดการแสดงข้อผิดพลาด
//ini_set('display_errors', 0); // ปิดการแสดงข้อผิดพลาด
error_reporting(~0); // แสดงข้อผิดพลาดทั้งหมด
//error_reporting(~1);  // แสดงข้อผิดพลาดทั้งหมด ยกเว้น E_NOTICE

session_start();  // เริ่มต้น session เพื่อเก็บข้อมูลผู้ใช้

include("func.php"); // รวมไฟล์ฟังก์ชันที่ใช้ในสคริปต์นี้
include("mysql_connect.inc.php");  // รวมไฟล์เชื่อมต่อฐานข้อมูล MySQL

$con_server   = "168.148.62.15";
$con_username = "root";
$con_password = "ssjkp#62@62"; 
$con_database = "radius";
$conn_port = 3306;

$db = new mysql_connect($con_server, $con_database, $con_username, $con_password, $conn_port);
$dev_sand_box = false;
if ( $dev_sand_box == true ) {
    // $client_id = remove_non_text('MlBDd0dKVjBJN2gwNDlQRXZYN0pxdGozZzBjb3VCWWQ');
    // $secret_id = remove_non_text('NlNhRHBUQ21PblhYd3B4elNXUnhIVjlNcEpFVWV2TTNiaDZMN2NFMA');
    // $redirect_uri = "https://mis.kpo.go.th/systemapi/internet_authen_snb.php";  
    // $url_token = 'https://imauthsbx.bora.dopa.go.th/api/v2/oauth2/token/';
    // $url_auth = 'https://imauthsbx.bora.dopa.go.th/api/v2/oauth2/auth/';
} else {
    // $secret_id = remove_non_text('Z2JJV0NHRFREcEo4cmZxeUhwckoyQ2JURlNlb0J6OG4ycGgyc3lCMg');
    // $client_id = remove_non_text('Z0ZiTXJoaHhwUWRtUnhoNVVtREliZUNFMUpWT1c2TjY');
    // $redirect_uri = "https://mis.kpo.go.th/systemapi/internet_authen_snb.php";  
    // $url_token = 'https://imauth.bora.dopa.go.th/api/v2/oauth2/token/';
    // $url_auth = 'https://imauth.bora.dopa.go.th/api/v2/oauth2/auth/';    

	//$redirect_uri := 'http://localhost:16222';
    $redirect_uri = 'https://mis.kpo.go.th/systemapi/internet_authen_by_providerid.php';  // URL สำหรับ redirect หลังจากล็อกอินสำเร็จ
	$moph_id_url = 'https://moph.id.th' ;  // URL สำหรับ MOPH ID
    $provider_id_url = 'https://provider.id.th'; // URL สำหรับ Provider ID
    $moph_id_Client_ID = '019613c0-1da3-70f6-a917-fa985f66d0dc';  // MOPH ID Client ID
    $moph_id_Secret_Key = '324bdcba49a5b21c515c8882acdf8ff9a8dddbf6';  // MOPH ID Secret Key
    $providerID_Client_ID = '69157fab-8334-4906-a5f2-54267db8ced1';  // Provider ID Client ID
    $providerID_Secret_Key = 'xnyEkLGY3ed3L1bNmatBSKQoiXZSgXJD';  // Provider ID Secret Key

    $url_auth = $moph_id_url;
}


function getjsonvalue($json, $key) {    // ฟังก์ชันนี้ใช้เพื่อดึงค่า value จาก JSON string ตาม key ที่ระบุ
    $data = json_decode($json, true);    // แปลง JSON string เป็น array
    if (is_array($data) && array_key_exists($key, $data)) {  // ตรวจสอบว่า $data เป็น array และมี key ที่ระบุอยู่หรือไม่
        return $data[$key];  // คืนค่าที่ตรงกับ key ที่ระบุ
    } else {
        return null;  // ถ้าไม่พบ key ให้คืนค่า null
    }
}

// function ThaID_GETDATA( $code, $client_id, $secret_id, $redirect_uri ) {
//     //gloval $url_token = 'https://imauth.bora.dopa.go.th/api/v2/oauth2/token/';
//     global  $url_token;
//     $token = 'Basic '.base64_encode($client_id.':'.$secret_id);
//       // Replace with your actual token
//       $data = [
//         'grant_type' => 'authorization_code',
//         'code' => $code,
//         'redirect_uri'=> $redirect_uri,
//         //'redirect_uri'=> 'https://kpo.moph.go.th/callback/kpothaid.php',
//       ];
//       //print_r($data);
//       return HTTP_POST($url_token, $token, $data);
// }


function getMophIDToken($code) { // ฟังก์ชันนี้ใช้เพื่อดึง access token ของ MOPH ID โดยใช้ authorization code ที่ได้จากการล็อกอิน
    global $moph_id_url, $redirect_uri, $moph_id_Client_ID, $moph_id_Secret_Key;

    $token_url = rtrim($moph_id_url, '/') . '/api/v1/token'; // URL สำหรับขอ access token ของ MOPH ID

    $postData = [  // ข้อมูลที่ต้องส่งไปยัง MOPH ID
        'grant_type'    => 'authorization_code',
        'code'          => $code,
        'redirect_uri'  => $redirect_uri,
        'client_id'     => $moph_id_Client_ID,
        'client_secret' => $moph_id_Secret_Key,
    ];

    $ch = curl_init($token_url); // เริ่มต้น cURL session
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true); // คืนค่าผลลัพธ์เป็นสตริง
    curl_setopt($ch, CURLOPT_POST, true);  // ใช้ POST method
    curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query($postData));  // แปลงข้อมูลเป็น query string
    curl_setopt($ch, CURLOPT_HTTPHEADER, [  // กำหนด header สำหรับ cURL
        'Content-Type: application/x-www-form-urlencoded'
    ]);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, true); // เปิดไว้เสมอถ้าใช้ HTTPS จริง

    $response = curl_exec($ch);  // ส่งคำขอและรับผลลัพธ์
    if (curl_errno($ch)) {  // ตรวจสอบข้อผิดพลาดของ cURL
        echo 'CURL Error: ' . curl_error($ch);
        curl_close($ch);
        return '';
    }
    curl_close($ch);  //    ปิด cURL session

    $json = json_decode($response, true); // แปลง response JSON เป็น array

    // echo '<pre>';
    // var_dump($json);
    // echo '</pre>';

    if (isset($json['data']['access_token'])) {
        return $json['data']['access_token'];
    } elseif (isset($json['access_token'])) {
        return $json['access_token']; // เผื่อกรณีที่ไม่ได้อยู่ใน 'data'
    }

    // ตรวจสอบ error message เผื่อช่วย debug
    // if (isset($json['error_description'])) {
    //     echo 'Error: ' . htmlspecialchars($json['error_description']);
    // } elseif (isset($json['error'])) {
    //     echo 'Error: ' . htmlspecialchars($json['error']);
    // }

    //return '';
}

function getProviderIDToken($moph_id_access_token) { // ฟังก์ชันนี้ใช้เพื่อดึง access token ของ Provider ID โดยใช้ access token ของ MOPH ID
    global $provider_id_url, $providerID_Client_ID, $providerID_Secret_Key;

    $token_url = rtrim($provider_id_url, '/') . '/api/v1/services/token'; // URL สำหรับขอ access token ของ Provider ID

    $postData = [  // ข้อมูลที่ต้องส่งไปยัง Provider ID
        'client_id'  => $providerID_Client_ID,
        'secret_key' => $providerID_Secret_Key,
        'token_by'   => 'Health ID',
        'token'      => $moph_id_access_token,
    ];

    $ch = curl_init($token_url); // เริ่มต้น cURL session
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true); // คืนค่าผลลัพธ์เป็นสตริง
    curl_setopt($ch, CURLOPT_POST, true); // ใช้ POST method
    curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query($postData)); // แปลงข้อมูลเป็น query string
    curl_setopt($ch, CURLOPT_HTTPHEADER, [ // กำหนด header สำหรับ cURL
        'Content-Type: application/x-www-form-urlencoded'
    ]);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, true); // แนะนำเปิดใช้งานใน production

    $response = curl_exec($ch); // ส่งคำขอและรับผลลัพธ์
    if (curl_errno($ch)) {  // ตรวจสอบข้อผิดพลาดของ cURL
        echo 'CURL Error: ' . curl_error($ch);
        curl_close($ch);
        return '';
    }
    curl_close($ch);

    // แปลง response JSON เป็น array
    $json = json_decode($response, true); // ถ้าใช้ PHP 7.1 ขึ้นไป สามารถใช้ JSON_THROW_ON_ERROR ได้

    // echo '<pre>';
    // var_dump($json);
    // echo '</pre>';

    // echo response (เพื่อ debug เหมือน Delphi ใช้ echo)
    // echo "<pre>ProviderID Response:\n";
    // print_r($json);
    // echo "</pre>";

    if (isset($json['data']['access_token'])) { // ตรวจสอบว่ามี access token ใน response หรือไม่
        return $json['data']['access_token']; // ถ้ามี ให้คืนค่า access token
        exit; // ออกจากฟังก์ชันหลังจากคืนค่าแล้ว
    }
    return '';
}

function getProviderProfile($access_token) { // ฟังก์ชันนี้ใช้เพื่อดึงข้อมูลโปรไฟล์จาก Provider ID โดยใช้ access token ที่ได้จาก MOPH ID
    global $providerID_Client_ID, $providerID_Secret_Key; // ใช้ตัวแปร global เพื่อเข้าถึงค่าที่กำหนดไว้ข้างนอกฟังก์ชัน

    $url = 'https://provider.id.th/api/v1/services/profile';
    $url .= '?moph_center_token=1&moph_idp_permission=1&position_type=1'; // เพิ่มพารามิเตอร์ตามที่ต้องการ

    $headers = [ // กำหนด header สำหรับ cURL
        'Content-Type: application/json',
        'Authorization: Bearer ' . $access_token,
        'client-id: ' . $providerID_Client_ID,
        'secret-key: ' . $providerID_Secret_Key,        
    ];

    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true); // คืนค่าผลลัพธ์เป็นสตริง
    curl_setopt($ch, CURLOPT_HTTPHEADER, $headers); // ตั้งค่า header
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, true); // เปิดใช้งานเมื่อใช้ HTTPS จริง

    $response = curl_exec($ch); // ส่งคำขอและรับผลลัพธ์
    if (curl_errno($ch)) { // ตรวจสอบข้อผิดพลาดของ cURL
        echo 'CURL Error: ' . curl_error($ch);
        curl_close($ch);
        return '';
    }
    curl_close($ch); // ปิด cURL

    // echo "<pre>Provider Profile Response:\n";
    // print_r(json_decode($response, true));
    // echo "</pre>";

    return $response;
}


// ถ้าส่งมาโดย POST 
if ($_SERVER["REQUEST_METHOD"] == "POST") {
    //print_r($_POST);
    $newPassword = kill_injection( $_POST['newPassword'] );
    $pid_ = kill_injection( $_POST['pid'] );    
    // แฮชรหัสผ่านใหม่
    $hashedPassword = $newPassword;//password_hash($newPassword, PASSWORD_DEFAULT);
    // อัปเดตฐานข้อมูล
    // $sql = "UPDATE person SET passwd = '$hashedPassword', passwd_md5 = md5('".$newPassword."') WHERE cid = '$pid_'"; // 
    // if ( $db->execsql( $sql ) === true ) {
    // //if ($conn->query($sql) === TRUE) {
    //     echo "เปลี่ยนรหัสผ่านสำเร็จ";        
    //     header("Location: https://kpo.moph.go.th");
    // } else {
    //     //echo "เกิดข้อผิดพลาด: " . $conn->error;
    // }    
    // //echo $sql;
    // exit;
}

// function IFFF($value, $default) {
//    // return isset($value) ? $value : $default;
//    if ( isset($value) ) {
//        return $value;
//    } else {
//        return $default;
//    }
// }


//$code_thaid = _PARAM("code", "");
//$state_thaid = _PARAM("state", "");
// echo $state_thaid;
$referer = $_SERVER['REQUEST_URI']; // ดึง URL ปัจจุบัน (referer) เพื่อใช้ตรวจสอบ
// print_r( $_SERVER );//['HTTP_REFERER'];

//if(( $code_thaid == "" ) or ( $state_thaid == "" ) and ( $referer == '' ) ){
$code = ""; // กำหนดค่าเริ่มต้นเป็นว่าง
if ( $referer == '/systemapi/internet_authen_by_providerid.php' ) { 
    $tmp = '{HealthID-URL}/oauth/redirect?client_id={client_id}&redirect_uri={redirect_uri}&response_type=code';
    $tmp = str_replace('{HealthID-URL}', $moph_id_url, $tmp);  // แทนที่ {HealthID-URL} ด้วย URL ของ MOPH ID
    $tmp = str_replace('{client_id}', $moph_id_Client_ID, $tmp);  // แทนที่ {client_id} ด้วย Client ID ของ MOPH ID
    $tmp = str_replace('{redirect_uri}', urlencode($redirect_uri), $tmp);   // แทนที่ {redirect_uri} ด้วย URL ที่กำหนดไว้
    $link =  $tmp;
    echo "<a href='$link'><img src='./images/providerid.png' width='200' height='100'></a>";	// แสดง Logo ของ Provider ID	
    exit;  // ออกจากสคริปต์ถ้า referer เป็นหน้า Logo ของ Provider ID
} else { // ถ้า referer ไม่ใช่หน้า Logo ของ Provider ID
    $parsedUrl = parse_url($referer); // แยก URL เพื่อดึง query string
    if (isset($parsedUrl['query'])) { // ตรวจสอบว่ามี query string หรือไม่
        parse_str($parsedUrl['query'], $params); // แปลง query string เป็น array
        if (isset($params['code'])) { // ตรวจสอบว่ามี key 'code' ใน array หรือไม่
            $code = $params['code']; // ถ้ามี key 'code' ให้เก็บค่าไว้ในตัวแปร $code
        }
    }
}
//if ( $referer != '/systemapi/internet_authen_by_providerid.php' ) {
if ( strlen( $code ) > 0  ) { // ถ้ามี code ใน referer หรือมีการส่ง code มาจาก Provider ID
    //echo $referer."<br/>";    
    if ($code !== '') { // ถ้ามี code ใน referer ได้จากเมื่อผู้ใช้ล็อกอินผ่าน MOPH ID
        //echo "Code: " . htmlspecialchars($code); // GetMOPHIDToken
        $access_token = getMophIDToken( $code ); //ใช้ code ที่ได้จาก MOPH ID เพื่อขอ access token
        //echo "<br/>access_token=".$access_token;
        if ( $access_token != '' ) { // ถ้าได้ access token ของ MOPH ID มาแล้ว
            $providerID_access_token = getProviderIDToken( $access_token ); // ใช้ access token เพื่อขอ access token ของ Provider ID
            //echo "<br/>providerID_access_token=".$providerID_access_token;
            if ( $providerID_access_token != '' ) {                                
                $tmp = getProviderProfile( $providerID_access_token ); // ใช้ access token ของ Provider ID เพื่อดึงข้อมูลโปรไฟล์
                //echo $tmp."<br/>";
                $data = json_decode($tmp, true); // แปลง JSON เป็น array
                // ดึงค่าที่ต้องการ
                $providerID = IFNULL($data['data']['provider_id'], ''); // 
                $position   = IFNULL($data['data']['organization'][0]['position'], '');// ?? '';
                $email      = IFNULL($data['data']['email'], '');// ?? '';
                $hname_th   = IFNULL($data['data']['organization'][0]['hname_th'], '');// ?? '';
                $hash_cid   = IFNULL($data['data']['hash_cid'], '');// ?? '';
                $account_id = IFNULL($data['data']['account_id'], '');// ?? '';
                $name_th    = IFNULL($data['data']['name_th'], '');// ?? '';
                
                // // แสดงผล
                // echo "📌 providerID: $providerID<br>";
                // echo "📌 ตำแหน่ง: $position<br>";
                // echo "📧 Email: $email<br>";
                // echo "🏥 หน่วยงาน: $hname_th<br>";
                // echo "🧬 Hash CID: $hash_cid<br>";
                // echo "🆔 Account ID: $account_id<br>";
                // echo "👤 ชื่อ-นามสกุล: $name_th<br>";

                // ดึงข้อมูลเข้าตัวแปร
                $ial_level        = IFNULL( $data['data']['ial_level'] , '' );
                $account_id       = IFNULL( $data['data']['account_id'] , '' );
                $hash_cid         = IFNULL( $data['data']['hash_cid'] , '' );
                $provider_id      = IFNULL( $data['data']['provider_id'] , '' );
                $title_th         = IFNULL( $data['data']['title_th'] , '' );
                $special_title_th = IFNULL( $data['data']['special_title_th'] , '' );
                $name_th          = IFNULL( $data['data']['name_th'] , '' );
                $name_eng         = IFNULL( $data['data']['name_eng'] , '' );
                $created_at       = IFNULL( $data['data']['created_at'] , '' );
                $title_en         = IFNULL( $data['data']['title_en'] , '' );
                $special_title_en = IFNULL( $data['data']['special_title_en'] , '' );
                $firstname_th     = IFNULL( $data['data']['firstname_th'] , '' );
                $lastname_th      = IFNULL( $data['data']['lastname_th'] , '' );
                $firstname_en     = IFNULL( $data['data']['firstname_en'] , '' );
                $lastname_en      = IFNULL( $data['data']['lastname_en'] , '' );
                $email            = IFNULL( $data['data']['email'] , '' );
                $date_of_birth    = IFNULL( $data['data']['date_of_birth'] , '' );

                // ดึง organization ตัวแรก (index 0)
                $org = IFNULL( $data['data']['organization'][0], [] );// ?? [];

                $business_id      = IFNULL( $org['business_id'] , '' );
                $position         = IFNULL( $org['position'] , '' );
                $position_id      = IFNULL( $org['position_id'] , '' );
                $affiliation      = IFNULL( $org['affiliation'] , '' );
                $license_id       = IFNULL( $org['license_id'] , '' );
                $hcode            = IFNULL( $org['hcode'] , '' );
                $code9            = IFNULL( $org['code9'] , '' );
                $hcode9           = IFNULL( $org['hcode9'] , '' );
                $level            = IFNULL( $org['level'] , '' );
                $hname_th         = IFNULL( $org['hname_th'] , '' );
                $hname_eng        = IFNULL( $org['hname_eng'] , '' );
                $tax_id           = IFNULL( $org['tax_id'] , '' );
                $license_expired_date = IFNULL( $org['license_expired_date'] , '' );
                $license_id_verify = IFNULL( $org['license_id_verify'] , false ); // ?? false;
                $expertise        = IFNULL( $org['expertise'] , '' );
                $expertise_id     = IFNULL( $org['expertise_id'] , '' );
                $moph_station_ref_code = IFNULL( $org['moph_station_ref_code'] , '' );
                $is_private_provider = IFNULL( $org['is_private_provider'] , false );
                $is_hr_admin      = IFNULL( $org['is_hr_admin'] , false );
                $is_director      = IFNULL( $org['is_director'] , false );
                $moph_access_token_idp = IFNULL( $org['moph_access_token_idp'] , '' );
                $position_type    = IFNULL( $org['position_type'] , '' );

                // ดึง address ใน organization
                $address = IFNULL( $org['address'], [] );
                $address_text     = IFNULL( $address['address'] , '' );
                $moo              = IFNULL( $address['moo'] , '' );
                $building         = IFNULL( $address['building'] , '' );
                $soi              = IFNULL( $address['soi'] , '' );
                $street           = IFNULL( $address['street'] , '' );
                $province         = IFNULL( $address['province'] , '' );
                $district         = IFNULL( $address['district'] , '' );
                $sub_district     = IFNULL( $address['sub_district'] , '' );
                $zip_code         = IFNULL( $address['zip_code'] , '' );

                // แสดงผลจากตัวแปร
                echo "ial_level: $ial_level<br/>";
                echo "account_id: $account_id<br/>";
                echo "hash_cid: $hash_cid<br/>";
                echo "provider_id: $provider_id<br/>";
                echo "title_th: $title_th<br/>";
                echo "special_title_th: $special_title_th<br/>";
                echo "name_th: $name_th<br/>";
                echo "name_eng: $name_eng<br/>";
                echo "created_at: $created_at<br/>";
                echo "title_en: $title_en<br/>";
                echo "special_title_en: $special_title_en<br/>";
                echo "firstname_th: $firstname_th<br/>";
                echo "lastname_th: $lastname_th<br/>";
                echo "firstname_en: $firstname_en<br/>";
                echo "lastname_en: $lastname_en<br/>";
                echo "email: $email<br/>";
                echo "date_of_birth: $date_of_birth<br/>";

                echo "<br/>--- Organization ---<br/>";
                echo "business_id: $business_id<br/>";
                echo "position: $position<br/>";
                echo "position_id: $position_id<br/>";
                echo "affiliation: $affiliation<br/>";
                echo "license_id: $license_id<br/>";
                echo "hcode: $hcode<br/>";
                echo "code9: $code9<br/>";
                echo "hcode9: $hcode9<br/>";
                echo "level: $level<br/>";
                echo "hname_th: $hname_th<br/>";
                echo "hname_eng: $hname_eng<br/>";
                echo "tax_id: $tax_id<br/>";
                echo "license_expired_date: $license_expired_date<br/>";
                echo "license_id_verify: " . ($license_id_verify ? 'true' : 'false') . "<br/>";
                echo "expertise: $expertise<br/>";
                echo "expertise_id: $expertise_id<br/>";
                echo "moph_station_ref_code: $moph_station_ref_code<br/>";
                echo "is_private_provider: " . ($is_private_provider ? 'true' : 'false') . "<br/>";
                echo "is_hr_admin: " . ($is_hr_admin ? 'true' : 'false') . "<br/>";
                echo "is_director: " . ($is_director ? 'true' : 'false') . "<br/>";
                echo "moph_access_token_idp: $moph_access_token_idp<br/>";
                echo "position_type: $position_type<br/>";

                echo "<br/>--- Address ---<br/>";
                echo "address: $address_text<br/>";
                echo "moo: $moo<br/>";
                echo "building: $building<br/>";
                echo "soi: $soi<br/>";
                echo "street: $street<br/>";
                echo "province: $province<br/>";
                echo "district: $district<br/>";
                echo "sub_district: $sub_district<br/>";
                echo "zip_code: $zip_code<br/>";
                

            } else { // ถ้าไม่สามารถดึง access token ของ Provider ID ได้
                echo "Failed to get Provider ID access token.";
            }
        } else { // ถ้าไม่สามารถดึง access token ของ MOPH ID ได้
            echo "Failed to get MOPH ID access token.";
        }

    } else { // ถ้าไม่มี code ใน referer หรือไม่สามารถดึง code ได้
        echo "No code found in referer.";
    }
    //$referer = $_SERVER['HTTP_REFERER'];
    //$code = '';
   // echo $referer;    
  //exit;
  
  //$address = getjsonvalue($address, "formatted"); //[formatted]  

//   $result = $db->getsqldata('SELECT * FROM radcheck WHERE username = "'.$username.'" ');
  
// 		while($row = $result->fetch_assoc()) { // $result->fetch_array
//     		echo "username: " . $row["username"]. " - value: " . $row["value"]; //. " " . $row["lastname"]. "<br>";
//   		}
   $cid = ""; // กำหนดค่าเริ่มต้นเป็นว่าง
   if ( isset($hash_cid) ) { // ถ้ามี hash_cid
      $cid = $db->getsqlstringdata('SELECT cid FROM person_radius WHERE sha2(cid, 256 ) = "'.$cid.'" LIMIT 1;'); // ดึง cid จากฐานข้อมูล person_radius โดยใช้ sha2 ของ hash_cid
      $old_pass = $db->getsqlstringdata('SELECT passwd FROM person_radius WHERE sha2(cid, 256 ) = "'.$cid.'" LIMIT 1;');  // ดึงรหัสผ่านเก่าจากฐานข้อมูล person_radius โดยใช้ sha2 ของ hash_cid
      //echo "Hash CID: $old_pass <br/>"; // แสดงผล hash_cid
   } else {        
   }
   if ( $cid == '' ) {  // ถ้าไม่พบ cid จาก hash_cid
      $cid = $account_id; // ถ้าไม่มี hash_cid ใช้ account_id แทน        
      //exit;
   }
   $username = $cid; // ใช้ account_id เป็น usernames
   exit;
   //$old_pass = $db->getsqlstringdata('SELECT passwd FROM person_radius WHERE cid = "'.$cid.'" LIMIT 1;');
	  
   $passwd_rnd = randomTextSP(7, true, false, false, false);  // สุ่มรหัสผ่านใหม่ 7 ตัวอักษร
   $passwd_rnd = randomTextSP(1, false, false, true, false).$passwd_rnd;   // เพิ่มตัวอักษรพิเศษที่ตำแหน่งแรก

   if ( strlen( $old_pass ) > 0 ) { // ถ้ามีรหัสผ่านเก่า ให้ใช้รหัสผ่านเก่าเป็นรหัสผ่านใหม่
      $passwd_rnd = $old_pass; 
      //$passwd_rnd = $old_pass; 
   }

   $passwd_rnd_base64 = base64_encode( $passwd_rnd ); // เข้ารหัสรหัสผ่านใหม่เป็น base64
   $username_base64 = base64_encode( $username ); // เข้ารหัสชื่อผู้ใช้เป็น base64
   $tmp1 = randomTextSP(225, true, true, true, false); // สุ่มข้อความสำหรับ tmp1
   $tmp2 = randomTextSP(99, true, true, true, false); // สุ่มข้อความสำหรับ tmp2
    
   $attribute = "MD5-Password";
   $op = ":=";
   $value = "md5('".$passwd_rnd."')";
    //$address = $address;
   $active = "Y";
   $date_register = "NOW()";
    //$date_expire = "DATE_ADD(NOW(), INTERVAL 1 DAY)";
   $date_expire = "DATE_FORMAT(NOW(), '%Y-%m-%d 23:59:59')";  // กำหนดวันหมดอายุเป็นวันปัจจุบันเวลา 23:59:59
   $note = "Login by PROVIDER ID";    // หมายเหตุสำหรับการล็อกอินผ่าน PROVIDER ID
    
    // เก็บประวัติการ Login ใน radcheck_mirror
    $asql = "INSERT INTO radcheck_mirror (username, attribute, op, `value`, `tmp_passwd`, `address`, active, date_register, date_expire, note) 
        VALUES ('$username', '$attribute', '$op', $value, '$passwd_rnd', '$address', '$active', $date_register, $date_expire, '$note')";    
        //echo $sql."<br/>";
    $db->execsql( $asql );

    
    //-------------------------------------- add new not exists ---------
    $ccount = $db->getsqlstringdata('SELECT COUNT(*) FROM radcheck WHERE username = "'.$username.'" ');
    if ( $ccount <= 0 ) {  // ยังไม่มี account ใน radius ทำการ Add Account.........            
      $asql = "INSERT INTO radcheck (username, attribute, op, `value`)VALUES ('$username', '$attribute', '$op', $value )";         
      $db->execsql( $asql );
        //$asql = 'SELECT COUNT(*) FROM radcheck WHERE `username` = "$cid" ';
        //echo $sql."<br/>";
        //$ccount = $db->getsqlstringdata( $asql );
        //if ( $ccount <= 0 ) {
        //  $asql = "INSERT INTO radcheck (username, attribute, op, `value`)VALUES ('$username', '$attribute', '$op', $value )";         
        //} else {
        //  $asql = "UPDATE radcheck SET attribute = '$attribute', `value` = $value WHERE `username` = '$cid' ";         
        //}
        //    echo $sql."<br/>";
      //$db->execsql( $asql ); 
    }
    //--------------------------------------
    else { // มีเคยมี account แล้ว update password ใหม่
      $asql = "UPDATE radcheck SET attribute = '$attribute', `value` = $value WHERE `username` = '$cid' ";   
      $db->execsql( $asql ); 
    } 
    //echo $asql;   
    $db->close();
    header("Location: http://192.168.199.1:8000/state=$tmp1&c0=$username_base64&c1=$passwd_rnd_base64&c3=$tmp2");
    //header("Location: http://192.168.199.1:8000/state=$tmp1&c0=$username_base64&c1=$passwd_rnd_base64&c3=$tmp2");
    //header("Location: http://192.168.199.1:8000/c0=$username&c1=$passwd_rnd");
    exit();
    
}elseif($state_thaid == "login1"){
 

}

//$conn->close();
$db->close();

//echo "test".$data;
exit;

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
        <!-- form id="passwordForm" onsubmit="return validatePassword()" -->
        <form id="passwordForm" action="" method="POST" onsubmit="return validatePassword()">                 
        <div class="error" id="error"></div>
        
        <!-- input type="text" id="newPassword" name="newPassword" value="<?=$passwd_rnd?>" -->
        <center>
        <p><strong>AccountName : <?=$cid?></strong></p>
        <p><strong>Password : <?=$passwd_rnd?></strong></p>
        <p><strong>expire : 2024-10-10 23:59</strong></p>
        
        </center>
        <!-- <input type="password" id="confirmPassword" name="confirmPassword" placeholder="ยืนยันรหัสผ่านใหม่" required> -->
        <input type="hidden" id="pid" name="pid" value="<?=$cid?>">
        <input type="submit" value="ตกลง">
        </form>
        
    </div>

    <script>
        function validatePassword() {
            var newPassword = document.getElementById('newPassword').value;
            var confirmPassword = document.getElementById('confirmPassword').value;
            var errorDiv = document.getElementById('error');

            // ตรวจสอบว่ารหัสผ่านใหม่ตรงกับการยืนยันรหัสผ่านใหม่หรือไม่
            if (newPassword !== confirmPassword) {
                errorDiv.textContent = "รหัสผ่านใหม่ไม่ตรงกัน";
                return false;
            }

            // ตรวจสอบว่ารหัสผ่านใหม่ยาวพอหรือไม่ (อย่างน้อย 8 ตัวอักษร)
            if (newPassword.length < 8) {
                errorDiv.textContent = "รหัสผ่านใหม่ต้องมีความยาวอย่างน้อย 8 ตัวอักษร";
                return false;
            }

            // ตรวจสอบว่ารหัสผ่านใหม่มีทั้งตัวอักษรและตัวเลข
            var hasLetter = /[a-zA-Z]/.test(newPassword);
            var hasNumber = /[0-9]/.test(newPassword);
            if (!hasLetter || !hasNumber) {
                errorDiv.textContent = "รหัสผ่านใหม่ต้องมีทั้งตัวอักษรและตัวเลข";
                return false;
            }

            // ถ้าผ่านการตรวจสอบทั้งหมด
            errorDiv.textContent = "";
            return true;
        }
    </script>

</body>
</html>

