import { pathToFileURL } from 'node:url';
const {Workbook,SpreadsheetFile}=await import(pathToFileURL(process.argv[2]).href);
const w=Workbook.create();
for(const name of ['Training Data','Device Catalog','Method']) {
 const s=w.worksheets.add(name);
 s.getRange('A1').values=[['Header']];
 s.getRange('A1:L1').format.fill='#183B56';
 s.getRange('A1:L1').format.font.color='#FFFFFF';
}
const file=await SpreadsheetFile.exportXlsx(w);
await file.save('.gsm_build/template.xlsx');
