unit AuthThaiD;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, HTTPDefs, fpHTTP, fpjson, jsonparser, fphttpclient, opensslsockets, uriparser,
  Router, SessionMgr, RadiusDB, Config, base64, License;

procedure HandleThaiDLogin(Req: TRequest; Res: TResponse);
procedure HandleThaiDCallback(Req: TRequest; Res: TResponse);

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

{ ถอดรหัส JWT Payload (Base64url → JSON string) }
function DecodeJWTPayload(const JWTToken: string): string;
var
  Parts: TStringList;
  Payload: string;
  PadLen: Integer;
begin
  Result := '';
  Parts := TStringList.Create;
  try
    // แยก JWT ออกเป็น 3 ส่วนด้วย '.'
    Parts.Delimiter := '.';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := JWTToken;

    if Parts.Count < 2 then Exit;

    // ส่วนที่ 2 คือ Payload (index 1)
    Payload := Parts[1];

    // แปลง Base64url → Base64 ปกติ (แทน - ด้วย + และ _ ด้วย /)
    Payload := StringReplace(Payload, '-', '+', [rfReplaceAll]);
    Payload := StringReplace(Payload, '_', '/', [rfReplaceAll]);

    // เติม padding '=' ให้ครบ
    PadLen := (4 - (Length(Payload) mod 4)) mod 4;
    Payload := Payload + StringOfChar('=', PadLen);

    // Decode Base64
    Result := DecodeStringBase64(Payload);
  finally
    Parts.Free;
  end;
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

{ Handler: เริ่มกระบวนการ OAuth2 ของ ThaID }
procedure HandleThaiDLogin(Req: TRequest; Res: TResponse);
var
  State, AuthUrl, SessionID: string;
  Data: TSessionData;
begin
  if not HasFeature('thaid') then
  begin
    Res.Content := '{"error": "ThaID login is not enabled in your license"}';
    Res.Code := 403;
    Exit;
  end;

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

  // สร้าง Authorization URL ไปยัง ThaID
  AuthUrl := AppCfg.ThaIDAuthURL + '?response_type=code' +
             '&client_id=' + EncodeURLElement(AppCfg.ThaIDClientID) +
             '&redirect_uri=' + EncodeURLElement(AppCfg.ThaIDRedirectURI) +
             '&scope=' + EncodeURLElement(AppCfg.ThaIDScope) +
             '&state=' + State;

  Redirect(Res, AuthUrl);
end;

{ Handler: รับ Callback จาก ThaID หลังผู้ใช้ยืนยันตัวตนสำเร็จ }
procedure HandleThaiDCallback(Req: TRequest; Res: TResponse);
var
  Code, State, SessionID: string;
  Client: TFPHttpClient;
  PostData: TStringList;
  ResponseStr: string;
  JSON: TJSONObject;
  AccessToken: string;
  PlainPass, PID, FullName, Email: string;
  Data: TSessionData;
  AuthHeader: string;
  IsActive: Boolean;
  PayloadStr: string;
  PayloadJSON: TJSONObject;
begin
  if not HasFeature('thaid') then
  begin
    Res.Content := '{"error": "ThaID login is not enabled in your license"}';
    Res.Code := 403;
    Exit;
  end;

  Code := Req.QueryFields.Values['code'];
  State := Req.QueryFields.Values['state'];

  // ตรวจสอบว่ามี Authorization Code
  if Code = '' then
  begin
    Redirect(Res, '/sso/?error=thaid_no_code');
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

    // ตั้งค่า Basic Auth Header สำหรับ Token Request
    AuthHeader := 'Basic ' + EncodeStringBase64(AppCfg.ThaIDClientID + ':' + AppCfg.ThaIDSecret);
    Client.AddHeader('Authorization', AuthHeader);

    PostData.Add('grant_type=authorization_code');
    PostData.Add('code=' + Code);
    PostData.Add('redirect_uri=' + AppCfg.ThaIDRedirectURI);

    try
      // ขอ Access Token จาก ThaID Token Endpoint
      ResponseStr := Client.FormPost(AppCfg.ThaIDTokenURL, PostData);

      JSON := GetJSON(ResponseStr) as TJSONObject;
      try
        AccessToken := GetJSONStr(JSON, 'access_token');
      finally
        JSON.Free;
      end;

      if AccessToken = '' then
      begin
        Redirect(Res, '/sso/?error=thaid_token');
        Exit;
      end;

      // ถอดรหัส JWT Payload เพื่อดึงข้อมูลผู้ใช้ (ThaID ฝัง user info ใน access_token)
      PayloadStr := DecodeJWTPayload(AccessToken);
      PID := '';
      FullName := '';
      Email := '';

      if PayloadStr <> '' then
      begin
        try
          PayloadJSON := GetJSON(PayloadStr) as TJSONObject;
          try
            // ThaID ใส่ PID ใน field 'pid' หรือ 'sub'
            PID := GetJSONStr(PayloadJSON, 'pid');
            if PID = '' then
              PID := GetJSONStr(PayloadJSON, 'sub');

            // ดึงชื่อ-นามสกุล
            FullName := Trim(GetJSONStr(PayloadJSON, 'given_name') + ' ' + GetJSONStr(PayloadJSON, 'family_name'));
            if FullName = ' ' then
              FullName := GetJSONStr(PayloadJSON, 'name');

            Email := GetJSONStr(PayloadJSON, 'email');
          finally
            PayloadJSON.Free;
          end;
        except
          on E: Exception do
            Writeln('AuthThaiD: JWT Parse Error: ', E.Message);
        end;
      end;

      // ตรวจสอบว่าได้ PID จริง
      if PID = '' then
      begin
        Writeln('AuthThaiD: Cannot extract PID from token. Payload: ', PayloadStr);
        Redirect(Res, '/sso/?error=thaid_no_pid');
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
        // ตรวจสอบ Demo Limit
        if not SessionManager.CheckAndRegisterLogin then
        begin
          ShowDemoLimitError(Res);
          Exit;
        end;
        
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
        Writeln('AuthThaiD: Error: ', E.Message);
        Redirect(Res, '/sso/?error=' + EncodeURLElement(E.Message));
      end;
    end;
  finally
    Client.Free;
    PostData.Free;
  end;
end;

initialization
  RegisterRoute('GET', '/auth/thaid', @HandleThaiDLogin);
  RegisterRoute('GET', '/auth/thaid/callback', @HandleThaiDCallback);

end.
