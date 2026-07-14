unit AuthProviderID;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, HTTPDefs, fpHTTP, fpjson, jsonparser, fphttpclient, opensslsockets, uriparser,
  Router, SessionMgr, RadiusDB, Config, base64;

procedure HandleProviderIDLogin(Req: TRequest; Res: TResponse);
procedure HandleProviderIDCallback(Req: TRequest; Res: TResponse);

implementation

function GenerateStateToken: string;
var
  Guid: TGuid;
begin
  CreateGUID(Guid);
  Result := StringReplace(GUIDToString(Guid), '{', '', [rfReplaceAll]);
  Result := StringReplace(Result, '}', '', [rfReplaceAll]);
  Result := StringReplace(Result, '-', '', [rfReplaceAll]);
end;

procedure HandleProviderIDLogin(Req: TRequest; Res: TResponse);
var
  State, AuthUrl: string;
begin
  State := GenerateStateToken;
  
  AuthUrl := AppCfg.ProviderIDURL + '/login?response_type=code' +
             '&client_id=' + EncodeURLElement(AppCfg.ProviderIDClientID) +
             '&redirect_uri=' + EncodeURLElement(AppCfg.ProviderIDRedirectURI) +
             '&state=' + State;
             
  Redirect(Res, AuthUrl);
end;

procedure HandleProviderIDCallback(Req: TRequest; Res: TResponse);
var
  Code: string;
  Client: TFPHttpClient;
  PostData: TStringList;
  ResponseStr: string;
  JSON: TJSONObject;
  AccessToken, PID, FullName, PlainPass, SessionID: string;
  Data: TSessionData;
begin
  Code := Req.QueryFields.Values['code'];
  
  if Code = '' then
  begin
    SendJSONError(Res, 400, 'Authorization code missing');
    Exit;
  end;
  
  Client := TFPHttpClient.Create(nil);
  PostData := TStringList.Create;
  try
    Client.AllowRedirect := True;
    
    PostData.Add('grant_type=authorization_code');
    PostData.Add('code=' + Code);
    PostData.Add('client_id=' + AppCfg.ProviderIDClientID);
    PostData.Add('client_secret=' + AppCfg.ProviderIDSecret);
    PostData.Add('redirect_uri=' + AppCfg.ProviderIDRedirectURI);
    
    try
      ResponseStr := Client.FormPost(AppCfg.ProviderIDURL + '/token', PostData);
      
      JSON := GetJSON(ResponseStr) as TJSONObject;
      try
        AccessToken := JSON.Get('access_token', '');
      finally
        JSON.Free;
      end;
      
      if AccessToken = '' then
      begin
        SendJSONError(Res, 500, 'Failed to obtain access token');
        Exit;
      end;
      
      PID := 'provider_999'; // Placeholder
      FullName := 'MOPH Provider User';
      
      PlainPass := SSORadiusAuth(PID, '', FullName);
      
      if PlainPass <> '' then
      begin
        SessionID := Req.CookieFields.Values['SSOSESSID'];
        if (SessionID = '') or not SessionManager.GetSession(SessionID, Data) then
        begin
          SessionID := SessionManager.CreateSession;
          SessionManager.GetSession(SessionID, Data);
        end;
        
        Data.Username := PID;
        Data.FullName := FullName;
        Data.PlainPass := PlainPass;
        SessionManager.UpdateSession(SessionID, Data);
        
        with Res.Cookies.Add do
        begin
          Name := 'SSOSESSID';
          Value := SessionID;
          Path := '/';
          Expires := Now + 1;
          HttpOnly := True;
        end;
        Redirect(Res, '/sso/fortigate/handshake');
      end
      else
        Redirect(Res, '/sso/?error=db');
        
    except
      on E: Exception do
        SendJSONError(Res, 500, 'ProviderID API Error: ' + E.Message);
    end;
  finally
    Client.Free;
    PostData.Free;
  end;
end;

initialization
  RegisterRoute('GET', '/auth/providerid', @HandleProviderIDLogin);
  RegisterRoute('GET', '/auth/providerid/callback', @HandleProviderIDCallback);

end.
