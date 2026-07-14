unit RadiusAuth;

{$mode objfpc}{$H+}

interface

uses SysUtils, RadiusConfig, RadiusDB, RadiusPacket;

// Handle Auth Request
function HandleAuth(const Req: TRadiusPacket; const Cfg: TRadiusConfig; const NasIP: string): TByteArray;

implementation

function HandleAuth(const Req: TRadiusPacket; const Cfg: TRadiusConfig; const NasIP: string): TByteArray;
var
  Username, Password: string;
  Accepted: Boolean;
begin
  Username := GetAttrString(Req, ATTR_USER_NAME);
  Password := DecryptPassword(Req, Cfg.SharedSecret);
  
  LogMsg(1, 'Auth Request from ' + NasIP + ' for user: ' + Username);
  
  Accepted := CheckUserPassword(Username, Password);
  
  if Accepted then
  begin
    Result := BuildAccept(Req, Cfg.SharedSecret);
    LogMsg(1, 'Access-Accept for ' + Username);
  end
  else
  begin
    Result := BuildReject(Req, Cfg.SharedSecret);
    LogMsg(1, 'Access-Reject for ' + Username);
  end;
  
  LogAccessAttempt(Username, NasIP, Accepted, Now);
end;

end.
