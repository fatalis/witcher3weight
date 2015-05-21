module wrapper;

export {
    extern (Windows)
    void* DirectInput8Create(void* hinst, uint dwVersion, void* riidltf, void** ppvOut, void* punkOuter)
    {
        if (!DirectInput8Create_Real)
            return null;
        return DirectInput8Create_Real(hinst, dwVersion, riidltf, ppvOut, punkOuter);
    }
}

__gshared {
    extern (Windows)
    void* function(void* hinst, uint dwVersion, void* riidltf, void** ppvOut, void* punkOuter) DirectInput8Create_Real = null;
}