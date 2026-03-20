# ExoGridChart DSL (Domain Specific Language)

High-level, trader-friendly language for defining trading strategies on real-time market data.

**Status**: 🟢 In Development
**Supported Targets**: Zig, C, TypeScript, JavaScript, Python, Go

---

## Quick Example

```exo
// strategy.exo
MARKET BTC-USD {
    WATCH [coinbase, kraken, lcx]

    WHEN price > 50000 AND volume > 1000 {
        ALERT "Price spike!"
        LOG "High activity detected"
    }

    WHEN price < 45000 {
        ALERT "Price dip"
    }

    AGGREGATE 1m {
        SHOW ohlcv
        CALCULATE sma(20)
    }
}
```

---

## Compile to Any Language

```bash
# Compile to TypeScript
exogrid-dsl compile strategy.exo --target typescript

# Compile to Python
exogrid-dsl compile strategy.exo --target python

# Compile to Go
exogrid-dsl compile strategy.exo --target go

# Compile to Zig
exogrid-dsl compile strategy.exo --target zig

# Run directly (uses JS executor)
exogrid-dsl run strategy.exo
```

---

## Directory Structure

```
ExoGridChartDSL/
├── parser/              # DSL Parser
│   ├── lexer.ts
│   ├── parser.ts
│   └── ast.ts
├── compiler/            # Code generators
│   ├── typescript.ts
│   ├── python.ts
│   ├── go.ts
│   ├── zig.ts
│   └── c.ts
├── executor/            # Runtime executor
│   └── executor.ts
├── examples/            # Example .exo files
│   ├── basic.exo
│   ├── advanced.exo
│   └── ma_crossover.exo
└── cli/                 # CLI tool
    └── cli.ts
```

---

## Language Features

- ✅ Market watching (multiple exchanges)
- ✅ Conditional triggers (WHEN)
- ✅ Actions (ALERT, LOG, BUY, SELL)
- ✅ Aggregation (AGGREGATE)
- ✅ Calculations (SMA, RSI, MACD)
- ✅ Data storage
- ✅ Notifications

---

## Coming Next

1. Lexer (tokenize DSL)
2. Parser (build AST)
3. Compiler (generate code)
4. Executor (run strategies)
