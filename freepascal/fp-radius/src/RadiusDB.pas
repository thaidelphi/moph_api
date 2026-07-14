unit RadiusDB;

{$mode objfpc}{$H+}

interface

uses 
  SysUtils, md5, mysql80conn, sqldb, db, RadiusConfig;

function DBConnect(const Cfg: TRadiusConfig): Boolean;
procedure DBDisconnect;
function CheckUserPassword(const Username, Password: string): Boolean;
procedure LogAccessAttempt(const Username, NasIP: string; Accepted: Boolean; const Timestamp: TDateTime);
procedure LogAccounting(const SessionID, Username, NasIP: string; StatusType: Integer; SessionTime: LongWord);

var
  MySQLConn: TMySQL80Connection;
  SQLTrans: TSQLTransaction;

implementation

function DBConnect(const Cfg: TRadiusConfig): Boolean;
begin
  Result := False;
  try
    MySQLConn := TMySQL80Connection.Create(nil);
    SQLTrans := TSQLTransaction.Create(nil);
    
    MySQLConn.Transaction := SQLTrans;
    MySQLConn.HostName := Cfg.DBHost;
    MySQLConn.UserName := Cfg.DBUser;
    MySQLConn.Password := Cfg.DBPass;
    MySQLConn.DatabaseName := Cfg.DBName;
    MySQLConn.Port := Cfg.DBPort;
    
    MySQLConn.Connected := True;
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

procedure DBDisconnect;
begin
  if Assigned(MySQLConn) then
  begin
    MySQLConn.Connected := False;
    MySQLConn.Free;
  end;
  if Assigned(SQLTrans) then
    SQLTrans.Free;
end;

function CheckUserPassword(const Username, Password: string): Boolean;
var
  Query: TSQLQuery;
  DBPass: string;
begin
  Result := False;
  if not Assigned(MySQLConn) or not MySQLConn.Connected then Exit;

  Query := TSQLQuery.Create(nil);
  try
    Query.DataBase := MySQLConn;
    
    // Step 1: ตรวจสอบ radcheck_cleartext
    Query.SQL.Text := 'SELECT value FROM radcheck_cleartext WHERE username = :u AND value = :p LIMIT 1';
    Query.Params.ParamByName('u').AsString := Username;
    Query.Params.ParamByName('p').AsString := Password;
    Query.Open;
    
    if not Query.EOF then
    begin
      Result := True;
      Query.Close;
      Exit; 
    end;
    Query.Close;

    // Step 2: ตรวจสอบ radcheck ปกติ
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
    
  except
    on E: Exception do
      LogMsg(0, 'Error in CheckUserPassword: ' + E.Message);
  end;
  Query.Free;
end;

procedure LogAccessAttempt(const Username, NasIP: string; Accepted: Boolean; const Timestamp: TDateTime);
var
  Query: TSQLQuery;
begin
  if not Assigned(MySQLConn) or not MySQLConn.Connected then Exit;

  Query := TSQLQuery.Create(nil);
  try
    Query.DataBase := MySQLConn;
    Query.SQL.Text := 'INSERT INTO radius_access_log (username, nas_ip, accepted, login_time) VALUES (:u, :ip, :acc, :ts)';
    Query.Params.ParamByName('u').AsString := Username;
    Query.Params.ParamByName('ip').AsString := NasIP;
    if Accepted then Query.Params.ParamByName('acc').AsInteger := 1
    else Query.Params.ParamByName('acc').AsInteger := 0;
    Query.Params.ParamByName('ts').AsDateTime := Timestamp;
    
    Query.ExecSQL;
    SQLTrans.Commit;
  except
    on E: Exception do
    begin
      LogMsg(0, 'Error in LogAccessAttempt: ' + E.Message);
      SQLTrans.Rollback;
    end;
  end;
  Query.Free;
end;

procedure LogAccounting(const SessionID, Username, NasIP: string; StatusType: Integer; SessionTime: LongWord);
var
  Query: TSQLQuery;
begin
  if not Assigned(MySQLConn) or not MySQLConn.Connected then Exit;

  Query := TSQLQuery.Create(nil);
  try
    Query.DataBase := MySQLConn;
    Query.SQL.Text := 'INSERT INTO radius_acct_log (session_id, username, nas_ip, status_type, session_time, log_time) VALUES (:sid, :u, :ip, :st, :time, :ts)';
    Query.Params.ParamByName('sid').AsString := SessionID;
    Query.Params.ParamByName('u').AsString := Username;
    Query.Params.ParamByName('ip').AsString := NasIP;
    Query.Params.ParamByName('st').AsInteger := StatusType;
    Query.Params.ParamByName('time').AsInteger := SessionTime;
    Query.Params.ParamByName('ts').AsDateTime := Now;
    
    Query.ExecSQL;
    SQLTrans.Commit;
  except
    on E: Exception do
    begin
      LogMsg(0, 'Error in LogAccounting: ' + E.Message);
      SQLTrans.Rollback;
    end;
  end;
  Query.Free;
end;

end.
