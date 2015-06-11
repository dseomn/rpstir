#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include "util/stringutils.h"
#include "test/unittest.h"


/**
 * @brief store a sequence of @len characters in both @p dst and @p
 * ref
 */
static void
init_dst(
    char *dst,
    char *ref,
    size_t len)
{
    memset(dst, 0, len);
    memset(ref, 0, len);
}

static bool test_scrub_for_print__length_if_truncated(
    void)
{
    size_t const DST_LEN = 5;
    char src[] = "0123456789";
    char dst[DST_LEN + 50];
    char ref[sizeof(dst) - DST_LEN];
    init_dst(dst + DST_LEN, ref, sizeof(ref));

    scrub_for_print(dst, src, DST_LEN, NULL, "");
    TEST(size_t, "%zu", strlen(dst), ==, DST_LEN - 1);
    TEST_BOOL(memcmp(dst + DST_LEN, ref, sizeof(ref)), false);

    return true;
}

static bool test_scrub_for_print__length_if_expansion_truncated(
    size_t const dst_sz)
{
    char src[50];
    char dst[dst_sz + 50];
    char ref[sizeof(dst) - dst_sz];
    init_dst(dst + dst_sz, ref, sizeof(ref));

    sprintf(src, "%c%c%s", 'a', '\n', "12345");
    scrub_for_print(dst, src, dst_sz, NULL, "");
    TEST(size_t, "%zu", strlen(dst), ==, dst_sz - 1);
    TEST_BOOL(memcmp(dst + dst_sz, ref, sizeof(ref)), false);

    return true;
}

static bool test_scrub_for_print__null_input(
    void)
{
    size_t const DST_LEN = 5;
    char src[] = "";
    char dst[DST_LEN];

    scrub_for_print(dst, src, DST_LEN, NULL, "");
    TEST(size_t, "%zu", strlen(dst), ==, 0);

    return true;
}

static bool test_scrub_for_print__copy_all(
    void)
{
    size_t const DST_LEN = 10;
    char src[] = "abcdefg";
    char dst[DST_LEN];

    scrub_for_print(dst, src, DST_LEN, NULL, "");
    TEST(size_t, "%zu", strlen(dst), ==, strlen(src));

    return true;
}

static bool test_scrub_for_print__backslash(
    void)
{
    size_t const DST_LEN = 50;
    char src[] = "ab\\cde\\";
    char dst[DST_LEN];

    scrub_for_print(dst, src, DST_LEN, NULL, "");
    TEST(size_t, "%zu", strlen(dst), ==, strlen(src) + 2);

    return true;
}

static bool test_scrub_for_print__escape_chars(
    void)
{
    size_t const DST_LEN = 50;
    char src[] = "abcde";
    char dst[DST_LEN];

    scrub_for_print(dst, src, DST_LEN, NULL, "bd");
    TEST_BOOL(strcmp(dst, "a\\bc\\de"), false);

    return true;
}

static bool test_scrub_for_print__sz(
    void)
{
    size_t const DST_LEN = 50;
    char src[50];
    char dst[DST_LEN];
    size_t sz;

    sprintf(src, "%c%c%s", 'a', '\n', "1234\\5b\"\\cde");
    scrub_for_print(dst, src, DST_LEN, &sz, "");
    TEST(size_t, "%zu", strlen(dst), ==, sz);

    return true;
}


int main(
    void)
{
    if (!test_scrub_for_print__length_if_truncated())
        return EXIT_FAILURE;

    if (!test_scrub_for_print__length_if_expansion_truncated(1))
        return EXIT_FAILURE;
    if (!test_scrub_for_print__length_if_expansion_truncated(2))
        return EXIT_FAILURE;
    if (!test_scrub_for_print__length_if_expansion_truncated(3))
        return EXIT_FAILURE;
    if (!test_scrub_for_print__length_if_expansion_truncated(4))
        return EXIT_FAILURE;
    if (!test_scrub_for_print__length_if_expansion_truncated(5))
        return EXIT_FAILURE;
    if (!test_scrub_for_print__length_if_expansion_truncated(6))
        return EXIT_FAILURE;
    if (!test_scrub_for_print__length_if_expansion_truncated(7))
        return EXIT_FAILURE;

    if (!test_scrub_for_print__null_input())
        return EXIT_FAILURE;

    if (!test_scrub_for_print__copy_all())
        return EXIT_FAILURE;

    if (!test_scrub_for_print__backslash())
        return EXIT_FAILURE;

    if (!test_scrub_for_print__escape_chars())
        return EXIT_FAILURE;

    if (!test_scrub_for_print__sz())
        return EXIT_FAILURE;

    return EXIT_SUCCESS;
}
