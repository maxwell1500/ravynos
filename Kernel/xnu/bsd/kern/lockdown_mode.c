/*
 * Copyright (c) 2022 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * The contents of this file constitute Original Code as defined in and
 * are subject to the Apple Public Source License Version 1.1 (the
 * "License").  You may not use this file except in compliance with the
 * License.  Please obtain a copy of the License at
 * http://www.apple.com/publicsource and read it before using this file.
 *
 * This Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

#include <libkern/libkern.h>
#include <sys/sysctl.h>
#include <sys/lockdown_mode.h>
#include <IOKit/IOPlatformExpert.h>
#include <IOKit/IOKitKeysPrivate.h>

static const char * kLockdownModeNVRAMVariableKey = kIOKitSystemGUID ":ldm";

#pragma mark Initialization

static LCK_GRP_DECLARE(lockdown_mode_init_lck_grp, "lockdown_mode_init_lock");
static LCK_MTX_DECLARE(lockdown_mode_init_mtx, &lockdown_mode_init_lck_grp);

static int lockdown_mode_init_done = 0;

int lockdown_mode_state = 0;

SYSCTL_DECL(_security_mac);
SYSCTL_INT(_security_mac, OID_AUTO, lockdown_mode_state, CTLFLAG_RD | CTLFLAG_LOCKED, &lockdown_mode_state, 0, "Lockdown Mode state");

__startup_func
void
lockdown_mode_init(void)
{
	lockdown_mode_state = 0;

	lck_mtx_lock(&lockdown_mode_init_mtx);
	lockdown_mode_init_done = 1;
	wakeup(&lockdown_mode_init_done);
	lck_mtx_unlock(&lockdown_mode_init_mtx);
}

__startup_func
static void
lockdown_mode_init_startup(void)
{
	lockdown_mode_init();
}
STARTUP(EARLY_BOOT, STARTUP_RANK_LAST, lockdown_mode_init_startup);

int
get_lockdown_mode_state(void)
{
	lck_mtx_lock(&lockdown_mode_init_mtx);
	if (!lockdown_mode_init_done) {
		msleep(&lockdown_mode_init_done, &lockdown_mode_init_mtx, 0, "get_lockdown_mode_state", NULL);
	}
	lck_mtx_unlock(&lockdown_mode_init_mtx);

#if XNU_TARGET_OS_XR
	printf("lockdown_mode: disabling lockdown mode on visionOS\n");
	disable_lockdown_mode();
#endif

	return lockdown_mode_state;
}

void
enable_lockdown_mode(void)
{
	lockdown_mode_state = 1;
	PEWriteNVRAMBooleanProperty(kLockdownModeNVRAMVariableKey, TRUE);
}

void
disable_lockdown_mode(void)
{
	lockdown_mode_state = 0;
	PERemoveNVRAMProperty(kLockdownModeNVRAMVariableKey);
}
