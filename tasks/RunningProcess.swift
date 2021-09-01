import Foundation

class RunningProcess
{
	let pid: Int
	let path: String
	let name: String

	init(pid: Int, path: String, name: String) {
		self.pid = pid
		self.path = path
		self.name = name
	}
}
