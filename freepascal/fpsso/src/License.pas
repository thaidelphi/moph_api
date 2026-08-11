unit License;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, HMAC, SHA1, BaseUnix;

type
  { สถานะผลลัพธ์จากการตรวจสอบ License }
  TLicenseStatus = (
    lsValid,              // License ถูกต้อง พร้อมใช้งาน
    lsExpired,            // License หมดอายุแล้ว
    lsInvalidMachine,     // Machine ID ไม่ตรงกับเครื่องนี้
    lsInvalidSignature,   // ลายเซ็นไม่ถูกต้อง (ถูกแก้ไข/ปลอมแปลง)
    lsNotFound,           // ไม่พบไฟล์ License
    lsInvalidFormat,      // รูปแบบไฟล์ License ผิดพลาด
    lsTampered            // ตรวจพบการดัดแปลง Binary หรือ Debugger
  );

  { ข้อมูล License ที่อ่านได้จากไฟล์ }
  TLicenseInfo = record
    Status: TLicenseStatus;   // ผลการตรวจสอบ
    Serial: string;           // รหัส Serial (เช่น FPSSO-2026-XXXX)
    Licensee: string;         // ชื่อหน่วยงาน/ลูกค้า
    MachineID: string;        // Machine ID ที่ผูกไว้กับ License
    IssuedDate: string;       // วันที่ออก License (YYYY-MM-DD)
    ExpiryDate: string;       // วันหมดอายุ (YYYY-MM-DD หรือว่าง = ไม่หมดอายุ)
    MaxUsers: Integer;        // จำนวนผู้ใช้สูงสุด (0 = ไม่จำกัด)
    Features: string;         // ฟีเจอร์ที่เปิดใช้งาน (all, basic, thaid, providerid)
  end;

  { Thread สำหรับตรวจสอบ License ซ้ำเป็นระยะ (ป้องกัน runtime patching) }
  TLicenseWatchdogThread = class(TThread)
  private
    FLicensePath: string;  // path ไปยังไฟล์ license.key ที่ต้องตรวจซ้ำ
  protected
    procedure Execute; override;
  public
    constructor Create(const ALicPath: string);
  end;

{ อ่าน Machine ID ของเครื่องปัจจุบัน จาก /etc/machine-id }
function GetMachineID: string;

{ ตรวจสอบไฟล์ License ว่าถูกต้องหรือไม่ }
function ValidateLicense(const LicPath: string): TLicenseInfo;

{ สร้างไฟล์ License Key ใหม่ (เฉพาะผู้พัฒนาใช้) }
function GenerateLicenseFile(const ASerial, ALicensee, AMachineID,
  AIssuedDate, AExpiryDate, AFeatures: string;
  AMaxUsers: Integer; const AOutputPath: string): Boolean;

{ สร้าง Serial Number แบบสุ่ม }
function GenerateSerialNumber: string;

{ แปลง License Status เป็นข้อความภาษาไทย }
function LicenseStatusText(Status: TLicenseStatus): string;

{ ตรวจสอบว่ามี Debugger กำลัง Attach อยู่หรือไม่ }
function IsDebuggerPresent: Boolean;

{ ตรวจสอบ License แบบกระจาย (เรียกจากหลายจุดในโปรแกรม) }
procedure QuickLicenseCheck;

var
  { ค่า License Path สำหรับใช้ในการตรวจสอบซ้ำจากจุดต่างๆ }
  GlobalLicensePath: string;
  { Flag ระบุว่า License ผ่านการตรวจสอบแล้ว }
  LicenseVerified: Boolean;
  { Flag ระบุว่าทำงานใน Demo Mode (ไม่มี License, จำกัด 10 user/day) }
  DemoModeActive: Boolean;

implementation

{ ===================================================================== }
{   ชั้นที่ 1: XOR Obfuscation ของ Secret Key                          }
{   Secret Key จะไม่ถูกเก็บเป็น plaintext ใน binary                     }
{   ป้องกันการใช้คำสั่ง `strings` เพื่อหาค่า Secret                      }
{ ===================================================================== }

const
  { XOR Key สำหรับถอดรหัส Secret (สุ่มค่ามาเอง) }
  XOR_KEY: array[0..7] of Byte = ($A7, $3B, $5E, $C2, $91, $F4, $68, $0D);

  { Secret Key ที่เข้ารหัส XOR แล้ว (จะถูกถอดรหัสตอน runtime เท่านั้น) }
  { ค่าจริง = 'fpsso-v1-thaidelphi-moph-2026-secret-key-do-not-share' }
  { เข้ารหัสด้วย XOR_KEY เพื่อไม่ให้เห็นเป็น plaintext ใน binary }
  ENC_SECRET: array[0..52] of Byte = (
    $C1, $4B, $2D, $B1, $FE, $D9, $1E, $3C,  // fpsso-v1
    $8A, $4F, $36, $A3, $F8, $90, $0D, $61,  // -thaidel
    $D7, $53, $37, $EF, $FC, $9B, $18, $65,  // phi-moph
    $8A, $09, $6E, $F0, $A7, $D9, $1B, $68,  // -2026-se
    $C4, $49, $3B, $B6, $BC, $9F, $0D, $74,  // cret-key
    $8A, $5F, $31, $EF, $FF, $9B, $1C, $20,  // -do-not-
    $D4, $53, $3F, $B0, $F4                   // share
  );

  { ตัวคั่นระหว่าง field ใน License data ก่อนทำ HMAC }
  FIELD_SEP = '|';

{ ถอดรหัส Secret Key จาก XOR (เรียกตอน Runtime เท่านั้น) }
function DecryptSecret: string;
var
  I: Integer;
begin
  SetLength(Result, Length(ENC_SECRET));
  for I := 0 to High(ENC_SECRET) do
    Result[I + 1] := Chr(ENC_SECRET[I] xor XOR_KEY[I mod Length(XOR_KEY)]);
end;

{ ===================================================================== }
{   ชั้นที่ 2: Anti-Debugging (ตรวจจับ Debugger/Tracer)                 }
{   ป้องกันการใช้ gdb, strace, ltrace เพื่อ reverse engineer            }
{ ===================================================================== }

{ ตรวจสอบ /proc/self/status ว่ามี process อื่น trace อยู่หรือไม่ }
function IsDebuggerPresent: Boolean;
var
  SL: TStringList;
  I: Integer;
  Line: string;
  TracerPID: Integer;
begin
  Result := False;

  // วิธีที่ 1: ตรวจสอบ TracerPid ใน /proc/self/status
  // ค่า TracerPid จะเป็น 0 ถ้าไม่มี debugger, เป็น PID ของ debugger ถ้ามี
  if FileExists('/proc/self/status') then
  begin
    SL := TStringList.Create;
    try
      SL.LoadFromFile('/proc/self/status');
      for I := 0 to SL.Count - 1 do
      begin
        Line := SL[I];
        if Pos('TracerPid:', Line) = 1 then
        begin
          TracerPID := StrToIntDef(Trim(Copy(Line, 11, Length(Line))), 0);
          if TracerPID <> 0 then
          begin
            Result := True;
            Exit;
          end;
        end;
      end;
    finally
      SL.Free;
    end;
  end;

  // วิธีที่ 2: ตรวจสอบ Environment Variables ที่ debugger มักตั้งไว้
  if (GetEnvironmentVariable('LD_PRELOAD') <> '') then
    Result := True;
end;

{ ===================================================================== }
{   ชั้นที่ 3: Binary Integrity Check (Self-checksum)                   }
{   ตรวจสอบว่าไฟล์ binary ไม่ได้ถูก patch/แก้ไข                         }
{ ===================================================================== }

var
  { เก็บ checksum ของ binary ตอนเริ่มต้นโปรแกรม }
  OriginalBinaryHash: string;

{ คำนวณ SHA1 hash ของไฟล์ binary ตัวเอง }
function ComputeBinaryHash: string;
var
  FS: TFileStream;
  Context: TSHA1Context;
  Digest: TSHA1Digest;
  Buffer: array[0..8191] of Byte;
  BytesRead: Integer;
  ExePath: string;
begin
  Result := '';
  ExePath := ParamStr(0);

  if not FileExists(ExePath) then Exit;

  try
    FS := TFileStream.Create(ExePath, fmOpenRead or fmShareDenyNone);
    try
      SHA1Init(Context);
      repeat
        BytesRead := FS.Read(Buffer, SizeOf(Buffer));
        if BytesRead > 0 then
          SHA1Update(Context, Buffer, BytesRead);
      until BytesRead = 0;
      SHA1Final(Context, Digest);
      Result := SHA1Print(Digest);
    finally
      FS.Free;
    end;
  except
    // ถ้าอ่านไฟล์ไม่ได้ ให้คืนค่าว่าง
    Result := '';
  end;
end;

{ ตรวจสอบว่า binary ยังคงเหมือนเดิมตอนเริ่มต้น (ไม่ถูก patch ระหว่างรัน) }
function IsBinaryIntact: Boolean;
var
  CurrentHash: string;
begin
  // ถ้ายังไม่ได้เก็บ hash ไว้ (เช่น เพิ่ง initialize) ให้ข้ามการตรวจ
  if OriginalBinaryHash = '' then
  begin
    Result := True;
    Exit;
  end;

  CurrentHash := ComputeBinaryHash;
  Result := (CurrentHash <> '') and (CurrentHash = OriginalBinaryHash);
end;

{ ===================================================================== }
{   License Core Functions                                              }
{ ===================================================================== }

{ อ่าน Machine ID จาก /etc/machine-id (Linux systemd) }
function GetMachineID: string;
var
  SL: TStringList;
begin
  Result := '';
  if FileExists('/etc/machine-id') then
  begin
    SL := TStringList.Create;
    try
      SL.LoadFromFile('/etc/machine-id');
      if SL.Count > 0 then
        Result := Trim(SL[0]);
    finally
      SL.Free;
    end;
  end;
end;

{ สร้าง HMAC-SHA1 ลายเซ็นจากข้อมูล License }
function SignLicenseData(const AData: string): string;
var
  Secret: string;
begin
  // ถอดรหัส Secret Key ตอน Runtime (ไม่เก็บเป็น plaintext)
  Secret := DecryptSecret;
  try
    Result := HMACSHA1(Secret, AData);
  finally
    // ล้าง Secret ออกจาก Memory ทันทีหลังใช้งาน
    FillChar(Pointer(Secret)^, Length(Secret), 0);
    Secret := '';
  end;
end;

{ รวม field ต่างๆ ของ License เป็น string เดียวสำหรับทำ HMAC }
function BuildSignableData(const ASerial, ALicensee, AMachineID,
  AIssuedDate, AExpiryDate, AFeatures: string;
  AMaxUsers: Integer): string;
begin
  Result := ASerial + FIELD_SEP +
            ALicensee + FIELD_SEP +
            AMachineID + FIELD_SEP +
            AIssuedDate + FIELD_SEP +
            AExpiryDate + FIELD_SEP +
            IntToStr(AMaxUsers) + FIELD_SEP +
            AFeatures;
end;

{ แยกค่า value จากบรรทัด key=value }
function ExtractValue(const Line: string): string;
var
  P: Integer;
begin
  Result := '';
  P := Pos('=', Line);
  if P > 0 then
    Result := Trim(Copy(Line, P + 1, Length(Line)));
end;

{ ===================================================================== }
{   ชั้นที่ 4: License Validation หลัก (รวมการตรวจสอบทุกชั้น)            }
{ ===================================================================== }

function ValidateLicense(const LicPath: string): TLicenseInfo;
var
  SL: TStringList;
  I: Integer;
  Line, Key, Signature, ExpectedSig, SignableData: string;
  ExpiryDT: TDateTime;
begin
  // กำหนดค่าเริ่มต้น
  Result.Status := lsNotFound;
  Result.Serial := '';
  Result.Licensee := '';
  Result.MachineID := '';
  Result.IssuedDate := '';
  Result.ExpiryDate := '';
  Result.MaxUsers := 0;
  Result.Features := '';

  // ชั้นที่ 2: ตรวจสอบ Debugger ก่อนตรวจ License
  if IsDebuggerPresent then
  begin
    Result.Status := lsTampered;
    Exit;
  end;

  // ชั้นที่ 3: ตรวจสอบ Binary Integrity (ถ้ามี hash ที่เก็บไว้)
  if not IsBinaryIntact then
  begin
    Result.Status := lsTampered;
    Exit;
  end;

  // ตรวจสอบว่าไฟล์ License มีอยู่หรือไม่
  if not FileExists(LicPath) then
    Exit;

  SL := TStringList.Create;
  try
    SL.LoadFromFile(LicPath);

    Signature := '';

    // อ่านข้อมูลทีละบรรทัดจากไฟล์ license.key
    for I := 0 to SL.Count - 1 do
    begin
      Line := Trim(SL[I]);
      if (Line = '') or (Line[1] = '#') then Continue;

      if Pos('=', Line) > 0 then
        Key := Trim(Copy(Line, 1, Pos('=', Line) - 1))
      else
        Continue;

      if Key = 'serial' then
        Result.Serial := ExtractValue(Line)
      else if Key = 'licensee' then
        Result.Licensee := ExtractValue(Line)
      else if Key = 'machine_id' then
        Result.MachineID := ExtractValue(Line)
      else if Key = 'issued_date' then
        Result.IssuedDate := ExtractValue(Line)
      else if Key = 'expiry_date' then
        Result.ExpiryDate := ExtractValue(Line)
      else if Key = 'max_users' then
        Result.MaxUsers := StrToIntDef(ExtractValue(Line), 0)
      else if Key = 'features' then
        Result.Features := ExtractValue(Line)
      else if Key = 'signature' then
        Signature := ExtractValue(Line);
    end;

    // ตรวจสอบว่าข้อมูลจำเป็นครบถ้วนหรือไม่
    if (Result.Serial = '') or (Result.MachineID = '') or (Signature = '') then
    begin
      Result.Status := lsInvalidFormat;
      Exit;
    end;

    // ชั้นที่ 1: ตรวจสอบ HMAC Signature (ป้องกันการแก้ไขไฟล์ license.key)
    SignableData := BuildSignableData(
      Result.Serial, Result.Licensee, Result.MachineID,
      Result.IssuedDate, Result.ExpiryDate, Result.Features,
      Result.MaxUsers
    );
    ExpectedSig := SignLicenseData(SignableData);

    if LowerCase(Signature) <> LowerCase(ExpectedSig) then
    begin
      Result.Status := lsInvalidSignature;
      Exit;
    end;

    // ตรวจสอบ Machine ID
    if LowerCase(Result.MachineID) <> LowerCase(GetMachineID) then
    begin
      Result.Status := lsInvalidMachine;
      Exit;
    end;

    // ตรวจสอบวันหมดอายุ
    if Result.ExpiryDate <> '' then
    begin
      try
        ExpiryDT := EncodeDate(
          StrToInt(Copy(Result.ExpiryDate, 1, 4)),
          StrToInt(Copy(Result.ExpiryDate, 6, 2)),
          StrToInt(Copy(Result.ExpiryDate, 9, 2))
        );
        if Trunc(Now) > ExpiryDT then
        begin
          Result.Status := lsExpired;
          Exit;
        end;
      except
        Result.Status := lsInvalidFormat;
        Exit;
      end;
    end;

    // ผ่านทุกการตรวจสอบ — License ถูกต้อง
    Result.Status := lsValid;
    LicenseVerified := True;

  finally
    SL.Free;
  end;
end;

{ ===================================================================== }
{   ชั้นที่ 5: Scattered License Checks (กระจายจุดตรวจสอบ)              }
{   เรียกจากหลายจุดในโปรแกรม ป้องกันการ NOP out จุดตรวจจุดเดียว          }
{ ===================================================================== }

{ ตรวจสอบ License แบบเร็ว (เรียกจากหลายจุดในโปรแกรม เช่น Router) }
procedure QuickLicenseCheck;
var
  LicInfo: TLicenseInfo;
begin
  // ตรวจสอบ flag ก่อน
  if not LicenseVerified and not DemoModeActive then
  begin
    Writeln('LICENSE ERROR: License verification flag is invalid.');
    Halt(1);
  end;

  // ตรวจ Debugger ซ้ำ (อาจ attach มาทีหลัง)
  if IsDebuggerPresent then
  begin
    Writeln('LICENSE ERROR: Debugger detected.');
    Halt(1);
  end;

  // ตรวจ License ไฟล์จริงซ้ำเป็นระยะ (ยกเว้นโหมด Demo)
  if (not DemoModeActive) and (GlobalLicensePath <> '') then
  begin
    LicInfo := ValidateLicense(GlobalLicensePath);
    if LicInfo.Status <> lsValid then
    begin
      Writeln('LICENSE ERROR: ', LicenseStatusText(LicInfo.Status));
      Halt(1);
    end;
  end;
end;

{ ===================================================================== }
{   ชั้นที่ 6: Watchdog Thread (ตรวจซ้ำเป็นระยะอัตโนมัติ)                }
{   ทุก 5 นาทีจะตรวจสอบ License + Debugger + Binary Integrity ซ้ำ       }
{ ===================================================================== }

constructor TLicenseWatchdogThread.Create(const ALicPath: string);
begin
  inherited Create(True); // สร้างแบบ Suspended
  FLicensePath := ALicPath;
  FreeOnTerminate := True;
end;

procedure TLicenseWatchdogThread.Execute;
var
  LicInfo: TLicenseInfo;
begin
  while not Terminated do
  begin
    // รอ 5 นาที ก่อนตรวจซ้ำ
    Sleep(5 * 60 * 1000);

    if Terminated then Exit;

    // ตรวจ Debugger
    if IsDebuggerPresent then
    begin
      Writeln('WATCHDOG: Debugger detected. Shutting down.');
      Halt(1);
    end;

    // ตรวจ Binary Integrity
    if not IsBinaryIntact then
    begin
      Writeln('WATCHDOG: Binary integrity check failed. Shutting down.');
      Halt(1);
    end;

    // ตรวจ License ไฟล์ซ้ำ (ยกเว้น Demo mode)
    if (not DemoModeActive) and (FLicensePath <> '') then
    begin
      LicInfo := ValidateLicense(FLicensePath);
      if LicInfo.Status <> lsValid then
      begin
        Writeln('WATCHDOG: License validation failed: ', LicenseStatusText(LicInfo.Status));
        Halt(1);
      end;
    end;
  end;
end;

{ ===================================================================== }
{   License Key Generation (เฉพาะผู้พัฒนาใช้)                           }
{ ===================================================================== }

{ สร้าง Serial Number แบบสุ่ม รูปแบบ FPSSO-YYYY-XXXX-XXXX-XXXX }
function GenerateSerialNumber: string;
const
  HexChars = '0123456789ABCDEF';
var
  I, Block: Integer;
  S: string;
begin
  Result := 'FPSSO-' + FormatDateTime('yyyy', Now);
  for Block := 1 to 3 do
  begin
    S := '';
    for I := 1 to 4 do
      S := S + HexChars[Random(16) + 1];
    Result := Result + '-' + S;
  end;
end;

{ สร้างไฟล์ License Key ใหม่ }
function GenerateLicenseFile(const ASerial, ALicensee, AMachineID,
  AIssuedDate, AExpiryDate, AFeatures: string;
  AMaxUsers: Integer; const AOutputPath: string): Boolean;
var
  SL: TStringList;
  SignableData, Signature: string;
begin
  Result := False;

  SignableData := BuildSignableData(
    ASerial, ALicensee, AMachineID,
    AIssuedDate, AExpiryDate, AFeatures,
    AMaxUsers
  );

  Signature := SignLicenseData(SignableData);

  SL := TStringList.Create;
  try
    SL.Add('# ===================================');
    SL.Add('# fpsso License Key');
    SL.Add('# ===================================');
    SL.Add('# WARNING: Do not modify this file.');
    SL.Add('');
    SL.Add('serial=' + ASerial);
    SL.Add('licensee=' + ALicensee);
    SL.Add('machine_id=' + AMachineID);
    SL.Add('issued_date=' + AIssuedDate);
    SL.Add('expiry_date=' + AExpiryDate);
    SL.Add('max_users=' + IntToStr(AMaxUsers));
    SL.Add('features=' + AFeatures);
    SL.Add('signature=' + Signature);

    try
      SL.SaveToFile(AOutputPath);
      Result := True;
    except
      on E: Exception do
        Writeln('ERROR: Cannot save license file: ', E.Message);
    end;
  finally
    SL.Free;
  end;
end;

{ แปลง License Status เป็นข้อความภาษาไทย }
function LicenseStatusText(Status: TLicenseStatus): string;
begin
  case Status of
    lsValid:            Result := 'License ถูกต้อง พร้อมใช้งาน';
    lsExpired:          Result := 'License หมดอายุแล้ว กรุณาต่ออายุ';
    lsInvalidMachine:   Result := 'License ไม่ตรงกับเครื่องนี้ (Machine ID ไม่ตรง)';
    lsInvalidSignature: Result := 'License ไม่ถูกต้อง (ลายเซ็นไม่ผ่าน)';
    lsNotFound:         Result := 'ไม่พบไฟล์ License';
    lsInvalidFormat:    Result := 'รูปแบบไฟล์ License ไม่ถูกต้อง';
    lsTampered:         Result := 'ตรวจพบการดัดแปลง Binary หรือ Debugger';
  else
    Result := 'สถานะไม่ทราบ';
  end;
end;

initialization
  Randomize;
  LicenseVerified := False;
  DemoModeActive := False;
  GlobalLicensePath := '';
  // เก็บ SHA1 hash ของ binary ตัวเองตอนเริ่มต้น เพื่อใช้ตรวจสอบ integrity ทีหลัง
  OriginalBinaryHash := ComputeBinaryHash;

end.
