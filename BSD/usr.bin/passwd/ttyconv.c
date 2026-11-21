/* SPDX-License-Identifier: BSD-2-Clause */
/* The conventional terminal conversation function: prompt on stderr, read the
 * answer from stdin, and turn echo off for PAM_PROMPT_ECHO_OFF.  FreeBSD ships
 * this inside libpam; this libpam does not export it, so passwd carries it. */
#include <sys/types.h>

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <security/openpam.h>

int
openpam_ttyconv(int num_msg, const struct pam_message **msg,
    struct pam_response **resp, void *data)
{
	struct pam_response *r;
	char buf[256];
	int i;

	(void)data;
	if (num_msg <= 0 || (*resp = calloc(num_msg, sizeof(**resp))) == NULL)
		return PAM_BUF_ERR;
	r = *resp;
	for (i = 0; i < num_msg; i++) {
		switch (msg[i]->msg_style) {
		case PAM_PROMPT_ECHO_OFF:
		case PAM_PROMPT_ECHO_ON:
			if (msg[i]->msg != NULL)
				fputs(msg[i]->msg, stderr);
			if (fgets(buf, sizeof(buf), stdin) == NULL) {
				free(r);
				*resp = NULL;
				return PAM_CONV_ERR;
			}
			buf[strcspn(buf, "\n")] = '\0';
			if ((r[i].resp = strdup(buf)) == NULL) {
				free(r);
				*resp = NULL;
				return PAM_BUF_ERR;
			}
			break;
		case PAM_ERROR_MSG:
			if (msg[i]->msg != NULL)
				fprintf(stderr, "%s\n", msg[i]->msg);
			break;
		case PAM_TEXT_INFO:
			if (msg[i]->msg != NULL)
				printf("%s\n", msg[i]->msg);
			break;
		default:
			free(r);
			*resp = NULL;
			return PAM_CONV_ERR;
		}
	}
	return PAM_SUCCESS;
}
