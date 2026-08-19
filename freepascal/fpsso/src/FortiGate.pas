unit FortiGate;

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, SysUtils, HTTPDefs, fpHTTP, Router, SessionMgr, Config, fphttpclient, fpjson, jsonparser, RadiusDB;

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

// ฟังก์ชันช่วยปรับแต่ง URL ของ FortiGate ให้ถูกต้องตามโปรโตคอลและพอร์ต
function SanitizeFortiGateUrl(const AUrl: string): string;
var
  Url: string;
begin
  Url := Trim(AUrl);
  if Url = '' then
    Url := Trim(AppCfg.FortiGateAuthURL);
  if Url = '' then
    Url := 'https://192.168.200.1:1003/fgtauth';

  Result := Url;
end;

{ Handler: หน้า Handshake ที่ Auto-submit ข้อมูลกลับไปยัง FortiGate }
procedure HandleFortiGateHandshake(Req: TRequest; Res: TResponse);
var
  SessionID: string;
  Data: TSessionData;
  HtmlContent, TargetUrl, RedirUrl, Proto, HostHeader, BaseUrl: string;
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

  // กู้คืนค่า FortiGate Magic Token, PostUrl, UserMac จาก Cookie หากใน Session ว่างเปล่า
  if (Data.Magic = '') and (Req.CookieFields.Values['FGT_MAGIC'] <> '') then
    Data.Magic := Req.CookieFields.Values['FGT_MAGIC'];
  if (Data.PostUrl = '') and (Req.CookieFields.Values['FGT_POST'] <> '') then
    Data.PostUrl := Req.CookieFields.Values['FGT_POST'];
  if (Data.UserMac = '') and (Req.CookieFields.Values['FGT_MAC'] <> '') then
    Data.UserMac := Req.CookieFields.Values['FGT_MAC'];

  // 3. เตรียม URL ของ FortiGate (ดึงแบบ Dynamic ถ้ามี, ถ้าไม่มีใช้ค่าจาก .env)
  TargetUrl := SanitizeFortiGateUrl(Data.PostUrl);

  // หา Base URL ของระบบจาก .env (APP_URL) หรือตรวจจับแบบไดนามิกจาก Request Header
  BaseUrl := Trim(AppCfg.AppURL);
  if BaseUrl = '' then
  begin
    Proto := Req.GetCustomHeader('X-Forwarded-Proto');
    if Pos(',', Proto) > 0 then
      Proto := Trim(Copy(Proto, 1, Pos(',', Proto) - 1));

    if Proto = '' then
    begin
      if (Length(Req.URL) >= 5) and (LowerCase(Copy(Req.URL, 1, 5)) = 'https') then
        Proto := 'https'
      else
        Proto := 'http';
    end;

    HostHeader := Req.GetCustomHeader('X-Forwarded-Host');
    if Pos(',', HostHeader) > 0 then
      HostHeader := Trim(Copy(HostHeader, 1, Pos(',', HostHeader) - 1));

    if HostHeader = '' then
      HostHeader := Req.Host;

    if Pos(',', HostHeader) > 0 then
      HostHeader := Trim(Copy(HostHeader, 1, Pos(',', HostHeader) - 1));

    if HostHeader <> '' then
      BaseUrl := Proto + '://' + HostHeader
    else
      BaseUrl := '';
  end;

  // ตัดเครื่องหมาย slash ท้ายสุดออกหากมี
  if (Length(BaseUrl) > 0) and (BaseUrl[Length(BaseUrl)] = '/') then
    SetLength(BaseUrl, Length(BaseUrl) - 1);

  // 4. กำหนด URL ปลายทางหลังล็อกอินสำเร็จ (อ่านจาก .env เช่น POST_LOGIN_REDIRECT_URL ถ้าเป็นค่าว่างให้ไปที่ /sso/status เสมอ)
  RedirUrl := Trim(AppCfg.PostLoginRedirectURL);
  if RedirUrl = '' then
    RedirUrl := '/sso/status';

  // หากเป็น Relative path ให้แปลงเป็น Full Absolute URL เพื่อส่งให้ FortiGate (4Tredir)
  if (Pos('http://', LowerCase(RedirUrl)) <> 1) and (Pos('https://', LowerCase(RedirUrl)) <> 1) then
  begin
    if BaseUrl <> '' then
    begin
      if (Length(RedirUrl) > 0) and (RedirUrl[1] = '/') then
        RedirUrl := BaseUrl + RedirUrl
      else
        RedirUrl := BaseUrl + '/' + RedirUrl;
    end;
  end;

  // แนบ SessionID ไปใน RedirUrl เพื่อให้ FortiGate ส่งกลับมายังหน้า Status ได้อย่างแม่นยำ 100%
  if SessionID <> '' then
  begin
    if Pos('?', RedirUrl) > 0 then
      RedirUrl := RedirUrl + '&sid=' + SessionID
    else
      RedirUrl := RedirUrl + '?sid=' + SessionID;
  end;

  WriteLn('FortiGate Handshake for user: ', Data.Username, ' | TargetUrl: ', TargetUrl, ' | Magic: ', Data.Magic, ' | RedirUrl: ', RedirUrl);

  // หากไม่มี Magic Token จาก FortiGate (เกิดจากผู้ใช้พิมพ์ URL /sso/ เข้ามาตรงๆ โดยไม่ได้ผ่าน Captive Portal redirect)
  if Data.Magic = '' then
  begin
    // ล้าง PlainPass ออกจาก Session เพื่อความปลอดภัย
    Data.PlainPass := '';
    SessionManager.UpdateSession(SessionID, Data);
    
    // พาผู้ใช้ไปยังหน้าปลายทางโดยตรง ไม่ส่งไป FortiGate /fgtauth เพราะจะทำให้เกิด ERR_EMPTY_RESPONSE เมื่อไม่มี Magic
    Redirect(Res, RedirUrl);
    Exit;
  end;

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
    '        <input type="hidden" name="4Tredir" value="' + HtmlEncode(RedirUrl) + '">' + LineEnding +
    '        <input type="hidden" name="redir" value="' + HtmlEncode(RedirUrl) + '">' + LineEnding +
    '    </form>' + LineEnding +
    '    <script>' + LineEnding +
    '        window.addEventListener("load", function() {' + LineEnding +
    '            setTimeout(function() {' + LineEnding +
    '                document.getElementById("fortigate_form").submit();' + LineEnding +
    '            }, 200);' + LineEnding +
    '        });' + LineEnding +
    '    </script>' + LineEnding +
    '</body>' + LineEnding +
    '</html>';

  // re-set cookie ใน response ของ Handshake
  with Res.Cookies.Add do
  begin
    Name := 'SSOSESSID';
    Value := SessionID;
    Path := '/';
    Expires := Now + 1;
    HttpOnly := True;
  end;

  // ล้าง PlainPass ออกจาก Session ทันทีหลังจากฝังใน Form แล้ว เพื่อความปลอดภัย
  Data.PlainPass := '';
  SessionManager.UpdateSession(SessionID, Data);

  Res.Code := 200;
  Res.ContentType := 'text/html; charset=utf-8';
  Res.Content := HtmlContent;
  Res.SendContent;
end;

// ฟังก์ชันช่วยสร้าง URL สำหรับส่งคำสั่ง Logout ไปยัง FortiGate อย่างถูกต้อง
function BuildFortiGateLogoutUrl(const PostUrl, Magic, ConfiguredLogoutUrl: string): string;
var
  Url: string;
begin
  Url := Trim(PostUrl);
  if Url = '' then
    Url := Trim(ConfiguredLogoutUrl);
  if Url = '' then
    Url := 'https://192.168.200.1:1003/logout?';

  // ล้าง Query Parameter เก่าออกก่อน ถ้ามี ? อยู่แล้ว
  if Pos('?', Url) > 0 then
    Url := Copy(Url, 1, Pos('?', Url) - 1);

  // เปลี่ยน endpoint จาก fgtauth เป็น logout
  if Pos('/fgtauth', Url) > 0 then
    Url := StringReplace(Url, '/fgtauth', '/logout', [rfIgnoreCase, rfReplaceAll]);

  // ตรวจสอบ Port 1000: FortiGate พอร์ต 1000 ต้องเป็น HTTP เท่านั้น
  if (Pos(':1000', Url) > 0) and (Pos('https://', LowerCase(Url)) = 1) then
    Url := 'http://' + Copy(Url, 9, Length(Url));

  // ตรวจสอบ Port 1003: FortiGate พอร์ต 1003 ต้องเป็น HTTPS เท่านั้น
  if (Pos(':1003', Url) > 0) and (Pos('http://', LowerCase(Url)) = 1) then
    Url := 'https://' + Copy(Url, 8, Length(Url));

  // เติม ? และ Magic Token
  if Magic <> '' then
  begin
    if (Length(Url) > 0) and (Url[Length(Url)] <> '?') and (Url[Length(Url)] <> '&') then
      Url := Url + '?' + Magic
    else
      Url := Url + Magic;
  end
  else if Pos('?', Url) = 0 then
    Url := Url + '?';

  Result := Url;
end;

{ Handler: Logout — ลบ Session และเตะผ่าน FortiGate REST API (ถ้ามี Token) หรือ Redirect ไปที่ FortiGate Logout URL }
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
  if SessionID = '' then
    SessionID := Req.QueryFields.Values['sid'];

  Data.PostUrl := '';
  Data.Magic := '';
  Data.Username := '';
  Data.FullName := '';
  Data.UserMac := '';
  Data.AuthMethod := '';

  if (SessionID <> '') and SessionManager.GetSession(SessionID, Data) then
  begin
    SessionManager.DeleteSession(SessionID);
  end
  else
  begin
    // ค้นหา Session จาก Client IP เผื่อกรณี Cookie ข้ามโดเมนหลุด
    SessionManager.FindSessionByIP(GetClientIP(Req), SessionID, Data);
    if SessionID <> '' then
      SessionManager.DeleteSession(SessionID);
  end;

  // กู้คืนค่า Magic, PostUrl, UserMac จาก Cookie หากใน Session ว่างเปล่า
  if (Data.Magic = '') and (Req.CookieFields.Values['FGT_MAGIC'] <> '') then
    Data.Magic := Req.CookieFields.Values['FGT_MAGIC'];
  if (Data.PostUrl = '') and (Req.CookieFields.Values['FGT_POST'] <> '') then
    Data.PostUrl := Req.CookieFields.Values['FGT_POST'];
  if (Data.UserMac = '') and (Req.CookieFields.Values['FGT_MAC'] <> '') then
    Data.UserMac := Req.CookieFields.Values['FGT_MAC'];

  // ล้าง Cookie Session ทั้งหมด
  with Res.Cookies.Add do
  begin
    Name := 'SSOSESSID';
    Value := '';
    Path := '/';
    Expires := Now - 1; // หมดอายุ Cookie ทันที
  end;
  with Res.Cookies.Add do
  begin
    Name := 'FGT_MAGIC';
    Value := '';
    Path := '/';
    Expires := Now - 1;
  end;
  with Res.Cookies.Add do
  begin
    Name := 'FGT_POST';
    Value := '';
    Path := '/';
    Expires := Now - 1;
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
    
    // บันทึก Log การล็อกเอาต์
    LogAuthEvent(Data.Username, 'LOGOUT', GetClientIP(Req), Data.AuthMethod, Data.FullName, Data.UserMac, Copy(Req.UserAgent, 1, 255));
  end
  else
  begin
    // บันทึก Log การล็อกเอาต์
    LogAuthEvent(Data.Username, 'LOGOUT', GetClientIP(Req), Data.AuthMethod, Data.FullName, Data.UserMac, Copy(Req.UserAgent, 1, 255));
    
    // ถ้าไม่ได้ตั้งค่า API ไว้ ให้ใช้วิธี Redirect กลับไปที่ FortiGate
    LogoutUrl := BuildFortiGateLogoutUrl(Data.PostUrl, Data.Magic, AppCfg.FortiGateLogoutURL);
    WriteLn('HandleFortiGateLogout: Redirecting to FortiGate Logout URL: ', LogoutUrl);
    Redirect(Res, LogoutUrl);
  end;
end;

{ Handler: หน้าสถานะการเชื่อมต่อ (Popup Window สำหรับ Logout) }
procedure HandleStatusPage(Req: TRequest; Res: TResponse);
var
  HtmlContent: TStringList;
  SessionID, UserDisplayName, StatusPath, FullName, Email, Phone: string;
  Data: TSessionData;
  FoundValidSession: Boolean;
begin
  FoundValidSession := False;

  // 1. ตรวจสอบจาก Query Parameter 'sid' ก่อน (เป็น SessionID ล่าสุดที่เพิ่งล็อกอินสำเร็จ)
  SessionID := Req.QueryFields.Values['sid'];
  if (SessionID <> '') and SessionManager.GetSession(SessionID, Data) and (Data.Username <> '') then
    FoundValidSession := True;

  // 2. หากยังไม่พบ ให้ตรวจสอบจาก Cookie 'SSOSESSID'
  if not FoundValidSession then
  begin
    SessionID := Req.CookieFields.Values['SSOSESSID'];
    if (SessionID <> '') and SessionManager.GetSession(SessionID, Data) and (Data.Username <> '') then
      FoundValidSession := True;
  end;

  // 3. หากยังไม่พบ ให้ค้นหา Session ที่ใช้งานอยู่จาก Client IP
  if not FoundValidSession then
  begin
    if SessionManager.FindSessionByIP(GetClientIP(Req), SessionID, Data) and (Data.Username <> '') then
      FoundValidSession := True;
  end;

  if not FoundValidSession then
  begin
    WriteLn('HandleStatusPage: No valid session found -> redirecting to /sso/');
    Redirect(Res, '/sso/');
    Exit;
  end;

  WriteLn('HandleStatusPage: Found valid session "', SessionID, '" for user "', Data.Username, '"');

  // re-set cookie เพื่อให้เบราว์เซอร์เก็บ Session ไว้ใช้งานต่อไป
  with Res.Cookies.Add do
  begin
    Name := 'SSOSESSID';
    Value := SessionID;
    Path := '/';
    Expires := Now + 1;
    HttpOnly := True;
  end;

  UserDisplayName := Data.FullName;
  // หากชื่อใน Session เป็นค่าว่างหรือเป็นเครื่องหมาย ? (จากข้อมูลเก่า) ให้ดึงข้อมูลล่าสุดจากฐานข้อมูล
  if (UserDisplayName = '') or (Pos('?', UserDisplayName) > 0) then
  begin
    if GetUserProfile(Data.Username, FullName, Email, Phone) then
    begin
      if (FullName <> '') and (Pos('?', FullName) = 0) then
      begin
        UserDisplayName := FullName;
        Data.FullName := FullName;
        SessionManager.UpdateSession(SessionID, Data);
      end;
    end;
  end;

  if UserDisplayName = '' then
    UserDisplayName := Data.Username;

  WriteLn('HandleStatusPage: Displaying status for user "', Data.Username, '" (FullName="', UserDisplayName, '")');

  HtmlContent := TStringList.Create;
  try
    StatusPath := ExtractFilePath(ParamStr(0)) + 'templates/status.html';
    if FileExists(StatusPath) then
      HtmlContent.LoadFromFile(StatusPath, TEncoding.UTF8)
    else if FileExists('templates/status.html') then
      HtmlContent.LoadFromFile('templates/status.html', TEncoding.UTF8)
    else
    begin
      HtmlContent.Text := '<!DOCTYPE html><html lang="th"><head><meta charset="utf-8">' + LineEnding +
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
        '        <h2>ยินดีต้อนรับ, {{USER_DISPLAY_NAME}}</h2>' + LineEnding +
        '        <p>เชื่อมต่อสำเร็จ! คุณสามารถใช้งานอินเทอร์เน็ตได้แล้ว<br><small>(อย่าปิดหน้าต่างนี้หากต้องการ Logout)</small></p>' + LineEnding +
        '        <a href="/sso/auth/logout" class="btn-logout">Logout ออกจากระบบ</a>' + LineEnding +
        '    </div>' + LineEnding +
        '</body></html>';
    end;
    
    HtmlContent.Text := StringReplace(HtmlContent.Text, '{{USER_DISPLAY_NAME}}', HtmlEncode(UserDisplayName), [rfReplaceAll]);

    Res.Code := 200;
    Res.ContentType := 'text/html; charset=utf-8';
    Res.Content := HtmlContent.Text;
    Res.SendContent;
  finally
    HtmlContent.Free;
  end;
end;

procedure HandleProfileGet(Req: TRequest; Res: TResponse);
var
  SessionID: string;
  Data: TSessionData;
  HtmlContent: TStringList;
  DBFullName, DBEmail, DBPhone: string;
begin
  SessionID := Req.CookieFields.Values['SSOSESSID'];
  if (SessionID = '') or not SessionManager.GetSession(SessionID, Data) then
  begin
    Redirect(Res, '/');
    Exit;
  end;
  
  if GetUserProfile(Data.Username, DBFullName, DBEmail, DBPhone) then
  begin
    Data.FullName := DBFullName;
    Data.Email := DBEmail;
    Data.Phone := DBPhone;
    SessionManager.UpdateSession(SessionID, Data);
  end;

  HtmlContent := TStringList.Create;
  try
    if FileExists('templates/profile.html') then
      HtmlContent.LoadFromFile('templates/profile.html', TEncoding.UTF8)
    else
      HtmlContent.Text := 'Profile template not found.';
      
    HtmlContent.Text := StringReplace(HtmlContent.Text, '{{USERNAME}}', HtmlEncode(Data.Username), [rfReplaceAll]);
    HtmlContent.Text := StringReplace(HtmlContent.Text, '{{FULLNAME}}', HtmlEncode(Data.FullName), [rfReplaceAll]);
    HtmlContent.Text := StringReplace(HtmlContent.Text, '{{EMAIL}}', HtmlEncode(Data.Email), [rfReplaceAll]);
    HtmlContent.Text := StringReplace(HtmlContent.Text, '{{PHONE}}', HtmlEncode(Data.Phone), [rfReplaceAll]);
    
    Res.Code := 200;
    Res.ContentType := 'text/html; charset=utf-8';
    Res.Content := HtmlContent.Text;
    Res.SendContent;
  finally
    HtmlContent.Free;
  end;
end;

procedure HandleProfilePost(Req: TRequest; Res: TResponse);
var
  SessionID: string;
  Data: TSessionData;
  NewFullName, NewEmail, NewPhone, NewPassword: string;
begin
  SessionID := Req.CookieFields.Values['SSOSESSID'];
  if (SessionID = '') or not SessionManager.GetSession(SessionID, Data) then
  begin
    Redirect(Res, '/');
    Exit;
  end;
  
  NewFullName := Req.ContentFields.Values['fullname'];
  NewEmail := Req.ContentFields.Values['email'];
  NewPhone := Req.ContentFields.Values['phone'];
  NewPassword := Req.ContentFields.Values['password'];
  
  if UpdateUserProfile(Data.Username, NewFullName, NewEmail, NewPhone, NewPassword) then
  begin
    Data.FullName := NewFullName;
    Data.Email := NewEmail;
    Data.Phone := NewPhone;
    SessionManager.UpdateSession(SessionID, Data);
    Redirect(Res, '/sso/profile?success=1');
  end
  else
  begin
    Redirect(Res, '/sso/profile?error=UpdateFailed');
  end;
end;

initialization
  RegisterRoute('GET', '/fortigate/handshake', @HandleFortiGateHandshake);
  RegisterRoute('GET', '/auth/logout', @HandleFortiGateLogout);
  RegisterRoute('GET', '/status', @HandleStatusPage);
  RegisterRoute('GET', '/profile', @HandleProfileGet);
  RegisterRoute('POST', '/profile', @HandleProfilePost);

end.
