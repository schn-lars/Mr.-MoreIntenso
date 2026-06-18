/// Single-slot buffer needed for CPVixelBuffer

actor AtomicBuffer<T> {
    private var value: T? = nil
    
    func store(_ newValue: T) {
        value = newValue
    }
    
    func take() -> T? {
        defer { value = nil }
        return value
    }
    
    func peek() -> T? {
        return value
    }
}
