/*
 * df -- report mounted filesystem usage.
 */
#include <err.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mount.h>
#include <sys/param.h>

int
main(void)
{
	struct statfs *mnt;
	int count = getmntinfo(&mnt, MNT_WAIT);
	if (count <= 0)
		err(1, "getmntinfo");

	printf("%-24s %10s %10s %10s %5s %s\n",
	    "Filesystem", "1024-blocks", "Used", "Available", "Capacity", "Mounted on");
	for (int i = 0; i < count; i++) {
		unsigned long long total = (unsigned long long)mnt[i].f_blocks *
		    (mnt[i].f_bsize / 1024);
		unsigned long long used = (unsigned long long)(mnt[i].f_blocks -
		    mnt[i].f_bfree) * (mnt[i].f_bsize / 1024);
		unsigned long long avail = (unsigned long long)mnt[i].f_bavail *
		    (mnt[i].f_bsize / 1024);
		int pct = total ? (int)((used * 100) / total) : 0;
		printf("%-24s %10llu %10llu %10llu %4d%% %s\n",
		    mnt[i].f_mntfromname, total, used, avail, pct,
		    mnt[i].f_mntonname);
	}
	return 0;
}
