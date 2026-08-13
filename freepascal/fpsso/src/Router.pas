unit Router;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, HTTPDefs, fpHTTP;

procedure ShowDemoLimitError(Res: TResponse);

type
  TRouteHandler = procedure(Req: TRequest; Res: TResponse);

  TRoute = record
    Method: string;
    Path: string;
    Handler: TRouteHandler;
  end;

var
  Routes: array of TRoute;

procedure RegisterRoute(const AMethod, APath: string; AHandler: TRouteHandler);
procedure HandleRequest(Req: TRequest; Res: TResponse);
procedure SendJSONError(Res: TResponse; StatusCode: Integer; const Msg: string);
procedure Redirect(Res: TResponse; const URL: string);
function GetClientIP(Req: TRequest): string;

implementation

uses
  License;

procedure ShowDemoLimitError(Res: TResponse);
begin
  Res.Code := 403;
  Res.ContentType := 'text/html; charset=utf-8';
  Res.Content := '<html><head><meta charset="utf-8"><title>License Limit Reached</title></head>' +
                 '<body style="font-family: sans-serif; text-align: center; padding: 50px; background-color: #f8f9fa;">' +
                 '<h2 style="color: #dc3545;">ขีดจำกัดการใช้งาน Demo (10 Users/Day)</h2>' +
                 '<p>ระบบของคุณทำงานอยู่ในโหมด Demo และครบกำหนดจำนวนผู้ใช้งานสูงสุดในวันนี้แล้ว</p>' +
                 '<p>กรุณาติดต่อผู้พัฒนาเพื่อสั่งซื้อ License Key สำหรับการใช้งานแบบไม่จำกัด</p>' +
                 '</body></html>';
  Res.SendContent;
end;

procedure RegisterRoute(const AMethod, APath: string; AHandler: TRouteHandler);
begin
  SetLength(Routes, Length(Routes) + 1);
  Routes[High(Routes)].Method := UpperCase(AMethod);
  Routes[High(Routes)].Path := APath;
  Routes[High(Routes)].Handler := AHandler;
end;

procedure SendJSONError(Res: TResponse; StatusCode: Integer; const Msg: string);
begin
  Res.Code := StatusCode;
  Res.ContentType := 'application/json; charset=utf-8';
  Res.Content := '{"error": "' + Msg + '"}';
  Res.SendContent;
end;

procedure Redirect(Res: TResponse; const URL: string);
begin
  Res.Code := 302;
  Res.SetCustomHeader('Location', URL);
  Res.SendContent;
end;

function GetClientIP(Req: TRequest): string;
begin
  Result := Req.GetCustomHeader('X-Forwarded-For');
  if Result = '' then
    Result := Req.GetCustomHeader('X-Real-IP');
  if Result = '' then
    Result := Req.RemoteAddress;
end;

procedure HandleRequest(Req: TRequest; Res: TResponse);
var
  I: Integer;
  Method, Path: string;
begin
  Method := UpperCase(Req.Method);
  Path := Req.PathInfo;
  
  // ตัด /sso ออกจากเริ่มต้น Path (เผื่อหลุดมาจาก reverse proxy แบบไม่สมบูรณ์)
  if Pos('/sso', Path) = 1 then
    Path := Copy(Path, 5, Length(Path));
    
  if Path = '' then
    Path := '/';
    
  // Scattered License Check
  QuickLicenseCheck;
  
  Writeln('SSO Request: ', Method, ' ', Req.URI, ' (Routed Path: ', Path, ')');
  
  // Clean trailing slash if not root
  if (Length(Path) > 1) and (Path[Length(Path)] = '/') then
    Path := Copy(Path, 1, Length(Path) - 1);

  for I := 0 to High(Routes) do
  begin
    if ((Routes[I].Method = Method) or (Routes[I].Method = 'ANY')) and
       (Routes[I].Path = Path) then
    begin
      try
        Routes[I].Handler(Req, Res);
      except
        on E: Exception do
        begin
          SendJSONError(Res, 500, 'Internal Server Error: ' + E.Message);
        end;
      end;
      Exit;
    end;
  end;

  SendJSONError(Res, 404, 'Not Found');
end;

end.
