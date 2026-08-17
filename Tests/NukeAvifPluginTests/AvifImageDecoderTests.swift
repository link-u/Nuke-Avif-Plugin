import CoreGraphics
import Nuke
import XCTest
@testable import NukeAvifPlugin

/// AvifImageDecoder および ImageDecoderRegistry 連携の回帰テスト。
///
/// フィクスチャ:
/// - 本番相当: manga-up CDN 由来の cavif / avifenc × gray / yuv420 / yuv422 / yuv444（8種）
/// - エッジケース: fox（monochrome, odd-size）— 本番 8 種ではカバーしないレイアウト境界用
final class AvifImageDecoderTests: XCTestCase {
    /// manga-up 検証用 AVIF（Tests/NukeAvifPluginTests/Fixtures に同梱）
    private enum ProductionFixture: String, CaseIterable {
        case cavifGray = "test_cavif_gray"
        case cavifYUV420 = "test_cavif_yuv420"
        case cavifYUV422 = "test_cavif_yuv422"
        case cavifYUV444 = "test_cavif_yuv444"
        case avifencGray = "test_avifenc_gray"
        case avifencYUV420 = "test_avifenc_yuv420"
        case avifencYUV422 = "test_avifenc_yuv422"
        case avifencYUV444 = "test_avifenc_yuv444"

        /// アルファなしカラー（YUV420/422/444）。gray はモノクロ経路のため除外。
        static var colorNoAlpha: [ProductionFixture] {
            [.cavifYUV420, .cavifYUV422, .cavifYUV444, .avifencYUV420, .avifencYUV422, .avifencYUV444]
        }
    }

    private static let foxFixtureName = "fox.profile0.8bpc.yuv420.monochrome.odd-width.odd-height"
    private static let registrySampleFixture = ProductionFixture.cavifYUV420

    private var foxAvifData: Data!
    private var jpegHeaderData: Data!
    private var pngHeaderData: Data!

    /// 各テスト実行前に共通データを読み込む。
    /// - foxAvifData: 奇数サイズ monochrome エッジケース用（fox 専用テストのみ使用）
    /// - jpegHeaderData / pngHeaderData: 非 AVIF 判定用の先頭バイト列
    override func setUpWithError() throws {
        foxAvifData = try loadFixture(named: Self.foxFixtureName)
        jpegHeaderData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        pngHeaderData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    /// Bundle から AVIF フィクスチャを読み込む。
    private func loadFixture(named resourceName: String) throws -> Data {
        let fixtureURL = try XCTUnwrap(
            Bundle.module.url(forResource: resourceName, withExtension: "avif")
        )
        return try Data(contentsOf: fixtureURL)
    }

    // MARK: - Production fixtures (8種)

    /// 本番相当 8 種すべてで `Data.isAvifData` が true になることを検証する。
    ///
    /// cavif / avifenc それぞれの gray・yuv420・yuv422・yuv444 が
    /// libavif の `avifPeekCompatibleFileType` で AVIF と判定されることを確認する。
    func testIsAvifDataReturnsTrueForProductionFixtures() throws {
        for fixture in ProductionFixture.allCases {
            let data = try loadFixture(named: fixture.rawValue)
            try XCTContext.runActivity(named: fixture.rawValue) { _ in
                XCTAssertTrue(data.isAvifData)
            }
        }
    }

    /// 本番相当 8 種すべてを `AvifImageDecoder.decode` できることを検証する。
    ///
    /// - type が `.avif` であること
    /// - プレビューではないこと (`isPreview == false`)
    /// - 画像サイズが 0 より大きいこと
    func testDecodeProducesImageContainerForProductionFixtures() throws {
        let decoder = AvifImageDecoder()

        for fixture in ProductionFixture.allCases {
            let data = try loadFixture(named: fixture.rawValue)
            try XCTContext.runActivity(named: fixture.rawValue) { _ in
                let container = try decoder.decode(data)

                XCTAssertEqual(container.type, AssetType.avif)
                XCTAssertFalse(container.isPreview)
                XCTAssertGreaterThan(container.image.size.width, 0)
                XCTAssertGreaterThan(container.image.size.height, 0)
            }
        }
    }

    /// 本番相当 8 種すべてで registry が AvifImageDecoder を返し、デコードできることを検証する。
    ///
    /// ダウンロード完了 (`isCompleted == true`) かつ AVIF データの場合に
    /// Nuke 13 の registry → decode フローが通ることを確認する。
    func testRegistryDecodesProductionFixtures() throws {
        ImageDecoderRegistry.shared.clear()
        AvifImageDecoder.enable()

        for fixture in ProductionFixture.allCases {
            let data = try loadFixture(named: fixture.rawValue)
            try XCTContext.runActivity(named: fixture.rawValue) { _ in
                let context = ImageDecodingContext(
                    request: ImageRequest(url: URL(string: "https://example.com/\(fixture.rawValue).avif")!),
                    data: data,
                    isCompleted: true
                )

                let decoder = try XCTUnwrap(ImageDecoderRegistry.shared.decoder(for: context))
                XCTAssertTrue(decoder is AvifImageDecoder)

                let container = try decoder.decode(data)
                XCTAssertEqual(container.type, AssetType.avif)
                XCTAssertGreaterThan(container.image.size.width, 0)
                XCTAssertGreaterThan(container.image.size.height, 0)
            }
        }
    }

    // MARK: - Registry edge cases

    /// ダウンロード途中 (`isCompleted == false`) の AVIF では、プログレッシブ非対応のため registry が nil を返すことを検証する。
    /// Nuke 13 推奨: 完了前はデコーダーを登録しない。代表として本番相当フィクスチャ 1 種で確認する。
    func testRegistryReturnsNilForPartialAvifContext() throws {
        ImageDecoderRegistry.shared.clear()
        AvifImageDecoder.enable()

        let data = try loadFixture(named: Self.registrySampleFixture.rawValue)
        let context = ImageDecodingContext(
            request: ImageRequest(url: URL(string: "https://example.com/\(Self.registrySampleFixture.rawValue).avif")!),
            data: data,
            isCompleted: false
        )

        XCTAssertNil(ImageDecoderRegistry.shared.decoder(for: context))
    }

    /// ダウンロード完了でも非 AVIF データの場合、registry が nil を返すことを検証する。
    /// JPEG 等が誤って AvifImageDecoder に渡らないことを確認する。
    func testRegistryReturnsNilForCompletedNonAvifContext() {
        ImageDecoderRegistry.shared.clear()
        AvifImageDecoder.enable()

        let context = ImageDecodingContext(
            request: ImageRequest(url: URL(string: "https://example.com/image.jpg")!),
            data: jpegHeaderData,
            isCompleted: true
        )

        XCTAssertNil(ImageDecoderRegistry.shared.decoder(for: context))
    }

    // MARK: - Format detection

    /// JPEG / PNG / 空データに対して `Data.isAvifData` が false を返すことを検証する。
    /// 誤って AVIF デコーダーが選択されないためのネガティブテスト。
    func testIsAvifDataReturnsFalseForNonAvifData() {
        XCTAssertFalse(jpegHeaderData.isAvifData)
        XCTAssertFalse(pngHeaderData.isAvifData)
        XCTAssertFalse(Data().isAvifData)
    }

    // MARK: - Fox edge case (odd-size monochrome)

    /// fox フィクスチャに対して `Data.isAvifData` が true を返すことを検証する。
    /// 奇数 width/height の monochrome AVIF でもフォーマット判定が通ることを確認する。
    func testIsAvifDataReturnsTrueForFoxFixture() {
        XCTAssertTrue(foxAvifData.isAvifData)
    }

    /// fox フィクスチャを `AvifImageDecoder.decode` できることを検証する。
    ///
    /// 本番 8 種ではカバーしない odd-width / odd-height monochrome の decode 経路を確認する。
    /// - type が `.avif` であること
    /// - プレビューではないこと (`isPreview == false`)
    /// - 画像サイズが 0 より大きいこと
    func testDecodeProducesImageContainerForFoxFixture() throws {
        let container = try AvifImageDecoder().decode(foxAvifData)

        XCTAssertEqual(container.type, AssetType.avif)
        XCTAssertFalse(container.isPreview)
        XCTAssertGreaterThan(container.image.size.width, 0)
        XCTAssertGreaterThan(container.image.size.height, 0)
    }

    // MARK: - Color decode (no alpha)

    /// アルファなしカラー 6 種が RGB 色空間の 32bpp XRGB（`.noneSkipFirst`）になることを検証する。
    ///
    /// 現行コンバータは ARGB8888 を RGB888 に切り出さず、先頭バイトをスキップして渡す。
    /// gray フィクスチャは DeviceGray 経路のため対象外。
    func testColorFixturesDecodeAsThirtyTwoBitXRGBWithoutAlpha() throws {
        for fixture in ProductionFixture.colorNoAlpha {
            let image = try decodeCGImage(named: fixture.rawValue)
            XCTAssertEqual(image.bitsPerComponent, 8, fixture.rawValue)
            XCTAssertEqual(image.bitsPerPixel, 32, fixture.rawValue)
            XCTAssertEqual(image.alphaInfo, .noneSkipFirst, fixture.rawValue)
            XCTAssertEqual(image.colorSpace?.model, .rgb, fixture.rawValue)
            XCTAssertGreaterThan(image.width, 0, fixture.rawValue)
            XCTAssertGreaterThan(image.height, 0, fixture.rawValue)
        }
    }

    /// アルファなしカラー 6 種の dataProvider が XRGB（[X,R,G,B]）として読め、単色塗りではないことを検証する。
    ///
    /// 四隅と中央をサンプリングし、全点が同一 RGB ならデコード失敗（白飛び・黒潰れ）とみなす。
    func testColorFixturesHaveReadableRGBPixelsAndAreNotFlat() throws {
        for fixture in ProductionFixture.colorNoAlpha {
            let image = try decodeCGImage(named: fixture.rawValue)
            let samples = sampleCornerAndCenterRGB(image)
            XCTAssertEqual(samples.count, 5, fixture.rawValue)
            let unique = Set(samples.map { "\($0.r),\($0.g),\($0.b)" })
            XCTAssertGreaterThan(
                unique.count,
                1,
                "\(fixture.rawValue) decoded as a flat fill \(samples[0])"
            )
        }
    }

    // MARK: - Helpers

    /// フィクスチャ名から decode し、UIImage 配下の CGImage を取り出す。
    private func decodeCGImage(named resourceName: String) throws -> CGImage {
        let data = try loadFixture(named: resourceName)
        let container = try AvifImageDecoder().decode(data)
        return try XCTUnwrap(container.image.cgImage)
    }

    /// 32bpp `.noneSkipFirst` バッファから 1 画素の RGB を読む（先頭バイトは無視）。
    private func rgbPixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        XCTAssertEqual(image.bitsPerPixel, 32)
        XCTAssertEqual(image.alphaInfo, .noneSkipFirst)
        guard let data = image.dataProvider?.data else {
            XCTFail("missing data provider")
            return (0, 0, 0)
        }
        let pointer = CFDataGetBytePtr(data)!
        let offset = y * image.bytesPerRow + x * 4
        return (pointer[offset + 1], pointer[offset + 2], pointer[offset + 3])
    }

    /// 四隅と中央の 5 点を XRGB として読む。
    private func sampleCornerAndCenterRGB(_ image: CGImage) -> [(r: UInt8, g: UInt8, b: UInt8)] {
        let maxX = image.width - 1
        let maxY = image.height - 1
        let midX = image.width / 2
        let midY = image.height / 2
        return [
            rgbPixel(image, x: 0, y: 0),
            rgbPixel(image, x: maxX, y: 0),
            rgbPixel(image, x: 0, y: maxY),
            rgbPixel(image, x: maxX, y: maxY),
            rgbPixel(image, x: midX, y: midY)
        ]
    }
}
