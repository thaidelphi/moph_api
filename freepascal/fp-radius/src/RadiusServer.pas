unit RadiusServer;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Sockets, BaseUnix, RadiusConfig, RadiusPacket,
  RadiusAuth, RadiusAccounting, RadiusDB, RadiusWorker;

type
  TRadiusServer = class
  private
    FAuthSocket : LongInt;   // UDP Socket สำหรับ Port 1812
    FAcctSocket : LongInt;   // UDP Socket สำหรับ Port 1813
    FCfg        : TRadiusConfig;
    FRunning    : Boolean;
    
    FQueue      : TPacketQueue;
    FWorkers    : array of TRadiusWorkerThread;

    procedure HandleAuthPacket(const Buf: TByteArray; const ClientAddr: TSockAddr);
    procedure HandleAcctPacket(const Buf: TByteArray; const ClientAddr: TSockAddr);

  public
    constructor Create(const Cfg: TRadiusConfig);
    destructor Destroy; override;
    procedure Start;     // เริ่ม Server Loop (Blocking)
    procedure Stop;      // หยุด Server
  end;

implementation

constructor TRadiusServer.Create(const Cfg: TRadiusConfig);
begin
  FCfg := Cfg;
  FRunning := False;
  FQueue := TPacketQueue.Create;
end;

destructor TRadiusServer.Destroy;
begin
  Stop;
  FQueue.Free;
  inherited;
end;

procedure TRadiusServer.Stop;
var
  i: Integer;
begin
  FRunning := False;
  
  if Assigned(FQueue) then
    FQueue.SignalAll;
    
  for i := Low(FWorkers) to High(FWorkers) do
  begin
    FWorkers[i].Terminate;
    FQueue.SignalAll;
    FWorkers[i].WaitFor;
    FWorkers[i].Free;
  end;
  SetLength(FWorkers, 0);

  if FAuthSocket > 0 then fpClose(FAuthSocket);
  if FAcctSocket > 0 then fpClose(FAcctSocket);
end;

procedure TRadiusServer.HandleAuthPacket(const Buf: TByteArray; const ClientAddr: TSockAddr);
var
  Job: TPacketJob;
begin
  Job.PktType := ptAuth;
  Job.Buffer := Buf;
  Job.ClientAddr := ClientAddr;
  Job.SocketFD := FAuthSocket;
  FQueue.Push(Job);
end;

procedure TRadiusServer.HandleAcctPacket(const Buf: TByteArray; const ClientAddr: TSockAddr);
var
  Job: TPacketJob;
begin
  Job.PktType := ptAcct;
  Job.Buffer := Buf;
  Job.ClientAddr := ClientAddr;
  Job.SocketFD := FAcctSocket;
  FQueue.Push(Job);
end;

procedure TRadiusServer.Start;
var
  AuthAddr, AcctAddr : TSockAddr;
  Buf                : array[0..4095] of Byte;
  RecvLen            : Integer;
  ClientAddr         : TSockAddr;
  ClientAddrLen      : TSocklen;
  BytesBuf           : TByteArray;
  FDSets             : TFDSet;
  MaxFD              : Integer;
  Timeout            : TTimeVal;
begin
  // สร้าง Socket สำหรับ Authentication (Port 1812)
  FAuthSocket := fpSocket(AF_INET, SOCK_DGRAM, 0);

  // Bind Port 1812
  FillChar(AuthAddr, SizeOf(AuthAddr), 0);
  AuthAddr.sin_family := AF_INET;
  AuthAddr.sin_port   := htons(FCfg.RadiusPort);
  AuthAddr.sin_addr.s_addr := INADDR_ANY;
  fpBind(FAuthSocket, @AuthAddr, SizeOf(AuthAddr));

  // สร้าง Socket สำหรับ Accounting (Port 1813)
  FAcctSocket := fpSocket(AF_INET, SOCK_DGRAM, 0);
  
  // Bind Port 1813
  FillChar(AcctAddr, SizeOf(AcctAddr), 0);
  AcctAddr.sin_family := AF_INET;
  AcctAddr.sin_port   := htons(FCfg.AcctPort);
  AcctAddr.sin_addr.s_addr := INADDR_ANY;
  fpBind(FAcctSocket, @AcctAddr, SizeOf(AcctAddr));

  LogMsg(1, 'fp-radius started on UDP :'
            + IntToStr(FCfg.RadiusPort)
            + ' (Auth) and :'
            + IntToStr(FCfg.AcctPort)
            + ' (Acct)');

  // Initialize Thread Pool
  SetLength(FWorkers, 20); // 20 threads pool
  for RecvLen := Low(FWorkers) to High(FWorkers) do
  begin
    FWorkers[RecvLen] := TRadiusWorkerThread.Create(FQueue, FCfg);
    FWorkers[RecvLen].Start;
  end;
  LogMsg(1, 'Started 20 Worker Threads.');

  FRunning := True;
  ClientAddrLen := SizeOf(ClientAddr);

  if FAuthSocket > FAcctSocket then
    MaxFD := FAuthSocket + 1
  else
    MaxFD := FAcctSocket + 1;

  while FRunning do 
  begin
    fpFD_ZERO(FDSets);
    fpFD_SET(FAuthSocket, FDSets);
    fpFD_SET(FAcctSocket, FDSets);

    Timeout.tv_sec := 1;
    Timeout.tv_usec := 0;

    if fpSelect(MaxFD, @FDSets, nil, nil, @Timeout) > 0 then
    begin
      // ตรวจสอบ Auth Port
      if fpFD_ISSET(FAuthSocket, FDSets) > 0 then
      begin
        RecvLen := fpRecvFrom(FAuthSocket, @Buf[0], SizeOf(Buf), 0, @ClientAddr, @ClientAddrLen);
        if RecvLen > 0 then 
        begin
          SetLength(BytesBuf, RecvLen);
          Move(Buf[0], BytesBuf[0], RecvLen);
          HandleAuthPacket(BytesBuf, ClientAddr);
        end;
      end;

      // ตรวจสอบ Acct Port
      if fpFD_ISSET(FAcctSocket, FDSets) > 0 then
      begin
        RecvLen := fpRecvFrom(FAcctSocket, @Buf[0], SizeOf(Buf), 0, @ClientAddr, @ClientAddrLen);
        if RecvLen > 0 then 
        begin
          SetLength(BytesBuf, RecvLen);
          Move(Buf[0], BytesBuf[0], RecvLen);
          HandleAcctPacket(BytesBuf, ClientAddr);
        end;
      end;
    end;
  end;
end;

end.
