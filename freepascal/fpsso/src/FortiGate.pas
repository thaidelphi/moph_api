unit FortiGate;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, HTTPDefs, fpHTTP, Router, SessionMgr, Config;

procedure HandleFortiGateHandshake(Req: TRequest; Res: TResponse);

implementation

procedure HandleFortiGateHandshake(Req: TRequest; Res: TResponse);
var
  SessionID: string;
  Data: TSessionData;
  HtmlContent: string;
begin
  SessionID := Req.CookieFields.Values['SSOSESSID'];
  
  if (SessionID = '') or not SessionManager.GetSession(SessionID, Data) then
  begin
    Redirect(Res, '/sso/?error=session');
    Exit;
  end;
  
  // Basic template replacement
  HtmlContent := '<!DOCTYPE html><html lang="th"><head><meta charset="utf-8">' + LineEnding +
    '    <link rel="stylesheet" href="/assets/css/fonts.css">' + LineEnding +
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
    '    <form id="fortigate_form" action="' + AppCfg.FortiGateAuthURL + '" method="post" style="display: none;">' + LineEnding +
    '        <input type="hidden" name="username" value="' + Data.Username + '">' + LineEnding +
    '        <input type="hidden" name="password" value="' + Data.PlainPass + '">' + LineEnding +
    '        <input type="hidden" name="magic" value="' + Data.Magic + '">' + LineEnding +
    '        <input type="hidden" name="redir" value="' + Data.RedirUrl + '">' + LineEnding +
    '    </form>' + LineEnding +
    '    <script>' + LineEnding +
    '        window.addEventListener("load", function() {' + LineEnding +
    '            setTimeout(function() { ' + LineEnding +
    '                // Try to open a small popup for logout (May be blocked by browsers)' + LineEnding +
    '                window.open("/sso/status", "LogoutWindow", "width=400,height=350,toolbar=no,location=no,status=no,menubar=no,scrollbars=yes,resizable=yes");' + LineEnding +
    '                document.getElementById("fortigate_form").submit(); ' + LineEnding +
    '            }, 1000);' + LineEnding +
    '        });' + LineEnding +
    '    </script>' + LineEnding +
    '</body>' + LineEnding +
    '</html>';

  Res.Code := 200;
  Res.ContentType := 'text/html; charset=utf-8';
  Res.Content := HtmlContent;
  Res.SendContent;
end;

procedure HandleFortiGateLogout(Req: TRequest; Res: TResponse);
var
  SessionID: string;
begin
  SessionID := Req.CookieFields.Values['SSOSESSID'];
  if SessionID <> '' then
  begin
    SessionManager.DeleteSession(SessionID);
    with Res.Cookies.Add do
    begin
      Name := 'SSOSESSID';
      Value := '';
      Path := '/';
      Expires := Now - 1; // Expire cookie
    end;
  end;
  
  Redirect(Res, AppCfg.FortiGateLogoutURL);
end;

procedure HandleStatusPage(Req: TRequest; Res: TResponse);
var
  HtmlContent: string;
begin
  HtmlContent := '<!DOCTYPE html><html lang="th"><head><meta charset="utf-8">' + LineEnding +
    '    <link rel="stylesheet" href="/assets/css/fonts.css">' + LineEnding +
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
