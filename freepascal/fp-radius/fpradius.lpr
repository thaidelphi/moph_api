program fpradius;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads, Unix,{$ENDIF}
  SysUtils, RadiusConfig, RadiusDB, RadiusServer, mysql80conn, RadiusSchemaData;

var
  Cfg    : TRadiusConfig;
  Server : TRadiusServer;
  EnvPath: string;
  TestConn: TMySQL80Connection;
  I      : Integer;
  IsInitDB: Boolean = False;
  IsInstallSvc: Boolean = False;
  IsUninstallSvc: Boolean = False;

procedure InitDatabase(const ACfg: TRadiusConfig);
var
  CmdCreate, CmdImport: string;
  Res: Integer;
  SchemaPath: string;
  F: file;
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
  SchemaPath := '/var/www/api/radius_schema.sql';
  if not FileExists(SchemaPath) then
  begin
    SchemaPath := ExtractFilePath(ParamStr(0)) + 'radius_schema.sql';
    if not FileExists(SchemaPath) then
    begin
      WriteLn('Schema file not found. Extracting embedded schema...');
      SchemaPath := '/tmp/fpradius_embedded_schema.sql';
      AssignFile(F, SchemaPath);
      Rewrite(F, 1);
      BlockWrite(F, RadiusSchemaBytes[0], RadiusSchemaSize);
      CloseFile(F);
    end;
  end;

  CmdImport := 'mysql -h ' + ACfg.DBHost + ' -u ' + ACfg.DBUser + ' -p' + ACfg.DBPass + 
               ' ' + ACfg.DBName + ' < ' + SchemaPath;
  WriteLn('Executing: Import ', SchemaPath);
  Res := fpSystem(CmdImport);
  if Res <> 0 then
  begin
    WriteLn('ERROR: Failed to import schema from ', SchemaPath);
    if SchemaPath = '/tmp/fpradius_embedded_schema.sql' then DeleteFile(SchemaPath);
    Halt(1);
  end;

  if SchemaPath = '/tmp/fpradius_embedded_schema.sql' then DeleteFile(SchemaPath);

  WriteLn('SUCCESS: Database initialization completed successfully!');
end;

procedure InstallService(const AEnvPath: string);
var
  SvcPath, BinPath, Content: string;
  F: TextFile;
begin
  BinPath := ExpandFileName(ParamStr(0));
  SvcPath := '/tmp/fpradius.service';
  
  Content := '[Unit]' + sLineBreak +
             'Description=fp-radius Server' + sLineBreak +
             'After=network.target mysql.service mariadb.service' + sLineBreak +
             sLineBreak +
             '[Service]' + sLineBreak +
             'Type=simple' + sLineBreak +
             'ExecStart=' + BinPath + ' ' + ExpandFileName(AEnvPath) + sLineBreak +
             'Restart=always' + sLineBreak +
             'RestartSec=5' + sLineBreak +
             'WorkingDirectory=' + ExtractFilePath(BinPath) + sLineBreak +
             sLineBreak +
             '[Install]' + sLineBreak +
             'WantedBy=multi-user.target' + sLineBreak;
             
  AssignFile(F, SvcPath);
  try
    Rewrite(F);
    Write(F, Content);
    CloseFile(F);
  except
    WriteLn('ERROR: Cannot write to ', SvcPath);
    Halt(1);
  end;

  WriteLn('Installing service to /etc/systemd/system/fpradius.service ...');
  if fpSystem('sudo mv ' + SvcPath + ' /etc/systemd/system/fpradius.service') <> 0 then
  begin
    WriteLn('ERROR: Failed to move service file. Make sure you have sudo privileges.');
    Halt(1);
  end;
  
  WriteLn('Reloading systemd daemon...');
  fpSystem('sudo systemctl daemon-reload');
  
  WriteLn('Enabling fpradius service...');
  fpSystem('sudo systemctl enable fpradius.service');
  
  WriteLn('Starting fpradius service...');
  fpSystem('sudo systemctl start fpradius.service');
  
  WriteLn('SUCCESS: fpradius service installed and started successfully!');
end;

procedure UninstallService;
begin
  WriteLn('Stopping fpradius service...');
  fpSystem('sudo systemctl stop fpradius.service');
  
  WriteLn('Disabling fpradius service...');
  fpSystem('sudo systemctl disable fpradius.service');
  
  WriteLn('Removing service file from /etc/systemd/system/fpradius.service ...');
  if fpSystem('sudo rm -f /etc/systemd/system/fpradius.service') <> 0 then
  begin
    WriteLn('ERROR: Failed to remove service file. Make sure you have sudo privileges.');
  end;
  
  WriteLn('Reloading systemd daemon...');
  fpSystem('sudo systemctl daemon-reload');
  
  WriteLn('SUCCESS: fpradius service uninstalled successfully!');
end;

function PromptDefault(const Msg, DefaultVal: string): string;
begin
  if DefaultVal <> '' then
    Write(Msg, ' [', DefaultVal, ']: ')
  else
    Write(Msg, ': ');
  ReadLn(Result);
  if Result = '' then Result := DefaultVal;
end;

procedure SetEnvVar(List: TStringList; const Key, Value: string);
var
  I: Integer;
begin
  for I := 0 to List.Count - 1 do
  begin
    if Pos(Key + '=', Trim(List[I])) = 1 then
    begin
      List[I] := Key + '=' + Value;
      Exit;
    end;
  end;
  List.Add(Key + '=' + Value);
end;

procedure SetupWizard(const AEnvPath: string);
var
  EnvContent: TStringList;
  Ans: string;
begin
  WriteLn('=========================================');
  WriteLn('    fp-radius Configuration Setup Wizard');
  WriteLn('=========================================');
  WriteLn('Leave blank to use the [default value].');
  WriteLn('');
  
  EnvContent := TStringList.Create;
  try
    if FileExists(AEnvPath) then
    begin
      WriteLn('Existing configuration found at ', AEnvPath, '. Updating it safely.');
      EnvContent.LoadFromFile(AEnvPath);
    end;

    SetEnvVar(EnvContent, 'DB_HOST', PromptDefault('Database Host', '127.0.0.1'));
    SetEnvVar(EnvContent, 'DB_PORT', PromptDefault('Database Port', '3306'));
    SetEnvVar(EnvContent, 'DB_USER', PromptDefault('Database User', 'root'));
    SetEnvVar(EnvContent, 'DB_PASS', PromptDefault('Database Password', ''));
    SetEnvVar(EnvContent, 'DB_NAME', PromptDefault('Database Name', 'radius'));
    
    // Check if RADIUS_SECRET exists for spacing
    if EnvContent.IndexOf('RADIUS_SECRET=') = -1 then EnvContent.Add('');
    
    SetEnvVar(EnvContent, 'RADIUS_SECRET', PromptDefault('RADIUS Shared Secret', 'testing123'));
    SetEnvVar(EnvContent, 'RADIUS_PORT', PromptDefault('RADIUS Auth Port', '1812'));
    SetEnvVar(EnvContent, 'RADIUS_ACCT_PORT', PromptDefault('RADIUS Acct Port', '1813'));
    
    WriteLn('');
    WriteLn('Saving configuration to: ', AEnvPath);
    try
      EnvContent.SaveToFile(AEnvPath);
      WriteLn('Configuration saved successfully!');
    except
      on E: Exception do
      begin
        WriteLn('Failed to save .env file: ', E.Message);
        WriteLn('Did you run with sudo?');
        Halt(1);
      end;
    end;
  finally
    EnvContent.Free;
  end;
  
  WriteLn('');
  Ans := PromptDefault('Do you want to initialize the database schema now? (y/n)', 'y');
  if LowerCase(Ans) = 'y' then
  begin
    InitDatabase(LoadConfig(AEnvPath));
  end;

  WriteLn('');
  Ans := PromptDefault('Do you want to install fp-radius as a background service now? (y/n)', 'y');
  if LowerCase(Ans) = 'y' then
  begin
    InstallService(AEnvPath);
  end;
  
  WriteLn('Setup complete! You can start the server manually by running: ./fpradius');
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
    WriteLn('      sudo mysql_secure_installation');
    WriteLn('    For CentOS/RHEL:');
    WriteLn('      sudo yum install mariadb-server');
    WriteLn('      sudo systemctl enable mariadb && sudo systemctl start mariadb');
    WriteLn('      sudo mysql_secure_installation');
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
    WriteLn('    * If not provided, it will look for .env in the current directory,');
    WriteLn('      then default to: /var/www/api/.env');
    WriteLn('');
    WriteLn(' 5. Database Initialization (--init-database)');
    WriteLn('    To automatically create the database and setup tables based on .env credentials, run:');
    WriteLn('      ./fpradius --init-database');
    WriteLn('');
    WriteLn(' 6. Install as Systemd Service (--installservice)');
    WriteLn('    To install and start fp-radius as a background service:');
    WriteLn('      sudo ./fpradius --installservice');
    WriteLn('');
    WriteLn(' 7. Uninstall Systemd Service (--uninstallservice)');
    WriteLn('    To stop and remove the fp-radius background service:');
    WriteLn('      sudo ./fpradius --uninstallservice');
    WriteLn('');
    WriteLn(' 8. Setup Wizard (--setup-wizard or --install-wizard)');
    WriteLn('    To launch the interactive configuration wizard:');
    WriteLn('      sudo ./fpradius --setup-wizard');
    WriteLn('');
    WriteLn(' 9. Viewing Logs (Systemd)');
    WriteLn('    To view real-time logs when running as a service:');
    WriteLn('      sudo journalctl -u fpradius -f');
    WriteLn('');
    WriteLn(' 10. Run with PM2 (Alternative Process Manager)');
    WriteLn('    If you prefer using PM2 instead of Systemd, you can run:');
    WriteLn('      pm2 start ./fpradius --name "fpradius"');
    WriteLn('      pm2 save');
    WriteLn('      pm2 startup');
    WriteLn('====================================================');
    Halt(0);
  end;

  // รับ Path ของ .env จาก Command Line หรือใช้ค่า Default
  EnvPath := ''; 
  for I := 1 to ParamCount do
  begin
    if ParamStr(I) = '--init-database' then
      IsInitDB := True
    else if ParamStr(I) = '--installservice' then
      IsInstallSvc := True
    else if ParamStr(I) = '--uninstallservice' then
      IsUninstallSvc := True
    else if not ((ParamStr(I) = '--help') or (ParamStr(I) = '-h')) then
      EnvPath := ParamStr(I); // สมมติว่า parameter อื่นๆ คือ Path ของ .env
  end;

  if EnvPath = '' then
  begin
    if FileExists('.env') then
      EnvPath := '.env'
    else if FileExists(ExtractFilePath(ParamStr(0)) + '.env') then
      EnvPath := ExtractFilePath(ParamStr(0)) + '.env'
    else
      EnvPath := '/var/www/api/.env';
  end;

  // ตรวจสอบ Setup Wizard
  for I := 1 to ParamCount do
  begin
    if (ParamStr(I) = '--setup-wizard') or (ParamStr(I) = '--install-wizard') then
    begin
      SetupWizard(EnvPath);
      Halt(0);
    end;
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
  
  // ถ้าต้องการติดตั้ง Service ให้ทำตรงนี้แล้วออกเลย
  if IsInstallSvc then
  begin
    InstallService(EnvPath);
    Halt(0);
  end;
  
  // ถ้าต้องการลบ Service ให้ทำตรงนี้แล้วออกเลย
  if IsUninstallSvc then
  begin
    UninstallService;
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
