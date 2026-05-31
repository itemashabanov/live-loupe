import Darwin
import Foundation

struct LocalNetworkEndpoint: Identifiable, Hashable {
    let id: String
    let interfaceName: String
    let address: String
    let title: String
}

enum NetworkAddress {
    static func localHostname() -> String? {
        let rawName = ProcessInfo.processInfo.hostName
        guard !rawName.isEmpty else { return nil }
        return rawName.hasSuffix(".local") ? rawName : "\(rawName).local"
    }

    static func primaryIPv4Address() -> String? {
        ipv4Endpoints().first?.address
    }

    static func ipv4Endpoints() -> [LocalNetworkEndpoint] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else {
            return []
        }

        defer { freeifaddrs(interfaces) }

        var candidates: [LocalNetworkEndpoint] = []

        for pointer in sequence(first: firstInterface, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let flags = Int32(interface.ifa_flags)

            guard flags & IFF_UP == IFF_UP,
                  flags & IFF_LOOPBACK == 0,
                  interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            let name = String(cString: interface.ifa_name)
            guard !name.hasPrefix("utun"),
                  !name.hasPrefix("awdl"),
                  !name.hasPrefix("llw"),
                  !name.hasPrefix("bridge") else {
                continue
            }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            guard result == 0 else { continue }
            let address = hostname.withUnsafeBufferPointer { buffer -> String in
                guard let baseAddress = buffer.baseAddress else { return "" }
                return String(cString: baseAddress)
            }

            candidates.append(
                LocalNetworkEndpoint(
                    id: "\(name)-\(address)",
                    interfaceName: name,
                    address: address,
                    title: title(forInterface: name, address: address)
                )
            )
        }

        return candidates.sorted { left, right in
            let leftPriority = priority(for: left)
            let rightPriority = priority(for: right)

            if leftPriority == rightPriority {
                return left.interfaceName.localizedStandardCompare(right.interfaceName) == .orderedAscending
            }

            return leftPriority < rightPriority
        }
    }

    private static func priority(for endpoint: LocalNetworkEndpoint) -> Int {
        if endpoint.address.hasPrefix("172.20.10.") {
            return 0
        }

        if endpoint.interfaceName == "en0" {
            return 1
        }

        if endpoint.address.hasPrefix("169.254.") {
            return 2
        }

        if endpoint.interfaceName.hasPrefix("en") {
            return 3
        }

        return 4
    }

    private static func title(forInterface interfaceName: String, address: String) -> String {
        if address.hasPrefix("172.20.10.") {
            return "iPhone Hotspot"
        }

        if interfaceName == "en0" {
            return "Wi-Fi"
        }

        if address.hasPrefix("169.254.") {
            return "Cable Link"
        }

        return interfaceName
    }
}
