/**
 * Compile DSL to Go
 */

import * as AST from '../parser/ast';

export class GoCompiler {
  compile(program: AST.Program): string {
    let code = this.generateHeader();

    for (const market of program.markets) {
      code += this.compileMarket(market);
    }

    code += this.generateFooter();
    return code;
  }

  private compileMarket(market: AST.MarketBlock): string {
    const varName = market.name.replace(/-/g, '_').toLowerCase();
    let code = `\n// Market: ${market.pair}\n`;
    code += `exo${this.capitalize(varName)}, _ := exogrid.Init()\n`;
    code += `exo${this.capitalize(varName)}.Start(exogrid.AllExchanges, func(tick *exogrid.Tick) {\n`;

    // Compile rules
    for (const rule of market.rules) {
      code += this.compileRule(rule);
    }

    code += `})\n\n`;

    // Compile aggregations
    for (const agg of market.aggregations) {
      code += this.compileAggregation(agg);
    }

    code += `defer exo${this.capitalize(varName)}.Stop()\n`;

    return code;
  }

  private compileRule(rule: AST.Rule): string {
    let code = `    if ${this.compileExpression(rule.condition)} {\n`;

    for (const action of rule.actions) {
      code += `        ${this.compileAction(action)}\n`;
    }

    code += `    }\n`;

    return code;
  }

  private compileAggregation(agg: AST.Aggregation): string {
    let code = `\n// Aggregation: ${agg.interval}\n`;
    code += `go func() {\n`;
    code += `    ticker := time.NewTicker(60 * time.Second)\n`;
    code += `    defer ticker.Stop()\n`;
    code += `    for range ticker.C {\n`;

    for (const action of agg.actions) {
      code += `        ${this.compileAction(action)}\n`;
    }

    code += `    }\n`;
    code += `}()\n\n`;

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
      return `tick.${this.capitalize(id.name)}`;
    }

    if (expr.type === 'MemberAccess') {
      const ma = expr as AST.MemberAccess;
      const obj = this.compileExpression(ma.object);
      return `${obj}.${this.capitalize(ma.property)}`;
    }

    return '';
  }

  private compileAction(action: AST.Action): string {
    switch (action.actionType) {
      case 'ALERT':
        return `log.Println("⚠️ ${action.params.message}")`;
      case 'LOG':
        return `log.Println("📊 ${action.params.message}")`;
      case 'BUY':
        return `log.Println("💰 BUY signal")`;
      case 'SELL':
        return `log.Println("🔴 SELL signal")`;
      case 'STORE':
        return `storeData(tick)`;
      case 'NOTIFY':
        return `notifyTraders("${action.params.message}")`;
      default:
        return '';
    }
  }

  private generateHeader(): string {
    return `package main

// Auto-generated Go from ExoGridChart DSL
import (
    "log"
    "time"
    "exogrid"
)

func main() {
`;
  }

  private generateFooter(): string {
    return `
    // Keep running
    select {}
}
`;
  }

  private capitalize(str: string): string {
    return str.charAt(0).toUpperCase() + str.slice(1);
  }
}
