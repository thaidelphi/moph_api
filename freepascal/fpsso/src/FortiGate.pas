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
  HtmlContent := '<!DOCTYPE html>' + LineEnding +
    '<html lang="th">' + LineEnding +
    '<head>' + LineEnding +
    '    <meta charset="UTF-8">' + LineEnding +
    '    <title>กำลังเชื่อมต่อระบบเครือข่าย...</title>' + LineEnding +
    '    <style>' + LineEnding +
    '        body { font-family: sans-serif; background-color: #f4f7f6; display: flex; justify-content: center; align-items: center; height: 100vh; }' + LineEnding +
    '        .loading-box { text-align: center; background: white; padding: 40px; border-radius: 12px; box-shadow: 0 4px 15px rgba(0,0,0,0.05); }' + LineEnding +
    '    </style>' + LineEnding +
    '</head>' + LineEnding +
    '<body>' + LineEnding +
    '    <div class="loading-box">' + LineEnding +
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
    '            setTimeout(function() { document.getElementById("fortigate_form").submit(); }, 1000);' + LineEnding +
    '        });' + LineEnding +
    '    </script>' + LineEnding +
    '</body>' + LineEnding +
    '</html>';

  Res.Code := 200;
  Res.ContentType := 'text/html; charset=utf-8';
  Res.Content := HtmlContent;
  Res.SendContent;
end;

initialization
  RegisterRoute('GET', '/fortigate/handshake', @HandleFortiGateHandshake);

end.
