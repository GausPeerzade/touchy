#pragma once
#include <stdbool.h>

// Layout of a contact as delivered by the private MultitouchSupport framework.
typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position, velocity; } MTVector;

typedef struct {
    int frame;
    double timestamp;
    int identifier;
    int state;          // 3 = make touch, 4 = touching; other values are hover/lift
    int fingerID;
    int handID;
    MTVector normalized; // 0...1, origin at the bottom-left of the trackpad
    float total;
    float pressure;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absolute;
    int field14;
    int field15;
    float density;
} MTTouch;

typedef void (*MTFrameCallback)(void *device, const MTTouch *touches, int count, double timestamp, int frame);

// Starts contact callbacks on the built-in trackpad (or the first one found). Main thread only.
bool TPStart(MTFrameCallback callback);
void TPStop(void);
// True once after each TPStart, so the callback thread can drop state from a previous session.
bool TPTakeReset(void);

// Clicks the trackpad's haptic engine. Safe to call from the callback thread; no-op if unsupported.
void TPHaptic(bool strong);
void TPSetHapticsEnabled(bool on);

// Built-in display brightness (0...1). Get also caches the display that Set writes to.
bool TPGetBrightness(float *value);
void TPSetBrightness(float value);
