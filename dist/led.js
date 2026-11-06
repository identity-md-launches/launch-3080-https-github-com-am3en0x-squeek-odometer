// The LED board: a dot-matrix sign drawn on a canvas, fed by app.js with the wheel's live state.
// window.LedBoard.set({ state: 'running' | 'napping' | 'nosignal' | 'loading', km, rpm, block })
;(function () {
  // 5x7 glyphs, one string per row; narrow glyphs use shorter rows
  const G = {
    A: ['01110', '10001', '10001', '11111', '10001', '10001', '10001'],
    B: ['11110', '10001', '10001', '11110', '10001', '10001', '11110'],
    C: ['01110', '10001', '10000', '10000', '10000', '10001', '01110'],
    D: ['11110', '10001', '10001', '10001', '10001', '10001', '11110'],
    E: ['11111', '10000', '10000', '11110', '10000', '10000', '11111'],
    F: ['11111', '10000', '10000', '11110', '10000', '10000', '10000'],
    G: ['01110', '10001', '10000', '10111', '10001', '10001', '01111'],
    H: ['10001', '10001', '10001', '11111', '10001', '10001', '10001'],
    I: ['111', '010', '010', '010', '010', '010', '111'],
    J: ['00111', '00010', '00010', '00010', '00010', '10010', '01100'],
    K: ['10001', '10010', '10100', '11000', '10100', '10010', '10001'],
    L: ['10000', '10000', '10000', '10000', '10000', '10000', '11111'],
    M: ['10001', '11011', '10101', '10101', '10001', '10001', '10001'],
    N: ['10001', '10001', '11001', '10101', '10011', '10001', '10001'],
    O: ['01110', '10001', '10001', '10001', '10001', '10001', '01110'],
    P: ['11110', '10001', '10001', '11110', '10000', '10000', '10000'],
    Q: ['01110', '10001', '10001', '10001', '10101', '10010', '01101'],
    R: ['11110', '10001', '10001', '11110', '10100', '10010', '10001'],
    S: ['01111', '10000', '10000', '01110', '00001', '00001', '11110'],
    T: ['11111', '00100', '00100', '00100', '00100', '00100', '00100'],
    U: ['10001', '10001', '10001', '10001', '10001', '10001', '01110'],
    V: ['10001', '10001', '10001', '10001', '10001', '01010', '00100'],
    W: ['10001', '10001', '10001', '10101', '10101', '10101', '01010'],
    X: ['10001', '10001', '01010', '00100', '01010', '10001', '10001'],
    Y: ['10001', '10001', '10001', '01010', '00100', '00100', '00100'],
    Z: ['11111', '00001', '00010', '00100', '01000', '10000', '11111'],
    0: ['01110', '10001', '10011', '10101', '11001', '10001', '01110'],
    1: ['00100', '01100', '00100', '00100', '00100', '00100', '01110'],
    2: ['01110', '10001', '00001', '00010', '00100', '01000', '11111'],
    3: ['11111', '00010', '00100', '00010', '00001', '10001', '01110'],
    4: ['00010', '00110', '01010', '10010', '11111', '00010', '00010'],
    5: ['11111', '10000', '11110', '00001', '00001', '10001', '01110'],
    6: ['00110', '01000', '10000', '11110', '10001', '10001', '01110'],
    7: ['11111', '00001', '00010', '00100', '01000', '01000', '01000'],
    8: ['01110', '10001', '10001', '01110', '10001', '10001', '01110'],
    9: ['01110', '10001', '10001', '01111', '00001', '00010', '01100'],
    '.': ['0', '0', '0', '0', '0', '0', '1'],
    ',': ['00', '00', '00', '00', '00', '01', '10'],
    ':': ['0', '0', '1', '0', '1', '0', '0'],
    '-': ['000', '000', '000', '111', '000', '000', '000'],
    '/': ['00001', '00010', '00010', '00100', '01000', '01000', '10000'],
    '!': ['1', '1', '1', '1', '1', '0', '1'],
    ' ': ['00', '00', '00', '00', '00', '00', '00'],
  }
  const C = { off: '#131316', orange: '#f6a63b', cream: '#f3e9cc', grey: '#6f6f7b', label: '#5c5c68', blue: '#8fa2ff', green: '#7fe08a', rim: '#8a8a96', dim: '#34343e', red: '#ff5a3c' }
  const textWidth = (s, k) => [...s].reduce((w, ch) => w + ((G[ch] || G[' '])[0].length + 1) * k, -k)

  const canvas = document.getElementById('led')
  if (!canvas) return
  const ctx = canvas.getContext('2d')
  const still = matchMedia('(prefers-reduced-motion: reduce)').matches
  let data = { state: 'loading' }
  let cols = 0, rows = 0, pitch = 0, lit = null, turn = 0, tick = 0, timer = null

  function put(x, y, color) { if (x >= 0 && y >= 0 && x < cols && y < rows) lit[y * cols + x] = color }
  function text(s, x, y, color, k = 1) {
    for (const ch of s) {
      const g = G[ch] || G[' ']
      for (let r = 0; r < 7; r++) for (let c = 0; c < g[r].length; c++) {
        if (g[r][c] !== '1') continue
        for (let i = 0; i < k; i++) for (let j = 0; j < k; j++) put(x + c * k + i, y + r * k + j, color)
      }
      x += (g[0].length + 1) * k
    }
  }
  // a wheel of dots: rim, hub and three spokes that turn with the frame counter
  function wheel(cx, cy, R, turn) {
    for (let a = 0; a < 360; a += 3) {
      const t = (a * Math.PI) / 180
      put(Math.round(cx + R * Math.cos(t)), Math.round(cy + R * Math.sin(t)), C.rim)
    }
    for (let a = 0; a < 360; a += 30) {
      const t = ((a + turn * 10) * Math.PI) / 180
      put(Math.round(cx + (R - 2) * Math.cos(t)), Math.round(cy + (R - 2) * Math.sin(t)), C.grey)
    }
    for (let s = 0; s < 3; s++) {
      const t = ((s * 120 + turn * 10) * Math.PI) / 180
      for (let d = 2; d < R - 2; d++) put(Math.round(cx + d * Math.cos(t)), Math.round(cy + d * Math.sin(t)), C.grey)
    }
    for (let i = -1; i <= 1; i++) for (let j = -1; j <= 1; j++) put(cx + i, cy + j, C.orange)
  }

  // The sign, top to bottom: his state, then two odometers (the whole wheel and yours), then the raw numbers.
  // Each row has a height in dots, a gap after it, a width and a painter.
  const PAD = 2
  function layout() {
    const s = data.state
    const st = 'SQUEEKTOSHI ' + (s === 'running' ? 'IS RUNNING' : s === 'napping' ? 'IS NAPPING' : s === 'nosignal' ? 'IS OFF AIR' : 'TUNING IN')
    const stColor = s === 'running' ? C.green : s === 'napping' ? C.blue : C.cream
    const out = []
    const row = (h, gap, paint, w) => out.push({ h, gap, paint, w })
    // leave room on the right for the wheel on wide boards
    const avail = cols - 2 * PAD - (cols >= 150 ? 44 : 0)

    if (textWidth(st, 1) <= avail) row(7, 5, (y) => text(st, PAD, y, stColor), textWidth(st, 1))
    else {
      row(7, 2, (y) => text('SQUEEKTOSHI', PAD, y, stColor), textWidth('SQUEEKTOSHI', 1))
      row(7, 5, (y) => text(st.slice(12), PAD, y, stColor), textWidth(st.slice(12), 1))
    }

    // both odometers share one size and one number of drums so their digits line up
    const meters = [['WHEEL', data.km], ['YOURS', data.mine]]
    const ints = meters.map(([, v]) => (v != null ? String(Math.floor(v)) : ''))
    const need = Math.max(2, ...ints.map((i) => i.length))
    const labelW = textWidth('WHEEL', 1) + 5
    const unitW = 3 + textWidth('KM', 1)
    let pick = null
    for (const k of [3, 2, 1]) {
      for (const inline of [true, false]) {
        for (let drums = Math.max(4, need); drums >= need && !pick; drums--) {
          const w = (inline ? labelW : 0) + textWidth('0'.repeat(drums) + '.00', k) + 2 + unitW
          if (w <= avail) pick = { k, inline, drums, w }
        }
        if (pick) break
      }
      if (pick) break
    }
    if (!pick) pick = { k: 1, inline: false, drums: need, w: textWidth('0'.repeat(need) + '.00', 1) + unitW }
    const { k, inline, drums } = pick
    meters.forEach(([label, v], i) => {
      const last = i === meters.length - 1
      if (!inline) row(7, 2, (y) => text(label, PAD, y, C.label), textWidth(label, 1))
      row(7 * k, last ? 6 : 5, (y) => {
        if (inline) text(label, PAD, y + 7 * k - 7, C.label)
        odometer(PAD + (inline ? labelW : 0), y, v, drums, k)
      }, pick.w)
    })

    const rpm = (data.rpm != null ? Math.round(data.rpm) : '--') + ' RPM'
    const bh = data.block != null ? data.block.toLocaleString('en-US') : '--'
    const block = (textWidth('SQUEEK BLOCK ' + bh, 1) <= avail ? 'SQUEEK BLOCK ' : 'BLOCK ') + bh
    if (textWidth(rpm + '   ' + block, 1) <= avail) {
      row(7, 0, (y) => { text(rpm, PAD, y, C.label); text(block, PAD + textWidth(rpm + '   ', 1) + 1, y, C.label) }, textWidth(rpm + '   ' + block, 1))
    } else {
      row(7, 2, (y) => text(rpm, PAD, y, C.label), textWidth(rpm, 1))
      row(7, 0, (y) => text(block, PAD, y, C.label), textWidth(block, 1))
    }
    return out
  }

  // One odometer readout: unlit-looking leading drums, the whole kilometres in cream and the hundredths in red, like
  // the last drum of a mechanical odometer. No value yet: dim dashes.
  function odometer(x, y, v, drums, k) {
    const adv = (ch) => ((G[ch] || G[' '])[0].length + 1) * k
    if (v == null) {
      // one dash per drum, centred where its digit will be, so the empty readout lines up with the full one
      const dash = (n) => { for (let i = 0; i < n; i++) { text('-', x + k, y, C.dim, k); x += adv('0') } }
      dash(drums)
      text('.', x, y, C.dim, k); x += adv('.')
      dash(2)
      text('KM', x + 2, y + 7 * k - 7, C.label)
      return
    }
    const [int, frac] = v.toFixed(2).split('.')
    const lead = drums - int.length
    const whole = int.padStart(drums, '0')
    ;[...whole].forEach((ch, i) => { text(ch, x, y, i < lead ? C.dim : C.cream, k); x += adv(ch) })
    text('.', x, y, C.cream, k); x += adv('.')
    const w = textWidth(frac, k)
    text(frac, x, y, C.red, k)
    x += w + k
    text('KM', x + 2, y + 7 * k - 7, C.label)
  }

  const height = (rs) => rs.reduce((h, r) => h + r.h + r.gap, 2 * PAD)

  function compose(rs) {
    lit = new Array(cols * rows).fill(null)
    let y = PAD, left = 0
    for (const r of rs) {
      r.paint(y)
      left = Math.max(left, r.w)
      y += r.h + r.gap
    }
    // the wheel fills the free space on the right, as tall as the board; it stands still while he naps
    const free = cols - left - PAD - 6
    const rad = Math.min(Math.floor((rows - 4) / 2), Math.floor((free - 4) / 2))
    if (rad >= 10) {
      wheel(cols - rad - 4, Math.floor(rows / 2), rad, turn)
      if (data.state === 'napping' && tick % 2 === 0) text('Z', cols - 8, 1, C.blue)
    }
  }

  function draw() {
    const dpr = window.devicePixelRatio || 1
    const w = canvas.clientWidth
    if (!w) return
    cols = Math.max(48, Math.floor(w / (w >= 900 ? 6 : w >= 520 ? 5 : 4.4)))
    pitch = w / cols
    const rs = layout()
    rows = height(rs)
    const h = rows * pitch
    canvas.style.height = h + 'px'
    if (canvas.width !== Math.round(w * dpr) || canvas.height !== Math.round(h * dpr)) {
      canvas.width = Math.round(w * dpr)
      canvas.height = Math.round(h * dpr)
    }
    compose(rs)
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    ctx.clearRect(0, 0, w, h)
    const rad = pitch * 0.36
    for (let y = 0; y < rows; y++) for (let x = 0; x < cols; x++) {
      ctx.fillStyle = lit[y * cols + x] || C.off
      ctx.beginPath()
      ctx.arc((x + 0.5) * pitch, (y + 0.5) * pitch, rad, 0, 6.2832)
      ctx.fill()
    }
  }

  // the wheel steps faster as he runs: one step every 300 ms at a crawl, 60 ms at full tilt; asleep, only the Z blinks
  function loop() {
    clearTimeout(timer)
    if (still || (data.state !== 'running' && data.state !== 'napping')) return
    const running = data.state === 'running'
    const ms = running ? Math.max(60, 300 - (data.rpm || 0) * 3) : 900
    timer = setTimeout(() => { if (running) turn++; tick++; draw(); loop() }, ms)
  }

  function label() {
    const s = data.state
    const words = s === 'running' ? 'is running' : s === 'napping' ? 'is napping' : s === 'nosignal' ? 'cannot be reached' : 'is loading'
    const km = data.km != null ? `, the wheel has run ${data.km.toFixed(2)} km` : ''
    const mine = data.mine != null ? `, yours ${data.mine.toFixed(2)} km` : ''
    canvas.setAttribute('aria-label', `LED board: Squeektoshi ${words}${km}${mine}.`)
  }

  window.LedBoard = {
    set(next) { data = { ...data, ...next }; label(); draw(); loop() },
  }
  new ResizeObserver(() => draw()).observe(canvas)
  label()
  draw()
})()
