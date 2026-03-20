import * as AST from '../parser/ast';

export class CCompiler {
  compile(program: AST.Program): string {
    let code = `#include "exogrid.h"
#include <stdio.h>

void on_tick(const Tick* tick) {
`;

    for (const market of program.markets) {
      for (const rule of market.rules) {
        code += `    if (${this.compileCondition(rule.condition)}) {
${this.compileActions(rule.actions)}
    }
`;
      }
    }

    code += `}

int main() {
    exo_init();
    exo_start(0x7, &on_tick);
    sleep(10);
    exo_stop();
    exo_deinit();
    return 0;
}
`;
    return code;
  }

  private compileCondition(expr: AST.Expression): string {
    if (expr.type === 'BinaryOp') {
      const binOp = expr as AST.BinaryOp;
      return `${this.compileCondition(binOp.left)} ${binOp.operator === 'AND' ? '&&' : '||'} ${this.compileCondition(binOp.right)}`;
    }
    if (expr.type === 'MemberAccess') {
      const ma = expr as AST.MemberAccess;
      return `tick->${ma.property}`;
    }
    return '';
  }

  private compileActions(actions: AST.Action[]): string {
    return actions.map(a => `        printf("Action: ${a.actionType}\\n");`).join('\n');
  }
}
