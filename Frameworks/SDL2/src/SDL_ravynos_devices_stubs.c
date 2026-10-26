/* Generated device-subsystem stubs: ravynOS has no joystick, game controller,
 * sensor or haptic hardware, so every entry point in those subsystems is
 * present with the exact SDL 2.32 signature and a no-device result.
 *
 * Do not edit by hand. Regenerate with:
 *     python3 tools/bootlab/gen_sdl_device_stubs.py
 */

#include "SDL_ravynos_internal.h"

void SDLCALL SDL_UnlockJoysticks(void) {
}
int SDLCALL SDL_NumJoysticks(void) {
    return (int)0;
}
int SDLCALL SDL_JoystickGetDevicePlayerIndex(int) {
    (void)0;
    return (int)0;
}
SDL_JoystickGUID SDLCALL SDL_JoystickGetDeviceGUID(int) {
    (void)0;
    SDL_JoystickGUID zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
Uint16 SDLCALL SDL_JoystickGetDeviceVendor(int) {
    (void)0;
    Uint16 zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
Uint16 SDLCALL SDL_JoystickGetDeviceProduct(int) {
    (void)0;
    Uint16 zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
Uint16 SDLCALL SDL_JoystickGetDeviceProductVersion(int) {
    (void)0;
    Uint16 zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
SDL_JoystickType SDLCALL SDL_JoystickGetDeviceType(int) {
    (void)0;
    SDL_JoystickType zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
SDL_JoystickID SDLCALL SDL_JoystickGetDeviceInstanceID(int) {
    (void)0;
    SDL_JoystickID zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
int SDLCALL SDL_JoystickAttachVirtual(SDL_JoystickType, int, int, int) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_JoystickDetachVirtual(int) {
    (void)0;
    return (int)0;
}
SDL_bool SDLCALL SDL_JoystickIsVirtual(int) {
    (void)0;
    SDL_bool zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
int SDLCALL SDL_JoystickSetVirtualAxis(SDL_Joystick *, int, Sint16) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_JoystickSetVirtualButton(SDL_Joystick *, int, Uint8) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_JoystickSetVirtualHat(SDL_Joystick *, int, Uint8) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_JoystickGetPlayerIndex(SDL_Joystick *) {
    (void)0;
    return (int)0;
}
void SDLCALL SDL_JoystickSetPlayerIndex(SDL_Joystick *, int) {
    (void)0;
}
SDL_JoystickGUID SDLCALL SDL_JoystickGetGUID(SDL_Joystick *) {
    (void)0;
    SDL_JoystickGUID zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
Uint16 SDLCALL SDL_JoystickGetVendor(SDL_Joystick *) {
    (void)0;
    Uint16 zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
Uint16 SDLCALL SDL_JoystickGetProduct(SDL_Joystick *) {
    (void)0;
    Uint16 zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
Uint16 SDLCALL SDL_JoystickGetProductVersion(SDL_Joystick *) {
    (void)0;
    Uint16 zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
Uint16 SDLCALL SDL_JoystickGetFirmwareVersion(SDL_Joystick *) {
    (void)0;
    Uint16 zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
const char * SDLCALL SDL_JoystickGetSerial(SDL_Joystick *) {
    (void)0;
    return NULL;
}
SDL_JoystickType SDLCALL SDL_JoystickGetType(SDL_Joystick *) {
    (void)0;
    SDL_JoystickType zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
void SDLCALL SDL_JoystickGetGUIDString(SDL_JoystickGUID, char *, int) {
    (void)0;
}
SDL_JoystickGUID SDLCALL SDL_JoystickGetGUIDFromString(const char *) {
    (void)0;
    SDL_JoystickGUID zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
void SDLCALL SDL_GetJoystickGUIDInfo(SDL_JoystickGUID, Uint16 *, Uint16 *, Uint16 *, Uint16 *) {
    (void)0;
}
SDL_bool SDLCALL SDL_JoystickGetAttached(SDL_Joystick *) {
    (void)0;
    SDL_bool zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
SDL_JoystickID SDLCALL SDL_JoystickInstanceID(SDL_Joystick *) {
    (void)0;
    SDL_JoystickID zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
int SDLCALL SDL_JoystickNumAxes(SDL_Joystick *) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_JoystickNumBalls(SDL_Joystick *) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_JoystickNumHats(SDL_Joystick *) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_JoystickNumButtons(SDL_Joystick *) {
    (void)0;
    return (int)0;
}
void SDLCALL SDL_JoystickUpdate(void) {
}
int SDLCALL SDL_JoystickEventState(int) {
    (void)0;
    return (int)0;
}
SDL_bool SDLCALL SDL_JoystickGetAxisInitialState(SDL_Joystick *, int, Sint16 *) {
    (void)0;
    SDL_bool zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
int SDLCALL SDL_JoystickGetBall(SDL_Joystick *, int, int *, int *) {
    (void)0;
    return (int)0;
}
Uint8 SDLCALL SDL_JoystickGetButton(SDL_Joystick *, int) {
    (void)0;
    Uint8 zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
int SDLCALL SDL_JoystickRumble(SDL_Joystick *, Uint16, Uint16, Uint32) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_JoystickRumbleTriggers(SDL_Joystick *, Uint16, Uint16, Uint32) {
    (void)0;
    return (int)0;
}
SDL_bool SDLCALL SDL_JoystickHasLED(SDL_Joystick *) {
    (void)0;
    SDL_bool zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
SDL_bool SDLCALL SDL_JoystickHasRumble(SDL_Joystick *) {
    (void)0;
    SDL_bool zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
SDL_bool SDLCALL SDL_JoystickHasRumbleTriggers(SDL_Joystick *) {
    (void)0;
    SDL_bool zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
int SDLCALL SDL_JoystickSetLED(SDL_Joystick *, Uint8, Uint8, Uint8) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_JoystickSendEffect(SDL_Joystick *, const void *, int) {
    (void)0;
    return (int)0;
}
void SDLCALL SDL_JoystickClose(SDL_Joystick *) {
    (void)0;
}
SDL_JoystickPowerLevel SDLCALL SDL_JoystickCurrentPowerLevel(SDL_Joystick *) {
    (void)0;
    SDL_JoystickPowerLevel zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
int SDLCALL SDL_GameControllerAddMappingsFromRW(SDL_RWops *, int) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_GameControllerNumMappings(void) {
    return (int)0;
}
char * SDLCALL SDL_GameControllerMappingForIndex(int) {
    (void)0;
    return NULL;
}
char * SDLCALL SDL_GameControllerMappingForGUID(SDL_JoystickGUID) {
    (void)0;
    return NULL;
}
char * SDLCALL SDL_GameControllerMapping(SDL_GameController *) {
    (void)0;
    return NULL;
}
SDL_bool SDLCALL SDL_IsGameController(int) {
    (void)0;
    SDL_bool zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
SDL_GameControllerType SDLCALL SDL_GameControllerTypeForIndex(int) {
    (void)0;
    SDL_GameControllerType zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
SDL_GameControllerType SDLCALL SDL_GameControllerGetType(SDL_GameController *) {
    (void)0;
    SDL_GameControllerType zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
int SDLCALL SDL_GameControllerGetPlayerIndex(SDL_GameController *) {
    (void)0;
    return (int)0;
}
void SDLCALL SDL_GameControllerSetPlayerIndex(SDL_GameController *, int) {
    (void)0;
}
Uint16 SDLCALL SDL_GameControllerGetVendor(SDL_GameController *) {
    (void)0;
    Uint16 zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
Uint16 SDLCALL SDL_GameControllerGetProduct(SDL_GameController *) {
    (void)0;
    Uint16 zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
Uint16 SDLCALL SDL_GameControllerGetProductVersion(SDL_GameController *) {
    (void)0;
    Uint16 zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
Uint16 SDLCALL SDL_GameControllerGetFirmwareVersion(SDL_GameController *) {
    (void)0;
    Uint16 zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
const char * SDLCALL SDL_GameControllerGetSerial(SDL_GameController *) {
    (void)0;
    return NULL;
}
Uint64 SDLCALL SDL_GameControllerGetSteamHandle(SDL_GameController *) {
    (void)0;
    Uint64 zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
SDL_bool SDLCALL SDL_GameControllerGetAttached(SDL_GameController *) {
    (void)0;
    SDL_bool zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
int SDLCALL SDL_GameControllerEventState(int) {
    (void)0;
    return (int)0;
}
void SDLCALL SDL_GameControllerUpdate(void) {
}
SDL_GameControllerAxis SDLCALL SDL_GameControllerGetAxisFromString(const char *) {
    (void)0;
    SDL_GameControllerAxis zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
const char* SDLCALL SDL_GameControllerGetStringForAxis(SDL_GameControllerAxis) {
    (void)0;
    return NULL;
}
SDL_GameControllerButtonBind SDLCALL SDL_GameControllerGetBindForAxis(SDL_GameController *, SDL_GameControllerAxis) {
    (void)0;
    SDL_GameControllerButtonBind zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
SDL_bool SDLCALL SDL_GameControllerHasAxis(SDL_GameController *, SDL_GameControllerAxis) {
    (void)0;
    SDL_bool zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
Sint16 SDLCALL SDL_GameControllerGetAxis(SDL_GameController *, SDL_GameControllerAxis) {
    (void)0;
    Sint16 zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
SDL_GameControllerButton SDLCALL SDL_GameControllerGetButtonFromString(const char *) {
    (void)0;
    SDL_GameControllerButton zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
const char* SDLCALL SDL_GameControllerGetStringForButton(SDL_GameControllerButton) {
    (void)0;
    return NULL;
}
SDL_GameControllerButtonBind SDLCALL SDL_GameControllerGetBindForButton(SDL_GameController *, SDL_GameControllerButton) {
    (void)0;
    SDL_GameControllerButtonBind zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
SDL_bool SDLCALL SDL_GameControllerHasButton(SDL_GameController *, SDL_GameControllerButton) {
    (void)0;
    SDL_bool zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
Uint8 SDLCALL SDL_GameControllerGetButton(SDL_GameController *, SDL_GameControllerButton) {
    (void)0;
    Uint8 zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
int SDLCALL SDL_GameControllerGetNumTouchpads(SDL_GameController *) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_GameControllerGetNumTouchpadFingers(SDL_GameController *, int) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_GameControllerGetTouchpadFinger(SDL_GameController *, int, int, Uint8 *, float *, float *, float *) {
    (void)0;
    return (int)0;
}
SDL_bool SDLCALL SDL_GameControllerHasSensor(SDL_GameController *, SDL_SensorType) {
    (void)0;
    SDL_bool zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
int SDLCALL SDL_GameControllerSetSensorEnabled(SDL_GameController *, SDL_SensorType, SDL_bool) {
    (void)0;
    return (int)0;
}
SDL_bool SDLCALL SDL_GameControllerIsSensorEnabled(SDL_GameController *, SDL_SensorType) {
    (void)0;
    SDL_bool zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
float SDLCALL SDL_GameControllerGetSensorDataRate(SDL_GameController *, SDL_SensorType) {
    (void)0;
    return (float)0;
}
int SDLCALL SDL_GameControllerGetSensorData(SDL_GameController *, SDL_SensorType, float *, int) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_GameControllerGetSensorDataWithTimestamp(SDL_GameController *, SDL_SensorType, Uint64 *, float *, int) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_GameControllerRumble(SDL_GameController *, Uint16, Uint16, Uint32) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_GameControllerRumbleTriggers(SDL_GameController *, Uint16, Uint16, Uint32) {
    (void)0;
    return (int)0;
}
SDL_bool SDLCALL SDL_GameControllerHasLED(SDL_GameController *) {
    (void)0;
    SDL_bool zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
SDL_bool SDLCALL SDL_GameControllerHasRumble(SDL_GameController *) {
    (void)0;
    SDL_bool zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
SDL_bool SDLCALL SDL_GameControllerHasRumbleTriggers(SDL_GameController *) {
    (void)0;
    SDL_bool zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
int SDLCALL SDL_GameControllerSetLED(SDL_GameController *, Uint8, Uint8, Uint8) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_GameControllerSendEffect(SDL_GameController *, const void *, int) {
    (void)0;
    return (int)0;
}
void SDLCALL SDL_GameControllerClose(SDL_GameController *) {
    (void)0;
}
const char* SDLCALL SDL_GameControllerGetAppleSFSymbolsNameForButton(SDL_GameController *, SDL_GameControllerButton) {
    (void)0;
    return NULL;
}
const char* SDLCALL SDL_GameControllerGetAppleSFSymbolsNameForAxis(SDL_GameController *, SDL_GameControllerAxis) {
    (void)0;
    return NULL;
}
void SDLCALL SDL_UnlockSensors(void) {
}
int SDLCALL SDL_NumSensors(void) {
    return (int)0;
}
SDL_SensorType SDLCALL SDL_SensorGetDeviceType(int) {
    (void)0;
    SDL_SensorType zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
int SDLCALL SDL_SensorGetDeviceNonPortableType(int) {
    (void)0;
    return (int)0;
}
SDL_SensorID SDLCALL SDL_SensorGetDeviceInstanceID(int) {
    (void)0;
    SDL_SensorID zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
SDL_SensorType SDLCALL SDL_SensorGetType(SDL_Sensor *) {
    (void)0;
    SDL_SensorType zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
int SDLCALL SDL_SensorGetNonPortableType(SDL_Sensor *) {
    (void)0;
    return (int)0;
}
SDL_SensorID SDLCALL SDL_SensorGetInstanceID(SDL_Sensor *) {
    (void)0;
    SDL_SensorID zero;
    SDL_memset(&zero, 0, sizeof(zero));
    return zero;
}
int SDLCALL SDL_SensorGetData(SDL_Sensor *, float *, int) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_SensorGetDataWithTimestamp(SDL_Sensor *, Uint64 *, float *, int) {
    (void)0;
    return (int)0;
}
void SDLCALL SDL_SensorClose(SDL_Sensor *) {
    (void)0;
}
void SDLCALL SDL_SensorUpdate(void) {
}
int SDLCALL SDL_NumHaptics(void) {
    return (int)0;
}
int SDLCALL SDL_HapticOpened(int) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_HapticIndex(SDL_Haptic *) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_MouseIsHaptic(void) {
    return (int)0;
}
int SDLCALL SDL_JoystickIsHaptic(SDL_Joystick *) {
    (void)0;
    return (int)0;
}
void SDLCALL SDL_HapticClose(SDL_Haptic *) {
    (void)0;
}
int SDLCALL SDL_HapticNumEffects(SDL_Haptic *) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_HapticNumEffectsPlaying(SDL_Haptic *) {
    (void)0;
    return (int)0;
}
unsigned int SDLCALL SDL_HapticQuery(SDL_Haptic *) {
    (void)0;
    return (unsigned int)0;
}
int SDLCALL SDL_HapticNumAxes(SDL_Haptic *) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_HapticEffectSupported(SDL_Haptic *, SDL_HapticEffect *) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_HapticNewEffect(SDL_Haptic *, SDL_HapticEffect *) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_HapticUpdateEffect(SDL_Haptic *, int, SDL_HapticEffect *) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_HapticRunEffect(SDL_Haptic *, int, Uint32) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_HapticStopEffect(SDL_Haptic *, int) {
    (void)0;
    return (int)0;
}
void SDLCALL SDL_HapticDestroyEffect(SDL_Haptic *, int) {
    (void)0;
}
int SDLCALL SDL_HapticGetEffectStatus(SDL_Haptic *, int) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_HapticSetGain(SDL_Haptic *, int) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_HapticSetAutocenter(SDL_Haptic *, int) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_HapticPause(SDL_Haptic *) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_HapticUnpause(SDL_Haptic *) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_HapticStopAll(SDL_Haptic *) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_HapticRumbleSupported(SDL_Haptic *) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_HapticRumbleInit(SDL_Haptic *) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_HapticRumblePlay(SDL_Haptic *, float, Uint32) {
    (void)0;
    return (int)0;
}
int SDLCALL SDL_HapticRumbleStop(SDL_Haptic *) {
    (void)0;
    return (int)0;
}
