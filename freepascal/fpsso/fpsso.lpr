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
begin
  if FileExists(AppCfg.LoginTemplatePath) then
  begin
    with TStringList.Create do
    try
      LoadFromFile(AppCfg.LoginTemplatePath);
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
    SendJSONError(Res, 404, 'Login template not found at: ' + AppCfg.LoginTemplatePath);
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
