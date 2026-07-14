program fpradius;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads, Unix,{$ENDIF}
  SysUtils, RadiusConfig, RadiusDB, RadiusServer, mysql80conn;

var
  Cfg    : TRadiusConfig;
  Server : TRadiusServer;
  EnvPath: string;
  TestConn: TMySQL80Connection;
  I      : Integer;
  IsInitDB: Boolean = False;

procedure InitDatabase(const ACfg: TRadiusConfig);
var
  CmdCreate, CmdImport: string;
  Res: Integer;
begin
  WriteLn('fp-radius: Initializing Database ', ACfg.DBName, ' at ', ACfg.DBHost, '...');
  
  // 1. Create database
  CmdCreate := 'mysql -h ' + ACfg.DBHost + ' -u ' + ACfg.DBUser + ' -p' + ACfg.DBPass + 
               ' -e "CREATE DATABASE IF NOT EXISTS ' + ACfg.DBName + ' CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"';
  WriteLn('Executing: CREATE DATABASE IF NOT EXISTS ', ACfg.DBName);
  Res := fpSystem(CmdCreate);
  if Res <> 0 then
  begin
    WriteLn('ERROR: Failed to create database. mysql client might not be installed or credentials are wrong.');
    Halt(1);
  end;

  // 2. Import schema
  CmdImport := 'mysql -h ' + ACfg.DBHost + ' -u ' + ACfg.DBUser + ' -p' + ACfg.DBPass + 
               ' ' + ACfg.DBName + ' < /var/www/api/radius_schema.sql';
  WriteLn('Executing: Import /var/www/api/radius_schema.sql');
  Res := fpSystem(CmdImport);
  if Res <> 0 then
  begin
    WriteLn('ERROR: Failed to import schema from /var/www/api/radius_schema.sql');
    Halt(1);
  end;

  WriteLn('SUCCESS: Database initialization completed successfully!');
end;

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
    WriteLn('');
    WriteLn(' 5. Database Initialization (--init-database)');
    WriteLn('    To automatically create the database and setup tables based on .env credentials, run:');
    WriteLn('      ./fpradius .env --init-database');
    WriteLn('====================================================');
    Halt(0);
  end;

  // รับ Path ของ .env จาก Command Line หรือใช้ค่า Default
  EnvPath := '/var/www/api/.env'; // ค่าเริ่มต้น
  for I := 1 to ParamCount do
  begin
    if ParamStr(I) = '--init-database' then
      IsInitDB := True
    else if not ((ParamStr(I) = '--help') or (ParamStr(I) = '-h')) then
      EnvPath := ParamStr(I); // สมมติว่า parameter อื่นๆ คือ Path ของ .env
  end;

  WriteLn('fp-radius: Loading config from ', EnvPath);

  // โหลด Config
  Cfg := LoadConfig(EnvPath);

  // ถ้าต้องการสร้าง Database ให้ทำตรงนี้แล้วออกเลย
  if IsInitDB then
  begin
    InitDatabase(Cfg);
    Halt(0);
  end;

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
