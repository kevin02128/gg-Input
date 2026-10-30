import Foundation
import Darwin

public final class PhraseDB: LanguageModel {
    private static let sortedPragmaHeader = "# format org.openvanilla.mcbopomofo.sorted\n"

    private var fileDescriptor: Int32 = -1
    private var mappedPointer: UnsafeMutableRawPointer? = nil
    private var fileSize: Int = 0
    private var ownedNSData: NSData? = nil

    private var bufferBegin: UnsafePointer<UInt8>? = nil
    private var bufferEnd: UnsafePointer<UInt8>? = nil

    public init() {}

    deinit {
        close()
    }

    public var isLoaded: Bool {
        bufferBegin != nil && bufferEnd != nil && bufferBegin! < bufferEnd!
    }

    public func open(path: String) -> Bool {
        close()

        let fd = Darwin.open(path, O_RDONLY)
        guard fd >= 0 else {
            return false
        }

        var statInfo = stat()
        guard fstat(fd, &statInfo) == 0, statInfo.st_size > 0 else {
            Darwin.close(fd)
            return false
        }

        let size = Int(statInfo.st_size)
        let ptr = Darwin.mmap(nil, size, PROT_READ, MAP_SHARED, fd, 0)
        guard ptr != MAP_FAILED, let mapped = ptr else {
            Darwin.close(fd)
            return false
        }

        self.fileDescriptor = fd
        self.mappedPointer = mapped
        self.fileSize = size

        let typedPtr = mapped.bindMemory(to: UInt8.self, capacity: size)
        var begin = UnsafePointer<UInt8>(typedPtr)
        let end = begin.advanced(by: size)

        let headerBytes = Array(Self.sortedPragmaHeader.utf8)
        if size >= headerBytes.count && memcmp(begin, headerBytes, headerBytes.count) == 0 {
            begin = begin.advanced(by: headerBytes.count)
        } else {
            close()
            return false
        }

        self.bufferBegin = begin
        self.bufferEnd = end
        return true
    }

    public func open(data: Data) -> Bool {
        close()
        guard !data.isEmpty else { return false }
        let nsData = data as NSData
        self.ownedNSData = nsData

        let typedPtr = nsData.bytes.bindMemory(to: UInt8.self, capacity: nsData.length)
        var begin = UnsafePointer<UInt8>(typedPtr)
        let end = begin.advanced(by: nsData.length)

        let headerBytes = Array(Self.sortedPragmaHeader.utf8)
        if nsData.length >= headerBytes.count && memcmp(begin, headerBytes, headerBytes.count) == 0 {
            begin = begin.advanced(by: headerBytes.count)
        }
        self.bufferBegin = begin
        self.bufferEnd = end
        return true
    }

    public func close() {
        if let mapped = mappedPointer {
            Darwin.munmap(mapped, fileSize)
            mappedPointer = nil
        }
        if fileDescriptor >= 0 {
            Darwin.close(fileDescriptor)
            fileDescriptor = -1
        }
        fileSize = 0
        ownedNSData = nil
        bufferBegin = nil
        bufferEnd = nil
    }

    // MARK: - LanguageModel protocol
    public func getUnigrams(reading: String) -> [Unigram] {
        guard let begin = bufferBegin, let end = bufferEnd, begin < end else {
            return []
        }

        let searchKey = reading + " "
        let keyBytes = Array(searchKey.utf8)
        guard let matchStart = findFirstMatchingLine(keyBytes: keyBytes, begin: begin, end: end) else {
            return []
        }

        var unigrams: [Unigram] = []
        var ptr = matchStart

        while ptr.advanced(by: keyBytes.count) <= end && memcmp(ptr, keyBytes, keyBytes.count) == 0 {
            // Find end of current line
            var eol = ptr
            while eol < end && eol.pointee != 0x0A { // '\n'
                eol = eol.advanced(by: 1)
            }

            // Parse line: <reading> <value> <score>
            var valPtr = ptr.advanced(by: keyBytes.count)
            while valPtr < eol && valPtr.pointee == 0x20 { // ' '
                valPtr = valPtr.advanced(by: 1)
            }

            var valEnd = valPtr
            while valEnd < eol && valEnd.pointee != 0x20 {
                valEnd = valEnd.advanced(by: 1)
            }

            let valLen = valEnd - valPtr
            if valLen > 0 {
                let valueStr = String(decoding: UnsafeBufferPointer(start: valPtr, count: valLen), as: UTF8.self)

                var scorePtr = valEnd
                while scorePtr < eol && scorePtr.pointee == 0x20 {
                    scorePtr = scorePtr.advanced(by: 1)
                }

                let scoreLen = eol - scorePtr
                var score = 0.0
                if scoreLen > 0 {
                    score = Self.parseAsciiDouble(start: scorePtr, end: eol)
                }

                let tags = POSTagDictionary.resolve(word: valueStr)
                unigrams.append(Unigram(value: valueStr, score: score, primaryPOS: tags.primary, secondaryPOS: tags.secondary))
            }

            if eol == end {
                break
            }
            ptr = eol.advanced(by: 1)
        }

        return unigrams
    }

    public func hasUnigrams(reading: String) -> Bool {
        guard let begin = bufferBegin, let end = bufferEnd, begin < end else {
            return false
        }
        let searchKey = reading + " "
        let keyBytes = Array(searchKey.utf8)
        return findFirstMatchingLine(keyBytes: keyBytes, begin: begin, end: end) != nil
    }

    public func findRows(prefix: String) -> [String] {
        guard let begin = bufferBegin, let end = bufferEnd, begin < end else {
            return []
        }
        let keyBytes = Array(prefix.utf8)
        guard let matchStart = findFirstMatchingLine(keyBytes: keyBytes, begin: begin, end: end) else {
            return []
        }

        var rows: [String] = []
        var ptr = matchStart
        while ptr.advanced(by: keyBytes.count) <= end && memcmp(ptr, keyBytes, keyBytes.count) == 0 {
            var eol = ptr
            while eol < end && eol.pointee != 0x0A {
                eol = eol.advanced(by: 1)
            }
            let lineStr = String(decoding: UnsafeBufferPointer(start: ptr, count: eol - ptr), as: UTF8.self)
            rows.append(lineStr)
            if eol == end { break }
            ptr = eol.advanced(by: 1)
        }
        return rows
    }

    public func reverseFindRows(value: String) -> [(reading: String, score: Double)] {
        guard let begin = bufferBegin, let end = bufferEnd, begin < end else {
            return []
        }
        var results: [(reading: String, score: Double)] = []
        var ptr = begin
        let valBytes = Array((value + " ").utf8)

        while ptr < end {
            var eol = ptr
            while eol < end && eol.pointee != 0x0A {
                eol = eol.advanced(by: 1)
            }

            var space1 = ptr
            while space1 < eol && space1.pointee != 0x20 {
                space1 = space1.advanced(by: 1)
            }

            var valStart = space1
            while valStart < eol && valStart.pointee == 0x20 {
                valStart = valStart.advanced(by: 1)
            }

            if valStart.advanced(by: valBytes.count) <= eol && memcmp(valStart, valBytes, valBytes.count) == 0 {
                let reading = String(decoding: UnsafeBufferPointer(start: ptr, count: space1 - ptr), as: UTF8.self)
                let scoreStart = valStart.advanced(by: valBytes.count)
                var score = 0.0
                if scoreStart < eol {
                    score = Self.parseAsciiDouble(start: scoreStart, end: eol)
                }
                results.append((reading: reading, score: score))
            }

            if eol == end { break }
            ptr = eol.advanced(by: 1)
        }
        return results
    }

    // MARK: - Binary Search
    private func findLineStart(begin: UnsafePointer<UInt8>, position: UnsafePointer<UInt8>) -> UnsafePointer<UInt8> {
        var cursor = position
        while cursor > begin {
            cursor = cursor.advanced(by: -1)
            if cursor.pointee == 0x0A { // '\n'
                return cursor.advanced(by: 1)
            }
        }
        return begin
    }

    private func findFirstMatchingLine(keyBytes: [UInt8],
                                       begin: UnsafePointer<UInt8>,
                                       end: UnsafePointer<UInt8>) -> UnsafePointer<UInt8>? {
        if keyBytes.isEmpty {
            return begin
        }

        var top = begin
        var bottom = end
        let keyLen = keyBytes.count

        while top < bottom {
            let mid = top.advanced(by: (bottom - top) / 2)
            let ptr = findLineStart(begin: begin, position: mid)

            if ptr.advanced(by: keyLen) > end {
                break
            }

            let cmp = memcmp(ptr, keyBytes, keyLen)
            if cmp > 0 {
                bottom = mid.advanced(by: -1)
                continue
            }
            if cmp < 0 {
                top = mid.advanced(by: 1)
                continue
            }

            if ptr == begin {
                return ptr
            }

            let prevLineEnd = ptr.advanced(by: -1)
            let prevLineStart = findLineStart(begin: begin, position: prevLineEnd)

            if prevLineStart.advanced(by: keyLen) <= end && memcmp(prevLineStart, keyBytes, keyLen) == 0 {
                bottom = mid.advanced(by: -1)
            } else {
                return ptr
            }
        }

        return nil
    }

    private static func parseAsciiDouble(start: UnsafePointer<UInt8>, end: UnsafePointer<UInt8>) -> Double {
        var ptr = start
        while ptr < end && (ptr.pointee == 0x20 || ptr.pointee == 0x09) {
            ptr = ptr.advanced(by: 1)
        }
        guard ptr < end else { return 0.0 }

        var isNegative = false
        if ptr.pointee == 0x2D { // '-'
            isNegative = true
            ptr = ptr.advanced(by: 1)
        } else if ptr.pointee == 0x2B { // '+'
            ptr = ptr.advanced(by: 1)
        }

        var integerPart: Double = 0.0
        while ptr < end && ptr.pointee >= 0x30 && ptr.pointee <= 0x39 {
            integerPart = integerPart * 10.0 + Double(ptr.pointee - 0x30)
            ptr = ptr.advanced(by: 1)
        }

        var fractionPart: Double = 0.0
        var divisor: Double = 1.0
        if ptr < end && ptr.pointee == 0x2E { // '.'
            ptr = ptr.advanced(by: 1)
            while ptr < end && ptr.pointee >= 0x30 && ptr.pointee <= 0x39 {
                fractionPart = fractionPart * 10.0 + Double(ptr.pointee - 0x30)
                divisor *= 10.0
                ptr = ptr.advanced(by: 1)
            }
        }

        let value = integerPart + (fractionPart / divisor)
        return isNegative ? -value : value
    }
}
