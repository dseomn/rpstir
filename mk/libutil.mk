noinst_LIBRARIES += lib/util/libutil.a

LDADD_LIBUTIL = \
	lib/util/libutil.a

lib_util_libutil_a_SOURCES = \
	lib/util/bag.c \
	lib/util/bag.h \
	lib/util/cryptlib_compat.c \
	lib/util/cryptlib_compat.h \
	lib/util/file.c \
	lib/util/file.h \
	lib/util/hashutils.c \
	lib/util/hashutils.h \
	lib/util/inet.c \
	lib/util/inet.h \
	lib/util/logging.c \
	lib/util/logging.h \
	lib/util/macros.h \
	lib/util/path_compat.c \
	lib/util/path_compat.h \
	lib/util/queue.c \
	lib/util/queue.h \
	lib/util/semaphore_compat.c \
	lib/util/semaphore_compat.h \
	lib/util/stringutils.c \
	lib/util/stringutils.h


check_LIBRARIES += lib/util/libutildebug.a

lib_util_libutildebug_a_SOURCES = \
	$(lib_util_libutil_a_SOURCES)

lib_util_libutildebug_a_CPPFLAGS = \
	$(AM_CPPFLAGS) \
	-DDEBUG


check_PROGRAMS += lib/util/tests/bag-test

lib_util_tests_bag_test_LDADD = \
	lib/util/libutildebug.a

TESTS += lib/util/tests/bag-test


check_PROGRAMS += lib/util/tests/queue-test

lib_util_tests_queue_test_LDADD = \
	lib/util/libutildebug.a

TESTS += lib/util/tests/queue-test


check_PROGRAMS += lib/util/tests/stringutils-test

lib_util_tests_stringutils_test_LDADD = \
	lib/util/libutildebug.a

TESTS += lib/util/tests/stringutils-test


dist_pkgdata_DATA += lib/util/shell_utils


dist_pkgdata_DATA += lib/util/trap_errors
