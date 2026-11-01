/*
 * mount -- list mounted filesystems.  Mounting new filesystems is the
 * installer's job (Phase 6); this is the read-only view /sbin/mount
 * provides on a running system.
 */
#include <err.h>
#include <stdio.h>
#include <sys/mount.h>
#include <sys/param.h>

int
main(void)
{
	struct statfs *mnt;
	int count = getmntinfo(&mnt, MNT_WAIT);

	if (count <= 0)
		err(1, "getmntinfo");
	for (int i = 0; i < count; i++)
		printf("%s on %s (%s, %s)\n", mnt[i].f_mntfromname,
		    mnt[i].f_mntonname, mnt[i].f_fstypename,
		    (mnt[i].f_flags & MNT_RDONLY) ? "read-only" : "local");
	return 0;
}
