/*
 * AppCatalog.m - Software catalog and metadata management for ravynOS App Store
 */
#import "AppCatalog.h"

@implementation AppItem
@end

@interface AppCatalog () {
    NSMutableArray *_items;
    NSArray *_categories;
}
@end

@implementation AppCatalog

+ (instancetype)sharedCatalog {
    static AppCatalog *s_instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_instance = [[AppCatalog alloc] init];
    });
    return s_instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _categories = @[
            @"Featured",
            @"Graphics & Design",
            @"Productivity",
            @"Audio & Video",
            @"Developer Tools",
            @"Games & Emulation",
            @"Utilities"
        ];
        _items = [NSMutableArray array];
        [self _seedCatalog];
        [self refreshInstalledStatus];
    }
    return self;
}

- (void)_addApp:(NSString *)port
           name:(NSString *)name
       category:(NSString *)category
        summary:(NSString *)summary
        version:(NSString *)version
          isGUI:(BOOL)isGUI
          glyph:(NSString *)glyph {
    AppItem *item = [[AppItem alloc] init];
    item.portName = port;
    item.displayName = name;
    item.category = category;
    item.summary = summary;
    item.version = version;
    item.isGUIApp = isGUI;
    item.iconGlyph = glyph;
    item.isInstalled = NO;
    [_items addObject:item];
}

- (void)_seedCatalog {
    /* Featured & Graphics */
    [self _addApp:@"gimp2" name:@"GIMP" category:@"Graphics & Design"
          summary:@"GNU Image Manipulation Program for photo editing and digital drawing."
          version:@"2.10.36" isGUI:YES glyph:@"🎨"];
    [self _addApp:@"inkscape" name:@"Inkscape" category:@"Graphics & Design"
          summary:@"Professional vector graphics editor for illustrations and SVG designs."
          version:@"1.3.2" isGUI:YES glyph:@"📐"];
    [self _addApp:@"blender" name:@"Blender" category:@"Graphics & Design"
          summary:@"3D creation suite supporting modeling, rigging, animation, and rendering."
          version:@"4.0.2" isGUI:YES glyph:@"🧊"];
    [self _addApp:@"imagemagick" name:@"ImageMagick" category:@"Graphics & Design"
          summary:@"CLI suite to create, edit, compose, or convert bitmap images."
          version:@"7.1.1" isGUI:NO glyph:@"🖼️"];

    /* Productivity & Office */
    [self _addApp:@"libreoffice" name:@"LibreOffice" category:@"Productivity"
          summary:@"Comprehensive office suite: Writer, Calc, Impress, and Draw."
          version:@"7.6.4" isGUI:YES glyph:@"📝"];
    [self _addApp:@"ghostscript" name:@"Ghostscript" category:@"Productivity"
          summary:@"PostScript and PDF interpreter, rasterizer, and document conversion."
          version:@"10.02.1" isGUI:NO glyph:@"📄"];
    [self _addApp:@"pandoc" name:@"Pandoc" category:@"Productivity"
          summary:@"Universal document markup converter supporting Markdown, HTML, LaTeX."
          version:@"3.1.9" isGUI:NO glyph:@"📑"];

    /* Audio & Video */
    [self _addApp:@"vlc" name:@"VLC Media Player" category:@"Audio & Video"
          summary:@"Versatile multimedia player that plays most codecs and streaming protocols."
          version:@"3.0.20" isGUI:YES glyph:@"🎬"];
    [self _addApp:@"audacity" name:@"Audacity" category:@"Audio & Video"
          summary:@"Multi-track audio editor and recorder for podcasts and music production."
          version:@"3.4.2" isGUI:YES glyph:@"🎙️"];
    [self _addApp:@"ffmpeg" name:@"FFmpeg" category:@"Audio & Video"
          summary:@"Complete cross-platform solution to record, convert and stream audio and video."
          version:@"6.1.1" isGUI:NO glyph:@"🎥"];

    /* Developer Tools */
    [self _addApp:@"git" name:@"Git" category:@"Developer Tools"
          summary:@"Fast, scalable distributed revision control system."
          version:@"2.43.0" isGUI:NO glyph:@"🌿"];
    [self _addApp:@"cmake" name:@"CMake" category:@"Developer Tools"
          summary:@"Cross-platform open-source build system generator."
          version:@"3.28.1" isGUI:NO glyph:@"⚙️"];
    [self _addApp:@"python312" name:@"Python 3.12" category:@"Developer Tools"
          summary:@"Modern, versatile high-level interpreted programming language."
          version:@"3.12.1" isGUI:NO glyph:@"🐍"];
    [self _addApp:@"nodejs20" name:@"Node.js 20" category:@"Developer Tools"
          summary:@"JavaScript runtime built on Chrome's V8 engine for server and CLI tools."
          version:@"20.10.0" isGUI:NO glyph:@"🟢"];
    [self _addApp:@"neovim" name:@"Neovim" category:@"Developer Tools"
          summary:@"Vim-fork focused on extensibility, Lua plugins, and modern editor integration."
          version:@"0.9.5" isGUI:NO glyph:@"💻"];

    /* Games & Emulation */
    [self _addApp:@"dosbox-x" name:@"DOSBox-X" category:@"Games & Emulation"
          summary:@"Accurate x86 PC emulator with Sound Blaster, Gravis UltraSound, and DOS."
          version:@"2023.10" isGUI:YES glyph:@"🕹️"];
    [self _addApp:@"scummvm" name:@"ScummVM" category:@"Games & Emulation"
          summary:@"Engine interpreter for classic adventure games (LucasArts, Sierra, Humongous)."
          version:@"2.8.0" isGUI:YES glyph:@"👾"];
    [self _addApp:@"openttd" name:@"OpenTTD" category:@"Games & Emulation"
          summary:@"Open-source transport simulation game based on Transport Tycoon Deluxe."
          version:@"13.4" isGUI:YES glyph:@"🚂"];

    /* Utilities */
    [self _addApp:@"htop" name:@"htop" category:@"Utilities"
          summary:@"Interactive process viewer and system resource monitor for terminal."
          version:@"3.3.0" isGUI:NO glyph:@"📊"];
    [self _addApp:@"tmux" name:@"tmux" category:@"Utilities"
          summary:@"Terminal multiplexer: manage multiple shell sessions inside a single window."
          version:@"3.3a" isGUI:NO glyph:@"🪟"];
    [self _addApp:@"wget" name:@"wget" category:@"Utilities"
          summary:@"Non-interactive network downloader supporting HTTP, HTTPS, and FTP."
          version:@"1.21.4" isGUI:NO glyph:@"⬇️"];
    [self _addApp:@"tree" name:@"tree" category:@"Utilities"
          summary:@"Recursive directory-listing command that displays a colored file hierarchy."
          version:@"2.1.1" isGUI:NO glyph:@"🌲"];
    [self _addApp:@"ncdu" name:@"ncdu" category:@"Utilities"
          summary:@"Fast, NCurses-based disk usage analyzer for finding large directories."
          version:@"1.19" isGUI:NO glyph:@"💾"];
}

- (NSArray<NSString *> *)categories {
    return _categories;
}

- (void)refreshInstalledStatus {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (AppItem *item in _items) {
        NSString *binPath = [NSString stringWithFormat:@"/opt/local/bin/%@", item.portName];
        NSString *appPath = [NSString stringWithFormat:@"/Applications/%@.app", item.displayName];
        NSString *mpAppPath = [NSString stringWithFormat:@"/Applications/MacPorts/%@.app", item.displayName];

        BOOL installed = [fm fileExistsAtPath:binPath] ||
                         [fm fileExistsAtPath:appPath] ||
                         [fm fileExistsAtPath:mpAppPath];
        item.isInstalled = installed;
    }
}

- (NSArray *)appsForCategory:(NSString *)category searchQuery:(NSString *)query {
    [self refreshInstalledStatus];

    BOOL allCategories = [category isEqualToString:@"Featured"];
    NSMutableArray *result = [NSMutableArray array];

    for (AppItem *item in _items) {
        if (!allCategories && ![item.category isEqualToString:category]) {
            continue;
        }
        if (query && [query length] > 0) {
            NSString *q = [query lowercaseString];
            BOOL match = ([[item.displayName lowercaseString] rangeOfString:q].location != NSNotFound) ||
                         ([[item.portName lowercaseString] rangeOfString:q].location != NSNotFound) ||
                         ([[item.summary lowercaseString] rangeOfString:q].location != NSNotFound);
            if (!match) {
                continue;
            }
        }
        [result addObject:item];
    }
    return result;
}

@end
