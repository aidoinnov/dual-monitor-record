import Foundation

let commands = ["start", "stop", "toggle", "status", "open", "reveal"]
let command = CommandLine.arguments.dropFirst().first ?? "help"

guard commands.contains(command) else {
    print("Usage: dualrec <start|stop|toggle|status|open|reveal>")
    exit(command == "help" ? 0 : 2)
}

let routes: [String: (String, String)] = [
    "start": ("POST", "/v1/recording/start"),
    "stop": ("POST", "/v1/recording/stop"),
    "toggle": ("POST", "/v1/recording/toggle"),
    "status": ("GET", "/v1/status"),
    "open": ("POST", "/v1/latest/open"),
    "reveal": ("POST", "/v1/latest/reveal")
]

let route = routes[command]!
var request = URLRequest(url: URL(string: "http://127.0.0.1:17842\(route.1)")!)
request.httpMethod = route.0
let semaphore = DispatchSemaphore(value: 0)
var resultCode = 1

URLSession.shared.dataTask(with: request) { data, response, error in
    defer { semaphore.signal() }
    if let error {
        fputs("dualrec: 앱이 실행 중인지 확인하세요. \(error.localizedDescription)\n", stderr)
        return
    }
    if let data, let text = String(data: data, encoding: .utf8) { print(text) }
    if let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) { resultCode = 0 }
}.resume()

_ = semaphore.wait(timeout: .now() + 10)
exit(Int32(resultCode))
