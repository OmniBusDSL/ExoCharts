/**
 * ExoGridChart DSL Parser
 * Converts tokens to AST
 */

import { Lexer, Token, TokenType } from './lexer';
import * as AST from './ast';

export class Parser {
  private tokens: Token[];
  private position = 0;

  static parse(source: string): AST.Program {
    const lexer = new Lexer(source);
    const tokens = lexer.tokenize();
    const parser = new Parser(tokens);
    return parser.parseProgram();
  }

  constructor(tokens: Token[]) {
    this.tokens = tokens;
  }

  private parseProgram(): AST.Program {
    const markets: AST.MarketBlock[] = [];

    while (!this.isAtEnd()) {
      if (this.check(TokenType.MARKET)) {
        markets.push(this.parseMarketBlock());
      } else {
        this.advance();
      }
    }

    return { type: 'Program', markets };
  }

  private parseMarketBlock(): AST.MarketBlock {
    this.consume(TokenType.MARKET, 'Expected MARKET');
    const name = this.consume(TokenType.STRING, 'Expected market name').value;
    const pair = name;

    this.consume(TokenType.LBRACE, 'Expected {');

    const watches: string[] = [];
    const rules: AST.Rule[] = [];
    const aggregations: AST.Aggregation[] = [];

    while (!this.check(TokenType.RBRACE) && !this.isAtEnd()) {
      if (this.check(TokenType.WATCH)) {
        watches.push(...this.parseWatchClause());
      } else if (this.check(TokenType.WHEN)) {
        rules.push(this.parseRule());
      } else if (this.check(TokenType.AGGREGATE)) {
        aggregations.push(this.parseAggregation());
      } else {
        this.advance();
      }
    }

    this.consume(TokenType.RBRACE, 'Expected }');

    return {
      type: 'MarketBlock',
      name,
      pair,
      watches,
      rules,
      aggregations,
    };
  }

  private parseWatchClause(): string[] {
    this.consume(TokenType.WATCH, 'Expected WATCH');
    const exchanges: string[] = [];

    if (this.check(TokenType.LBRACKET)) {
      this.consume(TokenType.LBRACKET, 'Expected [');
      while (!this.check(TokenType.RBRACKET)) {
        exchanges.push(this.consume(TokenType.IDENTIFIER, 'Expected exchange name').value);
        if (this.check(TokenType.COMMA)) {
          this.advance();
        }
      }
      this.consume(TokenType.RBRACKET, 'Expected ]');
    } else {
      exchanges.push(this.consume(TokenType.IDENTIFIER, 'Expected exchange name').value);
    }

    return exchanges;
  }

  private parseRule(): AST.Rule {
    this.consume(TokenType.WHEN, 'Expected WHEN');
    const condition = this.parseExpression();

    this.consume(TokenType.LBRACE, 'Expected {');
    const actions: AST.Action[] = [];

    while (!this.check(TokenType.RBRACE) && !this.isAtEnd()) {
      actions.push(this.parseAction());
    }

    this.consume(TokenType.RBRACE, 'Expected }');

    return {
      type: 'Rule',
      condition,
      actions,
    };
  }

  private parseAction(): AST.Action {
    const tokenType = this.peek().type as TokenType;
    const actionType = tokenType as any;

    if (![TokenType.ALERT, TokenType.LOG, TokenType.BUY, TokenType.SELL, TokenType.STORE, TokenType.NOTIFY].includes(tokenType)) {
      throw new Error(`Expected action, got ${tokenType}`);
    }

    this.advance();

    const params: Record<string, any> = {};

    if (this.check(TokenType.STRING)) {
      params.message = this.consume(TokenType.STRING, 'Expected string').value;
    }

    return {
      type: 'Action',
      actionType: actionType as any,
      params,
    };
  }

  private parseAggregation(): AST.Aggregation {
    this.consume(TokenType.AGGREGATE, 'Expected AGGREGATE');
    const interval = this.consume(TokenType.IDENTIFIER, 'Expected interval').value;

    this.consume(TokenType.LBRACE, 'Expected {');
    const metrics: string[] = [];
    const actions: AST.Action[] = [];

    while (!this.check(TokenType.RBRACE) && !this.isAtEnd()) {
      if (this.check(TokenType.SHOW) || this.check(TokenType.CALCULATE)) {
        this.advance();
        metrics.push(this.consume(TokenType.IDENTIFIER, 'Expected metric name').value);
      } else {
        actions.push(this.parseAction());
      }
    }

    this.consume(TokenType.RBRACE, 'Expected }');

    return {
      type: 'Aggregation',
      interval,
      metrics,
      actions,
    };
  }

  private parseExpression(): AST.Expression {
    return this.parseOrExpression();
  }

  private parseOrExpression(): AST.Expression {
    let expr = this.parseAndExpression();

    while (this.check(TokenType.OR)) {
      this.advance();
      const right = this.parseAndExpression();
      expr = {
        type: 'BinaryOp',
        left: expr,
        operator: 'OR',
        right,
      };
    }

    return expr;
  }

  private parseAndExpression(): AST.Expression {
    let expr = this.parseComparisonExpression();

    while (this.check(TokenType.AND)) {
      this.advance();
      const right = this.parseComparisonExpression();
      expr = {
        type: 'BinaryOp',
        left: expr,
        operator: 'AND',
        right,
      };
    }

    return expr;
  }

  private parseComparisonExpression(): AST.Expression {
    let expr = this.parsePrimaryExpression();

    while (this.check(TokenType.GT) || this.check(TokenType.LT) ||
           this.check(TokenType.GTE) || this.check(TokenType.LTE) ||
           this.check(TokenType.EQ) || this.check(TokenType.NEQ)) {
      const operator = this.advance().value;
      const right = this.parsePrimaryExpression();
      expr = {
        type: 'BinaryOp',
        left: expr,
        operator,
        right,
      };
    }

    return expr;
  }

  private parsePrimaryExpression(): AST.Expression {
    if (this.check(TokenType.NUMBER)) {
      return {
        type: 'Literal',
        value: parseFloat(this.advance().value),
      };
    }

    if (this.check(TokenType.STRING)) {
      return {
        type: 'Literal',
        value: this.advance().value,
      };
    }

    if (this.check(TokenType.IDENTIFIER)) {
      let expr: AST.Expression = {
        type: 'Identifier',
        name: this.advance().value,
      };

      // Handle member access (e.g., tick.price)
      while (this.check(TokenType.DOT)) {
        this.advance();
        const property = this.consume(TokenType.IDENTIFIER, 'Expected property name').value;
        expr = {
          type: 'MemberAccess',
          object: expr,
          property,
        };
      }

      return expr;
    }

    if (this.check(TokenType.LPAREN)) {
      this.advance();
      const expr = this.parseExpression();
      this.consume(TokenType.RPAREN, 'Expected )');
      return expr;
    }

    throw new Error(`Unexpected token: ${this.peek().type}`);
  }

  private check(type: TokenType): boolean {
    if (this.isAtEnd()) return false;
    return this.peek().type === type;
  }

  private advance(): Token {
    if (!this.isAtEnd()) this.position++;
    return this.previous();
  }

  private isAtEnd(): boolean {
    return this.peek().type === TokenType.EOF;
  }

  private peek(): Token {
    return this.tokens[this.position];
  }

  private previous(): Token {
    return this.tokens[this.position - 1];
  }

  private consume(type: TokenType, message: string): Token {
    if (this.check(type)) return this.advance();
    throw new Error(`${message} at ${this.peek().line}:${this.peek().column}`);
  }
}
