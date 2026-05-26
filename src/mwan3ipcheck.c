// SPDX-License-Identifier: GPL-2.0
/*
 * mwan3ipcheck - validate and classify IP addresses and CIDR notation
 *
 * Uses inet_pton() to determine whether a string is a valid IPv4 or
 * IPv6 address, optionally with a CIDR prefix length.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <arpa/inet.h>

static int classify(const char *arg)
{
	char buf[64];
	unsigned char addr[sizeof(struct in6_addr)];
	const char *pfxstr = NULL;
	int family;
	size_t len;

	len = strlen(arg);
	if (len == 0 || len >= sizeof(buf))
		return 0;

	memcpy(buf, arg, len + 1);

	char *slash = strchr(buf, '/');
	if (slash) {
		*slash = '\0';
		pfxstr = slash + 1;
		if (*pfxstr == '\0')
			return 0;
	}

	if (inet_pton(AF_INET, buf, addr) == 1)
		family = AF_INET;
	else if (inet_pton(AF_INET6, buf, addr) == 1)
		family = AF_INET6;
	else
		return 0;

	if (pfxstr) {
		char *end;
		long pfx;
		int max_pfx = (family == AF_INET) ? 32 : 128;

		if (pfxstr[0] == '0' && pfxstr[1] != '\0')
			return 0;

		pfx = strtol(pfxstr, &end, 10);
		if (*end != '\0' || end == pfxstr)
			return 0;
		if (pfx < 0 || pfx > max_pfx)
			return 0;
	}

	return family;
}

static int classify_list(const char *arg)
{
	char buf[512];
	char *token = NULL, *saveptr = NULL;
	int common_family = 0;

	size_t len = strlen(arg);
	if (len == 0 || len >= sizeof(buf))
		return 0;

	memcpy(buf, arg, len + 1);

	for (token = strtok_r(buf, ",", &saveptr);
	     token;
	     token = strtok_r(NULL, ",", &saveptr)) {
		while (*token && isspace((unsigned char)*token))
			token++;
		size_t tlen = strlen(token);
		while (tlen > 0 && isspace((unsigned char)token[tlen - 1]))
			token[--tlen] = '\0';
		if (tlen == 0)
			continue;

		int family = classify(token);
		if (family == 0)
			return 0;

		if (common_family == 0)
			common_family = family;
		else if (family != common_family)
			return -1;
	}

	if (common_family == 0)
		return 0;

	return common_family;
}

int main(int argc, char *argv[])
{
	int result;

	if (argc != 2)
		result = 0;
	else
		result = classify_list(argv[1]);

	if (result == AF_INET)
		puts("ipv4");
	else if (result == AF_INET6)
		puts("ipv6");
	else if (result == -1) {
		puts("mixed");
		return EXIT_FAILURE;
	} else {
		puts("invalid");
		return EXIT_FAILURE;
	}

	return EXIT_SUCCESS;
}
