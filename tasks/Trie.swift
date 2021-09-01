//import Foundation
//
//class Trie
//{
//	var data = [Character: Trie]()
//	var containsMatch = false
//
//	func insert(_ word: String) {
//		if let nextLetter = word.first {
//			if !data[nextLetter] {
//				// create a new trie here
//				data[nextLetter] = Trie()
//			}
//		}
//		else {
//			// no next letter, this is the end of the word
//			containsMatch = true
//		}
//	}
//	
//	func startsWith(_ prefix: String) -> Bool
//}
