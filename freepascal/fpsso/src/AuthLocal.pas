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
  IsActive: Boolean;
begin
  if Req.Method <> 'POST' then
  begin
    SendJSONError(Res, 405, 'Method Not Allowed');
    Exit;
  end;

  Username := Req.ContentFields.Values['username'];
  Pass := Req.ContentFields.Values['password'];

  if (Username = '') or (Pass = '') then
  begin
    SendJSONError(Res, 400, 'Username and password required');
    Exit;
  end;

  // Local login verifies existing username and password in radius
  PlainPass := LocalRadiusAuth(Username, Pass, IsActive);
  
  if not IsActive then
  begin
    Redirect(Res, '/sso/?error=pending');
    Exit;
  end;
  
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
