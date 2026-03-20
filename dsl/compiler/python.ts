/**
 * Compile DSL to Python
 */

import * as AST from '../parser/ast';

export class PythonCompiler {
  compile(program: AST.Program): string {
    let code = this.generateHeader();

    for (const market of program.markets) {
      code += this.compileMarket(market);
    }

    code += this.generateFooter();
    return code;
  }

  private compileMarket(market: AST.MarketBlock): string {
    const varName = market.name.replace(/-/g, '_').lower();
    let code = `\n# Market: ${market.pair}\n`;
    code += `exo_${varName} = ExoGrid(host='localhost', port=9090)\n`;
    code += `exo_${varName}.connect()\n\n`;

    // Compile rules
    for (let i = 0; i < market.rules.length; i++) {
      code += this.compileRule(market, market.rules[i], i);
    }

    // Compile aggregations
    for (let i = 0; i < market.aggregations.length; i++) {
      code += this.compileAggregation(market, market.aggregations[i], i);
    }

    return code;
  }

  private compileRule(market: AST.MarketBlock, rule: AST.Rule, index: number): string {
    const varName = market.name.replace(/-/g, '_').toLowerCase();
    let code = `\ndef on_tick_${index}(tick):\n`;
    code += `    if ${this.compileExpression(rule.condition)}:\n`;

    for (const action of rule.actions) {
      code += `        ${this.compileAction(action)}\n`;
    }

    code += `\nexo_${varName}.on_tick(on_tick_${index})\n\n`;

    return code;
  }

  private compileAggregation(market: AST.MarketBlock, agg: AST.Aggregation, index: number): string {
    const varName = market.name.replace(/-/g, '_').toLowerCase();
    let code = `\n# Aggregation: ${agg.interval}\n`;
    code += `def aggregate_${index}():\n`;
    code += `    matrix = exo_${varName}.get_matrix('${market.pair}', '${agg.interval}')\n`;

    for (const action of agg.actions) {
      code += `    ${this.compileAction(action)}\n`;
    }

    code += `\nimport threading\n`;
    code += `timer = threading.Timer(60.0, aggregate_${index})\n`;
    code += `timer.daemon = True\n`;
    code += `timer.start()\n\n`;

    return code;
  }

  private compileExpression(expr: AST.Expression): string {
    if (expr.type === 'BinaryOp') {
      const binOp = expr as AST.BinaryOp;
      const left = this.compileExpression(binOp.left);
      const right = this.compileExpression(binOp.right);
      const op = binOp.operator === 'AND' ? 'and' : binOp.operator === 'OR' ? 'or' : binOp.operator;
      return `${left} ${op} ${right}`;
    }

    if (expr.type === 'Literal') {
      const lit = expr as AST.Literal;
      return typeof lit.value === 'string' ? `"${lit.value}"` : String(lit.value);
    }

    if (expr.type === 'Identifier') {
      const id = expr as AST.Identifier;
      return id.name;
    }

    if (expr.type === 'MemberAccess') {
      const ma = expr as AST.MemberAccess;
      return `${this.compileExpression(ma.object)}.${ma.property}`;
    }

    return '';
  }

  private compileAction(action: AST.Action): string {
    switch (action.actionType) {
      case 'ALERT':
        return `print(f'⚠️ ${action.params.message}')`;
      case 'LOG':
        return `print(f'📊 ${action.params.message}')`;
      case 'BUY':
        return `print('💰 BUY signal')`;
      case 'SELL':
        return `print('🔴 SELL signal')`;
      case 'STORE':
        return `store_data(tick)`;
      case 'NOTIFY':
        return `notify_traders('${action.params.message}')`;
      default:
        return '';
    }
  }

  private generateHeader(): string {
    return `#!/usr/bin/env python3
# Auto-generated Python from ExoGridChart DSL
from exogrid import ExoGrid
import threading

def main():
`;
  }

  private generateFooter(): string {
    return `
if __name__ == '__main__':
    main()
    # Keep running
    try:
        while True:
            import time
            time.sleep(1)
    except KeyboardInterrupt:
        print('\\nShutdown...')
`;
  }
}
