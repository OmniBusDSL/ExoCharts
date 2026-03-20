/**
 * ExoGridChart DSL Lexer
 * Tokenizes DSL source code
 */

export enum TokenType {
  // Keywords
  MARKET = 'MARKET',
  WATCH = 'WATCH',
  WHEN = 'WHEN',
  THEN = 'THEN',
  ALERT = 'ALERT',
  LOG = 'LOG',
  BUY = 'BUY',
  SELL = 'SELL',
  AGGREGATE = 'AGGREGATE',
  SHOW = 'SHOW',
  CALCULATE = 'CALCULATE',
  STORE = 'STORE',
  NOTIFY = 'NOTIFY',
  ON = 'ON',
  AND = 'AND',
  OR = 'OR',
  NOT = 'NOT',

  // Literals
  STRING = 'STRING',
  NUMBER = 'NUMBER',
  IDENTIFIER = 'IDENTIFIER',

  // Operators
  GT = '>',
  LT = '<',
  GTE = '>=',
  LTE = '<=',
  EQ = '==',
  NEQ = '!=',
  ASSIGN = '=',

  // Delimiters
  LBRACE = '{',
  RBRACE = '}',
  LPAREN = '(',
  RPAREN = ')',
  LBRACKET = '[',
  RBRACKET = ']',
  COMMA = ',',
  DOT = '.',
  COLON = ':',

  // Special
  EOF = 'EOF',
  NEWLINE = 'NEWLINE',
}

export interface Token {
  type: TokenType;
  value: string;
  line: number;
  column: number;
}

export class Lexer {
  private source: string;
  private position = 0;
  private line = 1;
  private column = 1;
  private tokens: Token[] = [];

  private keywords = new Set([
    'MARKET', 'WATCH', 'WHEN', 'THEN', 'ALERT', 'LOG',
    'BUY', 'SELL', 'AGGREGATE', 'SHOW', 'CALCULATE',
    'STORE', 'NOTIFY', 'ON', 'AND', 'OR', 'NOT'
  ]);

  constructor(source: string) {
    this.source = source;
  }

  tokenize(): Token[] {
    while (this.position < this.source.length) {
      this.skipWhitespaceAndComments();
      if (this.position >= this.source.length) break;

      const char = this.current();

      if (this.isNewline(char)) {
        this.advance();
        continue;
      }

      if (char === '"' || char === "'") {
        this.tokens.push(this.readString());
      } else if (this.isDigit(char)) {
        this.tokens.push(this.readNumber());
      } else if (this.isAlpha(char)) {
        this.tokens.push(this.readIdentifierOrKeyword());
      } else if (this.isOperator(char)) {
        this.tokens.push(this.readOperator());
      } else if (this.isDelimiter(char)) {
        this.tokens.push(this.makeToken(char as TokenType, char));
        this.advance();
      } else {
        throw new Error(`Unexpected character '${char}' at ${this.line}:${this.column}`);
      }
    }

    this.tokens.push(this.makeToken(TokenType.EOF, ''));
    return this.tokens;
  }

  private readString(): Token {
    const quote = this.current();
    const startLine = this.line;
    const startCol = this.column;
    let value = '';

    this.advance(); // Skip opening quote
    while (this.current() !== quote && !this.isAtEnd()) {
      if (this.current() === '\\') {
        this.advance();
        const escaped = this.current();
        value += escaped === 'n' ? '\n' : escaped === 't' ? '\t' : escaped;
        this.advance();
      } else {
        value += this.current();
        this.advance();
      }
    }

    if (this.isAtEnd()) {
      throw new Error(`Unterminated string at ${startLine}:${startCol}`);
    }

    this.advance(); // Skip closing quote
    return this.makeTokenWithValue(TokenType.STRING, value);
  }

  private readNumber(): Token {
    let value = '';
    while (this.isDigit(this.current()) || this.current() === '.') {
      value += this.current();
      this.advance();
    }
    return this.makeTokenWithValue(TokenType.NUMBER, value);
  }

  private readIdentifierOrKeyword(): Token {
    let value = '';
    while (this.isAlphaNumeric(this.current())) {
      value += this.current();
      this.advance();
    }

    const type = this.keywords.has(value)
      ? (value as TokenType)
      : TokenType.IDENTIFIER;

    return this.makeTokenWithValue(type, value);
  }

  private readOperator(): Token {
    const char = this.current();
    const next = this.peek();

    if ((char === '>' || char === '<') && next === '=') {
      const op = char + next;
      this.advance();
      this.advance();
      return this.makeTokenWithValue(op as TokenType, op);
    }

    if ((char === '=' || char === '!') && next === '=') {
      const op = char + next;
      this.advance();
      this.advance();
      return this.makeTokenWithValue(op as TokenType, op);
    }

    const type = char as TokenType;
    this.advance();
    return this.makeToken(type, char);
  }

  private skipWhitespaceAndComments(): void {
    while (!this.isAtEnd()) {
      const char = this.current();

      if (char === ' ' || char === '\t' || char === '\r') {
        this.advance();
      } else if (char === '/' && this.peek() === '/') {
        // Skip line comment
        while (!this.isNewline(this.current()) && !this.isAtEnd()) {
          this.advance();
        }
      } else {
        break;
      }
    }
  }

  private current(): string {
    return this.isAtEnd() ? '' : this.source[this.position];
  }

  private peek(): string {
    return this.position + 1 >= this.source.length ? '' : this.source[this.position + 1];
  }

  private advance(): void {
    if (this.isNewline(this.current())) {
      this.line++;
      this.column = 1;
    } else {
      this.column++;
    }
    this.position++;
  }

  private isAtEnd(): boolean {
    return this.position >= this.source.length;
  }

  private isNewline(char: string): boolean {
    return char === '\n';
  }

  private isDigit(char: string): boolean {
    return char >= '0' && char <= '9';
  }

  private isAlpha(char: string): boolean {
    return (char >= 'a' && char <= 'z') ||
           (char >= 'A' && char <= 'Z') ||
           char === '_';
  }

  private isAlphaNumeric(char: string): boolean {
    return this.isAlpha(char) || this.isDigit(char);
  }

  private isOperator(char: string): boolean {
    return '><!='.includes(char);
  }

  private isDelimiter(char: string): boolean {
    return '{}()[],.,:'.includes(char);
  }

  private makeToken(type: TokenType, value: string): Token {
    return {
      type,
      value,
      line: this.line,
      column: this.column,
    };
  }

  private makeTokenWithValue(type: TokenType, value: string): Token {
    return {
      type,
      value,
      line: this.line,
      column: this.column - value.length,
    };
  }
}
