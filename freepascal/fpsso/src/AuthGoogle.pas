unit AuthGoogle;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, HTTPDefs, fpHTTP, Router;

procedure HandleGoogleLogin(Req: TRequest; Res: TResponse);
procedure HandleGoogleCallback(Req: TRequest; Res: TResponse);

implementation

procedure HandleGoogleLogin(Req: TRequest; Res: TResponse);
begin
  SendJSONError(Res, 501, 'Google OAuth not yet implemented in FreePascal version');
end;

procedure HandleGoogleCallback(Req: TRequest; Res: TResponse);
begin
  SendJSONError(Res, 501, 'Google OAuth not yet implemented in FreePascal version');
end;

initialization
  RegisterRoute('GET', '/auth/google', @HandleGoogleLogin);
  RegisterRoute('GET', '/auth/google/callback', @HandleGoogleCallback);

end.
