const fs = require("node:fs/promises");
const path = require("node:path");

const catalogPath = path.join(__dirname, "gsmarena-models.csv");

async function getCatalogModels(brand) {
    const csv = await fs.readFile(catalogPath, "utf8");
    const year = new Date().getFullYear();
    const models = new Set();
    for (const line of csv.split(/\r?\n/).slice(1)) {
        const row = /^"((?:[^"]|"")*)","((?:[^"]|"")*)",(?:"[^"]*\b(\d{4})\b[^"]*"|(\d{4}))(?:,|$)/.exec(line);
        if (row && row[1].toLowerCase() === brand.toLowerCase()) {
            const announcedYear = Number(row[3] || row[4]);
            if (announcedYear < year - 10 || announcedYear > year) continue;

            const model = row[2].replaceAll('""', '"');
            const prefix = `${row[1]} `;
            models.add(model.toLowerCase().startsWith(prefix.toLowerCase()) ? model.slice(prefix.length) : model);
        }
    }
    return [...models];
}

const identity = value => String(value || "").toLowerCase().replace(/[^a-z0-9]/g, "");
const splitCodes = value => String(value || "").split(/[,|;\n]/).map(identity).filter(Boolean);

const parse = line => Array.from(line.matchAll(/(?:^|,)(?:"((?:[^"]|"")*)"|([^,"]*))/g),
    ([, quoted, plain]) => quoted == null ? plain : quoted.replaceAll('""', '"'));

async function getCatalogModelCodes(brand) {
    const brandKey = identity(brand);
    if (!brandKey) return [];
    const csv = await fs.readFile(catalogPath, "utf8").catch(error => {
        if (error.code === "ENOENT") return "";
        throw error;
    });
    const [header, ...lines] = csv.split(/\r?\n/);
    const codesIndex = parse(header.replace(/^\uFEFF/, ""))
        .findIndex(column => ["modelCode", "model_codes"].includes(column));
    if (codesIndex < 0) return [];

    return lines.filter(line => identity(line.slice(0, line.indexOf(","))) === brandKey)
        .map(line => {
            const fields = parse(line);
            const raw = fields[codesIndex] || "";
            const codes = raw.startsWith("[") ? JSON.parse(raw) : raw.split(/[,|;\n]/);
            return {
                name: fields[1],
                codes: codes.map(code => code.trim()).filter(code => identity(code).length >= 4),
            };
        });
}

function catalogModelKey(brand, name) {
    const key = identity(name);
    const prefix = identity(brand);
    return key.startsWith(prefix) ? key.slice(prefix.length) : key;
}

function findCatalogCodes(brand, name, rows) {
    const key = catalogModelKey(brand, name);
    return [...new Set(rows.filter(row => catalogModelKey(brand, row.name) === key)
        .flatMap(row => row.codes))];
}

async function getCatalogModelName(brand, modelCode, expectedModel) {
    const code = identity(modelCode);
    if (!code) return null;
    const rows = await getCatalogModelCodes(brand);
    const matches = rows.filter(row => row.codes.some(candidate => identity(candidate) === code));
    const expectedKey = catalogModelKey(brand, expectedModel);
    const exact = matches.find(row => catalogModelKey(brand, row.name) === expectedKey);
    if (exact) return exact.name;
    const names = [...new Set(matches.map(row => row.name))];
    return names.length === 1 ? names[0] : null;
}

async function getCatalogSpecs(brand, model, modelCode, ram) {
    const csv = await fs.readFile(catalogPath, "utf8").catch(error => {
        if (error.code === "ENOENT") return "";
        throw error;
    });
    const [header, ...lines] = csv.split(/\r?\n/);
    const columns = parse(header.replace(/^\uFEFF/, ""));
    const specsIndex = columns.findIndex(column => ["specs", "specifications"].includes(column));
    const codesIndex = columns.findIndex(column => ["modelCode", "model_codes"].includes(column));
    if (specsIndex < 0 || !identity(brand)) return null;
    const codes = new Set(splitCodes(modelCode));
    const modelKey = identity(model);
    const brandKey = identity(brand);
    const withoutBrand = key => key.startsWith(brandKey) ? key.slice(brandKey.length) : key;
    const candidates = [];
    for (const line of lines) {
        if (identity(line.slice(0, line.indexOf(","))) !== brandKey) continue;
        const fields = parse(line);
        if (identity(fields[0]) !== brandKey || !fields[specsIndex]) continue;
        const nameMatches = Boolean(modelKey) && withoutBrand(identity(fields[1])) === withoutBrand(modelKey);
        const rawCodes = fields[codesIndex];
        const variants = rawCodes?.startsWith("[") ? splitCodes(JSON.parse(rawCodes).join(",")) : splitCodes(rawCodes);
        const codeMatches = variants.some(code => codes.has(code));
        if (nameMatches || codeMatches) candidates.push({ score: Number(nameMatches) + 2 * Number(codeMatches), raw: fields[specsIndex] });
    }
    candidates.sort((a, b) => b.score - a.score);
    if (!candidates.length || candidates[0].score === candidates[1]?.score && candidates[0].raw !== candidates[1].raw) return null;

    const rows = JSON.parse(candidates[0].raw).flatMap(section => section.rows);
    const value = key => rows.find(row => row.key === key)?.value || "";
    const main = value("cam1modules").split("\n");
    return {
        screen: [value("displaysize"), value("displaytype"), value("displayresolution")].filter(Boolean).join(" · "),
        rear_camera: value("cam1modules"),
        charging: rows.find(row => /^charging$/i.test(row.label))?.value || "",
        soc: value("chipset"),
        gpu: value("gpu"),
        ram,
        storage: value("internalmemory"),
        main_camera: main[0],
        ultra_camera: main.find(line => /ultrawide|ultra-wide/i.test(line)),
        tele_camera: main.find(line => /telephoto/i.test(line)),
        selfie_camera: value("cam2modules"),
        battery: value("batdescription1"),
        dimensions: value("dimensions"),
        weight: value("weight"),
        ip_rating: value("bodyother").match(/\bIP\d{2}[A-Z]?\b/i)?.[0],
        os: value("os"),
        connectivity: ["wlan", "bluetooth", "nfc", "usb"].map(key => value(key) && `${key.toUpperCase()}: ${value(key)}`).filter(Boolean).join(" · ")
    };
}

module.exports = { catalogPath, getCatalogModels, getCatalogSpecs, getCatalogModelCodes, findCatalogCodes, getCatalogModelName };
