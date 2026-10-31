/*
 * LaunchServices item-property keys, exported from CoreServices.
 *
 * XUL binds kLSItem* at load ("Symbol not found: _kLSItemDisplayName",
 * "Expected in: CoreServices"); the header declares kLSItemContentTypesKey
 * inline, which gives every translation unit its own copy and exports
 * nothing.  These are real declarations with the documented values, so a
 * caller can pass them to LSCopyItemAttribute and friends.
 */
#include <CoreFoundation/CoreFoundation.h>

const CFStringRef kLSItemContentType = CFSTR("LSItemContentType");
const CFStringRef kLSItemDisplayName = CFSTR("LSItemDisplayName");
const CFStringRef kLSItemDisplayKind = CFSTR("LSItemDisplayKind");
const CFStringRef kLSItemRoleHandlerDisplayName = CFSTR("LSItemRoleHandlerDisplayName");
const CFStringRef kLSItemIsInvisible = CFSTR("LSItemIsInvisible");
const CFStringRef kLSItemExtension = CFSTR("LSItemExtension");
const CFStringRef kLSItemExtensionIsHidden = CFSTR("LSItemExtensionIsHidden");
const CFStringRef kLSItemFileType = CFSTR("LSItemFileType");
const CFStringRef kLSItemFileCreator = CFSTR("LSItemFileCreator");
const CFStringRef kLSItemKind = CFSTR("LSItemKind");
const CFStringRef kLSItemSize = CFSTR("LSItemSize");
const CFStringRef kLSItemCreationDate = CFSTR("LSItemCreationDate");
const CFStringRef kLSItemModificationDate = CFSTR("LSItemModificationDate");
const CFStringRef kLSItemContentModificationDate = CFSTR("LSItemContentModificationDate");
const CFStringRef kLSItemFSName = CFSTR("LSItemFSName");
const CFStringRef kLSItemQuarantineProperties = CFSTR("LSItemQuarantineProperties");
const CFStringRef kLSItemLastUsedDate = CFSTR("LSItemLastUsedDate");
const CFStringRef kLSItemDateAdded = CFSTR("LSItemDateAdded");

/* Quarantine property keys, also part of XUL's load-time references. */
const CFStringRef kLSQuarantineTypeKey = CFSTR("LSQuarantineType");
const CFStringRef kLSQuarantineDataURLKey = CFSTR("LSQuarantineDataURL");
const CFStringRef kLSQuarantineOriginURLKey = CFSTR("LSQuarantineOriginURL");
const CFStringRef kLSQuarantineTimeStampKey = CFSTR("LSQuarantineTimeStamp");
const CFStringRef kLSQuarantineAgentNameKey = CFSTR("LSQuarantineAgentName");
const CFStringRef kLSQuarantineAgentBundleIdentifierKey = CFSTR("LSQuarantineAgentBundleIdentifier");
const CFStringRef kLSQuarantineEventIdentifierKey = CFSTR("LSQuarantineEventIdentifier");

/* Quarantine type values. */
const CFStringRef kLSQuarantineTypeWebDownload = CFSTR("LSQuarantineTypeWebDownload");
const CFStringRef kLSQuarantineTypeOtherDownload = CFSTR("LSQuarantineTypeOtherDownload");
const CFStringRef kLSQuarantineTypeEmailAttachment = CFSTR("LSQuarantineTypeEmailAttachment");
const CFStringRef kLSQuarantineTypeInstantMessageAttachment = CFSTR("LSQuarantineTypeInstantMessageAttachment");
const CFStringRef kLSQuarantineTypeCalendarEventAttachment = CFSTR("LSQuarantineTypeCalendarEventAttachment");
const CFStringRef kLSQuarantineTypeOtherAttachment = CFSTR("LSQuarantineTypeOtherAttachment");

/* Spotlight metadata attribute names exported through CoreServices. */
const CFStringRef kMDItemWhereFroms = CFSTR("kMDItemWhereFroms");
const CFStringRef kMDItemContentType = CFSTR("kMDItemContentType");
const CFStringRef kMDItemContentTypeTree = CFSTR("kMDItemContentTypeTree");
const CFStringRef kMDItemFSName = CFSTR("kMDItemFSName");
const CFStringRef kMDItemDisplayName = CFSTR("kMDItemDisplayName");
const CFStringRef kMDItemKind = CFSTR("kMDItemKind");
const CFStringRef kMDItemFSSize = CFSTR("kMDItemFSSize");
const CFStringRef kMDItemFSCreationDate = CFSTR("kMDItemFSCreationDate");
const CFStringRef kMDItemFSContentChangeDate = CFSTR("kMDItemFSContentChangeDate");
const CFStringRef kMDItemContentModificationDate = CFSTR("kMDItemContentModificationDate");
const CFStringRef kMDItemLastUsedDate = CFSTR("kMDItemLastUsedDate");
const CFStringRef kMDItemUseCount = CFSTR("kMDItemUseCount");
const CFStringRef kMDItemDownloadedDate = CFSTR("kMDItemDownloadedDate");

/* Uniform Type Identifier tag classes and the common public types. */
const CFStringRef kUTTagClassFilenameExtension = CFSTR("public.filename-extension");
const CFStringRef kUTTagClassMIMEType = CFSTR("public.mime-type");

const CFStringRef kUTTypeItem = CFSTR("public.item");
const CFStringRef kUTTypeContent = CFSTR("public.content");
const CFStringRef kUTTypeData = CFSTR("public.data");
const CFStringRef kUTTypeText = CFSTR("public.text");
const CFStringRef kUTTypePlainText = CFSTR("public.plain-text");
const CFStringRef kUTTypeHTML = CFSTR("public.html");
const CFStringRef kUTTypeJSON = CFSTR("public.json");
const CFStringRef kUTTypeXML = CFSTR("public.xml");
const CFStringRef kUTTypeSourceCode = CFSTR("public.source-code");
const CFStringRef kUTTypeImage = CFSTR("public.image");
const CFStringRef kUTTypeJPEG = CFSTR("public.jpeg");
const CFStringRef kUTTypePNG = CFSTR("public.png");
const CFStringRef kUTTypeTIFF = CFSTR("public.tiff");
const CFStringRef kUTTypeGIF = CFSTR("com.compuserve.gif");
const CFStringRef kUTTypeMovie = CFSTR("public.movie");
const CFStringRef kUTTypeAudio = CFSTR("public.audio");
const CFStringRef kUTTypeAudiovisualContent = CFSTR("public.audiovisual-content");
const CFStringRef kUTTypeDirectory = CFSTR("public.directory");
const CFStringRef kUTTypeFolder = CFSTR("public.folder");
const CFStringRef kUTTypeURL = CFSTR("public.url");
const CFStringRef kUTTypeFileURL = CFSTR("public.file-url");
const CFStringRef kUTTypeApplication = CFSTR("com.apple.application");
const CFStringRef kUTTypeApplicationBundle = CFSTR("com.apple.application-bundle");
const CFStringRef kUTTypeWebArchive = CFSTR("com.apple.webarchive");
const CFStringRef kUTTagClassNSPboardType = CFSTR("com.apple.nspboard-type");
const CFStringRef kUTTagClassOSType = CFSTR("com.apple.ostype");
