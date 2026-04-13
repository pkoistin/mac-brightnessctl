#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>
#import <IOKit/hidsystem/ev_keymap.h>
#import "KeyboardManager.h"
#import "BrightnessControl.h"

#define NX_KEYSTATE_DOWN 0x0A

// Attempt a perceptual brightness curve so that each step feels
// equally spaced.  Gamma 3.0 was chosen empirically — it gives
// fine control at the dim end where the eye is most sensitive.
// Coincides with Stevens' power law (1961) for self-luminous sources.
#define kNumSteps 16
#define kGamma    3.0f

static CFMachPortRef gEventTap = NULL;

static float brightnessForStep(int step) {
    return powf((float)step / kNumSteps, kGamma);
}

static int stepForBrightness(float brightness) {
    float normalized = powf(fmaxf(0.0f, fminf(1.0f, brightness)), 1.0f / kGamma);
    return (int)roundf(normalized * kNumSteps);
}

static void adjustKeyboardBrightness(BOOL increase) {
    float current = [BrightnessControl getBrightness];
    int step = stepForBrightness(current);
    step = increase ? MIN(step + 1, kNumSteps) : MAX(step - 1, 0);
    float target = brightnessForStep(step);

    [BrightnessControl setBrightness:target];
    printf("\rKeyboard backlight: %2d/%d", step, kNumSteps);
    fflush(stdout);
}

static CGEventRef eventTapCallback(CGEventTapProxy proxy __unused,
                                   CGEventType type,
                                   CGEventRef event,
                                   void *userInfo __unused) {
    if (type == kCGEventTapDisabledByTimeout ||
        type == kCGEventTapDisabledByUserInput) {
        if (gEventTap) CGEventTapEnable(gEventTap, true);
        return event;
    }

    CGEventFlags flags = CGEventGetFlags(event);
    if (!(flags & kCGEventFlagMaskAlternate)) return event;

    // Brightness media keys (default keyboard mode)
    if (type == NX_SYSDEFINED) {
        NSEvent *nsEvent = [NSEvent eventWithCGEvent:event];
        if (!nsEvent || nsEvent.subtype != NX_SUBTYPE_AUX_CONTROL_BUTTONS)
            return event;

        NSInteger data1 = nsEvent.data1;
        int keyCode  = (data1 >> 16) & 0xFF;
        int keyState = (data1 >>  8) & 0x0F;

        if (keyCode != NX_KEYTYPE_BRIGHTNESS_UP &&
            keyCode != NX_KEYTYPE_BRIGHTNESS_DOWN)
            return event;

        if (keyState == NX_KEYSTATE_DOWN)
            adjustKeyboardBrightness(keyCode == NX_KEYTYPE_BRIGHTNESS_UP);
        return NULL;
    }

    // F1/F2 regular key events ("standard function keys" mode)
    if (type == kCGEventKeyDown || type == kCGEventKeyUp) {
        CGKeyCode keyCode = (CGKeyCode)CGEventGetIntegerValueField(
            event, kCGKeyboardEventKeycode);

        if (keyCode != kVK_F1 && keyCode != kVK_F2) return event;

        if (type == kCGEventKeyDown)
            adjustKeyboardBrightness(keyCode == kVK_F2);
        return NULL;
    }

    return event;
}

int main(int argc __unused, const char *argv[] __unused) {
    @autoreleasepool {
        [KeyboardManager configure];

        printf("Option + Brightness keys -> keyboard backlight (Ctrl+C to quit)\n");

        if (!AXIsProcessTrusted()) {
            NSDictionary *opts = @{
                (__bridge NSString *)kAXTrustedCheckOptionPrompt : @YES
            };
            AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts);
            fprintf(stderr,
                "Error: Accessibility permission required.\n"
                "Grant access in System Settings > Privacy & Security > "
                "Accessibility, then re-run.\n");
            return 1;
        }

        CGEventMask mask = CGEventMaskBit(NX_SYSDEFINED)
                         | CGEventMaskBit(kCGEventKeyDown)
                         | CGEventMaskBit(kCGEventKeyUp);

        gEventTap = CGEventTapCreate(
            kCGSessionEventTap, kCGHeadInsertEventTap,
            kCGEventTapOptionDefault, mask,
            eventTapCallback, NULL);

        if (!gEventTap) {
            fprintf(stderr, "Error: Failed to create event tap.\n");
            return 1;
        }

        CFRunLoopSourceRef src = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault, gEventTap, 0);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopCommonModes);
        CGEventTapEnable(gEventTap, true);

        // Stop the run loop on SIGINT/SIGTERM
        signal(SIGINT, SIG_IGN);
        signal(SIGTERM, SIG_IGN);
        CFRunLoopRef runLoop = CFRunLoopGetCurrent();
        dispatch_source_t sigint = dispatch_source_create(
            DISPATCH_SOURCE_TYPE_SIGNAL, SIGINT, 0,
            dispatch_get_main_queue());
        dispatch_source_t sigterm = dispatch_source_create(
            DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0,
            dispatch_get_main_queue());
        dispatch_source_set_event_handler(sigint,  ^{ CFRunLoopStop(runLoop); });
        dispatch_source_set_event_handler(sigterm, ^{ CFRunLoopStop(runLoop); });
        dispatch_resume(sigint);
        dispatch_resume(sigterm);

        printf("Keyboard backlight: %2d/%d",
               stepForBrightness([BrightnessControl getBrightness]), kNumSteps);
        fflush(stdout);

        CFRunLoopRun();

        printf("\nShutting down.\n");
        CGEventTapEnable(gEventTap, false);
        CFRunLoopRemoveSource(runLoop, src, kCFRunLoopCommonModes);
        CFRelease(src);
        CFRelease(gEventTap);
    }
    return 0;
}
