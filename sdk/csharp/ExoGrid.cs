using System;
using System.Runtime.InteropServices;
using System.Threading.Tasks;

namespace ExoGridChart
{
    [StructLayout(LayoutKind.Sequential)]
    public struct Tick
    {
        public float Price;
        public float Size;
        public byte Side;
        public ulong TimestampNs;
        public uint ExchangeId;
        public byte TickerId;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MatrixStats
    {
        public ulong TicksProcessed;
        public ulong TotalVolume;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 3)]
        public ulong[] ExchangeTicks;
    }

    public delegate void TickCallback(ref Tick tick);

    public class ExoGrid : IDisposable
    {
        [DllImport("exogrid", CallingConvention = CallingConvention.Cdecl)]
        private static extern int exo_init();

        [DllImport("exogrid", CallingConvention = CallingConvention.Cdecl)]
        private static extern void exo_deinit();

        [DllImport("exogrid", CallingConvention = CallingConvention.Cdecl)]
        private static extern int exo_start(uint exchanges, TickCallback callback);

        [DllImport("exogrid", CallingConvention = CallingConvention.Cdecl)]
        private static extern void exo_stop();

        [DllImport("exogrid", CallingConvention = CallingConvention.Cdecl)]
        private static extern ulong exo_get_tick_count();

        [DllImport("exogrid", CallingConvention = CallingConvention.Cdecl)]
        private static extern MatrixStats exo_get_matrix_stats(byte tickerId);

        public ExoGrid()
        {
            if (exo_init() != 0)
                throw new InvalidOperationException("Failed to initialize ExoGrid");
        }

        public void Start(uint exchanges, TickCallback callback)
        {
            if (exo_start(exchanges, callback) != 0)
                throw new InvalidOperationException("Failed to start streaming");
        }

        public void Stop()
        {
            exo_stop();
        }

        public ulong GetTickCount()
        {
            return exo_get_tick_count();
        }

        public MatrixStats GetMatrixStats(byte tickerId)
        {
            return exo_get_matrix_stats(tickerId);
        }

        public void Dispose()
        {
            exo_deinit();
            GC.SuppressFinalize(this);
        }

        public const uint EXCHANGE_COINBASE = 0x1;
        public const uint EXCHANGE_KRAKEN = 0x2;
        public const uint EXCHANGE_LCX = 0x4;
        public const uint EXCHANGE_ALL = 0x7;
    }
}
