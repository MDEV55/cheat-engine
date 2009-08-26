unit debug;

interface

uses windows, sysutils, dbk32functions, classes;

type TDebuggerstate=record
	eflags : DWORD;
	eax : DWORD;
	ebx : DWORD;
	ecx : DWORD;
	edx : DWORD;
	esi : DWORD;
	edi : DWORD;
	ebp : DWORD;
	esp : DWORD;
	eip : DWORD;
	cs  : DWORD;
	ds  : DWORD;
	es  : DWORD;
	fs  : DWORD;
	gs  : DWORD;
	ss  : DWORD;
  dr0 : DWORD;
  dr1 : DWORD;
  dr2 : DWORD;
  dr3 : DWORD;
  dr6 : DWORD;
  dr7 : DWORD;
end;
type PDebuggerstate=^TDebuggerstate;

type TBreakType=(bt_OnInstruction=0,bt_OnWrites=1, bt_OnIOAccess=2, bt_OnReadsAndWrites=3);
type TBreakLength=(bl_1byte=0, bl_2byte=1, bl_8byte=2{Only when in 64-bit}, bl_4byte=3);

function DBKDebug_ContinueDebugEvent(handled: BOOL): boolean; stdcall;
function DBKDebug_WaitForDebugEvent(timeout: dword): boolean; stdcall;
function DBKDebug_GetDebuggerState(state: PDebuggerstate): boolean; stdcall;
function DBKDebug_SetDebuggerState(state: PDebuggerstate): boolean; stdcall;

function DBKDebug_SetGlobalDebugState(state: BOOL): BOOL; stdcall;
function DBKDebug_StartDebugging(processid:dword):BOOL; stdcall;
function DBKDebug_StopDebugging:BOOL; stdcall;
function DBKDebug_GD_SetBreakpoint(active: BOOL; debugregspot: integer; Address: dword; breakType: TBreakType; breakLength: TBreakLength): BOOL; stdcall;


implementation

function internal_hookints(parameters: pointer): BOOL; stdcall;
var cc,br: dword;
begin
  if hdevice<>INVALID_HANDLE_VALUE then
  begin
    cc:=IOCTL_CE_HOOKINTS;
    result:=deviceiocontrol(hdevice,cc,nil,0,nil,0,br,nil);
  end else result:=false;
  
end;

function StartCEKernelDebug:BOOL; stdcall;
var
    br,cc: dword;
    i:integer;
    cpunr,PA,SA:Dword;
    cpunr2:byte;
begin
  outputdebugstring('StartCEKernelDebug');
  foreachcpu(internal_hookints, nil);

  result:=true;
end;

function internal_SetGlobalDebugState(state: pointer): BOOL; stdcall;
var
  x: BOOL;
  br,cc: dword;
begin
  outputdebugstring('SetGlobalDebugState');
  x:=PBOOL(state)^;

  result:=false;
  if hdevice<>INVALID_HANDLE_VALUE then
  begin
    cc:=IOCTL_CE_SETGLOBALDEBUGSTATE;
    result:=deviceiocontrol(hdevice,cc,@x,sizeof(x),nil,0,br,nil);
  end;
end;

function DBKDebug_SetGlobalDebugState(state: BOOL): BOOL; stdcall;
begin
  result:=foreachcpu(internal_SetGlobalDebugState, @state);
end;

function internal_touchdebugregister(parameters: pointer): BOOL; stdcall;
var
  br,cc: dword;
begin
  result:=false;
  if hdevice<>INVALID_HANDLE_VALUE then
  begin
    cc:=IOCTL_CE_TOUCHDEBUGREGISTER;
    result:=deviceiocontrol(hdevice,cc,nil,0,nil,0,br,nil);
  end;
end;

procedure DBKDebug_TouchDebugRegister;
//this routine touches the debug registers on each cpu
//when global debug is enabled this facilitates in setting or unsetting changes in the breakpoint list
//this way when a breakpoint is set, it actually gets set, or unset the same
//just make sure to disable the breakpoint before removing the handler
begin
  foreachcpu(internal_touchdebugregister,nil);
end;

function DBKDebug_GD_SetBreakpoint(active: BOOL; debugregspot: integer; Address: dword; breakType: TBreakType; breakLength: TBreakLength): BOOL; stdcall;
var
  input: record
    active: BOOL;
    debugregspot: integer;
    address: DWORD;
    breaktype: TBreakType;
    breakLength: TBreakLength;
  end;

  br,cc: dword;
begin
  if hdevice<>INVALID_HANDLE_VALUE then
  begin
    result:=StartCEKernelDebug;
    input.active:=active;
    input.debugregspot:=debugregspot;
    input.address:=address;
    input.breaktype:=breaktype;
    input.breakLength:=breaklength;
    
    cc:=IOCTL_CE_GD_SETBREAKPOINT;
    result:=result and deviceiocontrol(hdevice,cc,@input,sizeof(input),@input,0,br,nil);
    DBKDebug_TouchDebugRegister; //update the system state
  end;
end;


function DBKDebug_StartDebuggingInternal(processid: pointer):BOOL; stdcall;
type Tinput=record
  ProcessID:DWORD;
end;
var input:TInput;
    br,cc: dword;
begin
  if hdevice<>INVALID_HANDLE_VALUE then
  begin
    result:=StartCEKernelDebug;
    input.Processid:=PDWORD(processid)^;
    cc:=IOCTL_CE_DEBUGPROCESS;
    result:=result and deviceiocontrol(hdevice,cc,@input,sizeof(input),@input,0,br,nil);
  end;
end;



function DBKDebug_StartDebugging(processid:dword):BOOL; stdcall;
begin
  foreachcpu(DBKDebug_StartDebuggingInternal, @processid);
end;

function internal_StopDebugging(parameters: pointer):BOOL; stdcall;
var x,cc: dword;
begin
  outputdebugstring('DBK32: StopDebugging called');
  result:=false;
  if hdevice<>INVALID_HANDLE_VALUE then
  begin
    cc:=IOCTL_CE_STOPDEBUGGING;
    result:=deviceiocontrol(hdevice,cc,nil,0,nil,0,x,nil);
  end;
end;

function DBKDebug_StopDebugging:BOOL; stdcall;
begin
  result:=foreachcpu(internal_StopDebugging,nil);
end;

function DBKDebug_GetDebuggerState(state: PDebuggerstate): boolean; stdcall;
var
  Output: TDebuggerstate;
  cc: dword;
begin
  OutputDebugString('DBKDebug_GetDebuggerState');
  result:=false;
  if (hdevice<>INVALID_HANDLE_VALUE) then
  begin
    cc:=IOCTL_CE_GETDEBUGGERSTATE;
    result:=deviceiocontrol(hdevice,cc,nil,0,@output,sizeof(output),cc,nil);
    if result then
    begin
      OutputDebugString('result = true');
      state^:=output;
    end;
  end;
end;

function DBKDebug_SetDebuggerState(state: PDebuggerstate): boolean; stdcall;
var
  input: TDebuggerstate;
  cc: dword;
begin
  OutputDebugString('DBKDebug_SetDebuggerState');
  result:=false;
  if (hdevice<>INVALID_HANDLE_VALUE) then
  begin
    cc:=IOCTL_CE_SETDEBUGGERSTATE;
    input:=state^;
    result:=deviceiocontrol(hdevice,cc,@input,sizeof(Input),nil,0,cc,nil);
  end;
end;


function DBKDebug_ContinueDebugEvent(handled: BOOL): boolean; stdcall;
var
  cc: dword;
  Input: record
    handled: BOOL;
  end;
begin
  result:=false;
  input.handled:=handled;
  if (hdevice<>INVALID_HANDLE_VALUE) then
  begin
    cc:=IOCTL_CE_CONTINUEDEBUGEVENT;
    result:=deviceiocontrol(hdevice,cc,@Input,sizeof(input),nil,0,cc,nil);
  end;
end;

function DBKDebug_WaitForDebugEvent(timeout: dword): boolean; stdcall;
type TInput=record
  Timeout: DWORD;
end;
var cc: dword;
    x: TInput;
begin
  result:=false;
  x.timeout:=timeout;

  if (hdevice<>INVALID_HANDLE_VALUE) then
  begin
    cc:=IOCTL_CE_WAITFORDEBUGEVENT;
    result:=deviceiocontrol(hdevice,cc,@x,sizeof(x),nil,0,cc,nil);
  end;
end;


end.
