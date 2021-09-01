import SwiftUI
import Darwin


func delete() {
	print("Hello")
}

let prefix = "file://"

func isSymlinkOrNonexistent(path: String) -> Bool {
	let url = URL(fileURLWithPath: path)
	if let ok = try? url.checkResourceIsReachable(), ok {
		let vals = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
		return vals?.isSymbolicLink ?? true
	}
	return true
}

func getAllProcesses() -> [NSRunningApplication] {
	let task = Process()
	task.executableURL = URL(fileURLWithPath: "/bin/ps")
	task.arguments = ["ax", "-o", "pid"]
	let outputPipe = Pipe()
	task.standardOutput = outputPipe
	try? task.run()
	let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
	let resp = String(decoding: outputData, as: UTF8.self)
	
	var out: [NSRunningApplication] = []
	for line in resp.components(separatedBy: "\n") {
		if line == "PID" {
			continue
		}
		let pid = Int32(line.trimmingCharacters(in: .whitespaces)) ?? 1
		if let app = NSRunningApplication(processIdentifier: pid) {
			out.append(app)
		}
	}
	print(out.count)
	if (out.count == 0) {
		// nothing running? maybe we were sandboxed, we can fallback to the running apps
		let workspace = NSWorkspace.shared
		print("Falling back to running apps")
		return workspace.runningApplications
	}
	return out
}

struct ContentView: View {
	var protectedDirs = Set<String>()
	var unsafeDirs = Set<String>()
	var processList: [String] = []
	
	func getAllTasks(filtered: Bool) -> [String] {
	let applications = getAllProcesses()
	print("Count")
	print(applications.count)
		 
	 var out: [String] = []
	 for app in applications {
		 var path = app.executableURL?.absoluteString ?? "unknown"
		 if path.hasPrefix(prefix) {
			 path = String(path.dropFirst(prefix.count))
		 }
		 if filtered {
			 // if it belongs to a path that contains a prefix in the set of protected files, ignore it
			 // so check all parts of the path
			 let comps = path.components(separatedBy: "/")
			 var isSafe = false
			 var curPrefix = ""
			 for comp in comps {
				if curPrefix == "/" {
					curPrefix += comp
				} else {
					curPrefix += "/\(comp)"
				}
//				print("Checking for ", curPrefix)
				if protectedDirs.contains(curPrefix) {
					isSafe = true
				}
				if unsafeDirs.contains(curPrefix) {
					isSafe = false
				}
				// don't break early, always allow it to become safe or unsafe depending on the path
				// TODO: (alternatively, come from the back and do break early?)
			 }
			if isSafe {
				// skip this from the listing
				continue
			}
		 }
//		 out.append(path)
		out.append("(\(app.processIdentifier)) - \(app.localizedName ?? "Unknown")")
	 }
	 return out
 }

	mutating func updateLists(filename: String) {
		let data = FileManager.default.contents(atPath: filename) ?? Data()
		let contents = String(decoding: data, as: UTF8.self)
		let lines = contents.components(separatedBy: "\n")
		for line in lines {
			let parts = line.components(separatedBy: "\t")
			let first = parts.first ?? "*"
			let last = parts.last ?? "unknown"
			if first == "" && !isSymlinkOrNonexistent(path: last) {
				// this a safe path! It has no first component, and the last one is an existing non-sym link
				print("Safe: ", last)
				self.protectedDirs.insert(last)
			} else {
				// we don't like it, maybe it's "*" wildcard, maybe something else, but either way we don't want it
				self.unsafeDirs.insert(last)
			}
		}
	}
	
	init() {
		updateLists(filename: "/System/Library/Sandbox/rootless.conf")
		processList = getAllTasks(filtered: true)
	}
    var body: some View {
		List(processList, id:\.self) { Text($0) }
		.navigationTitle("Tasks")
		.toolbar {
//			Button(
//				"Show System",
//			   action: delete
//			)
			Button(
				"End Task",
			   action: delete
			)
		}
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
