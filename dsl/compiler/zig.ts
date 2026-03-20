import * as AST from '../parser/ast';

export class ZigCompiler {
  compile(program: AST.Program): string {
    let code = `const std = @import("std");
const exogrid = @import("exogrid.zig");

pub fn main() !void {\n`;

    for (const market of program.markets) {
      code += this.compileMarket(market);
    }

    code += `}\n`;
    return code;
  }

  private compileMarket(market: AST.MarketBlock): string {
    let code = `    var agg = exogrid.ParallelAggregator.init(allocator);\n`;
    code += `    try agg.start(0x7, &onTick);\n`;
    code += `    std.time.sleep(10 * std.time.ns_per_s);\n`;
    code += `    agg.stop();\n\n`;
    return code;
  }
}
