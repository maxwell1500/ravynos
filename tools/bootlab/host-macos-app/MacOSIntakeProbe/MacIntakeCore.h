#ifndef MAC_INTAKE_CORE_H
#define MAC_INTAKE_CORE_H

#ifdef __cplusplus
extern "C" {
#endif

/* Returns 'MACI' when the embedded dylib was loaded at all. */
int MacIntakeCoreMagic(void);

#ifdef __cplusplus
}
#endif

#endif /* MAC_INTAKE_CORE_H */
