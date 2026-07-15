unit Config;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, strutils;

type
  TAppConfig = record
    DBHost: string;
    DBUser: string;
    DBPass: string;
    DBName: string;
    
    ThaIDClientID: string;
    ThaIDSecret: string;
    ThaIDRedirectURI: string;
    ThaIDTokenURL: string;
    ThaIDAuthURL: string;
    ThaIDScope: string;
    
    ProviderIDClientID: string;
    ProviderIDSecret: string;
    ProviderIDRedirectURI: string;
    ProviderIDURL: string;
    MophIDURL: string;
    
    FortiGateAuthURL: string;
    FortiGateLogoutURL: string;
    
    LoginTemplatePath: string;
    
    AdminUser: string;
    AdminPass: string;
    
    SSOAutoApprove: Boolean;
  end;

var
  AppCfg: TAppConfig;

function LoadConfig(const EnvPath: string): Boolean;

implementation

function LoadConfig(const EnvPath: string): Boolean;
var
  Lines: TStringList;
  I: Integer;
  Line, Key, Value: string;
  SplitPos: Integer;
begin
  Result := False;
  if not FileExists(EnvPath) then Exit;
  
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(EnvPath);
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      if (Line = '') or (Line[1] = '#') then Continue;
      
      SplitPos := Pos('=', Line);
      if SplitPos > 0 then
      begin
        Key := Trim(Copy(Line, 1, SplitPos - 1));
        Value := Trim(Copy(Line, SplitPos + 1, Length(Line)));
        
        // Remove quotes if present
        if (Length(Value) >= 2) and 
           (((Value[1] = '"') and (Value[Length(Value)] = '"')) or 
            ((Value[1] = '''') and (Value[Length(Value)] = ''''))) then
        begin
          Value := Copy(Value, 2, Length(Value) - 2);
        end;

        if (Key = 'DB_HOST') then AppCfg.DBHost := Value
        else if (Key = 'DB_USER') or (Key = 'DB_USERNAME') then AppCfg.DBUser := Value
        else if (Key = 'DB_PASS') or (Key = 'DB_PASSWORD') then AppCfg.DBPass := Value
        else if (Key = 'DB_NAME') or (Key = 'DB_DATABASE') then AppCfg.DBName := Value
        
        else if (Key = 'THAID_CLIENT_ID') then AppCfg.ThaIDClientID := Value
        else if (Key = 'THAID_SECRET_ID') then AppCfg.ThaIDSecret := Value
        else if (Key = 'THAID_REDIRECT_URI') then AppCfg.ThaIDRedirectURI := Value
        else if (Key = 'THAID_URL_TOKEN') then AppCfg.ThaIDTokenURL := Value
        else if (Key = 'THAID_URL_AUTH') then AppCfg.ThaIDAuthURL := Value
        else if (Key = 'THAID_SCOPE') then AppCfg.ThaIDScope := Value
        
        else if (Key = 'PROVIDER_ID_CLIENT_ID') then AppCfg.ProviderIDClientID := Value
        else if (Key = 'PROVIDER_ID_SECRET_KEY') then AppCfg.ProviderIDSecret := Value
        else if (Key = 'PROVIDER_ID_REDIRECT_URI') then AppCfg.ProviderIDRedirectURI := Value
        else if (Key = 'PROVIDER_ID_URL') then AppCfg.ProviderIDURL := Value
        else if (Key = 'MOPH_ID_URL') then AppCfg.MophIDURL := Value
        
        else if (Key = 'FORTIGATE_AUTH_URL') then AppCfg.FortiGateAuthURL := Value
        else if (Key = 'FORTIGATE_LOGOUT_URL') then AppCfg.FortiGateLogoutURL := Value
        else if (Key = 'LOGIN_TEMPLATE_PATH') then AppCfg.LoginTemplatePath := Value
        
        else if (Key = 'ADMIN_USERNAME') then AppCfg.AdminUser := Value
        else if (Key = 'ADMIN_PASSWORD') then AppCfg.AdminPass := Value
        else if (Key = 'SSO_AUTO_APPROVE') then AppCfg.SSOAutoApprove := (LowerCase(Value) = 'true') or (Value = '1');
      end;
    end;
    
    if AppCfg.FortiGateLogoutURL = '' then
      AppCfg.FortiGateLogoutURL := StringReplace(AppCfg.FortiGateAuthURL, 'fgtauth', 'logout', [rfIgnoreCase]);
      
    Result := True;
  finally
    Lines.Free;
  end;
end;

initialization
  // Set defaults
  AppCfg.DBHost := '127.0.0.1';
  AppCfg.DBUser := 'root';
  AppCfg.DBPass := '';
  AppCfg.DBName := 'radius';
  AppCfg.LoginTemplatePath := '/var/www/api/freepascal/fpsso/templates/login.html';
  AppCfg.AdminUser := 'admin';
  AppCfg.AdminPass := 'password';
  AppCfg.SSOAutoApprove := True;
  
end.
