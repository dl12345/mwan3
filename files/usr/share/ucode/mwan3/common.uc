'use strict';

// common.uc: the shared mwan3 ucode library, the ucode analogue of common.sh.
// Each shared ucode routine is defined here so it lives, and is tested, in one
// place.

import { openlog, syslog, LOG_PID, LOG_DAEMON } from 'log';

// ---- Logging ---------------------------------------------------------------
//
// All mwan3 ucode logs through these functions so the sink, tag format and
// verbose gate live in one place. Output goes to syslog, the same destination
// logger(1) reaches, so it appears in logread regardless of how procd handles
// the process stderr.

let verbose = false;

// Map the level names mwan3 uses (the shell's warn/error vocabulary and the
// canonical syslog names) onto the exact tokens parse_priority() accepts. It
// rejects "warn" and "error", so an unmapped name would be dropped; an unknown
// level falls back to notice so a mislabelled message still logs.

const PRIO = {
	emerg: "emerg", alert: "alert", crit: "crit",
	err: "err", error: "err",
	warn: "warning", warning: "warning",
	notice: "notice", info: "info", debug: "debug",
};

// Open the syslog connection with the given identity. LOG_PID appends the pid
// so the tag reads ident[pid], matching the shell's "${SCRIPTNAME}[$$]"
// convention. Facility daemon suits these long-running and service-invoked
// components.

function log_open(ident) {
	openlog(ident, LOG_PID, LOG_DAEMON);
}

// Set the verbose gate. The caller reads mwan3.globals.verbose_logging and
// pushes the parsed bool here; debug is suppressed unless verbose, exactly as
// common.sh:LOG() gates the debug facility behind MWAN3_VERBOSE_LOGGING.

function log_verbose(enable) {
	verbose = enable;
}

// Emit one message. debug is dropped unless verbose; every other level always
// logs. Message content is passed as a %s argument so it is never treated as a
// format string.

function log_msg(level, msg) {
	if (level == "debug" && !verbose)
		return;
	syslog(PRIO[level] ?? "notice", "%s", msg);
}

// ---- Config helpers --------------------------------------------------------

// Parse a UCI bool the way the shell's config_get_bool does: 1/on/true/yes/
// enabled are true, everything else is false. Kept here so every ucode
// consumer interprets a UCI bool identically to the shell. It reads no config
// itself, so it does not couple the module to uci.

function ucibool(val) {
	switch (val) {
	case 'yes':
	case 'on':
	case 'true':
	case 'enabled':
		return true;
	default:
		return !!int(val);
	}
}

// ---- Exports ---------------------------------------------------------------

// The module's public interface. Declared as an export list rather than inline
// on each function, which this ucode build does not accept.

export { log_open, log_verbose, log_msg, ucibool };
