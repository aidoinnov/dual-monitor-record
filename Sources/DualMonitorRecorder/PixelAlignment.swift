enum PixelAlignment {
    static func size(_ value: Int) -> Int { max(2, value / 2 * 2) }
    static func coordinate(_ value: Int) -> Int { max(0, value / 2 * 2) }
}
