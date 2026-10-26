const fs = require('fs');
const content = fs.readFileSync('reByteWebsite/listingModule/listing.html', 'utf8');
const lines = content.split(/\r?\n/);
lines.forEach((l, i) => {
  if (l.toLowerCase().includes('scroll') || l.includes('href="#"') || l.includes('page-btn') || l.includes('paginationControls')) {
    console.log((i+1) + ': ' + l.trim());
  }
});
