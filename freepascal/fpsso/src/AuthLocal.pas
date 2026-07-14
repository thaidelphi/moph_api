unit AuthLocal;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, HTTPDefs, fpHTTP, Router, SessionMgr, RadiusDB;

procedure HandleLogin(Req: TRequest; Res: TResponse);

implementation

procedure HandleLogin(Req: TRequest; Res: TResponse);
var
  SessionID: string;
  Username, Pass: string;
  Data: TSessionData;
  PlainPass: string;
begin
  if Req.Method <> 'POST' then
  begin
    SendJSONError(Res, 405, 'Method Not Allowed');
    Exit;
  end;

  Username := Req.ContentFields.Values['username'];
  Pass := Req.ContentFields.Values['password'];

  if (Username = '') then
  begin
    SendJSONError(Res, 400, 'Username required');
    Exit;
  end;

  // Verify username/pass in radius? Or assume it's external.
  // For local login, we will just pass it to Radius DB to create/get a tmp_passwd
  PlainPass := SSORadiusAuth(Username, '', '');
  
  if PlainPass <> '' then
  begin
    SessionID := Req.CookieFields.Values['SSOSESSID'];
    if (SessionID = '') or not SessionManager.GetSession(SessionID, Data) then
    begin
      SessionID := SessionManager.CreateSession;
      SessionManager.GetSession(SessionID, Data);
    end;
    
    Data.Username := Username;
    Data.PlainPass := PlainPass;
    SessionManager.UpdateSession(SessionID, Data);
    
    // Set or refresh cookie
    with Res.Cookies.Add do
    begin
      Name := 'SSOSESSID';
      Value := SessionID;
      Path := '/';
      Expires := Now + 1;
      HttpOnly := True;
    end;
    
    // Redirect to FortiGate Handshake
    Redirect(Res, '/sso/fortigate/handshake');
  end
  else
  begin
    Redirect(Res, '/sso/?error=1');
  end;
end;

initialization
  RegisterRoute('POST', '/auth/login', @HandleLogin);

end.
