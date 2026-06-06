//  LargestRemainderAllocatorTests.swift
//  ProWorkTests
//  KDV toplamını line bazına dağıtmak için kullanılan
//  generic largest-remainder allocator'ın sum-preservation ve dağılım
//  doğruluğunu garanti eder.

import XCTest
@testable import ProWork

final class LargestRemainderAllocatorTests: XCTestCase {

    func test_emptyWeights_returnsEmpty() {
        XCTAssertEqual(LargestRemainderAllocator.allocate(total: 100, weights: []), [])
    }

    func test_zeroTotal_returnsZeros() {
        XCTAssertEqual(
            LargestRemainderAllocator.allocate(total: 0, weights: [10, 20, 30]),
            [0, 0, 0]
        )
    }

    func test_negativeTotal_returnsZeros() {
        XCTAssertEqual(
            LargestRemainderAllocator.allocate(total: -5, weights: [10, 20, 30]),
            [0, 0, 0]
        )
    }

    func test_allWeightsZero_dumpsTotalIntoFirstSlot() {
        // Sum korunmalı; ağırlık 0 ise tek belirleyici slot ilk pozisyon.
        XCTAssertEqual(
            LargestRemainderAllocator.allocate(total: 42, weights: [0, 0, 0]),
            [42, 0, 0]
        )
    }

    func test_negativeWeights_areClampedToZero() {
        let result = LargestRemainderAllocator.allocate(total: 60, weights: [-10, 30, 30])
        XCTAssertEqual(result.reduce(0, +), 60)
        XCTAssertEqual(result[0], 0, "Negatif ağırlık 0 sayılmalı")
    }

    func test_evenDivision_preservesTotal() {
        let result = LargestRemainderAllocator.allocate(total: 99, weights: [33, 33, 33])
        XCTAssertEqual(result.reduce(0, +), 99)
        XCTAssertEqual(Set(result), [33])
    }

    func test_remainderGoesToLargestRemainder() {
        // total=20, weights=[33,33,33]:
        //   her slot 20*33/99 = 6.66 → quotient 6, remainder 660/99 ≈ 6.66
        //   tüm remainder'lar eşit → stable: en küçük index'ten başla.
        //   2 kalan minor → index 0 ve 1.
        let result = LargestRemainderAllocator.allocate(total: 20, weights: [33, 33, 33])
        XCTAssertEqual(result.reduce(0, +), 20)
        XCTAssertEqual(result, [7, 7, 6])
    }

    func test_unevenWeights_distributesProportionally() {
        // total=100, weights=[1,2,7]: hedef ≈ [10, 20, 70].
        let result = LargestRemainderAllocator.allocate(total: 100, weights: [1, 2, 7])
        XCTAssertEqual(result.reduce(0, +), 100)
        XCTAssertEqual(result, [10, 20, 70])
    }

    func test_totalIsAlwaysPreserved_acrossManyShapes() {
        // Property-style smoke: bir dizi şekil için toplam korunmalı.
        let cases: [(total: Int, weights: [Int])] = [
            (1, [1, 1, 1]),
            (7, [1, 2, 3]),
            (1000, [12, 7, 91, 4]),
            (3, [0, 0, 5]),
            (50, [25, 25]),
            (999, Array(repeating: 1, count: 13))
        ]
        for c in cases {
            let r = LargestRemainderAllocator.allocate(total: c.total, weights: c.weights)
            XCTAssertEqual(r.reduce(0, +), c.total, "Sum bozuldu: \(c)")
            XCTAssertEqual(r.count, c.weights.count)
            XCTAssertTrue(r.allSatisfy { $0 >= 0 })
        }
    }
}
