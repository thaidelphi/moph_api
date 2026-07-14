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
    WriteLn(' Additional Instructions for fp-radius');
    WriteLn('====================================================');
    WriteLn('');
    WriteLn(' 1. Firewall Configuration (Allow Ports)');
    WriteLn('    RADIUS requires UDP ports 1812 and 1813.');
    WriteLn('    For ufw (Ubuntu/Debian):');
    WriteLn('      sudo ufw allow 1812/udp');
    WriteLn('      sudo ufw allow 1813/udp');
    WriteLn('');
    WriteLn('    For firewalld (CentOS/RHEL):');
    WriteLn('      sudo firewall-cmd --zone=public --add-port=1812/udp --permanent');
    WriteLn('      sudo firewall-cmd --zone=public --add-port=1813/udp --permanent');
    WriteLn('      sudo firewall-cmd --reload');
    WriteLn('');
    WriteLn(' 2. MariaDB Server Installation');
    WriteLn('    For Ubuntu/Debian:');
    WriteLn('      sudo apt-get install mariadb-server');
    WriteLn('      sudo systemctl enable mariadb && sudo systemctl start mariadb');
    WriteLn('    For CentOS/RHEL:');
    WriteLn('      sudo yum install mariadb-server');
    WriteLn('      sudo systemctl enable mariadb && sudo systemctl start mariadb');
    WriteLn('');
    WriteLn(' 3. MySQL/MariaDB Client Library Installation');
    WriteLn('    If you encounter "Can not load default MySQL library..." error, install:');
    WriteLn('    For Ubuntu/Debian:');
    WriteLn('      sudo apt-get install libmysqlclient-dev');
    WriteLn('    For CentOS/RHEL:');
    WriteLn('      sudo yum install mysql-devel');
    WriteLn('');
    WriteLn(' 4. Loading Environment Variables (.env)');
    WriteLn('    You can specify the path to your .env file as an argument:');
    WriteLn('      ./fpradius /opt/radius/.env');
    WriteLn('    * If not provided, it will default to: /var/www/api/.env');
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
