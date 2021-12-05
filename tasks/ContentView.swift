import SwiftUI
import Darwin

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
//	print(initialNumPids)
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
//		print("Falling back to running apps")
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
    
    @State var processList: [String]
    @State var task: String = ""
    @State var hideSystem: Bool = true
	
	func getAllTasks(filtered: Bool) -> [String] {
        let applications = getAllProcesses()
		 
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
         let paths = app.path.split(separator: "/")
         let pathName = paths.count > 0 ? paths[paths.count - 1] : "Unknown"
         out.append("(\(app.pid)) - \(app.name) - [\(pathName)]")
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
//				print("Safe: ", last)
				self.protectedDirs.insert(last)
			} else {
				// we don't like it, maybe it's "*" wildcard, maybe something else, but either way we don't want it
				self.unsafeDirs.insert(last)
			}
		}
	}
	
	init() {
        _processList = State(initialValue: [])
		updateLists(filename: "/System/Library/Sandbox/rootless.conf")
		let procs = getAllTasks(filtered: hideSystem)
        _processList = State(initialValue: procs)
        
//        DispatchQueue.main.async {
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [self] timer in
            self.processList = getAllTasks(filtered: hideSystem)
        }
//        }
	}
        
    var body: some View {
		List(processList, id:\.self) { task in
            // https://stackoverflow.com/a/63181274
            HStack {
                Text(task)
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                self.task = task
            }
            .listRowBackground(self.task == task ? Color.accentColor : Color(NSColor.clear))
        }
		.navigationTitle("Tasks")
		.toolbar {
			Toggle(
				"Hide Protected",
			   isOn: $hideSystem
			)
                .onChange(of: hideSystem) { value in
                    processList = getAllTasks(filtered: hideSystem)
                }
//            Button(
//                "Refresh",
//                action: {
//                    processList = getAllTasks(filtered: hideSystem)
//                }
//            )
			Button(
				"End Task",
                action: self.delete
			)
                .disabled(self.task == "")
		}
    }
    
    func delete() {
        // TODO: use a data structure instead of storing strings and unpacking
        // https://stackoverflow.com/questions/36941365/swift-regex-for-extracting-words-between-parenthesis
        let pids = matches(for: "^\\((?=.{0,10}\\)).*?\\)", in: self.task)
        let pid = pids[0].trimmingCharacters(in: ["(", ")"])
       
        // https://stackoverflow.com/questions/45701825/kill-process-in-swift
        // https://unix.stackexchange.com/a/102865
        let pipe = Pipe()
        let task = Process()
        task.launchPath = "/usr/bin/command"
        task.arguments = ["kill", "-9", pid]
        task.standardOutput = pipe
        task.standardError = pipe
        task.launch()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        processList = getAllTasks(filtered: hideSystem)
        self.task = ""
        if let output = String(data: data, encoding: .utf8) {
            if output != "" {
                let alert = NSAlert()
                alert.messageText = output
                alert.addButton(withTitle: "OK")
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

// https://stackoverflow.com/questions/27880650/swift-extract-regex-matches
func matches(for regex: String, in text: String) -> [String] {

    do {
        let regex = try NSRegularExpression(pattern: regex)
        let results = regex.matches(in: text,
                                    range: NSRange(text.startIndex..., in: text))
        return results.map {
            String(text[Range($0.range, in: text)!])
        }
    } catch let error {
//        print("invalid regex: \(error.localizedDescription)")
        return []
    }
}
