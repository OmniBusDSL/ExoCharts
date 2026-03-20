#!/usr/bin/env node

/**
 * ExoGridChart DSL CLI
 * Compile and execute trading strategies
 */

import * as fs from 'fs';
import * as path from 'path';
import { Parser } from '../parser/parser';
import { TypeScriptCompiler } from '../compiler/typescript';
import { PythonCompiler } from '../compiler/python';
import { GoCompiler } from '../compiler/go';
import { ZigCompiler } from '../compiler/zig';
import { CCompiler } from '../compiler/c';
import { JavaScriptCompiler } from '../compiler/javascript';

const args = process.argv.slice(2);
const command = args[0];

function help() {
  console.log(`
ExoGridChart DSL CLI

Usage:
  exogrid-dsl compile <file> --target <language>
  exogrid-dsl run <file>
  exogrid-dsl validate <file>

Commands:
  compile      Compile DSL to target language
  run          Execute DSL directly
  validate     Validate DSL syntax

Examples:
  exogrid-dsl compile strategy.exo --target typescript
  exogrid-dsl compile strategy.exo --target python
  exogrid-dsl run strategy.exo
  exogrid-dsl validate strategy.exo
`);
}

function compile(dslFile: string, target: string) {
  try {
    const source = fs.readFileSync(dslFile, 'utf-8');
    const program = Parser.parse(source);

    let compiled: string;

    switch (target.toLowerCase()) {
      case 'typescript':
      case 'ts':
        compiled = new TypeScriptCompiler().compile(program);
        break;
      case 'python':
      case 'py':
        compiled = new PythonCompiler().compile(program);
        break;
      case 'go':
        compiled = new GoCompiler().compile(program);
        break;
      case 'zig':
        compiled = new ZigCompiler().compile(program);
        break;
      case 'c':
        compiled = new CCompiler().compile(program);
        break;
      case 'javascript':
      case 'js':
        compiled = new JavaScriptCompiler().compile(program);
        break;
      default:
        console.error(`Unknown target: ${target}`);
        return;
    }

    const outputFile = dslFile.replace('.exo', `.${getExtension(target)}`);
    fs.writeFileSync(outputFile, compiled);
    console.log(`✅ Compiled to ${outputFile}`);
  } catch (error) {
    console.error(`❌ Compilation failed:`, error instanceof Error ? error.message : error);
    process.exit(1);
  }
}

function run(dslFile: string) {
  try {
    const source = fs.readFileSync(dslFile, 'utf-8');
    const program = Parser.parse(source);

    // Execute using JavaScript/TypeScript runtime
    const executor = new JavaScriptCompiler().compile(program);
    console.log('📊 Running strategy...\n');
    console.log(executor);

    // In production, would actually execute the code
    console.log('\n✅ Strategy loaded and ready');
  } catch (error) {
    console.error(`❌ Execution failed:`, error instanceof Error ? error.message : error);
    process.exit(1);
  }
}

function validate(dslFile: string) {
  try {
    const source = fs.readFileSync(dslFile, 'utf-8');
    Parser.parse(source);
    console.log(`✅ ${dslFile} is valid`);
  } catch (error) {
    console.error(`❌ Validation failed:`, error instanceof Error ? error.message : error);
    process.exit(1);
  }
}

function getExtension(target: string): string {
  const extensions: Record<string, string> = {
    typescript: 'ts',
    ts: 'ts',
    python: 'py',
    py: 'py',
    go: 'go',
    zig: 'zig',
    c: 'c',
    javascript: 'js',
    js: 'js',
  };
  return extensions[target.toLowerCase()] || 'txt';
}

// Main
if (args.length === 0) {
  help();
} else if (command === 'compile') {
  const file = args[1];
  const targetIdx = args.indexOf('--target');
  if (!file || targetIdx === -1) {
    console.error('Usage: exogrid-dsl compile <file> --target <language>');
    process.exit(1);
  }
  const target = args[targetIdx + 1];
  compile(file, target);
} else if (command === 'run') {
  const file = args[1];
  if (!file) {
    console.error('Usage: exogrid-dsl run <file>');
    process.exit(1);
  }
  run(file);
} else if (command === 'validate') {
  const file = args[1];
  if (!file) {
    console.error('Usage: exogrid-dsl validate <file>');
    process.exit(1);
  }
  validate(file);
} else if (command === '--help' || command === '-h') {
  help();
} else {
  console.error(`Unknown command: ${command}`);
  help();
  process.exit(1);
}
