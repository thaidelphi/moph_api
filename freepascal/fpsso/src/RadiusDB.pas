unit RadiusDB;

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, SysUtils, md5, mysql80conn, sqldb, db, Config;

// Equivalent to sso_radius_auth in PHP
function SSORadiusAuth(const Username: string; out IsActive: Boolean; const Email: string = ''; const Fullname: string = ''; const Address: string = ''): string;
function LocalRadiusAuth(const Username, Password: string; out IsActive: Boolean): string;

procedure EnsureDBSchema;
procedure LogAuthEvent(const Username, EventType, IPAddress, AuthMethod: string; const FullName: string = ''; const MacAddress: string = ''; const UserAgent: string = '');
function GetUserProfile(const Username: string; out FullName, Email, Phone: string): Boolean;
function UpdateUserProfile(const Username, FullName, Email, Phone, NewPassword: string): Boolean;
function FindUsernameByEmail(const Email: string): string;

implementation

function RandomString(Len: Integer): string;
const
  Chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$*()_-+=';
var
  I: Integer;
begin
  Result := '';
  SetLength(Result, Len);
  for I := 1 to Len do
    Result[I] := Chars[Random(Length(Chars)) + 1];
end;

procedure EnsureDBSchema;
var
  Conn: TMySQL80Connection;
  Trans: TSQLTransaction;
  Query: TSQLQuery;
begin
  Conn := TMySQL80Connection.Create(nil);
  Trans := TSQLTransaction.Create(nil);
  Query := TSQLQuery.Create(nil);
  try
    Conn.HostName := AppCfg.DBHost;
    Conn.UserName := AppCfg.DBUser;
    Conn.Password := AppCfg.DBPass;
    Conn.DatabaseName := AppCfg.DBName;
    Conn.CharSet := 'utf8mb4';
    Conn.Transaction := Trans;
    Query.DataBase := Conn;
    
    try
      Conn.Connected := True;
      Conn.ExecuteDirect('SET NAMES utf8mb4;');
      
      // Check if phone column exists
      Query.SQL.Text := 'SHOW COLUMNS FROM radcheck_mirror LIKE ''phone''';
      Query.Open;
      if Query.EOF then
      begin
        Query.Close;
        Query.SQL.Text := 'ALTER TABLE radcheck_mirror ADD COLUMN phone VARCHAR(20) DEFAULT NULL';
        Query.ExecSQL;
        Trans.Commit;
        Writeln('Database Schema: Added phone column to radcheck_mirror.');
      end
      else
        Query.Close;
        
      // Create login_history table if it doesn't exist
      Query.SQL.Text := 'CREATE TABLE IF NOT EXISTS login_history (' +
                        'id INT AUTO_INCREMENT PRIMARY KEY, ' +
                        'username VARCHAR(64) NOT NULL, ' +
                        'fullname VARCHAR(255) DEFAULT NULL, ' +
                        'event_type VARCHAR(20) NOT NULL, ' + // LOGIN or LOGOUT
                        'ip_address VARCHAR(45) NOT NULL, ' +
                        'mac_address VARCHAR(32) DEFAULT NULL, ' +
                        'user_agent VARCHAR(255) DEFAULT NULL, ' +
                        'auth_method VARCHAR(20) DEFAULT NULL, ' +
                        'event_time DATETIME NOT NULL' +
                        ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;';
      Query.ExecSQL;
      Trans.Commit;
      
      // Auto-add auth_method if missing (for existing tables)
      Query.Close;
      Query.SQL.Text := 'SHOW COLUMNS FROM login_history LIKE ''auth_method''';
      Query.Open;
      if Query.EOF then
      begin
        Query.Close;
        Query.SQL.Text := 'ALTER TABLE login_history ADD COLUMN auth_method VARCHAR(20) DEFAULT NULL';
        Query.ExecSQL;
        Trans.Commit;
      end
      else
        Query.Close;

      // Auto-add fullname if missing
      Query.SQL.Text := 'SHOW COLUMNS FROM login_history LIKE ''fullname''';
      Query.Open;
      if Query.EOF then
      begin
        Query.Close;
        Query.SQL.Text := 'ALTER TABLE login_history ADD COLUMN fullname VARCHAR(255) DEFAULT NULL';
        Query.ExecSQL;
        Trans.Commit;
      end
      else
        Query.Close;

      // Auto-add mac_address if missing
      Query.SQL.Text := 'SHOW COLUMNS FROM login_history LIKE ''mac_address''';
      Query.Open;
      if Query.EOF then
      begin
        Query.Close;
        Query.SQL.Text := 'ALTER TABLE login_history ADD COLUMN mac_address VARCHAR(32) DEFAULT NULL';
        Query.ExecSQL;
        Trans.Commit;
      end
      else
        Query.Close;

      // Auto-add user_agent if missing
      Query.SQL.Text := 'SHOW COLUMNS FROM login_history LIKE ''user_agent''';
      Query.Open;
      if Query.EOF then
      begin
        Query.Close;
        Query.SQL.Text := 'ALTER TABLE login_history ADD COLUMN user_agent VARCHAR(255) DEFAULT NULL';
        Query.ExecSQL;
        Trans.Commit;
      end
      else
        Query.Close;
        
    except
      on E: Exception do
        Writeln('EnsureDBSchema Error: ', E.Message);
    end;
  finally
    Query.Free;
    Trans.Free;
    Conn.Free;
  end;
end;

procedure LogAuthEvent(const Username, EventType, IPAddress, AuthMethod: string; const FullName: string = ''; const MacAddress: string = ''; const UserAgent: string = '');
var
  Conn: TMySQL80Connection;
  Trans: TSQLTransaction;
  Query: TSQLQuery;
begin
  if Username = '' then Exit;
  
  Conn := TMySQL80Connection.Create(nil);
  Trans := TSQLTransaction.Create(nil);
  Query := TSQLQuery.Create(nil);
  try
    Conn.HostName := AppCfg.DBHost;
    Conn.UserName := AppCfg.DBUser;
    Conn.Password := AppCfg.DBPass;
    Conn.DatabaseName := AppCfg.DBName;
    Conn.CharSet := 'utf8mb4';
    Conn.Transaction := Trans;
    Query.DataBase := Conn;
    
    try
      Conn.Connected := True;
      Conn.ExecuteDirect('SET NAMES utf8mb4;');
      Query.SQL.Text := 'INSERT INTO login_history (username, fullname, event_type, ip_address, mac_address, user_agent, auth_method, event_time) ' +
                        'VALUES (:u, :f, :e, :ip, :mac, :ua, :m, NOW())';
      Query.Params.ParamByName('u').AsString := Username;
      Query.Params.ParamByName('f').AsString := FullName;
      Query.Params.ParamByName('e').AsString := EventType;
      Query.Params.ParamByName('ip').AsString := IPAddress;
      Query.Params.ParamByName('mac').AsString := MacAddress;
      Query.Params.ParamByName('ua').AsString := UserAgent;
      Query.Params.ParamByName('m').AsString := AuthMethod;
      Query.ExecSQL;
      Trans.Commit;
    except
      on E: Exception do Writeln('LogAuthEvent Error: ', E.Message);
    end;
  finally
    Query.Free;
    Trans.Free;
    Conn.Free;
  end;
end;

function GetUserProfile(const Username: string; out FullName, Email, Phone: string): Boolean;
var
  Conn: TMySQL80Connection;
  Trans: TSQLTransaction;
  Query: TSQLQuery;
begin
  Result := False;
  FullName := ''; Email := ''; Phone := '';
  Conn := TMySQL80Connection.Create(nil);
  Trans := TSQLTransaction.Create(nil);
  Query := TSQLQuery.Create(nil);
  try
    Conn.HostName := AppCfg.DBHost;
    Conn.UserName := AppCfg.DBUser;
    Conn.Password := AppCfg.DBPass;
    Conn.DatabaseName := AppCfg.DBName;
    Conn.CharSet := 'utf8mb4';
    Conn.Transaction := Trans;
    Query.DataBase := Conn;
    
    try
      Conn.Connected := True;
      Conn.ExecuteDirect('SET NAMES utf8mb4;');
      Query.SQL.Text := 'SELECT fullname, email, phone FROM radcheck_mirror WHERE username = :u ORDER BY id DESC LIMIT 1';
      Query.Params.ParamByName('u').AsString := Username;
      Query.Open;
      if not Query.EOF then
      begin
        FullName := Query.FieldByName('fullname').AsString;
        Email := Query.FieldByName('email').AsString;
        Phone := Query.FieldByName('phone').AsString;
        Result := True;
      end;
    except
    end;
  finally
    Query.Free;
    Trans.Free;
    Conn.Free;
  end;
end;

function FindUsernameByEmail(const Email: string): string;
var
  Conn: TMySQL80Connection;
  Trans: TSQLTransaction;
  Query: TSQLQuery;
begin
  Result := '';
  if Email = '' then Exit;
  
  Conn := TMySQL80Connection.Create(nil);
  Trans := TSQLTransaction.Create(nil);
  Query := TSQLQuery.Create(nil);
  try
    Conn.HostName := AppCfg.DBHost;
    Conn.UserName := AppCfg.DBUser;
    Conn.Password := AppCfg.DBPass;
    Conn.DatabaseName := AppCfg.DBName;
    Conn.CharSet := 'utf8mb4';
    Conn.Transaction := Trans;
    Query.DataBase := Conn;
    
    try
      Conn.Connected := True;
      Conn.ExecuteDirect('SET NAMES utf8mb4;');
      Query.SQL.Text := 'SELECT username FROM radcheck_mirror WHERE email = :e LIMIT 1';
      Query.Params.ParamByName('e').AsString := Email;
      Query.Open;
      if not Query.EOF then
        Result := Query.FieldByName('username').AsString;
    except
    end;
  finally
    Query.Free;
    Trans.Free;
    Conn.Free;
  end;
end;

function UpdateUserProfile(const Username, FullName, Email, Phone, NewPassword: string): Boolean;
var
  Conn: TMySQL80Connection;
  Trans: TSQLTransaction;
  Query: TSQLQuery;
begin
  Result := False;
  Conn := TMySQL80Connection.Create(nil);
  Trans := TSQLTransaction.Create(nil);
  Query := TSQLQuery.Create(nil);
  try
    Conn.HostName := AppCfg.DBHost;
    Conn.UserName := AppCfg.DBUser;
    Conn.Password := AppCfg.DBPass;
    Conn.DatabaseName := AppCfg.DBName;
    Conn.CharSet := 'utf8mb4';
    Conn.Transaction := Trans;
    Query.DataBase := Conn;
    
    try
      Conn.Connected := True;
      Conn.ExecuteDirect('SET NAMES utf8mb4;');
      
      Query.SQL.Text := 'UPDATE radcheck_mirror SET fullname = :f, email = :e, phone = :p WHERE username = :u';
      Query.Params.ParamByName('f').AsString := FullName;
      Query.Params.ParamByName('e').AsString := Email;
      Query.Params.ParamByName('p').AsString := Phone;
      Query.Params.ParamByName('u').AsString := Username;
      Query.ExecSQL;
      
      if NewPassword <> '' then
      begin
        Query.SQL.Text := 'UPDATE radcheck_mirror SET tmp_passwd = :pw WHERE username = :u';
        Query.Params.ParamByName('pw').AsString := NewPassword;
        Query.Params.ParamByName('u').AsString := Username;
        Query.ExecSQL;
        
        // Update RADIUS cleartext password if applicable
        Query.SQL.Text := 'UPDATE radcheck_cleartext SET value = :pw WHERE username = :u';
        Query.Params.ParamByName('pw').AsString := NewPassword;
        Query.Params.ParamByName('u').AsString := Username;
        Query.ExecSQL;
        
        // Also update radcheck if it exists there (local users)
        Query.SQL.Text := 'UPDATE radcheck SET value = :pw WHERE username = :u AND attribute = ''Cleartext-Password''';
        Query.Params.ParamByName('pw').AsString := NewPassword;
        Query.Params.ParamByName('u').AsString := Username;
        Query.ExecSQL;
      end;
      
      Trans.Commit;
      Result := True;
    except
      if Trans.Active then Trans.Rollback;
    end;
  finally
    Query.Free;
    Trans.Free;
    Conn.Free;
  end;
end;

function LocalRadiusAuth(const Username, Password: string; out IsActive: Boolean): string;
var
  Conn: TMySQL80Connection;
  Trans: TSQLTransaction;
  Query: TSQLQuery;
  Attr, Val: string;
begin
  IsActive := True; // Default to true so unknown users get "Wrong password" instead of "Pending"
  Result := '';
  Conn := TMySQL80Connection.Create(nil);
  Trans := TSQLTransaction.Create(nil);
  Query := TSQLQuery.Create(nil);
  try
    Conn.HostName := AppCfg.DBHost;
    Conn.UserName := AppCfg.DBUser;
    Conn.Password := AppCfg.DBPass;
    Conn.DatabaseName := AppCfg.DBName;
    Conn.CharSet := 'utf8mb4';
    Conn.Transaction := Trans;
    Query.DataBase := Conn;
    
    try
      Conn.Connected := True;
      Conn.ExecuteDirect('SET NAMES utf8mb4;');
    except
      on E: Exception do Exit;
    end;
    
    // 1. Check in radcheck first (for manual users or approved SSO users)
    Query.SQL.Text := 'SELECT attribute, value FROM radcheck WHERE username = :u AND attribute IN (''Cleartext-Password'', ''MD5-Password'', ''Suspended-Password'') LIMIT 1';
    Query.Params.ParamByName('u').AsString := Username;
    Query.Open;
    
    if not Query.EOF then
    begin
      Attr := Query.FieldByName('attribute').AsString;
      Val := Query.FieldByName('value').AsString;
      Query.Close;
      
      if Attr = 'Suspended-Password' then
      begin
        IsActive := False; // User is suspended
        Exit;
      end;
      
      if (Attr = 'Cleartext-Password') and (Val = Password) then
      begin
        Result := Password;
        Exit;
      end;
      
      if (Attr = 'MD5-Password') and (LowerCase(Val) = LowerCase(MD5Print(MD5String(Password)))) then
      begin
        Result := Password;
        Exit;
      end;
    end
    else
      Query.Close;
      
    // 2. If not found or wrong password, check if they exist in radcheck_mirror as pending
    Query.SQL.Text := 'SELECT tmp_passwd, active FROM radcheck_mirror WHERE username = :u ORDER BY id DESC LIMIT 1';
    Query.Params.ParamByName('u').AsString := Username;
    Query.Open;
    
    if not Query.EOF then
    begin
      if Query.FieldByName('active').AsString = 'N' then
      begin
        IsActive := False; // Pending approval
      end
      else if Query.FieldByName('tmp_passwd').AsString = Password then
      begin
        Result := Password; // Match in mirror
      end;
    end;
    Query.Close;
    
  finally
    Query.Free;
    Trans.Free;
    Conn.Free;
  end;
end;

function SSORadiusAuth(const Username: string; out IsActive: Boolean; const Email: string = ''; const Fullname: string = ''; const Address: string = ''): string;
var
  Conn: TMySQL80Connection;
  Trans: TSQLTransaction;
  Query: TSQLQuery;
  NewPass, MD5Pass, DateReg, DateExp, ActiveStr: string;
begin
  IsActive := False;
  Result := '';
  Conn := TMySQL80Connection.Create(nil);
  Trans := TSQLTransaction.Create(nil);
  Query := TSQLQuery.Create(nil);
  try
    Conn.HostName := AppCfg.DBHost;
    Conn.UserName := AppCfg.DBUser;
    Conn.Password := AppCfg.DBPass;
    Conn.DatabaseName := AppCfg.DBName;
    Conn.CharSet := 'utf8mb4';
    Conn.Transaction := Trans;
    Query.DataBase := Conn;
    
    try
      Conn.Connected := True;
      Conn.ExecuteDirect('SET NAMES utf8mb4;');
    except
      on E: Exception do
      begin
        Writeln('RadiusDB Connection Error: ', E.Message);
        if (Pos('Can not load MySQL client', E.Message) > 0) or 
           (Pos('libmysqlclient', E.Message) > 0) then
        begin
          Writeln('====================================================');
          Writeln('ไลบรารี libmysqlclient ไม่ได้ถูกติดตั้งในระบบ!');
          Writeln('กรุณาติดตั้งด้วยคำสั่ง:');
          Writeln('sudo apt-get update && sudo apt-get install libmysqlclient-dev');
          Writeln('====================================================');
        end;
        Exit;
      end;
    end;
    
    // 1. ตรวจสอบว่ามี tmp_passwd ใน radcheck_mirror หรือไม่ (ดึงรายการล่าสุด)
    Query.SQL.Text := 'SELECT tmp_passwd, active FROM radcheck_mirror WHERE username = :u ORDER BY id DESC LIMIT 1';
    Query.Params.ParamByName('u').AsString := Username;
    Query.Open;
    
    if not Query.EOF then
    begin
      Result := Query.FieldByName('tmp_passwd').AsString;
      ActiveStr := UpperCase(Trim(Query.FieldByName('active').AsString));
      if AppCfg.SSOAutoApprove then
        IsActive := (ActiveStr <> 'N')
      else
        IsActive := (ActiveStr = 'Y');
      Query.Close;
      
      if Result <> '' then
      begin
        // อัปเดตข้อมูล fullname, address, email และ active ใน radcheck_mirror
        Query.SQL.Text := 'UPDATE radcheck_mirror SET ';
        if Fullname <> '' then
          Query.SQL.Text := Query.SQL.Text + 'fullname = :f, ';
        if Address <> '' then
          Query.SQL.Text := Query.SQL.Text + 'address = :addr, ';
        if Email <> '' then
          Query.SQL.Text := Query.SQL.Text + 'email = :e, ';
        if IsActive then
          Query.SQL.Text := Query.SQL.Text + 'active = ''Y'' '
        else
          Query.SQL.Text := Query.SQL.Text + 'active = ''N'' ';
        Query.SQL.Text := Query.SQL.Text + 'WHERE username = :u';

        if Fullname <> '' then
          Query.Params.ParamByName('f').AsString := Fullname;
        if Address <> '' then
          Query.Params.ParamByName('addr').AsString := Address;
        if Email <> '' then
          Query.Params.ParamByName('e').AsString := Email;
        Query.Params.ParamByName('u').AsString := Username;
        Query.ExecSQL;
        // ซิงค์ข้อมูลลง radcheck (MD5-Password) และ radcheck_cleartext เพื่อให้ RADIUS ตรวจสอบรหัสผ่านได้ตรงกัน
        if IsActive then
        begin
          MD5Pass := MD5Print(MD5String(Result));
          Query.SQL.Text := 'SELECT COUNT(*) as cnt FROM radcheck WHERE username = :u AND attribute = ''MD5-Password''';
          Query.Params.ParamByName('u').AsString := Username;
          Query.Open;
          if Query.FieldByName('cnt').AsInteger > 0 then
          begin
            Query.Close;
            Query.SQL.Text := 'UPDATE radcheck SET op = '':='', value = :v WHERE username = :u AND attribute = ''MD5-Password''';
            Query.Params.ParamByName('v').AsString := MD5Pass;
            Query.Params.ParamByName('u').AsString := Username;
            Query.ExecSQL;
          end
          else
          begin
            Query.Close;
            Query.SQL.Text := 'INSERT INTO radcheck (username, attribute, op, value) VALUES (:u, ''MD5-Password'', '':='', :v)';
            Query.Params.ParamByName('u').AsString := Username;
            Query.Params.ParamByName('v').AsString := MD5Pass;
            Query.ExecSQL;
          end;

          Query.SQL.Text := 'SELECT COUNT(*) as cnt FROM radcheck_cleartext WHERE username = :u';
          Query.Params.ParamByName('u').AsString := Username;
          Query.Open;
          if Query.FieldByName('cnt').AsInteger > 0 then
          begin
            Query.Close;
            Query.SQL.Text := 'UPDATE radcheck_cleartext SET value = :v WHERE username = :u';
            Query.Params.ParamByName('v').AsString := Result;
            Query.Params.ParamByName('u').AsString := Username;
            Query.ExecSQL;
          end
          else
          begin
            Query.Close;
            Query.SQL.Text := 'INSERT INTO radcheck_cleartext (username, attribute, op, value) VALUES (:u, ''Cleartext-Password'', '':='', :v)';
            Query.Params.ParamByName('u').AsString := Username;
            Query.Params.ParamByName('v').AsString := Result;
            Query.ExecSQL;
          end;
        end;

        Trans.Commit;
        Exit;
      end;
    end else
      Query.Close;
      
    // 2. หากไม่พบ สร้างรหัสผ่านใหม่
    NewPass := RandomString(8);
    MD5Pass := MD5Print(MD5String(NewPass));
    
    ActiveStr := 'Y';
    if not AppCfg.SSOAutoApprove then
      ActiveStr := 'N';
    IsActive := (ActiveStr = 'Y');
    
    // บันทึกใน radcheck และ radcheck_cleartext เฉพาะกรณี Active เท่านั้น
    if IsActive then
    begin
      // บันทึกใน radcheck (MD5-Password)
      Query.SQL.Text := 'SELECT COUNT(*) as cnt FROM radcheck WHERE username = :u AND attribute = ''MD5-Password''';
      Query.Params.ParamByName('u').AsString := Username;
      Query.Open;
      if Query.FieldByName('cnt').AsInteger > 0 then
      begin
        Query.Close;
        Query.SQL.Text := 'UPDATE radcheck SET op = '':='', value = :v WHERE username = :u AND attribute = ''MD5-Password''';
        Query.Params.ParamByName('v').AsString := MD5Pass;
        Query.Params.ParamByName('u').AsString := Username;
        Query.ExecSQL;
      end
      else
      begin
        Query.Close;
        Query.SQL.Text := 'INSERT INTO radcheck (username, attribute, op, value) VALUES (:u, ''MD5-Password'', '':='', :v)';
        Query.Params.ParamByName('u').AsString := Username;
        Query.Params.ParamByName('v').AsString := MD5Pass;
        Query.ExecSQL;
      end;

      // บันทึกใน radcheck_cleartext
      Query.SQL.Text := 'SELECT COUNT(*) as cnt FROM radcheck_cleartext WHERE username = :u';
      Query.Params.ParamByName('u').AsString := Username;
      Query.Open;
      if Query.FieldByName('cnt').AsInteger > 0 then
      begin
        Query.Close;
        Query.SQL.Text := 'UPDATE radcheck_cleartext SET value = :v WHERE username = :u';
        Query.Params.ParamByName('v').AsString := NewPass;
        Query.Params.ParamByName('u').AsString := Username;
        Query.ExecSQL;
      end
      else
      begin
        Query.Close;
        Query.SQL.Text := 'INSERT INTO radcheck_cleartext (username, attribute, op, value) VALUES (:u, ''Cleartext-Password'', '':='', :v)';
        Query.Params.ParamByName('u').AsString := Username;
        Query.Params.ParamByName('v').AsString := NewPass;
        Query.ExecSQL;
      end;
    end;
    
    // บันทึกใน radcheck_mirror
    DateReg := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now);
    DateExp := FormatDateTime('yyyy-mm-dd', Now) + ' 23:59:59';
    
    Query.SQL.Text := 'SELECT COUNT(*) as cnt FROM radcheck_mirror WHERE username = :u';
    Query.Params.ParamByName('u').AsString := Username;
    Query.Open;
    if Query.FieldByName('cnt').AsInteger > 0 then
    begin
      Query.Close;
      Query.SQL.Text := 'UPDATE radcheck_mirror SET tmp_passwd = :tp, attribute = ''MD5-Password'', op = '':='', value = :v, email = :e, fullname = :f, address = :addr, active = :a WHERE username = :u';
      Query.Params.ParamByName('tp').AsString := NewPass;
      Query.Params.ParamByName('v').AsString := MD5Pass;
      Query.Params.ParamByName('e').AsString := Email;
      Query.Params.ParamByName('f').AsString := Fullname;
      Query.Params.ParamByName('addr').AsString := Address;
      Query.Params.ParamByName('a').AsString := ActiveStr;
      Query.Params.ParamByName('u').AsString := Username;
      Query.ExecSQL;
    end
    else
    begin
      Query.Close;
      Query.SQL.Text := 'INSERT INTO radcheck_mirror (username, attribute, op, value, tmp_passwd, date_register, date_expire, note, active, email, fullname, address) ' +
                        'VALUES (:u, ''MD5-Password'', '':='', :v, :tp, :dreg, :dexp, ''Auto-generated by SSO Auth'', :a, :e, :f, :addr)';
      Query.Params.ParamByName('u').AsString := Username;
      Query.Params.ParamByName('v').AsString := MD5Pass;
      Query.Params.ParamByName('tp').AsString := NewPass;
      Query.Params.ParamByName('dreg').AsString := DateReg;
      Query.Params.ParamByName('dexp').AsString := DateExp;
      Query.Params.ParamByName('a').AsString := ActiveStr;
      Query.Params.ParamByName('e').AsString := Email;
      Query.Params.ParamByName('f').AsString := Fullname;
      Query.Params.ParamByName('addr').AsString := Address;
      Query.ExecSQL;
    end;
    
    Trans.Commit;
    Result := NewPass;
    
  finally
    Query.Free;
    Trans.Free;
    Conn.Free;
  end;
end;

initialization
  Randomize;

end.
