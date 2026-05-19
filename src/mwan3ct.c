// SPDX-License-Identifier: GPL-2.0
/*
 * mwan3ct - targeted conntrack flush helper for mwan3
 *
 * Uses libnetfilter_conntrack's NFCT_Q_FLUSH_FILTER to perform
 * kernel-side filtered conntrack entry deletion by mark and/or
 * status bits.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <errno.h>
#include <libnetfilter_conntrack/libnetfilter_conntrack.h>

/*
 * id2mask - expand a sequential bit index into a sparse mask
 *
 * Maps each set bit in 'id' (counting from bit 0) to the
 * corresponding set bit position in 'mask', producing a value
 * that occupies only the bit positions defined by 'mask'.
 */

static uint32_t id2mask(uint32_t id, uint32_t mask)
{
	uint32_t result = 0;
	uint32_t bit = 1;

	for (uint32_t m = mask; m; m &= m - 1) {
		if (id & bit)
			result |= m & (-m);
		bit <<= 1;
	}
	return result;
}

/*
 * flush_filtered - flush conntrack entries matching mark and/or status
 *
 * Builds a kernel-side filter from the supplied mark and status
 * value/mask pairs, then issues a single NFCT_Q_FLUSH_FILTER query.
 * ENOENT (no matching entries) is treated as success.
 */

static int flush_filtered(struct nfct_handle *h,
			  uint32_t mark_val, uint32_t mark_mask,
			  uint32_t status_val, uint32_t status_mask,
			  int have_mark, int have_status)
{
	struct nfct_filter_dump *filter = NULL;
	int ret;

	filter = nfct_filter_dump_create();
	if (!filter) {
		fprintf(stderr, "mwan3ct: nfct_filter_dump_create: %s\n",
			strerror(errno));
		return -1;
	}

	if (have_mark) {
		struct nfct_filter_dump_mark mark = {
			.val = mark_val,
			.mask = mark_mask,
		};
		nfct_filter_dump_set_attr(filter, NFCT_FILTER_DUMP_MARK,
					  &mark);
	}
	if (have_status) {
		struct nfct_filter_dump_mark status = {
			.val = status_val,
			.mask = status_mask,
		};
		nfct_filter_dump_set_attr(filter, NFCT_FILTER_DUMP_STATUS,
					  &status);
	}

	ret = nfct_query(h, NFCT_Q_FLUSH_FILTER, filter);
	nfct_filter_dump_destroy(filter);

	if (ret == -1 && errno != ENOENT)
		return -1;
	return 0;
}

/*
 * flush_any_marked - flush conntrack entries for all mark values in a mask
 *
 * Iterates over every non-zero combination of bits within 'mask'
 * and issues a filtered flush for each. Used when the caller wants
 * to remove all mwan3-marked entries regardless of which interface
 * they belong to.
 */

static int flush_any_marked(struct nfct_handle *h, uint32_t mask,
			    uint32_t status_val, uint32_t status_mask,
			    int have_status)
{
	int bitcount = __builtin_popcount(mask);
	uint32_t max_id;

	if (bitcount > 16) {
		errno = EINVAL;
		return -1;
	}
	max_id = (1U << bitcount) - 1;

	for (uint32_t id = 1; id <= max_id; id++) {
		uint32_t mark_val = id2mask(id, mask);
		int ret = flush_filtered(h, mark_val, mask, status_val,
					 status_mask, 1, have_status);
		if (ret < 0)
			return ret;
	}
	return 0;
}

/*
 * parse_u32 - parse a string as a uint32_t with full validation
 *
 * Rejects negative values, overflow, and empty input. On success
 * *endp points past the last consumed character, allowing the caller
 * to check for trailing garbage. Returns 0 on success, -1 on failure.
 */

static int parse_u32(const char *s, char **endp, uint32_t *out)
{
	unsigned long tmp;

	if (*s == '-')
		return -1;

	errno = 0;
	tmp = strtoul(s, endp, 0);
	if (*endp == s || errno)
		return -1;
	if ((uint32_t)tmp != tmp)
		return -1;
	*out = (uint32_t)tmp;
	return 0;
}

/*
 * parse_val_mask - parse a "value/mask" string into two uint32 values
 *
 * Accepts "val/mask" or just "val", in which case the mask defaults
 * to the value itself. Returns 0 on success, -1 on parse failure.
 */

static int parse_val_mask(const char *arg, uint32_t *val, uint32_t *mask)
{
	char *end = NULL;

	if (parse_u32(arg, &end, val))
		return -1;

	if (*end == '/') {
		if (parse_u32(end + 1, &end, mask))
			return -1;
		if (*end != '\0')
			return -1;
	} else if (*end == '\0') {
		*mask = *val;
	} else {
		return -1;
	}
	return 0;
}

/*
 * usage - print command usage to stderr
 */

static void usage(void)
{
	fprintf(stderr,
		"Usage: mwan3ct flush [--mark <val>/<mask>] "
		"[--mark-any <mask>] [--status <val>/<mask>]\n");
}

/*
 * main - parse arguments and dispatch the requested flush operation
 *
 * Supports three mutually exclusive filter modes: --mark (exact
 * value/mask match), --mark-any (iterate all non-zero mark values
 * within a mask), and --status (conntrack status bit filter).
 * --mark and --status, or --mark-any and --status, may be combined.
 */

int main(int argc, char *argv[])
{
	uint32_t mark_val = 0, mark_mask = 0;
	uint32_t status_val = 0, status_mask = 0;
	int have_mark = 0, have_mark_any = 0, have_status = 0;
	struct nfct_handle *h = NULL;
	int ret;

	if (argc >= 2 && (strcmp(argv[1], "--help") == 0 ||
			  strcmp(argv[1], "-h") == 0)) {
		usage();
		return EXIT_SUCCESS;
	}

	if (argc < 2 || strcmp(argv[1], "flush") != 0) {
		usage();
		return EXIT_FAILURE;
	}

	for (int i = 2; i < argc; i++) {
		if (strcmp(argv[i], "--mark") == 0 && i + 1 < argc) {
			if (have_mark) {
				fprintf(stderr,
					"mwan3ct: duplicate --mark\n");
				return EXIT_FAILURE;
			}
			if (parse_val_mask(argv[++i], &mark_val, &mark_mask)) {
				fprintf(stderr, "mwan3ct: bad --mark value\n");
				return EXIT_FAILURE;
			}
			have_mark = 1;
		} else if (strcmp(argv[i], "--mark-any") == 0 && i + 1 < argc) {
			char *end;

			if (have_mark_any) {
				fprintf(stderr,
					"mwan3ct: duplicate --mark-any\n");
				return EXIT_FAILURE;
			}
			if (parse_u32(argv[++i], &end, &mark_mask) ||
			    *end != '\0' || !mark_mask) {
				fprintf(stderr,
					"mwan3ct: bad --mark-any mask\n");
				return EXIT_FAILURE;
			}
			have_mark_any = 1;
		} else if (strcmp(argv[i], "--status") == 0 && i + 1 < argc) {
			if (have_status) {
				fprintf(stderr,
					"mwan3ct: duplicate --status\n");
				return EXIT_FAILURE;
			}
			if (parse_val_mask(argv[++i],
					   &status_val, &status_mask)) {
				fprintf(stderr,
					"mwan3ct: bad --status value\n");
				return EXIT_FAILURE;
			}
			have_status = 1;
		} else {
			usage();
			return EXIT_FAILURE;
		}
	}

	if (have_mark && have_mark_any) {
		fprintf(stderr,
			"mwan3ct: --mark and --mark-any "
			"are mutually exclusive\n");
		return EXIT_FAILURE;
	}

	if (!have_mark && !have_mark_any && !have_status) {
		fprintf(stderr, "mwan3ct: at least one filter required\n");
		usage();
		return EXIT_FAILURE;
	}

	if (have_mark && !mark_mask) {
		fprintf(stderr, "mwan3ct: --mark mask must be non-zero\n");
		return EXIT_FAILURE;
	}
	if (have_mark && (mark_val & ~mark_mask)) {
		fprintf(stderr,
			"mwan3ct: --mark value has bits outside mask\n");
		return EXIT_FAILURE;
	}
	if (have_status && !status_mask) {
		fprintf(stderr,
			"mwan3ct: --status mask must be non-zero\n");
		return EXIT_FAILURE;
	}
	if (have_status && (status_val & ~status_mask)) {
		fprintf(stderr,
			"mwan3ct: --status value has bits outside mask\n");
		return EXIT_FAILURE;
	}

	h = nfct_open(CONNTRACK, 0);
	if (!h) {
		fprintf(stderr, "mwan3ct: nfct_open: %s\n", strerror(errno));
		return EXIT_FAILURE;
	}

	if (have_mark_any)
		ret = flush_any_marked(h, mark_mask, status_val,
				       status_mask, have_status);
	else
		ret = flush_filtered(h, mark_val, mark_mask,
				     status_val, status_mask,
				     have_mark, have_status);

	nfct_close(h);

	if (ret < 0) {
		fprintf(stderr, "mwan3ct: flush failed: %s\n", strerror(errno));
		return EXIT_FAILURE;
	}

	return EXIT_SUCCESS;
}
