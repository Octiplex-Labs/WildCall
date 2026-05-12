import Foundation

public enum BlockStoreFormat {
    public static let blockMagic: [UInt8] = Array("WCB1".utf8)
    public static let identMagic: [UInt8] = Array("WCI1".utf8)
    public static let version: UInt32 = 1
}
