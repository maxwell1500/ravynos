/*
 * tsample -- print where every thread of a process is executing.
 *
 * tdump shows which thread burns CPU but not where.  As root,
 * task_for_pid + task_threads + thread_get_state gives each thread's
 * user PC; reading the target's dyld_all_image_infos (TASK_DYLD_INFO)
 * resolves that PC to "image + offset" so it can be symbolicated without
 * a kernel debugger and without guessing the ASLR slide.
 *
 *   tsample <pid>
 */
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <mach/task_info.h>
#include <mach/thread_act.h>
#include <mach/i386/thread_status.h>
#include <mach/thread_info.h>
#include <mach-o/dyld_images.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_IMAGES 512

static int
read_mem(task_t task, uint64_t addr, void *buf, mach_vm_size_t size)
{
	mach_vm_size_t out = 0;
	return mach_vm_read_overwrite(task, (mach_vm_address_t)addr, size,
	    (mach_vm_address_t)(uintptr_t)buf, &out) == KERN_SUCCESS ? 0 : -1;
}

int
main(int argc, char **argv)
{
	task_t task = MACH_PORT_NULL;
	thread_act_array_t threads = NULL;
	mach_msg_type_number_t count = 0;
	struct task_dyld_info tdi;
	mach_msg_type_number_t tdic = TASK_DYLD_INFO_COUNT;
	struct dyld_image_info images[MAX_IMAGES];
	uint64_t bases[MAX_IMAGES];
	int nimages = 0;
	int pid;

	if (argc != 2) {
		fprintf(stderr, "usage: tsample <pid>\n");
		return 2;
	}
	pid = atoi(argv[1]);

	kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
	if (kr != KERN_SUCCESS) {
		fprintf(stderr, "tsample: task_for_pid(%d) kr=0x%x\n", pid, kr);
		return 1;
	}

	memset(&tdi, 0, sizeof(tdi));
	if (task_info(task, TASK_DYLD_INFO, (task_info_t)&tdi, &tdic) == KERN_SUCCESS &&
	    tdi.all_image_info_addr != 0) {
		struct dyld_all_image_infos aii;
		memset(&aii, 0, sizeof(aii));
		if (read_mem(task, tdi.all_image_info_addr, &aii,
		    sizeof(aii.version) + sizeof(aii.infoArrayCount) + sizeof(aii.infoArray)) == 0) {
			uint32_t n = aii.infoArrayCount;
			if (n > MAX_IMAGES) n = MAX_IMAGES;
			if (n && read_mem(task, (uint64_t)(uintptr_t)aii.infoArray, images,
			    (mach_vm_size_t)n * sizeof(struct dyld_image_info)) == 0) {
				nimages = (int)n;
				for (int i = 0; i < nimages; i++)
					bases[i] = (uint64_t)(uintptr_t)images[i].imageLoadAddress;
			}
		}
	}

	kr = task_threads(task, &threads, &count);
	if (kr != KERN_SUCCESS) {
		fprintf(stderr, "tsample: task_threads kr=0x%x\n", kr);
		return 1;
	}
	printf("tsample: pid %d threads=%u images=%d\n", pid, count, nimages);
	for (mach_msg_type_number_t i = 0; i < count; i++) {
		x86_thread_state64_t state;
		mach_msg_type_number_t sc = x86_THREAD_STATE64_COUNT;
		thread_identifier_info_data_t ti;
		mach_msg_type_number_t tc = THREAD_IDENTIFIER_INFO_COUNT;
		const char *where = "?";
		char path[256];
		uint64_t off = 0;
		uint64_t tid = 0;

		if (thread_get_state(threads[i], x86_THREAD_STATE64,
		    (thread_state_t)&state, &sc) != KERN_SUCCESS)
			continue;
		if (thread_info(threads[i], THREAD_IDENTIFIER_INFO,
		    (thread_info_t)&ti, &tc) == KERN_SUCCESS)
			tid = ti.thread_id;

		int best = -1;
		for (int k = 0; k < nimages; k++) {
			if (bases[k] <= state.__rip && (best < 0 || bases[k] > bases[best]))
				best = k;
		}
		if (best >= 0) {
			memset(path, 0, sizeof(path));
			if (read_mem(task, (uint64_t)(uintptr_t)images[best].imageFilePath,
			    path, sizeof(path) - 1) == 0) {
				const char *slash = strrchr(path, '/');
				where = slash ? slash + 1 : path;
			}
			off = state.__rip - bases[best];
		}
		printf("  tid %llu rip 0x%016llx %s+0x%llx\n",
		    (unsigned long long)tid, (unsigned long long)state.__rip,
		    where, (unsigned long long)off);
	}

	for (mach_msg_type_number_t i = 0; i < count; i++)
		mach_port_deallocate(mach_task_self(), threads[i]);
	mach_port_deallocate(mach_task_self(), task);
	return 0;
}
