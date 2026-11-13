#ifndef CGIF_RAW_H
#define CGIF_RAW_H

#include <stdint.h>

#include "cgif.h"

#ifdef __cplusplus
extern "C" {
#endif

#define DISPOSAL_METHOD_LEAVE      (1uL << 2)
#define DISPOSAL_METHOD_BACKGROUND (2uL << 2)
#define DISPOSAL_METHOD_PREVIOUS   (3uL << 2)

// flags to set the GIF attributes
#define CGIF_RAW_ATTR_IS_ANIMATED     (1uL << 0) // make an animated GIF (default is non-animated GIF)
#define CGIF_RAW_ATTR_NO_LOOP         (1uL << 1) // don't loop a GIF animation: only play it one time.

// flags to set the Frame attributes
#define CGIF_RAW_FRAME_ATTR_HAS_TRANS  (1uL << 0) // provided transIndex should be set
#define CGIF_RAW_FRAME_ATTR_INTERLACED (1uL << 1) // encode frame interlaced

// CGIFRaw_Config type
// note: internal sections, subject to change.
typedef struct {
  cgif_write_fn *pWriteFn;     // callback function for chunks of output data
  void*          pContext;     // opaque pointer passed as the first parameter to pWriteFn
  uint8_t*       pGCT;         // global color table of the GIF
  uint32_t       attrFlags;    // fixed attributes of the GIF (e.g. whether it is animated or not)
  uint16_t       width;        // effective width of each frame in the GIF
  uint16_t       height;       // effective height of each frame in the GIF
  uint16_t       sizeGCT;      // size of the global color table (GCT)
  uint16_t       numLoops;     // number of repetitons of an animated GIF (set to INFINITE_LOOP resp. 0 for infinite loop, use CGIF_ATTR_NO_LOOP if you don't want any repetition)
} CGIFRaw_Config;

// CGIFRaw_FrameConfig type
// note: internal sections, subject to chage.
typedef struct {
  uint8_t*  pLCT;              // local color table of the frame (LCT)
  uint8_t*  pImageData;        // image data to be encoded (indices to CT)
  uint32_t  attrFlags;         // fixed attributes of the GIF frame
  uint16_t  width;             // width of frame
  uint16_t  height;            // height of frame
  uint16_t  top;               // top offset of frame
  uint16_t  left;              // left offset of frame
  uint16_t  delay;             // delay before the next frame is shown (units of 0.01 s [cs])
  uint16_t  sizeLCT;           // size of the local color table (LCT)
  uint8_t   disposalMethod;    // specifies how this frame should be disposed after being displayed.
  uint8_t   transIndex;        // transparency index
} CGIFRaw_FrameConfig;

// CGIFRaw type
// note: internal sections, subject to change.
typedef struct {
  CGIFRaw_Config config;    // configutation parameters of the GIF (see above)
  cgif_result    curResult; // current result status of GIFRaw stream
} CGIFRaw;

// prototypes
CGIFRaw*    cgif_raw_newgif   (const CGIFRaw_Config* pConfig);
cgif_result cgif_raw_addframe (CGIFRaw* pGIF, const CGIFRaw_FrameConfig* pConfig);
cgif_result cgif_raw_close    (CGIFRaw* pGIF);

#ifdef __cplusplus
}
#endif

#endif // CGIF_RAW_H
