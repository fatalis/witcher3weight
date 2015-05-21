module dllmain;

import std.c.windows.windows;
import core.sys.windows.dll;
import std.string;
import std.c.string: memcmp, memcpy, strcat;
import core.stdc.wchar_: wcsncmp;
import std.conv: to;

import wrapper: DirectInput8Create_Real;
import windows;

__gshared HINSTANCE g_hInst;

extern (Windows)
bool DllMain(void* hInstance, uint ulReason, void* pvReserved)
{
    final switch (ulReason)
    {
    case DLL_PROCESS_ATTACH:
        g_hInst = hInstance;
        dll_process_attach(hInstance, true);
        InitWrapper();
        PatchCode();
        break;

    case DLL_PROCESS_DETACH:
        dll_process_detach(hInstance, true);
        break;

    case DLL_THREAD_ATTACH:
        dll_thread_attach(true, true);
        break;

    case DLL_THREAD_DETACH:
        dll_thread_detach(true, true);
        break;
    }
    return true;
}

void InitWrapper()
{
    char dll[MAX_PATH];
    GetSystemDirectoryA(dll.ptr, dll.sizeof);
    strcat(dll.ptr, r"\dinput8.dll");

    DebugPrint("dinput8 real: %s", dll);

    auto dinput = LoadLibraryA(dll.ptr);
    DebugPrint("dinput8 address %X", dinput);
    DirectInput8Create_Real = cast(typeof(DirectInput8Create_Real))GetProcAddress(dinput, "DirectInput8Create");
}

void PatchCode()
{
    auto func = GetScriptFunc("GetItemWeight");
    if (!func)
        return;

    // .text:00007FF6B4245A6C F3 0F 11 06    movss   dword ptr [rsi], xmm0
    byte[] instr = [cast(byte)0xf3, cast(byte)0x0f, cast(byte)0x11, cast(byte)0x06]; // figure out why these nasty casts are needed
    auto instrAddr = FindBytes(instr.ptr, instr.length, cast(byte*)func, 128);
    if (!instrAddr)
        return;
    
    DebugPrint("instrAddr %X", instrAddr);
    // xor eax ,eax
    // mov dword ptr [rsi], eax
    memcpy_protected(instrAddr, "\x31\xc0\x89".ptr, 3);
}

void* GetScriptFunc(const wchar[] name)
{
    auto mod = GetModuleHandleA(null);

    MODULEINFO info;
    if (!GetModuleInformation(GetCurrentProcess(), mod, &info, info.sizeof))
        return null;

    auto base = cast(byte*)info.lpBaseOfDll;
    auto size = info.SizeOfImage;

    auto nameAddr = FindBytes(cast(byte*)name.ptr, name.length*wchar.sizeof, base, size);
    if (!nameAddr)
        return null;

    auto leaAddr = FindLEARDXForAddr(nameAddr, base, size);
    if (!leaAddr)
        return null;

    // .text:00007FF6B424ED73 48 8D 05 96 6C FF FF    lea rax, GetItemWeight
    byte[] lea2 = [cast(byte)0x48, cast(byte)0x8D, cast(byte)0x05];
    auto lea2Addr = FindBytesReverse(lea2.ptr, lea2.length, cast(byte*)leaAddr, 64);
    if (!lea2Addr)
        return null;

    auto offset = *cast(int*)(lea2Addr+3);
    auto funcAddr = lea2Addr + 7 + offset;

    return funcAddr;
}

// .text:00007FF6B424ED9A 48 8D 15 A7 B3 71 01    lea rdx, aGetitemweight 
void* FindLEARDXForAddr(void* addr, byte* mem, size_t size)
{
    byte[] lea = [cast(byte)0x48, cast(byte)0x8D, cast(byte)0x15];
    foreach (byte* i; FindAllBytes(lea, mem, size))
    {
        auto encodedAddr = cast(int)(addr - (i + 7));
        if (*cast(int*)(i+3) == encodedAddr)
            return i;
    }

    return null;
}

void* FindBytes(byte* search, size_t size, byte* mem, size_t len)
{
    for (auto ptr = mem; ptr < mem + len - size; ptr++)
    {
        if (memcmp(ptr, search, size) == 0)
        {
            return ptr;
        }
    }

    return null;
}

void* FindBytesReverse(byte* search, size_t size, byte* mem, size_t len)
{
    for (auto ptr = mem-size; ptr >= mem-len; ptr--)
    {
        if (memcmp(ptr, search, size) == 0)
        {
            return ptr;
        }
    }

    return null;
}

byte*[] FindAllBytes(const byte[] search, byte* mem, size_t len)
{
    byte*[] ret;
    
    for (auto ptr = mem; ptr < mem + len - search.length; ptr++)
    {
        if (memcmp(ptr, search.ptr, search.length) == 0)
        {
            ret ~= ptr;
        }
    }

    return ret;
}

void DebugPrint(Char, Args...)(Char[] fmt, Args args)
{
    debug {
        string str = format(fmt, args);
        OutputDebugStringA(str.toStringz());
    }
}

bool memcpy_protected(void* dest, in void* src, size_t size)
{
    uint oldProtect;
    if (VirtualProtect(dest, size, PAGE_EXECUTE_READWRITE, &oldProtect))
    {
        memcpy(dest, src, size);
        VirtualProtect(dest, size, oldProtect, &oldProtect);
        return true;
    }

    return false;
}
