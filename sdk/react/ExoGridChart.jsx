import React, { useEffect, useState, useRef } from 'react';
import { ExoGrid } from '../../js/index.js';

export const ExoGridChart = ({ host = 'localhost', port = 9090 }) => {
    const [matrix, setMatrix] = useState(null);
    const [ticks, setTicks] = useState(0);
    const [connected, setConnected] = useState(false);
    const exoRef = useRef(null);

    useEffect(() => {
        const exo = new ExoGrid({ host, port });

        exo.on('connected', () => setConnected(true));
        exo.on('disconnected', () => setConnected(false));
        exo.on('matrix', (data) => setMatrix(data));
        exo.on('tick', () => setTicks(t => t + 1));

        exoRef.current = exo;
        exo.connect();

        return () => exo.disconnect();
    }, [host, port]);

    return (
        <div className="exogrid-chart">
            <div className="status">
                <span className={`indicator ${connected ? 'connected' : 'disconnected'}`} />
                {connected ? 'Connected' : 'Disconnected'}
            </div>
            <div className="stats">
                <div>Ticks: {ticks}</div>
                {matrix && (
                    <>
                        <div>POC: ${matrix.poc_price?.toFixed(2)}</div>
                        <div>Volume: {matrix.total_volume}</div>
                    </>
                )}
            </div>
            <canvas id="chart" width={800} height={600} />
        </div>
    );
};

export default ExoGridChart;
