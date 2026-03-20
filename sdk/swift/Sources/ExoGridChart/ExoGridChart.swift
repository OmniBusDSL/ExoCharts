import Foundation
import CExoGridChart

public struct Tick {
    public let price: Float
    public let size: Float
    public let side: UInt8
    public let timestampNs: UInt64
    public let exchangeId: UInt32
    public let tickerId: UInt8
}

public struct MatrixStats {
    public let ticksProcessed: UInt64
    public let totalVolume: UInt64
    public let exchangeTicks: [UInt64]
}

public typealias TickCallback = (Tick) -> Void

public class ExoGridChart {
    private var callback: TickCallback?

    public static let shared = ExoGridChart()

    private init() {
        _ = exo_init()
    }

    deinit {
        exo_deinit()
    }

    public func start(exchanges: UInt32 = 0x7, callback: @escaping TickCallback) throws {
        self.callback = callback

        let result = exo_start(exchanges) { tickPtr in
            guard let tick = tickPtr else { return }
            let goTick = Tick(
                price: tick.pointee.price,
                size: tick.pointee.size,
                side: tick.pointee.side,
                timestampNs: tick.pointee.timestamp_ns,
                exchangeId: tick.pointee.exchange_id,
                tickerId: tick.pointee.ticker_id
            )
            // Call the callback on main thread
            DispatchQueue.main.async {
                self.callback?(goTick)
            }
        }

        if result != 0 {
            throw NSError(domain: "ExoGridChart", code: -1, userInfo: nil)
        }
    }

    public func stop() {
        exo_stop()
    }

    public func getTickCount() -> UInt64 {
        exo_get_tick_count()
    }

    public func getMatrixStats(tickerId: UInt8) -> MatrixStats {
        let stats = exo_get_matrix_stats(tickerId)
        return MatrixStats(
            ticksProcessed: stats.ticks_processed,
            totalVolume: stats.total_volume,
            exchangeTicks: [
                stats.exchange_ticks.0,
                stats.exchange_ticks.1,
                stats.exchange_ticks.2,
            ]
        )
    }

    public func isInitialized() -> Bool {
        exo_is_initialized()
    }

    public enum Exchange {
        case coinbase
        case kraken
        case lcx
        case all

        var rawValue: UInt32 {
            switch self {
            case .coinbase: return 0x1
            case .kraken: return 0x2
            case .lcx: return 0x4
            case .all: return 0x7
            }
        }
    }
}
