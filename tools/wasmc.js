// A host for the self-hosted Witness compiler: run a compiler module (a WebAssembly module
// produced by compiler/driver.wtn) on a source file and write the module it produces.
//
//   node --stack-size=200000 tools/wasmc.js compiler.wasm source.wtn out.wasm
//   node --stack-size=200000 tools/wasmc.js compiler.wasm source.wtn - drive_check
//
// The second checks the source instead (drive_check_mcu, _esp32 and _embedded for the other
// profiles), prints what it found and exits with the verdict. With drive_flatten the source
// is every module of compiler/ORDER as one `(modules ...)` form, and what is written is the
// compiler as one module: imports resolved by hash and spliced in (compiler/link.wtn).
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
  const checking = (entry || '').startsWith('drive_check');
  let answer;
  try {
    answer = compile(fs.readFileSync(wasmPath), fs.readFileSync(srcPath), entry || 'drive');
  } catch (ex) {
    if (!checking || !(ex instanceof WebAssembly.RuntimeError)) throw ex;
    // A trap is the compiled checker stopping, not a verdict: its Int is 64 bits where
    // the language's is unbounded, so a proof about a wide range can overflow it. Say so,
    // and never let it pass for an answer.
    console.log(`unread module the compiled checker stopped (${ex.message}), so no verdict is given\nunread`);
    process.exit(3);
  }
  const {out, printed, memory} = answer;
  for (const line of printed) console.log(line);
  if (checking) {
    // The checker answers its findings and, last, the verdict; the exit status is the
    // verdict's, as `witness check` has it: 0 accepted (with or without warnings), 1
    // rejected, 3 not read, so a script cannot take "not read" for "accepted".
    const text = out.toString('utf8');
    process.stdout.write(text.endsWith('\n') ? text : text + '\n');
    const verdict = text.trimEnd().split('\n').pop();
    process.exit(verdict === 'accept' || verdict === 'warn' ? 0 : verdict === 'reject' ? 1 : 3);
  }
  if (entry === 'drive_files') {
    // Several files at once (tools/pin.wtn's re-pinned modules): each path and its text,
    // NUL-separated, or a line saying why not.
    const text = out.toString('utf8');
    if (text.startsWith('error')) { console.error(text); process.exit(1); }
    const parts = text.split('\0');
    for (let i = 0; i + 1 < parts.length; i += 2) {
      fs.writeFileSync(parts[i], parts[i + 1]);
      console.error(`wrote ${parts[i]}`);
    }
    process.exit(0);
  }
  if (entry && !entry.startsWith('drive')) {
    // Any other entry gives text (tools/gen.wtn's backends, say), written where asked.
    fs.writeFileSync(outPath, out);
    process.exit(0);
  }
  if (entry === 'drive_flatten') {
    // The flattened compiler is source text; an answer that is not one says why.
    const text = out.toString('utf8');
    if (text.startsWith('(module ')) {
      fs.writeFileSync(outPath, out);
      console.error(`wrote ${out.length} bytes of source`);
      process.exit(0);
    }
    console.error(text);
    process.exit(1);
  }
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
