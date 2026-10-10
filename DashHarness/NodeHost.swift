import Darwin
import Foundation

/// 用 posix_spawn 拉起内嵌的 Node 运行 `@deepseek-ai/dsh web`，
/// 监听 127.0.0.1:3280（iOS 无 NSTask/Process，只能用 posix_spawn）。
/// dsh 启动时会在 stdout 打印一次带 ?token= 的根 URL，我们捕获它做首访换 cookie。
final class NodeHost {
    static let shared = NodeHost()
    let port = 3280
    private var nodePID: pid_t = -1
    private(set) var serverLogPath: String = ""

    private var baseURL: URL {
        URL(string: "http://127.0.0.1:\(port)")!
    }

    var isRunning: Bool { nodePID > 0 }

    @discardableResult
    func start() -> Bool {
        guard nodePID <= 0 else { return true }

        guard let bin = Bundle.main.path(forResource: "node", ofType: nil, inDirectory: "node"),
              let dshRoot = Bundle.main.path(forResource: "dsh", ofType: nil, inDirectory: nil) else {
            NSLog("[NodeHost] 资源缺失: node 或 dsh")
            return false
        }
        let entry = dshRoot + "/node_modules/@deepseek-ai/dsh/lib/bin.js"
        let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first
            ?? NSHomeDirectory()
        let tmp = NSTemporaryDirectory()
        serverLogPath = docs + "/dsh-server.log"

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

        // stdout/stderr 重定向到日志文件（posix_spawn_file_actions）
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        if let a = actions {
            _ = serverLogPath.withCString { path in
                posix_spawn_file_actions_addopen(&a, 1, path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
                    + posix_spawn_file_actions_addopen(&a, 2, path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
            }
        }

        let pid = UnsafeMutablePointer<pid_t>.allocate(capacity: 1)
        defer { pid.deallocate() }

        let r = posix_spawn(pid, bin, actions, nil, &cargv, &cenv)
        if let a = actions { posix_spawn_file_actions_destroy(&a) }
        if r == 0 {
            nodePID = pid.pointee
            NSLog("[NodeHost] spawned pid=%d log=%@", nodePID, serverLogPath)
            return true
        } else {
            NSLog("[NodeHost] posix_spawn 失败 errno=%d", r)
            nodePID = -1
            return false
        }
    }

    func stop() {
        if nodePID > 0 { kill(nodePID, SIGTERM); nodePID = -1 }
    }

    /// 从服务器日志提取启动 token
    func launchToken() -> String? {
        guard !serverLogPath.isEmpty,
              let content = try? String(contentsOfFile: serverLogPath, encoding: .utf8) else { return nil }
        let patterns = [
            "token=([A-Za-z0-9_-]{6,})",
            "\\?token=([A-Za-z0-9_-]{6,})",
        ]
        for p in patterns {
            if let range = content.range(of: p, options: .regularExpression) {
                var token = String(content[range])
                if let eq = token.firstIndex(of: "=") {
                    token = String(token[token.index(after: eq)...])
                }
                if !token.isEmpty { return token }
            }
        }
        return nil
    }

    /// 带 token 的启动 URL（用于首访换 cookie）
    func launchURL() -> URL? {
        guard let t = launchToken() else { return baseURL }
        return URL(string: "http://127.0.0.1:\(port)/?token=\(t)")
    }

    func waitUntilReady(timeout: TimeInterval = 90) -> Bool {
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