import * as AST from '../parser/ast';

export class JavaScriptCompiler {
  compile(program: AST.Program): string {
    let code = `// Auto-generated JavaScript from ExoGridChart DSL
const { ExoGrid } = require('exogridchart');

const exo = new ExoGrid();

`;

    for (const market of program.markets) {
      code += this.compileMarket(market);
    }

    code += `
exo.connect();
`;
    return code;
  }

  private compileMarket(market: AST.MarketBlock): string {
    let code = `// Market: ${market.pair}
exo.on('tick', (tick) => {
`;

    for (const rule of market.rules) {
      code += `    if (${this.compileExpression(rule.condition)}) {
`;
      for (const action of rule.actions) {
        code += `        ${this.compileAction(action)}\n`;
      }
      code += `    }\n`;
    }

    code += `});\n\n`;
    return code;
  }

  private compileExpression(expr: AST.Expression): string {
    if (expr.type === 'BinaryOp') {
      const binOp = expr as AST.BinaryOp;
      const op = binOp.operator === 'AND' ? '&&' : binOp.operator === 'OR' ? '||' : binOp.operator;
      return `(${this.compileExpression(binOp.left)} ${op} ${this.compileExpression(binOp.right)})`;
    }
    if (expr.type === 'Literal') {
      const lit = expr as AST.Literal;
      return typeof lit.value === 'string' ? `"${lit.value}"` : String(lit.value);
    }
    if (expr.type === 'MemberAccess') {
      const ma = expr as AST.MemberAccess;
      return `tick.${ma.property}`;
    }
    return '';
  }

  private compileAction(action: AST.Action): string {
    switch (action.actionType) {
      case 'ALERT':
        return `console.warn('⚠️ ${action.params.message}');`;
      case 'LOG':
        return `console.log('📊 ${action.params.message}');`;
      default:
        return `console.log('Action: ${action.actionType}');`;
    }
  }
}
