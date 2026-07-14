unit SessionMgr;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, syncobjs, fgl;

type
  TSessionData = record
    Username: string;
    FullName: string;
    Email: string;
    // FortiGate handshake data
    Magic: string;
    RedirUrl: string;
    
    // Auto-login credential
    PlainPass: string;
    
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
    procedure UpdateSession(const SessionID: string; const Data: TSessionData);
    procedure DeleteSession(const SessionID: string);
    procedure CleanupExpired(MaxAgeMinutes: Integer);
  end;

var
  SessionManager: TSessionManager;

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
  Data.PlainPass := '';
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

initialization
  SessionManager := TSessionManager.Create;

finalization
  SessionManager.Free;

end.
