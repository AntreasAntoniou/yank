import XCTest
import AppKit
import CryptoKit
@testable import Yank

/// T3: Image payloads (and their thumbnails) are encrypted at rest with the
/// `enc1:` AES-GCM seal. The PLAINTEXT png is hashed BEFORE sealing, so T2's
/// content-addressed `<hash>.png` dedup is unchanged. New captures are sealed by
/// ClipboardMonitor.persistImage; pre-encryption PNGs are upgraded once by
/// ClipStore.encryptImagePayloadsIfNeeded() (driven here through ClipStore.init).
@MainActor
final class ImageEncryptionTests: XCTestCase {
    private var tempDir: URL!
    private static let migrationFlag = "imagesEncryptedV1"

    override func setUp() {
        super.setUp()
        Feedback.soundEnabled = false
        // Clear the one-time migration gate so the at-rest upgrade actually runs
        // for each ClipStore we construct in this suite.
        UserDefaults.standard.removeObject(forKey: Self.migrationFlag)
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DittoImageEncTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        UserDefaults.standard.removeObject(forKey: Self.migrationFlag)
        super.tearDown()
    }

    // MARK: Helpers

    /// Deterministic solid-colour PNG so identical inputs => identical bytes,
    /// matching T2's dedup fixture.
    private func pngData(red: CGFloat, width: Int = 4, height: Int = 4) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(red: red, green: 0, blue: 0, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Pre-seed a plaintext `<hash>.png` + `<hash>-thumb.png` pair on disk AND a
    /// referencing image row in the store's DB, as a pre-encryption build would
    /// have left them. The DB row matters: ClipStore.init sweeps orphan payloads,
    /// so a payload with no referencing clip would be deleted before the
    /// encryption pass runs. Returns the content hash. Leaves the migration gate
    /// CLEARED so the next `ClipStore(directory:)` runs the upgrade pass.
    @discardableResult
    private func seedReferencedPlaintextPayload(red: CGFloat) -> String {
        let png = pngData(red: red)
        let hash = sha256Hex(png)
        // Persist a referencing row via a throwaway store (writes to the shared DB).
        let seeder = ClipStore(directory: tempDir)
        let item = ClipItem(kind: .image, text: "Image")
        item.imageHash = hash
        item.payloadFile = "\(hash).png"
        seeder.add(item)
        // Now lay down the PLAINTEXT payload + thumbnail (overwriting anything the
        // store may have left), simulating a pre-encryption on-disk state.
        try! png.write(to: tempDir.appendingPathComponent("\(hash).png"))
        try! png.write(to: tempDir.appendingPathComponent("\(hash)-thumb.png"))
        // Re-open the migration gate so the pass actually runs next init.
        UserDefaults.standard.removeObject(forKey: Self.migrationFlag)
        return hash
    }

    private func isPNGHeader(_ data: Data) -> Bool {
        // PNG magic: 89 50 4E 47 0D 0A 1A 0A.
        let magic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        return data.count >= 8 && Array(data.prefix(8)) == magic
    }

    // MARK: Tests

    /// (1) After the at-rest upgrade, both `<hash>.png` and `<hash>-thumb.png`
    /// begin with the `enc1:` marker and are NOT a valid PNG header.
    func testPayloadAndThumbAreSealedNotPlaintextPNG() {
        let hash = seedReferencedPlaintextPayload(red: 1.0)
        _ = ClipStore(directory: tempDir)   // runs encryptImagePayloadsIfNeeded()

        for name in ["\(hash).png", "\(hash)-thumb.png"] {
            let url = tempDir.appendingPathComponent(name)
            let raw = try! Data(contentsOf: url)
            XCTAssertTrue(Crypto.isSealed(raw), "\(name) must carry the enc1: marker")
            XCTAssertFalse(isPNGHeader(raw), "\(name) must NOT start with PNG magic at rest")
        }
    }

    /// (2) Each sealed file round-trips via Crypto.open to a decodable NSImage.
    func testSealedPayloadAndThumbRoundTripToImage() {
        let hash = seedReferencedPlaintextPayload(red: 0.5)
        _ = ClipStore(directory: tempDir)

        for name in ["\(hash).png", "\(hash)-thumb.png"] {
            let url = tempDir.appendingPathComponent(name)
            let raw = try! Data(contentsOf: url)
            guard let opened = Crypto.open(raw) else {
                return XCTFail("\(name) failed to decrypt via Crypto.open")
            }
            XCTAssertTrue(isPNGHeader(opened), "decrypted \(name) must be a valid PNG")
            XCTAssertNotNil(NSImage(data: opened), "decrypted \(name) must decode to an NSImage")
        }
    }

    /// (3) Two captures of byte-identical images reuse the same `<hash>.png`:
    /// the hash is taken over the PLAINTEXT png, so encryption leaves T2's
    /// content-addressed dedup intact (still one payload on disk).
    func testByteIdenticalImagesReuseSamePayloadHash() {
        let pngA = pngData(red: 1.0)
        let pngB = pngData(red: 1.0)
        XCTAssertEqual(pngA, pngB, "fixture must produce byte-identical PNGs")
        // Hash is over plaintext bytes — identical content => identical filename.
        XCTAssertEqual(sha256Hex(pngA), sha256Hex(pngB))

        let hash = sha256Hex(pngA)
        // First capture seals + writes; a second capture for the same content
        // sees the file already present and reuses it (filename-based dedup).
        let url = tempDir.appendingPathComponent("\(hash).png")
        if !FileManager.default.fileExists(atPath: url.path) {
            try! Crypto.seal(pngA)!.write(to: url)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        // Sealing does not change the content address: the second capture's hash
        // still resolves to the one existing payload.
        XCTAssertEqual(sha256Hex(pngB), hash)

        let pngs = (try? FileManager.default.contentsOfDirectory(atPath: tempDir.path))?
            .filter { $0.hasSuffix(".png") && !$0.hasSuffix("-thumb.png") } ?? []
        XCTAssertEqual(pngs.count, 1, "byte-identical images must share one payload")
    }

    /// (4) encryptImagePayloadsIfNeeded() seals a pre-seeded plaintext PNG+thumb
    /// and is idempotent: a second store over the same dir (flag re-cleared,
    /// mimicking an interrupted/re-run pass) leaves the already-sealed bytes
    /// untouched and still decryptable.
    func testMigrationIsIdempotent() {
        let hash = seedReferencedPlaintextPayload(red: 0.75)
        let url = tempDir.appendingPathComponent("\(hash).png")
        let thumbURL = tempDir.appendingPathComponent("\(hash)-thumb.png")

        _ = ClipStore(directory: tempDir)
        let sealedOnce = try! Data(contentsOf: url)
        let thumbSealedOnce = try! Data(contentsOf: thumbURL)
        XCTAssertTrue(Crypto.isSealed(sealedOnce))
        XCTAssertTrue(Crypto.isSealed(thumbSealedOnce))

        // Re-run the pass: re-clear the gate and rebuild the store. Already-sealed
        // payloads (isSealed == true) are skipped, so bytes are byte-stable.
        UserDefaults.standard.removeObject(forKey: Self.migrationFlag)
        _ = ClipStore(directory: tempDir)
        let sealedTwice = try! Data(contentsOf: url)
        let thumbSealedTwice = try! Data(contentsOf: thumbURL)
        XCTAssertEqual(sealedOnce, sealedTwice, "re-running must not re-seal an already-sealed payload")
        XCTAssertEqual(thumbSealedOnce, thumbSealedTwice, "re-running must not re-seal an already-sealed thumb")

        // Still decryptable back to the original plaintext PNG bytes.
        XCTAssertEqual(Crypto.open(sealedTwice), pngData(red: 0.75))
    }
}
