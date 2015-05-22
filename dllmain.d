module dllmain;

import std.c.windows.windows;
import core.sys.windows.dll;
import std.string;
import std.c.string: memcmp, memcpy, strcat;
import std.conv: to;

import wrapper: DirectInput8Create_Real;
import windows;

const int JMP_SIZE = 12;
__gshared {
    void* g_hInst;
    float g_weightMultiplier = 1;
    float g_durabilityMultiplier = 1;
}

extern (Windows)
bool DllMain(void* hInstance, uint ulReason, void* pvReserved)
{
    final switch (ulReason)
    {
    case DLL_PROCESS_ATTACH:
        g_hInst = hInstance;
        dll_process_attach(hInstance, true);
        InitWrapper();
        LoadSettings();
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

void LoadSettings()
{
    char ini[MAX_PATH];
    GetCurrentDirectoryA(ini.sizeof, ini.ptr);
    strcat(ini.ptr, r"\witcher3weight.ini");
    DebugPrint("ini %s", ini);

    char weight[32];
    GetPrivateProfileStringA("Settings", "ItemWeightMultiplier", "1.0", weight.ptr, weight.sizeof, ini.ptr);
    debug {
    char durability[32];
    GetPrivateProfileStringA("Settings", "ItemMaxDurabilityMultiplier", "1.0", durability.ptr, durability.sizeof, ini.ptr);
    }

    try
    {
        g_weightMultiplier = to!float(to!string(weight.ptr));
        debug g_durabilityMultiplier = to!float(to!string(durability.ptr));
    }
    catch (Exception ex)
    {
        DebugPrint(ex.toString());
    }

    DebugPrint("settings %f %f", g_weightMultiplier, g_durabilityMultiplier);

}

void PatchCode()
{
    auto weightFunc = GetScriptFunc("GetItemWeight");
    if (!weightFunc)
        return;

    InstallTrampoline(cast(ubyte*)weightFunc, cast(ubyte*)&GetItemWeight_Hook, cast(ubyte*)&GetItemWeight_Gate, JMP_SIZE+3);

    debug {
    auto maxDuraFunc = GetScriptFunc("GetItemMaxDurability");
    if (!maxDuraFunc)
        return;

    InstallTrampoline(cast(ubyte*)maxDuraFunc, cast(ubyte*)&GetItemMaxDurability_Hook, cast(ubyte*)&GetItemMaxDurability_Gate, JMP_SIZE+3);

    auto initialDuraFunc = GetScriptFunc("GetItemInitialDurability");
    if (!initialDuraFunc)
        return;

    InstallTrampoline(cast(ubyte*)initialDuraFunc, cast(ubyte*)&GetItemInitialDurability_Hook, cast(ubyte*)&GetItemInitialDurability_Gate, JMP_SIZE+3);
    }
}

extern(C++)
void GetItemWeight_Hook(void* a1, void* a2, float* weight)
{
    GetItemWeight_Gate(a1, a2, weight);
    if (weight !is null)
    {
        DebugPrint("weight %f", *weight);
        *weight /= g_weightMultiplier;
    }
}

extern(C++)
void GetItemWeight_Gate(void* a1, void* a2, float* weight)
{
    asm {
        naked;
        nop;nop;nop;nop;nop;nop;nop;nop;nop;nop;nop;nop;
        nop; nop; nop;
        nop;nop;nop;nop;nop;nop;nop;nop;nop;nop;nop;nop;
    }
}

debug {
extern(C++)
void GetItemMaxDurability_Hook(void* a1, void* a2, float* durability)
{
    GetItemMaxDurability_Gate(a1, a2, durability);
    if (durability !is null)
    {
        DebugPrint("durability %f", *durability);
        *durability *= g_durabilityMultiplier;
    }
}

extern(C++)
void GetItemMaxDurability_Gate(void* a1, void* a2, float* durability)
{
    asm {
        naked;
        nop;nop;nop;nop;nop;nop;nop;nop;nop;nop;nop;nop;
        nop; nop; nop;
        nop;nop;nop;nop;nop;nop;nop;nop;nop;nop;nop;nop;
    }
}

extern(C++)
void GetItemInitialDurability_Hook(void* a1, void* a2, float* durability)
{
    GetItemInitialDurability_Gate(a1, a2, durability);
    if (durability !is null)
    {
        DebugPrint("initial durability %f", *durability);
        *durability *= g_durabilityMultiplier;
    }
}

extern(C++)
void GetItemInitialDurability_Gate(void* a1, void* a2, float* durability)
{
    asm {
        naked;
        nop;nop;nop;nop;nop;nop;nop;nop;nop;nop;nop;nop;
        nop; nop; nop;
        nop;nop;nop;nop;nop;nop;nop;nop;nop;nop;nop;nop;
    }
}
}

void* GetScriptFunc(const wchar[] name)
{
    auto mod = GetModuleHandleA(null);

    MODULEINFO info;
    if (!GetModuleInformation(GetCurrentProcess(), mod, &info, info.sizeof))
        return null;

    auto base = cast(ubyte*)info.lpBaseOfDll;
    auto size = info.SizeOfImage;

    auto nameAddr = FindBytes(cast(ubyte*)name.ptr, name.length*wchar.sizeof, base, size);
    if (!nameAddr)
        return null;

    auto leaAddr = FindLEARDXForAddr(nameAddr, base, size);
    if (!leaAddr)
        return null;

    // .text:00007FF6B424ED73 48 8D 05 96 6C FF FF    lea rax, GetItemWeight
    ubyte[] lea2 = [0x48, 0x8D, 0x05];
    auto lea2Addr = FindBytesReverse(lea2.ptr, lea2.length, cast(ubyte*)leaAddr, 64);
    if (!lea2Addr)
        return null;

    auto offset = *cast(int*)(lea2Addr+3);
    auto funcAddr = lea2Addr + 7 + offset;

    return funcAddr;
}

// .text:00007FF6B424ED9A 48 8D 15 A7 B3 71 01    lea rdx, aGetitemweight 
void* FindLEARDXForAddr(void* addr, ubyte* mem, size_t size)
{
    ubyte[] lea = [0x48, 0x8D, 0x15];
    foreach (ubyte* i; FindAllBytes(lea, mem, size))
    {
        auto encodedAddr = cast(int)(addr - (i + 7));
        if (*cast(int*)(i+3) == encodedAddr)
        {
            return i;
        }
    }

    return null;
}

void* FindBytes(ubyte* search, size_t size, ubyte* mem, size_t len)
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

void* FindBytesReverse(ubyte* search, size_t size, ubyte* mem, size_t len)
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

ubyte*[] FindAllBytes(const ubyte[] search, ubyte* mem, size_t len)
{
    ubyte*[] ret;
    
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

void WriteJMP(ubyte* src, ubyte* dest, int nops)
{
    uint oldProtect;
    if (VirtualProtect(src, JMP_SIZE+nops, PAGE_EXECUTE_READWRITE, &oldProtect))
    {
        *(src) = 0x48; // mov rax immediate
        *(src+1) = 0xb8;
        *cast(void**)(src+2) = dest;
        *(src+10) = 0xff; // jmp rax
        *(src+11) = 0xe0;

        for (int i = 0; i < nops; i++)
            *(src + JMP_SIZE + i) = 0x90;

        VirtualProtect(src, JMP_SIZE+nops, oldProtect, &oldProtect);
    }
}

void InstallTrampoline(ubyte* src, ubyte* dest, ubyte* gate, int overwritten)
{
    uint oldProtect;
    if (VirtualProtect(gate, overwritten, PAGE_EXECUTE_READWRITE, &oldProtect))
    {
        memcpy(gate, src, overwritten);
        //gate[0..overwritten-1] = src[0..overwritten-1];
        VirtualProtect(gate, overwritten, oldProtect, &oldProtect);
    }

    WriteJMP(gate+overwritten, src+overwritten, 0);
    WriteJMP(src, dest, (overwritten > JMP_SIZE ? overwritten - JMP_SIZE : 0));
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
