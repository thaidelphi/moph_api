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
