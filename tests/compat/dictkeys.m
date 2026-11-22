/*
 * dictkeys.m -- Foundation dictionary key semantics fixture.
 *
 * WindowServer keys its per-pid app registry with
 *   [[NSString alloc] initWithFormat:@"%d", pid]
 * and macOS code assumes two such strings with different digits are
 * different dictionary keys.  This fixture exercises exactly that
 * (plus the +stringWithFormat and stringWithCString variants) against
 * the guest Foundation, printing counts and lookup results so a broken
 * hash/equality bridge shows up as numbers, not as a bare desktop.
 */

#import <Foundation/Foundation.h>
#import <stdio.h>

static int failures;

static void
check(const char *name, int ok, const char *detail)
{
    fprintf(stderr, "%s %s%s%s\n", ok ? "PASS" : "FAIL", name,
        ok ? "" : ": ", ok ? "" : (detail ? detail : "failed"));
    if (!ok)
        failures++;
}

int
main(void)
{
    /* 1. alloc/initWithFormat keys, as WindowServer builds them. */
    NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
    NSString *k44 = [[NSString alloc] initWithFormat:@"%d", 44];
    NSString *k45 = [[NSString alloc] initWithFormat:@"%d", 45];
    [d setObject:@"a" forKey:k44];
    [d setObject:@"b" forKey:k45];
    fprintf(stderr, "dictkeys: initWithFormat count after 2 inserts = %lu\n",
        (unsigned long)[d count]);
    check("initWithFormat two keys distinct", [d count] == 2, "count != 2");

    NSString *k44b = [[NSString alloc] initWithFormat:@"%d", 44];
    id v = [d objectForKey:k44b];
    check("initWithFormat re-lookup finds value", [v isEqualToString:@"a"],
        v ? "wrong value" : "not found");

    /* 2. The same, via +stringWithFormat (different code path). */
    NSMutableDictionary *e = [NSMutableDictionary new];
    [e setObject:@"a" forKey:[NSString stringWithFormat:@"%d", 44]];
    [e setObject:@"b" forKey:[NSString stringWithFormat:@"%d", 45]];
    fprintf(stderr, "dictkeys: stringWithFormat count after 2 inserts = %lu\n",
        (unsigned long)[e count]);
    check("stringWithFormat two keys distinct", [e count] == 2, "count != 2");

    /* 3. Cross-class equality: format key vs cString key with the same
     * text -- CFEqual's bridge must see them as one key. */
    NSMutableDictionary *f = [NSMutableDictionary new];
    NSString *cf = [[NSString alloc] initWithFormat:@"%d", 7];
    NSString *cs = [NSString stringWithCString:"7"];
    [f setObject:@"one" forKey:cf];
    id w = [f objectForKey:cs];
    check("format key equals cString key", [w isEqualToString:@"one"],
        w ? "wrong value" : "not found");

    /* 4. Removal by a fresh equal key. */
    [f removeObjectForKey:[NSString stringWithCString:"7"]];
    check("removeObject by equal key", [f count] == 0, "count != 0");

    return failures ? 1 : 0;
}
