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

func getAllProcesses() -> [RunningProcess] {
	// https://gist.github.com/kainjow/0e7650cc797a52261e0f4ba851477c2f
	// https://ops.tips/blog/macos-pid-absolute-path-and-procfs-exploration/
	let initialNumPids = PROC_PIDPATHINFO_SIZE
	let buffer = UnsafeMutablePointer<pid_t>.allocate(capacity: Int(initialNumPids) + 20)
	defer { buffer.deallocate() }
	let bufferLength = initialNumPids * Int32(MemoryLayout<pid_t>.size)
	print(initialNumPids)
	// Call the function again with our inputs now ready
	let numPids = proc_listallpids(buffer, bufferLength)
	var out: [RunningProcess] = []
	
	var parentMap = [Int:[Int]]()

	for x in 0..<numPids {
		// pid number
		let pid = buffer[Int(x)]
		
		// path of process
		let pathBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(MAXPATHLEN))
		defer { pathBuffer.deallocate() }
		proc_pidpath(pid, pathBuffer, UInt32(MAXPATHLEN))
		
		// name of process
		let nameBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(MAXPATHLEN))
		defer { nameBuffer.deallocate() }
		proc_name(pid, nameBuffer, UInt32(MAXPATHLEN))
		
		// get all children, and mark them for later
		let childBufferLen = Int(PROC_PIDPATHINFO_SIZE)
		let childBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: childBufferLen)
		defer { childBuffer.deallocate() }
		proc_listchildpids(pid, childBuffer, Int32(childBufferLen))
		let ipid = Int(pid)
		for y in 0..<childBufferLen {
			let childPid = childBuffer[Int(y)]
			if parentMap[ipid] == nil {
				parentMap[ipid] = []
			}
			parentMap[ipid]!.append(Int(childPid))
		}
		
		// put it all together
		out.append(RunningProcess(
					pid: Int(pid),
					path: String(cString: pathBuffer),
					name: String(cString: nameBuffer)
		))
	}
	return out
}

func getAllProcessesByCLI() -> [RunningProcess] {
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
	if (out.count == 0) {
		// nothing running? maybe we were sandboxed, we can fallback to the running apps
		let workspace = NSWorkspace.shared
		print("Falling back to running apps")
		out = workspace.runningApplications
	}
	return out.map { RunningProcess(
		pid: Int($0.processIdentifier),
		path: $0.executableURL?.absoluteString ?? "unknown",
		name: $0.localizedName ?? "Unknown"
	) }
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
		 var path = app.path
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
		out.append("(\(app.pid)) - \(app.name)")
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
