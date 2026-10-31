// Run a compiler compiled through the intermediate representation (compiler/lower_ir.wtn).
//
//   node --stack-size=200000 tools/irc.js compiler.wasm source.wtn out.wasm
//
// The source goes in as a counted string made by the module's own `rt_new`; `drive` answers
// the module it wrote (or the reason it did not); that is written out, released, and what the
// heap reached is printed, since this compiler frees what it no longer holds.
const fs = require('fs');
const [wasmPath, srcPath, outPath] = process.argv.slice(2);
let x;
const dv = () => new DataView(x.memory.buffer);
const read = (p) => {
  const n = Number(dv().getBigInt64(Number(p), true));
  return Buffer.from(new Uint8Array(x.memory.buffer, Number(p) + 8, n));
};
const printed = [];
x = new WebAssembly.Instance(new WebAssembly.Module(fs.readFileSync(wasmPath)),
  {Console: {print: (p) => printed.push(read(p).toString())}}).exports;
const src = fs.readFileSync(srcPath);
const p = x.rt_new(BigInt(src.length));
new Uint8Array(x.memory.buffer).set(src, Number(p) + 8);
const out = x.drive(p);
fs.writeFileSync(outPath, read(out));
x.rt_release(out);
x.rt_release(p);
console.log(JSON.stringify({heap: Number(x.rt_alloc(0n)), printed}));
