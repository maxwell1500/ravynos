/*
 * backup -- tmutil must copy a tree, verify it, notice a changed file,
 * and restore the original bytes.
 */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int
write_file(const char *path, const char *text)
{
	int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (fd < 0)
		return -1;
	if (write(fd, text, strlen(text)) != (ssize_t)strlen(text)) {
		close(fd);
		return -1;
	}
	close(fd);
	return 0;
}

static int
read_file(const char *path, char *buf, size_t size)
{
	int fd = open(path, O_RDONLY);
	ssize_t n;
	if (fd < 0)
		return -1;
	n = read(fd, buf, size - 1);
	close(fd);
	if (n < 0)
		return -1;
	buf[n] = '\0';
	return 0;
}

int
main(void)
{
	char buf[64];

	mkdir("/tmp/tmtest", 0777);
	mkdir("/tmp/tmtest/src", 0777);
	mkdir("/tmp/tmtest/src/sub", 0777);
	if (write_file("/tmp/tmtest/src/sub/file.txt", "original\n") != 0)
		return 1;

	if (system("/usr/bin/tmutil backup /tmp/tmtest/src /tmp/tmtest/dst") != 0)
		return 1;
	if (system("/usr/bin/tmutil verify /tmp/tmtest/src /tmp/tmtest/dst") != 0)
		return 1;

	if (write_file("/tmp/tmtest/src/sub/file.txt", "changed\n") != 0)
		return 1;
	if (system("/usr/bin/tmutil verify /tmp/tmtest/src /tmp/tmtest/dst") == 0)
		return 1;	/* a changed file must not verify */

	if (system("/usr/bin/tmutil restore /tmp/tmtest/dst /tmp/tmtest/src") != 0)
		return 1;
	if (read_file("/tmp/tmtest/src/sub/file.txt", buf, sizeof(buf)) != 0)
		return 1;
	if (strcmp(buf, "original\n") != 0)
		return 1;

	printf("backup: copy, detect and restore verified\n");
	return 0;
}
