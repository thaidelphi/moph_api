program keygen;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, License;

var
  GenMachineID, GenLicensee, GenExpiry, GenFeatures: string;
  GenSerial, GenIssuedDate, GenMaxUsersStr: string;
  GenMaxUsers: Integer;
  Ans: string;

begin
  Writeln('============================================');
  Writeln('      fpsso License Key Generator');
  Writeln('============================================');
  Writeln('');
  
  // รับข้อมูลจากผู้ใช้แบบ Interactive
  Write('Machine ID ของลูกค้า: ');
  ReadLn(GenMachineID);
  if GenMachineID = '' then
  begin
    Writeln('ERROR: Machine ID ต้องไม่ว่าง');
    Halt(1);
  end;
  
  Write('ชื่อหน่วยงาน: ');
  ReadLn(GenLicensee);
  if GenLicensee = '' then
    GenLicensee := 'Unnamed';
  
  Write('วันหมดอายุ (YYYY-MM-DD, ว่าง=ไม่หมดอายุ): ');
  ReadLn(GenExpiry);
  
  Write('จำนวนผู้ใช้สูงสุด (0=ไม่จำกัด): ');
  ReadLn(GenMaxUsersStr);
  GenMaxUsers := StrToIntDef(GenMaxUsersStr, 0);
  
  GenFeatures := '';
  
  Write('เปิดใช้ Login ด้วย Username/Password (y/n) [y]: ');
  ReadLn(Ans);
  if (Ans = '') or (LowerCase(Ans) = 'y') then
    GenFeatures := GenFeatures + 'local,';

  Write('เปิดใช้ Login ด้วย ThaID (y/n) [y]: ');
  ReadLn(Ans);
  if (Ans = '') or (LowerCase(Ans) = 'y') then
    GenFeatures := GenFeatures + 'thaid,';

  Write('เปิดใช้ Login ด้วย Provider ID (y/n) [y]: ');
  ReadLn(Ans);
  if (Ans = '') or (LowerCase(Ans) = 'y') then
    GenFeatures := GenFeatures + 'providerid,';
    
  // ลบ comma ตัวสุดท้าย
  if Length(GenFeatures) > 0 then
    SetLength(GenFeatures, Length(GenFeatures) - 1);
  if GenFeatures = '' then
    GenFeatures := 'none';
  
  // สร้าง Serial Number
  GenSerial := GenerateSerialNumber;
  GenIssuedDate := FormatDateTime('yyyy-mm-dd', Now);
  
  // สร้างไฟล์ License Key
  if GenerateLicenseFile(
    GenSerial, GenLicensee, GenMachineID,
    GenIssuedDate, GenExpiry, GenFeatures,
    GenMaxUsers, 'license.key'
  ) then
  begin
    Writeln('');
    Writeln('License Key สร้างสำเร็จ!');
    Writeln('  Serial    : ', GenSerial);
    Writeln('  Licensee  : ', GenLicensee);
    Writeln('  Machine ID: ', GenMachineID);
    Writeln('  Issued    : ', GenIssuedDate);
    Writeln('  Expiry    : ', GenExpiry);
    Writeln('  Max Users : ', GenMaxUsers);
    Writeln('  Features  : ', GenFeatures);
    Writeln('');
    Writeln('ไฟล์ถูกบันทึกที่: license.key');
    Writeln('กรุณาส่งไฟล์นี้ให้ลูกค้า');
  end
  else
  begin
    Writeln('');
    Writeln('ERROR: ไม่สามารถสร้าง License Key ได้');
    Halt(1);
  end;
end.
