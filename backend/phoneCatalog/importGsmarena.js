const fs = require("node:fs/promises");
const { setTimeout: pause } = require("node:timers/promises");
const brands = require("./brands");
const { catalogPath } = require("./gsmarena");

const progressPath = catalogPath + ".progress.json";
const progressVersion = 2;
const csvField = value => '"' + value.replace(/\s+/g, " ").trim().replaceAll('"', '""') + '"';

async function saveAtomically(file, content) {
    const temporary = `${file}.${process.pid}.tmp`;
    await fs.writeFile(temporary, content, "utf8");
    await fs.rename(temporary, file);
}

async function main() {
    const { createScraper } = await import("../gsmarenaWebScraper/scraper.js");
    const now = new Date();
    const year = now.getFullYear();
    const scraper = createScraper(async url => {
        await pause(750);
        const response = await fetch(url, { signal: AbortSignal.timeout(15000) });
        if (!response.ok) throw new Error(`GSMArena returned HTTP ${response.status} for ${url}`);
        return response;
    }, () => now, 1);
    let progress = { version: progressVersion, year, brands: {} };
    try {
        const saved = JSON.parse(await fs.readFile(progressPath, "utf8"));
        if (saved.version === progressVersion && saved.year === year) progress = saved;
    } catch (error) {
        if (error.code !== "ENOENT") throw error;
    }

    try {
        for (const brand of brands) {
            const entry = progress.brands[brand] ??= { complete: false, models: {} };
            if (entry.complete) continue;
            const result = await scraper.byBrand(brand, { yearOnly: true });
            if (result.status !== "brand" || !result.phones.length) throw new Error(`No catalog data returned for ${brand}.`);
            const prefix = `${result.brand} `;
            let sinceCheckpoint = 0;
            for (const phone of result.phones) {
                if (entry.models[phone.id]) continue;
                const details = await scraper.byId(phone.id);
                if (details.status !== "found") throw new Error(`No specifications returned for ${phone.name}.`);
                const { modelCodes, sections } = details.phone;
                const fields = sections.flatMap(section => section.rows);
                entry.models[phone.id] = {
                    model: phone.name.startsWith(prefix) ? phone.name.slice(prefix.length) : phone.name,
                    year: phone.year,
                    modelCodes,
                    msrp: fields.find(field => /\bmsrp\b/i.test(field.label))?.value || "",
                    reportedPrice: fields.find(field => field.key === "price" || /^price$/i.test(field.label))?.value || "",
                    specs: sections,
                    url: phone.url
                };
                if (++sinceCheckpoint === 20) {
                    await saveAtomically(progressPath, JSON.stringify(progress));
                    sinceCheckpoint = 0;
                }
            }
            entry.complete = true;
            await saveAtomically(progressPath, JSON.stringify(progress));
            console.log(`${brand}: ${Object.keys(entry.models).length} models`);
        }
    } catch (error) {
        await saveAtomically(progressPath, JSON.stringify(progress));
        throw error;
    }

    const rows = brands.flatMap(brand => Object.values(progress.brands[brand].models).map(record =>
        [
            csvField(brand), csvField(record.model), record.year, csvField(JSON.stringify(record.modelCodes)),
            csvField(record.msrp), csvField(record.reportedPrice), csvField(JSON.stringify(record.specs)), csvField(record.url)
        ].join(",")
    ));
    const unique = [...new Set(rows)];
    await saveAtomically(catalogPath, [
        "brand,model,announcement_year,model_codes,msrp,reported_price,specifications,source_url", ...unique, ""
    ].join("\n"));
    await fs.unlink(progressPath);
    console.log(`Saved ${unique.length} records to ${catalogPath}`);
}

main().catch(error => {
    console.error(error.message);
    process.exitCode = 1;
});
