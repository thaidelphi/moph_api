unit HttpServer;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fphttpserver, HTTPDefs, Router, Config, opensslsockets;

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
    
    if AppCfg.UseSSL and FileExists(AppCfg.SSLCert) and FileExists(AppCfg.SSLKey) then
    begin
      Server.UseSSL := True;
      Server.CertificateData.Certificate.FileName := AppCfg.SSLCert;
      Server.CertificateData.PrivateKey.FileName := AppCfg.SSLKey;
      Writeln('Starting FreePascal SSO Server (HTTPS) on port ', Port, '...');
    end
    else
    begin
      Writeln('Starting FreePascal SSO Server (HTTP) on port ', Port, '...');
    end;
    
    Server.Active := True;
  finally
    Server.Free;
  end;
end;

end.
