package com.exogridchart;

public class ExoGrid {
    static {
        System.loadLibrary("exogrid");
    }

    public static class Tick {
        public float price;
        public float size;
        public byte side;
        public long timestampNs;
        public int exchangeId;
        public byte tickerId;
    }

    public static class MatrixStats {
        public long ticksProcessed;
        public long totalVolume;
        public long[] exchangeTicks = new long[3];
    }

    public interface TickCallback {
        void onTick(Tick tick);
    }

    // JNI Methods
    private native int nativeInit();
    private native void nativeDeinit();
    private native int nativeStart(int exchanges, TickCallback callback);
    private native void nativeStop();
    private native long nativeGetTickCount();
    private native MatrixStats nativeGetMatrixStats(byte tickerId);

    public ExoGrid() {
        if (nativeInit() != 0) {
            throw new RuntimeException("Failed to initialize ExoGrid");
        }
    }

    public void start(int exchanges, TickCallback callback) {
        if (nativeStart(exchanges, callback) != 0) {
            throw new RuntimeException("Failed to start streaming");
        }
    }

    public void stop() {
        nativeStop();
    }

    public long getTickCount() {
        return nativeGetTickCount();
    }

    public MatrixStats getMatrixStats(byte tickerId) {
        return nativeGetMatrixStats(tickerId);
    }

    public void close() {
        nativeDeinit();
    }

    @Override
    protected void finalize() throws Throwable {
        close();
        super.finalize();
    }

    // Exchange constants
    public static final int EXCHANGE_COINBASE = 0x1;
    public static final int EXCHANGE_KRAKEN = 0x2;
    public static final int EXCHANGE_LCX = 0x4;
    public static final int EXCHANGE_ALL = 0x7;

    // Ticker constants
    public static final byte TICKER_BTC = 0;
    public static final byte TICKER_ETH = 1;
    public static final byte TICKER_XRP = 2;
    public static final byte TICKER_LTC = 3;
}
