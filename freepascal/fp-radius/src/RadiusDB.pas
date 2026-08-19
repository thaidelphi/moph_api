unit RadiusDB;

{$mode objfpc}{$H+}

interface

uses 
  SysUtils, md5, mysql80conn, sqldb, db, RadiusConfig;

function DBConnect(const Cfg: TRadiusConfig; out Conn: TMySQL80Connection): Boolean;
procedure DBDisconnect(var Conn: TMySQL80Connection);
function CheckUserPassword(Conn: TMySQL80Connection; const Username, Password: string; SSOAutoApprove: Boolean = True): Boolean;
procedure LogAccessAttempt(Conn: TMySQL80Connection; const Username, NasIP: string; Accepted: Boolean; const Timestamp: TDateTime);
procedure LogAccounting(Conn: TMySQL80Connection; const SessionID, Username, NasIP: string; StatusType: Integer; SessionTime: LongWord);

implementation

var
  DBInitialized: Boolean = False;

function DBConnect(const Cfg: TRadiusConfig; out Conn: TMySQL80Connection): Boolean;
var
  Trans: TSQLTransaction;
begin
  Result := False;
  Conn := nil;
  try
    Conn := TMySQL80Connection.Create(nil);
    Trans := TSQLTransaction.Create(nil);
    
    Conn.Transaction := Trans;
    Conn.HostName := Cfg.DBHost;
    Conn.UserName := Cfg.DBUser;
    Conn.Password := Cfg.DBPass;
    Conn.DatabaseName := Cfg.DBName;
    Conn.Port := Cfg.DBPort;
    
    Conn.Connected := True;
    
    // Auto-create necessary missing log tables if they don't exist
    // This will only run once during the main thread's initial connection test
    if not DBInitialized then
    begin
      DBInitialized := True;
      try
        Conn.ExecuteDirect('CREATE TABLE IF NOT EXISTS radius_access_log (id BIGINT AUTO_INCREMENT PRIMARY KEY, username VARCHAR(255), nas_ip VARCHAR(50), accepted TINYINT(1), login_time DATETIME) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci');
        Conn.ExecuteDirect('CREATE TABLE IF NOT EXISTS radius_acct_log (id BIGINT AUTO_INCREMENT PRIMARY KEY, session_id VARCHAR(255), username VARCHAR(255), nas_ip VARCHAR(50), status_type INT, session_time INT, log_time DATETIME) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci');
        
        // Auto-insert default test user if it doesn't exist
        Conn.ExecuteDirect('INSERT INTO radcheck (username, attribute, op, value) SELECT ''test'', ''Cleartext-Password'', ''=='', ''test01'' FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM radcheck WHERE username = ''test'') LIMIT 1');
        Conn.ExecuteDirect('INSERT INTO userinfo (username, firstname, lastname, creationdate) SELECT ''test'', ''Test'', ''User'', NOW() FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM userinfo WHERE username = ''test'') LIMIT 1');
        
        Trans.Commit;
      except
        on E: Exception do
        begin
          LogMsg(0, 'Failed to initialize log tables: ' + E.Message);
          Trans.Rollback;
        end;
      end;
    end;

    Result := True;
    LogMsg(1, 'Connected to database ' + Cfg.DBName + ' at ' + Cfg.DBHost);
  except
    on E: Exception do
    begin
      LogMsg(0, 'Database connection failed: ' + E.Message);
      if (Pos('Can not load MySQL client', E.Message) > 0) or 
         (Pos('libmysqlclient', E.Message) > 0) then
      begin
        LogMsg(0, '====================================================');
        LogMsg(0, 'ไลบรารี libmysqlclient ไม่ได้ถูกติดตั้งในระบบ!');
        LogMsg(0, 'กรุณาติดตั้งด้วยคำสั่ง:');
        LogMsg(0, 'sudo apt-get update && sudo apt-get install libmysqlclient-dev');
        LogMsg(0, '====================================================');
      end;
    end;
  end;
end;

procedure DBDisconnect(var Conn: TMySQL80Connection);
var
  Trans: TSQLTransaction;
begin
  if Assigned(Conn) then
  begin
    Trans := Conn.Transaction as TSQLTransaction;
    Conn.Connected := False;
    Conn.Free;
    Conn := nil;
    if Assigned(Trans) then
      Trans.Free;
  end;
end;

function CheckUserPassword(Conn: TMySQL80Connection; const Username, Password: string; SSOAutoApprove: Boolean = True): Boolean;
var
  Query: TSQLQuery;
  DBPass, ActiveStr: string;
  IsOAuthUser: Boolean;
  I: Integer;
begin
  Result := False;
  if not Assigned(Conn) then Exit;

  if not Conn.Connected then
  begin
    try
      Conn.Connected := True;
    except
      on E: Exception do
      begin
        LogMsg(0, 'DB Reconnect failed in CheckUserPassword: ' + E.Message);
        Exit;
      end;
    end;
  end;

  // ตรวจสอบว่า username เป็นตัวเลขล้วน (ThaID, ProviderID = เลขบัตรประชาชน)
  // ถ้าใช่ → ตรวจแค่ว่า active ใน radcheck_mirror ไม่ใช่ N ก็ Accept ทันที
  // เพราะการยืนยันตัวตนผ่าน ThaID OAuth แล้ว FortiGate แค่ต้องการ Accept
  IsOAuthUser := (Length(Username) >= 8);
  if IsOAuthUser then
    for I := 1 to Length(Username) do
      if not (Username[I] in ['0'..'9']) then
      begin
        IsOAuthUser := False;
        Break;
      end;

  Query := TSQLQuery.Create(nil);
  try
    Query.DataBase := Conn;

    if IsOAuthUser then
    begin
      // ThaID/OAuth user (username เลขล้วน):
      // SSO_AUTO_APPROVE=true: ตรวจแค่ว่า user มีอยู่ใน radcheck_mirror ก็ Accept
      // SSO_AUTO_APPROVE=false: ตรวจ active ด้วย ถ้า active=N ให้ Reject
      Query.SQL.Text := 'SELECT active FROM radcheck_mirror WHERE username = :u LIMIT 1';
      Query.Params.ParamByName('u').AsString := Username;
      Query.Open;
      if not Query.EOF then
      begin
        ActiveStr := UpperCase(Trim(Query.FieldByName('active').AsString));
        if (not SSOAutoApprove) and (ActiveStr = 'N') then
        begin
          Query.Close;
          LogMsg(1, 'ThaID/OAuth Reject: ' + Username + ' (active=N, SSOAutoApprove=false)');
          Result := False;
        end
        else
        begin
          Query.Close;
          Result := True;
          LogMsg(1, 'ThaID/OAuth Accept: ' + Username + ' (active=' + ActiveStr + ')');
        end;
      end
      else
      begin
        // ไม่พบใน radcheck_mirror เลย → fallback ตรวจ Cleartext-Password
        LogMsg(1, Username + ' not in radcheck_mirror, fallback to radcheck');
        Query.SQL.Text := 'SELECT value FROM radcheck WHERE username = :u AND attribute = ''Cleartext-Password'' LIMIT 1';
        Query.Params.ParamByName('u').AsString := Username;
        Query.Open;
        if not Query.EOF then
          Result := (Query.FieldByName('value').AsString = Password);
        Query.Close;
      end;
    end
    else
    begin
      // Local user: ตรวจสอบ Cleartext-Password หรือ MD5-Password จาก radcheck ปกติ
      // SSO_AUTO_APPROVE=false: ตรวจ radcheck_mirror.active ก่อน ถ้า active=N ให้ Reject ทันที
      if not SSOAutoApprove then
      begin
        Query.SQL.Text := 'SELECT active FROM radcheck_mirror WHERE username = :u ORDER BY id DESC LIMIT 1';
        Query.Params.ParamByName('u').AsString := Username;
        Query.Open;
        if not Query.EOF then
        begin
          ActiveStr := UpperCase(Trim(Query.FieldByName('active').AsString));
          if ActiveStr = 'N' then
          begin
            Query.Close;
            LogMsg(1, 'Local User Reject: ' + Username + ' (active=N, SSOAutoApprove=false)');
            Exit; // Result ยังเป็น False
          end;
        end;
        Query.Close;
      end;

      // ตรวจสอบ Password จาก radcheck
      Query.SQL.Text := 'SELECT attribute, value FROM radcheck WHERE username = :u';
      Query.Params.ParamByName('u').AsString := Username;
      Query.Open;
      while not Query.EOF do
      begin
        if Query.FieldByName('attribute').AsString = 'Cleartext-Password' then
        begin
          if Query.FieldByName('value').AsString = Password then
          begin
            Result := True;
            Break;
          end;
        end
        else if Query.FieldByName('attribute').AsString = 'MD5-Password' then
        begin
          DBPass := Query.FieldByName('value').AsString;
          if LowerCase(DBPass) = LowerCase(MD5Print(MD5String(Password))) then
          begin
            Result := True;
            Break;
          end;
        end;
        Query.Next;
      end;
      Query.Close;
    end;

    if Assigned(Conn.Transaction) and Conn.Transaction.Active then
      (Conn.Transaction as TSQLTransaction).Commit;

  except
    on E: Exception do
    begin
      LogMsg(0, 'Error in CheckUserPassword: ' + E.Message);
      if Assigned(Conn.Transaction) and Conn.Transaction.Active then
        (Conn.Transaction as TSQLTransaction).Rollback;
    end;
  end;
  Query.Free;
end;


procedure LogAccessAttempt(Conn: TMySQL80Connection; const Username, NasIP: string; Accepted: Boolean; const Timestamp: TDateTime);
var
  Query: TSQLQuery;
begin
  if not Assigned(Conn) then Exit;
  if not Conn.Connected then
  begin
    try
      Conn.Connected := True;
    except
      Exit;
    end;
  end;

  Query := TSQLQuery.Create(nil);
  try
    Query.DataBase := Conn;
    Query.SQL.Text := 'INSERT INTO radius_access_log (username, nas_ip, accepted, login_time) VALUES (:u, :ip, :acc, :ts)';
    Query.Params.ParamByName('u').AsString := Username;
    Query.Params.ParamByName('ip').AsString := NasIP;
    if Accepted then Query.Params.ParamByName('acc').AsInteger := 1
    else Query.Params.ParamByName('acc').AsInteger := 0;
    Query.Params.ParamByName('ts').AsDateTime := Timestamp;
    
    Query.ExecSQL;
    if Assigned(Conn.Transaction) and Conn.Transaction.Active then
      (Conn.Transaction as TSQLTransaction).Commit;
  except
    on E: Exception do
    begin
      LogMsg(0, 'Error in LogAccessAttempt: ' + E.Message);
      if Assigned(Conn.Transaction) and Conn.Transaction.Active then
        (Conn.Transaction as TSQLTransaction).Rollback;
    end;
  end;
  Query.Free;
end;

procedure LogAccounting(Conn: TMySQL80Connection; const SessionID, Username, NasIP: string; StatusType: Integer; SessionTime: LongWord);
var
  Query: TSQLQuery;
begin
  if not Assigned(Conn) or not Conn.Connected then Exit;

  Query := TSQLQuery.Create(nil);
  try
    Query.DataBase := Conn;
    Query.SQL.Text := 'INSERT INTO radius_acct_log (session_id, username, nas_ip, status_type, session_time, log_time) VALUES (:sid, :u, :ip, :st, :time, :ts)';
    Query.Params.ParamByName('sid').AsString := SessionID;
    Query.Params.ParamByName('u').AsString := Username;
    Query.Params.ParamByName('ip').AsString := NasIP;
    Query.Params.ParamByName('st').AsInteger := StatusType;
    Query.Params.ParamByName('time').AsInteger := SessionTime;
    Query.Params.ParamByName('ts').AsDateTime := Now;
    
    Query.ExecSQL;
    Conn.Transaction.Commit;
  except
    on E: Exception do
    begin
      LogMsg(0, 'Error in LogAccounting: ' + E.Message);
      Conn.Transaction.Rollback;
    end;
  end;
  Query.Free;
end;

end.
