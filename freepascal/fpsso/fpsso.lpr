program fpsso;

{$mode objfpc}{$H+}
{$codepage utf8}

uses
  {$IFDEF UNIX}
  cthreads,
  cwstring,
  {$ENDIF}
  Classes, SysUtils, Process,
  Config, SessionMgr, Router, HttpServer, HTTPDefs,
  AuthLocal, AuthThaiD, AuthProviderID, AuthGoogle, FortiGate, AdminUsers,
  License, RadiusDB;

// Thread สำหรับล้าง Session ที่หมดอายุแล้วออกจาก Memory ทุก 10 นาที
type
  TSessionCleanupThread = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure TSessionCleanupThread.Execute;
begin
  // วนซ้ำตลอดเวลาจนกว่า Thread จะถูกสั่งหยุด
  while not Terminated do
  begin
    Sleep(10 * 60 * 1000); // รอ 10 นาที (milliseconds)
    if not Terminated then
    begin
      // ล้าง Session ที่ไม่มีการใช้งานมานานเกิน 30 นาที
      SessionManager.CleanupExpired(30);
      Writeln('SessionCleanup: Expired sessions cleaned up.');
    end;
  end;
end;

procedure HandleRoot(Req: TRequest; Res: TResponse);
var
  HtmlContent: string;
  TemplatePath: string;
  MagicToken, SessionID: string;
  Data: TSessionData;
begin
  // Handle FortiGate 'magic' and 'post' tokens
  MagicToken := Req.QueryFields.Values['magic'];
  if (MagicToken <> '') or (Req.QueryFields.Values['post'] <> '') then
  begin
    SessionID := Req.CookieFields.Values['SSOSESSID'];
    if (SessionID = '') or not SessionManager.GetSession(SessionID, Data) then
    begin
      SessionID := SessionManager.CreateSession;
      SessionManager.GetSession(SessionID, Data);
    end;
    
    if MagicToken <> '' then
      Data.Magic := MagicToken;
      
    if Req.QueryFields.Values['post'] <> '' then
      Data.PostUrl := Req.QueryFields.Values['post'];

    if Req.QueryFields.Values['redir'] <> '' then
      Data.RedirUrl := Req.QueryFields.Values['redir']
    else if Req.QueryFields.Values['url'] <> '' then
      Data.RedirUrl := Req.QueryFields.Values['url'];

    if Req.QueryFields.Values['usermac'] <> '' then
      Data.UserMac := Req.QueryFields.Values['usermac'];
      
    if Req.QueryFields.Values['userip'] <> '' then
      Data.ClientIP := Req.QueryFields.Values['userip']
    else
      Data.ClientIP := GetClientIP(Req);
      
    SessionManager.UpdateSession(SessionID, Data);
    
    with Res.Cookies.Add do
    begin
      Name := 'SSOSESSID';
      Value := SessionID;
      Path := '/';
      Expires := Now + 1; // 1 day
      HttpOnly := True;
    end;
  end
  else
  begin
    // หากไม่ได้ถูก FortiGate ส่งมา (ไม่มี magic token) และผู้ใช้ล็อกอินอยู่แล้ว ให้พาไปหน้าสถานะ /sso/status ทันที
    SessionID := Req.CookieFields.Values['SSOSESSID'];
    if (SessionID <> '') and SessionManager.GetSession(SessionID, Data) and (Data.Username <> '') then
    begin
      Redirect(Res, '/sso/status');
      Exit;
    end;
  end;

  // ตรวจสอบ login.html ในโฟลเดอร์ templates/login_template ก่อน
  TemplatePath := ExtractFilePath(ParamStr(0)) + 'templates/login_template/login.html';
  
  if not FileExists(TemplatePath) then
    TemplatePath := AppCfg.LoginTemplatePath;

  if FileExists(TemplatePath) then
  begin
    with TStringList.Create do
    try
      LoadFromFile(TemplatePath);
      HtmlContent := Text;
    finally
      Free;
    end;
    
    // กำหนด Feature Flags สำหรับ Template (ถ้าไม่มี License ให้ถือว่าใช้ได้ทุกอย่างแบบ Demo)
    if DemoModeActive then
    begin
      HtmlContent := StringReplace(HtmlContent, '{{FEAT_LOCAL}}', 'true', [rfReplaceAll]);
      HtmlContent := StringReplace(HtmlContent, '{{FEAT_THAID}}', 'true', [rfReplaceAll]);
      HtmlContent := StringReplace(HtmlContent, '{{FEAT_PROVIDERID}}', 'true', [rfReplaceAll]);
      HtmlContent := StringReplace(HtmlContent, '{{FEAT_GOOGLE}}', 'true', [rfReplaceAll]);
      HtmlContent := StringReplace(HtmlContent, '{{POPUP_ENABLED}}', 'true', [rfReplaceAll]);
    end
    else
    begin
      HtmlContent := StringReplace(HtmlContent, '{{FEAT_LOCAL}}', BoolToStr(HasFeature('local'), 'true', 'false'), [rfReplaceAll]);
      HtmlContent := StringReplace(HtmlContent, '{{FEAT_THAID}}', BoolToStr(HasFeature('thaid'), 'true', 'false'), [rfReplaceAll]);
      HtmlContent := StringReplace(HtmlContent, '{{FEAT_PROVIDERID}}', BoolToStr(HasFeature('providerid'), 'true', 'false'), [rfReplaceAll]);
      HtmlContent := StringReplace(HtmlContent, '{{FEAT_GOOGLE}}', BoolToStr(HasFeature('google'), 'true', 'false'), [rfReplaceAll]);
      HtmlContent := StringReplace(HtmlContent, '{{POPUP_ENABLED}}', BoolToStr(AppCfg.EnableLogoutPopup, 'true', 'false'), [rfReplaceAll]);
    end;  
    
    Res.Code := 200;
    Res.ContentType := 'text/html; charset=utf-8';
    Res.SetCustomHeader('Cache-Control', 'no-store, no-cache, must-revalidate');
    Res.SetCustomHeader('Pragma', 'no-cache');
    Res.SetCustomHeader('Expires', '0');
    Res.Content := HtmlContent;
    Res.SendContent;
  end
  else
    SendJSONError(Res, 404, 'Login template not found at: ' + TemplatePath);
end;

function ReadBinaryFile(const FileName: string): string;
var
  FS: TFileStream;
begin
  Result := '';
  if FileExists(FileName) then
  begin
    FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      SetLength(Result, FS.Size);
      if FS.Size > 0 then
        FS.ReadBuffer(Result[1], FS.Size);
    finally
      FS.Free;
    end;
  end;
end;

procedure HandleImage(Req: TRequest; Res: TResponse);
var
  FilePath: string;
  Ext: string;
begin
  FilePath := ExtractFilePath(ParamStr(0)) + 'templates/login_template' + Req.PathInfo;
  if FileExists(FilePath) then
  begin
    Res.Code := 200;
    Ext := LowerCase(ExtractFileExt(FilePath));
    if Ext = '.png' then Res.ContentType := 'image/png'
    else if (Ext = '.jpg') or (Ext = '.jpeg') then Res.ContentType := 'image/jpeg'
    else if Ext = '.svg' then Res.ContentType := 'image/svg+xml'
    else Res.ContentType := 'application/octet-stream';
    
    Res.SetCustomHeader('Cache-Control', 'public, max-age=86400');
    Res.Content := ReadBinaryFile(FilePath);
    Res.SendContent;
  end
  else
  begin
    Res.Code := 404;
    Res.ContentType := 'text/plain';
    Res.Content := 'Image not found';
    Res.SendContent;
  end;
end;

procedure HandleHowTo(Req: TRequest; Res: TResponse);
var
  TemplatePath, MdPath: string;
  HtmlContent, MdContent: string;
begin
  TemplatePath := ExtractFilePath(ParamStr(0)) + 'templates/howto.html';
  MdPath := ExtractFilePath(ParamStr(0)) + 'deploy_guide.md';
  
  if FileExists(TemplatePath) and FileExists(MdPath) then
  begin
    with TStringList.Create do
    try
      LoadFromFile(MdPath);
      MdContent := Text;
      
      LoadFromFile(TemplatePath);
      HtmlContent := Text;
    finally
      Free;
    end;
    
    // Inject markdown into the HTML template
    HtmlContent := StringReplace(HtmlContent, '{{MARKDOWN_CONTENT}}', MdContent, [rfReplaceAll]);
    
    Res.Code := 200;
    Res.ContentType := 'text/html; charset=utf-8';
    Res.Content := HtmlContent;
    Res.SendContent;
  end
  else
  begin
    SendJSONError(Res, 404, 'HowTo template or markdown file not found');
  end;
end;

procedure InstallService;
var
  ServiceFileContent: string;
  ExePath, WorkDir, OutStr: string;
  StrList: TStringList;
begin
  Writeln('Installing fpsso as a systemd service...');
  ExePath := ExpandFileName(ParamStr(0));
  WorkDir := ExtractFilePath(ExePath);
  if (Length(WorkDir) > 0) and (WorkDir[Length(WorkDir)] = DirectorySeparator) then
    SetLength(WorkDir, Length(WorkDir) - 1);

  ServiceFileContent := 
    '[Unit]' + sLineBreak +
    'Description=FreePascal SSO HTTP Server' + sLineBreak +
    'After=network.target mysql.service' + sLineBreak +
    sLineBreak +
    '[Service]' + sLineBreak +
    'Type=simple' + sLineBreak +
    'User=root' + sLineBreak +
    'WorkingDirectory=' + WorkDir + sLineBreak +
    'ExecStart=' + ExePath + sLineBreak +
    'Restart=on-failure' + sLineBreak +
    'RestartSec=5s' + sLineBreak +
    'StandardOutput=journal' + sLineBreak +
    'StandardError=journal' + sLineBreak +
    sLineBreak +
    '[Install]' + sLineBreak +
    'WantedBy=multi-user.target' + sLineBreak;

  StrList := TStringList.Create;
  try
    StrList.Text := ServiceFileContent;
    try
      StrList.SaveToFile('/etc/systemd/system/fpsso.service');
      Writeln('Successfully wrote /etc/systemd/system/fpsso.service');
    except
      on E: Exception do
      begin
        Writeln('Failed to write service file: ', E.Message);
        Writeln('Did you run with sudo? (e.g., sudo ./fpsso --installservice)');
        Halt(1);
      end;
    end;
  finally
    StrList.Free;
  end;

  Writeln('Reloading systemd daemon...');
  RunCommand('systemctl', ['daemon-reload'], OutStr);
  
  Writeln('Enabling fpsso service...');
  RunCommand('systemctl', ['enable', 'fpsso'], OutStr);
  
  Writeln('Starting fpsso service...');
  RunCommand('systemctl', ['start', 'fpsso'], OutStr);
  
  Writeln('Service installed and started successfully!');
  Writeln('You can check status with: sudo systemctl status fpsso');
end;

procedure UninstallService;
var
  OutStr: string;
begin
  Writeln('Uninstalling fpsso systemd service...');
  
  Writeln('Stopping fpsso service...');
  RunCommand('systemctl', ['stop', 'fpsso'], OutStr);
  
  Writeln('Disabling fpsso service...');
  RunCommand('systemctl', ['disable', 'fpsso'], OutStr);
  
  if FileExists('/etc/systemd/system/fpsso.service') then
  begin
    Writeln('Removing service file...');
    if not DeleteFile('/etc/systemd/system/fpsso.service') then
      Writeln('Failed to delete /etc/systemd/system/fpsso.service. Did you run with sudo?');
  end;
  
  Writeln('Reloading systemd daemon...');
  RunCommand('systemctl', ['daemon-reload'], OutStr);
  
  Writeln('Service uninstalled successfully!');
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

procedure InstallApacheProxy(const DomainName, PortStr: string);
var
  Ans, ConfPath, ProxyStr, OutStr: string;
  StrList: TStringList;
  I, InsertPos: Integer;
  HasProxy: Boolean;
begin
  Writeln('');
  Ans := PromptDefault('Do you want to automatically configure Apache Reverse Proxy? (y/n)', 'y');
  if LowerCase(Ans) <> 'y' then Exit;

  ConfPath := PromptDefault('Apache VirtualHost config file path', '/etc/apache2/sites-available/api.conf');
  if not FileExists(ConfPath) then
  begin
    Writeln('File not found: ', ConfPath);
    Exit;
  end;

  StrList := TStringList.Create;
  try
    StrList.LoadFromFile(ConfPath);
    
    HasProxy := False;
    InsertPos := -1;
    for I := 0 to StrList.Count - 1 do
    begin
      if Pos('ProxyPass /sso/', StrList[I]) > 0 then
      begin
        HasProxy := True;
        Break;
      end;
      if Pos('</VirtualHost>', StrList[I]) > 0 then
        InsertPos := I;
    end;

    if HasProxy then
    begin
      Writeln('Proxy configuration already exists in this file. Skipping.');
    end
    else if InsertPos >= 0 then
    begin
      ProxyStr := 
        '    # === Reverse Proxy for FreePascal SSO Server ===' + sLineBreak +
        '    ProxyPreserveHost On' + sLineBreak +
        '    RequestHeader set X-Forwarded-Proto "https"' + sLineBreak +
        '    RequestHeader set X-Forwarded-Host "' + DomainName + '"' + sLineBreak +
        '    ProxyPass /sso/ http://127.0.0.1:' + PortStr + '/ timeout=60' + sLineBreak +
        '    ProxyPassReverse /sso/ http://127.0.0.1:' + PortStr + '/';
      
      StrList.Insert(InsertPos, ProxyStr);
      try
        StrList.SaveToFile(ConfPath);
        Writeln('Successfully injected reverse proxy configuration into: ', ConfPath);
        
        Writeln('Enabling Apache proxy modules...');
        RunCommand('a2enmod', ['proxy', 'proxy_http', 'headers'], OutStr);
        
        Writeln('Reloading Apache...');
        RunCommand('systemctl', ['reload', 'apache2'], OutStr);
        
        Writeln('Apache Reverse Proxy configured successfully!');
      except
        on E: Exception do
          Writeln('Failed to write Apache config. Did you run with sudo? Error: ', E.Message);
      end;
    end
    else
    begin
      Writeln('Could not find </VirtualHost> tag in the file. Skipping injection.');
    end;
  finally
    StrList.Free;
  end;
end;

procedure SetupWizard;
var
  EnvContent: TStringList;
  EnvPath: string;
  Ans, DomainName, PortStr: string;
begin
  Writeln('=========================================');
  Writeln('    fp-sso Configuration Setup Wizard');
  Writeln('=========================================');
  Writeln('Leave blank to use the [default value].');
  Writeln('');
  
  DomainName := PromptDefault('Base Domain Name (e.g. api.domain.go.th)', 'yourdomain.com');
  Writeln('');
  
  EnvContent := TStringList.Create;
  try
    EnvContent.Add('DB_HOST=' + PromptDefault('Database Host', '127.0.0.1'));
    EnvContent.Add('DB_USER=' + PromptDefault('Database User', 'root'));
    EnvContent.Add('DB_PASS=' + PromptDefault('Database Password', ''));
    EnvContent.Add('DB_NAME=' + PromptDefault('Database Name', 'radius'));
    EnvContent.Add('');
    
    Writeln('');
    Writeln('--- ThaID Configuration ---');
    EnvContent.Add('THAID_CLIENT_ID=' + PromptDefault('ThaID Client ID', ''));
    EnvContent.Add('THAID_SECRET_ID=' + PromptDefault('ThaID Secret', ''));
    EnvContent.Add('THAID_REDIRECT_URI=' + PromptDefault('ThaID Redirect URI', 'https://' + DomainName + '/sso/auth/thaid/callback'));
    EnvContent.Add('THAID_URL_TOKEN=' + PromptDefault('ThaID Token URL', 'https://imauth.bora.dopa.go.th/api/v2/oauth2/token/'));
    EnvContent.Add('THAID_URL_AUTH=' + PromptDefault('ThaID Auth URL', 'https://imauth.bora.dopa.go.th/api/v2/oauth2/auth/'));
    EnvContent.Add('THAID_SCOPE=' + PromptDefault('ThaID Scope', 'pid name address'));
    EnvContent.Add('');
    
    Writeln('');
    Writeln('--- MOPH Provider ID Configuration ---');
    EnvContent.Add('PROVIDER_ID_CLIENT_ID=' + PromptDefault('Provider ID Client ID', ''));
    EnvContent.Add('PROVIDER_ID_SECRET_KEY=' + PromptDefault('Provider ID Secret', ''));
    EnvContent.Add('PROVIDER_ID_REDIRECT_URI=' + PromptDefault('Provider ID Redirect URI', 'https://' + DomainName + '/sso/auth/providerid/callback'));
    EnvContent.Add('PROVIDER_ID_URL=' + PromptDefault('Provider ID Base URL', 'https://provider.id.th'));
    EnvContent.Add('');
    
    Writeln('');
    Writeln('--- FortiGate & System Configuration ---');
    EnvContent.Add('FORTIGATE_LOGOUT_URL=' + PromptDefault('FortiGate Logout URL', ''));
    EnvContent.Add('LOGIN_TEMPLATE_PATH=' + PromptDefault('Custom Login Template Path', ExtractFilePath(ParamStr(0)) + 'templates/login.html'));
    EnvContent.Add('ADMIN_USERNAME=' + PromptDefault('Admin Username', 'admin'));
    EnvContent.Add('SSO_AUTO_APPROVE=' + PromptDefault('SSO Auto Approve new users (true/false)', 'false'));
    PortStr := PromptDefault('Application Port', '8080');
    EnvContent.Add('APP_PORT=' + PortStr);
    
    Writeln('');
    EnvPath := ExtractFilePath(ParamStr(0)) + '.env';
    Writeln('Saving configuration to: ', EnvPath);
    try
      EnvContent.SaveToFile(EnvPath);
      Writeln('Configuration saved successfully!');
    except
      on E: Exception do
      begin
        Writeln('Failed to save .env file: ', E.Message);
        Writeln('Did you run with sudo? (e.g., sudo ./fpsso --setup-wizard)');
        Halt(1);
      end;
    end;
  finally
    EnvContent.Free;
  end;
  
  Writeln('');
  Ans := PromptDefault('Do you want to install fpsso as a background service now? (y/n)', 'y');
  if LowerCase(Ans) = 'y' then
  begin
    InstallService;
  end;
  
  InstallApacheProxy(DomainName, PortStr);
  
  Writeln('Setup complete! If you did not install the service, you can start the server manually by running: ./fpsso');
end;

procedure ShowHelp;
begin
  Writeln('Usage: fpsso [OPTIONS]');
  Writeln('');
  Writeln('Options:');
  Writeln('  -h, --help           Show this help message and exit');
  Writeln('  --installservice     Generate systemd service file and install it');
  Writeln('  --uninstallservice   Stop and remove the systemd service');
  Writeln('  --setup-wizard       Launch the interactive configuration wizard to generate .env');
  Writeln('  --hwid               Show Machine ID of this server (for license activation)');
  Writeln('');
  Writeln('License:');
  Writeln('  Place license.key file next to the fpsso binary, or set LICENSE_KEY in .env');
  Writeln('');
  Writeln('Service Management Commands (Systemd):');
  Writeln('  sudo systemctl start fpsso      Start the service');
  Writeln('  sudo systemctl stop fpsso       Stop the service');
  Writeln('  sudo systemctl restart fpsso    Restart the service');
  Writeln('  sudo systemctl status fpsso     Check service status');
  Writeln('');
  Writeln('Running without any options will start the SSO HTTP server (default port 8080).');
  Halt(0);
end;
var
  EnvPathToLoad: string;
  CleanupThread: TSessionCleanupThread;  // Thread สำหรับล้าง Session หมดอายุ
  WatchdogThread: TLicenseWatchdogThread; // Thread ตรวจสอบ License และ Debugger
  LicInfo: TLicenseInfo;  // ข้อมูล License ที่อ่านได้
  LicPath: string;  // path ของไฟล์ license.key

begin
  Writeln('Initializing fp-sso...');

  if (ParamCount > 0) then
  begin
    if (ParamStr(1) = '-h') or (ParamStr(1) = '--help') then
      ShowHelp;

    if ParamStr(1) = '--installservice' then
    begin
      InstallService;
      Halt(0);
    end;

    if ParamStr(1) = '--uninstallservice' then
    begin
      UninstallService;
      Halt(0);
    end;

    if ParamStr(1) = '--setup-wizard' then
    begin
      SetupWizard;
      Halt(0);
    end;

    // แสดง Machine ID ของเครื่องปัจจุบัน (สำหรับส่งให้ผู้พัฒนาเพื่อสร้าง License Key)
    if ParamStr(1) = '--hwid' then
    begin
      Writeln('=== fpsso Machine ID ===' );
      Writeln('Machine ID: ', GetMachineID);
      Writeln('');
      Writeln('กรุณาส่งค่า Machine ID นี้ให้กับผู้พัฒนาเพื่อสร้าง License Key');
      Halt(0);
    end;
  end;

  EnvPathToLoad := '.env';
  if not FileExists(EnvPathToLoad) then
    EnvPathToLoad := ExtractFilePath(ParamStr(0)) + '.env';

  if not LoadConfig(EnvPathToLoad) then
  begin
    Writeln('ERROR: Could not load ', EnvPathToLoad);
    Halt(1);
  end;

  // ตรวจสอบและสร้างโครงสร้างตารางฐานข้อมูลที่จำเป็น
  EnsureDBSchema;

  RegisterRoute('GET', '/', @HandleRoot);
  RegisterRoute('GET', '/howto', @HandleHowTo);
  RegisterRoute('GET', '/images/logo_moph.png', @HandleImage);
  RegisterRoute('GET', '/images/login_illustration.png', @HandleImage);
  RegisterRoute('GET', '/images/thaid.png', @HandleImage);
  RegisterRoute('GET', '/images/providerid.png', @HandleImage);

  // ===== ตรวจสอบ License Key ก่อนเริ่ม Server =====
  LicPath := AppCfg.LicenseKeyPath;
  // ถ้าเป็น relative path ให้หาจากข้าง binary
  if not FileExists(LicPath) then
    LicPath := ExtractFilePath(ParamStr(0)) + AppCfg.LicenseKeyPath;

  LicInfo := ValidateLicense(LicPath);

  if LicInfo.Status <> lsValid then
  begin
    Writeln('');
    Writeln('============================================');
    Writeln('  fpsso LICENSE VALIDATION FAILED');
    Writeln('============================================');
    Writeln('  สถานะ: ', LicenseStatusText(LicInfo.Status));
    Writeln('');
    case LicInfo.Status of
      lsNotFound:
      begin
        Writeln('  ไม่พบไฟล์ License Key');
        Writeln('  กรุณาวาง license.key ไว้ข้าง fpsso binary');
        Writeln('');
        Writeln('  หากยังไม่มี License Key:');
        Writeln('    1. รัน: ./fpsso --hwid');
        Writeln('    2. ส่งค่า Machine ID ให้ผู้พัฒนา');
        Writeln('    3. รับไฟล์ license.key กลับมาวางไว้ข้าง fpsso');
      end;
      lsInvalidMachine:
      begin
        Writeln('  Machine ID ของเครื่องนี้: ', GetMachineID);
        Writeln('  Machine ID ใน License  : ', LicInfo.MachineID);
        Writeln('');
        Writeln('  License นี้ถูกผูกกับเครื่องอื่น กรุณาติดต่อผู้พัฒนาเพื่อขอ License ใหม่');
      end;
      lsExpired:
      begin
        Writeln('  Serial   : ', LicInfo.Serial);
        Writeln('  หมดอายุ  : ', LicInfo.ExpiryDate);
        Writeln('');
        Writeln('  กรุณาติดต่อผู้พัฒนาเพื่อต่ออายุ License');
      end;
      lsInvalidSignature:
      begin
        Writeln('  ไฟล์ License อาจถูกแก้ไขหรือเสียหาย');
        Writeln('  กรุณาติดต่อผู้พัฒนาเพื่อขอ License ใหม่');
      end;
    end;
    Writeln('');
    Writeln('  ระบบจะทำงานใน DEMO MODE (จำกัด 10 login ต่อวัน)');
    Writeln('============================================');
    
    // ทำงานต่อในโหมด Demo
    DemoModeActive := True;
    LicenseVerified := False;
  end
  else
  begin
    // แสดงข้อมูล License ที่ถูกต้อง
    DemoModeActive := False;
    LicenseVerified := True;
    GlobalLicenseInfo := LicInfo;
    Writeln('License: ', LicInfo.Serial, ' (', LicInfo.Licensee, ')');
    if LicInfo.ExpiryDate <> '' then
      Writeln('License Expiry: ', LicInfo.ExpiryDate)
    else
      Writeln('License Expiry: Lifetime (ไม่หมดอายุ)');
  end;

  // เริ่ม Background Thread ล้าง Session ที่หมดอายุแล้วทุก 10 นาที
  CleanupThread := TSessionCleanupThread.Create(True);
  CleanupThread.FreeOnTerminate := True;
  CleanupThread.Start;
  Writeln('Session cleanup thread started (interval: 10 min, max age: 30 min).');

  // แจ้งให้ License unit ทราบว่าไฟล์อยู่ที่ไหน เพื่อใช้ตรวจซ้ำใน watchdog และ quick check
  GlobalLicensePath := LicPath;

  // เริ่ม Watchdog Thread ตรวจสอบ License, Debugger, Binary Integrity ซ้ำทุก 5 นาที
  WatchdogThread := TLicenseWatchdogThread.Create(LicPath);
  WatchdogThread.Start;
  Writeln('License watchdog thread started (interval: 5 min).');

  try
    StartServer(AppCfg.AppPort);
  except
    on E: Exception do
      Writeln('Server error: ', E.Message);
  end;
end.
