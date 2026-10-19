const axios = require("axios");

// ReByte Company / Central Hub location: 5.453240417145323, 100.2848625551094
const COMPANY_LOCATION = {
    lat: 5.453240417145323,
    lng: 100.2848625551094,
    address: "ReByte Central Hub, Penang"
};

/**
 * Calls public OSRM Routing Service to calculate driving duration and distance between two coordinates
 * OSRM expects coordinates in {longitude},{latitude} format.
 *
 * @param {Object} from - { lat: number, lng: number }
 * @param {Object} to - { lat: number, lng: number }
 * @returns {Promise<{ durationMinutes: number, distanceKm: number, durationSeconds: number, distanceMeters: number }>}
 */
async function getOsrmRoute(from, to) {
    try {
        const fromLng = Number(from.lng || from.lon);
        const fromLat = Number(from.lat);
        const toLng = Number(to.lng || to.lon);
        const toLat = Number(to.lat);

        if (isNaN(fromLng) || isNaN(fromLat) || isNaN(toLng) || isNaN(toLat)) {
            throw new Error(`Invalid coordinates for OSRM: from(${fromLat}, ${fromLng}), to(${toLat}, ${toLng})`);
        }

        const url = `http://router.project-osrm.org/route/v1/driving/${fromLng},${fromLat};${toLng},${toLat}?overview=false`;
        const res = await axios.get(url, { timeout: 6000 });

        if (res.data && res.data.routes && res.data.routes.length > 0) {
            const route = res.data.routes[0];
            const durationSeconds = route.duration || 0;
            const distanceMeters = route.distance || 0;
            return {
                durationSeconds: Math.round(durationSeconds),
                durationMinutes: Math.max(1, Math.ceil(durationSeconds / 60)),
                distanceMeters: Math.round(distanceMeters),
                distanceKm: Number((distanceMeters / 1000).toFixed(2))
            };
        }
    } catch (err) {
        console.warn("OSRM routing request failed or timed out, falling back to Haversine estimation:", err.message);
    }

    // Fallback: Haversine distance with average 40 km/h driving speed in urban Malaysia
    return calculateHaversineFallback(from, to);
}

/**
 * Fallback distance and duration estimation using Haversine formula
 */
function calculateHaversineFallback(from, to) {
    const lat1 = Number(from.lat);
    const lon1 = Number(from.lng || from.lon);
    const lat2 = Number(to.lat);
    const lon2 = Number(to.lng || to.lon);

    const R = 6371; // km
    const dLat = (lat2 - lat1) * (Math.PI / 180);
    const dLon = (lon2 - lon1) * (Math.PI / 180);
    const a =
        Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(lat1 * (Math.PI / 180)) * Math.cos(lat2 * (Math.PI / 180)) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    const distanceKm = Number((R * c).toFixed(2));
    
    // Average urban speed: 35 km/h + 5 min traffic buffer
    const durationMinutes = Math.max(5, Math.ceil((distanceKm / 35) * 60) + 5);

    return {
        durationSeconds: durationMinutes * 60,
        durationMinutes,
        distanceMeters: Math.round(distanceKm * 1000),
        distanceKm
    };
}

module.exports = {
    COMPANY_LOCATION,
    getOsrmRoute
};
