/*
 * ravynOS LaunchServices
 *
 * Copyright (C) 2021-2022 Zoe Knox <zoe@pixin.net>
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import <Foundation/NSRaiseException.h>
#import <Foundation/NSPlatform.h>
#import <CoreFoundation/CoreFoundation.h>
#import "LaunchServices.h"
#import "LaunchServices_private.h"
#import "UTTypes.h"
#import "UTTypes-private.h"

#include <sqlite3.h>
#include <stdio.h>
#include <unistd.h>
#include <cstddef>
#ifdef _REWRITE_ME_
#include <QDBusConnection>
#include <QDBusInterface>
#include <QMimeDatabase>
#include <QMimeType>
#endif // _REWRITE_ME_

#import <launch.h>
#import <stdlib.h>
#import <limits.h>

#import <WindowServer/message.h>
#include <mach/mach.h>
#include <servers/bootstrap.h>

extern "C" {
extern mach_port_t bootstrap_port;
extern void bootstrap_init(void);
}

#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE 500
#endif

//#include <X11/Xlib.h>

#define _NET_WM_STATE_REMOVE 0
#define _NET_WM_STATE_ADD 1
#define _NET_WM_STATE_TOGGLE 2

static NSString *_LSSQLResourcePath(NSString *base);

@implementation LaunchServices
+database {
    static NSString *db = nil;

    if(db == nil) {
        /* The per-user directory does not exist on a freshly imaged system,
         * and /var/db is not writable for an ordinary user: create the
         * directory, and fall back to /var/tmp when that is impossible. */
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *dir = [NSString stringWithFormat:
            @"/var/db/launchd/com.apple.launchd.peruser.%u", getuid()];
        NSString *path = [dir stringByAppendingPathComponent:@"launchservices.db"];

        if(![fm fileExistsAtPath:dir])
            [fm createDirectoryAtPath:dir withIntermediateDirectories:YES
                            attributes:nil error:NULL];

        if(![fm fileExistsAtPath:dir] || ![fm isWritableFileAtPath:dir]) {
            NSString *fallback = [NSString stringWithFormat:@"/var/tmp/launchservices_%u.db", getuid()];
            path = fallback;
        }
        db = path;
    }
    return db;
}
@end

// FIXME: which error code to return for each case is just a guess

//------------------------------------------------------------------------
//    INTERNAL FUNCTIONS - DON'T USE. SEE BELOW FOR PUBLIC API
//------------------------------------------------------------------------

static BOOL _LSCheckAndUpdateSchema()
{
    const int desiredSchema = 4;

    sqlite3 *pDB = 0;
    if(sqlite3_open([[LaunchServices database] UTF8String], &pDB) != SQLITE_OK) {
        sqlite3_close(pDB);
        return false; // FIXME: log error somewhere
    }

    int currentSchema = 0;
    const char *query = "SELECT version FROM schema";
    size_t length = strlen(query);
    sqlite3_stmt *stmt;
    const char *tail;

    if(sqlite3_prepare_v2(pDB, query, length, &stmt, &tail) != SQLITE_OK) {
        sqlite3_close(pDB);
        return false;
    }

    if(sqlite3_step(stmt) != SQLITE_ROW) {
        sqlite3_finalize(stmt);
        sqlite3_close(pDB);
        return false;
    }

    currentSchema = sqlite3_column_int(stmt, 0);
    sqlite3_finalize(stmt);

    // Iterate the schema updates until we are at the latest
    while(currentSchema < desiredSchema) {
        NSString *schemaFile = [NSString stringWithFormat:@"DBSchema_%d_%d", currentSchema, currentSchema+1];
        NSString *sqlPath = _LSSQLResourcePath(schemaFile);
        if(sqlPath == nil) {
    	    NSLog(@"ERROR: cannot find %@.sql to update launchservices.db schema", schemaFile);
        } else {
            FILE *sql = fopen([sqlPath UTF8String], "r");
	        char *line;
            if(sql == NULL) {
                sqlite3_close(pDB);
                return false;
            }
            line = fgetln(sql, &length);

        	while(length > 0) {
	            if(sqlite3_prepare_v2(pDB, line, length, &stmt, &tail) != SQLITE_OK) {
	    	        sqlite3_close(pDB);
		            fclose(sql);
		            return false;
	            }
	            sqlite3_step(stmt);
	            sqlite3_finalize(stmt);
	            line = fgetln(sql, &length);
	        }
        }
        ++currentSchema;
    }

    sqlite3_close(pDB);
    return true;
}

static BOOL _LSAddRecordToDatabase(const LSAppRecord *appRecord, BOOL isUpdate);

/* Register one bundle: the applications row plus the typemap rows that
 * make it the handler for the types it declares. */
static void _LSRegisterBundle(NSString *path)
{
    NSURL *appURL = [NSURL fileURLWithPath:path];
    LSAppRecord *record = [[LSAppRecord alloc] initWithURL:appURL];
    NSArray *docTypes = [record documentTypes];
    sqlite3 *pDB = NULL;
    unsigned i;

    if(record == nil)
        return;

    _LSAddRecordToDatabase(record, NO);

    if(sqlite3_open([[LaunchServices database] UTF8String], &pDB) != SQLITE_OK) {
        sqlite3_close(pDB);
        return;
    }

    for(i = 0; i < [docTypes count]; i++) {
        NSDictionary *docType = [docTypes objectAtIndex:i];
        NSMutableArray *utis = [NSMutableArray array];
        NSArray *declared = [docType objectForKey:@"LSItemContentTypes"];
        NSArray *extensions = [docType objectForKey:@"CFBundleTypeExtensions"];
        unsigned j;

        if(declared != nil)
            [utis addObjectsFromArray:declared];

        /* The legacy key: an extension is turned into its uniform type. */
        for(j = 0; extensions != nil && j < [extensions count]; j++) {
            NSString *ext = [extensions objectAtIndex:j];
            CFStringRef uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,
                                                                   (__bridge CFStringRef)ext, NULL);
            if(uti != NULL) {
                NSString *s = (__bridge_transfer NSString *)uti;
                if(![utis containsObject:s])
                    [utis addObject:s];
            }
        }

        for(j = 0; j < [utis count]; j++) {
            NSString *uti = [utis objectAtIndex:j];
            sqlite3_stmt *stmt = NULL;
            if(sqlite3_prepare_v2(pDB,
                    "INSERT OR IGNORE INTO typemap (uti, application, rank) VALUES (?1,?2,?3)",
                    -1, &stmt, NULL) != SQLITE_OK)
                continue;
            sqlite3_bind_text(stmt, 1, [uti UTF8String], [uti length], SQLITE_STATIC);
            sqlite3_bind_text(stmt, 2, [[appURL absoluteString] UTF8String],
                              [[appURL absoluteString] length], SQLITE_STATIC);
            sqlite3_bind_int(stmt, 3, 100);
            sqlite3_step(stmt);
            sqlite3_finalize(stmt);
        }
    }

    sqlite3_close(pDB);
}

/* Scan the standard application directories and register every bundle that
 * is not in the database yet.  Runs once per database: the applications
 * table is empty on a freshly imaged system. */
static BOOL _LSEnsureDatabasePopulated(void)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *searchDirs = [NSArray arrayWithObjects:@"/Applications",
                            @"/Applications/Utilities",
                            @"/System/Library/CoreServices", nil];
    sqlite3 *pDB = NULL;
    int count = 0;
    unsigned i;

    if(sqlite3_open([[LaunchServices database] UTF8String], &pDB) != SQLITE_OK) {
        sqlite3_close(pDB);
        return NO;
    }

    {
        sqlite3_stmt *stmt = NULL;
        if(sqlite3_prepare_v2(pDB, "SELECT count(*) FROM applications", -1, &stmt, NULL) == SQLITE_OK) {
            if(sqlite3_step(stmt) == SQLITE_ROW)
                count = sqlite3_column_int(stmt, 0);
            sqlite3_finalize(stmt);
        }
    }
    if(count > 0) {
        sqlite3_close(pDB);
        return YES;
    }

    for(i = 0; i < [searchDirs count]; i++) {
        NSString *dir = [searchDirs objectAtIndex:i];
        NSArray *entries = [fm contentsOfDirectoryAtPath:dir error:NULL];
        unsigned j;

        if(entries == nil)
            continue;
        for(j = 0; j < [entries count]; j++) {
            NSString *name = [entries objectAtIndex:j];
            NSString *path;

            if(![name hasSuffix:@".app"])
                continue;
            path = [dir stringByAppendingPathComponent:name];
            if(![fm fileExistsAtPath:path])
                continue;
            _LSRegisterBundle(path);
        }
    }

    sqlite3_close(pDB);
    return YES;
}

/* Resources of a framework live under Versions/A/Resources.  This image has
 * no symlinks (the FAT32 boot volume cannot hold them), so the framework's
 * top-level Resources/Contents link does not exist and -pathForResource:
 * fails.  Fall back to the versioned directory explicitly. */
static NSString *_LSSQLResourcePath(NSString *base)
{
    NSString *name = [base stringByAppendingPathExtension:@"sql"];
    NSString *path = [[NSBundle bundleForClass:[LaunchServices class]]
                      pathForResource:base ofType:@"sql"];

    if(path != nil)
        return path;

    {
        NSArray *candidates = [NSArray arrayWithObjects:
            [@"/System/Library/Frameworks/LaunchServices.framework/Versions/A/Resources/" stringByAppendingString:name],
            [@"/System/Library/Frameworks/LaunchServices.framework/Resources/" stringByAppendingString:name],
            nil];
        unsigned i;

        for(i = 0; i < [candidates count]; i++)
            if([[NSFileManager defaultManager] fileExistsAtPath:[candidates objectAtIndex:i]])
                return [candidates objectAtIndex:i];
    }
    return nil;
}

static BOOL _LSInitializeDatabase()
{
    NSFileManager *fm = [NSFileManager defaultManager];
    if([fm fileExistsAtPath:[LaunchServices database]]) {
        BOOL ok = _LSCheckAndUpdateSchema();
        if(ok)
            _LSEnsureDatabasePopulated();
        return ok;
    }

    [fm createFileAtPath:[LaunchServices database] contents:[NSData new] attributes:[NSDictionary new]];

    sqlite3 *pDB = 0;
    if(sqlite3_open([[LaunchServices database] UTF8String], &pDB) != SQLITE_OK) {
        sqlite3_close(pDB);
        return false; // FIXME: log error somewhere
    }

    // Create and populate the DB from our resource file
    NSString *sqlPath = _LSSQLResourcePath(@"InitDB");
    if(sqlPath == nil) {
    	NSLog(@"ERROR: cannot find InitDB.sql to init launchservices.db");
        /* Without the schema every later query fails; report the database as
         * unusable instead of querying tables that do not exist. */
        sqlite3_close(pDB);
        return false;
    } else {
        sqlite3_stmt *stmt;
        const char *tail;
        FILE *sql = fopen([sqlPath UTF8String], "r");
	size_t length;
	char *line = fgetln(sql, &length);

	while(length > 0) {
	    if(sqlite3_prepare_v2(pDB, line, length, &stmt, &tail) != SQLITE_OK) {
	    	sqlite3_close(pDB);
		fclose(sql);
		return false;
	    }
	    sqlite3_step(stmt);
	    sqlite3_finalize(stmt);
	    line = fgetln(sql, &length);
	}
    }
    sqlite3_close(pDB);
    return true;
}

BOOL LSFindRecordInDatabase(const NSURL *appURL, LSAppRecord **appRecord)
{
    sqlite3 *pDB = 0;
    if(sqlite3_open([[LaunchServices database] UTF8String], &pDB) != SQLITE_OK) {
        sqlite3_close(pDB);
        return false; // FIXME: log error somewhere
    }
    
    const char *query = "SELECT * FROM applications WHERE url=? OR basename=?";
    const int length = strlen(query);
    sqlite3_stmt *stmt;
    const char *tail;

    if(sqlite3_prepare_v2(pDB, query, length, &stmt, &tail) != SQLITE_OK) {
        sqlite3_close(pDB);
        return false;
    }

    if(sqlite3_bind_text(stmt, 1, [[appURL absoluteString] UTF8String], [[appURL absoluteString] length], SQLITE_STATIC) != SQLITE_OK
        || sqlite3_bind_text(stmt, 2, [[appURL lastPathComponent] UTF8String], [[appURL lastPathComponent] length], SQLITE_STATIC) != SQLITE_OK)
    {
        sqlite3_finalize(stmt);
        sqlite3_close(pDB);
        return false;
    }

    int rc = sqlite3_step(stmt);
    if(rc == SQLITE_ROW) {
        NSData *blob = [[NSData alloc]
            initWithBytes:sqlite3_column_blob(stmt, 3)
            length:sqlite3_column_bytes(stmt, 3)];
        *appRecord = [NSKeyedUnarchiver unarchiveObjectWithData:blob];
    }

    sqlite3_finalize(stmt);
    sqlite3_close(pDB);
    return (rc == SQLITE_ROW) ? true : false;
}

BOOL LSFindRecordInDatabaseByBundleID(const NSString *bundleID, LSAppRecord **appRecord)
{
    sqlite3 *pDB = 0;
    if(sqlite3_open([[LaunchServices database] UTF8String], &pDB) != SQLITE_OK) {
        sqlite3_close(pDB);
        return false; // FIXME: log error somewhere
    }
    
    const char *query = "SELECT * FROM applications WHERE bundleid=?";
    const int length = strlen(query);
    sqlite3_stmt *stmt;
    const char *tail;

    if(sqlite3_prepare_v2(pDB, query, length, &stmt, &tail) != SQLITE_OK) {
        sqlite3_close(pDB);
        return false;
    }

    if(sqlite3_bind_text(stmt, 1, [bundleID UTF8String], [bundleID length], SQLITE_STATIC) != SQLITE_OK)
    {
        sqlite3_finalize(stmt);
        sqlite3_close(pDB);
        return false;
    }

    int rc = sqlite3_step(stmt);
    if(rc == SQLITE_ROW) {
        NSData *blob = [[NSData alloc]
            initWithBytes:sqlite3_column_blob(stmt, 3)
            length:sqlite3_column_bytes(stmt, 3)];
        *appRecord = [NSKeyedUnarchiver unarchiveObjectWithData:blob];
    }

    sqlite3_finalize(stmt);
    sqlite3_close(pDB);
    return (rc == SQLITE_ROW) ? true : false;
}

OSStatus LSFindAppsForUTI(NSString *uti, NSMutableArray **outAppURLs)
{
    sqlite3 *pDB = 0;
    if(sqlite3_open([[LaunchServices database] UTF8String], &pDB) != SQLITE_OK) {
        sqlite3_close(pDB);
        return kLSServerCommunicationErr; // FIXME: log error somewhere
    }
    
    const char *query = "SELECT application,rank FROM typemap WHERE uti=? ORDER BY rank ASC";
    const int length = strlen(query);
    sqlite3_stmt *stmt;
    const char *tail;

    if(sqlite3_prepare_v2(pDB, query, length, &stmt, &tail) != SQLITE_OK) {
        sqlite3_close(pDB);
        return kLSServerCommunicationErr;
    }

    if(sqlite3_bind_text(stmt, 1, [uti UTF8String], [uti length], SQLITE_STATIC) != SQLITE_OK) {
        sqlite3_finalize(stmt);
        sqlite3_close(pDB);
        return kLSServerCommunicationErr;
    }

    int rc = sqlite3_step(stmt);
    if(rc != SQLITE_ROW) {
        sqlite3_finalize(stmt);
        return kLSApplicationNotFoundErr;
    }

    for(; rc == SQLITE_ROW; rc = sqlite3_step(stmt)) {
        NSString *url = [NSString stringWithCString:(const char *)sqlite3_column_text(stmt, 0)];
        [*outAppURLs addObject:[NSURL URLWithString:url]];
    }

    sqlite3_finalize(stmt);
    sqlite3_close(pDB);
    return 0;
}

static BOOL _LSAddRecordToDatabase(const LSAppRecord *appRecord, BOOL isUpdate) {
    sqlite3 *pDB = 0;
    if(sqlite3_open([[LaunchServices database] UTF8String], &pDB) != SQLITE_OK) {
        sqlite3_close(pDB);
        return false; // FIXME: log error somewhere
    }
    
    sqlite3_busy_timeout(pDB, 1000);

    const char *query;
    if(isUpdate)
        query = "UPDATE applications SET basename=?2, version=?3, apprecord=?4, bundleid=?5 WHERE url=?1";
    else
        query = "INSERT INTO applications (url,basename,version,apprecord,bundleid) VALUES (?1,?2,?3,?4,?5)";
    int length = strlen(query);
    sqlite3_stmt *stmt;
    const char *tail;

    if(sqlite3_prepare_v2(pDB, query, length, &stmt, &tail) != SQLITE_OK) {
        sqlite3_close(pDB);
        return false;
    }

    NSString *bundleID = [NSString new];
    NSBundle *b = [NSBundle bundleWithPath:[[appRecord URL] path]];
    if(b)
        bundleID = [b bundleIdentifier];

    NSData *blob = [NSKeyedArchiver archivedDataWithRootObject:appRecord];
    if(sqlite3_bind_text(stmt, 1, [[[appRecord URL] absoluteString] UTF8String], [[[appRecord URL] absoluteString] length], SQLITE_STATIC) != SQLITE_OK
        || sqlite3_bind_text(stmt, 2, [[[appRecord URL] lastPathComponent] UTF8String], [[[appRecord URL] lastPathComponent] length], SQLITE_STATIC) != SQLITE_OK
        || sqlite3_bind_int(stmt, 3, [appRecord version]) != SQLITE_OK
        || sqlite3_bind_blob(stmt, 4, [blob bytes], [blob length], SQLITE_STATIC) != SQLITE_OK
        || sqlite3_bind_text(stmt, 5, [bundleID UTF8String], [bundleID length], SQLITE_STATIC) != SQLITE_OK)
    {
        sqlite3_finalize(stmt);
        sqlite3_close(pDB);
        return false;
    }

    int rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    if(rc != SQLITE_DONE) {
        sqlite3_close(pDB);
        return false;
    }

    query = "DELETE FROM typemap WHERE application = ?";
    length = strlen(query);

    if(sqlite3_prepare_v2(pDB, query, length, &stmt, &tail) != SQLITE_OK) {
        sqlite3_close(pDB);
        return false;
    }

    if(sqlite3_bind_text(stmt, 1, [[[appRecord URL] absoluteString] UTF8String], [[[appRecord URL] absoluteString] length], SQLITE_STATIC) != SQLITE_OK) {
        sqlite3_finalize(stmt);
        sqlite3_close(pDB);
        return false;
    }

    // we don't care if this one fails because there may not be records for this app
    sqlite3_step(stmt); 
    sqlite3_finalize(stmt);

    query = "INSERT INTO typemap (uti,application,rank) VALUES (?,?,?)";
    length = strlen(query);

    NSEnumerator *docTypes = [[appRecord documentTypes] objectEnumerator];
    while(NSDictionary *docType = [docTypes nextObject]) {
	int rank = kLSRankAlternate;
	NSString *nsrank = [docType objectForKey:@"LSHandlerRank"];
	if([nsrank isEqualToString:@"Default"])
	    rank = kLSRankDefault;
	else if([nsrank isEqualToString:@"Owner"])
	    rank = kLSRankOwner;

	NSMutableArray *things = [docType objectForKey:(__bridge NSString *)kLSItemContentTypesKey];
	if([things count] == 0) {
	    // do the old keys exist?
	    NSArray *extensions = [docType objectForKey:(__bridge NSString *)kCFBundleTypeExtensionsKey];
	    for(int x = 0; x < [extensions count]; ++x) {
		CFStringRef uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,
		    (__bridge CFStringRef)[extensions objectAtIndex:x], NULL);
		if(uti)
		    [things addObject:(__bridge_transfer id)uti];
	    }
	    // FIXME: also check for MIME Types key
	}

	for(int x = 0; x < [things count]; ++x) {
	    if(sqlite3_prepare_v2(pDB, query, length, &stmt, &tail) != SQLITE_OK) {
		sqlite3_close(pDB);
		return false;
	    }

	    NSString *uti = [things objectAtIndex:x];
	
	    if(sqlite3_bind_text(stmt, 1, [uti UTF8String], [uti length], SQLITE_STATIC) != SQLITE_OK
		|| sqlite3_bind_text(stmt, 2, [[[appRecord URL] absoluteString] UTF8String], [[[appRecord URL] absoluteString] length], SQLITE_STATIC) != SQLITE_OK
		|| sqlite3_bind_int(stmt, 3, rank) != SQLITE_OK)
	    {
		sqlite3_finalize(stmt);
		sqlite3_close(pDB);
		return false;
	    }

	    sqlite3_step(stmt);
	    sqlite3_finalize(stmt);
	}
    }

    sqlite3_close(pDB);
    return true;
}

#ifdef _X11_
static void PostXEvent(Display *display, Window window, Atom messageType, long d0, long d1,
    long d2, long d3, long d4)
{
    XEvent e;
    memset(&e, 0, sizeof(e));
    e.type = ClientMessage;
    e.xclient.display = display;
    e.xclient.window = window;
    e.xclient.message_type = messageType;
    e.xclient.format = 32;
    e.xclient.data.l[0] = d0;
    e.xclient.data.l[1] = d1;
    e.xclient.data.l[2] = d2;
    e.xclient.data.l[3] = d3;
    e.xclient.data.l[4] = d4;

    XWindowAttributes attr;
    XGetWindowAttributes(display, window, &attr);
    XSendEvent(display, attr.screen->root, False, SubstructureNotifyMask | SubstructureRedirectMask, &e);
}
#endif // _X11_

void LSRevealInFiler(CFArrayRef inItemURLs)
{
#ifdef _REWRITE_ME_
    QDBusConnection dbus = QDBusConnection::sessionBus();
    QDBusInterface filerIface(QStringLiteral("org.freedesktop.FileManager1"),
        QStringLiteral("/org/freedesktop/FileManager1"), "", dbus);
    if(filerIface.isValid()) {
        // we need to convert the CFArray into a QList in order to call DBus
        // this sucks. FIXME: maybe use DBusKit instead?
        QStringList uriList;
        NSArray *urls = (__bridge NSArray *)inItemURLs;
        for(int x=0; x<[urls count]; ++x) {
            NSURL *u = [urls objectAtIndex:x];
            if(![u isFileURL])
                continue;
            NSString *value = [u absoluteString];
            uriList.append(QString::fromUtf8([value UTF8String]));
        }
        filerIface.call("ShowItems", uriList, "0");
    } else {
        fprintf(stderr, "Unable to connect to Filer!\n");
    }
#endif // _REWRITE_ME_
}

/* from xpc_type.c */
static size_t
xpc_data_hash(const uint8_t *data, size_t length)
{
    size_t hash = 5381;

    while (length--)
        hash = ((hash << 5) + hash) + data[length];

    return (hash);
}

static void _LSCheckAndHandleLaunchFlags(NSTask *task, LSLaunchFlags launchFlags)
{
    int _launchd = 0;
    int err = 0;
    size_t hash = 0;

    // Can I play with madness?
    if(getenv("__LAUNCHD_FD") != NULL)
        _launchd = strtoul(getenv("__LAUNCHD_FD"), NULL, 10);

    if(launchFlags & kLSLaunchNewInstance) {
        // FIXME: launch new instance of app
    }
    if(launchFlags & kLSLaunchDontSwitch) {
        // FIXME: send a 'do not activate' request
    }

    // we may have already dup()'d other descriptors to 0,1,2 in `open`.
    if(_launchd) {
        launch_data_t job = launch_data_alloc(LAUNCH_DATA_DICTIONARY);
        launch_data_t args = launch_data_alloc(LAUNCH_DATA_ARRAY);

        // FIXME: handle IO redirection

        const char *p = [[task launchPath] UTF8String];
        launch_data_t s = launch_data_new_string(p);
        launch_data_array_set_index(args, s, 0);
        hash = xpc_data_hash((const uint8_t *)p, [[task launchPath] length]);
        NSArray *ta = [task arguments];
        if([ta count]) {
            for(int x = 0; x < [ta count]; ++x) {
                p = [[[ta objectAtIndex:x] absoluteString] UTF8String];
                launch_data_t s = launch_data_new_string(p);
                launch_data_array_set_index(args, s, 1+x);
                hash += xpc_data_hash((const uint8_t *)p, [[[ta objectAtIndex:x] absoluteString] length]);
            }
        }
        launch_data_dict_insert(job, args, LAUNCH_JOBKEY_PROGRAMARGUMENTS);
        launch_data_dict_insert(job, launch_data_new_bool(true), LAUNCH_JOBKEY_RUNATLOAD);

        NSDictionary *env = [task environment];
        NSArray *keys = [env allKeys];
        NSArray *vals = [env allValues];
        BOOL hasXDGRuntime = NO;
        launch_data_t envDict = launch_data_alloc(LAUNCH_DATA_DICTIONARY);
        for(int i = 0; i < [keys count]; ++i) {
            if([[keys objectAtIndex:i] isEqualToString:@"XDG_RUNTIME_DIR"])
                hasXDGRuntime = YES;
            launch_data_dict_insert(envDict,
                launch_data_new_string([[vals objectAtIndex:i] UTF8String]),
                [[keys objectAtIndex:i] UTF8String]);
	}
        if(!hasXDGRuntime) {
            char *xdgdir;
            asprintf(&xdgdir, "/tmp/runtime.%d", getuid());
            launch_data_dict_insert(envDict, launch_data_new_string("XDG_RUNTIME_DIR"), xdgdir);
            free(xdgdir);
        }
        launch_data_dict_insert(job, envDict, LAUNCH_JOBKEY_ENVIRONMENTVARIABLES);

        char *label = 0;
        asprintf(&label, "task.%lx.%s", hash, [[[task launchPath] lastPathComponent] UTF8String]);
        launch_data_dict_insert(job, launch_data_new_string(label), LAUNCH_JOBKEY_LABEL);

        launch_data_t request = launch_data_alloc(LAUNCH_DATA_DICTIONARY);
        launch_data_dict_insert(request, job, LAUNCH_KEY_SUBMITJOB);
        launch_data_t response = launch_msg(request);

        launch_data_free(request);
        err = launch_data_get_errno(response);

        switch(err) {
            case EEXIST:	/* identical job exists - start it */
                request = launch_data_alloc(LAUNCH_DATA_DICTIONARY);
                launch_data_dict_insert(request, launch_data_new_string(label),
                    LAUNCH_KEY_STARTJOB);
                launch_msg(request);
                launch_data_free(request);
                break;
            default: break;
        }
        free(label);
    } else {
        [task setStandardInput:[[NSFileHandle alloc] initWithFileDescriptor:0]];
        [task setStandardOutput:[[NSFileHandle alloc] initWithFileDescriptor:1]];
        [task setStandardError:[[NSFileHandle alloc] initWithFileDescriptor:2]];
        [task launch];
    }

    if(launchFlags & kLSLaunchAndHide) {
        // FIXME: send a 'hide' request
    }

    if(launchFlags & kLSLaunchAndWaitForExit)
        [task waitUntilExit]; // FIXME: handle this for launchd tasks too
}

// Some apps can't handle a local file URL with 'localhost', so remove it
NSArray *_LSCleanFileURLs(NSArray *inItemURLs)
{
    NSMutableArray *outItemURLs = [NSMutableArray arrayWithCapacity:[inItemURLs count]];

    NSEnumerator *urls = [inItemURLs objectEnumerator];
    while(NSURL *url = [urls nextObject]) {
        if([[url host] isEqualToString:@"localhost"])
            url = [[NSURL alloc] initWithScheme:[url scheme] host:nil
                path:[@"//" stringByAppendingString:[url path]]];
        [outItemURLs addObject:url];
    }
    return outItemURLs;
}

/* Hand the documents to the WindowServer, which routes them to the running
 * instance of the app (or launches it with the documents as arguments).
 * That is the single place that knows about the running applications, so
 * every launch shares one document-routing path. */
static BOOL _LSOpenDocumentsWithWindowServer(NSString *bundlePath, NSArray *itemURLs)
{
    mach_port_t port = MACH_PORT_NULL;
    Message msg;
    size_t used = 0;
    unsigned i;
    const char *bundle = [bundlePath UTF8String];

    if(bootstrap_port == MACH_PORT_NULL)
        bootstrap_init();
    if(bootstrap_look_up(bootstrap_port, WINDOWSERVER_SVC_NAME, &port) != KERN_SUCCESS)
        return NO;

    memset(&msg, 0, sizeof(msg));
    msg.header.msgh_remote_port = port;
    msg.header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, 0, 0, 0);
    msg.header.msgh_id = MSG_ID_INLINE;
    msg.header.msgh_size = sizeof(msg) - sizeof(mach_msg_trailer_t);
    msg.code = CODE_OPEN_DOCUMENTS;
    msg.pid = getpid();
    strncpy(msg.bundleID, "com.ravynos.launchservices", sizeof(msg.bundleID) - 1);

    if(bundle != NULL) {
        size_t l = strlen(bundle) + 1;
        if(l > sizeof(msg.data))
            return NO;
        memcpy(msg.data, bundle, l);
        used = l;
    }
    for(i = 0; i < [itemURLs count]; i++) {
        NSString *path = [[itemURLs objectAtIndex:i] path];
        const char *p = [path UTF8String];
        size_t l;
        if(p == NULL)
            continue;
        l = strlen(p) + 1;
        if(used + l > sizeof(msg.data))
            break;
        memcpy(msg.data + used, p, l);
        used += l;
    }
    msg.len = (unsigned)used;

    if(mach_msg((mach_msg_header_t *)&msg, MACH_SEND_MSG | MACH_SEND_TIMEOUT,
                sizeof(msg) - sizeof(mach_msg_trailer_t), 0, MACH_PORT_NULL,
                200 /* ms timeout */, MACH_PORT_NULL) != MACH_MSG_SUCCESS)
        return NO;

    return YES;
}

static OSStatus _LSOpenAllWithSpecifiedApp(const LSLaunchURLSpec *inLaunchSpec, CFURLRef _Nullable *outLaunchedURL)
{
    const NSURL *appURL = (__bridge NSURL *)inLaunchSpec->appURL;
    if([appURL isFileURL] == NO)
        return kLSDataErr;

    // Launch app and pass all itemURLs to it
    // FIXME: use GURL or odoc events instead of passing on cmd line
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *appPath = [appURL path];
    BOOL isDir;
    BOOL exists = [fm fileExistsAtPath:appPath isDirectory:&isDir];

    if(exists == NO)
        return kLSNoExecutableErr;

    if(isDir == YES) {
        NSBundle *app = [NSBundle bundleWithPath:appPath];
        if([fm isExecutableFileAtPath:[app executablePath]] == NO)
            return kLSNoExecutableErr;

        if(outLaunchedURL != NULL)
            *outLaunchedURL = (__bridge_retained CFURLRef)[NSURL fileURLWithPath:[app executablePath]];

        /* The WindowServer owns the running applications: let it route the
         * documents to the app (starting it when it is not running). */
        if(_LSOpenDocumentsWithWindowServer(appPath,
                                            (__bridge NSArray *)inLaunchSpec->itemURLs))
            return 0;

        NSMutableArray *args = [NSMutableArray new];
        if(inLaunchSpec->taskArgs)
            [args addObjectsFromArray:(__bridge NSArray *)inLaunchSpec->taskArgs];
        else
            [args addObjectsFromArray:[[app infoDictionary] objectForKey:@"ProgramArguments"]];
        [args addObjectsFromArray:_LSCleanFileURLs((__bridge NSArray *)inLaunchSpec->itemURLs)];
        NSTask *task = [NSTask new];
        [task setEnvironment:(__bridge NSDictionary *)inLaunchSpec->taskEnv];
        [task setArguments:args];
        [task setLaunchPath:[app executablePath]];
        _LSCheckAndHandleLaunchFlags(task, inLaunchSpec->launchFlags);
    } else {
        // it's not a bundle so just try to exec the file
        if([fm isExecutableFileAtPath:appPath] == NO)
            return kLSNoExecutableErr;

        if(outLaunchedURL != NULL)
            *outLaunchedURL = (__bridge_retained CFURLRef)[NSURL fileURLWithPath:appPath];

        // Check if we have any stored arguments in the database
        NSMutableArray *args = [NSMutableArray new];
        if(inLaunchSpec->taskArgs)
            [args addObjectsFromArray:(__bridge NSArray *)inLaunchSpec->taskArgs];

        LSAppRecord *appRecord;
        if(LSFindRecordInDatabase(appURL, &appRecord) == YES) {
            [args addObjectsFromArray:[appRecord arguments]];
        }

        // Just open the app unless there are itemURLs
        // Otherwise, launch the app with each one
        if([(__bridge NSArray *)inLaunchSpec->itemURLs count] == 0) {
            for(int i=0; i<[args count]; ++i) {
                if([[args objectAtIndex:i] caseInsensitiveCompare:@"%U"] == NSOrderedSame ||
                    [[args objectAtIndex:i] caseInsensitiveCompare:@"%F"] == NSOrderedSame) {
                    [args removeObjectAtIndex:i];
                }
            }
            NSTask *task = [NSTask new];
            [task setEnvironment:(__bridge NSDictionary*)inLaunchSpec->taskEnv];
            [task setArguments:args];
            [task setLaunchPath:appPath];

            _LSCheckAndHandleLaunchFlags(task, inLaunchSpec->launchFlags);
            return 0;
        }

        NSEnumerator *items = [_LSCleanFileURLs((__bridge NSArray *)inLaunchSpec->itemURLs) objectEnumerator];
        BOOL found = NO;

        while(NSURL *item = [items nextObject]) {
            NSMutableArray *copyargs = [args copy];
            for(int i=0; i<[copyargs count]; ++i) {
                if([[copyargs objectAtIndex:i] caseInsensitiveCompare:@"%U"] == NSOrderedSame) {
                    [copyargs replaceObjectAtIndex:i withObject:[item absoluteString]];
                    found = YES;
                }
                if([[copyargs objectAtIndex:i] caseInsensitiveCompare:@"%F"] == NSOrderedSame) {
                    [copyargs replaceObjectAtIndex:i withObject:[item path]];
                    found = YES;
                }
            }

            if(found == NO)
                [copyargs addObject:[item path]];

            NSTask *task = [NSTask new];
            [task setEnvironment:(__bridge NSDictionary *)inLaunchSpec->taskEnv];
            [task setArguments:copyargs];
            [task setLaunchPath:appPath];

            _LSCheckAndHandleLaunchFlags(task, inLaunchSpec->launchFlags);
        }
    }
    return 0;
}

static BOOL _acceptsThing(NSArray *things, NSString *aThing)
{
    NSEnumerator *thingEnumerator = [things objectEnumerator];
    NSString *currentThing;
    while(currentThing = [thingEnumerator nextObject]) {
        if([currentThing isEqualToString:@"*"] || [currentThing isEqualToString:aThing]) {
            return YES;
        }
    }
    return NO;
}

static BOOL _acceptsRole(NSString *role, LSRolesMask rolesMask)
{
    if([role isEqualToString:@"None"]) return NO;
    if(rolesMask == kLSRolesAll) return YES;
    if([role isEqualToString:@"Shell"] && (rolesMask & kLSRolesShell)) return YES;
    if([role isEqualToString:@"Viewer"] && (rolesMask & kLSRolesViewer)) return YES;
    if([role isEqualToString:@"Editor"] && (rolesMask & kLSRolesEditor)) return YES;
    return NO;
}

Boolean LSIsNSBundle(CFURLRef cfurl)
{
    NSURL *url = (__bridge NSURL *)cfurl;
    if([[url scheme] isEqualToString:@"file"] &&
       [[url pathExtension] isEqualToString:@"app"]) {
       return YES;
    }
    return NO;
}

Boolean LSIsAppDir(CFURLRef cfurl)
{
    NSURL *url = (__bridge NSURL *)cfurl;
    if([[url scheme] isEqualToString:@"file"] &&
       [[url pathExtension] caseInsensitiveCompare:@"appdir"] == NSOrderedSame) {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *appRunPath = [[url URLByAppendingPathComponent:@"AppRun"] path];
    if([fm fileExistsAtPath:appRunPath] && [fm isExecutableFileAtPath:appRunPath])
        return YES;
    }
    return NO;
}

//------------------------------------------------------------------------
//    PUBLIC API
//------------------------------------------------------------------------

OSStatus LSOpenCFURLRef(CFURLRef inURL, CFURLRef _Nullable *outLaunchedURL)
{
    LSLaunchURLSpec spec;
    memset(&spec, 0, sizeof(spec));
    spec.itemURLs = CFArrayCreate(NULL, (const void **)&inURL, 1, NULL);
    spec.launchFlags = kLSLaunchDefaults;
    OSStatus rc = LSOpenFromURLSpec(&spec, outLaunchedURL);
    CFRelease(spec.itemURLs);
    return rc;
}

OSStatus LSOpenFromURLSpec(const LSLaunchURLSpec *inLaunchSpec, CFURLRef _Nullable *outLaunchedURL)
{
    _LSInitializeDatabase();

    CFArrayRef taskArgs = NULL;
    CFDictionaryRef taskEnv;

    if(inLaunchSpec->launchFlags & kLSALaunchTaskEnvIsValid)
        taskEnv = inLaunchSpec->taskEnv;
    else
        taskEnv = (__bridge_retained CFDictionaryRef)[[NSPlatform currentPlatform] environment];

    if(inLaunchSpec->launchFlags & kLSALaunchTaskArgsIsValid)
        taskArgs = inLaunchSpec->taskArgs;

    if(inLaunchSpec->appURL) {
        // We are launching this specific application which must be a file URL
        // Guard against bad data in inLaunchSpec :)
        LSLaunchURLSpec spec;
        memset(&spec, 0, sizeof(spec));
        spec.appURL = inLaunchSpec->appURL;
        spec.itemURLs = inLaunchSpec->itemURLs;
        spec.launchFlags = inLaunchSpec->launchFlags;
        spec.taskArgs = taskArgs;
        spec.taskEnv = taskEnv;
        OSStatus rc = _LSOpenAllWithSpecifiedApp(&spec, outLaunchedURL);
        if(!(inLaunchSpec->launchFlags & kLSALaunchTaskEnvIsValid))
            CFRelease(taskEnv);
        return rc;
    }

    // We are opening one or more files or URLs with their preferred apps
    // If any of the items refer to application bundles, they will be launched
    // NOTE: Plain executable files are NOT considered "applications" here
    // because file permissions are not reliable. e.g. Samba shares often have
    // execute permission on non-executable files.

    NSEnumerator *items = [(__bridge id)(inLaunchSpec->itemURLs) objectEnumerator];
    NSURL *item;

    while(item = [items nextObject]) {
        if(LSIsNSBundle((__bridge CFURLRef)item)) {
            LSLaunchURLSpec spec;
            memset(&spec, 0, sizeof(spec));
            spec.appURL = (__bridge_retained CFURLRef)item;
            spec.itemURLs = NULL;
            spec.launchFlags = inLaunchSpec->launchFlags;
            spec.taskArgs = taskArgs;
            spec.taskEnv = taskEnv;
            _LSOpenAllWithSpecifiedApp(&spec, NULL);
            CFRelease(spec.appURL);
        } else if(LSIsAppDir((__bridge CFURLRef)item)) {
            LSLaunchURLSpec spec;
            memset(&spec, 0, sizeof(spec));
            spec.appURL = (__bridge_retained CFURLRef)([item URLByAppendingPathComponent:@"AppRun"]);
            spec.itemURLs = NULL;
            spec.launchFlags = inLaunchSpec->launchFlags;
            spec.taskArgs = taskArgs;
            spec.taskEnv = taskEnv;
            _LSOpenAllWithSpecifiedApp(&spec, NULL);
            CFRelease(spec.appURL);
        } else {
            NSString *uti = nil;
            if([[item pathExtension] isEqualToString:@""] == NO)
                uti = (__bridge_transfer NSString *)UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,
                    (__bridge CFStringRef)[item pathExtension], NULL);

#ifdef _REWRITE_ME_
            if(uti == nil) {
                // We don't have a recognized extension. Try to identify by mime type.
                QMimeDatabase mimedb;
                QMimeType mimetype = mimedb.mimeTypeForFile(QString::fromUtf8([[item path] UTF8String]));
                QStringList parents(mimetype.name());
                parents.append(mimetype.parentMimeTypes());

                for(QString s : parents) {
                    NSString *mimestring = [NSString stringWithCString:s.toUtf8()];
                    uti = (__bridge_transfer NSString *)UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType,
                        (__bridge CFStringRef)mimestring, NULL);
                    if(uti)
                        break;
                }
            }
#endif // _REWRITE_ME_

            if(uti == nil) {
                if(!(inLaunchSpec->launchFlags & kLSALaunchTaskEnvIsValid))
                    CFRelease(taskEnv);
                return kLSApplicationNotFoundErr;
            }

            NSMutableArray *appCandidates = [NSMutableArray arrayWithCapacity:6];
            NSMutableArray *conforms = [NSMutableArray arrayWithCapacity:20];

            [conforms addObject:uti];
            for(int x=0; x<[conforms count]; ++x) {
                NSString *uti = [conforms objectAtIndex:x];
                [conforms addObjectsFromArray:(__bridge_transfer NSArray*)UTTypeCopyConformsTo((__bridge CFStringRef)uti)];
            }

            int rc = -1;
            for(int x=0; x<[conforms count] && (rc = LSFindAppsForUTI([conforms objectAtIndex:x], &appCandidates)) != 0; )
                ++x;
            if(rc == 0) {
                LSLaunchURLSpec spec;
                memset(&spec, 0, sizeof(spec));
                spec.appURL = (__bridge_retained CFURLRef)[[appCandidates firstObject] copy];
                spec.itemURLs = (__bridge_retained CFArrayRef)[NSArray arrayWithObject:item];
                spec.launchFlags = inLaunchSpec->launchFlags;
                spec.taskArgs = taskArgs;
                spec.taskEnv = taskEnv;
                _LSOpenAllWithSpecifiedApp(&spec, NULL);
                CFRelease(spec.appURL);
                CFRelease(spec.itemURLs);
            }
        }    
    }

    if(!(inLaunchSpec->launchFlags & kLSALaunchTaskEnvIsValid))
        CFRelease(taskEnv);
    return 0;
}

OSStatus LSRegisterURL(CFURLRef inURL, Boolean inUpdate)
{
    // Per Apple, inURL must be a file URL that refers to an app bundle
    // or executable. This version will also accept a .desktop file as
    // a special case.
    _LSInitializeDatabase();

    NSURL *appURL = (__bridge NSURL *)inURL;
    if([appURL isFileURL] == NO)
        return kLSDataErr;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *appPath = [appURL path];
    BOOL isDir;
    BOOL exists = [fm fileExistsAtPath:appPath isDirectory:&isDir];
    BOOL isDesktopFile = [appPath hasSuffix:@".desktop"];

    if(exists == NO)
        return kLSNoExecutableErr;

    if(isDir == YES) {
        NSBundle *app = [NSBundle bundleWithPath:appPath];
        if([fm isExecutableFileAtPath:[app executablePath]] == NO)
            return kLSNoExecutableErr;
    } else {
        if( isDesktopFile == NO && [fm isExecutableFileAtPath:appPath] == NO)
            return kLSNoExecutableErr;
    }

    NSDictionary *attributes = [fm fileAttributesAtPath:appPath traverseLink:NO];

    // Does this app exist in the database already?
    LSAppRecord *appRecord = [[LSAppRecord alloc] initWithURL:appURL];
    LSAppRecord *appRecordInDB = [LSAppRecord new];

    // Use the parsed appRecord to handle .desktop files: the Exec=
    // is not the same as the appURL. Sigh.
    BOOL inDatabase = LSFindRecordInDatabase([appRecord URL], &appRecordInDB);

    if(inDatabase == YES && inUpdate == NO && [appRecord modificationDate] == [attributes fileModificationDate])
        return 0; // Date hasn't changed and "force update" not specified

    // Either record did not exist, file has been modified, or an update is forced
    BOOL rc = _LSAddRecordToDatabase(appRecord, inDatabase);
    return (rc == true) ? 0 : kLSServerCommunicationErr;
}

OSStatus LSCanURLAcceptURL(CFURLRef inItemURL, CFURLRef inTargetURL, LSRolesMask inRoleMask, LSAcceptanceFlags inFlags, Boolean *outAcceptsItem)
{
    *outAcceptsItem = NO;
    _LSInitializeDatabase();

    NSURL *appURL = (__bridge NSURL *)inTargetURL;
    if([appURL isFileURL] == NO)
        return kLSDataErr;

    LSAppRecord *appRecord = [LSAppRecord new];
    if(LSFindRecordInDatabase(appURL, &appRecord) == NO)
        return kLSApplicationNotFoundErr;

    if([[(__bridge NSURL *)inItemURL scheme] isEqualToString:@"file"]) {
        NSString *ext = [(__bridge NSURL *)inItemURL pathExtension];
        CFStringRef uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,
		(__bridge CFStringRef)ext, NULL);

        NSEnumerator *docTypes = [[appRecord documentTypes] objectEnumerator];
        NSDictionary *docType;

        while(docType = [docTypes nextObject]) {
            NSArray *things = [docType objectForKey:(__bridge NSString *)kLSItemContentTypesKey];
            if([things count]) {
                if(_acceptsThing(things, (__bridge NSString*)uti) && _acceptsRole([docType objectForKey:(__bridge NSString *)kCFBundleTypeRoleKey], inRoleMask)) {
                    *outAcceptsItem = YES;
                    break;
                }
            } else {
                things = [docType objectForKey:(__bridge NSString *)kCFBundleTypeExtensionsKey];
                if(_acceptsThing(things, ext) && _acceptsRole([docType objectForKey:(__bridge NSString *)kCFBundleTypeRoleKey], inRoleMask)) {
                    *outAcceptsItem = YES;
                    break;
                }
            }
        }
        CFRelease(uti);
    } else {
        NSString *itemScheme = [(__bridge NSURL *)inItemURL scheme];
        NSEnumerator *appSchemes = [[appRecord URLSchemes] objectEnumerator];
        NSDictionary *appScheme;

        while(appScheme = [appSchemes nextObject]) {
            if(_acceptsThing([appScheme objectForKey:(__bridge NSString *)kCFBundleURLSchemesKey], itemScheme) && _acceptsRole([appScheme objectForKey:(__bridge NSString *)kCFBundleTypeRoleKey], inRoleMask)) {
                *outAcceptsItem = YES;
                break;
            }
        }
    }

    return 0;
}

