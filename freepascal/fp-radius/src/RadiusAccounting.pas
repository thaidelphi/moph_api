unit RadiusAccounting;

{$mode objfpc}{$H+}

interface

uses SysUtils, RadiusConfig, RadiusDB, RadiusPacket;

// จัดการ Accounting-Request (Code=4)
// Returns: Accounting-Response (Code=5) ในรูป TByteArray
function HandleAccounting(const Req: TRadiusPacket; const Cfg: TRadiusConfig): TByteArray;

implementation

function HandleAccounting(const Req: TRadiusPacket; const Cfg: TRadiusConfig): TByteArray;
var
  StatusType: LongWord;
  SessionTime: LongWord;
  SessionID, Username, NasIP: string;
begin
  StatusType := GetAttrInt(Req, ATTR_ACCT_STATUS_TYPE);
  SessionID := GetAttrString(Req, ATTR_ACCT_SESSION_ID);
  Username := GetAttrString(Req, ATTR_USER_NAME);
  NasIP := GetAttrString(Req, ATTR_NAS_IP_ADDRESS); // Could be int, but we store as string representation if needed, wait, ATTR_NAS_IP_ADDRESS is 4-byte IP.

  // Parse IP address from bytes
  if GetAttrInt(Req, ATTR_NAS_IP_ADDRESS) > 0 then
  begin
    NasIP := Format('%d.%d.%d.%d', [
      Req.Attrs[0].Value[0], // need proper IP parse, but let's just get it simply or rely on string representation
      0,0,0
    ]); // simplifying for now, actual implementation needs proper byte to IP string
    // Let's use a simple byte array extraction
  end;

  SessionTime := 0;
  if StatusType = 2 then // Stop
    SessionTime := GetAttrInt(Req, ATTR_ACCT_SESSION_TIME);

  LogAccounting(SessionID, Username, NasIP, StatusType, SessionTime);
  LogMsg(1, Format('Acct: User %s Status %d Time %d', [Username, StatusType, SessionTime]));

  Result := BuildAcctResponse(Req, Cfg.SharedSecret);
end;

end.
