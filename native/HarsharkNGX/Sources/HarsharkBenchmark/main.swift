import Foundation
import Darwin
import HarsharkCore

func residentBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return status == KERN_SUCCESS ? info.resident_size : 0
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: harshark-benchmark FILE.har\n".utf8))
    exit(2)
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])
var result: [String: Any] = ["file": url.lastPathComponent, "resident_before": residentBytes()]
try autoreleasepool {
    let started = Date()
    let archive = try HARParser().read(from: url)
    let rows = archive.entries.map(HARRow.init)
    result["import_seconds"] = Date().timeIntervalSince(started)
    result["entries"] = rows.count
    result["resident_loaded"] = residentBytes()
    let filterStart = Date()
    let matches = rows.filter { $0.matches("example.test") }
    result["filter_seconds"] = Date().timeIntervalSince(filterStart)
    result["matches"] = matches.count
    let sortStart = Date()
    let sorted = rows.sorted { $0.duration < $1.duration }
    result["sort_seconds"] = Date().timeIntervalSince(sortStart)
    result["sorted_count"] = sorted.count
    let previewStart = Date()
    if let entry = archive.entries.first {
        let detail = HARFormatter.bodyDetail(entry.responseBody, pretty: true)
        result["preview_chars"] = detail.text.count
        result["preview_notice"] = detail.notice
    }
    result["preview_seconds"] = Date().timeIntervalSince(previewStart)
    result["resident_inspected"] = residentBytes()
}
result["resident_after_release"] = residentBytes()
var usage = rusage()
getrusage(RUSAGE_SELF, &usage)
result["peak_resident_bytes"] = usage.ru_maxrss
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
