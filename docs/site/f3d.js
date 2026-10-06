// Flione 的 3D F：頁尾上方的收尾區塊。
// 四個色塊依 app icon 的幾何（scripts/icon/flione-f-gradient.png）擠出成實體，顏色取自 icon 的漸層。
// 進場：四塊從散開的位置彈回組成 F。互動：跟著游標轉、滑過時四塊沿深度拆開、拖曳旋轉後彈回、點一下拆開再合起來。
// 只在區塊出現在畫面上時繪製；減少動態效果時保持靜止。
import * as THREE from "three";
import { RoomEnvironment } from "./vendor/three/RoomEnvironment.js";

const stage = document.getElementById("f3d");
const canvas = stage.querySelector("canvas");
const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;

// ---- 幾何（icon 的座標，1254 × 1254，y 向下）----
const CX = 638.5, CY = 643.5; // F 外框的中心
const BLUE_END = Math.atan2(692 - 737, 209 - 541) * 180 / Math.PI; // 藍色圓弧與左緣的交點（約 -172.3°）

function arc(points, cx, cy, r, a0, a1, n = 48) {
  for (let i = 1; i <= n; i++) {
    const t = (a0 + (a1 - a0) * i / n) * Math.PI / 180;
    points.push([cx + r * Math.cos(t), cy + r * Math.sin(t)]);
  }
}

const PIECES = [
  { // 左上角的紅橘色：往下延伸到藍色直條後面、稍微往後放，由直條蓋住。
    // 照 icon 剪成弧形的話，左下會剩一個尖角，圓邊做不出來，會從直條左邊凸出去。
    // 藏在直條後面的部分往內收（左下斜切、右緣 541 → 521），側面不和直條的側面重疊在同一個平面，轉動時不會閃
    name: "corner",
    points: (() => { const p = [[235, 720], [209, 692], [209, 381]]; arc(p, 483, 381, 274, 180, 270); p.push([541, 107], [541, 402], [521, 422], [521, 720]); return p; })(),
    gradient: [[320, 180], "#fc4500", [228, 560], "#fc6302"],
    burst: [-0.9, 0.7], layer: -110, back: 10,
  },
  { // 上方的橘黃橫槓
    name: "top",
    points: (() => { const p = [[541, 107], [920.5, 107]]; arc(p, 920.5, 254.5, 147.5, -90, 90); p.push([541, 402]); return p; })(),
    gradient: [[560, 390], "#fc5e00", [1000, 175], "#fdb501"],
    burst: [0.9, 0.8], layer: 80,
  },
  { // 藍色直條
    name: "stem",
    points: (() => { const p = [[541, 402]]; arc(p, 541, 737, 335, -90, BLUE_END); p.push([209, 1014]); arc(p, 375, 1014, 166, 180, 0); return p; })(),
    gradient: [[300, 1140], "#002ce1", [530, 430], "#0065ff"],
    burst: [-0.8, -0.9], layer: 0,
  },
  { // 中間的淺藍橫槓
    name: "mid",
    points: (() => { const p = [[541, 599], [924.5, 599]]; arc(p, 924.5, 731.5, 132.5, -90, 90); p.push([541, 864]); return p; })(),
    gradient: [[560, 855], "#007ffc", [990, 630], "#01c3fb"],
    burst: [1, -0.5], layer: 220,
  },
];

const DEPTH = 150, BEVEL = 24;

function buildMesh(piece, material) {
  const shape = new THREE.Shape(piece.points.map(([x, y]) => new THREE.Vector2(x - CX, -(y - CY))));
  const geometry = new THREE.ExtrudeGeometry(shape, {
    depth: DEPTH, curveSegments: 1,
    // bevelOffset = -bevelSize：圓邊往內收，外形和 icon 一樣大，相鄰的色塊不會重疊
    bevelEnabled: true, bevelThickness: BEVEL, bevelSize: BEVEL, bevelOffset: -BEVEL, bevelSegments: 10,
  });
  geometry.translate(0, 0, -DEPTH / 2);

  // 漸層：每個頂點投影到這塊的漸層方向上取色（sRGB → 線性）
  const [p0, c0, p1, c1] = piece.gradient;
  const a = new THREE.Color().setStyle(c0, THREE.SRGBColorSpace), b = new THREE.Color().setStyle(c1, THREE.SRGBColorSpace);
  const gx = p1[0] - p0[0], gy = p1[1] - p0[1], len2 = gx * gx + gy * gy;
  const pos = geometry.attributes.position, colors = new Float32Array(pos.count * 3), c = new THREE.Color();
  for (let i = 0; i < pos.count; i++) {
    const x = pos.getX(i) + CX, y = CY - pos.getY(i);
    const t = THREE.MathUtils.clamp(((x - p0[0]) * gx + (y - p0[1]) * gy) / len2, 0, 1);
    c.copy(a).lerp(b, t);
    colors.set([c.r, c.g, c.b], i * 3);
  }
  geometry.setAttribute("color", new THREE.BufferAttribute(colors, 3));

  // 每塊以自己的中心為旋轉軸，進場與拆開時才自然
  geometry.computeBoundingBox();
  const center = geometry.boundingBox.getCenter(new THREE.Vector3());
  geometry.translate(-center.x, -center.y, -center.z);
  const mesh = new THREE.Mesh(geometry, material);
  center.z -= piece.back || 0;
  mesh.position.copy(center);
  mesh.userData = { home: center.clone(), piece };
  return mesh;
}

// ---- 場景 ----
// 用 GPU 算圖。沒有 WebGL，或瀏覽器沒有 GPU、只能用 CPU 模擬時，這裡會丟出錯誤，頁面留著平面的 F 圖（f-logo.png）
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: "high-performance", failIfMajorPerformanceCaveat: true });
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.NeutralToneMapping; // 不會把飽和的橘與藍洗淡
renderer.toneMappingExposure = 0.95;

const scene = new THREE.Scene();
const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.03).texture;
scene.environmentIntensity = 0.45; // 太強會把橘與藍洗成粉色

// near 放遠一點（相機約在 4000 外，最近的色塊也在 2000 外）：深度的精度高很多，前後很接近的面不會互相閃爍
const camera = new THREE.PerspectiveCamera(26, 1, 300, 20000);
const key = new THREE.DirectionalLight(0xffffff, 1.25);
key.position.set(-700, 900, 1400);
scene.add(key);
const rim = new THREE.DirectionalLight(0xfff1e0, 0.9);
rim.position.set(900, -300, -600);
scene.add(rim);
scene.add(new THREE.AmbientLight(0xffffff, 0.15));

const material = new THREE.MeshPhysicalMaterial({
  vertexColors: true, roughness: 0.38, metalness: 0, clearcoat: 1, clearcoatRoughness: 0.1,
});

const root = new THREE.Group();   // 漂浮、跟著游標、拖曳
const logo = new THREE.Group();   // 四塊
root.add(logo);
scene.add(root);
const meshes = PIECES.map(p => buildMesh(p, material));
meshes.forEach(m => logo.add(m));

// 地面的柔和影子：一張徑向漸層貼圖
const shadowCanvas = document.createElement("canvas");
shadowCanvas.width = shadowCanvas.height = 256;
const sctx = shadowCanvas.getContext("2d");
const grad = sctx.createRadialGradient(128, 128, 0, 128, 128, 128);
grad.addColorStop(0, "rgba(40,24,10,0.55)");
grad.addColorStop(0.45, "rgba(40,24,10,0.18)");
grad.addColorStop(1, "rgba(40,24,10,0)");
sctx.fillStyle = grad;
sctx.fillRect(0, 0, 256, 256);
const shadow = new THREE.Mesh(
  new THREE.PlaneGeometry(1, 1),
  new THREE.MeshBasicMaterial({ map: new THREE.CanvasTexture(shadowCanvas), transparent: true, depthWrite: false }),
);
shadow.rotation.x = -Math.PI / 2;
shadow.position.y = -(1180 - CY) - 150;
scene.add(shadow);

// ---- 尺寸 ----
function resize() {
  const w = stage.clientWidth, h = stage.clientHeight;
  if (!w || !h) return;
  renderer.setSize(w, h, false);
  camera.aspect = w / h;
  const tan = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
  // F 高 1073、寬 859；四周留白，拆開時也不會出框
  const byHeight = (1073 * 1.75) / (2 * tan);
  const byWidth = (859 * 2.1) / (2 * tan * camera.aspect);
  camera.position.set(0, 60, Math.max(byHeight, byWidth));
  camera.lookAt(0, -20, 0);
  camera.updateProjectionMatrix();
  if (!running) render();
}
new ResizeObserver(resize).observe(stage);

// ---- 動態 ----
// 每塊的偏移用彈簧追回 0：進場與點一下都是加速度，不是寫死的動畫
const springs = meshes.map(() => ({
  p: new THREE.Vector3(), v: new THREE.Vector3(),
  r: new THREE.Vector3(), w: new THREE.Vector3(),
  delay: 0,
}));
const pointer = { x: 0, y: 0, inside: false };
let explode = 0, spin = 0, spinVelocity = 0, spinTarget = 0, dragging = false, lastX = 0, downX = 0, downY = 0, introDone = reduce;
let running = false, time = 0, last = performance.now();
const look = { x: 0, y: 0 };

function scatter() {
  springs.forEach((s, i) => {
    const [bx, by] = meshes[i].userData.piece.burst;
    s.p.set(bx * 900, by * 700, 600 + i * 220);
    s.v.set(0, 0, 0);
    s.r.set((Math.random() - 0.5) * 2.4, (Math.random() - 0.5) * 2.8, (Math.random() - 0.5) * 1.6);
    s.w.set(0, 0, 0);
    s.delay = 0.12 + i * 0.11;
  });
}

function pop() {
  springs.forEach((s, i) => {
    const [bx, by] = meshes[i].userData.piece.burst;
    s.v.add(new THREE.Vector3(bx * 4200, by * 3600, 2600 + i * 700));
    s.w.add(new THREE.Vector3((Math.random() - 0.5) * 14, (Math.random() - 0.5) * 16, (Math.random() - 0.5) * 9));
  });
  spinTarget += Math.PI * 2; // 整個 F 轉一圈
}

function step(dt) {
  time += dt;
  // 彈簧：k 決定速度，c 決定回彈的多寡（略低於臨界阻尼，有一點點回彈）
  const k = 70, c = 13.5, kr = 60, cr = 12;
  springs.forEach(s => {
    if (s.delay > 0) { s.delay -= dt; return; }
    s.v.addScaledVector(s.p, -k * dt).multiplyScalar(Math.exp(-c * dt));
    s.p.addScaledVector(s.v, dt);
    s.w.addScaledVector(s.r, -kr * dt).multiplyScalar(Math.exp(-cr * dt));
    s.r.addScaledVector(s.w, dt);
  });

  // 滑過時四塊沿深度拆開，看得出是四塊拼成的
  const ease = 1 - Math.exp(-dt * 5);
  explode += ((pointer.inside && !dragging ? 1 : 0) - explode) * ease;

  meshes.forEach((m, i) => {
    const s = springs[i], piece = m.userData.piece, home = m.userData.home;
    m.position.set(
      home.x + s.p.x + piece.burst[0] * 70 * explode,
      home.y + s.p.y + piece.burst[1] * 50 * explode,
      home.z + s.p.z + piece.layer * 1.2 * explode,
    );
    m.rotation.set(s.r.x, s.r.y + piece.burst[0] * 0.12 * explode, s.r.z);
  });

  // 旋轉：彈簧追 spinTarget（拖曳放開時設成最近的整圈，點一下加一圈）
  if (!dragging) {
    spinVelocity += (spinTarget - spin) * 22 * dt;
    spinVelocity *= Math.exp(-5.2 * dt);
    spin += spinVelocity * dt;
  }

  // 跟著游標轉、緩慢漂浮
  const follow = 1 - Math.exp(-dt * 4);
  look.x += ((pointer.inside ? pointer.x : Math.sin(time * 0.35) * 0.35) - look.x) * follow;
  look.y += ((pointer.inside ? pointer.y : Math.sin(time * 0.27) * 0.15) - look.y) * follow;
  root.rotation.y = look.x * 0.55 + spin;
  root.rotation.x = -look.y * 0.35 + scrollTilt;
  root.position.y = Math.sin(time * 0.9) * 14;
  root.rotation.z = Math.sin(time * 0.5) * 0.015;

  // 影子跟著高度變大變淡
  const lift = root.position.y + 14;
  shadow.scale.set(1250 - lift * 4 + explode * 220, 420, 1);
  shadow.material.opacity = 0.9 - lift * 0.012 - explode * 0.25;

  key.position.x = -700 + look.x * 500;
}

function render() { renderer.render(scene, camera); }

function frame(now) {
  if (!running) return;
  const dt = Math.min((now - last) / 1000, 1 / 30);
  last = now;
  step(dt);
  render();
  requestAnimationFrame(frame);
}

function start() {
  if (running || reduce) return;
  running = true;
  last = performance.now();
  requestAnimationFrame(frame);
}
function stop() { running = false; }

// ---- 捲動與可見 ----
let visible = false, scrollTilt = 0;
new IntersectionObserver(([e]) => {
  visible = e.isIntersecting;
  if (visible && !introDone && e.intersectionRatio > 0.3) {
    introDone = true;
    scatter();
  }
  visible && !document.hidden ? start() : stop();
}, { threshold: [0, 0.3, 0.6] }).observe(stage);
document.addEventListener("visibilitychange", () => (visible && !document.hidden ? start() : stop()));
addEventListener("scroll", () => {
  const r = stage.getBoundingClientRect();
  const progress = THREE.MathUtils.clamp((innerHeight - r.top) / (innerHeight + r.height), 0, 1);
  scrollTilt = (progress - 0.5) * 0.35;
}, { passive: true });

// ---- 游標、拖曳、點一下 ----
function setPointer(e) {
  const r = stage.getBoundingClientRect();
  pointer.x = THREE.MathUtils.clamp(((e.clientX - r.left) / r.width) * 2 - 1, -1, 1);
  pointer.y = THREE.MathUtils.clamp(((e.clientY - r.top) / r.height) * 2 - 1, -1, 1);
}
function touched() { stage.classList.add("touched"); }
if (!reduce) {
  stage.addEventListener("pointermove", e => {
    setPointer(e);
    pointer.inside = e.pointerType === "mouse";
    if (dragging) {
      const dx = e.clientX - lastX;
      lastX = e.clientX;
      spin += dx * 0.01;
      spinVelocity = dx * 0.6;
    }
  });
  stage.addEventListener("pointerleave", () => { pointer.inside = false; });
  stage.addEventListener("pointerdown", e => {
    dragging = true; lastX = downX = e.clientX; downY = e.clientY;
    try { stage.setPointerCapture(e.pointerId); } catch {} // 合成的事件沒有真的指標
    stage.classList.add("grabbing");
    touched();
  });
  const release = e => {
    if (!dragging) return;
    dragging = false;
    stage.classList.remove("grabbing");
    if (Math.hypot(e.clientX - downX, e.clientY - downY) < 6) pop();
    else spinTarget = Math.round((spin + spinVelocity * 0.25) / (Math.PI * 2)) * Math.PI * 2; // 甩得快就多轉一圈
  };
  stage.addEventListener("pointerup", release);
  stage.addEventListener("pointercancel", release);
}

resize();
render();
stage.classList.add("ready");
