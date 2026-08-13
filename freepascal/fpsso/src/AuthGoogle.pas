unit AuthGoogle;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, HTTPDefs, fpHTTP, jsonparser, fpjson,
  opensslsockets, fphttpclient, uriparser, Router, Config, SessionMgr, 
  RadiusDB, License;

procedure HandleGoogleLogin(Req: TRequest; Res: TResponse);
procedure HandleGoogleCallback(Req: TRequest; Res: TResponse);

implementation

// -----------------------------------------------------------------------------
// Helper functions
// -----------------------------------------------------------------------------
{ สร้าง State Token แบบ Random GUID สำหรับป้องกัน CSRF }
function GenerateStateToken: string;
var
  Guid: TGuid;
begin
  CreateGUID(Guid);
  Result := StringReplace(GUIDToString(Guid), '{', '', [rfReplaceAll]);
  Result := StringReplace(Result, '}', '', [rfReplaceAll]);
  Result := StringReplace(Result, '-', '', [rfReplaceAll]);
end;

{ ดึงค่า field แบบ string จาก JSON Object (ป้องกัน exception) }
function GetJSONStr(JObj: TJSONObject; const Key: string): string;
var
  Node: TJSONData;
begin
  Result := '';
  try
    Node := JObj.Find(Key);
    if Assigned(Node) then
      Result := Node.AsString;
  except
    Result := '';
  end;
end;

// -----------------------------------------------------------------------------
// Step 1: Redirect to Google
// -----------------------------------------------------------------------------
procedure HandleGoogleLogin(Req: TRequest; Res: TResponse);
var
  SessionID: string;
  StateStr: string;
  AuthURL: string;
  Data: TSessionData;
begin
  if not HasFeature('google') then
  begin
    Redirect(Res, '/sso/?error=' + EncodeURLElement('Google Auth is disabled by license.'));
    Exit;
  end;

  StateStr := GenerateStateToken;
  SessionID := Req.CookieFields.Values['SSOSESSID'];
  if (SessionID = '') or not SessionManager.GetSession(SessionID, Data) then
  begin
    SessionID := SessionManager.CreateSession;
    SessionManager.GetSession(SessionID, Data);
  end;
  
  // เก็บ State ไว้ใน Session เพื่อ verify ใน Callback
  Data.OAuthState := StateStr;
  SessionManager.UpdateSession(SessionID, Data);

  // ตั้งค่า Cookie Session
  with Res.Cookies.Add do
  begin
    Name := 'SSOSESSID';
    Value := SessionID;
    Path := '/';
    HttpOnly := True;
  end;
  
  // ตรวจสอบ Demo Limit
  if not SessionManager.CheckAndRegisterLogin then
  begin
    ShowDemoLimitError(Res);
    Exit;
  end;

  // Build Google OAuth URL
  AuthURL := AppCfg.GoogleAuthURL +
    '?client_id=' + EncodeURLElement(AppCfg.GoogleClientID) +
    '&redirect_uri=' + EncodeURLElement(AppCfg.GoogleRedirectURI) +
    '&response_type=code' +
    '&scope=' + EncodeURLElement('email profile') +
    '&state=' + StateStr;

  Redirect(Res, AuthURL);
end;

// -----------------------------------------------------------------------------
// Step 2: Handle Google Callback
// -----------------------------------------------------------------------------
procedure HandleGoogleCallback(Req: TRequest; Res: TResponse);
var
  AuthCode, ReturnedState, SessionID, AccessToken: string;
  Data: TSessionData;
  Client: TFPHTTPClient;
  PostData: TStringList;
  ResponseStr: string;
  JSON: TJSONObject;
  GoogleID, Email, FullName: string;
  PlainPass: string;
  IsActive: Boolean;
begin
  AuthCode := Req.QueryFields.Values['code'];
  ReturnedState := Req.QueryFields.Values['state'];
  
  SessionID := Req.CookieFields.Values['SSOSESSID'];
  if (SessionID = '') or not SessionManager.GetSession(SessionID, Data) then
  begin
    Redirect(Res, '/sso/?error=session_expired');
    Exit;
  end;

  if Req.QueryFields.Values['error'] <> '' then
  begin
    Redirect(Res, '/sso/?error=' + EncodeURLElement(Req.QueryFields.Values['error']));
    Exit;
  end;

  if (AuthCode = '') or (ReturnedState = '') then
  begin
    Redirect(Res, '/sso/?error=invalid_callback');
    Exit;
  end;

  if ReturnedState <> Data.OAuthState then
  begin
    Redirect(Res, '/sso/?error=invalid_state');
    Exit;
  end;

  // เคลียร์ State ป้องกัน Replay Attack
  Data.OAuthState := '';
  SessionManager.UpdateSession(SessionID, Data);

  Client := TFPHTTPClient.Create(nil);
  PostData := TStringList.Create;
  try
    Client.AllowRedirect := True;
    
    PostData.Add('grant_type=authorization_code');
    PostData.Add('code=' + AuthCode);
    PostData.Add('client_id=' + AppCfg.GoogleClientID);
    PostData.Add('client_secret=' + AppCfg.GoogleClientSecret);
    PostData.Add('redirect_uri=' + AppCfg.GoogleRedirectURI);

    try
      ResponseStr := Client.FormPost(AppCfg.GoogleTokenURL, PostData);

      JSON := GetJSON(ResponseStr) as TJSONObject;
      try
        AccessToken := GetJSONStr(JSON, 'access_token');
      finally
        JSON.Free;
      end;

      if AccessToken = '' then
      begin
        Writeln('AuthGoogle: Token exchange failed. Response: ', ResponseStr);
        Redirect(Res, '/sso/?error=google_token');
        Exit;
      end;

      // ขั้นตอนที่ 2: ดึงข้อมูลผู้ใช้จาก UserInfo Endpoint
      Client.RequestHeaders.Clear;
      Client.AddHeader('Authorization', 'Bearer ' + AccessToken);

      GoogleID := '';
      FullName := '';
      Email := '';

      try
        ResponseStr := Client.Get(AppCfg.GoogleUserInfoURL);

        JSON := GetJSON(ResponseStr) as TJSONObject;
        try
          // ดึง Google ID (sub)
          GoogleID := GetJSONStr(JSON, 'sub');
          FullName := GetJSONStr(JSON, 'name');
          Email := GetJSONStr(JSON, 'email');
        finally
          JSON.Free;
        end;
      except
        on E: Exception do
          Writeln('AuthGoogle: UserInfo fetch error: ', E.Message);
      end;

      // ตรวจสอบว่าได้ GoogleID จริง
      if GoogleID = '' then
      begin
        Writeln('AuthGoogle: Cannot extract Google ID from userinfo. Response: ', ResponseStr);
        Redirect(Res, '/sso/?error=google_no_id');
        Exit;
      end;

      // บันทึกหรืออัปเดตข้อมูลผู้ใช้ใน radcheck_mirror และขอ tmp_passwd
      IsActive := False;
      PlainPass := SSORadiusAuth(GoogleID, IsActive, Email, FullName);

      if not IsActive then
      begin
        Redirect(Res, '/sso/?error=pending');
        Exit;
      end;

      if PlainPass <> '' then
      begin
        // ตรวจสอบ Demo Limit (อีกครั้งเพื่อความชัวร์)
        if not SessionManager.CheckAndRegisterLogin then
        begin
          ShowDemoLimitError(Res);
          Exit;
        end;
        
        // อัปเดต Session ด้วยข้อมูลผู้ใช้และ Credential
        Data.Username := GoogleID;
        Data.FullName := FullName;
        Data.PlainPass := PlainPass;
        SessionManager.UpdateSession(SessionID, Data);

        // บันทึก Log การล็อกอิน
        LogAuthEvent(GoogleID, 'LOGIN', GetClientIP(Req));

        Redirect(Res, '/sso/fortigate/handshake');
      end
      else
        Redirect(Res, '/sso/?error=db');

    except
      on E: Exception do
      begin
        Writeln('AuthGoogle: Error: ', E.Message);
        Redirect(Res, '/sso/?error=' + EncodeURLElement(E.Message));
      end;
    end;
  finally
    Client.Free;
    PostData.Free;
  end;
end;

initialization
  RegisterRoute('GET', '/auth/google', @HandleGoogleLogin);
  RegisterRoute('GET', '/auth/google/callback', @HandleGoogleCallback);
  RegisterRoute('GET', '/google_api.php', @HandleGoogleCallback);

end.
