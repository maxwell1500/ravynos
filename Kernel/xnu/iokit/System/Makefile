export MakeInc_cmd=${SRCROOT}/makedefs/MakeInc.cmd
export MakeInc_def=${SRCROOT}/makedefs/MakeInc.def
export MakeInc_rule=${SRCROOT}/makedefs/MakeInc.rule
export MakeInc_dir=${SRCROOT}/makedefs/MakeInc.dir

# These are System.framework headers

include $(MakeInc_cmd)
include $(MakeInc_def)

ALL_HDRS = $(shell (cd $(SOURCE); echo *.h))

# INSTINC_SUBDIRS = Headers

EXPINC_SUBDIRS = ${INSTINC_SUBDIRS}

EXPORT_MI_LIST = $(ALL_HDRS)
EXPORT_MI_DIR = System

INSTALL_SF_MI_LCL_LIST = $(ALL_HDRS)

INSTALL_MI_GEN_LIST = $(GENERATED_HEADERS)

include $(MakeInc_rule)
include $(MakeInc_dir)
