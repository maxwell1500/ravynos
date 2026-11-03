/*
 * spawnprobe -- does posix_spawn deliver a Mach port set to the child?
 *
 * Gecko's first content-process launch waits for the child to send a Mach
 * port and dies with MACH_RCV_TIMED_OUT (0x10004003).  Two questions decide
 * where that is lost:
 *
 *   1. does posix_spawn run a plain child at all (file actions, argv, wait)?
 *   2. does posix_spawnattr_set_registered_ports_np hand the child a send
 *      right it can use to reach the parent?
 *
 * The probe is its own child: "spawnprobe --child <n>" looks the registered
 * ports up and sends one word to the first one.  The parent prints each step
 * and exits non-zero if either answer is no.
 */
#include <errno.h>
#include <mach/mach.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

/* Not in the public SDK header; Apple's libsyscall exports it. */
extern int posix_spawnattr_set_registered_ports_np(posix_spawnattr_t *attrp,
    mach_port_t portarray[], int count);

static int
run_child(int argc, char **argv)
{
	mach_port_array_t ports = NULL;
	mach_msg_type_number_t count = 0;
	kern_return_t kr;
	mach_msg_header_t msg;
	int value = (argc > 2) ? atoi(argv[2]) : 7;

	kr = mach_ports_lookup(mach_task_self(), &ports, &count);
	if (kr != KERN_SUCCESS) {
		fprintf(stderr, "spawnprobe child: mach_ports_lookup kr=0x%x\n",
		    (unsigned)kr);
		return 2;
	}
	if (count < 1 || ports[0] == MACH_PORT_NULL) {
		fprintf(stderr, "spawnprobe child: no registered port (count=%u)\n",
		    (unsigned)count);
		return 3;
	}

	memset(&msg, 0, sizeof(msg));
	msg.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
	msg.msgh_size = sizeof(msg);
	msg.msgh_remote_port = ports[0];
	msg.msgh_local_port = MACH_PORT_NULL;
	msg.msgh_id = value;

	kr = mach_msg(&msg, MACH_SEND_MSG, sizeof(msg), 0,
	    MACH_PORT_NULL, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
	if (kr != KERN_SUCCESS) {
		fprintf(stderr, "spawnprobe child: mach_msg send kr=0x%x\n",
		    (unsigned)kr);
		return 4;
	}
	return 0;
}

int
main(int argc, char **argv)
{
	posix_spawnattr_t attr;
	posix_spawn_file_actions_t actions;
	posix_spawnattr_t *attrp = NULL;
	mach_port_t receive, send;
	char *child_argv[4];
	pid_t pid = 0;
	int err, status = 0;
	kern_return_t kr;
	mach_msg_header_t msg;
	char receive_buffer[512];

	if (argc > 1 && strcmp(argv[1], "--child") == 0)
		return run_child(argc, argv);
	if (argc > 1 && strcmp(argv[1], "--plain") == 0)
		return 0;

	/* 1. Plain spawn, with the same file-action calls Gecko makes. */
	err = posix_spawn_file_actions_init(&actions);
	if (err == 0)
		err = posix_spawn_file_actions_addinherit_np(&actions, STDOUT_FILENO);
	if (err != 0) {
		printf("spawnprobe: file_actions err=%d\n", err);
		return 1;
	}

	child_argv[0] = argv[0];
	child_argv[1] = "--plain";
	child_argv[2] = NULL;
	err = posix_spawn(&pid, argv[0], &actions, NULL, child_argv, environ);
	posix_spawn_file_actions_destroy(&actions);
	printf("spawnprobe: plain posix_spawn err=%d pid=%d\n", err, (int)pid);
	if (err == 0) {
		if (waitpid(pid, &status, 0) != pid || !WIFEXITED(status) ||
		    WEXITSTATUS(status) != 0)
			printf("spawnprobe: plain child status=0x%x\n", status);
		else
			printf("spawnprobe: plain child ok\n");
	}

	/* 2. Spawn with a Mach receive right registered for the child. */
	kr = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE,
	    &receive);
	if (kr != KERN_SUCCESS) {
		printf("spawnprobe: mach_port_allocate kr=0x%x\n", (unsigned)kr);
		return 1;
	}
	kr = mach_port_insert_right(mach_task_self(), receive, receive,
	    MACH_MSG_TYPE_MAKE_SEND);
	if (kr != KERN_SUCCESS) {
		printf("spawnprobe: mach_port_insert_right kr=0x%x\n",
		    (unsigned)kr);
		return 1;
	}

	err = posix_spawnattr_init(&attr);
	if (err == 0)
		err = posix_spawnattr_set_registered_ports_np(&attr, &receive, 1);
	if (err != 0) {
		printf("spawnprobe: set_registered_ports_np err=%d\n", err);
		return 1;
	}
	attrp = &attr;

	pid = 0;
	child_argv[0] = argv[0];
	child_argv[1] = "--child";
	child_argv[2] = "7";
	child_argv[3] = NULL;
	err = posix_spawn(&pid, argv[0], NULL, attrp, child_argv, environ);
	posix_spawnattr_destroy(&attr);
	printf("spawnprobe: port posix_spawn err=%d pid=%d\n", err, (int)pid);
	if (err != 0)
		return 1;

	memset(receive_buffer, 0, sizeof(receive_buffer));
	kr = mach_msg((mach_msg_header_t *)receive_buffer,
	    MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0, sizeof(receive_buffer),
	    receive, 5000, MACH_PORT_NULL);
	memcpy(&msg, receive_buffer, sizeof(msg));
	printf("spawnprobe: rendezvous recv kr=0x%x id=%u\n", (unsigned)kr,
	    (unsigned)msg.msgh_id);

	if (kr == KERN_SUCCESS && msg.msgh_id == 7) {
		if (waitpid(pid, &status, 0) != pid || !WIFEXITED(status) ||
		    WEXITSTATUS(status) != 0)
			printf("spawnprobe: port child status=0x%x\n", status);
		else
			printf("spawnprobe: port child ok\n");
		return 0;
	}
	return 1;
}
