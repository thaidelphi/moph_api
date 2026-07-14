unit RadiusPacket;

{$mode objfpc}{$H+}

interface

uses SysUtils, md5;

const
  // RADIUS Packet Codes
  RADIUS_ACCESS_REQUEST    = 1;
  RADIUS_ACCESS_ACCEPT     = 2;
  RADIUS_ACCESS_REJECT     = 3;
  RADIUS_ACCT_REQUEST      = 4;
  RADIUS_ACCT_RESPONSE     = 5;

  // RADIUS Attribute Types
  ATTR_USER_NAME           = 1;
  ATTR_USER_PASSWORD       = 2;
  ATTR_NAS_IP_ADDRESS      = 4;
  ATTR_NAS_PORT            = 5;
  ATTR_SERVICE_TYPE        = 6;
  ATTR_REPLY_MESSAGE       = 18;
  ATTR_ACCT_STATUS_TYPE    = 40;
  ATTR_ACCT_SESSION_ID     = 44;
  ATTR_ACCT_SESSION_TIME   = 46;

type
  TByteArray = array of Byte;

  // Attribute เดี่ยว
  TRadiusAttr = record
    AttrType : Byte;
    Value    : TByteArray;         // Raw bytes ของ Value (ไม่รวม Type และ Length)
  end;

  // Packet ทั้งหมด
  TRadiusPacket = record
    Code          : Byte;
    Identifier    : Byte;
    Length        : Word;
    Authenticator : array[0..15] of Byte;  // 16 bytes
    Attrs         : array of TRadiusAttr;
    AttrCount     : Integer;
  end;

// ฟังก์ชัน Parse Raw UDP Buffer → TRadiusPacket
function ParsePacket(const Buf: TByteArray): TRadiusPacket;

// ดึงค่า Attribute เป็น String
function GetAttrString(const Pkt: TRadiusPacket; AttrType: Byte): string;

// ดึงค่า Attribute เป็น Integer (Big Endian 4 bytes)
function GetAttrInt(const Pkt: TRadiusPacket; AttrType: Byte): LongWord;

// ดึงค่า Attribute เป็น Raw Bytes
function GetAttrBytes(const Pkt: TRadiusPacket; AttrType: Byte): TByteArray;

// ถอดรหัส User-Password (RFC 2865 §5.2)
function DecryptPassword(Pkt: TRadiusPacket; Secret: string): string;

// สร้าง Access-Accept Response (คำนวณ Response Authenticator)
function BuildAccept(Req: TRadiusPacket; Secret: string): TByteArray;

// สร้าง Access-Reject Response
function BuildReject(Req: TRadiusPacket; Secret: string): TByteArray;

// สร้าง Accounting-Response
function BuildAcctResponse(Req: TRadiusPacket; Secret: string): TByteArray;

implementation

function ParsePacket(const Buf: TByteArray): TRadiusPacket;
var
  i, AttrLen: Integer;
  PktLen: Integer;
begin
  Result.AttrCount := 0;
  SetLength(Result.Attrs, 0);

  if Length(Buf) < 20 then Exit;

  Result.Code := Buf[0];
  Result.Identifier := Buf[1];
  Result.Length := (Buf[2] shl 8) or Buf[3];
  
  PktLen := Result.Length;
  if PktLen > Length(Buf) then PktLen := Length(Buf);

  Move(Buf[4], Result.Authenticator[0], 16);

  i := 20;
  while i < PktLen do
  begin
    if i + 1 >= PktLen then Break; // ข้อมูลไม่ครบ
    
    AttrLen := Buf[i+1];
    if AttrLen < 2 then Break; // ป้องกัน infinite loop กรณี packet เสีย
    if i + AttrLen > PktLen then Break; // ยาวเกินขนาด packet

    SetLength(Result.Attrs, Result.AttrCount + 1);
    Result.Attrs[Result.AttrCount].AttrType := Buf[i];
    SetLength(Result.Attrs[Result.AttrCount].Value, AttrLen - 2);
    
    if AttrLen > 2 then
      Move(Buf[i+2], Result.Attrs[Result.AttrCount].Value[0], AttrLen - 2);
      
    Inc(Result.AttrCount);
    Inc(i, AttrLen);
  end;
end;

function GetAttrBytes(const Pkt: TRadiusPacket; AttrType: Byte): TByteArray;
var
  i: Integer;
begin
  SetLength(Result, 0);
  for i := 0 to Pkt.AttrCount - 1 do
  begin
    if Pkt.Attrs[i].AttrType = AttrType then
    begin
      Result := Pkt.Attrs[i].Value;
      Exit;
    end;
  end;
end;

function GetAttrString(const Pkt: TRadiusPacket; AttrType: Byte): string;
var
  Bytes: TByteArray;
  i: Integer;
begin
  Result := '';
  Bytes := GetAttrBytes(Pkt, AttrType);
  if Length(Bytes) > 0 then
  begin
    SetLength(Result, Length(Bytes));
    for i := 0 to Length(Bytes) - 1 do
      Result[i+1] := Char(Bytes[i]);
  end;
end;

function GetAttrInt(const Pkt: TRadiusPacket; AttrType: Byte): LongWord;
var
  Bytes: TByteArray;
begin
  Result := 0;
  Bytes := GetAttrBytes(Pkt, AttrType);
  if Length(Bytes) >= 4 then
    Result := (Bytes[0] shl 24) or (Bytes[1] shl 16) or (Bytes[2] shl 8) or Bytes[3];
end;

function DecryptPassword(Pkt: TRadiusPacket; Secret: string): string;
var
  EncBuf: TByteArray;      
  i, j: Integer;
  b: TMD5Digest;
  ctx: TMD5Context;
  ResBytes: TByteArray;
begin
  Result := '';
  EncBuf := GetAttrBytes(Pkt, ATTR_USER_PASSWORD);
  if Length(EncBuf) = 0 then Exit;

  SetLength(ResBytes, Length(EncBuf));

  // รอบแรก: MD5(Secret + Authenticator)
  MD5Init(ctx);
  if Length(Secret) > 0 then
    MD5Update(ctx, Secret[1], Length(Secret));
  MD5Update(ctx, Pkt.Authenticator[0], 16);
  MD5Final(ctx, b);

  // XOR 16 bytes แรก
  for i := 0 to 15 do
  begin
    if i < Length(EncBuf) then
      ResBytes[i] := EncBuf[i] xor b[i];
  end;

  // รอบถัดไป: MD5(Secret + Ciphertext[prev 16 bytes])
  j := 16;
  while j < Length(EncBuf) do 
  begin
    MD5Init(ctx);
    if Length(Secret) > 0 then
      MD5Update(ctx, Secret[1], Length(Secret));
    MD5Update(ctx, EncBuf[j-16], 16);
    MD5Final(ctx, b);

    for i := 0 to 15 do
    begin
      if (j + i) < Length(EncBuf) then
        ResBytes[j+i] := EncBuf[j+i] xor b[i];
    end;
    Inc(j, 16);
  end;

  // ตัด null padding ออกจากท้าย
  i := Length(ResBytes);
  while (i > 0) and (ResBytes[i-1] = 0) do Dec(i);
  SetLength(ResBytes, i);

  if i > 0 then
  begin
    SetLength(Result, i);
    for j := 0 to i - 1 do
      Result[j+1] := Char(ResBytes[j]);
  end;
end;

function BuildHMACMD5(Data: TByteArray; KeyStr: string): TMD5Digest;
var
  K_ipad, K_opad: array[0..63] of Byte;
  i: Integer;
  tk: TMD5Digest;
  ctx: TMD5Context;
  ActualKey: TByteArray;
begin
  if Length(KeyStr) > 64 then
  begin
    MD5Init(ctx);
    MD5Update(ctx, KeyStr[1], Length(KeyStr));
    MD5Final(ctx, tk);
    SetLength(ActualKey, 16);
    Move(tk[0], ActualKey[0], 16);
  end
  else
  begin
    SetLength(ActualKey, Length(KeyStr));
    if Length(KeyStr) > 0 then
      Move(KeyStr[1], ActualKey[0], Length(KeyStr));
  end;

  FillChar(K_ipad, sizeof(K_ipad), $36);
  FillChar(K_opad, sizeof(K_opad), $5c);

  for i := 0 to Length(ActualKey) - 1 do
  begin
    K_ipad[i] := K_ipad[i] xor ActualKey[i];
    K_opad[i] := K_opad[i] xor ActualKey[i];
  end;

  MD5Init(ctx);
  MD5Update(ctx, K_ipad, 64);
  if Length(Data) > 0 then
    MD5Update(ctx, Data[0], Length(Data));
  MD5Final(ctx, tk);

  MD5Init(ctx);
  MD5Update(ctx, K_opad, 64);
  MD5Update(ctx, tk[0], 16);
  MD5Final(ctx, Result);
end;

function BuildAccept(Req: TRadiusPacket; Secret: string): TByteArray;
var
  TotalLen: Word;
  ctx: TMD5Context;
  RespAuth: TMD5Digest;
  HMacHash: TMD5Digest;
begin
  TotalLen := 20 + 18; // 20 header + 18 for Message-Authenticator
  SetLength(Result, TotalLen);
  Result[0] := RADIUS_ACCESS_ACCEPT;           
  Result[1] := Req.Identifier;                  
  Result[2] := Hi(TotalLen);                    
  Result[3] := Lo(TotalLen);                    

  // 1. Put Request Authenticator in the header for HMAC calculation
  Move(Req.Authenticator[0], Result[4], 16);

  // 2. Add Message-Authenticator (Type 80) with 16 bytes of zeros
  Result[20] := 80;
  Result[21] := 18;
  FillChar(Result[22], 16, 0);

  // 3. Calculate HMAC-MD5 of the whole packet
  HMacHash := BuildHMACMD5(Result, Secret);
  Move(HMacHash[0], Result[22], 16); // Put actual HMAC in place of zeros

  // 4. Calculate actual Response Authenticator
  MD5Init(ctx);
  MD5Update(ctx, Result[0], TotalLen);          
  if Length(Secret) > 0 then
    MD5Update(ctx, Secret[1], Length(Secret)); 
  MD5Final(ctx, RespAuth);

  Move(RespAuth[0], Result[4], 16);
end;

function BuildReject(Req: TRadiusPacket; Secret: string): TByteArray;
var
  TotalLen: Word;
  ctx: TMD5Context;
  RespAuth: TMD5Digest;
  HMacHash: TMD5Digest;
begin
  TotalLen := 20 + 18; 
  SetLength(Result, TotalLen);
  Result[0] := RADIUS_ACCESS_REJECT;           
  Result[1] := Req.Identifier;                  
  Result[2] := Hi(TotalLen);                    
  Result[3] := Lo(TotalLen);                    

  Move(Req.Authenticator[0], Result[4], 16);

  Result[20] := 80;
  Result[21] := 18;
  FillChar(Result[22], 16, 0);

  HMacHash := BuildHMACMD5(Result, Secret);
  Move(HMacHash[0], Result[22], 16);

  MD5Init(ctx);
  MD5Update(ctx, Result[0], TotalLen);          
  if Length(Secret) > 0 then
    MD5Update(ctx, Secret[1], Length(Secret)); 
  MD5Final(ctx, RespAuth);

  Move(RespAuth[0], Result[4], 16);
end;

function BuildAcctResponse(Req: TRadiusPacket; Secret: string): TByteArray;
var
  TotalLen: Word;
  ctx: TMD5Context;
  RespAuth: TMD5Digest;
begin
  TotalLen := 20; 
  SetLength(Result, TotalLen);
  Result[0] := RADIUS_ACCT_RESPONSE;           
  Result[1] := Req.Identifier;                  
  Result[2] := Hi(TotalLen);                    
  Result[3] := Lo(TotalLen);                    

  Move(Req.Authenticator[0], Result[4], 16);

  MD5Init(ctx);
  MD5Update(ctx, Result[0], TotalLen);          
  if Length(Secret) > 0 then
    MD5Update(ctx, Secret[1], Length(Secret)); 
  MD5Final(ctx, RespAuth);

  Move(RespAuth[0], Result[4], 16);
end;

end.
