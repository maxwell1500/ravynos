extern "C" void __libcxx_exp_memrsc_init() noexcept;
extern "C" void __libcxx_ios_init() noexcept;
extern "C" void __libcxx_memrsc_init() noexcept;
extern "C" void __libcxx_init(void);

void __libcxx_init(void)
{
    __libcxx_exp_memrsc_init();
    __libcxx_ios_init();
    __libcxx_memrsc_init();
}

