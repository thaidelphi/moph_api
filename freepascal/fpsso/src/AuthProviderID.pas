unit AuthProviderID;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, HTTPDefs, fpHTTP, fpjson, jsonparser, fphttpclient, opensslsockets, uriparser,
  Router, SessionMgr, RadiusDB, Config, base64;

procedure HandleProviderIDLogin(Req: TRequest; Res: TResponse);
procedure HandleProviderIDCallback(Req: TRequest; Res: TResponse);

implementation

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

{ Handler: เริ่มกระบวนการ OAuth2 ของ MOPH Provider ID }
procedure HandleProviderIDLogin(Req: TRequest; Res: TResponse);
var
  State, AuthUrl, SessionID: string;
  Data: TSessionData;
begin
  // สร้าง State Token และบันทึกลง Session เพื่อตรวจสอบ CSRF ในขั้นตอน Callback
  State := GenerateStateToken;
  SessionID := Req.CookieFields.Values['SSOSESSID'];
  if (SessionID = '') or not SessionManager.GetSession(SessionID, Data) then
  begin
    SessionID := SessionManager.CreateSession;
    SessionManager.GetSession(SessionID, Data);
  end;

  // เก็บ State ไว้ใน Session เพื่อ verify ใน Callback
  Data.OAuthState := State;
  SessionManager.UpdateSession(SessionID, Data);

  // ตั้งค่า Cookie Session
  with Res.Cookies.Add do
  begin
    Name := 'SSOSESSID';
    Value := SessionID;
    Path := '/';
    Expires := Now + 1;
    HttpOnly := True;
  end;

  // สร้าง Authorization URL ไปยัง Provider ID
  AuthUrl := AppCfg.ProviderIDURL + '/login?response_type=code' +
             '&client_id=' + EncodeURLElement(AppCfg.ProviderIDClientID) +
             '&redirect_uri=' + EncodeURLElement(AppCfg.ProviderIDRedirectURI) +
             '&state=' + State;

  Redirect(Res, AuthUrl);
end;

{ Handler: รับ Callback จาก Provider ID หลังผู้ใช้ยืนยันตัวตนสำเร็จ }
procedure HandleProviderIDCallback(Req: TRequest; Res: TResponse);
var
  Code, State, SessionID: string;
  Client: TFPHttpClient;
  PostData: TStringList;
  ResponseStr: string;
  IsActive: Boolean;
  JSON: TJSONObject;
  AccessToken, PID, FullName, Email, PlainPass: string;
  Data: TSessionData;
begin
  Code := Req.QueryFields.Values['code'];
  State := Req.QueryFields.Values['state'];

  // ตรวจสอบว่ามี Authorization Code
  if Code = '' then
  begin
    Redirect(Res, '/sso/?error=providerid_no_code');
    Exit;
  end;

  // ตรวจสอบ State Token เพื่อป้องกัน CSRF Attack
  SessionID := Req.CookieFields.Values['SSOSESSID'];
  if SessionID = '' then
  begin
    Redirect(Res, '/sso/?error=session');
    Exit;
  end;

  if not SessionManager.GetSession(SessionID, Data) then
  begin
    Redirect(Res, '/sso/?error=session');
    Exit;
  end;

  // เปรียบเทียบ State ที่ได้รับกับ State ที่บันทึกไว้ใน Session
  if (State = '') or (State <> Data.OAuthState) then
  begin
    Redirect(Res, '/sso/?error=csrf');
    Exit;
  end;

  // ล้าง OAuthState หลังจากตรวจสอบแล้ว (ใช้ได้ครั้งเดียว)
  Data.OAuthState := '';
  SessionManager.UpdateSession(SessionID, Data);

  Client := TFPHttpClient.Create(nil);
  PostData := TStringList.Create;
  try
    Client.AllowRedirect := True;

    // ขั้นตอนที่ 1: แลก Authorization Code เป็น Access Token
    PostData.Add('grant_type=authorization_code');
    PostData.Add('code=' + Code);
    PostData.Add('client_id=' + AppCfg.ProviderIDClientID);
    PostData.Add('client_secret=' + AppCfg.ProviderIDSecret);
    PostData.Add('redirect_uri=' + AppCfg.ProviderIDRedirectURI);

    try
      ResponseStr := Client.FormPost(AppCfg.ProviderIDURL + '/token', PostData);

      JSON := GetJSON(ResponseStr) as TJSONObject;
      try
        AccessToken := GetJSONStr(JSON, 'access_token');
      finally
        JSON.Free;
      end;

      if AccessToken = '' then
      begin
        Writeln('AuthProviderID: Token exchange failed. Response: ', ResponseStr);
        Redirect(Res, '/sso/?error=providerid_token');
        Exit;
      end;

      // ขั้นตอนที่ 2: ดึงข้อมูลผู้ใช้จาก UserInfo Endpoint
      Client.RequestHeaders.Clear;
      Client.AddHeader('Authorization', 'Bearer ' + AccessToken);

      PID := '';
      FullName := '';
      Email := '';

      try
        ResponseStr := Client.Get(AppCfg.ProviderIDURL + '/userinfo');

        JSON := GetJSON(ResponseStr) as TJSONObject;
        try
          // ดึง PID (Provider ID ใช้ field 'pid' หรือ 'sub')
          PID := GetJSONStr(JSON, 'pid');
          if PID = '' then
            PID := GetJSONStr(JSON, 'sub');

          // ดึงชื่อ-นามสกุล
          FullName := Trim(GetJSONStr(JSON, 'given_name') + ' ' + GetJSONStr(JSON, 'family_name'));
          if FullName = ' ' then
            FullName := GetJSONStr(JSON, 'name');

          Email := GetJSONStr(JSON, 'email');
        finally
          JSON.Free;
        end;
      except
        on E: Exception do
          Writeln('AuthProviderID: UserInfo fetch error: ', E.Message);
      end;

      // ตรวจสอบว่าได้ PID จริง
      if PID = '' then
      begin
        Writeln('AuthProviderID: Cannot extract PID from userinfo. Response: ', ResponseStr);
        Redirect(Res, '/sso/?error=providerid_no_pid');
        Exit;
      end;

      // บันทึกหรืออัปเดตข้อมูลผู้ใช้ใน radcheck_mirror และขอ tmp_passwd
      PlainPass := SSORadiusAuth(PID, IsActive, Email, FullName);

      if not IsActive then
      begin
        Redirect(Res, '/sso/?error=pending');
        Exit;
      end;

      if PlainPass <> '' then
      begin
        // อัปเดต Session ด้วยข้อมูลผู้ใช้และ Credential
        Data.Username := PID;
        Data.FullName := FullName;
        Data.PlainPass := PlainPass;
        SessionManager.UpdateSession(SessionID, Data);

        Redirect(Res, '/sso/fortigate/handshake');
      end
      else
        Redirect(Res, '/sso/?error=db');

    except
      on E: Exception do
      begin
        Writeln('AuthProviderID: Error: ', E.Message);
        Redirect(Res, '/sso/?error=' + EncodeURLElement(E.Message));
      end;
    end;
  finally
    Client.Free;
    PostData.Free;
  end;
end;

initialization
  RegisterRoute('GET', '/auth/providerid', @HandleProviderIDLogin);
  RegisterRoute('GET', '/auth/providerid/callback', @HandleProviderIDCallback);

end.
