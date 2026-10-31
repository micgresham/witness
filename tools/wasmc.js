// A host for the self-hosted Witness compiler: run a compiler module (a WebAssembly module
// produced by compiler/driver.wtn) on a source file and write the module it produces.
//
//   node --stack-size=200000 tools/wasmc.js compiler.wasm source.wtn out.wasm
//
// The host does three things the language does not: it loads the module, it puts the
// source in the module's memory as a length word and the bytes, and it reads the answer
// back. A module imports only the capabilities it uses, from a module named for the
// effect (`Console.print`); this host grants Console and nothing else, so a compiler that
// asked for the network would not load. Everything else -- reading, type
// checking, lowering, encoding -- happens inside the module.
'use strict';
const fs = require('fs');

function compile(compilerWasm, source, entry = 'drive') {
  const printed = [];
  let inst;
  const imports = {Console: {print: (p) => {
    const dv = new DataView(inst.exports.memory.buffer);
    const n = Number(dv.getBigInt64(Number(p), true));
    printed.push(Buffer.from(inst.exports.memory.buffer, Number(p) + 8, n).toString('utf8'));
  }}};
  inst = new WebAssembly.Instance(new WebAssembly.Module(compilerWasm), imports);
  const x = inst.exports;
  // a counted string when the module counts references (rt_new writes its length and header)
  const p = x.rt_new ? x.rt_new(BigInt(source.length)) : x.rt_alloc(BigInt(8 + source.length));
  new DataView(x.memory.buffer).setBigInt64(Number(p), BigInt(source.length), true);
  new Uint8Array(x.memory.buffer).set(source, Number(p) + 8);
  const r = x[entry](p);
  const n = Number(new DataView(x.memory.buffer).getBigInt64(Number(r), true));
  const out = Buffer.from(x.memory.buffer.slice(Number(r) + 8, Number(r) + 8 + n));
  return {out, printed, memory: x.memory.buffer.byteLength};
}

module.exports = {compile};

if (require.main === module) {
  const [wasmPath, srcPath, outPath, entry] = process.argv.slice(2);
  if (!outPath) { console.error('usage: wasmc.js compiler.wasm source.wtn out [entry]'); process.exit(2); }
  const {out, printed, memory} = compile(fs.readFileSync(wasmPath), fs.readFileSync(srcPath), entry || 'drive');
  for (const line of printed) console.log(line);
  const isWasm = out[0] === 0 && out[1] === 0x61 && out[2] === 0x73 && out[3] === 0x6d;
  const isElf = out[0] === 0x7f && out[1] === 0x45 && out[2] === 0x4c && out[3] === 0x46;
  if (isWasm || isElf) {
    fs.writeFileSync(outPath, out);
    console.error(`wrote ${out.length} bytes (memory ${memory})`);
  } else {
    console.error(out.toString('utf8'));
    process.exit(1);
  }
}
