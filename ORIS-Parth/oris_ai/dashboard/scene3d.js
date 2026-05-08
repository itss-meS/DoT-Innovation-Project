/**
 * scene3d.js
 * ==========
 * Canvas-based 3D city renderer with pan, zoom, and richer obstacle assets.
 */

(function () {
    const STYLE_COLORS = {
        office: { left: "#bfc4bd", right: "#d8ddd6", top: "#595e63", accent: "#89a3b2" },
        residential: { left: "#d2cec2", right: "#ebe5d9", top: "#5c6165", accent: "#8d979c" },
        brick: { left: "#7d4d3e", right: "#985f4c", top: "#494d52", accent: "#ccbda8" },
        civic: { left: "#c9bea7", right: "#e0d5bf", top: "#484d52", accent: "#7e7d71" },
        podium: { left: "#9da7ad", right: "#b8c0c4", top: "#51565b", accent: "#73848c" }
    };

    function clamp(value, min, max) {
        return Math.max(min, Math.min(max, value));
    }

    function mixColor(hex, amount) {
        const color = hex.replace("#", "");
        const num = parseInt(color, 16);
        const r = clamp(((num >> 16) & 255) + amount, 0, 255);
        const g = clamp(((num >> 8) & 255) + amount, 0, 255);
        const b = clamp((num & 255) + amount, 0, 255);
        return `rgb(${r}, ${g}, ${b})`;
    }

    class CityScene3D {
        constructor({ canvas, container }) {
            this.canvas = canvas;
            this.container = container;
            this.ctx = canvas.getContext("2d");
            this.state = null;
            this.time = 0;
            this.cameraIndex = 0;
            this.cameraPresets = [
                { name: "Judge View", tileX: 3.25, tileY: 1.62, height: 0.74, offsetX: 0, offsetY: 0, zoom: 1 },
                { name: "Wide Orbit", tileX: 3.95, tileY: 1.44, height: 0.88, offsetX: 10, offsetY: 18, zoom: 0.94 },
                { name: "Street Focus", tileX: 2.85, tileY: 1.86, height: 0.68, offsetX: -24, offsetY: -8, zoom: 1.08 },
                { name: "Coverage Scan", tileX: 3.55, tileY: 1.52, height: 0.8, offsetX: 18, offsetY: -12, zoom: 1.18 }
            ];
            this.camera = { ...this.cameraPresets[0] };
            this.panX = 0;
            this.panY = 0;
            this.zoom = this.camera.zoom;
            this.resize();
        }

        cycleCamera() {
            this.cameraIndex = (this.cameraIndex + 1) % this.cameraPresets.length;
            this.camera = { ...this.cameraPresets[this.cameraIndex] };
            this.zoom = this.camera.zoom;
            this.panX = 0;
            this.panY = 0;
            this.resize();
        }

        getCameraLabel() {
            return `${this.camera.name} | drag to pan | wheel to zoom`;
        }

        panBy(dx, dy) {
            this.panX = clamp(this.panX + dx, -220, 220);
            this.panY = clamp(this.panY + dy, -180, 180);
            this.resize();
        }

        zoomBy(delta) {
            this.zoom = clamp(this.zoom + delta, 0.72, 1.65);
            this.resize();
        }

        resize() {
            const rect = this.container.getBoundingClientRect();
            const width = Math.max(720, Math.floor(rect.width));
            const height = Math.max(520, Math.floor(rect.height));
            const dpr = Math.min(window.devicePixelRatio || 1, 2);

            this.width = width;
            this.height = height;
            this.canvas.width = width * dpr;
            this.canvas.height = height * dpr;
            this.canvas.style.width = `${width}px`;
            this.canvas.style.height = `${height}px`;
            this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

            this.centerX = width / 2 + this.camera.offsetX + this.panX;
            this.baseY = height * 0.78 + this.camera.offsetY + this.panY;
        }

        project(x, y, z = 0) {
            const worldX = x - GRID_SIZE / 2;
            const worldY = y - GRID_SIZE / 2;
            const tileX = this.camera.tileX * this.zoom;
            const tileY = this.camera.tileY * this.zoom;
            const heightScale = this.camera.height * this.zoom;
            return {
                x: this.centerX + (worldX - worldY) * tileX,
                y: this.baseY + (worldX + worldY) * tileY - z * heightScale
            };
        }

        pickGround(event) {
            const rect = this.canvas.getBoundingClientRect();
            const sx = event.clientX - rect.left;
            const sy = event.clientY - rect.top;
            const tileX = this.camera.tileX * this.zoom;
            const tileY = this.camera.tileY * this.zoom;
            const dx = (sx - this.centerX) / tileX;
            const dy = (sy - this.baseY) / tileY;
            const worldX = (dy + dx) / 2;
            const worldY = (dy - dx) / 2;
            return [
                clamp(worldX + GRID_SIZE / 2, 5, GRID_SIZE - 5),
                clamp(worldY + GRID_SIZE / 2, 5, GRID_SIZE - 5)
            ];
        }

        updateFromState(state) {
            this.state = state;
        }

        drawPoly(points, fill, stroke = null, lineWidth = 1) {
            const ctx = this.ctx;
            ctx.beginPath();
            ctx.moveTo(points[0].x, points[0].y);
            for (let i = 1; i < points.length; i++) {
                ctx.lineTo(points[i].x, points[i].y);
            }
            ctx.closePath();
            ctx.fillStyle = fill;
            ctx.fill();
            if (stroke) {
                ctx.strokeStyle = stroke;
                ctx.lineWidth = lineWidth;
                ctx.stroke();
            }
        }

        drawShadow(x, y, rx, ry, alpha) {
            const foot = this.project(x, y, 0.01);
            const ctx = this.ctx;
            ctx.fillStyle = `rgba(15, 23, 42, ${alpha})`;
            ctx.beginPath();
            ctx.ellipse(foot.x, foot.y + 2, rx * this.zoom, ry * this.zoom, 0, 0, Math.PI * 2);
            ctx.fill();
        }

        drawBuilding(structure) {
            const palette = STYLE_COLORS[structure.style] || STYLE_COLORS.office;
            const x0 = structure.x;
            const y0 = structure.y;
            const x1 = structure.x + structure.w;
            const y1 = structure.y + structure.d;
            const h = structure.h;

            const top = [
                this.project(x0, y0, h),
                this.project(x1, y0, h),
                this.project(x1, y1, h),
                this.project(x0, y1, h)
            ];
            const left = [
                this.project(x0, y1, 0),
                this.project(x0, y1, h),
                this.project(x1, y1, h),
                this.project(x1, y1, 0)
            ];
            const right = [
                this.project(x1, y0, 0),
                this.project(x1, y0, h),
                this.project(x1, y1, h),
                this.project(x1, y1, 0)
            ];

            this.drawShadow(structure.x + structure.w / 2, structure.y + structure.d / 2, structure.w * 1.8, structure.d * 0.9, 0.14);
            this.drawPoly(left, palette.left, "rgba(255,255,255,0.06)");
            this.drawPoly(right, palette.right, "rgba(255,255,255,0.08)");
            this.drawPoly(top, palette.top, "rgba(255,255,255,0.16)");

            this.drawWindows(structure, palette.accent);
            this.drawRooftop(structure, palette.accent);
        }

        drawWindows(structure, accent) {
            const ctx = this.ctx;
            const rows = Math.max(2, Math.floor(structure.h / 6));
            const colsX = Math.max(2, Math.floor(structure.w / 3.8));
            const colsY = Math.max(2, Math.floor(structure.d / 3.8));

            ctx.fillStyle = "rgba(185, 214, 228, 0.38)";
            for (let row = 0; row < rows; row++) {
                const z = 4 + row * 5.2;
                if (z >= structure.h - 2) break;

                for (let col = 1; col < colsX; col++) {
                    const x = structure.x + (structure.w * col) / colsX;
                    const a = this.project(x, structure.y + structure.d + 0.15, z);
                    const b = this.project(x + 0.8, structure.y + structure.d + 0.15, z + 1.8);
                    ctx.fillRect(a.x - 0.8, b.y, 1.5, Math.max(2, a.y - b.y));
                }

                ctx.fillStyle = accent;
                for (let col = 1; col < colsY; col++) {
                    const y = structure.y + (structure.d * col) / colsY;
                    const a = this.project(structure.x + structure.w - 0.15, y, z);
                    const b = this.project(structure.x + structure.w - 0.15, y + 0.8, z + 1.8);
                    ctx.fillRect(a.x - 0.8, b.y, 1.6, Math.max(2, a.y - b.y));
                }
                ctx.fillStyle = "rgba(185, 214, 228, 0.38)";
            }
        }

        drawRooftop(structure, accent) {
            const inset = Math.min(structure.w, structure.d) * 0.16;
            const roofHeight = 2;
            const x0 = structure.x + inset;
            const y0 = structure.y + inset;
            const x1 = structure.x + structure.w * 0.55;
            const y1 = structure.y + structure.d * 0.48;
            const z = structure.h + roofHeight;

            const top = [
                this.project(x0, y0, z),
                this.project(x1, y0, z),
                this.project(x1, y1, z),
                this.project(x0, y1, z)
            ];
            const side = [
                this.project(x0, y1, structure.h),
                this.project(x0, y1, z),
                this.project(x1, y1, z),
                this.project(x1, y1, structure.h)
            ];
            this.drawPoly(side, mixColor(accent, -20));
            this.drawPoly(top, mixColor(accent, 10), "rgba(255,255,255,0.18)");
        }

        drawRoadStripVertical(xCenter, width, color) {
            const x0 = xCenter - width / 2;
            const x1 = xCenter + width / 2;
            this.drawPoly([
                this.project(x0, 0, 0),
                this.project(x1, 0, 0),
                this.project(x1, GRID_SIZE, 0),
                this.project(x0, GRID_SIZE, 0)
            ], color);
        }

        drawRoadStripHorizontal(yCenter, width, color) {
            const y0 = yCenter - width / 2;
            const y1 = yCenter + width / 2;
            this.drawPoly([
                this.project(0, y0, 0),
                this.project(GRID_SIZE, y0, 0),
                this.project(GRID_SIZE, y1, 0),
                this.project(0, y1, 0)
            ], color);
        }

        drawGround() {
            const sky = this.ctx.createLinearGradient(0, 0, 0, this.height);
            sky.addColorStop(0, "#dce9f4");
            sky.addColorStop(0.42, "#c7d6df");
            sky.addColorStop(1, "#879aa7");
            this.ctx.fillStyle = sky;
            this.ctx.fillRect(0, 0, this.width, this.height);

            this.drawPoly([
                this.project(0, 0, 0),
                this.project(GRID_SIZE, 0, 0),
                this.project(GRID_SIZE, GRID_SIZE, 0),
                this.project(0, GRID_SIZE, 0)
            ], "#d6dee2");

            for (const line of [40, 80, 120, 160]) {
                this.drawRoadStripVertical(line, STREET_WIDTH + 3.5, "#c8d0d4");
                this.drawRoadStripHorizontal(line, STREET_WIDTH + 3.5, "#c8d0d4");
                this.drawRoadStripVertical(line, STREET_WIDTH, "#5c6672");
                this.drawRoadStripHorizontal(line, STREET_WIDTH, "#5c6672");
            }

            this.drawLaneMarks();
            this.drawParks();
            this.drawGroundGrid();
        }

        drawGroundGrid() {
            const ctx = this.ctx;
            ctx.strokeStyle = "rgba(255,255,255,0.05)";
            ctx.lineWidth = 1;
            for (let x = 0; x <= GRID_SIZE; x += 20) {
                ctx.beginPath();
                const a = this.project(x, 0, 0.02);
                const b = this.project(x, GRID_SIZE, 0.02);
                ctx.moveTo(a.x, a.y);
                ctx.lineTo(b.x, b.y);
                ctx.stroke();
            }
            for (let y = 0; y <= GRID_SIZE; y += 20) {
                ctx.beginPath();
                const a = this.project(0, y, 0.02);
                const b = this.project(GRID_SIZE, y, 0.02);
                ctx.moveTo(a.x, a.y);
                ctx.lineTo(b.x, b.y);
                ctx.stroke();
            }
        }

        drawLaneMarks() {
            const ctx = this.ctx;
            ctx.strokeStyle = "#efcf62";
            ctx.lineWidth = 1;

            for (const x of [40, 80, 120, 160]) {
                for (let y = 8; y < 190; y += 12) {
                    const a = this.project(x - 0.2, y, 0.02);
                    const b = this.project(x - 0.2, y + 5, 0.02);
                    ctx.beginPath();
                    ctx.moveTo(a.x, a.y);
                    ctx.lineTo(b.x, b.y);
                    ctx.stroke();
                }
            }

            for (const y of [40, 80, 120, 160]) {
                for (let x = 8; x < 190; x += 12) {
                    const a = this.project(x, y - 0.2, 0.02);
                    const b = this.project(x + 5, y - 0.2, 0.02);
                    ctx.beginPath();
                    ctx.moveTo(a.x, a.y);
                    ctx.lineTo(b.x, b.y);
                    ctx.stroke();
                }
            }
        }

        drawParks() {
            for (const park of PARKS) {
                this.drawPoly([
                    this.project(park.x, park.y, 0.04),
                    this.project(park.x + park.w, park.y, 0.04),
                    this.project(park.x + park.w, park.y + park.d, 0.04),
                    this.project(park.x, park.y + park.d, 0.04)
                ], "#90ab6b");

                for (let x = park.x + 4; x < park.x + park.w - 2; x += 5) {
                    for (let y = park.y + 4; y < park.y + park.d - 2; y += 6) {
                        this.drawTree(x, y);
                    }
                }
            }
        }

        drawTree(x, y) {
            const trunkBase = this.project(x, y, 0.08);
            const trunkTop = this.project(x, y, 4.2);
            const crown = this.project(x, y, 6.8);
            const ctx = this.ctx;

            ctx.strokeStyle = "#6a4e37";
            ctx.lineWidth = 1.4;
            ctx.beginPath();
            ctx.moveTo(trunkBase.x, trunkBase.y);
            ctx.lineTo(trunkTop.x, trunkTop.y);
            ctx.stroke();

            ctx.fillStyle = "#5d8148";
            ctx.beginPath();
            ctx.ellipse(crown.x, crown.y, 4.5 * this.zoom, 3.2 * this.zoom, 0, 0, Math.PI * 2);
            ctx.fill();
        }

        drawTower() {
            const base = this.project(TOWER_POS[0], TOWER_POS[1], 0);
            const top = this.project(TOWER_POS[0], TOWER_POS[1], 24);
            const ctx = this.ctx;

            this.drawShadow(TOWER_POS[0], TOWER_POS[1], 10, 4, 0.18);

            ctx.strokeStyle = "#8a98a8";
            ctx.lineWidth = 2.2;
            ctx.beginPath();
            ctx.moveTo(base.x, base.y);
            ctx.lineTo(top.x, top.y);
            ctx.stroke();

            ctx.fillStyle = "#f7d86b";
            ctx.beginPath();
            ctx.moveTo(top.x, top.y - 8);
            ctx.lineTo(top.x - 6, top.y + 5);
            ctx.lineTo(top.x + 6, top.y + 5);
            ctx.closePath();
            ctx.fill();

            for (let i = 0; i < 3; i++) {
                const r = 10 + i * 8 + ((this.time * 20 + i * 8) % 10);
                ctx.strokeStyle = `rgba(248, 214, 92, ${0.22 - i * 0.05})`;
                ctx.lineWidth = 1;
                ctx.beginPath();
                ctx.ellipse(top.x, top.y, r, r * 0.45, 0, -Math.PI / 4, Math.PI + Math.PI / 4);
                ctx.stroke();
            }
        }

        drawOris() {
            const cx = ORIS_POS[0];
            const cy = ORIS_POS[1];
            const pad = [
                this.project(cx - 4, cy - 4, 0.1),
                this.project(cx + 4, cy - 4, 0.1),
                this.project(cx + 4, cy + 4, 0.1),
                this.project(cx - 4, cy + 4, 0.1)
            ];
            this.drawShadow(cx, cy, 12, 5, 0.18);
            this.drawPoly(pad, "#cfd7de", "rgba(255,255,255,0.24)");

            const mastBase = this.project(cx, cy, 0.1);
            const mastTop = this.project(cx, cy, 9);
            const ctx = this.ctx;
            ctx.strokeStyle = "#76889a";
            ctx.lineWidth = 2.2;
            ctx.beginPath();
            ctx.moveTo(mastBase.x, mastBase.y);
            ctx.lineTo(mastTop.x, mastTop.y);
            ctx.stroke();

            const pulse = 0.55 + Math.sin(this.time * 2.5) * 0.1;
            for (let i = 0; i < 4; i++) {
                const angle = (Math.PI / 2) * i + this.time * 0.3;
                const px = cx + Math.cos(angle) * 2.4;
                const py = cy + Math.sin(angle) * 2.4;
                const panel = this.project(px, py, 7.5);
                ctx.fillStyle = `rgba(91, 185, 255, ${pulse})`;
                ctx.beginPath();
                ctx.ellipse(panel.x, panel.y, 6, 3.2, angle * 0.2, 0, Math.PI * 2);
                ctx.fill();
            }
        }

        drawVehicleBody(x, y, color, width, length, height) {
            const x0 = x - width / 2;
            const x1 = x + width / 2;
            const y0 = y - length / 2;
            const y1 = y + length / 2;
            const body = [
                this.project(x0, y0, 0.6),
                this.project(x1, y0, 0.6),
                this.project(x1, y1, 0.6),
                this.project(x0, y1, 0.6)
            ];
            const roof = [
                this.project(x0 + 0.3, y0 + 1.1, height),
                this.project(x1 - 0.3, y0 + 1.1, height),
                this.project(x1 - 0.3, y1 - 1.1, height),
                this.project(x0 + 0.3, y1 - 1.1, height)
            ];
            this.drawPoly(body, mixColor(color, -16), "rgba(255,255,255,0.08)");
            this.drawPoly(roof, mixColor(color, 14), "rgba(255,255,255,0.18)");
        }

        drawObstacle(obstacle) {
            this.drawShadow(obstacle.x, obstacle.y, obstacle.width * 2.2, obstacle.depth * 0.7, 0.18);

            if (obstacle.key === "container") {
                this.drawContainer(obstacle);
            } else if (obstacle.key === "barricade") {
                this.drawBarricade(obstacle);
            } else {
                this.drawTransitVehicle(obstacle);
            }
        }

        drawTransitVehicle(obstacle) {
            const height = obstacle.height * 0.72;
            this.drawVehicleBody(obstacle.x, obstacle.y, obstacle.color, obstacle.width, obstacle.depth, height);

            const top = [
                this.project(obstacle.x - obstacle.width * 0.24, obstacle.y - obstacle.depth * 0.2, height + 0.45),
                this.project(obstacle.x + obstacle.width * 0.24, obstacle.y - obstacle.depth * 0.2, height + 0.45),
                this.project(obstacle.x + obstacle.width * 0.24, obstacle.y + obstacle.depth * 0.2, height + 0.45),
                this.project(obstacle.x - obstacle.width * 0.24, obstacle.y + obstacle.depth * 0.2, height + 0.45)
            ];
            this.drawPoly(top, "rgba(214, 231, 242, 0.86)");
        }

        drawContainer(obstacle) {
            const x0 = obstacle.x - obstacle.width / 2;
            const x1 = obstacle.x + obstacle.width / 2;
            const y0 = obstacle.y - obstacle.depth / 2;
            const y1 = obstacle.y + obstacle.depth / 2;
            const h = obstacle.height;
            const top = [
                this.project(x0, y0, h),
                this.project(x1, y0, h),
                this.project(x1, y1, h),
                this.project(x0, y1, h)
            ];
            const left = [
                this.project(x0, y1, 0.4),
                this.project(x0, y1, h),
                this.project(x1, y1, h),
                this.project(x1, y1, 0.4)
            ];
            const right = [
                this.project(x1, y0, 0.4),
                this.project(x1, y0, h),
                this.project(x1, y1, h),
                this.project(x1, y1, 0.4)
            ];
            this.drawPoly(left, mixColor(obstacle.color, -18), "rgba(255,255,255,0.06)");
            this.drawPoly(right, mixColor(obstacle.color, 0), "rgba(255,255,255,0.08)");
            this.drawPoly(top, mixColor(obstacle.color, 18), "rgba(255,255,255,0.18)");
        }

        drawBarricade(obstacle) {
            const h = obstacle.height;
            const top = [
                this.project(obstacle.x - obstacle.width / 2, obstacle.y - obstacle.depth / 2, h),
                this.project(obstacle.x + obstacle.width / 2, obstacle.y - obstacle.depth / 2, h),
                this.project(obstacle.x + obstacle.width / 2, obstacle.y + obstacle.depth / 2, h),
                this.project(obstacle.x - obstacle.width / 2, obstacle.y + obstacle.depth / 2, h)
            ];
            const face = [
                this.project(obstacle.x - obstacle.width / 2, obstacle.y + obstacle.depth / 2, 0.35),
                this.project(obstacle.x - obstacle.width / 2, obstacle.y + obstacle.depth / 2, h),
                this.project(obstacle.x + obstacle.width / 2, obstacle.y + obstacle.depth / 2, h),
                this.project(obstacle.x + obstacle.width / 2, obstacle.y + obstacle.depth / 2, 0.35)
            ];
            this.drawPoly(face, mixColor(obstacle.color, -10), "rgba(255,255,255,0.08)");
            this.drawPoly(top, mixColor(obstacle.color, 18), "rgba(255,255,255,0.14)");
        }

        drawAmbientTraffic() {
            const traffic = [
                { x: 40, y: 12 + ((this.time * 12) % 176), width: 2.9, depth: 5.8, height: 1.8, color: "#3b82f6" },
                { x: 120, y: 188 - ((this.time * 11.5) % 176), width: 3.7, depth: 9.6, height: 2.8, color: "#f97316" },
                { x: 18 + ((this.time * 9) % 168), y: 80, width: 3.7, depth: 11.0, height: 3.2, color: "#2563eb" },
                { x: 188 - ((this.time * 8.2) % 168), y: 160, width: 3.1, depth: 5.8, height: 1.9, color: "#047857" }
            ];

            traffic.sort((a, b) => (a.x + a.y) - (b.x + b.y));
            for (const vehicle of traffic) {
                this.drawShadow(vehicle.x, vehicle.y, vehicle.width * 2.1, vehicle.depth * 0.7, 0.15);
                this.drawVehicleBody(vehicle.x, vehicle.y, vehicle.color, vehicle.width, vehicle.depth, vehicle.height);
            }
        }

        drawObstacles() {
            if (!this.state) return;
            const sorted = [...this.state.obstacles].sort((a, b) => (a.x + a.y) - (b.x + b.y));
            for (const obstacle of sorted) {
                this.drawObstacle(obstacle);
            }
        }

        drawUser() {
            if (!this.state) return;
            const [x, y] = this.state.userPos;
            const foot = this.project(x, y, 0.1);
            const body = this.project(x, y, 4);
            const head = this.project(x, y, 6.4);
            const signalColor = this.rssiColor(this.state.rssi);
            const ctx = this.ctx;

            this.drawShadow(x, y, 9, 4, 0.18);

            ctx.strokeStyle = signalColor;
            ctx.lineWidth = 1.6;
            ctx.beginPath();
            ctx.ellipse(foot.x, foot.y, 12, 6, 0, 0, Math.PI * 2);
            ctx.stroke();

            ctx.strokeStyle = "#e5edf4";
            ctx.lineWidth = 2.2;
            ctx.beginPath();
            ctx.moveTo(foot.x, foot.y - 2);
            ctx.lineTo(body.x, body.y);
            ctx.stroke();

            ctx.fillStyle = "#e2e8f0";
            ctx.beginPath();
            ctx.arc(body.x, body.y - 4, 4.6, 0, Math.PI * 2);
            ctx.fill();

            ctx.fillStyle = "#f1ceb4";
            ctx.beginPath();
            ctx.arc(head.x, head.y, 4.2, 0, Math.PI * 2);
            ctx.fill();
        }

        drawBeam() {
            if (!this.state || !this.state.aiOn) return;
            const start = this.project(ORIS_POS[0], ORIS_POS[1], 8.4);
            const end = this.project(this.state.userPos[0], this.state.userPos[1], 4.8);
            const ctx = this.ctx;
            const grad = ctx.createLinearGradient(start.x, start.y, end.x, end.y);
            grad.addColorStop(0, "rgba(91,185,255,0.08)");
            grad.addColorStop(0.45, "rgba(91,185,255,0.22)");
            grad.addColorStop(1, "rgba(91,185,255,0.62)");

            ctx.strokeStyle = grad;
            ctx.lineWidth = 8;
            ctx.beginPath();
            ctx.moveTo(start.x, start.y);
            ctx.lineTo(end.x, end.y);
            ctx.stroke();

            ctx.strokeStyle = "rgba(59,130,246,0.85)";
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.moveTo(start.x, start.y);
            ctx.lineTo(end.x, end.y);
            ctx.stroke();
        }

        rssiColor(rssi) {
            const t = clamp((rssi + 110) / 80, 0, 1);
            const palette = [
                [127, 29, 29],
                [239, 68, 36],
                [251, 191, 36],
                [34, 197, 94]
            ];
            const scaled = t * (palette.length - 1);
            const idx = Math.floor(scaled);
            const frac = scaled - idx;
            const a = palette[idx];
            const b = palette[Math.min(idx + 1, palette.length - 1)];
            const rgb = a.map((value, i) => Math.round(value + (b[i] - value) * frac));
            return `rgb(${rgb[0]}, ${rgb[1]}, ${rgb[2]})`;
        }

        drawStaticLabels() {
            const ctx = this.ctx;
            const tower = this.project(TOWER_POS[0], TOWER_POS[1], 28);
            const oris = this.project(ORIS_POS[0], ORIS_POS[1], 13);
            const user = this.state ? this.project(this.state.userPos[0], this.state.userPos[1], 8.5) : null;
            ctx.font = "700 12px Inter, sans-serif";
            ctx.fillStyle = "#f8fafc";
            ctx.fillText("SOURCE", tower.x - 20, tower.y - 10);
            ctx.fillText("O-RIS", oris.x - 16, oris.y - 10);
            if (user) ctx.fillText("USER", user.x - 14, user.y - 6);
        }

        drawSignalOverlay() {
            if (!this.state) return;
            const ctx = this.ctx;
            ctx.save();
            ctx.fillStyle = "rgba(15, 23, 42, 0.78)";
            ctx.strokeStyle = "rgba(148, 163, 184, 0.18)";
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.roundRect(18, 18, 180, 74, 10);
            ctx.fill();
            ctx.stroke();

            ctx.fillStyle = "#e2e8f0";
            ctx.font = "700 11px Inter, sans-serif";
            ctx.fillText("Link Intelligence", 30, 38);
            ctx.font = "600 10px Inter, sans-serif";
            ctx.fillStyle = "#94a3b8";
            ctx.fillText(`Quality ${this.state.quality.toFixed(0)} / 100`, 30, 56);

            const blockage = this.state.signalBreakdown
                ? `${this.state.signalBreakdown.buildingHits} building hits | ${this.state.signalBreakdown.obstacleHits} obstacle hits`
                : "No path diagnostics";
            ctx.fillText(blockage, 30, 72);
            ctx.fillText(`Zoom ${(this.zoom * 100).toFixed(0)}%`, 30, 88);
            ctx.restore();
        }

        renderCity() {
            this.drawGround();

            const structures = [...CITY_STRUCTURES].sort((a, b) => {
                const da = a.x + a.y + a.w + a.d;
                const db = b.x + b.y + b.w + b.d;
                return da - db;
            });
            for (const structure of structures) {
                this.drawBuilding(structure);
            }

            this.drawAmbientTraffic();
            this.drawTower();
            this.drawOris();
            this.drawBeam();
            this.drawObstacles();
            this.drawUser();
            this.drawStaticLabels();
            this.drawSignalOverlay();
        }

        animate() {
            this.time += 1 / 60;
            this.ctx.clearRect(0, 0, this.width, this.height);
            this.renderCity();
        }
    }

    window.CityScene3D = CityScene3D;
})();
