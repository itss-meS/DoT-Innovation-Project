/**
 * dashboard.js - O-RIS AI Dashboard Controller
 * ============================================
 * UI orchestration, charts, controls, and 3D scene sync.
 */

const cityCanvas = document.getElementById("city-canvas");
const threeContainer = document.getElementById("three-container");
const phaseCanvas = document.getElementById("phase-canvas");
const phaseCtx = phaseCanvas.getContext("2d");
const rssiCanvas = document.getElementById("rssi-chart");
const rssiCtx = rssiCanvas.getContext("2d");
const beamCanvas = document.getElementById("beam-canvas");
const beamCtx = beamCanvas.getContext("2d");
const obstacleTypeSelect = document.getElementById("obstacle-type");
const cameraInfo = document.getElementById("camera-info");

const cityScene = window.CityScene3D
    ? new window.CityScene3D({ canvas: cityCanvas, container: threeContainer })
    : null;

let dragState = null;
let suppressClickUntil = 0;

function setupCanvas(canvas, ctx, cssWidth, cssHeight) {
    const dpr = window.devicePixelRatio || 1;
    canvas.width = cssWidth * dpr;
    canvas.height = cssHeight * dpr;
    canvas.style.width = `${cssWidth}px`;
    canvas.style.height = `${cssHeight}px`;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.scale(dpr, dpr);
}

function avg(values) {
    return values.reduce((sum, value) => sum + value, 0) / Math.max(1, values.length);
}

function rssiToHex(rssi) {
    const t = Math.max(0, Math.min(1, (rssi + 110) / 80));
    const palette = [
        [127, 29, 29],
        [239, 68, 36],
        [251, 191, 36],
        [34, 197, 94],
        [22, 101, 52]
    ];
    const scaled = t * (palette.length - 1);
    const index = Math.floor(scaled);
    const frac = scaled - index;
    const a = palette[index];
    const b = palette[Math.min(index + 1, palette.length - 1)];
    const rgb = a.map((component, i) => Math.round(component + (b[i] - component) * frac));
    return `rgb(${rgb[0]}, ${rgb[1]}, ${rgb[2]})`;
}

function qualityLabel(quality) {
    if (quality >= 78) return "Excellent";
    if (quality >= 58) return "Good";
    if (quality >= 35) return "Moderate";
    return "Obstructed";
}

function renderPhaseMatrix() {
    const w = 256;
    const h = 32;
    const imgData = phaseCtx.createImageData(w, h);
    const data = imgData.data;
    const phaseMatrix = SimState.phaseMatrix;

    for (let panel = 0; panel < N_PANELS; panel++) {
        const rowOffset = panel * 4;
        for (let c = 0; c < 256; c++) {
            const activation = phaseMatrix[panel * CELLS_PER_PANEL + c];
            const colorOn = [
                Math.round(39 + activation * 68),
                Math.round(95 + activation * 104),
                Math.round(176 + activation * 70)
            ];
            const colorOff = [21, 33, 47];

            for (let dy = 0; dy < 4; dy++) {
                const idx = ((rowOffset + dy) * w + c) * 4;
                const active = activation > 0.2;
                const source = active ? colorOn : colorOff;
                data[idx] = source[0];
                data[idx + 1] = source[1];
                data[idx + 2] = source[2];
                data[idx + 3] = active ? 220 : 110;
            }
        }
    }

    phaseCtx.putImageData(imgData, 0, 0);

    let activeCount = 0;
    for (let i = 0; i < N_PHASE_ELEMENTS; i++) {
        if (phaseMatrix[i] > 0.5) activeCount++;
    }
    document.getElementById("phase-active").textContent = `${activeCount} / ${N_PHASE_ELEMENTS} active`;
}

function renderRssiChart() {
    const ctx = rssiCtx;
    const w = 300;
    const h = 80;
    ctx.clearRect(0, 0, w, h);

    const background = ctx.createLinearGradient(0, 0, 0, h);
    background.addColorStop(0, "#0f172a");
    background.addColorStop(1, "#0b1220");
    ctx.fillStyle = background;
    ctx.fillRect(0, 0, w, h);

    ctx.strokeStyle = "rgba(148, 163, 184, 0.08)";
    ctx.lineWidth = 0.5;
    for (let db = -110; db <= -30; db += 20) {
        const y = h - ((db + 120) / 90) * h;
        ctx.beginPath();
        ctx.moveTo(0, y);
        ctx.lineTo(w, y);
        ctx.stroke();
    }

    const history = SimState.rssiHistory;
    if (history.length < 2) return;

    const xStep = w / Math.max(1, SimState.maxHistory - 1);
    ctx.beginPath();
    history.forEach((value, index) => {
        const x = index * xStep + (SimState.maxHistory - history.length) * xStep;
        const y = h - ((value + 120) / 90) * h;
        if (index === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
    });

    const lastColor = rssiToHex(history[history.length - 1]);
    ctx.strokeStyle = lastColor;
    ctx.lineWidth = 2.2;
    ctx.stroke();

    const thresholdY = h - ((-70 + 120) / 90) * h;
    ctx.strokeStyle = "rgba(251, 191, 36, 0.45)";
    ctx.setLineDash([5, 4]);
    ctx.beginPath();
    ctx.moveTo(0, thresholdY);
    ctx.lineTo(w, thresholdY);
    ctx.stroke();
    ctx.setLineDash([]);

    const trendEl = document.getElementById("rssi-trend");
    if (history.length >= 10) {
        const recent = avg(history.slice(-5));
        const previous = avg(history.slice(-10, -5));
        const delta = recent - previous;
        if (delta > 0.8) {
            trendEl.textContent = `Up +${delta.toFixed(1)} dB`;
            trendEl.style.color = "#10b981";
        } else if (delta < -0.8) {
            trendEl.textContent = `Down ${delta.toFixed(1)} dB`;
            trendEl.style.color = "#ef4444";
        } else {
            trendEl.textContent = "Stable";
            trendEl.style.color = "#94a3b8";
        }
    }
}

function renderBeamPattern() {
    const ctx = beamCtx;
    const w = 180;
    const h = 180;
    const cx = w / 2;
    const cy = h / 2;
    const maxR = 72;

    ctx.clearRect(0, 0, w, h);
    ctx.fillStyle = "#0f172a";
    ctx.beginPath();
    ctx.arc(cx, cy, maxR + 10, 0, Math.PI * 2);
    ctx.fill();

    ctx.strokeStyle = "rgba(148, 163, 184, 0.1)";
    ctx.lineWidth = 0.6;
    for (let i = 1; i <= 3; i++) {
        ctx.beginPath();
        ctx.arc(cx, cy, (maxR / 3) * i, 0, Math.PI * 2);
        ctx.stroke();
    }

    for (let axis = 0; axis < 8; axis++) {
        const angle = axis * Math.PI / 4;
        ctx.beginPath();
        ctx.moveTo(cx, cy);
        ctx.lineTo(cx + Math.cos(angle) * maxR, cy + Math.sin(angle) * maxR);
        ctx.stroke();
    }

    const points = [];
    for (let deg = 0; deg <= 360; deg++) {
        let diff = Math.abs(deg - SimState.beamAz);
        if (diff > 180) diff = 360 - diff;
        const main = Math.max(0.08, Math.cos(diff * Math.PI / 58));
        const side = 0.12 * Math.max(0, Math.cos(diff * Math.PI / 16));
        const r = Math.max(main, side) * maxR;
        const angle = (-deg + 90) * Math.PI / 180;
        points.push([cx + Math.cos(angle) * r, cy - Math.sin(angle) * r]);
    }

    ctx.beginPath();
    points.forEach(([x, y], index) => {
        if (index === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
    });
    ctx.closePath();
    ctx.fillStyle = "rgba(59,130,246,0.15)";
    ctx.fill();
    ctx.strokeStyle = "#60a5fa";
    ctx.lineWidth = 1.4;
    ctx.stroke();

    const beamAngle = (-SimState.beamAz + 90) * Math.PI / 180;
    ctx.beginPath();
    ctx.moveTo(cx, cy);
    ctx.lineTo(cx + Math.cos(beamAngle) * maxR * 0.9, cy - Math.sin(beamAngle) * maxR * 0.9);
    ctx.strokeStyle = "#ef4444";
    ctx.lineWidth = 2;
    ctx.stroke();

    ctx.fillStyle = "#94a3b8";
    ctx.font = "600 8px Inter";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText("N", cx, cy - maxR - 10);
    ctx.fillText("S", cx, cy + maxR + 10);
    ctx.fillText("E", cx + maxR + 10, cy);
    ctx.fillText("W", cx - maxR - 10, cy);
}

function initServoGrid() {
    const grid = document.getElementById("servo-grid");
    grid.innerHTML = "";
    for (let i = 0; i < N_PANELS; i++) {
        const item = document.createElement("div");
        item.className = "servo-item";
        item.innerHTML = `
            <span class="servo-label">P${i + 1}</span>
            <span class="servo-value" id="servo-val-${i}">0.0 deg</span>
            <div class="servo-bar"><div class="servo-bar-fill" id="servo-bar-${i}"></div></div>
        `;
        grid.appendChild(item);
    }
}

function updateServoBars() {
    for (let i = 0; i < N_PANELS; i++) {
        const angle = SimState.servoAngles[i];
        const frac = (angle + 15) / 30;
        const valueEl = document.getElementById(`servo-val-${i}`);
        const barEl = document.getElementById(`servo-bar-${i}`);
        valueEl.textContent = `${angle >= 0 ? "+" : ""}${angle.toFixed(1)} deg`;
        valueEl.style.color = angle >= 0 ? "#22d3ee" : "#fbbf24";
        barEl.style.width = `${Math.max(6, frac * 100)}%`;
        barEl.style.background = angle >= 0
            ? "linear-gradient(90deg, #22d3ee, #3b82f6)"
            : "linear-gradient(90deg, #fbbf24, #f97316)";
    }
}

function updateCameraHint() {
    if (!cameraInfo || !cityScene) return;
    const selectedObstacle = OBSTACLE_TYPES[SimState.obstacleType];
    cameraInfo.querySelector("span").textContent =
        `${cityScene.getCameraLabel()} | obstacle: ${selectedObstacle.label} | quality: ${qualityLabel(SimState.quality)}`;
}

function updateKPIs() {
    const rssi = SimState.rssi;
    const snr = SimState.snr;
    const beam = SimState.beamAz;
    const latency = SimState.inferenceMs;
    const gain = rssi - SimState.rssiBaseline;

    document.getElementById("kpi-rssi-val").textContent = rssi.toFixed(1);
    document.getElementById("kpi-snr-val").textContent = snr.toFixed(1);
    document.getElementById("kpi-beam-val").textContent = beam.toFixed(0);
    document.getElementById("kpi-latency-val").textContent = latency.toFixed(2);
    document.getElementById("kpi-gain-val").textContent = `${gain >= 0 ? "+" : ""}${gain.toFixed(1)}`;

    const rssiColor = rssi > -70 ? "#10b981" : (rssi > -90 ? "#fbbf24" : "#ef4444");
    const snrColor = snr > 10 ? "#10b981" : "#fbbf24";
    const latencyColor = latency > 0 && latency < 2 ? "#10b981" : (latency === 0 ? "#94a3b8" : "#ef4444");

    document.getElementById("kpi-rssi-val").style.color = rssiColor;
    document.getElementById("kpi-snr-val").style.color = snrColor;
    document.getElementById("kpi-latency-val").style.color = latencyColor;

    document.getElementById("kpi-rssi-bar").style.width = `${((rssi + 120) / 90) * 100}%`;
    document.getElementById("kpi-snr-bar").style.width = `${Math.min(100, (snr / 60) * 100)}%`;
    document.getElementById("kpi-beam-bar").style.width = `${(beam / 360) * 100}%`;
    document.getElementById("kpi-latency-bar").style.width = latency > 0 ? `${Math.min(100, 100 / Math.max(1, latency))}%` : "0%";
    document.getElementById("kpi-gain-bar").style.width = `${Math.max(0, Math.min(100, (gain + 5) * 3.2))}%`;
}

function updateObsButton() {
    const button = document.getElementById("btn-add-obstacle");
    const overlay = document.getElementById("canvas-overlay");
    const selectedObstacle = OBSTACLE_TYPES[SimState.obstacleType];
    if (SimState.addObsMode) {
        button.classList.add("active");
        overlay.classList.add("active");
        overlay.querySelector("span").textContent = `Click to place ${selectedObstacle.label.toLowerCase()} obstacle`;
    } else {
        button.classList.remove("active");
        overlay.classList.remove("active");
        overlay.querySelector("span").textContent = "Click any clear road or open block edge to place the user node";
    }
    updateCameraHint();
}

function syncScene() {
    if (cityScene) {
        cityScene.updateFromState(SimState);
    }
}

function handleSceneClick(event) {
    if (!cityScene || performance.now() < suppressClickUntil || (dragState && dragState.dragged)) return;
    const picked = cityScene.pickGround(event);
    if (!picked) return;

    if (SimState.addObsMode) {
        SimState.addObstacle(picked);
        SimState.addObsMode = false;
        updateObsButton();
    } else {
        SimState.setUserPosition(picked);
        updateCameraHint();
    }
}

function handlePointerDown(event) {
    if (!cityScene) return;
    dragState = {
        pointerId: event.pointerId,
        startX: event.clientX,
        startY: event.clientY,
        lastX: event.clientX,
        lastY: event.clientY,
        dragged: false
    };
    cityCanvas.setPointerCapture(event.pointerId);
}

function handlePointerMove(event) {
    if (!dragState || dragState.pointerId !== event.pointerId || !cityScene) return;
    const dx = event.clientX - dragState.lastX;
    const dy = event.clientY - dragState.lastY;
    if (Math.abs(event.clientX - dragState.startX) > 3 || Math.abs(event.clientY - dragState.startY) > 3) {
        dragState.dragged = true;
    }
    if (dragState.dragged) {
        cityScene.panBy(dx, dy);
        updateCameraHint();
    }
    dragState.lastX = event.clientX;
    dragState.lastY = event.clientY;
}

function clearDragState(event) {
    if (!dragState) return;
    if (dragState.dragged) suppressClickUntil = performance.now() + 180;
    if (event && dragState.pointerId === event.pointerId) {
        try {
            cityCanvas.releasePointerCapture(event.pointerId);
        } catch (error) {
            // Ignore capture release issues during teardown.
        }
    }
    dragState = null;
}

document.getElementById("btn-ai-toggle").addEventListener("click", () => {
    SimState.aiOn = !SimState.aiOn;
    const btn = document.getElementById("btn-ai-toggle");
    const card = document.getElementById("ai-card");
    const chip = document.getElementById("ai-status-chip");
    const hint = document.getElementById("ai-hint");

    if (SimState.aiOn) {
        btn.dataset.state = "on";
        document.getElementById("ai-btn-text").textContent = "AI ON";
        card.classList.add("active");
        chip.textContent = "ACTIVE";
        hint.textContent = "Obstacle-aware steering is dynamically shaping the metasurface";
    } else {
        btn.dataset.state = "off";
        document.getElementById("ai-btn-text").textContent = "AI OFF";
        card.classList.remove("active");
        chip.textContent = "OFFLINE";
        hint.textContent = "Enable to activate beam steering intelligence";
    }
});

document.getElementById("btn-add-obstacle").addEventListener("click", () => {
    SimState.addObsMode = !SimState.addObsMode;
    updateObsButton();
});

document.getElementById("btn-clear").addEventListener("click", () => {
    SimState.reset();
    if (obstacleTypeSelect) obstacleTypeSelect.value = SimState.obstacleType;
    updateObsButton();
});

document.getElementById("btn-toggle-view").addEventListener("click", () => {
    if (cityScene) {
        cityScene.cycleCamera();
        updateCameraHint();
    }
});

document.getElementById("btn-start-demo").addEventListener("click", () => {
    document.getElementById("presentation-overlay").classList.add("hidden");
});

if (obstacleTypeSelect) {
    obstacleTypeSelect.addEventListener("change", (event) => {
        SimState.setObstacleType(event.target.value);
        updateObsButton();
    });
    obstacleTypeSelect.value = SimState.obstacleType;
}

cityCanvas.addEventListener("click", handleSceneClick);
cityCanvas.addEventListener("pointerdown", handlePointerDown);
cityCanvas.addEventListener("pointermove", handlePointerMove);
cityCanvas.addEventListener("pointerup", clearDragState);
cityCanvas.addEventListener("pointercancel", clearDragState);
cityCanvas.addEventListener("wheel", (event) => {
    if (!cityScene) return;
    event.preventDefault();
    cityScene.zoomBy(event.deltaY < 0 ? 0.08 : -0.08);
    updateCameraHint();
}, { passive: false });

let frameCount = 0;
let lastFpsTime = performance.now();

function updateFpsCounter() {
    frameCount++;
    const now = performance.now();
    if (now - lastFpsTime >= 1000) {
        document.getElementById("fps-counter").textContent = `${frameCount} FPS`;
        frameCount = 0;
        lastFpsTime = now;
    }
}

function handleResize() {
    if (cityScene) {
        cityScene.resize();
        updateCameraHint();
    }
}

window.addEventListener("resize", handleResize);

let lastUpdate = 0;
const UPDATE_INTERVAL = 1000 / 30;

function loop(timestamp) {
    requestAnimationFrame(loop);

    if (timestamp - lastUpdate >= UPDATE_INTERVAL) {
        lastUpdate = timestamp;
        SimState.update();
        updateKPIs();
        updateServoBars();
        renderPhaseMatrix();
        renderRssiChart();
        renderBeamPattern();
        syncScene();
        updateCameraHint();
    }

    if (cityScene) cityScene.animate();
    updateFpsCounter();
}

function init() {
    initServoGrid();
    setupCanvas(phaseCanvas, phaseCtx, 256, 32);
    setupCanvas(rssiCanvas, rssiCtx, 300, 80);
    setupCanvas(beamCanvas, beamCtx, 180, 180);
    handleResize();
    updateObsButton();

    document.getElementById("connection-status").textContent = cityScene
        ? "Interactive 3D urban mode"
        : "3D engine unavailable";

    document.addEventListener("keydown", (event) => {
        if (event.key === "f" || event.key === "F") {
            if (!document.fullscreenElement) document.documentElement.requestFullscreen();
            else document.exitFullscreen();
        }
        if (event.key === "a" || event.key === "A") {
            document.getElementById("btn-ai-toggle").click();
        }
        if (event.key === "r" || event.key === "R") {
            document.getElementById("btn-clear").click();
        }
        if (event.key === "c" || event.key === "C") {
            document.getElementById("btn-toggle-view").click();
        }
        if (event.key === "p" || event.key === "P") {
            document.getElementById("presentation-overlay").classList.toggle("hidden");
        }
        if (event.key === "+" || event.key === "=") {
            if (cityScene) cityScene.zoomBy(0.08);
            updateCameraHint();
        }
        if (event.key === "-") {
            if (cityScene) cityScene.zoomBy(-0.08);
            updateCameraHint();
        }
        if (event.key === "Escape") {
            document.getElementById("presentation-overlay").classList.add("hidden");
            clearDragState();
        }
    });

    document.getElementById("presentation-overlay").classList.remove("hidden");
    requestAnimationFrame(loop);
}

if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
} else {
    init();
}
