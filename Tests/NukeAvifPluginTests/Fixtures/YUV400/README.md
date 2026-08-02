# YUV400 grayscale fixtures

AVIF fixtures for YUV400 / 8-bit grayscale path tests (and fallback cases).
Generated with Homebrew `libavif` (`avifenc` 1.4.2 / aom 3.14.1).

Existing production fixtures remain in the parent `Fixtures/` directory.
Bundle loading (SwiftPM `.process("Fixtures")`):

```swift
Bundle.module.url(
    forResource: "yuv400.8bpc.limited.no-alpha.gray-ramps",
    withExtension: "avif",
    subdirectory: "YUV400"
)
```

## Files

| File | Format | Depth | Range | Alpha | Size | Pattern / purpose |
|------|--------|-------|-------|-------|------|-------------------|
| `yuv400.8bpc.limited.no-alpha.gray-ramps.avif` | YUV400 | 8 | limited | no | 96×64 | Vertical bands **Y=16 / 126 / 235** (black / mid / white). Pixel-value checks for limited expansion. |
| `yuv400.8bpc.full.no-alpha.known-y.avif` | YUV400 | 8 | full | no | 100×40 | Vertical bands **Y=0 / 64 / 128 / 192 / 255**. Full-range (no expansion) checks. |
| `yuv420.8bpc.limited.no-alpha.visual-mono.avif` | YUV420 | 8 | limited | no | 96×64 | Same Y bands as gray-ramps, **U=V=128**. Visual mono / fallback (not YUV400). |
| `yuv400.10bpc.limited.no-alpha.fallback.avif` | YUV400 | 10 | limited | no | 64×32 | Vertical bands **Y10=64 / 502 / 940**. 10-bit fallback. |
| `yuv400.8bpc.limited.alpha.fallback.avif` | YUV400 | 8 | limited | yes | 64×32 | Gray bands + alpha bands **A=255 / 128 / 0**. Alpha fallback. |
| `yuv400.8bpc.limited.no-alpha.odd-width-1179.avif` | YUV400 | 8 | limited | no | **1179**×32 | Same Y bands as gray-ramps. Odd-width stride / row-shift checks. |

Verified with `avifdec --info` (format/depth/range/alpha/size) and round-trip `avifdec → y4m` Y sampling for the 8-bit no-alpha cases.

## Generation

Tool: `brew install libavif` → `avifenc` / `avifdec`.

Source images were synthetic Y4M (mono / 420) or grayscale+alpha PNG. Limited-range encode cannot use `avifenc -l` (lossless requires full range); use `-q 100 -s 0` instead.

```bash
# 1) YUV400 8-bit limited — gray ramps (from Cmono XCOLORRANGE=LIMITED y4m)
avifenc -q 100 -s 0 -y 400 yuv400_8b_limited_ramps.y4m \
  yuv400.8bpc.limited.no-alpha.gray-ramps.avif

# 2) YUV400 8-bit full — known Y (from Cmono XCOLORRANGE=FULL y4m)
avifenc -l -y 400 yuv400_8b_full_known.y4m \
  yuv400.8bpc.full.no-alpha.known-y.avif

# 3) YUV420 8-bit limited — visual mono (from C420jpeg XCOLORRANGE=LIMITED y4m, U=V=128)
avifenc -q 100 -s 0 -y 420 yuv420_8b_limited_mono.y4m \
  yuv420.8bpc.limited.no-alpha.visual-mono.avif

# 4) YUV400 10-bit limited (from Cmono10 XCOLORRANGE=LIMITED y4m)
avifenc -q 100 -s 0 -y 400 -d 10 yuv400_10b_limited.y4m \
  yuv400.10bpc.limited.no-alpha.fallback.avif

# 5) YUV400 8-bit limited + alpha (from 8-bit grayscale+alpha PNG)
avifenc -q 100 -s 0 -y 400 -r limited --qalpha 100 yuv400_8b_alpha.png \
  yuv400.8bpc.limited.alpha.fallback.avif

# 6) YUV400 8-bit limited odd width 1179
avifenc -q 100 -s 0 -y 400 yuv400_8b_limited_odd1179.y4m \
  yuv400.8bpc.limited.no-alpha.odd-width-1179.avif
```

### Y4M notes

- Mono 8-bit: `YUV4MPEG2 W{w} H{h} F30:1 Ip A0:0 Cmono XCOLORRANGE={LIMITED|FULL}`
- Mono 10-bit: `Cmono10` with 16-bit little-endian samples
- 420: `C420jpeg` + U/V planes (neutral 128)

### PNG (alpha case)

- 8-bit grayscale + alpha (`IHDR` color type 4)
- Gray bands 16 / 128 / 235; alpha bands 255 / 128 / 0
- RGB→YUV for limited range is not bit-exact on Y; this file is for alpha/fallback path only
