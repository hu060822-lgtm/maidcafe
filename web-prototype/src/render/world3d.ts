import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { CSS2DObject, CSS2DRenderer } from 'three/addons/renderers/CSS2DRenderer.js';
import type { BusinessSim, CustAgent, Party, Worker } from '../game/business';
import type { Cell, FurnitureType, GameState } from '../game/types';
import { DISH_BY_ID } from '../game/data/content';
import { MAID_BY_ID } from '../game/data/maids';
import { COFFEE, DOOR, H, KITCHEN_WALL, Layout, PASS_SLOTS, RECEPTION_DESK, SOFA, STAFF_WALL, STOVE1, STOVE2, W } from '../game/layout';

export type Pick =
  | { kind: 'worker'; id: string }
  | { kind: 'customer'; partyId: string }
  | { kind: 'cell'; cell: Cell };

const SKIN = 0xf6d7c3;
const PARTY_ICON: Record<string, string> = {
  arriving: '',
  queue: '⏳',
  toSeat: '',
  browsing: '📖',
  waitOrder: '🙋',
  waitFood: '🍽',
  eating: '😋',
  angry: '💢',
  leaving: '👋',
};

// Shared caches so per-frame props don't leak GPU resources.
const matCache = new Map<string, THREE.MeshStandardMaterial>();
const geoCache = new Map<string, THREE.BufferGeometry>();
function mat(color: number, extra: Partial<THREE.MeshStandardMaterialParameters> = {}) {
  const k = `${color}|${JSON.stringify(extra)}`;
  let m = matCache.get(k);
  if (!m) {
    m = new THREE.MeshStandardMaterial({ color, roughness: 0.8, ...extra });
    matCache.set(k, m);
  }
  return m;
}
function geo<T extends THREE.BufferGeometry>(k: string, make: () => T): T {
  let g = geoCache.get(k);
  if (!g) {
    g = make();
    geoCache.set(k, g);
  }
  return g as T;
}
function box(w: number, h: number, d: number, color: number, extra?: Partial<THREE.MeshStandardMaterialParameters>) {
  const m = new THREE.Mesh(geo(`b${w},${h},${d}`, () => new THREE.BoxGeometry(w, h, d)), mat(color, extra));
  m.castShadow = true;
  m.receiveShadow = true;
  return m;
}
function cyl(rt: number, rb: number, h: number, color: number, seg = 16) {
  const m = new THREE.Mesh(geo(`c${rt},${rb},${h},${seg}`, () => new THREE.CylinderGeometry(rt, rb, h, seg)), mat(color));
  m.castShadow = true;
  return m;
}
function sphere(r: number, color: number, extra?: Partial<THREE.MeshStandardMaterialParameters>) {
  const m = new THREE.Mesh(geo(`s${r}`, () => new THREE.SphereGeometry(r, 16, 12)), mat(color, extra));
  m.castShadow = true;
  return m;
}

interface AgentView {
  group: THREE.Group;
  body: THREE.Group;
  label: CSS2DObject;
  labelEl: HTMLDivElement;
  bubble: CSS2DObject;
  bubbleEl: HTMLDivElement;
  tray: THREE.Object3D;
  phase: number;
}

export class World3D {
  renderer: THREE.WebGLRenderer;
  labelRenderer: CSS2DRenderer;
  scene = new THREE.Scene();
  camera: THREE.PerspectiveCamera;
  controls: OrbitControls;
  private furnitureGroup = new THREE.Group();
  private dynamicGroup = new THREE.Group();
  private agents = new Map<string, AgentView>();
  private floor: THREE.Mesh;
  private ghost: THREE.Group | null = null;
  private ghostType: FurnitureType | null = null;
  private selRing: THREE.Mesh;
  private raycaster = new THREE.Raycaster();
  private stove2: THREE.Object3D;
  private sofa: THREE.Object3D;
  private coffeeUp: THREE.Object3D;
  followId: string | null = null;
  selected: Pick | null = null;
  private clock = new THREE.Clock();

  constructor(private container: HTMLElement) {
    this.renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
    this.renderer.setPixelRatio(Math.min(2, window.devicePixelRatio));
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    container.appendChild(this.renderer.domElement);
    this.labelRenderer = new CSS2DRenderer();
    this.labelRenderer.domElement.className = 'label-layer';
    container.appendChild(this.labelRenderer.domElement);

    this.scene.background = new THREE.Color(0x2a2235);
    this.scene.fog = new THREE.Fog(0x2a2235, 30, 60);
    this.camera = new THREE.PerspectiveCamera(38, 1, 0.1, 200);
    this.camera.position.set(6.8, 16.5, 23.5);
    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.target.set(6.8, 0, 6.2);
    this.controls.enableDamping = true;
    this.controls.minDistance = 4;
    this.controls.maxDistance = 32;
    this.controls.minPolarAngle = 0.25;
    this.controls.maxPolarAngle = 1.25;
    this.controls.mouseButtons = { LEFT: THREE.MOUSE.ROTATE, MIDDLE: THREE.MOUSE.DOLLY, RIGHT: THREE.MOUSE.PAN };
    this.controls.update();

    // lights
    this.scene.add(new THREE.HemisphereLight(0xfff1e0, 0x4a3a5a, 1.1));
    const sun = new THREE.DirectionalLight(0xfff0d8, 1.6);
    sun.position.set(4, 18, 10);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    const sc = sun.shadow.camera as THREE.OrthographicCamera;
    sc.left = -14;
    sc.right = 14;
    sc.top = 14;
    sc.bottom = -14;
    sun.target.position.set(8.5, 0, 5.5);
    this.scene.add(sun, sun.target);
    for (const p of [
      [5, 6],
      [12, 6],
      [8.5, 2],
    ]) {
      const l = new THREE.PointLight(0xffc98a, 6, 9, 1.5);
      l.position.set(p[0], 2.6, p[1]);
      this.scene.add(l);
    }

    // floor (pick target)
    const tex = this.checkerTexture();
    this.floor = new THREE.Mesh(new THREE.PlaneGeometry(W, H), new THREE.MeshStandardMaterial({ map: tex, roughness: 0.9 }));
    this.floor.rotation.x = -Math.PI / 2;
    this.floor.position.set(W / 2 - 0.5, 0, H / 2 - 0.5);
    this.floor.receiveShadow = true;
    this.floor.userData.pick = 'floor';
    this.scene.add(this.floor);
    const street = new THREE.Mesh(new THREE.PlaneGeometry(40, 8), mat(0x6a6670));
    street.rotation.x = -Math.PI / 2;
    street.position.set(W / 2, -0.02, H + 3);
    street.receiveShadow = true;
    this.scene.add(street);

    this.buildStatic();
    this.stove2 = this.makeStove(STOVE2);
    this.sofa = this.makeSofa();
    this.coffeeUp = box(0.3, 0.25, 0.3, 0xc0c0c8, { metalness: 0.6, roughness: 0.3 });
    this.coffeeUp.position.set(COFFEE.x + 0.1, 1.15, COFFEE.z);
    this.scene.add(this.stove2, this.sofa, this.coffeeUp);
    this.scene.add(this.furnitureGroup, this.dynamicGroup);

    this.selRing = new THREE.Mesh(new THREE.RingGeometry(0.32, 0.42, 32), new THREE.MeshBasicMaterial({ color: 0xffe066, side: THREE.DoubleSide, transparent: true, opacity: 0.9 }));
    this.selRing.rotation.x = -Math.PI / 2;
    this.selRing.visible = false;
    this.scene.add(this.selRing);

    window.addEventListener('resize', () => this.resize());
    this.resize();
  }

  private checkerTexture() {
    const c = document.createElement('canvas');
    c.width = c.height = 64;
    const g = c.getContext('2d')!;
    g.fillStyle = '#c9a27a';
    g.fillRect(0, 0, 64, 64);
    g.fillStyle = '#b48c66';
    g.fillRect(0, 0, 32, 32);
    g.fillRect(32, 32, 32, 32);
    g.strokeStyle = 'rgba(80,50,30,.25)';
    g.strokeRect(0, 0, 64, 64);
    const t = new THREE.CanvasTexture(c);
    t.wrapS = t.wrapT = THREE.RepeatWrapping;
    t.repeat.set(W / 2, H / 2);
    t.colorSpace = THREE.SRGBColorSpace;
    t.magFilter = THREE.NearestFilter;
    return t;
  }

  private buildStatic() {
    const g = new THREE.Group();
    const wallC = 0xf3e2d0;
    // back wall + side walls (low front so the camera can look in)
    const back = box(W, 2.6, 0.2, wallC);
    back.position.set(W / 2 - 0.5, 1.3, -0.4);
    const left = box(0.2, 2.6, H, wallC);
    left.position.set(-0.4, 1.3, H / 2 - 0.5);
    const right = box(0.2, 2.6, H, wallC);
    right.position.set(W - 0.6, 1.3, H / 2 - 0.5);
    const wainscot = box(W, 0.8, 0.22, 0x8a5a3a);
    wainscot.position.set(W / 2 - 0.5, 0.4, -0.38);
    g.add(back, left, right, wainscot);
    for (let x = 0; x < W; x++) {
      if (x === DOOR.x) continue;
      const f = box(1, 0.5, 0.2, 0x8a5a3a);
      f.position.set(x, 0.25, H - 0.6);
      g.add(f);
    }
    // door frame
    const sign = box(1.6, 0.35, 0.08, 0xe86a8a);
    sign.position.set(DOOR.x, 1.2, H - 0.55);
    g.add(sign);
    // kitchen floor tint
    const kf = new THREE.Mesh(new THREE.PlaneGeometry(6, 4), mat(0xdfe6ea));
    kf.rotation.x = -Math.PI / 2;
    kf.position.set(2.5, 0.01, 1.5);
    kf.receiveShadow = true;
    g.add(kf);
    const sf = new THREE.Mesh(new THREE.PlaneGeometry(4, 3), mat(0xa8c8a0));
    sf.rotation.x = -Math.PI / 2;
    sf.position.set(14.5, 0.01, 2);
    sf.receiveShadow = true;
    g.add(sf);
    // inner walls
    for (const c of [...KITCHEN_WALL, ...STAFF_WALL]) {
      const w = box(1, 1.6, 0.9, 0xe6d2bc);
      w.position.set(c.x, 0.8, c.z);
      g.add(w);
    }
    for (let x = 0; x <= 16; x++) {
      if (x === 0 || x === 17) continue;
    }
    // kitchen counters
    for (const c of [{ x: 3, z: 1 }, { x: 5, z: 1 }]) {
      const k = box(0.95, 0.9, 0.9, 0xdedede);
      k.position.set(c.x, 0.45, c.z);
      g.add(k);
    }
    g.add(this.makeStove(STOVE1));
    const cm = box(0.95, 0.9, 0.9, 0xdedede);
    cm.position.set(COFFEE.x, 0.45, COFFEE.z);
    const mach = box(0.5, 0.5, 0.45, 0x5a4a4a);
    mach.position.set(COFFEE.x, 1.15, COFFEE.z);
    g.add(cm, mach);
    for (const c of PASS_SLOTS) {
      const p = box(0.98, 1.0, 0.8, 0xb07850);
      p.position.set(c.x, 0.5, c.z);
      const top = box(1, 0.06, 0.9, 0xf0e0c0);
      top.position.set(c.x, 1.02, c.z);
      g.add(p, top);
    }
    const desk = box(0.95, 1.0, 0.8, 0xb07850);
    desk.position.set(RECEPTION_DESK.x, 0.5, RECEPTION_DESK.z);
    const reg = box(0.35, 0.25, 0.3, 0x333344);
    reg.position.set(RECEPTION_DESK.x, 1.12, RECEPTION_DESK.z);
    g.add(desk, reg);
    // staff room locker
    const locker = box(0.9, 1.8, 0.5, 0x8899aa);
    locker.position.set(13, 0.9, 1);
    g.add(locker);
    this.scene.add(g);
  }

  private makeStove(c: Cell) {
    const g = new THREE.Group();
    const b = box(0.95, 0.9, 0.9, 0x7a7a82, { metalness: 0.4 });
    b.position.y = 0.45;
    const top = box(0.95, 0.04, 0.9, 0x222222);
    top.position.y = 0.92;
    const pot = cyl(0.18, 0.16, 0.2, 0xb0b0b8);
    pot.position.set(0.15, 1.02, 0);
    g.add(b, top, pot);
    g.position.set(c.x, 0, c.z);
    return g;
  }
  private makeSofa() {
    const g = new THREE.Group();
    const seat = box(1.9, 0.4, 0.8, 0xc06a7a);
    seat.position.set(0.5, 0.25, 0);
    const back = box(1.9, 0.6, 0.2, 0xb05a6a);
    back.position.set(0.5, 0.6, -0.35);
    g.add(seat, back);
    g.position.set(SOFA[0].x, 0, SOFA[0].z);
    return g;
  }

  resize() {
    const w = this.container.clientWidth;
    const h = this.container.clientHeight;
    this.renderer.setSize(w, h);
    this.labelRenderer.setSize(w, h);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
  }

  // ------------------------------------------------------------ furniture
  rebuildFurniture(state: GameState) {
    this.furnitureGroup.clear();
    for (const f of state.furniture) {
      const o = this.makeFurniture(f.type);
      o.position.set(f.x, 0, f.z);
      o.userData.furnitureId = f.id;
      this.furnitureGroup.add(o);
    }
    this.stove2.visible = state.upgrades.secondStove;
    this.sofa.visible = state.upgrades.sofa;
    this.coffeeUp.visible = state.upgrades.coffeeMachine;
  }

  makeFurniture(type: FurnitureType): THREE.Group {
    const g = new THREE.Group();
    switch (type) {
      case 'table': {
        const top = cyl(0.42, 0.42, 0.06, 0xfaf3ea, 24);
        top.position.y = 0.72;
        const leg = cyl(0.06, 0.1, 0.7, 0x6a4a3a);
        leg.position.y = 0.35;
        g.add(top, leg);
        for (const dx of [-1, 1]) {
          const seat = box(0.5, 0.08, 0.5, 0xe88aa0);
          seat.position.set(dx, 0.45, 0);
          const back = box(0.08, 0.5, 0.5, 0xd07890);
          back.position.set(dx * 1.22, 0.7, 0);
          const l = cyl(0.04, 0.04, 0.42, 0x6a4a3a);
          l.position.set(dx, 0.22, 0);
          g.add(seat, back, l);
        }
        break;
      }
      case 'plant': {
        const pot = cyl(0.22, 0.16, 0.35, 0xb06040);
        pot.position.y = 0.18;
        const leaves = sphere(0.38, 0x4f9a50);
        leaves.position.y = 0.65;
        leaves.scale.y = 1.2;
        g.add(pot, leaves);
        break;
      }
      case 'lamp': {
        const pole = cyl(0.03, 0.05, 1.5, 0x3a3a3a);
        pole.position.y = 0.75;
        const shade = cyl(0.15, 0.28, 0.3, 0xfff0c0);
        shade.position.y = 1.55;
        shade.material = mat(0xfff0c0, { emissive: new THREE.Color(0xffc060), emissiveIntensity: 0.8 });
        g.add(pole, shade);
        break;
      }
      case 'gramophone': {
        const b = box(0.5, 0.6, 0.5, 0x6a3a1a);
        b.position.y = 0.3;
        const horn = new THREE.Mesh(new THREE.ConeGeometry(0.28, 0.5, 16, 1, true), mat(0xd4a040, { metalness: 0.6, side: THREE.DoubleSide }));
        horn.position.set(0, 0.95, 0.1);
        horn.rotation.x = Math.PI * 0.75;
        g.add(b, horn);
        break;
      }
      case 'plush': {
        const body = sphere(0.35, 0xc08a5a);
        body.position.y = 0.35;
        const head = sphere(0.26, 0xc08a5a);
        head.position.y = 0.85;
        for (const dx of [-0.18, 0.18]) {
          const ear = sphere(0.09, 0xa06a3a);
          ear.position.set(dx, 1.08, 0);
          g.add(ear);
        }
        const bow = box(0.25, 0.1, 0.05, 0xe84a6a);
        bow.position.set(0, 0.63, 0.25);
        g.add(body, head, bow);
        break;
      }
      case 'vase': {
        const st = box(0.5, 0.7, 0.5, 0x3a2a2a);
        st.position.y = 0.35;
        const v = sphere(0.2, 0xf6f6ff, { roughness: 0.2 });
        v.position.y = 0.9;
        v.scale.y = 1.4;
        const fl = sphere(0.18, 0xe86080);
        fl.position.y = 1.25;
        g.add(st, v, fl);
        break;
      }
      case 'crystal': {
        const st = cyl(0.1, 0.2, 0.9, 0x4a3a6a);
        st.position.y = 0.45;
        const c = new THREE.Mesh(new THREE.OctahedronGeometry(0.3), mat(0x9ad0ff, { emissive: new THREE.Color(0x4080ff), emissiveIntensity: 0.9, roughness: 0.1 }));
        c.position.y = 1.25;
        c.userData.spin = true;
        g.add(st, c);
        break;
      }
      case 'photo': {
        const frame = box(0.9, 1.3, 0.08, 0xffb0c8);
        frame.position.y = 0.9;
        const heart = sphere(0.18, 0xff4a7a);
        heart.position.set(0, 1.25, 0.06);
        const base = box(0.9, 0.08, 0.5, 0xffffff);
        base.position.y = 0.04;
        g.add(frame, heart, base);
        break;
      }
      case 'stage': {
        const p = box(1.95, 0.3, 1.95, 0x8a3a5a);
        p.position.set(0.5, 0.15, 0.5);
        const top = box(2, 0.04, 2, 0xd06a8a);
        top.position.set(0.5, 0.31, 0.5);
        const mic = cyl(0.02, 0.03, 1.1, 0x222222);
        mic.position.set(0.5, 0.85, 0.2);
        g.add(p, top, mic);
        break;
      }
    }
    return g;
  }

  setGhost(type: FurnitureType | null, cell: Cell | null, ok: boolean) {
    if (type !== this.ghostType) {
      if (this.ghost) this.scene.remove(this.ghost);
      this.ghost = null;
      this.ghostType = type;
      if (type) {
        this.ghost = this.makeFurniture(type);
        this.ghost.traverse((o) => {
          if ((o as THREE.Mesh).isMesh) {
            const m = (o as THREE.Mesh).material as THREE.MeshStandardMaterial;
            (o as THREE.Mesh).material = m.clone();
            ((o as THREE.Mesh).material as THREE.MeshStandardMaterial).transparent = true;
            ((o as THREE.Mesh).material as THREE.MeshStandardMaterial).opacity = 0.55;
          }
        });
        this.scene.add(this.ghost);
      }
    }
    if (this.ghost) {
      this.ghost.visible = !!cell;
      if (cell) this.ghost.position.set(cell.x, 0.02, cell.z);
      this.ghost.traverse((o) => {
        if ((o as THREE.Mesh).isMesh) ((o as THREE.Mesh).material as THREE.MeshStandardMaterial).emissive.setHex(ok ? 0x2a8a2a : 0xaa2222);
      });
    }
  }

  // ------------------------------------------------------------ agents
  private makeAgent(kind: 'maid' | 'manager' | 'customer', opts: { hair: number; color: number; name: string; costume?: boolean }): AgentView {
    const group = new THREE.Group();
    const body = new THREE.Group();
    group.add(body);
    const head = sphere(0.16, SKIN);
    head.position.y = 1.02;
    const hair = sphere(0.172, opts.hair);
    hair.position.set(0, 1.06, -0.025);
    hair.scale.set(1, 0.95, 1);
    body.add(head, hair);
    // eyes
    for (const dx of [-0.055, 0.055]) {
      const e = sphere(0.022, 0x222233);
      e.position.set(dx, 1.02, 0.145);
      e.castShadow = false;
      body.add(e);
    }
    if (kind === 'maid') {
      const dress = opts.costume ? 0xe85a8a : 0x22202c;
      const skirt = cyl(0.13, 0.32, 0.5, dress, 18);
      skirt.position.y = 0.38;
      const torso = cyl(0.11, 0.13, 0.3, dress);
      torso.position.y = 0.76;
      const apron = box(0.24, 0.42, 0.02, 0xffffff);
      apron.position.set(0, 0.45, 0.22);
      apron.rotation.x = -0.32;
      const bib = box(0.16, 0.16, 0.02, 0xffffff);
      bib.position.set(0, 0.78, 0.12);
      const band = box(0.26, 0.05, 0.08, 0xffffff);
      band.position.set(0, 1.19, 0.02);
      for (const dx of [-0.07, 0.07]) {
        const leg = cyl(0.035, 0.035, 0.18, 0xffffff, 8);
        leg.position.set(dx, 0.09, 0);
        body.add(leg);
      }
      // twin tails / long hair variants
      const tail = sphere(0.1, opts.hair);
      tail.position.set(0, 0.92, -0.16);
      tail.scale.set(1.2, 1.6, 0.8);
      body.add(skirt, torso, apron, bib, band, tail);
    } else if (kind === 'manager') {
      const pants = cyl(0.12, 0.14, 0.45, 0x2a2a3a);
      pants.position.y = 0.23;
      const jacket = cyl(0.14, 0.17, 0.42, 0x2c3e6a);
      jacket.position.y = 0.66;
      const tie = box(0.05, 0.2, 0.02, 0xd04050);
      tie.position.set(0, 0.72, 0.16);
      body.add(pants, jacket, tie);
    } else {
      const legs = cyl(0.12, 0.14, 0.42, 0x3a3a4a);
      legs.position.y = 0.21;
      const torso = cyl(0.15, 0.19, 0.46, opts.color);
      torso.position.y = 0.65;
      body.add(legs, torso);
    }
    const tray = new THREE.Group();
    const plate = cyl(0.14, 0.14, 0.02, 0xc0a070);
    tray.add(plate);
    const dish = sphere(0.07, 0xf5d040);
    dish.position.y = 0.05;
    tray.add(dish);
    tray.position.set(0.18, 0.82, 0.2);
    tray.visible = false;
    body.add(tray);

    const labelEl = document.createElement('div');
    labelEl.className = `agent-label ${kind}`;
    const label = new CSS2DObject(labelEl);
    label.position.set(0, 1.5, 0);
    group.add(label);
    const bubbleEl = document.createElement('div');
    bubbleEl.className = 'bubble';
    const bubble = new CSS2DObject(bubbleEl);
    bubble.position.set(0, 1.95, 0);
    group.add(bubble);
    for (const o of [group, ...body.children]) o.userData.agent = true;
    this.dynamicGroup.add(group);
    return { group, body, label, labelEl, bubble, bubbleEl, tray, phase: Math.random() * 6 };
  }

  private removeAgent(id: string) {
    const v = this.agents.get(id);
    if (!v) return;
    v.label.element.remove();
    v.bubble.element.remove();
    v.group.removeFromParent();
    this.agents.delete(id);
  }

  private dynMeshes: THREE.Object3D[] = [];
  private clearDyn() {
    for (const o of this.dynMeshes) o.removeFromParent();
    this.dynMeshes = [];
  }

  /** Sync all moving things with the simulation. */
  sync(sim: BusinessSim, opts: { showLabels: boolean; costume: boolean }) {
    const dt = Math.min(0.05, this.clock.getDelta());
    const t = this.clock.elapsedTime;
    const seen = new Set<string>();
    const selWorker = this.selected?.kind === 'worker' ? this.selected.id : null;
    const selParty = this.selected?.kind === 'customer' ? this.selected.partyId : null;
    let ringPos: THREE.Vector3 | null = null;

    for (const w of sim.workers) {
      const vid = `w:${w.id}:${opts.costume ? 1 : 0}`;
      seen.add(vid);
      let v = this.agents.get(vid);
      if (!v) {
        const def = w.maidId ? MAID_BY_ID[w.maidId] : null;
        v = this.makeAgent(w.kind === 'maid' ? 'maid' : 'manager', { hair: def ? def.hair : 0x3a2a20, color: 0, name: w.name, costume: opts.costume });
        v.group.userData.pick = { kind: 'worker', id: w.id };
        this.agents.set(vid, v);
      }
      this.placeAgent(v, w, t, dt, w.performing ? 'dance' : w.moving ? 'walk' : 'stand');
      v.tray.visible = !!w.carrying;
      const m = w.maidId ? sim.maid(w.maidId) : null;
      const prog = w.steps[0]?.kind === 'work' && w.stepDur > 0 ? Math.min(1, w.stepT / w.stepDur) : -1;
      const html = `<b>${w.name}</b><span class="act">${w.activity}</span>${prog >= 0 ? `<i class="prog"><i style="width:${prog * 100}%"></i></i>` : ''}${m ? `<i class="mini"><i class="fat" style="width:${m.fatigue}%"></i></i>` : ''}`;
      if (v.labelEl.innerHTML !== html) v.labelEl.innerHTML = html;
      v.label.visible = opts.showLabels || selWorker === w.id;
      this.setBubble(v, w.bubble && w.bubble.until > sim.t ? w.bubble.text : null);
      if (selWorker === w.id) ringPos = v.group.position;
    }
    for (const p of sim.parties) {
      for (const c of p.members) {
        const vid = `c:${c.id}`;
        seen.add(vid);
        let v = this.agents.get(vid);
        if (!v) {
          v = this.makeAgent('customer', { hair: c.hair, color: c.color, name: c.name });
          v.group.userData.pick = { kind: 'customer', partyId: p.id };
          this.agents.set(vid, v);
        }
        this.placeAgent(v, c, t, dt, c.sitting ? 'sit' : c.moving ? 'walk' : 'stand');
        v.tray.visible = false;
        if (c === p.members[0]) {
          const html = this.custLabel(c, p);
          if (v.labelEl.innerHTML !== html) v.labelEl.innerHTML = html;
          v.label.visible = true;
          v.labelEl.classList.toggle('angry', p.state === 'angry');
          v.labelEl.classList.toggle('named', !!c.defId);
        } else v.label.visible = false;
        this.setBubble(v, c.bubble && c.bubble.until > sim.t ? c.bubble.text : null);
        if (selParty === p.id && c === p.members[0]) ringPos = v.group.position;
      }
    }
    for (const id of [...this.agents.keys()]) if (!seen.has(id)) this.removeAgent(id);

    // dynamic props: dishes on the pass, messes, dirty tables, food on tables
    this.clearDyn();
    sim.slots.forEach((oid, i) => {
      if (!oid || oid.startsWith('reserved')) return;
      const o = sim.order(oid);
      if (!o) return;
      o.items.forEach((it, k) => {
        const d = sphere(0.09, DISH_BY_ID[it].color);
        d.position.set(PASS_SLOTS[i].x - 0.15 + k * 0.3, 1.13, PASS_SLOTS[i].z);
        this.addDyn(d);
      });
    });
    for (const st of sim.layout.stations) {
      if (sim.stationBusy[st.id]) {
        const steam = sphere(0.1, 0xffffff, { transparent: true, opacity: 0.55 });
        steam.position.set(st.cell.x, 1.3 + ((t * 0.8) % 0.5), st.cell.z);
        this.addDyn(steam);
      }
    }
    for (const m of sim.messes) {
      const puddle = new THREE.Mesh(geo('puddle', () => new THREE.CircleGeometry(0.35, 20)), mat(0x7a4a2a, { roughness: 0.2, transparent: true, opacity: 0.85 }));
      puddle.rotation.x = -Math.PI / 2;
      puddle.position.set(m.cell.x, 0.02, m.cell.z);
      puddle.userData.pick = { kind: 'cell', cell: m.cell };
      this.addDyn(puddle);
    }
    for (const tid of sim.dirtyTables) {
      const tb = sim.layout.tableById(tid);
      if (!tb) continue;
      for (const dx of [-0.15, 0.15]) {
        const plate = cyl(0.11, 0.11, 0.02, 0xdddddd);
        plate.position.set(tb.cell.x + dx, 0.77, tb.cell.z);
        const crumbs = sphere(0.04, 0x8a6a4a);
        crumbs.position.set(tb.cell.x + dx, 0.8, tb.cell.z);
        this.addDyn(plate);
        this.addDyn(crumbs);
      }
    }
    for (const p of sim.parties) {
      if (p.state !== 'eating' || !p.tableId) continue;
      const tb = sim.layout.tableById(p.tableId);
      if (!tb) continue;
      const items = p.members.flatMap((m) => m.items);
      items.forEach((it, k) => {
        const d = sphere(0.08, DISH_BY_ID[it].color);
        d.position.set(tb.cell.x - 0.2 + (k % 3) * 0.2, 0.82, tb.cell.z + (k > 2 ? 0.15 : -0.05));
        this.addDyn(d);
      });
    }
    // spin crystals
    this.furnitureGroup.traverse((o) => {
      if (o.userData.spin) o.rotation.y += dt * 1.2;
    });

    if (ringPos) {
      this.selRing.visible = true;
      this.selRing.position.set(ringPos.x, 0.03, ringPos.z);
    } else if (this.selected?.kind === 'cell') {
      this.selRing.visible = true;
      this.selRing.position.set(this.selected.cell.x, 0.03, this.selected.cell.z);
    } else this.selRing.visible = false;

    if (this.followId) {
      const v = [...this.agents.entries()].find(([k]) => k.startsWith(`w:${this.followId}:`) || k === `c:${this.followId}`)?.[1];
      if (v) {
        const target = v.group.position.clone();
        const delta = target.clone().sub(this.controls.target);
        delta.y = 0;
        this.controls.target.add(delta.multiplyScalar(0.12));
        this.camera.position.add(delta);
      }
    }
  }

  private addDyn(o: THREE.Object3D) {
    this.dynamicGroup.add(o);
    this.dynMeshes.push(o);
  }

  private custLabel(c: CustAgent, p: Party) {
    const icon = PARTY_ICON[p.state] ?? '';
    const sat = Math.max(0, Math.min(100, c.sat));
    const col = sat >= 70 ? '#5cd68a' : sat >= 45 ? '#f2c94c' : '#ff6b6b';
    const extra = p.members.length > 1 ? ' +1' : '';
    return `<b>${icon} ${c.name}${extra}</b><i class="mini"><i style="width:${sat}%;background:${col}"></i></i>`;
  }

  private setBubble(v: AgentView, text: string | null) {
    if (!text) {
      v.bubble.visible = false;
      return;
    }
    v.bubble.visible = true;
    if (v.bubbleEl.textContent !== text) v.bubbleEl.textContent = text;
  }

  private placeAgent(v: AgentView, m: { pos: { x: number; z: number }; facing: number; seat?: Cell | null }, t: number, _dt: number, pose: 'walk' | 'stand' | 'sit' | 'dance') {
    v.group.position.set(m.pos.x, 0, m.pos.z);
    v.group.rotation.y = m.facing;
    const ph = t * 10 + v.phase;
    v.body.position.y = 0;
    v.body.rotation.z = 0;
    v.body.scale.y = 1;
    if (pose === 'walk') v.body.position.y = Math.abs(Math.sin(ph)) * 0.05;
    if (pose === 'sit') {
      v.body.position.y = 0.05;
      v.body.scale.y = 0.85;
    }
    if (pose === 'dance') {
      v.body.position.y = 0.3 + Math.abs(Math.sin(ph * 0.6)) * 0.12;
      v.body.rotation.z = Math.sin(ph * 0.3) * 0.15;
      v.group.rotation.y = Math.sin(t * 1.5) * 0.6;
    }
    if (pose === 'stand') v.body.scale.y = 1 + Math.sin(t * 2 + v.phase) * 0.008;
  }

  // ------------------------------------------------------------ picking
  pick(clientX: number, clientY: number): Pick | null {
    const r = this.renderer.domElement.getBoundingClientRect();
    const ndc = new THREE.Vector2(((clientX - r.left) / r.width) * 2 - 1, -((clientY - r.top) / r.height) * 2 + 1);
    this.raycaster.setFromCamera(ndc, this.camera);
    const hits = this.raycaster.intersectObjects([this.dynamicGroup, this.furnitureGroup, this.floor], true);
    for (const h of hits) {
      let o: THREE.Object3D | null = h.object;
      while (o) {
        if (o.userData.pick && typeof o.userData.pick === 'object') return o.userData.pick as Pick;
        if (o.userData.furnitureId) {
          return { kind: 'cell', cell: { x: Math.round(o.position.x), z: Math.round(o.position.z) } };
        }
        o = o.parent;
      }
      if (h.object === this.floor) {
        return { kind: 'cell', cell: { x: Math.round(h.point.x), z: Math.round(h.point.z) } };
      }
    }
    return null;
  }

  /** Floor cell under the cursor (ignores agents), used for placement. */
  cellAt(clientX: number, clientY: number): Cell | null {
    const r = this.renderer.domElement.getBoundingClientRect();
    const ndc = new THREE.Vector2(((clientX - r.left) / r.width) * 2 - 1, -((clientY - r.top) / r.height) * 2 + 1);
    this.raycaster.setFromCamera(ndc, this.camera);
    const h = this.raycaster.intersectObject(this.floor)[0];
    return h ? { x: Math.round(h.point.x), z: Math.round(h.point.z) } : null;
  }

  furnitureAt(layout: Layout, c: Cell) {
    return layout.furnitureAt.get(`${c.x},${c.z}`) ?? null;
  }

  resetCamera() {
    this.followId = null;
    this.controls.target.set(6.8, 0, 6.2);
    this.camera.position.set(6.8, 16.5, 23.5);
  }

  render() {
    this.controls.update();
    this.renderer.render(this.scene, this.camera);
    this.labelRenderer.render(this.scene, this.camera);
  }
}

export type { Worker };
