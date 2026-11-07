/*
 * plist.m -- property lists must survive a write/read round trip in the
 * formats our frameworks can write, and the keyed archiver must survive the
 * same trip.  That codec is not academic: AppKit's window-server menu channel
 * serializes with +[NSKeyedArchiver archivedDataWithRootObject:]
 * (NSApplication.m:1160, sendMenusToWindowServer) and reads it back with
 * +[NSKeyedUnarchiver unarchiveObjectWithData:] in the service loop
 * (NSApplication.m:577).  The firefox boot of 2026-11-06 logged, inside
 * that loop, "propertyListFromData: error while decoding plist content :
 * *** Parse error at position 40, line 2. src=*nil*. EOF expected. Next
 * token is <." then "-[NSMutableArray_concrete addObject:] nil object" and
 * finally "menuForApp: not a dictionary" -- the keyed XML payload the writer
 * produced was not being read back, so every app-side menu came back empty.
 *
 * Built with Apple's clang and SDK, like the other fixtures, so a pass is a
 * statement about the frameworks in the guest, not about our headers.
 */

#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>

static int g_failures;

static void
fail(const char *what)
{
	fprintf(stderr, "plist: FAIL %s\n", what);
	g_failures++;
}

/* Show the payload head so the record states what the writer emitted. */
static void
dumpHead(NSData *data, size_t want)
{
	const unsigned char *raw = (const unsigned char *)(const void *)data.bytes;
	size_t n = (size_t)data.length;
	size_t i;

	if(n < want)
	 want = n;
	fputs("plist: payload head ", stderr);
	for(i = 0; i < want; i++){
	 unsigned char c = raw[i];

	 if(c == '\n' || c == '\r' || c == '\t')
		 fputs(" ", stderr);
	 else if(c < 0x20 || c >= 0x7f)
		 fprintf(stderr, "\\x%02x", c);
	 else
		 fwrite(&c, 1, 1, stderr);
	}
	fputs("\n", stderr);
}
/* Print a byte window so a tokenizer complaint can be matched to the bytes
 * it choked over. */
static void
dumpWindow(NSData *data, size_t from, size_t width)
{
	const unsigned char *raw = (const unsigned char *)(const void *)data.bytes;
	size_t n = (size_t)data.length;
	size_t i;

	if(from >= n)
	 return;
	if(from + width > n)
	 width = n - from;
	fputs("plist: payload bytes ", stderr);
	fprintf(stderr, "%lu..%lu: ", (unsigned long)from, (unsigned long)(from + width));
	for(i = from; i < from + width; i++){
	 unsigned char c = raw[i];

	 if(c < 0x20 || c >= 0x7f)
		 fprintf(stderr, "\\x%02x", c);
	 else
		 fwrite(&c, 1, 1, stderr);
	}
	fputs("\n", stderr);
}

/* One graph, checked however it was carried: the item under "data" has to
 * come back with the same class and the same bytes, because
 * -[NSPasteboard dataForType:] (AppKit NSPasteboard.m:377) returns the value
 * untouched and -stringForType: (:385) reads NSData bytes out of it. */
static void
checkPasteboardGraph(id back, const char *label)
{
	const char want[] = "clipboard text";
	NSDictionary *top;
	NSDictionary *items;
	NSArray *names;
	id item;

 top = (NSDictionary *)back;
	if(back == nil || ![back isKindOfClass:[NSDictionary class]] ||
	[top count] != 3){
	 fprintf(stderr, "plist: FAIL %s lost its keys\n", label);
	 g_failures++;
	 return;
		}

 items = [top objectForKey:@"data"];
 names = [top objectForKey:@"types"];
 item = (items != nil) ? [items objectForKey:@"text"] : nil;

 if(items == nil || ![items isKindOfClass:[NSDictionary class]] ||
	[items count] != 1 || item == nil ||
	![names isKindOfClass:[NSArray class]] || [names count] != 1){
	 fprintf(stderr, "plist: FAIL %s lost a container\n", label);
	 g_failures++;
	 return;
		}

 if(![item isKindOfClass:[NSData class]] ||
	[((NSData *)item) length] != (NSUInteger)(sizeof(want) - 1) ||
	(memcmp((const void *)((const unsigned char *)((NSData *)item).bytes),
	 want, sizeof(want) - 1) != 0)){
	 fprintf(stderr, "plist: FAIL %s changed the item's class or bytes\n",
		(label));
	 g_failures++;
	 return;
		}

 fprintf(stderr, "plist: case %s ok\n", label);
	}

/* The graph AppKit's pasteboard keeps on disk: NSPasteboard.m:274 writes a
 * dict with a counter, the type names, and the items as plist bytes; _load
 * at :255 reads it back with NULL for both out parameters. */
static NSDictionary *
buildPasteboardGraph(void)
{
	 const char raw[] = "clipboard text";

	return [NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithInt:7], @"changeCount",
		[NSArray arrayWithObject:(NSString *)@"text"], @"types",
		[NSDictionary dictionaryWithObjectsAndKeys:
			[NSData dataWithBytes:raw length:(sizeof(raw) - 1)], @"text",
			(NSDictionary *)nil], @"data",
		(NSDictionary *)nil];
}

static NSDictionary *
buildDict(void)
{
	return [NSDictionary dictionaryWithObjectsAndKeys:
		@"RAVYN-PLIST-OK", @"marker",
		[NSNumber numberWithInt:42], @"answer",
		[NSNumber numberWithDouble:3.25], @"pi",
		[NSNumber numberWithBool:YES], @"flag",
		[NSData dataWithBytes:"\x00\x01\xfe\xff" length:4], @"blob",
		[NSArray arrayWithObjects:[NSNumber numberWithInt:1], @"two", nil],
			@"list",
		[NSDictionary dictionaryWithObjectsAndKeys:@"inner", @"k", nil],
			@"sub",
		@"<b>&amp;</b>", @"tricky",
		@"plain", @"marker2",
		nil];
}

/*
 * Every shape the writer can emit must come back with the same value:
 * strings (including one whose text needs CDATA), integers, reals, bools
 * (the writer emits <true/>), data, arrays and nested dicts.
 */
static void
checkDict(NSDictionary *back, const char *label, NSUInteger wantKeys)
{
	if(back == nil){
	 fail(label);
	 return;
	}
	if(![back isKindOfClass:[NSDictionary class]]){
	 fail("read back is not a dictionary");
	 return;
	}
	if([back count] != wantKeys){
	 fprintf(stderr, "plist: FAIL %s key count %lu, want %lu\n", label,
		(unsigned long)[back count], (unsigned long)wantKeys);
	 g_failures++;
	}

	{
	 NSString *marker = [back objectForKey:@"marker"];

	 if(marker == nil || ![marker isEqualToString:@"RAVYN-PLIST-OK"])
		 fail("marker string lost");
	}
	{
	 NSNumber *answer = [back objectForKey:@"answer"];

	 if(answer == nil || [answer intValue] != 42)
		 fail("integer 42 lost");
	}
	{
	 NSNumber *pi = [back objectForKey:@"pi"];

	 if(pi == nil || [pi doubleValue] != 3.25)
		 fail("real 3.25 lost");
	}
	{
	 NSNumber *flag = [back objectForKey:@"flag"];

	 if(flag == nil || ![flag boolValue])
		 fail("bool true lost (the writer emits <true/>)");
	}
	{
	 NSString *t = [back objectForKey:@"tricky"];

	 if(t == nil || ![t isEqualToString:@"<b>&amp;</b>"])
		 fail("CDATA string lost (the writer wraps <, > and & in CDATA)");
	}
	{
	 NSData *blob = [back objectForKey:@"blob"];

	 if(blob == nil || (size_t)blob.length != 4 ||
		 memcmp((const void *)blob.bytes, "\x00\x01\xfe\xff", 4) != 0)
		 fail("base64 data blob lost");
	}
	{
	 NSArray *list = [back objectForKey:@"list"];

	 if(list == nil || (size_t)list.count != 2){
		 fail("array of two lost");
		}
	 else {
		 id first = [list objectAtIndex:0];
		 id second = [list objectAtIndex:1];

		 if(first == nil || ![first isKindOfClass:[NSNumber class]] ||
			 [first intValue] != 1)
				 fail("array element 1 lost");
		 if(second == nil || ![second isEqualToString:@"two"])
			 fail("array element two lost");
		 }
	}
	{
	 NSDictionary *sub = [back objectForKey:@"sub"];

	 if(sub == nil)
		 fail("nested dict lost");
	 else {
		 id k = [sub objectForKey:@"k"];

		 if(k == nil || ![k isEqualToString:@"inner"])
			 fail("nested value lost");
		}
	}
	{
	 NSString *m2 = [back objectForKey:@"marker2"];

	 if(m2 == nil || ![m2 isEqualToString:@"plain"])
		 fail("plain second string lost");
	}
}

/*
 * One hand-built document per construct, so a failure names the construct
 * that broke and not merely "the codec".  The prolog+DOCTYPE case is exactly
 * what NSPropertyListWriter_xml1 emits (its header at line 253).
 */
static void
tryXMLText(NSString *xml, const char *label, NSString *expectKey,
	 NSString *expectValue)
{
 fprintf(stderr, "plist: case %s start\n", label);
	if(xml == nil){
	 fprintf(stderr, "plist: FAIL %s (no document given)\n", label);
	 g_failures++;
	 return;
	}

	 NSData *data = [xml dataUsingEncoding:NSUTF8StringEncoding];

	if(data == nil){
	 fprintf(stderr, "plist: FAIL %s (no bytes)\n", label);
	 g_failures++;
	 return;
	}

	 NSString *err = nil;
	 NSPropertyListFormat fmt = (NSPropertyListFormat)0;
	 id back = nil;

	 /* A raise inside one of these calls is still worth its own line in the
	 * record: the case marker printed just before the crash says which
	 * construct raised, and the run ends with a loud exit status.  Apple's
	 * NS_DURING macro cannot catch our raise, so the fixture does not try.
	 */
	 back = [NSPropertyListSerialization propertyListFromData:data
		 mutabilityOption:NSPropertyListMutableContainersAndLeaves
		 format:&fmt errorDescription:&err];

	if(back == nil){
	 fprintf(stderr, "plist: FAIL %s read as nil\n", label);
	 g_failures++;
	 return;
	}
	if(expectKey != nil && ![back isKindOfClass:[NSDictionary class]]){
	 fprintf(stderr, "plist: FAIL %s not a dictionary\n", label);
	 g_failures++;
	 return;
	}
	if(expectKey == nil){
	 fprintf(stderr, "plist: case %s ok (parsed)\n", label);
	 return;
	}

	 id value = [((NSDictionary *)back) objectForKey:expectKey];

	if(value == nil){
	 fprintf(stderr, "plist: FAIL %s key %s has no value\n", label,
		[expectKey UTF8String]);
	 g_failures++;
	 return;
		}

	if(expectValue != nil && ![value isEqualToString:expectValue]){
	 /* Show what the codecs actually produced, so a decoding gap can be
	 * read rather than guessed at; the value in these cases is short. */
	 NSString *shown = [value isKindOfClass:[NSString class]] ?
		(NSString *)value : [value description];
	 fprintf(stderr, "plist: FAIL %s decoded %s wanted %s\n", label,
		[shown UTF8String], [expectValue UTF8String]);
	 if([value isKindOfClass:[NSString class]] &&
		[value length] != [expectValue length]){
	  /* The unit dump says whether a numeric reference turned into one
	  * wrong code unit or into a run of them. */
	  char units[128];
	  NSUInteger n = [value length], written = 0;
	  for(NSUInteger i = 0; i < n && written + 6 < sizeof units; i++)
		written += (NSUInteger)snprintf(units + written, sizeof(units) - written,
		" %x", (unsigned)[value characterAtIndex:i]);
	  units[written] = '\0';
	  fprintf(stderr, "plist: %s units %lu/%lu:%s\n", label,
		(unsigned long)n, (unsigned long)[expectValue length], units);
		}
	 g_failures++;
	 return;
		}

fprintf(stderr, "plist: case %s ok\n", label);
}

/* A document whose root value is an array of mixed scalars: bools in arrays
 * are how Firefox's serialized prefs and the keyed $objects table nest. */
static void
tryXMLArrayText(NSString *xml, const char *label)
{
	 fprintf(stderr, "plist: case %s start\n", label);
	 NSData *data = (xml != nil)? [xml dataUsingEncoding:NSUTF8StringEncoding]
		: nil;
	 NSString *err = nil;
	 NSPropertyListFormat fmt = (NSPropertyListFormat)0;
	 id back = nil;

	 if(data != nil)
		 back = [NSPropertyListSerialization propertyListFromData:data
			 mutabilityOption:NSPropertyListMutableContainersAndLeaves
			 format:&fmt errorDescription:&err];

	if(back == nil || ![back isKindOfClass:[NSArray class]] ||
			 (size_t)((NSArray *)back).count != 4){
	 fprintf(stderr, "plist: FAIL %s array of four not read back\n", label);
	 g_failures++;
	 return;
	}

	 int i;
	 int ints = 0;
	 int strings = 0;
	 int bools = 0;

	for(i = 0; i < (int)((NSArray *)back).count; i++){
	 id obj = [back objectAtIndex:i];

	 if([obj isKindOfClass:[NSNumber class]]){
		 if([obj isKindOfClass:[NSString class]])
			 strings++;
		 else if(strcmp(((NSNumber *)obj).objCType, "c") == 0)
			 bools++;
		 else
			 ints++;
		}
	 else if([obj isKindOfClass:[NSString class]])
		 strings++;
	}
	if(ints != 1 || strings != 2 || bools != 1){
	 fprintf(stderr, "plist: FAIL %s element classes: ints=%d strings=%d "
		"bools=%d\n", label, ints, strings, bools);
	 g_failures++;
	 return;
	}
	fprintf(stderr, "plist: case %s ok\n", label);
}

int
main(void)
{
	 NSDictionary *want = buildDict();
	 const NSUInteger wantKeys = 9;
	 NSString *err = nil;
	 NSPropertyListFormat fmt = (NSPropertyListFormat)0;


	 /* isValidForFormat: gates callers such as NSURL+SOSPlistStore.m:26 and
	 * SFSignInAnalytics.m:123 before they serialize; it used to answer NO
	 * for every graph, which made those callers skip their own plist.
	 */
	 if([NSPropertyListSerialization propertyList:want
		 isValidForFormat:NSPropertyListXMLFormat_v1_0] == NO)
		 fail("isValidForFormat: rejects a graph the writer can emit");


	 /*
	 * 1. The XML plist codec: what the writer emits, read straight back.
	 */
	 NSData *xml = [NSPropertyListSerialization dataFromPropertyList:want
		 format:NSPropertyListXMLFormat_v1_0
		 errorDescription:&err];

	if(xml == nil){
	 fail("no XML plist output");
		}
	else {
	 fprintf(stderr, "plist: xml payload %lu bytes\n",
		(unsigned long)xml.length);
	 dumpHead(xml, 96);
	 id back = [NSPropertyListSerialization propertyListFromData:xml
		 mutabilityOption:NSPropertyListMutableContainersAndLeaves
		 format:&fmt errorDescription:&err];

	 if(back == nil)
		 fail("xml plist read back as nil");
	 else
		 checkDict(back, "xml", wantKeys);
	}

	 /*
	 * 2. The keyed object-graph codec, the exact call pair AppKit's menu
	 * channel uses.
	 */
	 NSData *keyed = [NSKeyedArchiver archivedDataWithRootObject:want];

	if(keyed == nil){
	 fail("keyed archiver produced nothing");
		}
	else {
	 fprintf(stderr, "plist: keyed payload %lu bytes\n",
		(unsigned long)keyed.length);
	 dumpHead(keyed, 96);
	 id back2 = [NSKeyedUnarchiver unarchiveObjectWithData:keyed];

	 if(back2 == nil)
		 fail("keyed read back nil (the menu channel's failure mode)");
	 else
		 checkDict(back2, "keyed", wantKeys);
	}

	 /*
	 * 3. Hand-built documents that isolate one construct each.
	 */
	 tryXMLText(@"<dict><key>probe</key><string>ok</string></dict>",
		"bare dict", @"probe", @"ok");
	 tryXMLText(@"<plist version=\"1.0\"><dict><key>probe</key>"
		"<string>ok</string></dict></plist>",
		"plist wrapper", @"probe", @"ok");
	 tryXMLText(@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
		"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
		"\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
		"<plist version=\"1.0\"><dict><key>probe</key><string>ok</string>"
		"</dict></plist>",
		"prolog plus doctype", @"probe", @"ok");
	 tryXMLText(@"<plist version=\"1.0\"><dict><key>probe</key>"
		"<array><integer>1</integer><string>s</string></array>"
		"</dict></plist>",
		"array value", @"probe", nil);
	 tryXMLText(@"<plist version=\"1.0\"><dict><key>probe</key>"
		"<date>2006-01-02T03:04:05Z</date></dict></plist>",
		"date value", @"probe", nil);
	 tryXMLArrayText(@"<plist version=\"1.0\"><array>"
		"<integer>7</integer><string>s</string><true/><string>t</string>"
		"</array></plist>",
		"mixed array with self-closing true");
	 tryXMLText(@"<dict><key>probe</key><string>a &amp; b &#65; c &lt;@&gt;</string></dict>",
		"bare dict with entities", @"probe", @"a & b A c <@>");

	 tryXMLText(@"<dict><key>probe</key><string>&#65;</string></dict>",
		"lone numeric reference", @"probe", @"A");
	 tryXMLText(@"<dict><key>probe</key><string>a&#65;b</string></dict>",
		"numeric reference inside text", @"probe", @"aAb");
	 tryXMLText(@"<dict><key>probe</key><string>a&amp;b</string></dict>",
		"named reference inside text", @"probe", @"a&b");

	 /* The graph AppKit's pasteboard keeps on disk: NSPasteboard.m:274
	 * writes it with the XML writer and _load at :255 reads it back with
	 * NULL for both out parameters.  The same graph in the old Mac syntax
	 * covers the vintage pair, which has to keep the item's bytes as well
	 * (NSPropertyListWriter_vintage.m:210 writes an unquoted hex literal,
	 * NSPropertyListReader_vintage.m:440 reads it back). */
	 NSDictionary *pboard = buildPasteboardGraph();
	 NSData *pboardXML = [NSPropertyListSerialization dataFromPropertyList:pboard
		format:NSPropertyListXMLFormat_v1_0 errorDescription:NULL];
	 NSData *pboardVintage = [NSPropertyListSerialization
		 dataFromPropertyList:pboard
		 format:NSPropertyListOpenStepFormat errorDescription:&err];

	if(pboardXML != nil){
	 fprintf(stderr, "plist: xml pasteboard payload %lu bytes\n",
		(unsigned long)pboardXML.length);
	 dumpHead(pboardXML, 120);
	 dumpWindow(pboardXML, 40, 56);
	 checkPasteboardGraph([NSPropertyListSerialization propertyListFromData:pboardXML
		 mutabilityOption:NSPropertyListMutableContainers
		 format:NULL errorDescription:NULL],
		"xml pasteboard graph");
		}
	 else
	 fail("xml pasteboard graph: the writer answered nothing");

	if(pboardVintage != nil){
	 fprintf(stderr, "plist: open step pasteboard payload %lu bytes\n",
		(unsigned long)pboardVintage.length);
	 dumpHead(pboardVintage, 150);
	 checkPasteboardGraph([NSPropertyListSerialization propertyListFromData:pboardVintage
		 mutabilityOption:NSPropertyListMutableContainers
		 format:&fmt errorDescription:&err],
		"open step pasteboard graph");
		}
	 else
	 fail("open step pasteboard graph: the writer answered nothing");

	 /* Stock apps put XML-significant characters in plists: menu labels,
	 * window titles and preferences carry & and <, which is exactly what
	 * the measured menu payload was carrying when the tokenizer complained
	 * "Unexpected character < in Tag" and AppKit answered
	 * "menuForApp: not a dictionary".  Both the key and the value have to
	 * come back unchanged. */
	 NSString *tricky = @"AT&T <tag> \"quoted\" 'single'";
	 NSDictionary *escaped = [NSDictionary dictionaryWithObject:tricky forKey:@"a & b < c"];
	 NSData *escapedXML = [NSPropertyListSerialization dataFromPropertyList:escaped
		/* the writer decides the escaping; the reader has to undo it */
		 format:NSPropertyListXMLFormat_v1_0 errorDescription:NULL];

	if(escapedXML != nil){
	 fprintf(stderr, "plist: escaped payload %lu bytes\n",
		(unsigned long)escapedXML.length);
	 dumpHead(escapedXML, 200);
	 id again = [NSPropertyListSerialization propertyListFromData:escapedXML
		 mutabilityOption:NSPropertyListMutableContainers
		 format:NULL errorDescription:NULL];
	 id value = (again != nil) ? [again objectForKey:@"a & b < c"] : nil;

	 if(again == nil || ![again isKindOfClass:[NSDictionary class]] ||
		[again count] != 1 || value == nil ||
		![value isKindOfClass:[NSString class]] ||
		![value isEqualToString:tricky]){
	  fprintf(stderr, "plist: FAIL the escaping changed the string or the key\n");
	  g_failures++;
		}
	 else
	 fprintf(stderr, "plist: case escaping round trip ok\n");
		}
	 else
	 fail("escaping round trip: the writer answered nothing");


	 fprintf(stderr, "plist: %d failures\n", g_failures);
	 return g_failures == 0 ? 0 : 1;
}
