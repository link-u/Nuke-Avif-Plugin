import CoreGraphics
import XCTest
import libavif
@testable import NukeAvifPlugin

/// YUV400 → DeviceGray 8bpp 経路およびフォールバックの検証。
///
/// 許容誤差:
/// - limited / `-q 100`: エンコード非可逆のため ±2
/// - full / lossless (`-l`): ±0（入力 Y のまま）
final class YUV400DeviceGrayDecodingTests: XCTestCase {

    /// limited-range フィクスチャ（`-q 100`）の画素比較許容誤差。
    private static let limitedPixelTolerance = 2
    /// full-range lossless フィクスチャの画素比較許容誤差。
    private static let fullPixelTolerance = 0

    private enum Fixture: String {
        case limitedGrayRamps = "yuv400.8bpc.limited.no-alpha.gray-ramps"
        case fullKnownY = "yuv400.8bpc.full.no-alpha.known-y"
        case visualMono420 = "yuv420.8bpc.limited.no-alpha.visual-mono"
        case depth10Fallback = "yuv400.10bpc.limited.no-alpha.fallback"
        case alphaFallback = "yuv400.8bpc.limited.alpha.fallback"
        case oddWidth1179 = "yuv400.8bpc.limited.no-alpha.odd-width-1179"
    }

    override func setUp() {
        super.setUp()
        AvifImageDecoder.yuv400DeviceGrayDecodingEnabled = true
    }

    override func tearDown() {
        AvifImageDecoder.yuv400DeviceGrayDecodingEnabled = true
        super.tearDown()
    }

    // MARK: - Flag default

    /// フラグのデフォルト（および setUp 復元後）が ON であることを検証する。
    func testYUV400DeviceGrayDecodingEnabledDefaultsToTrue() {
        XCTAssertTrue(AvifImageDecoder.yuv400DeviceGrayDecodingEnabled)
    }

    // MARK: - Eligibility (pure)

    /// YUV400 / 8bit / アルファなし / transform なしだけが DeviceGray 経路の対象になることを検証する。
    func testEligibilityAcceptsYUV400EightBitNoAlpha() {
        let input = YUV400GrayscaleEligibility(
            yuvFormat: AVIF_PIXEL_FORMAT_YUV400,
            depth: 8,
            alphaPresent: false,
            alphaPlaneIsNull: true,
            transformFlags: AVIF_TRANSFORM_NONE.rawValue
        )
        XCTAssertTrue(isEligibleForYUV400GrayscaleDecoding(input))
    }

    /// YUV420（見た目グレーでも chroma あり）は DeviceGray 経路に入らないことを検証する。
    func testEligibilityRejectsYUV420VisualMono() {
        let input = YUV400GrayscaleEligibility(
            yuvFormat: AVIF_PIXEL_FORMAT_YUV420,
            depth: 8,
            alphaPresent: false,
            alphaPlaneIsNull: true,
            transformFlags: AVIF_TRANSFORM_NONE.rawValue
        )
        XCTAssertFalse(isEligibleForYUV400GrayscaleDecoding(input))
    }

    /// 10bit YUV400 は DeviceGray 8bpp 経路の対象外であることを検証する。
    func testEligibilityRejectsTenBit() {
        let input = YUV400GrayscaleEligibility(
            yuvFormat: AVIF_PIXEL_FORMAT_YUV400,
            depth: 10,
            alphaPresent: false,
            alphaPlaneIsNull: true,
            transformFlags: AVIF_TRANSFORM_NONE.rawValue
        )
        XCTAssertFalse(isEligibleForYUV400GrayscaleDecoding(input))
    }

    /// alphaPresent または alphaPlane がある YUV400 は DeviceGray 経路の対象外であることを検証する。
    func testEligibilityRejectsAlphaPresent() {
        let present = YUV400GrayscaleEligibility(
            yuvFormat: AVIF_PIXEL_FORMAT_YUV400,
            depth: 8,
            alphaPresent: true,
            alphaPlaneIsNull: true,
            transformFlags: AVIF_TRANSFORM_NONE.rawValue
        )
        let plane = YUV400GrayscaleEligibility(
            yuvFormat: AVIF_PIXEL_FORMAT_YUV400,
            depth: 8,
            alphaPresent: false,
            alphaPlaneIsNull: false,
            transformFlags: AVIF_TRANSFORM_NONE.rawValue
        )
        XCTAssertFalse(isEligibleForYUV400GrayscaleDecoding(present))
        XCTAssertFalse(isEligibleForYUV400GrayscaleDecoding(plane))
    }

    /// irot / imir 付き YUV400 は transform があるため DeviceGray 経路の対象外であることを検証する。
    func testEligibilityRejectsIROTOrIMIRTransform() {
        let irot = YUV400GrayscaleEligibility(
            yuvFormat: AVIF_PIXEL_FORMAT_YUV400,
            depth: 8,
            alphaPresent: false,
            alphaPlaneIsNull: true,
            transformFlags: AVIF_TRANSFORM_IROT.rawValue
        )
        let imir = YUV400GrayscaleEligibility(
            yuvFormat: AVIF_PIXEL_FORMAT_YUV400,
            depth: 8,
            alphaPresent: false,
            alphaPlaneIsNull: true,
            transformFlags: AVIF_TRANSFORM_IMIR.rawValue
        )
        XCTAssertFalse(isEligibleForYUV400GrayscaleDecoding(irot))
        XCTAssertFalse(isEligibleForYUV400GrayscaleDecoding(imir))
    }

    // MARK: - Limited YUV400 → DeviceGray

    /// limited YUV400 が monochrome / 8bpc / 8bpp / alpha none になり、帯の画素が伸長後期待値になることを検証する。
    ///
    /// 入力 Y=16/126/235 → expandLimitedRangeYToGray8 → 0 / 128 / 255（許容 ±2）。
    func testLimitedYUV400DecodesAsDeviceGrayWithExpandedPixels() throws {
        let data = try loadYUV400Fixture(.limitedGrayRamps)
        let cgImage = try decodeCGImage(data)

        assertDeviceGray8NoAlpha(cgImage)
        XCTAssertEqual(cgImage.colorSpace?.model, .monochrome)
        XCTAssertEqual(cgImage.width, 96)
        XCTAssertEqual(cgImage.height, 64)

        let expectedBlack = expandLimitedRangeYToGray8(16)
        let expectedMid = expandLimitedRangeYToGray8(126)
        let expectedWhite = expandLimitedRangeYToGray8(235)
        XCTAssertEqual(expectedBlack, 0)
        XCTAssertEqual(expectedMid, 128)
        XCTAssertEqual(expectedWhite, 255)

        // 3 bands × 32px; sample band centers on first and last rows.
        assertGrayNear(cgImage, x: 16, y: 0, expected: expectedBlack, tolerance: Self.limitedPixelTolerance)
        assertGrayNear(cgImage, x: 48, y: 0, expected: expectedMid, tolerance: Self.limitedPixelTolerance)
        assertGrayNear(cgImage, x: 80, y: 0, expected: expectedWhite, tolerance: Self.limitedPixelTolerance)
        assertGrayNear(cgImage, x: 16, y: 63, expected: expectedBlack, tolerance: Self.limitedPixelTolerance)
        assertGrayNear(cgImage, x: 48, y: 63, expected: expectedMid, tolerance: Self.limitedPixelTolerance)
        assertGrayNear(cgImage, x: 80, y: 63, expected: expectedWhite, tolerance: Self.limitedPixelTolerance)
    }

    // MARK: - Full YUV400

    /// full-range YUV400 が DeviceGray になり、画素が入力 Y のままであることを検証する。
    func testFullYUV400DecodesAsDeviceGrayPreservingY() throws {
        let data = try loadYUV400Fixture(.fullKnownY)
        let cgImage = try decodeCGImage(data)

        assertDeviceGray8NoAlpha(cgImage)
        XCTAssertEqual(cgImage.width, 100)
        XCTAssertEqual(cgImage.height, 40)

        // 5 bands × 20px: Y = 0 / 64 / 128 / 192 / 255
        let expectedYs: [UInt8] = [0, 64, 128, 192, 255]
        for (index, expected) in expectedYs.enumerated() {
            let x = index * 20 + 10
            assertGrayNear(cgImage, x: x, y: 0, expected: expected, tolerance: Self.fullPixelTolerance)
            assertGrayNear(cgImage, x: x, y: 39, expected: expected, tolerance: Self.fullPixelTolerance)
        }
    }

    // MARK: - Fallbacks (not new path)

    /// YUV420 visual-mono は適格判定に失敗し、フラグ ON/OFF で同等（新経路に入らない）ことを検証する。
    func testYUV420VisualMonoDoesNotTakeDeviceGrayPath() throws {
        XCTAssertFalse(
            isEligibleForYUV400GrayscaleDecoding(
                YUV400GrayscaleEligibility(
                    yuvFormat: AVIF_PIXEL_FORMAT_YUV420,
                    depth: 8,
                    alphaPresent: false,
                    alphaPlaneIsNull: true,
                    transformFlags: AVIF_TRANSFORM_NONE.rawValue
                )
            )
        )

        let data = try loadYUV400Fixture(.visualMono420)

        AvifImageDecoder.yuv400DeviceGrayDecodingEnabled = true
        let onImage = try decodeCGImage(data)
        let onFingerprint = try imageFingerprint(onImage)

        AvifImageDecoder.yuv400DeviceGrayDecodingEnabled = false
        let offImage = try decodeCGImage(data)
        let offFingerprint = try imageFingerprint(offImage)

        XCTAssertEqual(onFingerprint, offFingerprint)

        // YUV420 既存経路は chroma あり → RGB（bpp ≠ 8 の DeviceGray 新経路ではない）。
        XCTAssertNotEqual(onImage.bitsPerPixel, 8)
        XCTAssertFalse(isNewDeviceGrayPath(onImage))
    }

    /// 10bit YUV400 は新経路に入らないことを検証する。
    func testTenBitYUV400DoesNotTakeDeviceGrayPath() throws {
        XCTAssertFalse(
            isEligibleForYUV400GrayscaleDecoding(
                YUV400GrayscaleEligibility(
                    yuvFormat: AVIF_PIXEL_FORMAT_YUV400,
                    depth: 10,
                    alphaPresent: false,
                    alphaPlaneIsNull: true,
                    transformFlags: AVIF_TRANSFORM_NONE.rawValue
                )
            )
        )

        let data = try loadYUV400Fixture(.depth10Fallback)
        assertFlagOnOffEquivalent(data)
    }

    /// alpha 付き YUV400 は新経路に入らず、16bpp（A + Gray）・`.first` になることを検証する。
    ///
    /// DeviceGray 8bpp はアルファを持てないため、既存の monochromeCombine 経路へ落ちる。
    func testAlphaYUV400DoesNotTakeDeviceGrayPath() throws {
        let data = try loadYUV400Fixture(.alphaFallback)

        AvifImageDecoder.yuv400DeviceGrayDecodingEnabled = true
        let onImage = try decodeCGImage(data)
        AvifImageDecoder.yuv400DeviceGrayDecodingEnabled = false
        let offImage = try decodeCGImage(data)

        XCTAssertEqual(try imageFingerprint(onImage), try imageFingerprint(offImage))
        // Alpha 経路は alpha 付きビットマップになる（新経路の alpha none / 8bpp ではない）。
        XCTAssertNotEqual(onImage.alphaInfo, .none)
        XCTAssertFalse(isNewDeviceGrayPath(onImage))
    }

    /// アルファ付き YUV400 が 8bit 成分 × 2（`.first`）でデコードされ、アルファ帯が残ることを検証する。
    ///
    /// フィクスチャは A=255 / 128 / 0 の帯。limited 伸長後も不透明・半透明・透明が混在する。
    /// カラー+アルファの本番フィクスチャは未同梱のため、透過の画素確認はこのファイルで行う。
    func testAlphaYUV400DecodesSixteenBitAlphaFirstLayoutWithVaryingAlpha() throws {
        let data = try loadYUV400Fixture(.alphaFallback)
        let image = try decodeCGImage(data)

        XCTAssertEqual(image.width, 64)
        XCTAssertEqual(image.height, 32)
        XCTAssertEqual(image.bitsPerComponent, 8)
        XCTAssertEqual(image.bitsPerPixel, 16)
        XCTAssertEqual(image.alphaInfo, .first)
        XCTAssertEqual(image.colorSpace?.model, .monochrome)
        XCTAssertFalse(isNewDeviceGrayPath(image))

        var alphas: [UInt8] = []
        let stepX = max(1, image.width / 8)
        let stepY = max(1, image.height / 4)
        for y in stride(from: 0, to: image.height, by: stepY) {
            for x in stride(from: 0, to: image.width, by: stepX) {
                alphas.append(alphaGrayPixel(image, x: x, y: y).alpha)
            }
        }

        let uniqueAlphas = Set(alphas)
        XCTAssertGreaterThanOrEqual(uniqueAlphas.count, 2, "alpha plane should not be opaque-only: \(uniqueAlphas)")
        XCTAssertGreaterThanOrEqual(alphas.max() ?? 0, 200, "expected a near-opaque alpha band")
        XCTAssertLessThanOrEqual(alphas.min() ?? 255, 30, "expected a near-transparent alpha band")
    }

    // MARK: - Odd width

    /// 奇数幅 1179 でもクラッシュせず、幅と帯の画素（行ずれなし）を検証する。
    func testOddWidth1179DecodesWithoutRowShift() throws {
        let data = try loadYUV400Fixture(.oddWidth1179)
        let cgImage = try decodeCGImage(data)

        assertDeviceGray8NoAlpha(cgImage)
        XCTAssertEqual(cgImage.width, 1179)
        XCTAssertEqual(cgImage.height, 32)

        let expectedBlack = expandLimitedRangeYToGray8(16)
        let expectedMid = expandLimitedRangeYToGray8(126)
        let expectedWhite = expandLimitedRangeYToGray8(235)
        // 3 bands × 393px
        let sampleRows = [0, 15, 31]
        for y in sampleRows {
            assertGrayNear(cgImage, x: 196, y: y, expected: expectedBlack, tolerance: Self.limitedPixelTolerance)
            assertGrayNear(cgImage, x: 589, y: y, expected: expectedMid, tolerance: Self.limitedPixelTolerance)
            assertGrayNear(cgImage, x: 982, y: y, expected: expectedWhite, tolerance: Self.limitedPixelTolerance)
        }
    }

    // MARK: - Concurrency

    /// 複数スレッド同時 decode でもクラッシュ・値化けしないことを検証する。
    func testConcurrentDecodeMatchesReferenceBytes() throws {
        let data = try loadYUV400Fixture(.limitedGrayRamps)
        let referenceImage = try decodeCGImage(data)
        let reference = try XCTUnwrap(referenceImage.dataProvider?.data as Data?)

        let iterations = 8
        let lock = NSLock()
        var failures: [String] = []

        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            do {
                guard let image = try AvifImageDecoder().decode(data).image.cgImage,
                      let bytes = image.dataProvider?.data as Data? else {
                    lock.lock()
                    failures.append("iteration \(index): missing image bytes")
                    lock.unlock()
                    return
                }
                if bytes != reference {
                    lock.lock()
                    failures.append("iteration \(index): byte mismatch")
                    lock.unlock()
                }
            } catch {
                lock.lock()
                failures.append("iteration \(index): \(error)")
                lock.unlock()
            }
        }

        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "; "))
    }

    // MARK: - Flag OFF → legacy path

    /// フラグ OFF 時、適格 YUV400 でも既存経路でデコードできることを検証する。
    ///
    /// 新経路は CICP monochrome（本フィクスチャは BT709 / sRGB）を使う。
    /// 既存経路も YUV400 では monochrome 8bpp になり得るため、画素／model だけでは区別しない。
    func testFlagOffUsesLegacyPathForEligibleYUV400() throws {
        let data = try loadYUV400Fixture(.limitedGrayRamps)

        AvifImageDecoder.yuv400DeviceGrayDecodingEnabled = true
        let onImage = try decodeCGImage(data)
        assertDeviceGray8NoAlpha(onImage)
        // limited gray-ramps は Color Primaries=1 / Transfer=13 → CICP 生成が成功し DeviceGray フォールバックに落ちない。
        XCTAssertNotEqual(
            onImage.colorSpace?.name as String?,
            CGColorSpaceCreateDeviceGray().name as String?,
            "ON path should use CICP monochrome, not DeviceGray fallback"
        )

        AvifImageDecoder.yuv400DeviceGrayDecodingEnabled = false
        let offImage = try decodeCGImage(data)
        XCTAssertEqual(offImage.width, onImage.width)
        XCTAssertEqual(offImage.height, onImage.height)
        // オプトアウト後もデコード成功（既存 converter 経路）。
        XCTAssertNotNil(offImage.dataProvider?.data)
    }

    // MARK: - Helpers

    private func loadYUV400Fixture(_ fixture: Fixture) throws -> Data {
        // `.process("Fixtures")` flattens nested files into the resource bundle root.
        // Prefer subdirectory when preserved (e.g. `.copy`); fall back to root.
        let fixtureURL = Bundle.module.url(
            forResource: fixture.rawValue,
            withExtension: "avif",
            subdirectory: "YUV400"
        ) ?? Bundle.module.url(
            forResource: fixture.rawValue,
            withExtension: "avif"
        )
        return try Data(contentsOf: try XCTUnwrap(fixtureURL))
    }

    private func decodeCGImage(_ data: Data) throws -> CGImage {
        let container = try AvifImageDecoder().decode(data)
        return try XCTUnwrap(container.image.cgImage)
    }

    private func assertDeviceGray8NoAlpha(_ image: CGImage, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(image.bitsPerComponent, 8, file: file, line: line)
        XCTAssertEqual(image.bitsPerPixel, 8, file: file, line: line)
        XCTAssertEqual(image.alphaInfo, .none, file: file, line: line)
        XCTAssertEqual(image.colorSpace?.model, .monochrome, file: file, line: line)
    }

    /// 新経路の典型属性（monochrome / 8 / 8 / none）。
    private func isNewDeviceGrayPath(_ image: CGImage) -> Bool {
        image.bitsPerComponent == 8
            && image.bitsPerPixel == 8
            && image.alphaInfo == .none
            && image.colorSpace?.model == .monochrome
    }

    private func assertGrayNear(
        _ image: CGImage,
        x: Int,
        y: Int,
        expected: UInt8,
        tolerance: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actual = grayPixel(image, x: x, y: y)
        let delta = abs(Int(actual) - Int(expected))
        XCTAssertLessThanOrEqual(
            delta,
            tolerance,
            "pixel(\(x),\(y))=\(actual) expected~\(expected) (±\(tolerance))",
            file: file,
            line: line
        )
    }

    private func grayPixel(_ image: CGImage, x: Int, y: Int) -> UInt8 {
        precondition(image.bitsPerPixel == 8)
        guard let data = image.dataProvider?.data else {
            XCTFail("missing data provider")
            return 0
        }
        let ptr = CFDataGetBytePtr(data)!
        return ptr[y * image.bytesPerRow + x]
    }

    /// 16bpp `.first`（[A, Gray]）から 1 画素のアルファと輝度を読む。
    private func alphaGrayPixel(_ image: CGImage, x: Int, y: Int) -> (alpha: UInt8, gray: UInt8) {
        XCTAssertEqual(image.bitsPerPixel, 16)
        XCTAssertEqual(image.alphaInfo, .first)
        guard let data = image.dataProvider?.data else {
            XCTFail("missing data provider")
            return (0, 0)
        }
        let pointer = CFDataGetBytePtr(data)!
        let offset = y * image.bytesPerRow + x * 2
        return (pointer[offset], pointer[offset + 1])
    }

    private func imageFingerprint(_ image: CGImage) throws -> Data {
        var payload = Data()
        payload.append(contentsOf: withUnsafeBytes(of: image.width) { Array($0) })
        payload.append(contentsOf: withUnsafeBytes(of: image.height) { Array($0) })
        payload.append(contentsOf: withUnsafeBytes(of: image.bitsPerComponent) { Array($0) })
        payload.append(contentsOf: withUnsafeBytes(of: image.bitsPerPixel) { Array($0) })
        payload.append(contentsOf: withUnsafeBytes(of: image.alphaInfo.rawValue) { Array($0) })
        let name = (image.colorSpace?.name as String?) ?? ""
        payload.append(contentsOf: name.utf8)
        if let bytes = image.dataProvider?.data as Data? {
            payload.append(bytes)
        }
        return payload
    }

    private func assertFlagOnOffEquivalent(_ data: Data, file: StaticString = #filePath, line: UInt = #line) {
        AvifImageDecoder.yuv400DeviceGrayDecodingEnabled = true
        let onResult = Result { try decodeCGImage(data) }
        AvifImageDecoder.yuv400DeviceGrayDecodingEnabled = false
        let offResult = Result { try decodeCGImage(data) }

        switch (onResult, offResult) {
        case (.success(let onImage), .success(let offImage)):
            do {
                XCTAssertEqual(
                    try imageFingerprint(onImage),
                    try imageFingerprint(offImage),
                    file: file,
                    line: line
                )
                XCTAssertFalse(isNewDeviceGrayPath(onImage), file: file, line: line)
            } catch {
                XCTFail("fingerprint failed: \(error)", file: file, line: line)
            }
        case (.failure(let onError), .failure(let offError)):
            XCTAssertEqual(
                String(describing: onError),
                String(describing: offError),
                file: file,
                line: line
            )
        default:
            XCTFail("ON/OFF decode outcome mismatch: on=\(onResult) off=\(offResult)", file: file, line: line)
        }
    }
}
