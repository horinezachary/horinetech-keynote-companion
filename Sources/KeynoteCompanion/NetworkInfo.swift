import Darwin
import Foundation

enum NetworkInfo {
    /// This Mac's IPv4 addresses, excluding loopback and link-local, for showing in the menu.
    static func ipv4Addresses() -> [String] {
        var result: [String] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            let flags = Int32(ifa.ifa_flags)
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0
            else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard
                getnameinfo(
                    addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0,
                    NI_NUMERICHOST) == 0
            else { continue }
            let ip = String(cString: host)
            if !ip.hasPrefix("169.254."), !result.contains(ip) {
                result.append(ip)
            }
        }
        return result
    }
}
