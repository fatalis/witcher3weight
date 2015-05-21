module windows;

extern(Windows) {
    void OutputDebugStringA(const char* lpPathName);
    bool GetModuleInformation(void* hProcess, void* hModule, MODULEINFO* lpmodinfo, uint cb);
    //uint GetSystemDirectoryA(const char* lpBuffer, uint uSize);
    uint GetPrivateProfileStringA(const char* lpAppName, const char* lpKeyName, const char* lpDefault, char* lpReturnedString, uint nSize, const char* lpFileName);
}

struct MODULEINFO { 
    void* lpBaseOfDll;
    uint  SizeOfImage;
    void* EntryPoint;
};
