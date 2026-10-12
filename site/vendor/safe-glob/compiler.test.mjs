import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { build } from 'vite';
import dynamicImport from 'vite-plugin-dynamic-import';

await test('the actual compiler dependency resolves variable imports through the replacement', async () => {
  const root=mkdtempSync(join(tmpdir(),'orbit-compiler-glob-'));
  try {
    mkdirSync(join(root,'modules'));
    writeFileSync(join(root,'modules','alpha.js'),'export default "synthetic-module-alpha";');
    writeFileSync(join(root,'modules','beta.js'),'export default "synthetic-module-beta";');
    writeFileSync(join(root,'entry.js'),'export function load(name) { return import("./modules/" + name + ".js"); }');
    const result=await build({configFile:false,root,logLevel:'silent',plugins:[dynamicImport()],build:{write:false,minify:false,lib:{entry:join(root,'entry.js'),formats:['es']}}});
    const chunks=(Array.isArray(result)?result:[result]).flatMap(row=>row.output).filter(row=>row.type==='chunk');
    assert.ok(chunks.some(row=>row.code.includes('synthetic-module-alpha')));
    assert.ok(chunks.some(row=>row.code.includes('synthetic-module-beta')));
    const entry=chunks.find(row=>row.isEntry);
    assert.ok(entry.code.includes('./modules/alpha.js'));
    assert.ok(entry.code.includes('./modules/beta.js'));
  } finally { rmSync(root,{recursive:true,force:true}); }
});
