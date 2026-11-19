#if !canImport(simd)
func simd_length(_ v: SIMD2<Float>) -> Float { (v * v).sum().squareRoot() }
func simd_length(_ v: SIMD3<Float>) -> Float { (v * v).sum().squareRoot() }
func simd_dot(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { (a * b).sum() }
func simd_dot(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { (a * b).sum() }
func simd_normalize(_ v: SIMD3<Float>) -> SIMD3<Float> { v / simd_length(v) }
func simd_cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}
#endif
