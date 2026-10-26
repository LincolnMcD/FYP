const fs = require('fs');
const path = require('path');

function searchPatterns(dir, exts) {
  const matches = [];
  function walk(d) {
    let files;
    try {
      files = fs.readdirSync(d, { withFileTypes: true });
    } catch (_) { return; }
    for (const f of files) {
      const full = path.join(d, f.name);
      if (f.isDirectory() && f.name !== 'node_modules' && f.name !== '.git' && f.name !== 'build' && f.name !== '.dart_tool') {
        walk(full);
      } else if (f.isFile() && exts.some(e => f.name.endsWith(e))) {
        try {
          const content = fs.readFileSync(full, 'utf8');
          const lines = content.split(/\r?\n/);
          lines.forEach((line, idx) => {
            const l = line.toLowerCase();
            if (l.includes('brand') && (l.includes('model') || l.includes('modelname'))) {
              if (line.includes('$') || line.includes('+') || line.includes('`')) {
                matches.push({ file: full, line: idx + 1, content: line.trim() });
              }
            }
          });
        } catch (_) {}
      }
    }
  }
  walk(dir);
  return matches;
}

console.log('=== Flutter Mobile Matches ===');
const dartMatches = searchPatterns('rebyte_mobile', ['.dart']);
dartMatches.forEach(m => console.log(m.file + ':' + m.line + ' ' + m.content));

console.log('\n=== Website Matches ===');
const webMatches = searchPatterns('reByteWebsite', ['.html', '.js']);
webMatches.forEach(m => console.log(m.file + ':' + m.line + ' ' + m.content));
