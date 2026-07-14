unit RadiusWorker;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs, Sockets, BaseUnix,
  RadiusConfig, RadiusDB, RadiusPacket, mysql80conn,
  RadiusAuth, RadiusAccounting;

type
  TPacketType = (ptAuth, ptAcct);

  TPacketJob = record
    PktType: TPacketType;
    Buffer: TByteArray;
    ClientAddr: TSockAddr;
    SocketFD: LongInt;
  end;

  TPacketQueue = class
  private
    FList: TList;
    FLock: TCriticalSection;
    FEvent: pRTLEvent;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Push(const Job: TPacketJob);
    function Pop(out Job: TPacketJob): Boolean;
    procedure SignalAll; 
  end;

  TRadiusWorkerThread = class(TThread)
  private
    FQueue: TPacketQueue;
    FCfg: TRadiusConfig;
    FDBConn: TMySQL80Connection;
    procedure HandleJob(const Job: TPacketJob);
  protected
    procedure Execute; override;
  public
    constructor Create(AQueue: TPacketQueue; const Cfg: TRadiusConfig);
    destructor Destroy; override;
  end;

implementation

{ TPacketQueue }

constructor TPacketQueue.Create;
begin
  FList := TList.Create;
  FLock := TCriticalSection.Create;
  FEvent := RTLEventCreate;
end;

destructor TPacketQueue.Destroy;
var
  i: Integer;
  PJob: ^TPacketJob;
begin
  FLock.Acquire;
  try
    for i := 0 to FList.Count - 1 do
    begin
      PJob := FList[i];
      Dispose(PJob);
    end;
    FList.Free;
  finally
    FLock.Release;
  end;
  FLock.Free;
  RTLEventDestroy(FEvent);
  inherited;
end;

procedure TPacketQueue.Push(const Job: TPacketJob);
var
  PJob: ^TPacketJob;
begin
  New(PJob);
  PJob^ := Job;
  FLock.Acquire;
  try
    FList.Add(PJob);
  finally
    FLock.Release;
  end;
  RTLEventSetEvent(FEvent);
end;

function TPacketQueue.Pop(out Job: TPacketJob): Boolean;
var
  PJob: ^TPacketJob;
begin
  Result := False;
  RTLEventWaitFor(FEvent);
  
  FLock.Acquire;
  try
    if FList.Count > 0 then
    begin
      PJob := FList[0];
      Job := PJob^;
      FList.Delete(0);
      Dispose(PJob);
      Result := True;
    end;
    if FList.Count > 0 then
      RTLEventSetEvent(FEvent)
    else
      RTLEventResetEvent(FEvent);
  finally
    FLock.Release;
  end;
end;

procedure TPacketQueue.SignalAll;
begin
  RTLEventSetEvent(FEvent);
end;

{ TRadiusWorkerThread }

constructor TRadiusWorkerThread.Create(AQueue: TPacketQueue; const Cfg: TRadiusConfig);
begin
  FQueue := AQueue;
  FCfg := Cfg;
  FDBConn := nil;
  FreeOnTerminate := False;
  inherited Create(False);
end;

destructor TRadiusWorkerThread.Destroy;
begin
  inherited;
end;

procedure TRadiusWorkerThread.Execute;
var
  Job: TPacketJob;
begin
  // Connect to DB for this thread
  if DBConnect(FCfg, FDBConn) then
  begin
    while not Terminated do
    begin
      if FQueue.Pop(Job) then
      begin
        if Terminated then Break;
        HandleJob(Job);
      end
      else
      begin
        // Event was signaled but queue is empty, likely termination
        if Terminated then Break;
      end;
    end;
    DBDisconnect(FDBConn);
  end
  else
  begin
    LogMsg(0, 'Worker Thread failed to connect to DB, terminating.');
  end;
end;

procedure TRadiusWorkerThread.HandleJob(const Job: TPacketJob);
var
  Pkt: TRadiusPacket;
  Response: TByteArray;
  ClientIP: string;
begin
  Pkt := ParsePacket(Job.Buffer);
  Response := nil;

  if Job.PktType = ptAuth then
  begin
    if Pkt.Code = RADIUS_ACCESS_REQUEST then
    begin
      ClientIP := NetAddrToStr(Job.ClientAddr.sin_addr);
      Response := HandleAuth(Pkt, FCfg, ClientIP, FDBConn);
    end;
  end
  else if Job.PktType = ptAcct then
  begin
    if Pkt.Code = RADIUS_ACCT_REQUEST then
    begin
      Response := HandleAccounting(Pkt, FCfg, FDBConn);
    end;
  end;

  if Length(Response) > 0 then
    fpSendTo(Job.SocketFD, @Response[0], Length(Response), 0, @Job.ClientAddr, SizeOf(Job.ClientAddr));
end;

end.
