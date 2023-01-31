/*  SM Franug FakePlayers Interface
 *
 *  Copyright (C) 2022 Francisco 'Franc1sco' García
 * 
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option) 
 * any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT 
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS 
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with 
 * this program. If not, see http://www.gnu.org/licenses/.
 */
 
#include <sourcemod>
#include <sdktools>
#include <dhooks>
#include <bytebuffer>


int g_platform;

public Plugin myinfo = 
{
	name = "SM Franug FakePlayers Interface",
	author = "Franc1sco franug",
	description = "",
	version = "0.2",
	url = "http://steamcommunity.com/id/franug"
}

enum struct Bots
{
	char name[MAX_NAME_LENGTH];
	int time;
	int score;
}

Handle array_bots_name;
Handle array_bots_score;
Handle array_bots_time;

public APLRes AskPluginLoad2(Handle plugin, bool late, char[] error, int err_max)
{
	RegPluginLibrary("FranugFakePlayers");
	CreateNative("FranugFakePlayers_AddBot", Native_AddBot);
	CreateNative("FranugFakePlayers_ResetBots", Native_ResetBots);
	return APLRes_Success;
}

public Native_AddBot(Handle plugin, int argc)
{  
	char name[MAX_NAME_LENGTH];
	GetNativeString(1, name, MAX_NAME_LENGTH);

	addBot(name, GetNativeCell(2), GetNativeCell(3));
}

public Native_ResetBots(Handle plugin, int argc)
{  
	ClearArray(array_bots_name);
	ClearArray(array_bots_score);
	ClearArray(array_bots_time);
}

public void OnPluginStart()
{
  array_bots_name = CreateArray(MAX_NAME_LENGTH);
  array_bots_score = CreateArray(MAX_NAME_LENGTH);
  array_bots_time = CreateArray(MAX_NAME_LENGTH);
  GameData hGameConf;
  char error[128];

  hGameConf = LoadGameConfigFile("franug_fakeplayers.games");
  if(!hGameConf)
  {
    Format(error, sizeof(error), "Failed to find franug_fakeplayers.games");
    SetFailState(error);
  }

  g_platform = hGameConf.GetOffset("WindowsOrLinux");

  Handle hNetSendPacket = DHookCreateDetour(Address_Null, CallConv_CDECL, ReturnType_Int, ThisPointer_Ignore);
  if (!hNetSendPacket)
    SetFailState("Failed to setup detour for NET_SendPacket");

  if (!DHookSetFromConf(hNetSendPacket, hGameConf, SDKConf_Signature, "NET_SendPacket"))
    SetFailState("Failed to load NET_SendPacket signature from gamedata");


  if(g_platform == 1)
  {
    DHookAddParam(hNetSendPacket, HookParamType_Int, .custom_register=DHookRegister_EDX); // Windows call convention
    DHookAddParam(hNetSendPacket, HookParamType_ObjectPtr, -1, DHookPass_ByRef, DHookRegister_ECX);
  }
  else
  {
    DHookAddParam(hNetSendPacket, HookParamType_Int);
    //DHookAddParam(hNetSendPacket, HookParamType_ObjectPtr, -1, DHookPass_ByRef);
    DHookAddParam(hNetSendPacket, HookParamType_Int);
  }
  DHookAddParam(hNetSendPacket, HookParamType_Int);
  DHookAddParam(hNetSendPacket, HookParamType_Int);
  DHookAddParam(hNetSendPacket, HookParamType_Int);

  if (!DHookEnableDetour(hNetSendPacket, false, Detour_OnNetSendPacket))
      SetFailState("Failed to detour NET_SendPacket.");
  
}

void addBot(char name[128], int time, int score)
{
	Bots fakeplayer;
	fakeplayer.name = name;
	fakeplayer.score = score;
	fakeplayer.time = time;
	
	PushArrayString(array_bots_name, fakeplayer.name);
	PushArrayCell(array_bots_score, fakeplayer.score);
	PushArrayCell(array_bots_time, fakeplayer.time);
}

int GetInfoPlayersIndex(const int[] bytes)
{
  int cursor = 6; // Skip header + protocol;
  int strings;

  do
  {
    if(bytes[cursor] == '\0')
      strings++;

    cursor++;
  } while(strings < 4);

  cursor += 2; // Skip ID;
  return cursor;
}

int RetrieveData(const int[] bytes, int[] out)
{
  int cursor = 5; // skip header
  int outCursor;
  int players = bytes[cursor];
  int outPlayers;

  // New header
  out[0] = 0xFF;
  out[1] = 0xFF;
  out[2] = 0xFF;
  out[3] = 0xFF;
  out[4] = 0x44;
  out[5] = players;
  outCursor += 6;

  cursor++; // skip player count
  for(int i = 0; i < players; i++)
  {
    char name[MAX_NAME_LENGTH];
    int nameLength;

    do
    {
      name[nameLength] = bytes[cursor + 1 + nameLength];
      nameLength++;
    } while(bytes[cursor + nameLength] != '\0');

    outPlayers++;
    nameLength = 0;

    out[outCursor] = bytes[cursor];
    cursor++; // skip id
    outCursor++;

    do
    {
      out[outCursor + nameLength] = bytes[cursor + nameLength];
      nameLength++;
    } while(bytes[cursor + nameLength] != '\0');

    cursor += nameLength + 1; // skip name + null
    outCursor += nameLength + 1;

    out[outCursor] = bytes[cursor];
    out[outCursor + 1] = bytes[cursor + 1];
    out[outCursor + 2] = bytes[cursor + 2];
    out[outCursor + 3] = bytes[cursor + 3];

    cursor += 4; // skip score
    outCursor += 4;

    out[outCursor] = bytes[cursor];
    out[outCursor + 1] = bytes[cursor + 1];
    out[outCursor + 2] = bytes[cursor + 2];
    out[outCursor + 3] = bytes[cursor + 3];

    cursor += 4; // skip duration
    outCursor += 4;
  }
  
  int fakeSize = GetArraySize(array_bots_name);
  if(fakeSize > 0)
  {
	  for(int i = 0; i < fakeSize; i++)
	  {
	    Bots fakeplayer;
	    GetArrayString(array_bots_name, i, fakeplayer.name, sizeof(fakeplayer.name));
	    fakeplayer.score = GetArrayCell(array_bots_score, i);
	    fakeplayer.time = GetArrayCell(array_bots_time, i)+GetEngineTime();
	    int nameLength;
	    ByteBuffer gbytes;
	
	    outPlayers++;
	    nameLength = 0;
	
	    out[outCursor] = i+players; // id
	    cursor++; // skip id
	    outCursor++;
	
	    gbytes = CreateByteBuffer(true, "", 0);
	    gbytes.WriteString(fakeplayer.name);
	    nameLength = gbytes.Cursor
	    gbytes.Cursor = 0;
	    
	    for (int x = 0; x < nameLength - 1; x++)
	    {
	    	out[outCursor + x] = gbytes.ReadByte();
	    }
	    gbytes.Close();

	    cursor += nameLength; // skip name + null
	    outCursor += nameLength;
		
	    gbytes = CreateByteBuffer(true, "", 0);
	    gbytes.WriteInt(fakeplayer.score);
	    gbytes.Cursor = 0;
	    out[outCursor] = gbytes.ReadByte();
	    out[outCursor + 1] = gbytes.ReadByte();
	    out[outCursor + 2] = gbytes.ReadByte();
	    out[outCursor + 3] = gbytes.ReadByte();
	    gbytes.Close();
	    cursor += 4; // skip score
	    outCursor += 4;
	
	    gbytes = CreateByteBuffer(true, "", 0);
	    gbytes.WriteInt(fakeplayer.time);
	    gbytes.Cursor = 0;
	    out[outCursor] = gbytes.ReadByte();
	    out[outCursor + 1] = gbytes.ReadByte();
	    out[outCursor + 2] = gbytes.ReadByte();
	    out[outCursor + 3] = gbytes.ReadByte();
	    gbytes.Close();
	    cursor += 4; // skip duration
	    outCursor += 4;
	  }
  }
  out[5] = outPlayers; // Update players field
  return outCursor;
}

public MRESReturn Detour_OnNetSendPacket(Handle hReturn, Handle hParams)
{
  Address strAddress = DHookGetParam(hParams, 3);
  int size = DHookGetParam(hParams, 4);
  int bytes[512];

  int packetHeader = LoadFromAddress(strAddress + view_as<Address>(4), NumberType_Int8);

  if(packetHeader != 0x44 && packetHeader != 0x49)
    return MRES_Ignored;
    
  for(int i = 0; i < size; i++)
  {
    int val = LoadFromAddress(strAddress + view_as<Address>(i), NumberType_Int8);
    bytes[i] = val;
  }

  if(packetHeader == 0x44) // A2S_PLAYER
  {
    int newData[2048];
    int newSize = RetrieveData(bytes, newData);
    for(int i = 0; i < newSize; i++)
    {
      StoreToAddress(strAddress + view_as<Address>(i), newData[i], NumberType_Int8);
    }
    DHookSetParam(hParams, 4, newSize);
  }
  else if(packetHeader == 0x49) // A2S_INFO
  {
    int playersIndex = GetInfoPlayersIndex(bytes);
    int playerCount = LoadFromAddress(strAddress + view_as<Address>(playersIndex), NumberType_Int8);
    int excludeCount = 0;

    if(excludeCount < 0)
      excludeCount = 0;

    playerCount += GetArraySize(array_bots_name);
    StoreToAddress(strAddress + view_as<Address>(playersIndex), playerCount, NumberType_Int8);
  }
  return MRES_ChangedHandled;
}