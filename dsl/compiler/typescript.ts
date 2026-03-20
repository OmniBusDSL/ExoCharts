/**
 * Compile DSL to TypeScript
 */

import * as AST from '../parser/ast';

export class TypeScriptCompiler {
  compile(program: AST.Program): string {
    let code = this.generateHeader();

    for (const market of program.markets) {
      code += this.compileMarket(market);
    }

    code += this.generateFooter();
    return code;
  }

  private compileMarket(market: AST.MarketBlock): string {
    let code = `\n// Market: ${market.pair}\n`;
    code += `const exo_${market.name.replace(/-/g, '_')} = new ExoGrid();\n`;
    code += `exo_${market.name.replace(/-/g, '_')}.connect();\n\n`;

    // Compile rules
    for (const rule of market.rules) {
      code += this.compileRule(market, rule);
    }

    // Compile aggregations
    for (const agg of market.aggregations) {
      code += this.compileAggregation(market, agg);
    }

    return code;
  }

  private compileRule(market: AST.MarketBlock, rule: AST.Rule): string {
    let code = `exo_${market.name.replace(/-/g, '_')}.on('tick', (tick: Tick) => {\n`;
    code += `  if (${this.compileExpression(rule.condition)}) {\n`;

    for (const action of rule.actions) {
      code += `    ${this.compileAction(action)}\n`;
    }

    code += `  }\n`;
    code += `});\n\n`;

    return code;
  }

  private compileAggregation(market: AST.MarketBlock, agg: AST.Aggregation): string {
    let code = `// Aggregation: ${agg.interval}\n`;
    code += `setInterval(async () => {\n`;
    code += `  const matrix = await exo_${market.name.replace(/-/g, '_')}.getMatrix('${market.pair}', '${agg.interval}');\n`;

    for (const action of agg.actions) {
      code += `  ${this.compileAction(action)}\n`;
    }

    code += `}, 60000);\n\n`;

    return code;
  }

  private compileExpression(expr: AST.Expression): string {
    if (expr.type === 'BinaryOp') {
      const binOp = expr as AST.BinaryOp;
      const left = this.compileExpression(binOp.left);
      const right = this.compileExpression(binOp.right);
      const op = binOp.operator === 'AND' ? '&&' : binOp.operator === 'OR' ? '||' : binOp.operator;
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
        return `console.warn('⚠️ ${action.params.message}');`;
      case 'LOG':
        return `console.log('📊 ${action.params.message}');`;
      case 'BUY':
        return `console.log('💰 BUY signal');`;
      case 'SELL':
        return `console.log('🔴 SELL signal');`;
      case 'STORE':
        return `await storeData(tick);`;
      case 'NOTIFY':
        return `await notifyTraders('${action.params.message}');`;
      default:
        return '';
    }
  }

  private generateHeader(): string {
    return `
// Auto-generated TypeScript from ExoGridChart DSL
import { ExoGrid, Tick } from 'exogridchart';

async function runStrategy() {
`;
  }

  private generateFooter(): string {
    return `
}

// Run strategy
runStrategy().catch(console.error);
`;
  }
}
