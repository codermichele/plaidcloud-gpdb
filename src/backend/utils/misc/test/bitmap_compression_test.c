#include <stdarg.h>
#include <stddef.h>
#include <setjmp.h>
#include "cmockery.h"

#include "postgres.h"
#include "utils/memutils.h"

#include "../bitmap_compression.c"

static void 
test__BitmapCompression__ZeroBitmap(void **state) 
{
	uint32 bitmap[4];
	memset(bitmap, 0, sizeof(uint32) * 4);

	unsigned char output[20];
	memset(output, 0, 20);

	int onDiskBlockCount = 0;
	int bmsWordCount = 0;
	/*
	 * For 64bit bms, bmsWordCount is half of onDiskBlockCount;
	 * For 32bit bms, bmsWordCount is equal to onDiskBlockCount.
	 */
	int expectedBmwWordCount = BITS_PER_BITMAPWORD == 64 ? 2 : 4;
	Bitmapset *bms;

	/* fake a bitmapset with the bitmap data */
	bms = (Bitmapset *) palloc(BITMAPSET_SIZE(expectedBmwWordCount));
	bms->nwords = expectedBmwWordCount;
	memcpy(bms->words, bitmap, sizeof(uint32) * 4);

	BitmapCompress_CalculateBlockCounts(bms,
										&onDiskBlockCount,
										&bmsWordCount);
	assert_int_equal(4, onDiskBlockCount);
	assert_int_equal(expectedBmwWordCount, bmsWordCount);

	int r = Bitmap_Compress(
		BITMAP_COMPRESSION_TYPE_DEFAULT, 
		bitmap, onDiskBlockCount,
		output, 20);
	assert_true(r < sizeof(uint32) * 4 && r >= 0);
	uint32 bitmap2[4];
	memset(bitmap2, 1, sizeof(uint32) * 4);

	BitmapDecompressState decomp_state;
	BitmapDecompress_Init(&decomp_state, output, r);
	assert_false(BitmapDecompress_HasError(&decomp_state));
	assert_int_equal(BITMAP_COMPRESSION_TYPE_DEFAULT, 
			BitmapDecompress_GetCompressionType(&decomp_state));
	assert_int_equal(4, BitmapDecompress_GetBlockCount(&decomp_state));

	BitmapDecompress_CalculateBlockCounts(&decomp_state,
										  &onDiskBlockCount,
										  &bmsWordCount);
	assert_int_equal(4, onDiskBlockCount);
	assert_int_equal(expectedBmwWordCount, bmsWordCount);

	BitmapDecompress_Decompress(&decomp_state,
		bitmap2, onDiskBlockCount);
	assert_memory_equal(bitmap, bitmap2, sizeof(uint32) * 4);
}

static void
test__BitmapCompression__Raw(void **state)
{
	int blockCount = 4;
	uint32 bitmap[4];
	memset(bitmap, 0, sizeof(uint32) * blockCount);
	bitmap[0] = 0xFFFFFFFFU; /* one case */
	bitmap[1] = 0xFF00FF00U; /* Raw */
	bitmap[2] = 0xFF00FF00U; /*One repetition, use RLE */
	bitmap[3] = 0xFFFFFFFFU; /* one case */

	unsigned char output[sizeof(uint32) * 5];
	memset(output, 0, sizeof(uint32) * 5);

	int onDiskBlockCount = 0;
	int bmsWordCount = 0;
	/*
	 * For 64bit bms, bmsWordCount is half of onDiskBlockCount;
	 * For 32bit bms, bmsWordCount is equal to onDiskBlockCount.
	 */
	int expectedBmwWordCount = BITS_PER_BITMAPWORD == 64 ? 2 : 4;
	Bitmapset *bms;

	/* fake a bitmapset with the bitmap data */
	bms = (Bitmapset *) palloc(BITMAPSET_SIZE(expectedBmwWordCount));
	bms->nwords = expectedBmwWordCount;
	memcpy(bms->words, bitmap, sizeof(uint32) * 4);

	BitmapCompress_CalculateBlockCounts(bms,
										&onDiskBlockCount,
										&bmsWordCount);
	assert_int_equal(4, onDiskBlockCount);
	assert_int_equal(expectedBmwWordCount, bmsWordCount);

	int r = Bitmap_Compress(
		BITMAP_COMPRESSION_TYPE_DEFAULT, 
		bitmap, onDiskBlockCount,
		output, sizeof(uint32) * 5);
	assert_true(r < sizeof(uint32) * blockCount && r >= 0);
	uint32 bitmap2[4];
	memset(bitmap2, 1, sizeof(uint32) * blockCount);

	BitmapDecompressState decomp_state;
	BitmapDecompress_Init(&decomp_state, output, r);
	assert_false(BitmapDecompress_HasError(&decomp_state));
	assert_int_equal(BITMAP_COMPRESSION_TYPE_DEFAULT, 
			BitmapDecompress_GetCompressionType(&decomp_state));
	assert_int_equal(blockCount, BitmapDecompress_GetBlockCount(&decomp_state));

	BitmapDecompress_CalculateBlockCounts(&decomp_state,
										  &onDiskBlockCount,
										  &bmsWordCount);
	assert_int_equal(blockCount, onDiskBlockCount);
	assert_int_equal(expectedBmwWordCount, bmsWordCount);

	BitmapDecompress_Decompress(&decomp_state,
		bitmap2, onDiskBlockCount);
	assert_memory_equal(bitmap, bitmap2, sizeof(uint32) * blockCount);
}

static void
test__BitmapCompression__ExplicitNoCompression(void **state)
{
	int blockCount = 4;
	uint32 bitmap[4];
	memset(bitmap, 0, sizeof(uint32) * blockCount);
	bitmap[0] = 0xFFFFFFFFU; /* one case */
	bitmap[1] = 0xFF00FF00U; /* Raw */
	bitmap[2] = 0xFF00FF00U; /*One repetition, use RLE */
	bitmap[3] = 0xFFFFFFFFU; /* one case */

	unsigned char output[sizeof(uint32) * 5];
	memset(output, 0, sizeof(uint32) * 5);

	int onDiskBlockCount = 0;
	int bmsWordCount = 0;
	/*
	 * For 64bit bms, bmsWordCount is half of onDiskBlockCount;
	 * For 32bit bms, bmsWordCount is equal to onDiskBlockCount.
	 */
	int expectedBmwWordCount = BITS_PER_BITMAPWORD == 64 ? 2 : 4;
	Bitmapset *bms;

	/* fake a bitmapset with the bitmap data */
	bms = (Bitmapset *) palloc(BITMAPSET_SIZE(expectedBmwWordCount));
	bms->nwords = expectedBmwWordCount;
	memcpy(bms->words, bitmap, sizeof(uint32) * 4);

	BitmapCompress_CalculateBlockCounts(bms,
										&onDiskBlockCount,
										&bmsWordCount);
	assert_int_equal(4, onDiskBlockCount);
	assert_int_equal(expectedBmwWordCount, bmsWordCount);

	int r = Bitmap_Compress(
			BITMAP_COMPRESSION_TYPE_NO, 
		bitmap, onDiskBlockCount,
		output, sizeof(uint32) * 5);
	assert_int_equal(r, (sizeof(uint32) * 4) + 2);

	uint32 bitmap2[4];
	memset(bitmap2, 1, sizeof(uint32) * blockCount);

	BitmapDecompressState decomp_state;
	BitmapDecompress_Init(&decomp_state, output, r);
	assert_false(BitmapDecompress_HasError(&decomp_state));
	assert_int_equal(BITMAP_COMPRESSION_TYPE_NO, 
			BitmapDecompress_GetCompressionType(&decomp_state));
	assert_int_equal(blockCount, BitmapDecompress_GetBlockCount(&decomp_state));

	BitmapDecompress_CalculateBlockCounts(&decomp_state,
										  &onDiskBlockCount,
										  &bmsWordCount);
	assert_int_equal(blockCount, onDiskBlockCount);
	assert_int_equal(expectedBmwWordCount, bmsWordCount);

	BitmapDecompress_Decompress(&decomp_state,
		bitmap2, onDiskBlockCount);
	assert_memory_equal(bitmap, bitmap2, sizeof(uint32) * blockCount);
}

static void
test__BitmapCompression__ExplicitNoCompressionNoBlocks(void **state)
{
	int blockCount = 0;
	uint32 bitmap[1];
	memset(bitmap, 0, sizeof(uint32) * 1);

	unsigned char output[sizeof(uint32) * 5];
	memset(output, 0, sizeof(uint32) * 5);

	int onDiskBlockCount = 0;
	int bmsWordCount = 0;

	BitmapCompress_CalculateBlockCounts(NULL,
										&onDiskBlockCount,
										&bmsWordCount);
	assert_int_equal(0, onDiskBlockCount);
	assert_int_equal(0, bmsWordCount);

	int r = Bitmap_Compress(
			BITMAP_COMPRESSION_TYPE_NO, 
		bitmap, onDiskBlockCount,
		output, sizeof(uint32) * 5);
	assert_int_equal(r, 2);

	uint32 bitmap2[1];
	memset(bitmap2, 1, sizeof(uint32) * 1);

	BitmapDecompressState decomp_state;
	BitmapDecompress_Init(&decomp_state, output, r);
	assert_false(BitmapDecompress_HasError(&decomp_state));
	assert_int_equal(BITMAP_COMPRESSION_TYPE_NO, 
			BitmapDecompress_GetCompressionType(&decomp_state));
	assert_int_equal(blockCount, BitmapDecompress_GetBlockCount(&decomp_state));

	BitmapDecompress_CalculateBlockCounts(&decomp_state,
										  &onDiskBlockCount,
										  &bmsWordCount);
	assert_int_equal(blockCount, onDiskBlockCount);
	assert_int_equal(0, bmsWordCount);

	BitmapDecompress_Decompress(&decomp_state,
		bitmap2, onDiskBlockCount);
}

static void
test__BitmapCompression__ImplicitNoCompression(void **state)
{
	int blockCount = 4;
	uint32 bitmap[4];
	memset(bitmap, 0, sizeof(uint32) * blockCount);
	bitmap[0] = 0x00FFFFFFU; 
	bitmap[1] = 0xFF00FF00U; 
	bitmap[2] = 0xFFFF00FFU; 
	bitmap[3] = 0xFFFFFF00U; 

	unsigned char output[18];
	memset(output, 0, 18);

	int onDiskBlockCount = 0;
	int bmsWordCount = 0;
	/*
	 * For 64bit bms, bmsWordCount is half of onDiskBlockCount;
	 * For 32bit bms, bmsWordCount is equal to onDiskBlockCount.
	 */
	int expectedBmwWordCount = BITS_PER_BITMAPWORD == 64 ? 2 : 4;
	Bitmapset *bms;

	/* fake a bitmapset with the bitmap data */
	bms = (Bitmapset *) palloc(BITMAPSET_SIZE(expectedBmwWordCount));
	bms->nwords = expectedBmwWordCount;
	memcpy(bms->words, bitmap, sizeof(uint32) * 4);

	BitmapCompress_CalculateBlockCounts(bms,
										&onDiskBlockCount,
										&bmsWordCount);
	assert_int_equal(4, onDiskBlockCount);
	assert_int_equal(expectedBmwWordCount, bmsWordCount);

	int r = Bitmap_Compress(
			BITMAP_COMPRESSION_TYPE_DEFAULT, 
		bitmap, onDiskBlockCount,
		output, 18);
	assert_int_equal(r, (sizeof(uint32) * 4) + 2);

	uint32 bitmap2[4];
	memset(bitmap2, 1, sizeof(uint32) * blockCount);

	BitmapDecompressState decomp_state;
	BitmapDecompress_Init(&decomp_state, output, r);
	assert_false(BitmapDecompress_HasError(&decomp_state));
	assert_int_equal(BITMAP_COMPRESSION_TYPE_NO, 
			BitmapDecompress_GetCompressionType(&decomp_state));
	assert_int_equal(blockCount, BitmapDecompress_GetBlockCount(&decomp_state));

	BitmapDecompress_CalculateBlockCounts(&decomp_state,
										  &onDiskBlockCount,
										  &bmsWordCount);
	assert_int_equal(blockCount, onDiskBlockCount);
	assert_int_equal(expectedBmwWordCount, bmsWordCount);

	BitmapDecompress_Decompress(&decomp_state,
		bitmap2, onDiskBlockCount);
	assert_memory_equal(bitmap, bitmap2, sizeof(uint32) * blockCount);
}

static void
test__BitmapCompression__MultipleTypeBitmap(void **state)
{
	uint32 bitmap[16];
	memset(bitmap, 0, sizeof(uint32) * 16);
	bitmap[0] = 0xFFFFFFFFU; /* one case */
	bitmap[1] = 0xFF00FF00U; /* Raw */
	bitmap[2] = 0xFF00FF00U; /*One repetition, use RLE */
	bitmap[3] = 0xFFFFFFFFU; /* one case */
	bitmap[4] = 0xFFFFFFFFU; /* One repetition, no use RLE */
	bitmap[5] = 0x00000000U;
	bitmap[6] = 0xFFFFFFFFU; /* one case */
	bitmap[7] = 0xFFFFFFFFU; 
	bitmap[8] = 0xFFFFFFFFU;
	bitmap[9] = 0xFFFFFFFFU; 
	bitmap[10] = 0xFFFFFFFFU; 
	bitmap[11] = 0xFFFFFFFFU; 
	bitmap[12] = 0xFFFFFFFFU; 
	bitmap[13] = 0xFFFFFFFFU; /*use RLE */
	bitmap[14] = 0xFF22FF00U; /* Raw */
	bitmap[15] = 0xFF11FF00U; /* Raw */

	unsigned char output[sizeof(uint32) * 17];
	memset(output, 0, sizeof(uint32) * 17);

	int onDiskBlockCount = 0;
	int bmsWordCount = 0;
	/*
	 * For 64bit bms, bmsWordCount is half of onDiskBlockCount;
	 * For 32bit bms, bmsWordCount is equal to onDiskBlockCount.
	 */
	int expectedBmwWordCount = BITS_PER_BITMAPWORD == 64 ? 8 : 16;
	Bitmapset *bms;

	/* fake a bitmapset with the bitmap data */
	bms = (Bitmapset *) palloc(BITMAPSET_SIZE(expectedBmwWordCount));
	bms->nwords = expectedBmwWordCount;
	memcpy(bms->words, bitmap, sizeof(uint32) * 4);

	BitmapCompress_CalculateBlockCounts(bms,
										&onDiskBlockCount,
										&bmsWordCount);
	assert_int_equal(16, onDiskBlockCount);
	assert_int_equal(expectedBmwWordCount, bmsWordCount);

	int r = Bitmap_Compress(
		BITMAP_COMPRESSION_TYPE_DEFAULT, 
		bitmap, onDiskBlockCount,
		output, sizeof(uint32) * 17);
	assert_true(r < sizeof(uint32) * 16 && r >= 0);
	uint32 bitmap2[16];
	memset(bitmap2, 1, sizeof(uint32) * 16);

	BitmapDecompressState decomp_state;
	BitmapDecompress_Init(&decomp_state, output, r);
	assert_false(BitmapDecompress_HasError(&decomp_state));
	assert_int_equal(BITMAP_COMPRESSION_TYPE_DEFAULT, 
			BitmapDecompress_GetCompressionType(&decomp_state));
	assert_int_equal(16, BitmapDecompress_GetBlockCount(&decomp_state));

	BitmapDecompress_CalculateBlockCounts(&decomp_state,
										  &onDiskBlockCount,
										  &bmsWordCount);
	assert_int_equal(16, onDiskBlockCount);
	assert_int_equal(16, BitmapDecompress_GetBlockCount(&decomp_state));

	BitmapDecompress_Decompress(&decomp_state,
		bitmap2, onDiskBlockCount);
	assert_memory_equal(bitmap, bitmap2, sizeof(uint32) * 16);
}

static void
test__BitmapCompression_ShortDecompress(void **state)
{
	uint32 bitmap[16];
	memset(bitmap, 0, sizeof(uint32) * 16);
	bitmap[0] = 0xFFFFFFFFU; /* one case */
	bitmap[1] = 0xFF00FF00U; /* Raw */
	bitmap[2] = 0xFF00FF00U; /*One repetition, use RLE */
	bitmap[3] = 0xFFFFFFFFU; /* one case */
	bitmap[4] = 0xFFFFFFFFU; /* One repetition, no use RLE */
	bitmap[5] = 0x00000000U;
	bitmap[6] = 0xFFFFFFFFU; /* one case */
	bitmap[7] = 0xFFFFFFFFU; 
	bitmap[8] = 0xFFFFFFFFU;
	bitmap[9] = 0xFFFFFFFFU; 
	bitmap[10] = 0xFFFFFFFFU; 
	bitmap[11] = 0xFFFFFFFFU; 
	bitmap[12] = 0xFFFFFFFFU; 
	bitmap[13] = 0xFFFFFFFFU; /*use RLE */
	bitmap[14] = 0xFF22FF00U; /* Raw */
	bitmap[15] = 0xFF11FF00U; /* Raw */

	unsigned char output[sizeof(uint32) * 17];
	memset(output, 0, sizeof(uint32) * 17);

	int onDiskBlockCount = 0;
	int bmsWordCount = 0;
	/*
	 * For 64bit bms, bmsWordCount is half of onDiskBlockCount;
	 * For 32bit bms, bmsWordCount is equal to onDiskBlockCount.
	 */
	int expectedBmwWordCount = BITS_PER_BITMAPWORD == 64 ? 8 : 16;
	Bitmapset *bms;

	/* fake a bitmapset with the bitmap data */
	bms = (Bitmapset *) palloc(BITMAPSET_SIZE(expectedBmwWordCount));
	bms->nwords = expectedBmwWordCount;
	memcpy(bms->words, bitmap, sizeof(uint32) * 16);

	BitmapCompress_CalculateBlockCounts(bms,
										&onDiskBlockCount,
										&bmsWordCount);
	assert_int_equal(16, onDiskBlockCount);
	assert_int_equal(expectedBmwWordCount, bmsWordCount);

	int r = Bitmap_Compress(
		BITMAP_COMPRESSION_TYPE_DEFAULT, 
		bitmap, onDiskBlockCount,
		output, sizeof(uint32) * 17);
	assert_true(r < sizeof(uint32) * 16 && r >= 0);
	uint32 bitmap2[16];
	memset(bitmap2, 1, sizeof(uint32) * 16);

	for (int i = 0; i < 2; i++)
	{
		BitmapDecompressState decomp_state;
		assert_false(BitmapDecompress_Init(&decomp_state, output, i));
		assert_true(BitmapDecompress_HasError(&decomp_state));
	}
    
	for (int i = 2; i < r; i++)
	{
		BitmapDecompressState decomp_state;
		assert_true(BitmapDecompress_Init(&decomp_state, output, i));
		assert_false(BitmapDecompress_HasError(&decomp_state));
		assert_int_equal(BITMAP_COMPRESSION_TYPE_DEFAULT, 
			BitmapDecompress_GetCompressionType(&decomp_state));
		assert_int_equal(16, BitmapDecompress_GetBlockCount(&decomp_state));

		BitmapDecompress_CalculateBlockCounts(
			&decomp_state,
			&onDiskBlockCount,
			&bmsWordCount);
		assert_int_equal(16, onDiskBlockCount);
		assert_int_equal(expectedBmwWordCount, bmsWordCount);

		PG_TRY();
		{
			BitmapDecompress_Decompress(&decomp_state, bitmap2, onDiskBlockCount);
			assert_true(false); /*should not be reached */
		}
		PG_CATCH();
		{
			FlushErrorState();
		}
		PG_END_TRY();	
	}
}

static void
test__BitmapCompression__IllegalCompressionType(void **state)
{
	uint32 bitmap[1];
	memset(bitmap, 0, sizeof(uint32) * 1);

	unsigned char output[sizeof(uint32) * 5];
	memset(output, 0, sizeof(uint32) * 5);

	int onDiskBlockCount = 0;
	int bmsWordCount = 0;
	/*
	 * When onDiskBlockCount is 1, bmsWordCount is always 1 for
	 * both 64bit and 32bit bms.
	 */
	int expectedBmwWordCount = 1;
	Bitmapset *bms;

	/* fake a bitmapset with the bitmap data */
	bms = (Bitmapset *) palloc0(BITMAPSET_SIZE(expectedBmwWordCount));
	bms->nwords = expectedBmwWordCount;
	memcpy(bms->words, bitmap, sizeof(uint32));

	BitmapCompress_CalculateBlockCounts(bms,
										&onDiskBlockCount,
										&bmsWordCount);
	assert_int_equal(1, onDiskBlockCount);
	assert_int_equal(expectedBmwWordCount, bmsWordCount);

	PG_TRY();
	{
		Bitmap_Compress(
		14, 
		bitmap, onDiskBlockCount,
		output, sizeof(uint32) * 5);
		assert_true(false); /*should not be reached */
	}
	PG_CATCH();
	{
		FlushErrorState();
	}
	PG_END_TRY();	
}

int
main(int argc, char* argv[])
{
	cmockery_parse_arguments(argc, argv);

	const UnitTest tests[] = {
		unit_test(test__BitmapCompression__ZeroBitmap),
		unit_test(test__BitmapCompression__Raw),
		unit_test(test__BitmapCompression__ExplicitNoCompression),
		unit_test(test__BitmapCompression__ImplicitNoCompression),
		unit_test(test__BitmapCompression__MultipleTypeBitmap),
		unit_test(test__BitmapCompression_ShortDecompress),
		unit_test(test__BitmapCompression__ExplicitNoCompressionNoBlocks),
		unit_test(test__BitmapCompression__IllegalCompressionType)
	};

	MemoryContextInit();

	return run_tests(tests);
}
