unit RadiusDB;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, md5, mysql80conn, sqldb, db, Config;

// Equivalent to sso_radius_auth in PHP
function SSORadiusAuth(const Username: string; const Email: string = ''; const Fullname: string = ''): string;

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

function SSORadiusAuth(const Username: string; const Email: string = ''; const Fullname: string = ''): string;
var
  Conn: TMySQL80Connection;
  Trans: TSQLTransaction;
  Query: TSQLQuery;
  NewPass, MD5Pass, DateReg, DateExp: string;
begin
  Result := '';
  Conn := TMySQL80Connection.Create(nil);
  Trans := TSQLTransaction.Create(nil);
  Query := TSQLQuery.Create(nil);
  try
    Conn.HostName := AppCfg.DBHost;
    Conn.UserName := AppCfg.DBUser;
    Conn.Password := AppCfg.DBPass;
    Conn.DatabaseName := AppCfg.DBName;
    Conn.Transaction := Trans;
    Query.DataBase := Conn;
    
    try
      Conn.Connected := True;
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
    
    // 1. ตรวจสอบว่ามี tmp_passwd ใน radcheck_mirror หรือไม่
    Query.SQL.Text := 'SELECT tmp_passwd FROM radcheck_mirror WHERE username = :u LIMIT 1';
    Query.Params.ParamByName('u').AsString := Username;
    Query.Open;
    
    if not Query.EOF then
    begin
      Result := Query.FieldByName('tmp_passwd').AsString;
      Query.Close;
      
      if Result <> '' then
      begin
        // อัปเดตข้อมูล email และ fullname ใน radcheck_mirror
        Query.SQL.Text := 'UPDATE radcheck_mirror SET email = :e, fullname = :f WHERE username = :u';
        Query.Params.ParamByName('e').AsString := Email;
        Query.Params.ParamByName('f').AsString := Fullname;
        Query.Params.ParamByName('u').AsString := Username;
        Query.ExecSQL;

        // ซิงค์ข้อมูลลง radcheck_cleartext เพื่อใช้กับ RADIUS
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

        Trans.Commit;
        Exit;
      end;
    end else
      Query.Close;
      
    // 2. หากไม่พบ สร้างรหัสผ่านใหม่
    NewPass := RandomString(8);
    MD5Pass := MD5Print(MD5String(NewPass));
    
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
    
    // บันทึกใน radcheck_mirror
    DateReg := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now);
    DateExp := FormatDateTime('yyyy-mm-dd', Now) + ' 23:59:59';
    
    Query.SQL.Text := 'SELECT COUNT(*) as cnt FROM radcheck_mirror WHERE username = :u';
    Query.Params.ParamByName('u').AsString := Username;
    Query.Open;
    if Query.FieldByName('cnt').AsInteger > 0 then
    begin
      Query.Close;
      Query.SQL.Text := 'UPDATE radcheck_mirror SET tmp_passwd = :tp, attribute = ''MD5-Password'', op = '':='', value = :v, email = :e, fullname = :f WHERE username = :u';
      Query.Params.ParamByName('tp').AsString := NewPass;
      Query.Params.ParamByName('v').AsString := MD5Pass;
      Query.Params.ParamByName('e').AsString := Email;
      Query.Params.ParamByName('f').AsString := Fullname;
      Query.Params.ParamByName('u').AsString := Username;
      Query.ExecSQL;
    end
    else
    begin
      Query.Close;
      Query.SQL.Text := 'INSERT INTO radcheck_mirror (username, attribute, op, value, tmp_passwd, date_register, date_expire, note, active, email, fullname) ' +
                        'VALUES (:u, ''MD5-Password'', '':='', :v, :tp, :dreg, :dexp, ''Auto-generated by SSO Auth'', ''Y'', :e, :f)';
      Query.Params.ParamByName('u').AsString := Username;
      Query.Params.ParamByName('v').AsString := MD5Pass;
      Query.Params.ParamByName('tp').AsString := NewPass;
      Query.Params.ParamByName('dreg').AsString := DateReg;
      Query.Params.ParamByName('dexp').AsString := DateExp;
      Query.Params.ParamByName('e').AsString := Email;
      Query.Params.ParamByName('f').AsString := Fullname;
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
