unit AuthLocal;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, HTTPDefs, fpHTTP, Router, SessionMgr, RadiusDB, License;

procedure HandleLogin(Req: TRequest; Res: TResponse);

implementation

procedure HandleLogin(Req: TRequest; Res: TResponse);
var
  SessionID: string;
  Username, Pass: string;
  Data: TSessionData;
  PlainPass, DummyEmail, DummyPhone: string;
  IsActive: Boolean;
begin
  if Req.Method <> 'POST' then
  begin
    SendJSONError(Res, 405, 'Method Not Allowed');
    Exit;
  end;
  
  if not HasFeature('local') then
  begin
    SendJSONError(Res, 403, 'Username/Password login is not enabled in your license');
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
    // ตรวจสอบ Demo Limit
    if not SessionManager.CheckAndRegisterLogin then
    begin
      ShowDemoLimitError(Res);
      Exit;
    end;
    
    SessionID := Req.CookieFields.Values['SSOSESSID'];
    if (SessionID = '') or not SessionManager.GetSession(SessionID, Data) then
    begin
      SessionID := SessionManager.CreateSession;
      SessionManager.GetSession(SessionID, Data);
    end;
    
    Data.Username := Username;
    Data.PlainPass := PlainPass;
    Data.AuthMethod := 'LOCAL';
    
    // ดึงชื่อ-นามสกุลจากฐานข้อมูล
    GetUserProfile(Username, Data.FullName, DummyEmail, DummyPhone);
    
    // ดึงค่า magic, post, redir ที่ส่งมาจาก Form เพิ่มเติม (ป้องกันกรณี Session หลุดหรือ Restart ระบบ)
    if Req.ContentFields.Values['magic'] <> '' then
      Data.Magic := Req.ContentFields.Values['magic']
    else if Req.QueryFields.Values['magic'] <> '' then
      Data.Magic := Req.QueryFields.Values['magic'];

    if Req.ContentFields.Values['post'] <> '' then
      Data.PostUrl := Req.ContentFields.Values['post']
    else if Req.QueryFields.Values['post'] <> '' then
      Data.PostUrl := Req.QueryFields.Values['post'];

    if Req.ContentFields.Values['redir'] <> '' then
      Data.RedirUrl := Req.ContentFields.Values['redir']
    else if Req.QueryFields.Values['redir'] <> '' then
      Data.RedirUrl := Req.QueryFields.Values['redir'];
      
    SessionManager.UpdateSession(SessionID, Data);
    
    // บันทึก Log การล็อกอิน
    LogAuthEvent(Username, 'LOGIN', GetClientIP(Req), 'LOCAL', Data.FullName, Data.UserMac, Copy(Req.UserAgent, 1, 255));
    
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
