import XCTest
import Nuke
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
}
