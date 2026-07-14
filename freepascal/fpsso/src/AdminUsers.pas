unit AdminUsers;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, HTTPDefs, fpHTTP, fpjson, jsonparser, Router, Config, 
  mysql80conn, sqldb, db, Base64;

procedure HandleAdminHtml(Req: TRequest; Res: TResponse);
procedure HandleApiUsers(Req: TRequest; Res: TResponse);

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
// GET / POST /sso/api/users
// -------------------------------------------------------------
procedure HandleApiUsers(Req: TRequest; Res: TResponse);
var
  Conn: TMySQL80Connection;
  Trans: TSQLTransaction;
  Query: TSQLQuery;
  
  JArr: TJSONArray;
  JUser: TJSONObject;
  
  Action, Username, Password, Attr, IDStr, FirstName, LastName, Department: string;
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
      Query.SQL.Text := 'SELECT r.id, r.username, r.value, r.attribute, u.firstname, u.lastname, u.department ' +
                        'FROM radcheck r LEFT JOIN userinfo u ON r.username = u.username ' +
                        'WHERE r.attribute IN (''Cleartext-Password'', ''Suspended-Password'') ORDER BY r.id DESC';
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
      
      if Action = 'add' then
      begin
        if (Username = '') or (Password = '') then
        begin
          SendJSONErrorMsg(Res, 'Missing data');
          Exit;
        end;
        
        // Check if exists
        Query.SQL.Text := 'SELECT id FROM radcheck WHERE username = :u';
        Query.ParamByName('u').AsString := Username;
        Query.Open;
        if not Query.EOF then
        begin
          SendJSONErrorMsg(Res, 'Username already exists.');
          Exit;
        end;
        Query.Close;
        
        // Insert
        Conn.ExecuteDirect('INSERT INTO radcheck (username, attribute, op, value) VALUES (' +
          QuotedStr(Username) + ', ''Cleartext-Password'', ''=='', ' + QuotedStr(Password) + ')');
        
        Conn.ExecuteDirect('INSERT INTO userinfo (username, firstname, lastname, department, creationdate) VALUES (' +
          QuotedStr(Username) + ', ' + QuotedStr(FirstName) + ', ' + QuotedStr(LastName) + ', ' + QuotedStr(Department) + ', NOW())');
        
        Trans.Commit;
        SendJSONSuccess(Res);
        Exit;
      end;
      
      if Action = 'edit' then
      begin
        if (IDStr = '') or (Password = '') then
        begin
          SendJSONErrorMsg(Res, 'Missing data');
          Exit;
        end;
        
        Conn.ExecuteDirect('UPDATE radcheck SET value = ' + QuotedStr(Password) + ' WHERE id = ' + IDStr);
        
        Query.SQL.Text := 'SELECT id FROM userinfo WHERE username = :u';
        Query.ParamByName('u').AsString := Username;
        Query.Open;
        if Query.EOF then
          Conn.ExecuteDirect('INSERT INTO userinfo (username, firstname, lastname, department, creationdate) VALUES (' +
            QuotedStr(Username) + ', ' + QuotedStr(FirstName) + ', ' + QuotedStr(LastName) + ', ' + QuotedStr(Department) + ', NOW())')
        else
          Conn.ExecuteDirect('UPDATE userinfo SET firstname = ' + QuotedStr(FirstName) + ', lastname = ' + QuotedStr(LastName) + 
            ', department = ' + QuotedStr(Department) + ', updatedate = NOW() WHERE username = ' + QuotedStr(Username));
        Query.Close;
        
        Trans.Commit;
        SendJSONSuccess(Res);
        Exit;
      end;
      
      if Action = 'delete' then
      begin
        if (IDStr = '') then
        begin
          SendJSONErrorMsg(Res, 'Missing data');
          Exit;
        end;
        
        Query.SQL.Text := 'SELECT username FROM radcheck WHERE id = ' + IDStr;
        Query.Open;
        if not Query.EOF then
        begin
          Username := Query.FieldByName('username').AsString;
          Conn.ExecuteDirect('DELETE FROM userinfo WHERE username = ' + QuotedStr(Username));
        end;
        Query.Close;
        
        Conn.ExecuteDirect('DELETE FROM radcheck WHERE id = ' + IDStr);
        Trans.Commit;
        SendJSONSuccess(Res);
        Exit;
      end;
      
      if Action = 'toggle_suspend' then
      begin
        if (IDStr = '') then
        begin
          SendJSONErrorMsg(Res, 'Missing data');
          Exit;
        end;
        
        if Attr = 'Cleartext-Password' then
          Attr := 'Suspended-Password'
        else
          Attr := 'Cleartext-Password';
          
        Conn.ExecuteDirect('UPDATE radcheck SET attribute = ' + QuotedStr(Attr) + ' WHERE id = ' + IDStr);
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

initialization
  RegisterRoute('GET', '/admin', @HandleAdminHtml);
  RegisterRoute('GET', '/api/users', @HandleApiUsers);
  RegisterRoute('POST', '/api/users', @HandleApiUsers);

end.
