#include <stdlib.h>
#include <string.h>

#include "cgif_raw.h"

#define SIZE_MAIN_HEADER  (13)
#define SIZE_APP_EXT      (19)
#define SIZE_FRAME_HEADER (10)
#define SIZE_GRAPHIC_EXT  ( 8)

#define HEADER_OFFSET_SIGNATURE    (0x00)
#define HEADER_OFFSET_VERSION      (0x03)
#define HEADER_OFFSET_WIDTH        (0x06)
#define HEADER_OFFSET_HEIGHT       (0x08)
#define HEADER_OFFSET_PACKED_FIELD (0x0A)
#define HEADER_OFFSET_BACKGROUND   (0x0B)
#define HEADER_OFFSET_MAP          (0x0C)

#define IMAGE_OFFSET_LEFT          (0x01)
#define IMAGE_OFFSET_TOP           (0x03)
#define IMAGE_OFFSET_WIDTH         (0x05)
#define IMAGE_OFFSET_HEIGHT        (0x07)
#define IMAGE_OFFSET_PACKED_FIELD  (0x09)

#define IMAGE_PACKED_FIELD(a)      (*((uint8_t*) (a + IMAGE_OFFSET_PACKED_FIELD)))

#define APPEXT_OFFSET_NAME            (0x03)
#define APPEXT_NETSCAPE_OFFSET_LOOPS  (APPEXT_OFFSET_NAME + 13)

#define GEXT_OFFSET_DELAY          (0x04)

#define MAX_CODE_LEN    12                    // maximum code length for lzw
#define MAX_DICT_LEN    (1uL << MAX_CODE_LEN) // maximum length of the dictionary
#define BLOCK_SIZE      0xFF                  // number of bytes in one block of the image data

#define MULU16(a, b) (((uint32_t)a) * ((uint32_t)b)) // helper macro to correctly multiply two U16's without default signed int promotion

typedef struct {
  uint8_t* pRasterData;
  uint32_t sizeRasterData;
} LZWResult;

typedef struct {
  uint16_t*       pTreeInit;  // LZW dictionary tree for the initial dictionary (0-255 max)
  uint16_t*       pTreeListMap;   // LZW tree list: mapPos per node
  uint8_t*        pTreeListColor; // LZW tree list: child color per node
  uint16_t*       pTreeListIdx;   // LZW tree list: child LZW index per node
  uint16_t*       pTreeMap;   // LZW dictionary tree as map (backup to pTreeList in case more than 1 child is present)
  uint16_t*       pLZWData;   // pointer to LZW data
  const uint8_t*  pImageData; // pointer to image data
  uint32_t        numPixel;   // number of pixels per frame
  uint32_t        LZWPos;     // position of the current LZW code
  uint16_t        dictPos;    // currrent position in dictionary, we need to store 0-4096 -- so there are at least 13 bits needed here
  uint16_t        mapPos;     // current position in LZW tree mapping table
} LZWGenState;

/* converts host U16 to little-endian (LE) U16 */
static uint16_t hU16toLE(const uint16_t n) {
  int      isBE;
  uint16_t newVal;
  uint16_t one;

  one    = 1;
  isBE   = *((uint8_t*)&one) ? 0 : 1;
  if(isBE) {
    newVal = (n >> 8) | (n << 8);
  } else {
    newVal = n; // already LE
  }
  return newVal;
}

/* calculate next power of two exponent of given number (n MUST be <= 256) */
static uint8_t calcNextPower2Ex(uint16_t n) {
  uint8_t nextPow2;

  for (nextPow2 = 0; n > (1uL << nextPow2); ++nextPow2);
  return nextPow2;
}

/* compute which initial LZW-code length is needed */
static uint8_t calcInitCodeLen(uint16_t numEntries) {
  uint8_t index;

  index = calcNextPower2Ex(numEntries);
  return (index < 3) ? 3 : index + 1;
}

/* reset the dictionary of known LZW codes -- will reset the current code length as well */
static void resetDict(LZWGenState* pContext, const uint16_t initDictLen) {
  pContext->dictPos                    = initDictLen + 2;                             // reset current position in dictionary (number of colors + 2 for start and end code)
  pContext->mapPos                     = 1;
  pContext->pLZWData[pContext->LZWPos] = initDictLen;                                 // issue clear-code
  ++(pContext->LZWPos);                                                               // increment position in LZW data
  // reset LZW list
  memset(pContext->pTreeInit, 0, initDictLen * sizeof(uint16_t) * initDictLen);
  memset(pContext->pTreeListMap, 0, sizeof(uint16_t) * MAX_DICT_LEN);
  memset(pContext->pTreeListColor, 0, sizeof(uint8_t) * MAX_DICT_LEN);
  memset(pContext->pTreeListIdx, 0, sizeof(uint16_t) * MAX_DICT_LEN);
}

/* add new child node */
static void add_child(LZWGenState* pContext, const uint16_t parentIndex, const uint16_t LZWIndex, const uint16_t initDictLen, const uint8_t nextColor) {
  uint16_t mapPos;

  mapPos = pContext->pTreeListMap[parentIndex];
  if(!mapPos) { // if pTreeMap is not used yet for the parent node
    if(pContext->pTreeListIdx[parentIndex]) { // if at least one child node exists, switch to pTreeMap
      mapPos = pContext->mapPos;
      // add child to mapping table (pTreeMap)
      memset(pContext->pTreeMap + ((mapPos - 1) * initDictLen), 0, initDictLen * sizeof(uint16_t));
      pContext->pTreeMap[(mapPos - 1) * initDictLen + nextColor] = LZWIndex;
      pContext->pTreeListMap[parentIndex] = mapPos;
      ++(pContext->mapPos);
    } else { // use the free spot in pTreeList for the child node
      pContext->pTreeListColor[parentIndex] = nextColor; // color that leads to child node
      pContext->pTreeListIdx[parentIndex]   = LZWIndex;  // position of child node
    }
  } else { // directly add child node to pTreeMap
    pContext->pTreeMap[(mapPos - 1) * initDictLen + nextColor] = LZWIndex;
  }
  ++(pContext->dictPos); // increase current position in the dictionary
}

/* find next LZW code representing the longest pixel sequence that is still in the dictionary*/
static int lzw_crawl_tree(LZWGenState* pContext, uint32_t* pStrPos, uint16_t parentIndex, const uint16_t initDictLen) {
  uint16_t* pTreeInit;
  uint32_t  strPos;
  uint16_t  nextParent;
  uint16_t  mapPos;

  if(parentIndex >= initDictLen) {
    return CGIF_EINDEX; // error: index in image data out-of-bounds
  }
  pTreeInit = pContext->pTreeInit;
  strPos    = *pStrPos;
  // get the next LZW code from pTreeInit:
  // the initial nodes (0-255 max) have more children on average.
  // use the mapping approach right from the start for these nodes.
  if(strPos < (pContext->numPixel - 1)) {
    if(pContext->pImageData[strPos + 1] >= initDictLen) {
      return CGIF_EINDEX; // error: index in image data out-of-bounds
    }
    nextParent = pTreeInit[parentIndex * initDictLen + pContext->pImageData[strPos + 1]];
    if(nextParent) {
      parentIndex = nextParent;
      ++strPos;
    } else {
      pContext->pLZWData[pContext->LZWPos] = parentIndex; // write last LZW code in LZW data
      ++(pContext->LZWPos);
      if(pContext->dictPos < MAX_DICT_LEN) {
        pTreeInit[parentIndex * initDictLen + pContext->pImageData[strPos + 1]] = pContext->dictPos;
        ++(pContext->dictPos);
      } else {
        resetDict(pContext, initDictLen);
      }
      ++strPos;
      *pStrPos = strPos;
      return CGIF_OK;
    }
  }
  // inner loop for codes > initDictLen
  while(strPos < (pContext->numPixel - 1)) {
    if(pContext->pImageData[strPos + 1] >= initDictLen) {
      return CGIF_EINDEX;  // error: index in image data out-of-bounds
    }
    // first try to find child in LZW list
    if(pContext->pTreeListIdx[parentIndex] && pContext->pTreeListColor[parentIndex] == pContext->pImageData[strPos + 1]) {
      parentIndex = pContext->pTreeListIdx[parentIndex];
      ++strPos;
      continue;
    }
    // not found child yet? try to look into the LZW mapping table
    mapPos = pContext->pTreeListMap[parentIndex];
    if(mapPos) {
      nextParent = pContext->pTreeMap[(mapPos - 1) * initDictLen + pContext->pImageData[strPos + 1]];
      if(nextParent) {
        parentIndex = nextParent;
        ++strPos;
        continue;
      }
    }
    // still not found child? add current parentIndex to LZW data and add new child
    pContext->pLZWData[pContext->LZWPos] = parentIndex; // write last LZW code in LZW data
    ++(pContext->LZWPos);
    if(pContext->dictPos < MAX_DICT_LEN) { // if LZW-dictionary is not full yet
      add_child(pContext, parentIndex, pContext->dictPos, initDictLen, pContext->pImageData[strPos + 1]); // add new LZW code to dictionary
    } else {
      // the dictionary reached its maximum code => reset it (not required by GIF-standard but mostly done like this)
      resetDict(pContext, initDictLen);
    }
    ++strPos;
    *pStrPos = strPos;
    return CGIF_OK;
  }
  pContext->pLZWData[pContext->LZWPos] = parentIndex; // if the end of the image is reached, write last LZW code
  ++(pContext->LZWPos);
  ++strPos;
  *pStrPos = strPos;
  return CGIF_OK;
}

/* generate LZW-codes that compress the image data*/
static int lzw_generate(LZWGenState* pContext, uint16_t initDictLen) {
  uint32_t strPos;
  int      r;
  uint8_t  parentIndex;

  strPos = 0;                                                                          // start at beginning of the image data
  resetDict(pContext, initDictLen);                                            // reset dictionary and issue clear-code at first
  while(strPos < pContext->numPixel) {                                                 // while there are still image data to be encoded
    parentIndex  = pContext->pImageData[strPos];                                       // start at root node
    // get longest sequence that is still in dictionary, return new position in image data
    r = lzw_crawl_tree(pContext, &strPos, (uint16_t)parentIndex, initDictLen);
    if(r != CGIF_OK) {
      return r; // error: return error code to callee
    }
  }
  pContext->pLZWData[pContext->LZWPos] = initDictLen + 1; // termination code
  ++(pContext->LZWPos);
  return CGIF_OK;
}

/* pack the LZW data into a byte sequence*/
static uint32_t create_byte_list(uint8_t *byteList, uint32_t lzwPos, uint16_t *lzwStr, uint16_t initDictLen, uint8_t initCodeLen){
  uint32_t i;
  uint32_t dictPos;                                                             // counting new LZW codes
  uint16_t n             = 2 * initDictLen;                             // if n - initDictLen == dictPos, the LZW code size is incremented by 1 bit
  uint32_t bytePos       = 0;                                                   // position of current byte
  uint8_t  bitOffset      = 0;                                                   // number of bits used in the last byte
  uint8_t  lzwCodeLen    = initCodeLen;                                 // dynamically increasing length of the LZW codes
  int      correctLater  = 0;                                                   // 1: one empty byte too much if end is reached after current code, 0 otherwise

  byteList[0] = 0; // except from the 1st byte all other bytes should be initialized stepwise (below)
  // the very first symbol might be the clear-code. However, this is not mandatory. Quote:
  // "Encoders should output a Clear code as the first code of each image data stream."
  // We keep the option to NOT output the clear code as the first symbol in this function.
  dictPos     = 1;
  for(i = 0; i < lzwPos; ++i) {                                                 // loop over all LZW codes
    if((lzwCodeLen < MAX_CODE_LEN) && ((uint32_t)(n - (initDictLen)) == dictPos)) { // larger code is used for the 1st time at i = 256 ...+ 512 ...+ 1024 -> 256, 768, 1792
      ++lzwCodeLen;                                                             // increment the length of the LZW codes (bit units)
      n *= 2;                                                                   // set threshold for next increment of LZW code size
    }
    correctLater       = 0;                                                     // 1 indicates that one empty byte is too much at the end
    byteList[bytePos] |= ((uint8_t)(lzwStr[i] << bitOffset));                   // add 1st bits of the new LZW code to the byte containing part of the previous code
    if(lzwCodeLen + bitOffset >= 8) {                                           // if the current byte is not enough of the LZW code
      if(lzwCodeLen + bitOffset == 8) {                                         // if just this byte is filled exactly
        byteList[++bytePos] = 0;                                                // byte is full -- go to next byte and initialize as 0
        correctLater        = 1;                                                // use if one 0byte to much at the end
      } else if(lzwCodeLen + bitOffset < 16) {                                  // if the next byte is not completely filled
        byteList[++bytePos] = (uint8_t)(lzwStr[i] >> (8-bitOffset));
      } else if(lzwCodeLen + bitOffset == 16) {                                 // if the next byte is exactly filled by LZW code
        byteList[++bytePos] = (uint8_t)(lzwStr[i] >> (8-bitOffset));
        byteList[++bytePos] = 0;                                                // byte is full -- go to next byte and initialize as 0
        correctLater        = 1;                                                // use if one 0byte to much at the end
      } else {                                                                  // lzw-code ranges over 3 bytes in total
        byteList[++bytePos] = (uint8_t)(lzwStr[i] >> (8-bitOffset));            // write part of LZW code to next byte
        byteList[++bytePos] = (uint8_t)(lzwStr[i] >> (16-bitOffset));           // write part of LZW code to byte after next byte
      }
    }
    bitOffset = (lzwCodeLen + bitOffset) % 8;                                   // how many bits of the last byte are used?
    ++dictPos;                                                                  // increment count of LZW codes
    if(lzwStr[i] == initDictLen) {                                      // if a clear code appears in the LZW data
      lzwCodeLen = initCodeLen;                                         // reset length of LZW codes
      n          = 2 * initDictLen;                                     // reset threshold for next increment of LZW code length
      dictPos = 1;                                                              // reset (see comment below)
      // take first code already into account to increment lzwCodeLen exactly when the code length cannot represent the current maximum symbol.
      // Note: This is usually done implicitly, as the very first symbol is a clear-code itself.
    }
  }
  // comment: the last byte can be zero in the following case only:
  // terminate code has been written (initial dict length + 1), but current code size is larger so padding zero bits were added and extend into the next byte(s).
  if(correctLater) {                                                            // if an unneccessaray empty 0-byte was initialized at the end
    --bytePos;                                                                  // don't consider the last empty byte
  }
  return bytePos;
}

/* put byte sequence in blocks as required by GIF-format */
static uint32_t create_byte_list_block(uint8_t *byteList, uint8_t *byteListBlock, const uint32_t numBytes) {
  uint32_t i;
  uint32_t numBlock = numBytes / BLOCK_SIZE;                                                    // number of byte blocks with length BLOCK_SIZE
  uint8_t  numRest  = numBytes % BLOCK_SIZE;                                                    // number of bytes in last block (if not completely full)

  for(i = 0; i < numBlock; ++i) {                                                               // loop over all blocks
    byteListBlock[i * (BLOCK_SIZE+1)] = BLOCK_SIZE;                                             // number of bytes in the following block
    memcpy(byteListBlock + 1+i*(BLOCK_SIZE+1), byteList + i*BLOCK_SIZE, BLOCK_SIZE);            // copy block from byteList to byteListBlock
  }
  if(numRest>0) {
    byteListBlock[numBlock*(BLOCK_SIZE+1)] = numRest;                                           // number of bytes in the following block
    memcpy(byteListBlock + 1+numBlock*(BLOCK_SIZE+1), byteList + numBlock*BLOCK_SIZE, numRest); // copy block from byteList to byteListBlock
    byteListBlock[1 + numBlock * (BLOCK_SIZE + 1) + numRest] = 0;                               // set 0 at end of frame
    return 1 + numBlock * (BLOCK_SIZE + 1) + numRest;                                           // index of last entry in byteListBlock
  }
  // all LZW blocks in the frame have the same block size (BLOCK_SIZE), so there are no remaining bytes to be writen.
  byteListBlock[numBlock *(BLOCK_SIZE + 1)] = 0;                                                // set 0 at end of frame
  return numBlock *(BLOCK_SIZE + 1);                                                            // index of last entry in byteListBlock
}

/* create all LZW raster data in GIF-format */
static int LZW_GenerateStream(LZWResult* pResult, const uint32_t numPixel, const uint8_t* pImageData, const uint16_t initDictLen, const uint8_t initCodeLen){
  LZWGenState* pContext;
  uint32_t     lzwPos, bytePos, entriesPerCycle, maxResets;
  uint32_t     bytePosBlock;
  int          r;
  // TBD recycle LZW tree list and map (if possible) to decrease the number of allocs
  pContext             = malloc(sizeof(LZWGenState));
  if(pContext == NULL) {
    return CGIF_EALLOC;
  }
  memset(pContext, 0, sizeof(LZWGenState));
  pContext->pTreeInit  = malloc((initDictLen * sizeof(uint16_t)) * initDictLen);
  if(pContext->pTreeInit == NULL) {
    r = CGIF_EALLOC;
    goto LZWGENERATE_Cleanup;
  }
  pContext->pTreeListMap   = malloc(sizeof(uint16_t) * MAX_DICT_LEN);
  pContext->pTreeListColor = malloc(sizeof(uint8_t) * MAX_DICT_LEN);
  pContext->pTreeListIdx   = malloc(sizeof(uint16_t) * MAX_DICT_LEN);
  if(pContext->pTreeListMap == NULL || pContext->pTreeListColor == NULL || pContext->pTreeListIdx == NULL) {
    r = CGIF_EALLOC;
    goto LZWGENERATE_Cleanup;
  }
  pContext->pTreeMap   = malloc(((MAX_DICT_LEN / 2) + 1) * (initDictLen * sizeof(uint16_t)));
  if(pContext->pTreeMap == NULL) {
    r = CGIF_EALLOC;
    goto LZWGENERATE_Cleanup;
  }
  pContext->numPixel   = numPixel;
  pContext->pImageData = pImageData;
  // Buffer must hold at max (conservative upper bound): 1 initial clear + numPixel data codes + N reset clears + 1 termination
  // where N = max dictionary resets = numPixel / (MAX_DICT_LEN - initDictLen - 2)
  entriesPerCycle = MAX_DICT_LEN - initDictLen - 2; // maximum added number of dictionary entries per cycle: -2 to account for start and end code
  maxResets = numPixel / entriesPerCycle;
  pContext->pLZWData   = malloc(sizeof(uint16_t) * ((size_t)numPixel + 2 + maxResets));
  if(pContext->pLZWData == NULL) {
    r = CGIF_EALLOC;
    goto LZWGENERATE_Cleanup;
  }
  pContext->LZWPos     = 0;

  // actually generate the LZW sequence.
  r = lzw_generate(pContext, initDictLen);
  if(r != CGIF_OK) {
    goto LZWGENERATE_Cleanup;
  }
  lzwPos = pContext->LZWPos;

  // pack the generated LZW data into blocks of 255 bytes
  uint8_t *byteList; // lzw-data packed in byte-list
  uint8_t *byteListBlock; // lzw-data packed in byte-list with 255-block structure
  uint64_t MaxByteListLen = (uint64_t)MAX_CODE_LEN * lzwPos / 8ull + 2ull + 1ull; // conservative upper bound
  uint64_t MaxByteListBlockLen = (uint64_t)MAX_CODE_LEN * lzwPos * (BLOCK_SIZE + 1ull) / 8ull / BLOCK_SIZE + 2ull + 1ull +1ull; // conservative upper bound
  byteList      = malloc(MaxByteListLen);
  byteListBlock = malloc(MaxByteListBlockLen);
  if(byteList == NULL || byteListBlock == NULL) {
    free(byteList);
    free(byteListBlock);
    r = CGIF_EALLOC;
    goto LZWGENERATE_Cleanup;
  }
  bytePos       = create_byte_list(byteList,lzwPos, pContext->pLZWData, initDictLen, initCodeLen);
  bytePosBlock  = create_byte_list_block(byteList, byteListBlock, bytePos+1);
  free(byteList);
  pResult->sizeRasterData = bytePosBlock + 1; // save
  pResult->pRasterData    = byteListBlock;
LZWGENERATE_Cleanup:
  free(pContext->pLZWData);
  free(pContext->pTreeInit);
  free(pContext->pTreeListMap);
  free(pContext->pTreeListColor);
  free(pContext->pTreeListIdx);
  free(pContext->pTreeMap);
  free(pContext);
  return r;
}

/* initialize the header of the GIF */
static void initMainHeader(const CGIFRaw_Config* pConfig, uint8_t* pHeader) {
  uint16_t width, height;
  uint8_t  pow2GlobalPalette;

  width  = pConfig->width;
  height = pConfig->height;

  // set header to a clean state
  memset(pHeader, 0, SIZE_MAIN_HEADER);

  // set Signature field to value "GIF"
  pHeader[HEADER_OFFSET_SIGNATURE]     = 'G';
  pHeader[HEADER_OFFSET_SIGNATURE + 1] = 'I';
  pHeader[HEADER_OFFSET_SIGNATURE + 2] = 'F';

  // set Version field to value "89a"
  pHeader[HEADER_OFFSET_VERSION]       = '8';
  pHeader[HEADER_OFFSET_VERSION + 1]   = '9';
  pHeader[HEADER_OFFSET_VERSION + 2]   = 'a';

  // set width of screen (LE ordering)
  const uint16_t widthLE  = hU16toLE(width);
  memcpy(pHeader + HEADER_OFFSET_WIDTH, &widthLE, sizeof(uint16_t));

  // set height of screen (LE ordering)
  const uint16_t heightLE = hU16toLE(height);
  memcpy(pHeader + HEADER_OFFSET_HEIGHT, &heightLE, sizeof(uint16_t));

  // init packed field
  if(pConfig->sizeGCT) {
    pHeader[HEADER_OFFSET_PACKED_FIELD] = (1 << 7); // M = 1 (see GIF specc): global color table is present
    // calculate needed size of global color table (GCT).
    // MUST be a power of two.
    pow2GlobalPalette = calcNextPower2Ex(pConfig->sizeGCT);
    pow2GlobalPalette = (pow2GlobalPalette < 1) ? 1 : pow2GlobalPalette;      // minimum size is 2^1
    pHeader[HEADER_OFFSET_PACKED_FIELD] |= ((pow2GlobalPalette - 1) << 0);    // set size of GCT (0 - 7 in header + 1)
  }
}

/* initialize NETSCAPE app extension block (needed for animation) */
static void initAppExtBlock(uint8_t* pAppExt, uint16_t numLoops) {
  memset(pAppExt, 0, SIZE_APP_EXT);
  // set data
  pAppExt[0] = 0x21;
  pAppExt[1] = 0xFF; // start of block
  pAppExt[2] = 0x0B; // eleven bytes to follow

  // write identifier for Netscape animation extension
  pAppExt[APPEXT_OFFSET_NAME]      = 'N';
  pAppExt[APPEXT_OFFSET_NAME + 1]  = 'E';
  pAppExt[APPEXT_OFFSET_NAME + 2]  = 'T';
  pAppExt[APPEXT_OFFSET_NAME + 3]  = 'S';
  pAppExt[APPEXT_OFFSET_NAME + 4]  = 'C';
  pAppExt[APPEXT_OFFSET_NAME + 5]  = 'A';
  pAppExt[APPEXT_OFFSET_NAME + 6]  = 'P';
  pAppExt[APPEXT_OFFSET_NAME + 7]  = 'E';
  pAppExt[APPEXT_OFFSET_NAME + 8]  = '2';
  pAppExt[APPEXT_OFFSET_NAME + 9]  = '.';
  pAppExt[APPEXT_OFFSET_NAME + 10] = '0';
  pAppExt[APPEXT_OFFSET_NAME + 11] = 0x03; // 3 bytes to follow
  pAppExt[APPEXT_OFFSET_NAME + 12] = 0x01; // TBD clarify
  // set number of repetitions (animation; LE ordering)
  const uint16_t netscapeLE = hU16toLE(numLoops);
  memcpy(pAppExt + APPEXT_NETSCAPE_OFFSET_LOOPS, &netscapeLE, sizeof(uint16_t));
}

/* write numBytes dummy bytes */
static int writeDummyBytes(cgif_write_fn* pWriteFn, void* pContext, int numBytes) {
  int rWrite              = 0;
  const uint8_t dummyByte = 0;

  for(int i = 0; i < numBytes; ++i) {
    rWrite |= pWriteFn(pContext, &dummyByte, 1);
  }
  return rWrite;
}

CGIFRaw* cgif_raw_newgif(const CGIFRaw_Config* pConfig) {
  uint8_t  aAppExt[SIZE_APP_EXT];
  uint8_t  aHeader[SIZE_MAIN_HEADER];
  CGIFRaw* pGIF;
  int      rWrite;
  // check for invalid GCT size
  if(pConfig->sizeGCT > 256) {
    return NULL; // invalid GCT size
  }
  pGIF = malloc(sizeof(CGIFRaw));
  if(!pGIF) {
    return NULL;
  }
  memcpy(&(pGIF->config), pConfig, sizeof(CGIFRaw_Config));
  // initiate all sections we can at this stage:
  // - main GIF header
  // - global color table (GCT), if required
  // - netscape application extension (for animation), if required
  initMainHeader(pConfig, aHeader);
  rWrite = pConfig->pWriteFn(pConfig->pContext, aHeader, SIZE_MAIN_HEADER);

  // GCT required? => write it.
  if(pConfig->sizeGCT) {
    rWrite |= pConfig->pWriteFn(pConfig->pContext, pConfig->pGCT, pConfig->sizeGCT * 3);
    uint8_t pow2GCT             = calcNextPower2Ex(pConfig->sizeGCT);
    pow2GCT                     = (pow2GCT < 1) ? 1 : pow2GCT; // minimum size is 2^1
    const uint16_t numBytesLeft = ((1 << pow2GCT) - pConfig->sizeGCT) * 3;
    rWrite |= writeDummyBytes(pConfig->pWriteFn, pConfig->pContext, numBytesLeft);
  }
  // GIF should be animated? => init & write app extension header ("NETSCAPE2.0")
  // No loop? Don't write NETSCAPE extension.
  if((pConfig->attrFlags & CGIF_RAW_ATTR_IS_ANIMATED) && !(pConfig->attrFlags & CGIF_RAW_ATTR_NO_LOOP)) {
    initAppExtBlock(aAppExt, pConfig->numLoops);
    rWrite |= pConfig->pWriteFn(pConfig->pContext, aAppExt, SIZE_APP_EXT);
  }
  // check for write errors
  if(rWrite) {
    free(pGIF);
    return NULL;
  }

  // assume error per default.
  // set to CGIF_OK by the first successful cgif_raw_addframe() call, as a GIF without frames is invalid.
  pGIF->curResult = CGIF_PENDING;
  return pGIF;
}

/* add new frame to the raw GIF stream */
cgif_result cgif_raw_addframe(CGIFRaw* pGIF, const CGIFRaw_FrameConfig* pConfig) {
  uint8_t    aFrameHeader[SIZE_FRAME_HEADER];
  uint8_t    aGraphicExt[SIZE_GRAPHIC_EXT];
  LZWResult  encResult;
  int        r, rWrite;
  const int  useLCT = pConfig->sizeLCT; // LCT stands for "local color table"
  const int  isInterlaced = (pConfig->attrFlags & CGIF_RAW_FRAME_ATTR_INTERLACED) ? 1 : 0;
  uint16_t   numEffColors; // number of effective colors
  uint16_t   initDictLen;
  uint8_t    pow2LCT, initCodeLen;

  if(pGIF->curResult != CGIF_OK && pGIF->curResult != CGIF_PENDING) {
    return pGIF->curResult; // return previous error
  }
  // check for invalid LCT size
  if(pConfig->sizeLCT > 256) {
    pGIF->curResult = CGIF_ERROR; // invalid LCT size
    return pGIF->curResult;
  }

  rWrite = 0;
  // set frame header to a clean state
  memset(aFrameHeader, 0, SIZE_FRAME_HEADER);
  // set needed fields in frame header
  aFrameHeader[0] = ','; // set frame seperator
  if(useLCT) {
    pow2LCT = calcNextPower2Ex(pConfig->sizeLCT);
    pow2LCT = (pow2LCT < 1) ? 1 : pow2LCT; // minimum size is 2^1
    IMAGE_PACKED_FIELD(aFrameHeader)  = (1 << 7);
    // set size of local color table (0-7 in header + 1)
    IMAGE_PACKED_FIELD(aFrameHeader) |= ((pow2LCT- 1) << 0);
    numEffColors = pConfig->sizeLCT;
  } else {
    numEffColors = pGIF->config.sizeGCT; // global color table in use
  }
  // encode frame interlaced?
  IMAGE_PACKED_FIELD(aFrameHeader) |= (isInterlaced << 6);

  // transparency in use? we might need to increase numEffColors
  if((pGIF->config.attrFlags & (CGIF_RAW_ATTR_IS_ANIMATED)) && (pConfig->attrFlags & (CGIF_RAW_FRAME_ATTR_HAS_TRANS)) && pConfig->transIndex >= numEffColors) {
    numEffColors = pConfig->transIndex + 1;
  }

  // calculate initial code length and initial dict length
  initCodeLen = calcInitCodeLen(numEffColors);
  initDictLen = 1uL << (initCodeLen - 1);
  const uint8_t initialCodeSize = initCodeLen - 1;

  const uint16_t frameWidthLE  = hU16toLE(pConfig->width);
  const uint16_t frameHeightLE = hU16toLE(pConfig->height);
  const uint16_t frameTopLE    = hU16toLE(pConfig->top);
  const uint16_t frameLeftLE   = hU16toLE(pConfig->left);
  memcpy(aFrameHeader + IMAGE_OFFSET_WIDTH,  &frameWidthLE,  sizeof(uint16_t));
  memcpy(aFrameHeader + IMAGE_OFFSET_HEIGHT, &frameHeightLE, sizeof(uint16_t));
  memcpy(aFrameHeader + IMAGE_OFFSET_TOP,    &frameTopLE,    sizeof(uint16_t));
  memcpy(aFrameHeader + IMAGE_OFFSET_LEFT,   &frameLeftLE,   sizeof(uint16_t));
  // apply interlaced pattern
  // TBD creating a copy of pImageData is not ideal, but changes on the LZW encoding would
  // be necessary otherwise.
  if(isInterlaced) {
    uint8_t* pInterlaced = malloc(MULU16(pConfig->width, pConfig->height));
    if(pInterlaced == NULL) {
      pGIF->curResult = CGIF_EALLOC;
      return pGIF->curResult;
    }
    uint8_t* p = pInterlaced;
    // every 8th row (starting with row 0)
    for(uint32_t i = 0; i < pConfig->height; i += 8) {
      memcpy(p, pConfig->pImageData + i * pConfig->width, pConfig->width);
      p += pConfig->width;
    }
    // every 8th row (starting with row 4)
    for(uint32_t i = 4; i < pConfig->height; i += 8) {
      memcpy(p, pConfig->pImageData + i * pConfig->width, pConfig->width);
      p += pConfig->width;
    }
    // every 4th row (starting with row 2)
    for(uint32_t i = 2; i < pConfig->height; i += 4) {
      memcpy(p, pConfig->pImageData + i * pConfig->width, pConfig->width);
      p += pConfig->width;
    }
    // every 2th row (starting with row 1)
    for(uint32_t i = 1; i < pConfig->height; i += 2) {
      memcpy(p, pConfig->pImageData + i * pConfig->width, pConfig->width);
      p += pConfig->width;
    }
    r = LZW_GenerateStream(&encResult, MULU16(pConfig->width, pConfig->height), pInterlaced, initDictLen, initCodeLen);
    free(pInterlaced);
  } else {
    r = LZW_GenerateStream(&encResult, MULU16(pConfig->width, pConfig->height), pConfig->pImageData, initDictLen, initCodeLen);
  }

  // generate LZW raster data (actual image data)
  // check for errors
  if(r != CGIF_OK) {
    pGIF->curResult = r;
    return r;
  }

  // check whether the Graphic Control Extension is required or not:
  // It's required for animations and frames with transparency.
  int needsGraphicCtrlExt = (pGIF->config.attrFlags & CGIF_RAW_ATTR_IS_ANIMATED) | (pConfig->attrFlags & CGIF_RAW_FRAME_ATTR_HAS_TRANS);
  // do things for animation / transparency, if required.
  if(needsGraphicCtrlExt) {
    memset(aGraphicExt, 0, SIZE_GRAPHIC_EXT);
    aGraphicExt[0] = 0x21;
    aGraphicExt[1] = 0xF9;
    aGraphicExt[2] = 0x04;
    aGraphicExt[3] = pConfig->disposalMethod;
    // set flag indicating that transparency is used, if required.
    if(pConfig->attrFlags & CGIF_RAW_FRAME_ATTR_HAS_TRANS) {
      aGraphicExt[3] |= 0x01;
      aGraphicExt[6]  = pConfig->transIndex;
    }
    // set delay (LE ordering)
    const uint16_t delayLE = hU16toLE(pConfig->delay);
    memcpy(aGraphicExt + GEXT_OFFSET_DELAY, &delayLE, sizeof(uint16_t));
    // write Graphic Control Extension
    rWrite |= pGIF->config.pWriteFn(pGIF->config.pContext, aGraphicExt, SIZE_GRAPHIC_EXT);
  }

  // write frame
  rWrite |= pGIF->config.pWriteFn(pGIF->config.pContext, aFrameHeader, SIZE_FRAME_HEADER);
  if(useLCT) {
    rWrite |= pGIF->config.pWriteFn(pGIF->config.pContext, pConfig->pLCT, pConfig->sizeLCT * 3);
    const uint16_t numBytesLeft = ((1 << pow2LCT) - pConfig->sizeLCT) * 3;
    rWrite |= writeDummyBytes(pGIF->config.pWriteFn, pGIF->config.pContext, numBytesLeft);
  }
  rWrite |= pGIF->config.pWriteFn(pGIF->config.pContext, &initialCodeSize, 1);
  rWrite |= pGIF->config.pWriteFn(pGIF->config.pContext, encResult.pRasterData, encResult.sizeRasterData);

  // check for write errors
  if(rWrite) {
    pGIF->curResult = CGIF_EWRITE;
  } else {
    pGIF->curResult = CGIF_OK;
  }
  // cleanup
  free(encResult.pRasterData);
  return pGIF->curResult;
}

cgif_result cgif_raw_close(CGIFRaw* pGIF) {
  int         rWrite;
  cgif_result result;

  rWrite = pGIF->config.pWriteFn(pGIF->config.pContext, (unsigned char*) ";", 1); // write term symbol
  // check for write errors
  if(rWrite) {
    pGIF->curResult = CGIF_EWRITE;
  }
  result = pGIF->curResult;
  free(pGIF);
  return result;
}
