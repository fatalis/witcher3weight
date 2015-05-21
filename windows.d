module windows;

extern(Windows) {
    void OutputDebugStringA(const char* lpPathName);
    bool GetModuleInformation(void* hProcess, void* hModule, MODULEINFO* lpmodinfo, uint cb);
    //uint GetSystemDirectoryA(const char* lpBuffer, uint uSize);
}

struct MODULEINFO { 
    void* lpBaseOfDll;
    uint  SizeOfImage;
    void* EntryPoint;
};
