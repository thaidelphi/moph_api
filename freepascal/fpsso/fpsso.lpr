program fpsso;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, Process,
  Config, SessionMgr, Router, HttpServer, HTTPDefs,
  AuthLocal, AuthThaiD, AuthProviderID, AuthGoogle, FortiGate, AdminUsers;

procedure HandleRoot(Req: TRequest; Res: TResponse);
var
  HtmlContent: string;
  TemplatePath: string;
  MagicToken, SessionID: string;
  Data: TSessionData;
begin
  // Handle FortiGate 'magic' token
  MagicToken := Req.QueryFields.Values['magic'];
  if MagicToken <> '' then
  begin
    SessionID := Req.CookieFields.Values['SSOSESSID'];
    if (SessionID = '') or not SessionManager.GetSession(SessionID, Data) then
    begin
      SessionID := SessionManager.CreateSession;
      SessionManager.GetSession(SessionID, Data);
    end;
    
    Data.Magic := MagicToken;
    SessionManager.UpdateSession(SessionID, Data);
    
    with Res.Cookies.Add do
    begin
      Name := 'SSOSESSID';
      Value := SessionID;
      Path := '/';
      Expires := Now + 1; // 1 day
      HttpOnly := True;
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
    Res.Code := 200;
    Res.ContentType := 'text/html; charset=utf-8';
    Res.Content := HtmlContent;
    Res.SendContent;
  end
  else
    SendJSONError(Res, 404, 'Login template not found at: ' + TemplatePath);
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
  Halt(0);
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
  Halt(0);
end;

begin
  Writeln('Initializing fp-sso...');
  
  if (ParamCount > 0) and (ParamStr(1) = '--installservice') then
  begin
    InstallService;
  end;

  if (ParamCount > 0) and (ParamStr(1) = '--uninstallservice') then
  begin
    UninstallService;
  end;
  
  if not LoadConfig('/var/www/api/.env') then
  begin
    Writeln('ERROR: Could not load /var/www/api/.env');
    Halt(1);
  end;

  RegisterRoute('GET', '/', @HandleRoot);
  RegisterRoute('GET', '/howto', @HandleHowTo);
  
  try
    StartServer(8080);
  except
    on E: Exception do
      Writeln('Server error: ', E.Message);
  end;
end.
