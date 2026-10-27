/*
 * libcups.2.dylib for ravynOS.
 *
 * IPP request/response objects are real (attributes are stored and can be
 * read back), so an application that builds a Get-Printer-Attributes request
 * gets a well-formed object.  Delivery is not: there is no cupsd, so
 * cupsGetDests() reports zero destinations and cupsDoRequest() reports
 * CUPS_HTTP_DEFAULT as unavailable (NULL).  An application therefore shows an
 * empty printer list instead of crashing or inventing a queue.
 */
#include <stdlib.h>
#include <string.h>

#include "cups/cups.h"

/* -------------------------------------------------------------------- IPP */

struct _ipp_attribute_s {
    ipp_attribute_t *next;
    char *name;
    int group;
    int value_tag;
    int num_values;
    int *int_values;
    char **str_values;
    ipp_t **collections;
};

struct _ipp_s {
    int major_version;
    int minor_version;
    int status_code;
    ipp_attribute_t *first;
    ipp_attribute_t *last;
    ipp_attribute_t *cursor;
};

static int g_last_error;
static const char *g_last_error_string = "No error";

static ipp_attribute_t *ipp_append(ipp_t *ipp, int group, int value_tag,
                                   const char *name, int num_values)
{
    ipp_attribute_t *attr;
    if (ipp == NULL || name == NULL) {
        return NULL;
    }
    attr = (ipp_attribute_t *)calloc(1, sizeof(*attr));
    if (attr == NULL) {
        return NULL;
    }
    attr->name = strdup(name);
    attr->group = group;
    attr->value_tag = value_tag;
    attr->num_values = num_values;
    if (ipp->last) {
        ipp->last->next = attr;
    } else {
        ipp->first = attr;
    }
    ipp->last = attr;
    return attr;
}

ipp_t *ippNew(void)
{
    ipp_t *ipp = (ipp_t *)calloc(1, sizeof(*ipp));
    if (ipp) {
        ipp->major_version = 1;
        ipp->minor_version = 1;
    }
    return ipp;
}

ipp_t *ippNewRequest(int operation)
{
    ipp_t *ipp = ippNew();
    if (ipp) {
        ipp->status_code = operation;
        ippAddInteger(ipp, IPP_TAG_OPERATION, IPP_TAG_INTEGER, "attributes-charset", 0);
    }
    return ipp;
}

void ippDelete(ipp_t *ipp)
{
    ipp_attribute_t *a;
    if (ipp == NULL) {
        return;
    }
    a = ipp->first;
    while (a) {
        ipp_attribute_t *next = a->next;
        free(a->name);
        free(a->int_values);
        if (a->str_values) {
            for (int i = 0; i < a->num_values; i++) {
                free(a->str_values[i]);
            }
            free(a->str_values);
        }
        free(a->collections);
        free(a);
        a = next;
    }
    free(ipp);
}

void ippSetVersion(ipp_t *ipp, int major, int minor)
{
    if (ipp) {
        ipp->major_version = major;
        ipp->minor_version = minor;
    }
}

int ippGetStatusCode(ipp_t *ipp)
{
    return ipp ? ipp->status_code : IPP_STATUS_ERROR;
}

ipp_attribute_t *ippAddString(ipp_t *ipp, int group, int value_tag,
                              const char *name, const char *language,
                              const char *value)
{
    ipp_attribute_t *a = ipp_append(ipp, group, value_tag, name, 1);
    (void)language;
    if (a) {
        a->str_values = (char **)calloc(1, sizeof(char *));
        if (a->str_values) {
            a->str_values[0] = value ? strdup(value) : NULL;
        }
    }
    return a;
}

ipp_attribute_t *ippAddStrings(ipp_t *ipp, int group, int value_tag,
                               const char *name, int num_values,
                               const char *language, const char *const *values)
{
    ipp_attribute_t *a = ipp_append(ipp, group, value_tag, name, num_values);
    (void)language;
    if (a && num_values > 0) {
        a->str_values = (char **)calloc((size_t)num_values, sizeof(char *));
        if (a->str_values) {
            for (int i = 0; i < num_values; i++) {
                a->str_values[i] = values && values[i] ? strdup(values[i]) : NULL;
            }
        }
    }
    return a;
}

ipp_attribute_t *ippAddInteger(ipp_t *ipp, int group, int value_tag,
                               const char *name, int value)
{
    ipp_attribute_t *a = ipp_append(ipp, group, value_tag, name, 1);
    if (a) {
        a->int_values = (int *)calloc(1, sizeof(int));
        if (a->int_values) {
            a->int_values[0] = value;
        }
    }
    return a;
}

ipp_attribute_t *ippAddBoolean(ipp_t *ipp, int group, const char *name, int value)
{
    return ippAddInteger(ipp, group, IPP_TAG_BOOLEAN, name, value ? 1 : 0);
}

ipp_attribute_t *ippAddRange(ipp_t *ipp, int group, const char *name,
                             int lower, int upper)
{
    ipp_attribute_t *a = ipp_append(ipp, group, IPP_TAG_RANGE, name, 1);
    if (a) {
        a->int_values = (int *)calloc(2, sizeof(int));
        if (a->int_values) {
            a->int_values[0] = lower;
            a->int_values[1] = upper;
        }
    }
    return a;
}

ipp_attribute_t *ippAddCollection(ipp_t *ipp, int group, const char *name,
                                  ipp_t *value)
{
    ipp_attribute_t *a = ipp_append(ipp, group, IPP_TAG_BEGIN_COLLECTION, name, 1);
    if (a) {
        a->collections = (ipp_t **)calloc(1, sizeof(ipp_t *));
        if (a->collections) {
            a->collections[0] = value;
        }
    }
    return a;
}

ipp_attribute_t *ippAddCollections(ipp_t *ipp, int group, const char *name,
                                   int num_values, const ipp_t **values)
{
    ipp_attribute_t *a = ipp_append(ipp, group, IPP_TAG_BEGIN_COLLECTION, name, num_values);
    if (a && num_values > 0) {
        a->collections = (ipp_t **)calloc((size_t)num_values, sizeof(ipp_t *));
        if (a->collections) {
            for (int i = 0; i < num_values; i++) {
                a->collections[i] = values ? (ipp_t *)values[i] : NULL;
            }
        }
    }
    return a;
}

int ippGetCount(ipp_attribute_t *attr)
{
    return attr ? attr->num_values : 0;
}

int ippGetInteger(ipp_attribute_t *attr, int element)
{
    if (attr == NULL || attr->int_values == NULL) {
        return 0;
    }
    if (element < 0 || element >= attr->num_values) {
        return attr->int_values[0];
    }
    return attr->int_values[element];
}

const char *ippGetString(ipp_attribute_t *attr, int element, const char **language)
{
    (void)language;
    if (attr == NULL || attr->str_values == NULL) {
        return NULL;
    }
    if (element < 0 || element >= attr->num_values) {
        return attr->str_values[0];
    }
    return attr->str_values[element];
}

int ippGetRange(ipp_attribute_t *attr, int element, int *upper)
{
    (void)element;
    if (attr && attr->int_values && upper) {
        *upper = attr->int_values[1];
    }
    return attr && attr->int_values ? attr->int_values[0] : 0;
}

int ippGetResolution(ipp_attribute_t *attr, int element, int *yres, int *units)
{
    (void)attr; (void)element;
    if (yres) *yres = 0;
    if (units) *units = 3;  /* dots per inch */
    return 0;
}

ipp_t *ippGetCollection(ipp_attribute_t *attr, int element)
{
    if (attr && attr->collections && element >= 0 && element < attr->num_values) {
        return attr->collections[element];
    }
    return NULL;
}

const char *ippGetName(ipp_attribute_t *attr)
{
    return attr ? attr->name : NULL;
}

int ippGetGroupTag(ipp_attribute_t *attr)
{
    return attr ? attr->group : 0;
}

ipp_attribute_t *ippFindAttribute(ipp_t *ipp, const char *name, int tag)
{
    if (ipp == NULL || name == NULL) {
        return NULL;
    }
    for (ipp_attribute_t *a = ipp->first; a; a = a->next) {
        if (strcmp(a->name, name) == 0 && (tag == 0 || a->group == tag)) {
            return a;
        }
    }
    return NULL;
}

ipp_attribute_t *ippFirstAttribute(ipp_t *ipp)
{
    ipp->cursor = ipp ? ipp->first : NULL;
    return ipp->cursor;
}

ipp_attribute_t *ippNextAttribute(ipp_t *ipp)
{
    if (ipp == NULL || ipp->cursor == NULL) {
        return NULL;
    }
    ipp->cursor = ipp->cursor->next;
    return ipp->cursor;
}

int ippDeleteAttribute(ipp_t *ipp, ipp_attribute_t *attr)
{
    ipp_attribute_t *prev = NULL;
    ipp_attribute_t *a;

    if (ipp == NULL || attr == NULL) {
        return 0;
    }
    for (a = ipp->first; a; prev = a, a = a->next) {
        if (a == attr) {
            if (prev) {
                prev->next = a->next;
            } else {
                ipp->first = a->next;
            }
            if (ipp->last == a) {
                ipp->last = prev;
            }
            free(a->name);
            free(a->int_values);
            if (a->str_values) {
                for (int i = 0; i < a->num_values; i++) {
                    free(a->str_values[i]);
                }
                free(a->str_values);
            }
            free(a->collections);
            free(a);
            return 0;
        }
    }
    return 0;
}

void ippCopyAttribute(ipp_t *dst, ipp_attribute_t *attr, int group)
{
    if (dst == NULL || attr == NULL) {
        return;
    }
    if (attr->str_values) {
        ippAddStrings(dst, group, attr->value_tag, attr->name, attr->num_values,
                      NULL, (const char *const *)attr->str_values);
    } else if (attr->int_values) {
        for (int i = 0; i < attr->num_values; i++) {
            ippAddInteger(dst, group, attr->value_tag, attr->name, attr->int_values[i]);
        }
    }
}

int ippValidateAttributes(ipp_t *ipp)
{
    (void)ipp;
    return 0;
}

/* ------------------------------------------------------------------ HTTP */

http_t *httpConnect2(const char *host, int port, void *addr, int family,
                     int encryption, int blocking, int msec, int *cancel)
{
    (void)host; (void)port; (void)addr; (void)family; (void)encryption;
    (void)blocking; (void)msec; (void)cancel;
    return NULL;        /* no CUPS scheduler to connect to */
}

void httpClose(http_t *http)
{
    (void)http;
}

/* ---------------------------------------------------------------- CUPS API */

static char g_server[] = "localhost";

int cupsGetDests(cups_dest_t **dests)
{
    if (dests) {
        *dests = NULL;
    }
    return 0;
}

int cupsGetDests2(http_t *http, cups_dest_t **dests)
{
    (void)http;
    return cupsGetDests(dests);
}

void cupsFreeDests(int num_dests, cups_dest_t *dests)
{
    if (dests == NULL) {
        return;
    }
    for (int i = 0; i < num_dests; i++) {
        free(dests[i].name);
        free(dests[i].instance);
        cupsFreeOptions(dests[i].num_options, dests[i].options);
    }
    free(dests);
}

cups_dest_t *cupsGetDest(const char *name, const char *instance,
                         int num_dests, cups_dest_t *dests)
{
    for (int i = 0; i < num_dests; i++) {
        if ((name == NULL || strcmp(dests[i].name, name) == 0) &&
            (instance == NULL || (dests[i].instance &&
             strcmp(dests[i].instance, instance) == 0))) {
            return &dests[i];
        }
    }
    return NULL;
}

cups_dest_t *cupsGetNamedDest(http_t *http, const char *name, const char *instance)
{
    (void)http; (void)name; (void)instance;
    return NULL;
}

cups_dest_t *cupsCopyDest(cups_dest_t *dest, int num_dests, cups_dest_t *dests)
{
    (void)num_dests; (void)dests;
    if (dest == NULL) {
        return NULL;
    }
    cups_dest_t *copy = (cups_dest_t *)calloc(1, sizeof(*copy));
    if (copy == NULL) {
        return NULL;
    }
    copy->name = dest->name ? strdup(dest->name) : NULL;
    copy->instance = dest->instance ? strdup(dest->instance) : NULL;
    copy->is_default = dest->is_default;
    for (int i = 0; i < dest->num_options; i += 2) {
        cupsAddOption(dest->options[i], dest->options[i + 1], copy->num_options,
                      &copy->options);
        copy->num_options += 2;
    }
    return copy;
}

cups_dest_info_t *cupsCopyDestInfo(http_t *http, cups_dest_t *dest)
{
    (void)http; (void)dest;
    return NULL;
}

void cupsFreeDestInfo(cups_dest_info_t *dinfo)
{
    (void)dinfo;
}

int cupsCheckDestSupported(http_t *http, cups_dest_t *dest, cups_dest_info_t *dinfo,
                           const char *option, const char *value)
{
    (void)http; (void)dest; (void)dinfo; (void)option; (void)value;
    return 0;       /* not supported: no destination exists */
}

char *cupsFindDestDefault(http_t *http, cups_dest_t *dest, cups_dest_info_t *dinfo,
                          const char *option)
{
    (void)http; (void)dest; (void)dinfo; (void)option;
    return NULL;
}

char *cupsFindDestSupported(http_t *http, cups_dest_t *dest, cups_dest_info_t *dinfo,
                            const char *option)
{
    (void)http; (void)dest; (void)dinfo; (void)option;
    return NULL;
}

char *cupsLocalizeDestValue(http_t *http, cups_dest_t *dest, cups_dest_info_t *dinfo,
                            const char *uri, const char *keyword)
{
    (void)http; (void)dest; (void)dinfo; (void)uri;
    return keyword ? strdup(keyword) : NULL;
}

char *cupsGetOption(const char *name, int num_options, char **options)
{
    if (name == NULL || options == NULL) {
        return NULL;
    }
    for (int i = 0; i + 1 < num_options; i += 2) {
        if (options[i] && strcmp(options[i], name) == 0) {
            return options[i + 1];
        }
    }
    return NULL;
}

int cupsAddOption(const char *name, const char *value, int num_options,
                  char ***options)
{
    char **grown;

    if (name == NULL || options == NULL) {
        return num_options;
    }
    grown = (char **)realloc(*options, sizeof(char *) * (size_t)(num_options + 2));
    if (grown == NULL) {
        return num_options;
    }
    *options = grown;
    grown[num_options] = strdup(name);
    grown[num_options + 1] = value ? strdup(value) : NULL;
    return num_options + 2;
}

void cupsFreeOptions(int num_options, char **options)
{
    if (options == NULL) {
        return;
    }
    for (int i = 0; i < num_options; i++) {
        free(options[i]);
    }
    free(options);
}

int cupsCancelJob2(http_t *http, const char *printer, int job_id, int purge)
{
    (void)http; (void)printer; (void)job_id; (void)purge;
    g_last_error = 1;
    g_last_error_string = "No destinations";
    return 0;
}

int cupsEnumDests(unsigned flags, int msec, int *cancel,
                  const char *const *include, const char *const *exclude,
                  int (*cb)(cups_dest_t *dest, void *user_data), void *user_data)
{
    (void)flags; (void)msec; (void)cancel; (void)include; (void)exclude;
    (void)cb; (void)user_data;
    return 0;       /* enumeration complete, zero destinations */
}

int cupsLastError(void)
{
    return g_last_error;
}

const char *cupsLastErrorString(void)
{
    return g_last_error_string;
}

const char *cupsServer(void)
{
    return g_server;
}

const char *cupsUser(void)
{
    return NULL;
}

const char *cupsUserAgent(void)
{
    return "ravynOS libcups/2.14";
}

ipp_t *cupsDoRequest(http_t *http, ipp_t *request, const char *resource)
{
    (void)http; (void)resource;
    /* Nothing to talk to.  The request is consumed, as CUPS does on a
     * transport failure. */
    ippDelete(request);
    g_last_error = 1;
    g_last_error_string = "No destinations";
    return NULL;
}

ipp_t *cupsDoRequestAsync(http_t *http, ipp_t *request, const char *resource)
{
    return cupsDoRequest(http, request, resource);
}

ipp_t *cupsGetResponse(http_t *http)
{
    (void)http;
    return NULL;
}

ipp_t *cupsSendRequest(http_t *http, ipp_t *request, const char *resource,
                       size_t length)
{
    (void)length;
    return cupsDoRequest(http, request, resource);
}

int cupsWriteRequestData(http_t *http, const char *buffer, size_t length)
{
    (void)http; (void)buffer; (void)length;
    return -1;
}

const char *ippPort(void)
{
    return "ipp";
}

void *pwgMediaForSize(int width, int height)
{
    (void)width; (void)height;
    return NULL;
}
