unit Router;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, HTTPDefs, fpHTTP;

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

implementation

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

procedure HandleRequest(Req: TRequest; Res: TResponse);
var
  I: Integer;
  Method, Path: string;
begin
  Method := UpperCase(Req.Method);
  Path := Req.PathInfo;
  if Path = '' then
    Path := '/';
  
  Writeln('SSO Request: ', Method, ' ', Req.URI, ' (PathInfo: ', Path, ')');
  
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
