// Copyright (c) 2022 and onwards The McBopomofo Authors.
//
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use,
// copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following
// conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.

import XCTest
import SwiftEngine

final class UTF8HelperTests: XCTestCase {
    func testGetCodePoint1() {
        let s = "一二三四"
        let r = UTF8Helper.getCodePoint(s, 2)
        XCTAssertEqual(r, "三")
    }

    func testGetCodePoint2() {
        let s = "ABCD"
        let r = UTF8Helper.getCodePoint(s, 2)
        XCTAssertEqual(r, "C")
    }

    func testGetCodePoint3() {
        let s = "11\u{1F333}1"
        let r = UTF8Helper.getCodePoint(s, 2)
        XCTAssertEqual(r, "\u{1F333}")
    }

    func testGetCodePoint4() {
        let s = "\u{1F333}\u{1F333}1\u{1F333}"
        let r = UTF8Helper.getCodePoint(s, 2)
        XCTAssertEqual(r, "1")
    }
}
