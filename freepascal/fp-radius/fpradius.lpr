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
  if not DBConnect(Cfg) then
  begin
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
