/* Retro 90s browser splash-style animated background for the supporter
   page hero. The scene renders at low resolution with 4x4 ordered dithering
   and web-safe color quantization, then upscales with image-rendering:
   pixelated. Animation steps at 70ms/frame to match the cadence of the
   era's splash screens. Purely decorative: the canvases are aria-hidden and
   the whole thing is skipped for prefers-reduced-motion. */

(function () {
  'use strict';

  if (!window.requestAnimationFrame || !window.Path2D) return;

  var STEP_MS = 70;
  var PIX = 3;

  var BAYER = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5]
  ];

  function mulberry32(seed) {
    var a = seed >>> 0;
    return function () {
      a |= 0; a = (a + 0x6D2B79F5) | 0;
      var t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  // Ordered dither + web-safe (multiple of 51) quantization. With alphaToo,
  // soft alpha is crunched to on/off pixels so glows and trails get the
  // classic GIF speckle instead of smooth gradients.
  function ditherImageData(img, alphaToo) {
    var d = img.data, w = img.width;
    var x = 0, y = 0;
    for (var p = 0; p < d.length; p += 4) {
      var b = (BAYER[y & 3][x & 3] + 0.5) / 16 - 0.5;
      var skip = false;
      if (alphaToo) {
        var a = d[p + 3];
        if (a === 0) {
          skip = true;
        } else {
          d[p + 3] = (a + b * 160) >= 128 ? 255 : 0;
          if (!d[p + 3]) skip = true;
        }
      }
      if (!skip) {
        for (var c = 0; c < 3; c++) {
          var v = Math.round((d[p + c] + b * 51) / 51) * 51;
          d[p + c] = v < 0 ? 0 : v > 255 ? 255 : v;
        }
      }
      if (++x === w) { x = 0; y++; }
    }
  }

  // Teal glow ramp sampled from the Navigator 2.02 splash, as a 256-entry LUT.
  var RAMP = [
    [0.00, 0x00, 0x00, 0x00],
    [0.10, 0x06, 0x18, 0x1a],
    [0.25, 0x0e, 0x3b, 0x40],
    [0.42, 0x1e, 0x6a, 0x6a],
    [0.58, 0x33, 0x93, 0x90],
    [0.72, 0x62, 0xb8, 0xab],
    [0.84, 0xa8, 0xde, 0xd2],
    [0.93, 0xdd, 0xf7, 0xee],
    [1.00, 0xff, 0xff, 0xff]
  ];
  var LUT = (function () {
    var lut = new Uint8Array(256 * 3);
    for (var i = 0; i < 256; i++) {
      var t = i / 255, s = 0;
      while (s < RAMP.length - 2 && RAMP[s + 1][0] < t) s++;
      var a = RAMP[s], b = RAMP[s + 1];
      var k = (t - a[0]) / (b[0] - a[0]);
      k = k < 0 ? 0 : k > 1 ? 1 : k;
      for (var c = 0; c < 3; c++) lut[i * 3 + c] = Math.round(a[c + 1] + (b[c + 1] - a[c + 1]) * k);
    }
    return lut;
  })();

  function starColor(r) {
    if (r < 0.62) return '#e8fffa';
    if (r < 0.76) return '#ffffff';
    if (r < 0.86) return '#9fe8ff';
    if (r < 0.95) return '#ffdd88';
    return '#ff9966';
  }

  /* ---------------- shared dynamic sprites ---------------- */

  function spawnMeteor(W, H, big, cfg) {
    var slope = 0.34 + Math.random() * 0.24;
    var inv = 1 / Math.sqrt(1 + slope * slope);
    var speed = (big ? cfg.bigSpeed : cfg.speed) * (0.85 + Math.random() * 0.35);
    return {
      x: W * (0.25 + Math.random() * 0.95),
      y: H * (-0.06 + Math.random() * cfg.spawnBand),
      vx: -speed * inv,
      vy: speed * slope * inv,
      w: big ? cfg.bigWidth * (0.85 + Math.random() * 0.3) : cfg.width * (0.8 + Math.random() * 0.5),
      trail: speed * (big ? 7 : 5.2),
      big: big
    };
  }

  function drawMeteor(fx, m, cfg) {
    var spd = Math.sqrt(m.vx * m.vx + m.vy * m.vy);
    var ux = m.vx / spd, uy = m.vy / spd;
    var tx = m.x - ux * m.trail, ty = m.y - uy * m.trail;

    if (m.big && cfg.flashR) {
      var fl = fx.createRadialGradient(m.x, m.y, 0, m.x, m.y, cfg.flashR);
      fl.addColorStop(0, 'rgba(150,235,215,' + (cfg.flashA || 0.45) + ')');
      fl.addColorStop(1, 'rgba(150,235,215,0)');
      fx.fillStyle = fl;
      fx.fillRect(m.x - cfg.flashR, m.y - cfg.flashR, cfg.flashR * 2, cfg.flashR * 2);
    }

    var g = fx.createLinearGradient(m.x, m.y, tx, ty);
    g.addColorStop(0, 'rgba(255,255,255,1)');
    g.addColorStop(0.25, 'rgba(205,255,242,0.9)');
    g.addColorStop(0.7, 'rgba(110,220,200,0.55)');
    g.addColorStop(1, 'rgba(30,120,120,0)');
    fx.strokeStyle = g;
    fx.lineWidth = m.w;
    fx.lineCap = 'round';
    fx.beginPath();
    fx.moveTo(m.x, m.y);
    fx.lineTo(tx, ty);
    fx.stroke();

    fx.strokeStyle = 'rgba(255,255,255,0.95)';
    fx.lineWidth = Math.max(1, m.w * 0.45);
    fx.beginPath();
    fx.moveTo(m.x, m.y);
    fx.lineTo(m.x - ux * m.trail * 0.5, m.y - uy * m.trail * 0.5);
    fx.stroke();

    fx.fillStyle = '#ffffff';
    fx.fillRect(m.x - 1, m.y - 1, 3, 3);
    fx.fillRect(m.x - 3, m.y, 1, 1);
    fx.fillRect(m.x + 3, m.y, 1, 1);
    fx.fillRect(m.x, m.y - 3, 1, 1);
    fx.fillRect(m.x, m.y + 3, 1, 1);
  }

  function drawFlare(fx, f) {
    var k = 1 - f.phase / f.life;
    var L = f.size * (f.phase < 2 ? (f.phase + 1) / 2 : k);
    fx.strokeStyle = 'rgba(225,255,248,' + (0.85 * k + 0.1) + ')';
    fx.lineWidth = 1;
    fx.beginPath();
    fx.moveTo(f.x - L, f.y); fx.lineTo(f.x + L, f.y);
    fx.moveTo(f.x, f.y - L * 0.55); fx.lineTo(f.x, f.y + L * 0.55);
    fx.moveTo(f.x - L * 0.35, f.y - L * 0.35); fx.lineTo(f.x + L * 0.35, f.y + L * 0.35);
    fx.moveTo(f.x - L * 0.35, f.y + L * 0.35); fx.lineTo(f.x + L * 0.35, f.y - L * 0.35);
    fx.stroke();
    fx.strokeStyle = 'rgba(170,240,228,' + (0.5 * k) + ')';
    fx.beginPath();
    fx.arc(f.x, f.y, 3 + f.phase * 2.2, 0, Math.PI * 2);
    fx.stroke();
    fx.fillStyle = 'rgba(255,255,255,' + (0.6 + 0.4 * k) + ')';
    fx.fillRect(f.x - 1, f.y - 1, 2, 2);
  }

  function drawTwinkle(fx, t) {
    var arm = [1, 2, 3, 3, 2, 1][t.phase] * t.scale;
    fx.strokeStyle = 'rgba(255,255,255,0.9)';
    fx.lineWidth = 1;
    fx.beginPath();
    fx.moveTo(t.x - arm, t.y); fx.lineTo(t.x + arm, t.y);
    fx.moveTo(t.x, t.y - arm); fx.lineTo(t.x, t.y + arm);
    fx.stroke();
    fx.fillStyle = '#ffffff';
    fx.fillRect(t.x, t.y, 1, 1);
  }

  function stepSprites(p) {
    var cfg = p.cfg, W = p.W, H = p.H, i;

    if (p.meteors.filter(function (m) { return !m.big; }).length < cfg.maxSmall &&
        Math.random() < cfg.spawnChance) {
      p.meteors.push(spawnMeteor(W, H, false, cfg));
    }
    if (--p.nextBig <= 0) {
      p.meteors.push(spawnMeteor(W, H, true, cfg));
      p.nextBig = cfg.bigEvery[0] + Math.random() * (cfg.bigEvery[1] - cfg.bigEvery[0]);
    }
    for (i = p.meteors.length - 1; i >= 0; i--) {
      var m = p.meteors[i];
      m.x += m.vx; m.y += m.vy;
      if (m.x + m.trail < -4 || m.y - m.trail > H + 4) p.meteors.splice(i, 1);
    }

    if (--p.nextFlare <= 0) {
      p.flares.push({
        x: W * (0.08 + Math.random() * 0.84),
        y: H * (0.04 + Math.random() * cfg.flareBand),
        phase: 0,
        life: 6,
        size: cfg.flareSize * (0.7 + Math.random() * 0.6)
      });
      p.nextFlare = cfg.flareEvery[0] + Math.random() * (cfg.flareEvery[1] - cfg.flareEvery[0]);
    }
    for (i = p.flares.length - 1; i >= 0; i--) {
      if (++p.flares[i].phase >= p.flares[i].life) p.flares.splice(i, 1);
    }

    while (p.twinkles.length < cfg.twinkles && p.stars.length) {
      var s = p.stars[(Math.random() * p.stars.length) | 0];
      p.twinkles.push({ x: s[0], y: s[1], phase: 0, scale: cfg.twinkleScale });
    }
    for (i = p.twinkles.length - 1; i >= 0; i--) {
      if (++p.twinkles[i].phase > 5) p.twinkles.splice(i, 1);
    }
  }

  function renderSprites(p) {
    var fx = p.fctx, i;
    fx.clearRect(0, 0, p.W, p.H);
    for (i = 0; i < p.meteors.length; i++) drawMeteor(fx, p.meteors[i], p.cfg);
    for (i = 0; i < p.flares.length; i++) drawFlare(fx, p.flares[i]);
    for (i = 0; i < p.twinkles.length; i++) drawTwinkle(fx, p.twinkles[i]);

    var img = fx.getImageData(0, 0, p.W, p.H);
    ditherImageData(img, true);
    fx.putImageData(img, 0, 0);

    var ctx = p.ctx;
    ctx.drawImage(p.staticCv, 0, 0);
    ctx.globalCompositeOperation = 'lighten';
    ctx.drawImage(p.fxCv, 0, 0);
    ctx.globalCompositeOperation = 'source-over';
    if (p.overlayCv) ctx.drawImage(p.overlayCv, 0, 0);

    // the planet comet travels in front of the overlay
    if (p.pComet) {
      var f2 = p.fctx2;
      f2.clearRect(0, 0, p.W, p.H);
      p.drawPlanetComet(f2);
      var img2 = f2.getImageData(0, 0, p.W, p.H);
      ditherImageData(img2, true);
      f2.putImageData(img2, 0, 0);
      ctx.globalCompositeOperation = 'lighten';
      ctx.drawImage(p.fx2Cv, 0, 0);
      ctx.globalCompositeOperation = 'source-over';
    }
  }

  function makeLayers(p, W, H) {
    p.W = W; p.H = H;
    p.cv.width = W; p.cv.height = H;
    p.staticCv = document.createElement('canvas');
    p.staticCv.width = W; p.staticCv.height = H;
    p.sctx = p.staticCv.getContext('2d');
    p.fxCv = document.createElement('canvas');
    p.fxCv.width = W; p.fxCv.height = H;
    p.fctx = p.fxCv.getContext('2d', { willReadFrequently: true });
    p.fx2Cv = document.createElement('canvas');
    p.fx2Cv.width = W; p.fx2Cv.height = H;
    p.fctx2 = p.fx2Cv.getContext('2d', { willReadFrequently: true });
  }

  /* ---------------- the big hero scene ---------------- */

  function HeroPainter(canvas) {
    this.cv = canvas;
    this.ctx = canvas.getContext('2d');
    this.meteors = [];
    this.flares = [];
    this.twinkles = [];
    this.stars = [];
    this.cfg = {
      spawnChance: 0.09,
      maxSmall: 2,
      spawnBand: 0.4,
      bigEvery: [100, 170],
      flareEvery: [120, 210],
      flareBand: 0.4,
      flareSize: 15,
      twinkles: 6,
      twinkleScale: 1
    };
    this.nextBig = 40 + Math.random() * 60;
    this.nextFlare = 30 + Math.random() * 60;
    this.pComet = null;
    this.nextPComet = 80 + Math.random() * 100;
  }

  HeroPainter.prototype.resize = function (wCss, hCss) {
    var W = Math.max(60, Math.round(wCss / PIX));
    var H = Math.max(40, Math.round(hCss / PIX));
    if (W === this.W && H === this.H) return;
    makeLayers(this, W, H);
    this.cfg.speed = W * 0.075;
    this.cfg.bigSpeed = W * 0.08;
    this.cfg.width = 2.5;
    this.cfg.bigWidth = 6.5;
    this.cfg.flashR = W * 0.3;
    this.pComet = null;
    this.renderStatic();
    renderSprites(this);
  };

  HeroPainter.prototype.horizonY = function (x) {
    var dx = x - this.pcx;
    var s = this.pR * this.pR - dx * dx;
    if (s <= 0) return this.H + 60;
    return this.pcy - Math.sqrt(s);
  };

  HeroPainter.prototype.wheelPath = function (cx, cy, R) {
    var p = new Path2D();
    // solid face; the spoke shapes come from the petal openings cut out of it
    p.arc(cx, cy, R, 0, Math.PI * 2, false);
    for (var k = 0; k < 8; k++) {
      var a = k * Math.PI / 4;
      var ca = Math.cos(a), sa = Math.sin(a);
      var px = -sa, py = ca;

      // handle: neck from the outer ring, then a turned teardrop knob.
      // Wound clockwise to match the disc and knob — opposite winding would
      // cancel under the nonzero fill rule and punch see-through slots where
      // the neck overlaps them.
      var n0 = R * 0.97, n1 = R * 1.13, nw0 = R * 0.055, nw1 = R * 0.038;
      p.moveTo(cx + ca * n0 - px * nw0, cy + sa * n0 - py * nw0);
      p.lineTo(cx + ca * n1 - px * nw1, cy + sa * n1 - py * nw1);
      p.lineTo(cx + ca * n1 + px * nw1, cy + sa * n1 + py * nw1);
      p.lineTo(cx + ca * n0 + px * nw0, cy + sa * n0 + py * nw0);
      p.closePath();
      p.ellipse(cx + ca * R * 1.24, cy + sa * R * 1.24, R * 0.145, R * 0.075, a, 0, Math.PI * 2);
    }
    return p;
  };

  // The openings between spokes, matching the splash art: wedges that are
  // wide at the ring, narrow to a rounded tip near the hub, with concave
  // flanks so the spokes flare into fillets at both ends.
  HeroPainter.prototype.petalPath = function (cx, cy, R, inset) {
    var p = new Path2D();
    // dOut leaves the spokes only slightly wider than the handle necks where
    // they meet the ring; rOut keeps the ring band thin. An inset (in scene
    // px) shrinks the petals, e.g. to erase glow while keeping a lit rim.
    inset = inset || 0;
    var rOut = R * 0.78 - inset, rTip = R * 0.3 + inset, rMid = R * 0.54;
    var dOut = 0.31 - inset / rOut, dTip = 0.096 - inset / rTip, dCtl = 0.12;
    for (var k = 0; k < 8; k++) {
      var tc = k * Math.PI / 4 + Math.PI / 8;
      p.moveTo(cx + Math.cos(tc - dOut) * rOut, cy + Math.sin(tc - dOut) * rOut);
      p.arc(cx, cy, rOut, tc - dOut, tc + dOut, false);
      p.quadraticCurveTo(
        cx + Math.cos(tc + dCtl) * rMid, cy + Math.sin(tc + dCtl) * rMid,
        cx + Math.cos(tc + dTip) * rTip, cy + Math.sin(tc + dTip) * rTip);
      p.arc(cx, cy, rTip, tc + dTip, tc - dTip, true);
      p.quadraticCurveTo(
        cx + Math.cos(tc - dCtl) * rMid, cy + Math.sin(tc - dCtl) * rMid,
        cx + Math.cos(tc - dOut) * rOut, cy + Math.sin(tc - dOut) * rOut);
      p.closePath();
    }
    return p;
  };

  HeroPainter.prototype.renderStatic = function () {
    var W = this.W, H = this.H, sc = this.sctx;
    var rand = mulberry32(0xC0FFEE);
    var x, y, i;

    // the planet horizon is a proper circular disc, like the logo box
    this.pcx = W * 0.5;
    this.pR = W;
    this.pcy = H * 0.83 + this.pR;

    var yH = new Float32Array(W);
    for (x = 0; x < W; x++) yH[x] = this.horizonY(x);

    // on wide layouts, keep the wheel right of the hero copy
    var wcx = W * (W > H * 1.6 ? 0.59 : 0.56);
    var R = Math.min(H * 0.5, W * 0.62);
    var wcy = this.horizonY(wcx) + R * 0.2;

    // dithered glow field
    var g1x = wcx, g1y = H * 0.68, g1sx = W * 0.36, g1sy = H * 0.42;
    var g2x = wcx, g2y = wcy - R * 0.5, g2sx = R * 0.62, g2sy = R * 0.46;
    var img = sc.createImageData(W, H);
    var d = img.data, p = 0;
    for (y = 0; y < H; y++) {
      for (x = 0; x < W; x++, p += 4) {
        var dx1 = (x - g1x) / g1sx, dy1 = (y - g1y) / g1sy;
        var dx2 = (x - g2x) / g2sx, dy2 = (y - g2y) / g2sy;
        var t = 0.045 +
          0.55 * Math.exp(-(dx1 * dx1 + dy1 * dy1) * 0.7) +
          0.24 * Math.exp(-(dx2 * dx2 + dy2 * dy2) * 0.9);
        // cap the glow so the center stays teal instead of blowing out white
        if (t > 0.78) t = 0.78;
        var hd = yH[x] - y;
        if (hd > 0 && hd < 8) t += 0.2 * (1 - hd / 8);
        t = Math.pow(t > 1 ? 1 : t, 1.12);
        var ti = (t * 255) | 0;
        var b = (BAYER[y & 3][x & 3] + 0.5) / 16 - 0.5;
        for (var c = 0; c < 3; c++) {
          var v = Math.round((LUT[ti * 3 + c] + b * 51) / 51) * 51;
          d[p + c] = v < 0 ? 0 : v > 255 ? 255 : v;
        }
        d[p + 3] = 255;
      }
    }
    sc.putImageData(img, 0, 0);

    // pixel stars
    sc.globalCompositeOperation = 'lighten';
    this.stars = [];
    var count = Math.round(W * H / 620);
    for (i = 0; i < count; i++) {
      x = (rand() * W) | 0;
      y = (rand() * H * 0.96) | 0;
      if (y > yH[x] - 2) continue;
      var big = rand() > 0.94;
      sc.fillStyle = starColor(rand());
      sc.fillRect(x, y, 1, 1);
      if (big) {
        sc.fillRect(x - 1, y, 1, 1); sc.fillRect(x + 1, y, 1, 1);
        sc.fillRect(x, y - 1, 1, 1); sc.fillRect(x, y + 1, 1, 1);
      }
      if (y < H * 0.75) this.stars.push([x, y]);
    }
    sc.globalCompositeOperation = 'source-over';

    // the backlit ship's wheel + horizon live on a foreground overlay, so
    // meteors pass behind them
    var wheel = document.createElement('canvas');
    wheel.width = W; wheel.height = H;
    var wc = wheel.getContext('2d', { willReadFrequently: true });
    // silhouette mask: union shape minus the petal-shaped openings, so glow,
    // rim light, and body shading all follow the true silhouette (a stroked
    // path would outline subpath edges buried inside the union)
    var mask = document.createElement('canvas');
    mask.width = W; mask.height = H;
    var mk = mask.getContext('2d');
    var petals = this.petalPath(wcx, wcy, R);
    mk.fillStyle = '#f2fffb';
    mk.fill(this.wheelPath(wcx, wcy, R));
    mk.globalCompositeOperation = 'destination-out';
    mk.fill(petals);
    mk.globalCompositeOperation = 'source-over';

    // rim-light mask without the handles: outlining them draws distracting
    // lines at the ring joints and knob waists, so the handles are left to
    // the corona glow alone
    var coreMask = document.createElement('canvas');
    coreMask.width = W; coreMask.height = H;
    var ck = coreMask.getContext('2d');
    ck.fillStyle = '#f2fffb';
    ck.beginPath();
    ck.arc(wcx, wcy, R, 0, Math.PI * 2);
    ck.fill();
    ck.globalCompositeOperation = 'destination-out';
    ck.fill(petals);
    ck.globalCompositeOperation = 'source-over';

    var OFF = 4000;
    wc.save();
    wc.translate(-OFF, 0);
    wc.shadowOffsetX = OFF;
    wc.shadowColor = 'rgba(236,255,250,0.6)';
    wc.shadowBlur = R * 0.11;
    wc.drawImage(mask, 0, 0);
    wc.shadowBlur = R * 0.04;
    wc.shadowColor = 'rgba(255,255,255,0.9)';
    wc.drawImage(mask, 0, 0);
    wc.restore();

    // crisp rim light: 1px-dilated silhouette under the body, outlining the
    // ring and every petal opening (handles excluded)
    var OFFS = [[-1, 0], [1, 0], [0, -1], [0, 1], [-1, -1], [1, -1], [-1, 1], [1, 1]];
    for (i = 0; i < OFFS.length; i++) wc.drawImage(coreMask, OFFS[i][0], OFFS[i][1]);

    // keep the openings truly transparent: the corona bleeds into them, so
    // clear their interiors back out, leaving only a thin lit rim
    wc.globalCompositeOperation = 'destination-out';
    wc.fill(this.petalPath(wcx, wcy, R, 2));
    wc.globalCompositeOperation = 'source-over';

    // sprites for the dynamic light the planet comet casts as it passes:
    // the wheel's inner edge (silhouette minus its 1px erosion) and the
    // planet's rim, lit per-frame around the comet's head
    var erode = document.createElement('canvas');
    erode.width = W; erode.height = H;
    var ek = erode.getContext('2d');
    ek.drawImage(mask, 0, 0);
    ek.globalCompositeOperation = 'destination-in';
    for (i = 0; i < OFFS.length; i++) ek.drawImage(mask, OFFS[i][0], OFFS[i][1]);
    var edge = document.createElement('canvas');
    edge.width = W; edge.height = H;
    var ec = edge.getContext('2d');
    ec.drawImage(mask, 0, 0);
    ec.globalCompositeOperation = 'destination-out';
    ec.drawImage(erode, 0, 0);
    ec.globalCompositeOperation = 'source-in';
    ec.fillStyle = '#dffff6';
    ec.fillRect(0, 0, W, H);
    // clip away the wheel's lower half hidden behind the planet, so the
    // comet never lights edges that aren't actually visible
    var pclip = new Path2D();
    pclip.arc(this.pcx, this.pcy, this.pR, 0, Math.PI * 2);
    ec.globalCompositeOperation = 'destination-out';
    ec.fill(pclip);
    this.wheelEdgeCv = edge;

    var wvis = document.createElement('canvas');
    wvis.width = W; wvis.height = H;
    var wv = wvis.getContext('2d');
    wv.drawImage(mask, 0, 0);
    wv.globalCompositeOperation = 'destination-out';
    wv.fill(pclip);
    this.wheelMaskCv = wvis;

    var rim = document.createElement('canvas');
    rim.width = W; rim.height = H;
    var rc = rim.getContext('2d');
    rc.strokeStyle = 'rgba(235,255,250,0.95)';
    rc.lineWidth = 1.5;
    rc.beginPath();
    rc.arc(this.pcx, this.pcy, this.pR, 0, Math.PI * 2);
    rc.stroke();
    rc.strokeStyle = 'rgba(180,240,225,0.5)';
    rc.lineWidth = 4;
    rc.beginPath();
    rc.arc(this.pcx, this.pcy, this.pR + 2, 0, Math.PI * 2);
    rc.stroke();
    this.planetRimCv = rim;

    this.lightCv = document.createElement('canvas');
    this.lightCv.width = W; this.lightCv.height = H;
    this.lctx = this.lightCv.getContext('2d');

    // 3D body shading composited inside the mask: dark at the hub, catching
    // more light toward the ring and handle tips
    var bodyCv = document.createElement('canvas');
    bodyCv.width = W; bodyCv.height = H;
    var bc = bodyCv.getContext('2d');
    bc.drawImage(mask, 0, 0);
    bc.globalCompositeOperation = 'source-in';
    var body = bc.createRadialGradient(wcx, wcy, R * 0.1, wcx, wcy, R * 1.42);
    body.addColorStop(0, '#0e282b');
    body.addColorStop(0.5, '#133438');
    body.addColorStop(0.7, '#1e4a4e');
    body.addColorStop(0.86, '#376d70');
    body.addColorStop(1, '#639e9d');
    bc.fillStyle = body;
    bc.fillRect(0, 0, W, H);

    // light falling from above
    bc.globalCompositeOperation = 'source-atop';
    var lg = bc.createLinearGradient(0, wcy - R * 1.42, 0, wcy + R * 0.2);
    lg.addColorStop(0, 'rgba(225,255,250,0.55)');
    lg.addColorStop(0.4, 'rgba(190,235,228,0.16)');
    lg.addColorStop(1, 'rgba(0,0,0,0)');
    bc.fillStyle = lg;
    bc.fillRect(0, 0, W, H);

    // hub cap
    var hg = bc.createRadialGradient(wcx - R * 0.04, wcy - R * 0.05, 0, wcx, wcy, R * 0.14);
    hg.addColorStop(0, '#4d8487');
    hg.addColorStop(1, '#0e282b');
    bc.fillStyle = hg;
    bc.beginPath();
    bc.arc(wcx, wcy, R * 0.13, 0, Math.PI * 2);
    bc.fill();

    wc.drawImage(bodyCv, 0, 0);

    // the circular planet, covering the wheel's lower half
    var pp = new Path2D();
    pp.arc(this.pcx, this.pcy, this.pR, 0, Math.PI * 2);
    var pg = wc.createRadialGradient(this.pcx, this.pcy, this.pR * 0.85, this.pcx, this.pcy, this.pR);
    pg.addColorStop(0, '#010404');
    pg.addColorStop(0.78, '#020c0c');
    pg.addColorStop(0.96, '#0a2423');
    pg.addColorStop(1, '#143c3a');
    wc.fillStyle = pg;
    wc.fill(pp);

    // faint surface noise below the rim
    for (i = 0; i < 260; i++) {
      x = (rand() * W) | 0;
      y = (yH[x] + 1 + rand() * 30) | 0;
      if (y < H && y > yH[x]) {
        wc.fillStyle = rand() < 0.5 ? '#0a1c1e' : '#153539';
        wc.fillRect(x, y, 1, 1);
      }
    }

    // atmosphere haze hugging the rim
    wc.strokeStyle = 'rgba(120,220,205,0.35)';
    wc.lineWidth = 4;
    wc.beginPath();
    wc.arc(this.pcx, this.pcy, this.pR + 2.5, 0, Math.PI * 2);
    wc.stroke();

    var wImg = wc.getImageData(0, 0, W, H);
    ditherImageData(wImg, true);
    wc.putImageData(wImg, 0, 0);

    // crisp lit rim on top of the dithered art
    wc.strokeStyle = 'rgba(226,255,248,0.95)';
    wc.lineWidth = 1;
    wc.beginPath();
    wc.arc(this.pcx, this.pcy, this.pR, 0, Math.PI * 2);
    wc.stroke();

    this.planetPath = pp;
    this.overlayCv = wheel;
  };

  // The showpiece comet: sweeps low across the sky in front of the planet,
  // mirrored in its surface, like the big one in the Navigator throbber.
  HeroPainter.prototype.stepPlanetComet = function () {
    if (!this.pComet) {
      if (--this.nextPComet <= 0) {
        var y0 = this.H * (0.3 + Math.random() * 0.12);
        // aim the dive so it reaches the planet's face before exiting
        var slope = Math.min(1.2, Math.max(0.22, (this.H * 0.86 - y0) / (this.W * 0.75)));
        var inv = 1 / Math.sqrt(1 + slope * slope);
        var speed = this.W * 0.055;
        this.pComet = {
          x: this.W * 1.06,
          y: y0,
          vx: -speed * inv,
          vy: speed * slope * inv,
          w: 5,
          trail: speed * 7.5,
          big: true
        };
        this.nextPComet = 160 + Math.random() * 140;
      }
      return;
    }
    var m = this.pComet;
    m.x += m.vx;
    m.y += m.vy;
    if (m.x + m.trail < -6 || m.y - m.trail > this.H + 6) this.pComet = null;
  };

  HeroPainter.prototype.drawPlanetComet = function (f2) {
    var m = this.pComet;
    // gentler flash than the sky meteors: the reflected edge light and
    // surface sheen below should read as the comet's glow, not a flat wash
    drawMeteor(f2, m, { flashR: this.W * 0.2, flashA: 0.26 });

    var spd = Math.sqrt(m.vx * m.vx + m.vy * m.vy);
    var ux = m.vx / spd, uy = m.vy / spd;
    var tx = m.x - ux * m.trail, ty = m.y - uy * m.trail;

    var yhH = this.horizonY(m.x);
    var yhT = this.horizonY(Math.max(0, Math.min(this.W - 1, tx)));
    if (yhH > this.H + 40) return;

    // mirrored, squashed reflection on the planet face
    var ry = yhH + (yhH - m.y) * 0.55;
    var rty = yhT + (yhT - ty) * 0.55;
    f2.save();
    f2.clip(this.planetPath);
    f2.globalAlpha = 0.4;
    var g = f2.createLinearGradient(m.x, ry, tx, rty);
    g.addColorStop(0, 'rgba(255,255,255,0.9)');
    g.addColorStop(0.5, 'rgba(160,235,220,0.5)');
    g.addColorStop(1, 'rgba(40,130,125,0)');
    f2.strokeStyle = g;
    f2.lineWidth = m.w * 0.75;
    f2.lineCap = 'round';
    f2.beginPath();
    f2.moveTo(m.x, ry);
    f2.lineTo(tx, rty);
    f2.stroke();
    f2.globalAlpha = 1;
    f2.restore();

    // the comet's light reflecting off the wheel and planet: surface sheen
    // plus lit edges, faded by distance from the comet's head
    var lc = this.lctx;
    lc.clearRect(0, 0, this.W, this.H);
    // sheen alphas sit just above the alpha-dither threshold so only a
    // sparse speckle survives near the comet instead of a flat wash
    lc.globalAlpha = 0.22;
    lc.drawImage(this.wheelMaskCv, 0, 0);
    lc.globalAlpha = 0.2;
    lc.fillStyle = '#d8fff4';
    lc.fill(this.planetPath);
    lc.globalAlpha = 1;
    lc.drawImage(this.wheelEdgeCv, 0, 0);
    lc.drawImage(this.planetRimCv, 0, 0);
    lc.globalCompositeOperation = 'destination-in';
    var fade = lc.createRadialGradient(m.x, m.y, 0, m.x, m.y, this.W * 0.24);
    fade.addColorStop(0, 'rgba(0,0,0,0.95)');
    fade.addColorStop(0.4, 'rgba(0,0,0,0.45)');
    fade.addColorStop(1, 'rgba(0,0,0,0)');
    lc.fillStyle = fade;
    lc.fillRect(0, 0, this.W, this.H);
    lc.globalCompositeOperation = 'source-over';
    f2.drawImage(this.lightCv, 0, 0);

    // glint where the comet's light kisses the rim
    var prox = 1 - Math.min(1, Math.abs(yhH - m.y) / (this.H * 0.45));
    if (prox > 0.02 && yhH < this.H + 2) {
      var gw = 6 + 30 * prox;
      var gl = f2.createLinearGradient(m.x - gw, 0, m.x + gw, 0);
      gl.addColorStop(0, 'rgba(230,255,250,0)');
      gl.addColorStop(0.5, 'rgba(255,255,255,' + (0.9 * prox).toFixed(2) + ')');
      gl.addColorStop(1, 'rgba(230,255,250,0)');
      f2.strokeStyle = gl;
      f2.lineWidth = 2;
      f2.beginPath();
      f2.moveTo(m.x - gw, yhH);
      f2.lineTo(m.x + gw, yhH);
      f2.stroke();
    }
  };

  HeroPainter.prototype.frame = function () {
    stepSprites(this);
    this.stepPlanetComet();
    renderSprites(this);
  };

  /* ---------------- boot + loop ---------------- */

  function init() {
    var host = document.querySelector('.supporter-hero-retro');
    if (!host) return;
    var sceneCv = host.querySelector('canvas.retro-scene');
    if (!sceneCv) return;

    var heroPainter = new HeroPainter(sceneCv);
    var painters = [heroPainter];

    function sizeScene() {
      var r = host.getBoundingClientRect();
      if (r.width && r.height) heroPainter.resize(r.width, r.height);
    }
    sizeScene();

    var media = window.matchMedia ? window.matchMedia('(prefers-reduced-motion: reduce)') : null;
    var inView = true;
    var rafId = null;
    var last = 0, acc = 0;

    function frameAll() {
      for (var i = 0; i < painters.length; i++) painters[i].frame();
    }

    function tick(now) {
      rafId = requestAnimationFrame(tick);
      var dt = now - last;
      last = now;
      if (dt > 0) acc += Math.min(500, dt);
      if (acc >= STEP_MS) {
        acc = acc % STEP_MS;
        frameAll();
      }
    }

    function running() {
      return inView && !document.hidden && !(media && media.matches);
    }

    function update() {
      if (running() && rafId === null) {
        last = performance.now();
        acc = 0;
        rafId = requestAnimationFrame(tick);
      } else if (!running() && rafId !== null) {
        cancelAnimationFrame(rafId);
        rafId = null;
      }
    }

    if (window.IntersectionObserver) {
      new IntersectionObserver(function (entries) {
        inView = entries[0].isIntersecting;
        update();
      }).observe(host);
    }
    document.addEventListener('visibilitychange', update);
    if (media && media.addEventListener) media.addEventListener('change', update);

    if (window.ResizeObserver) {
      var pending = null;
      new ResizeObserver(function () {
        if (pending) clearTimeout(pending);
        pending = setTimeout(sizeScene, 120);
      }).observe(host);
    } else {
      window.addEventListener('resize', sizeScene);
    }

    // A calm hand-picked frame for reduced-motion users
    if (media && media.matches) {
      heroPainter.meteors.push(spawnMeteor(heroPainter.W, heroPainter.H, false, heroPainter.cfg));
      frameAll();
    }

    update();

    // debug/testing hook
    window.__nsHero = {
      painters: painters,
      advance: function (n) { for (var i = 0; i < (n || 1); i++) frameAll(); }
    };
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
