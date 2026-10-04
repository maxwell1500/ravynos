/*-
 * Copyright (c) 1996 by
 * Sean Eric Fagan <sef@kithrup.com>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, is permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice immediately at the beginning of the file, without modification,
 *    this list of conditions, and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. This work was done expressly for inclusion into FreeBSD.  Other use
 *    is permitted provided this notation is included.
 * 4. Absolutely no warranty of function or purpose is made by the authors.
 * 5. Modifications may be freely made to this file providing the above
 *    conditions are met.
 *
 * Login class handling: setusercontext() and friends.
 *
 * ravynOS: vendored from FreeBSD lib/libutil/login_class.c.  Deviations, all
 * forced by what this tree has:
 *
 *  - sys/cpuset.h, sys/rtprio.h and sys/mac.h do not exist in this SDK, and
 *    the facilities behind them do not exist in this kernel either (there is
 *    no cpuset syscall anywhere in Kernel/xnu, no rtprio(), and no MAC
 *    framework).  So:
 *      * setclasscpumask() parses the mask into a cpu_set_t as upstream does
 *        and then has no syscall to hand it to.  It reports that plainly
 *        instead of silently claiming success.
 *      * setclasspriority() clamps to the setpriority(2) range and drops the
 *        rtprio(2) escalation path.
 *      * the LOGIN_SETMAC block is gone; mac_is_present() is not defined
 *        anywhere, so the branch was unreachable and its condition could not
 *        be evaluated.
 *  - setloginclass() does not exist in this tree's libc or kernel.  The
 *    LOGIN_SETLOGINCLASS branch is kept but its body is dropped; see
 *    setusercontext().
 *  - The resource table loses the rows for RLIMIT_ constants this kernel does
 *    not have (RLIMIT_SBSIZE, RLIMIT_VMEM, RLIMIT_NPTS, RLIMIT_SWAP,
 *    RLIMIT_UMTXP, RLIMIT_KQUEUES, RLIMIT_VMM, RLIMIT_PIPEBUF), and
 *    "memoryuse" moves from RLIMIT_RSS to RLIMIT_AS because this SDK defines
 *    RLIMIT_AS and only aliases RLIMIT_RSS to it.
 *  - cpu_set_t and the CPU_SETSIZE/CPU_ZERO/CPU_SET macros are defined here
 *    (login_class_local.h) because sys/cpuset.h is not available.
 */

#include <sys/param.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/time.h>

#include <ctype.h>
#include <errno.h>
#include <login_cap.h>
#include <paths.h>
#include <pwd.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <unistd.h>

#include "login_class_local.h"

static struct login_res {
    const char *what;
    rlim_t (*who)(login_cap_t *, const char *, rlim_t, rlim_t);
    int why;
} resources[] = {
    { "cputime",         login_getcaptime, RLIMIT_CPU     },
    { "filesize",        login_getcapsize, RLIMIT_FSIZE   },
    { "datasize",        login_getcapsize, RLIMIT_DATA    },
    { "stacksize",       login_getcapsize, RLIMIT_STACK   },
    { "memoryuse",       login_getcapsize, RLIMIT_AS      },
    { "memorylocked",    login_getcapsize, RLIMIT_MEMLOCK },
    { "maxproc",         login_getcapnum,  RLIMIT_NPROC   },
    { "openfiles",       login_getcapnum,  RLIMIT_NOFILE  },
    { "coredumpsize",    login_getcapsize, RLIMIT_CORE    },
    { NULL,              0,                0              }
};


void
setclassresources(login_cap_t *lc)
{
    struct login_res *lr;

    if (lc == NULL)
	return;

    for (lr = resources; lr->what != NULL; ++lr) {
	struct rlimit	rlim;

	/*
	 * The login.conf file can have <limit>, <limit>-max, and
	 * <limit>-cur entries.
	 * What we do is get the current current- and maximum- limits.
	 * Then, we try to get an entry for <limit> from the capability,
	 * using the current and max limits we just got as the
	 * default/error values.
	 * *Then*, we try looking for <limit>-cur and <limit>-max,
	 * again using the appropriate values as the default/error
	 * conditions.
	 */

	if (getrlimit(lr->why, &rlim) != 0)
	    syslog(LOG_ERR, "getting %s resource limit: %m", lr->what);
	else {
	    char	name_cur[40];
	    char	name_max[40];
	    rlim_t	rcur = rlim.rlim_cur;
	    rlim_t	rmax = rlim.rlim_max;

	    snprintf(name_cur, sizeof name_cur, "%s-cur", lr->what);
	    snprintf(name_max, sizeof name_max, "%s-max", lr->what);

	    rcur = (*lr->who)(lc, lr->what, rcur, rcur);
	    rmax = (*lr->who)(lc, lr->what, rmax, rmax);
	    rlim.rlim_cur = (*lr->who)(lc, name_cur, rcur, rcur);
	    rlim.rlim_max = (*lr->who)(lc, name_max, rmax, rmax);

	    if (setrlimit(lr->why, &rlim) == -1)
		syslog(LOG_WARNING, "set class '%s' resource limit %s: %m", lc->lc_class, lr->what);
	}
    }
}



static struct login_vars {
    const char *tag;
    const char *var;
    const char *def;
    int overwrite;
} pathvars[] = {
    { "path",           "PATH",       NULL, 1},
    { "cdpath",         "CDPATH",     NULL, 1},
    { "manpath",        "MANPATH",    NULL, 1},
    { NULL,             NULL,         NULL, 0}
}, envars[] = {
    { "lang",           "LANG",       NULL, 1},
    { "charset",        "MM_CHARSET", NULL, 1},
    { "mail",           "MAIL",       NULL, 1},
    { "timezone",       "TZ",         NULL, 1},
    { "term",           "TERM",       NULL, 0},
    { NULL,             NULL,         NULL, 0}
};

static char *
substvar(const char * var, const struct passwd * pwd, int hlen, int pch, int nlen)
{
    char    *np = NULL;

    if (var != NULL) {
	int	tildes = 0;
	int	dollas = 0;
	char	*p;
	const char *q;

	if (pwd != NULL) {
	    for (q = var; *q != '\0'; ++q) {
		tildes += (*q == '~');
		dollas += (*q == '$');
	    }
	}

	np = malloc(strlen(var) + (dollas * nlen)
		    - dollas + (tildes * (pch+hlen))
		    - tildes + 1);

	if (np != NULL) {
	    p = strcpy(np, var);

	    if (pwd != NULL) {
		/*
		 * This loop does user username and homedir substitutions
		 * for unescaped $ (username) and ~ (homedir)
		 */
		while (*(p += strcspn(p, "~$")) != '\0') {
		    int	l = strlen(p);

		    if (p > np && *(p-1) == '\\')  /* Escaped: */
			memmove(p - 1, p, l + 1); /* Slide-out the backslash */
		    else if (*p == '~') {
			int	v = pch && *(p+1) != '/'; /* Avoid double // */
			memmove(p + hlen + v, p + 1, l);  /* Subst homedir */
			memmove(p, pwd->pw_dir, hlen);
			if (v)
			    p[hlen] = '/';
			p += hlen + v;
		    }
		    else /* if (*p == '$') */ {
			memmove(p + nlen, p + 1, l);	/* Subst username */
			memmove(p, pwd->pw_name, nlen);
			p += nlen;
		    }
		}
	    }
	}
    }

    return (np);
}


void
setclassenvironment(login_cap_t *lc, const struct passwd * pwd, int paths)
{
    struct login_vars	*vars = paths ? pathvars : envars;
    int			hlen = pwd ? strlen(pwd->pw_dir) : 0;
    int			nlen = pwd ? strlen(pwd->pw_name) : 0;
    char pch = 0;

    if (hlen && pwd->pw_dir[hlen-1] != '/')
	++pch;

    while (vars->tag != NULL) {
	const char * var = paths ? login_getpath(lc, vars->tag, NULL)
				 : login_getcapstr(lc, vars->tag, NULL, NULL);

	char * np  = substvar(var, pwd, hlen, pch, nlen);

	if (np != NULL) {
	    setenv(vars->var, np, vars->overwrite);
	    free(np);
	} else if (vars->def != NULL) {
	    setenv(vars->var, vars->def, 0);
	}
	++vars;
    }

    /*
     * If we're not processing paths, then see if there is a setenv list by
     * which the admin and/or user may set an arbitrary set of env vars.
     */
    if (!paths) {
	const char	**set_env = login_getcaplist(lc, "setenv", ",");

	if (set_env != NULL) {
	    while (*set_env != NULL) {
		char	*p = strchr(*set_env, '=');

		if (p != NULL && p != *set_env) {  /* Discard invalid entries */
		    const char	*ep;
		    char	*np;

		    *p++ = '\0';
		    /* Strip leading spaces from variable name */
		    ep = *set_env;
		    while (*ep == ' ' || *ep == '\t')
			ep++;
		    if ((np = substvar(p, pwd, hlen, pch, nlen)) != NULL) {
			setenv(ep, np, 1);
			free(np);
		    }
		}
		++set_env;
	    }
	}
    }
}


static int
list2cpuset(const char *list, cpuset_t *mask)
{
	enum { NONE, NUM, DASH } state;
	int lastnum;
	int curnum;
	const char *l;

	state = NONE;
	curnum = lastnum = 0;
	for (l = list; *l != '\0';) {
		if (isdigit((unsigned char)*l)) {
			curnum = atoi(l);
			if (curnum >= CPU_SETSIZE)
				return (0);
			while (isdigit((unsigned char)*l))
				l++;
			switch (state) {
			case NONE:
				lastnum = curnum;
				state = NUM;
				break;
			case DASH:
				for (; lastnum <= curnum; lastnum++)
					CPU_SET(lastnum, mask);
				state = NONE;
				break;
			case NUM:
			default:
				return (0);
			}
			continue;
		}
		switch (*l) {
		case ',':
			switch (state) {
			case NONE:
				break;
			case NUM:
				CPU_SET(curnum, mask);
				state = NONE;
				break;
			case DASH:
				return (0);
				break;
			}
			break;
		case '-':
			if (state != NUM)
				return (0);
			state = DASH;
			break;
		default:
			return (0);
		}
		l++;
	}
	switch (state) {
		case NONE:
			break;
		case NUM:
			CPU_SET(curnum, mask);
			break;
		case DASH:
			return (0);
	}
	return (1);
}


void
setclasscpumask(login_cap_t *lc)
{
	const char *maskstr;
	cpuset_t maskset;
	int ncpu, nset;

	maskstr = login_getcapstr(lc, "cpumask", NULL, NULL);
	CPU_ZERO(&maskset);
	if (maskstr == NULL)
		return;
	if (strcasecmp("default", maskstr) == 0)
		return;
	if (!list2cpuset(maskstr, &maskset)) {
		syslog(LOG_WARNING,
		    "list2cpuset(%s) invalid mask specification", maskstr);
		return;
	}

	/*
	 * Upstream hands the parsed mask to cpuset_setaffinity(2).  That
	 * syscall does not exist in this kernel -- there is no cpuset code in
	 * Kernel/xnu at all, and no cpuset_setaffinity symbol in any SDK
	 * dylib -- and there is no other way to constrain a process to a set
	 * of CPUs: the kernel's only affinity interface is
	 * thread_affinity_set(), which tags a thread for cache-locality
	 * grouping and takes no CPU list.  So the mask is validated (which is
	 * the part that can be done correctly) and then reported as not
	 * applied, rather than silently succeeding.
	 */
	for (ncpu = nset = 0; ncpu < CPU_SETSIZE; ncpu++)
		if (CPU_ISSET(ncpu, &maskset))
			nset++;
	if (nset == 0)
		syslog(LOG_ERR, "cpumask '%s' selects no CPUs", maskstr);
	else
		syslog(LOG_ERR,
		    "cpumask '%s' selects %d of %d CPUs: not applied, "
		    "this kernel has no cpuset facility", maskstr, nset,
		    CPU_SETSIZE);
}


/*
 * setclasscontext()
 *
 * For the login class <class>, set various class context values
 * (limits, mainly) to the values for that class.  Which values are
 * set are controlled by <flags> -- see <login_class.h> for the
 * possible values.
 *
 * setclasscontext() can only set resources, priority, and umask.
 */

int
setclasscontext(const char *classname, unsigned int flags)
{
    int		rc;
    login_cap_t *lc;

    lc = login_getclassbyname(classname, NULL);

    flags &= LOGIN_SETRESOURCES | LOGIN_SETPRIORITY |
	    LOGIN_SETUMASK | LOGIN_SETPATH;

    rc = lc ? setusercontext(lc, NULL, 0, flags) : -1;
    login_close(lc);
    return (rc);
}


static const char * const inherit_enum[] = {
    "inherit",
    NULL
};

/*
 * Private function setting umask from the login class.
 */
static void
setclassumask(login_cap_t *lc, const struct passwd *pwd)
{
	/*
	 * Make it unlikely that someone would input our default sentinel
	 * indicating no specification.
	 */
	const rlim_t def_val = INT64_MIN + 1, err_val = INT64_MIN;
	rlim_t val;

	/* If value is "inherit", nothing to change. */
	if (login_getcapenum(lc, "umask", inherit_enum) == 0)
		return;

	val = login_getcapnum(lc, "umask", def_val, err_val);

	if (val != def_val) {
		if (val < 0 || val > UINT16_MAX) {
			/* We get here also on 'err_val'. */
			syslog(LOG_WARNING,
			    "%s%s%sLogin class '%s': "
			    "Invalid umask specification: '%s'",
			    pwd ? "Login '" : "",
			    pwd ? pwd->pw_name : "",
			    pwd ? "': " : "",
			    lc->lc_class,
			    login_getcapstr(lc, "umask", "", ""));
		} else {
			const mode_t mode = val;

			umask(mode);
		}
	}
}

/*
 * Private function which takes care of processing
 */
static void
setlogincontext(login_cap_t *lc, const struct passwd *pwd, unsigned long flags)
{
	if (lc == NULL)
		return;

	/* Set resources. */
	if ((flags & LOGIN_SETRESOURCES) != 0)
		setclassresources(lc);

	/* See if there's a umask override. */
	if ((flags & LOGIN_SETUMASK) != 0)
		setclassumask(lc, pwd);

	/* Set paths. */
	if ((flags & LOGIN_SETPATH) != 0)
		setclassenvironment(lc, pwd, 1);

	/* Set environment. */
	if ((flags & LOGIN_SETENV) != 0)
		setclassenvironment(lc, pwd, 0);

	/* Set cpu affinity. */
	if ((flags & LOGIN_SETCPUMASK) != 0)
		setclasscpumask(lc);
}


/*
 * Private function to set process priority.
 */
static void
setclasspriority(login_cap_t * const lc, struct passwd const * const pwd)
{
	const rlim_t def_val = 0, err_val = INT64_MIN;
	rlim_t p;
	int rc;

	/* If value is "inherit", nothing to change. */
	if (login_getcapenum(lc, "priority", inherit_enum) == 0)
		return;

	p = login_getcapnum(lc, "priority", def_val, err_val);

	if (p == err_val) {
		/* Invariant: 'lc' != NULL. */
		syslog(LOG_WARNING,
		    "%s%s%sLogin class '%s': "
		    "Invalid priority specification: '%s'",
		    pwd ? "Login '" : "",
		    pwd ? pwd->pw_name : "",
		    pwd ? "': " : "",
		    lc->lc_class,
		    login_getcapstr(lc, "priority", "", ""));
		/* Reset the priority, as if the capability was not present. */
		p = def_val;
	}

	/*
	 * Upstream escalates priorities outside the setpriority(2) range to
	 * rtprio(2) (RTP_PRIO_IDLE above the range, RTP_PRIO_REALTIME below
	 * it).  rtprio(2) does not exist in this kernel -- no sys/rtprio.h
	 * in the SDK, no rtprio symbol in any dylib, and no implementation
	 * anywhere in Kernel/xnu -- so a priority outside the nice range is
	 * clamped into it and the loss is reported rather than passed to
	 * setpriority(2), which would fail on it anyway.
	 */
	if (p > PRIO_MAX || p < PRIO_MIN) {
		syslog(LOG_WARNING,
		    "%s%s%sLogin class '%s': priority %lld is outside "
		    "the setpriority(2) range [%d, %d]; clamped",
		    pwd ? "Login '" : "",
		    pwd ? pwd->pw_name : "",
		    pwd ? "': " : "",
		    lc ? lc->lc_class : "<none>",
		    (long long)p, PRIO_MIN, PRIO_MAX);
		p = (p > PRIO_MAX) ? PRIO_MAX : PRIO_MIN;
	}

	rc = setpriority(PRIO_PROCESS, 0, (int)p);

	if (rc != 0)
		syslog(LOG_WARNING,
		    "%s%s%sLogin class '%s': "
		    "Setting priority failed: %m",
		    pwd ? "Login '" : "",
		    pwd ? pwd->pw_name : "",
		    pwd ? "': " : "",
		    lc ? lc->lc_class : "<none>");
}

/*
 * setusercontext()
 *
 * Given a login class <lc> and a user in <pwd>, with a uid <uid>,
 * set the context as in setclasscontext().  <flags> controls which
 * values are set.
 *
 * The difference between setclasscontext() and setusercontext() is
 * that the former sets things up for an already-existing process,
 * while the latter sets things up from a root context.  Such as might
 * be called from login(1).
 *
 */

int
setusercontext(login_cap_t *lc, const struct passwd *pwd, uid_t uid, unsigned int flags)
{
    login_cap_t *llc = NULL;

    if (lc == NULL) {
	if (pwd != NULL && (lc = login_getpwclass(pwd)) != NULL)
	    llc = lc; /* free this when we're done */
    }

    if (flags & LOGIN_SETPATH)
	pathvars[0].def = uid ? _PATH_DEFPATH : _PATH_STDPATH;

    /* we need a passwd entry to set these */
    if (pwd == NULL)
	flags &= ~(LOGIN_SETGROUP | LOGIN_SETLOGIN);

    /* Set the process priority */
    if (flags & LOGIN_SETPRIORITY)
	setclasspriority(lc, pwd);

    /* Setup the user's group permissions */
    if (flags & LOGIN_SETGROUP) {
	if (setgid(pwd->pw_gid) != 0) {
	    syslog(LOG_ERR, "setgid(%lu): %m", (u_long)pwd->pw_gid);
	    login_close(llc);
	    return (-1);
	}
	if (initgroups(pwd->pw_name, pwd->pw_gid) == -1) {
	    syslog(LOG_ERR, "initgroups(%s,%lu): %m", pwd->pw_name,
		   (u_long)pwd->pw_gid);
	    login_close(llc);
	    return (-1);
	}
    }

    /* Set the sessions login */
    if ((flags & LOGIN_SETLOGIN) && setlogin(pwd->pw_name) != 0) {
	syslog(LOG_ERR, "setlogin(%s): %m", pwd->pw_name);
	login_close(llc);
	return (-1);
    }

    /*
     * Inform the kernel about current login class.
     *
     * Upstream calls setloginclass(), a syscall wrapper that does not
     * exist here: it is not declared in the SDK's unistd.h (only in
     * BSD/include/unistd.h, which nothing in this build reads), it is
     * defined in no SDK dylib, and Kernel/xnu has no corresponding
     * syscall or sysctl -- there is no sys_setloginclass and no kern
     * sysctl for it.  The flag stays honoured as a no-op and the class
     * name is logged, so a caller that asks for it learns that the
     * kernel was not told rather than believing that it was.
     */
    if (lc != NULL && lc->lc_class != NULL && (flags & LOGIN_SETLOGINCLASS))
	syslog(LOG_INFO, "login class '%s' not set in the kernel: "
	    "setloginclass() is not implemented on this system", lc->lc_class);

    setlogincontext(lc, pwd, flags);

    login_close(llc);

    /* This needs to be done after anything that needs root privs */
    if ((flags & LOGIN_SETUSER) && setuid(uid) != 0) {
	syslog(LOG_ERR, "setuid(%lu): %m", (u_long)uid);
	return (-1);	/* Paranoia again */
    }

    /*
     * Now, we repeat some of the above for the user's private entries
     */
    if (geteuid() == uid && (lc = login_getuserclass(pwd)) != NULL) {
	setlogincontext(lc, pwd, flags);
	if (flags & LOGIN_SETPRIORITY)
	    setclasspriority(lc, pwd);
	login_close(lc);
    }

    return (0);
}