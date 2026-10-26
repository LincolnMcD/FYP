const fs = require('fs');
const content = fs.readFileSync('reByteWebsite/listingModule/listing.html', 'utf8');
const lines = content.split(/\r?\n/);
lines.forEach((l, i) => {
  if (l.toLowerCase().includes('edit') && (l.includes('function') || l.includes('class=') || l.includes('onclick') || l.includes('href') || l.includes('action'))) {
    console.log((i+1) + ': ' + l.trim());
  }
});
