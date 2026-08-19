unit SessionMgr;

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses
  Classes, SysUtils, syncobjs, fgl, License;

type
  TSessionData = record
    Username: string;
    FullName: string;
    Email: string;
    Phone: string;
    AuthMethod: string;
    // FortiGate handshake data
    Magic: string;
    RedirUrl: string;
    PostUrl: string;
    UserMac: string;
    ClientIP: string;

    // Auto-login credential (ล้างหลัง Handshake สำเร็จเพื่อความปลอดภัย)
    PlainPass: string;

    // OAuth2 State Token สำหรับป้องกัน CSRF Attack
    OAuthState: string;

    CreatedAt: TDateTime;
    LastAccessed: TDateTime;
  end;

  TSessionMap = specialize TFPGMap<string, TSessionData>;

  TSessionManager = class
  private
    FMap: TSessionMap;
    FLock: TCriticalSection;
    function GenerateSessionID: string;
  public
    constructor Create;
    destructor Destroy; override;
    
    function CreateSession: string;
    function GetSession(const SessionID: string; out Data: TSessionData): Boolean;
    function FindSessionByIP(const ClientIP: string; out FoundSessionID: string; out Data: TSessionData): Boolean;
    procedure UpdateSession(const SessionID: string; const Data: TSessionData);
    procedure DeleteSession(const SessionID: string);
    procedure CleanupExpired(MaxAgeMinutes: Integer);
    
    // ตรวจสอบลิมิต Demo Mode
    function CheckAndRegisterLogin: Boolean;
  end;

var
  SessionManager: TSessionManager;
  LastLoginDate: TDate;
  DailyLoginCount: Integer;

implementation

{ TSessionManager }

constructor TSessionManager.Create;
begin
  FMap := TSessionMap.Create;
  FLock := TCriticalSection.Create;
end;

destructor TSessionManager.Destroy;
begin
  FMap.Free;
  FLock.Free;
  inherited Destroy;
end;

function TSessionManager.GenerateSessionID: string;
var
  Guid: TGuid;
begin
  CreateGUID(Guid);
  Result := StringReplace(GUIDToString(Guid), '{', '', [rfReplaceAll]);
  Result := StringReplace(Result, '}', '', [rfReplaceAll]);
  Result := StringReplace(Result, '-', '', [rfReplaceAll]);
end;

function TSessionManager.CreateSession: string;
var
  NewID: string;
  Data: TSessionData;
begin
  NewID := GenerateSessionID;
  Data.Username := '';
  Data.FullName := '';
  Data.Email := '';
  Data.Magic := '';
  Data.RedirUrl := '';
  Data.PostUrl := '';
  Data.PlainPass := '';
  Data.OAuthState := '';   // เริ่มต้น OAuthState เป็นว่าง
  Data.CreatedAt := Now;
  Data.LastAccessed := Now;

  FLock.Acquire;
  try
    FMap.Add(NewID, Data);
  finally
    FLock.Release;
  end;

  Result := NewID;
end;

function TSessionManager.GetSession(const SessionID: string; out Data: TSessionData): Boolean;
var
  Idx: Integer;
begin
  Result := False;
  FLock.Acquire;
  try
    Idx := FMap.IndexOf(SessionID);
    if Idx >= 0 then
    begin
      Data := FMap.Data[Idx];
      Data.LastAccessed := Now;
      FMap.Data[Idx] := Data;
      Result := True;
    end;
  finally
    FLock.Release;
  end;
end;

function TSessionManager.FindSessionByIP(const ClientIP: string; out FoundSessionID: string; out Data: TSessionData): Boolean;
var
  I, BestIdx: Integer;
  BestTime: TDateTime;
begin
  Result := False;
  FoundSessionID := '';
  BestIdx := -1;
  BestTime := 0;

  if ClientIP = '' then Exit;

  FLock.Acquire;
  try
    for I := 0 to FMap.Count - 1 do
    begin
      if (FMap.Data[I].ClientIP = ClientIP) and (FMap.Data[I].Username <> '') then
      begin
        if (BestIdx = -1) or (FMap.Data[I].LastAccessed > BestTime) then
        begin
          BestIdx := I;
          BestTime := FMap.Data[I].LastAccessed;
        end;
      end;
    end;

    if BestIdx >= 0 then
    begin
      FoundSessionID := FMap.Keys[BestIdx];
      Data := FMap.Data[BestIdx];
      Data.LastAccessed := Now;
      FMap.Data[BestIdx] := Data;
      Result := True;
    end;
  finally
    FLock.Release;
  end;
end;

procedure TSessionManager.UpdateSession(const SessionID: string; const Data: TSessionData);
var
  Idx: Integer;
begin
  FLock.Acquire;
  try
    Idx := FMap.IndexOf(SessionID);
    if Idx >= 0 then
    begin
      FMap.Data[Idx] := Data;
    end;
  finally
    FLock.Release;
  end;
end;

procedure TSessionManager.DeleteSession(const SessionID: string);
var
  Idx: Integer;
begin
  FLock.Acquire;
  try
    Idx := FMap.IndexOf(SessionID);
    if Idx >= 0 then
      FMap.Delete(Idx);
  finally
    FLock.Release;
  end;
end;

procedure TSessionManager.CleanupExpired(MaxAgeMinutes: Integer);
var
  I: Integer;
  Data: TSessionData;
begin
  FLock.Acquire;
  try
    for I := FMap.Count - 1 downto 0 do
    begin
      Data := FMap.Data[I];
      if (Now - Data.LastAccessed) * 24 * 60 > MaxAgeMinutes then
      begin
        FMap.Delete(I);
      end;
    end;
  finally
    FLock.Release;
  end;
end;

function TSessionManager.CheckAndRegisterLogin: Boolean;
var
  Today: TDate;
begin
  FLock.Acquire;
  try
    Today := Trunc(Now);
    
    // รีเซ็ตการนับเมื่อเปลี่ยนวัน
    if LastLoginDate <> Today then
    begin
      LastLoginDate := Today;
      DailyLoginCount := 0;
    end;
    
    // ตรวจสอบโหมด Demo (จำกัด 10 login ต่อวัน)
    if License.DemoModeActive and (DailyLoginCount >= 10) then
    begin
      Result := False;
      Exit;
    end;
    
    // บันทึกการ login สำเร็จ
    Inc(DailyLoginCount);
    Result := True;
  finally
    FLock.Release;
  end;
end;

initialization
  SessionManager := TSessionManager.Create;
  LastLoginDate := 0;
  DailyLoginCount := 0;

finalization
  SessionManager.Free;

end.
