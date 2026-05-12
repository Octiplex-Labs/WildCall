import Foundation

public enum BlockStoreFormat {
    public static let blockMagic: [UInt8] = Array("WCB1".utf8)
    public static let identMagic: [UInt8] = Array("WCI1".utf8)
    public static let version: UInt32 = 1

    // WCB1 header layout (16 bytes):
    //   [0..4)   magic "WCB1"
    //   [4..8)   version u32
    //   [8..16)  count   u64
    //   [16...)  count × Int64 sorted ascending
    public static let blockHeaderSize = 16

    // WCI1 header layout (24 bytes):
    //   [0..4)   magic "WCI1"
    //   [4..8)   version          u32
    //   [8..16)  count            u64
    //   [16..24) stringTableOffset u64
    //   followed by: count × Int64 sorted ascending
    //   followed by: count × u32 label offsets into string table
    //   followed by: string table (each entry = u32 length + UTF-8 bytes)
    public static let identHeaderSize = 24
}
