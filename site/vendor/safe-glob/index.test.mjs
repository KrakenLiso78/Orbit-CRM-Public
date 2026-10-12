import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import safeGlob from './index.mjs';

void test('dynamic-import extension alternatives and nested index paths retain file-only matching', () => {
  const cwd=mkdtempSync(join(tmpdir(),'orbit-safe-glob-'));
  try {
    mkdirSync(join(cwd,'modules','nested'),{recursive:true});
    for(const name of ['a.js','b.ts','ignored.txt','.hidden.js','nested/index.ts'])writeFileSync(join(cwd,'modules',name),'synthetic fixture');
    assert.deepEqual(safeGlob.sync(['modules/*.{js,ts}','modules/*/index.{js,ts}','modules/a.js'],{cwd}),['modules/a.js','modules/b.ts','modules/nested/index.ts']);
    assert.deepEqual(safeGlob.sync(['modules/**/*.{js,ts}','!modules/a.js'],{cwd}),['modules/b.ts','modules/nested/index.ts']);
    assert.deepEqual(safeGlob.sync('modules',{cwd}),[]);
  } finally { rmSync(cwd,{recursive:true,force:true}); }
});

void test('deeply nested adversarial braces and groups fail before traversal', () => {
  for(const [open,close] of [['{','}'],['(',')']]) {
    const pattern=open.repeat(1000)+'x'+close.repeat(1000);
    assert.throws(()=>safeGlob.sync(pattern,{cwd:'nonexistent-directory'}),{name:'RangeError',message:'Glob pattern is too deeply nested'});
  }
  assert.throws(()=>safeGlob.sync('a'.repeat(4097)),RangeError);
  assert.throws(()=>safeGlob.sync(Array(257).fill('*.js')),RangeError);
});

void test('unsupported API options cannot silently change compiler semantics', () => {
  assert.throws(()=>safeGlob.sync('*.js',{ignore:['private/**']}),/Unsupported glob option/);
  assert.throws(()=>safeGlob.sync([null]),TypeError);
  assert.throws(()=>safeGlob.sync('*.js',{cwd:42}),TypeError);
});
