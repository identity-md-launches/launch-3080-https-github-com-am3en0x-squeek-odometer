// Squeek Odometer site: plain JSON-RPC, no libraries. Reads go to a public Sepolia RPC so the page works without a
// wallet; only the mint goes through the wallet.
const CFG = window.ODOMETER_CONFIG
const SEL = { mint: '0x1249c58b', idOf: '0xd94fe832', tokenURI: '0xc87b56dd', totalMinted: '0xa2309ff8', refresh: '0x9c75dd35' }
const MINTED = '0xc9d0543a84d3510329c0783b91576878ceb484e8699944cb5610c3436b3b8e39' // Minted(uint256,address,uint256)
const CHAIN_HEX = '0x' + CFG.chainId.toString(16)
const $ = (id) => document.getElementById(id)
let account = null
let mineId = 0
const short = (a) => a.slice(0, 6) + '\u2026' + a.slice(-4)

// ---------------------------------------------------------------- JSON-RPC and ABI helpers
let rpcId = 0
async function rpc(method, params = []) {
  const r = await fetch(CFG.rpc, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', id: ++rpcId, method, params }) })
  const j = await r.json()
  if (j.error) throw new Error(j.error.message)
  return j.result
}
const word = (n) => BigInt(n).toString(16).padStart(64, '0')
const call = (data) => rpc('eth_call', [{ to: CFG.address, data }, 'latest'])
function decodeString(hex) {
  const h = hex.slice(2)
  const off = Number(BigInt('0x' + h.slice(0, 64))) * 2
  const len = Number(BigInt('0x' + h.slice(off, off + 64)))
  const bytes = new Uint8Array(len)
  for (let i = 0; i < len; i++) bytes[i] = parseInt(h.substr(off + 64 + i * 2, 2), 16)
  return new TextDecoder().decode(bytes)
}
async function token(id) {
  const uri = decodeString(await call(SEL.tokenURI + word(id)))
  return JSON.parse(atob(uri.slice(uri.indexOf(',') + 1)))
}
const trait = (meta, name) => (meta.attributes.find((a) => a.trait_type === name) || {}).value
const km = (meta) => Number(trait(meta, 'Distance (km)')).toFixed(2)

// ---------------------------------------------------------------- the page
function say(text, kind = '') { const m = $('msg'); m.textContent = text; m.className = 'msg ' + kind }

async function showSupply() {
  if (!CFG.address) return
  try { $('supply').textContent = Number(BigInt(await call(SEL.totalMinted))).toLocaleString('en-US') + ' / 9,999' } catch {}
}

async function showMine() {
  if (!account || !CFG.address) return
  const id = Number(BigInt(await call(SEL.idOf + word(account))))
  mineId = id
  if (!id) { $('mint').disabled = false; $('mine-caption').textContent = 'Yours shows up here after you mint.'; return }
  const meta = await token(id)
  window.LedBoard?.set({ mine: Number(trait(meta, 'Distance (km)')) })
  $('mine').closest('figure').classList.add('minted')
  $('mine').src = meta.image
  $('mine').alt = `Your odometer, #${id}`
  $('mine-caption').textContent = `#${id} \u00b7 ${km(meta)} km since your mint \u00b7 ${trait(meta, 'Stage')} \u00b7 ${trait(meta, 'Status')}`
  $('mint').disabled = true
  $('mint').textContent = 'Minted'
  $('refresh').hidden = false
}

async function showRecent() {
  const box = $('recent')
  if (!CFG.address) { box.innerHTML = '<p class="fine">The contract is not deployed yet.</p>'; return }
  try {
    const head = Number(BigInt(await rpc('eth_blockNumber')))
    const logs = []
    // public RPCs cap a log search, so walk back in 50,000-block steps until there are enough mints
    for (let to = head; to >= CFG.fromBlock && logs.length < 8; to -= 50_000) {
      const from = Math.max(CFG.fromBlock, to - 49_999)
      const part = await rpc('eth_getLogs', [{ address: CFG.address, topics: [MINTED], fromBlock: '0x' + from.toString(16), toBlock: '0x' + to.toString(16) }])
      logs.unshift(...part)
    }
    const ids = logs.map((l) => Number(BigInt(l.topics[1]))).reverse().slice(0, 8)
    if (!ids.length) { box.innerHTML = '<p class="fine">No odometers yet. Be the first.</p>'; return }
    box.innerHTML = ''
    for (const id of ids) {
      const meta = await token(id)
      const card = document.createElement('figure')
      card.className = 'card'
      const img = document.createElement('img')
      img.src = meta.image; img.alt = meta.name; img.width = 160; img.height = 160; img.loading = 'lazy'
      const cap = document.createElement('figcaption')
      const b = document.createElement('b')
      b.textContent = `#${id}`
      cap.append(b, ` \u00b7 ${km(meta)} km \u00b7 ${trait(meta, 'Status')}`)
      card.append(img, cap)
      box.append(card)
    }
  } catch (e) {
    box.innerHTML = '<p class="fine">Could not read the latest mints right now. Reload in a minute.</p>'
  }
}

// The wheel's live state from Squeekchain's API: the LED board and the numbers beside it.
async function showLive() {
  const led = window.LedBoard
  try {
    const st = await (await fetch(CFG.api + '/v1/status')).json()
    const m = st.measurement || {}
    const online = m.freshness === 'online'
    const rpm = (m.rpmMilli || 0) / 1000
    const work = m.cumulativeWorkUnits != null ? Number(m.cumulativeWorkUnits) : null
    const block = ((st.builder || {}).anchor || {}).blockHeight
    const state = !online ? 'nosignal' : rpm > 0 ? 'running' : 'napping'
    const kmRun = work != null ? (work * 887) / 1e6 : null
    const doing = state === 'running' ? `is running at ${rpm.toFixed(0)} rpm` : state === 'napping' ? 'is napping' : 'is off the air'
    const turns = work != null ? ` The wheel has turned ${work.toLocaleString('en-US')} times on this core, ${kmRun.toFixed(2)} km` : ''
    const at = block != null ? ` by Squeek block ${Number(block).toLocaleString('en-US')}.` : turns ? '.' : ''
    $('live-line').textContent = `Right now Squeektoshi ${doing}.${turns}${at}`
    led?.set({ state, km: kmRun, rpm: online ? rpm : null, block: block != null ? Number(block) : null })
  } catch {
    $('live-line').textContent = 'The wheel cannot be read right now.'
    led?.set({ state: 'nosignal' })
  }
}

// ---------------------------------------------------------------- wallet
async function connect() {
  if (!window.ethereum) { say('No wallet found. Install MetaMask or another browser wallet.', 'bad'); return }
  try {
    const [a] = await window.ethereum.request({ method: 'eth_requestAccounts' })
    account = a.toLowerCase()
    $('connect-label').textContent = short(a)
    $('connect').classList.add('on')
    await switchChain()
    await showMine()
    if (!$('mint').disabled) say('')
  } catch (e) { say(e.message || 'The wallet refused.', 'bad') }
}

async function switchChain() {
  const id = await window.ethereum.request({ method: 'eth_chainId' })
  if (id === CHAIN_HEX) return
  await window.ethereum.request({ method: 'wallet_switchEthereumChain', params: [{ chainId: CHAIN_HEX }] })
}

async function mint() {
  if (!account) return connect()
  $('mint').disabled = true
  $('mint').setAttribute('aria-busy', 'true')
  try {
    await switchChain()
    say('Confirm the mint in your wallet. It is free; you pay only Sepolia gas.')
    const hash = await window.ethereum.request({ method: 'eth_sendTransaction', params: [{ from: account, to: CFG.address, data: SEL.mint }] })
    say('Minting\u2026 waiting for Sepolia to include it.')
    const receipt = await waitFor(hash)
    if (!receipt || receipt.status !== '0x1') throw new Error('The mint did not go through. If you already minted, each wallet gets one.')
    say('Minted. Your odometer starts counting now.', 'good')
    await Promise.all([showMine(), showSupply(), showRecent()])
  } catch (e) {
    say(e.message || 'The mint did not go through.', 'bad')
    $('mint').disabled = false
  } finally {
    $('mint').removeAttribute('aria-busy')
  }
}

async function waitFor(hash) {
  for (let i = 0; i < 90; i++) {
    const receipt = await rpc('eth_getTransactionReceipt', [hash])
    if (receipt) return receipt
    await new Promise((r) => setTimeout(r, 2000))
  }
  return null
}

// refresh(id) only emits ERC-4906 MetadataUpdate, so marketplaces fetch the art again. Anyone may call it.
async function redraw() {
  if (!account || !mineId) return
  const btn = $('refresh')
  btn.disabled = true
  btn.setAttribute('aria-busy', 'true')
  try {
    await switchChain()
    say('Confirm in your wallet. It only asks marketplaces to redraw your odometer.')
    const hash = await window.ethereum.request({ method: 'eth_sendTransaction', params: [{ from: account, to: CFG.address, data: SEL.refresh + word(mineId) }] })
    const receipt = await waitFor(hash)
    if (!receipt || receipt.status !== '0x1') throw new Error('The refresh did not go through.')
    say('Done. Marketplaces will redraw it on their next fetch.', 'good')
  } catch (e) {
    say(e.message || 'The refresh did not go through.', 'bad')
  } finally {
    btn.disabled = false
    btn.removeAttribute('aria-busy')
  }
}

// An IMD-hosted build ships dist/imd-deployment.json with the live addresses: use it when config.js has none.
async function fromImdDeployment() {
  try {
    const j = await (await fetch('imd-deployment.json')).json()
    let found = null
    const walk = (o, name) => {
      if (found || !o || typeof o !== 'object') return
      const label = String(o.contract ?? o.name ?? name ?? '')
      const addr = o.address ?? o.contractAddress ?? (typeof o === 'object' && /^0x[0-9a-fA-F]{40}$/.test(o[name]) ? o[name] : null)
      if (/SqueekOdometer/.test(label) && /^0x[0-9a-fA-F]{40}$/.test(addr ?? '')) {
        found = { address: addr, block: Number(o.blockNumber ?? o.block ?? 0) }
        return
      }
      for (const [k, v] of Object.entries(o)) {
        if (typeof v === 'string' && /SqueekOdometer/.test(k) && /^0x[0-9a-fA-F]{40}$/.test(v)) { found = { address: v, block: 0 }; return }
        walk(v, k)
      }
    }
    walk(j)
    if (found) { CFG.address = found.address; if (found.block) CFG.fromBlock = found.block }
  } catch {}
}

async function init() {
  if (!CFG.address) await fromImdDeployment()
  $('connect').onclick = connect
  $('mint').onclick = mint
  $('refresh').onclick = redraw
  if (CFG.address) {
    $('mint').disabled = false
    const link = $('contract-link')
    link.href = CFG.explorer + '/address/' + CFG.address
    link.textContent = short(CFG.address)
  } else {
    $('contract-link').removeAttribute('target')
    $('mint').textContent = 'Mint opens at deploy'
    say('The contract is not deployed yet.')
  }
  if (CFG.repo) for (const id of ['repo-link', 'repo-link-2']) $(id).href = CFG.repo
  showSupply(); showRecent(); showLive()
  setInterval(showLive, 30_000)
  if (window.ethereum) window.ethereum.on?.('accountsChanged', () => location.reload())
}
init()
