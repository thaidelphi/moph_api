unit Config;

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, SysUtils, strutils;

type
  TAppConfig = record
    DBHost: string;
    DBUser: string;
    DBPass: string;
    DBName: string;
    
    ThaIDApiKey: string;
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
    
    GoogleClientID: string;
    GoogleClientSecret: string;
    GoogleRedirectURI: string;
    GoogleAuthURL: string;
    GoogleTokenURL: string;
    GoogleUserInfoURL: string;
    
    MophIDURL: string;
    
    // FortiGate Settings
    FortiGateAuthURL: string;
    FortiGateLogoutURL: string;
    FortiGateApiToken: string;
    FortiGateApiUrl: string;
    
    // System Settings
    LoginTemplatePath: string;
    EnableLogoutPopup: Boolean;
    
    AdminUser: string;
    AdminPass: string;
    
    UseSSL: Boolean;
    SSLCert: string;
    SSLKey: string;
    
    SSOAutoApprove: Boolean;
    AppPort: Word;
    AppURL: string;          // Base URL ของระบบ (เช่น https://api1.kpo.go.th) กำหนดจาก .env
    PostLoginRedirectURL: string; // URL ปลายทางหลังล็อกอินสำเร็จ (ค่าเริ่มต้น /sso/status)
    LicenseKeyPath: string;  // path ไปยังไฟล์ license.key
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

        if (Key = 'ENABLE_LOGOUT_POPUP') then AppCfg.EnableLogoutPopup := LowerCase(Value) = 'true'
        else if (Key = 'DB_HOST') then AppCfg.DBHost := Value
        else if (Key = 'DB_USER') or (Key = 'DB_USERNAME') then AppCfg.DBUser := Value
        else if (Key = 'DB_PASS') or (Key = 'DB_PASSWORD') then AppCfg.DBPass := Value
        else if (Key = 'DB_NAME') or (Key = 'DB_DATABASE') then AppCfg.DBName := Value
        
        else if (Key = 'THAID_API_KEY') then AppCfg.ThaIDApiKey := Value
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
        
        else if (Key = 'GOOGLE_CLIENT_ID') then AppCfg.GoogleClientID := Value
        else if (Key = 'GOOGLE_CLIENT_SECRET') then AppCfg.GoogleClientSecret := Value
        else if (Key = 'GOOGLE_REDIRECT_URI') then AppCfg.GoogleRedirectURI := Value
        else if (Key = 'GOOGLE_URL_AUTH') then AppCfg.GoogleAuthURL := Value
        else if (Key = 'GOOGLE_URL_TOKEN') then AppCfg.GoogleTokenURL := Value
        else if (Key = 'GOOGLE_URL_USERINFO') then AppCfg.GoogleUserInfoURL := Value
        
        else if (Key = 'MOPH_ID_URL') then AppCfg.MophIDURL := Value
        else if (Key = 'FORTIGATE_AUTH_URL') then AppCfg.FortiGateAuthURL := Value
        else if (Key = 'FORTIGATE_LOGOUT_URL') then AppCfg.FortiGateLogoutURL := Value
        else if (Key = 'FORTIGATE_API_TOKEN') then AppCfg.FortiGateApiToken := Value
        else if (Key = 'FORTIGATE_API_URL') then AppCfg.FortiGateApiUrl := Value
        else if (Key = 'LOGIN_TEMPLATE_PATH') then AppCfg.LoginTemplatePath := Value
        
        else if (Key = 'ADMIN_USERNAME') then AppCfg.AdminUser := Value
        else if (Key = 'ADMIN_PASSWORD') then AppCfg.AdminPass := Value
        else if (Key = 'USE_SSL') then AppCfg.UseSSL := (LowerCase(Value) = 'true') or (Value = '1')
        else if (Key = 'SSL_CERT') then AppCfg.SSLCert := Value
        else if (Key = 'SSL_KEY') then AppCfg.SSLKey := Value
        else if (Key = 'SSO_AUTO_APPROVE') then AppCfg.SSOAutoApprove := (LowerCase(Value) = 'true') or (Value = '1')
        else if (Key = 'APP_PORT') then AppCfg.AppPort := StrToIntDef(Value, 8080)
        else if (Key = 'APP_URL') or (Key = 'BASE_URL') then AppCfg.AppURL := Value
        else if (Key = 'POST_LOGIN_REDIRECT_URL') or (Key = 'REDIRECT_AFTER_LOGIN') or (Key = 'LOGIN_SUCCESS_URL') then AppCfg.PostLoginRedirectURL := Value
        else if (Key = 'LICENSE_KEY') then AppCfg.LicenseKeyPath := Value;
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
  AppCfg.LoginTemplatePath := ExtractFilePath(ParamStr(0)) + 'templates/login.html';
  AppCfg.EnableLogoutPopup := False; // ปิดการเปิดป๊อปอัปสถานะเป็นค่าเริ่มต้น เพื่อป้องกันการเปิดแท็บซ้ำซ้อน
  AppCfg.AdminUser := 'admin';
  AppCfg.AdminPass := 'password';
  AppCfg.UseSSL := False;
  AppCfg.SSLCert := ExtractFilePath(ParamStr(0)) + 'cert.pem';
  AppCfg.SSLKey := ExtractFilePath(ParamStr(0)) + 'key.pem';
  AppCfg.SSOAutoApprove := True;
  AppCfg.AppPort := 8080;
  AppCfg.LicenseKeyPath := 'license.key';  // ค่าเริ่มต้นอยู่ข้าง binary
  
end.
