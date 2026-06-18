//
//  PCA2DProjector.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import Accelerate
import Foundation
import simd

/// PCA -> 2D projection using BLAS + LAPACK (ssyev on covariance matrix).
/// Returns N coords in arbitrary scale; normalize afterwards.
struct PCA2DProjector: Projector2D {
    func project(_ vectors: [[Float]]) -> [SIMD2<Float>] {
        let n = vectors.count
        guard n >= 2 else { return vectors.map { _ in SIMD2<Float>(0, 0) } }
        let d = vectors.first?.count ?? 0
        guard d >= 2 else { return vectors.map { _ in SIMD2<Float>(0, 0) } }

        // Mean per dimension
        var mean = [Float](repeating: 0, count: d)
        for j in 0 ..< d {
            var s: Float = 0
            for i in 0 ..< n {
                s += vectors[i][j]
            }
            mean[j] = s / Float(n)
        }

        // X as column-major (d x n): column i = centered vector of point i
        var X = [Float](repeating: 0, count: d * n)
        for i in 0 ..< n {
            let colBase = i * d
            for j in 0 ..< d {
                X[colBase + j] = vectors[i][j] - mean[j]
            }
        }

        // Covariance C = (1/(n-1)) * X * X^T (d x d), column-major
        var C = [Float](repeating: 0, count: d * d)
        let alpha: Float = 1.0 / max(1.0, Float(n - 1))
        let beta: Float = 0.0

        cblas_sgemm(
            CblasColMajor,
            CblasNoTrans,
            CblasTrans,
            Int32(d),
            Int32(d),
            Int32(n),
            alpha,
            X,
            Int32(d),
            X,
            Int32(d),
            beta,
            &C,
            Int32(d)
        )

        // Eigen decomposition of symmetric covariance C (ssyev)
        var jobz: Int8 = 86 // 'V' eigenvalues+eigenvectors
        var uplo: Int8 = 85 // 'U' upper triangle stored
        var N = Int32(d)
        var lda = Int32(d)
        var w = [Float](repeating: 0, count: d)

        // Workspace query
        var lwork: Int32 = -1
        var workQuery: Float = 0
        var info: Int32 = 0

        ssyev_(&jobz, &uplo, &N, &C, &lda, &w, &workQuery, &lwork, &info)
        lwork = Int32(workQuery)
        var work = [Float](repeating: 0, count: Int(max(1, lwork)))

        ssyev_(&jobz, &uplo, &N, &C, &lda, &w, &work, &lwork, &info)

        guard info == 0 else {
            // Fall back to zeros
            return vectors.map { _ in SIMD2<Float>(0, 0) }
        }

        // Eigenvalues are ascending; top PCs are last columns
        let pc1Col = d - 1
        let pc2Col = d - 2

        var out: [SIMD2<Float>] = []
        out.reserveCapacity(n)

        for i in 0 ..< n {
            var y1: Float = 0
            var y2: Float = 0
            let xBase = i * d

            for r in 0 ..< d {
                let xr = X[xBase + r]
                y1 += C[pc1Col * d + r] * xr
                y2 += C[pc2Col * d + r] * xr
            }

            out.append(SIMD2<Float>(y1, y2))
        }

        return out
    }
}
