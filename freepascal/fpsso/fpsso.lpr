program fpsso;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils,
  Config, SessionMgr, Router, HttpServer, HTTPDefs,
  AuthLocal, AuthThaiD, AuthProviderID, AuthGoogle, FortiGate;

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

begin
  Writeln('Initializing fp-sso...');
  
  if not LoadConfig('/var/www/api/.env') then
  begin
    Writeln('ERROR: Could not load /var/www/api/.env');
    Halt(1);
  end;

  RegisterRoute('GET', '/', @HandleRoot);
  
  try
    StartServer(8080);
  except
    on E: Exception do
      Writeln('Server error: ', E.Message);
  end;
end.
