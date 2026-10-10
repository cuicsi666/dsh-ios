import Darwin
import Foundation

/// 用 posix_spawn 拉起内嵌的 Node 运行 `@deepseek-ai/dsh web`，
/// 监听 127.0.0.1:3280（iOS 无 NSTask/Process，只能用 posix_spawn）。
final class NodeHost {
    static let shared = NodeHost()
    let port = 3280
    private var nodePID: pid_t = -1

    private var baseURL: URL {
        URL(string: "http://127.0.0.1:\(port)")!
    }

    var isRunning: Bool { nodePID > 0 }

    /// 启动内嵌 dsh。返回启动是否发起（不代表已就绪，就绪用 waitUntilReady）
    @discardableResult
    func start() -> Bool {
        guard nodePID <= 0 else { return true }

        guard let bin = Bundle.main.path(forResource: "node", ofType: nil, inDirectory: "node"),
              let dshRoot = Bundle.main.path(forResource: "dsh", ofType: nil, inDirectory: nil) else {
            NSLog("[NodeHost] 资源缺失: node 或 dsh 目录")
            return false
        }
        let entry = dshRoot + "/node_modules/@deepseek-ai/dsh/lib/bin.js"
        let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first
            ?? NSHomeDirectory()
        let tmp = NSTemporaryDirectory()

        var argv = [bin, entry, "web", "--no-open", "--port", "\(port)"]
        var cargv: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
        cargv.append(nil)
        defer { cargv.forEach { if let p = $0 { free(p) } } }

        let env = [
            "HOME=\(docs)",
            "TMPDIR=\(tmp)",
            "TMP=\(tmp)",
            "TEMP=\(tmp)",
            "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
            "NODE_ENV=production",
            "DSH_BASE=\(dshRoot)",
            "DSH_WORKSPACE=\(docs)",
            "DSH_HOME=\(docs)",
        ]
        var cenv: [UnsafeMutablePointer<CChar>?] = env.map { strdup($0) }
        cenv.append(nil)
        defer { cenv.forEach { if let p = $0 { free(p) } } }

        let pid = UnsafeMutablePointer<pid_t>.allocate(capacity: 1)
        defer { pid.deallocate() }

        let r = posix_spawn(pid, bin, nil, nil, &cargv, &cenv)
        if r == 0 {
            nodePID = pid.pointee
            NSLog("[NodeHost] 已 spawn node pid=%d", nodePID)
            return true
        } else {
            NSLog("[NodeHost] posix_spawn 失败 errno=%d", r)
            nodePID = -1
            return false
        }
    }

    func stop() {
        if nodePID > 0 {
            kill(nodePID, SIGTERM)
            nodePID = -1
        }
    }

    /// 轮询直到 HTTP 就绪（超时秒数）
    func waitUntilReady(timeout: TimeInterval = 60) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if healthCheck() { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return healthCheck()
    }

    func healthCheck() -> Bool {
        var req = URLRequest(url: baseURL, timeoutInterval: 2)
        req.httpMethod = "GET"
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        URLSession.shared.dataTask(with: req) { _, resp, err in
            if err == nil, let r = resp as? HTTPURLResponse,
               (100..<500).contains(r.statusCode) { ok = true }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 3)
        return ok
    }
}