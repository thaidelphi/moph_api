unit FortiGate;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, HTTPDefs, fpHTTP, Router, SessionMgr, Config, fphttpclient, fpjson, jsonparser;

procedure HandleFortiGateHandshake(Req: TRequest; Res: TResponse);

implementation

{ ฟังก์ชัน HTML Encode ป้องกัน XSS จากค่าที่ฝังใน HTML Attribute }
function HtmlEncode(const S: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    case C of
      '&': Result := Result + '&amp;';
      '<': Result := Result + '&lt;';
      '>': Result := Result + '&gt;';
      '"': Result := Result + '&quot;';
      '''': Result := Result + '&#39;';
    else
      Result := Result + C;
    end;
  end;
end;

{ Handler: หน้า Handshake ที่ Auto-submit ข้อมูลกลับไปยัง FortiGate }
procedure HandleFortiGateHandshake(Req: TRequest; Res: TResponse);
var
  SessionID: string;
  Data: TSessionData;
  HtmlContent, TargetUrl: string;
begin
  SessionID := Req.CookieFields.Values['SSOSESSID'];

  if (SessionID = '') or not SessionManager.GetSession(SessionID, Data) then
  begin
    Redirect(Res, '/sso/?error=session');
    Exit;
  end;

  // ตรวจสอบว่ามีข้อมูลที่จำเป็นครบถ้วน
  if (Data.Username = '') or (Data.PlainPass = '') then
  begin
    Redirect(Res, '/sso/?error=session');
    Exit;
  end;

  // 3. เตรียม URL ของ FortiGate (ดึงแบบ Dynamic ถ้ามี, ถ้าไม่มีใช้ค่าจาก .env)
  TargetUrl := Data.PostUrl;
  if TargetUrl = '' then
    TargetUrl := AppCfg.FortiGateAuthURL;

  // HTML Encode ค่าทั้งหมดที่จะฝังใน HTML เพื่อป้องกัน XSS
  HtmlContent := '<!DOCTYPE html><html lang="th"><head><meta charset="utf-8">' + LineEnding +
    '    <link href="https://fonts.googleapis.com/css2?family=Sarabun:wght@300;400;500;600&display=swap" rel="stylesheet">' + LineEnding +
    '    <title>กำลังเชื่อมต่อระบบเครือข่าย...</title>' + LineEnding +
    '    <style>' + LineEnding +
    '        body { font-family: "Sarabun", sans-serif; background-color: #f4f7f6; margin: 0; display: flex; justify-content: center; align-items: center; height: 100vh; }' + LineEnding +
    '        .loading-box { text-align: center; background: white; padding: 40px; border-radius: 12px; box-shadow: 0 4px 15px rgba(0, 0, 0, 0.05); max-width: 400px; width: 100%; }' + LineEnding +
    '        .loading-box img { width: 80px; margin-bottom: 20px; }' + LineEnding +
    '        .spinner { border: 4px solid rgba(0, 0, 0, 0.1); width: 50px; height: 50px; border-radius: 50%; border-left-color: #007bff; animation: spin 1s linear infinite; margin: 0 auto 20px auto; }' + LineEnding +
    '        @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }' + LineEnding +
    '        h2 { color: #333; margin-bottom: 10px; font-size: 18px; }' + LineEnding +
    '        p { color: #666; font-size: 14px; }' + LineEnding +
    '    </style>' + LineEnding +
    '</head><body>' + LineEnding +
    '    <div class="loading-box">' + LineEnding +
    '        <img src="/images/logo_moph.png" alt="Logo">' + LineEnding +
    '        <div class="spinner"></div>' + LineEnding +
    '        <h2>กำลังอนุญาตสิทธิ์เข้าใช้งานอินเทอร์เน็ต</h2>' + LineEnding +
    '        <p>กรุณารอสักครู่ ระบบกำลังลงทะเบียนอุปกรณ์ของท่านกับทาง FortiGate...</p>' + LineEnding +
    '    </div>' + LineEnding +
    '    <form id="fortigate_form" action="' + HtmlEncode(TargetUrl) + '" method="post" style="display: none;">' + LineEnding +
    '        <input type="hidden" name="username" value="' + HtmlEncode(Data.Username) + '">' + LineEnding +
    '        <input type="hidden" name="password" value="' + HtmlEncode(Data.PlainPass) + '">' + LineEnding +
    '        <input type="hidden" name="magic" value="' + HtmlEncode(Data.Magic) + '">' + LineEnding +
    '        <input type="hidden" name="4Tredir" value="' + HtmlEncode(Data.PostUrl) + '">' + LineEnding +
    '    </form>' + LineEnding +
    '    <script>' + LineEnding +
    '        window.addEventListener("load", function() {' + LineEnding +
    '            setTimeout(function() { ' + LineEnding +
    '                document.getElementById("fortigate_form").submit(); ' + LineEnding +
    '            }, 500);' + LineEnding +
    '        });' + LineEnding +
    '    </script>' + LineEnding +
    '</body>' + LineEnding +
    '</html>';

  // ล้าง PlainPass ออกจาก Session ทันทีหลังจากฝังใน Form แล้ว เพื่อความปลอดภัย
  Data.PlainPass := '';
  SessionManager.UpdateSession(SessionID, Data);

  Res.Code := 200;
  Res.ContentType := 'text/html; charset=utf-8';
  Res.Content := HtmlContent;
  Res.SendContent;
end;

{ Handler: Logout — ลบ Session และเตะผ่าน FortiGate REST API (ถ้ามี Token) }
procedure HandleFortiGateLogout(Req: TRequest; Res: TResponse);
var
  SessionID: string;
  Data: TSessionData;
  LogoutUrl: string;
  ClientIP: string;
  Client: TFPHTTPClient;
  ResponseStr: string;
  DeauthUrl: string;
  JsonData, ResultsArr, UserObj, JsonBody, JsonPayload: TJSONData;
  ReqBody: TJSONObject;
  UsersArray: TJSONArray;
  UserItem: TJSONObject;
  I: Integer;
  FoundId: Integer;
  FoundSrcType, FoundMethod: string;
  HtmlContent: TStringList;
begin
  SessionID := Req.CookieFields.Values['SSOSESSID'];
  Data.PostUrl := '';
  if SessionID <> '' then
  begin
    SessionManager.GetSession(SessionID, Data);
    SessionManager.DeleteSession(SessionID);
    with Res.Cookies.Add do
    begin
      Name := 'SSOSESSID';
      Value := '';
      Path := '/';
      Expires := Now - 1; // หมดอายุ Cookie ทันที
    end;
  end;

  // หากมีการตั้งค่า FortiGate API ให้ยิง API เพื่อสั่งเตะ IP
  if (AppCfg.FortiGateApiToken <> '') and (AppCfg.FortiGateApiUrl <> '') then
  begin
    ClientIP := Req.RemoteAddress;
    
    Client := TFPHTTPClient.Create(nil);
    try
      Client.AddHeader('Authorization', 'Bearer ' + AppCfg.FortiGateApiToken);
      Client.AddHeader('Content-Type', 'application/json');
      
      try
        // 1. ดึงข้อมูล User จาก FortiGate
        ResponseStr := Client.Get(AppCfg.FortiGateApiUrl);
        JsonData := GetJSON(ResponseStr);
        if Assigned(JsonData) then
        begin
          try
            ResultsArr := JsonData.FindPath('results');
            if Assigned(ResultsArr) and (ResultsArr.JSONType = jtArray) then
            begin
              FoundId := -1;
              for I := 0 to ResultsArr.Count - 1 do
              begin
                UserObj := ResultsArr.Items[I];
                if Assigned(UserObj) and (UserObj.JSONType = jtObject) then
                begin
                  if UserObj.FindPath('ipaddr') <> nil then
                  begin
                    if UserObj.FindPath('ipaddr').AsString = ClientIP then
                    begin
                      FoundId := UserObj.FindPath('id').AsInteger;
                      FoundSrcType := UserObj.FindPath('src_type').AsString;
                      FoundMethod := LowerCase(UserObj.FindPath('method').AsString);
                      Break;
                    end;
                  end;
                end;
              end;
              
              // 2. ถ้าเจอ IP ให้ส่งคำสั่ง Deauthenticate
              if FoundId >= 0 then
              begin
                ReqBody := TJSONObject.Create;
                try
                  UsersArray := TJSONArray.Create;
                  UserItem := TJSONObject.Create;
                  UserItem.Add('user_type', 'firewall');
                  UserItem.Add('id', FoundId);
                  UserItem.Add('ip', ClientIP);
                  UserItem.Add('ip_version', FoundSrcType);
                  UserItem.Add('method', FoundMethod);
                  UsersArray.Add(UserItem);
                  ReqBody.Add('users', UsersArray);
                  
                  // สร้าง URL สำหรับ deauth
                  DeauthUrl := StringReplace(AppCfg.FortiGateApiUrl, '/select', '/deauth', [rfIgnoreCase]);
                  
                  Client.RequestBody := TRawByteStringStream.Create(ReqBody.AsJSON);
                  Client.Post(DeauthUrl);
                finally
                  ReqBody.Free;
                end;
              end;
            end;
          finally
            JsonData.Free;
          end;
        end;
      except
        // ข้ามไปหากเกิดข้อผิดพลาดในการเรียก API
      end;
    finally
      if Assigned(Client.RequestBody) then
        Client.RequestBody.Free;
      Client.Free;
    end;
    
    // โหลดหน้าจอ Logout.html
    HtmlContent := TStringList.Create;
    try
      if FileExists('templates/logout.html') then
        HtmlContent.LoadFromFile('templates/logout.html', TEncoding.UTF8)
      else
        HtmlContent.Text := 'Logged out successfully.';
        
      Res.Code := 200;
      Res.ContentType := 'text/html; charset=utf-8';
      Res.Content := HtmlContent.Text;
      Res.SendContent;
    finally
      HtmlContent.Free;
    end;
  end
  else
  begin
    // ถ้าไม่ได้ตั้งค่า API ไว้ ให้ใช้วิธี Redirect กลับไปที่ FortiGate
    if Data.PostUrl <> '' then
      LogoutUrl := StringReplace(Data.PostUrl, 'fgtauth', 'logout?', [rfIgnoreCase])
    else
      LogoutUrl := AppCfg.FortiGateLogoutURL;
      
    Redirect(Res, LogoutUrl);
  end;
end;

{ Handler: หน้าสถานะการเชื่อมต่อ (Popup Window สำหรับ Logout) }
procedure HandleStatusPage(Req: TRequest; Res: TResponse);
var
  HtmlContent: string;
begin
  HtmlContent := '<!DOCTYPE html><html lang="th"><head><meta charset="utf-8">' + LineEnding +
    '    <link href="https://fonts.googleapis.com/css2?family=Sarabun:wght@300;400;500;600&display=swap" rel="stylesheet">' + LineEnding +
    '    <title>สถานะการเชื่อมต่อ</title>' + LineEnding +
    '    <style>' + LineEnding +
    '        body { font-family: "Sarabun", sans-serif; background-color: #f4f7f6; margin: 0; padding: 20px; text-align: center; }' + LineEnding +
    '        .box { background: white; padding: 30px; border-radius: 12px; box-shadow: 0 4px 15px rgba(0,0,0,0.1); margin: 0 auto; max-width: 300px; }' + LineEnding +
    '        .success-icon { color: #28a745; font-size: 40px; margin-bottom: 10px; }' + LineEnding +
    '        h2 { color: #333; font-size: 20px; margin: 10px 0; }' + LineEnding +
    '        p { color: #666; font-size: 14px; margin-bottom: 25px; }' + LineEnding +
    '        .btn-logout { background-color: #dc3545; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px; font-weight: bold; display: inline-block; transition: 0.3s; border: none; cursor: pointer; width: 100%; }' + LineEnding +
    '        .btn-logout:hover { background-color: #c82333; }' + LineEnding +
    '    </style>' + LineEnding +
    '</head><body>' + LineEnding +
    '    <div class="box">' + LineEnding +
    '        <div class="success-icon">✔️</div>' + LineEnding +
    '        <h2>เชื่อมต่อสำเร็จ</h2>' + LineEnding +
    '        <p>คุณสามารถใช้งานอินเทอร์เน็ตได้แล้ว<br><small>(อย่าปิดหน้าต่างนี้หากต้องการ Logout)</small></p>' + LineEnding +
    '        <a href="/sso/auth/logout" class="btn-logout">Logout ออกจากระบบ</a>' + LineEnding +
    '    </div>' + LineEnding +
    '</body></html>';

  Res.Code := 200;
  Res.ContentType := 'text/html; charset=utf-8';
  Res.Content := HtmlContent;
  Res.SendContent;
end;

initialization
  RegisterRoute('GET', '/fortigate/handshake', @HandleFortiGateHandshake);
  RegisterRoute('GET', '/auth/logout', @HandleFortiGateLogout);
  RegisterRoute('GET', '/status', @HandleStatusPage);

end.
