(function (g) {
  // Host bridge: every call goes through the synchronous `openrest` message channel as [name, ...args].
  const H = new Proxy({}, {
    get: (_t, name) => (...args) => {
      const r = sendMessage('openrest', JSON.stringify([String(name), ...args]));
      return r === undefined ? null : r;
    },
  });
  g.__hostError = (m) => H.error(String(m));
  g.__pending = 0;
  g.__runDone = true;
  g.__sleepers = [];
  g.__state = function () {
    if (g.__runDone && g.__pending === 0) return -2;
    if (g.__sleepers.length === 0) return -1;
    const now = Date.now();
    return Math.max(0, Math.min.apply(null, g.__sleepers.map((s) => s.at)) - now);
  };
  g.__wakeDue = function () {
    const now = Date.now();
    const due = g.__sleepers.filter((s) => s.at <= now);
    g.__sleepers = g.__sleepers.filter((s) => s.at > now);
    due.forEach((s) => s.resolve());
  };
  const jp = (s) => (s == null ? undefined : JSON.parse(s));
  const js = (v) => (v === undefined ? null : JSON.stringify(v));

  g.__reqState = null;
  g.__loadReq = function () { g.__reqState = JSON.parse(H.reqJson()); };
  g.__saveReq = function () {
    const s = g.__reqState;
    if (!s) return;
    const copy = Object.assign({}, s);
    if (copy.body !== null && typeof copy.body === 'object') copy.body = JSON.stringify(copy.body);
    H.applyReq(JSON.stringify(copy));
  };

  g.req = {
    getUrl: () => g.__reqState.url,
    setUrl: (u) => { g.__reqState.url = String(u); },
    getMethod: () => g.__reqState.method,
    setMethod: (m) => { g.__reqState.method = String(m).toUpperCase(); },
    getName: () => g.__reqState.name,
    getHeader: (n) => { const h = g.__reqState.headers; const k = Object.keys(h).find((x) => x.toLowerCase() === String(n).toLowerCase()); return k === undefined ? undefined : h[k]; },
    getHeaders: () => g.__reqState.headers,
    setHeader: (n, v) => { g.__reqState.headers[n] = String(v); },
    setHeaders: (o) => { g.__reqState.headers = Object.assign({}, o); },
    deleteHeader: (n) => { const h = g.__reqState.headers; Object.keys(h).filter((x) => x.toLowerCase() === String(n).toLowerCase()).forEach((k) => delete h[k]); },
    getBody: () => { const b = g.__reqState.body; if (typeof b === 'string') { try { return JSON.parse(b); } catch (e) { return b; } } return b; },
    setBody: (b) => { g.__reqState.body = b; },
    getTimeout: () => g.__reqState.timeout,
    setTimeout: (t) => { g.__reqState.timeout = t; },
    setMaxRedirects: () => {},
    getAuthMode: () => g.__reqState.authMode,
  };

  function getPath(obj, path) {
    if (path === undefined || path === null || path === '') return obj;
    let p = String(path).trim();
    if (p.startsWith('$')) p = p.slice(1);
    const parts = p.match(/[^.\[\]'"]+/g) || [];
    let cur = obj;
    for (const k of parts) {
      if (cur === null || cur === undefined) return undefined;
      cur = cur[k];
    }
    return cur;
  }
  g.__getPath = getPath;

  g.__loadRes = function () {
    const r = JSON.parse(H.resJson());
    if (!r) { g.res = undefined; return; }
    let body = r.body;
    try { body = JSON.parse(r.body); } catch (e) {}
    const headers = {};
    (r.headers || []).forEach((h) => { headers[h[0].toLowerCase()] = h[1]; });
    const f = function (path) { return getPath(f.body, path); };
    f.status = r.status; f.statusText = r.statusText; f.headers = headers; f.body = body;
    f.responseTime = r.time; f.size = r.size; f.url = r.url;
    f.getStatus = () => f.status;
    f.getStatusText = () => f.statusText;
    f.getHeader = (n) => f.headers[String(n).toLowerCase()];
    f.getHeaders = () => f.headers;
    f.getBody = () => f.body;
    f.setBody = (b) => { f.body = b; };
    f.getResponseTime = () => f.responseTime;
    f.getSize = () => ({ body: f.size, headers: 0, total: f.size });
    f.getUrl = () => f.url;
    g.res = f;
  };

  g.bru = {
    getVar: (k) => jp(H.getVar(String(k))),
    setVar: (k, v) => H.setVar(String(k), js(v)),
    hasVar: (k) => H.getVar(String(k)) != null,
    deleteVar: (k) => H.deleteVar(String(k)),
    deleteAllVars: () => H.deleteAllVars(),
    getEnvVar: (k) => jp(H.getEnvVar(String(k))),
    setEnvVar: (k, v) => H.setEnvVar(String(k), js(v)),
    getEnvName: () => H.envName(),
    getCollectionName: () => H.collectionName(),
    getCollectionVar: (k) => jp(H.getCollVar(String(k))),
    getProcessEnv: (k) => H.getProcessEnv(String(k)),
    getFolderVar: (k) => jp(H.getCollVar(String(k))),
    getRequestVar: (k) => jp(H.getVar(String(k))),
    interpolate: (s) => H.interpolate(String(s)),
    sleep: (ms) => new Promise((resolve) => { g.__sleepers.push({ at: Date.now() + Math.min(Math.max(Math.trunc(Number(ms)) || 0, 0), 60000), resolve }); }),
    setNextRequest: (n) => H.nextReq(n === null ? null : String(n)),
    cwd: () => H.cwd(),
    runner: {
      skipRequest: () => H.skip(),
      stopExecution: () => H.stop(),
      setNextRequest: (n) => H.nextReq(n === null ? null : String(n)),
    },
  };

  const fmt = (a) => (typeof a === 'string' ? a : (() => { try { return JSON.stringify(a); } catch (e) { return String(a); } })());
  g.console = {
    log: (...a) => H.log('log', a.map(fmt).join(' ')),
    info: (...a) => H.log('info', a.map(fmt).join(' ')),
    warn: (...a) => H.log('warn', a.map(fmt).join(' ')),
    error: (...a) => H.log('error', a.map(fmt).join(' ')),
    debug: (...a) => H.log('debug', a.map(fmt).join(' ')),
  };
  g.btoa = (s) => H.btoa(String(s));
  g.atob = (s) => H.atob(String(s));

  g.test = function (name, fn) {
    try {
      const r = fn();
      if (r && typeof r.then === 'function') {
        g.__pending++;
        r.then(() => { g.__pending--; H.testResult(String(name), true, ''); }, (e) => { g.__pending--; H.testResult(String(name), false, String((e && e.message) || e)); });
      } else H.testResult(String(name), true, '');
    } catch (e) { H.testResult(String(name), false, String((e && e.message) || e)); }
  };
  g.it = g.test;
  g.describe = function (name, fn) { fn(); };

  const inspect = (v) => { try { return typeof v === 'string' ? JSON.stringify(v) : (v === undefined ? 'undefined' : JSON.stringify(v)); } catch (e) { return String(v); } };
  const deepEq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  const typeOf = (v) => (v === null ? 'null' : Array.isArray(v) ? 'array' : typeof v);
  const CHAIN = ['to', 'be', 'been', 'is', 'that', 'which', 'and', 'has', 'have', 'with', 'at', 'of', 'same', 'but', 'does', 'still', 'also', 'a_', 'an_'];

  function mk(val, neg, deep) {
    const check = (cond, msg, nmsg) => {
      if (neg ? cond : !cond) throw new Error(neg ? (nmsg || 'expected ' + inspect(val) + ' not to ' + msg) : 'expected ' + inspect(val) + ' to ' + msg);
    };
    const self = {};
    const ret = () => proxy;
    const methods = {
      equal: (x) => { check(deep ? deepEq(val, x) : val === x, 'equal ' + inspect(x)); return ret(); },
      eql: (x) => { check(deepEq(val, x), 'deeply equal ' + inspect(x)); return ret(); },
      above: (x) => { check(val > x, 'be above ' + x); return ret(); },
      least: (x) => { check(val >= x, 'be at least ' + x); return ret(); },
      below: (x) => { check(val < x, 'be below ' + x); return ret(); },
      most: (x) => { check(val <= x, 'be at most ' + x); return ret(); },
      within: (a, b) => { check(val >= a && val <= b, 'be within ' + a + '..' + b); return ret(); },
      property: (n, v) => {
        const has = val !== null && val !== undefined && n in Object(val);
        check(has, 'have property ' + inspect(n));
        if (v !== undefined && !neg) check(deepEq(val[n], v), 'have property ' + inspect(n) + ' of ' + inspect(v));
        return mk(has ? val[n] : undefined, false, false);
      },
      include: (x) => {
        let ok;
        if (typeof val === 'string') ok = val.includes(x);
        else if (Array.isArray(val)) ok = val.some((e) => deepEq(e, x));
        else if (val && typeof val === 'object' && typeof x === 'object') ok = Object.keys(x).every((k) => deepEq(val[k], x[k]));
        else ok = false;
        check(ok, 'include ' + inspect(x)); return ret();
      },
      keys: (...ks) => { const kk = Array.isArray(ks[0]) ? ks[0] : ks; check(kk.every((k) => k in Object(val)), 'have keys ' + inspect(kk)); return ret(); },
      lengthOf: (n) => { check(val != null && val.length === n, 'have length ' + n + ' (got ' + (val && val.length) + ')'); return ret(); },
      match: (re) => { check(re.test(val), 'match ' + re); return ret(); },
      string: (s) => { check(typeof val === 'string' && val.includes(s), 'contain string ' + inspect(s)); return ret(); },
      oneOf: (l) => { check(l.some((e) => deepEq(e, val)), 'be one of ' + inspect(l)); return ret(); },
      satisfy: (fn) => { check(!!fn(val), 'satisfy the predicate'); return ret(); },
      instanceof: (c) => { check(val instanceof c, 'be an instance of ' + (c && c.name)); return ret(); },
      members: (m) => { check(Array.isArray(val) && m.every((x) => val.some((e) => deepEq(e, x))), 'have members ' + inspect(m)); return ret(); },
      closeTo: (x, d) => { check(Math.abs(val - x) <= d, 'be close to ' + x); return ret(); },
      a: (t) => { check(typeOf(val) === String(t).toLowerCase(), 'be a ' + t + ' (is ' + typeOf(val) + ')'); return ret(); },
    };
    const aliases = {
      equals: 'equal', eq: 'equal', eqls: 'eql', gt: 'above', greaterThan: 'above', gte: 'least', lt: 'below', lessThan: 'below', lte: 'most',
      includes: 'include', contain: 'include', contains: 'include', lengthOf: 'lengthOf', length: 'length', an: 'a', string_: 'string',
      matches: 'match', ownProperty: 'property', haveOwnProperty: 'property', throw: 'throw',
    };
    const flags = {
      true: () => { check(val === true, 'be true'); },
      false: () => { check(val === false, 'be false'); },
      null: () => { check(val === null, 'be null'); },
      undefined: () => { check(val === undefined, 'be undefined'); },
      NaN: () => { check(Number.isNaN(val), 'be NaN'); },
      exist: () => { check(val !== null && val !== undefined, 'exist'); },
      ok: () => { check(!!val, 'be truthy'); },
      empty: () => { check(val == null || (typeof val === 'object' && !Array.isArray(val) ? Object.keys(val).length === 0 : val.length === 0), 'be empty'); },
    };
    const proxy = new Proxy(self, {
      get(t, p) {
        if (typeof p === 'symbol') return undefined;
        if (p === 'not') return mk(val, !neg, deep);
        if (p === 'deep') return mk(val, neg, true);
        if (p === 'length') {
          const sub = mk(val == null ? undefined : val.length, neg, deep);
          const fn = (n) => methods.lengthOf(n);
          return new Proxy(fn, { get: (tt, pp) => (pp in tt ? tt[pp] : sub[pp]) });
        }
        if (p === 'a' || p === 'an') return methods.a;
        if (p in flags) { flags[p](); return proxy; }
        if (p === 'throw') return () => { let threw = false; try { val(); } catch (e) { threw = true; } check(threw, 'throw'); return proxy; };
        if (CHAIN.includes(p)) return proxy;
        const m = aliases[p] || p;
        if (m in methods) return methods[m];
        if (p === 'then') return undefined;
        return proxy;
      },
    });
    return proxy;
  }
  g.expect = (v) => mk(v, false, false);
  g.require = function (name) {
    if (name === 'chai') return { expect: g.expect, assert: {} };
    throw new Error("Cannot find module '" + name + "' (only 'chai' is available in OpenRest scripts)");
  };

  g.__assert = function (expr, spec) {
    const m = String(spec).trim().match(/^(\S+)\s*([\s\S]*)$/);
    const op = m ? m[1] : 'eq';
    let rhsSrc = m ? m[2] : '';
    rhsSrc = H.interpolate(rhsSrc);
    let actual;
    try { actual = (0, eval)('(' + expr + ')'); } catch (e) { actual = undefined; }
    const ev = (src) => { try { return (0, eval)('(' + src + ')'); } catch (e) { return src; } };
    const rhs = ev(rhsSrc);
    let pass = false;
    switch (op) {
      case 'eq': pass = deepEq(actual, rhs) || actual == rhs; break;
      case 'neq': pass = !(deepEq(actual, rhs) || actual == rhs); break;
      case 'gt': pass = actual > rhs; break;
      case 'gte': pass = actual >= rhs; break;
      case 'lt': pass = actual < rhs; break;
      case 'lte': pass = actual <= rhs; break;
      case 'in': pass = Array.isArray(rhs) && rhs.some((x) => deepEq(x, actual)); break;
      case 'notIn': pass = Array.isArray(rhs) && !rhs.some((x) => deepEq(x, actual)); break;
      case 'contains': pass = actual != null && (typeof actual === 'string' ? actual.includes(rhs) : Array.isArray(actual) && actual.some((x) => deepEq(x, rhs))); break;
      case 'notContains': pass = !(actual != null && (typeof actual === 'string' ? actual.includes(rhs) : Array.isArray(actual) && actual.some((x) => deepEq(x, rhs)))); break;
      case 'length': pass = actual != null && actual.length === rhs; break;
      case 'matches': pass = new RegExp(rhsSrc.replace(/^\/|\/$/g, '')).test(actual); break;
      case 'notMatches': pass = !new RegExp(rhsSrc.replace(/^\/|\/$/g, '')).test(actual); break;
      case 'startsWith': pass = typeof actual === 'string' && actual.startsWith(rhs); break;
      case 'endsWith': pass = typeof actual === 'string' && actual.endsWith(rhs); break;
      case 'between': { const b = rhsSrc.split(',').map((x) => Number(x.trim())); pass = actual >= b[0] && actual <= b[1]; break; }
      case 'isEmpty': pass = actual == null || (typeof actual === 'object' && !Array.isArray(actual) ? Object.keys(actual).length === 0 : actual.length === 0); break;
      case 'isNotEmpty': pass = !(actual == null || (typeof actual === 'object' && !Array.isArray(actual) ? Object.keys(actual).length === 0 : actual.length === 0)); break;
      case 'isNull': pass = actual === null; break;
      case 'isUndefined': pass = actual === undefined; break;
      case 'isDefined': pass = actual !== undefined; break;
      case 'isTruthy': pass = !!actual; break;
      case 'isFalsy': pass = !actual; break;
      case 'isJson': pass = actual !== null && typeof actual === 'object'; break;
      case 'isNumber': pass = typeof actual === 'number'; break;
      case 'isString': pass = typeof actual === 'string'; break;
      case 'isBoolean': pass = typeof actual === 'boolean'; break;
      case 'isArray': pass = Array.isArray(actual); break;
      default: return JSON.stringify({ pass: false, msg: 'Unknown operator: ' + op });
    }
    return JSON.stringify({ pass, msg: pass ? '' : 'expected ' + expr + ' (' + inspect(actual) + ') to ' + op + ' ' + rhsSrc });
  };

  g.__evalExpr = function (expr) {
    let v;
    try { v = (0, eval)('(' + expr + ')'); } catch (e) { return null; }
    return v === undefined ? null : JSON.stringify(v);
  };
})(globalThis);
