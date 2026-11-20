// screeninfo.m -- print the screen metrics a stock application sees.
//
// Firefox sizes its browser window from the screen it is told it has.  When it
// asked for a 3x33 window, the question was whether it got a degenerate screen
// (or queried CoreGraphics rather than AppKit and got something else again),
// so measure both paths from a stock-built binary, not from the tree's source.
//
// Prints one SCREEN line per screen, then the CoreGraphics answers, then a
// verdict line: SCREEN-OK when the main screen is at least 640x480.
#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import <stdio.h>

int main(int argc, char **argv) {
    @autoreleasepool {
        NSArray *screens = [NSScreen screens];
        printf("SCREEN-COUNT: %d\n", (int)[screens count]);
        printf("SCREEN-MAIN:  %s\n", [NSScreen mainScreen] ? "yes" : "null");

        for (NSScreen *s in screens) {
            NSRect f = [s frame];
            NSRect v = [s visibleFrame];
            NSNumber *num = [[s deviceDescription] objectForKey:@"NSScreenNumber"];
            printf("SCREEN %u frame=%.0f,%.0f %.0fx%.0f visible=%.0f,%.0f %.0fx%.0f"
                   " scale=%.2f num=%u\n",
                   (unsigned)num.unsignedIntValue,
                   f.origin.x, f.origin.y, f.size.width, f.size.height,
                   v.origin.x, v.origin.y, v.size.width, v.size.height,
                   [s backingScaleFactor], (unsigned)num.unsignedIntValue);
        }

        // The same information through CoreGraphics, which is what the widget
        // layer reads for pixel geometry.
        CGDirectDisplayID d = CGMainDisplayID();
        CGRect b = CGDisplayBounds(d);
        printf("CG main=%u bounds=%.0f,%.0f %.0fx%.0f pixels=%zux%zu mm=%.0fx%.0f\n",
               (unsigned)d, b.origin.x, b.origin.y, b.size.width, b.size.height,
               CGDisplayPixelsWide(d), CGDisplayPixelsHigh(d),
               CGDisplayScreenSize(d).width, CGDisplayScreenSize(d).height);

        // "How many displays are there?" is CGGetActiveDisplayList(0, NULL, &n)
        // -- the count must be the real number of displays, not the number that
        // fitted in a zero-length array.  Then enumerate for real.
        uint32_t n = 0;
        CGError e0 = CGGetActiveDisplayList(0, NULL, &n);
        CGDirectDisplayID ids[8] = {0};
        uint32_t got = 0;
        CGError e1 = CGGetActiveDisplayList(8, ids, &got);
        printf("CG active displays: count=%u err=%d  enumerated=%u err=%d first=%u\n",
               (unsigned)n, (int)e0, (unsigned)got, (int)e1, (unsigned)ids[0]);

        BOOL enum_ok = n >= 1 && got >= 1 && ids[0] == (CGDirectDisplayID)d;
        printf("CG-ENUM-%s\n", enum_ok ? "OK" : "FAIL");

        // Firefox also reads the menu-bar height and the dock height off the
        // visible frame; report the two insets explicitly.
        NSScreen *m = [NSScreen mainScreen];
        if (m) {
            NSRect f = [m frame], v = [m visibleFrame];
            printf("INSETS top=%.0f bottom=%.0f left=%.0f right=%.0f\n",
                   NSMaxY(f) - NSMaxY(v), NSMinY(v) - NSMinY(f),
                   NSMinX(v) - NSMinX(f), NSMaxX(f) - NSMaxX(v));
        }

        BOOL ok = m != nil && [m frame].size.width >= 640 && [m frame].size.height >= 480 && enum_ok;
        printf("SCREEN-%s\n", ok ? "OK" : "FAIL");
        return ok ? 0 : 1;
    }
}
