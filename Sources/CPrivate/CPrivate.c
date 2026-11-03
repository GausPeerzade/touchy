#include "CPrivate.h"
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <os/lock.h>
#include <stdatomic.h>
#include <stdio.h>

typedef void *MTDeviceRef;

static CFMutableArrayRef (*MTDeviceCreateList)(void);
static void (*MTRegisterContactFrameCallback)(MTDeviceRef, MTFrameCallback);
static void (*MTUnregisterContactFrameCallback)(MTDeviceRef, MTFrameCallback);
static void (*MTDeviceStart)(MTDeviceRef, int);
static void (*MTDeviceStop)(MTDeviceRef);
static bool (*MTDeviceIsBuiltIn)(MTDeviceRef);
// Haptics are optional: missing symbols just mean no clicks.
static int (*MTDeviceGetDeviceID)(MTDeviceRef, uint64_t *);
static CFTypeRef (*MTActuatorCreateFromDeviceID)(uint64_t);
static int (*MTActuatorOpen)(CFTypeRef);
static int (*MTActuatorClose)(CFTypeRef);
static int (*MTActuatorActuate)(CFTypeRef, int32_t, uint32_t, float, float);

static int (*DisplayServicesGetBrightness)(CGDirectDisplayID, float *);
static int (*DisplayServicesSetBrightness)(CGDirectDisplayID, float);

static CFMutableArrayRef devices;
static MTDeviceRef device;
static MTFrameCallback activeCallback;
static atomic_bool resetPending;
static CFTypeRef actuator;
// Stopping a device isn't known to wait for a callback already running, so a click
// in flight mustn't race with closing the actuator.
static os_unfair_lock actuatorLock = OS_UNFAIR_LOCK_INIT;
static atomic_bool hapticsOn = true;
static CGDirectDisplayID display = kCGNullDirectDisplay;

static void *open_framework(const char *name) {
    char path[256];
    snprintf(path, sizeof path, "/System/Library/PrivateFrameworks/%s.framework/%s", name, name);
    return dlopen(path, RTLD_LAZY | RTLD_LOCAL);
}

static bool load_multitouch(void) {
    static int loaded = -1;
    if (loaded >= 0) return loaded;
    void *h = open_framework("MultitouchSupport");
    if (h) {
        MTDeviceCreateList = dlsym(h, "MTDeviceCreateList");
        MTRegisterContactFrameCallback = dlsym(h, "MTRegisterContactFrameCallback");
        MTUnregisterContactFrameCallback = dlsym(h, "MTUnregisterContactFrameCallback");
        MTDeviceStart = dlsym(h, "MTDeviceStart");
        MTDeviceStop = dlsym(h, "MTDeviceStop");
        MTDeviceIsBuiltIn = dlsym(h, "MTDeviceIsBuiltIn"); // optional
        MTDeviceGetDeviceID = dlsym(h, "MTDeviceGetDeviceID");
        MTActuatorCreateFromDeviceID = dlsym(h, "MTActuatorCreateFromDeviceID");
        MTActuatorOpen = dlsym(h, "MTActuatorOpen");
        MTActuatorClose = dlsym(h, "MTActuatorClose");
        MTActuatorActuate = dlsym(h, "MTActuatorActuate");
    }
    loaded = h && MTDeviceCreateList && MTRegisterContactFrameCallback &&
             MTUnregisterContactFrameCallback && MTDeviceStart && MTDeviceStop;
    return loaded;
}

static bool load_display_services(void) {
    static int loaded = -1;
    if (loaded >= 0) return loaded;
    void *h = open_framework("DisplayServices");
    if (h) {
        DisplayServicesGetBrightness = dlsym(h, "DisplayServicesGetBrightness");
        DisplayServicesSetBrightness = dlsym(h, "DisplayServicesSetBrightness");
    }
    loaded = h && DisplayServicesGetBrightness && DisplayServicesSetBrightness;
    return loaded;
}

bool TPStart(MTFrameCallback callback) {
    if (devices) return true;
    if (!callback || !load_multitouch()) return false;
    devices = MTDeviceCreateList();
    if (!devices) return false;
    CFIndex n = CFArrayGetCount(devices);
    if (n == 0) {
        CFRelease(devices);
        devices = NULL;
        return false;
    }
    // One trackpad only (the built-in one when present), so gesture state never mixes devices.
    device = (MTDeviceRef)CFArrayGetValueAtIndex(devices, 0);
    for (CFIndex i = 0; MTDeviceIsBuiltIn && i < n; i++) {
        MTDeviceRef candidate = (MTDeviceRef)CFArrayGetValueAtIndex(devices, i);
        if (MTDeviceIsBuiltIn(candidate)) { device = candidate; break; }
    }
    // Open the same trackpad's haptic engine; it stays open (idle) for the session.
    uint64_t id;
    if (MTDeviceGetDeviceID && MTActuatorCreateFromDeviceID && MTActuatorOpen && MTActuatorClose &&
        MTActuatorActuate && MTDeviceGetDeviceID(device, &id) == 0 &&
        (actuator = MTActuatorCreateFromDeviceID(id)) && MTActuatorOpen(actuator) != 0) {
        CFRelease(actuator);
        actuator = NULL;
    }
    activeCallback = callback;
    atomic_store(&resetPending, true);
    MTRegisterContactFrameCallback(device, callback);
    MTDeviceStart(device, 0);
    return true;
}

void TPStop(void) {
    if (!devices) return;
    MTUnregisterContactFrameCallback(device, activeCallback);
    MTDeviceStop(device);
    os_unfair_lock_lock(&actuatorLock);
    if (actuator) {
        MTActuatorClose(actuator);
        CFRelease(actuator);
        actuator = NULL;
    }
    os_unfair_lock_unlock(&actuatorLock);
    CFRelease(devices);
    devices = NULL;
    device = NULL;
    activeCallback = NULL;
}

void TPSetHapticsEnabled(bool on) {
    atomic_store(&hapticsOn, on);
}

void TPHaptic(bool strong) {
    // 3 and 6 are the light and firm clicks of the Force Touch engine.
    if (!atomic_load_explicit(&hapticsOn, memory_order_relaxed)) return;
    os_unfair_lock_lock(&actuatorLock);
    if (actuator) MTActuatorActuate(actuator, strong ? 6 : 3, 0, 0, 0);
    os_unfair_lock_unlock(&actuatorLock);
}

bool TPTakeReset(void) {
    return atomic_load_explicit(&resetPending, memory_order_relaxed) && atomic_exchange(&resetPending, false);
}

static CGDirectDisplayID builtin_display(void) {
    CGDirectDisplayID ids[16];
    uint32_t n = 0;
    if (CGGetOnlineDisplayList(16, ids, &n) != kCGErrorSuccess) return kCGNullDirectDisplay;
    for (uint32_t i = 0; i < n; i++)
        if (CGDisplayIsBuiltin(ids[i])) return ids[i];
    return kCGNullDirectDisplay;
}

bool TPGetBrightness(float *value) {
    if (!value || !load_display_services()) return false;
    display = builtin_display();
    return display != kCGNullDirectDisplay && DisplayServicesGetBrightness(display, value) == 0;
}

void TPSetBrightness(float value) {
    if (display != kCGNullDirectDisplay && load_display_services())
        DisplayServicesSetBrightness(display, value);
}
