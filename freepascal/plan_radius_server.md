# แผนการสร้าง RADIUS Server ด้วย FreePascal (fp-radius)
## รายละเอียดระดับ Implementation

---

## 1. บทนำและภาพรวม

### 1.1 วัตถุประสงค์

สร้าง RADIUS Authentication Server ด้วย FreePascal ที่:
- รับ Authentication Request จาก FortiGate ผ่าน UDP Port 1812
- ตรวจสอบ Username/Password กับฐานข้อมูล MySQL (ตาราง `radcheck` และ `radcheck_mirror`)
- ส่ง Access-Accept หรือ Access-Reject กลับไปยัง FortiGate
- รับ Accounting Request จาก FortiGate ผ่าน UDP Port 1813 (บันทึกเวลาใช้งาน)

### 1.2 ภาพรวมสถาปัตยกรรม

```
                    ┌──────────────────────────────────────────────────┐
  Wi-Fi User        │              เซิร์ฟเวอร์ api1.kpo.go.th          │
  ────────────►     │                                                  │
  (เชื่อม Wi-Fi)    │  ┌────────────────┐   ┌─────────────────────┐   │
                    │  │  Apache HTTPS  │   │  fp-radius (Pascal) │   │
  FortiGate AP      │  │  (Port 443)    │   │  (UDP Port 1812)    │   │
  ────────────►     │  │  fp-sso        │   │                     │   │
  (Captive Portal   │  │  (Port 8080)   │   │  ┌───────────────┐  │   │
   Redirect)        │  └───────┬────────┘   │  │  MySQL        │  │   │
                    │          │            │  │  (radcheck    │  │   │
                    │          ▼            │  │   _mirror)    │  │   │
                    │  ┌───────────────┐    │  └───────────────┘  │   │
                    │  │  SSO Login    │    └─────────────────────┘   │
                    │  │  (ThaID/      │                              │
                    │  │   ProviderID/ │                              │
                    │  │   Google)     │                              │
                    │  └───────┬───────┘                              │
                    │          │ สร้าง tmp_passwd ใน MySQL             │
                    │          ▼                                      │
                    │  [Browser POST ไป FortiGate]                    │
                    │                                                  │
                    └──────────────────────────────────────────────────┘
                                        │
                    FortiGate ส่ง Access-Request → fp-radius:1812
                    fp-radius ตรวจสอบ MySQL → Access-Accept/Reject
```

### 1.3 โฟลว์การทำงานเต็มรูปแบบ

```
ขั้นที่ 1: ผู้ใช้เชื่อมต่อ Wi-Fi
  └── FortiGate ตรวจสอบว่ามี Session หรือไม่
      ├── มี Session ที่ Valid → อนุญาตให้ใช้งานอินเทอร์เน็ตทันที (จบ)
      └── ไม่มี → ไปขั้นที่ 2

ขั้นที่ 2: FortiGate Redirect ไป Captive Portal
  └── Browser ถูกนำไปที่ https://api1.kpo.go.th/?magic=XXXX&redirurl=https://...
      └── ผู้ใช้เห็นหน้า Login SSO (ThaID / Provider ID / Google / Username)

ขั้นที่ 3: ผู้ใช้ล็อกอินผ่าน SSO (ตัวอย่าง ThaID)
  └── SSO Server ยืนยันตัวตนสำเร็จ
      └── เรียก sso_radius_auth() สร้าง/ดึง tmp_passwd จาก radcheck_mirror
      └── บันทึก username + tmp_passwd ลง Session

ขั้นที่ 4: Browser Auto-Submit Form ไปที่ FortiGate
  └── POST: username, password (tmp_passwd), magic, redir → FortiGate URL

ขั้นที่ 5: FortiGate ส่ง Access-Request ไปที่ fp-radius
  └── UDP Packet → 0.0.0.0:1812
      ├── User-Name = username
      ├── User-Password = encrypted(tmp_passwd) ด้วย MD5 XOR + SharedSecret
      └── NAS-IP-Address = IP ของ FortiGate

ขั้นที่ 6: fp-radius ถอดรหัสและตรวจสอบ
  └── ถอดรหัส User-Password ด้วย MD5 XOR + SharedSecret
      ├── Query radcheck_mirror WHERE username = ? → ได้ tmp_passwd
      ├── เปรียบเทียบ password กับ tmp_passwd
      └── ถ้าตรง → ส่ง Access-Accept
      └── ถ้าไม่ตรง → Query radcheck WHERE attribute='MD5-Password'
                     → เปรียบเทียบ MD5(password)
                     → ถ้าตรง → Access-Accept
                     → ถ้าไม่ตรง → Access-Reject

ขั้นที่ 7: FortiGate รับ Access-Accept
  └── เปิด Internet Access ให้ผู้ใช้
      └── Redirect ไปยัง URL เดิม (redirurl)
```

---

## 2. RADIUS Protocol (RFC 2865) — รายละเอียดเต็ม

### 2.1 โครงสร้าง Packet Header (20 bytes)

```
 Octet 0          1          2          3
 +--------+--------+--------+--------+
 |  Code  |  Ident | Length (2 bytes)|
 +--------+--------+--------+--------+
 |                                   |
 |      Authenticator (16 bytes)     |
 |                                   |
 |                                   |
 +-----------------------------------+
 |   Attributes (TLV format)...      |
 +-----------------------------------+
```

| Field | Bytes | คำอธิบาย |
|---|---|---|
| Code | 1 | ประเภท Packet (1=Access-Request, 2=Accept, 3=Reject, 4=Acct-Request, 5=Acct-Response) |
| Identifier | 1 | ID ใช้จับคู่ Request กับ Response (0–255) |
| Length | 2 | ความยาวทั้งหมดของ Packet รวม Header (Big Endian) |
| Authenticator | 16 | Request: Random 16 bytes / Response: MD5(Code+ID+Length+ReqAuth+Attrs+Secret) |

### 2.2 โครงสร้าง Attribute (TLV Format)

```
 +--------+--------+-----------+
 |  Type  | Length |   Value   |
 +--------+--------+-----------+
    1 byte   1 byte  (Length-2) bytes
```

**Length = Type(1) + Length(1) + Value(n) = n + 2**

### 2.3 Attributes หลักที่ต้องรองรับ

| Type | ชื่อ | Data Type | หน้าที่ |
|---|---|---|---|
| 1 | User-Name | String | Username ของผู้ใช้งาน |
| 2 | User-Password | Encrypted Bytes | รหัสผ่าน (เข้ารหัส MD5 XOR) |
| 4 | NAS-IP-Address | 4-byte IP | IP Address ของ FortiGate |
| 5 | NAS-Port | 4-byte Integer | Port ที่ผู้ใช้เชื่อมต่อ |
| 6 | Service-Type | 4-byte Integer | 1=Login, 2=Framed |
| 40 | Acct-Status-Type | 4-byte Integer | 1=Start, 2=Stop (สำหรับ Accounting) |
| 41 | Acct-Delay-Time | 4-byte Integer | วินาทีที่รอก่อนส่ง Accounting |
| 44 | Acct-Session-Id | String | ID ของ Session ใช้เชื่อมระหว่าง Start/Stop |
| 46 | Acct-Session-Time | 4-byte Integer | เวลาที่ใช้งาน (วินาที) |
| 49 | Acct-Terminate-Cause | 4-byte Integer | สาเหตุการตัดการเชื่อมต่อ |

### 2.4 User-Password Encryption/Decryption Algorithm (RFC 2865 §5.2)

```
กำหนดให้:
  S  = Shared Secret (string)
  RA = Request Authenticator (16 bytes)
  P  = Plaintext Password (pad ด้วย 0x00 ให้ยาวเป็นผลคูณ 16)
  C  = Ciphertext (ค่าใน Packet)

การเข้ารหัส (FortiGate → fp-radius):
  b1 = MD5(S + RA)                  // MD5 ของ Secret + Authenticator
  C[0..15] = P[0..15] XOR b1        // XOR กับ 16 bytes แรก

  b2 = MD5(S + C[0..15])            // MD5 ของ Secret + Ciphertext ชุดก่อน
  C[16..31] = P[16..31] XOR b2      // XOR กับ 16 bytes ถัดไป

  ... (ทำซ้ำจนหมด)

การถอดรหัส (fp-radius ← FortiGate):
  b1 = MD5(S + RA)
  P[0..15] = C[0..15] XOR b1

  b2 = MD5(S + C[0..15])
  P[16..31] = C[16..31] XOR b2

  ... (ทำซ้ำจนหมด)
  แล้วตัด 0x00 padding ออกจากท้าย
```

### 2.5 Response Authenticator (สำหรับ Access-Accept/Reject)

```
Response Authenticator = MD5(Code + ID + Length + RequestAuth + Attributes + SharedSecret)

ต้องคำนวณทุกครั้งที่ส่ง Response
FortiGate จะตรวจสอบค่านี้เพื่อยืนยันว่า Response มาจาก RADIUS Server ที่ถูกต้อง
```

---

## 3. โครงสร้างโปรเจกต์

```
/var/www/api/freepascal/fp-radius/
├── .htaccess                    ← บล็อก HTTP Access จากภายนอก
├── fpradius.lpr                 ← Main Program (Entry Point)
├── fpradius.lpi                 ← Lazarus Project Config
├── fpradius                     ← Compiled Binary (หลัง Build)
├── fpradius.service             ← Systemd Service File
└── src/
    ├── RadiusConfig.pas         ← อ่านค่า Config จาก .env
    ├── RadiusPacket.pas         ← Parse + Build RADIUS Packet
    ├── RadiusAuth.pas           ← Password Decrypt + ตรวจสอบสิทธิ์
    ├── RadiusDB.pas             ← MySQL Database Operations
    ├── RadiusAccounting.pas     ← Accounting Handler (Port 1813)
    └── RadiusServer.pas         ← UDP Server Main Loop
```

---

## 4. Source Code — รายละเอียดแต่ละไฟล์

### 4.1 `RadiusConfig.pas` — Config Reader

```pascal
unit RadiusConfig;

{$mode objfpc}{$H+}

interface

type
  TRadiusConfig = record
    // การเชื่อมต่อฐานข้อมูล Radius MySQL
    DBHost     : string;
    DBPort     : Word;
    DBUser     : string;
    DBPass     : string;
    DBName     : string;

    // การตั้งค่า RADIUS Server
    RadiusPort     : Word;    // default 1812
    AcctPort       : Word;    // default 1813
    SharedSecret   : string;  // ต้องตรงกับที่ตั้งบน FortiGate

    // Logging
    LogFile    : string;
    LogLevel   : Integer;     // 0=Error, 1=Info, 2=Debug
  end;

// โหลดค่าจากไฟล์ .env
function LoadConfig(const EnvPath: string): TRadiusConfig;
procedure LogMsg(const Level: Integer; const Msg: string);
```

**Logic การโหลด .env:**
- อ่านไฟล์ทีละบรรทัด
- ข้ามบรรทัดที่ขึ้นต้นด้วย `#`
- แยก `KEY=VALUE` ด้วย `=` ตัวแรก
- Trim ช่องว่างทั้งสองด้าน

---

### 4.2 `RadiusPacket.pas` — Packet Parser + Builder

```pascal
unit RadiusPacket;

{$mode objfpc}{$H+}

interface

uses SysUtils, MD5;

const
  // RADIUS Packet Codes
  RADIUS_ACCESS_REQUEST    = 1;
  RADIUS_ACCESS_ACCEPT     = 2;
  RADIUS_ACCESS_REJECT     = 3;
  RADIUS_ACCT_REQUEST      = 4;
  RADIUS_ACCT_RESPONSE     = 5;

  // RADIUS Attribute Types
  ATTR_USER_NAME           = 1;
  ATTR_USER_PASSWORD       = 2;
  ATTR_NAS_IP_ADDRESS      = 4;
  ATTR_NAS_PORT            = 5;
  ATTR_SERVICE_TYPE        = 6;
  ATTR_REPLY_MESSAGE       = 18;
  ATTR_ACCT_STATUS_TYPE    = 40;
  ATTR_ACCT_SESSION_ID     = 44;
  ATTR_ACCT_SESSION_TIME   = 46;

type
  // Attribute เดี่ยว
  TRadiusAttr = record
    AttrType : Byte;
    Value    : TBytes;         // Raw bytes ของ Value (ไม่รวม Type และ Length)
  end;

  // Packet ทั้งหมด
  TRadiusPacket = record
    Code          : Byte;
    Identifier    : Byte;
    Length        : Word;
    Authenticator : array[0..15] of Byte;  // 16 bytes
    Attrs         : array of TRadiusAttr;
    AttrCount     : Integer;
  end;

  TByteArray = array of Byte;

// ฟังก์ชัน Parse Raw UDP Buffer → TRadiusPacket
function ParsePacket(const Buf: TByteArray): TRadiusPacket;

// ดึงค่า Attribute เป็น String
function GetAttrString(const Pkt: TRadiusPacket; AttrType: Byte): string;

// ดึงค่า Attribute เป็น Integer (Big Endian 4 bytes)
function GetAttrInt(const Pkt: TRadiusPacket; AttrType: Byte): LongWord;

// ถอดรหัส User-Password (RFC 2865 §5.2)
function DecryptPassword(const Pkt: TRadiusPacket; const Secret: string): string;

// สร้าง Access-Accept Response (คำนวณ Response Authenticator)
function BuildAccept(const Req: TRadiusPacket; const Secret: string): TByteArray;

// สร้าง Access-Reject Response
function BuildReject(const Req: TRadiusPacket; const Secret: string): TByteArray;

// สร้าง Accounting-Response
function BuildAcctResponse(const Req: TRadiusPacket; const Secret: string): TByteArray;
```

**รายละเอียด DecryptPassword:**
```pascal
function DecryptPassword(const Pkt: TRadiusPacket; const Secret: string): string;
var
  EncBuf : TBytes;      // Encrypted bytes จาก Attribute Type=2
  i, j   : Integer;
  b      : TMD5Digest;
  ctx    : TMD5Context;
  Result : TBytes;
begin
  EncBuf := GetAttrBytes(Pkt, ATTR_USER_PASSWORD);
  SetLength(Result, Length(EncBuf));

  // รอบแรก: MD5(Secret + Authenticator)
  MD5Init(ctx);
  MD5Update(ctx, Secret[1], Length(Secret));
  MD5Update(ctx, Pkt.Authenticator[0], 16);
  MD5Final(ctx, b);

  // XOR 16 bytes แรก
  for i := 0 to 15 do
    Result[i] := EncBuf[i] XOR b[i];

  // รอบถัดไป: MD5(Secret + Ciphertext[prev 16 bytes])
  j := 16;
  while j < Length(EncBuf) do begin
    MD5Init(ctx);
    MD5Update(ctx, Secret[1], Length(Secret));
    MD5Update(ctx, EncBuf[j-16], 16);
    MD5Final(ctx, b);

    for i := 0 to 15 do
      if (j + i) < Length(EncBuf) then
        Result[j+i] := EncBuf[j+i] XOR b[i];

    Inc(j, 16);
  end;

  // ตัด null padding ออกจากท้าย
  i := Length(Result);
  while (i > 0) and (Result[i-1] = 0) do Dec(i);
  SetLength(Result, i);

  DecryptPassword := string(Result);
end;
```

**รายละเอียด BuildAccept:**
```pascal
function BuildAccept(const Req: TRadiusPacket; const Secret: string): TByteArray;
var
  Buf       : TByteArray;
  TotalLen  : Word;
  ctx       : TMD5Context;
  RespAuth  : TMD5Digest;
begin
  // Header 20 bytes + optional reply-message attribute
  TotalLen := 20;  // เพิ่ม Attributes ถ้าต้องการ

  SetLength(Buf, TotalLen);
  Buf[0] := RADIUS_ACCESS_ACCEPT;           // Code = 2
  Buf[1] := Req.Identifier;                  // ใช้ ID เดิมจาก Request
  Buf[2] := Hi(TotalLen);                    // Length High byte
  Buf[3] := Lo(TotalLen);                    // Length Low byte

  // ใส่ Request Authenticator ชั่วคราวก่อน (ใช้คำนวณ Response Auth)
  Move(Req.Authenticator[0], Buf[4], 16);

  // คำนวณ Response Authenticator:
  // MD5(Code + ID + Length + RequestAuthenticator + Attributes + SharedSecret)
  MD5Init(ctx);
  MD5Update(ctx, Buf[0], TotalLen);          // ทั้ง Packet รวม ReqAuth
  MD5Update(ctx, Secret[1], Length(Secret)); // ต่อด้วย SharedSecret
  MD5Final(ctx, RespAuth);

  // แทนที่ Authenticator ด้วย Response Authenticator
  Move(RespAuth[0], Buf[4], 16);

  Result := Buf;
end;
```

---

### 4.3 `RadiusDB.pas` — MySQL Database Operations

```pascal
unit RadiusDB;

{$mode objfpc}{$H+}

interface

uses SysUtils, MD5, RadiusConfig;

// เชื่อมต่อ MySQL
function DBConnect(const Cfg: TRadiusConfig): Boolean;
procedure DBDisconnect;

// ตรวจสอบ Username + Password
// Returns: True = ยืนยันตัวตนสำเร็จ, False = ล้มเหลว
function CheckUserPassword(const Username, Password: string): Boolean;

// บันทึก Log การเข้าใช้งาน
procedure LogAccessAttempt(const Username, NasIP: string;
                            Accepted: Boolean; const Timestamp: TDateTime);

// บันทึก Accounting Start/Stop
procedure LogAccounting(const SessionID, Username, NasIP: string;
                         StatusType: Integer; SessionTime: LongWord);
```

**Logic CheckUserPassword (สอดคล้องกับ radius_auth.php):**
```
ขั้นที่ 1: ตรวจสอบจาก radcheck_mirror (tmp_passwd = Plaintext)
  SQL: SELECT tmp_passwd FROM radcheck_mirror
       WHERE username = ? AND active != 'N' LIMIT 1

  ถ้าพบและ tmp_passwd ตรงกับ password → Return True
  ถ้าพบแต่ tmp_passwd ไม่ตรง → Return False (ไม่ต้องลองตาราง radcheck)

ขั้นที่ 2: ถ้าไม่พบใน radcheck_mirror → ตรวจสอบจาก radcheck (MD5)
  SQL: SELECT value FROM radcheck
       WHERE username = ? AND attribute = 'MD5-Password' LIMIT 1

  ถ้าพบ: เปรียบเทียบ MD5(password) กับ value
  ถ้าตรง → Return True
  ถ้าไม่ตรง → Return False

ขั้นที่ 3: ไม่พบเลย → Return False
```

**ตารางเพิ่มเติมสำหรับ Accounting Log:**
```sql
CREATE TABLE IF NOT EXISTS radius_access_log (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  username    VARCHAR(64) NOT NULL,
  nas_ip      VARCHAR(45) DEFAULT NULL,
  accepted    TINYINT(1) DEFAULT 0,
  login_time  DATETIME NOT NULL,
  INDEX (username),
  INDEX (login_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS radius_acct_log (
  id              INT AUTO_INCREMENT PRIMARY KEY,
  session_id      VARCHAR(64) NOT NULL,
  username        VARCHAR(64) NOT NULL,
  nas_ip          VARCHAR(45) DEFAULT NULL,
  status_type     TINYINT,     -- 1=Start, 2=Stop
  session_time    INT DEFAULT 0,
  log_time        DATETIME NOT NULL,
  INDEX (session_id),
  INDEX (username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

---

### 4.4 `RadiusAccounting.pas` — Accounting Handler

```pascal
unit RadiusAccounting;

{$mode objfpc}{$H+}

interface

uses RadiusPacket, RadiusDB, RadiusConfig;

// จัดการ Accounting-Request (Code=4)
// Returns: Accounting-Response (Code=5) ในรูป TByteArray
function HandleAccounting(const Req: TRadiusPacket;
                           const Cfg: TRadiusConfig): TByteArray;
```

**Logic:**
- ดึง Acct-Status-Type (Type=40): 1=Start, 2=Stop
- ดึง Acct-Session-Id (Type=44), Username (Type=1), NAS-IP (Type=4)
- ถ้า Stop: ดึง Acct-Session-Time (Type=46) สำหรับเวลาที่ใช้งาน
- บันทึกลงตาราง `radius_acct_log`
- ส่ง Accounting-Response (Code=5) กลับ

---

### 4.5 `RadiusServer.pas` — UDP Server Main Loop

```pascal
unit RadiusServer;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Sockets, RadiusConfig, RadiusPacket,
  RadiusAuth, RadiusAccounting, RadiusDB;

type
  TRadiusServer = class
  private
    FAuthSocket : LongInt;   // UDP Socket สำหรับ Port 1812
    FAcctSocket : LongInt;   // UDP Socket สำหรับ Port 1813
    FCfg        : TRadiusConfig;
    FRunning    : Boolean;

    procedure HandleAuthPacket(const Buf: TByteArray; const ClientAddr: TSockAddr);
    procedure HandleAcctPacket(const Buf: TByteArray; const ClientAddr: TSockAddr);

  public
    constructor Create(const Cfg: TRadiusConfig);
    destructor Destroy; override;
    procedure Start;     // เริ่ม Server Loop (Blocking)
    procedure Stop;      // หยุด Server
  end;
```

**Logic HandleAuthPacket:**
```
1. ParsePacket(Buf) → TRadiusPacket
2. ตรวจสอบ Code = RADIUS_ACCESS_REQUEST (1)
3. ดึง Username = GetAttrString(Pkt, 1)
4. ถอดรหัส Password = DecryptPassword(Pkt, SharedSecret)
5. LogMsg('Auth Request from ' + NasIP + ' for user: ' + Username)
6. if CheckUserPassword(Username, Password) then
     Response := BuildAccept(Pkt, SharedSecret)
     LogMsg('Access-Accept for ' + Username)
   else
     Response := BuildReject(Pkt, SharedSecret)
     LogMsg('Access-Reject for ' + Username)
7. SendTo(AuthSocket, Response, ClientAddr)
8. LogAccessAttempt(Username, NasIP, Accepted, Now)
```

**UDP Socket Setup:**
```pascal
procedure TRadiusServer.Start;
var
  AuthAddr, AcctAddr : TSockAddr;
  Buf                : array[0..4095] of Byte;
  BufLen, RecvLen    : Integer;
  ClientAddr         : TSockAddr;
  ClientAddrLen      : Integer;
begin
  // สร้าง Socket สำหรับ Authentication (Port 1812)
  FAuthSocket := fpSocket(AF_INET, SOCK_DGRAM, 0);

  // Bind Port 1812
  FillChar(AuthAddr, SizeOf(AuthAddr), 0);
  AuthAddr.sin_family := AF_INET;
  AuthAddr.sin_port   := htons(FCfg.RadiusPort);
  AuthAddr.sin_addr.s_addr := INADDR_ANY;
  fpBind(FAuthSocket, @AuthAddr, SizeOf(AuthAddr));

  // สร้างและ Bind Port 1813 สำหรับ Accounting
  FAcctSocket := fpSocket(AF_INET, SOCK_DGRAM, 0);
  // ... (เหมือนกัน แต่ใช้ FCfg.AcctPort)

  LogMsg(1, 'fp-radius started on UDP :'
            + IntToStr(FCfg.RadiusPort)
            + ' (Auth) and :'
            + IntToStr(FCfg.AcctPort)
            + ' (Acct)');

  FRunning := True;
  ClientAddrLen := SizeOf(ClientAddr);

  // Main Loop — รับ Datagram และตอบกลับ
  while FRunning do begin
    RecvLen := fpRecvFrom(FAuthSocket, @Buf, SizeOf(Buf), 0,
                          @ClientAddr, @ClientAddrLen);
    if RecvLen > 0 then begin
      // Convert Buf → TByteArray แล้วส่งให้ Handler
      HandleAuthPacket(BufToBytes(Buf, RecvLen), ClientAddr);
    end;
    // TODO: ใช้ select() หรือ Thread เพื่อรับทั้ง Auth และ Acct พร้อมกัน
  end;
end;
```

---

### 4.6 `fpradius.lpr` — Main Program Entry Point

```pascal
program fpradius;

{$mode objfpc}{$H+}

uses
  SysUtils, RadiusConfig, RadiusDB, RadiusServer;

var
  Cfg    : TRadiusConfig;
  Server : TRadiusServer;
  EnvPath: string;

begin
  // รับ Path ของ .env จาก Command Line หรือใช้ค่า Default
  if ParamCount > 0 then
    EnvPath := ParamStr(1)
  else
    EnvPath := '/var/www/api/.env';

  WriteLn('fp-radius: Loading config from ', EnvPath);

  // โหลด Config
  Cfg := LoadConfig(EnvPath);

  // เชื่อมต่อฐานข้อมูล
  if not DBConnect(Cfg) then begin
    WriteLn('fp-radius: ERROR - Cannot connect to MySQL. Exiting.');
    Halt(1);
  end;

  // สร้างและเริ่ม RADIUS Server
  Server := TRadiusServer.Create(Cfg);
  try
    Server.Start;   // Blocking Loop
  finally
    Server.Free;
    DBDisconnect;
  end;
end.
```

---

## 5. Build และ Compile

### 5.1 Prerequisites

```bash
# ตรวจสอบว่ามี fpc ติดตั้งแล้ว
fpc --version

# ติดตั้ง MySQL Development Libraries
sudo apt-get install libmysqlclient-dev
```

### 5.2 คำสั่ง Compile

```bash
cd /var/www/api/freepascal/fp-radius/

# Compile ด้วย fpc โดยตรง
fpc -O3 -Xs -XX -CX \
    -Fu./src \
    -Fi./src \
    fpradius.lpr \
    -o fpradius

# ตรวจสอบ Binary
./fpradius --version
```

**Options ที่ใช้:**
| Option | ความหมาย |
|---|---|
| `-O3` | Optimization Level 3 (เร็วที่สุด) |
| `-Xs` | Strip Debug Symbols (ไฟล์เล็กลง) |
| `-XX` | ใช้ Smart Linking |
| `-CX` | External Linker |
| `-Fu./src` | เพิ่ม Source Path |

### 5.3 ทดสอบก่อน Deploy

```bash
# รันแบบ Foreground เพื่อดู Log
sudo ./fpradius /var/www/api/.env

# ทดสอบด้วย radtest tool (ต้องติดตั้ง freeradius-utils)
sudo apt-get install freeradius-utils

radtest testuser testpass 127.0.0.1 0 your_shared_secret
# คาดหวัง: Received Access-Accept หรือ Access-Reject
```

---

## 6. Systemd Service

### 6.1 ไฟล์ `fpradius.service`

```ini
[Unit]
Description=FreePascal RADIUS Authentication Server (fp-radius)
Documentation=https://tools.ietf.org/html/rfc2865
After=network.target mysql.service mariadb.service
Wants=mysql.service

[Service]
Type=simple
User=www-data
Group=www-data

# ชี้ไปที่ Binary และ Config
ExecStart=/var/www/api/freepascal/fp-radius/fpradius /var/www/api/.env

# Restart อัตโนมัติเมื่อ Process ล้มเหลว
Restart=always
RestartSec=5

# Security Hardening
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/var/log/fp-radius

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=fp-radius

[Install]
WantedBy=multi-user.target
```

### 6.2 ติดตั้ง Service

```bash
# คัดลอกไฟล์ Service
sudo cp fpradius.service /etc/systemd/system/

# เปิดใช้งานและเริ่ม Service
sudo systemctl daemon-reload
sudo systemctl enable fpradius
sudo systemctl start fpradius

# ตรวจสอบสถานะ
sudo systemctl status fpradius

# ดู Log แบบ Real-time
sudo journalctl -u fpradius -f
```

---

## 7. การตั้งค่า Firewall

```bash
# เปิด Port สำหรับ RADIUS (UDP)
sudo ufw allow 1812/udp   # Authentication
sudo ufw allow 1813/udp   # Accounting

# หรือเปิดเฉพาะจาก IP ของ FortiGate (แนะนำ)
sudo ufw allow from [FortiGate-IP] to any port 1812 proto udp
sudo ufw allow from [FortiGate-IP] to any port 1813 proto udp

# ตรวจสอบ
sudo ufw status verbose
```

---

## 8. การตั้งค่าบน FortiGate

### 8.1 เพิ่ม RADIUS Server

```
FortiGate GUI → User & Authentication → RADIUS Servers → Create New

Field                    Value
─────────────────────────────────────────────────
Name:                    fp-radius-server
Primary Server Name/IP:  [IP เซิร์ฟเวอร์ api1.kpo.go.th]
Primary Server Port:     1812
Secondary Server:        (ไม่จำเป็น)
Secret:                  [ค่า RADIUS_SECRET ใน .env — ต้องตรงกัน]
Authentication Method:   PAP (ใช้ User-Password แบบ MD5 XOR)
NAS IP:                  [IP FortiGate Interface ที่เชื่อมต่อ]
```

### 8.2 ทดสอบการเชื่อมต่อจาก FortiGate

```
FortiGate GUI → RADIUS Servers → [เลือก fp-radius-server] → Test Connectivity
หรือผ่าน CLI:
  diagnose test authserver radius fp-radius-server pap testuser testpass
```

### 8.3 ผูก RADIUS Server กับ Captive Portal

```
FortiGate GUI → Policy & Objects → Firewall Policy
  → เลือก Policy ของ Wi-Fi Interface
  → Authentication → Captive Portal
  → User Group → [เลือก Group ที่ใช้ RADIUS]

User & Authentication → User Groups → Create/Edit
  → Remote Groups → Add
  → Remote Server: fp-radius-server
```

---

## 9. ค่าที่ต้องเพิ่มใน `.env`

```ini
# ── RADIUS Server Settings ──────────────────────────────────────
RADIUS_PORT=1812
RADIUS_ACCT_PORT=1813

# Shared Secret ต้องตั้งให้ตรงกับที่กำหนดบน FortiGate
# ใช้ตัวอักษร + ตัวเลข + สัญลักษณ์ ยาวอย่างน้อย 16 ตัว
RADIUS_SECRET=change_this_to_a_strong_secret_key_here

# Log Level: 0=Error, 1=Info, 2=Debug
RADIUS_LOG_LEVEL=1
RADIUS_LOG_FILE=/var/log/fp-radius/access.log
```

---

## 10. แผนการทดสอบ (Testing Plan)

### 10.1 Unit Test — ทดสอบ Packet Parser

```bash
# สร้าง Test Program แยก
# ส่ง Raw bytes ของ Access-Request จริงๆ (จาก Wireshark) เข้าไป
# ตรวจสอบว่า ParsePacket() อ่านค่าได้ถูกต้อง
# ตรวจสอบว่า DecryptPassword() ถอดรหัสได้ถูกต้อง
```

### 10.2 Integration Test — ทดสอบกับ radtest

```bash
# ทดสอบ Accept (ต้องมี user นี้ใน radcheck_mirror ด้วย tmp_passwd = "testpass")
radtest testuser testpass 127.0.0.1 1812 your_shared_secret

# คาดหวัง Output:
# Received Access-Accept Id 1 from 127.0.0.1:1812 to ...

# ทดสอบ Reject (รหัสผ่านผิด)
radtest testuser wrongpass 127.0.0.1 1812 your_shared_secret

# คาดหวัง Output:
# Received Access-Reject Id 2 from 127.0.0.1:1812 to ...
```

### 10.3 Load Test — ทดสอบ Concurrent Requests

```bash
# ใช้ radclient ส่ง Request พร้อมกันหลายอัน
for i in $(seq 1 100); do
  radtest testuser testpass 127.0.0.1 1812 secret &
done
wait
```

---

## 11. ลำดับการพัฒนาที่แนะนำ

```
Week 1:  RadiusConfig.pas + RadiusPacket.pas
         └── Focus: อ่าน .env + Parse/Build Packet + ถอดรหัส Password
         └── ทดสอบ: Unit Test กับ Raw Bytes จาก Wireshark

Week 2:  RadiusDB.pas
         └── Focus: MySQL Connect + CheckUserPassword()
         └── ทดสอบ: ทดสอบกับ radcheck_mirror จริง

Week 3:  RadiusServer.pas + รวม Modules
         └── Focus: UDP Server + Integration Test
         └── ทดสอบ: radtest tool

Week 4:  RadiusAccounting.pas + Systemd + Firewall + FortiGate Config
         └── Focus: Production Deploy + End-to-End Test
         └── ทดสอบ: ทดสอบกับ FortiGate จริง
```
