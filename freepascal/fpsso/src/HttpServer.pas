unit HttpServer;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fphttpserver, HTTPDefs, Router;

type
  TSSOServer = class(TFPHttpServer)
  public
    procedure HandleRequest(var ARequest: TFPHTTPConnectionRequest;
                            var AResponse: TFPHTTPConnectionResponse); override;
  end;

var
  Server: TSSOServer;

procedure StartServer(Port: Word);

implementation

procedure TSSOServer.HandleRequest(var ARequest: TFPHTTPConnectionRequest;
                                   var AResponse: TFPHTTPConnectionResponse);
begin
  // Set default CORS headers
  AResponse.SetCustomHeader('Access-Control-Allow-Origin', '*');
  AResponse.SetCustomHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  AResponse.SetCustomHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if ARequest.Method = 'OPTIONS' then
  begin
    AResponse.Code := 204;
    AResponse.SendContent;
    Exit;
  end;

  // Pass to Router
  Router.HandleRequest(ARequest, AResponse);
end;

procedure StartServer(Port: Word);
begin
  Server := TSSOServer.Create(nil);
  try
    Server.Port := Port;
    Server.Threaded := True;
    Writeln('Starting FreePascal SSO Server on port ', Port, '...');
    Server.Active := True;
  finally
    Server.Free;
  end;
end;

end.
