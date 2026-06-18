import Foundation

/**
    Singleton for storing class names of YOLOWorld-Detection.
 */
final class Constants {
    static let shared = Constants()
    
    private let classes = ["accessory", "acorn", "aftershave", "airbag", "album", "alcohol", "alligator", "alpaca", "alpenhorn", "angel", "antelope", "antique", "ape", "appetiser", "architecture", "ark", "arm", "armadillo", "armor", "arrow", "art", "artichoke", "ashtray", "avocado", "award", "baby", "bacon", "bag", "bagpipe", "balloon", "bandanna", "banjo", "banner", "baseball", "basil", "basin", "basketball", "bat", "bathtub", "bean", "bear", "beaver", "bee", "beer", "beet", "bell", "belt", "bench", "berry", "bike", "bikini", "bird", "boat", "bongo", "book", "bra", "bracelet", "bread", "bridge", "broccoli", "brownie", "bucket", "blackboard", "bug", "bull", "cable", "cake", "candy", "cannon", "cat", "car", "cereal", "chain", "chair", "chart", "cheese", "chess", "chicken", "chorus", "church", "cigarette", "clock", "coffee", "coffin", "coin", "computer", "cup", "cookie", "crow", "daisy", "dancer", "deer", "deodorant", "desk", "dessert", "device", "dinosaur", "dish", "dishwasher", "display", "dog", "doll", "dolphin", "doughnut", "dress", "drink", "drum", "duck", "dwarf", "eagle", "earth", "elephant", "elf", "faucet", "feather", "feature", "ferret", "fondue", "football", "frog", "go-kart", "graffiti", "greenhouse", "grenade", "gun", "hammer", "hammock", "hamster", "hand", "headphones", "hotdog", "ice-cream", "jacket", "jar", "jellyfish", "jewel", "kangaroo", "kebab", "kettle", "keyboard", "kiwi", "lasagna", "laptop", "lemon", "lemur", "leopard", "logo", "man", "melon", "meme", "mouse", "muffin", "newspaper", "notebook", "pancake", "pants", "pepper", "pepperoni", "pencil", "perfume", "phone", "photo", "photograph", "pig", "pillow", "pizza", "plane", "plant", "poppy", "pot", "poster", "pumpkin", "puppet", "purse", "rabbit", "refrigerator", "robe", "robot", "sailboat", "salami", "salmon", "salsa", "saxophone", "scarecrow", "scarf", "seagull", "seaplane", "shampoo", "shark", "shirt", "shoe", "shovel", "skeleton", "ski", "skirt", "skunk", "sloth", "snake", "sofa", "spider", "statue", "sticker", "sushi", "sweater", "taco", "tandem", "tangerine", "tank", "tent", "toast", "tool", "toothbrush", "top-hat", "towel", "train", "tree", "trumpet", "turtle", "tuxedo", "van", "vinyl", "violin", "volleyball", "wasp", "woman", "wombat", "wood", "woodchuck", "zebrafish", "zucchini"]
    
    func getClassAt(_ idx: Int) -> String {
        return idx < getNumberOfClasses() ? classes[idx] : "UNKNOWN"
    }
    
    func getNumberOfClasses() -> Int {
        return classes.count
    }
}
