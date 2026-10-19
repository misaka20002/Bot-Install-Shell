// 仅读取生产函数；Hapi 文件系统与 /proc 全部使用内存替身。
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert/strict');
const source = fs.readFileSync(path.join(__dirname, '../../Manage/SYS_Manage.sh'), 'utf8').replace(/\r\n/g, '\n');
const code = source.split("node - \"$version\" <<'NODE'\n")[1]?.split('\nNODE')[0];
assert.ok(code, '必须抽到真实 Hapi 检测器');
let pass = 0;
function run(options = {}, detector = code) {
    const root = '/root/.hapi/runtime';
    const output = [];
    const mock = {
        realpathSync: p => options.symlink ? '/other' : p,
        statSync: () => ({ isDirectory: () => true }),
        lstatSync: p => ({ isSymbolicLink: () => options.oldLink && p.endsWith('0.20.2') }),
        readdirSync: p => p === '/proc' ? ['1'] : ['0.20.2', '0.30.7', '0.31.0', 'unknown'],
        readlinkSync: p => {
            if (options.denied) throw Object.assign(new Error('denied'), {code: 'EACCES'});
            return options.running ? root + '/0.20.2/tools/helper' : '/usr/bin/init';
        },
        readFileSync: p => {
            if (p.includes('/proc/')) return '/sbin/init\0';
            if (options.badMarker) return 'different';
            return p.split('/').at(-2);
        }
    };
    let status = 0;
    try {
        vm.runInNewContext(detector, {
            require: name => name === 'fs' ? mock : name === 'path' ? path.posix : require(name),
            process: {argv: ['node', '-', options.version || 'hapi version: 0.30.7'], env: {HOME: '/root'}, pid: 999, exit: n => { throw {exit: n}; }},
            console: {log: x => output.push(x)}
        });
    } catch (e) { if (!('exit' in e)) throw e; status = e.exit; }
    return {status, output};
}
function check(name, test) { test(); pass++; console.log('OK ' + name); }
check('仅旧版本进入候选，当前与未来版本保留', () => assert.deepEqual(run().output, ['/root/.hapi/runtime/0.20.2']));
check('运行中跳过', () => assert.equal(run({running: true}).status, 1));
check('无法读取进程时跳过', () => assert.equal(run({denied: true}).status, 1));
check('版本无法识别时跳过', () => assert.equal(run({version: 'unknown'}).status, 1));
check('根目录软链接跳过', () => assert.equal(run({symlink: true}).status, 1));
check('旧目录软链接保留', () => assert.deepEqual(run({oldLink: true}).output, []));
check('资源标记不吻合时保留', () => assert.deepEqual(run({badMarker: true}).output, []));
check('反例：移除运行中保护会暴露删除候选', () => {
    const broken = code.replace('if (refs.some(', 'if (false && refs.some(');
    assert.notDeepEqual(run({running: true}, broken), run({running: true}));
});
console.log(`TOTAL pass=${pass} fail=0`);
