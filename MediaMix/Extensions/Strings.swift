extension String {
    func getStableRepresentation() -> Int {
        return self.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    }
}
