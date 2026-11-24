-- Pruebas del motor e interfaz de MarcosJV.lua en PC (Lua 5.1 con mocks del API Nspire)
local SRC = ...
platform = {window = {invalidate = function() end, width = function() return 318 end, height = function() return 212 end}}
on = {}
toolpalette = {register = function(t) TP = t end}

local calls = 0
local function num(v, name)
  if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
    error("argumento no numerico en " .. name .. ": " .. tostring(v), 3)
  end
end
local gc = {}
function gc:setFont(f, s, z) assert(type(f) == "string" and type(s) == "string"); num(z, "setFont") end
function gc:setColorRGB(r, g, b) num(r, "rgb"); num(g, "rgb"); num(b, "rgb"); assert(r >= 0 and r <= 255 and g >= 0 and g <= 255 and b >= 0 and b <= 255, "color fuera de rango") end
function gc:drawString(s, x, y, a) assert(type(s) == "string", "drawString texto"); num(x, "drawString x"); num(y, "drawString y"); calls = calls + 1 end
function gc:getStringWidth(s) assert(type(s) == "string"); return #s * 5 end
function gc:getStringHeight(s) return 10 end
function gc:drawLine(a, b, c, d) num(a, "line"); num(b, "line"); num(c, "line"); num(d, "line"); calls = calls + 1 end
function gc:drawRect(a, b, c, d) num(a, "rect"); num(b, "rect"); num(c, "rect"); num(d, "rect") end
function gc:fillRect(a, b, c, d) num(a, "frect"); num(b, "frect"); num(c, "frect"); num(d, "frect") end
function gc:drawArc(a, b, c, d, e, f) for _, v in ipairs({a, b, c, d, e, f}) do num(v, "arc") end end
function gc:fillArc(a, b, c, d, e, f) for _, v in ipairs({a, b, c, d, e, f}) do num(v, "farc") end end
function gc:drawPolyLine(t) assert(#t >= 4 and #t % 2 == 0, "polyline"); for _, v in ipairs(t) do num(v, "poly") end end
function gc:fillPolygon(t) assert(#t >= 6, "polygon"); for _, v in ipairs(t) do num(v, "fpoly") end end
function gc:setPen(a, b) assert(type(a) == "string") end

dofile(SRC)
local A = MARCOS2D
local nfail, nok = 0, 0
local function near(a, b, tol, msg)
  tol = tol or 1e-6
  local ok = math.abs(a - b) <= tol * math.max(1, math.abs(b))
  if ok then nok = nok + 1 else nfail = nfail + 1; print("FALLA: " .. msg .. "  obtenido=" .. tostring(a) .. "  esperado=" .. tostring(b)) end
end
local function yes(c, msg) if c then nok = nok + 1 else nfail = nfail + 1; print("FALLA: " .. msg) end end

local function nd(x, y, s) return {x = x, y = y, sup = s or 1, sx = 0, sy = 0, sr = 0, kx = 0, ky = 0, kr = 0} end
local function base() return {fu = 1, lu = 1, ax = 1, ms = 1, nodes = {}, secs = {{E = 2e8, A = 0.01, I = 1e-4}}, elems = {}, nl = {}, el = {}} end
local function el(i, j, hi, hj) return {i = i, j = j, s = 1, hi = hi or 1, hj = hj or 1} end
local function run(m) A.setModel(m); local r, e = A.solve(); return r, e end
local function at(R, k, x) local X = R.EL[k]; local Lf, Rt = A.query(X.ctx, X.S0, x); return Lf, Rt end
local EI = 2e8 * 1e-4

-- 1) Viga simplemente apoyada, carga uniforme
do
  local R = run(A.examples[1][2]())
  near(R.RX[1][2], 30, 1e-9, "Ej1 Ry1"); near(R.RX[2][2], 30, 1e-9, "Ej1 Ry2")
  near(R.gx[3].mx.v, 45, 1e-9, "Ej1 Mmax"); near(R.gx[3].mx.x, 3, 1e-5, "Ej1 x Mmax")
  near(R.gx[5].mn.v, -5 * 10 * 6 ^ 4 / (384 * EI), 1e-7, "Ej1 flecha max")
  near(R.d[3], -10 * 6 ^ 3 / (24 * EI), 1e-7, "Ej1 giro apoyo")
  yes(R.GI == 0, "Ej1 isostatica")
  local Lf = at(R, 1, 1.5); near(Lf[2], 15, 1e-9, "Ej1 V(1.5)"); near(Lf[3], 30 * 1.5 - 5 * 1.5 ^ 2, 1e-9, "Ej1 M(1.5)")
end

-- 2) Biempotrada uniforme
do
  local m = base(); m.nodes = {nd(0, 0, 2), nd(6, 0, 2)}; m.elems = {el(1, 2)}
  m.el = {{e = 1, t = 1, d = 1, v1 = -10, v2 = -10, a = 0, b = 0}}
  local R = run(m)
  near(R.RX[1][3], 30, 1e-9, "Biemp M1 reaccion"); near(R.RX[2][3], -30, 1e-9, "Biemp M2 reaccion")
  near(R.gx[3].mn.v, -30, 1e-9, "Biemp Mmin"); near(R.gx[3].mx.v, 15, 1e-9, "Biemp Mcentro")
  near(R.gx[5].mn.v, -10 * 6 ^ 4 / (384 * EI), 1e-7, "Biemp flecha")
  yes(R.GI == 3, "Biemp GI=3 (con axial)")
end

-- 3) Apoyada-empotrada con carga puntual al centro
do
  local m = base(); m.nodes = {nd(0, 0, 2), nd(8, 0, 4)}; m.elems = {el(1, 2)}
  m.el = {{e = 1, t = 2, d = 1, v1 = -16, v2 = 0, a = 4, b = 0}}
  local R = run(m)
  near(R.RX[1][3], 3 * 16 * 8 / 16, 1e-9, "Propped M empotr."); near(R.RX[2][2], 5 * 16 / 16, 1e-9, "Propped R rodillo")
  local Lf, Rt = at(R, 1, 4); near(Lf[2] - Rt[2], 16, 1e-9, "salto de V en carga")
  yes(R.GI == 1, "Propped GI=1")
end

-- 4) Viga Gerber
do
  local R = run(A.examples[4][2]())
  near(R.RX[1][2], 50, 1e-9, "Gerber Ry1"); near(R.RX[1][3], 120, 1e-9, "Gerber M1"); near(R.RX[3][2], 10, 1e-9, "Gerber R3")
  yes(R.GI == 0, "Gerber isostatica")
  local Lf = at(R, 1, 4); near(Lf[3], 0, 1e-9, "Gerber M en rotula")
  near(R.gx[3].mx.v, 20, 1e-9, "Gerber Mmax tramo 2")
end

-- 5) Marco del ejemplo 2: equilibrio global y comparacion con solucion independiente
do
  local R = run(A.examples[2][2]())
  local sx, sy, sm = 20, -90, -80 - 270
  for k, r in pairs(R.RX) do local p = A.getModel().nodes[k]; sx = sx + r[1]; sy = sy + r[2]; sm = sm + r[3] + p.x * r[2] - p.y * r[1] end
  near(sx, 0, 1e-8, "Marco ΣFx"); near(sy, 0, 1e-8, "Marco ΣFy"); near(sm, 0, 1e-8, "Marco ΣM")
  yes(R.GI == 3, "Marco GI=3")
  PORTAL = {R.d[4], R.d[5], R.d[6], R.d[7], R.d[8], R.d[9], R.RX[1][1], R.RX[1][2], R.RX[1][3], R.RX[4][3]}
  -- consistencia: v(L) del integrador = desplazamiento nodal
  for k, X in ipairs(R.EL) do
    local Lf = at(R, k, X.ctx.L)
    near(Lf[5], X.dl[5], 1e-6, "compatibilidad v(L) E" .. k); near(Lf[4], X.dl[6], 1e-6, "compatibilidad θ(L) E" .. k)
    near(Lf[6], X.dl[4], 1e-6, "compatibilidad u(L) E" .. k)
  end
end

-- 6) Armadura de 2 barras (rotulas en ambos extremos)
do
  local m = base(); m.nodes = {nd(0, 0, 3), nd(4, 0, 3), nd(2, 2, 1)}
  m.elems = {el(1, 3, 2, 2), el(2, 3, 2, 2)}
  m.nl = {{n = 3, fx = 0, fy = -10, m = 0}}
  local R, e = run(m)
  yes(R ~= nil, "Armadura resuelve " .. tostring(e))
  if R then
    near(R.EL[1].S0[1], -10 / (2 * math.sin(math.pi / 4)), 1e-9, "Armadura N1")
    near(R.gx[3].mx.v, 0, 1e-6, "Armadura M=0")
    yes(R.GI == 0, "Armadura isostatica GI=" .. R.GI)
  end
end

-- 7) Asentamiento en biempotrada
do
  local m = base(); m.nodes = {nd(0, 0, 2), nd(6, 0, 2)}; m.elems = {el(1, 2)}
  m.nodes[2].sy = -0.01
  local R = run(m)
  near(math.abs(R.RX[1][3]), 6 * EI * 0.01 / 36, 1e-9, "Asentamiento M")
  near(math.abs(R.RX[1][2]), 12 * EI * 0.01 / 216, 1e-9, "Asentamiento V")
end

-- 8) Resorte
do
  local m = base(); m.nodes = {nd(0, 0, 3), nd(4, 0, 1)}; m.elems = {el(1, 2)}
  m.nodes[2].ky = 1000
  m.nl = {{n = 2, fx = 0, fy = -10, m = 0}}
  local R = run(m)
  -- articulado + resorte: no hay momento en el empotramiento (es articulado) -> resorte toma 10
  near(R.RX[2][2], 10, 1e-9, "Resorte reaccion"); near(R.d[5], -0.01, 1e-9, "Resorte desplazamiento")
end

-- 9) Mecanismo
do
  local m = base(); m.nodes = {nd(0, 0, 4), nd(5, 0, 4)}; m.elems = {el(1, 2)}
  local R, e = run(m)
  yes(R == nil and e:find("INESTABLE"), "Detecta mecanismo")
end

-- 10) Carga triangular
do
  local m = base(); m.nodes = {nd(0, 0, 3), nd(9, 0, 4)}; m.elems = {el(1, 2)}
  m.el = {{e = 1, t = 1, d = 1, v1 = 0, v2 = -12, a = 0, b = 0}}
  local R = run(m)
  near(R.RX[1][2], 12 * 9 / 6, 1e-9, "Triangular Ra"); near(R.RX[2][2], 12 * 9 / 3, 1e-9, "Triangular Rb")
  near(R.gx[3].mx.v, 12 * 81 / (9 * math.sqrt(3)), 1e-8, "Triangular Mmax")
  near(R.gx[3].mx.x, 9 / math.sqrt(3), 1e-5, "Triangular x Mmax")
end

-- 11) Viga inclinada con carga proyectada = viga horizontal en momentos
do
  local m = base(); m.nodes = {nd(0, 0, 3), nd(6, 3, 4)}; m.elems = {el(1, 2)}
  m.el = {{e = 1, t = 1, d = 5, v1 = -10, v2 = -10, a = 0, b = 0}}
  local R = run(m)
  near(R.RX[1][2] + R.RX[2][2], 60, 1e-9, "Inclinada ΣRy"); near(R.gx[3].mx.v, 45, 1e-8, "Inclinada Mmax")
end

-- 12) Carga parcial y momento en el tramo
do
  local m = base(); m.nodes = {nd(0, 0, 3), nd(10, 0, 4)}; m.elems = {el(1, 2)}
  m.el = {{e = 1, t = 1, d = 1, v1 = -5, v2 = -5, a = 2, b = 6}, {e = 1, t = 3, d = 1, v1 = 20, a = 8}}
  local R = run(m)
  -- Rb*10 = 20*4 - 20 -> Rb = 6 ; Ra = 14  (momento antihorario +20)
  near(R.RX[2][2], (20 * 4 - 20) / 10, 1e-9, "Parcial Rb"); near(R.RX[1][2], 20 - 6, 1e-9, "Parcial Ra")
  local Lf, Rt = at(R, 1, 8); near(Lf[3] - Rt[3], 20, 1e-9, "Salto de M por momento aplicado")
end

-- 13) Serializacion y conversion de unidades
do
  A.setModel(A.examples[3][2]())
  local s = A.ser(A.getModel())
  local m2 = A.deser(s)
  local R1 = run(A.examples[3][2]())
  local R2 = run(m2)
  near(R2.gx[3].mn.v, R1.gx[3].mn.v, 1e-12, "Serializacion")
  yes(R1.GI == 1, "Continua GI=1")
end

-- 14) Interfaz: recorrer pantallas y teclas
do
  A.setModel(A.examples[2][2]())
  local function paint() on.paint(gc); local m = A.msg(); if m and m.text:find("Error") then error(m.text) end end
  local function top() local s = A.stack(); return s[#s] end
  local function save() local f = top(); for _ = 1, 15 do if top() ~= f then return end; A.key("kEnter") end end
  paint()
  for _ = 1, 25 do A.key("arrow", "down"); paint() end
  A.push(A.Canvas(1)); paint()
  for _ = 1, 9 do A.key("tab"); paint() end
  A.key("char", "v"); paint(); A.key("char", "v"); paint(); A.key("char", "+"); paint(); A.key("arrow", "left"); paint()
  A.key("kEnter"); paint()
  for _ = 1, 7 do A.key("tab"); paint(); A.key("arrow", "right"); paint(); A.key("arrow", "up"); paint() end
  A.key("kEnter"); paint(); A.key("char", "2"); A.key("char", "."); A.key("char", "5"); paint(); A.key("kEnter"); paint()
  A.key("kEsc"); paint()
  A.key("char", "e"); paint()
  for _ = 1, 30 do A.key("arrow", "down"); paint() end
  A.key("arrow", "right"); paint(); A.key("arrow", "right"); paint(); A.key("kEnter"); paint()
  A.key("kEsc"); A.key("kEsc"); A.key("kEsc"); paint()
  A.push(A.Summary()); paint(); for _ = 1, 20 do A.key("arrow", "down"); paint() end
  A.key("kEnter"); paint(); A.key("kEsc"); A.key("kEsc")
  A.push(A.About()); paint(); A.key("kEsc")
  for _, k in ipairs({"reac", "disp", "ends", "max"}) do A.push(A.Table(k)); paint(); A.key("arrow", "down"); paint(); A.key("kEsc") end
  for _, k in ipairs({"nodes", "secs", "elems", "nl", "el"}) do
    A.push(A.List(k)); paint()
    local n0 = #({nodes = A.getModel().nodes, secs = A.getModel().secs, elems = A.getModel().elems, nl = A.getModel().nl, el = A.getModel().el})[k]
    A.key("char", "+"); paint()
    A.key("char", "−"); A.key("char", "3"); A.key("back"); A.key("char", "1"); A.key("char", "ᴇ"); A.key("char", "2"); paint()
    A.key("arrow", "down"); paint(); A.key("arrow", "right"); paint(); A.key("arrow", "down"); paint()
    save(); paint()
    if top().msg then print("  aviso en " .. k .. ": " .. top().msg); A.key("kEsc") end
    if A.msg() then A.key("kEsc") end
    A.key("kEsc"); paint()
  end
  A.push(A.UnitsForm()); paint(); A.key("arrow", "right"); A.key("arrow", "down"); A.key("arrow", "right"); paint(); save(); paint()
  yes(A.getModel().fu == 2 and A.getModel().lu == 2, "Cambio de unidades")
  A.push(A.ExamplesMenu()); paint(); A.key("arrow", "down"); A.key("kEnter"); paint(); A.key("kEnter"); paint()
  yes(A.getModel().fu == 1 and #A.getModel().nodes == 2, "Carga ejemplo 1")
  local R = A.solve()
  near(R.gx[3].mx.v, 45, 1e-9, "Ejemplo 1 desde la interfaz")
  A.push(A.UnitsForm()); A.key("arrow", "left"); A.key("arrow", "left"); A.key("arrow", "down"); A.key("arrow", "left"); A.key("arrow", "left"); save()
  yes(A.getModel().fu == 5 and A.getModel().lu == 4, "unidades lbf ft")
  R = A.solve()
  near(R.gx[3].mx.v, 45000 / 4.4482216152605 / 0.3048, 1e-9, "Mmax en lbf·ft")
  for i, ex in ipairs(A.examples) do
    A.setModel(ex[2]()); A.ensure()
    local c = A.Canvas(1); A.push(c)
    for _ = 1, 8 do paint(); A.key("tab") end
    A.key("kEsc")
    A.push(A.EqView(1)); for _ = 1, 6 do paint(); A.key("arrow", "right") end; A.key("kEsc")
    yes(A.res() ~= nil, "ejemplo " .. i .. " resuelto")
  end
  local st = on.save(); on.restore(st); paint()
  print("llamadas de dibujo: " .. calls)
end

-- 15) Ecuaciones por tramo = valores del integrador
do
  local cases = {}
  for _, ex in ipairs(A.examples) do cases[#cases + 1] = ex[2]() end
  local m = base(); m.nodes = {nd(0, 0, 3), nd(10, 0, 4)}; m.elems = {el(1, 2)}
  m.el = {{e = 1, t = 1, d = 1, v1 = -5, v2 = -9, a = 2, b = 6}, {e = 1, t = 3, d = 1, v1 = 20, a = 8}, {e = 1, t = 2, d = 4, v1 = 7, a = 5}}
  cases[#cases + 1] = m
  local worst = 0
  local ntr = 0
  for _, mm in ipairs(cases) do
    local R = run(mm)
    for k, X in ipairs(R.EL) do
      for _, t in ipairs(A.tramos(X)) do
        ntr = ntr + 1
        for s = 0, 4 do
          local x = t.xa + (t.xb - t.xa) * (0.05 + 0.9 * s / 4)
          local Lf = A.query(X.ctx, X.S0, x)
          local EI = X.ctx.EI
          local pairs_ = {{A.polyEval(t.N, x), Lf[1], R.qmax[1]}, {A.polyEval(t.V, x), Lf[2], R.qmax[2]},
                          {A.polyEval(t.M, x), Lf[3], R.qmax[3]}, {A.polyEval(t.EIt, x) / EI, Lf[4], R.qmax[4]},
                          {A.polyEval(t.EIv, x) / EI, Lf[5], R.qmax[5]}}
          for _, p in ipairs(pairs_) do
            local e = math.abs(p[1] - p[2]) / math.max(p[3], 1e-30)
            if e > worst then worst = e end
          end
        end
      end
    end
  end
  yes(worst < 1e-9, "Ecuaciones por tramo coinciden (error rel. max " .. worst .. ", " .. ntr .. " tramos)")
  yes(A.polyStr({30, -10}, 6) == "30 - 10x", "Formato V(x): " .. A.polyStr({30, -10}, 6))
  yes(A.polyStr({0, 30, -5}, 6) == "30x - 5x²", "Formato M(x): " .. A.polyStr({0, 30, -5}, 6))
end

print(string.format("OK: %d   FALLAS: %d", nok, nfail))