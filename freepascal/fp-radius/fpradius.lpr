program fpradius;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, RadiusConfig, RadiusDB, RadiusServer, mysql80conn;

var
  Cfg    : TRadiusConfig;
  Server : TRadiusServer;
  EnvPath: string;
  TestConn: TMySQL80Connection;

begin
  // ตรวจสอบ Parameter --help หรือ -h
  if (ParamCount > 0) and ((ParamStr(1) = '--help') or (ParamStr(1) = '-h')) then
  begin
    WriteLn('Usage: ./fpradius [path_to_env_file]');
    WriteLn('');
    WriteLn('====================================================');
    WriteLn(' คำแนะนำเพิ่มเติมก่อนการใช้งานระบบ fp-radius');
    WriteLn('====================================================');
    WriteLn('');
    WriteLn(' 1. การตั้งค่า Firewall (Allow Port)');
    WriteLn('    ระบบ RADIUS จำเป็นต้องใช้ Port UDP 1812 และ 1813');
    WriteLn('    คำสั่งเปิด Port สำหรับ ufw (Ubuntu):');
    WriteLn('      sudo ufw allow 1812/udp');
    WriteLn('      sudo ufw allow 1813/udp');
    WriteLn('');
    WriteLn('    สำหรับ firewalld (CentOS/RHEL):');
    WriteLn('      sudo firewall-cmd --zone=public --add-port=1812/udp --permanent');
    WriteLn('      sudo firewall-cmd --zone=public --add-port=1813/udp --permanent');
    WriteLn('      sudo firewall-cmd --reload');
    WriteLn('');
    WriteLn(' 2. การติดตั้ง Library เชื่อมต่อ MySQL/MariaDB');
    WriteLn('    หากพบ Error "Can not load default MySQL library..." ให้ติดตั้ง:');
    WriteLn('    สำหรับ Ubuntu/Debian:');
    WriteLn('      sudo apt-get install libmysqlclient-dev');
    WriteLn('    สำหรับ CentOS/RHEL:');
    WriteLn('      sudo yum install mysql-devel');
    WriteLn('');
    WriteLn(' 3. การเรียกไฟล์ตั้งค่า (.env)');
    WriteLn('    คุณสามารถระบุพาธของไฟล์ .env ต่อท้ายคำสั่งรันได้เลย เช่น:');
    WriteLn('      ./fpradius /opt/radius/.env');
    WriteLn('    * หากไม่ระบุ โปรแกรมจะพยายามไปอ่านไฟล์จาก /var/www/api/.env เป็นค่าเริ่มต้น');
    WriteLn('====================================================');
    Halt(0);
  end;

  // รับ Path ของ .env จาก Command Line หรือใช้ค่า Default
  if ParamCount > 0 then
    EnvPath := ParamStr(1)
  else
    EnvPath := '/var/www/api/.env';

  WriteLn('fp-radius: Loading config from ', EnvPath);

  // โหลด Config
  Cfg := LoadConfig(EnvPath);

  // ทดสอบเชื่อมต่อฐานข้อมูลเบื้องต้น
  if not DBConnect(Cfg, TestConn) then
  begin
    WriteLn('fp-radius: ERROR - Cannot connect to MySQL. Exiting.');
    Halt(1);
  end;
  DBDisconnect(TestConn);

  // สร้างและเริ่ม RADIUS Server (แต่ละ Thread จะสร้าง DB Connection ของตัวเอง)
  Server := TRadiusServer.Create(Cfg);
  try
    Server.Start;   // Blocking Loop
  finally
    Server.Free;
  end;
end.
