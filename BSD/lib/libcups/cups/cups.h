/*
 * CUPS client interface for ravynOS.
 *
 * There is no printing subsystem here: no cupsd, no queues, no PPDs.  The
 * library exports the calls a GUI application makes when it builds a print
 * dialog (CUPS_HTTP_DEFAULT, ippNewRequest, ippAddString, cupsGetDests,
 * cupsDoRequest) so the application can discover that zero destinations
 * exist and present an empty printer list.  Every call that would describe a
 * printer answers "none" or an error; none of them invents a queue.
 */
#ifndef _CUPS_CUPS_H_
#define _CUPS_CUPS_H_

#include <sys/cdefs.h>
#include <stddef.h>
#include <stdint.h>

__BEGIN_DECLS

typedef struct _ipp_s ipp_t;
typedef struct _http_s http_t;
typedef struct _ipp_attribute_s ipp_attribute_t;

#define CUPS_HTTP_DEFAULT ((http_t *)0)
#define IPP_OK 0x0000
#define IPP_OK_SUBST 0x0001
#define IPP_ERROR 0x0400
#define IPP_STATUS_OK 0x0000
#define IPP_STATUS_ERROR 0x0400
#define HTTP_STATUS_OK 200
#define IPP_TAG_OPERATION 0x01
#define IPP_TAG_JOB 0x02
#define IPP_TAG_END 0x03
#define IPP_TAG_PRINTER 0x04
#define IPP_TAG_UNSUPPORTED_GROUP 0x05
#define IPP_TAG_SUBSCRIPTION 0x06
#define IPP_TAG_EVENT_NOTIFICATION 0x07
#define IPP_TAG_ZERO 0x00
#define IPP_TAG_INTEGER 0x21
#define IPP_TAG_BOOLEAN 0x22
#define IPP_TAG_ENUM 0x23
#define IPP_TAG_STRING 0x30
#define IPP_TAG_DATE 0x31
#define IPP_TAG_RESOLUTION 0x32
#define IPP_TAG_RANGE 0x33
#define IPP_TAG_BEGIN_COLLECTION 0x34
#define IPP_TAG_TEXT 0x41
#define IPP_TAG_NAME 0x42
#define IPP_TAG_KEYWORD 0x44
#define IPP_TAG_URI 0x45
#define IPP_TAG_CHARSET 0x47
#define IPP_TAG_LANGUAGE 0x48
#define IPP_TAG_MIMETYPE 0x49

#define IPP_OP_GET_PRINTER_ATTRIBUTES 0x000B
#define IPP_OP_GET_JOBS 0x000A
#define IPP_OP_PRINT_JOB 0x0002
#define IPP_OP_CREATE_JOB 0x0005
#define IPP_OP_SEND_DOCUMENT 0x0006

typedef struct {
    char *name;
    char *instance;
    int is_default;
    int num_options;
    char **options;
} cups_dest_t;

typedef struct {
    int num_dests;
    cups_dest_t *dests;
} cups_dests_t;

typedef struct _cups_dest_info_s cups_dest_info_t;
typedef struct _ppd_file_s ppd_file_t;

extern int cupsGetDests(cups_dest_t **dests);
extern int cupsGetDests2(http_t *http, cups_dest_t **dests);
extern void cupsFreeDests(int num_dests, cups_dest_t *dests);
extern cups_dest_t *cupsGetDest(const char *name, const char *instance,
                                int num_dests, cups_dest_t *dests);
extern cups_dest_t *cupsGetNamedDest(http_t *http, const char *name,
                                     const char *instance);
extern cups_dest_t *cupsCopyDest(cups_dest_t *dest, int num_dests, cups_dest_t *dests);
extern cups_dest_info_t *cupsCopyDestInfo(http_t *http, cups_dest_t *dest);
extern void cupsFreeDestInfo(cups_dest_info_t *dinfo);
extern int cupsCheckDestSupported(http_t *http, cups_dest_t *dest,
                                  cups_dest_info_t *dinfo, const char *option,
                                  const char *value);
extern char *cupsFindDestDefault(http_t *http, cups_dest_t *dest,
                                 cups_dest_info_t *dinfo, const char *option);
extern char *cupsFindDestSupported(http_t *http, cups_dest_t *dest,
                                   cups_dest_info_t *dinfo, const char *option);
extern char *cupsLocalizeDestValue(http_t *http, cups_dest_t *dest,
                                   cups_dest_info_t *dinfo, const char *uri,
                                   const char *keyword);
extern char *cupsGetOption(const char *name, int num_options, char **options);
extern int cupsAddOption(const char *name, const char *value, int num_options,
                         char ***options);
extern void cupsFreeOptions(int num_options, char **options);
extern int cupsCancelJob2(http_t *http, const char *printer, int job_id, int purge);
extern int cupsEnumDests(unsigned flags, int msec, int *cancel,
                         const char *const *include, const char *const *exclude,
                         int (*cb)(cups_dest_t *dest, void *user_data),
                         void *user_data);
extern int cupsLastError(void);
extern const char *cupsLastErrorString(void);
extern const char *cupsServer(void);
extern const char *cupsUser(void);
extern const char *cupsUserAgent(void);

extern http_t *httpConnect2(const char *host, int port, void *addr, int family,
                            int encryption, int blocking, int msec, int *cancel);
extern void httpClose(http_t *http);

extern ipp_t *ippNew(void);
extern ipp_t *ippNewRequest(int operation);
extern void ippDelete(ipp_t *ipp);
extern void ippSetVersion(ipp_t *ipp, int major, int minor);
extern int ippGetStatusCode(ipp_t *ipp);
extern int ippGetCount(ipp_attribute_t *attr);
extern int ippGetInteger(ipp_attribute_t *attr, int element);
extern const char *ippGetString(ipp_attribute_t *attr, int element,
                                const char **language);
extern int ippGetRange(ipp_attribute_t *attr, int element, int *upper);
extern int ippGetResolution(ipp_attribute_t *attr, int element, int *yres,
                            int *units);
extern ipp_t *ippGetCollection(ipp_attribute_t *attr, int element);
extern const char *ippGetName(ipp_attribute_t *attr);
extern int ippGetGroupTag(ipp_attribute_t *attr);
extern ipp_attribute_t *ippFindAttribute(ipp_t *ipp, const char *name, int tag);
extern ipp_attribute_t *ippFirstAttribute(ipp_t *ipp);
extern ipp_attribute_t *ippNextAttribute(ipp_t *ipp);
extern ipp_attribute_t *ippAddString(ipp_t *ipp, int group, int value_tag,
                                     const char *name, const char *language,
                                     const char *value);
extern ipp_attribute_t *ippAddStrings(ipp_t *ipp, int group, int value_tag,
                                      const char *name, int num_values,
                                      const char *language,
                                      const char *const *values);
extern ipp_attribute_t *ippAddInteger(ipp_t *ipp, int group, int value_tag,
                                      const char *name, int value);
extern ipp_attribute_t *ippAddBoolean(ipp_t *ipp, int group, const char *name,
                                      int value);
extern ipp_attribute_t *ippAddRange(ipp_t *ipp, int group, const char *name,
                                    int lower, int upper);
extern ipp_attribute_t *ippAddCollection(ipp_t *ipp, int group, const char *name,
                                         ipp_t *value);
extern ipp_attribute_t *ippAddCollections(ipp_t *ipp, int group, const char *name,
                                          int num_values, const ipp_t **values);
extern int ippDeleteAttribute(ipp_t *ipp, ipp_attribute_t *attr);
extern void ippCopyAttribute(ipp_t *dst, ipp_attribute_t *attr, int group);
extern int ippValidateAttributes(ipp_t *ipp);

extern ipp_t *cupsDoRequest(http_t *http, ipp_t *request, const char *resource);
extern ipp_t *cupsDoRequestAsync(http_t *http, ipp_t *request, const char *resource);
extern ipp_t *cupsGetResponse(http_t *http);
extern ipp_t *cupsSendRequest(http_t *http, ipp_t *request, const char *resource,
                              size_t length);
extern int cupsWriteRequestData(http_t *http, const char *buffer, size_t length);
extern const char *ippPort(void);
extern void *pwgMediaForSize(int width, int height);

__END_DECLS

#endif
