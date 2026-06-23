import Foundation

enum TestData {

    static func shapefileUrl(package: String, name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("TestData")
            .appendingPathComponent(package)
            .appendingPathComponent(name)
    }

}
