unit AdminUsers;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, HTTPDefs, fpHTTP, fpjson, jsonparser, Router, Config, 
  mysql80conn, sqldb, db, Base64, License;

procedure HandleAdminHtml(Req: TRequest; Res: TResponse);
procedure HandleApiUsers(Req: TRequest; Res: TResponse);
procedure HandleApiLicense(Req: TRequest; Res: TResponse);
procedure HandleApiLogs(Req: TRequest; Res: TResponse);

implementation

// -------------------------------------------------------------
// HELPER: Check Basic Auth
// -------------------------------------------------------------
function CheckBasicAuth(Req: TRequest; Res: TResponse): Boolean;
var
  AuthHeader, DecodedStr, ReqUser, ReqPass: string;
  SplitPos: Integer;
begin
  Result := False;
  AuthHeader := Req.Authorization;
  
  if Pos('Basic ', AuthHeader) = 1 then
  begin
    AuthHeader := Copy(AuthHeader, 7, Length(AuthHeader));
    DecodedStr := DecodeStringBase64(AuthHeader);
    SplitPos := Pos(':', DecodedStr);
    if SplitPos > 0 then
    begin
      ReqUser := Copy(DecodedStr, 1, SplitPos - 1);
      ReqPass := Copy(DecodedStr, SplitPos + 1, Length(DecodedStr));
      if (ReqUser = AppCfg.AdminUser) and (ReqPass = AppCfg.AdminPass) then
        Result := True;
    end;
  end;

  if not Result then
  begin
    Res.Code := 401;
    Res.SetCustomHeader('WWW-Authenticate', 'Basic realm="RADIUS Admin Panel"');
    Res.ContentType := 'text/plain; charset=utf-8';
    Res.Content := 'Unauthorized Access';
    Res.SendContent;
  end;
end;

// -------------------------------------------------------------
// HELPER: Connect to DB
// -------------------------------------------------------------
function GetDBConn(out Conn: TMySQL80Connection; out Trans: TSQLTransaction): Boolean;
begin
  Result := False;
  Conn := TMySQL80Connection.Create(nil);
  Trans := TSQLTransaction.Create(nil);
  try
    Conn.HostName := AppCfg.DBHost;
    Conn.UserName := AppCfg.DBUser;
    Conn.Password := AppCfg.DBPass;
    Conn.DatabaseName := AppCfg.DBName;
    Conn.CharSet := 'utf8mb4';
    Conn.Transaction := Trans;
    Conn.Connected := True;
    Result := True;
  except
    Conn.Free;
    Trans.Free;
    Conn := nil;
    Trans := nil;
  end;
end;

procedure SendJSONResponse(Res: TResponse; JObj: TJSONObject);
begin
  Res.Code := 200;
  Res.ContentType := 'application/json; charset=utf-8';
  Res.Content := JObj.AsJSON;
  Res.SendContent;
  JObj.Free;
end;

procedure SendJSONErrorMsg(Res: TResponse; ErrorMsg: string);
var
  J: TJSONObject;
begin
  J := TJSONObject.Create;
  J.Add('success', False);
  J.Add('error', ErrorMsg);
  SendJSONResponse(Res, J);
end;

procedure SendJSONSuccess(Res: TResponse);
var
  J: TJSONObject;
begin
  J := TJSONObject.Create;
  J.Add('success', True);
  SendJSONResponse(Res, J);
end;

// -------------------------------------------------------------
// GET /sso/admin
// -------------------------------------------------------------
procedure HandleAdminHtml(Req: TRequest; Res: TResponse);
var
  TemplatePath: string;
  HtmlContent: string;
begin
  if not CheckBasicAuth(Req, Res) then Exit;

  TemplatePath := ExtractFilePath(ParamStr(0)) + 'templates/admin.html';
  if FileExists(TemplatePath) then
  begin
    with TStringList.Create do
    try
      LoadFromFile(TemplatePath);
      HtmlContent := Text;
    finally
      Free;
    end;
    Res.Code := 200;
    Res.ContentType := 'text/html; charset=utf-8';
    Res.Content := HtmlContent;
    Res.SendContent;
  end
  else
    SendJSONError(Res, 404, 'Admin template not found at: ' + TemplatePath);
end;

// -------------------------------------------------------------
// GET / POST /sso/api/license
// -------------------------------------------------------------
procedure HandleApiLicense(Req: TRequest; Res: TResponse);
var
  JObj: TJSONObject;
  LicText: string;
  F: TextFile;
begin
  if not CheckBasicAuth(Req, Res) then Exit;

  if Req.Method = 'GET' then
  begin
    JObj := TJSONObject.Create;
    JObj.Add('machine_id', GetMachineID);
    JObj.Add('demo_mode', DemoModeActive);
    JObj.Add('license_path', GlobalLicensePath);
    
    if not DemoModeActive then
    begin
      JObj.Add('serial', GlobalLicenseInfo.Serial);
      JObj.Add('licensee', GlobalLicenseInfo.Licensee);
      JObj.Add('issued', GlobalLicenseInfo.IssuedDate);
      JObj.Add('expiry', GlobalLicenseInfo.ExpiryDate);
      JObj.Add('features', GlobalLicenseInfo.Features);
      JObj.Add('max_users', GlobalLicenseInfo.MaxUsers);
    end;
    
    SendJSONResponse(Res, JObj);
    Exit;
  end;

  if Req.Method = 'POST' then
  begin
    LicText := Trim(Req.ContentFields.Values['license_text']);
    if LicText = '' then
    begin
      SendJSONErrorMsg(Res, 'License text is empty');
      Exit;
    end;
    
    // บันทึกไฟล์ทับของเดิม
    AssignFile(F, GlobalLicensePath);
    try
      Rewrite(F);
      Write(F, LicText);
      CloseFile(F);
    except
      on E: Exception do
      begin
        SendJSONErrorMsg(Res, 'Failed to save license file: ' + E.Message);
        Exit;
      end;
    end;
    
    // โหลด License ใหม่เข้าระบบ
    ReloadLicense;
    
    if DemoModeActive then
      SendJSONErrorMsg(Res, 'License saved but validation failed. Still in Demo Mode.')
    else
      SendJSONSuccess(Res);
      
    Exit;
  end;
end;

// -------------------------------------------------------------
// GET / POST /sso/api/users
// -------------------------------------------------------------
procedure HandleApiUsers(Req: TRequest; Res: TResponse);
var
  Conn: TMySQL80Connection;
  Trans: TSQLTransaction;
  Query: TSQLQuery;
  
  JArr: TJSONArray;
  JUser: TJSONObject;
  
  Action, Username, Password, Attr, IDStr, FirstName, LastName, Department, Email, MobilePhone: string;
begin
  if not CheckBasicAuth(Req, Res) then Exit;

  if not GetDBConn(Conn, Trans) then
  begin
    SendJSONErrorMsg(Res, 'Database connection failed');
    Exit;
  end;
  Query := TSQLQuery.Create(nil);
  Query.DataBase := Conn;

  try
    // === GET (LIST USERS) ===
    if Req.Method = 'GET' then
    begin
      Query.SQL.Text := 'SELECT r.id, r.username, r.value, r.attribute, u.firstname, u.lastname, u.department, u.email, u.mobilephone ' +
                        'FROM radcheck r LEFT JOIN userinfo u ON r.username = u.username ' +
                        'WHERE r.attribute IN (''Cleartext-Password'', ''Suspended-Password'', ''MD5-Password'') ORDER BY r.id DESC';
      Query.Open;
      
      JArr := TJSONArray.Create;
      while not Query.EOF do
      begin
        JUser := TJSONObject.Create;
        JUser.Add('id', Query.FieldByName('id').AsInteger);
        JUser.Add('username', Query.FieldByName('username').AsString);
        JUser.Add('value', Query.FieldByName('value').AsString);
        JUser.Add('attribute', Query.FieldByName('attribute').AsString);
        JUser.Add('firstname', Query.FieldByName('firstname').AsString);
        JUser.Add('lastname', Query.FieldByName('lastname').AsString);
        JUser.Add('department', Query.FieldByName('department').AsString);
        JUser.Add('email', Query.FieldByName('email').AsString);
        JUser.Add('mobilephone', Query.FieldByName('mobilephone').AsString);
        JArr.Add(JUser);
        Query.Next;
      end;
      Query.Close;
      
      Res.Code := 200;
      Res.ContentType := 'application/json; charset=utf-8';
      Res.Content := JArr.AsJSON;
      Res.SendContent;
      JArr.Free;
      Exit;
    end;

    // === POST (CRUD) ===
    if Req.Method = 'POST' then
    begin
      Action := Req.ContentFields.Values['action'];
      IDStr := Req.ContentFields.Values['id'];
      Username := Trim(Req.ContentFields.Values['username']);
      Password := Trim(Req.ContentFields.Values['password']);
      Attr := Req.ContentFields.Values['attribute'];
      FirstName := Trim(Req.ContentFields.Values['firstname']);
      LastName := Trim(Req.ContentFields.Values['lastname']);
      Department := Trim(Req.ContentFields.Values['department']);
      Email := Trim(Req.ContentFields.Values['email']);
      MobilePhone := Trim(Req.ContentFields.Values['mobilephone']);
      
      if Action = 'add' then
      begin
        if (Username = '') or (Password = '') then
        begin
          SendJSONErrorMsg(Res, 'Missing data');
          Exit;
        end;

        // ตรวจสอบว่ามี Username อยู่แล้วหรือไม่
        Query.SQL.Text := 'SELECT id FROM radcheck WHERE username = :u';
        Query.ParamByName('u').AsString := Username;
        Query.Open;
        if not Query.EOF then
        begin
          Query.Close;
          SendJSONErrorMsg(Res, 'Username already exists.');
          Exit;
        end;
        Query.Close;

        // Insert radcheck ด้วย Parameterized Query ป้องกัน SQL Injection
        Query.SQL.Text := 'INSERT INTO radcheck (username, attribute, op, value) VALUES (:u, ''Cleartext-Password'', ''=='', :v)';
        Query.ParamByName('u').AsString := Username;
        Query.ParamByName('v').AsString := Password;
        Query.ExecSQL;

        // Insert userinfo ด้วย Parameterized Query
        Query.SQL.Text := 'INSERT INTO userinfo (username, firstname, lastname, department, email, mobilephone, creationdate) ' +
                          'VALUES (:u, :fn, :ln, :dep, :em, :mp, NOW())';
        Query.ParamByName('u').AsString := Username;
        Query.ParamByName('fn').AsString := FirstName;
        Query.ParamByName('ln').AsString := LastName;
        Query.ParamByName('dep').AsString := Department;
        Query.ParamByName('em').AsString := Email;
        Query.ParamByName('mp').AsString := MobilePhone;
        Query.ExecSQL;

        Trans.Commit;
        SendJSONSuccess(Res);
        Exit;
      end;
      
      if Action = 'edit' then
      begin
        if IDStr = '' then
        begin
          SendJSONErrorMsg(Res, 'Missing data');
          Exit;
        end;

        // อัปเดต radcheck ด้วย Parameterized Query ป้องกัน SQL Injection
        if Password <> '' then
        begin
          Query.SQL.Text := 'UPDATE radcheck SET attribute = ''Cleartext-Password'', value = :v WHERE id = :id';
          Query.ParamByName('v').AsString := Password;
          Query.ParamByName('id').AsInteger := StrToIntDef(IDStr, 0);
          Query.ExecSQL;
        end;

        // ตรวจสอบและ Upsert userinfo ด้วย Parameterized Query
        Query.SQL.Text := 'SELECT id FROM userinfo WHERE username = :u';
        Query.ParamByName('u').AsString := Username;
        Query.Open;
        if Query.EOF then
        begin
          Query.Close;
          Query.SQL.Text := 'INSERT INTO userinfo (username, firstname, lastname, department, email, mobilephone, creationdate) ' +
                            'VALUES (:u, :fn, :ln, :dep, :em, :mp, NOW())';
          Query.ParamByName('u').AsString := Username;
          Query.ParamByName('fn').AsString := FirstName;
          Query.ParamByName('ln').AsString := LastName;
          Query.ParamByName('dep').AsString := Department;
          Query.ParamByName('em').AsString := Email;
          Query.ParamByName('mp').AsString := MobilePhone;
          Query.ExecSQL;
        end
        else
        begin
          Query.Close;
          Query.SQL.Text := 'UPDATE userinfo SET firstname = :fn, lastname = :ln, department = :dep, ' +
                            'email = :em, mobilephone = :mp, updatedate = NOW() WHERE username = :u';
          Query.ParamByName('fn').AsString := FirstName;
          Query.ParamByName('ln').AsString := LastName;
          Query.ParamByName('dep').AsString := Department;
          Query.ParamByName('em').AsString := Email;
          Query.ParamByName('mp').AsString := MobilePhone;
          Query.ParamByName('u').AsString := Username;
          Query.ExecSQL;
        end;

        Trans.Commit;
        SendJSONSuccess(Res);
        Exit;
      end;
      
      if Action = 'delete' then
      begin
        if IDStr = '' then
        begin
          SendJSONErrorMsg(Res, 'Missing data');
          Exit;
        end;

        // ดึง username ก่อนลบ เพื่อลบ userinfo ด้วย Parameterized Query
        Query.SQL.Text := 'SELECT username FROM radcheck WHERE id = :id';
        Query.ParamByName('id').AsInteger := StrToIntDef(IDStr, 0);
        Query.Open;
        if not Query.EOF then
        begin
          Username := Query.FieldByName('username').AsString;
          Query.Close;
          Query.SQL.Text := 'DELETE FROM userinfo WHERE username = :u';
          Query.ParamByName('u').AsString := Username;
          Query.ExecSQL;
        end
        else
          Query.Close;

        // ลบ radcheck ด้วย Parameterized Query
        Query.SQL.Text := 'DELETE FROM radcheck WHERE id = :id';
        Query.ParamByName('id').AsInteger := StrToIntDef(IDStr, 0);
        Query.ExecSQL;

        Trans.Commit;
        SendJSONSuccess(Res);
        Exit;
      end;
      
      if Action = 'toggle_suspend' then
      begin
        if IDStr = '' then
        begin
          SendJSONErrorMsg(Res, 'Missing data');
          Exit;
        end;

        // สลับสถานะ Active/Suspended ด้วย Parameterized Query
        if Attr = 'Cleartext-Password' then
          Attr := 'Suspended-Password'
        else
          Attr := 'Cleartext-Password';

        Query.SQL.Text := 'UPDATE radcheck SET attribute = :attr WHERE id = :id';
        Query.ParamByName('attr').AsString := Attr;
        Query.ParamByName('id').AsInteger := StrToIntDef(IDStr, 0);
        Query.ExecSQL;

        Trans.Commit;
        SendJSONSuccess(Res);
        Exit;
      end;
      
      SendJSONErrorMsg(Res, 'Invalid action');
    end;
  finally
    Query.Free;
    Trans.Free;
    Conn.Free;
  end;
end;

// -------------------------------------------------------------
// API: Logs (/api/logs)
// -------------------------------------------------------------
procedure HandleApiLogs(Req: TRequest; Res: TResponse);
var
  Conn: TMySQL80Connection;
  Trans: TSQLTransaction;
  Query: TSQLQuery;
  RootObj: TJSONObject;
  LogsArr: TJSONArray;
  ItemObj: TJSONObject;
  LimitStr, MethodFilter, Search: string;
begin
  if not CheckBasicAuth(Req, Res) then Exit;

  if not GetDBConn(Conn, Trans) then
  begin
    SendJSONErrorMsg(Res, 'Database connection failed');
    Exit;
  end;

  Query := TSQLQuery.Create(nil);
  try
    Query.DataBase := Conn;
    Query.Transaction := Trans;

    LimitStr := Req.QueryFields.Values['limit'];
    if (LimitStr = '') or (StrToIntDef(LimitStr, 0) <= 0) then
      LimitStr := '100';

    MethodFilter := Req.QueryFields.Values['method'];
    Search := Req.QueryFields.Values['q'];

    Query.SQL.Text := 'SELECT id, username, fullname, event_type, ip_address, mac_address, user_agent, auth_method, event_time ' +
                      'FROM login_history WHERE 1=1 ';

    if MethodFilter <> '' then
      Query.SQL.Text := Query.SQL.Text + 'AND auth_method = ' + QuotedStr(MethodFilter) + ' ';

    if Search <> '' then
      Query.SQL.Text := Query.SQL.Text + 'AND (username LIKE ' + QuotedStr('%' + Search + '%') + ' OR fullname LIKE ' + QuotedStr('%' + Search + '%') + ') ';

    Query.SQL.Text := Query.SQL.Text + 'ORDER BY id DESC LIMIT ' + IntToStr(StrToIntDef(LimitStr, 100));
    Query.Open;

    LogsArr := TJSONArray.Create;
    while not Query.EOF do
    begin
      ItemObj := TJSONObject.Create;
      ItemObj.Add('id', Query.FieldByName('id').AsInteger);
      ItemObj.Add('username', Query.FieldByName('username').AsString);
      ItemObj.Add('fullname', Query.FieldByName('fullname').AsString);
      ItemObj.Add('event_type', Query.FieldByName('event_type').AsString);
      ItemObj.Add('ip_address', Query.FieldByName('ip_address').AsString);
      ItemObj.Add('mac_address', Query.FieldByName('mac_address').AsString);
      ItemObj.Add('user_agent', Query.FieldByName('user_agent').AsString);
      ItemObj.Add('auth_method', Query.FieldByName('auth_method').AsString);
      ItemObj.Add('event_time', FormatDateTime('yyyy-mm-dd hh:nn:ss', Query.FieldByName('event_time').AsDateTime));
      LogsArr.Add(ItemObj);
      Query.Next;
    end;

    RootObj := TJSONObject.Create;
    RootObj.Add('success', True);
    RootObj.Add('count', LogsArr.Count);
    RootObj.Add('logs', LogsArr);

    SendJSONResponse(Res, RootObj);
  finally
    Query.Free;
    Trans.Free;
    Conn.Free;
  end;
end;

initialization
  RegisterRoute('GET', '/admin', @HandleAdminHtml);
  RegisterRoute('GET', '/api/users', @HandleApiUsers);
  RegisterRoute('POST', '/api/users', @HandleApiUsers);
  RegisterRoute('GET', '/api/license', @HandleApiLicense);
  RegisterRoute('POST', '/api/license', @HandleApiLicense);
  RegisterRoute('GET', '/api/logs', @HandleApiLogs);

end.
