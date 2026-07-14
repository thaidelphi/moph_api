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
begin
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
