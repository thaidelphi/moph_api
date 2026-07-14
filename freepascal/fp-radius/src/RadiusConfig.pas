unit RadiusConfig;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes;

type
  TRadiusConfig = record
    // การเชื่อมต่อฐานข้อมูล Radius MySQL
    DBHost     : string;
    DBPort     : Word;
    DBUser     : string;
    DBPass     : string;
    DBName     : string;

    // การตั้งค่า RADIUS Server
    RadiusPort     : Word;    // default 1812
    AcctPort       : Word;    // default 1813
    SharedSecret   : string;  // ต้องตรงกับที่ตั้งบน FortiGate

    // Logging
    LogFile    : string;
    LogLevel   : Integer;     // 0=Error, 1=Info, 2=Debug
  end;

// โหลดค่าจากไฟล์ .env
function LoadConfig(const EnvPath: string): TRadiusConfig;
procedure LogMsg(const Level: Integer; const Msg: string);

var
  GlobalLogLevel: Integer = 1;
  GlobalLogFile: string = '';

implementation

function LoadConfig(const EnvPath: string): TRadiusConfig;
var
  Lines: TStringList;
  i: Integer;
  Line, Key, Value: string;
  PosEq: Integer;
begin
  // ค่าเริ่มต้น (Default values)
  Result.DBHost := '127.0.0.1';
  Result.DBPort := 3306;
  Result.DBUser := 'root';
  Result.DBPass := '';
  Result.DBName := 'radius';
  Result.RadiusPort := 1812;
  Result.AcctPort := 1813;
  Result.SharedSecret := 'testing123';
  Result.LogFile := '/var/log/fp-radius.log';
  Result.LogLevel := 1;

  if not FileExists(EnvPath) then
  begin
    LogMsg(0, 'Config file not found: ' + EnvPath + '. Using default values.');
    Exit;
  end;

  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(EnvPath);
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[i]);
      if (Line = '') or (Line[1] = '#') then Continue;

      PosEq := Pos('=', Line);
      if PosEq > 0 then
      begin
        Key := Trim(Copy(Line, 1, PosEq - 1));
        Value := Trim(Copy(Line, PosEq + 1, Length(Line) - PosEq));
        
        // Remove quotes if present
        if (Length(Value) >= 2) and 
           (((Value[1] = '"') and (Value[Length(Value)] = '"')) or 
            ((Value[1] = '''') and (Value[Length(Value)] = ''''))) then
          Value := Copy(Value, 2, Length(Value) - 2);

        if Key = 'DB_HOST' then Result.DBHost := Value
        else if Key = 'DB_PORT' then Result.DBPort := StrToIntDef(Value, 3306)
        else if (Key = 'DB_USERNAME') or (Key = 'DB_USER') then Result.DBUser := Value
        else if (Key = 'DB_PASSWORD') or (Key = 'DB_PASS') then Result.DBPass := Value
        else if (Key = 'DB_DATABASE') or (Key = 'DB_NAME') then Result.DBName := Value
        else if Key = 'RADIUS_PORT' then Result.RadiusPort := StrToIntDef(Value, 1812)
        else if Key = 'RADIUS_ACCT_PORT' then Result.AcctPort := StrToIntDef(Value, 1813)
        else if Key = 'RADIUS_SECRET' then Result.SharedSecret := Value
        else if Key = 'RADIUS_LOG_FILE' then Result.LogFile := Value
        else if Key = 'RADIUS_LOG_LEVEL' then Result.LogLevel := StrToIntDef(Value, 1);
      end;
    end;
  finally
    Lines.Free;
  end;
  
  GlobalLogLevel := Result.LogLevel;
  GlobalLogFile := Result.LogFile;
end;

procedure LogMsg(const Level: Integer; const Msg: string);
var
  LogText: string;
  F: TextFile;
begin
  if Level > GlobalLogLevel then Exit;

  LogText := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' ';
  case Level of
    0: LogText := LogText + '[ERROR] ';
    1: LogText := LogText + '[INFO] ';
    2: LogText := LogText + '[DEBUG] ';
  else
    LogText := LogText + '[LOG] ';
  end;
  
  LogText := LogText + Msg;
  WriteLn(LogText); // Output to standard output

  if GlobalLogFile <> '' then
  begin
    try
      AssignFile(F, GlobalLogFile);
      if FileExists(GlobalLogFile) then
        Append(F)
      else
        Rewrite(F);
      WriteLn(F, LogText);
      CloseFile(F);
    except
      // Ignore file write errors so it doesn't crash the server
    end;
  end;
end;

end.
