/* SPDX-License-Identifier: BSD-2-Clause */
/* diff(1) for ravynOS.
 *
 * The image shipped no diff frontend.  This implements the forms build scripts
 * actually use: normal ed-style output, unified output (-u), brief mode (-q),
 * recursive directory comparison (-r) and treat-absent-as-empty (-N).
 *
 * The core is a patience diff: lines unique on both sides anchor the problem,
 * the gaps are solved with an LCS table.  A gap larger than the table budget
 * is emitted as a replacement rather than silently mis-ordered, so the output
 * stays applicable even though it is coarser for pathological inputs. */
#include <sys/types.h>
#include <sys/stat.h>

#include <dirent.h>
#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define LCS_BUDGET	(4u * 1024u * 1024u)	/* cells, 16 MB of uint32 */
#define CONTEXT		3

struct line {
	char *s;
	size_t len;
	int nl;
	uint64_t hash;
};

struct file {
	struct line *lines;
	size_t n;
	char *data;
};

enum op_type { OP_SAME = ' ', OP_DEL = '-', OP_ADD = '+' };

struct op {
	enum op_type type;
	size_t ai;
	size_t bi;
};

struct ops {
	struct op *v;
	size_t n, cap;
};

static int uflag, qflag, rflag, nflag;
static int status;

static void
ops_add(struct ops *ops, enum op_type type, size_t ai, size_t bi)
{
	if (ops->n == ops->cap) {
		size_t cap = ops->cap ? ops->cap * 2 : 256;
		struct op *v = realloc(ops->v, cap * sizeof(*v));

		if (v == NULL)
			err(2, NULL);
		ops->v = v;
		ops->cap = cap;
	}
	ops->v[ops->n].type = type;
	ops->v[ops->n].ai = ai;
	ops->v[ops->n].bi = bi;
	ops->n++;
}

static uint64_t
hash_line(const char *s, size_t len)
{
	uint64_t h = 1469598103934665603ULL;

	for (size_t i = 0; i < len; i++) {
		h ^= (unsigned char)s[i];
		h *= 1099511628211ULL;
	}
	return h;
}

static int
read_file(const char *path, struct file *f)
{
	char *data = NULL;
	size_t size = 0, cap = 0;
	int fd;

	memset(f, 0, sizeof(*f));
	if (strcmp(path, "/dev/null") == 0)
		return 0;
	if (strcmp(path, "-") == 0)
		fd = STDIN_FILENO;
	else
		fd = open(path, O_RDONLY);
	if (fd < 0)
		return -1;
	for (;;) {
		ssize_t got;

		if (size == cap) {
			cap = cap ? cap * 2 : 65536;
			if ((data = realloc(data, cap + 1)) == NULL)
				err(2, NULL);
		}
		got = read(fd, data + size, cap - size);
		if (got < 0) {
			int saved = errno;

			free(data);
			if (fd != STDIN_FILENO)
				close(fd);
			errno = saved;
			return -1;
		}
		if (got == 0)
			break;
		size += (size_t)got;
	}
	if (fd != STDIN_FILENO)
		close(fd);
	if (data == NULL)
		data = calloc(1, 1);
	data[size] = '\0';

	/* Count lines.  A trailing newline terminates the last line; it does
	 * not introduce an empty one. */
	size_t count = 0;
	for (size_t i = 0; i < size; i++)
		if (data[i] == '\n')
			count++;
	if (size != 0 && data[size - 1] != '\n')
		count++;
	f->lines = calloc(count ? count : 1, sizeof(*f->lines));
	if (f->lines == NULL)
		err(2, NULL);
	f->data = data;
	f->n = count;
	for (size_t i = 0, start = 0, li = 0; i <= size && li < count; i++) {
		if (i == size || data[i] == '\n') {
			struct line *line = &f->lines[li++];

			line->s = data + start;
			line->len = i - start;
			line->nl = i < size && data[i] == '\n';
			line->hash = hash_line(line->s, line->len);
			start = i + 1;
		}
	}
	return 0;
}

static int
line_equal(const struct file *a, size_t ai, const struct file *b, size_t bi)
{
	const struct line *la = &a->lines[ai];
	const struct line *lb = &b->lines[bi];

	return la->hash == lb->hash && la->len == lb->len &&
	    memcmp(la->s, lb->s, la->len) == 0 && la->nl == lb->nl;
}

struct hent {
	uint64_t hash;
	size_t idx;
};

static int
hent_cmp(const void *va, const void *vb)
{
	const struct hent *a = va, *b = vb;

	if (a->hash < b->hash)
		return -1;
	if (a->hash > b->hash)
		return 1;
	return (a->idx > b->idx) - (a->idx < b->idx);
}

static void lcs_range(const struct file *, size_t, size_t, const struct file *,
    size_t, size_t, struct ops *);

static void
fallback_range(const struct file *a, size_t a0, size_t a1, const struct file *b,
    size_t b0, size_t b1, struct ops *ops)
{
	(void)a;
	(void)b;
	for (size_t i = a0; i < a1; i++)
		ops_add(ops, OP_DEL, i, 0);
	for (size_t i = b0; i < b1; i++)
		ops_add(ops, OP_ADD, 0, i);
}

static void
diff_range(const struct file *a, size_t a0, size_t a1, const struct file *b,
    size_t b0, size_t b1, struct ops *ops)
{
	size_t prefix = 0, suffix = 0;

	while (a0 + prefix < a1 && b0 + prefix < b1 &&
	    line_equal(a, a0 + prefix, b, b0 + prefix))
		prefix++;
	while (a1 - suffix > a0 + prefix && b1 - suffix > b0 + prefix &&
	    line_equal(a, a1 - suffix - 1, b, b1 - suffix - 1))
		suffix++;
	for (size_t i = 0; i < prefix; i++)
		ops_add(ops, OP_SAME, a0 + i, b0 + i);
	a0 += prefix;
	b0 += prefix;
	a1 -= suffix;
	b1 -= suffix;
	if (a0 < a1 || b0 < b1) {
		size_t na = a1 - a0, nb = b1 - b0;
		struct hent *ha = calloc(na ? na : 1, sizeof(*ha));
		struct hent *hb = calloc(nb ? nb : 1, sizeof(*hb));
		size_t *tails, *prev, *match_a, *match_b;
		size_t nmatch = 0, k = 0;

		if (ha == NULL || hb == NULL)
			err(2, NULL);
		for (size_t i = 0; i < na; i++) {
			ha[i].hash = a->lines[a0 + i].hash;
			ha[i].idx = a0 + i;
		}
		for (size_t i = 0; i < nb; i++) {
			hb[i].hash = b->lines[b0 + i].hash;
			hb[i].idx = b0 + i;
		}
		qsort(ha, na, sizeof(*ha), hent_cmp);
		qsort(hb, nb, sizeof(*hb), hent_cmp);
		match_a = calloc(na < nb ? na : nb, sizeof(size_t));
		match_b = calloc(na < nb ? na : nb, sizeof(size_t));
		if (match_a == NULL || match_b == NULL)
			err(2, NULL);
		/* Unique-on-both-sides anchors. */
		for (size_t ia = 0, ib = 0; ia < na && ib < nb; ) {
			size_t ea = ia + 1, eb = ib + 1;

			while (ea < na && ha[ea].hash == ha[ia].hash)
				ea++;
			while (eb < nb && hb[eb].hash == hb[ib].hash)
				eb++;
			if (ea - ia == 1 && eb - ib == 1 &&
			    line_equal(a, ha[ia].idx, b, hb[ib].idx)) {
				match_a[nmatch] = ha[ia].idx;
				match_b[nmatch] = hb[ib].idx;
				nmatch++;
			}
			if (ha[ia].hash < hb[ib].hash)
				ia = ea;
			else if (ha[ia].hash > hb[ib].hash)
				ib = eb;
			else {
				ia = ea;
				ib = eb;
			}
		}
		free(ha);
		free(hb);

		/* Longest increasing subsequence of b indices. */
		tails = calloc(nmatch ? nmatch : 1, sizeof(*tails));
		prev = calloc(nmatch ? nmatch : 1, sizeof(*prev));
		if (tails == NULL || prev == NULL)
			err(2, NULL);
		for (size_t i = 0; i < nmatch; i++) {
			size_t lo = 0, hi = k;

			while (lo < hi) {
				size_t mid = (lo + hi) / 2;

				if (match_b[tails[mid]] < match_b[i])
					lo = mid + 1;
				else
					hi = mid;
			}
			prev[i] = lo > 0 ? tails[lo - 1] : (size_t)-1;
			tails[lo] = i;
			if (lo == k)
				k++;
		}
		if (k == 0) {
			lcs_range(a, a0, a1, b, b0, b1, ops);
		} else {
			size_t *chain = calloc(k, sizeof(*chain));
			size_t at = tails[k - 1];

			if (chain == NULL)
				err(2, NULL);
			for (size_t i = k; i-- > 0; ) {
				chain[i] = at;
				at = prev[at];
			}
			size_t pa = a0, pb = b0;
			for (size_t i = 0; i < k; i++) {
				size_t ai = match_a[chain[i]];
				size_t bi = match_b[chain[i]];

				diff_range(a, pa, ai, b, pb, bi, ops);
				ops_add(ops, OP_SAME, ai, bi);
				pa = ai + 1;
				pb = bi + 1;
			}
			diff_range(a, pa, a1, b, pb, b1, ops);
			free(chain);
		}
		free(tails);
		free(prev);
		free(match_a);
		free(match_b);
	}
	for (size_t i = 0; i < suffix; i++)
		ops_add(ops, OP_SAME, a1 + i, b1 + i);
}

static void
lcs_range(const struct file *a, size_t a0, size_t a1, const struct file *b,
    size_t b0, size_t b1, struct ops *ops)
{
	size_t n = a1 - a0, m = b1 - b0;

	if (n == 0 || m == 0 || n * m > LCS_BUDGET) {
		fallback_range(a, a0, a1, b, b0, b1, ops);
		return;
	}
	uint32_t *dp = calloc((n + 1) * (m + 1), sizeof(*dp));

	if (dp == NULL)
		err(2, NULL);
	for (size_t i = 1; i <= n; i++) {
		for (size_t j = 1; j <= m; j++) {
			if (line_equal(a, a0 + i - 1, b, b0 + j - 1))
				dp[i * (m + 1) + j] =
				    dp[(i - 1) * (m + 1) + j - 1] + 1;
			else {
				uint32_t up = dp[(i - 1) * (m + 1) + j];
				uint32_t left = dp[i * (m + 1) + j - 1];

				dp[i * (m + 1) + j] = up > left ? up : left;
			}
		}
	}
	size_t i = n, j = m, out = 0;
	struct op *rev = calloc(n + m ? n + m : 1, sizeof(*rev));

	if (rev == NULL)
		err(2, NULL);
	while (i > 0 || j > 0) {
		if (i > 0 && j > 0 &&
		    line_equal(a, a0 + i - 1, b, b0 + j - 1)) {
			rev[out++] = (struct op){ OP_SAME, a0 + i - 1,
			    b0 + j - 1 };
			i--;
			j--;
		} else if (j == 0 || (i > 0 && dp[(i - 1) * (m + 1) + j] >=
		    dp[i * (m + 1) + j - 1])) {
			rev[out++] = (struct op){ OP_DEL, a0 + i - 1, 0 };
			i--;
		} else {
			rev[out++] = (struct op){ OP_ADD, 0, b0 + j - 1 };
			j--;
		}
	}
	while (out > 0) {
		out--;
		ops_add(ops, rev[out].type, rev[out].ai, rev[out].bi);
	}
	free(rev);
	free(dp);
}

static void
put_line(const char *prefix, const struct line *line)
{
	fputs(prefix, stdout);
	fwrite(line->s, 1, line->len, stdout);
	if (line->nl)
		putchar('\n');
	else
		fputs("\n\\ No newline at end of file\n", stdout);
}

static void
range_str(char *buf, size_t buflen, size_t first, size_t count)
{
	if (count == 0)
		snprintf(buf, buflen, "0,0");
	else if (count == 1)
		snprintf(buf, buflen, "%zu", first);
	else
		snprintf(buf, buflen, "%zu,%zu", first, first + count - 1);
}

static void
print_normal(const struct file *a, const struct file *b, const struct ops *ops)
{
	size_t i = 0;

	while (i < ops->n) {
		size_t a_start, b_start, adel = 0, badd = 0, j = i;

		if (ops->v[i].type == OP_SAME) {
			i++;
			continue;
		}
		/* Determine the 1-based first line of each side at i. */
		a_start = 1;
		b_start = 1;
		for (size_t k = 0; k < i; k++) {
			if (ops->v[k].type != OP_ADD)
				a_start++;
			if (ops->v[k].type != OP_DEL)
				b_start++;
		}
		while (j < ops->n && ops->v[j].type != OP_SAME) {
			if (ops->v[j].type == OP_DEL)
				adel++;
			else
				badd++;
			j++;
		}
		char ar[64], br[64];

		range_str(ar, sizeof(ar), a_start, adel);
		range_str(br, sizeof(br), b_start, badd);
		if (adel && badd)
			printf("%sc%s\n", ar, br);
		else if (adel)
			printf("%sd%zu\n", ar, b_start - 1);
		else
			printf("%zua%s\n", a_start - 1, br);
		for (size_t k = i; k < j; k++)
			if (ops->v[k].type == OP_DEL)
				put_line("< ", &a->lines[ops->v[k].ai]);
		if (adel && badd)
			fputs("---\n", stdout);
		for (size_t k = i; k < j; k++)
			if (ops->v[k].type == OP_ADD)
				put_line("> ", &b->lines[ops->v[k].bi]);
		i = j;
	}
}

static void
print_unified(const struct file *a, const struct file *b, const struct ops *ops)
{
	size_t i = 0;
	size_t aline[2] = { 1, 1 };

	/* Precompute line numbers at each op index. */
	size_t *anum = calloc(ops->n + 1, sizeof(*anum));
	size_t *bnum = calloc(ops->n + 1, sizeof(*bnum));

	if (anum == NULL || bnum == NULL)
		err(2, NULL);
	for (size_t k = 0; k < ops->n; k++) {
		anum[k] = aline[0];
		bnum[k] = aline[1];
		if (ops->v[k].type != OP_ADD)
			aline[0]++;
		if (ops->v[k].type != OP_DEL)
			aline[1]++;
	}
	anum[ops->n] = aline[0];
	bnum[ops->n] = aline[1];

	while (i < ops->n) {
		size_t first, last, start, end, actx = 0, bctx = 0;

		if (ops->v[i].type == OP_SAME) {
			i++;
			continue;
		}
		first = last = i;
		size_t j = i, gap = 0;

		while (j < ops->n) {
			if (ops->v[j].type == OP_SAME) {
				gap++;
				j++;
				if (gap > 2 * CONTEXT)
					break;
			} else {
				gap = 0;
				last = j;
				j++;
			}
		}
		start = first > CONTEXT ? first - CONTEXT : 0;
		end = last + CONTEXT + 1;
		if (end > ops->n)
			end = ops->n;
		size_t acount = 0, bcount = 0;

		for (size_t k = start; k < end; k++) {
			if (ops->v[k].type != OP_ADD)
				acount++;
			if (ops->v[k].type != OP_DEL)
				bcount++;
		}
		(void)actx;
		(void)bctx;
		printf("@@ -%zu,%zu +%zu,%zu @@\n",
		    acount ? anum[start] : anum[start] - 1, acount,
		    bcount ? bnum[start] : bnum[start] - 1, bcount);
		for (size_t k = start; k < end; k++) {
			switch (ops->v[k].type) {
			case OP_SAME:
				put_line(" ", &a->lines[ops->v[k].ai]);
				break;
			case OP_DEL:
				put_line("-", &a->lines[ops->v[k].ai]);
				break;
			case OP_ADD:
				put_line("+", &b->lines[ops->v[k].bi]);
				break;
			}
		}
		i = end;
	}
	free(anum);
	free(bnum);
}

/* Within a change block, emit deletions before additions.  The LCS
 * backtracker can interleave them when both directions tie, and patch(1)
 * expects the conventional order. */
static void
normalize_ops(struct ops *ops)
{
	size_t i = 0;

	while (i < ops->n) {
		size_t j = i, del = 0;

		while (j < ops->n && ops->v[j].type != OP_SAME) {
			if (ops->v[j].type == OP_DEL)
				del++;
			j++;
		}
		if (del != 0 && del != j - i) {
			struct op *tmp = malloc((j - i) * sizeof(*tmp));
			size_t d = 0, a = del;

			if (tmp == NULL)
				err(2, NULL);
			for (size_t k = i; k < j; k++) {
				if (ops->v[k].type == OP_DEL)
					tmp[d++] = ops->v[k];
				else
					tmp[a++] = ops->v[k];
			}
			memcpy(&ops->v[i], tmp, (j - i) * sizeof(*tmp));
			free(tmp);
		}
		i = j > i ? j : i + 1;
	}
}

static void
diff_files(const char *pa, const char *pb)
{
	struct file a, b;
	struct ops ops = { 0 };

	if (read_file(pa, &a) != 0) {
		warn("%s", pa);
		status = 2;
		return;
	}
	if (read_file(pb, &b) != 0) {
		warn("%s", pb);
		status = 2;
		free(a.data);
		free(a.lines);
		return;
	}
	int same = a.n == b.n;

	for (size_t i = 0; same && i < a.n; i++)
		same = line_equal(&a, i, &b, i);
	if (same) {
		free(a.data);
		free(a.lines);
		free(b.data);
		free(b.lines);
		return;
	}
	status = 1;
	if (qflag) {
		printf("Files %s and %s differ\n", pa, pb);
		free(a.data);
		free(a.lines);
		free(b.data);
		free(b.lines);
		return;
	}
	diff_range(&a, 0, a.n, &b, 0, b.n, &ops);
	normalize_ops(&ops);
	if (uflag) {
		printf("--- %s\n+++ %s\n", pa, pb);
		print_unified(&a, &b, &ops);
	} else
		print_normal(&a, &b, &ops);
	free(ops.v);
	free(a.data);
	free(a.lines);
	free(b.data);
	free(b.lines);
}

struct names {
	char **v;
	size_t n;
};

static int
name_cmp(const void *va, const void *vb)
{
	return strcmp(*(char *const *)va, *(char *const *)vb);
}

static void
add_name(struct names *names, const char *name)
{
	char **v = realloc(names->v, (names->n + 1) * sizeof(*v));

	if (v == NULL)
		err(2, NULL);
	names->v = v;
	names->v[names->n++] = strdup(name);
}

static int
list_dir(const char *path, struct names *names)
{
	DIR *dir = opendir(path);
	struct dirent *dp;

	if (dir == NULL)
		return -1;
	while ((dp = readdir(dir)) != NULL) {
		if (strcmp(dp->d_name, ".") == 0 ||
		    strcmp(dp->d_name, "..") == 0)
			continue;
		add_name(names, dp->d_name);
	}
	closedir(dir);
	return 0;
}

static int
is_dir(const char *path)
{
	struct stat st;

	return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

static void
diff_paths(const char *pa, const char *pb)
{
	if (is_dir(pa) && is_dir(pb)) {
		if (!rflag) {
			printf("Common subdirectories: %s and %s\n", pa, pb);
			status = 1;
			return;
		}
		struct names names = { 0 };
		char *suba, *subb;

		if (list_dir(pa, &names) != 0) {
			warn("%s", pa);
			status = 2;
			return;
		}
		struct names nb = { 0 };
		if (list_dir(pb, &nb) != 0) {
			warn("%s", pb);
			status = 2;
		}
		for (size_t i = 0; i < nb.n; i++) {
			int found = 0;

			for (size_t j = 0; j < names.n; j++)
				if (strcmp(names.v[j], nb.v[i]) == 0)
					found = 1;
			if (!found)
				add_name(&names, nb.v[i]);
		}
		qsort(names.v, names.n, sizeof(*names.v), name_cmp);
		for (size_t i = 0; i < names.n; i++) {
			if (asprintf(&suba, "%s/%s", pa, names.v[i]) == -1 ||
			    asprintf(&subb, "%s/%s", pb, names.v[i]) == -1)
				err(2, NULL);
			int ea = access(suba, F_OK) == 0;
			int eb = access(subb, F_OK) == 0;

			if (ea && eb)
				diff_paths(suba, subb);
			else if (nflag) {
				if (!ea)
					diff_files("/dev/null", subb);
				else
					diff_files(suba, "/dev/null");
			} else {
				printf("Only in %s: %s\n", ea ? pa : pb,
				    names.v[i]);
				status = 1;
			}
			free(suba);
			free(subb);
		}
		for (size_t i = 0; i < names.n; i++)
			free(names.v[i]);
		free(names.v);
		for (size_t i = 0; i < nb.n; i++)
			free(nb.v[i]);
		free(nb.v);
	} else if (is_dir(pa) != is_dir(pb)) {
		warnx("%s: directory/file mismatch", is_dir(pa) ? pa : pb);
		status = 2;
	} else
		diff_files(pa, pb);
}

static void
usage(void)
{
	fprintf(stderr, "usage: diff [-qruN] file1 file2\n");
	exit(2);
}

int
main(int argc, char *argv[])
{
	int ch;

	while ((ch = getopt(argc, argv, "qruN")) != -1) {
		switch (ch) {
		case 'q':
			qflag = 1;
			break;
		case 'r':
			rflag = 1;
			break;
		case 'u':
			uflag = 1;
			break;
		case 'N':
			nflag = 1;
			break;
		default:
			usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc != 2)
		usage();
	diff_paths(argv[0], argv[1]);
	return status;
}
