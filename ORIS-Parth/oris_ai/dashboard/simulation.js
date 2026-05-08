/**
 * simulation.js - O-RIS urban canyon physics and dashboard state
 * ==============================================================
 * Browser-side propagation model with obstacle-aware steering logic.
 */

const FREQ_GHZ = 3.5;
const FREQ_HZ = FREQ_GHZ * 1e9;
const C = 3e8;
const LAMBDA = C / FREQ_HZ;
const TX_POWER_DBM = 43.0;
const N_PANELS = 8;
const CELLS_PER_PANEL = 256;
const N_PHASE_ELEMENTS = N_PANELS * CELLS_PER_PANEL;
const PANEL_AREA = 0.23 * 0.23;
const NOISE_FLOOR_DBM = -100.0;
const GRID_SIZE = 200.0;
const STREET_GRID = [0, 40, 80, 120, 160, 200];
const STREET_WIDTH = 8;
const TOWER_POS = [8.0, 100.0];
const ORIS_POS = [104.0, 100.0];
const PANEL_AZIMUTHS = Array.from({ length: N_PANELS }, (_, i) => i * 45);

const CITY_STRUCTURES = [
    { x: 8, y: 8, w: 18, d: 22, h: 36, style: "office" },
    { x: 28, y: 8, w: 10, d: 20, h: 22, style: "brick" },
    { x: 8, y: 48, w: 14, d: 26, h: 32, style: "office" },
    { x: 24, y: 44, w: 14, d: 30, h: 28, style: "residential" },
    { x: 8, y: 88, w: 12, d: 24, h: 22, style: "residential" },
    { x: 22, y: 88, w: 16, d: 24, h: 30, style: "civic" },
    { x: 8, y: 128, w: 16, d: 24, h: 34, style: "office" },
    { x: 26, y: 126, w: 12, d: 28, h: 20, style: "brick" },
    { x: 8, y: 168, w: 14, d: 24, h: 26, style: "residential" },
    { x: 24, y: 168, w: 14, d: 22, h: 18, style: "civic" },

    { x: 48, y: 8, w: 12, d: 18, h: 40, style: "residential" },
    { x: 62, y: 8, w: 10, d: 18, h: 26, style: "brick" },
    { x: 48, y: 30, w: 26, d: 10, h: 14, style: "podium" },
    { x: 48, y: 48, w: 14, d: 24, h: 34, style: "office" },
    { x: 64, y: 48, w: 10, d: 24, h: 20, style: "brick" },
    { x: 48, y: 88, w: 12, d: 24, h: 22, style: "brick" },
    { x: 62, y: 88, w: 12, d: 24, h: 32, style: "residential" },
    { x: 48, y: 128, w: 12, d: 24, h: 18, style: "brick" },
    { x: 62, y: 128, w: 12, d: 24, h: 42, style: "office" },
    { x: 48, y: 168, w: 26, d: 24, h: 24, style: "residential" },

    { x: 88, y: 8, w: 10, d: 22, h: 30, style: "brick" },
    { x: 100, y: 8, w: 12, d: 22, h: 24, style: "residential" },
    { x: 114, y: 8, w: 18, d: 22, h: 38, style: "office" },
    { x: 88, y: 48, w: 14, d: 24, h: 46, style: "office" },
    { x: 104, y: 48, w: 12, d: 24, h: 30, style: "brick" },
    { x: 118, y: 48, w: 14, d: 24, h: 34, style: "civic" },
    { x: 88, y: 128, w: 14, d: 24, h: 36, style: "residential" },
    { x: 104, y: 128, w: 12, d: 24, h: 28, style: "brick" },
    { x: 118, y: 128, w: 14, d: 24, h: 44, style: "office" },
    { x: 88, y: 168, w: 10, d: 22, h: 26, style: "brick" },
    { x: 100, y: 168, w: 12, d: 22, h: 18, style: "residential" },
    { x: 114, y: 168, w: 18, d: 22, h: 34, style: "office" },

    { x: 136, y: 8, w: 16, d: 22, h: 22, style: "residential" },
    { x: 154, y: 8, w: 18, d: 22, h: 32, style: "office" },
    { x: 174, y: 8, w: 18, d: 22, h: 18, style: "civic" },
    { x: 136, y: 48, w: 14, d: 24, h: 30, style: "civic" },
    { x: 152, y: 48, w: 12, d: 24, h: 18, style: "brick" },
    { x: 166, y: 48, w: 12, d: 24, h: 24, style: "residential" },
    { x: 180, y: 48, w: 12, d: 24, h: 40, style: "office" },
    { x: 136, y: 128, w: 18, d: 24, h: 28, style: "office" },
    { x: 156, y: 128, w: 12, d: 24, h: 20, style: "brick" },
    { x: 170, y: 128, w: 22, d: 24, h: 34, style: "residential" },
    { x: 136, y: 168, w: 16, d: 22, h: 24, style: "residential" },
    { x: 154, y: 168, w: 18, d: 22, h: 36, style: "office" },
    { x: 174, y: 168, w: 18, d: 22, h: 26, style: "civic" }
];

const PARKS = [
    { x: 86, y: 84, w: 26, d: 28 },
    { x: 158, y: 84, w: 24, d: 28 }
];

const OBSTACLE_TYPES = {
    car: {
        key: "car",
        label: "Car",
        width: 3.2,
        depth: 6.0,
        height: 2.2,
        attenuation: 7.5,
        color: "#c84d44",
        category: "road"
    },
    truck: {
        key: "truck",
        label: "Truck",
        width: 3.8,
        depth: 9.0,
        height: 3.8,
        attenuation: 10.5,
        color: "#d97706",
        category: "road"
    },
    bus: {
        key: "bus",
        label: "Bus",
        width: 3.8,
        depth: 11.5,
        height: 4.3,
        attenuation: 11.5,
        color: "#2563eb",
        category: "road"
    },
    container: {
        key: "container",
        label: "Container",
        width: 6.0,
        depth: 10.0,
        height: 5.0,
        attenuation: 14.0,
        color: "#0f766e",
        category: "static"
    },
    barricade: {
        key: "barricade",
        label: "Barricade",
        width: 6.5,
        depth: 2.4,
        height: 1.8,
        attenuation: 6.2,
        color: "#a855f7",
        category: "static"
    }
};

const BUILDINGS = CITY_STRUCTURES.map((item) => ({
    x: item.x,
    y: item.y,
    w: item.w,
    d: item.d,
    h: item.h,
    x2: item.x + item.w,
    y2: item.y + item.d
}));

function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
}

function lerp(a, b, t) {
    return a + (b - a) * t;
}

function wrapDiffDeg(a, b) {
    let diff = a - b;
    while (diff > 180) diff -= 360;
    while (diff < -180) diff += 360;
    return diff;
}

function freeSpaceLoss(distanceMeters) {
    const distanceKm = Math.max(0.001, distanceMeters / 1000);
    return 32.44 + 20 * Math.log10(distanceKm) + 20 * Math.log10(FREQ_GHZ * 1000);
}

function deterministicNoise(userPos) {
    return (
        1.1 * Math.sin(userPos[0] * 0.043) +
        0.8 * Math.cos(userPos[1] * 0.037) +
        0.5 * Math.sin((userPos[0] + userPos[1]) * 0.018)
    );
}

function pointInRect(point, rect) {
    return point[0] >= rect.x && point[0] <= rect.x2 && point[1] >= rect.y && point[1] <= rect.y2;
}

function distancePointToSegment(point, start, end) {
    const vx = end[0] - start[0];
    const vy = end[1] - start[1];
    const wx = point[0] - start[0];
    const wy = point[1] - start[1];
    const lenSq = vx * vx + vy * vy;
    const t = lenSq <= 1e-6 ? 0 : clamp((wx * vx + wy * vy) / lenSq, 0, 1);
    const projX = start[0] + vx * t;
    const projY = start[1] + vy * t;
    return {
        distance: Math.hypot(point[0] - projX, point[1] - projY),
        t
    };
}

function segmentRectMetrics(start, end, rect) {
    const dx = end[0] - start[0];
    const dy = end[1] - start[1];
    const p = [-dx, dx, -dy, dy];
    const q = [start[0] - rect.x, rect.x2 - start[0], start[1] - rect.y, rect.y2 - start[1]];
    let t0 = 0;
    let t1 = 1;

    for (let i = 0; i < 4; i++) {
        if (Math.abs(p[i]) < 1e-8) {
            if (q[i] < 0) return { intersects: false, overlap: 0, tNear: 1 };
        } else {
            const value = q[i] / p[i];
            if (p[i] < 0) {
                t0 = Math.max(t0, value);
            } else {
                t1 = Math.min(t1, value);
            }
            if (t0 > t1) return { intersects: false, overlap: 0, tNear: 1 };
        }
    }

    return {
        intersects: true,
        overlap: Math.max(0, t1 - t0),
        tNear: t0
    };
}

function nearestStreetDistance(value) {
    let best = Infinity;
    for (let i = 1; i < STREET_GRID.length - 1; i++) {
        best = Math.min(best, Math.abs(value - STREET_GRID[i]));
    }
    return best;
}

function isRoadPoint(point) {
    return nearestStreetDistance(point[0]) <= STREET_WIDTH * 0.6 ||
        nearestStreetDistance(point[1]) <= STREET_WIDTH * 0.6;
}

function isInsideBuilding(point) {
    return BUILDINGS.some((building) => pointInRect(point, building));
}

function obstacleRect(obstacle) {
    const width = obstacle.width;
    const depth = obstacle.depth;
    return {
        x: obstacle.x - width / 2,
        y: obstacle.y - depth / 2,
        x2: obstacle.x + width / 2,
        y2: obstacle.y + depth / 2,
        width,
        depth
    };
}

function createObstacleAt(position, typeKey) {
    const kind = OBSTACLE_TYPES[typeKey] || OBSTACLE_TYPES.car;
    const x = clamp(position[0], 6, GRID_SIZE - 6);
    const y = clamp(position[1], 6, GRID_SIZE - 6);
    let orientation = "vertical";

    if (kind.category === "road") {
        const nearestX = STREET_GRID.slice(1, -1).reduce((best, value) =>
            Math.abs(value - x) < Math.abs(best - x) ? value : best, STREET_GRID[1]);
        const nearestY = STREET_GRID.slice(1, -1).reduce((best, value) =>
            Math.abs(value - y) < Math.abs(best - y) ? value : best, STREET_GRID[1]);
        if (Math.abs(nearestX - x) <= Math.abs(nearestY - y)) {
            orientation = "vertical";
            return {
                ...kind,
                x: nearestX,
                y,
                orientation
            };
        }
        orientation = "horizontal";
        return {
            ...kind,
            x,
            y: nearestY,
            orientation
        };
    }

    return {
        ...kind,
        x,
        y,
        orientation
    };
}

function constrainUserPosition(position) {
    const clamped = [
        clamp(position[0], 6, GRID_SIZE - 6),
        clamp(position[1], 6, GRID_SIZE - 6)
    ];
    if (!isInsideBuilding(clamped)) return clamped;

    const candidates = [];
    for (let dx = -12; dx <= 12; dx += 2) {
        for (let dy = -12; dy <= 12; dy += 2) {
            const point = [
                clamp(clamped[0] + dx, 6, GRID_SIZE - 6),
                clamp(clamped[1] + dy, 6, GRID_SIZE - 6)
            ];
            if (!isInsideBuilding(point)) {
                candidates.push(point);
            }
        }
    }

    if (candidates.length === 0) return clamped;
    candidates.sort((a, b) =>
        Math.hypot(a[0] - clamped[0], a[1] - clamped[1]) -
        Math.hypot(b[0] - clamped[0], b[1] - clamped[1]));
    return candidates[0];
}

function buildingPathLoss(start, end) {
    let totalLoss = 0;
    let weightedHits = 0;

    for (const building of BUILDINGS) {
        const hit = segmentRectMetrics(start, end, building);
        if (hit.intersects) {
            weightedHits += 1;
            totalLoss += 10.5 + hit.overlap * 18 + building.h * 0.11;
        } else {
            const center = [(building.x + building.x2) / 2, (building.y + building.y2) / 2];
            const near = distancePointToSegment(center, start, end);
            if (near.distance < 8) {
                totalLoss += (8 - near.distance) * 0.45 * (building.h / 40);
            }
        }
    }

    return {
        loss: totalLoss,
        hits: weightedHits
    };
}

function obstacleShadowLoss(start, end, obstacles) {
    let loss = 0;
    let hits = 0;

    for (const obstacle of obstacles) {
        const rect = obstacleRect(obstacle);
        const hit = segmentRectMetrics(start, end, rect);
        if (hit.intersects) {
            const pathFactor = 0.6 + hit.overlap * 2.2;
            const heightFactor = 0.7 + obstacle.height / 6;
            loss += obstacle.attenuation * pathFactor * heightFactor;
            hits++;
            continue;
        }

        const near = distancePointToSegment([obstacle.x, obstacle.y], start, end);
        const influenceRadius = Math.max(obstacle.width, obstacle.depth) * 0.9;
        if (near.distance < influenceRadius) {
            loss += obstacle.attenuation * 0.18 * (1 - near.distance / influenceRadius);
        }
    }

    return { loss, hits };
}

function urbanClutterLoss(userPos) {
    const roadDistance = Math.min(nearestStreetDistance(userPos[0]), nearestStreetDistance(userPos[1]));
    const canyonPenalty = clamp((roadDistance - STREET_WIDTH * 0.2) * 0.12, 0, 4.5);
    const edgePenalty = clamp(8 - Math.min(userPos[0], userPos[1], GRID_SIZE - userPos[0], GRID_SIZE - userPos[1]), 0, 8) * 0.18;
    return canyonPenalty + edgePenalty;
}

function fresnelPenalty(start, end, blockerCount) {
    const distance = Math.hypot(end[0] - start[0], end[1] - start[1]);
    const radius = Math.sqrt((LAMBDA * Math.max(distance, 1)) / 2);
    return blockerCount * clamp(radius * 0.55, 0.6, 3.8);
}

function risGainDb(servoAngles, phaseMatrix, userPos, obstacles) {
    const targetAz = (Math.atan2(userPos[1] - ORIS_POS[1], userPos[0] - ORIS_POS[0]) * 180 / Math.PI + 360) % 360;
    const panelGains = [];
    const azimuths = [];
    const cellPitch = 0.0057;
    const cellsPerSide = Math.sqrt(CELLS_PER_PANEL);

    for (let i = 0; i < N_PANELS; i++) {
        const offset = i * CELLS_PER_PANEL;
        let dphiDx = 0;

        if (cellsPerSide > 1) {
            let sumDiff = 0;
            for (let col = 1; col < cellsPerSide; col++) {
                sumDiff += phaseMatrix[offset + col] * Math.PI - phaseMatrix[offset + col - 1] * Math.PI;
            }
            dphiDx = (sumDiff / (cellsPerSide - 1)) / cellPitch;
        }

        const sinThetaR = clamp((LAMBDA / (2 * Math.PI)) * dphiDx, -1, 1);
        const steerAngleRad = Math.asin(sinThetaR);
        const panelAz = (PANEL_AZIMUTHS[i] + steerAngleRad * 180 / Math.PI + 360) % 360;
        azimuths.push(panelAz);

        let activeCount = 0;
        for (let c = 0; c < CELLS_PER_PANEL; c++) {
            if (phaseMatrix[offset + c] > 0.5) activeCount++;
        }

        const activeFrac = activeCount / CELLS_PER_PANEL;
        const facing = Math.max(0, 1 - Math.abs(wrapDiffDeg(targetAz, panelAz)) / 95);
        const servoAlignment = Math.max(0.2, 1 - Math.abs(servoAngles[i]) / 18);
        const obstaclePenalty = obstacles.reduce((penalty, obstacle) => {
            const obsAz = (Math.atan2(obstacle.y - ORIS_POS[1], obstacle.x - ORIS_POS[0]) * 180 / Math.PI + 360) % 360;
            const diff = Math.abs(wrapDiffDeg(panelAz, obsAz));
            if (diff < 14 && Math.hypot(obstacle.x - ORIS_POS[0], obstacle.y - ORIS_POS[1]) < Math.hypot(userPos[0] - ORIS_POS[0], userPos[1] - ORIS_POS[1])) {
                return penalty + (14 - diff) * 0.22;
            }
            return penalty;
        }, 0);

        let gain = 10 * Math.log10(Math.max(1, activeCount) * PANEL_AREA / (LAMBDA * LAMBDA));
        gain += facing * 5.4 + servoAlignment * 1.8 - obstaclePenalty;
        gain = clamp(gain, 0, 34);
        panelGains.push(gain * (0.45 + activeFrac * 0.55));
    }

    let maxGain = -Infinity;
    let bestPanel = 0;
    for (let i = 0; i < panelGains.length; i++) {
        if (panelGains[i] > maxGain) {
            maxGain = panelGains[i];
            bestPanel = i;
        }
    }

    return {
        gain: maxGain,
        beamAz: azimuths[bestPanel],
        panelGains
    };
}

function computeRssi(servoAngles, phaseMatrix, userPos, obstacles) {
    const directDistance = Math.hypot(TOWER_POS[0] - userPos[0], TOWER_POS[1] - userPos[1]);
    const directBuildings = buildingPathLoss(TOWER_POS, userPos);
    const directObstacles = obstacleShadowLoss(TOWER_POS, userPos, obstacles);
    const directLoss = freeSpaceLoss(directDistance) +
        directBuildings.loss +
        directObstacles.loss +
        fresnelPenalty(TOWER_POS, userPos, directBuildings.hits + directObstacles.hits) +
        urbanClutterLoss(userPos);
    const rssiDirect = TX_POWER_DBM - directLoss;

    const towerToRisDistance = Math.hypot(TOWER_POS[0] - ORIS_POS[0], TOWER_POS[1] - ORIS_POS[1]);
    const risToUserDistance = Math.hypot(ORIS_POS[0] - userPos[0], ORIS_POS[1] - userPos[1]);
    const incidenceBuildings = buildingPathLoss(TOWER_POS, ORIS_POS);
    const reflectionBuildings = buildingPathLoss(ORIS_POS, userPos);
    const reflectionObstacles = obstacleShadowLoss(ORIS_POS, userPos, obstacles);
    const { gain: risGain, beamAz, panelGains } = risGainDb(servoAngles, phaseMatrix, userPos, obstacles);

    const targetAz = (Math.atan2(userPos[1] - ORIS_POS[1], userPos[0] - ORIS_POS[0]) * 180 / Math.PI + 360) % 360;
    const beamAlignment = Math.max(0.15, 1 - Math.abs(wrapDiffDeg(targetAz, beamAz)) / 110);
    const twoHopLoss = freeSpaceLoss(towerToRisDistance) + freeSpaceLoss(risToUserDistance);
    const reflectionCoupling = 32 + risGain * 0.58 + beamAlignment * 8.5;
    const reflectionLoss = twoHopLoss -
        reflectionCoupling +
        incidenceBuildings.loss * 0.34 +
        reflectionBuildings.loss * 0.46 +
        reflectionObstacles.loss +
        fresnelPenalty(ORIS_POS, userPos, reflectionBuildings.hits + reflectionObstacles.hits) * 0.8;
    const rssiRis = TX_POWER_DBM - reflectionLoss;

    const dbToLin = (value) => Math.pow(10, value / 10);
    const linToDb = (value) => 10 * Math.log10(Math.max(value, 1e-20));
    const rssiTotal = clamp(linToDb(dbToLin(rssiDirect) + dbToLin(rssiRis)), -120, -35);

    const noiseFloor = NOISE_FLOOR_DBM +
        deterministicNoise(userPos) +
        urbanClutterLoss(userPos) * 0.4 +
        reflectionObstacles.loss * 0.08;
    const snr = clamp(rssiTotal - noiseFloor, -25, 60);

    const panelRssi = panelGains.map((panelGain, index) => {
        const facing = Math.max(0, 1 - Math.abs(wrapDiffDeg(targetAz, PANEL_AZIMUTHS[index])) / 150);
        return clamp(rssiTotal + facing * 2.4 + panelGain * 0.15 - 2.8, -120, -30);
    });

    const quality = clamp((snr + 10) * 1.25 + (rssiTotal + 100) * 0.65, 0, 100);

    return {
        rssi: rssiTotal,
        snr,
        beamAz,
        panelRssi,
        quality,
        breakdown: {
            directLoss,
            reflectionLoss,
            buildingHits: directBuildings.hits + reflectionBuildings.hits,
            obstacleHits: directObstacles.hits + reflectionObstacles.hits
        }
    };
}

class HeuristicAgent {
    constructor() {
        this.servoAngles = new Float32Array(N_PANELS);
        this.phaseMatrix = new Float32Array(N_PHASE_ELEMENTS);
    }

    predict(userPos, obstacles) {
        const t0 = performance.now();
        const dx = userPos[0] - ORIS_POS[0];
        const dy = userPos[1] - ORIS_POS[1];
        const targetAz = (Math.atan2(dy, dx) * 180 / Math.PI + 360) % 360;
        const targetDistance = Math.max(10, Math.hypot(dx, dy));
        const desiredElev = clamp((70 - targetDistance) * 0.2, -10, 12);

        for (let i = 0; i < N_PANELS; i++) {
            const diff = wrapDiffDeg(targetAz, PANEL_AZIMUTHS[i]);
            const facing = Math.max(0, 1 - Math.abs(diff) / 110);
            const blockers = obstacles.reduce((score, obstacle) => {
                const obsAz = (Math.atan2(obstacle.y - ORIS_POS[1], obstacle.x - ORIS_POS[0]) * 180 / Math.PI + 360) % 360;
                const obsDistance = Math.hypot(obstacle.x - ORIS_POS[0], obstacle.y - ORIS_POS[1]);
                if (obsDistance >= targetDistance) return score;
                const obsDiff = Math.abs(wrapDiffDeg(obsAz, PANEL_AZIMUTHS[i]));
                if (obsDiff > 28) return score;
                return score + (28 - obsDiff) / 28 * obstacle.attenuation * 0.08;
            }, 0);

            const desiredServo = clamp((diff / 100) * 12 + desiredElev * facing - blockers * 0.5, -15, 15);
            this.servoAngles[i] += (desiredServo - this.servoAngles[i]) * 0.16;
        }

        for (let i = 0; i < N_PANELS; i++) {
            const offset = i * CELLS_PER_PANEL;
            const panelAz = PANEL_AZIMUTHS[i];
            const diff = Math.abs(wrapDiffDeg(targetAz, panelAz));
            const facing = Math.max(0.06, 1 - diff / 125);

            let shadowPenalty = 0;
            for (const obstacle of obstacles) {
                const obsAz = (Math.atan2(obstacle.y - ORIS_POS[1], obstacle.x - ORIS_POS[0]) * 180 / Math.PI + 360) % 360;
                const obsDiff = Math.abs(wrapDiffDeg(obsAz, panelAz));
                if (obsDiff < 24) {
                    shadowPenalty += ((24 - obsDiff) / 24) * obstacle.attenuation * 0.025;
                }
            }

            for (let c = 0; c < CELLS_PER_PANEL; c++) {
                const row = Math.floor(c / 16);
                const col = c % 16;
                const horizontalBias = (col / 15 - 0.5) * (diff / 90);
                const verticalBias = (row / 15 - 0.5) * (this.servoAngles[i] / 15);
                const stripe = ((row + col + i) % 4) * 0.04;
                const energy = facing + horizontalBias - Math.abs(verticalBias) * 0.45 - shadowPenalty + stripe;
                const desired = energy > 0.48 ? 1 : 0;
                const idx = offset + c;
                this.phaseMatrix[idx] += (desired - this.phaseMatrix[idx]) * 0.24;
            }
        }

        return {
            servoAngles: Array.from(this.servoAngles),
            phaseMatrix: Array.from(this.phaseMatrix),
            inferenceMs: performance.now() - t0
        };
    }
}

const SimState = {
    userPos: [150, 150],
    obstacles: [],
    obstacleType: "car",
    servoAngles: new Float32Array(N_PANELS),
    phaseMatrix: new Float32Array(N_PHASE_ELEMENTS),
    rssi: -100,
    snr: 0,
    quality: 0,
    beamAz: 0,
    inferenceMs: 0,
    rssiBaseline: -100,
    aiOn: false,
    addObsMode: false,
    agent: new HeuristicAgent(),
    rssiHistory: [],
    maxHistory: 60,
    signalBreakdown: null,

    reset() {
        this.userPos = [150, 150];
        this.obstacles = [];
        this.servoAngles = new Float32Array(N_PANELS);
        this.phaseMatrix = new Float32Array(N_PHASE_ELEMENTS);
        this.rssiHistory = [];
        this.rssi = -100;
        this.snr = 0;
        this.quality = 0;
        this.beamAz = 0;
        this.inferenceMs = 0;
        this.rssiBaseline = -100;
        this.signalBreakdown = null;
    },

    setObstacleType(typeKey) {
        if (OBSTACLE_TYPES[typeKey]) {
            this.obstacleType = typeKey;
        }
    },

    addObstacle(position) {
        this.obstacles.push(createObstacleAt(position, this.obstacleType));
    },

    setUserPosition(position) {
        this.userPos = constrainUserPosition(position);
    },

    update() {
        const baseline = computeRssi(
            new Float32Array(N_PANELS),
            new Float32Array(N_PHASE_ELEMENTS),
            this.userPos,
            this.obstacles
        );
        this.rssiBaseline = baseline.rssi;

        if (this.aiOn) {
            const action = this.agent.predict(this.userPos, this.obstacles);
            this.servoAngles = new Float32Array(action.servoAngles);
            this.phaseMatrix = new Float32Array(action.phaseMatrix);
            this.inferenceMs = action.inferenceMs;
        } else {
            this.servoAngles = new Float32Array(N_PANELS);
            this.phaseMatrix = new Float32Array(N_PHASE_ELEMENTS);
            this.inferenceMs = 0;
        }

        const result = computeRssi(
            this.servoAngles,
            this.phaseMatrix,
            this.userPos,
            this.obstacles
        );

        this.rssi = result.rssi;
        this.snr = result.snr;
        this.quality = result.quality;
        this.beamAz = result.beamAz;
        this.signalBreakdown = result.breakdown;

        this.rssiHistory.push(this.rssi);
        if (this.rssiHistory.length > this.maxHistory) {
            this.rssiHistory.shift();
        }
    }
};

window.SimState = SimState;
window.BUILDINGS = BUILDINGS;
window.CITY_STRUCTURES = CITY_STRUCTURES;
window.PARKS = PARKS;
window.STREET_GRID = STREET_GRID;
window.STREET_WIDTH = STREET_WIDTH;
window.TOWER_POS = TOWER_POS;
window.ORIS_POS = ORIS_POS;
window.GRID_SIZE = GRID_SIZE;
window.N_PANELS = N_PANELS;
window.N_PHASE_ELEMENTS = N_PHASE_ELEMENTS;
window.CELLS_PER_PANEL = CELLS_PER_PANEL;
window.OBSTACLE_TYPES = OBSTACLE_TYPES;
window.computeRssi = computeRssi;
