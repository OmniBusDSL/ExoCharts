/**
 * Abstract Syntax Tree for ExoGridChart DSL
 */

export interface ASTNode {
  type: string;
}

export interface Program extends ASTNode {
  type: 'Program';
  markets: MarketBlock[];
}

export interface MarketBlock extends ASTNode {
  type: 'MarketBlock';
  name: string;
  pair: string;
  watches: string[];
  rules: Rule[];
  aggregations: Aggregation[];
}

export interface Rule extends ASTNode {
  type: 'Rule';
  condition: Expression;
  actions: Action[];
}

export interface Expression extends ASTNode {
  type: 'Expression' | 'BinaryOp' | 'Literal' | 'Identifier';
}

export interface BinaryOp extends Expression {
  type: 'BinaryOp';
  left: Expression;
  operator: string;
  right: Expression;
}

export interface Literal extends Expression {
  type: 'Literal';
  value: string | number;
}

export interface Identifier extends Expression {
  type: 'Identifier';
  name: string;
}

export interface MemberAccess extends Expression {
  type: 'MemberAccess';
  object: Expression;
  property: string;
}

export interface Action extends ASTNode {
  type: 'Action';
  actionType: 'ALERT' | 'LOG' | 'BUY' | 'SELL' | 'STORE' | 'NOTIFY';
  params: Record<string, any>;
}

export interface Aggregation extends ASTNode {
  type: 'Aggregation';
  interval: string;
  metrics: string[];
  actions: Action[];
}

/**
 * Example parsed program:
 * {
 *   type: 'Program',
 *   markets: [
 *     {
 *       type: 'MarketBlock',
 *       name: 'BTC-USD',
 *       pair: 'BTC-USD',
 *       watches: ['coinbase', 'kraken'],
 *       rules: [
 *         {
 *           type: 'Rule',
 *           condition: {
 *             type: 'BinaryOp',
 *             left: { type: 'MemberAccess', object: { type: 'Identifier', name: 'price' }, property: 'value' },
 *             operator: '>',
 *             right: { type: 'Literal', value: 50000 }
 *           },
 *           actions: [
 *             {
 *               type: 'Action',
 *               actionType: 'ALERT',
 *               params: { message: 'Price spike!' }
 *             }
 *           ]
 *         }
 *       ]
 *     }
 *   ]
 * }
 */
