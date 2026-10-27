/*
 * The UEFI (efi64) entry points of libffi.
 *
 * libffi exports ffi_call_efi64 and friends for the Microsoft/UEFI calling
 * convention.  ravynOS does not implement that ABI; these functions report
 * FFI_BAD_ABI (1) instead of jumping into a calling convention the platform
 * does not support.  A caller that asks for it gets a defined error.
 */
#include "ffi.h"

ffi_status ffi_prep_cif_machdep_efi64(ffi_cif *cif)
{
	(void)cif;
	return FFI_BAD_ABI;
}

void ffi_call_efi64(ffi_cif *cif, void (*fn)(void), void *rvalue, void **avalue)
{
	(void)cif; (void)fn; (void)rvalue; (void)avalue;
}

ffi_status ffi_prep_closure_loc_efi64(ffi_closure *closure, ffi_cif *cif,
                                      void (*fun)(ffi_cif *, void *, void **, void *),
                                      void *user_data, void *codeloc)
{
	(void)closure; (void)cif; (void)fun; (void)user_data; (void)codeloc;
	return FFI_BAD_ABI;
}

ffi_status ffi_prep_go_closure_efi64(ffi_go_closure *closure, ffi_cif *cif,
                                     void (*fun)(ffi_cif *, void *, void **, void *))
{
	(void)closure; (void)cif; (void)fun;
	return FFI_BAD_ABI;
}

void ffi_call_go_efi64(ffi_cif *cif, void (*fn)(void), void *rvalue,
                       void **avalue, void *closure)
{
	(void)cif; (void)fn; (void)rvalue; (void)avalue; (void)closure;
}
