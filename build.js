const esbuild = require('esbuild');

const bannerCode = `
import nodeNet from 'node:net';
import nodeCrypto from 'node:crypto';
import nodeStream from 'node:stream';
import nodePath from 'node:path';
import nodeFs from 'node:fs';
import nodeChildProcess from 'node:child_process';
import nodeDns from 'node:dns';
import nodeTls from 'node:tls';
import nodeZlib from 'node:zlib';
import nodeStringDecoder from 'node:string_decoder';
import nodeAssert from 'node:assert';
import nodeBuffer from 'node:buffer';
import nodeEvents from 'node:events';
import nodeUtil from 'node:util';

const nodeModules = {
  'net': nodeNet,
  'node:net': nodeNet,
  'crypto': nodeCrypto,
  'node:crypto': nodeCrypto,
  'stream': nodeStream,
  'node:stream': nodeStream,
  'path': nodePath,
  'node:path': nodePath,
  'fs': nodeFs,
  'node:fs': nodeFs,
  'child_process': nodeChildProcess,
  'node:child_process': nodeChildProcess,
  'dns': nodeDns,
  'node:dns': nodeDns,
  'tls': nodeTls,
  'node:tls': nodeTls,
  'zlib': nodeZlib,
  'node:zlib': nodeZlib,
  'string_decoder': nodeStringDecoder,
  'node:string_decoder': nodeStringDecoder,
  'assert': nodeAssert,
  'node:assert': nodeAssert,
  'buffer': nodeBuffer,
  'node:buffer': nodeBuffer,
  'events': nodeEvents,
  'node:events': nodeEvents,
  'util': nodeUtil,
  'node:util': nodeUtil
};

globalThis.require = function(x) {
  if (nodeModules[x]) {
    return nodeModules[x];
  }
  throw new Error('Dynamic require of "' + x + '" is not supported');
};
`;

esbuild.build({
  entryPoints: ['workers_keep_alive.js'],
  bundle: true,
  platform: 'node',
  format: 'esm',
  outfile: 'workers_keep_alive_dist.js',
  banner: {
    js: bannerCode
  },
  external: [
    'net', 'node:net',
    'crypto', 'node:crypto',
    'stream', 'node:stream',
    'path', 'node:path',
    'fs', 'node:fs',
    'child_process', 'node:child_process',
    'dns', 'node:dns',
    'tls', 'node:tls',
    'zlib', 'node:zlib',
    'string_decoder', 'node:string_decoder',
    'assert', 'node:assert',
    'buffer', 'node:buffer',
    'events', 'node:events',
    'util', 'node:util'
  ]
}).then(() => {
  console.log('Build complete successfully.');
}).catch((err) => {
  console.error('Build failed:', err);
  process.exit(1);
});
